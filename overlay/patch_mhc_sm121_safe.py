#!/usr/bin/env python3
"""Route vLLM mHC custom ops to their native implementations on GB10/SM121.

The TileLang/DeepGEMM mHC path has produced repeatable CUDA illegal-address
failures for partial long-prefix prefills on a DGX Spark.  The native methods
are the reference implementations already shipped by vLLM.
"""
from pathlib import Path

TARGET = Path("/usr/local/lib/python3.12/dist-packages/vllm/model_executor/layers/mhc.py")


def patch(path: Path = TARGET) -> None:
    source = path.read_text()
    if "GLM53_SAFE_MHC" in source:
        return
    source = source.replace("import torch\n", "import os\n\nimport torch\n", 1)
    old = "    def enabled(cls) -> bool:\n        return True\n"
    new = (
        "    def enabled(cls) -> bool:\n"
        "        # GB10 safety switch: native PyTorch avoids the SM121 TileLang/DeepGEMM\n"
        "        # illegal-address failure seen with partial long-prefix prefills.\n"
        "        return os.environ.get(\"GLM53_SAFE_MHC\", \"1\") != \"1\"\n"
    )
    count = source.count(old)
    if count != 4:
        raise RuntimeError(f"expected four mHC enabled() methods, found {count}")
    path.write_text(source.replace(old, new))


if __name__ == "__main__":
    patch()
    print("GLM53_SAFE_MHC runtime switch installed (safe/native default)")
