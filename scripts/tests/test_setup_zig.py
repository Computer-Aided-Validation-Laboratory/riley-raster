"""Portable toolchain-selection tests without executing the packaging build."""

import ast
from pathlib import Path
import shutil
import subprocess
import sys
import sysconfig
import tomllib
import unittest
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[2]


class ZigSelectionTests(unittest.TestCase):
    def setUp(self):
        # Importing setup.py would cythonize sources and invoke setuptools.
        # Deliberately bind only these selectors' stdlib dependencies; update
        # this fixture if they acquire new module-level dependencies.
        tree = ast.parse((PROJECT_ROOT / "setup.py").read_text())
        declarations = [
            node for node in tree.body
            if (
                isinstance(node, ast.FunctionDef)
                and node.name in ("select_zig_runner", "get_windows_target_triple")
            ) or (
                isinstance(node, ast.Assign)
                and any(
                    isinstance(target, ast.Name)
                    and target.id == "REQUIRED_ZIG_VERSION"
                    for target in node.targets
                )
            )
        ]
        self.namespace = {
            "shutil": shutil, "subprocess": subprocess,
            "sys": sys, "sysconfig": sysconfig,
        }
        exec(compile(ast.Module(body=declarations, type_ignores=[]), "setup.py", "exec"), self.namespace)
        self.select = self.namespace["select_zig_runner"]
        self.fallback = [sys.executable, "-m", "ziglang"]
        self.path_zig = str(PROJECT_ROOT / "test-toolchain" / "zig")

    def test_matching_path_version_is_preferred(self):
        with mock.patch.object(shutil, "which", return_value=self.path_zig), mock.patch.object(
            subprocess, "check_output", return_value="0.16.0\n"
        ) as probe:
            self.assertEqual(self.select(), [self.path_zig])
        probe.assert_called_once_with(
            [self.path_zig, "version"], text=True,
            stderr=subprocess.STDOUT, timeout=10,
        )

    def test_missing_path_uses_pinned_module(self):
        with mock.patch.object(shutil, "which", return_value=None), mock.patch.object(
            subprocess, "check_output", return_value="0.16.0\n"
        ) as probe:
            self.assertEqual(self.select(), self.fallback)
        self.assertEqual(probe.call_args.args[0], self.fallback + ["version"])

    def test_mismatched_path_uses_pinned_module(self):
        with mock.patch.object(shutil, "which", return_value=self.path_zig), mock.patch.object(
            subprocess, "check_output", side_effect=["0.15.2\n", "0.16.0\n"]
        ) as probe:
            self.assertEqual(self.select(), self.fallback)
        self.assertEqual(probe.call_count, 2)

    def test_unusable_path_uses_pinned_module(self):
        failures = [
            OSError("not executable"),
            subprocess.CalledProcessError(1, [self.path_zig, "version"]),
            subprocess.TimeoutExpired([self.path_zig, "version"], 10),
        ]
        for failure in failures:
            with self.subTest(failure=type(failure).__name__), mock.patch.object(
                shutil, "which", return_value=self.path_zig
            ), mock.patch.object(
                subprocess, "check_output", side_effect=[failure, "0.16.0\n"]
            ):
                self.assertEqual(self.select(), self.fallback)

    def test_mismatched_module_fails_with_actionable_error(self):
        with mock.patch.object(shutil, "which", return_value=self.path_zig), mock.patch.object(
            subprocess, "check_output", side_effect=["0.15.2\n", "0.17.0-dev\n"]
        ), self.assertRaisesRegex(RuntimeError, "requires Zig 0.16.0") as caught:
            self.select()
        message = str(caught.exception)
        self.assertIn("ziglang==0.16.0", message)
        self.assertIn("0.15.2", message)
        self.assertIn("0.17.0-dev", message)

    def test_missing_module_fails_with_actionable_error(self):
        with mock.patch.object(shutil, "which", return_value=None), mock.patch.object(
            subprocess, "check_output",
            side_effect=subprocess.CalledProcessError(1, self.fallback + ["version"]),
        ), self.assertRaisesRegex(RuntimeError, "Install ziglang==0.16.0"):
            self.select()

    def test_windows_target_matches_python_platform_not_wheel_matrix(self):
        select_target = self.namespace["get_windows_target_triple"]
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
                self.assertEqual(select_target(), target)

    def test_unknown_windows_platform_fails_with_actionable_error(self):
        with mock.patch.object(sysconfig, "get_platform", return_value="unknown"), self.assertRaisesRegex(
            RuntimeError, "Unsupported Windows Python platform for Zig build: unknown"
        ):
            self.namespace["get_windows_target_triple"]()

    def test_extras_and_checkout_groups_remain_in_sync(self):
        metadata = tomllib.loads((PROJECT_ROOT / "pyproject.toml").read_text())
        for name in ("dev", "docs"):
            with self.subTest(group=name):
                self.assertEqual(
                    metadata["project"]["optional-dependencies"][name],
                    metadata["dependency-groups"][name],
                )

    def test_toolchain_version_matches_packaging_pins(self):
        metadata = tomllib.loads((PROJECT_ROOT / "pyproject.toml").read_text())
        pinned = "ziglang==" + self.namespace["REQUIRED_ZIG_VERSION"]
        self.assertIn(pinned, metadata["build-system"]["requires"])
        self.assertIn(pinned, metadata["project"]["optional-dependencies"]["dev"])
        self.assertIn(pinned, metadata["dependency-groups"]["dev"])


if __name__ == "__main__":
    unittest.main()
