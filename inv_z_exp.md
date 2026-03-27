# Perspective Interpolation vs. Shape Function Mapping

The question is whether element attributes (like UVs or Normals) need the $1/z$ perspective weighting when using higher-order kernels and a Newton-Raphson solver.

### The Short Answer
**No, they do not.** If we have already solved for the "true" parametric coordinates $(\xi, \eta)$ that project to a specific pixel $(x, y)$, then any attribute $A$ defined at the nodes should be interpolated linearly in parametric space using the shape functions:
$$ A(x, y) = \sum_{i=1}^N N_i(\xi, \eta) \cdot A_i $$

### The Long Explanation
In standard triangle rasterization, we interpolate barycentric coordinates linearly in *screen space*. However, because of the perspective projection, a linear step in screen space does not correspond to a linear step on the 3D triangle surface. This is why we must use the $1/z$ trick:
1. Interpolate $A_i/z_i$ linearly in screen space.
2. Interpolate $1/z_i$ linearly in screen space.
3. Divide the two to get the perspective-correct attribute: $A = (\sum w_i A_i / z_i) / (\sum w_i / z_i)$.

**Our Newton Solver Approach:**
Our Newton solver solves the equation:
$$ \sum_{i=1}^N N_i(\xi, \eta) \cdot (X_{pixel} \cdot W_i - X_i) = 0 $$
where $W_i$ is the perspective weight (often $1/z$ or similar depending on the projection).

By solving this equation directly, we find the exact $(\xi, \eta)$ on the 3D element surface that projects to the pixel. Since the mapping from $(\xi, \eta)$ to the surface attributes is already defined by the shape functions $N_i$ in the element's "local" space, we simply evaluate the shape functions at the converged $(\xi, \eta)$. 

### Summary of Implementations
- **`.raster` Coordinate Space**: This is essentially standard rasterization. It uses linear interpolation in screen space and **requires** the $1/z$ perspective correction for attributes.
- **`.clip_px_leng` Coordinate Space**: This space is used by our higher-order kernels (Tri6, Quad8, etc.). The solver finds the "true" surface coordinates. Therefore, attributes should be interpolated **linearly** using the shape functions $N_i$ without any $1/z$ weighting.

**Correction applied during implementation:**
During the initial SIMD implementation, I incorrectly applied perspective correction (weighting by $1/z$) to kernels using the `.clip_px_leng` space. This was causing a mismatch against the baseline. I have since corrected this by implementing `fillFlatSIMD` and `fillTexSIMD`, which use linear shape function interpolation for these kernels.
