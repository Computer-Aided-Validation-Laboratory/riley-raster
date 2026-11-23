"""Check packaged demo imports and demo parity validation."""

from __future__ import annotations

import importlib
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from riley.__main__ import _DEMO_FUNCS


def test_numbered_demo_cli_modules_are_importable() -> None:
    expected = (
        "demo0_quickstart",
        "demo1_sphere",
        "demo2a_rabbits_mono",
        "demo2b_rabbits_rgb",
        "demo2c_rabbits_fields",
        "demo3_dicuq",
        "demo3_dicuq_from_exodus",
        "demo4_stereocal",
        "demo5_cameramodels",
        "demo6_featurezoo",
    )
    assert tuple(_DEMO_FUNCS) == expected
    for name in expected:
        module = importlib.import_module(_DEMO_FUNCS[name])
        assert callable(module.main)


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
                assert not _has_cameramodel_renders(tmp_path)
                path = tmp_path / distort / psf / mode / "cam0_frame0_field0.bmp"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
    assert _has_cameramodel_renders(tmp_path)


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
