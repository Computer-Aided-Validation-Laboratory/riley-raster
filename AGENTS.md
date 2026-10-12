# Riley — Agent Instructions

Riley is a high-performance Zig rasteriser for scientific camera simulation and digital image correlation (DIC). Prioritise **correctness, performance, and simplicity for users** together.

## Read first

- **Project documentation:** Start with [`./dev/README.md`](./dev/README.md). Follow its links and read the relevant uppercase Markdown documents in `./dev/` before changing an affected subsystem. Treat these documents as the source of truth for Riley's current architecture, assumptions, workflows, and verification procedures.
- **Organisation-wide standards:** Read and follow the [CAVL Performance Oriented Software Guide](https://github.com/Computer-Aided-Validation-Laboratory/styleguides/blob/main/guides/performance_oriented_software_guide.md) and [CAVL Zig Style Guide](https://github.com/Computer-Aided-Validation-Laboratory/styleguides/blob/main/guides/zig_style_guide.md). Read the guides themselves, not just these links; use a local checkout if web access is unavailable. Do not guess their contents.

## Riley-specific rules

1. **Engineering, not formal proof.** Riley is a run-and-done simulation tool. Work within documented input and numerical assumptions; do not add complexity to support arbitrary pathological cases outside that contract.
2. **Validate once, upstream.** Check external inputs at preparation boundaries. Inside hot computational stages, rely on established invariants or assertions; do not repeatedly check `isFinite` or revalidate inputs.
3. **Performance is a design requirement.** Consider data layout, cache traffic, branches, SIMD, threading, and allocations from the start. Benchmark representative workloads rather than assuming precomputation or abstraction improves performance.
4. **Keep hot paths lean.** Avoid per-element/pixel allocation, I/O, logging, unnecessary indirection, and repeated work. Prefer explicit ownership and predictable memory access.
5. **Respect numerical conventions.** Preserve documented coordinates, element ordering, camera/pixel conventions, tolerances, determinism, and supported approximations unless the task explicitly changes them.
6. **Prefer simple, cohesive code.** Avoid speculative generality, elaborate fallback machinery, and gratuitous single-use helper functions. Keep readable code together when that makes control flow clearer.
7. **Preserve subsystem boundaries.** Understand existing geometry, distortion, culling/hulls, rasterisation, shading, and render orchestration before changing their interfaces or responsibilities.
8. **Keep user-facing behaviour stable.** Avoid incidental API changes, dependencies, arbitrary capacity limits, or unrelated refactors.
9. **Verify numerical changes.** Add focused tests and independent references where possible. Exercise relevant element types, camera modes, and edge cases *within supported assumptions*; do not blindly regenerate gold outputs.
10. **Report evidence.** Run applicable formatting, tests, and benchmarks described in `./dev/`; distinguish measured results from hypotheses and state what was not tested.

For substantial changes, first identify the relevant `./dev/` documentation and affected code; then implement the smallest cohesive change and summarise its verification.
