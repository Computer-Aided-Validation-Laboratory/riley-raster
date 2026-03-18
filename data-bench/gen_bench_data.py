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

def constrain_uvs(coords, u_range=(0.4, 0.6), v_range=(0.4, 0.6)):
    xmin, ymin = np.min(coords[:, :2], axis=0)
    xmax, ymax = np.max(coords[:, :2], axis=0)
    xrng = xmax - xmin if xmax > xmin else 1.0
    yrng = ymax - ymin if ymax > ymin else 1.0
    uvs = np.zeros((len(coords), 2))
    uvs[:, 0] = u_range[0] + (u_range[1] - u_range[0]) * (coords[:, 0] - xmin) / xrng
    uvs[:, 1] = v_range[0] + (v_range[1] - v_range[0]) * (coords[:, 1] - ymin) / yrng
    return uvs

def get_rgb_gradient(coords):
    xmin, ymin = np.min(coords[:, :2], axis=0)
    xmax, ymax = np.max(coords[:, :2], axis=0)
    xrng = xmax - xmin if xmax > xmin else 1.0
    yrng = ymax - ymin if ymax > ymin else 1.0
    xn = (coords[:, 0] - xmin) / xrng
    yn = (coords[:, 1] - ymin) / yrng
    # Red at bottom-left, Green at bottom-right, Blue at top
    r = (1.0 - xn) * (1.0 - yn)
    g = xn * (1.0 - yn)
    b = yn
    return np.stack([r, g, b], axis=1)

def generate_fullraster(etype, out_dir):
    if "tri" in etype:
        coords = np.array([[-1, -1, 10], [1, -1, 10], [1, 1, 10], [-1, 1, 10]], dtype=np.float64)
        if etype == "tri6":
            coords = np.vstack([coords, [[0,-1,10], [1,0,10], [0,1,10], [-1,0,10], [0,0,10]]])
            conn = np.array([[0, 1, 2, 4, 5, 8], [0, 2, 3, 8, 6, 7]], dtype=np.int32)
        else:
            conn = np.array([[0, 1, 2], [0, 2, 3]], dtype=np.int32)
    else:
        coords = np.array([[-1, -1, 10], [1, -1, 10], [1, 1, 10], [-1, 1, 10]], dtype=np.float64)
        if etype in ["quad8", "quad9"]:
            coords = np.vstack([coords, [[0,-1,10], [1,0,10], [0,1,10], [-1,0,10], [0,0,10]]])
            if etype == "quad8": conn = np.array([[0, 1, 2, 3, 4, 5, 6, 7]], dtype=np.int32)
            else: conn = np.array([[0, 1, 2, 3, 4, 5, 6, 7, 8]], dtype=np.int32)
        else:
            conn = np.array([[0, 1, 2, 3]], dtype=np.int32)
    save_csv(f"{out_dir}/coords.csv", coords)
    save_csv(f"{out_dir}/connect.csv", conn)
    save_csv(f"{out_dir}/field.csv", get_rgb_gradient(coords))
    save_csv(f"{out_dir}/uvs.csv", constrain_uvs(coords))

def generate_grid(etype, out_dir, N=320):
    x = np.linspace(-1, 1, N+1)
    y = np.linspace(-1, 1, N+1)
    xv, yv = np.meshgrid(x, y)
    coords = np.stack([xv.flatten(), yv.flatten(), np.full_like(xv.flatten(), 10)], axis=1)
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
    save_csv(f"{out_dir}/field.csv", get_rgb_gradient(coords))
    save_csv(f"{out_dir}/uvs.csv", constrain_uvs(coords))

def generate_sphere(etype, out_dir):
    rows, cols = 60, 60
    u_vals = np.linspace(0, 2 * np.pi, cols)
    v_vals = np.linspace(0, np.pi, rows)
    coords, u_polar, v_polar = [], [], []
    for iv in v_vals:
        for iu in u_vals:
            coords.append([np.cos(iu)*np.sin(iv), np.sin(iu)*np.sin(iv), np.cos(iv) + 10])
            u_polar.append(iu); v_polar.append(iv)
    coords = np.array(coords)
    u_polar = np.array(u_polar); v_polar = np.array(v_polar)
    conn = []
    for r in range(rows - 1):
        for c in range(cols - 1):
            i0, i1, i2, i3 = r*cols+c, r*cols+c+1, (r+1)*cols+c+1, (r+1)*cols+c
            if "tri" in etype:
                conn.append([i0, i1, i2]); conn.append([i0, i2, i3])
            else:
                conn.append([i0, i1, i2, i3])
    nodes_n = get_nodes_for_elem(etype)
    final_conn = np.array(conn)
    if nodes_n > final_conn.shape[1]:
        final_conn = np.hstack([final_conn, np.tile(final_conn[:, -1:], (1, nodes_n - final_conn.shape[1]))])
    save_csv(f"{out_dir}/coords.csv", coords)
    save_csv(f"{out_dir}/connect.csv", final_conn)
    u_uv = 0.4 + (u_polar / (2 * np.pi)) * 0.2
    v_uv = 0.4 + (v_polar / np.pi) * 0.2
    save_csv(f"{out_dir}/uvs.csv", np.stack([u_uv, v_uv], axis=1))
    r_c = np.sin(3 * u_polar) * 0.5 + 0.5
    g_c = np.sin(3 * u_polar + 2*np.pi/3) * 0.5 + 0.5
    b_c = np.sin(3 * u_polar + 4*np.pi/3) * 0.5 + 0.5
    save_csv(f"{out_dir}/field.csv", np.stack([r_c, g_c, b_c], axis=1))

if __name__ == "__main__":
    for et in ["tri3", "tri3opt", "tri6", "quad4ibi", "quad4newton", "quad8", "quad9"]:
        print(f"Generating data for {et}...")
        generate_fullraster(et, f"data-bench/{et}_fullraster")
        generate_grid(et, f"data-bench/{et}_geom")
        generate_sphere(et, f"data-bench/{et}_cullsphere")
