# Riley Engineering Assumptions and Reasoning Contract

This document defines the **supported engineering domain, accepted assumptions, design philosophy, and reasoning rules** for Riley.

It exists primarily so that humans and AI coding/review agents do not waste time trying to make Riley correct for arbitrary mathematical pathologies outside its intended operating domain.

Riley is a **scientific software rasteriser for engineering camera simulation, DIC/optical metrology, validation, and uncertainty quantification**. It is not a general-purpose theorem prover, symbolic geometry package, adversarial computational-geometry library, or real-time game engine.

The core standard is:

> **Engineering correctness over a clearly defined and testable operating domain, with high performance and controlled failure behaviour.**

---

## 1. Core Reasoning and Review Rules

Treat the assumptions in this document as **axioms for design and code review unless a task explicitly states otherwise**. Once an assumption has been accepted, do not reintroduce counterexamples that violate it.

### Failure Classification Taxonomy

When identifying any potential failure mode, classify it as one of:

1. **Bug**: The implementation fails for an input that Riley explicitly supports under these assumptions. Deserves investigation and a fix.
2. **Engineering limitation**: The implementation may fail near the edge of the intended operating envelope, but the case is plausible in scientific use. This may justify a conservative margin, runtime validation, an assertion, or documentation—**not** replacing a fast method with a globally rigorous, expensive one.
3. **Out-of-domain mathematical pathology**: The failure requires violating Riley's stated assumptions, using adversarial input, constructing a nonphysical camera map, or providing an invalid FE mesh. Do not redesign Riley around these.

### Questions for Reviewers and Agents

Before claiming that an algorithm or bounding strategy is defective, answer these questions:

1. **Does the failure mode occur inside the supported domain?** (If it violates stated assumptions, classify as out-of-domain and stop).
2. **Is the error operationally relevant?** Compare against physical scales: pixel pitch, subpixel spacing, PSF width, or DIC accuracy requirements.
3. **Is it a false positive or false negative?** Conservative false positives cost only modest performance; false negatives cause rendering errors.
4. **What is the computational cost of the proposed fix?** Quantify evaluations per element/pixel, memory allocations, and SIMD impact.
5. **Can a cheaper conservative margin, validation check, or fallback solve it?** Prefer cheap conservative bounds and reference tests over complex global solvers.

### Default Decision Rule

When choosing between:
- **A.** A simple, fast algorithm demonstrably correct throughout Riley's intended engineering domain and easy to verify, and
- **B.** A significantly slower or more complex algorithm that additionally handles pathological inputs Riley does not support,

**Choose A by default.** Choose B only when the broader guarantee is required by a real supported use case or has negligible overhead.

---

## 2. Design and Performance Priorities

When several valid implementations are possible, optimise in this order:

1. **Correctness** within the supported engineering domain;
2. **Deterministic and reproducible behaviour** for scientific simulation and UQ;
3. **High throughput and scalability** (SIMD vectorisation, tiled rasterisation, multithreading);
4. **Low algorithmic and implementation complexity**;
5. **Clear verification and failure detection**;
6. **Mathematical generality outside the supported domain** (lowest priority).

### Hot-Path Efficiency

- **Bounded approximations over global proofs**: Riley is allowed to use bounded, testable engineering approximations when they are substantially cheaper than global mathematical guarantees.
- **Data layouts and memory traffic**: Prefer contiguous layouts (e.g. polynomial coefficient buffers, packed SIMD vectors, element connectivity) over scattered pointers.
- **SIMD vs. scalar crossovers**: Forward camera distortion is fixed-cost arithmetic and vectorises well; short loops with high packing overhead should use scalar fast paths.
- **Threading abstraction**: Hide thread pool and worker details behind clean configuration defaults (`render_threads: u32 = 4`).

---

## 3. Mesh and Geometry Assumptions

Riley assumes input meshes are valid engineering meshes produced by trusted FE, meshing, or simulation workflows.

Unless a task explicitly concerns malformed-input validation, assume:

- Element connectivity, node indexing, and element types are valid;
- Elements have positive, usable area/volume with non-singular Jacobian mappings;
- Surfaces do not intentionally self-intersect or fold through themselves;
- Projected element footprints are finite, and curvature is physically plausible for FE meshes (no extreme high-frequency nodal oscillations);
- Scene scale, camera placement, and mesh resolution are mutually sensible.

> **Curved higher-order elements**: Riley supports curved quadratic and higher-order elements. It is not required to handle arbitrary pathological polynomial patches that fold or invert.

---

## 4. Camera and Distortion Model Assumptions

Riley camera models represent calibrated or intentionally prescribed optical systems, not adversarial nonlinear coordinate maps.

### Supported Domain

- **Smooth and locally invertible**: Over the active sensor and relevant rendering envelope, the mapping is smooth, the required forward mapping is well-defined, and the distortion Jacobian is nonsingular.
- **Calibrated vs. arbitrary coefficients**: Flexible polynomial models (e.g. degrees 1–7) can mathematically express extreme oscillations, folding, or multiple roots. Such parameter sets are **out of domain**. Riley only supports coefficient sets representing smooth physical optics or calibrated residual fields.
- **Iterative inversion**: Newton-Raphson solvers operate within a documented convergence regime with physically motivated initial guesses, small iteration caps, and pixel/subpixel stopping tolerances.

### Model Composition

Camera and shader stages (ideal projection, analytic lens distortion, polynomial residual mapping, optical PSF blur, detector response) are explicitly typed and statically composable. The sequence must reflect the physical optical model.

---

## 5. Spatial Bounds, Culling, and Conservative Margins

The purpose of spatial bounding and culling is to avoid unnecessary raster work while preserving complete geometric coverage.

- **Sampling plus conservative expansion**: Element and sensor bounds sample the boundary at configured image-space spacings (e.g. pixel scale) and expand by a safety halo. This absorbs bounded inter-sample deviation without requiring expensive global extrema solvers.
- **Memoized sensor hulls**: Camera-dependent ideal-sensor bounds depend only on camera configuration; compute or memoize them once per camera rather than recomputing per frame or element.
- **False positives over false negatives**: Small conservative overestimations (pixel halos, ceil/floor tile expansions, PSF support bounds) are cheap and safe. Avoid complex exact geometric clipping that costs more than the raster work it saves.

---

## 6. Numerical Philosophy and Scale

Riley operates in finite-resolution digital camera space using standard IEEE 754 floating-point arithmetic.

- **Finite precision is normal**: Tolerances, margins, and stable formulations are preferred over symbolic exactness or arbitrary-precision arithmetic.
- **Operational relevance**: A geometric or numerical discrepancy orders of magnitude below pixel/subpixel resolution (or below the requested DIC precision) is not an operational defect.
- **Discretisation and cyonvergence**: Under refinement (SSAA supersampling, mesh density, quadrature order, PSF support), discretisation bias should converge systematically toward reference solutions.

---

## 7. Verification and Failure Handling

- **Verification over formal proof**: Verify approximate fast production methods against independent, high-fidelity reference implementations (analytic cases, scalar loops, dense sampling, OpenCV reprojections). Do not confuse "not formally proven" with "not verified".
- **Cheaper failure detection**: Fail clearly on cheaply detectable errors (invalid sensor dimensions, non-finite parameters, unsupported element types, detected iterative solver divergence). Do not add expensive global checks to inner raster loops for implausible data corruption.

---

## 8. Summary for Developers and AI Agents

> **Riley is engineering software for valid FE meshes and well-behaved calibrated camera models.**
> Optimise for correctness inside that domain, deterministic scientific behaviour, throughput, simplicity, and verification.
> Do not redesign hot-path algorithms around malformed elements, self-folding higher-order patches, singular/adversarial distortion maps, or arbitrary polynomial pathologies.
> A lack of a global mathematical proof is not a bug. Demonstrate a realistic in-domain failure, quantify its operational significance at pixel scale, and consider cheap margins, validation, or reference testing before proposing expensive machinery.
