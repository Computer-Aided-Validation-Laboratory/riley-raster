# --------------------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
# --------------------------------------------------------------------------------------
from __future__ import annotations

import hashlib
import os
import platform
import shutil
import subprocess
import sys
from importlib.util import find_spec
from pathlib import Path
from time import perf_counter

import numpy as np
import pytest
from PIL import Image

from riley.pydemos import __all__ as DEMO_NAMES

PROJECT_ROOT = Path.cwd()
EXACT_8BIT_COMPARE = True
FLOAT_FALLBACK_ABS_TOL = 0.5

# The Exodus tutorial uses demo3_dicuq as its Zig reference.
EXODUS_DEMO = "demo3_dicuq_from_exodus"
STANDARD_DEMOS = tuple(demo for demo in DEMO_NAMES if demo != EXODUS_DEMO)

PROCEDURAL_DEMOS = (
    "demo0b_procedural_quickstart",
    "demo1b_procedural_sphere",
    "demo2d_rabbit_procedural",
)

# Exact default render matrices, as (cameras, frames).
RENDER_COUNTS = {
    "demo1b_procedural_sphere": (1, 3),
    "demo2d_rabbit_procedural": (1, 1),
    "demo3_dicuq": (2, 2),
    "demo4_stereocal": (2, 8),
}


def test_raster_config_exposes_global_subpixel_sizing() -> None:
    """Python callers can tune both global accumulation tile dimensions."""
    import riley

    config = riley.RasterConfig()
    assert config.global_subpx_tile_size_min == 64
    assert config.global_subpx_tile_size_max == 1024
    assert config.global_subpx_tile_size_override == 0
    assert config.global_subpx_stripe_size_min == 256
    assert config.global_subpx_stripe_size_max == 4096
    assert config.global_subpx_stripe_size_override == 0

    config.global_subpx_tile_size_override = 128
    config.global_subpx_stripe_size_override = 512
    assert config.global_subpx_tile_size_override == 128
    assert config.global_subpx_stripe_size_override == 512


def _repo_assets_available() -> bool:
    required_paths = (
        PROJECT_ROOT / "src" / "run_all_demos.zig",
        PROJECT_ROOT / "data",
        PROJECT_ROOT / "texture",
    )
    return all(path.exists() for path in required_paths)


def _has_zig_compiler() -> bool:
    if shutil.which("zig") or shutil.which("zig.exe"):
        return True
    return find_spec("ziglang") is not None


def _get_zig_run_cmd() -> list[str]:
    zig_bin = shutil.which("zig") or shutil.which("zig.exe")
    base_cmd = [zig_bin] if zig_bin else [sys.executable, "-m", "ziglang"]
    cmd = list(base_cmd)
    cmd.extend(["run", "-lc", "-O", "ReleaseFast"])
    if platform.system().lower() == "windows":
        arch = platform.machine().lower()
        if arch in ("amd64", "x86_64"):
            target_triple = "x86_64-windows-msvc"
        elif arch in ("arm64", "aarch64"):
            target_triple = "aarch64-windows-msvc"
        else:
            target_triple = "x86-windows-msvc"
        cmd.extend(["-target", target_triple])
    cmd.append(str(PROJECT_ROOT / "src" / "run_all_demos.zig"))
    return cmd


def _render_paths(dir_path: Path) -> list[Path]:
    return sorted(
        path
        for path in dir_path.rglob("*")
        if path.suffix.lower() in (".bmp", ".tif", ".tiff") and path.is_file()
    )



def _has_cameramodel_renders(dir_path: Path) -> bool:
    """Require full distortion/PSF/buffer matrix, not a partial render."""
    distorts = (
        "none",
        "brown_conrady",
        "brown_conrady_ext",
        "polynomial",
        "brown_conrady_polynomial",
        "brown_conrady_ext_polynomial",
    )
    psfs = (
        "pixel_box",
        "gaussian_separable",
        "gaussian_nonseparable",
        "anisotropic_separable",
        "anisotropic_rotated",
    )
    modes = ("tile_local", "global_subpx_full", "global_subpx_stripe")
    expected = {
        Path(distort) / psf / mode / "cam0_frame0_field0.bmp"
        for distort in distorts for psf in psfs for mode in modes
    }
    actual = {path.relative_to(dir_path) for path in _render_paths(dir_path)}
    return actual == expected


def _has_expected_demo_renders(dir_path: Path) -> bool:
    if dir_path.name == "demo5_cameramodels":
        return _has_cameramodel_renders(dir_path)

    actual = {path.relative_to(dir_path) for path in _render_paths(dir_path)}
    if dir_path.name == "demo0b_procedural_quickstart":
        return actual == {Path("disk.bmp")}
    if dir_path.name not in RENDER_COUNTS:
        return bool(actual)
    cameras, frames = RENDER_COUNTS[dir_path.name]
    return actual == {
        Path(f"cam{camera}_frame{frame}_field0.bmp")
        for camera in range(cameras) for frame in range(frames)
    }


def _run_command(label: str, cmd: list[str], env: dict[str, str]) -> float:
    print(f"Running {label}: {' '.join(cmd)}")
    start_time = perf_counter()
    res = subprocess.run(
        cmd,
        check=False,
        cwd=PROJECT_ROOT,
        env=dict(env, PYTHONIOENCODING="utf-8"),
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if res.returncode != 0:
        print(f"FAILED {label} (exit code {res.returncode}):")
        if res.stdout:
            print(f"--- stdout ---\n{res.stdout}")
        if res.stderr:
            print(f"--- stderr ---\n{res.stderr}")
        res.check_returncode()
    elapsed_time = perf_counter() - start_time
    print(f"{label} completed in {elapsed_time:.3f}s.")
    return elapsed_time


def _compare_renders(path_a: Path, path_b: Path) -> None:
    arr_a_raw = np.asarray(Image.open(path_a))
    arr_b_raw = np.asarray(Image.open(path_b))
    if arr_a_raw.shape != arr_b_raw.shape:
        raise AssertionError(
            f"shape mismatch for {path_a.name}: "
            f"zig={arr_a_raw.shape} python={arr_b_raw.shape}",
        )

    if (
        EXACT_8BIT_COMPARE
        and arr_a_raw.dtype == np.uint8
        and arr_b_raw.dtype == np.uint8
    ):
        if not np.array_equal(arr_a_raw, arr_b_raw):
            diff = np.abs(
                arr_a_raw.astype(np.int16) - arr_b_raw.astype(np.int16)
            )
            raise AssertionError(
                f"render mismatch for {path_a.name}: "
                f"max_abs_diff={int(np.max(diff))}, "
                f"diff_px={int(np.count_nonzero(diff))}",
            )
        return

    arr_a = arr_a_raw.astype(np.float32, copy=False)
    arr_b = arr_b_raw.astype(np.float32, copy=False)
    max_diff = float(np.max(np.abs(arr_a - arr_b)))
    if max_diff > FLOAT_FALLBACK_ABS_TOL:
        raise AssertionError(
            f"render mismatch for {path_a.name}: "
            f"max_abs_diff={max_diff:.4f} > tol={FLOAT_FALLBACK_ABS_TOL:.4f}",
        )


def _compare_render_dirs(dir_a: Path, dir_b: Path) -> None:
    files_a = [path.relative_to(dir_a) for path in _render_paths(dir_a)]
    files_b = [path.relative_to(dir_b) for path in _render_paths(dir_b)]
    if files_a != files_b:
        raise AssertionError(
            f"output file mismatch: zig={files_a}, python={files_b}"
        )

    print(f"Comparing renders in {dir_a} against {dir_b}...")
    start_time = perf_counter()
    for rel_path in files_a:
        _compare_renders(dir_a / rel_path, dir_b / rel_path)
    elapsed_time = perf_counter() - start_time
    print(f"Compare completed in {elapsed_time:.3f}s.")


def _verify_procedural_pattern(dir_path: Path) -> None:
    for image_path in _render_paths(dir_path):
        with Image.open(image_path) as image:
            pixels = np.asarray(image.convert("L"))
        height, width = pixels.shape
        # The central quarter is on the mesh, where both disk tones should appear.
        # The exterior shares a tone with the pattern (black rabbit, white sphere).
        interior = pixels[3 * height // 8:5 * height // 8, 3 * width // 8:5 * width // 8]
        dark = np.mean(interior <= 32)
        bright = np.mean(interior >= 223)
        assert dark > 0.10 and bright > 0.10, (
            f"procedural pattern in {image_path}: interior is {dark:.2%} dark and "
            f"{bright:.2%} bright; expected more than 10% of each"
        )


def _verify_rabbit_coverage(dir_path: Path) -> None:
    images = _render_paths(dir_path)
    assert images, f"no rabbit renders in {dir_path}"
    for image_path in images:
        image = np.asarray(Image.open(image_path))
        foreground = (
            np.any(image != 128, axis=2) if image.ndim == 3 else image != 128
        )
        coverage = np.count_nonzero(foreground) / foreground.size
        assert coverage > 0.10, (
            f"rabbit foreground coverage for {image_path} is "
            f"{coverage:.2%}; expected more than 10%"
        )


def _verify_feature_zoo_coverage(dir_path: Path) -> None:
    for image_path in _render_paths(dir_path):
        image = np.asarray(Image.open(image_path))
        background = 128 if image.dtype == np.uint8 else 32768
        if image.ndim == 3:
            foreground = np.any(image != background, axis=2)
        else:
            foreground = image != background
        coverage = np.count_nonzero(foreground) / foreground.size
        assert coverage > 0.25, (
            f"feature-zoo foreground coverage for {image_path} is "
            f"{coverage:.2%}; expected more than 25%"
        )
        assert not np.any(foreground[0])
        assert not np.any(foreground[-1])
        assert not np.any(foreground[:, 0])
        assert not np.any(foreground[:, -1])



def _compute_zig_demo_sources_sha(cmd: list[str]) -> str:
    hasher = hashlib.sha256()
    for arg in cmd:
        hasher.update(arg.encode("utf-8") + b"\0")

    # Include all native demo sources (including shared helpers) and mesh/texture inputs.
    paths: list[Path] = []
    src_dir = PROJECT_ROOT / "src"
    if src_dir.is_dir():
        paths.extend(src_dir.rglob("*.zig"))
    for dir_name in ("data", "texture"):
        asset_dir = PROJECT_ROOT / dir_name
        if asset_dir.is_dir():
            paths.extend(f for f in asset_dir.rglob("*") if f.is_file())
    paths.sort()
    for path in paths:
        rel_str = str(path.relative_to(PROJECT_ROOT).as_posix())
        hasher.update(rel_str.encode("utf-8"))
        hasher.update(path.read_bytes())
    return hasher.hexdigest()


@pytest.fixture(scope="session")
def ensure_zig_demo_renders() -> None:
    if not _repo_assets_available():
        pytest.skip("Riley repo assets are not available from the current directory.")
    if not _has_zig_compiler():
        pytest.skip("Zig compiler is not available to render Zig demos for comparison.")

    silent_env = dict(os.environ)
    silent_env["RILEY_DEMO_SILENT"] = "1"

    stamp_path = PROJECT_ROOT / "out" / ".zig_demos.sha256"
    zig_cmd = _get_zig_run_cmd()
    current_sha = _compute_zig_demo_sources_sha(zig_cmd)
    try:
        cached_sha = stamp_path.read_text(encoding="utf-8").strip()
    except OSError:
        cached_sha = ""

    zig_dirs = [PROJECT_ROOT / "out" / demo for demo in STANDARD_DEMOS]
    if (
        os.environ.get("RILEY_FORCE_ZIG_RENDER") != "1"
        and cached_sha == current_sha
        and all(_has_expected_demo_renders(path) for path in zig_dirs)
    ):
        print("Reusing cached Zig demo renders.")
        return

    stamp_path.unlink(missing_ok=True)
    for path in zig_dirs:
        shutil.rmtree(path, ignore_errors=True)
    _run_command("zig demo render", zig_cmd, silent_env)
    # Leave incomplete results unstamped; each parity case checks its own directory.
    if all(_has_expected_demo_renders(path) for path in zig_dirs):
        stamp_path.write_text(f"{current_sha}\n", encoding="utf-8")


def _run_demo_case(demo: str, zig_demo: str) -> None:
    zig_dir = PROJECT_ROOT / "out" / zig_demo
    assert _has_expected_demo_renders(zig_dir), f"missing or unexpected Zig renders in {zig_dir}"

    py_dir = PROJECT_ROOT / "out_riley_py" / demo
    shutil.rmtree(py_dir, ignore_errors=True)

    _run_command(
        f"python render {demo}",
        [sys.executable, "-m", "riley", demo],
        dict(os.environ, RILEY_DEMO_SILENT="1"),
    )
    _compare_render_dirs(zig_dir, py_dir)
    if demo in PROCEDURAL_DEMOS:
        _verify_procedural_pattern(zig_dir)

    if demo in ("demo2a_rabbits_mono", "demo2b_rabbits_rgb", "demo2c_rabbits_fields"):
        _verify_rabbit_coverage(zig_dir)
        _verify_rabbit_coverage(py_dir)

    if demo == "demo6_featurezoo":
        _verify_feature_zoo_coverage(zig_dir)
        _verify_feature_zoo_coverage(py_dir)


@pytest.mark.usefixtures("ensure_zig_demo_renders")
@pytest.mark.parametrize("demo", STANDARD_DEMOS)
def test_demo_parity(demo: str) -> None:
    _run_demo_case(demo, demo)


@pytest.mark.usefixtures("ensure_zig_demo_renders")
@pytest.mark.skipif(
    find_spec("netCDF4") is None,
    reason="netCDF4 is required for the exodus Python demo parity test.",
)
def test_demo3_dicuq_from_exodus_parity() -> None:
    _run_demo_case(EXODUS_DEMO, "demo3_dicuq")
