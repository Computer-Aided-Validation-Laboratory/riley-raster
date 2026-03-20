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
    xmin, ymin, _ = np.min(coords, axis=0)
    xmax, ymax, _ = np.max(coords, axis=0)
    xrng, yrng = max(xmax - xmin, 1.0), max(ymax - ymin, 1.0)
    uvs = np.zeros((len(coords), 2))
    for j in range(len(coords)):
        x, y, _ = coords[j]
        uvs[j, 0] = u_range[0] + (u_range[1] - u_range[0]) * (x - xmin) / xrng
        uvs[j, 1] = v_range[0] + (v_range[1] - v_range[0]) * (y - ymin) / yrng
    return uvs

def compute_rgb_fields(coords):
    xmin, ymin, _ = np.min(coords, axis=0)
    xmax, ymax, _ = np.max(coords, axis=0)
    xrng, yrng = max(xmax - xmin, 1.0), max(ymax - ymin, 1.0)
    fields = np.zeros((len(coords), 3))
    for j in range(len(coords)):
        xn = (coords[j, 0] - xmin) / xrng
        yn = (coords[j, 1] - ymin) / yrng
        # Purely linear gradient experiment
        r = xn
        g = yn
        b = 1.0 - (xn + yn) / 2.0
        fields[j] = [r, g, b]
    return fields

def generate_fullscreen(etype, out_dir):
    if "tri" in etype:
        coords = np.array([[0, 0, 0], [WIDTH, 0, 0], [WIDTH, HEIGHT, 0], [0, HEIGHT, 0]], dtype=float)
        if etype == "tri6":
            coords = np.array([
                [0, 0, 0], [WIDTH, 0, 0], [WIDTH, HEIGHT, 0], [0, HEIGHT, 0],
                [WIDTH/2, 0, 0], [WIDTH, HEIGHT/2, 0], [WIDTH/2, HEIGHT, 0], [0, HEIGHT/2, 0],
                [WIDTH/2, HEIGHT/2, 0]
            ], dtype=float)
            connect = np.array([[0, 1, 2, 4, 5, 8], [0, 2, 3, 8, 6, 7]])
        else:
            connect = np.array([[0, 1, 2], [0, 2, 3]])
    else:
        coords = np.array([[0, 0, 0], [WIDTH, 0, 0], [WIDTH, HEIGHT, 0], [0, HEIGHT, 0]], dtype=float)
        if etype in ["quad8", "quad9"]:
            coords = np.array([
                [0, 0, 0], [WIDTH, 0, 0], [WIDTH, HEIGHT, 0], [0, HEIGHT, 0],
                [WIDTH/2, 0, 0], [WIDTH, HEIGHT/2, 0], [WIDTH/2, HEIGHT, 0], [0, HEIGHT/2, 0],
                [WIDTH/2, HEIGHT/2, 0]
            ], dtype=float)
            if etype == "quad8": connect = np.array([[0, 1, 2, 3, 4, 5, 6, 7]])
            else: connect = np.array([[0, 1, 2, 3, 4, 5, 6, 7, 8]])
        else:
            connect = np.array([[0, 1, 2, 3]])
    save_csv(f"{out_dir}/coords.csv", coords)
    save_csv(f"{out_dir}/connect.csv", connect)
    save_csv(f"{out_dir}/field.csv", compute_rgb_fields(coords))
    save_csv(f"{out_dir}/uvs.csv", compute_uvs(coords))

def generate_grid(etype, out_dir, N=320):
    is_higher = etype in ["tri6", "quad8", "quad9"]
    step = 2 if is_higher else 1
    xn, yn = N * step, N * step
    x, y = np.linspace(0, WIDTH, xn + 1), np.linspace(0, HEIGHT, yn + 1)
    xv, yv = np.meshgrid(x, y)
    coords = np.stack([xv.flatten(), yv.flatten(), np.zeros_like(xv.flatten())], axis=1)
    conn = []
    for jj in range(0, yn, step):
        for ii in range(0, xn, step):
            i0, i1, i2, i3 = jj*(xn+1)+ii, jj*(xn+1)+ii+step, (jj+step)*(xn+1)+ii+step, (jj+step)*(xn+1)+ii
            if etype in ["tri3", "tri3opt"]:
                conn.append([i0, i1, i2]); conn.append([i0, i2, i3])
            elif "quad" in etype and not is_higher:
                conn.append([i0, i1, i2, i3])
            elif etype == "tri6":
                m01, m12, m23, m30 = i0+1, i1+(xn+1), i3+1, i0+(xn+1)
                m02 = i0+(xn+1)+1
                conn.append([i0, i1, i2, m01, m12, m02])
                conn.append([i0, i2, i3, m02, m23, m30])
            elif etype in ["quad8", "quad9"]:
                m01, m12, m23, m30 = i0+1, i1+(xn+1), i3+1, i0+(xn+1)
                q8 = [i0, i1, i2, i3, m01, m12, m23, m30]
                if etype == "quad9": q8.append(i0+(xn+1)+1)
                conn.append(q8)
    save_csv(f"{out_dir}/coords.csv", coords)
    save_csv(f"{out_dir}/connect.csv", np.array(conn))
    save_csv(f"{out_dir}/field.csv", compute_rgb_fields(coords))
    save_csv(f"{out_dir}/uvs.csv", compute_uvs(coords))

def generate_sphere(etype, out_dir):
    rows, cols = 60, 60
    u_vals, v_vals = np.linspace(0, 2*np.pi, cols), np.linspace(0, np.pi, rows)
    coords, u_polar = [], []
    for iv in v_vals:
        for iu in u_vals:
            coords.append([np.cos(iu)*np.sin(iv), np.sin(iu)*np.sin(iv), np.cos(iv) + 10])
            u_polar.append(iu)
    coords = np.array(coords); u_polar = np.array(u_polar)
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
    save_csv(f"{out_dir}/uvs.csv", 0.4 + np.random.rand(len(coords), 2) * 0.2)
    save_csv(f"{out_dir}/field.csv", np.stack([np.sin(3*u_polar)*0.5+0.5, np.sin(3*u_polar+2*np.pi/3)*0.5+0.5, np.sin(3*u_polar+4*np.pi/3)*0.5+0.5], axis=1))

if __name__ == "__main__":
    for et in ["tri3", "tri3opt", "tri6", "quad4ibi", "quad4newton", "quad8", "quad9"]:
        print(f"Generating data for {et}...")
        generate_fullscreen(et, f"data-bench/{et}_fullraster")
        generate_grid(et, f"data-bench/{et}_geom", N=320)
        generate_grid(et, f"data-bench/{et}_bal", N=8)
        generate_sphere(et, f"data-bench/{et}_cullsphere")
