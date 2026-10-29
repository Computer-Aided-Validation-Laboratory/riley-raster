"""Tests for rejected Python parallel configuration."""

import pytest
import riley


@pytest.mark.parametrize("parallel", (True, False, 1.5, "4"))
def test_raster_config_rejects_non_integer_parallel(parallel: object) -> None:
    with pytest.raises(TypeError, match="parallel"):
        riley.RasterConfig(parallel=parallel)


@pytest.mark.parametrize("parallel", (0, -1, 65536))
def test_raster_config_rejects_out_of_range_parallel(parallel: int) -> None:
    with pytest.raises(ValueError, match="parallel"):
        riley.RasterConfig(parallel=parallel)
