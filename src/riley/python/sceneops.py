from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Sequence

import numpy as np


class AxisAnchor(Enum):
    MIN = "min"
    CENTER = "center"
    MAX = "max"


class OverlapDirection(Enum):
    NEGATIVE = "negative"
    CURRENT = "current"
    POSITIVE = "positive"


@dataclass(frozen=True, slots=True)
class Bounds3D:
    min: np.ndarray
    max: np.ndarray
    center: np.ndarray
    extent: np.ndarray


@dataclass(frozen=True, slots=True)
class MeshGroup:
    mesh_start: int
    mesh_len: int


@dataclass(frozen=True, slots=True)
class GridSpec:
    gap: tuple[float, float, float]
    max_divs: tuple[int, int, int]


@dataclass(frozen=True, slots=True)
class BoundsOverlapSpec:
    overlap_frac: tuple[float, float, float]
    enabled_axes: tuple[bool, bool, bool] = (True, True, True)
    direction: tuple[OverlapDirection, OverlapDirection, OverlapDirection] = (
        OverlapDirection.CURRENT,
        OverlapDirection.CURRENT,
        OverlapDirection.CURRENT,
    )
    extra_offset: tuple[float, float, float] = (0.0, 0.0, 0.0)


def mesh_group_span(mesh_start: int, mesh_len: int) -> MeshGroup:
    return MeshGroup(mesh_start=mesh_start, mesh_len=mesh_len)


def mesh_group_single(mesh_idx: int) -> MeshGroup:
    return mesh_group_span(mesh_idx, 1)


def _group_indices(group: MeshGroup) -> range:
    return range(group.mesh_start, group.mesh_start + group.mesh_len)


def bounds_for_coords(coords: np.ndarray) -> Bounds3D:
    min_vals = np.min(coords, axis=0)
    max_vals = np.max(coords, axis=0)
    return Bounds3D(
        min=min_vals,
        max=max_vals,
        center=0.5 * (min_vals + max_vals),
        extent=max_vals - min_vals,
    )


def bounds_for_meshes(meshes: Sequence[object]) -> Bounds3D:
    all_coords = np.concatenate([mesh.coords for mesh in meshes], axis=0)
    return bounds_for_coords(all_coords)


def bounds_for_mesh_group(meshes: Sequence[object], group: MeshGroup) -> Bounds3D:
    coords = np.concatenate([meshes[idx].coords for idx in _group_indices(group)], axis=0)
    return bounds_for_coords(coords)


def translate_mesh_group(
    meshes: Sequence[object],
    group: MeshGroup,
    translation: tuple[float, float, float] | np.ndarray,
) -> None:
    translation_arr = np.asarray(translation, dtype=np.float64)
    for idx in _group_indices(group):
        meshes[idx].coords[:, :] += translation_arr


def center_mesh_group_at(
    meshes: Sequence[object],
    group: MeshGroup,
    target_center: tuple[float, float, float] | np.ndarray,
) -> None:
    bounds = bounds_for_mesh_group(meshes, group)
    target_arr = np.asarray(target_center, dtype=np.float64)
    translate_mesh_group(meshes, group, target_arr - bounds.center)


def _overlap_sign(current_sep: float, direction: OverlapDirection) -> float:
    if direction is OverlapDirection.NEGATIVE:
        return -1.0
    if direction is OverlapDirection.POSITIVE:
        return 1.0
    return -1.0 if current_sep < 0.0 else 1.0


def overlap_mesh_group_bounds(
    meshes: Sequence[object],
    fixed_group: MeshGroup,
    moving_group: MeshGroup,
    spec: BoundsOverlapSpec,
) -> None:
    fixed_bounds = bounds_for_mesh_group(meshes, fixed_group)
    moving_bounds = bounds_for_mesh_group(meshes, moving_group)
    translation = np.asarray(spec.extra_offset, dtype=np.float64)

    for axis in range(3):
        if not spec.enabled_axes[axis]:
            continue

        desired_overlap = spec.overlap_frac[axis] * min(
            fixed_bounds.extent[axis],
            moving_bounds.extent[axis],
        )
        center_sep_mag = (
            0.5 * (fixed_bounds.extent[axis] + moving_bounds.extent[axis])
            - desired_overlap
        )
        current_sep = moving_bounds.center[axis] - fixed_bounds.center[axis]
        sep_sign = _overlap_sign(current_sep, spec.direction[axis])
        target_center = (
            fixed_bounds.center[axis]
            + sep_sign * center_sep_mag
            + spec.extra_offset[axis]
        )
        translation[axis] = target_center - moving_bounds.center[axis]

    translate_mesh_group(meshes, moving_group, translation)


def arrange_mesh_groups_grid(
    meshes: Sequence[object],
    groups: Sequence[MeshGroup],
    spec: GridSpec,
) -> None:
    max_extent = np.zeros((3,), dtype=np.float64)
    for group in groups:
        bounds = bounds_for_mesh_group(meshes, group)
        max_extent = np.maximum(max_extent, bounds.extent)

    stride = max_extent + np.asarray(spec.gap, dtype=np.float64)
    x_divs, y_divs, _ = spec.max_divs

    for index, group in enumerate(groups):
        xx = index % x_divs
        yy = (index // x_divs) % y_divs
        zz = index // (x_divs * y_divs)
        center_mesh_group_at(
            meshes,
            group,
            (
                float(xx) * stride[0],
                float(yy) * stride[1],
                float(zz) * stride[2],
            ),
        )
