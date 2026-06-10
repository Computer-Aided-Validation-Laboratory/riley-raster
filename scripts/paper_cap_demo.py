#!/usr/bin/env python3
from __future__ import annotations

import shlex
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.colors as mcolors
import matplotlib.pyplot as plt
import mooseherder as mh
import numpy as np
import pyvista as pv
from PIL import Image
from scipy.interpolate import LinearNDInterpolator
from scipy.spatial import Delaunay

from paper_const import PAPER_DIR, PLOT_RESOLUTION_DPI, repo_root


VERIF_DIR = Path("verif")
OUT_FIGS_TEX_PATH = VERIF_DIR / "figs_cap_demo.tex"
SUBFIGURE_WIDTH = "0.245\\textwidth"
SUBFIGURE_GAP = "0.01\\textwidth"
PNG_DPI = int(PLOT_RESOLUTION_DPI)
PANEL_COLORBAR_LABEL_SIZE = 30
PANEL_COLORBAR_TICK_SIZE = 24
PANEL_IMAGE_FIGSIZE = (7.6, 6.0)
PANEL_AX_RECT = [0.055, 0.08, 0.69, 0.84]
PANEL_CBAR_RECT = [0.76, 0.14, 0.03, 0.72]

STEREOCAL_DIR = Path("out/demo-stereocal-nodist")
DICUQ_DIR = Path("out/demo-dicuq-nodist")
DIC_RESULTS_DIR = Path("out/pyvale-stereo-dic-res")
EXODUS_PATH = Path("data/FE/platehole3d_2mr_63f.e")

CAL_CAM0_BMP = STEREOCAL_DIR / "cam0_frame0_field0.bmp"
CAL_CAM1_BMP = STEREOCAL_DIR / "cam1_frame0_field0.bmp"
RENDER_CAM0_BMP = DICUQ_DIR / "cam0_frame0_field0.bmp"
RENDER_CAM1_BMP = DICUQ_DIR / "cam1_frame0_field0.bmp"

DIC_REFERENCE_FRAME = 1
DIC_FINAL_FRAME = 63
FE_FINAL_FRAME_INDEX = -1

CMAP = "coolwarm"
PANEL_FACE_COLOR = "white"
EDGE_COLOR = "#2f2f2f"
EDGE_WIDTH = 0.45

CAL_CAM0_PNG = "fig_cap_demo_cal_cam0.png"
CAL_CAM1_PNG = "fig_cap_demo_cal_cam1.png"
RENDER_CAM0_PNG = "fig_cap_demo_render_cam0.png"
RENDER_CAM1_PNG = "fig_cap_demo_render_cam1.png"
FE_UX_PNG = "fig_cap_demo_fe_ux.png"
FE_UY_PNG = "fig_cap_demo_fe_uy.png"
DIC_UX_PNG = "fig_cap_demo_dic_ux.png"
DIC_UY_PNG = "fig_cap_demo_dic_uy.png"

FIG_CAPTION = (
    "Capability demonstration for the \\texttt{Riley} stereo DIC-UQ workflow. Top row: "
    "synthetic stereo calibration target images for cameras 0 and 1. Second "
    "row: synthetic reference images of the perforated plate specimen for "
    "cameras 0 and 1. Third row: finite-element displacement fields on the "
    "specimen front face at the final frame. Bottom "
    "row: stereo-DIC displacements from the field of view at the final frame."
)


def output_dirs() -> tuple[Path, Path]:
    return repo_root() / VERIF_DIR, PAPER_DIR


def ensure_output_dirs() -> tuple[Path, Path]:
    verif_dir, paper_dir = output_dirs()
    verif_dir.mkdir(parents=True, exist_ok=True)
    paper_dir.mkdir(parents=True, exist_ok=True)
    return verif_dir, paper_dir


def save_pil_to_outputs(image: Image.Image, file_name: str) -> None:
    verif_dir, paper_dir = ensure_output_dirs()
    image.save(verif_dir / file_name)
    image.save(paper_dir / file_name)


def save_matplotlib_figure(fig: plt.Figure, file_name: str) -> None:
    verif_dir, paper_dir = ensure_output_dirs()
    save_kwargs = {
        "dpi": PNG_DPI,
        "facecolor": PANEL_FACE_COLOR,
    }
    fig.savefig(verif_dir / file_name, **save_kwargs)
    fig.savefig(paper_dir / file_name, **save_kwargs)


def write_figs_tex(figs_tex: str) -> None:
    verif_dir, paper_dir = ensure_output_dirs()
    (verif_dir / OUT_FIGS_TEX_PATH.name).write_text(figs_tex)
    (paper_dir / OUT_FIGS_TEX_PATH.name).write_text(figs_tex)


def export_bmp_as_png(src_path: Path, dst_name: str) -> None:
    image = Image.open(src_path)
    save_pil_to_outputs(image, dst_name)


def dic_results_path(frame_idx: int) -> Path:
    return DIC_RESULTS_DIR / f"dic_results_cam0_frame{frame_idx:02d}_field0.csv"


def load_dic_rows(csv_path: Path) -> np.ndarray:
    lines = csv_path.read_text().splitlines()[1:]
    return np.array(
        [list(map(float, shlex.split(line))) for line in lines],
        dtype=np.float64,
    )


def load_dic_displacements() -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    ref_rows = load_dic_rows(dic_results_path(DIC_REFERENCE_FRAME))
    final_rows = load_dic_rows(dic_results_path(DIC_FINAL_FRAME))

    # Convert stereo output coordinates into the FE-style Cartesian frame:
    # x right, y up. The raw stereo y coordinate is image-style y-down.
    ref_pos = np.column_stack((ref_rows[:, 16], -ref_rows[:, 17]))
    final_pos = np.column_stack((final_rows[:, 16], -final_rows[:, 17]))

    x_ref = ref_pos[:, 0]
    y_ref = ref_pos[:, 1]
    disp = final_pos - ref_pos
    disp_x = disp[:, 0]
    disp_y = disp[:, 1]
    return x_ref, y_ref, disp_x, disp_y


def calc_panel_scale(clim: tuple[float, float]) -> tuple[float, int]:
    max_abs = max(abs(clim[0]), abs(clim[1]))
    if max_abs == 0.0:
        return 1.0, 0
    exponent = int(np.floor(np.log10(max_abs)))
    if abs(exponent) < 2:
        return 1.0, 0
    return 10.0 ** exponent, exponent


def scaled_panel_label(base_label: str, exponent: int) -> str:
    if exponent == 0:
        return base_label
    return f"{base_label} [$\\times 10^{{{exponent}}}$ mm]"


def make_panel_figure(
    aspect_ratio: float,
) -> tuple[plt.Figure, plt.Axes, plt.Axes]:
    h_fig = 5.5
    h_ax = 5.0
    h_bottom = 0.25

    w_left = 0.15
    w_ax = h_ax * aspect_ratio
    w_gap = 0.25
    w_cbar = 0.25
    w_text = 1.3

    w_fig = w_left + w_ax + w_gap + w_cbar + w_text

    ax_rect = [
        w_left / w_fig,
        h_bottom / h_fig,
        w_ax / w_fig,
        h_ax / h_fig,
    ]

    cax_rect = [
        (w_left + w_ax + w_gap) / w_fig,
        0.5 / h_fig,
        w_cbar / w_fig,
        4.5 / h_fig,
    ]

    fig = plt.figure(figsize=(w_fig, h_fig), facecolor=PANEL_FACE_COLOR)
    ax = fig.add_axes(ax_rect)
    cax = fig.add_axes(cax_rect)
    return fig, ax, cax


def save_panel_image_with_colorbar(
    image: np.ndarray,
    clim: tuple[float, float],
    scalar_title: str,
    out_name: str,
    aspect_ratio: float,
) -> None:
    scale, exponent = calc_panel_scale(clim)
    fig, ax, cax = make_panel_figure(aspect_ratio)
    ax.imshow(image)
    ax.axis("off")

    norm = mcolors.Normalize(vmin=clim[0] / scale, vmax=clim[1] / scale)
    mappable = plt.cm.ScalarMappable(norm=norm, cmap=CMAP)
    mappable.set_array([])
    colorbar = fig.colorbar(mappable, cax=cax)
    colorbar.set_label(
        scaled_panel_label(scalar_title, exponent),
        fontsize=PANEL_COLORBAR_LABEL_SIZE,
    )
    colorbar.ax.tick_params(labelsize=PANEL_COLORBAR_TICK_SIZE)

    save_matplotlib_figure(fig, out_name)
    plt.close(fig)


def load_fe_front_face() -> pv.PolyData:
    exodus_reader = mh.ExodusReader(EXODUS_PATH)
    sim_data = exodus_reader.read_all_sim_data()

    coords_mm = sim_data.coords * 1000.0
    disp_x_mm = sim_data.node_vars["disp_x"][:, FE_FINAL_FRAME_INDEX] * 1000.0
    disp_y_mm = sim_data.node_vars["disp_y"][:, FE_FINAL_FRAME_INDEX] * 1000.0

    # Rebuild the specimen front face directly from the HEX20 connectivity so
    # the FE panel is a clean face-on surface without duplicated side strips.
    connect = sim_data.connect["connect1"] - 1
    face_map = np.array(
        (
            (0, 1, 2, 3),
            (0, 3, 7, 4),
            (4, 7, 6, 5),
            (1, 5, 6, 2),
            (0, 4, 5, 1),
            (2, 6, 7, 3),
        ),
        dtype=np.int64,
    )
    z_max = float(coords_mm[:, 2].max())

    unique_faces: list[tuple[int, int, int, int]] = []
    seen_faces: set[tuple[int, int, int, int]] = set()
    for elem_idx in range(connect.shape[1]):
        for face_nodes_idx in face_map:
            face_nodes = tuple(connect[face_nodes_idx, elem_idx].tolist())
            if not np.allclose(coords_mm[list(face_nodes), 2], z_max):
                continue
            face_key = tuple(sorted(face_nodes))
            if face_key in seen_faces:
                continue
            seen_faces.add(face_key)
            unique_faces.append(face_nodes)

    cells = np.array(
        [entry for face_nodes in unique_faces for entry in (4, *face_nodes)],
        dtype=np.int64,
    )
    cell_types = np.full(len(unique_faces), pv.CellType.QUAD, dtype=np.uint8)
    front_face = pv.UnstructuredGrid(cells, cell_types, coords_mm)
    front_face.point_data["disp_x_mm"] = disp_x_mm
    front_face.point_data["disp_y_mm"] = disp_y_mm
    return front_face.extract_cells(np.arange(len(unique_faces))).clean()


def crop_to_content(image: np.ndarray) -> np.ndarray:
    non_white = np.any(image < 255, axis=-1)
    rows = np.any(non_white, axis=1)
    cols = np.any(non_white, axis=0)
    if not np.any(rows) or not np.any(cols):
        return image
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    rmin = max(0, rmin - 2)
    rmax = min(image.shape[0] - 1, rmax + 2)
    cmin = max(0, cmin - 2)
    cmax = min(image.shape[1] - 1, cmax + 2)
    return image[rmin : rmax + 1, cmin : cmax + 1]


def render_fe_panel(
    front_face: pv.PolyData,
    scalar_name: str,
    scalar_title: str,
    clim: tuple[float, float],
    out_name: str,
) -> None:
    plotter = pv.Plotter(off_screen=True, window_size=(2000, 1600))
    plotter.set_background(PANEL_FACE_COLOR)
    plotter.add_mesh(
        front_face,
        scalars=scalar_name,
        cmap=CMAP,
        clim=clim,
        show_edges=True,
        edge_color=EDGE_COLOR,
        line_width=EDGE_WIDTH,
        show_scalar_bar=False,
    )
    plotter.view_xy()
    plotter.enable_parallel_projection()
    plotter.camera.tight(view="xy", padding=0.015)
    screenshot = plotter.screenshot(return_img=True)
    plotter.close()

    cropped = crop_to_content(screenshot)
    fe_aspect_ratio = 25.0 / 35.0
    save_panel_image_with_colorbar(
        cropped,
        clim,
        scalar_title,
        out_name,
        fe_aspect_ratio,
    )


def build_dic_sample_mesh(
    x_ref: np.ndarray,
    y_ref: np.ndarray,
    disp_x: np.ndarray,
    disp_y: np.ndarray,
) -> tuple[pv.PolyData, np.ndarray]:
    points_xy = np.column_stack((x_ref, y_ref))
    delaunay = Delaunay(points_xy)
    keep_mask = ~mask_dic_triangles(points_xy, delaunay.simplices)
    simplices = delaunay.simplices[keep_mask]

    faces = np.hstack((
        np.full((simplices.shape[0], 1), 3, dtype=np.int64),
        simplices.astype(np.int64),
    )).ravel()
    points_3d = np.column_stack((x_ref, y_ref, np.zeros_like(x_ref)))

    mesh = pv.PolyData(points_3d, faces)
    mesh.point_data["disp_x_mm"] = disp_x
    mesh.point_data["disp_y_mm"] = disp_y
    return mesh.clean(), simplices


def sample_dic_to_regular_grid(
    dic_mesh: pv.PolyData,
    simplices: np.ndarray,
    x_ref: np.ndarray,
    y_ref: np.ndarray,
    values: np.ndarray,
    scalar_name: str,
    grid_cols: int = 700,
) -> tuple[np.ndarray, tuple[float, float]]:
    bounds = dic_mesh.bounds
    x_min, x_max, y_min, y_max = bounds[0], bounds[1], bounds[2], bounds[3]
    x_span = x_max - x_min
    y_span = y_max - y_min
    grid_rows = max(2, int(round(grid_cols * (y_span / x_span))))

    x_vec = np.linspace(x_min, x_max, grid_cols)
    y_vec = np.linspace(y_min, y_max, grid_rows)
    x_grid, y_grid = np.meshgrid(x_vec, y_vec, indexing="xy")
    z_grid = np.zeros_like(x_grid)

    sample_grid = pv.StructuredGrid(x_grid, y_grid, z_grid)
    sample_points = np.column_stack((
        x_grid.ravel(order="C"),
        y_grid.ravel(order="C"),
        z_grid.ravel(order="C"),
    ))
    containing_cells = np.asarray(dic_mesh.find_containing_cell(sample_points))
    valid_mask = (containing_cells >= 0).reshape(y_grid.shape)

    interpolator = LinearNDInterpolator(
        np.column_stack((x_ref, y_ref)),
        values,
        fill_value=np.nan,
    )
    sampled_vals = interpolator(x_grid, y_grid)
    sampled_vals[~valid_mask] = np.nan

    return sampled_vals, (x_min, x_max, y_min, y_max)


def render_dic_panel(
    dic_mesh: pv.PolyData,
    simplices: np.ndarray,
    x_ref: np.ndarray,
    y_ref: np.ndarray,
    values: np.ndarray,
    scalar_name: str,
    clim: tuple[float, float],
    scalar_title: str,
    out_name: str,
) -> None:
    sampled_vals, extent = sample_dic_to_regular_grid(
        dic_mesh,
        simplices,
        x_ref,
        y_ref,
        values,
        scalar_name,
    )

    scale, exponent = calc_panel_scale(clim)
    aspect_ratio = (extent[1] - extent[0]) / (extent[3] - extent[2])
    fig, ax, cax = make_panel_figure(aspect_ratio)
    image = ax.imshow(
        sampled_vals / scale,
        origin="lower",
        extent=extent,
        cmap=CMAP,
        vmin=clim[0] / scale,
        vmax=clim[1] / scale,
        interpolation="nearest",
    )
    colorbar = fig.colorbar(image, cax=cax)
    colorbar.set_label(
        scaled_panel_label(scalar_title, exponent),
        fontsize=PANEL_COLORBAR_LABEL_SIZE,
    )
    colorbar.ax.tick_params(labelsize=PANEL_COLORBAR_TICK_SIZE)
    ax.set_aspect("equal")
    ax.axis("off")
    save_matplotlib_figure(fig, out_name)
    plt.close(fig)


def mask_dic_triangles(
    points_xy: np.ndarray,
    simplices: np.ndarray,
) -> np.ndarray:
    xs = points_xy[simplices, 0]
    ys = points_xy[simplices, 1]

    x_min = float(np.min(points_xy[:, 0]))
    x_max = float(np.max(points_xy[:, 0]))
    y_min = float(np.min(points_xy[:, 1]))
    y_max = float(np.max(points_xy[:, 1]))
    hole_radius = float(np.min(np.sqrt(points_xy[:, 0] * points_xy[:, 0] + points_xy[:, 1] * points_xy[:, 1])))
    hole_radius *= 0.995

    centroids_x = xs.mean(axis=1)
    centroids_y = ys.mean(axis=1)
    mid01_x = (xs[:, 0] + xs[:, 1]) * 0.5
    mid01_y = (ys[:, 0] + ys[:, 1]) * 0.5
    mid12_x = (xs[:, 1] + xs[:, 2]) * 0.5
    mid12_y = (ys[:, 1] + ys[:, 2]) * 0.5
    mid20_x = (xs[:, 2] + xs[:, 0]) * 0.5
    mid20_y = (ys[:, 2] + ys[:, 0]) * 0.5

    def outside_specimen(px: np.ndarray, py: np.ndarray) -> np.ndarray:
        outside_bounds = (px < x_min) | (px > x_max) | (py < y_min) | (py > y_max)
        inside_hole = (px * px + py * py) < (hole_radius * hole_radius)
        return outside_bounds | inside_hole

    return (
        outside_specimen(centroids_x, centroids_y) |
        outside_specimen(mid01_x, mid01_y) |
        outside_specimen(mid12_x, mid12_y) |
        outside_specimen(mid20_x, mid20_y)
    )


def combined_clim(fe_vals: np.ndarray, dic_vals: np.ndarray) -> tuple[float, float]:
    lower = float(min(np.nanmin(fe_vals), np.nanmin(dic_vals)))
    upper = float(max(np.nanmax(fe_vals), np.nanmax(dic_vals)))
    return (lower, upper)


def subfigure_block(file_name: str, caption: str, label: str) -> str:
    return (
        "\\begin{subfigure}[t]{" + SUBFIGURE_WIDTH + "}\n"
        "\\centering\n"
        f"\\includegraphics[width=\\linewidth]{{{file_name}}}\n"
        f"\\caption{{{caption}}}\n"
        f"\\label{{{label}}}\n"
        "\\end{subfigure}"
    )


def build_figs_tex() -> str:
    rows = [
        (
            subfigure_block(CAL_CAM0_PNG, "Cal target C0.", "fig:cap_demo_cal_cam0"),
            subfigure_block(CAL_CAM1_PNG, "Cal target C1.", "fig:cap_demo_cal_cam1"),
        ),
        (
            subfigure_block(RENDER_CAM0_PNG, "Specimen C0.", "fig:cap_demo_render_cam0"),
            subfigure_block(RENDER_CAM1_PNG, "Specimen C1.", "fig:cap_demo_render_cam1"),
        ),
        (
            subfigure_block(FE_UX_PNG, "FE $u_x$.", "fig:cap_demo_fe_ux"),
            subfigure_block(FE_UY_PNG, "FE $u_y$.", "fig:cap_demo_fe_uy"),
        ),
        (
            subfigure_block(DIC_UX_PNG, "Stereo DIC $u_x$.", "fig:cap_demo_dic_ux"),
            subfigure_block(DIC_UY_PNG, "Stereo DIC $u_y$.", "fig:cap_demo_dic_uy"),
        ),
    ]

    row_blocks = []
    for left_block, right_block in rows:
        row_blocks.append(
            "\\makebox[\\textwidth][c]{%\n"
            + left_block
            + "\n\\hspace{"
            + SUBFIGURE_GAP
            + "}\n"
            + right_block
            + "\n}"
        )

    body = "\n\\par\\medskip\n".join(row_blocks)
    return (
        "\\begin{figure}[htbp]\n"
        "\\centering\n"
        f"{body}\n"
        f"\\caption{{{FIG_CAPTION}}}\n"
        "\\label{fig:capability_demo}\n"
        "\\end{figure}\n"
    )


def main() -> int:
    print("Exporting raw BMP assets to PNG...")
    export_bmp_as_png(CAL_CAM0_BMP, CAL_CAM0_PNG)
    export_bmp_as_png(CAL_CAM1_BMP, CAL_CAM1_PNG)
    export_bmp_as_png(RENDER_CAM0_BMP, RENDER_CAM0_PNG)
    export_bmp_as_png(RENDER_CAM1_BMP, RENDER_CAM1_PNG)

    print("Loading DIC displacement fields...")
    x_ref, y_ref, dic_ux, dic_uy = load_dic_displacements()
    dic_mesh, dic_simplices = build_dic_sample_mesh(x_ref, y_ref, dic_ux, dic_uy)

    print("Loading FE final-frame front face...")
    fe_front_face = load_fe_front_face()
    fe_ux = np.asarray(fe_front_face["disp_x_mm"])
    fe_uy = np.asarray(fe_front_face["disp_y_mm"])

    ux_clim = combined_clim(fe_ux, dic_ux)
    uy_clim = combined_clim(fe_uy, dic_uy)

    print("Rendering FE panels...")
    render_fe_panel(fe_front_face, "disp_x_mm", r"$u_x$", ux_clim, FE_UX_PNG)
    render_fe_panel(fe_front_face, "disp_y_mm", r"$u_y$", uy_clim, FE_UY_PNG)

    print("Rendering DIC panels...")
    render_dic_panel(
        dic_mesh,
        dic_simplices,
        x_ref,
        y_ref,
        dic_ux,
        "disp_x_mm",
        ux_clim,
        r"$u_x$",
        DIC_UX_PNG,
    )
    render_dic_panel(
        dic_mesh,
        dic_simplices,
        x_ref,
        y_ref,
        dic_uy,
        "disp_y_mm",
        uy_clim,
        r"$u_y$",
        DIC_UY_PNG,
    )

    print("Writing TeX...")
    write_figs_tex(build_figs_tex())
    print(f"Wrote {repo_root() / OUT_FIGS_TEX_PATH}")
    print(f"Wrote {PAPER_DIR / OUT_FIGS_TEX_PATH.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
