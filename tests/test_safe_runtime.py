import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SafeRuntimePatchTests(unittest.TestCase):
    def test_mhc_patch_is_safe_and_idempotent(self):
        mod = load("patch_mhc", ROOT / "overlay/patch_mhc_sm121_safe.py")
        original = "import torch\n\n" + ("    def enabled(cls) -> bool:\n        return True\n" * 4)
        with tempfile.TemporaryDirectory() as td:
            target = Path(td) / "mhc.py"
            target.write_text(original)
            mod.patch(target); once = target.read_text(); mod.patch(target)
            self.assertEqual(once, target.read_text())
            self.assertEqual(once.count("GLM53_SAFE_MHC"), 4)

    def test_exl3_patch_is_idempotent(self):
        mod = load("patch_exl3", ROOT / "overlay/patch_exl3_startup_clone.py")
        original = "        dest.copy_(loaded_weight)\n        loaded = loaded_weight.detach().contiguous()\n"
        with tempfile.TemporaryDirectory() as td:
            target = Path(td) / "exl3.py"
            target.write_text(original)
            mod.patch(target); once = target.read_text(); mod.patch(target)
            self.assertEqual(once, target.read_text())
            self.assertIn("loaded_weight = loaded_weight.clone()", once)


if __name__ == "__main__":
    unittest.main()
