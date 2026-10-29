"""Tests for Python raster configuration defaults and parallel budgets."""

import pytest
import riley


def test_raster_config_defaults_to_zig_auto_offline() -> None:
    config = riley.RasterConfig()
    assert config.render_mode == riley.RenderMode.offline
    assert config.parallel is None
    assert config.save_strategy == riley.SaveStrategy.memory
    assert config.multiroot_mode == riley.MultirootSolverMode.fast


def test_multiroot_solver_mode_can_be_configured() -> None:
    config = riley.RasterConfig()
    config.multiroot_mode = int(riley.MultirootSolverMode.robust)
    assert config.multiroot_mode == riley.MultirootSolverMode.robust



@pytest.mark.parametrize("budget", (1, 4, 65535))
def test_raster_config_accepts_explicit_thread_budget(budget: int) -> None:
    assert riley.RasterConfig(parallel=budget).parallel == budget


def test_raster_config_accepts_validation_mode() -> None:
    config = riley.RasterConfig(validate_input=riley.ValidateInput.full)
    assert config.validate_input is riley.ValidateInput.full


def test_raster_config_exposes_explicit_image_save_modes() -> None:
    assert tuple(riley.ImageSaveMode) == (
        riley.ImageSaveMode.grey,
        riley.ImageSaveMode.rgb,
        riley.ImageSaveMode.multifield,
        riley.ImageSaveMode.rgb_to_grey,
        riley.ImageSaveMode.grey_to_rgb,
    )


def test_raster_config_exposes_edge_fun_mode_and_halo() -> None:
    config = riley.RasterConfig()
    assert config.oneroot_edge_fun_mode == riley.EdgeFunMode.on_the_fly
    assert config.multiroot_edge_fun_mode == riley.EdgeFunMode.pre_calc
    assert config.raster_halo_px_override == 0

    config.oneroot_edge_fun_mode = int(riley.EdgeFunMode.pre_calc)
    config.multiroot_edge_fun_mode = int(riley.EdgeFunMode.on_the_fly)
    config.raster_halo_px_override = 2
    assert config.oneroot_edge_fun_mode == riley.EdgeFunMode.pre_calc
    assert config.multiroot_edge_fun_mode == riley.EdgeFunMode.on_the_fly
    assert config.raster_halo_px_override == 2
