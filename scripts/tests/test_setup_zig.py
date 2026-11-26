"""Portable toolchain-selection tests without executing the packaging build."""


import importlib.util
from pathlib import Path
import re
import subprocess
import sys
import sysconfig
import tomllib
import unittest
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "_riley_test_zig_toolchain", PROJECT_ROOT / "src" / "riley" / "_zig_toolchain.py",
)
assert SPEC is not None and SPEC.loader is not None
toolchain = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(toolchain)


class ZigSelectionTests(unittest.TestCase):
    def setUp(self):
        self.select = toolchain.select_zig_runner
        self.version = toolchain.REQUIRED_ZIG_VERSION + "\n"
        self.fallback = [sys.executable, "-m", "ziglang"]
        self.path_zig = str(PROJECT_ROOT / "test-toolchain" / "zig")
        self.module_spec = self.enterContext(mock.patch.object(toolchain, "find_spec"))
        self.which = self.enterContext(
            mock.patch.object(toolchain.shutil, "which", return_value=self.path_zig),
        )
        self.probe = self.enterContext(mock.patch.object(toolchain.subprocess, "check_output"))

    def test_matching_path_version_is_preferred(self):
        self.probe.return_value = self.version
        self.assertEqual(self.select(), [self.path_zig])
        self.probe.assert_called_once_with(
            [self.path_zig, "version"], text=True,
            stderr=subprocess.STDOUT, timeout=10,
        )
        self.module_spec.assert_not_called()

    def test_missing_path_uses_pinned_module(self):
        self.which.return_value = None
        self.probe.return_value = self.version
        self.assertEqual(self.select(), self.fallback)
        self.assertEqual(self.probe.call_args.args[0], self.fallback + ["version"])

    def test_mismatched_path_uses_pinned_module(self):
        self.probe.side_effect = ["0.16.0\n", self.version]
        self.assertEqual(self.select(), self.fallback)
        self.assertEqual(
            [call.args[0] for call in self.probe.call_args_list],
            [[self.path_zig, "version"], self.fallback + ["version"]],
        )

    def test_unusable_path_uses_pinned_module(self):
        failures = [
            OSError("not executable"),
            subprocess.CalledProcessError(1, [self.path_zig, "version"]),
            subprocess.TimeoutExpired([self.path_zig, "version"], 10),
        ]
        for failure in failures:
            with self.subTest(failure=type(failure).__name__):
                self.probe.side_effect = [failure, self.version]
                self.assertEqual(self.select(), self.fallback)

    def test_mismatched_module_fails_with_actionable_error(self):
        self.probe.side_effect = ["0.16.0\n", self.version.strip() + "-dev\n"]
        with self.assertRaises(toolchain.ZigUnavailableError) as caught:
            self.select()
        message = str(caught.exception)
        self.assertIn(f"ziglang=={toolchain.REQUIRED_ZIG_VERSION}", message)
        self.assertIn("0.16.0", message)
        self.assertIn(self.version.strip() + "-dev", message)

    def test_missing_module_fails_with_actionable_error(self):
        self.which.return_value = None
        self.module_spec.return_value = None
        with self.assertRaisesRegex(
            toolchain.ZigUnavailableError,
            re.escape(f"Install ziglang=={toolchain.REQUIRED_ZIG_VERSION}"),
        ) as caught:
            self.select()
        self.assertIn("zig not found on PATH", str(caught.exception))
        self.assertIn("ziglang is not installed", str(caught.exception))
        self.probe.assert_not_called()

    def test_broken_module_is_not_reported_as_missing(self):
        self.which.return_value = None
        failure = subprocess.CalledProcessError(1, self.fallback + ["version"])
        self.probe.side_effect = failure
        with self.assertRaises(RuntimeError) as caught:
            self.select()
        self.assertNotIsInstance(caught.exception, toolchain.ZigUnavailableError)
        self.assertIs(caught.exception.__cause__, failure)

    def test_toolchain_version_matches_packaging_pins(self):
        metadata = tomllib.loads((PROJECT_ROOT / "pyproject.toml").read_text())
        pinned = "ziglang==" + toolchain.REQUIRED_ZIG_VERSION
        self.assertIn(pinned, metadata["build-system"]["requires"])
        self.assertIn(pinned, metadata["project"]["optional-dependencies"]["dev"])
        self.assertIn(pinned, metadata["dependency-groups"]["dev"])


class WindowsTargetTests(unittest.TestCase):
    def test_windows_target_matches_python_platform_not_wheel_matrix(self):
        for tag, target in (
            ("win32", "x86-windows-msvc"),
            ("win-amd64", "x86_64-windows-msvc"),
            ("win_amd64", "x86_64-windows-msvc"),
            ("win-arm64", "aarch64-windows-msvc"),
            ("win_arm64", "aarch64-windows-msvc"),
        ):
            with self.subTest(tag=tag), mock.patch.object(
                sysconfig, "get_platform", return_value=tag
            ):
                self.assertEqual(toolchain.get_windows_target_triple(), target)

    def test_unknown_windows_platform_fails_with_actionable_error(self):
        with mock.patch.object(sysconfig, "get_platform", return_value="unknown"), self.assertRaisesRegex(
            RuntimeError, "Unsupported Windows Python platform for Zig build: unknown"
        ):
            toolchain.get_windows_target_triple()



if __name__ == "__main__":
    unittest.main()
