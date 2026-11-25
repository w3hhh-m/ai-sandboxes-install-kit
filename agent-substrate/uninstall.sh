#!/usr/bin/env bash
# Сносит Agent Substrate через ate-setup delete. Нужен тот же чекаут репо, что при
# установке (манифесты плюс бинарь ate-setup), путь к нему в SRC_DIR.
#   SRC_DIR    чекаут репо с собранным bin/ate-setup (обязательно)
#   NAMESPACE  namespace контроль-плейна (ate-system)
#   KIND       true — локальный kind (тот же флаг, что при install) (false)
#   CONTEXT    kube-контекст
set -euo pipefail
NAMESPACE="${NAMESPACE:-ate-system}"
KIND="${KIND:-false}"
CONTEXT="${CONTEXT:-}"
# kube-контекст: из переменной CONTEXT, иначе спросить интерактивно (Enter — текущий).
if [ -z "$CONTEXT" ] && [ -t 0 ]; then
  echo "Доступные kube-контексты:"; kubectl config get-contexts -o name | sed 's/^/  /'
  _cur="$(kubectl config current-context 2>/dev/null || true)"
  printf "Контекст [%s]: " "$_cur"; read -r CONTEXT || true
  CONTEXT="${CONTEXT:-$_cur}"
fi
SRC_DIR="${SRC_DIR:-}"
[ -n "$SRC_DIR" ] && [ -d "$SRC_DIR" ] || { echo "Задайте SRC_DIR = чекаут репо (тот же, что при install)."; exit 1; }

[ -x "$SRC_DIR/bin/ate-setup" ] || ( cd "$SRC_DIR" && GOTOOLCHAIN=auto go build -o bin/ate-setup ./cmd/ate-setup )
CTXFLAG=(); [ -n "$CONTEXT" ] && CTXFLAG=(--context "$CONTEXT")
KINDFLAG=(); [ "$KIND" = "true" ] && KINDFLAG=(--kind)
( cd "$SRC_DIR" && ./bin/ate-setup delete "$NAMESPACE" "${CTXFLAG[@]}" "${KINDFLAG[@]}" )
echo "Agent Substrate снесён из $NAMESPACE."
