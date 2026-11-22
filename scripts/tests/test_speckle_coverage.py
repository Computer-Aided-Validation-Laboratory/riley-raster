"""Offline coefficient and independent geometry/probability regression tests."""
from concurrent.futures import ThreadPoolExecutor
import math
from pathlib import Path
import tempfile
import unittest

import numpy as np

from scripts import generate_speckle_coverage as coverage


def slice_cell_area(x0: np.ndarray, y0: np.ndarray, radius: float) -> np.ndarray:
    """Integrate vertical circle slices, split at rectangle-edge crossings.

    Independent of the generator's quadrant inclusion/exclusion algorithm.
    Each interval's clipped height is a*sqrt(r*r-x*x) + b.
    """
    x0, y0 = np.broadcast_arrays(x0, y0)
    lo, hi = np.maximum(x0, -radius), np.minimum(x0+1, radius)
    crossings = [lo, np.maximum(lo, hi)]
    for edge in (y0, y0+1):
        cross = np.sqrt(np.maximum(0, radius**2 - edge*edge))
        crossings.extend((np.clip(-cross, lo, np.maximum(lo, hi)),
                          np.clip(cross, lo, np.maximum(lo, hi))))
    bounds = np.sort(np.stack(crossings), axis=0)
    area = np.zeros_like(x0)

    def primitive(x):
        x = np.clip(x, -radius, radius)
        h = np.sqrt(np.maximum(0, radius**2 - x*x))
        return 0.5 * (x*h + radius**2 * np.arctan2(x, h))

    for a, b in zip(bounds[:-1], bounds[1:]):
        mid = (a+b)*0.5
        height = np.sqrt(np.maximum(0, radius**2 - mid*mid))
        upper_arc, lower_arc = height < y0+1, -height > y0
        coefficient = upper_arc.astype(float) + lower_arc.astype(float)
        constant = np.where(upper_arc, 0, y0+1) - np.where(lower_arc, 0, y0)
        active = np.minimum(y0+1, height) > np.maximum(y0, -height)
        area += np.where(active, coefficient*(primitive(b) - primitive(a))
                         + constant*(b-a), 0)
    return np.clip(area, 0, 1)


def reference_coverages(radius: float, occupancies: np.ndarray,
                        order: int = 512) -> np.ndarray:
    nodes, weights = coverage.rule(order)
    x, y = nodes[:, None], nodes[None, :]
    # Direct probabilities, not the occupancy polynomial. Preserve dilute coverage.
    log_uncovered = np.zeros((len(occupancies), order, order))
    for i in range(-1, 2):
        for j in range(-1, 2):
            area = slice_cell_area(i-x, j-y, radius)
            with np.errstate(divide="ignore"):
                log_uncovered += np.log1p(-occupancies[:, None, None] * area)
    return np.sum(-np.expm1(log_uncovered) * weights[:, None] * weights[None, :],
                  axis=(1, 2))


def lookup_coverages(table: np.ndarray, radius: float, occupancies: np.ndarray) -> np.ndarray:
    """Test-side Hermite-basis evaluation; native frozen references test Zig itself."""
    if radius <= 0.5:
        return occupancies * np.polynomial.polynomial.polyval(
            occupancies, coverage.small_coefficients(radius))
    u = (radius - 0.5) * (2 * coverage.INTERVALS)
    index = min(int(u), coverage.INTERVALS - 1)
    t = u - index
    values = occupancies * np.polynomial.polynomial.polyval(occupancies, table.T)
    delta = np.diff(values, axis=0)
    left = (np.clip((3*delta[0] - delta[1])/2, 0, 3*delta[0]) if index == 0
            else 2*delta[index-1]*delta[index]/(delta[index-1] + delta[index]))
    right = (np.clip((3*delta[-1] - delta[-2])/2, 0, 3*delta[-1])
             if index == coverage.INTERVALS - 1
             else 2*delta[index]*delta[index+1]/(delta[index] + delta[index+1]))
    return ((2*t**3 - 3*t**2 + 1)*values[index]
            + (t**3 - 2*t**2 + t)*left
            + (-2*t**3 + 3*t**2)*values[index+1] + (t**3 - t**2)*right)


class SpeckleCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.table = coverage.read_table()

    def test_model_shape_and_analytic_first_row(self):
        # F/p has degree eight; its ninth coefficient M1 is analytic, not stored.
        self.assertEqual(self.table.shape, (coverage.INTERVALS + 1, 9))
        np.testing.assert_array_equal(self.table[0], coverage.small_coefficients(0.5))

    def test_check_accepts_roundoff_but_rejects_changed_coefficients_and_order(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "coefficients.zig"
            original = coverage.emit_table(self.table)
            path.write_text(original, encoding="ascii")
            perturbed = self.table.copy()
            perturbed[1, 1] += 1e-14
            self.assertLessEqual(coverage.check_table(perturbed, path), coverage.CHECK_ATOL)
            # Simultaneous same-sign drift in all eight stored terms is worst at p=1.
            allowed = self.table.copy()
            allowed[:, 1:] += 0.99 * coverage.CHECK_ATOL
            self.assertLessEqual(coverage.check_table(allowed, path), coverage.CHECK_ATOL)
            node_drift = np.max(np.abs(np.sum(allowed - self.table, axis=1)))
            self.assertLessEqual(node_drift, 8 * coverage.CHECK_ATOL)
            perturbed[1, 1] += 1e-9
            with self.assertRaisesRegex(ValueError, "exceeds"):
                coverage.check_table(perturbed, path)
            self.assertEqual(path.read_text(encoding="ascii"), original)  # No writes.
            path.write_text(coverage.emit_table(self.table[::-1]), encoding="ascii")
            with self.assertRaisesRegex(ValueError, "exceeds"):
                coverage.check_table(self.table, path)
            path.write_text(original.replace(f"[{coverage.INTERVALS + 1}][8]f64",
                                             "[2][8]f64"), encoding="ascii")
            with self.assertRaisesRegex(ValueError, "type or shape"):
                coverage.check_table(self.table, path)
            path.write_text(original, encoding="ascii")
            for invalid in (self.table[:-1], np.full_like(self.table, np.nan)):
                with self.assertRaisesRegex(ValueError, "shape or values"):
                    coverage.check_table(invalid, path)

    def test_read_table_checks_type_without_prose_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "coefficients.zig"
            source = "\n".join(line for line in coverage.emit_table(self.table).splitlines()
                               if not line.startswith("//"))
            path.write_text(source, encoding="ascii")
            self.assertEqual(coverage.check_table(self.table, path), 0)
            path.write_text(source.replace("][8]f64", "][8]f32"), encoding="ascii")
            with self.assertRaisesRegex(ValueError, "type or shape"):
                coverage.read_table(path)

    def test_read_table_rejects_invalid_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "coefficients.zig"
            source = coverage.emit_table(self.table)
            first = f"{self.table[0, 1]:.17e}"
            for malformed in (source.replace(first + ", ", "", 1),
                              source.replace(first, "nan", 1),
                              source.replace(first, "not_a_number", 1)):
                path.write_text(malformed, encoding="ascii")
                with self.assertRaisesRegex(ValueError, "Invalid coefficient payload"):
                    coverage.read_table(path)

    def test_exact_areas_partition_disk(self):
        for radius in (0.1, 0.5, 1/math.sqrt(2), 1.0):
            areas = coverage.cell_areas(radius, 24)
            np.testing.assert_allclose(sum(areas), math.pi*radius*radius,
                                       rtol=0, atol=3e-15)
            self.assertTrue(all(np.all((a >= 0) & (a <= 1)) for a in areas))

    def test_independent_circle_rectangle_algorithms(self):
        for radius in (0.01, 0.3, 0.5, 0.50001, 1/math.sqrt(2), 0.99999, 1):
            nodes, _ = coverage.rule(19)
            x, y = nodes[:, None], nodes[None, :]
            areas = coverage.cell_areas(radius, 19)
            for area, (i, j) in zip(areas, ((i, j) for i in range(-1, 2)
                                          for j in range(-1, 2))):
                ref = slice_cell_area(i-x, j-y, radius)
                # Independent asin/atan2 primitives round differently near tangencies.
                np.testing.assert_allclose(area, ref, rtol=0, atol=2e-14)

    def test_small_radius_integrated_formula_against_direct_probability(self):
        occupancies = np.array([1e-8, 0.01, 0.5, 1.0])
        for radius in (0.01, 0.1, 0.3, 0.5):
            ref = reference_coverages(radius, occupancies, order=192)
            actual = occupancies * np.polynomial.polynomial.polyval(
                occupancies, coverage.small_coefficients(radius))
            np.testing.assert_allclose(actual, ref, rtol=2e-7, atol=1e-10)

    def test_node_monotonicity_all_occupancies(self):
        # Runtime interpolation/inversion are exercised by the Zig module's tests.
        self.assertGreater(coverage.monotonicity_margin(self.table), 0)
        broken = self.table.copy()
        broken[1] = broken[0]-1
        with self.assertRaisesRegex(ValueError, "nonmonotone"):
            coverage.monotonicity_margin(broken)

    def test_nodes_and_interpolation_against_higher_order_independent_probability(self):
        occupancies = np.array([1e-8, 0.01, 0.1, 0.25, 0.5, 0.75, 1.0])
        # This Python PCHIP copy tests the table, not the native implementation.
        # Quarter/midpoints span the domain, both geometry breaks and the cap;
        # unlike source regeneration, the higher-order oracle sees node error.
        indices = sorted({0, 1, 52, 53, 54, 127, 128}
                         | {i + t for i in (0, 1, 32, 52, 53, 54, 96, 127)
                            for t in (0.25, 0.5, 0.75)})
        radii = [0.5 + i/(2 * coverage.INTERVALS) for i in indices]
        radii += [math.nextafter(0.5, math.inf), 1/math.sqrt(2)]
        coverage.rule(512)
        with ThreadPoolExecutor() as pool:
            refs = list(pool.map(lambda r: reference_coverages(r, occupancies), radii))
        for radius, ref in zip(radii, refs):
            actual = lookup_coverages(self.table, radius, occupancies)
            np.testing.assert_allclose(actual, ref, rtol=0, atol=1e-6,
                                       err_msg=f"radius={radius:.17g}")
        self.assertAlmostEqual(np.sum(self.table[-1]), 0.999498286229077, delta=2e-10)

    def test_higher_order_reference_convergence(self):
        occupancies = np.array([0.5, 1.0])
        for radius in (0.5009765625, 1/math.sqrt(2), 1.0):
            np.testing.assert_allclose(reference_coverages(radius, occupancies, order=768),
                                       reference_coverages(radius, occupancies, order=512),
                                       rtol=0, atol=2e-8)

    def test_generated_node_coefficients_against_checked_in_source(self):
        for index in (1, 53, coverage.INTERVALS):
            regenerated = coverage.integrate_coefficients(
                0.5 + index/(2 * coverage.INTERVALS))
            np.testing.assert_allclose(regenerated, self.table[index],
                                       rtol=0, atol=coverage.CHECK_ATOL)


if __name__ == "__main__":
    unittest.main()
