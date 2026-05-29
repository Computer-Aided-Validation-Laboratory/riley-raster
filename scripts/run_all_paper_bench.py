#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import subprocess
import sys


SCRIPT_ORDER = [
    "paper_bench1_raster.py",
    "paper_bench2_geom.py",
    "paper_bench3_ablation.py",
    "paper_bench4_threading.py",
]


def main() -> int:
    script_dir = pathlib.Path(__file__).resolve().parent
    repo_dir = script_dir.parent

    for script_name in SCRIPT_ORDER:
        script_path = script_dir / script_name
        if not script_path.is_file():
            raise FileNotFoundError(f"Missing benchmark paper script: {script_path}")

        print(f"[run_all_paper_bench] Running {script_name}...")
        subprocess.run(
            [sys.executable, str(script_path)],
            check=True,
            cwd=repo_dir,
        )

    print("[run_all_paper_bench] All benchmark paper scripts completed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
