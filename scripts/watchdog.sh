#!/usr/bin/env bash
set -u
NAME="${WATCHDOG_CONTAINER:-glm53-one-spark}"
BASE_URL="${WATCHDOG_URL:-http://127.0.0.1:18080}"
MODEL="${WATCHDOG_MODEL:-GLM-5.3-Flash-EXL3-2.05}"
INTERVAL="${WATCHDOG_INTERVAL:-30}"; FAILURES="${WATCHDOG_FAILURES:-6}"
STARTUP_GRACE="${WATCHDOG_STARTUP_GRACE:-1200}"
DEEP_CHECK="${WATCHDOG_DEEP_CHECK:-1}"; DEEP_INTERVAL="${WATCHDOG_DEEP_INTERVAL:-600}"
DEEP_TIMEOUT="${WATCHDOG_DEEP_TIMEOUT:-120}"; DEEP_FAILURES="${WATCHDOG_DEEP_FAILURES:-3}"
MAX_RESTARTS="${WATCHDOG_MAX_RESTARTS:-3}"; RESTART_WINDOW="${WATCHDOG_RESTART_WINDOW:-3600}"
http_failures=0; deep_failures=0; last_deep=0; restart_times=()
log(){ printf '%s glm53-watchdog: %s\n' "$(date -Iseconds)" "$*"; }
running(){ [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = true ] && [ "$(docker inspect -f '{{index .Config.Labels \"com.glm53.watchdog\"}}' "$NAME" 2>/dev/null)" = true ]; }
starting(){ [ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$NAME" 2>/dev/null)" = starting ]; }
shallow(){ curl -fsS --max-time 10 "$BASE_URL/health" >/dev/null && curl -fsS --max-time 10 "$BASE_URL/v1/models" | grep -Fq "$MODEL"; }
deep(){ curl -fsS --max-time "$DEEP_TIMEOUT" -H 'Content-Type: application/json' -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply OK\"}],\"max_tokens\":1,\"temperature\":0,\"chat_template_kwargs\":{\"enable_thinking\":false}}" "$BASE_URL/v1/chat/completions" | grep -q '"choices"'; }
restart_engine(){
  local reason="$1" now t kept=(); now="$(date +%s)"
  for t in "${restart_times[@]}"; do [ $((now-t)) -lt "$RESTART_WINDOW" ] && kept+=("$t"); done; restart_times=("${kept[@]}")
  if [ "${#restart_times[@]}" -ge "$MAX_RESTARTS" ]; then log "restart suppressed: limit reached ($reason)"; return 1; fi
  log "restarting $NAME: $reason"; docker restart "$NAME" >/dev/null || return 1
  restart_times+=("$now"); http_failures=0; deep_failures=0; last_deep="$now"; sleep "$STARTUP_GRACE"
}
log "started (container=$NAME interval=${INTERVAL}s)"
while true; do
  if ! running; then http_failures=0; deep_failures=0; sleep "$INTERVAL"; continue; fi
  if starting; then sleep "$INTERVAL"; continue; fi
  if shallow; then http_failures=0; else http_failures=$((http_failures+1)); log "shallow failure $http_failures/$FAILURES"; [ "$http_failures" -lt "$FAILURES" ] || restart_engine "health/model probes" || true; fi
  now="$(date +%s)"
  if [ "$DEEP_CHECK" = 1 ] && [ "$http_failures" = 0 ] && [ $((now-last_deep)) -ge "$DEEP_INTERVAL" ]; then
    last_deep="$now"; if deep; then deep_failures=0; else deep_failures=$((deep_failures+1)); log "deep failure $deep_failures/$DEEP_FAILURES"; [ "$deep_failures" -lt "$DEEP_FAILURES" ] || restart_engine "inference probes" || true; fi
  fi
  sleep "$INTERVAL"
done
