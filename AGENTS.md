# Riley — Agent Instructions

Riley is a high-performance Zig rasteriser for scientific camera simulation and digital image correlation (DIC). Prioritise **correctness, performance, and simplicity for users** together.

## 1. Development workflow — mandatory stage gates

**Default to Stage 1. Never advance stages without explicit user direction.**

### Stage 1 — Zig development (default)

- Develop, explore and refactor features entirely in Zig.
- Modify Zig implementation, types, internal interfaces, tests and Zig demos as needed.
- Do not propagate features into the C ABI, Cython or Python.
- Run focused tests and the relevant Verification and Basic suites in **Debug, f64, SIMD on**.
- Iterate freely on the Zig architecture without preserving backwards compatibility.

```bash
zig build test-verif -Dprecision=f64 -Dsimd=on
zig build test-basic -Dprecision=f64 -Dsimd=on
```

### Stage 2 — Zig consolidation and full verification

- Enter this stage only when the user requests full verification or consolidation.
- Complete the Zig refactoring and verify the agreed feature behaviour.
- Run the Full suite in **ReleaseSafe, f64, SIMD on and off**.
- Investigate relevant failures without silently changing numerical references.
- Keep all changes within Zig. Do not propagate to the C ABI or Python.

```bash
zig build test-full -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe
zig build test-full -Dprecision=f64 -Dsimd=off -Doptimize=ReleaseSafe
```

### Stage 3 — Language bindings and integration

- **Only enter this stage after explicit user approval of the Zig implementation and an instruction to propagate the feature.**
- Implement the C ABI, Cython and Python interfaces.
- Follow the existing binding conventions and keep interfaces minimal.
- Add focused integration tests and run the relevant Python test suite.
- Do not expand the binding API beyond the approved Zig feature.

**Passing tests, completing a feature or finishing a plan does not authorise advancing to another stage.**

## 2. Documentation and codebase exploration

- **Project documentation:** `dev/README.md` and the relevant documents in `dev/` define Riley's architecture, assumptions and verification procedures.
- **Organisation standards:** Follow the [CAVL Performance Oriented Software Guide](https://github.com/Computer-Aided-Validation-Laboratory/styleguides/blob/main/guides/performance_oriented_software_guide.md) and [CAVL Zig Style Guide](https://github.com/Computer-Aided-Validation-Laboratory/styleguides/blob/main/guides/zig_style_guide.md).
- **Read selectively:** For routine work, use these instructions and consult relevant documentation sections only. For substantial feature design or subsystem architecture changes, review the applicable project documents and both style guides in detail, reading the Performance Guide first.
- **Focused exploration:** Inspect user-specified reference modules or demos first. Otherwise inspect a narrowly scoped related implementation. Expand only when a concrete dependency or problem requires it.
- **Minimise context:** Use targeted searches, avoid unnecessary file reads and do not repeatedly read unchanged code or documentation already available in context.

## 3. Riley-specific engineering rules

1. **Engineering, not formal proof.** Riley is a run-and-done simulation tool. Work within documented input and numerical assumptions; do not add complexity for arbitrary mathematical pathologies outside that contract.

2. **Validate once, upstream.** Check external inputs at preparation boundaries. Inside hot computational stages, rely on established invariants or assertions; do not repeatedly check `isFinite` or revalidate inputs.

3. **Performance is a design requirement.** Consider data layout, cache traffic, branches, SIMD, threading and allocations from the start. Benchmark representative workloads rather than assuming precomputation or abstraction improves performance.

4. **Keep hot paths lean.** Avoid per-element/pixel allocation, I/O, logging, unnecessary indirection and repeated work. Prefer explicit ownership and predictable memory access.

5. **Respect numerical conventions.** Preserve documented coordinates, element ordering, camera/pixel conventions, tolerances, determinism and supported approximations unless explicitly changed.

6. **Prefer simple, cohesive code.** Avoid speculative generality, elaborate fallback machinery and gratuitous single-use helpers. Keep readable code together when that makes control flow clearer.

7. **Preserve subsystem boundaries.** Respect the responsibilities of geometry, distortion, culling/hulls, rasterisation, shading and render orchestration. Inspect relevant interfaces before changing their responsibilities.

8. **Allow API evolution.** Riley is under active development. Prefer clean, consistent APIs over backwards compatibility. Avoid deprecated aliases, compatibility shims and legacy paths. Update affected call sites within the current development stage only.

9. **Verify numerical changes.** Add focused tests and independent references where possible. Exercise relevant element types, camera modes and edge cases within supported assumptions. Do not blindly regenerate gold outputs.

10. **Report evidence.** Run formatting and verification appropriate to the current development stage. Distinguish measured results from hypotheses and state what was not tested.

## 4. Agent execution efficiency

- Follow the task specification and implementation plan; revisit agreed architectural decisions only for concrete reasons.
- Prefer coherent implementation and refactoring batches over repeated small edits and checks.
- Use deterministic scripts for large mechanical transformations where practical.
- Capture verbose compiler, test and benchmark output in local logs. Report concise results and relevant failure details.
- Avoid unnecessary repeated checks, broad repository searches and unsolicited polishing.
- Never regenerate existing gold references without explicit approval. Follow `dev/TESTING.md` for reference generation and review.
- **Do not update documentation, unrelated demos or docstrings unless explicitly requested.** Documentation consolidation is a separate development activity.
- Keep communication concise. Summarise changes, verification and outstanding issues without narrating routine operations.
- Stop when the requested work is complete.

## 5. Zig Style Guide Summary

These rules summarise the [CAVL Zig Style Guide](https://github.com/Computer-Aided-Validation-Laboratory/styleguides/blob/main/guides/zig_style_guide.md). Apply them to all Zig code.

### Types and architecture

1. **Use meaningful types.** Prefer enums, optionals and tagged unions over strings, manual tags, loosely coupled flags and redundant booleans.
2. **Model variants explicitly.** Use `union(enum)` for closed runtime variants with different data representations; enums for named states and `?T` for optional values.
3. **Express ownership and mutability.** Prefer `[]const T` and `[]T` for borrowed arrays; `*const T` and `*T` for objects. Use const inputs wherever possible.
4. **Choose dispatch deliberately.** Prefer compile-time dispatch for compile-time-known implementations, tagged unions or enums for closed runtime variants, and function pointers only for genuinely dynamic implementations.
5. **Avoid unnecessary abstraction.** Do not introduce runtime interfaces, indirection or generic machinery without a concrete need. Prefer direct, explicit implementations.

### Memory and resource management

6. **Allocation must be explicit.** Pass allocators to operations that allocate, resize or free. Do not store allocators in application types or hide allocation.
7. **Respect allocator lifetimes.** Use `outer_alloc` for returned memory and `local_alloc` for scratch memory. Never return memory backed by a local allocator.
8. **Keep cleanup local.** Use `defer` and `errdefer` around resource acquisition. Make ownership transfers and cleanup responsibilities obvious.
9. **Keep hot paths allocation-free.** Avoid unnecessary copies, temporary buffers, indirect calls and unpredictable memory access in performance-critical kernels.

### Errors and correctness

10. **Distinguish failures from programming errors.** Use Zig errors for legitimate runtime failures, `std.debug.assert` for internal invariants, and `unreachable` only for impossible states.
11. **Fail explicitly.** Do not use `catch unreachable`, silent fallbacks or fabricated defaults to conceal legitimate runtime failures.
12. **Validate before expensive work.** Check cheap preconditions before allocation or computation; rely on established invariants within validated kernels.

### Performance and specialisation

13. **Use `comptime` deliberately.** Specialise types, dimensions, policies and kernels when compile-time knowledge improves generated code. Avoid excessive specialisation.
14. **Use SIMD deliberately.** Prefer `@Vector` when the data layout and algorithm suit vectorisation. Consider memory access, alignment, vector width and generated code.
15. **Restrict `inline`.** Use `inline` and `inline for` only when compile-time semantics or demonstrated performance justify expansion.
16. **Measure performance.** Do not assume an optimisation helps. Benchmark representative workloads when evaluating performance changes.

### Modules and interfaces

17. **Keep imports direct.** Follow `dev/FILESTRUCTURE.md` for declaration ownership, module naming, imports and public reexports. Avoid accidental reexport chains.
18. **Keep C ABI boundaries explicit.** When Stage 3 is authorised, export only C-compatible representations. Keep native Zig internals behind the boundary.
19. **Use explicit I/O and concurrency.** Pass `std.Io` to I/O operations and prefer its concurrency facilities unless direct `std.Thread` control is justified.

### Naming, structure and testing

20. **Use descriptive names and simple expressions.** Functions are verbs; types are nouns. Follow `dev/ABBREVIATIONS.md`. Avoid ambiguous names, unnecessary casts and deeply nested expressions.
21. **Organise files consistently.** Follow `dev/FILESTRUCTURE.md` for file and declaration ordering. Run `zig fmt` on modified files.
22. **Test meaningful behaviour.** Use local deterministic tests, `std.testing.allocator`, `std.testing.io` when required, and tests for deliberately returned errors. Add regression tests for reproducible bugs.
