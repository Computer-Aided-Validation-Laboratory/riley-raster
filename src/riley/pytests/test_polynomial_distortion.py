from __future__ import annotations

import gc
import shutil
import subprocess
from pathlib import Path

import numpy as np
import pytest

import riley


def make_camera(**kwargs: object) -> riley.Camera:
    return riley.Camera(
        pixels_num=(100, 80),
        pixels_size=(1e-5, 1.1e-5),
        pos_world=(0, 0, 0.2),
        rot_world=(0, 0, 0),
        roi_cent_world=(0, 0, 0),
        focal_length=0.05,
        sub_sample=1,
        **kwargs,
    )


@pytest.mark.parametrize("model", (3, 4, 5))
@pytest.mark.parametrize("degree", range(1, 8))
@pytest.mark.parametrize("mode", tuple(riley.EPolyMode))
def test_poly_camera_roundtrip(
    tmp_path: Path, model: int, degree: int, mode: riley.EPolyMode
) -> None:
    count = (degree + 1) * (degree + 2) // 2
    coeffs = np.arange(2 * count, dtype=np.float64).reshape((count, 2)) * 1e-16
    # Noncontiguous arrays must be accepted without flattening the wrong order.
    strided = np.repeat(coeffs, 2, axis=1)[:, ::2]
    camera = make_camera(
        distort_model=model,
        distort_poly=riley.PolyMap(degree, mode, strided),
        distort_k1=-0.12 if model != 3 else 0,
        distort_tau_x=0.02 if model == 5 else 0,
        coord_sys=riley.CameraCoordSys.opencv,
    )
    riley.save_camera(str(tmp_path), "camera.csv", 0, camera)
    loaded = riley.load_camera(str(tmp_path), "camera.csv")
    gc.collect()
    assert loaded.distort_poly.degree == degree
    assert loaded.distort_poly.mode == mode
    np.testing.assert_array_equal(loaded.distort_poly.coeffs, coeffs)
    assert loaded.distort_poly.coeffs.flags.c_contiguous
    assert loaded.distort_k1 == pytest.approx(camera.distort_k1)
    assert loaded.distort_tau_x == pytest.approx(camera.distort_tau_x)
    assert loaded.coord_sys == camera.coord_sys
    riley.save_camera(str(tmp_path), "loaded.csv", 0, loaded)


@pytest.mark.parametrize("degree", (0, 8, -1, 1.5, True))
def test_invalid_degree(tmp_path: Path, degree: float) -> None:
    camera = make_camera(
        distort_model=3,
        distort_poly=riley.PolyMap(
            degree, riley.EPolyMode.displacement, np.zeros((3, 2))
        ),
    )
    with pytest.raises(ValueError, match="degree"):
        riley.save_camera(str(tmp_path), "invalid.csv", 0, camera)


@pytest.mark.parametrize("shape", ((0, 2), (2, 3), (6,), (4, 2), (3, 1)))
def test_invalid_shape(tmp_path: Path, shape: tuple[int, ...]) -> None:
    camera = make_camera(
        distort_model=3,
        distort_poly=riley.PolyMap(1, riley.EPolyMode.displacement, np.zeros(shape)),
    )
    with pytest.raises(ValueError, match="shape"):
        riley.save_camera(str(tmp_path), "invalid.csv", 0, camera)


@pytest.mark.parametrize("value", (np.nan, np.inf, -np.inf))
def test_nonfinite_coefficients(tmp_path: Path, value: float) -> None:
    coeffs = np.zeros((3, 2))
    coeffs[0, 0] = value
    camera = make_camera(
        distort_model=3,
        distort_poly=riley.PolyMap(1, riley.EPolyMode.coordinate, coeffs),
    )
    with pytest.raises(ValueError, match="finite"):
        riley.save_camera(str(tmp_path), "invalid.csv", 0, camera)


def test_invalid_mode_and_missing_map(tmp_path: Path) -> None:
    for poly in (None, riley.PolyMap(1, 2, np.zeros((3, 2)))):
        with pytest.raises(ValueError):
            riley.save_camera(
                str(tmp_path),
                "invalid.csv",
                0,
                make_camera(distort_model=3, distort_poly=poly),
            )


def test_poly_stereo_lifetime(tmp_path: Path) -> None:
    cameras = []
    for degree, mode in (
        (1, riley.EPolyMode.coordinate),
        (7, riley.EPolyMode.displacement),
    ):
        count = (degree + 1) * (degree + 2) // 2
        cameras.append(
            make_camera(
                distort_model=3,
                distort_poly=riley.PolyMap(degree, mode, np.ones((count, 2)) * 0.001),
            )
        )
    riley.save_stereo_pair(str(tmp_path), "stereo_data.csv", *cameras)
    loaded = riley.load_stereo_pair(str(tmp_path), "stereo_data.csv")
    del cameras
    gc.collect()
    for camera, degree in zip(loaded, (1, 7)):
        assert camera.distort_poly.degree == degree
        np.testing.assert_array_equal(camera.distort_poly.coeffs, 0.001)
    riley.save_stereo_pair(str(tmp_path), "stereo_data_copy.csv", *loaded)


@pytest.mark.parametrize(
    ("metadata", "error"),
    (
        ("poly_has_inv,1", "UnsupportedInvPoly"),
        ("poly_degree,8", "InvalidPolyDegree"),
        ("poly_mode,nonsense", "InvalidPolyMode"),
        ("poly_coeff_36_x,0", "InvalidPolyCoeffCount"),
        ("poly_coeff_0_x,nan", "NonFinitePolyCoeff"),
    ),
)
def test_bad_csv(tmp_path: Path, metadata: str, error: str) -> None:
    camera = make_camera(
        distort_model=3,
        distort_poly=riley.PolyMap(1, riley.EPolyMode.displacement, np.zeros((3, 2))),
    )
    riley.save_camera(str(tmp_path), "camera.csv", 0, camera)
    path = tmp_path / "camera.csv"
    key = metadata.split(",")[0]
    lines = [
        line for line in path.read_text().splitlines() if not line.startswith(key + ",")
    ]
    path.write_text("\n".join(lines + [metadata]) + "\n")
    with pytest.raises(RuntimeError, match=error):
        riley.load_camera(str(tmp_path), "camera.csv")


def test_public_poly_c_buffer_protocol(tmp_path: Path) -> None:
    compiler = shutil.which("cc")
    if compiler is None:
        pytest.skip("C compiler unavailable")
    source = Path(__file__).resolve().parents[2] / "tests" / "c_distortion_abi.c"
    lib_dir = Path(riley.__file__).resolve().parent / "cython"
    library = lib_dir / "libc_riley.so"
    if not source.exists() or not library.exists():
        pytest.skip("repository C regression or Linux shared library unavailable")
    camera = make_camera(
        distort_model=3,
        distort_poly=riley.PolyMap(
            7,
            riley.EPolyMode.displacement,
            np.arange(72, dtype=float).reshape((36, 2)) * 1e-5,
        ),
    )
    riley.save_camera(str(tmp_path), "camera.csv", 0, camera)
    executable = tmp_path / "c_poly_test"
    subprocess.run(
        [
            compiler,
            "-std=c11",
            str(source),
            str(library),
            "-Wl,-rpath," + str(lib_dir),
            "-o",
            str(executable),
        ],
        check=True,
    )
    subprocess.run([str(executable), str(tmp_path)], check=True)


@pytest.mark.parametrize("mode", tuple(riley.EPolyMode))
@pytest.mark.parametrize("subpixel_mode", (0, 1))
@pytest.mark.parametrize("threads", (1, 4))
def test_flat_plate_bc_poly_render_equivalence(
    mode: riley.EPolyMode, subpixel_mode: int, threads: int
) -> None:
    """Exercise the actual raster path, not curved-boundary correctness."""
    from dataclasses import replace

    coords = np.array([[-0.07, -0.06, 0], [0.07, -0.06, 0], [0, 0.06, 0]])
    connect = np.array([[0, 1, 2]], dtype=np.int64)
    convention = riley.ConnectConvention(
        riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY
    )
    shader = riley.FunctionShader(
        builtin=riley.FuncShaderBuiltin.constant,
        params=riley.FuncShaderParams(constant_value=1),
        scaling_type=riley.ScaleStrategy.none,
    )
    mesh = riley.create_mesh(convention, riley.MeshType.tri3, coords, connect, shader)
    camera = riley.Camera(
        pixels_num=(65, 49),
        pixels_size=(0.001, 0.001),
        pos_world=(0, 0, 0.2),
        rot_world=(0, 0, 0),
        roi_cent_world=(0, 0, 0),
        focal_length=0.05,
        sub_sample=2,
        distort_model=1,
        distort_k1=0.2,
        distort_k2=0.05,
        distort_k3=0.01,
        distort_p1=0.003,
        distort_p2=-0.002,
        subpixel_center_map=subpixel_mode,
    )
    coeffs = np.zeros((36, 2))
    coeffs[3:6] = ((-0.006, 0.003), (0.006, -0.004), (-0.002, 0.009))
    coeffs[[6, 8], 0] = 0.2
    coeffs[[7, 9], 1] = 0.2
    coeffs[[15, 17, 19], 0] = (0.05, 0.1, 0.05)
    coeffs[[16, 18, 20], 1] = (0.05, 0.1, 0.05)
    coeffs[[28, 30, 32, 34], 0] = (0.01, 0.03, 0.03, 0.01)
    coeffs[[29, 31, 33, 35], 1] = (0.01, 0.03, 0.03, 0.01)
    if mode == riley.EPolyMode.coordinate:
        coeffs[1, 0] = 1
        coeffs[2, 1] = 1
    poly_camera = replace(
        camera, distort_model=3, distort_poly=riley.PolyMap(7, mode, coeffs)
    )
    config = riley.RasterConfig(
        parallel=threads,
        save_strategy=riley.SaveStrategy.memory,
    )
    config.report = riley.ReportMode.off
    config.background_value = 0
    config.save_scaling = riley.ScaleStrategy.none
    brown_image = riley.raster(mesh, camera, config)
    poly_image = riley.raster(mesh, poly_camera, config)
    assert np.count_nonzero(brown_image) > 100
    assert np.count_nonzero(brown_image == 0) > 100
    np.testing.assert_allclose(poly_image, brown_image, rtol=0, atol=1e-12)
