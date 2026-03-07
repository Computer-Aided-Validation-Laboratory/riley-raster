import numpy as np
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
            xi = (x - xmin) / xrng
            eta = (y - ymin) / yrng
            
            disps_x[j, i] = ux_min + (ux_max - ux_min) * xi
            disps_y[j, i] = uy_min + (uy_max - uy_min) * eta
            
            # Diagonal gradient from bottom-left (0,0) to top-right (1,1)
            zeta = (xi + eta) / 2.0
            disps_z[j, i] = uz_min + (uz_max - uz_min) * zeta
            
    return disps_x, disps_y, disps_z

def move_midside(v1, v2, centroid, offset):
    # straight midside
    m = (v1 + v2) / 2.0
    # direction from centroid to m
    dir = m - centroid
    dist = np.linalg.norm(dir)
    if dist < 1e-9:
        # Fallback if m is at centroid (unlikely for boundary edge)
        return m
    unit_dir = dir / dist
    # move away from centroid if offset > 0, towards if offset < 0
    return m + unit_dir * offset

def main():
    # User Configurable Parameters
    L = 10.0 # Edge length
    D = 0.5  # Midside node shift
    
    # frame_params = (ux_min, ux_max, uy_min, uy_max, uz_min, uz_max)
    FRAME0_PARAMS = (-1e-6, 1e-6, -1e-6, 1e-6, -1e-6, 1e-6)
    FRAME1_PARAMS = (-0.5, 0.5, -0.5, 0.5, -0.5, 0.5)

    H = np.sqrt(3) / 2 * L
    tri_centroid = np.array([L/2, H/3, 0])
    v_tri = np.array([
        [0, 0, 0],
        [L, 0, 0],
        [L/2, H, 0]
    ])

    # Tri3 Single
    dx, dy, dz = compute_disps(v_tri, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case("tri3_single", v_tri, np.array([[0, 1, 2]]), dx, dy, dz)

    # Tri6 Single
    m01 = (v_tri[0] + v_tri[1]) / 2.0
    m12 = move_midside(v_tri[1], v_tri[2], tri_centroid, D)
    m20 = move_midside(v_tri[2], v_tri[0], tri_centroid, -D)
    
    coords_tri6 = np.vstack([v_tri, [m01, m12, m20]])
    dx, dy, dz = compute_disps(coords_tri6, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case("tri6_single", coords_tri6, np.array([[0, 1, 2, 3, 4, 5]]), dx, dy, dz)

    # Quad Single (Square)
    v_quad = np.array([
        [0, 0, 0], [L, 0, 0], [L, L, 0], [0, L, 0]
    ])
    quad_centroid = np.array([L/2, L/2, 0])

    # Quad4 Single
    dx, dy, dz = compute_disps(v_quad, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case("quad4_single", v_quad, np.array([[0, 1, 2, 3]]), dx, dy, dz)

    # Quad8 Single
    m01_q = (v_quad[0] + v_quad[1]) / 2.0
    m12_q = move_midside(v_quad[1], v_quad[2], quad_centroid, D)
    m23_q = move_midside(v_quad[2], v_quad[3], quad_centroid, -D)
    m30_q = (v_quad[3] + v_quad[0]) / 2.0

    coords_quad8 = np.vstack([v_quad, [m01_q, m12_q, m23_q, m30_q]])
    dx, dy, dz = compute_disps(coords_quad8, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case("quad8_single", coords_quad8, np.array([[0, 1, 2, 3, 4, 5, 6, 7]]), dx, dy, dz)

    # Quad9 Single
    coords_quad9 = np.vstack([coords_quad8, [quad_centroid]])
    dx, dy, dz = compute_disps(coords_quad9, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case("quad9_single", coords_quad9, np.array([[0, 1, 2, 3, 4, 5, 6, 7, 8]]), dx, dy, dz)

    print("Generated single element cases in data-small/")

if __name__ == "__main__":
    main()
