"""Contract checks for benchmark discovery, routing and failure reporting."""
import contextlib
import io
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from benchmark_catalog import BENCHMARKS, EXPERIMENTS, ROOT, binary_name, build_command
from benchmark_harness import main


class BenchmarkHarnessTests(unittest.TestCase):
    def test_catalogue_matches_native_targets(self):
        targets = set(re.findall(r'\.step_name = "bench-([^"]+)"', (ROOT / "build.zig").read_text()))
        self.assertEqual({name.replace("_", "-") for name in BENCHMARKS}, targets)
        for name in BENCHMARKS:
            self.assertTrue((ROOT / "scripts" / f"bench_{name}.py").is_file())
            self.assertIn(f"install-bench-{name.replace('_', '-')}", build_command(name))

    def test_experiment_values_match_native_enums(self):
        raster_config = (ROOT / "src/riley/zig/rasterconfig.zig").read_text()
        hull_modes = raster_config.split("pub const HullMode = enum", 1)[1].split("};", 1)[0]
        distort_modes = (ROOT / "src/bench_dist_psf.zig").read_text().split("pub const DistortCase = enum", 1)[1].split("};", 1)[0]
        for name, experiments in EXPERIMENTS.items():
            for cases in experiments.values():
                for flag, value in cases:
                    if flag == "--hull-mode":
                        self.assertRegex(hull_modes, rf"\b{value}\b")
                    if flag == "--distort":
                        self.assertRegex(distort_modes, rf"\b{value}\b")

    def test_binary_names(self):
        self.assertEqual(binary_name("geom"), "bench_geom_f64_simd")
        self.assertEqual(binary_name("geom", lanes=8), "bench_geom_f64_simd")
        self.assertEqual(binary_name("geom", lanes=4), "bench_geom_f64_simd_v4")
        self.assertEqual(binary_name("geom", simd="off"), "bench_geom_f64_scalar")
        self.assertEqual(binary_name("geom", "f32", lanes=16), "bench_geom_f32_simd")

    def test_every_smoke_profile_is_a_side_effect_free_dry_run(self):
        with patch("benchmark_harness.subprocess.run") as run:
            for name in BENCHMARKS:
                with self.subTest(name=name), contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(main(name, ["--profile", "smoke", "--dry-run"]), 0)
                    self.assertIn(binary_name(name), output.getvalue())
                    self.assertIn("--runs 1", output.getvalue())
            run.assert_not_called()

    def test_all_experiment_matrices_expand(self):
        for name, experiments in EXPERIMENTS.items():
            for experiment, cases in experiments.items():
                with self.subTest(name=name), contextlib.redirect_stdout(io.StringIO()) as output:
                    main(name, ["--experiment", experiment, "--profile", "smoke", "--dry-run"])
                    self.assertEqual(len(output.getvalue().splitlines()), len(cases))

    def test_extra_arguments_and_preserved_binary(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            main("geom", ["--binary", "out/baseline/geom", "--dry-run", "--", "--runs", "2"])
        self.assertIn(str(ROOT / "out/baseline/geom"), output.getvalue())
        self.assertTrue(output.getvalue().strip().endswith("--runs 2"))

    def test_generic_cli_parses_options_after_benchmark(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            main(argv=["geom", "--profile", "smoke", "--dry-run"])
        self.assertIn("--runs 1", output.getvalue())

    def test_failed_binary_preserves_logs_and_propagates_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch("benchmark_harness.subprocess.run", side_effect=subprocess.CalledProcessError(1, ["fake"])), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(subprocess.CalledProcessError):
                    main("geom", ["--profile", "smoke", "--out-root", directory])
            outputs = list(pathlib.Path(directory).glob("geom/*"))
            self.assertEqual(len(outputs), 1)
            metadata = json.loads((outputs[0] / "metadata.json").read_text())
            self.assertEqual(metadata["precision"], "f64")
            self.assertTrue((outputs[0] / "stderr.txt").is_file())

    def test_study_receives_runs_and_native_options(self):
        with patch("benchmark_harness.subprocess.run") as run, contextlib.redirect_stdout(io.StringIO()):
            main("multiroot", ["--study", "--runs", "1", "--", "--quick", "--skip-build"])
        self.assertEqual(run.call_args.args[0][-4:], ["--runs", "1", "--quick", "--skip-build"])


if __name__ == "__main__":
    unittest.main()
