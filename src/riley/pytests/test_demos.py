# --------------------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
# --------------------------------------------------------------------------------------
"""Check packaged demo imports and demo parity validation."""

from __future__ import annotations

import importlib
import pkgutil
import re
import sys
from importlib.resources import files
from pathlib import Path
from unittest.mock import patch

import numpy as np
import pytest
from PIL import Image

from riley import __main__ as cli
from riley import pydemos


def test_numbered_demo_cli_modules_are_importable() -> None:
    names = {
        name for _, name, ispkg in pkgutil.iter_modules(pydemos.__path__)
        if not ispkg and re.match(r"demo[0-9]", name)
    }
    assert names == set(cli.DEMO_NAMES)
    for name in sorted(names):
        module = importlib.import_module(f"riley.pydemos.{name}")
        assert callable(module.main)


@pytest.mark.parametrize(
    ("options", "exit_code"),
    (
        (["-h"], 0),
        (["--help"], 0),
        (["--typo"], 2),
        (["--help", "extra"], 2),
        (["--"], 2),
        (["--", "--help"], 2),
    ),
)
def test_optionless_demo_args_exit_before_import(
    options: list[str], exit_code: int,
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str],
) -> None:
    command = "demo0a_quickstart"
    monkeypatch.setattr(sys, "argv", ["riley", command, *options])
    with (
        patch.object(cli.importlib, "import_module") as import_demo,
        pytest.raises(SystemExit) as exc,
    ):
        cli.main()
    import_demo.assert_not_called()
    assert exc.value.code == exit_code
    output = capsys.readouterr()
    if exit_code == 0:
        assert f"python -m riley {command}" in output.out
        assert "takes no arguments" in output.out
    else:
        assert f"{command} does not accept arguments" in output.err


@pytest.mark.parametrize(
    ("directory", "connect_file"),
    (
        (("min", "tri6_sphere200"), "connect.csv"),
        (("rabbits", "riley_tri6"), "connectivity.csv"),
    ),
)
def test_procedural_demo_mesh_inputs_are_packaged(
    directory: tuple[str, str], connect_file: str,
) -> None:
    data_dir = files("riley.data").joinpath(*directory)
    for name in ("coords.csv", connect_file, "uvs.csv"):
        assert data_dir.joinpath(name).is_file()


def test_procedural_cache_requires_exact_output_membership(tmp_path: Path) -> None:
    from riley.pytests.test_riley import _has_expected_demo_renders

    demo_dir = tmp_path / "demo1b_procedural_sphere"
    demo_dir.mkdir()
    for frame in range(3):
        (demo_dir / f"cam0_frame{frame}_field0.bmp").touch()
    assert _has_expected_demo_renders(demo_dir)

    # Keep the same file count but replace an expected frame with an extra one.
    (demo_dir / "cam0_frame1_field0.bmp").rename(demo_dir / "unexpected.bmp")
    assert not _has_expected_demo_renders(demo_dir)


def test_partial_zig_render_leaves_other_parity_cases_runnable(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    from riley.pytests import test_riley

    complete = "demo0a_quickstart"
    incomplete = "demo1b_procedural_sphere"
    stamp = tmp_path / "out" / ".zig_demos.sha256"
    stamp.parent.mkdir()
    stamp.write_text("current\n", encoding="utf-8")

    def render(label: str, cmd: list[str], env: dict[str, str]) -> float:
        root = "out" if label == "zig demo render" else "out_riley_py"
        path = tmp_path / root / complete / "cam0_frame0_field0.bmp"
        path.parent.mkdir(parents=True)
        Image.new("L", (1, 1), 42).save(path)
        return 0.0

    monkeypatch.setattr(test_riley, "PROJECT_ROOT", tmp_path)
    monkeypatch.setattr(test_riley, "STANDARD_DEMOS", (complete, incomplete))
    monkeypatch.setattr(test_riley, "_repo_assets_available", lambda: True)
    monkeypatch.setattr(test_riley, "_has_zig_compiler", lambda: True)
    monkeypatch.setattr(test_riley, "_compute_zig_demo_sources_sha", lambda cmd: "current")
    monkeypatch.setattr(test_riley, "_run_command", render)

    test_riley.ensure_zig_demo_renders.__wrapped__()
    assert not stamp.exists()
    with pytest.raises(AssertionError, match=f"missing or unexpected Zig renders in .*{incomplete}"):
        test_riley._run_demo_case(incomplete, incomplete)
    test_riley._run_demo_case(complete, complete)


def test_zig_cache_hash_tracks_procedural_sources_and_inputs(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    from riley.pytests import test_riley

    monkeypatch.setattr(test_riley, "PROJECT_ROOT", tmp_path)
    zig_cmd = ["zig", "run", "src/run_all_demos.zig"]
    cached_sha = test_riley._compute_zig_demo_sources_sha(zig_cmd)
    for name in (
        "src/demo0b_procedural_quickstart.zig",
        "src/demo1b_procedural_sphere.zig",
        "src/demo2d_rabbit_procedural.zig",
        "data/min/tri6_sphere200/uvs.csv",
        "data/rabbits/riley_tri6/uvs.csv",
        "texture/speckle_mono.bmp",
    ):
        path = tmp_path / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch()
        added_sha = test_riley._compute_zig_demo_sources_sha(zig_cmd)
        assert added_sha != cached_sha
        path.write_text("modified", encoding="utf-8")
        cached_sha = test_riley._compute_zig_demo_sources_sha(zig_cmd)
        assert cached_sha != added_sha
    assert test_riley._compute_zig_demo_sources_sha([*zig_cmd, "-lc"]) != cached_sha


def test_cameramodel_cache_rejects_partial_matrices(tmp_path: Path) -> None:
    from riley.pytests.test_riley import _has_cameramodel_renders

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
    assert not _has_cameramodel_renders(tmp_path)
    for distort in distorts:
        for psf in psfs:
            for mode in modes:
                path = tmp_path / distort / psf / mode / "cam0_frame0_field0.bmp"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
    assert _has_cameramodel_renders(tmp_path)
    path.unlink()
    assert not _has_cameramodel_renders(tmp_path)


@pytest.mark.parametrize("channels", (1, 3))
def test_rabbit_coverage_rejects_blank_and_nearly_blank_images(
    tmp_path: Path, channels: int
) -> None:
    from riley.pytests.test_riley import _verify_rabbit_coverage

    shape = (20, 20) if channels == 1 else (20, 20, channels)
    image = np.full(shape, 128, dtype=np.uint8)
    image_path = tmp_path / "cam0_frame0_field0.bmp"
    Image.fromarray(image).save(image_path)
    with pytest.raises(AssertionError, match="rabbit foreground coverage"):
        _verify_rabbit_coverage(tmp_path)

    image[0, 0] = 0
    Image.fromarray(image).save(image_path)
    with pytest.raises(AssertionError, match="rabbit foreground coverage"):
        _verify_rabbit_coverage(tmp_path)

    image[5:15, 5:15] = 0
    Image.fromarray(image).save(image_path)
    _verify_rabbit_coverage(tmp_path)


def test_rabbit_coverage_rejects_missing_images(tmp_path: Path) -> None:
    from riley.pytests.test_riley import _verify_rabbit_coverage

    with pytest.raises(AssertionError, match="no rabbit renders"):
        _verify_rabbit_coverage(tmp_path)
