#!/usr/bin/env bash
# Сносит Google AX, Substrate не трогает. Нужен тот же чекаут, что при установке.
#   SRC_DIR    чекаут google/ax (обязательно)
#   NAMESPACE  namespace AX (ax-system)
#   CONTEXT    kube-контекст
set -euo pipefail
NAMESPACE="${NAMESPACE:-ax-system}"
CONTEXT="${CONTEXT:-}"
# kube-контекст: из переменной CONTEXT, иначе спросить интерактивно (Enter — текущий).
if [ -z "$CONTEXT" ] && [ -t 0 ]; then
  echo "Доступные kube-контексты:"; kubectl config get-contexts -o name | sed 's/^/  /'
  _cur="$(kubectl config current-context 2>/dev/null || true)"
  printf "Контекст [%s]: " "$_cur"; read -r CONTEXT || true
  CONTEXT="${CONTEXT:-$_cur}"
fi
SRC_DIR="${SRC_DIR:-}"
[ -n "$SRC_DIR" ] && [ -d "$SRC_DIR/deploy" ] || { echo "Задайте SRC_DIR = чекаут google/ax (с deploy/)."; exit 1; }
K=(kubectl); [ -n "$CONTEXT" ] && K+=(--context "$CONTEXT")

for f in "$SRC_DIR"/deploy/*.yaml; do "${K[@]}" delete -f "$f" --ignore-not-found; done
"${K[@]}" delete ns "$NAMESPACE" --ignore-not-found
echo "AX снесён из $NAMESPACE. Substrate не тронут."
