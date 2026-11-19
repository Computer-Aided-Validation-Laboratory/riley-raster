"""Shared build, execution, metadata and smoke profiles for native benchmarks."""
import argparse
import datetime
import os
import shlex
import subprocess
import sys
from benchmark_catalog import (
    BENCHMARKS, STUDIES, EXPERIMENTS, ROOT, binary_name, build_command,
)
from benchmark_runner import run_command


def main(name: str | None = None, argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    delimiter = argv.index("--") if "--" in argv else len(argv)
    options, extra = argv[:delimiter], argv[delimiter + 1:]
    parser = argparse.ArgumentParser(__doc__)
    if name is None:
        parser.add_argument("benchmark", choices=BENCHMARKS)
    parser.add_argument(
        "--profile", choices=("default", "smoke", "static_preparation"), default="default",
    )
    parser.add_argument("--runs", type=int, default=None)
    parser.add_argument("--precision", choices=("f64", "f32"), default="f64")
    parser.add_argument("--simd", choices=("on", "off"), default="on")
    parser.add_argument("--lanes", type=int)
    parser.add_argument("--out-root", type=str, default="out/benchmarks")
    parser.add_argument("--binary", type=str)
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--experiment", help="Named matrix: hulls, solver, buffers or distortion (benchmark dependent)",
    )
    parser.add_argument(
        "--study", action="store_true",
        help="Run specialised experiments; put study arguments after --",
    )
    args = parser.parse_args(options)
    if args.runs is not None and args.runs < 1:
        parser.error("--runs must be positive")
    if args.build and args.binary:
        parser.error(
            "--build and --binary cannot be combined; compile separately before selecting a binary"
        )
    if args.lanes is not None and args.lanes < 1:
        parser.error("--lanes must be positive")
    name = name or args.benchmark
    if args.study:
        if (
            args.precision != "f64" or args.simd != "on" or args.lanes or args.binary
            or args.build or args.experiment or args.profile != "default"
        ):
            parser.error("Study configuration belongs after --; use the study CLI for build and experiment options")
        if name not in STUDIES:
            parser.error("No specialised study for this benchmark; use binary arguments after --")
        study_args = (["--runs", str(args.runs)] if args.runs is not None else [])
        if args.out_root != "out/benchmarks":
            study_args += ["--out-root", args.out_root]
        command = [sys.executable, str(ROOT / "scripts" / STUDIES[name]), *study_args, *extra]
        print(shlex.join(command), flush=True)
        if not args.dry_run:
            subprocess.run(command, cwd=ROOT, check=True)
        return 0
    if args.experiment:
        experiments = EXPERIMENTS[name]
        if args.experiment not in experiments:
            parser.error(f"Available experiments: {', '.join(experiments)}")
        options = options[:]
        index = next(
            ii for ii, value in enumerate(options)
            if value == "--experiment" or value.startswith("--experiment=")
        )
        del options[index:index + (2 if options[index] == "--experiment" else 1)]
        if options and options[0] == name:
            options = options[1:]
        for case in experiments[args.experiment]:
            main(name, [*options, "--", *case, *extra])
        return 0
    if args.profile == "static_preparation" and name != "tiltraster":
        parser.error("static_preparation requires tiltraster")
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    output = (ROOT / args.out_root / name / stamp).resolve()
    binary = (
        ROOT / args.binary if args.binary
        else ROOT / "bin" / binary_name(name, args.precision, args.simd, args.lanes)
    )
    runs = args.runs or (1 if args.profile == "smoke" else 5)
    command = [str(binary), "--out-dir", os.path.relpath(output, ROOT), "--runs", str(runs)]
    custom = name in ("multiroot", "buffer_psf")
    if custom:
        command += ["--threads", "1"]
        if args.profile == "smoke":
            command += [
                "--width", "32", "--height", "32", "--elements-per-type", "1",
                "--warmup", "0", "--sub-sample", "1",
            ]
    else:
        command += ["--total-threads", "1", "--image-out-dir", "", "--save-strategy", "memory"]
        if args.profile == "smoke":
            command += ["--pixels-x", "32", "--pixels-y", "32", "--sub-sample", "1"]
            if name != "dist_psf":
                command += ["--smoke", "true"]
            if name == "dist_psf":
                command += [
                    "--mesh-subset", "tri3", "--mesh-density", "fullraster",
                    "--frames", "1", "--distort", "none", "--psf", "pixel_box",
                ]
            if name == "dicuq":
                command += ["--data-dir", "data/FE/platehole3d_2mr_7f/"]
            if name == "thread_geom":
                command += ["--element", "tri3", "--size", "1e3"]
    if args.profile == "static_preparation":
        command += [
            "--data-dir", "data/bench", "--data-suffix", "geom_1e5",
            "--shader-subset", "static_preparation", "--pixels-x", "1600",
            "--pixels-y", "1000", "--sub-sample", "1",
        ]
    command += extra
    build = build_command(name, args.precision, args.simd, args.lanes)
    if args.build:
        print(shlex.join(build), flush=True)
    print(shlex.join(command), flush=True)
    if args.dry_run:
        return 0
    if args.build:
        subprocess.run(build, cwd=ROOT, check=True)
    try:
        run_command(command, output, {
            "benchmark": name, "profile": args.profile, "runs": runs,
            "precision": args.precision, "simd": args.simd, "lanes": args.lanes,
            "build_command": build,
        })
    except subprocess.CalledProcessError:
        print(f"Benchmark failed; see {output / 'stderr.txt'}", file=sys.stderr)
        raise
    print(f"Results: {output}", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
