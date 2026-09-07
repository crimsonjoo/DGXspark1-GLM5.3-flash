#!/usr/bin/env bash
set -euo pipefail
# patch_glm_video_placeholders installs a .pth import hook into the live site-packages,
# so it must run at container start. The other overlay patches are applied at image build.
python3 /opt/glm53/patch_glm_video_placeholders.py
K="${ONE_SPARK_K:-5}"  # 5 = best general-purpose; 8 = structured output.
SPEC='{"method":"dflash","model":"/draft","num_speculative_tokens":'"$K"',"kv_cache_dtype":"auto","draft_sample_method":"probabilistic","rejection_sample_method":"standard","draft_tensor_parallel_size":1}'
exec vllm serve /model \
  --served-model-name "${ONE_SPARK_MODEL_NAME:-GLM-5.3-Flash-EXL3-2.05}" \
  --host "${ONE_SPARK_HOST:-0.0.0.0}" --port "${ONE_SPARK_PORT:-18080}" \
  --tensor-parallel-size 1 \
  --tool-call-parser glm47 --enable-auto-tool-choice \
  --reasoning-parser glm45 \
  --enable-prefix-caching --no-enable-flashinfer-autotune \
  --quantization exl3 \
  --max-model-len "${ONE_SPARK_CTX:-262144}" \
  --gpu-memory-utilization "${ONE_SPARK_GPU_MEM:-0.90}" \
  --max-num-seqs "${ONE_SPARK_SEQS:-4}" --max-num-batched-tokens "${ONE_SPARK_BATCHED_TOKENS:-7168}" \
  --kv-cache-dtype fp8 \
  --speculative-config "$SPEC" \
  --chat-template /opt/glm53/chat_template.jinja \
  --limit-mm-per-prompt '{"image":2,"video":0}' --skip-mm-profiling \
  --cudagraph-capture-sizes 1 2 4 8 16 24 32
