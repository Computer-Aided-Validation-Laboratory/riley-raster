# Riley Common Abbreviations

Use these abbreviations consistently in Riley Zig code.

Apply the same identifier spellings in the C ABI and Python bindings. Use
PascalCase for types, camelCase for Zig functions, and snake_case for fields and
variables where required by the language or existing convention.

These conventions apply only to Riley-owned identifiers. Keep standard-library
and third-party API names exactly as defined upstream, including
`std.mem.alignForward`, `std.mem.copyForwards`, and `numpy.polynomial`.

## Core Numeric Terms
- `resid`: residual
- `norm`: normalized or normalised
- `interp`: interpolated or interpolation when the shorter form is clear
- `det`: determinant
- `rel`: relative
- `para`: parametric
- `conv`: converged or convergence
- `convo`: convolution
- `dom`: domain
- `targ`: target
- `jac`: Jacobian
- `inv`: inverse
- `ford`: forward
- `poly`: polynomial
- `distort`: distortion
- `brown_con`: Brown–Conrady (for example, `BrownCon` and `BrownConExt`)
- `comp`: component
- `elem`: element
- `func`: function or functions
- `vec`: vector
- `buff`: buffer
- `tex`: texture
- `samp`: sample
- `grey`: greyscale
- `tol`: tolerance
- `align`: alignment
- `supp`: support
- `adapt`: adaptive
- `tri`: triangle
- `scal`: scalar
- `def`: default
- `vals`: values
- `calc`: calculate
- `avg`: average or averaged
- `accum`: accumulate
- `vis`: visible
- `prep`: prepare or prepared
- `dyn`: dynamic
- `err`: error
- `capt`: capture
- `inp`: input or inputs when the shorter form is clear
- `valid`: validate or validation when the shorter form is clear
- `strat`: strategy
- `glob`: global
- `persp`: perspective
- `comm`: common
- `pix`: pixel
- `cent`: center or centre or centers or centres
- `in`: inner
- `out`: outer

## Common Existing Terms
- `alloc`: allocator
- `ctx`: context
- `cfg`: config
- `img`: image
- `geom`: geometry
- `cam`: camera
- `dist`: distance when the shorter form is already established; use `distort`
  for distortion
- `iter`: iteration or iterator count
- `fail`: failed or failure when the shorter form is clear
- `lim`: limit
- `subpx`: sub-pixel
- `uvs`: uv coordinates
- `px`: pixel
- `roi`: region of interest
- `psf`: point spread function

## Guidance
- Common comptime constants may use single-capital abbreviations when the
  context is obvious:
  `F` = floating point precision such as `f64` or `f32`
  `N` = nodes per element
  `S` = SIMD vector width
  `C` = image channels
  `T` = a type
- Prefer clarity over maximal shortening.
- Abbreviations may appear in lower case or camel case depending on naming
  context.
- For example, `interp` and `Interp` are both valid when the local naming style
  calls for them, and `samp` and `Samp` are both valid.
- Use the short form only when it remains obvious in local context.
- Reuse established Riley abbreviations instead of inventing file-local variants.
- For example, use `PolyMap`, `DistortParams`, `fordWithJac`, `invDistortSIMD`,
  `brown_con`, and `distort_model` consistently. Serialized calibration model
  tags retain their conventional mathematical names.
- Follow `dev/FILESTRUCTURE.md` and other `dev/` guidance files whenever editing Zig.
