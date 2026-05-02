# zraster RAM Breakdown Analysis

This document provides a breakdown of estimated RAM usage for the `zraster` engine under various scenarios. All cases assume **8 Threads**, **.per_tile** mode, **Tri6** elements, and a **Deforming Mesh** (Displacement Fields loaded).

## Thread-Local RAM Consumption (Per Thread)
With a 32x32 tile and SSAA factor *S*:
- **4x4 SSAA (S=4):** Tile is 128x128 sub-pixels.
    - `inv_z`: 128 KB
    - `image`: 128 KB (1 field)
    - `ideal_centers`: 256 KB
    - **Total:** ~0.5 MB per thread (**~4 MB total for 8 threads**).
- **2x2 SSAA (S=2):** ~0.13 MB per thread (**~1 MB total for 8 threads**).

## Memory Scaling Model

The total RAM usage follows the model:
`RAM = (Memory_per_Thread * Num_Threads) + Global_Frame_Buffers + Static_Data`

### Extended SSAA Scaling (32x32 Base Tile)
Because the scratch buffers (Inverse-Z, Image, and Ideal Centers) are allocated for every sub-pixel in a tile, the RAM requirement grows **quadratically** with the SSAA factor (*S*). 

The calculation for a single field is roughly: `(32 * S)^2 * (8 + 8 + 16) bytes`.

| SSAA Factor | Sub-pixel Tile | Per-Thread RAM | 8-Thread Total |
| :---        | :---           | :---           | :---           |
| 1x1         | 32x32          | 0.03 MB        | 0.24 MB        |
| 2x2         | 64x64          | 0.13 MB        | 1.04 MB        |
| 4x4         | 128x128        | 0.52 MB        | 4.16 MB        |
| 8x8         | 256x256        | 2.00 MB        | 16.00 MB       |
| 16x16       | 512x512        | 8.00 MB        | 64.00 MB       |
| 32x32       | 1024x1024      | 32.00 MB       | 256.00 MB      |
| 64x64       | 2048x2048      | 128.00 MB      | 1.02 GB        |
| 128x128     | 4096x4096      | 512.00 MB      | 4.10 GB        |

### Analysis: Quadratic Tipping Point
While the engine is "constant-dominated" at standard SSAA levels (1x1 to 4x4), the quadratic growth of the sub-pixel tile means that at extreme anti-aliasing levels, the thread-local storage becomes the primary RAM consumer.

- **At 16x16 SSAA:** 8 threads use 64 MB. Still small compared to a 24MPx frame buffer (192 MB).
- **At 64x64 SSAA:** 8 threads use **1 GB**. The "Thread-Local" memory now exceeds the "Global Constant" memory of even the Stress Case.
- **At 128x128 SSAA:** 8 threads use **4.1 GB**. 

**Optimization Note:** If extreme SSAA is required, the `tile_size_max` (default 32) should be reduced (e.g., to 8 or 16) to keep the sub-pixel scratch buffers within cache limits and manageable RAM bounds. 

To maximize performance on modern hardware, the engine should target a **1.0 MB per-thread workspace**. This ensures that the primary scratch buffers (Inverse-Z, Image, and Ideal Centers) fit entirely within the **L2 Cache** (typically 1-2 MB per core on modern CPUs), avoiding the latency of L3 or DRAM access during the hot rasterization loop.

---

## Case 1: Standard
**1 Cam, 2MPx, 2x2 SSAA, 10k Elem, 50 Frames**

| Rank | Consumer                                      | Size (MB) | Type   |
| :--- | :-------------------------------------------- | :-------- | :----- |
| 1    | Displacement Fields (50 fr, 20k nodes, XYZ)   | 24.00     | Static |
| 2    | Frame Array (2MPx, f64)                       | 16.00     | Frame  |
| 3    | Source Texture (1MPx, u8)                     | 1.00      | Static |
| 4    | UV Map (10k elems, 6 nodes)                   | 0.96      | Static |
| 5    | Thread Scratch Buffers (8 threads, 2x2)       | 1.04      | Thread |
| 6    | Original Coordinates (20k nodes, XYZ)         | 0.48      | Static |
| 7    | Connectivity Table (10k elems, Tri6)          | 0.24      | Static |
| 8    | Culled Geometry (10k elems, Current Frame)    | 1.44      | Frame  |
| 9    | Tiling Metadata (Active Tiles + Overlaps)     | 0.50      | Frame  |
| 10   | GPA/Library Overhead                          | ~5.00     | System |
|      | **TOTAL**                                     | **~50.6 MB**|      |

---

## Case 2: Deforming
**2 Cams, 12MPx, 2x2 SSAA, 50k Elem, 100 Frames**

| Rank | Consumer                                      | Size (MB) | Type   |
| :--- | :-------------------------------------------- | :-------- | :----- |
| 1    | Displacement Fields (100 fr, 100k nodes, XYZ) | 240.00    | Static |
| 2    | Frame Array (12MPx, f64)                      | 96.00     | Frame  |
| 3    | Culled Geometry (50k elems, Current Frame)    | 7.20      | Frame  |
| 4    | UV Map (50k elems, 6 nodes)                   | 4.80      | Static |
| 5    | Original Coordinates (100k nodes, XYZ)        | 2.40      | Static |
| 6    | Tiling Metadata (2 cams, 50k overlaps)        | 2.50      | Frame  |
| 7    | Thread Scratch Buffers (8 threads, 2x2)       | 1.04      | Thread |
| 8    | Connectivity Table (50k elems, Tri6)          | 1.20      | Static |
| 9    | Source Texture (4MPx, u8)                     | 4.00      | Static |
| 10   | GPA/Library Overhead                          | ~15.00    | System |
|      | **TOTAL**                                     | **~374.1 MB**|     |

---

## Case 3: High-Res Stress
**4 Cams, 24MPx, 4x4 SSAA, 1e5 Elem, 100 Frames**

| Rank | Consumer                                      | Size (MB) | Type   |
| :--- | :-------------------------------------------- | :-------- | :----- |
| 1    | Displacement Fields (100 fr, 200k nodes, XYZ) | 480.00    | Static |
| 2    | Frame Array (24MPx, f64)                      | 192.00    | Frame  |
| 3    | Culled Geometry (100k elems, Current Frame)    | 14.40     | Frame  |
| 4    | UV Map (100k elems, 6 nodes)                  | 9.60      | Static |
| 5    | Source Texture (24MPx, u8)                    | 24.00     | Static |
| 6    | Tiling Metadata (4 cams, ~200k overlaps)      | 10.00     | Frame  |
| 7    | Original Coordinates (200k nodes, XYZ)        | 4.80      | Static |
| 8    | Thread Scratch Buffers (8 threads, 4x4)       | 4.16      | Thread |
| 9    | Connectivity Table (100k elems, Tri6)         | 2.40      | Static |
| 10   | GPA/Library Overhead                          | ~40.00    | System |
|      | **TOTAL**                                     | **~781.3 MB**|     |
