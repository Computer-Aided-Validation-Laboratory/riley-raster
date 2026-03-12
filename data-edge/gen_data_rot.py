import numpy as np
import os
from pathlib import Path

# Coordinate System: Right-handed Cartesian (X right, Y up, Z towards viewer).
# Vertex Winding: All elements MUST follow Counter-Clockwise (CCW) winding.

def save_case(base_dir, name, coords, connect, disp_x, disp_y, disp_z):
    out_dir = Path(base_dir) / name
    out_dir.mkdir(parents=True, exist_ok=True)
    np.savetxt(out_dir / "coords.csv", coords, delimiter=",")
    np.savetxt(out_dir / "connectivity.csv", connect.astype(int), 
               delimiter=",", fmt='%d')
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
    
    for i, (ux_min, ux_max, uy_min, uy_max, uz_min, uz_max) in enumerate(
        [frame0_params, frame1_params]):
        for j in range(num_nodes):
            x, y, _ = coords[j]
            # Normalised local coords [0, 1]
            xi = (x - xmin) / xrng
            eta = (y - ymin) / yrng
            
            disps_x[j, i] = ux_min + (ux_max - ux_min) * xi
            disps_y[j, i] = uy_min + (uy_max - uy_min) * eta
            
            zeta = (xi + eta) / 2.0
            disps_z[j, i] = uz_min + (uz_max - uz_min) * zeta
            
    return disps_x, disps_y, disps_z

def move_midside(v1, v2, centroid, offset):
    m = (v1 + v2) / 2.0
    dir = m - centroid
    dist = np.linalg.norm(dir)
    if dist < 1e-9:
        return m
    unit_dir = dir / dist
    return m + unit_dir * offset

def rotate_points(points, angle_deg, center):
    angle_rad = np.radians(angle_deg)
    cos_a = np.cos(angle_rad)
    sin_a = np.sin(angle_rad)
    rot_mat = np.array([
        [cos_a, -sin_a, 0],
        [sin_a, cos_a, 0],
        [0, 0, 1]
    ])
    
    rotated = []
    for p in points:
        rel_p = p - center
        rot_p = np.dot(rot_mat, rel_p)
        rotated.append(rot_p + center)
    return np.array(rotated)

def compute_uvs(coords, u_range=(0.4, 0.6), v_range=(0.4, 0.6)):
    num_nodes = coords.shape[0]
    xmin, ymin, _ = np.min(coords, axis=0)
    xmax, ymax, _ = np.max(coords, axis=0)
    
    xrng = xmax - xmin if xmax > xmin else 1.0
    yrng = ymax - ymin if ymax > ymin else 1.0
    
    uvs = np.zeros((num_nodes, 2))
    for j in range(num_nodes):
        x, y, _ = coords[j]
        uvs[j, 0] = u_range[0] + (u_range[1] - u_range[0]) * (x - xmin) / xrng
        uvs[j, 1] = v_range[0] + (v_range[1] - v_range[0]) * (y - ymin) / yrng
    return uvs

def save_uvs(base_dir, name, uvs):
    out_dir = Path(base_dir) / name
    out_dir.mkdir(parents=True, exist_ok=True)
    np.savetxt(out_dir / "uvs.csv", uvs, delimiter=",")

def main():
    base_dir = "data-edge"
    L = 10.0
    H = np.sqrt(3) * L / 2.0
    D = 1.0
    ANGLE_DEG = 45.0
    
    FRAME0_PARAMS = (-1e-6, 1e-6, -1e-6, 1e-6, -1e-6, 1e-6)
    FRAME1_PARAMS = (-0.5, 0.5, -0.5, 0.5, -0.5, 0.5)
    U_RANGE = (0.4, 0.6)
    V_RANGE = (0.4, 0.6)

    v_tri = np.array([
        [0, 0, 0],
        [L, 0, 0],
        [L/2, H, 0]
    ], dtype=float)
    centroid = np.array([L/2, H/3, 0], dtype=float)

    # Note on naming: 
    # Existing data-edge/tri6_concave has midsides bulging IN (Concave element).
    # Existing data-edge/tri6_convex has midsides bulging OUT (Convex element).
    # The user's prompt description says the opposite, but I will match the 
    # folder names to their standard geometric meaning as seen in the data.

    # 1. tri6_bulgein_rot (Bulge IN)
    m01_in = move_midside(v_tri[0], v_tri[1], centroid, -D)
    m12_in = move_midside(v_tri[1], v_tri[2], centroid, -D)
    m20_in = move_midside(v_tri[2], v_tri[0], centroid, -D)
    coords_conc = np.vstack([v_tri, [m01_in, m12_in, m20_in]])
    coords_conc_rot = rotate_points(coords_conc, ANGLE_DEG, centroid)
    
    dx, dy, dz = compute_disps(coords_conc_rot, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case(base_dir, "tri6_bulgein_rot", coords_conc_rot, np.array([[0, 1, 2, 3, 4, 5]]), dx, dy, dz)
    uvs_conc = compute_uvs(coords_conc_rot, U_RANGE, V_RANGE)
    save_uvs(base_dir, "tri6_bulgein_rot", uvs_conc)

    # 2. tri6_bulgeout_rot (Bulge OUT)
    m01_out = move_midside(v_tri[0], v_tri[1], centroid, D)
    m12_out = move_midside(v_tri[1], v_tri[2], centroid, D)
    m20_out = move_midside(v_tri[2], v_tri[0], centroid, D)
    coords_conv = np.vstack([v_tri, [m01_out, m12_out, m20_out]])
    coords_conv_rot = rotate_points(coords_conv, ANGLE_DEG, centroid)
    
    dx, dy, dz = compute_disps(coords_conv_rot, FRAME0_PARAMS, FRAME1_PARAMS)
    save_case(base_dir, "tri6_bulgeout_rot", coords_conv_rot, np.array([[0, 1, 2, 3, 4, 5]]), dx, dy, dz)
    uvs_conv = compute_uvs(coords_conv_rot, U_RANGE, V_RANGE)
    save_uvs(base_dir, "tri6_bulgeout_rot", uvs_conv)

    print(f"Generated rotated Tri6 cases in {base_dir}/ at {ANGLE_DEG} degrees.")

if __name__ == "__main__":
    main()
