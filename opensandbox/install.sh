#!/usr/bin/env bash
# Ставит OpenSandbox, продуктовый оркестратор песочниц: контроллер, lifecycle-
# сервер, ingress-gateway. Официальный способ — Helm umbrella-чарт из чекаута
# релизного тега, пакеты чартов отдельно не публикуют. См. docs/deployment/index.md.
#
# Переменные окружения, в скобках значение по умолчанию:
#   VERSION      релизный тег (release-1.2.1)
#   NAMESPACE    namespace контроль-плейна (opensandbox-system)
#   WORKLOAD_NS  namespace для рабочих песочниц (opensandbox)
#   VALUES       файл values, скопируйте из values.example.yaml (values.example.yaml)
#   API_KEY      ключ API сервера, пойдёт в секрет opensandbox-api-key
#   INSECURE     true разрешит сервер без ключа, только для теста (false)
#   ENABLE_GATEWAY / ENABLE_FAST_SANDBOX / ENABLE_NODE_AGENT (true/false/false)
#   SRC_DIR      готовый чекаут репо, пусто — скачать во временную папку
#   RELEASE      имя helm-релиза (opensandbox)
#   CONTEXT      kube-контекст
#
# Нужно: helm 3.x, git или curl+tar, kubectl. Для gVisor нужен RuntimeClass gvisor.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-release-1.2.1}"
NAMESPACE="${NAMESPACE:-opensandbox-system}"
WORKLOAD_NS="${WORKLOAD_NS:-opensandbox}"
VALUES="${VALUES:-values.example.yaml}"
API_KEY="${API_KEY:-}"
INSECURE="${INSECURE:-false}"
ENABLE_GATEWAY="${ENABLE_GATEWAY:-true}"
ENABLE_FAST_SANDBOX="${ENABLE_FAST_SANDBOX:-false}"
ENABLE_NODE_AGENT="${ENABLE_NODE_AGENT:-false}"
SRC_DIR="${SRC_DIR:-}"
RELEASE="${RELEASE:-opensandbox}"
CONTEXT="${CONTEXT:-}"
# kube-контекст: из переменной CONTEXT, иначе спросить интерактивно (Enter — текущий).
if [ -z "$CONTEXT" ] && [ -t 0 ]; then
  echo "Доступные kube-контексты:"; kubectl config get-contexts -o name | sed 's/^/  /'
  _cur="$(kubectl config current-context 2>/dev/null || true)"
  printf "Контекст [%s]: " "$_cur"; read -r CONTEXT || true
  CONTEXT="${CONTEXT:-$_cur}"
fi

K=(kubectl); [ -n "$CONTEXT" ] && K+=(--context "$CONTEXT")
H=(helm); [ -n "$CONTEXT" ] && H+=(--kube-context "$CONTEXT")

# 1. Получить чекаут релиза (чарты живут только в репо).
CLEANUP=""
if [ -z "$SRC_DIR" ]; then
  SRC_DIR="$(mktemp -d)"; CLEANUP="$SRC_DIR"
  echo "== скачиваю OpenSandbox $VERSION в $SRC_DIR =="
  if command -v git >/dev/null; then
    git clone --depth 1 --branch "$VERSION" https://github.com/opensandbox-group/OpenSandbox "$SRC_DIR/OpenSandbox"
  else
    curl -sL "https://codeload.github.com/opensandbox-group/OpenSandbox/tar.gz/refs/tags/$VERSION" | tar -xz -C "$SRC_DIR"
    mv "$SRC_DIR"/OpenSandbox-* "$SRC_DIR/OpenSandbox"
  fi
fi
CHART="$SRC_DIR/OpenSandbox/manifests/charts/opensandbox"
[ -d "$CHART" ] || { echo "umbrella-чарт не найден: $CHART"; exit 1; }

# 2. Namespaces (чарт сам создаёт NAMESPACE через --create-namespace, рабочий создаём вручную).
"${K[@]}" create namespace "$WORKLOAD_NS" --dry-run=client -o yaml | "${K[@]}" apply -f -

# 3. Режим аутентификации сервера.
# values.example.yaml задаёт server.env[0] = OPENSANDBOX_SERVER_API_KEY из секрета.
# В INSECURE нам этот env не нужен (и секрета нет), поэтому ЦЕЛИКОМ заменяем
# server.env оверлеем-values (вторым --values; он имеет приоритет и заменяет список,
# а не мёржит по индексу — иначе остаётся унаследованный valueFrom и env невалиден).
OVERLAY=""
if [ -n "$API_KEY" ]; then
  "${K[@]}" create secret generic opensandbox-api-key -n "$NAMESPACE" \
    --from-literal=api-key="$API_KEY" --dry-run=client -o yaml | "${K[@]}" apply -f -
elif [ "$INSECURE" = "true" ]; then
  echo "WARN: сервер стартует без API-ключа (INSECURE=true) — только для теста."
  OVERLAY="$(mktemp)"
  cat >"$OVERLAY" <<'YAML'
opensandbox-server:
  server:
    env:
      - name: OPENSANDBOX_INSECURE_SERVER
        value: "YES"
YAML
else
  echo "Нужен API_KEY=... (или INSECURE=true для теста без ключа)."; exit 1
fi

# 4. Собрать зависимости umbrella и установить.
echo "== helm dependency build =="
"${H[@]}" dependency build "$CHART"
echo "== helm upgrade --install $RELEASE =="
"${H[@]}" upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" --create-namespace \
  --values "$VALUES" \
  ${OVERLAY:+--values "$OVERLAY"} \
  --set "ingress-gateway.enabled=$ENABLE_GATEWAY" \
  --set "fast-sandbox.enabled=$ENABLE_FAST_SANDBOX" \
  --set "opensandbox-node-agent.enabled=$ENABLE_NODE_AGENT" \
  --wait --timeout 600s

[ -n "$OVERLAY" ] && rm -f "$OVERLAY"
[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"
echo
echo "OpenSandbox $VERSION установлен в $NAMESPACE (рабочий ns песочниц: $WORKLOAD_NS)."
echo "Проверка:  kubectl -n $NAMESPACE get pods"
echo "API сервера:  kubectl -n $NAMESPACE port-forward svc/opensandbox-server 8080:80  &  curl -s localhost:8080/health"
echo "CRD:  kubectl get crd | grep opensandbox.io"
