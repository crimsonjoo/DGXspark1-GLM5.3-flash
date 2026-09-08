#!/usr/bin/env python3
"""Exercise the formerly fatal repeated long-prefix request pattern."""
import json
import os
import urllib.request

base = os.getenv("GLM53_URL", "http://127.0.0.1:18080")
model = os.getenv("GLM53_MODEL", "GLM-5.3-Flash-EXL3-2.05")
prefix = " stable" * 14300
for added in (64, 320, 512):
    payload = json.dumps({"model": model, "messages": [{"role": "user",
        "content": prefix + (" suffix" * added) + "\nReply OK."}],
        "max_tokens": 8, "temperature": 0}).encode()
    req = urllib.request.Request(base + "/v1/chat/completions", payload,
        {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=1800) as response:
        result = json.load(response)
    assert result.get("choices"), result
    with urllib.request.urlopen(base + "/health", timeout=10) as response:
        assert response.status == 200
    print(f"long-prefix suffix={added}: OK usage={result.get('usage')}", flush=True)
