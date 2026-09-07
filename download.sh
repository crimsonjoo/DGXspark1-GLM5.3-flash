#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_REPO=turboderp/GLM-5.3-Flash-exl3; TARGET_REV=51058cd551c7e570d87bd32a4adee720edce2349
DRAFT_REPO=incoai/GLM-5.3-Flash-DFlash2; DRAFT_REV=bf582e4eacc1810f76656d1811693ff6c6737d2a
MODEL_DIR="${MODEL_DIR:-$HOME/models/GLM-5.3-Flash-exl3-2.05bpw}"; DFLASH_DIR="${DFLASH_DIR:-$HOME/models/GLM-5.3-Flash-DFlash2}"
[ "${ACCEPT_DFLASH2_NC_LICENSE:-0}" = 1 ] || { echo 'Accept the DFlash2 non-commercial license first: https://huggingface.co/incoai/GLM-5.3-Flash-DFlash2' >&2; exit 2; }
if command -v hf >/dev/null 2>&1; then HF=hf; else python3 -m venv "$ROOT/.venv-tools"; "$ROOT/.venv-tools/bin/pip" install -U 'huggingface_hub[hf_xet]'; HF="$ROOT/.venv-tools/bin/hf"; fi
mkdir -p "$MODEL_DIR" "$DFLASH_DIR"; export HF_XET_HIGH_PERFORMANCE=1
echo "Downloading pinned target (~80 GiB, resumable) to $MODEL_DIR"; "$HF" download "$TARGET_REPO" --revision "$TARGET_REV" --local-dir "$MODEL_DIR"
echo "Downloading pinned drafter (~2.2 GiB, resumable) to $DFLASH_DIR"; "$HF" download "$DRAFT_REPO" --revision "$DRAFT_REV" --local-dir "$DFLASH_DIR"
find "$MODEL_DIR" "$DFLASH_DIR" -type f \( -name '*.incomplete' -o -name '*.part' \) -print -quit | grep -q . && { echo 'Incomplete artifacts remain; rerun ./start.sh.' >&2; exit 1; }
printf '%s\n' "$TARGET_REV" > "$MODEL_DIR/ONE_SPARK_REVISION"; printf '%s\n' "$DRAFT_REV" > "$DFLASH_DIR/ONE_SPARK_REVISION"
echo 'Pinned downloads complete.'
