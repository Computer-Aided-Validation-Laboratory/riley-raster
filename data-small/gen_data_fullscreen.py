import numpy as np
import os
from pathlib import Path

def save_case(name, coords, connect, disp_x, disp_y, disp_z):
    out_dir = Path("data-small") / name
    out_dir.mkdir(parents=True, exist_ok=True)
    np.savetxt(out_dir / "coords.csv", coords, delimiter=",")
    np.savetxt(out_dir / "connectivity.csv", connect.astype(int), delimiter=",", fmt='%d')
    np.savetxt(out_dir / "field_disp_x.csv", disp_x, delimiter=",")
    np.savetxt(out_dir / "field_disp_y.csv", disp_y, delimiter=",")
    np.savetxt(out_dir / "field_disp_z.csv", disp_z, delimiter=",")

def compute_disps(coords, frame0_params, frame1_params):
    num_nodes = coords.shape[0]
    xmin, ymin, _ = np.min(coords, axis=0)
    xmax, ymax, _ = np.max(coords, axis=0)
    
    xrng = xmax - xmin if xmax > xmin else 1.0
    yrng = ymax - ymin if ymax > ymin else 1.0
    
    disps_x = np.zeros((num_nodes, 2))
    disps_y = np.zeros((num_nodes, 2))
    disps_z = np.zeros((num_nodes, 2))
    
    for i, (ux_min, ux_max, uy_min, uy_max, uz_min, uz_max) in enumerate([frame0_params, frame1_params]):
        for j in range(num_nodes):
            x, y, _ = coords[j]
            # Normalised local coords [0, 1]
            xi = (x - xmin) / xrng
            eta = (y - ymin) / yrng
            
            disps_x[j, i] = ux_min + (ux_max - ux_min) * xi
            disps_y[j, i] = uy_min + (uy_max - uy_min) * eta
            
            # Z gradient from bottom-left (0,0) to top-right (1,1)
            # Use average of normalized x and y for a diagonal gradient
            zeta = (xi + eta) / 2.0
            disps_z[j, i] = uz_min + (uz_max - uz_min) * zeta
            
    return disps_x, disps_y, disps_z

def main():
    # User Configurable Parameters
    WIDTH = 16.0
    HEIGHT = 10.0
    
    # frame_params = (ux_min, ux_max, uy_min, uy_max, uz_min, uz_max)
    FRAME0_PARAMS = (-1e-6, 1e-6, -1e-6, 1e-6, -1e-6, 1e-6)
    FRAME1_PARAMS = (-0.5, 0.5, -0.5, 0.5, -0.5, 0.5)

    # Tri3 Full Screen (2 elements)
    coords_tri3 = np.array([
        [0, 0, 0], [WIDTH, 0, 0], [WIDTH, HEIGHT, 0], [0, HEIGHT, 0]
    ], dtype=float)
    connect_tri3 = np.array([[0, 1, 2], [0, 2, 3]])
    dx, dy, dz = compute_disps(coords_tri3, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case("tri3_fullscreen", coords_tri3, connect_tri3, dx, dy, dz)

    # Tri6 Full Screen (2 elements)
    coords_tri6 = np.array([
        [0, 0, 0], [WIDTH, 0, 0], [WIDTH, HEIGHT, 0], [0, HEIGHT, 0], # vertices
        [WIDTH/2, 0, 0], [WIDTH, HEIGHT/2, 0], [WIDTH/2, HEIGHT, 0], [0, HEIGHT/2, 0], # side midsides
        [WIDTH/2, HEIGHT/2, 0] # diagonal midside
    ], dtype=float)
    connect_tri6 = np.array([
        [0, 1, 2, 4, 5, 8],
        [0, 2, 3, 8, 6, 7]
    ])
    dx, dy, dz = compute_disps(coords_tri6, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case("tri6_fullscreen", coords_tri6, connect_tri6, dx, dy, dz)

    # Quad4 Full Screen (1 element)
    coords_quad4 = np.array([
        [0, 0, 0], [WIDTH, 0, 0], [WIDTH, HEIGHT, 0], [0, HEIGHT, 0]
    ], dtype=float)
    connect_quad4 = np.array([[0, 1, 2, 3]])
    dx, dy, dz = compute_disps(coords_quad4, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case("quad4_fullscreen", coords_quad4, connect_quad4, dx, dy, dz)

    # Quad8 Full Screen (1 element)
    coords_quad8 = np.array([
        [0, 0, 0], [WIDTH, 0, 0], [WIDTH, HEIGHT, 0], [0, HEIGHT, 0], # vertices
        [WIDTH/2, 0, 0], [WIDTH, HEIGHT/2, 0], [WIDTH/2, HEIGHT, 0], [0, HEIGHT/2, 0] # midsides
    ], dtype=float)
    connect_quad8 = np.array([[0, 1, 2, 3, 4, 5, 6, 7]])
    dx, dy, dz = compute_disps(coords_quad8, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case("quad8_fullscreen", coords_quad8, connect_quad8, dx, dy, dz)

    # Quad9 Full Screen (1 element)
    coords_quad9 = np.array([
        [0, 0, 0], [WIDTH, 0, 0], [WIDTH, HEIGHT, 0], [0, HEIGHT, 0], # vertices
        [WIDTH/2, 0, 0], [WIDTH, HEIGHT/2, 0], [WIDTH/2, HEIGHT, 0], [0, HEIGHT/2, 0], # midsides
        [WIDTH/2, HEIGHT/2, 0] # center
    ], dtype=float)
    connect_quad9 = np.array([[0, 1, 2, 3, 4, 5, 6, 7, 8]])
    dx, dy, dz = compute_disps(coords_quad9, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case("quad9_fullscreen", coords_quad9, connect_quad9, dx, dy, dz)

    print("Generated full screen cases in data-small/")

if __name__ == "__main__":
    main()
