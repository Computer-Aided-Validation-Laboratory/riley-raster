"""Generate independent OpenCV and NumPy distortion oracle data."""

from __future__ import annotations

import csv
from dataclasses import dataclass
from math import comb
from pathlib import Path

import cv2
import numpy as np
from numpy.polynomial import polynomial as nppoly

MODEL_NONE = 0
MODEL_BROWN = 1
MODEL_BROWN_EXT = 2
MODEL_POLY = 3
MODEL_BROWN_POLY = 4
MODEL_BROWN_EXT_POLY = 5
COEFFS_NUM = 36


@dataclass(slots=True)
class OracleCase:
    """Complete specification for one distortion oracle case."""

    name: str
    model: int
    brown: tuple[float, ...] = (0.0,) * 14
    degree: int = 1
    mode: int = 1
    oracle_brown: bool = False
    ford_u: tuple[float, ...] | None = None
    ford_v: tuple[float, ...] | None = None


def _coeffs(*values: float) -> tuple[float, ...]:
    return tuple(values) + (0.0,) * (COEFFS_NUM - len(values))


def get_cases() -> list[OracleCase]:
    """Return diagnostic cases covering every existing model family."""

    poly_linear_u = _coeffs(1.0e-3, 8.0e-3, -3.0e-3)
    poly_linear_v = _coeffs(-2.0e-3, 4.0e-3, -7.0e-3)
    poly_quad_u = _coeffs(5.0e-4, 6.0e-3, -2.0e-3, 8.0e-3, 1.2e-2, -5.0e-3)
    poly_quad_v = _coeffs(-7.0e-4, 3.0e-3, -5.0e-3, -9.0e-3, 7.0e-3, 1.0e-2)
    poly_cubic_u = _coeffs(
        3.0e-4,
        5.0e-3,
        -2.0e-3,
        7.0e-3,
        -8.0e-3,
        4.0e-3,
        1.1e-2,
        -6.0e-3,
        9.0e-3,
        -5.0e-3,
    )
    poly_cubic_v = _coeffs(
        -4.0e-4,
        2.0e-3,
        -6.0e-3,
        -5.0e-3,
        1.0e-2,
        8.0e-3,
        -7.0e-3,
        5.0e-3,
        -1.2e-2,
        6.0e-3,
    )

    cases = [
        OracleCase("none", MODEL_NONE),
        OracleCase("brown_zero", MODEL_BROWN),
        OracleCase("brown_k1", MODEL_BROWN, (-0.12,) + (0.0,) * 13),
        OracleCase("brown_k2", MODEL_BROWN, (0.0, 0.08) + (0.0,) * 12),
        OracleCase("brown_k3", MODEL_BROWN, (0.0, 0.0, 0.0, 0.0, -0.04) + (0.0,) * 9),
        OracleCase("brown_p1", MODEL_BROWN, (0.0, 0.0, 1.5e-3) + (0.0,) * 11),
        OracleCase("brown_p2", MODEL_BROWN, (0.0, 0.0, 0.0, -2.0e-3) + (0.0,) * 10),
        OracleCase(
            "brown_mixed",
            MODEL_BROWN,
            (-0.11, 0.035, 1.2e-3, -1.7e-3, -0.008) + (0.0,) * 9,
        ),
        OracleCase("brown_ext_zero", MODEL_BROWN_EXT),
        OracleCase(
            "brown_ext_k4",
            MODEL_BROWN_EXT,
            (0.0, 0.0, 0.0, 0.0, 0.0, 0.07) + (0.0,) * 8,
        ),
        OracleCase(
            "brown_ext_k5",
            MODEL_BROWN_EXT,
            (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -0.04) + (0.0,) * 7,
        ),
        OracleCase(
            "brown_ext_k6",
            MODEL_BROWN_EXT,
            (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.025) + (0.0,) * 6,
        ),
        OracleCase(
            "brown_ext_mixed",
            MODEL_BROWN_EXT,
            (-0.10, 0.03, 1.1e-3, -1.6e-3, -0.007, 0.045, -0.018, 0.006) + (0.0,) * 6,
        ),
        OracleCase(
            "brown_ext_s1", MODEL_BROWN_EXT, (0.0,) * 8 + (2.0e-3,) + (0.0,) * 5
        ),
        OracleCase(
            "brown_ext_s2", MODEL_BROWN_EXT, (0.0,) * 9 + (-1.5e-3,) + (0.0,) * 4
        ),
        OracleCase(
            "brown_ext_s3", MODEL_BROWN_EXT, (0.0,) * 10 + (1.7e-3,) + (0.0,) * 3
        ),
        OracleCase(
            "brown_ext_s4", MODEL_BROWN_EXT, (0.0,) * 11 + (-1.2e-3,) + (0.0,) * 2
        ),
        OracleCase("brown_ext_tau_x", MODEL_BROWN_EXT, (0.0,) * 12 + (0.035, 0.0)),
        OracleCase("brown_ext_tau_y", MODEL_BROWN_EXT, (0.0,) * 12 + (0.0, -0.052)),
        OracleCase(
            "brown_ext_full14",
            MODEL_BROWN_EXT,
            (
                -0.10,
                0.03,
                1.1e-3,
                -1.6e-3,
                -0.007,
                0.045,
                -0.018,
                0.006,
                1.8e-3,
                -1.1e-3,
                1.4e-3,
                -9.0e-4,
                0.031,
                -0.047,
            ),
        ),
        OracleCase(
            "poly_linear",
            MODEL_POLY,
            degree=1,
            ford_u=poly_linear_u,
            ford_v=poly_linear_v,
        ),
        OracleCase(
            "poly_quadratic",
            MODEL_POLY,
            degree=2,
            ford_u=poly_quad_u,
            ford_v=poly_quad_v,
        ),
        OracleCase(
            "poly_cubic",
            MODEL_POLY,
            degree=3,
            ford_u=poly_cubic_u,
            ford_v=poly_cubic_v,
        ),
        OracleCase(
            "brown_poly",
            MODEL_BROWN_POLY,
            (-0.09, 0.025, 9.0e-4, -1.3e-3, -0.006) + (0.0,) * 9,
            degree=3,
            ford_u=poly_cubic_u,
            ford_v=poly_cubic_v,
        ),
        OracleCase(
            "brown_ext_poly",
            MODEL_BROWN_EXT_POLY,
            (-0.08, 0.02, 8.0e-4, -1.1e-3, -0.005, 0.035, -0.012, 0.004) + (0.0,) * 6,
            degree=2,
            ford_u=poly_quad_u,
            ford_v=poly_quad_v,
        ),
        OracleCase(
            "brown_ext_full14_poly",
            MODEL_BROWN_EXT_POLY,
            (
                -0.08,
                0.02,
                8.0e-4,
                -1.1e-3,
                -0.005,
                0.035,
                -0.012,
                0.004,
                1.5e-3,
                -8.0e-4,
                1.2e-3,
                -7.0e-4,
                0.027,
                -0.041,
            ),
            degree=3,
            ford_u=poly_cubic_u,
            ford_v=poly_cubic_v,
        ),
    ]

    powers: list[tuple[int, int]] = []
    for degree in range(8):
        for py in range(degree + 1):
            powers.append((degree - py, py))
    for output_name in ("u", "v"):
        for coeff_idx, (power_x, power_y) in enumerate(powers):
            degree = max(1, power_x + power_y)
            for mode in (0, 1):
                values_u = np.zeros(COEFFS_NUM)
                values_v = np.zeros(COEFFS_NUM)
                if mode == 0:
                    values_u[1] = 1
                    values_v[2] = 1
                values = values_u if output_name == "u" else values_v
                values[coeff_idx] += 7.0e-3
                cases.append(
                    OracleCase(
                        f"poly_basis_{output_name}_{power_x}_{power_y}_{mode}",
                        MODEL_POLY,
                        degree=degree,
                        mode=mode,
                        ford_u=tuple(values_u),
                        ford_v=tuple(values_v),
                    )
                )
    rng = np.random.default_rng(72491)
    for degree in range(1, 8):
        count = (degree + 1) * (degree + 2) // 2
        for mode in (0, 1):
            for model in (MODEL_POLY, MODEL_BROWN_POLY, MODEL_BROWN_EXT_POLY):
                cu = np.zeros(COEFFS_NUM)
                cv = np.zeros(COEFFS_NUM)
                cu[:count] = rng.uniform(-0.002, 0.002, count)
                cv[:count] = rng.uniform(-0.002, 0.002, count)
                if mode == 0:
                    cu[1] += 1
                    cv[2] += 1
                brown = (0.0,) * 14
                if model != MODEL_POLY:
                    brown = (
                        -0.08,
                        0.02,
                        8e-4,
                        -1.1e-3,
                        -0.005,
                        0.035,
                        -0.012,
                        0.004,
                        1.5e-3,
                        -8e-4,
                        1.2e-3,
                        -7e-4,
                        0.027,
                        -0.041,
                    )
                if model == MODEL_BROWN_POLY:
                    brown = brown[:5] + (0.0,) * 9
                cases.append(
                    OracleCase(
                        f"dense_{degree}_{mode}_{model}",
                        model,
                        brown,
                        degree=degree,
                        mode=mode,
                        ford_u=tuple(cu),
                        ford_v=tuple(cv),
                    )
                )
    equivalent_cases = [
        (2, (0, 0, 0.003, -0.002, 0) + (0,) * 9),
        (3, (-0.05, 0, 0, 0, 0) + (0,) * 9),
        (5, (0, 0.02, 0, 0, 0) + (0,) * 9),
        (7, (0, 0, 0, 0, -0.01) + (0,) * 9),
        (7, (-0.05, 0.02, 0.003, -0.002, -0.01) + (0,) * 9),
        (
            7,
            (
                -0.05,
                0.02,
                0.003,
                -0.002,
                -0.01,
                0,
                0,
                0,
                0.001,
                -0.002,
                -0.003,
                0.001,
                0,
                0,
            ),
        ),
    ]
    for case_id, (degree, brown) in enumerate(equivalent_cases):
        for mode in (0, 1):
            cu = np.zeros(COEFFS_NUM)
            cv = np.zeros(COEFFS_NUM)
            if mode == 0:
                cu[1] = 1
                cv[2] = 1
            k1, k2, p1, p2, k3 = brown[:5]
            cu[3:6] = (3 * p2 + brown[8], 2 * p1, p2 + brown[8])
            cv[3:6] = (p1 + brown[10], 2 * p2, 3 * p1 + brown[10])
            for index, factor in zip((10, 12, 14), (1, 2, 1)):
                cu[index] = factor * brown[9]
                cv[index] = factor * brown[11]
            for radial_degree, coefficient in enumerate((k1, k2, k3), 1):
                total = 2 * radial_degree + 1
                start = total * (total + 1) // 2
                for mm in range(radial_degree + 1):
                    cu[start + 2 * mm] = coefficient * comb(radial_degree, mm)
                    cv[start + 2 * mm + 1] = coefficient * comb(radial_degree, mm)
            cases.append(
                OracleCase(
                    f"bc_equivalent_{case_id}_{mode}",
                    MODEL_POLY,
                    brown,
                    degree=degree,
                    mode=mode,
                    oracle_brown=True,
                    ford_u=tuple(cu),
                    ford_v=tuple(cv),
                )
            )
    return cases


def get_points() -> np.ndarray:
    """Return a compact asymmetric sample of a wide normalized field."""

    x_values = np.array([-0.80, -0.57, -0.29, 0.0, 0.23, 0.51, 0.80])
    y_values = np.array([-0.60, -0.33, -0.11, 0.17, 0.39, 0.60])
    grid_x, grid_y = np.meshgrid(x_values, y_values)
    grid = np.column_stack((grid_x.ravel(), grid_y.ravel()))
    diagnostic = np.array(
        [
            [0.0, 0.0],
            [0.71, -0.23],
            [-0.37, 0.53],
            [0.12, -0.49],
            [-0.73, 0.08],
            [0.63, 0.44],
            [-0.19, -0.56],
            [0.79, 0.31],
            [-0.61, -0.41],
            [0.42, -0.52],
            [-0.48, 0.27],
            [0.06, 0.58],
        ]
    )
    return np.vstack((grid, diagnostic))


def _coefficient_matrix(coefficients: tuple[float, ...], degree: int) -> np.ndarray:
    matrix = np.zeros((degree + 1, degree + 1), dtype=np.float64)
    index = 0
    for total in range(degree + 1):
        for py in range(total + 1):
            matrix[total - py, py] = coefficients[index]
            index += 1
    return matrix


def evaluate_poly(
    points: np.ndarray,
    coefficients_u: tuple[float, ...],
    coefficients_v: tuple[float, ...],
    degree: int,
    mode: int,
) -> np.ndarray:
    """Evaluate an identity-plus-displacement polynomial using NumPy."""

    matrix_u = _coefficient_matrix(coefficients_u, degree)
    matrix_v = _coefficient_matrix(coefficients_v, degree)
    x = points[:, 0]
    y = points[:, 1]
    return np.column_stack(
        (
            (x if mode == 1 else 0) + nppoly.polyval2d(x, y, matrix_u),
            (y if mode == 1 else 0) + nppoly.polyval2d(x, y, matrix_v),
        )
    )


def evaluate_poly_jacobian(case: OracleCase, points: np.ndarray) -> np.ndarray:
    """Evaluate polynomial Jacobians using NumPy's analytic derivatives."""

    matrix_u = _coefficient_matrix(case.ford_u or (0.0,) * COEFFS_NUM, case.degree)
    matrix_v = _coefficient_matrix(case.ford_v or (0.0,) * COEFFS_NUM, case.degree)
    du_dx = nppoly.polyder(matrix_u, axis=0)
    du_dy = nppoly.polyder(matrix_u, axis=1)
    dv_dx = nppoly.polyder(matrix_v, axis=0)
    dv_dy = nppoly.polyder(matrix_v, axis=1)
    x = points[:, 0]
    y = points[:, 1]
    jac = np.empty((points.shape[0], 2, 2), dtype=np.float64)
    jac[:, 0, 0] = float(case.mode == 1) + nppoly.polyval2d(x, y, du_dx)
    jac[:, 0, 1] = nppoly.polyval2d(x, y, du_dy)
    jac[:, 1, 0] = nppoly.polyval2d(x, y, dv_dx)
    jac[:, 1, 1] = float(case.mode == 1) + nppoly.polyval2d(x, y, dv_dy)
    return jac


def evaluate_brown(case: OracleCase, points: np.ndarray) -> np.ndarray:
    """Evaluate Brown-Conrady using OpenCV projectPoints."""

    object_points = np.column_stack((points, np.ones(points.shape[0])))
    projected, _ = cv2.projectPoints(
        object_points,
        np.zeros(3),
        np.zeros(3),
        np.eye(3),
        np.asarray(case.brown, dtype=np.float64),
    )
    return projected.reshape((-1, 2))


def evaluate_case(case: OracleCase, points: np.ndarray) -> np.ndarray:
    """Evaluate one complete forward distortion case independently."""

    if case.oracle_brown:
        return evaluate_brown(case, points)
    values = points
    if case.model in (
        MODEL_BROWN,
        MODEL_BROWN_EXT,
        MODEL_BROWN_POLY,
        MODEL_BROWN_EXT_POLY,
    ):
        values = evaluate_brown(case, values)
    if case.model in (MODEL_POLY, MODEL_BROWN_POLY, MODEL_BROWN_EXT_POLY):
        if case.ford_u is not None and case.ford_v is not None:
            values = evaluate_poly(
                values, case.ford_u, case.ford_v, case.degree, case.mode
            )
        else:
            raise ValueError(f"missing polynomial map for {case.name}")
    return values.copy()


def evaluate_numerical_jacobian(case: OracleCase, points: np.ndarray) -> np.ndarray:
    """Differentiate the complete independent map by central differences."""

    step = 1.0e-6
    jac = np.empty((points.shape[0], 2, 2), dtype=np.float64)
    for axis in range(2):
        offset = np.zeros_like(points)
        offset[:, axis] = step
        derivative = (
            evaluate_case(case, points + offset) - evaluate_case(case, points - offset)
        ) / (2.0 * step)
        jac[:, :, axis] = derivative
    return jac


def _manifest_row(case_id: int, case: OracleCase) -> list[float | int]:
    ford_u = case.ford_u or (0.0,) * COEFFS_NUM
    ford_v = case.ford_v or (0.0,) * COEFFS_NUM
    return [
        case_id,
        case.model,
        case.degree,
        case.mode,
        *case.brown,
        *np.column_stack((ford_u, ford_v)).ravel(),
    ]


def generate_distort_oracles(gold_root: Path) -> list[Path]:
    """Generate compact committed distortion oracle CSV files."""

    gold_root.mkdir(parents=True, exist_ok=True)
    cases_path = gold_root / "distortion_oracle_cases.csv"
    points_path = gold_root / "distortion_oracle_points.csv"
    jacobians_path = gold_root / "distortion_oracle_jacobians.csv"
    cases = get_cases()
    points = get_points()
    jacobian_points = points[::5]

    with cases_path.open("w", newline="") as out_file:
        writer = csv.writer(out_file, lineterminator="\n")
        for case_id, case in enumerate(cases):
            writer.writerow(_manifest_row(case_id, case))

    with points_path.open("w", newline="") as out_file:
        writer = csv.writer(out_file, lineterminator="\n")
        for case_id, case in enumerate(cases):
            observed = evaluate_case(case, points)
            recovered = points
            for point_id, (ideal, distorted, inv) in enumerate(
                zip(points, observed, recovered)
            ):
                writer.writerow([case_id, point_id, *ideal, *distorted, *inv])

    with jacobians_path.open("w", newline="") as out_file:
        writer = csv.writer(out_file, lineterminator="\n")
        for case_id, case in enumerate(cases):
            if (
                case.model == MODEL_POLY
                and case.ford_u is not None
                and not case.oracle_brown
            ):
                jacobians = evaluate_poly_jacobian(case, jacobian_points)
            else:
                jacobians = evaluate_numerical_jacobian(case, jacobian_points)
            for point_id, (ideal, jac) in enumerate(zip(jacobian_points, jacobians)):
                writer.writerow([case_id, point_id, *ideal, *jac.ravel()])

    return [cases_path, points_path, jacobians_path]
