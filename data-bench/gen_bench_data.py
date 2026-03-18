import numpy as np
import os

def save_csv(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    np.savetxt(path, data, delimiter=',', fmt='%.10f' if data.dtype == np.float64 else '%d')

def get_nodes_for_elem(etype):
    return {
        "tri3": 3, "tri3opt": 3, "tri6": 6,
        "quad4ibi": 4, "quad4newton": 4, "quad8": 8, "quad9": 9
    }[etype]

WIDTH = 16.0
HEIGHT = 10.0

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

def compute_rgb_fields(coords):
    num_nodes = coords.shape[0]
    xmin, _, _ = np.min(coords, axis=0)
    xmax, _, _ = np.max(coords, axis=0)
    xrng = xmax - xmin if xmax > xmin else 1.0
    
    fields = np.zeros((num_nodes, 3))
    for j in range(num_nodes):
        x = (coords[j, 0] - xmin) / xrng
        # Red -> Green -> Blue transition across X
        if x <= 0.5:
            r = 1.0 - (x / 0.5)
            g = x / 0.5
            b = 0.0
        else:
            r = 0.0
            g = 1.0 - ((x - 0.5) / 0.5)
            b = (x - 0.5) / 0.5
        fields[j] = [r, g, b]
    return fields

def generate_fullscreen(etype, out_dir):
    # Tri3 Full Screen (2 elements)
    if "tri" in etype:
        coords = np.array([
            [0, 0, 0], [WIDTH, 0, 0], [WIDTH, HEIGHT, 0], [0, HEIGHT, 0]
        ], dtype=float)
        if etype == "tri6":
            coords = np.vstack([coords, [
                [WIDTH/2, 0, 0], [WIDTH, HEIGHT/2, 0], [WIDTH/2, HEIGHT, 0], [0, HEIGHT/2, 0],
                [WIDTH/2, HEIGHT/2, 0]
            ]])
            connect = np.array([[0, 1, 2, 4, 5, 8], [0, 2, 3, 8, 6, 7]])
        else:
            connect = np.array([[0, 1, 2], [0, 2, 3]])
    else:
        coords = np.array([
            [0, 0, 0], [WIDTH, 0, 0], [WIDTH, HEIGHT, 0], [0, HEIGHT, 0]
        ], dtype=float)
        if etype in ["quad8", "quad9"]:
            coords = np.vstack([coords, [
                [WIDTH/2, 0, 0], [WIDTH, HEIGHT/2, 0], [WIDTH/2, HEIGHT, 0], [0, HEIGHT/2, 0]
            ]])
            if etype == "quad9":
                coords = np.vstack([coords, [[WIDTH/2, HEIGHT/2, 0]]])
            connect = np.array([list(range(get_nodes_for_elem(etype)))])
        else:
            connect = np.array([[0, 1, 2, 3]])

    save_csv(f"{out_dir}/coords.csv", coords)
    save_csv(f"{out_dir}/connect.csv", connect)
    save_csv(f"{out_dir}/field.csv", compute_rgb_fields(coords))
    save_csv(f"{out_dir}/uvs.csv", compute_uvs(coords))

def generate_grid(etype, out_dir, N=100):
    x = np.linspace(0, WIDTH, N+1)
    y = np.linspace(0, HEIGHT, N+1)
    xv, yv = np.meshgrid(x, y)
    coords = np.stack([xv.flatten(), yv.flatten(), np.zeros_like(xv.flatten())], axis=1)
    
    conn = []
    for jj in range(N):
        for ii in range(N):
            i0, i1, i2, i3 = jj*(N+1)+ii, jj*(N+1)+ii+1, (jj+1)*(N+1)+ii+1, (jj+1)*(N+1)+ii
            if "tri" in etype:
                conn.append([i0, i1, i2]); conn.append([i0, i2, i3])
            else:
                conn.append([i0, i1, i2, i3])
    
    final_conn = np.array(conn)
    nodes_n = get_nodes_for_elem(etype)
    if nodes_n > final_conn.shape[1]:
        final_conn = np.hstack([final_conn, np.tile(final_conn[:, -1:], (1, nodes_n - final_conn.shape[1]))])

    save_csv(f"{out_dir}/coords.csv", coords)
    save_csv(f"{out_dir}/connect.csv", final_conn)
    save_csv(f"{out_dir}/field.csv", compute_rgb_fields(coords))
    save_csv(f"{out_dir}/uvs.csv", compute_uvs(coords))

def generate_sphere(etype, out_dir):
    rows, cols = 60, 60
    u_vals = np.linspace(0, 2 * np.pi, cols)
    v_vals = np.linspace(0, np.pi, rows)
    coords, u_polar = [], []
    for iv in v_vals:
        for iu in u_vals:
            coords.append([np.cos(iu)*np.sin(iv), np.sin(iu)*np.sin(iv), np.cos(iv) + 10])
            u_polar.append(iu)
    coords = np.array(coords)
    u_polar = np.array(u_polar)
    
    conn = []
    for r in range(rows - 1):
        for c in range(cols - 1):
            i0, i1, i2, i3 = r*cols+c, r*cols+c+1, (r+1)*cols+c+1, (r+1)*cols+c
            if "tri" in etype:
                conn.append([i0, i1, i2]); conn.append([i0, i2, i3])
            else:
                conn.append([i0, i1, i2, i3])
    
    final_conn = np.array(conn)
    nodes_n = get_nodes_for_elem(etype)
    if nodes_n > final_conn.shape[1]:
        final_conn = np.hstack([final_conn, np.tile(final_conn[:, -1:], (1, nodes_n - final_conn.shape[1]))])

    save_csv(f"{out_dir}/coords.csv", coords)
    save_csv(f"{out_dir}/connect.csv", final_conn)
    # Simple spherical mapping
    save_csv(f"{out_dir}/uvs.csv", 0.4 + np.random.rand(len(coords), 2) * 0.2)
    save_csv(f"{out_dir}/field.csv", np.stack([np.sin(3*u_polar)*0.5+0.5, np.sin(3*u_polar+2*np.pi/3)*0.5+0.5, np.sin(3*u_polar+4*np.pi/3)*0.5+0.5], axis=1))

if __name__ == "__main__":
    for et in ["tri3", "tri3opt", "tri6", "quad4ibi", "quad4newton", "quad8", "quad9"]:
        print(f"Generating data for {et}...")
        generate_fullscreen(et, f"data-bench/{et}_fullraster")
        generate_grid(et, f"data-bench/{et}_geom")
        generate_sphere(et, f"data-bench/{et}_cullsphere")
