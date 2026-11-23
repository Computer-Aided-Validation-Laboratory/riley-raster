# --------------------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
# --------------------------------------------------------------------------------------
import numpy as np
import pytest

from riley.cython import riley as bindings


def test_texture_storage_rejects_mismatched_dtype() -> None:
    with pytest.raises(ValueError, match="uint16"):
        bindings._contig_texture(
            np.zeros((2, 2), dtype=np.uint8),
            1,
            bindings.TextureStorage.u16,
        )
