#!/usr/bin/env bash
# Ставит Agent Substrate, actor/worker-платформу со снапшотами и zero-trust.
# Официальный путь: инсталлятор ate-setup из чекаута репо плюс готовые образы с
# ghcr, без сборки через ko. Рассчитано на обычный кластер, в том числе облачный.
# Подробности в README репо и cmd/ate-setup/README.md.
#
# Переменные окружения, в скобках значение по умолчанию:
#   VERSION           релизный тег (v1.0.0)
#   IMAGE_REPO        реестр образов контроль-плейна (ghcr.io/agent-substrate/substrate)
#   NAMESPACE         namespace контроль-плейна (ate-system)
#                     ВНИМАНИЕ: у `ate-setup deploy` позиционный аргумент — это ИМЯ
#                     КОМПОНЕНТА (ate-system = весь контроль-плейн; есть также
#                     apiserver, atelet, atenet, postgres и др.), а namespace
#                     задаётся отдельным флагом --namespace.
#   SANDBOX_CLASSES   gvisor или gvisor,microvm; microvm просит KVM (gvisor)
#   SNAPSHOT_LOCATION URI объект-хранилища под снапшоты, для облачного кластера
#                     обязателен: gs://BUCKET/substrate/ или s3://BUCKET/substrate/
#   KIND              true — локальный kind: ate-setup --kind сам даёт локальное
#                     хранилище снапшотов и реестр, SNAPSHOT_LOCATION не нужен (false)
#   INGRESS_SPIFFE    SPIFFE-id клиентов, которым router разрешает достук к акторам
#                     (spiffe://cluster.local/ns/ate-system/sa/atenet-client)
#   CRED_PROVIDER     провайдер кредов, JSON ({"name":"k8s.io"})
#   ROLLOUT_TIMEOUT   таймаут раскатки (15m)
#   EXTRA_ARGS        доп. флаги для ate-setup deploy, одной строкой
#   SRC_DIR           готовый чекаут репо, пусто — скачаем сами
#   CONTEXT           kube-контекст
#
# Что нужно иметь (подробнее в README каталога):
#   * Go 1.21+ (тулчейн 1.27 подтянется сам), git или curl+tar, kubectl, docker.
#   * На apiserver включены feature gates ClusterTrustBundle,
#     ClusterTrustBundleProjection, PodCertificateRequest и runtime-config
#     certificates.k8s.io/v1beta1; без них нет zero-trust идентичности актора.
#   * Объект-хранилище из SNAPSHOT_LOCATION, доступное из кластера.
#   * Для gVisor-акторов нужен runsc на нодах (RuntimeClass поднимет сам контроль-плейн).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-v1.0.0}"
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/agent-substrate/substrate}"
NAMESPACE="${NAMESPACE:-ate-system}"
SANDBOX_CLASSES="${SANDBOX_CLASSES:-gvisor}"
SNAPSHOT_LOCATION="${SNAPSHOT_LOCATION:-}"
KIND="${KIND:-false}"
INGRESS_SPIFFE="${INGRESS_SPIFFE:-spiffe://cluster.local/ns/ate-system/sa/atenet-client}"
CRED_PROVIDER="${CRED_PROVIDER:-{\"name\":\"k8s.io\"}}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-15m}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
SRC_DIR="${SRC_DIR:-}"
CONTEXT="${CONTEXT:-}"
# kube-контекст: из переменной CONTEXT, иначе спросить интерактивно (Enter — текущий).
if [ -z "$CONTEXT" ] && [ -t 0 ]; then
  echo "Доступные kube-контексты:"; kubectl config get-contexts -o name | sed 's/^/  /'
  _cur="$(kubectl config current-context 2>/dev/null || true)"
  printf "Контекст [%s]: " "$_cur"; read -r CONTEXT || true
  CONTEXT="${CONTEXT:-$_cur}"
fi

command -v go >/dev/null || { echo "нужен Go (1.21+); тулчейн 1.27 подтянется сам"; exit 1; }
if [ "$KIND" != "true" ]; then
  [ -n "$SNAPSHOT_LOCATION" ] || { echo "Задайте SNAPSHOT_LOCATION=gs://BUCKET/... (или s3://...) — объект-хранилище для снапшотов. Для локального kind: KIND=true."; exit 1; }
fi

# KIND: локальный docker-registry kind-registry:5000 (порт хоста 5001), который ждёт
# ate-setup --kind. Идемпотентно: поднять контейнер, подключить к сети kind, прописать
# containerd certs.d на нодах (localhost:5001 → kind-registry:5000).
if [ "$KIND" = "true" ]; then
  command -v docker >/dev/null || { echo "KIND=true требует docker (для kind-registry)."; exit 1; }
  KIND_CLUSTER="${KIND_CLUSTER:-kind}"; REG_NAME="kind-registry"; REG_PORT="${KIND_REGISTRY_PORT:-5001}"
  if [ "$(docker inspect -f '{{.State.Running}}' "$REG_NAME" 2>/dev/null || true)" != "true" ]; then
    echo "== поднимаю $REG_NAME на 127.0.0.1:$REG_PORT =="
    docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" --network bridge --name "$REG_NAME" registry:3
  fi
  if [ "$(docker inspect -f '{{json .NetworkSettings.Networks.kind}}' "$REG_NAME")" = "null" ]; then
    docker network connect kind "$REG_NAME"
  fi
  for node in $(kind get nodes --name "$KIND_CLUSTER"); do
    docker exec "$node" mkdir -p "/etc/containerd/certs.d/localhost:${REG_PORT}"
    echo "[host.\"http://${REG_NAME}:5000\"]" | docker exec -i "$node" cp /dev/stdin "/etc/containerd/certs.d/localhost:${REG_PORT}/hosts.toml"
  done
fi

# 1. Чекаут репо (ate-setup читает манифесты от корня чекаута).
if [ -z "$SRC_DIR" ]; then
  SRC_DIR="$(mktemp -d)/substrate"
  echo "== скачиваю Agent Substrate $VERSION =="
  if command -v git >/dev/null; then
    git clone --depth 1 --branch "$VERSION" https://github.com/agent-substrate/substrate "$SRC_DIR"
  else
    mkdir -p "$SRC_DIR"
    curl -sL "https://codeload.github.com/agent-substrate/substrate/tar.gz/refs/tags/$VERSION" | tar -xz -C "$SRC_DIR" --strip-components=1
  fi
fi

# 2. Собрать инсталлятор и CLI.
echo "== собираю ate-setup и kubectl-ate =="
( cd "$SRC_DIR" && export GOTOOLCHAIN=auto && \
  go build -o bin/ate-setup ./cmd/ate-setup && \
  go build -o bin/kubectl-ate ./cmd/kubectl-ate )

# 3. Деплой с готовыми образами из ghcr. На kind добавляем --kind (локальное
#    хранилище снапшотов и реестр), на облаке — --snapshot-location.
CTXFLAG=(); [ -n "$CONTEXT" ] && CTXFLAG=(--context "$CONTEXT")
STORAGE=(); [ "$KIND" = "true" ] && STORAGE=(--kind) || STORAGE=(--snapshot-location="$SNAPSHOT_LOCATION")
echo "== ate-setup deploy ate-system --namespace $NAMESPACE (образы $IMAGE_REPO:$VERSION, KIND=$KIND) =="
# ate-system здесь — имя КОМПОНЕНТА (весь контроль-плейн), а не namespace;
# namespace передаём флагом --namespace.
( cd "$SRC_DIR" && ./bin/ate-setup deploy ate-system \
    --namespace "$NAMESPACE" \
    "${CTXFLAG[@]}" \
    --image-repo "$IMAGE_REPO" --image-tag "$VERSION" \
    --sandbox-classes="$SANDBOX_CLASSES" \
    "${STORAGE[@]}" \
    --credential-provider="$CRED_PROVIDER" \
    --ingress-allowed-spiffe-ids="$INGRESS_SPIFFE" \
    --rollout-timeout="$ROLLOUT_TIMEOUT" \
    $EXTRA_ARGS )

echo
echo "Agent Substrate $VERSION установлен в $NAMESPACE."
echo "CLI собран: $SRC_DIR/bin/kubectl-ate (скопируйте в PATH)."
echo "Проверка:  kubectl -n $NAMESPACE get pods"
echo "Для сноса сохраните чекаут: SRC_DIR=$SRC_DIR ./uninstall.sh"
