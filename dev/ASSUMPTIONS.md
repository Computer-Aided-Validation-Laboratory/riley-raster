# Riley Engineering Assumptions and Reasoning Contract

This document defines the **supported engineering domain, accepted assumptions, design philosophy, and reasoning rules** for Riley.

It exists primarily so that humans and AI coding/review agents do not waste time trying to make Riley correct for arbitrary mathematical pathologies that are outside its intended operating domain.

Riley is a **scientific software rasteriser for engineering camera simulation, DIC/optical metrology, validation, and uncertainty quantification**. It is not a general-purpose theorem prover, symbolic geometry package, adversarial computational-geometry library, or OpenGL clone.

The correct standard is:

> **Engineering correctness over a clearly defined and testable operating domain, with high performance and controlled failure behaviour.**

A mathematically possible counterexample is not automatically a Riley defect. Before proposing a fix, an agent must first establish that the counterexample is inside Riley's supported operating domain and is relevant to realistic engineering use.

---

## 1. Core reasoning rule

Treat the assumptions in this document as **axioms for design and code review unless a task explicitly states otherwise**.

Once an assumption has been accepted, do **not** repeatedly reintroduce counterexamples that violate it.

When identifying any possible failure mode, classify it as one of:

### A. Bug

The implementation fails for an input that Riley explicitly supports under the assumptions in this document.

This deserves investigation and usually a fix.

### B. Engineering limitation

The implementation may fail near the edge of the intended operating envelope, but the case is plausible in real scientific use.

This may justify one or more of:

- a conservative numerical margin,
- a runtime validation check,
- a warning or assertion,
- a targeted verification test,
- documentation of the supported envelope,
- an optional slower mode.

It does **not** automatically justify replacing a fast method with a globally rigorous one.

### C. Out-of-domain mathematical pathology

The failure requires violating Riley's stated assumptions, using adversarial input, constructing a nonphysical camera map, providing an invalid FE mesh, or otherwise leaving the intended engineering domain.

Mention such cases only when they materially clarify the domain boundary. Do not redesign Riley around them.

---

## 2. Design priority

When several valid implementations are possible, optimise for the following, in roughly this order:

1. correctness within the supported engineering domain;
2. deterministic and reproducible behaviour;
3. high throughput and good scaling;
4. low algorithmic and implementation complexity;
5. clear verification and failure detection;
6. mathematical generality outside the supported domain.

A more mathematically general method is **not inherently better** if it materially increases:

- work per element,
- work per pixel or sub-sample,
- memory traffic,
- allocations,
- branching,
- code complexity,
- maintenance burden,
- difficulty of SIMD/vectorisation,
- difficulty of multithreading,
- difficulty of verification,

without solving a realistic Riley failure mode.

Riley is allowed to use **bounded, testable engineering approximations** when they are substantially cheaper than global mathematical guarantees.

---

## 3. Mesh validity assumptions

Riley assumes that input meshes are valid engineering meshes produced by trusted FE, meshing, or simulation workflows.

Unless a task explicitly concerns malformed-input validation, assume:

- element connectivity is valid;
- node indices are valid and correctly based/rebased;
- element types match their connectivity;
- elements have nonzero usable area;
- surfaces are not intentionally self-intersecting;
- element mappings are valid over their parameter domain;
- higher-order elements do not fold through themselves;
- the Jacobian of the element mapping does not become singular inside a valid element;
- the mesh does not contain arbitrary adversarial nodal placements designed to defeat geometric bounds;
- surface orientation is meaningful where back-face culling is enabled;
- grossly degenerate elements are upstream data errors, not normal rendering cases.

### Consequence for higher-order elements

The fact that a mathematically arbitrary quadratic or higher-order element *can* self-intersect, invert, or fold is not by itself a useful Riley objection.

If a proposed counterexample requires a quadratic triangle or quadrilateral to fold through itself, first classify that case as **outside the normal supported mesh domain** unless the current task explicitly concerns invalid-element detection.

Riley should support curved higher-order geometry. It is not required to support arbitrary pathological polynomial patches.

---

## 4. Geometry assumptions

Riley targets engineering geometry whose local behaviour is smooth at the scale relevant to rasterisation.

Assume that:

- element geometry is continuous within each element;
- higher-order curvature is physically plausible for an FE surface mesh;
- the projected footprint of a valid element is finite;
- extreme geometric oscillation between neighbouring nodes is not a normal case;
- the user is not deliberately constructing elements whose image-space geometry changes at arbitrarily high spatial frequency;
- scene scale, camera placement, and mesh resolution are mutually sensible for the simulation being performed.

Riley may use conservative image-space bounds, adaptive/fixed boundary sampling, local subdivision, or other approximate geometry methods where these are demonstrated to work over the supported engineering domain.

A geometric bound does not have to be a formal enclosure theorem over all possible polynomial patches unless that guarantee is specifically required by the feature.

---

## 5. Camera model assumptions

Riley camera models represent calibrated or intentionally prescribed optical systems, not arbitrary adversarial nonlinear maps.

Assume that over the active sensor and the image region relevant to rendering:

- the camera mapping is smooth;
- the required forward mapping is well defined;
- any inverse mapping Riley relies upon exists over the supported region;
- the distortion Jacobian is nonsingular in the supported operating range;
- the mapping does not contain arbitrary discontinuities;
- the mapping does not contain unresolved subpixel oscillations;
- distortion fields are representative of real lenses, calibrated residual maps, or deliberate but physically meaningful synthetic studies;
- Newton-type inversion is started in a regime where convergence is expected under the documented model assumptions.

A polynomial distortion model having enough mathematical freedom to produce absurd maps does **not** imply that Riley must support every such coefficient set.

For polynomial models, the supported domain is the subset of coefficient space that produces a smooth, usable camera mapping over the relevant sensor region.

---

## 6. Distortion-model assumptions

Riley supports distortion models because real imaging systems require them, including Brown-Conrady-type models, extended models, polynomial coordinate/displacement maps, and composed mappings.

The following reasoning rules apply:

- zero-valued distortion parameters may still exercise a different code path from `.none` and therefore may have measurable overhead;
- a higher-order polynomial model is permitted to represent fields that are not expressible by a lower-dimensional analytic lens model;
- this additional freedom does not make arbitrary pathological polynomial coefficient sets part of the supported domain;
- forward and inverse mappings should be verified independently where practical;
- dense or high-resolution reference sampling is a valid way to verify a faster production approximation;
- pathological examples should not automatically dictate the production algorithm.

Riley may use a fast production method plus a slower reference or verification method in tests and benchmarks.

---

## 7. Distortion-aware bounds and hulls

The purpose of distortion-aware culling/bounding is to avoid unnecessary raster work while preserving correctness for realistic distorted engineering imagery.

The production algorithm is allowed to use **sampling plus conservative expansion** rather than globally solving for exact extrema of an arbitrary nonlinear map.

For the current design philosophy, assume:

- distortion is smooth over the relevant image region;
- the camera mapping is locally invertible there;
- sampling at approximately pixel-scale spacing is meaningful because realistic image-space distortion does not oscillate arbitrarily between adjacent samples;
- a conservative halo/expansion is allowed to absorb bounded inter-sample deviation and numerical uncertainty;
- representative and deliberately severe realistic distortions should be tested against denser reference sampling;
- the supported operating envelope can be defined empirically and numerically rather than through a closed-form global proof.

### Sensor bounds

If a camera-dependent ideal-sensor bound depends only on invariant camera state and a halo/configuration key, compute or memoize it once rather than recomputing it per frame.

Do not prefer a formally cleaner method if it causes substantial repeated inverse solves or full-sensor scans that can be reused safely.

### Element bounds

Per-element distortion-aware bounds may sample the relevant projected boundary at a configured image-space spacing and conservatively expand the result.

Do not reject this design merely because an arbitrary smooth mathematical function could have an unsampled extremum between samples. The relevant question is whether such behaviour can occur **within Riley's stated camera assumptions and configured safety margin**.

If evidence shows that the current spacing/margin is insufficient for realistic supported distortions, improve the spacing rule, margin, validation, or fallback. Do not immediately jump to a globally exact extrema solver.

---

## 8. Visibility, culling, and enclosure

Culling algorithms exist to save work. Their own cost matters.

A culling method that is theoretically stronger but costs enough to erase the benefit of culling is generally a poor Riley design unless required for correctness in realistic supported cases.

When reviewing culling logic:

- distinguish conservative false positives from false negatives;
- false positives usually cost performance only;
- false negatives can be correctness bugs if they occur inside the supported domain;
- prefer cheap conservative expansion over expensive exact geometry when it prevents realistic false negatives;
- benchmark culling cost separately from total render time;
- count distortion evaluations, inverse solves, allocations, and memory traffic where useful;
- test both large elements and near-pixel-size elements because the optimal overhead balance changes with element size.

Do not demand proof that every intermediate hull is the exact geometric image of the element. Demand that the production bound is sufficiently conservative for the supported domain and verified accordingly.

---

## 9. Numerical philosophy

Riley is numerical engineering software. Floating-point arithmetic is part of the model.

Do not reason as though exact real arithmetic is available.

Assume that:

- small floating-point differences are normal;
- tolerances should be tied to physically/numerically meaningful scales where possible;
- exact equality should not be demanded for numerically derived geometric quantities unless the quantity is intentionally discrete;
- robust bounds may include small conservative expansions;
- finite precision is usually handled by tolerances, margins, or stable formulations rather than symbolic exactness;
- verification should distinguish harmless floating-point noise from systematic bias or topology-changing error.

Avoid solving numerical problems with disproportionately expensive exact or arbitrary-precision machinery unless a demonstrated supported-domain failure requires it.

---

## 10. Newton and iterative solves

Riley uses iterative numerical methods where appropriate, including camera inversion and other nonlinear operations.

Assume iterative solvers are used inside a documented convergence regime.

A valid engineering implementation may rely on:

- a good physically motivated initial guess;
- a small fixed iteration cap;
- a convergence tolerance appropriate to pixel/subpixel accuracy;
- bounded failure handling;
- validation that normal calibrated-camera cases converge rapidly.

The mere existence of nonlinear maps for which Newton-Raphson fails is not an objection unless those maps are inside the supported domain.

When improving iterative code, prioritise:

- convergence on realistic inputs;
- predictable cost;
- vectorisability where appropriate;
- good diagnostics for rare failures;
- avoiding unnecessary iteration for simple forward mappings.

---

## 11. Rasterisation and sampling assumptions

Riley is a scientific rasteriser whose rendered image should converge appropriately as numerical discretisation is refined.

Relevant numerical controls include, depending on the feature:

- supersampling / SSAA;
- geometry resolution;
- texture or field sampling resolution;
- interpolation/filter choice;
- PSF support and discretisation;
- quadrature order;
- time integration resolution;
- nonlinear solver tolerance.

These controls can interact. Do not automatically assume errors are additive or independent.

Where two schemes are intended to approximate the same continuous model, the important scientific question is whether they approach the same limit under refinement.

For DIC/UQ work, renderer discretisation bias should be driven toward a converged reference so that renderer artefacts can be separated from the measurement/model error of interest.

---

## 12. Determinism and reproducibility

Riley is intended for scientific simulation and uncertainty quantification, so determinism is valuable.

Prefer deterministic algorithms where practical.

Assume that:

- repeated renders with the same inputs/configuration should be reproducible within the intended floating-point/threading contract;
- ordered execution paths may be provided where deterministic ordering matters;
- parallelism should not silently change scientific meaning;
- nondeterministic Monte-Carlo pixel integration is not the default design direction;
- deterministic quadrature/sampling methods are generally preferred for scientific convergence studies.

---

## 13. Performance assumptions

Performance is a first-class design requirement, not an afterthought.

Riley is intended to render large engineering datasets, many elements, many pixels/subsamples, multiple frames, and potentially multiple cameras.

The following are legitimate design goals:

- SIMD/vectorised inner loops;
- compile-time specialisation;
- low runtime dispatch overhead;
- tiled rasterisation;
- hierarchical or grouped threading;
- reuse of invariant camera/scene data;
- low allocation counts in hot paths;
- contiguous data layouts where they improve access locality;
- avoiding repeated expensive transforms/inversions;
- avoiding unnecessary memory traffic;
- scalar fast paths for workloads too small to amortise SIMD setup/packing overhead;
- benchmarking whole-pipeline throughput as well as individual kernels.

Do not recommend a significantly slower algorithm solely because it offers a stronger guarantee outside the supported domain.

When proposing a more expensive correctness mechanism, quantify or at least reason explicitly about:

- asymptotic cost;
- constant-factor cost;
- number of evaluations per element/pixel;
- expected frequency of the guarded case;
- whether the cost is paid once, per camera, per frame, per element, per tile, or per sample;
- whether a cheaper validation/fallback strategy would solve the same realistic problem.

---

## 14. SIMD assumptions

SIMD is useful when enough homogeneous work exists to amortise setup and lane inefficiency.

Do not assume SIMD is always faster for tiny workloads.

For short sample counts, a scalar path may be preferable. The correct crossover should be benchmarked rather than derived from aesthetics alone.

Forward camera distortion is typically fixed-cost arithmetic and can vectorise well. Iterative inverse camera distortion has different cost characteristics because convergence/iteration behaviour may dominate.

Branching once to select scalar versus SIMD is acceptable when it measurably improves realistic workloads and does not complicate the implementation excessively.

---

## 15. Threading and I/O assumptions

Riley should hide unnecessary threading complexity from normal users while retaining advanced control where needed.

User-facing configuration should prefer good automatic defaults.

Internally, Riley may create/manage render groups, worker I/O objects, or thread resources rather than requiring every user to construct them manually.

Where Riley uses Zig's threaded I/O or worker limits, remember that user-facing thread counts may intentionally describe **total participating threads**, including the caller, while a lower-level API may count only spawned workers.

The public API should express concepts in terms users naturally understand rather than leaking implementation quirks unnecessarily.

---

## 16. Data-layout assumptions

Riley may prefer contiguous representations when a kernel usually consumes related values together.

This is especially relevant for:

- polynomial coefficient buffers;
- SIMD loads;
- element/connectivity data;
- camera parameter blocks;
- tightly coupled interpolation state.

Do not split data into multiple independently allocated arrays merely for conceptual neatness when the hot path always fetches them together and locality is materially better with a contiguous layout.

Conversely, do not perform large refactors for hypothetical cache benefits without evidence.

Benchmark material layout choices when they affect hot loops.

---

## 17. Scientific truth and verification

Riley's purpose is not merely to generate plausible pictures. It must support scientific verification.

Prefer tests against independent or higher-fidelity references where possible.

Useful verification patterns include:

- analytic cases;
- independently implemented scalar references;
- dense sampling references;
- forward/inverse reprojection checks;
- comparison against trusted external implementations such as OpenCV where the mathematical model matches;
- convergence studies;
- synthetic scenes with known exact geometry/fields;
- single-element edge cases;
- deliberately severe but still physically plausible parameter cases;
- tests that isolate individual pipeline stages.

A production algorithm can be approximate while its correctness is tested against a much more expensive reference implementation.

Do not confuse "not formally proven" with "not verified".

---

## 18. Failure handling

Riley should fail clearly when inputs violate a requirement that can be checked cheaply and usefully.

Good candidates include:

- invalid dimensions;
- impossible configuration combinations;
- non-finite parameters;
- failed iterative inversion where failure is detectable;
- unsupported element types;
- malformed connectivity;
- singular/obviously invalid camera configuration when cheaply detectable.

Do not add expensive global validity checks to every hot path merely to detect highly implausible upstream data corruption.

Validation cost should be proportional to realistic risk and scientific consequence.

---

## 19. Conservative engineering margins

Riley may deliberately overestimate bounds or supports when doing so is cheap and preserves correctness.

Examples include:

- pixel halos around geometric/distorted bounds;
- ceil/floor expansion at discrete tile boundaries;
- conservative PSF support bounds;
- small tolerance bands for floating-point comparisons.

Small conservative false positives are often preferable to complex exact calculations.

The margin should be justified by testing or a clear scale argument; it need not be the mathematically minimal possible margin.

---

## 20. Camera and image scale

Riley operates in finite-resolution digital camera space.

Pixel scale matters.

A mathematically real deviation many orders of magnitude below the pixel/subpixel tolerance of the simulation is not automatically operationally relevant.

When evaluating a proposed geometric/numerical issue, compare it to quantities such as:

- pixel pitch;
- sub-sample spacing;
- PSF width;
- requested DIC accuracy;
- culling halo;
- element image-space size;
- numerical tolerance.

Do not treat all nonzero errors as equally important.

---

## 21. Physical-camera realism versus adversarial maps

A recurring source of wasted reasoning is treating a flexible camera model as though every mathematically expressible map were an intended physical camera.

This is incorrect.

For example, a degree-7 polynomial may be able to express:

- extreme oscillation;
- local folding;
- enormous displacement;
- multiple inverse roots;
- singular Jacobians.

That does not make such parameter sets supported merely because the type system can store the coefficients.

The intended domain is **well-behaved calibrated or deliberately prescribed engineering distortion fields**.

If useful, Riley may provide diagnostics that detect egregiously invalid mappings, but production algorithms should not be designed around hostile polynomial fields.

---

## 22. Model composition

Riley may compose camera or shader stages when this reflects the physical/numerical pipeline.

Prefer explicit, typed, statically composable stages over a highly dynamic graph when the latter harms clarity, specialisation, SIMD, or verification.

For example, camera or material processing may be conceptually staged as transforms such as:

- ideal projection;
- analytic lens distortion;
- residual polynomial mapping;
- optical blur / PSF integration;
- detector or radiometric response.

The exact order matters and should follow the physical model.

Do not reorder stages merely because an implementation becomes simpler unless the reordered model is scientifically equivalent for the intended use.

---

## 23. Scope of Riley

Riley is primarily a **metrology/scientific camera simulator**.

Features should be judged against that mission.

The project values:

- FE-aware geometry;
- higher-order surfaces;
- physically/scientifically meaningful camera models;
- DIC and image-based mechanics;
- UQ and convergence studies;
- deterministic output;
- realistic PSFs and sampling;
- multiple cameras/frames;
- performance on engineering workloads;
- transparent verification.

Features that mainly serve real-time game rendering, arbitrary graphics-programming flexibility, or adversarial geometry robustness are lower priority unless they directly support scientific use.

---

## 24. Guidance for AI agents and reviewers

Before claiming that a Riley algorithm is incorrect, answer these questions explicitly:

1. **What exact supported assumption does the proposed failure satisfy?**
2. **Is the case physically or numerically plausible in Riley's intended use?**
3. **Can the failure be reproduced under realistic camera, mesh, and scale parameters?**
4. **Is the error large enough to matter at pixel/subpixel scale?**
5. **Is this a false positive costing performance, or a false negative causing wrong output?**
6. **What is the computational cost of the proposed fix, and where is that cost paid?**
7. **Can a cheaper conservative margin, validation test, or rare fallback solve the realistic problem?**
8. **Can the current fast method be verified against a slower reference instead of replaced?**

If the answer to Question 1 is "none; the counterexample violates the assumptions," classify it as out of domain and move on.

### Do not do this

Avoid review comments of the form:

> "There is no mathematical guarantee that..."

unless the missing guarantee corresponds to a realistic supported-domain failure.

Instead write:

> "Under assumptions X and Y, the current method appears safe/unsafe because..."

or:

> "This becomes unsafe if assumption X is violated; that case appears inside/outside the supported domain."

### Preferred reasoning style

Prefer:

- quantified engineering bounds;
- scale arguments;
- performance estimates;
- reference comparisons;
- convergence tests;
- stress tests;
- explicit domain restrictions;
- cheap diagnostics;
- benchmark-driven decisions.

Avoid:

- adversarial mathematical counterexamples with no engineering relevance;
- demanding global proofs when local/tested guarantees suffice;
- turning every theoretical possibility into production complexity;
- ignoring explicitly stated assumptions;
- repeating previously dismissed out-of-domain pathologies;
- treating performance as secondary in hot-path algorithms.

---

## 25. Default decision rule

When choosing between:

**A.** a simple, fast algorithm that is demonstrably correct throughout Riley's intended engineering domain and easy to verify,

and

**B.** a much slower or more complex algorithm that additionally handles pathological inputs Riley does not claim to support,

**choose A by default.**

Choose B only when the broader guarantee is required by a real supported use case, materially improves scientific reliability, or has negligible cost/complexity.

---

## 26. Updating this document

This file is not an excuse to ignore genuine failures.

If a realistic use case violates one of these assumptions, then either:

- the implementation must change,
- the supported domain must expand,
- the assumption must be refined,
- or the limitation must be documented more clearly.

Update this file when Riley's actual operating domain changes.

The purpose is to make the engineering contract explicit, not to freeze the design.

---

## Short version for agents

If you read nothing else, follow this:

> Riley is engineering software for valid FE meshes and well-behaved calibrated camera models. Optimise for correctness inside that domain, deterministic scientific behaviour, speed, simplicity, and verification. Do not redesign hot-path algorithms around malformed elements, self-folding higher-order patches, singular/adversarial distortion maps, or arbitrary polynomial pathologies. A lack of a global mathematical proof is not itself a bug. Demonstrate a realistic in-domain failure, quantify its significance, and consider cheap margins, validation, or reference testing before proposing expensive globally rigorous machinery.
