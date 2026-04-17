# Newton Guess Improvement Plan

This plan is for `src-simd2` only.

Goal:
- Improve the initial guess used by the SIMD Newton path for:
  - `quad4newton`
  - `tri6`
  - `quad8`
  - `quad9`
- Reuse recent converged seeds when they are trustworthy.
- Keep seed selection inexpensive relative to Newton iteration cost.
- Preserve correctness on curved and silhouette-heavy cases such as `sphere200` and
  `sphere2000`.

## Current State

1. The SIMD Newton path in
   [src-simd2/zigraster/zig/rasterengine.zig](/home/lloydf/zigraster/src-simd2/zigraster/zig/rasterengine.zig)
   gets a coarse hull guess from `element_tess.isInSIMD(...)`.

2. That hull guess is then overwritten for all Newton kernels by
   `Geometry.getNewtonGuess()`, so the actual SIMD solve currently starts from a fixed
   element-centroid guess.

3. The Newton helpers in
   [src-simd2/zigraster/zig/newton.zig](/home/lloydf/zigraster/src-simd2/zigraster/zig/newton.zig)
   currently expose:
   - convergence mask
   - iteration count
   - `xi_out`
   - `eta_out`
   but they do not expose:
   - residual at the final iterate
   - whether a lane converged before the inside-domain check
   - a domain-violation measure for converged-but-outside lanes

4. Because of that, the current code cannot rank converged lanes well enough to pick the
   best reusable seed.

## Strategy

Implement this in phases.

Phase 1:
- Reuse the best recent inside-converged seed as the initial guess for the next SIMD
  candidate block.

Phase 2:
- Optionally add a gated hull-seed fallback, but only if Phase 1 does not recover enough
  improvement on first-contact pixels.

Do not mix both immediately.
The first experiment should isolate the effect of the reusable local seed.

## Seed Policy

For each Newton overlap render, keep a small reusable seed cache.

Initial design:
- one `last_good_seed` for the current overlap
- reset it at the start of each `rasterSIMDNewton` call
- optionally refine later to one seed per row if needed

Seed contents:
- `xi`
- `eta`
- `resid_sq`
- `valid`

Only update this cache from lanes that are both:
- converged
- inside the element parametric domain

If multiple lanes in a SIMD solve qualify, choose the best one using:
1. smallest domain violation
2. then smallest residual

For Phase 1, since only inside lanes are allowed to update the cache, domain violation is
already zero for all accepted lanes. In practice the winner is the inside lane with the
smallest residual.

If no lane converged inside, do not update the cached seed.

## Why This Should Help

The candidate blocks are generated in local raster order inside the current tile overlap.
That means nearby pixels are usually close in parametric space, especially away from
silhouettes.

A recent inside-converged seed should therefore be:
- far more relevant than the fixed centroid guess
- cheap to select
- robust on smooth interior regions

It also avoids the known failure mode of blindly trusting hull guesses on strongly curved
screen-space edges.

## Required API Changes

### 1. Extend Newton result structs

In
[src-simd2/zigraster/zig/newton.zig](/home/lloydf/zigraster/src-simd2/zigraster/zig/newton.zig):

Add to `NewtonResult`:
- `pre_domain_converged: bool`
- `residual_x: f64`
- `residual_y: f64`

Add to `NewtonResultSIMD`:
- `pre_domain_converged: @Vector(8, bool)`
- `residual_x: @Vector(8, f64)`
- `residual_y: @Vector(8, f64)`

Rationale:
- We need residual to rank reusable seeds.
- We need pre-domain convergence status to distinguish:
  - numerically converged but outside domain
  - true solver divergence

### 2. Add a cheap residual metric

Define:
- `resid_sq = residual_x * residual_x + residual_y * residual_y`

This residual must be the same projected clip-space residual the Newton solver already uses.
Do not use raster-space residual for seed ranking.

### 3. Add domain-violation helpers per kernel family

In
[src-simd2/zigraster/zig/geometrykernels.zig](/home/lloydf/zigraster/src-simd2/zigraster/zig/geometrykernels.zig):

Add small helpers for Newton kernels only.

For `tri6`:
- `domainViolation(xi, eta) = max(-xi, 0) + max(-eta, 0) + max(xi + eta - 1, 0)`

For `quad4newton`, `quad8`, `quad9`:
- `domainViolation(xi, eta) = max(abs(xi) - 1, 0) + max(abs(eta) - 1, 0)`

This gives a cheap ordering rule when we later want to inspect converged-but-outside lanes.

## Phase 1 Implementation

### 1. Keep the current coarse hull pass unchanged

Do not change:
- hull membership
- candidate buffering
- AoSoA candidate storage

Only change the seed used for `Geometry.solveWeightsSIMD(...)`.

### 2. Add overlap-local seed state in `rasterSIMDNewton`

In
[src-simd2/zigraster/zig/rasterengine.zig](/home/lloydf/zigraster/src-simd2/zigraster/zig/rasterengine.zig):

At the start of `rasterSIMDNewton`, add:
- `last_seed_valid: bool`
- `last_seed_xi: f64`
- `last_seed_eta: f64`
- `last_seed_resid_sq: f64`

Initialize from the existing kernel default:
- `Geometry.getNewtonGuess()`
but mark `last_seed_valid = false`

### 3. Use the last good seed for each candidate block

Current behavior:
- candidate blocks carry per-lane guesses that are all set to the default centroid guess

Phase 1 behavior:
- when building each candidate block, if `last_seed_valid` is true:
  - fill all active lanes in that block with `last_seed_xi`, `last_seed_eta`
- otherwise:
  - keep the current default centroid seed

This is intentionally simple and cheap.

Do not use the hull guess in Phase 1.
You already observed it can hurt curved edge cases.

### 4. Update the reusable seed after each SIMD solve

After `Geometry.solveWeightsSIMD(...)` returns:
- inspect only lanes where:
  - `pre_domain_converged` is true
  - final domain violation is zero
- compute `resid_sq` for those lanes
- choose the lane with the smallest `resid_sq`
- write its `xi_out`, `eta_out`, and `resid_sq` into the overlap-local seed cache
- set `last_seed_valid = true`

If no lane qualifies:
- leave the cache unchanged

This keeps the selection cheap:
- at most 8 scalar lane inspections per block
- no extra Newton solve
- no extra hull work

## Optional Phase 1.5

If Phase 1 helps but leaves performance on the table at row starts or after large gaps:

Add a row-local fallback:
- carry one seed per `scratch_y` row
- reset on row change
- prefer row-local last seed over overlap-global last seed

This still stays cheap and keeps spatial locality stronger than a single overlap-global
seed.

## Phase 2: Gated Hull Fallback

Only try this if Phase 1 is safe and beneficial.

Use order:
1. last good inside seed
2. gated hull seed
3. default centroid seed

### Hull-seed gate

Do not accept hull seed blindly.

Add a cheap projected-residual check using the same residual model as the Newton solver:
- evaluate one forward residual at the hull `(xi, eta)` guess
- compute `resid_sq`
- accept the hull seed only if:
  - the parametric guess is inside or only slightly outside
  - and `resid_sq` is below a conservative threshold

The threshold should be tuned empirically.
Start conservative.

Suggested first pass:
- only accept hull seed if it is already inside the domain
- and its clip-space residual is clearly small relative to the element scale

Do not implement this until after Phase 1 has been benchmarked by itself.

## Optional Future Experiments

These are lower priority and should not be mixed into the first attempt:

1. Left-neighbor solved seed
- Use the previous solved pixel in raster order as a seed source.

2. Gradient-extrapolated seed
- Use two previous solved seeds to estimate local `d(xi)` / `d(eta)` and extrapolate.

3. Best-of-two seed check
- Compare:
  - last good seed
  - gated hull seed
  by one residual evaluation, then run Newton from the better one.

These may help, but they add more complexity and should only be tried after the simple
reuse strategy is understood.

## File-by-File Plan

### [src-simd2/zigraster/zig/newton.zig](/home/lloydf/zigraster/src-simd2/zigraster/zig/newton.zig)

Add:
- residual outputs
- pre-domain convergence outputs

Preserve:
- current solve math
- current inside-domain acceptance logic

### [src-simd2/zigraster/zig/geometrykernels.zig](/home/lloydf/zigraster/src-simd2/zigraster/zig/geometrykernels.zig)

Add for Newton kernels:
- domain-violation helper

Possibly add later:
- residual gate helper for hull guesses

Do not change scalar paths unless necessary to keep interfaces consistent.

### [src-simd2/zigraster/zig/rasterengine.zig](/home/lloydf/zigraster/src-simd2/zigraster/zig/rasterengine.zig)

Change:
- candidate-block guess assignment
- reusable overlap-local seed state
- post-solve lane ranking and seed-cache update

Do not change:
- hull coarse pass
- shading pass
- accepted AoSoA candidate storage structure

## Validation

After Phase 1:

1. `zig test -lc -O ReleaseSafe ./src-simd2/test_gold_all.zig`
2. `zig test -lc -O ReleaseSafe ./src-simd2/test_bench.zig`
3. `zig run -O ReleaseFast ./src-simd2/bench_fullraster.zig`
4. `zig run -O ReleaseFast ./src-simd2/bench_sphere2000.zig`

Benchmark focus:
- `quad4newton_*`
- `tri6_*`
- `quad8_*`
- `quad9_*`

Acceptance rule:
- keep the change only if both test suites pass and the Newton-kernel benchmark trend is
  positive overall
- reject if it causes sphere-edge correctness issues or broad regressions

## Success Criteria

Primary success:
- fewer Newton iterations on interior candidate blocks
- improved `bench_fullraster` for Newton kernels
- no correctness regressions on sphere cases

Secondary success:
- improvement on `bench_sphere2000`

Likely result:
- the strongest win should be on dense interior regions where nearby pixels share similar
  inverse-map coordinates
- silhouettes may see little benefit, but should remain safe because only inside-converged
  seeds are reused
