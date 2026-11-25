#!/usr/bin/env bash
# Сносит OpenSandbox: helm-релиз и, если попросить, CRD с namespace.
#   RELEASE      имя helm-релиза (opensandbox)
#   NAMESPACE    namespace контроль-плейна (opensandbox-system)
#   WORKLOAD_NS  namespace песочниц (opensandbox)
#   DATAPLANE_NS namespace фаст-сэндбокса, сервер создаёт его в рантайме (opensandbox-dataplane)
#   DELETE_CRD   true — снести ещё CRD и namespace (false)
#   CONTEXT      kube-контекст
set -euo pipefail
RELEASE="${RELEASE:-opensandbox}"
NAMESPACE="${NAMESPACE:-opensandbox-system}"
WORKLOAD_NS="${WORKLOAD_NS:-opensandbox}"
DATAPLANE_NS="${DATAPLANE_NS:-opensandbox-dataplane}"
DELETE_CRD="${DELETE_CRD:-false}"
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

"${H[@]}" uninstall "$RELEASE" -n "$NAMESPACE" || true

if [ "$DELETE_CRD" = "true" ]; then
  echo "== удаляю CRD OpenSandbox (каскадно снесёт все песочницы/пулы) =="
  "${K[@]}" get crd -o name | grep -E 'opensandbox.io|sandbox.fast.io' | xargs -r "${K[@]}" delete
  "${K[@]}" delete ns "$NAMESPACE" "$WORKLOAD_NS" "$DATAPLANE_NS" --ignore-not-found
fi
echo "OpenSandbox снесён (DELETE_CRD=$DELETE_CRD)."
