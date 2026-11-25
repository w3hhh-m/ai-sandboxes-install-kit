#!/usr/bin/env bash
# Сносит Agent Sandbox. Осторожно: удаление CRD каскадом снесёт все ресурсы
# Sandbox/Claim/WarmPool/Template во всех namespace. Скрипт сначала печатает, что
# сейчас используется, и ждёт CONFIRM=yes, прежде чем реально удалять.
#   VERSION  тот же тег, что при установке (v1.0.12)
#   MODE     standard | core | extensions (standard)
#   CONTEXT  kube-контекст
#   CONFIRM  yes, чтобы удалить по-настоящему (no)
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
CONFIRM="${CONFIRM:-no}"

REL="https://github.com/kubernetes-sigs/agent-sandbox/releases"
if [ "$VERSION" = "latest" ]; then BASE="$REL/latest/download"; else BASE="$REL/download/$VERSION"; fi
K=(kubectl); [ -n "$CONTEXT" ] && K+=(--context "$CONTEXT")

echo "== используемые ресурсы (проверьте перед сносом) =="
"${K[@]}" get sandboxes -A 2>/dev/null || true
"${K[@]}" get sandboxclaims -A 2>/dev/null || true
"${K[@]}" get sandboxwarmpools -A 2>/dev/null || true

if [ "$CONFIRM" != "yes" ]; then
  echo; echo "Это удалит CRD и КАСКАДНО все ресурсы выше. Повторите с CONFIRM=yes."; exit 0
fi

case "$MODE" in
  standard)   MANIFESTS=("$BASE/sandbox-with-extensions.yaml") ;;
  core)       MANIFESTS=("$BASE/sandbox.yaml") ;;
  extensions) MANIFESTS=("$BASE/extensions.yaml" "$BASE/sandbox.yaml") ;;
esac
for m in "${MANIFESTS[@]}"; do echo "-> delete $m"; "${K[@]}" delete -f "$m" --ignore-not-found; done
echo "Agent Sandbox снесён."
