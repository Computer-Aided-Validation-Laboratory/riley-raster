from __future__ import annotations

import shutil
import subprocess
from dataclasses import fields
from pathlib import Path

import pytest

import riley


def make_camera(**kwargs: object) -> riley.Camera:
    return riley.Camera(
        pixels_num=(100, 80),
        pixels_size=(1.0e-5, 1.1e-5),
        pos_world=(0.0, 0.0, 0.2),
        rot_world=(0.0, 0.0, 0.0),
        roi_cent_world=(0.0, 0.0, 0.0),
        focal_length=0.05,
        sub_sample=1,
        **kwargs,
    )


@pytest.mark.parametrize("model", (3, 4, 5))
@pytest.mark.parametrize("order", (1, 2, 3))
def test_poly_camera_roundtrip_through_c_abi(
    tmp_path: Path, model: int, order: int
) -> None:
    term_count = {1: 3, 2: 6, 3: 10}[order]
    coeffs_u = tuple((index + 1) * 0.001 for index in range(term_count)) + (0.0,) * (
        10 - term_count
    )
    coeffs_v = tuple(-value for value in coeffs_u)
    camera = make_camera(
        distort_model=model,
        distort_poly_order=order,
        distort_poly_u=coeffs_u,
        distort_poly_v=coeffs_v,
        distort_k1=-0.12 if model != 3 else 0.0,
        distort_tau_x=0.02 if model == 5 else 0.0,
        coord_sys=riley.CameraCoordSys.opencv,
    )
    riley.save_camera(str(tmp_path), "camera.csv", 0, camera)
    loaded = riley.load_camera(str(tmp_path), "camera.csv")
    assert loaded.distort_model == model
    assert loaded.distort_poly_order == order
    assert loaded.distort_poly_u == pytest.approx(coeffs_u)
    assert loaded.distort_poly_v == pytest.approx(coeffs_v)
    assert loaded.distort_k1 == pytest.approx(camera.distort_k1)
    assert loaded.distort_tau_x == pytest.approx(camera.distort_tau_x)
    assert loaded.coord_sys == camera.coord_sys
    content = (tmp_path / "camera.csv").read_text()
    assert "poly_u_0," in content
    assert "poly_v_0," in content
    assert "poly_has_" not in content
    assert "poly_inv" not in content


def test_poly_camera_has_no_direction_flags_or_inv_coefficients() -> None:
    names = {field.name for field in fields(riley.Camera)}
    assert "distort_poly_u" in names
    assert "distort_poly_v" in names
    assert not any("poly_has_" in name or "poly_inv" in name for name in names)
    with pytest.raises(TypeError):
        make_camera(distort_poly_has_inv=True)


@pytest.mark.parametrize("bad_length", (0, 3, 9, 11))
def test_poly_coefficients_require_ten_entries(
    tmp_path: Path, bad_length: int
) -> None:
    camera = make_camera(distort_model=3, distort_poly_u=(0.0,) * bad_length)
    with pytest.raises(ValueError, match="ten coefficients"):
        riley.save_camera(str(tmp_path), "camera.csv", 0, camera)


def test_inv_only_camera_csv_is_rejected(tmp_path: Path) -> None:
    camera = make_camera(distort_model=3)
    riley.save_camera(str(tmp_path), "camera.csv", 0, camera)
    path = tmp_path / "camera.csv"
    with path.open("a") as stream:
        stream.write("poly_has_inv,1\n")
    with pytest.raises(RuntimeError, match="UnsupportedInvPoly"):
        riley.load_camera(str(tmp_path), "camera.csv")


def test_public_poly_c_header_layout() -> None:
    compiler = shutil.which("cc")
    if compiler is None:
        pytest.skip("C compiler unavailable")
    source = Path(__file__).resolve().parents[2] / "tests" / "c_distortion_abi.c"
    subprocess.run([compiler, "-std=c11", "-fsyntax-only", str(source)], check=True)
