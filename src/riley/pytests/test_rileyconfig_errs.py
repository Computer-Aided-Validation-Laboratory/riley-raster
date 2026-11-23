# --------------------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
# --------------------------------------------------------------------------------------
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
