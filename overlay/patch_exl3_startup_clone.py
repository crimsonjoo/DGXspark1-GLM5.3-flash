#!/usr/bin/env python3
"""Backport the mmap-to-anonymous-RAM EXL3 startup optimization idempotently."""
from pathlib import Path

TARGET = Path(
    "/usr/local/lib/python3.12/dist-packages/vllm/model_executor/layers/quantization/exl3.py"
)


def patch(path: Path = TARGET) -> None:
    source = path.read_text()
    old_linear = "        dest.copy_(loaded_weight)\n"
    new_linear = (
        "        loaded_weight = loaded_weight.clone() if loaded_weight.device.type == \"cpu\" else loaded_weight.contiguous()\n"
        "        dest.copy_(loaded_weight)\n"
    )
    if new_linear not in source:
        if source.count(old_linear) != 1:
            raise RuntimeError("expected one EXL3 linear copy target")
        source = source.replace(old_linear, new_linear, 1)

    old_expert = "        loaded = loaded_weight.detach().contiguous()\n"
    new_expert = (
        "        loaded = loaded_weight.detach().contiguous()\n"
        "        loaded = loaded.clone() if loaded.device.type == \"cpu\" else loaded.contiguous()\n"
    )
    if new_expert not in source:
        if source.count(old_expert) != 1:
            raise RuntimeError("expected one EXL3 expert copy target")
        source = source.replace(old_expert, new_expert, 1)
    path.write_text(source)


if __name__ == "__main__":
    patch()
    print("EXL3 anonymous-RAM startup clone optimization installed")
