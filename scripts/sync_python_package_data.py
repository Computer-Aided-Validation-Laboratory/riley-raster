# --------------------------------------------------------------------------
# Riley: A High Performance Rasteriser for DIC UQ
#
# Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
# Licensed under the MIT License (see LICENSE file for details)
#
# Authors: scepticalrabbit (Lloyd Fletcher)
# --------------------------------------------------------------------------
from __future__ import annotations

import shutil
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
PACKAGE_DATA_ROOT = PROJECT_ROOT / "src" / "riley" / "data"


SYNC_FILES: tuple[tuple[str, str], ...] = (
    ("texture/speckle.bmp", "textures/speckle.bmp"),
    ("texture/cal_target-simple.tiff", "textures/cal_target-simple.tiff"),
    ("data/FE/platehole3d_2mr_63f.e", "fe/platehole3d_2mr_63f.e"),
    ("data/bench/tri6_sphere200/connect.csv", "bench/tri6_sphere200/connect.csv"),
    ("data/bench/tri6_sphere200/coords.csv", "bench/tri6_sphere200/coords.csv"),
    ("data/bench/tri6_sphere200/field.csv", "bench/tri6_sphere200/field.csv"),
    ("data/bench/tri6_sphere200/uvs.csv", "bench/tri6_sphere200/uvs.csv"),
    (
        "data/FE/platehole3d_2mr_63f/connect.csv",
        "fe/platehole3d_2mr_63f/connect.csv",
    ),
    (
        "data/FE/platehole3d_2mr_63f/coords.csv",
        "fe/platehole3d_2mr_63f/coords.csv",
    ),
    (
        "data/FE/platehole3d_2mr_63f/field_disp_x.csv",
        "fe/platehole3d_2mr_63f/field_disp_x.csv",
    ),
    (
        "data/FE/platehole3d_2mr_63f/field_disp_y.csv",
        "fe/platehole3d_2mr_63f/field_disp_y.csv",
    ),
    (
        "data/FE/platehole3d_2mr_63f/field_disp_z.csv",
        "fe/platehole3d_2mr_63f/field_disp_z.csv",
    ),
    (
        "data/FE/platehole3d_2mr_63f/uvs.csv",
        "fe/platehole3d_2mr_63f/uvs.csv",
    ),
    (
        "data/calplate/tri3_calplate3d/connect.csv",
        "calplate/tri3_calplate3d/connect.csv",
    ),
    (
        "data/calplate/tri3_calplate3d/coords.csv",
        "calplate/tri3_calplate3d/coords.csv",
    ),
    (
        "data/calplate/tri3_calplate3d/field_disp_x.csv",
        "calplate/tri3_calplate3d/field_disp_x.csv",
    ),
    (
        "data/calplate/tri3_calplate3d/field_disp_y.csv",
        "calplate/tri3_calplate3d/field_disp_y.csv",
    ),
    (
        "data/calplate/tri3_calplate3d/field_disp_z.csv",
        "calplate/tri3_calplate3d/field_disp_z.csv",
    ),
    (
        "data/calplate/tri3_calplate3d/states.csv",
        "calplate/tri3_calplate3d/states.csv",
    ),
    (
        "data/calplate/tri3_calplate3d/uvs.csv",
        "calplate/tri3_calplate3d/uvs.csv",
    ),
    ("data/rabbits/feebs_quad4/connectivity.csv", "rabbits/feebs_quad4/connectivity.csv"),
    ("data/rabbits/feebs_quad4/coords.csv", "rabbits/feebs_quad4/coords.csv"),
    ("data/rabbits/feebs_quad4/uvs.csv", "rabbits/feebs_quad4/uvs.csv"),
    ("data/rabbits/feebs_quad8/connectivity.csv", "rabbits/feebs_quad8/connectivity.csv"),
    ("data/rabbits/feebs_quad8/coords.csv", "rabbits/feebs_quad8/coords.csv"),
    ("data/rabbits/feebs_quad8/uvs.csv", "rabbits/feebs_quad8/uvs.csv"),
    ("data/rabbits/feebs_quad9/connectivity.csv", "rabbits/feebs_quad9/connectivity.csv"),
    ("data/rabbits/feebs_quad9/coords.csv", "rabbits/feebs_quad9/coords.csv"),
    ("data/rabbits/feebs_quad9/uvs.csv", "rabbits/feebs_quad9/uvs.csv"),
    ("data/rabbits/feebs_tri3/connectivity.csv", "rabbits/feebs_tri3/connectivity.csv"),
    ("data/rabbits/feebs_tri3/coords.csv", "rabbits/feebs_tri3/coords.csv"),
    ("data/rabbits/feebs_tri3/uvs.csv", "rabbits/feebs_tri3/uvs.csv"),
    ("data/rabbits/feebs_tri6/connectivity.csv", "rabbits/feebs_tri6/connectivity.csv"),
    ("data/rabbits/feebs_tri6/coords.csv", "rabbits/feebs_tri6/coords.csv"),
    ("data/rabbits/feebs_tri6/uvs.csv", "rabbits/feebs_tri6/uvs.csv"),
    ("data/rabbits/rabbit_quad4/connectivity.csv", "rabbits/rabbit_quad4/connectivity.csv"),
    ("data/rabbits/rabbit_quad4/coords.csv", "rabbits/rabbit_quad4/coords.csv"),
    ("data/rabbits/rabbit_quad4/uvs.csv", "rabbits/rabbit_quad4/uvs.csv"),
    ("data/rabbits/rabbit_quad8/connectivity.csv", "rabbits/rabbit_quad8/connectivity.csv"),
    ("data/rabbits/rabbit_quad8/coords.csv", "rabbits/rabbit_quad8/coords.csv"),
    ("data/rabbits/rabbit_quad8/uvs.csv", "rabbits/rabbit_quad8/uvs.csv"),
    ("data/rabbits/rabbit_quad9/connectivity.csv", "rabbits/rabbit_quad9/connectivity.csv"),
    ("data/rabbits/rabbit_quad9/coords.csv", "rabbits/rabbit_quad9/coords.csv"),
    ("data/rabbits/rabbit_quad9/uvs.csv", "rabbits/rabbit_quad9/uvs.csv"),
    ("data/rabbits/rabbit_tri3/connectivity.csv", "rabbits/rabbit_tri3/connectivity.csv"),
    ("data/rabbits/rabbit_tri3/coords.csv", "rabbits/rabbit_tri3/coords.csv"),
    ("data/rabbits/rabbit_tri3/uvs.csv", "rabbits/rabbit_tri3/uvs.csv"),
    ("data/rabbits/rabbit_tri6/connectivity.csv", "rabbits/rabbit_tri6/connectivity.csv"),
    ("data/rabbits/rabbit_tri6/coords.csv", "rabbits/rabbit_tri6/coords.csv"),
    ("data/rabbits/rabbit_tri6/uvs.csv", "rabbits/rabbit_tri6/uvs.csv"),
    ("data/rabbits/riley_quad4/connectivity.csv", "rabbits/riley_quad4/connectivity.csv"),
    ("data/rabbits/riley_quad4/coords.csv", "rabbits/riley_quad4/coords.csv"),
    ("data/rabbits/riley_quad4/uvs.csv", "rabbits/riley_quad4/uvs.csv"),
    ("data/rabbits/riley_quad8/connectivity.csv", "rabbits/riley_quad8/connectivity.csv"),
    ("data/rabbits/riley_quad8/coords.csv", "rabbits/riley_quad8/coords.csv"),
    ("data/rabbits/riley_quad8/uvs.csv", "rabbits/riley_quad8/uvs.csv"),
    ("data/rabbits/riley_quad9/connectivity.csv", "rabbits/riley_quad9/connectivity.csv"),
    ("data/rabbits/riley_quad9/coords.csv", "rabbits/riley_quad9/coords.csv"),
    ("data/rabbits/riley_quad9/uvs.csv", "rabbits/riley_quad9/uvs.csv"),
    ("data/rabbits/riley_tri3/connectivity.csv", "rabbits/riley_tri3/connectivity.csv"),
    ("data/rabbits/riley_tri3/coords.csv", "rabbits/riley_tri3/coords.csv"),
    ("data/rabbits/riley_tri3/uvs.csv", "rabbits/riley_tri3/uvs.csv"),
    ("data/rabbits/riley_tri6/connectivity.csv", "rabbits/riley_tri6/connectivity.csv"),
    ("data/rabbits/riley_tri6/coords.csv", "rabbits/riley_tri6/coords.csv"),
    ("data/rabbits/riley_tri6/uvs.csv", "rabbits/riley_tri6/uvs.csv"),
)


def sync_python_package_data() -> None:
    PACKAGE_DATA_ROOT.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(PACKAGE_DATA_ROOT / "__pycache__", ignore_errors=True)

    for src_rel, dst_rel in SYNC_FILES:
        src_path = PROJECT_ROOT / src_rel
        dst_path = PACKAGE_DATA_ROOT / dst_rel
        if not src_path.is_file():
            raise FileNotFoundError(
                f"Required package data source is missing: {src_path}",
            )
        dst_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src_path, dst_path)


def main() -> None:
    sync_python_package_data()


if __name__ == "__main__":
    main()
