# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
"""Generate rigid calibration-target displacement fields."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from itertools import product
from typing import TYPE_CHECKING, TypeAlias

import numpy as np
import numpy.typing as npt
from scipy.spatial.transform import Rotation

if TYPE_CHECKING:
    from riley.cython.riley import Camera


MotionRange: TypeAlias = tuple[float, float]
AxisMotionRanges: TypeAlias = tuple[MotionRange, MotionRange, MotionRange]
_NORMALISED_RANGES: TypeAlias = tuple[tuple[float, float], ...]


class ECalTargetMotionSampling(Enum):
    """Sampling strategy for calibration-target rigid motion."""

    RANDOM = "random"
    STRATIFIED = "stratified"
    HYPERCUBE = "hypercube"
    CARTESIAN = "cartesian"


@dataclass(frozen=True, slots=True)
class CalTargetMotionLimits:
    """Rigid calibration-target limits in world units and degrees.

    A single range applies to all three axes. Three ranges apply in XYZ order.
    Rotation values are intrinsic XYZ Euler angles in degrees. Equal endpoints
    fix an axis.
    """

    translation: MotionRange | AxisMotionRanges = (0.0, 0.0)
    rotation_deg: MotionRange | AxisMotionRanges = (0.0, 0.0)


def caltarget_motion_from_limits(
    coords: npt.ArrayLike,
    positions_num: int,
    *,
    limits: CalTargetMotionLimits,
    sampling: ECalTargetMotionSampling,
    include_reference_frame: bool = True,
    rotation_center: npt.ArrayLike | None = None,
    seed: int | None = None,
    rng: np.random.Generator | None = None,
    cartesian_levels: int | tuple[int, ...] | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Create rigid displacement fields from explicit pose limits.

    ``positions_num`` includes a requested reference frame for non-Cartesian
    sampling. ``seed`` reproducibly initialises random sampling and is mutually
    exclusive with ``rng``. Cartesian sampling uses ``cartesian_levels`` levels
    across each free degree of freedom and therefore has a grid-defined frame
    count.
    """
    coords_out = _validate_coords(coords)
    center = _validate_rotation_center(rotation_center, coords_out)
    ranges = _normalise_limits(limits)
    generator = _create_rng(seed, rng)
    poses = _sample_poses(
        positions_num,
        ranges,
        sampling,
        include_reference_frame,
        generator,
        cartesian_levels,
    )
    return _calculate_displacements(coords_out, center, poses)


def caltarget_motion_from_fov(
    coords: npt.ArrayLike,
    camera: Camera,
    positions_num: int,
    *,
    fov_fraction: float,
    limits: CalTargetMotionLimits,
    sampling: ECalTargetMotionSampling,
    include_reference_frame: bool = True,
    rotation_center: npt.ArrayLike | None = None,
    seed: int | None = None,
    rng: np.random.Generator | None = None,
    cartesian_levels: int | tuple[int, ...] | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Create rigid fields whose generated poses fit one camera's FOV.

    Translation limits describe the maximum requested motion. Each sampled
    pose is contracted automatically to remain in the central
    ``fov_fraction`` of the supplied OpenGL-coordinate-system camera sensor.
    The function raises ``ValueError`` only when the undeformed reference
    target cannot fit in that fraction.
    """
    coords_out = _validate_coords(coords)
    center = _validate_rotation_center(rotation_center, coords_out)
    _validate_camera(camera)
    _validate_fov_fraction(fov_fraction)
    ranges = _normalise_limits(limits)
    generator = _create_rng(seed, rng)

    poses = _sample_poses(
        positions_num,
        ranges,
        sampling,
        include_reference_frame,
        generator,
        cartesian_levels,
    )
    poses = _fit_poses_to_fov(
        coords_out,
        center,
        camera,
        fov_fraction,
        poses,
    )
    return _calculate_displacements(coords_out, center, poses)


def _validate_coords(coords: npt.ArrayLike) -> np.ndarray:
    coords_out = np.ascontiguousarray(coords, dtype=np.float64)
    if coords_out.ndim != 2 or coords_out.shape[0] == 0 or coords_out.shape[1] != 3:
        raise ValueError("coords must have shape (nodes, 3) and not be empty.")
    if not np.all(np.isfinite(coords_out)):
        raise ValueError("coords must contain only finite values.")
    return coords_out


def _validate_rotation_center(
    rotation_center: npt.ArrayLike | None,
    coords: np.ndarray,
) -> np.ndarray:
    if rotation_center is None:
        return np.ascontiguousarray(0.5 * (coords.min(axis=0) + coords.max(axis=0)))
    center = np.ascontiguousarray(rotation_center, dtype=np.float64)
    if center.shape != (3,) or not np.all(np.isfinite(center)):
        raise ValueError("rotation_center must have shape (3,) and finite values.")
    return center


def _normalise_limits(limits: CalTargetMotionLimits) -> _NORMALISED_RANGES:
    if not isinstance(limits, CalTargetMotionLimits):
        raise TypeError("limits must be a CalTargetMotionLimits instance.")
    return (*_normalise_axis_ranges(limits.translation, "translation"),
            *_normalise_axis_ranges(limits.rotation_deg, "rotation_deg"))


def _normalise_axis_ranges(
    values: MotionRange | AxisMotionRanges,
    name: str,
) -> AxisMotionRanges:
    array = np.asarray(values, dtype=np.float64)
    if array.shape == (2,):
        array = np.broadcast_to(array, (3, 2))
    if array.shape != (3, 2):
        raise ValueError(f"{name} must be one range or three XYZ ranges.")
    if not np.all(np.isfinite(array)):
        raise ValueError(f"{name} must contain only finite values.")
    if np.any(array[:, 0] > array[:, 1]):
        raise ValueError(f"{name} minimum values must not exceed maximum values.")
    normalised = tuple(
        (float(item[0]), float(item[1]))
        for item in array
    )
    return normalised  # type: ignore[return-value]


def _sample_poses(
    positions_num: int,
    ranges: _NORMALISED_RANGES,
    sampling: ECalTargetMotionSampling,
    include_reference_frame: bool,
    rng: np.random.Generator,
    cartesian_levels: int | tuple[int, ...] | None,
) -> np.ndarray:
    if not isinstance(sampling, ECalTargetMotionSampling):
        raise TypeError("sampling must be an ECalTargetMotionSampling value.")
    if positions_num < 1:
        raise ValueError("positions_num must be positive.")
    free_idxs = tuple(idx for idx, item in enumerate(ranges) if item[0] != item[1])

    if sampling is ECalTargetMotionSampling.CARTESIAN:
        poses = _sample_cartesian_poses(ranges, free_idxs, cartesian_levels)
    else:
        if cartesian_levels is not None:
            raise ValueError("cartesian_levels is only valid for CARTESIAN sampling.")
        generated_num = positions_num - int(include_reference_frame)
        poses = _sample_non_cartesian_poses(
            generated_num,
            ranges,
            free_idxs,
            sampling,
            rng,
        )

    reference = np.zeros((1, 6), dtype=np.float64)
    if include_reference_frame and not np.any(np.all(poses == reference, axis=1)):
        poses = np.vstack((reference, poses))
    return np.ascontiguousarray(poses)


def _create_rng(
    seed: int | None,
    rng: np.random.Generator | None,
) -> np.random.Generator:
    if seed is not None and rng is not None:
        raise ValueError("seed and rng are mutually exclusive.")
    if rng is not None:
        return rng
    return np.random.default_rng(seed)


def _sample_non_cartesian_poses(
    count: int,
    ranges: _NORMALISED_RANGES,
    free_idxs: tuple[int, ...],
    sampling: ECalTargetMotionSampling,
    rng: np.random.Generator,
) -> np.ndarray:
    poses = _fixed_pose(ranges, count)
    if count == 0 or not free_idxs:
        return poses
    for idx in free_idxs:
        lower, upper = ranges[idx]
        if sampling is ECalTargetMotionSampling.RANDOM:
            values = rng.uniform(lower, upper, size=count)
        else:
            strata = (np.arange(count, dtype=np.float64) + rng.random(count)) / count
            if sampling is ECalTargetMotionSampling.HYPERCUBE:
                strata = strata[rng.permutation(count)]
            values = lower + (upper - lower) * strata
        poses[:, idx] = values
    return poses


def _sample_cartesian_poses(
    ranges: _NORMALISED_RANGES,
    free_idxs: tuple[int, ...],
    cartesian_levels: int | tuple[int, ...] | None,
) -> np.ndarray:
    if cartesian_levels is None:
        raise ValueError("CARTESIAN sampling requires cartesian_levels.")
    if isinstance(cartesian_levels, int):
        levels = (cartesian_levels,) * len(free_idxs)
    else:
        levels = tuple(cartesian_levels)
    if len(levels) != len(free_idxs) or any(item < 1 for item in levels):
        raise ValueError("cartesian_levels must be positive for every free axis.")
    axes = [
        np.linspace(*ranges[idx], num=level)
        for idx, level in zip(free_idxs, levels)
    ]
    poses = _fixed_pose(ranges, int(np.prod(levels, dtype=np.intp)))
    for row_idx, values in enumerate(product(*axes)):
        poses[row_idx, list(free_idxs)] = values
    return poses


def _fixed_pose(ranges: _NORMALISED_RANGES, count: int) -> np.ndarray:
    poses = np.zeros((count, 6), dtype=np.float64)
    for idx, (lower, upper) in enumerate(ranges):
        if lower == upper:
            poses[:, idx] = lower
    return poses


def _calculate_pose_coords(
    coords: np.ndarray,
    center: np.ndarray,
    pose: np.ndarray,
) -> np.ndarray:
    rotation = Rotation.from_euler("ZYX", pose[3:][::-1], degrees=True)
    rotated = rotation.apply(coords - center)
    return rotated + center + pose[:3]


def _calculate_displacements(
    coords: np.ndarray,
    center: np.ndarray,
    poses: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    frames = np.empty((poses.shape[0], coords.shape[0], 3), dtype=np.float64)
    for frame_idx, pose in enumerate(poses):
        frames[frame_idx] = _calculate_pose_coords(coords, center, pose) - coords
    components = tuple(np.ascontiguousarray(frames[:, :, axis].T) for axis in range(3))
    return components  # type: ignore[return-value]


def _validate_camera(camera: Camera) -> None:
    pixels_num = np.asarray(camera.pixels_num)
    pixels_size = np.asarray(camera.pixels_size, dtype=np.float64)
    if pixels_num.shape != (2,) or np.any(pixels_num <= 0):
        raise ValueError("camera.pixels_num must contain two positive values.")
    if pixels_size.shape != (2,) or np.any(pixels_size <= 0):
        raise ValueError("camera.pixels_size must contain two positive values.")
    if not np.isfinite(camera.focal_length) or camera.focal_length <= 0.0:
        raise ValueError("camera.focal_length must be positive and finite.")
    if camera.coord_sys != 0:
        raise ValueError("caltarget_motion_from_fov requires an OpenGL camera.")
    if camera.distortion_model not in (0, 1, 2):
        raise ValueError(
            "caltarget_motion_from_fov supports no distortion, Brown-Conrady, "
            "and Brown-Conrady-Ext cameras."
        )
    if camera.distortion_tau_x != 0.0 or camera.distortion_tau_y != 0.0:
        raise ValueError("caltarget_motion_from_fov does not support sensor tilt.")


def _validate_fov_fraction(fov_fraction: float) -> None:
    if not np.isfinite(fov_fraction) or not 0.0 < fov_fraction <= 1.0:
        raise ValueError("fov_fraction must be finite and in (0.0, 1.0].")


def _fit_poses_to_fov(
    coords: np.ndarray,
    center: np.ndarray,
    camera: Camera,
    fov_fraction: float,
    poses: np.ndarray,
) -> np.ndarray:
    reference = np.zeros(6, dtype=np.float64)
    if not _pose_is_in_fov(coords, center, reference, camera, fov_fraction):
        raise ValueError(
            "the undeformed reference target does not fit within the requested "
            "camera FOV."
        )
    fitted = np.empty_like(poses)
    for pose_idx, pose in enumerate(poses):
        fitted[pose_idx] = _fit_pose_to_fov(
            coords,
            center,
            pose,
            reference,
            camera,
            fov_fraction,
        )
    return fitted


def _fit_pose_to_fov(
    coords: np.ndarray,
    center: np.ndarray,
    pose: np.ndarray,
    reference: np.ndarray,
    camera: Camera,
    fov_fraction: float,
) -> np.ndarray:
    rotation_pose = np.zeros(6, dtype=np.float64)
    rotation_pose[3:] = pose[3:]
    fitted_rotation = _contract_pose_to_fov(
        coords,
        center,
        reference,
        rotation_pose,
        camera,
        fov_fraction,
    )
    target_pose = fitted_rotation.copy()
    target_pose[:3] = pose[:3]
    return _contract_pose_to_fov(
        coords,
        center,
        fitted_rotation,
        target_pose,
        camera,
        fov_fraction,
    )


def _contract_pose_to_fov(
    coords: np.ndarray,
    center: np.ndarray,
    pose_start: np.ndarray,
    pose_end: np.ndarray,
    camera: Camera,
    fov_fraction: float,
) -> np.ndarray:
    if _pose_is_in_fov(coords, center, pose_end, camera, fov_fraction):
        return pose_end

    lower = 0.0
    upper = 1.0
    for _ in range(52):
        fraction = 0.5 * (lower + upper)
        pose = pose_start + fraction * (pose_end - pose_start)
        if _pose_is_in_fov(coords, center, pose, camera, fov_fraction):
            lower = fraction
        else:
            upper = fraction
    return pose_start + lower * (pose_end - pose_start)


def _pose_is_in_fov(
    coords: np.ndarray,
    center: np.ndarray,
    pose: np.ndarray,
    camera: Camera,
    fov_fraction: float,
) -> bool:
    pixels = _project_world_points(_calculate_pose_coords(coords, center, pose), camera)
    width, height = np.asarray(camera.pixels_num, dtype=np.float64)
    margin_x = 0.5 * (1.0 - fov_fraction) * width
    margin_y = 0.5 * (1.0 - fov_fraction) * height
    return bool(np.all(np.isfinite(pixels)) and np.all(pixels[:, 0] >= margin_x)
                and np.all(pixels[:, 0] <= width - margin_x)
                and np.all(pixels[:, 1] >= margin_y)
                and np.all(pixels[:, 1] <= height - margin_y))


def _project_world_points(coords: np.ndarray, camera: Camera) -> np.ndarray:
    camera_rotation = Rotation.from_euler(
        "ZYX",
        np.asarray(camera.rot_world, dtype=np.float64)[::-1],
    )
    cam_coords = camera_rotation.inv().apply(
        coords - np.asarray(camera.pos_world, dtype=np.float64),
    )
    depth = -cam_coords[:, 2]
    if np.any(depth <= 0.0):
        return np.full((coords.shape[0], 2), np.nan, dtype=np.float64)
    norm_x = cam_coords[:, 0] / depth
    norm_y = cam_coords[:, 1] / depth
    dist_x, dist_y = _apply_brown_conrady(norm_x, norm_y, camera)
    focal_px = camera.focal_length / np.asarray(camera.pixels_size, dtype=np.float64)
    pixels_num = np.asarray(camera.pixels_num, dtype=np.float64)
    return np.column_stack((0.5 * pixels_num[0] + focal_px[0] * dist_x,
                            0.5 * pixels_num[1] - focal_px[1] * dist_y))


def _apply_brown_conrady(
    x: np.ndarray,
    y: np.ndarray,
    camera: Camera,
) -> tuple[np.ndarray, np.ndarray]:
    if camera.distortion_model not in (1, 2):
        return x, y
    r2 = x * x + y * y
    radial_num = (
        1.0
        + camera.distortion_k1 * r2
        + camera.distortion_k2 * r2 * r2
        + camera.distortion_k3 * r2 * r2 * r2
    )
    radial = radial_num
    if camera.distortion_model == 2:
        radial_den = (
            1.0
            + camera.distortion_k4 * r2
            + camera.distortion_k5 * r2 * r2
            + camera.distortion_k6 * r2 * r2 * r2
        )
        radial = radial_num / radial_den
    xy = x * y
    x_out = (
        x * radial
        + 2.0 * camera.distortion_p1 * xy
        + camera.distortion_p2 * (r2 + 2.0 * x * x)
    )
    y_out = (
        y * radial
        + camera.distortion_p1 * (r2 + 2.0 * y * y)
        + 2.0 * camera.distortion_p2 * xy
    )
    if camera.distortion_model == 2:
        x_out += camera.distortion_s1 * r2 + camera.distortion_s2 * r2 * r2
        y_out += camera.distortion_s3 * r2 + camera.distortion_s4 * r2 * r2
    return x_out, y_out
