#!/usr/bin/env bash
# Ставит Google AX (Agent Executor), декларативный слой задач поверх уже
# установленного Agent Substrate. Официальный способ: make deploy, образы собирает
# ko. См. README репо google/ax, раздел «Deploy the control plane».
#
# ⚠️ Сначала прочитайте про совместимость версий в README каталога: AX и Substrate
#    должны совпасть по wire-протоколу, иначе ax-controller не создаст актора.
#
# Переменные окружения, в скобках значение по умолчанию:
#   AX_VERSION          тег AX (v0.3.1)
#   AX_IMAGE_REPO       реестр, куда ko пушит образы AX; задать обязательно,
#                       и кластер должен уметь его тянуть
#   NAMESPACE           namespace AX (ax-system)
#   SUBSTRATE_NS        namespace Substrate (ate-system)
#   AX_SNAPSHOTS_BUCKET свой бакет снапшотов вместо зашитого в манифест dev-бакета
#                       (gs://.../ или s3://...); очень желательно задать
#   GRANT               true настроит доступ AX к Substrate: метка ns плюс
#                       access-policy owner; тогда нужен KUBECTL_ATE (true)
#   KUBECTL_ATE         путь к бинарю kubectl-ate из установки Substrate (kubectl-ate)
#   SRC_DIR             готовый чекаут google/ax, пусто — скачаем сами
#   CONTEXT             kube-контекст
#
# Нужно: Substrate уже стоит и доступен (api.<SUBSTRATE_NS>.svc:443); ko
# (https://ko.build), go, git/curl, kubectl и реестр, из которого тянет кластер.
set -euo pipefail
cd "$(dirname "$0")"

AX_VERSION="${AX_VERSION:-v0.3.1}"
AX_IMAGE_REPO="${AX_IMAGE_REPO:-}"
NAMESPACE="${NAMESPACE:-ax-system}"
SUBSTRATE_NS="${SUBSTRATE_NS:-ate-system}"
AX_SNAPSHOTS_BUCKET="${AX_SNAPSHOTS_BUCKET:-}"
GRANT="${GRANT:-true}"
KUBECTL_ATE="${KUBECTL_ATE:-kubectl-ate}"
SRC_DIR="${SRC_DIR:-}"
CONTEXT="${CONTEXT:-}"
# kube-контекст: из переменной CONTEXT, иначе спросить интерактивно (Enter — текущий).
if [ -z "$CONTEXT" ] && [ -t 0 ]; then
  echo "Доступные kube-контексты:"; kubectl config get-contexts -o name | sed 's/^/  /'
  _cur="$(kubectl config current-context 2>/dev/null || true)"
  printf "Контекст [%s]: " "$_cur"; read -r CONTEXT || true
  CONTEXT="${CONTEXT:-$_cur}"
fi

[ -n "$AX_IMAGE_REPO" ] || { echo "Задайте AX_IMAGE_REPO=<реестр для образов AX> (ko пушит туда)."; exit 1; }
command -v ko >/dev/null || { echo "нужен ko (https://ko.build): brew install ko"; exit 1; }
K=(kubectl); [ -n "$CONTEXT" ] && K+=(--context "$CONTEXT")

# 0. Substrate на месте?
"${K[@]}" -n "$SUBSTRATE_NS" get svc api >/dev/null 2>&1 || {
  echo "Substrate не найден (svc api в $SUBSTRATE_NS). Сначала поставьте Agent Substrate."; exit 1; }

# 1. Чекаут AX.
if [ -z "$SRC_DIR" ]; then
  SRC_DIR="$(mktemp -d)/ax"
  echo "== скачиваю google/ax $AX_VERSION =="
  if command -v git >/dev/null; then
    git clone --depth 1 --branch "$AX_VERSION" https://github.com/google/ax "$SRC_DIR"
  else
    mkdir -p "$SRC_DIR"
    curl -sL "https://codeload.github.com/google/ax/tar.gz/refs/tags/$AX_VERSION" | tar -xz -C "$SRC_DIR" --strip-components=1
  fi
fi

# 2. Деплой (Redis + ax-server + ax-controller; образы собирает ko в AX_IMAGE_REPO).
echo "== make deploy AX_IMAGE_REPO=$AX_IMAGE_REPO =="
( cd "$SRC_DIR" && export GOTOOLCHAIN=auto && make deploy AX_IMAGE_REPO="$AX_IMAGE_REPO" )

# 3. Переопределить зашитый dev-бакет снапшотов (в deploy/ax-controller.yaml по умолчанию
#    стоит внутренний gs://-бакет Google — он вам недоступен).
if [ -n "$AX_SNAPSHOTS_BUCKET" ]; then
  echo "== AX_SNAPSHOTS_BUCKET=$AX_SNAPSHOTS_BUCKET =="
  "${K[@]}" -n "$NAMESPACE" set env deploy/ax-controller AX_SNAPSHOTS_BUCKET="$AX_SNAPSHOTS_BUCKET"
fi

# 4. Доступ AX → Substrate Control API:
#    (а) метка ns разрешает ingress на ateapi (у Substrate default-deny ingress);
#    (б) access-policy даёт ax-controller права создавать atespace/actor.
if [ "$GRANT" = "true" ]; then
  echo "== доступ ax-controller к Substrate =="
  "${K[@]}" label ns "$NAMESPACE" ate.dev/api-access=true --overwrite
  if command -v "$KUBECTL_ATE" >/dev/null 2>&1; then
    POL='bindings:
- role: owner
  members:
  - user:system:serviceaccount:'"$NAMESPACE"':ax-controller'
    CTXA=(); [ -n "$CONTEXT" ] && CTXA=(--context "$CONTEXT")
    echo "$POL" | "$KUBECTL_ATE" "${CTXA[@]}" create access-policy --global -f - 2>/dev/null \
      || echo "$POL" | "$KUBECTL_ATE" "${CTXA[@]}" update access-policy --global -f -
  else
    echo "WARN: kubectl-ate не найден ($KUBECTL_ATE) — выдайте доступ вручную:"
    echo "  kubectl-ate create access-policy --global с ролью owner для"
    echo "  user:system:serviceaccount:$NAMESPACE:ax-controller"
  fi
  "${K[@]}" -n "$NAMESPACE" rollout restart deploy/ax-controller
fi

"${K[@]}" -n "$NAMESPACE" rollout status deploy/ax-controller --timeout=180s || true
echo
echo "AX $AX_VERSION установлен в $NAMESPACE поверх Substrate ($SUBSTRATE_NS)."
echo "CLI: go install github.com/google/ax/cmd/ax@$AX_VERSION  (или $SRC_DIR/bin/ax после make build)"
echo "Проба:  ax apply -f $SRC_DIR/examples/task.yaml ; ax get tasks"
echo "Если задачи висят в Failed с ошибкой подключения/протокола — см. README (совместимость версий)."
