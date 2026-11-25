"""Exercise procedural demos and their packaged data using an installed Riley."""

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image


PROCEDURAL_CASES = {
    "demo00b_procedural_quickstart": (
        ("--width", "128", "--height", "96"),
        (128, 96),
        {"disk.bmp"},
    ),
    "demo01b_procedural_sphere": (
        (),
        (720, 450),
        {f"cam0_frame{frame}_field0.bmp" for frame in range(3)},
    ),
    "demo02d_rabbit_procedural": ((), (800, 500), {"cam0_frame0_field0.bmp"}),
}


def run_procedural_demo(demo: str, work_dir: Path) -> None:
    args, size, expected = PROCEDURAL_CASES[demo]
    output = work_dir / demo
    command = [sys.executable, "-I", "-m", "riley", demo, "--output", str(output), *args]
    subprocess.run(command, cwd=work_dir, check=True, timeout=60)
    images = {
        path.relative_to(output).as_posix(): path
        for path in output.rglob("*")
        if path.is_file() and path.suffix.lower() == ".bmp"
    }
    if images.keys() != expected:
        raise RuntimeError(f"{demo}: expected {sorted(expected)}, got {sorted(images)}")
    for path in images.values():
        with Image.open(path) as image:
            if image.format != "BMP" or image.size != size:
                raise RuntimeError(
                    f"{path}: expected BMP at {size}, got {image.format} at {image.size}"
                )
            low, high = image.convert("L").getextrema()
            if low == high:
                raise RuntimeError(f"{path}: rendered image is uniform ({low})")
    print(f"{demo}: verified {len(images)} rendered BMP(s)", flush=True)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="riley-procedural-smoke-") as tmp:
        for demo in PROCEDURAL_CASES:
            run_procedural_demo(demo, Path(tmp))


if __name__ == "__main__":
    main()
