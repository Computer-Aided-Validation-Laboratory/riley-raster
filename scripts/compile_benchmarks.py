#!/usr/bin/env python3
"""Compile selected benchmarks; defaults to all benchmarks, f64 and SIMD on."""
import argparse
import subprocess
from concurrent.futures import ThreadPoolExecutor
from benchmark_catalog import BENCHMARKS, ROOT, build_command


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("benchmarks", nargs="*", help="Benchmark names; omit to compile all")
    parser.add_argument("--precision", choices=("f64", "f32"), default="f64")
    parser.add_argument("--simd", choices=("on", "off"), default="on")
    parser.add_argument("--lanes", type=int)
    parser.add_argument("--jobs", type=int, default=2, help="Concurrent benchmark builds (default: 2)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    names = args.benchmarks or BENCHMARKS
    if args.lanes is not None and args.lanes < 1:
        parser.error("--lanes must be positive")
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    for name in names:
        if name not in BENCHMARKS:
            parser.error(f"Unknown benchmark: {name}")
    def compile_one(name):
        command = build_command(name, args.precision, args.simd, args.lanes)
        print(" ".join(command), flush=True)
        if not args.dry_run:
            subprocess.run(command, cwd=ROOT, check=True)
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(compile_one, names))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
