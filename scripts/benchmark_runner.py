"""Execution and artifact contract shared by native benchmark studies."""
import json
import pathlib
import shlex
import subprocess
import time

from benchmark_catalog import ROOT


def run_command(
    command: list[str], output_dir: pathlib.Path, metadata: dict | None = None,
) -> float:
    output_dir = pathlib.Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "command.txt").write_text(shlex.join(command) + "\n")
    (output_dir / "metadata.json").write_text(
        json.dumps({**(metadata or {}), "command": command}, indent=2) + "\n"
    )
    started = time.perf_counter()
    return_code = None
    try:
        with (
            (output_dir / "stdout.txt").open("w") as stdout,
            (output_dir / "stderr.txt").open("w") as stderr,
        ):
            result = subprocess.run(command, cwd=ROOT, stdout=stdout, stderr=stderr, check=True)
        return_code = result.returncode
    except subprocess.CalledProcessError as error:
        return_code = error.returncode
        raise
    finally:
        seconds = time.perf_counter() - started
        (output_dir / "execution.json").write_text(
            json.dumps({"seconds": seconds, "return_code": return_code}, indent=2) + "\n"
        )
    return seconds
