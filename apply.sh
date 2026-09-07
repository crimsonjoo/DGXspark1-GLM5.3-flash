#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; CONFIG_FILE="${CONFIG_FILE:-$ROOT/.env.glm}"; FORCE=0
while [ "$#" -gt 0 ]; do case "$1" in --force) FORCE=1; shift;; --config) CONFIG_FILE="$2"; shift 2;; -h|--help) echo 'Usage: ./apply.sh [--force] [--config PATH]'; exit;; *) exit 2;; esac; done
die(){ printf '\033[1;31mERROR\033[0m %s\n' "$*" >&2; exit 1; }; ok(){ printf '\033[1;32mOK\033[0m %s\n' "$*"; }
if [ "${CONFIG_ALREADY_LOADED:-0}" != 1 ]; then [ -f "$CONFIG_FILE" ] || die 'Run ./start.sh first'; set -a; source "$CONFIG_FILE"; set +a; fi
PORT="${PORT:-18080}"; HOST="${HOST:-0.0.0.0}"; MODEL_NAME="${MODEL_NAME:-GLM-5.3-Flash-EXL3-2.05}"; MODEL_DIR="${MODEL_DIR:-$HOME/models/GLM-5.3-Flash-exl3-2.05bpw}"; DFLASH_DIR="${DFLASH_DIR:-$HOME/models/GLM-5.3-Flash-DFlash2}"; CACHE_ROOT="${CACHE_ROOT:-$HOME/.cache/glm53-one-spark}"; IMAGE="${IMAGE:-ghcr.io/gitcommit90/glm-5.3-one-spark:general23}"
CTX="${CTX:-262144}"; SEQS="${SEQS:-4}"; GPU_MEM="${GPU_MEM:-0.90}"; MAX_BATCHED_TOKENS="${MAX_BATCHED_TOKENS:-7168}"; K="${K:-5}"; WATCHDOG="${WATCHDOG:-1}"; READY_TIMEOUT="${READY_TIMEOUT:-1200}"; SSH_USER="${SSH_USER:-sejin}"; CONFIGURE_SSH="${CONFIGURE_SSH:-1}"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-30}"; WATCHDOG_FAILURES="${WATCHDOG_FAILURES:-6}"; WATCHDOG_STARTUP_GRACE="${WATCHDOG_STARTUP_GRACE:-1200}"; WATCHDOG_DEEP_CHECK="${WATCHDOG_DEEP_CHECK:-1}"; WATCHDOG_DEEP_INTERVAL="${WATCHDOG_DEEP_INTERVAL:-600}"; WATCHDOG_DEEP_TIMEOUT="${WATCHDOG_DEEP_TIMEOUT:-120}"; WATCHDOG_DEEP_FAILURES="${WATCHDOG_DEEP_FAILURES:-3}"; WATCHDOG_MAX_RESTARTS="${WATCHDOG_MAX_RESTARTS:-3}"; WATCHDOG_RESTART_WINDOW="${WATCHDOG_RESTART_WINDOW:-3600}"
for x in PORT CTX SEQS MAX_BATCHED_TOKENS K READY_TIMEOUT; do [[ "${!x}" =~ ^[0-9]+$ ]] || die "Invalid $x=${!x}"; done
command -v docker >/dev/null || die 'Docker missing; run ./start.sh'; docker info >/dev/null || die 'Docker inaccessible'; docker compose version >/dev/null || die 'Compose missing; run ./start.sh'; docker image inspect "$IMAGE" >/dev/null || die "Image missing: $IMAGE"
[ -f "$MODEL_DIR/config.json" ] && [ -f "$MODEL_DIR/model.safetensors.index.json" ] || die "Target checkpoint missing: $MODEL_DIR"; [ -f "$DFLASH_DIR/config.json" ] || die "DFlash2 missing: $DFLASH_DIR"; mkdir -p "$CACHE_ROOT"/{vllm,triton,tilelang,torchinductor}
if ss -lnt 2>/dev/null | awk 'NR>1{print $4}' | grep -Eq "(^|:)$PORT$" && ! docker ps -a --format '{{.Names}}' | grep -qx glm53-one-spark; then die "Port $PORT is used by another process"; fi
export PORT HOST MODEL_NAME MODEL_DIR DFLASH_DIR CACHE_ROOT IMAGE CTX SEQS GPU_MEM MAX_BATCHED_TOKENS K WATCHDOG WATCHDOG_INTERVAL WATCHDOG_FAILURES WATCHDOG_STARTUP_GRACE WATCHDOG_DEEP_CHECK WATCHDOG_DEEP_INTERVAL WATCHDOG_DEEP_TIMEOUT WATCHDOG_DEEP_FAILURES WATCHDOG_MAX_RESTARTS WATCHDOG_RESTART_WINDOW
compose=(docker compose --project-name glm53-one-spark -f "$ROOT/compose.yaml")
if docker ps -a --format '{{.Names}}' | grep -qx glm53-one-spark; then project="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' glm53-one-spark 2>/dev/null || true)"; [ "$project" = glm53-one-spark ] || { echo 'Migrating legacy container to Compose'; docker rm -f glm53-one-spark >/dev/null; }; fi
args=(); [ "$FORCE" = 1 ] && args=(--force-recreate)
if [ "$WATCHDOG" = 1 ]; then "${compose[@]}" --profile watchdog up -d --build "${args[@]}"; else "${compose[@]}" --profile watchdog rm -sf watchdog >/dev/null 2>&1 || true; "${compose[@]}" up -d "${args[@]}" glm; fi
echo "Waiting for GLM API (timeout ${READY_TIMEOUT}s; first load can take several minutes)..."; deadline=$((SECONDS+READY_TIMEOUT)); last=0
until curl -fsS --max-time 3 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; do
  docker ps --format '{{.Names}}' | grep -qx glm53-one-spark || { docker logs --tail 200 glm53-one-spark 2>&1 || true; die 'Container stopped during startup'; }
  [ "$SECONDS" -lt "$deadline" ] || { docker logs --tail 200 glm53-one-spark 2>&1 || true; die 'API readiness timed out'; }
  if [ $((SECONDS-last)) -ge 30 ]; then printf '  still loading... %ss\n' "$SECONDS"; last="$SECONDS"; fi; sleep 5
done
PORT="$PORT" MODEL_NAME="$MODEL_NAME" "$ROOT/scripts/smoke-test.sh" "http://127.0.0.1:$PORT"; ok 'Health, model discovery, and inference passed'
ips="$(ip -4 -o addr show scope global 2>/dev/null | awk '$2 !~ /^(docker|br-|veth|cni|virbr|tailscale)/{split($4,a,"/");print a[1]}' | sort -u)"
printf '\n\033[1;32m============================================================\n GLM-5.3-Flash is ready (no API key)\n============================================================\033[0m\n'
printf 'Model          : %s\nContext        : %s\nPort           : %s\nLocal API      : http://127.0.0.1:%s/v1\n' "$MODEL_NAME" "$CTX" "$PORT" "$PORT"
while IFS= read -r ip; do [ -n "$ip" ] || continue; printf 'LAN API        : http://%s:%s/v1\nHealth         : http://%s:%s/health\n' "$ip" "$PORT" "$ip" "$PORT"; [ "$CONFIGURE_SSH" = 1 ] && printf 'SSH            : ssh %s@%s\n' "$SSH_USER" "$ip"; done <<<"$ips"
printf 'Logs           : docker logs -f glm53-one-spark\nStatus         : ./stop.sh --status\nApply settings : ./apply.sh\nStop           : ./stop.sh\nConfig         : %s\n\n' "$CONFIG_FILE"
printf '\033[1;33mSecurity: this endpoint intentionally has no API key. Expose it only on a trusted LAN/VPN; use an authenticated reverse proxy for the public Internet.\033[0m\n'
