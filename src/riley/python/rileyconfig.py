# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------

from numbers import Integral

from riley.cython.riley import (
    GeometrySchedulingMode,
    HullMode,
    ImageFormat,
    ImageSaveMode,
    NewtonSeedMode,
    NewtonSeedReuse,
    RasterConfig,
    RenderMode,
    ReportMode,
    SaveStrategy,
    ScaleStrategy,
    ValidateInput,
)


def create_raster_config(
    num_frames: int,
    total_threads: int = 1,
    save_strategy: SaveStrategy = SaveStrategy.both,
    validate_input: ValidateInput = ValidateInput.fast,
    output_name_format: str = (
        "cam{camera}_frame{frame}_field{field}"
    ),
    *,
    num_cameras: int = 1,
) -> RasterConfig:
    """Create an offline RasterConfig balanced across frames and workers.

    Parameters
    ----------
    num_frames : int
        Number of frames to render. Must be a positive integer.
    total_threads : int, default=1
        Render-thread budget, including group callers. Must be positive.
        Disk-save overlap threads are separate from this budget.
    num_cameras : int, default=1
        Number of cameras per frame. Used with num_frames to estimate available
        offline jobs and set the per-job worker cap.
    save_strategy : SaveStrategy, default=SaveStrategy.both
        Strategy for retaining and writing rendered frame buffers.
    output_name_format : str, optional
        Basename template for saved images. Available fields are ``camera``,
        ``frame``, and ``field``. Fields accept zero padding, for example
        ``"frame{frame:04}_{camera}"``. Riley appends the image extension.

    Returns
    -------
    RasterConfig
        Configured rasteriser settings.

    Raises
    ------
    TypeError
        If `num_frames`, `num_cameras`, or `total_threads` is not an integer, or
        `save_strategy` is not a `SaveStrategy` member.
    ValueError
        If `num_frames`, `num_cameras`, or `total_threads` is not positive.
    """

    if not isinstance(num_frames, Integral) or isinstance(num_frames, bool):
        raise TypeError("num_frames must be an integer.")

    if not isinstance(total_threads, Integral) or isinstance(
        total_threads,
        bool,
    ):
        raise TypeError("total_threads must be an integer.")

    if not isinstance(save_strategy, SaveStrategy):
        raise TypeError("save_strategy must be a SaveStrategy member.")

    if not isinstance(num_cameras, Integral) or isinstance(num_cameras, bool):
        raise TypeError("num_cameras must be an integer.")
    if num_cameras <= 0:
        raise ValueError("num_cameras must be positive.")

    if not isinstance(validate_input, ValidateInput):
        raise TypeError("validate_input must be a ValidateInput member.")

    if not isinstance(output_name_format, str):
        raise TypeError("output_name_format must be a string.")

    if not output_name_format:
        raise ValueError("output_name_format must not be empty.")
    if num_frames <= 0:
        raise ValueError("num_frames must be positive.")

    if total_threads <= 0:
        raise ValueError("total_threads must be positive.")

    # Match ManagedRenderGroups: prefer independent camera/frame jobs, then
    # distribute any remaining workers evenly. The largest group determines
    # the per-job cap; the C runtime applies each group's actual worker budget.
    jobs_available = int(num_frames) * int(num_cameras)
    threads_available = int(total_threads)
    render_group_count = min(threads_available, jobs_available)
    workers_per_group = (
        threads_available + render_group_count - 1
    ) // render_group_count

    return RasterConfig(
        render_mode=RenderMode.offline,
        total_threads=threads_available,
        geom_scheduling_mode=GeometrySchedulingMode.spread,
        max_raster_workers_per_job=workers_per_group,
        save_strategy=save_strategy,
        image_save_mode=ImageSaveMode.multifield,
        hull_mode=HullMode.on_no_fallback,
        newton_seed_mode=NewtonSeedMode.centroid,
        newton_seed_reuse=NewtonSeedReuse.off,
        validate_input=validate_input,
        report=ReportMode.bench,
        save_format=ImageFormat.bmp,
        save_bits=8,
        save_scaling=ScaleStrategy.auto,
        output_name_format=output_name_format,
    )


__all__ = ["create_raster_config"]
