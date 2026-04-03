# Performance Metrics Definitions

The following metrics are used across the `zigraster` project to evaluate and compare the performance of different rasterization and geometry implementations.

## Throughput Metrics (Millions of units per second)

### 1. MPx/s (Mega-Pixels per Second)
- **Definition**: Throughput relative to the total number of camera (output) pixels.
- **Formula**: `(pixels_x * pixels_y) / (raster_time_sec * 1e6)`
- **Note**: This ignores sub-sampling. It represents the "sensor-wide" rate at the target resolution.

### 2. MsubPx/s (Mega-SubPixels per Second)
- **Definition**: Throughput relative to the total number of sub-pixels defined by the sampling rate.
- **Formula**: `(pixels_x * pixels_y * sub_samp * sub_samp) / (raster_time_sec * 1e6)`
- **Note**: This represents the raw processing rate of the sub-pixel grid, regardless of whether a pixel is covered by an element.

### 3. MShades/s (Mega-Shades per Second)
- **Definition**: Throughput relative to the number of *actually shaded* camera pixels.
- **Formula**: `(shaded_camera_pixels) / (raster_time_sec * 1e6)`
- **Note**: A camera pixel is counted as "shaded" if at least one of its sub-pixels was covered by an element and passed the depth test.

### 4. MsubShades/s (Mega-SubShades per Second)
- **Definition**: Throughput relative to the number of *actually shaded* sub-pixels.
- **Formula**: `(total_shaded_sub_pixels) / (raster_time_sec * 1e6)`
- **Note**: This is the most direct measure of the shader's workload. Every sub-pixel covered by an element that passes the depth test is counted.

### 5. MElems/s (Mega-Elements per Second)
- **Definition**: Throughput of the geometry pipeline (projection, bounding box calculation, tiling) by number of elements processed)
- **Formula**: `(total_elements_in_scene) / ((geometry_time_sec + tiling_time_sec) * 1e6)`
- **Note**: This measures the efficiency of the "front-end" of the renderer.

### 6. MNodes/s (Mega-Nodes per Second)
- **Definition**: Throughput of the geometry pipeline (projection, bounding box calculation, tiling) by number of nodes processed in the scene.
- **Formula**: `(total_elements_in_scene*nodes_per_elem) / ((geometry_time_sec + tiling_time_sec) * 1e6)`
- **Note**: This measures the efficiency of the "front-end" of the renderer.

### 7. MOps/s (Mega-Operations per Second)
- **Definition**: Throughput of the whole pipeline, how many millions of node-weight multiplications per second
- **Formula**: `(nodes_per_elem*pixels_x * pixels_y * sub_samp * sub_samp) / ((geometry_time_sec + tiling_time_sec+raster_time_sec) * 1e6)`
- **Note**: This measures the efficiency of the "front-end" of the renderer.


## Relationship
- For a standard single-sample-per-pixel (`sub_samp = 1`) full-screen render where every pixel is covered:
`MPx/s == MsubPx/s == MShades/s == MsubShades/s`
- Standard benchmarks use sub_samp = 2
