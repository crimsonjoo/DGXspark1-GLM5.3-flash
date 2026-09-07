#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; CONFIG_FILE="${CONFIG_FILE:-$ROOT/.env.glm}"; REMOVE=0; STATUS=0
while [ "$#" -gt 0 ]; do case "$1" in --remove) REMOVE=1;; --status) STATUS=1;; -h|--help) echo 'Usage: ./stop.sh [--remove|--status]'; exit;; *) exit 2;; esac; shift; done
command -v docker >/dev/null || { echo 'Docker is not installed.'; exit; }; docker info >/dev/null || { echo 'Docker is not accessible.' >&2; exit 1; }
[ -f "$CONFIG_FILE" ] && { set -a; source "$CONFIG_FILE"; set +a; }
: "${IMAGE:=ghcr.io/gitcommit90/glm-5.3-one-spark:general23}" "${PORT:=18080}" "${MODEL_DIR:=$HOME/models/GLM-5.3-Flash-exl3-2.05bpw}" "${DFLASH_DIR:=$HOME/models/GLM-5.3-Flash-DFlash2}" "${CACHE_ROOT:=$HOME/.cache/glm53-one-spark}"; export IMAGE PORT MODEL_DIR DFLASH_DIR CACHE_ROOT
compose=(docker compose --project-name glm53-one-spark -f "$ROOT/compose.yaml" --profile watchdog)
if [ "$STATUS" = 1 ]; then for n in glm53-one-spark glm53-watchdog; do docker ps -a --filter "name=^/${n}$" --format '{{.Names}}: {{.Status}}' | grep . || echo "$n: not present"; done; exit; fi
if [ "$REMOVE" = 1 ]; then "${compose[@]}" down --remove-orphans; echo 'Containers/network removed; weights/images/caches preserved.'; else "${compose[@]}" stop; echo 'GLM and watchdog stopped; weights/images/caches preserved.'; fi; echo 'Restart with: ./apply.sh'
