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
import json
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

from riley._zig_toolchain import (
    REQUIRED_ZIG_VERSION,
    ZigUnavailableError,
    get_windows_target_triple,
    select_zig_runner,
)

PROJECT_ROOT = Path.cwd()
PYTHON_EXE = Path(sys.executable)
EXACT_8BIT_COMPARE = True
FLOAT_FALLBACK_ABS_TOL = 0.5

STANDARD_DEMO_CASES = (
    (
        "quickstart",
        [str(PYTHON_EXE), "-m", "riley", "demo00_quickstart"],
        "out/demo00_quickstart",
        "out_riley_py/demo00_quickstart",
        None,
    ),
    (
        "procedural_quickstart",
        [str(PYTHON_EXE), "-m", "riley", "demo00b_procedural_quickstart"],
        "out/demo00b_procedural_quickstart",
        "out_riley_py/demo00b_procedural_quickstart",
        None,
    ),
    (
        "sphere",
        [str(PYTHON_EXE), "-m", "riley", "demo01_sphere"],
        "out/demo01_sphere",
        "out_riley_py/demo01_sphere",
        None,
    ),
    (
        "procedural_sphere",
        [str(PYTHON_EXE), "-m", "riley", "demo01b_procedural_sphere"],
        "out/demo01b_procedural_sphere",
        "out_riley_py/demo01b_procedural_sphere",
        None,
    ),
    (
        "rabbits_mono",
        [str(PYTHON_EXE), "-m", "riley", "demo02a_rabbits_mono"],
        "out/demo02a_rabbits_mono",
        "out_riley_py/demo02a_rabbits_mono",
        None,
    ),
    (
        "rabbits_rgb",
        [str(PYTHON_EXE), "-m", "riley", "demo02b_rabbits_rgb"],
        "out/demo02b_rabbits_rgb",
        "out_riley_py/demo02b_rabbits_rgb",
        None,
    ),
    (
        "rabbits_fields",
        [str(PYTHON_EXE), "-m", "riley", "demo02c_rabbits_fields"],
        "out/demo02c_rabbits_fields",
        "out_riley_py/demo02c_rabbits_fields",
        None,
    ),
    (
        "rabbit_procedural",
        [str(PYTHON_EXE), "-m", "riley", "demo02d_rabbit_procedural"],
        "out/demo02d_rabbit_procedural",
        "out_riley_py/demo02d_rabbit_procedural",
        None,
    ),
    (
        "dicuq",
        [str(PYTHON_EXE), "-m", "riley", "demo03_dicuq"],
        "out/demo03_dicuq",
        "out_riley_py/demo03_dicuq",
        2,
    ),
    (
        "stereocal",
        [str(PYTHON_EXE), "-m", "riley", "demo04_stereocal"],
        "out/demo04_stereocal",
        "out_riley_py/demo04_stereocal",
        8,
    ),
    (
        "cameramodels",
        [str(PYTHON_EXE), "-m", "riley", "demo05_cameramodels"],
        "out/demo05_cameramodels",
        "out_riley_py/demo05_cameramodels",
        None,
    ),
    (
        "feature_zoo",
        [str(PYTHON_EXE), "-m", "riley", "demo06_featurezoo"],
        "out/demo06_featurezoo",
        "out_riley_py/demo06_featurezoo",
        None,
    ),
    (
        "shaderpipe_quickstart",
        [str(PYTHON_EXE), "-m", "riley", "demo07_shaderpipe_quickstart"],
        "out/demo07_shaderpipe_quickstart",
        "out_riley_py/demo07_shaderpipe_quickstart",
        None,
    ),
    (
        "shaderpipe_gallery",
        [str(PYTHON_EXE), "-m", "riley", "demo08_shaderpipe_gallery"],
        "out/demo08_shaderpipe_gallery",
        "out_riley_py/demo08_shaderpipe_gallery",
        None,
    ),
    (
        "diciruq",
        [str(PYTHON_EXE), "-m", "riley", "demo09_diciruq"],
        "out/demo09_diciruq",
        "out_riley_py/demo09_diciruq",
        None,
    ),
    (
        "sphere_lit",
        [str(PYTHON_EXE), "-m", "riley", "demo10_sphere_lit"],
        "out/demo10_sphere_lit",
        "out_riley_py/demo10_sphere_lit",
        None,
    ),
)

EXODUS_DEMO_CASE = (
    "dic_from_exodus",
    [str(PYTHON_EXE), "-m", "riley", "demo03_dicuq_from_exodus"],
    "out/demo03_dicuq",
    "out_riley_py/demo03_dicuq_from_exodus",
    2,
)

CALIBRATION_DEMO_CASE = (
    "stereocal",
    [str(PYTHON_EXE), "-m", "riley", "demo04_stereocal"],
    "out_riley_py/demo04_stereocal",
    8,
)

ALL_DEMO_CASES = (*STANDARD_DEMO_CASES, EXODUS_DEMO_CASE)
DEMO_CASES = ALL_DEMO_CASES

_PROCEDURAL_DEMO_RENDERS = {
    "demo00b_procedural_quickstart": {Path("disk.bmp")},
    "demo01b_procedural_sphere": {
        Path(f"cam0_frame{frame}_field0.bmp") for frame in range(3)
    },
    "demo02d_rabbit_procedural": {Path("cam0_frame0_field0.bmp")},
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


def _get_zig_run_cmd(zig_runner: list[str], *targets: str) -> list[str]:
    cmd = [
        *zig_runner, "build", *(targets or ("run-all-demos",)),
        "-Doptimize=ReleaseFast", "-Dprecision=f64", "-Dsimd=on",
    ]
    if platform.system().lower() == "windows":
        cmd.append(f"-Dtarget={get_windows_target_triple()}")
    return cmd


def _render_paths(dir_path: Path) -> list[Path]:
    return sorted(
        path
        for path in dir_path.rglob("*")
        if path.suffix.lower() in (".bmp", ".tif", ".tiff") and path.is_file()
    )


def _has_renders(dir_path: Path) -> bool:
    return dir_path.is_dir() and bool(_render_paths(dir_path))


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
    expected = set()
    for distort in distorts:
        for psf in psfs:
            for mode in modes:
                rel = Path(distort) / psf / mode / "cam0_frame0_field0.bmp"
                expected.add(rel)
    actual = {path.relative_to(dir_path) for path in _render_paths(dir_path)}
    return actual == expected


def _has_expected_demo_renders(
    dir_path: Path,
    frames_num: int | None,
) -> bool:
    if dir_path.name == "demo05_cameramodels":
        return _has_cameramodel_renders(dir_path)
    expected = _PROCEDURAL_DEMO_RENDERS.get(dir_path.name)
    if expected is None:
        if frames_num is None:
            return _has_renders(dir_path)
        expected = {
            Path(f"cam{camera}_frame{frame}_field0.bmp")
            for camera in range(2)
            for frame in range(frames_num)
        }
    actual = (
        {path.relative_to(dir_path) for path in _render_paths(dir_path)}
        if dir_path.is_dir()
        else set()
    )
    return actual == expected


def _run_command(label: str, cmd: list[str], env: dict[str, str]) -> float:
    print(f"Running {label}: {' '.join(cmd)}")
    start_time = perf_counter()
    res = subprocess.run(
        cmd,
        check=False,
        cwd=PROJECT_ROOT,
        env=env,
        capture_output=True,
        text=True,
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


def _compare_renders(path_a: Path, path_b: Path, *, require_contrast: bool = False) -> None:
    arr_a_raw = np.asarray(Image.open(path_a))
    arr_b_raw = np.asarray(Image.open(path_b))
    if require_contrast:
        for path, image in ((path_a, arr_a_raw), (path_b, arr_b_raw)):
            assert int(image.max()) - int(image.min()) >= 32, (
                f"procedural render lacks contrast: {path}"
            )
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
    files_a = sorted(
        path_a.relative_to(dir_a) for path_a in _render_paths(dir_a)
    )
    files_b = sorted(
        path_b.relative_to(dir_b) for path_b in _render_paths(dir_b)
    )
    expected = _PROCEDURAL_DEMO_RENDERS.get(dir_a.name)
    if expected is not None:
        for label, directory, files in (("zig", dir_a, files_a), ("python", dir_b, files_b)):
            actual = set(files)
            assert actual == expected, (
                f"unexpected {label} procedural render names in {directory}: "
                f"missing={sorted(expected - actual)}, extra={sorted(actual - expected)}"
            )
    if files_a != files_b:
        raise AssertionError(
            f"output file mismatch: zig={files_a}, python={files_b}"
        )

    print(f"Comparing renders in {dir_a} against {dir_b}...")
    start_time = perf_counter()
    for rel_path in files_a:
        _compare_renders(dir_a / rel_path, dir_b / rel_path, require_contrast=expected is not None)
    elapsed_time = perf_counter() - start_time
    print(f"Compare completed in {elapsed_time:.3f}s.")


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


@pytest.fixture(scope="session", autouse=True)
def ensure_repo_context() -> None:
    if not _repo_assets_available():
        pytest.skip(
            "Riley repo assets are not available from the current working "
            "directory. Repo parity demos are skipped.",
            allow_module_level=True,
        )


def _compute_zig_demo_sources_sha(full_cmd: list[str]) -> str:
    hasher = hashlib.sha256(f"zig version: {REQUIRED_ZIG_VERSION}\n".encode("utf-8"))
    hasher.update(json.dumps(full_cmd).encode("utf-8") + b"\n")
    paths = [
        path for name in ("build.zig", "build.zig.zon")
        if (path := PROJECT_ROOT / name).is_file()
    ]
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
        return
    try:
        zig_runner = select_zig_runner()
    except ZigUnavailableError as exc:
        pytest.skip(f"Cannot render Zig demos for parity: {exc}")
    _refresh_zig_demo_renders(zig_runner)


def _refresh_zig_demo_renders(zig_runner: list[str]) -> None:
    silent_env = dict(os.environ)
    silent_env["RILEY_DEMO_SILENT"] = "1"

    stamp_path = PROJECT_ROOT / "out" / ".zig_demos.sha256"
    full_cmd = _get_zig_run_cmd(zig_runner)
    current_sha = _compute_zig_demo_sources_sha(full_cmd)
    cached_sha = ""
    if stamp_path.is_file():
        try:
            cached_sha = stamp_path.read_text(encoding="utf-8").strip()
        except OSError:
            cached_sha = ""
    hash_mismatch = cached_sha != current_sha

    force_zig_render = os.environ.get("RILEY_FORCE_ZIG_RENDER", "0") == "1"

    procedural_dirs = tuple(
        PROJECT_ROOT / "out" / name for name in _PROCEDURAL_DEMO_RENDERS
    )
    needs_full_render = (
        force_zig_render
        or hash_mismatch
        or any(
            not _has_expected_demo_renders(PROJECT_ROOT / zig_dir, frames_num)
            for _, _, zig_dir, _, frames_num in DEMO_CASES
            if Path(zig_dir).name not in _PROCEDURAL_DEMO_RENDERS
        )
    )
    if not needs_full_render:
        invalid = [
            path for path in procedural_dirs if not _has_expected_demo_renders(path, None)
        ]
        if invalid:
            for path in invalid:
                shutil.rmtree(path, ignore_errors=True)
            targets = [path.name.replace("_", "-") for path in invalid]
            _run_command(
                "zig procedural demo render", _get_zig_run_cmd(zig_runner, *targets), silent_env,
            )
        else:
            print("Reusing cached Zig demo renders.")
        return

    if hash_mismatch and not force_zig_render:
        print(
            f"Zig demo cache signature changed (cached={cached_sha[:8]}, "
            f"current={current_sha[:8]}); re-rendering Zig demos."
        )
    stamp_path.unlink(missing_ok=True)
    for _, _, zig_dir, _, _ in DEMO_CASES:
        shutil.rmtree(PROJECT_ROOT / zig_dir, ignore_errors=True)
    _run_command("zig demo render", full_cmd, silent_env)
    invalid = [
        path.name for path in procedural_dirs if not _has_expected_demo_renders(path, None)
    ]
    if invalid:
        # The affected comparisons will report the missing/extra names.
        print(f"Not stamping Zig cache: invalid procedural renders for {', '.join(invalid)}.")
        return
    stamp_path.parent.mkdir(parents=True, exist_ok=True)
    stamp_path.write_text(f"{current_sha}\n", encoding="utf-8")


def _run_demo_case(
    case_name: str,
    python_cmd: list[str],
    zig_dir: str,
    py_dir: str,
) -> None:
    silent_env = dict(os.environ)
    silent_env["RILEY_DEMO_SILENT"] = "1"

    py_dir_path = PROJECT_ROOT / py_dir
    shutil.rmtree(py_dir_path, ignore_errors=True)

    print(f"Testing demo case: {case_name}")
    _run_command(f"python render {case_name}", python_cmd, silent_env)
    _compare_render_dirs(PROJECT_ROOT / zig_dir, py_dir_path)
    if case_name in ("rabbits_mono", "rabbits_rgb", "rabbits_fields"):
        _verify_rabbit_coverage(PROJECT_ROOT / zig_dir)
        _verify_rabbit_coverage(py_dir_path)
    if case_name == "cameramodels":
        assert _has_cameramodel_renders(PROJECT_ROOT / zig_dir)
        assert _has_cameramodel_renders(py_dir_path)
    if case_name == "shaderpipe_gallery":
        for directory in (PROJECT_ROOT / zig_dir, py_dir_path):
            rgb = _render_paths(directory / "e_rgb_expression")
            assert len(rgb) == 1
            assert np.asarray(Image.open(rgb[0])).shape == (512, 512, 3)
            fields = _render_paths(directory / "f_multifield_expression")
            assert {path.name for path in fields} == {
                f"cam0_frame0_field{ii}.tiff" for ii in range(4)
            }
    if case_name == "feature_zoo":
        _verify_feature_zoo_coverage(PROJECT_ROOT / zig_dir)
        _verify_feature_zoo_coverage(py_dir_path)


@pytest.mark.usefixtures("ensure_zig_demo_renders")
@pytest.mark.parametrize(
    ("case_name", "python_cmd", "zig_dir", "py_dir", "frames_num"),
    STANDARD_DEMO_CASES,
    ids=[case[0] for case in STANDARD_DEMO_CASES],
)
def test_demo_parity(
    case_name: str,
    python_cmd: list[str],
    zig_dir: str,
    py_dir: str,
    frames_num: int | None,
) -> None:
    del frames_num
    _run_demo_case(case_name, python_cmd, zig_dir, py_dir)


@pytest.mark.usefixtures("ensure_zig_demo_renders")
@pytest.mark.skipif(
    find_spec("netCDF4") is None,
    reason="netCDF4 is required for the exodus Python demo parity test.",
)
def test_demo03_dicuq_from_exodus_parity() -> None:
    case_name, python_cmd, zig_dir, py_dir, _ = EXODUS_DEMO_CASE
    _run_demo_case(case_name, python_cmd, zig_dir, py_dir)


def test_demo04_stereocal_motion() -> None:
    """The Python calibration helper drives the stereocal demonstration."""
    case_name, python_cmd, py_dir, frames_num = CALIBRATION_DEMO_CASE
    silent_env = dict(os.environ)
    silent_env["RILEY_DEMO_SILENT"] = "1"
    py_dir_path = PROJECT_ROOT / py_dir
    shutil.rmtree(py_dir_path, ignore_errors=True)

    _run_command(f"python render {case_name}", python_cmd, silent_env)
    assert _has_expected_demo_renders(py_dir_path, frames_num)
