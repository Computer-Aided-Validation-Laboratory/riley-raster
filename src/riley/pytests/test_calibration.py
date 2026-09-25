# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from __future__ import annotations

import numpy as np
import pytest

import riley


def _coords() -> np.ndarray:
    return np.array(((0.0, 0.0, 0.0), (1.0, 0.0, 0.0)), dtype=np.float64)


def _camera() -> riley.Camera:
    return riley.Camera(
        pixels_num=(100, 100),
        pixels_size=(1.0e-3, 1.0e-3),
        pos_world=(0.0, 0.0, 1.0),
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=(0.0, 0.0, 0.0),
        focal_length=0.05,
        sub_sample=1,
    )


def test_limits_create_reference_and_translation_fields() -> None:
    disp_x, disp_y, disp_z = riley.caltarget_motion_from_limits(
        _coords(),
        3,
        limits=riley.CalTargetMotionLimits(
            translation=((1.0, 1.0), (0.0, 0.0), (0.0, 0.0)),
        ),
        sampling=riley.ECalTargetMotionSampling.RANDOM,
    )

    assert disp_x.shape == (2, 3)
    assert disp_x.flags.c_contiguous
    np.testing.assert_array_equal(disp_x[:, 0], 0.0)
    np.testing.assert_array_equal(disp_x[:, 1:], 1.0)
    np.testing.assert_array_equal(disp_y, 0.0)
    np.testing.assert_array_equal(disp_z, 0.0)


def test_limits_apply_rotation_about_explicit_center() -> None:
    disp_x, disp_y, disp_z = riley.caltarget_motion_from_limits(
        np.array(((1.0, 0.0, 0.0),), dtype=np.float64),
        1,
        limits=riley.CalTargetMotionLimits(
            rotation_deg=((0.0, 0.0), (0.0, 0.0), (90.0, 90.0)),
        ),
        sampling=riley.ECalTargetMotionSampling.RANDOM,
        include_reference_frame=False,
        rotation_center=(0.0, 0.0, 0.0),
    )

    np.testing.assert_allclose(disp_x, ((-1.0,),), atol=1.0e-14)
    np.testing.assert_allclose(disp_y, ((1.0,),), atol=1.0e-14)
    np.testing.assert_allclose(disp_z, ((0.0,),), atol=1.0e-14)


def test_fixed_limits_keep_axes_stationary() -> None:
    disp_x, disp_y, disp_z = riley.caltarget_motion_from_limits(
        _coords(),
        8,
        limits=riley.CalTargetMotionLimits(
            translation=((0.0, 0.0), (-2.0, 2.0), (0.0, 0.0)),
            rotation_deg=(0.0, 0.0),
        ),
        sampling=riley.ECalTargetMotionSampling.HYPERCUBE,
        rng=np.random.default_rng(42),
    )

    np.testing.assert_array_equal(disp_x, 0.0)
    np.testing.assert_array_equal(disp_z, 0.0)
    assert np.all(np.abs(disp_y[:, 1:]) <= 2.0)


@pytest.mark.parametrize(
    "sampling",
    (
        riley.ECalTargetMotionSampling.RANDOM,
        riley.ECalTargetMotionSampling.STRATIFIED,
        riley.ECalTargetMotionSampling.HYPERCUBE,
    ),
)
def test_sampling_stays_within_limits(
    sampling: riley.ECalTargetMotionSampling,
) -> None:
    disp_x, _, _ = riley.caltarget_motion_from_limits(
        np.array(((0.0, 0.0, 0.0),), dtype=np.float64),
        16,
        limits=riley.CalTargetMotionLimits(
            translation=((2.0, 4.0), (0.0, 0.0), (0.0, 0.0)),
        ),
        sampling=sampling,
        include_reference_frame=False,
        rng=np.random.default_rng(5),
    )

    assert np.all(disp_x >= 2.0)
    assert np.all(disp_x <= 4.0)


def test_cartesian_sampling_returns_complete_grid() -> None:
    disp_x, disp_y, _ = riley.caltarget_motion_from_limits(
        np.array(((0.0, 0.0, 0.0),), dtype=np.float64),
        1,
        limits=riley.CalTargetMotionLimits(
            translation=((1.0, 2.0), (3.0, 4.0), (0.0, 0.0)),
        ),
        sampling=riley.ECalTargetMotionSampling.CARTESIAN,
        include_reference_frame=False,
        cartesian_levels=(2, 3),
    )

    assert disp_x.shape == (1, 6)
    assert set(zip(disp_x[0], disp_y[0], strict=True)) == {
        (1.0, 3.0), (1.0, 3.5), (1.0, 4.0),
        (2.0, 3.0), (2.0, 3.5), (2.0, 4.0),
    }


@pytest.mark.parametrize(
    "sampling",
    (
        riley.ECalTargetMotionSampling.RANDOM,
        riley.ECalTargetMotionSampling.STRATIFIED,
        riley.ECalTargetMotionSampling.HYPERCUBE,
    ),
)
def test_seed_reproducibly_controls_sampling(
    sampling: riley.ECalTargetMotionSampling,
) -> None:
    limits = riley.CalTargetMotionLimits(translation=(-1.0, 1.0))
    first = riley.caltarget_motion_from_limits(
        _coords(),
        4,
        limits=limits,
        sampling=sampling,
        seed=42,
    )
    second = riley.caltarget_motion_from_limits(
        _coords(),
        4,
        limits=limits,
        sampling=sampling,
        seed=42,
    )

    for first_component, second_component in zip(first, second, strict=True):
        np.testing.assert_array_equal(first_component, second_component)


def test_seed_and_rng_are_mutually_exclusive() -> None:
    with pytest.raises(ValueError, match="mutually exclusive"):
        riley.caltarget_motion_from_limits(
            _coords(),
            2,
            limits=riley.CalTargetMotionLimits(),
            sampling=riley.ECalTargetMotionSampling.RANDOM,
            seed=1,
            rng=np.random.default_rng(1),
        )


def test_fov_motion_keeps_all_nodes_inside_requested_fraction() -> None:
    coords = np.array(((-0.1, -0.1, 0.0), (0.1, 0.1, 0.0)), dtype=np.float64)
    disp = riley.caltarget_motion_from_fov(
        coords,
        _camera(),
        6,
        limits=riley.CalTargetMotionLimits(
            translation=((-0.1, 0.1), (-0.1, 0.1), (0.0, 0.0)),
        ),
        fov_fraction=0.8,
        sampling=riley.ECalTargetMotionSampling.HYPERCUBE,
        rng=np.random.default_rng(7),
    )

    assert all(component.shape == (2, 6) for component in disp)
    for frame_idx in range(6):
        deformed = coords + np.column_stack(
            tuple(component[:, frame_idx] for component in disp),
        )
        pixels = 50.0 + 50.0 * deformed[:, :2]
        assert np.all(pixels >= 10.0)
        assert np.all(pixels <= 90.0)


def test_fov_rejects_reference_target_outside_fraction() -> None:
    coords = np.array(((0.81, 0.0, 0.0),), dtype=np.float64)
    with pytest.raises(ValueError, match="cannot provide"):
        riley.caltarget_motion_from_fov(
            coords,
            _camera(),
            1,
            limits=riley.CalTargetMotionLimits(),
            fov_fraction=0.8,
            sampling=riley.ECalTargetMotionSampling.RANDOM,
        )


@pytest.mark.parametrize(
    "limits",
    (
        riley.CalTargetMotionLimits(translation=(1.0, -1.0)),
        riley.CalTargetMotionLimits(rotation_deg=((0.0, 1.0),)),
    ),
)
def test_limits_reject_invalid_ranges(limits: riley.CalTargetMotionLimits) -> None:
    with pytest.raises(ValueError):
        riley.caltarget_motion_from_limits(
            _coords(),
            1,
            limits=limits,
            sampling=riley.ECalTargetMotionSampling.RANDOM,
        )
