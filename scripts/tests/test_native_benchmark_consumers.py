"""Check the executable paths passed by benchmark consumers to their runners."""
import argparse
import contextlib
import csv
import datetime as dt
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import benchmark_harness
import benchmark_runner
import perf_common
import study_buffer_psf
import study_dicuq
import study_dist_psf
import study_multiroot
import study_tiltraster


class NativeBenchmarkConsumerTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory())).resolve()
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))

    def test_harness_resolves_installed_binary_for_each_platform(self):
        for platform, suffix in (("win32", ".exe"), ("linux", "")):
            with (
                self.subTest(platform=platform),
                patch.object(sys, "platform", platform),
                patch.object(benchmark_harness, "ROOT", self.root),
                patch.object(benchmark_harness, "run_command") as run,
            ):
                benchmark_harness.main("geom", ["--profile", "smoke", "--lanes", "4"])
                self.assertEqual(Path(run.call_args.args[0][0]), self.bin_dir / f"bench_geom_f64_simd_v4{suffix}")

    def test_harness_preserves_custom_path(self):
        with (
            patch.object(sys, "platform", "win32"),
            patch.object(benchmark_harness, "ROOT", self.root),
            patch.object(benchmark_harness, "run_command") as run,
        ):
            benchmark_harness.main("geom", ["--binary", "archive/custom geom"])
            self.assertEqual(Path(run.call_args.args[0][0]), self.root / "archive/custom geom")

    def test_dist_psf_launches_absolute_installed_path(self):
        exe = self.bin_dir / "bench_dist_psf_f64_simd.exe"
        exe.touch()
        with (
            patch.object(sys, "platform", "win32"),
            patch.object(study_dist_psf, "repo_root", return_value=self.root),
            patch.object(study_dist_psf, "run_command") as run,
        ):
            study_dist_psf.run_case(
                study_dist_psf.EXPERIMENT1_CASES[0], self.root, None,
                runs=1, frames=1, total_threads=1, max_raster_workers=1, dry_run=False,
            )
            self.assertEqual(Path(run.call_args.args[0][0]), exe)

    def test_tiltraster_uses_installed_exe_but_keeps_experiment_overrides(self):
        exe = self.bin_dir / "bench_tiltraster_f64_simd_v4.exe"
        exe.touch()
        custom = self.bin_dir / "custom tilt"
        custom.touch()
        for source, override in ((study_tiltraster.EXPERIMENT3_CASES, "experiment3_binary"),
                                 (study_tiltraster.EXPERIMENT4_CASES, "experiment4_binary")):
            case = {**source[0], "precision": "f64", "lanes": 4}
            for use_override in (False, True):
                with (
                    self.subTest(override=override, use_override=use_override),
                    patch.object(sys, "platform", "win32"),
                    patch.object(study_tiltraster, "repo_root", return_value=self.root),
                    patch.object(study_tiltraster, "run_command") as run,
                ):
                    overrides = dict(experiment3_binary=None, experiment4_binary=None)
                    if use_override:
                        overrides[override] = custom
                    study_tiltraster.run_case(
                        case, self.root / "runs", self.root / "images",
                        runs=1, pixels_x=None, pixels_y=None, dry_run=False, **overrides,
                    )
                    self.assertEqual(Path(run.call_args.args[0][0]), custom if use_override else exe)

    def test_perf_launches_installed_exe(self):
        exe = self.bin_dir / "bench_geom_f64_simd.exe"
        exe.touch()
        with (
            patch.object(sys, "platform", "win32"),
            patch.object(perf_common, "repo_root", return_value=self.root),
            patch.object(perf_common.subprocess, "run") as run,
        ):
            perf_common.run_benchmark_binary(
                perf_common.PERF_CASES["geom"], perf_common.profile_or_die("geom", "1thread"),
                runs=1, out_dir=self.root / "perf",
            )
            self.assertEqual(Path(run.call_args.args[0][0]), exe)

    def test_dicuq_launches_installed_exe(self):
        with (
            patch.object(sys, "platform", "win32"),
            patch.object(study_dicuq, "repo_root", return_value=self.root),
            patch.object(study_dicuq, "run_command") as run,
        ):
            study_dicuq.run_case(
                {"experiment": "smoke", "case_name": "smoke", "args": []}, self.root,
                runs=1, dry_run=False, case_idx=1, total_cases=1,
            )
            self.assertEqual(Path(run.call_args.args[0][0]), self.bin_dir / "bench_dicuq_f64_simd.exe")

    def test_multiroot_study_metadata_and_summaries_use_one_timestamp(self):
        def run_native(command, **_kwargs):
            options = dict(zip(command[1::2], command[2::2]))
            row = dict.fromkeys(study_multiroot.FIELDS, "1")
            for field in ("scene", "mode", "one_root_edge_mode", "multi_root_edge_mode", "buffer_mode"):
                row[field] = options["--" + field.replace("_", "-")]
            raw_csv = Path(options["--out-dir"]) / "raw_stats_multiroot.csv"
            with raw_csv.open("w", newline="") as file:
                writer = csv.DictWriter(file, fieldnames=row.keys())
                writer.writeheader()
                writer.writerow(row)
            return subprocess.CompletedProcess(command, 0)

        out_root = self.root / "runs"
        with (
            patch.object(study_multiroot, "ROOT", self.root),
            patch.object(study_multiroot, "dt") as clock,
            patch.object(benchmark_runner.subprocess, "run", side_effect=run_native) as run,
            patch.object(sys, "argv", ["study_multiroot.py", "--skip-build", "--out-root", str(out_root)]),
        ):
            clock.datetime.now.return_value = dt.datetime(2026, 11, 24, 12, 0, 0)
            study_multiroot.main()
        clock.datetime.now.assert_called_once_with()
        timestamp = "20261124_120000"
        run_root = out_root / timestamp
        aggregate = self.root / "out" / f"summary_bench_multiroot_median_{timestamp}.csv"
        self.assertEqual((run_root / "summary_stats_multiroot.csv").read_bytes(), aggregate.read_bytes())
        metadata_paths = list(out_root.glob("*/*/metadata.json"))
        self.assertEqual(len(metadata_paths), run.call_count)
        self.assertTrue(metadata_paths)
        for path in metadata_paths:
            metadata = json.loads(path.read_text())
            command = metadata["command"]
            self.assertEqual(Path(command[command.index("--out-dir") + 1]), path.parent)
            self.assertEqual(path.parent.parent, run_root)

    def test_small_scene_studies_launch_installed_exe_and_keep_multiroot_override(self):
        args = argparse.Namespace(
            out_dir=self.root, elements_per_type=1, width=32, height=32,
            runs=1, warmup=0, threads=1, sub_sample=1, binary=None,
        )
        custom = self.root / "archive/custom multi-root"
        for study, override, expected in (
            (study_buffer_psf, None, self.bin_dir / "bench_buffer_psf_f64_simd.exe"),
            (study_multiroot, None, self.bin_dir / "bench_multiroot_f64_simd.exe"),
            (study_multiroot, custom, custom),
        ):
            name = study.__name__.removeprefix("study_")

            def write_result(command, case_dir):
                case_dir.mkdir(exist_ok=True)
                (case_dir / f"raw_stats_{name}.csv").write_text("e2e_ms\n1\n")

            with (
                self.subTest(name=name, override=override),
                patch.object(sys, "platform", "win32"),
                patch.object(study, "ROOT", self.root),
                patch.object(study, "run_command", side_effect=write_result) as run,
            ):
                args.binary = override
                if study is study_buffer_psf:
                    study.run_case(args, "smoke", "sparse", "tile_local", "none", 1)
                else:
                    study.run_case(args, "simd", "smoke", "fast")
                self.assertEqual(Path(run.call_args.args[0][0]), expected)


if __name__ == "__main__":
    unittest.main()
