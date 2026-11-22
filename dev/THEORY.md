# Riley Mathematical Theory and Implementation Notes

This document collects mathematical formulations, camera models, coordinate systems, and architectural design notes for the Riley rasterisation engine.

---

## 1. Camera Models and Coordinate Systems

### Coordinate Systems

Riley natively operates in a right-handed camera coordinate frame matching OpenGL/computer graphics conventions:
- $+X$: Right across the sensor
- $+Y$: Up across the sensor
- $+Z$: Backwards (camera looks down $-Z$)

When interacting with computer vision pipelines (such as OpenCV):
- $+X$: Right across the sensor
- $+Y$: Down across the sensor
- $+Z$: Forwards (camera looks down $+Z$)

The `CameraCoordSys` enum (`.opengl` and `.opencv`) controls this convention. For OpenCV inputs, Riley internally transforms camera orientation and coordinates into its native viewing frame.

---

## 2. Polynomial Camera Distortion

### Formulation

Polynomial maps support total degrees 1 through 7. Riley accepts one forward map in dimensionless normalized camera coordinates, in the same direction as Brown–Conrady lens models. Inversion numerically solves that same map; there are no separate supplied inverse coefficients or direction flags.

Coefficients are stored in a row-major paired buffer with logical shape:

$$\text{shape} = [\text{term\_count},\, 2]$$

where:

$$\text{term\_count} = \frac{(\text{degree} + 1)(\text{degree} + 2)}{2}$$

Terms are ordered by increasing total degree, then descending $x$ exponent:
$$1,\, x,\, y,\, x^2,\, xy,\, y^2,\, x^3,\, x^2y,\, xy^2,\, y^3,\, \dots$$

Each term stores its $x$-output and $y$-output coefficients contiguously. Degrees 1 through 7 require 3, 6, 10, 15, 21, 28, and 36 coefficient pairs respectively.

### Evaluation Modes

- **`PolyMode.coordinate`**: Evaluates $(P(x,y),\, Q(x,y))$. Coordinate identity requires $x$ and $y$ linear coefficients of 1.0; all-zero coefficients describe a map collapsing to zero.
- **`PolyMode.displacement`**: Evaluates $(x + P(x,y),\, y + Q(x,y))$. Zero displacement coefficients describe the exact identity map.

```zig
const coeffs = [_]F{ 0, 0, 0.01, 0, 0, -0.01 };
const poly = try cam.PolyMap.init(1, .displacement, &coeffs);
const distort = try cam.DistortModel.init(.{ .poly = poly });
```

### Lifetime and Evaluation Semantics

- **Buffer Borrowing**: Native Zig maps borrow `[]const F`. Construction validates degree and buffer length but does not allocate. Coefficient storage must remain alive and unmodified until all rendering workers complete. Native empty map defaults retain displacement identity semantics.
- **Evaluation Methods**: `ford`, `fordWithJac`, and `inv`. Forward evaluation does not compute derivatives. Inversion uses Newton iteration and reports singularity, nonfinite arithmetic, or nonconvergence; only residual convergence indicates success.
- **Model Composition**: When composed with Brown–Conrady (`.brown_con`) or extended Brown–Conrady (`.brown_con_ext`), the lens model is applied first, followed by the polynomial mapping. Inversion reverses this evaluation order.

### Serialization and File Formats

CSV camera loading returns an explicit owner rather than an unmanaged camera input:

```zig
const loaded = try cameraio.LoadedCamera.init(outer_alloc, io, dir, "camera.csv");
defer loaded.deinit(outer_alloc);
// Render loaded.camera_input before deinitializing the owner.
```

Stereo pairs use `LoadedStereoPair.init/deinit` and expose `.stereo_pair`. The caller passes the freeing allocator to `deinit`. CSV metadata keys include `poly_degree`, `poly_mode`, and `poly_coeff_<term>_x` / `poly_coeff_<term>_y` with full floating-point precision.

### Python and C ABI Semantics

- **Python**: Cameras accept `distort_poly=riley.PolyMap(degree, mode, coeffs)`, where `mode` is `riley.EPolyMode.coordinate` or `.displacement`. Coefficients have shape `(term_count, 2)`. The Python binding copies a contiguous `f64` array into native memory, never silently padding or truncating incorrect shapes.
- **C ABI**: Exposes `distort_poly_degree`, `distort_poly_mode` (0 coordinate, 1 displacement), `distort_poly_coeffs`, and `distort_poly_coeffs_len`. `rileyLoadCamera` queries capacity when passed null storage with zero capacity, enabling two-pass caller allocation.

---

## 3. Distortion-Aware Rasterisation Frontend

The distortion-aware raster frontend constructs an ideal-space bounding box for each element from its triangle nodes or adaptive hull, clips it against the inverse-mapped sensor envelope, and then samples all four bounding box edges through the forward distortion model.

- `RasterConfig.edge_spacing_px` sets the ideal-pixel sample spacing (default: 1.0).
- Scalar and SIMD execution paths sample the exact same locations. Integer binning bounds are formed first, while tile overlap calculations use floating-point bounds prior to outward rounding.
- Subpixel center mapping supports `full_in_mem` (precalculated full-frame grid) or `per_tile` (computed dynamically per tile).
- Edge sampling provides an engineering tolerance for smooth lens distortion; it assumes elements are enclosed by their ideal adaptive hull and does not claim to bound singular or discontinuous transformations.

---

## 4. Render Thread Budgets and Concurrency

### Budget Allocation

`RasterConfig.parallel` controls CPU thread distribution:
- `.auto`: Uses the detected system core count.
- `.serial`: Forces single-threaded execution.
- `.{ .threads = N }`: Allocates an explicit $N$-thread budget.

Riley derives camera and frame jobs from input scenes, instantiates render groups, and partitions the thread budget among active groups:
- In **offline mode**, camera/frame jobs execute concurrently across groups.
- In **in-order mode**, concurrent groups are bounded by camera count to preserve deterministic output sequencing.
- Performance statistics reporting uses a dedicated worker thread.
- Thread budgets include worker callers but exclude asynchronous disk-save overlap threads.

### Python Configuration

In Python, `riley.RasterConfig(parallel=...)` passes thread settings directly to the Zig core:
- `parallel=None` maps to `.auto`.
- `parallel=1` selects serial execution.
- `parallel=N` specifies an explicit $N$-thread budget.

### Advanced Group Management

Advanced callers providing custom I/O or external group management use:

```zig
var managed_groups = try ManagedRenderGroups.init(outer_alloc, minimal, thread_budget, max_groups);
defer managed_groups.deinit(outer_alloc);

const images = try riley.rasterAdvanced(
    outer_alloc,
    io,
    cameras,
    meshes,
    config,
    .{ .supplied = managed_groups.groups },
    out_dir,
);
```

---

## 5. Image Save Modes and Output Formatting

`RasterConfig.output.image_save_mode` (in Zig) and `RasterConfig.image_save_mode` (in Python) select the output field layout:

| Mode | Required source fields | Output fields | Behaviour |
| :--- | :---: | :---: | :--- |
| `grey` | 1 | 1 | Single-channel monochrome (unchanged) |
| `rgb` | 3 | 3 | 3-channel RGB image (unchanged) |
| `multifield` | Any positive count | Same as source | Passes all channels through into individual fields |
| `rgb_to_grey` | 3 | 1 | Converts 3 RGB channels to 1 greyscale via luminance weighting |
| `grey_to_rgb` | 1 | 3 | Replicates 1 greyscale channel across R, G, and B |

- **Strict Input Validation**: Mismatched channel counts throw an immediate validation error unless validation is explicitly set to `.off`.
- **Bit Depths and Formats**: Controlled independently via `ImageSaveOpts`: formats include `.bmp`, `.tiff`, `.csv`, and `.fimg`; scaling supports `.none`, `.auto`, `.fixed`, and `.frac`.
- **Compiler Requirements**: Shared C library builds explicitly enforce LLVM backend compilation in Debug mode to prevent floating-point struct ABI corruption present in Zig 0.16's self-hosted x86_64 Debug backend.

---

## 6. Physical Speckle Calibration and Nominal Coverage

Use `C` for nominal coverage, `R` for physical radius, `p` for occupancy,
`J` for jitter, and `S` for edge softness. See the
[public contract](../docs/python-api/speckles.rst) for units and the UV domain.
[`specklegeom.zig`](../src/riley/zig/specklegeom.zig) integrates referenced
physical/UV face areas, including higher-order nodes:

```text
Aphys = sum over faces integral |dX/dxi cross dX/deta| dxi deta
Auv   = sum over faces integral |det(d(u,v)/d(xi,eta))| dxi deta
m     = integral ln(|X_u|/|X_v|) dAphys / Aphys
Lu    = sqrt(Aphys/Auv) * exp(m/2)
Lv    = sqrt(Aphys/Auv) * exp(-m/2); Lu*Lv = Aphys/Auv
```

`tri3`/`tri3opt` use exact constant-Jacobian one-point integration; `tri6` and
`quad4/8/9` use fixed 8×8 Gauss quadrature (Duffy mapping for triangles), assuming
usable FE geometry. All area and metric reductions accumulate in `f64`, including
f32 builds. The physical-area-weighted log-mean ratio varies continuously with
the mapping and recovers constant orthogonal planar scales. A UV sliver's ratio
influence grows logarithmically, weighted by its physical area fraction. Perlin
uses `cells_per_uv = (Lu / cell_size, Lv / cell_size)` with no coverage solve.

For disks and Gaussians, coverage is defined by the nominal disk support.
On an infinite square owner grid, each cell independently contains one uniformly
positioned centre with probability `p`. For normalized radius `r <= 1`, nine
owners suffice. Let `A_i(x,r)` be the intersection area of owner cell `i` and
the radius-`r` disk centred at query point `x`:

```text
F(p,r) = integral over unit query cell [1 - product_i(1 - p * A_i(x,r))] dx
       = sum from k=1 to 9 of M_k(r) * p^k
F(p,r) = C (solve for r); q = r / R
cells_per_uv = (Lu * q, Lv * q)
radius_mean = r; radius_jitter = r*(J/R); edge_softness = r*(S/R)
```

The signed coefficients integrate the expanded product; `M_1(r) = pi*r*r`.
This stratified Bernoulli model approximates the finite-precision hash sampler;
it is not the Poisson formula `1 - exp(-p*pi*r*r)`. Public jitter requires
`0 <= J <= R/2`. Full feasibility also requires `C <= F(p,1/(1+J/R+S/R))`;
validation checks this forward bound before geometry without an inverse solve.
Lowering inverts nominal coverage once, independently of jitter/softness, and
checks converted support `r + r*(J/R) + r*(S/R) <= 1` without clamping.
Nominal cap equality maps to `r = 1`.

[`specklecoverage.zig`](../src/riley/zig/specklecoverage.zig) computes in `f64`
without allocation or I/O: an integrated analytic polynomial for `r <= 0.5`,
otherwise a generated table over `0.5 <= r <= 1` with signed `M_2..M_9`
coefficients. Horner evaluation gives `F(p,r)/p` at nodes;
monotone PCHIP interpolates those values, not coefficients. At most 64 bisections
invert the approximation. Builds import constants without regeneration.

Separate oracle tests use vertical-slice circle/rectangle areas and direct
noncoverage probabilities, with `1e-6` absolute coverage acceptance near geometry
breaks and the cap. This is empirical evidence, not a global error bound or
finite-image guarantee. The generator checks node monotonicity in both modes;
`--check` verifies the committed table's shape and compares coefficients in
fixed radius-node order without rewriting the table. See
[Testing](TESTING.md#physical-speckle-verification) for offline and native checks.
