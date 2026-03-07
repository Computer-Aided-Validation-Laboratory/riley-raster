import numpy as np

def compute_uvs(coords, u_range=(0.4, 0.6), v_range=(0.4, 0.6)):
    """
    Project 3D coordinates to 2D UV coordinates within a specified range.
    Assumes projection along the Z-axis onto the XY plane.
    """
    num_nodes = coords.shape[0]
    xmin, ymin, _ = np.min(coords, axis=0)
    xmax, ymax, _ = np.max(coords, axis=0)
    
    xrng = xmax - xmin if xmax > xmin else 1.0
    yrng = ymax - ymin if ymax > ymin else 1.0
    
    uvs = np.zeros((num_nodes, 2))
    for j in range(num_nodes):
        x, y, _ = coords[j]
        # Normalize to [0, 1] then scale to [u_min, u_max]
        uvs[j, 0] = u_range[0] + (u_range[1] - u_range[0]) * (x - xmin) / xrng
        uvs[j, 1] = v_range[0] + (v_range[1] - v_range[0]) * (y - ymin) / yrng
    return uvs
