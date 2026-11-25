#!/usr/bin/env bash
# Ставит Agent Sandbox (kubernetes-sigs), оркестратор песочниц.
# Способ официальный, как в доке: kubectl apply релизного манифеста.
# https://agent-sandbox.sigs.k8s.io/docs/getting_started/
#
# Переменные окружения, в скобках значение по умолчанию:
#   VERSION   тег релиза либо latest (v1.0.12)
#   MODE      standard = core+extensions, либо core, либо extensions (standard)
#   CONTEXT   kube-контекст, пусто берёт текущий
#   DRY_RUN   true — только показать, что применилось бы (false)
#
# Нужен Kubernetes 1.25+, лучше 1.29+. На 1.25-1.28 не выключайте feature gate
# CustomResourceValidationExpressions, иначе отвалится CEL-валидация CRD.
# Контроллер поднимается в namespace agent-sandbox-system. Чем изолировать
# песочницу, задаёт RuntimeClass (gVisor/Kata) в Sandbox.spec.podTemplate,
# примеры в examples/.
set -euo pipefail

VERSION="${VERSION:-v1.0.12}"
MODE="${MODE:-standard}"
CONTEXT="${CONTEXT:-}"
# kube-контекст: из переменной CONTEXT, иначе спросить интерактивно (Enter — текущий).
if [ -z "$CONTEXT" ] && [ -t 0 ]; then
  echo "Доступные kube-контексты:"; kubectl config get-contexts -o name | sed 's/^/  /'
  _cur="$(kubectl config current-context 2>/dev/null || true)"
  printf "Контекст [%s]: " "$_cur"; read -r CONTEXT || true
  CONTEXT="${CONTEXT:-$_cur}"
fi
DRY_RUN="${DRY_RUN:-false}"

REL="https://github.com/kubernetes-sigs/agent-sandbox/releases"
if [ "$VERSION" = "latest" ]; then BASE="$REL/latest/download"; else BASE="$REL/download/$VERSION"; fi

K=(kubectl)
[ -n "$CONTEXT" ] && K+=(--context "$CONTEXT")
APPLY=(apply)
[ "$DRY_RUN" = "true" ] && APPLY=(apply --dry-run=server)

case "$MODE" in
  standard)   MANIFESTS=("$BASE/sandbox-with-extensions.yaml") ;;
  core)       MANIFESTS=("$BASE/sandbox.yaml") ;;
  extensions) MANIFESTS=("$BASE/sandbox.yaml" "$BASE/extensions.yaml") ;;
  *) echo "MODE должен быть standard|core|extensions (дано: $MODE)"; exit 1 ;;
esac

echo "== Agent Sandbox $VERSION ($MODE) =="
for m in "${MANIFESTS[@]}"; do
  echo "-> apply $m"
  "${K[@]}" "${APPLY[@]}" -f "$m"
done

[ "$DRY_RUN" = "true" ] && { echo "DRY_RUN — выход."; exit 0; }

echo "== ожидаю контроллер =="
"${K[@]}" -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=180s

echo
echo "Готово. Проверка:"
echo "  kubectl get crd sandboxes.agents.x-k8s.io"
echo "  kubectl get deploy agent-sandbox-controller -n agent-sandbox-system"
echo "Пример песочницы на gVisor:  kubectl apply -f examples/sandbox-gvisor.yaml"
echo "Warm-пул + claim:            kubectl apply -f examples/warmpool.yaml"
