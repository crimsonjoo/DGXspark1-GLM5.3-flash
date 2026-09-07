#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${1:-http://127.0.0.1:${PORT:-18080}}"; MODEL="${MODEL_NAME:-GLM-5.3-Flash-EXL3-2.05}"
curl -fsS --max-time 10 "$BASE/health" >/dev/null
curl -fsS --max-time 10 "$BASE/v1/models" | grep -Fq "$MODEL"
response="$(curl -fsS --max-time 180 -H 'Content-Type: application/json' -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly OK\"}],\"max_tokens\":8,\"temperature\":0,\"chat_template_kwargs\":{\"enable_thinking\":false}}" "$BASE/v1/chat/completions")"
python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["choices"][0]["message"]["content"]; print("Smoke test OK:", r["choices"][0]["message"]["content"].strip())' <<<"$response"
