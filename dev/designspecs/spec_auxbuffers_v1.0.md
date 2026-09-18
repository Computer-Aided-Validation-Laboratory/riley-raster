# Project Specification: Riley Auxiliary Buffers v1.0 – Depth Buffer

## 1. Background

Riley currently provides two main raster entry points:

* `raster`, where Riley allocates the output image and returns it.
* `rasterInto`, where the caller provides output storage for Riley to fill.

Rendered images are currently stored directly in `ndarray.NDArray(F)` with dimensions:

```text
(cameras, frames, channels, y_pixels, x_pixels)
```

Riley also computes inverse depth internally during rasterisation for visibility testing. This project will expose a resolved depth buffer as Riley's first auxiliary raster output.

The project has two purposes:

1. introduce useful image and auxiliary buffer abstractions into Riley;
2. provide a contained project for learning performant Zig through work on real renderer code.

The implementation should follow the Computer Aided Validation Lab performance oriented software and zig style guides. The APIs shown below are illustrative rather than fixed. They may be changed where a different design better fits the existing codebase or Riley's style conventions.

---

## 2. Scope

The project should introduce three related concepts:

* `ImageBuffer`, representing a rendered image;
* `AuxBuffer`, representing additional raster outputs;
* `RenderBuffers`, grouping the image and requested auxiliary outputs.

The first and only auxiliary output in v1.0 is depth.

The implementation must support:

* Riley allocated output through `raster`;
* caller allocated output through `rasterInto`;
* rendering with no auxiliary buffers;
* rendering with one resolved depth buffer;
* camera resolution depth output;
* supersampled rendering;
* existing camera distortion models;
* existing threaded rasterisation.

Saving auxiliary buffers to disk is not part of the core project but is set as an extension objective.

---

## 3. ImageBuffer

Introduce an `ImageBuffer(F)` abstraction around Riley's existing `ndarray.NDArray(F)`.

An image buffer has the fixed semantic dimensions:

```text
(cameras, frames, channels, y_pixels, x_pixels)
```

A possible interface is:

```zig
pub fn ImageBuffer(comptime F: type) type {
    return struct {
        array: ndarray.NDArray(F),

        pub const camera_dim: usize = 0;
        pub const frame_dim: usize = 1;
        pub const channel_dim: usize = 2;
        pub const y_dim: usize = 3;
        pub const x_dim: usize = 4;

        // Named dimension accessors...
    };
}
```

The wrapper should:

* contain the existing `NDArray(F)` rather than duplicate its storage;
* validate that the array has five dimensions;
* provide named access to its semantic dimensions;
* remove the need for renderer code to interpret numeric dimension indices directly.

For example:

```zig
image.cameras()
image.frames()
image.channels()
image.yPixels()
image.xPixels()
```

Validation against a particular camera or render configuration should remain separate from basic `ImageBuffer` construction. Existing image output should be migrated to use this abstraction.

---

## 4. Auxiliary Buffers

Auxiliary raster outputs should use a tagged union.

For v1.0 the only variant is depth:

```zig
pub fn AuxBuffer(comptime F: type) type {
    return union(enum) {
        depth: ndarray.NDArray(F),
    };
}
```

This design establishes a place for future outputs without implementing them now.

Possible future buffers include normals, UV coordinates or element identifiers, but these are outside the scope of this project.

### Depth dimensions

Depth is scalar, so the resolved depth buffer should have dimensions:

```text
(cameras, frames, y_pixels, x_pixels)
```

It should therefore contain no channel dimension.

Depth buffer validation should check that:

* the array has four dimensions;
* camera and frame counts match the render;
* `y_pixels` and `x_pixels` match the camera output resolution.

---

## 5. RenderBuffers

The complete result of a render should group the image and auxiliary buffers.

A possible design is:

```zig
pub fn RenderBuffers(comptime F: type) type {
    return struct {
        image_buffer: ImageBuffer(F),
        aux_buffers: []AuxBuffer(F),
    };
}
```

A render always contains one image buffer.

It may contain zero or more auxiliary buffers.

For v1.0:

```text
image only     -> aux_buffers.len == 0
image + depth  -> one .depth buffer
```

Duplicate depth buffers should not be permitted. The precise ownership and helper API should follow normal Riley allocator conventions. A `deinit` helper may be introduced if this makes ownership clearer.

---

## 6. Requesting Auxiliary Outputs

`RasterConfig` should specify which auxiliary outputs are required.

For example:

```zig
pub const AuxBufferType = enum {
    depth,
};
```

with:

```zig
aux_outputs: []const AuxBufferType = &.{},
```

The default should request no auxiliary outputs.

For example:

```zig
config.aux_outputs = &.{};
```

renders only the image, while:

```zig
config.aux_outputs = &.{ .depth };
```

requests image and depth output. The implementation should reject unsupported or duplicate auxiliary output requests.

---

## 7. `raster`

`raster` remains the Riley allocated entry point.

It should:

1. determine the requested outputs from `RasterConfig`;
2. allocate the image buffer;
3. allocate requested auxiliary buffers;
4. construct `RenderBuffers`;
5. perform the render;
6. return the completed buffers.

For a depth enabled render, the result is conceptually:

```text
RenderBuffers
|
+-- ImageBuffer
|   |
|   +-- NDArray(F)
|       (camera, frame, channel, y, x)
|
+-- AuxBuffer.depth
    |
    +-- NDArray(F)
        (camera, frame, y, x)
```

Allocation failure must clean up any storage already allocated.

---

## 8. `rasterInto`

`rasterInto` remains the caller allocated entry point.

The caller creates the required buffers before calling Riley:

```zig
try rasterInto(
    scene,
    camera,
    config,
    &render_buffers,
);
```

Before rendering, Riley should validate that the supplied buffers match the requested render.

For the image this includes:

* five dimensions;
* camera count;
* frame count;
* channel count;
* image resolution.

For depth this includes:

* four dimensions;
* camera count;
* frame count;
* image resolution.

The supplied auxiliary buffers must also match `RasterConfig.aux_outputs`.

For example:

```zig
config.aux_outputs = &.{ .depth };
```

requires one depth buffer.

`rasterInto` must not:

* replace caller supplied output buffers;
* resize them;
* free them;
* allocate alternative final output buffers.

Renderer scratch storage remains Riley managed.

Existing `.none` behaviour should be preserved.

---

## 9. Depth Semantics

The public depth buffer should contain camera space depth in Riley's normal geometric length units.

Riley's internal inverse depth representation remains an implementation detail.

The existing rasteriser already computes the visibility information required to determine depth. This project should reuse that state rather than introduce another geometry pass or another full subpixel depth representation.

The implementation should expose the resolved depth value already determined by the raster process and write it into the requested depth buffer.

Pixels containing no visible geometry should use a documented background value. Positive infinity should be used if this is compatible with Riley's existing numerical conventions.

---

## 10. Supersampling and Depth Resolve

The public depth buffer is always at camera resolution:

```text
(cameras, frames, y_pixels, x_pixels)
```

It should not expose Riley's internal subpixel representation.

When supersampling is enabled, the depth written for a camera pixel should correspond to the nearest visible subpixel surface.

For example, visible subpixel depths of:

```text
1 m
1 m
10 m
10 m
```

should resolve to:

```text
1 m
```

and not their average.

Riley already performs the relevant visibility calculations internally. The project should integrate depth output into that existing process rather than implement a separate depth algorithm.

---

## 11. Image and Depth Correspondence

Image and depth output from the same render must describe the same camera geometry.

For:

```text
image[camera, frame, channel, y, x]
```

the corresponding depth value is:

```text
depth[camera, frame, y, x]
```

They must therefore use the same:

* camera pose;
* projection;
* lens distortion;
* pixel locations;
* subpixel sample locations;
* geometry coverage;
* visibility decisions.

Lens distortion should affect depth through the same raster sample geometry used for the image.

No separate distortion pass should be applied to the resolved depth buffer.

---

## 12. Point Spread Function

The image point spread function models image formation and must not be applied to depth.

Conceptually:

```text
                 rasterisation
                      |
              subpixel geometry
                /           \
               /             \
              v               v
       image samples     inverse depth
              |               |
         image resolve    depth output
        including PSF
              |               |
              v               v
         ImageBuffer      AuxBuffer.depth
```

Changing the image PSF should therefore not alter depth values when the geometry and sample locations are unchanged.

---

## 13. Performance Requirements

The default configuration requests no auxiliary buffers.

When depth is not requested:

* no depth output array should be allocated;
* no depth output should be written;
* no depth resolve work should be performed solely to support this feature;
* existing image results should remain unchanged.

Image only rendering performance should remain within normal benchmark variation compared with the existing implementation.

For this project, a regression of less than approximately **1%** may be treated as run to run noise rather than a meaningful performance change.

The implementation should not:

* perform a second geometry rasterisation;
* allocate a second full subpixel depth buffer;
* retain subpixel depth after it is no longer required;
* add work to performance critical loops when no auxiliary output is requested unless that work is effectively free.

---

# Deliverables

## 1. ImageBuffer

Deliver an `ImageBuffer(F)` abstraction that:

* wraps the existing image `NDArray(F)`;
* defines the five image dimensions semantically;
* provides named dimension accessors;
* validates its dimensionality;
* is used by the renderer in place of directly exposing the raw image array where appropriate.

## 2. Auxiliary Buffer API

Deliver:

* an `AuxBuffer(F)` tagged union;
* a `.depth` variant;
* depth dimensionality and shape validation;
* an `AuxBufferType` used to request auxiliary outputs.

No additional auxiliary buffer types are required.

## 3. RenderBuffers

Deliver a `RenderBuffers(F)` abstraction containing:

* one `ImageBuffer`;
* zero or more `AuxBuffer` values;
* clear ownership and cleanup behaviour.

It must support both image only and image plus depth rendering.

## 4. `RasterConfig` Integration

Extend `RasterConfig` so callers can request auxiliary outputs.

The default configuration must continue to render only the image.

Invalid or duplicate requests should produce clear errors.

## 5. `raster` Integration

Update `raster` so Riley allocates and returns `RenderBuffers`.

Allocation should depend on the requested outputs.

Partial allocation failure must be handled correctly.

## 6. `rasterInto` Integration

Update `rasterInto` so callers can provide `RenderBuffers`.

Riley should validate the supplied storage before use and preserve caller ownership.

## 7. Depth Output

Expose camera space depth using Riley's existing visibility calculations.

Depth output must:

* be at camera resolution;
* contain the nearest visible surface for each pixel;
* work with supersampling;
* remain geometrically aligned with the image;
* work with distorted cameras;
* remain independent of the image PSF.

## 8. Tests

Update the existing renderer test suites to exercise image and depth output alongside the existing camera, geometry, supersampling and threading coverage.

Add a small focused set of unit tests for genuinely new behaviour, including:

* valid and invalid `ImageBuffer` shapes;
* valid and invalid depth buffer shapes;
* image only `RenderBuffers`;
* image plus depth `RenderBuffers`;
* configuration and supplied buffer mismatch;
* duplicate depth requests;
* known depth values;
* nearest surface behaviour at partially covered pixels;
* background depth behaviour.

Avoid duplicating broad renderer tests that already exist. Where an existing test exercises relevant geometry or camera behaviour, extend it to check depth as well.

Depth tests should compare numerical values directly.

## 9. Performance Check

Benchmark representative image only renders before and after the change.

Confirm that enabling the new infrastructure while requesting no auxiliary buffers changes image only performance by less than approximately 1%.

Also confirm that no additional full resolution or subpixel depth storage is allocated when depth is not requested.

---

# Extension Goal: Saving Auxiliary Buffers

Once the core buffer API is complete, integration with Riley's existing `SaveStrategy` may be added as an extension.

This would include:

* saving requested auxiliary buffers when disk output is enabled;
* deterministic auxiliary buffer filenames;
* quantitative depth file formats;
* separate image and auxiliary save options where required;
* ensuring depth values are not silently converted to display image intensities;
* ensuring `.both` saves the same resolved buffers returned to the caller without rerendering.

This extension should build on the completed `RenderBuffers` interface rather than influencing the core raster implementation unnecessarily.
