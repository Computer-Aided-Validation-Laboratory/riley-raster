"""Tests for Python raster configuration defaults and parallel budgets."""

import pytest
import riley


def test_raster_config_defaults_to_zig_auto_offline() -> None:
    config = riley.RasterConfig()
    assert config.render_mode == riley.RenderMode.offline
    assert config.parallel is None
    assert config.save_strategy == riley.SaveStrategy.memory


@pytest.mark.parametrize("budget", (1, 4, 65535))
def test_raster_config_accepts_explicit_thread_budget(budget: int) -> None:
    assert riley.RasterConfig(parallel=budget).parallel == budget


def test_raster_config_accepts_validation_mode() -> None:
    config = riley.RasterConfig(validate_input=riley.ValidateInput.full)
    assert config.validate_input is riley.ValidateInput.full
