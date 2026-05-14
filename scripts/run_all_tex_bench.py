#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import subprocess
import sys


def repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parent.parent


def python_path() -> pathlib.Path:
    venv_python = repo_root() / ".venv" / "bin" / "python"
    if venv_python.exists():
        return venv_python
    return pathlib.Path(sys.executable)


def run_script(script_name: str) -> None:
    script_path = repo_root() / "scripts" / script_name
    print(f"Running {script_name}...")
    subprocess.run(
        [str(python_path()), str(script_path)],
        cwd=repo_root(),
        check=True,
    )


def main() -> int:
    bench_scripts = [
        "paper_bench1_raster.py",
        "paper_bench2_geom.py",
        "paper_bench3_ablation.py",
    ]

    print("Running paper benchmark scripts...")
    for script_name in bench_scripts:
        run_script(script_name)

    print("Completed all paper benchmark scripts.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
