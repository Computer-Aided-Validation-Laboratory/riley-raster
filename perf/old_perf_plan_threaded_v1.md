# Scaling and Performance Experiments: ZRaster

1) Single thread: sensor size scaling
2) Single thread: subpixel tile size scaling
3) Single thread: geometry scaling
4) Multi thread:  within frame, single frame in flight scaling
5) Multi thread:  over frames, multiple frame in flight scaling

## Performance Axes
- *Threads*
- *Sensor Size*
- *Mesh Size*
- *Sub-Pixel Tile Size* = tile_size * SSAA

## Scenes
- *Raster Test*
    - Full screen: Minimal elements, 1 for quads 2 for triangles
- *Geometry Test*
    - Full screen: 1e5 - 1e6 elements 
- *DIC Sims*
    - Texture shading only: cubic_lut_lerp?
    - Plate with a hole: *tri6, quad8* 
    - Cameras: *1,2,4*
    - Sensor: *5 MPx, 24MPx*
    - Frames: *2,10,100,1000*

## Metrics
- Geometry Pre-Process: MElem/s
- Raster Loop: MPx/s
- Average time per frame
    - With and without IO
- End-to-end time
    - With and without IO

speedup = T_1 / T_N
parallel_efficiency = speedup / N

apparent_serial_fraction(N) =
    ((1 / speedup) - (1 / N)) / (1 - (1 / N))

## Threads
- Ryzen 7 Laptop: 1,2,4,8
- Threadripper Workstation: 1,2,4,8,16,32,64

## Sensor Size Scaling, Single Threaded:
- Constants: SSAA 2x2, tile size = 32x32

- Sensor Sizes:
    - 4/3 aspect ratio so 4/3 * px^2 = MPx
    - 400x250 pixels = 0.1 MPx
    - 1 MPx = 
    - 5 MPx =
    - 8 MPx =
    - 12 MPx =
    - 24 MPx =
    - 50 MPx =
    - 100 MPx = 4/3 * px^2 = 100e6

