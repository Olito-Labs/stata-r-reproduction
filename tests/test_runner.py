import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
spec = importlib.util.spec_from_file_location("runner", ROOT / "scripts/run_demo.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class RunnerTests(unittest.TestCase):
    def test_mac_command(self):
        self.assertEqual(mod.stata_command("/opt/stata mp", "Darwin"), ["/opt/stata mp", "-e", "do", "wrapper.do"])

    def test_linux_command(self):
        self.assertEqual(mod.stata_command("stata", "Linux"), ["stata", "-b", "do", "wrapper.do"])

    def test_windows_command(self):
        self.assertEqual(mod.stata_command("StataMP.exe", "Windows"), ["StataMP.exe", "/e", "do", "wrapper.do"])

    def test_unsupported_platform(self):
        with self.assertRaises(ValueError):
            mod.stata_command("stata", "Other")

    def test_exclusive_output(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(FileExistsError):
                mod.run(Path(temp), r_only=True)

    def test_missing_executable(self):
        with patch.object(mod.shutil, "which", return_value=None):
            with self.assertRaises(ValueError):
                mod.executable("nonexistent-rscript")

    def test_stata_success_marker_required(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                mod.check_stata_completion(Path(temp))
            (Path(temp) / "exit-status.txt").write_text("459\n")
            with self.assertRaises(ValueError):
                mod.check_stata_completion(Path(temp))
            (Path(temp) / "exit-status.txt").write_text("0\n")
            mod.check_stata_completion(Path(temp))

    def test_wrapper_uses_isolated_relative_paths(self):
        text = mod.wrapper_source()
        self.assertIn("capture noisily do", text)
        self.assertIn("local run_rc = _rc", text)
        self.assertIn('"exit-status.txt"', text)
        self.assertNotIn(str(ROOT), text)


if __name__ == "__main__":
    unittest.main()
