import numpy as np
from pathlib import Path
import gendata

def generate_twoelems(base_dir, length, d_shift, frame0, frame1):
    h = np.sqrt(3) / 2 * length
    
    # Vertices for two equilateral triangles joined at the center
    # V0 top-center, V2 bottom-center, V1 right, V3 left
    v0 = np.array([0.0, length/2.0, 0.0])
    v1 = np.array([h, 0.0, 0.0])
    v2 = np.array([0.0, -length/2.0, 0.0])
    v3 = np.array([-h, 0.0, 0.0])
    
    # Centroids
    c_right = (v0 + v1 + v2) / 3.0
    c_left = (v0 + v2 + v3) / 3.0
    
    # --- Tri3 TwoElems ---
    coords_tri3 = np.array([v0, v1, v2, v3])
    # Right: 0,1,2. Left: 0,2,3
    connect_tri3 = np.array([[0, 1, 2], [0, 2, 3]])
    dx, dy, dz = gendata.compute_disps(coords_tri3, frame0, frame1)
    gendata.save_case(base_dir, "tri3_twoelems", coords_tri3, connect_tri3, dx, dy, dz)
    
    # --- Tri6 TwoElems ---
    # Right Triangle (All OUT - away from centroid)
    m01_r = gendata.move_midside(v0, v1, c_right, d_shift)
    m12_r = gendata.move_midside(v1, v2, c_right, d_shift)
    m20_shared = gendata.move_midside(v2, v0, c_right, d_shift) # moves left
    
    # Left Triangle (All IN - towards centroid)
    m23_l = gendata.move_midside(v2, v3, c_left, -d_shift) # towards
    m30_l = gendata.move_midside(v3, v0, c_left, -d_shift) # towards
    
    coords_tri6 = np.array([v0, v1, v2, v3, m01_r, m12_r, m20_shared, m23_l, m30_l])
    # Right: corners 0,1,2, midsides 4,5,6
    # Left: corners 0,2,3, midsides 6,7,8
    connect_tri6 = np.array([
        [0, 1, 2, 4, 5, 6],
        [0, 2, 3, 6, 7, 8]
    ])
    dx, dy, dz = gendata.compute_disps(coords_tri6, frame0, frame1)
    gendata.save_case(base_dir, "tri6_twoelems", coords_tri6, connect_tri6, dx, dy, dz)
    
    # --- Quads ---
    # Two squares joined
    vq0 = np.array([-length, length/2.0, 0.0])
    vq1 = np.array([0.0, length/2.0, 0.0])
    vq2 = np.array([length, length/2.0, 0.0])
    vq3 = np.array([-length, -length/2.0, 0.0])
    vq4 = np.array([0.0, -length/2.0, 0.0])
    vq5 = np.array([length, -length/2.0, 0.0])
    
    # Quad4 TwoElems
    # Layout: [vq0, vq1, vq2, vq3, vq4, vq5]
    coords_quad4 = np.array([vq0, vq1, vq2, vq3, vq4, vq5])
    # Left Quad: vq0, vq1, vq4, vq3 -> [0, 1, 4, 3]
    # Right Quad: vq1, vq2, vq5, vq4 -> [1, 2, 5, 4]
    connect_quad4 = np.array([[0, 1, 4, 3], [1, 2, 5, 4]])
    dx, dy, dz = gendata.compute_disps(coords_quad4, frame0, frame1)
    gendata.save_case(base_dir, "quad4_twoelems", coords_quad4, connect_quad4, dx, dy, dz)
    
    # Quad8 TwoElems
    cq_left = np.array([-length/2.0, 0.0, 0.0])
    cq_right = np.array([length/2.0, 0.0, 0.0])
    
    # Left Quad (All IN)
    mq01_l = gendata.move_midside(vq0, vq1, cq_left, -d_shift)
    mq12_shared = gendata.move_midside(vq1, vq4, cq_left, -d_shift) # shared, moves LEFT (OUT for right quad)
    mq23_l = gendata.move_midside(vq4, vq3, cq_left, -d_shift)
    mq30_l = gendata.move_midside(vq3, vq0, cq_left, -d_shift)
    
    # Right Quad (All OUT)
    mq01_r = gendata.move_midside(vq1, vq2, cq_right, d_shift)
    mq12_r = gendata.move_midside(vq2, vq5, cq_right, d_shift)
    mq23_r = gendata.move_midside(vq5, vq4, cq_right, d_shift)
    
    coords_quad8 = np.vstack([coords_quad4, [mq01_l, mq12_shared, mq23_l, mq30_l, mq01_r, mq12_r, mq23_r]])
    # Left Quad: vq0(0), vq1(1), vq4(4), vq3(3), mq01_l(6), mq12_shared(7), mq23_l(8), mq30_l(9)
    # Right Quad: vq1(1), vq2(2), vq5(5), vq4(4), mq01_r(10), mq12_r(11), mq23_r(12), mq12_shared(7)
    connect_quad8 = np.array([
        [0, 1, 4, 3, 6, 7, 8, 9],
        [1, 2, 5, 4, 10, 11, 12, 7]
    ])
    dx, dy, dz = gendata.compute_disps(coords_quad8, frame0, frame1)
    gendata.save_case(base_dir, "quad8_twoelems", coords_quad8, connect_quad8, dx, dy, dz)
    
    # Quad9 TwoElems
    coords_quad9 = np.vstack([coords_quad8, [cq_left, cq_right]])
    # Left Quad center: index 13, Right Quad center: index 14
    connect_quad9 = np.array([
        [0, 1, 4, 3, 6, 7, 8, 9, 13],
        [1, 2, 5, 4, 10, 11, 12, 7, 14]
    ])
    dx, dy, dz = gendata.compute_disps(coords_quad9, frame0, frame1)
    gendata.save_case(base_dir, "quad9_twoelems", coords_quad9, connect_quad9, dx, dy, dz)

def main():
    base_dir = "data-simple"
    L = 10.0
    D = 1.0
    FRAME0_PARAMS = (-1e-6, 1e-6, -1e-6, 1e-6, -1e-6, 1e-6)
    FRAME1_PARAMS = (-0.5, 0.5, -0.5, 0.5, -0.5, 0.5)
    generate_twoelems(base_dir, L, D, FRAME0_PARAMS, FRAME1_PARAMS)
    print(f"Generated two-element cases in {base_dir}/")

if __name__ == "__main__":
    main()
