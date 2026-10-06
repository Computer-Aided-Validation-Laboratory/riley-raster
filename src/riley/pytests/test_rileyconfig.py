"""Tests for strict texture loading and raster configuration."""

from pathlib import Path
import numpy as np
import pytest
from PIL import Image
import riley


def test_create_raster_config_uses_enum_default() -> None:
    config = riley.create_raster_config(4, 8)
    assert config.save_strategy is riley.SaveStrategy.both
    assert config.max_raster_workers_per_job == 2
    assert config.validate_input is riley.ValidateInput.fast
    assert config.multiroot_mode == riley.MultirootSolverMode.fast


def test_multiroot_solver_mode_can_be_configured() -> None:
    config = riley.create_raster_config(1, 1)
    config.multiroot_mode = int(riley.MultirootSolverMode.robust)
    assert config.multiroot_mode == riley.MultirootSolverMode.robust


def test_create_raster_config_accepts_validate_input_modes() -> None:
    for mode in (
        riley.ValidateInput.off,
        riley.ValidateInput.fast,
        riley.ValidateInput.full,
    ):
        config = riley.create_raster_config(1, 1, validate_input=mode)
        assert config.validate_input is mode


@pytest.mark.parametrize(
    ("frames", "cameras", "budget", "workers"),
    ((1, 1, 4, 4), (3, 1, 7, 3), (5, 1, 12, 3), (2, 2, 8, 2), (8, 2, 8, 1)),
)
def test_create_raster_config_balances_camera_frame_jobs(
    frames: int, cameras: int, budget: int, workers: int,
) -> None:
    config = riley.create_raster_config(frames, budget, num_cameras=cameras)
    assert config.total_threads == budget
    assert config.max_raster_workers_per_job == workers
