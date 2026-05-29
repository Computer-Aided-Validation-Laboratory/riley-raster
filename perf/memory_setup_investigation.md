# Memory Setup Investigation

## Summary

The large `memory` setup cost is not related to the outer render-group
scheduler. It occurs before any call into `dispatchFrameJobsOffline` or
`dispatchFrameJobsInOrder`.

The exact `Setup time` measurement in `riley.zig` spans:

- start: [src/riley/zig/riley.zig:1368](/home/lloydf/riley/src/riley/zig/riley.zig:1368)
- end: [src/riley/zig/riley.zig:1415](/home/lloydf/riley/src/riley/zig/riley.zig:1415)

The code between those hooks is the only code contributing to the reported
`Setup time`.

## Timing Hooks

The setup timer begins at:

- [src/riley/zig/riley.zig:1368](/home/lloydf/riley/src/riley/zig/riley.zig:1368)

```zig
const time_start_render = Timestamp.now(summary_io, .awake);
```

The setup timer ends at:

- [src/riley/zig/riley.zig:1415](/home/lloydf/riley/src/riley/zig/riley.zig:1415)

```zig
const time_end_setup = Timestamp.now(summary_io, .awake);
```

The measured setup duration is then stored at:

- [src/riley/zig/riley.zig:1416](/home/lloydf/riley/src/riley/zig/riley.zig:1416)
  to [src/riley/zig/riley.zig:1420](/home/lloydf/riley/src/riley/zig/riley.zig:1420)

The printed `Setup time` label comes from:

- [src/riley/zig/report.zig:238](/home/lloydf/riley/src/riley/zig/report.zig:238)

## What Happens Between The Hooks

Between `time_start_render` and `time_end_setup`, the code does:

1. Optional output directory create/open
   - [src/riley/zig/riley.zig:1370](/home/lloydf/riley/src/riley/zig/riley.zig:1370)
     to [src/riley/zig/riley.zig:1378](/home/lloydf/riley/src/riley/zig/riley.zig:1378)
2. Static arena setup
   - [src/riley/zig/riley.zig:1380](/home/lloydf/riley/src/riley/zig/riley.zig:1380)
     to [src/riley/zig/riley.zig:1382](/home/lloydf/riley/src/riley/zig/riley.zig:1382)
3. Camera preparation
   - [src/riley/zig/riley.zig:1384](/home/lloydf/riley/src/riley/zig/riley.zig:1384)
4. Frame and field counting
   - [src/riley/zig/riley.zig:1390](/home/lloydf/riley/src/riley/zig/riley.zig:1390)
     to [src/riley/zig/riley.zig:1391](/home/lloydf/riley/src/riley/zig/riley.zig:1391)
5. Mesh static setup and nodal global scaling
   - [src/riley/zig/riley.zig:1403](/home/lloydf/riley/src/riley/zig/riley.zig:1403)
     to [src/riley/zig/riley.zig:1405](/home/lloydf/riley/src/riley/zig/riley.zig:1405)
6. All-frames output buffer initialization
   - [src/riley/zig/riley.zig:1407](/home/lloydf/riley/src/riley/zig/riley.zig:1407)
     to [src/riley/zig/riley.zig:1414](/home/lloydf/riley/src/riley/zig/riley.zig:1414)

## Position Relative To Dispatch

`initAllFramesBuffer` is entirely before the outer dispatch machinery.

The dispatch phase starts only after setup is finished:

- dispatch timer starts:
  [src/riley/zig/riley.zig:1421](/home/lloydf/riley/src/riley/zig/riley.zig:1421)
- in-order dispatch call:
  [src/riley/zig/riley.zig:1423](/home/lloydf/riley/src/riley/zig/riley.zig:1423)
  to [src/riley/zig/riley.zig:1437](/home/lloydf/riley/src/riley/zig/riley.zig:1437)
- offline dispatch call:
  [src/riley/zig/riley.zig:1439](/home/lloydf/riley/src/riley/zig/riley.zig:1439)
  to [src/riley/zig/riley.zig:1452](/home/lloydf/riley/src/riley/zig/riley.zig:1452)

This means:

- `initAllFramesBuffer` is in front of `std.Thread`
- `initAllFramesBuffer` is also in front of `dispatchFrameJobs*`
- outer scheduling changes cannot explain the `Setup time` gap

## Exact `memory` vs `disk` Differences Inside Setup

There are only two differences between `memory` and `disk` in the timed setup
region.

### 1. Output directory handling

In `bench_dicuq`, `disk` and `both` pass a non-null `out_dir_path`, while
`memory` passes `null`:

- [src/bench_dicuq.zig:210](/home/lloydf/riley/src/bench_dicuq.zig:210)
  to [src/bench_dicuq.zig:217](/home/lloydf/riley/src/bench_dicuq.zig:217)

That means only `disk` does:

- [src/riley/zig/riley.zig:1371](/home/lloydf/riley/src/riley/zig/riley.zig:1371)
  to [src/riley/zig/riley.zig:1376](/home/lloydf/riley/src/riley/zig/riley.zig:1376)

This is small and goes in the opposite direction. It makes `disk` do slightly
more setup work, not less.

### 2. `initAllFramesBuffer`

This is the only meaningful mode-dependent branch:

- [src/riley/zig/riley.zig:244](/home/lloydf/riley/src/riley/zig/riley.zig:244)
  to [src/riley/zig/riley.zig:273](/home/lloydf/riley/src/riley/zig/riley.zig:273)

Behavior:

- `memory` or `both`
  - scan all cameras for the max image dimensions
  - build the `[camera, time, field, y, x]` dimensions
  - allocate the full NDArray backing store
- `disk`
  - return `null`

The key condition is:

- [src/riley/zig/riley.zig:252](/home/lloydf/riley/src/riley/zig/riley.zig:252)

```zig
if (config.save_strategy == .memory or config.save_strategy == .both) {
```

The allocation itself is:

- [src/riley/zig/riley.zig:266](/home/lloydf/riley/src/riley/zig/riley.zig:266)
  to [src/riley/zig/riley.zig:269](/home/lloydf/riley/src/riley/zig/riley.zig:269)

```zig
return try ndarray.NDArray(T).initFlat(
    outer_alloc,
    dims[0..],
);
```

For `disk`, the function returns:

- [src/riley/zig/riley.zig:272](/home/lloydf/riley/src/riley/zig/riley.zig:272)

```zig
return null;
```

## Allocation Path Behind `initAllFramesBuffer`

The full-stack memory path goes through:

- [src/riley/zig/ndarray.zig:54](/home/lloydf/riley/src/riley/zig/ndarray.zig:54)
  to [src/riley/zig/ndarray.zig:63](/home/lloydf/riley/src/riley/zig/ndarray.zig:63)

`initFlat` does:

1. compute total element count
2. allocate the full backing slice
   - [src/riley/zig/ndarray.zig:60](/home/lloydf/riley/src/riley/zig/ndarray.zig:60)
3. allocate and populate dims/strides metadata
   - [src/riley/zig/ndarray.zig:30](/home/lloydf/riley/src/riley/zig/ndarray.zig:30)
     to [src/riley/zig/ndarray.zig:48](/home/lloydf/riley/src/riley/zig/ndarray.zig:48)

## Important Negative Finding

There is no explicit full-image-buffer `@memset` in the setup region in the
current code.

The earlier redundant global clear was removed and has not been reintroduced.
The setup-time code path no longer contains a whole-stack clear in `riley`.

## Conclusion

Within the exact `Setup time` hooks, the only meaningful `memory` vs `disk`
difference is `initAllFramesBuffer`.

So:

- the large `memory` setup cost is not caused by outer scheduling
- it is not caused by the `std.Thread` revert
- it is not caused by directory setup
- it is not caused by an explicit full-stack `@memset` in the current setup
  code
- it is attributable to the full retained-image-stack NDArray allocation path
  in `initAllFramesBuffer`
