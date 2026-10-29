#include "../riley/cython/riley.h"
#include <assert.h>
#include <stddef.h>

_Static_assert(sizeof(((CDistort *)0)->distort_poly_coeffs_len) == sizeof(size_t),
               "coefficient length must be size_t");
_Static_assert(sizeof(((CDistort *)0)->distort_poly_coeffs) == sizeof(const double *),
               "coefficients must be a borrowed pointer");

int main(int argc, char **argv) {
    assert(argc == 2);
    CCameraInput camera;
    assert(rileyLoadCamera(argv[1], "camera.csv", NULL, 0, &camera) == 0);
    assert(camera.distort.distort_poly_coeffs == NULL);
    assert(camera.distort.distort_poly_coeffs_len == 72);
    double coeffs[72];
    assert(rileyLoadCamera(argv[1], "camera.csv", coeffs, 71, &camera) != 0);
    assert(rileyLoadCamera(argv[1], "camera.csv", NULL, 72, &camera) != 0);
    assert(rileyLoadCamera(argv[1], "camera.csv", coeffs, 72, &camera) == 0);
    assert(camera.distort.distort_poly_coeffs == coeffs);
    assert(coeffs[71] > 0.00070 && coeffs[71] < 0.00072);
    /* The loader's arena is gone. Reuse the caller storage in another C call. */
    assert(rileySaveCamera(argv[1], "from_c.csv", 0, &camera) == 0);
    camera.distort.distort_poly_coeffs = NULL;
    assert(rileySaveCamera(argv[1], "bad.csv", 0, &camera) != 0);
    return 0;
}
