#include <stddef.h>
#include "../riley/cython/riley.h"

_Static_assert(sizeof(((CDistort *)0)->distort_poly_u) == 10 * sizeof(double),
               "polynomial u coefficient count");
_Static_assert(sizeof(((CDistort *)0)->distort_poly_v) == 10 * sizeof(double),
               "polynomial v coefficient count");
_Static_assert(offsetof(CDistort, distort_poly_v) ==
                   offsetof(CDistort, distort_poly_u) + 10 * sizeof(double),
               "polynomial coefficient arrays must be contiguous");
_Static_assert(sizeof(CDistort) ==
                   offsetof(CDistort, distort_poly_v) + 10 * sizeof(double),
               "no inverse polynomial fields in the ABI");
