#!/usr/bin/env python3
"""Generate the offline Bernoulli coverage table; --check never writes.

Integrates analytic circle/rectangle areas on the reflected quadrant [0, 0.5]^2.
The first row is analytic; M1 = pi*r*r is not stored. See dev/THEORY.md for the
model and scripts/tests/test_speckle_coverage.py for independent reference tests.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
import math
from pathlib import Path
import re

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
TABLE_PATH = ROOT / "src/riley/zig/specklecoveragecoeffs.zig"
INTERVALS = 128
ORDER = 256
# Allow quadrature/reduction roundoff across NumPy versions and CPU dispatch.
# Eight stored terms bound node coverage drift by 8*CHECK_ATOL for p in [0, 1],
# far below the independent model acceptance tolerance of 1e-6.
CHECK_ATOL = 1e-12


@lru_cache(maxsize=None)
def rule(order: int) -> tuple[np.ndarray, np.ndarray]:
    nodes, weights = np.polynomial.legendre.leggauss(order)
    return (nodes + 1.0) * 0.25, weights * 0.5


def small_coefficients(radius: float) -> np.ndarray:
    r = radius
    return np.array([
        math.pi * r * r,
        -(256 / 45 * r**5 - math.pi / 2 * r**6),
        (68 / 27 + math.pi**2 / 192) * r**8,
        -(3 * math.pi**3 / 256 - 421 * math.pi / 17280) * r**10,
        0.0, 0.0, 0.0, 0.0, 0.0,
    ])


def primitive(x: np.ndarray, radius: float) -> np.ndarray:
    x = np.clip(x, -radius, radius)
    return 0.5 * (x * np.sqrt(np.maximum(0, radius**2 - x*x))
                  + radius**2 * np.arcsin(x / radius))


def signed_area(x: np.ndarray, y: np.ndarray, radius: float) -> np.ndarray:
    a = np.minimum(np.abs(x), radius)
    b = np.minimum(np.abs(y), radius)
    t = np.minimum(a, np.sqrt(np.maximum(0, radius**2 - b*b)))
    return np.sign(x) * np.sign(y) * (b*t + primitive(a, radius) - primitive(t, radius))


def cell_areas(radius: float, order: int) -> list[np.ndarray]:
    nodes, _ = rule(order)
    x, y = nodes[:, None], nodes[None, :]
    # Shared corners avoid repeating transcendental evaluations for nine cells.
    corners = {(i, j): signed_area(i-x, j-y, radius)
               for i in range(-1, 3) for j in range(-1, 3)}
    return [np.clip(corners[i+1, j+1] - corners[i, j+1]
                    - corners[i+1, j] + corners[i, j], 0, 1)
            for i in range(-1, 2) for j in range(-1, 2)]


def integrate_coefficients(radius: float, order: int = ORDER) -> np.ndarray:
    if radius <= 0.5:
        return small_coefficients(radius)
    _, weights = rule(order)
    e = np.zeros((10, order, order))
    e[0] = 1
    for seen, area in enumerate(cell_areas(radius, order), 1):
        for k in range(seen, 0, -1):
            e[k] += area * e[k-1]
    result = np.sum(e[1:] * (weights[:, None] * weights[None, :]), axis=(1, 2))
    result[1::2] *= -1
    result[0] = math.pi * radius * radius
    return result


def generate_table() -> np.ndarray:
    rule(ORDER)
    with ThreadPoolExecutor() as pool:
        return np.array(list(pool.map(integrate_coefficients,
                                     np.linspace(0.5, 1, INTERVALS + 1))))


def monotonicity_margin(table: np.ndarray) -> float:
    """Positive Bernstein coefficients certify increasing F(p,r)/p at all nodes."""
    differences = np.diff(table, axis=0)
    bernstein = np.zeros_like(differences)
    degree = table.shape[1] - 1  # F/p has degree eight; F has degree nine.
    for k in range(degree + 1):
        for j in range(k+1):
            bernstein[:, k] += differences[:, j] * math.comb(k, j) / math.comb(degree, j)
    margin = float(np.min(bernstein))
    if margin <= 0:
        raise ValueError(f"nonmonotone table: Bernstein margin {margin}")
    return margin


def read_table(path: Path = TABLE_PATH) -> np.ndarray:
    """Read typed coefficients on the model's fixed uniform radius grid [0.5, 1]."""
    source = path.read_text(encoding="ascii")
    declaration = re.search(
        r"pub\s+const\s+coefficients\s*=\s*\[(\d+)\]\s*\[(\d+)\]f64\s*\{(.*?)\};",
        source, re.DOTALL)
    if (declaration is None
            or (int(declaration[1]), int(declaration[2])) != (INTERVALS + 1, 8)):
        raise ValueError("Coefficient table type or shape differs from the model")
    rows = re.findall(r"\.\{([^{}]*)\}", declaration[3])
    try:
        stored = np.array([[float(v.strip()) for v in row.split(",") if v.strip()]
                           for row in rows], dtype=np.float64)
    except ValueError as exc:
        raise ValueError("Invalid coefficient payload") from exc
    if stored.shape != (INTERVALS + 1, 8) or not np.all(np.isfinite(stored)):
        raise ValueError("Invalid coefficient payload")
    radii = np.linspace(0.5, 1, INTERVALS + 1)
    return np.column_stack(((math.pi * radii) * radii, stored))


def check_table(table: np.ndarray, path: Path = TABLE_PATH) -> float:
    """Compare numbers and typed shape; row order fixes radius nodes on [0.5, 1]."""
    stored = read_table(path)
    if table.shape != stored.shape or not np.all(np.isfinite(table)):
        raise ValueError("Invalid regenerated coefficient shape or values")
    difference = float(np.max(np.abs(table - stored)))
    if difference > CHECK_ATOL:
        raise ValueError(f"Coefficient difference {difference:.3e} exceeds {CHECK_ATOL:.1e}; "
                         "regenerate and review the numerical change")
    return difference


def emit_table(table: np.ndarray) -> str:
    stored = table[:, 1:]
    rows, columns = stored.shape
    lines = [
        "//! Generated by scripts/generate_speckle_coverage.py; do not edit.",
        f"//! {ORDER} Gauss-Legendre nodes per axis on [0, 0.5]^2; first row analytic.",
        f"//! {rows} radius nodes r = 0.5 + i/{2 * INTERVALS}; signed M2..M{columns + 1}, M1 = pi*r*r.",
        f"//! Numeric payload: {rows} * {columns} * {stored.itemsize} = {stored.nbytes} bytes. No build-time generation.",
        f"//! Check numerically (absolute {CHECK_ATOL:.0e}): .venv/bin/python scripts/generate_speckle_coverage.py --check",
        f"//! At p in [0, 1], {columns} stored terms allow at most {columns * CHECK_ATOL:.0e} node coverage drift.",
        "//! Independent references: scripts/tests/test_speckle_coverage.py (1e-6 absolute).",
        f"pub const coefficients = [{rows}][{columns}]f64{{",
    ]
    for row in table:
        lines.append("    .{ " + ", ".join(f"{value:.17e}" for value in row[1:]) + " },")
    return "\n".join(lines + ["};", ""])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="regenerate and compare without writing")
    args = parser.parse_args()
    table = generate_table()
    monotonicity_margin(table)
    if args.check:
        try:
            difference = check_table(table)
        except ValueError as exc:
            raise SystemExit(str(exc)) from exc
        print(f"Coefficients agree: max absolute difference {difference:.3e} "
              f"(limit {CHECK_ATOL:.1e}); typed shape and fixed-grid node ordering match")
    else:
        TABLE_PATH.write_text(emit_table(table), encoding="ascii")


if __name__ == "__main__":
    main()
