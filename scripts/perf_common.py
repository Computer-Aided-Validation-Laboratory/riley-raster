#!/usr/bin/env python3
from __future__ import annotations

import csv
import datetime as dt
import json
import pathlib
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass
from typing import Final


DEFAULT_GOLD_RUNS: Final[int] = 25
DEFAULT_TEST_RUNS: Final[int] = 10
E2E_KEY: Final[str] = "E2E Time [ms]"
RASTER_KEY: Final[str] = "Raster Time [ms]"
GEOM_KEY: Final[str] = "Geom Time [ms]"
TOP_N: Final[int] = 10


@dataclass(frozen=True)
class PerfCase:
    name: str
    benchmark_name: str
    binary_name: str


@dataclass(frozen=True)
class PerfDelta:
    case_name: str
    gold_median_ms: float
    gold_mad_ms: float
    current_median_ms: float
    current_mad_ms: float
    gold_raster_ms: float
    current_raster_ms: float
    gold_geom_ms: float
    current_geom_ms: float
    delta_ms: float
    delta_pct: float
    mad_units: float
    significant: bool


PERF_CASES: Final[dict[str, PerfCase]] = {
    "fullraster": PerfCase(
        name="fullraster",
        benchmark_name="bench_fullraster",
        binary_name="bench_fullraster_simd",
    ),
    "geom": PerfCase(
        name="geom",
        benchmark_name="bench_geom",
        binary_name="bench_geom_simd",
    ),
    "sphere2000": PerfCase(
        name="sphere2000",
        benchmark_name="bench_sphere2000",
        binary_name="bench_sphere2000_simd",
    ),
    "sphere2000zoom": PerfCase(
        name="sphere2000zoom",
        benchmark_name="bench_sphere2000zoom",
        binary_name="bench_sphere2000zoom_simd",
    ),
}


def repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parent.parent


def command_path(path: pathlib.Path) -> str:
    path_abs = path.resolve()
    root_abs = repo_root().resolve()
    try:
        return str(path_abs.relative_to(root_abs))
    except ValueError:
        return str(path_abs)


def python_path() -> pathlib.Path:
    venv_python = repo_root() / ".venv" / "bin" / "python"
    if venv_python.exists():
        return venv_python
    return pathlib.Path(sys.executable)


def timestamp_string() -> str:
    return dt.datetime.now().strftime("%Y%m%d_%H%M%S")


def case_or_die(case_name: str) -> PerfCase:
    try:
        return PERF_CASES[case_name]
    except KeyError as exc:
        names = ", ".join(PERF_CASES.keys())
        raise SystemExit(f"Unknown perf case '{case_name}'. Expected one of: {names}.") from exc


def binary_path(case: PerfCase) -> pathlib.Path:
    path = repo_root() / "bin" / case.binary_name
    if not path.exists():
        raise SystemExit(
            f"Missing benchmark binary {path}. Run scripts/compile_para_simd_benchmarks.py first.",
        )
    return path


def gold_dir(case: PerfCase) -> pathlib.Path:
    return repo_root() / "gold" / "perf" / case.name / "single_thread"


def test_run_dir(case: PerfCase) -> pathlib.Path:
    return repo_root() / "out" / "perf_test" / case.name / timestamp_string()


def gold_stage_dir(case: PerfCase) -> pathlib.Path:
    return repo_root() / "out" / "perf_gold_stage" / case.name / timestamp_string()


def image_out_dir(case: PerfCase) -> pathlib.Path:
    return repo_root() / "out" / "perf_images" / case.name


def summary_file_map(root: pathlib.Path) -> dict[str, pathlib.Path]:
    return {
        "median": root / "bench_stats_median.csv",
        "mad": root / "bench_stats_mad.csv",
        "min": root / "bench_stats_min.csv",
        "max": root / "bench_stats_max.csv",
        "cov": root / "bench_stats_cov.csv",
    }


def single_thread_args() -> list[str]:
    return [
        "--render-group-count",
        "1",
        "--total-threads",
        "1",
        "--max-geom-threads-per-frame",
        "1",
        "--max-raster-threads-per-frame",
        "1",
        "--max-frames-in-flight",
        "1",
        "--frame-batch-size-per-group",
        "1",
        "--max-geom-jobs-in-flight-per-group",
        "1",
        "--max-geom-workers-per-job",
        "1",
        "--max-raster-workers-per-job",
        "1",
        "--save-strategy",
        "memory",
    ]


def run_benchmark_binary(
    case: PerfCase,
    runs: int,
    out_dir: pathlib.Path,
) -> list[str]:
    out_dir.parent.mkdir(parents=True, exist_ok=True)
    image_out_dir(case).mkdir(parents=True, exist_ok=True)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    cmd = [
        str(binary_path(case)),
        "--out-dir",
        command_path(out_dir),
        "--image-out-dir",
        command_path(image_out_dir(case)),
        "--runs",
        str(runs),
        *single_thread_args(),
    ]

    (out_dir / "command.txt").write_text(" ".join(cmd) + "\n")

    with (out_dir / "stdout.txt").open("w") as stdout_file, (
        out_dir / "stderr.txt"
    ).open("w") as stderr_file:
        subprocess.run(
            cmd,
            cwd=repo_root(),
            check=True,
            stdout=stdout_file,
            stderr=stderr_file,
        )

    return cmd


def load_csv_rows(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open(newline="") as csv_file:
        return list(csv.DictReader(csv_file))


def load_summary_map(root: pathlib.Path, kind: str) -> dict[str, dict[str, str]]:
    rows = load_csv_rows(summary_file_map(root)[kind])
    return {row["Case"]: row for row in rows}


def parse_float(row: dict[str, str], key: str) -> float:
    return float(row[key])


def delta_significance_threshold_ms(
    gold_median_ms: float,
    gold_mad_ms: float,
    current_mad_ms: float,
) -> float:
    return max(
        3.0 * max(gold_mad_ms, current_mad_ms),
        0.02 * gold_median_ms,
        0.05,
    )


def compare_case_maps(
    gold_root: pathlib.Path,
    current_root: pathlib.Path,
) -> list[PerfDelta]:
    gold_median = load_summary_map(gold_root, "median")
    gold_mad = load_summary_map(gold_root, "mad")
    current_median = load_summary_map(current_root, "median")
    current_mad = load_summary_map(current_root, "mad")

    gold_cases = set(gold_median.keys())
    current_cases = set(current_median.keys())
    if gold_cases != current_cases:
        missing = sorted(gold_cases - current_cases)
        extra = sorted(current_cases - gold_cases)
        raise SystemExit(
            "Mismatch in compared perf cases. "
            f"Missing in current: {missing}. Extra in current: {extra}.",
        )

    deltas: list[PerfDelta] = []
    for case_name in sorted(gold_cases):
        gold_med_row = gold_median[case_name]
        gold_mad_row = gold_mad[case_name]
        cur_med_row = current_median[case_name]
        cur_mad_row = current_mad[case_name]

        gold_median_ms = parse_float(gold_med_row, E2E_KEY)
        current_median_ms = parse_float(cur_med_row, E2E_KEY)
        gold_mad_ms = parse_float(gold_mad_row, E2E_KEY)
        current_mad_ms = parse_float(cur_mad_row, E2E_KEY)
        delta_ms = current_median_ms - gold_median_ms
        delta_pct = 0.0 if gold_median_ms == 0.0 else delta_ms / gold_median_ms * 100.0
        mad_units = delta_ms / max(gold_mad_ms, current_mad_ms, 1e-9)
        significant = abs(delta_ms) >= delta_significance_threshold_ms(
            gold_median_ms,
            gold_mad_ms,
            current_mad_ms,
        )

        deltas.append(
            PerfDelta(
                case_name=case_name,
                gold_median_ms=gold_median_ms,
                gold_mad_ms=gold_mad_ms,
                current_median_ms=current_median_ms,
                current_mad_ms=current_mad_ms,
                gold_raster_ms=parse_float(gold_med_row, RASTER_KEY),
                current_raster_ms=parse_float(cur_med_row, RASTER_KEY),
                gold_geom_ms=parse_float(gold_med_row, GEOM_KEY),
                current_geom_ms=parse_float(cur_med_row, GEOM_KEY),
                delta_ms=delta_ms,
                delta_pct=delta_pct,
                mad_units=mad_units,
                significant=significant,
            ),
        )

    return deltas


def copy_perf_outputs(
    src_root: pathlib.Path,
    dst_root: pathlib.Path,
) -> None:
    if dst_root.exists():
        shutil.rmtree(dst_root)
    dst_root.mkdir(parents=True)

    for name in (
        "bench_stats_median.csv",
        "bench_stats_mad.csv",
        "bench_stats_min.csv",
        "bench_stats_max.csv",
        "bench_stats_cov.csv",
        "command.txt",
        "stdout.txt",
        "stderr.txt",
    ):
        path = src_root / name
        if path.exists():
            shutil.copy2(path, dst_root / name)

    for run_csv in src_root.glob("bench_run*.csv"):
        shutil.copy2(run_csv, dst_root / run_csv.name)


def write_metadata(
    out_dir: pathlib.Path,
    case: PerfCase,
    runs: int,
    command: list[str],
) -> None:
    payload = {
        "case": case.name,
        "benchmark_name": case.benchmark_name,
        "binary_name": case.binary_name,
        "runs": runs,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "single_threaded": True,
        "command": command,
    }
    (out_dir / "metadata.json").write_text(json.dumps(payload, indent=2) + "\n")


def write_comparison_json(
    out_dir: pathlib.Path,
    deltas: list[PerfDelta],
) -> None:
    payload = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "deltas": [asdict(delta) for delta in deltas],
    }
    (out_dir / "comparison.json").write_text(json.dumps(payload, indent=2) + "\n")


def report_deltas(case: PerfCase, deltas: list[PerfDelta]) -> int:
    regressions = sorted(
        [delta for delta in deltas if delta.delta_ms > 0.0],
        key=lambda item: (item.significant, item.delta_ms, item.delta_pct),
        reverse=True,
    )
    improvements = sorted(
        [delta for delta in deltas if delta.delta_ms < 0.0],
        key=lambda item: (item.significant, item.delta_ms),
    )

    significant_regressions = [delta for delta in regressions if delta.significant]
    significant_improvements = [delta for delta in improvements if delta.significant]

    print(f"[perf:{case.name}] Top regressions vs gold (E2E median):")
    for delta in regressions[:TOP_N]:
        sig = "SIGNIFICANT" if delta.significant else "noise"
        print(
            "  "
            f"{delta.case_name}: "
            f"{delta.current_median_ms:.6f} ms vs {delta.gold_median_ms:.6f} ms "
            f"({delta.delta_ms:+.6f} ms, {delta.delta_pct:+.2f}%, "
            f"{delta.mad_units:+.2f} MAD, {sig})",
        )

    print(f"[perf:{case.name}] Top improvements vs gold (E2E median):")
    for delta in improvements[:TOP_N]:
        sig = "SIGNIFICANT" if delta.significant else "noise"
        print(
            "  "
            f"{delta.case_name}: "
            f"{delta.current_median_ms:.6f} ms vs {delta.gold_median_ms:.6f} ms "
            f"({delta.delta_ms:+.6f} ms, {delta.delta_pct:+.2f}%, "
            f"{delta.mad_units:+.2f} MAD, {sig})",
        )

    if not significant_regressions and not significant_improvements:
        print(f"[perf:{case.name}] No significant performance difference detected.")
        return 0

    if significant_regressions:
        print(
            f"[perf:{case.name}] Significant regressions detected: "
            f"{len(significant_regressions)} case(s).",
        )
        return 1

    print(
        f"[perf:{case.name}] Significant improvements detected: "
        f"{len(significant_improvements)} case(s).",
    )
    return 0


def generate_gold(case_name: str, runs: int = DEFAULT_GOLD_RUNS) -> int:
    case = case_or_die(case_name)
    print(f"[perf:{case.name}] Generating gold with {runs} single-threaded runs...")
    staging_dir = gold_stage_dir(case)
    command = run_benchmark_binary(case, runs, staging_dir)
    final_gold_dir = gold_dir(case)
    copy_perf_outputs(staging_dir, final_gold_dir)
    write_metadata(final_gold_dir, case, runs, command)
    print(f"[perf:{case.name}] Gold written to {final_gold_dir}")
    return 0


def test_perf(case_name: str, runs: int = DEFAULT_TEST_RUNS) -> int:
    case = case_or_die(case_name)
    baseline_dir = gold_dir(case)
    if not baseline_dir.exists():
        raise SystemExit(
            f"Missing perf gold for {case.name} at {baseline_dir}. "
            f"Run gen_gold_perf_{case.name}.py first.",
        )

    print(f"[perf:{case.name}] Running comparison with {runs} single-threaded runs...")
    out_dir = test_run_dir(case)
    command = run_benchmark_binary(case, runs, out_dir)
    write_metadata(out_dir, case, runs, command)
    deltas = compare_case_maps(baseline_dir, out_dir)
    write_comparison_json(out_dir, deltas)
    return report_deltas(case, deltas)


def run_case_script(script_name: str, runs: int | None = None) -> None:
    command = [str(python_path()), str(repo_root() / "scripts" / script_name)]
    if runs is not None:
        command.extend(["--runs", str(runs)])
    subprocess.run(command, cwd=repo_root(), check=True)


def update_buildconfig_simd(simd_mode: str) -> None:
    buildconfig_path = repo_root() / "src" / "riley" / "zig" / "buildconfig.zig"
    text = buildconfig_path.read_text()
    pattern = re.compile(
        r"(^\s*simd:\s*SimdMode\s*=\s*)\.(on|off)(,\s*$)",
        re.MULTILINE,
    )
    text_updated, replace_count = pattern.subn(
        r"\1." + simd_mode + r"\3",
        text,
        count=1,
    )
    if replace_count != 1:
        raise SystemExit("Failed to update buildconfig simd mode.")
    buildconfig_path.write_text(text_updated)
