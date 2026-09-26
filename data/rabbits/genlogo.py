"""Generate refined vector SVG logo options for Riley.

Converts typography directly to exact vector path outlines using fonts from
/home/lloydf/lfdev/fonts (Zen Dots, Goldman, Audiowide, Michroma, Prosto One).
All variants use pure white regular-weight typography, ordered with Zen Dots
first, followed by Goldman, Audiowide, Michroma, and Prosto One.
"""

from __future__ import annotations

import math
from pathlib import Path
import subprocess
from typing import Sequence

from matplotlib.font_manager import FontProperties
from matplotlib.path import Path as MPath
from matplotlib.textpath import TextPath
import numpy as np
from svgpathtools import svg2paths


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_SVG = SCRIPT_DIR / "outline" / "Riley_ToMesh.svg"
OUTPUT_DIR = SCRIPT_DIR / "logo"
FONTS_DIR = Path("/home/lloydf/lfdev/fonts")

# =========================================================================
# 1. Canvas Configuration Constants
# =========================================================================
# Target width in SVG pixels for the rabbit silhouette on the canvas
CANVAS_TARGET_WIDTH: float = 720.0
# Padding (in pixels) added around the mesh boundary inside the canvas
CANVAS_PADDING: float = 20.0
# Explicit canvas dimensions (set to None for automatic tight viewBox)
CANVAS_FIXED_WIDTH: int | None = None
CANVAS_FIXED_HEIGHT: int | None = None
# Corner radius for the canvas background rectangle (0 for sharp corners)
CANVAS_CORNER_RADIUS: int = 0
# Default canvas background fill color
CANVAS_DEFAULT_BG_COLOR: str = "#070b0e"

# =========================================================================
# 2. Rabbit Size & Placement Constants
# =========================================================================
# Target bounding-box width of the rabbit graphic in canvas pixel space
RABBIT_TARGET_WIDTH: float = CANVAS_TARGET_WIDTH
# Horizontal flip to face right / match standard rabbit orientation
RABBIT_FLIP_HORIZONTAL: bool = True
# Explicit coordinate placement offsets on canvas (None for auto-fit)
RABBIT_OFFSET_X_OVERRIDE: float | None = None
RABBIT_OFFSET_Y_OVERRIDE: float | None = None
# Default number of boundary discretization sample points
RABBIT_DEFAULT_SAMPLE_POINTS: int = 84

# =========================================================================
# 3. Rabbit Mesh Parameters
# =========================================================================
# Default ribbon width for the boundary triangle chain mesh
MESH_DEFAULT_RIBBON_WIDTH: float = 0.024
# Default stroke width for wireframe element edges (pixels)
MESH_DEFAULT_STROKE_WIDTH: float = 1.2
# Default radius for vertex node circles (pixels)
MESH_DEFAULT_VERTEX_RADIUS: float = 2.0
# If True, only render node circles at the 3 triangle corner vertices
# (omitting the quadratic midside nodes for a cleaner visual)
MESH_RENDER_CORNER_NODES_ONLY: bool = True
# Default wireframe edge stroke color and node fill color
MESH_DEFAULT_STROKE_COLOR: str = "#10b981"
MESH_DEFAULT_VERTEX_COLOR: str = "#a7f3d0"

# =========================================================================
# 4. Font Size & Placement Constants
# =========================================================================
# Brand text string to render inside the mesh cavity
FONT_TEXT: str = "RILEY"
# Default font size in pt / px
FONT_DEFAULT_SIZE: float = 80.0
# Default font family name
FONT_DEFAULT_FAMILY: str = "Zen Dots"
# Default text fill color (strictly pure white)
FONT_DEFAULT_COLOR: str = "#ffffff"
# Additional manual X and Y offsets in pixels added to cavity center
FONT_MANUAL_X_OFFSET: float = 0.0
FONT_MANUAL_Y_OFFSET: float = 0.0
# Explicit canvas X and Y coordinates (None to compute from mesh cavity)
FONT_EXPLICIT_X: float | None = None
FONT_EXPLICIT_Y: float | None = None

# =========================================================================
# 5. Font File Path Mappings
# =========================================================================
FONT_PATHS: dict[str, Path] = {
    "Zen Dots": FONTS_DIR / "Zen_Dots" / "ZenDots-Regular.ttf",
    "Goldman": FONTS_DIR / "Goldman" / "Goldman-Regular.ttf",
    "Audiowide": FONTS_DIR / "Audiowide" / "Audiowide-Regular.ttf",
    "Michroma": FONTS_DIR / "Michroma" / "Michroma-Regular.ttf",
    "Prosto One": FONTS_DIR / "Prosto_One" / "ProstoOne-Regular.ttf",
}

# =========================================================================
# 6. PNG Rasterization & Export Constants
# =========================================================================
# Enable automatic high-resolution PNG generation via Inkscape CLI
PNG_EXPORT_ENABLED: bool = True
# Web quality resolution (pixel width)
PNG_WEB_WIDTH: int = 1200
# Print quality resolution (DPI, standard 300 DPI print)
PNG_PRINT_DPI: int = 300
# Output subdirectories for PNG assets
PNG_WEB_DIR: Path = OUTPUT_DIR / "png" / "web"
PNG_PRINT_DIR: Path = OUTPUT_DIR / "png" / "print"


def load_rabbit_boundary(
    svg_path: Path,
    num_points: int = RABBIT_DEFAULT_SAMPLE_POINTS,
    flip_horizontal: bool = RABBIT_FLIP_HORIZONTAL,
) -> np.ndarray:
    """Extract, normalize, and optionally flip rabbit outline points."""
    if not svg_path.exists():
        fallback = SCRIPT_DIR / "Riley_ToMesh.svg"
        if fallback.exists():
            svg_path = fallback
        else:
            raise FileNotFoundError(f"SVG not found at {svg_path}")

    paths, _ = svg2paths(str(svg_path))
    path = paths[0]
    sample_pts = np.array(
        [path.point(tt / 500) for tt in range(501)]
    )
    min_x = float(np.min(sample_pts.real))
    max_x = float(np.max(sample_pts.real))
    min_y = float(np.min(sample_pts.imag))
    scale = 1.0 / (max_x - min_x)

    raw_points = []
    for step_index in range(num_points):
        param = step_index / num_points
        pt = path.point(param)
        norm_x = (pt.real - min_x) * scale
        norm_y = -(pt.imag - min_y) * scale
        raw_points.append((norm_x, norm_y))

    if flip_horizontal:
        all_x = [pt[0] for pt in raw_points]
        min_flip_x, max_flip_x = min(all_x), max(all_x)
        flipped_points = [
            (max_flip_x + min_flip_x - pt[0], pt[1])
            for pt in raw_points
        ]
        pts = np.array(flipped_points, dtype=np.float64)
    else:
        pts = np.array(raw_points, dtype=np.float64)

    signed_area = 0.5 * np.sum(
        pts[:, 0] * np.roll(pts[:, 1], -1)
        - np.roll(pts[:, 0], -1) * pts[:, 1]
    )
    if signed_area < 0:
        pts = pts[::-1]
    return pts


def build_triangle_chain_mesh(
    boundary_points: np.ndarray,
    ribbon_width: float = MESH_DEFAULT_RIBBON_WIDTH,
) -> tuple[np.ndarray, np.ndarray]:
    """Build a fine zigzag ribbon chain of triangles along boundary."""
    num_pts = len(boundary_points)
    inner_pts = []

    for idx in range(num_pts):
        prev_pt = boundary_points[(idx - 1) % num_pts]
        curr_pt = boundary_points[idx]
        next_pt = boundary_points[(idx + 1) % num_pts]

        t1 = curr_pt - prev_pt
        t1_norm = np.linalg.norm(t1)
        if t1_norm > 1e-9:
            t1 = t1 / t1_norm

        t2 = next_pt - curr_pt
        t2_norm = np.linalg.norm(t2)
        if t2_norm > 1e-9:
            t2 = t2 / t2_norm

        tangent = (t1 + t2) / 2.0
        tangent_norm = np.linalg.norm(tangent)
        if tangent_norm > 1e-9:
            tangent = tangent / tangent_norm

        inward_normal = np.array([-tangent[1], tangent[0]])
        cos_half = max(
            float(np.dot(inward_normal, np.array([-t1[1], t1[0]]))),
            0.35,
        )
        miter_len = min(ribbon_width / cos_half, ribbon_width * 1.5)
        inner_pts.append(curr_pt + miter_len * inward_normal)

    inner_array = np.array(inner_pts, dtype=np.float64)
    all_coords: list[list[float]] = []
    connectivity: list[list[int]] = []

    for pt in boundary_points:
        all_coords.append([float(pt[0]), float(pt[1])])
    for pt in inner_array:
        all_coords.append([float(pt[0]), float(pt[1])])

    def add_tri6(v0_idx: int, v1_idx: int, v2_idx: int) -> None:
        p0 = np.array(all_coords[v0_idx])
        p1 = np.array(all_coords[v1_idx])
        p2 = np.array(all_coords[v2_idx])

        m01 = (p0 + p1) / 2.0
        m12 = (p1 + p2) / 2.0
        m20 = (p2 + p0) / 2.0

        m01_idx = len(all_coords)
        all_coords.append([float(m01[0]), float(m01[1])])
        m12_idx = len(all_coords)
        all_coords.append([float(m12[0]), float(m12[1])])
        m20_idx = len(all_coords)
        all_coords.append([float(m20[0]), float(m20[1])])

        connectivity.append([
            v0_idx, v1_idx, v2_idx, m01_idx, m12_idx, m20_idx
        ])

    for idx in range(num_pts):
        next_idx = (idx + 1) % num_pts
        outer_a = idx
        outer_b = next_idx
        inner_a = num_pts + idx
        inner_b = num_pts + next_idx

        add_tri6(outer_a, inner_a, outer_b)
        add_tri6(inner_a, inner_b, outer_b)

    return np.array(all_coords), np.array(connectivity, dtype=np.int64)


def get_tight_viewport(
    boundary_points: np.ndarray,
    target_width: float = CANVAS_TARGET_WIDTH,
    padding: float = CANVAS_PADDING,
    fixed_width: int | None = CANVAS_FIXED_WIDTH,
    fixed_height: int | None = CANVAS_FIXED_HEIGHT,
    offset_x_override: float | None = RABBIT_OFFSET_X_OVERRIDE,
    offset_y_override: float | None = RABBIT_OFFSET_Y_OVERRIDE,
) -> tuple[int, int, float, float, float]:
    """Calculate tight viewBox dimensions and transform parameters."""
    x_min = float(boundary_points[:, 0].min())
    x_max = float(boundary_points[:, 0].max())
    y_min = float(boundary_points[:, 1].min())
    y_max = float(boundary_points[:, 1].max())

    norm_w = x_max - x_min
    norm_h = y_max - y_min

    scale = target_width / norm_w
    svg_h = norm_h * scale
    total_w = (
        fixed_width
        if fixed_width is not None
        else int(math.ceil(target_width + 2 * padding))
    )
    total_h = (
        fixed_height
        if fixed_height is not None
        else int(math.ceil(svg_h + 2 * padding))
    )

    offset_x = (
        offset_x_override
        if offset_x_override is not None
        else padding - x_min * scale
    )
    offset_y = (
        offset_y_override
        if offset_y_override is not None
        else padding - (-y_max) * scale
    )

    return total_w, total_h, scale, offset_x, offset_y


def transform_coords(
    coords: np.ndarray,
    scale: float,
    offset_x: float,
    offset_y: float,
) -> np.ndarray:
    """Map normalized coordinates into SVG pixel space."""
    svg_coords = np.zeros_like(coords)
    svg_coords[:, 0] = offset_x + coords[:, 0] * scale
    svg_coords[:, 1] = offset_y + (-coords[:, 1]) * scale
    return svg_coords


def compute_cavity_center(
    svg_pts: np.ndarray,
    conn: np.ndarray,
    manual_x_offset: float = FONT_MANUAL_X_OFFSET,
    manual_y_offset: float = FONT_MANUAL_Y_OFFSET,
    explicit_x: float | None = FONT_EXPLICIT_X,
    explicit_y: float | None = FONT_EXPLICIT_Y,
) -> tuple[float, float]:
    """Compute geometric midpoint of rabbit inner cavity."""
    if explicit_x is not None and explicit_y is not None:
        return explicit_x + manual_x_offset, explicit_y + manual_y_offset

    p0 = svg_pts[conn[:, 0]]
    p1 = svg_pts[conn[:, 1]]
    p2 = svg_pts[conn[:, 2]]
    cents = (p0 + p1 + p2) / 3.0
    areas = 0.5 * np.abs(
        (p1[:, 0] - p0[:, 0]) * (p2[:, 1] - p0[:, 1])
        - (p2[:, 0] - p0[:, 0]) * (p1[:, 1] - p0[:, 1])
    )
    cog_x = float(np.sum(cents[:, 0] * areas) / np.sum(areas))

    inner_pts = svg_pts[conn[:, 1]]
    filtered = inner_pts[
        (inner_pts[:, 0] >= cog_x - 70) & (inner_pts[:, 0] <= cog_x + 70)
    ]
    top_y = filtered[filtered[:, 1] < 200, 1]
    bot_y = filtered[filtered[:, 1] > 200, 1]

    if len(top_y) > 0 and len(bot_y) > 0:
        base_y = float((np.mean(top_y) + np.mean(bot_y)) / 2.0)
    else:
        base_y = float(np.sum(cents[:, 1] * areas) / np.sum(areas)) + 12.0

    target_x = explicit_x if explicit_x is not None else cog_x
    target_y = explicit_y if explicit_y is not None else base_y
    return target_x + manual_x_offset, target_y + manual_y_offset


def text_to_vector_svg_path(
    text: str,
    font_path: Path,
    font_size: float,
    target_cx: float,
    target_cy: float,
) -> str:
    """Convert text into centered SVG vector path commands."""
    fp = FontProperties(fname=str(font_path), size=font_size)
    tp = TextPath((0, 0), text, prop=fp)
    bbox = tp.get_extents()
    glyph_cx = (bbox.xmin + bbox.xmax) / 2.0
    glyph_cy = (bbox.ymin + bbox.ymax) / 2.0

    d_parts = []
    v_idx = 0
    codes = tp.codes
    verts = tp.vertices

    while v_idx < len(codes):
        code = codes[v_idx]
        if code == MPath.MOVETO:
            x = target_cx + (verts[v_idx][0] - glyph_cx)
            y = target_cy - (verts[v_idx][1] - glyph_cy)
            d_parts.append(f"M {x:.1f} {y:.1f}")
            v_idx += 1
        elif code == MPath.LINETO:
            x = target_cx + (verts[v_idx][0] - glyph_cx)
            y = target_cy - (verts[v_idx][1] - glyph_cy)
            d_parts.append(f"L {x:.1f} {y:.1f}")
            v_idx += 1
        elif code == MPath.CURVE3:
            cx1 = target_cx + (verts[v_idx][0] - glyph_cx)
            cy1 = target_cy - (verts[v_idx][1] - glyph_cy)
            x = target_cx + (verts[v_idx + 1][0] - glyph_cx)
            y = target_cy - (verts[v_idx + 1][1] - glyph_cy)
            d_parts.append(f"Q {cx1:.1f} {cy1:.1f} {x:.1f} {y:.1f}")
            v_idx += 2
        elif code == MPath.CURVE4:
            cx1 = target_cx + (verts[v_idx][0] - glyph_cx)
            cy1 = target_cy - (verts[v_idx][1] - glyph_cy)
            cx2 = target_cx + (verts[v_idx + 1][0] - glyph_cx)
            cy2 = target_cy - (verts[v_idx + 1][1] - glyph_cy)
            x = target_cx + (verts[v_idx + 2][0] - glyph_cx)
            y = target_cy - (verts[v_idx + 2][1] - glyph_cy)
            d_parts.append(
                f"C {cx1:.1f} {cy1:.1f} {cx2:.1f} {cy2:.1f} "
                f"{x:.1f} {y:.1f}"
            )
            v_idx += 3
        elif code == MPath.CLOSEPOLY:
            d_parts.append("Z")
            v_idx += 1
        else:
            v_idx += 1

    return " ".join(d_parts)


def render_svg_file(
    output_path: Path,
    width: int,
    height: int,
    bg_color: str = CANVAS_DEFAULT_BG_COLOR,
    elements_svg: Sequence[str] = (),
    rx: int = CANVAS_CORNER_RADIUS,
) -> None:
    """Assemble and write a valid standalone SVG file."""
    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {width} {height}" '
        f'width="{width}" height="{height}">',
    ]

    if bg_color and bg_color.lower() != "none":
        rx_attr = f' rx="{rx}"' if rx > 0 else ""
        lines.append(
            f'  <rect width="100%" height="100%" '
            f'fill="{bg_color}"{rx_attr} />'
        )

    for item in elements_svg:
        lines.append(f"  {item}")

    lines.append("</svg>\n")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines), encoding="utf-8")


def build_logo_elements(
    svg_pts: np.ndarray,
    conn: np.ndarray,
    shades: Sequence[str],
    stroke_color: str,
    stroke_width: float,
    vertex_color: str,
    vertex_radius: float,
    font_family: str,
    font_size: float,
) -> list[str]:
    """Assemble SVG polygon, circle, and vector outline text elements."""
    svg_items = []
    for idx, elem in enumerate(conn):
        p0, p1, p2 = svg_pts[elem[0]], svg_pts[elem[1]], svg_pts[elem[2]]
        svg_items.append(
            f'<polygon points="{p0[0]:.1f},{p0[1]:.1f} '
            f'{p1[0]:.1f},{p1[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}" '
            f'fill="{shades[idx % len(shades)]}" stroke="{stroke_color}" '
            f'stroke-width="{stroke_width:.1f}" stroke-linejoin="round" />'
        )

    for elem in conn:
        for c_idx in elem[:3]:
            pt = svg_pts[c_idx]
            svg_items.append(
                f'<circle cx="{pt[0]:.1f}" cy="{pt[1]:.1f}" '
                f'r="{vertex_radius:.1f}" fill="{vertex_color}" />'
            )

    cx, cy = compute_cavity_center(svg_pts, conn)
    font_path = FONT_PATHS.get(font_family)
    if font_path and font_path.exists():
        d_path = text_to_vector_svg_path(
            FONT_TEXT, font_path, font_size, cx, cy
        )
        svg_items.append(f'<path d="{d_path}" fill="#ffffff" />')
    else:
        svg_items.append(
            f'<text x="{cx:.1f}" y="{cy:.1f}" text-anchor="middle" '
            f'dominant-baseline="central" '
            f'font-family="\'{font_family}\', sans-serif" '
            f'font-size="{font_size}" fill="#ffffff">'
            f'{FONT_TEXT}</text>'
        )

    return svg_items


# -------------------------------------------------------------------------
# Group 1: Style 1 (Emerald Obsidian Theme)
# -------------------------------------------------------------------------

def gen_group1_var1(out_dir: Path, base_svg: Path) -> None:
    """G1.1: Style 1 (N=80, Med), Zen Dots 78pt, Pure White."""
    boundary = load_rabbit_boundary(base_svg, num_points=80)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.024)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a"],
        stroke_color="#10b981", stroke_width=1.2,
        vertex_color="#a7f3d0", vertex_radius=2.0,
        font_family="Zen Dots", font_size=78.0,
    )
    render_svg_file(
        out_dir / "logo_01_var1_emerald_zen_dots_78pt.svg",
        w, h, "#070b0e", elems
    )


def gen_group1_var2(out_dir: Path, base_svg: Path) -> None:
    """G1.2: Style 1 (N=84, Med-Fine), Goldman 82pt, Pure White."""
    boundary = load_rabbit_boundary(base_svg, num_points=84)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.022)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a"],
        stroke_color="#10b981", stroke_width=1.2,
        vertex_color="#a7f3d0", vertex_radius=2.0,
        font_family="Goldman", font_size=82.0,
    )
    render_svg_file(
        out_dir / "logo_01_var2_emerald_goldman_82pt.svg",
        w, h, "#070b0e", elems
    )


def gen_group1_var3(out_dir: Path, base_svg: Path) -> None:
    """G1.3: Style 1 (N=76, Med), Audiowide 80pt, Pure White."""
    boundary = load_rabbit_boundary(base_svg, num_points=76)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.025)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a"],
        stroke_color="#10b981", stroke_width=1.3,
        vertex_color="#a7f3d0", vertex_radius=2.2,
        font_family="Audiowide", font_size=80.0,
    )
    render_svg_file(
        out_dir / "logo_01_var3_emerald_audiowide_80pt.svg",
        w, h, "#070b0e", elems
    )


def gen_group1_var4(out_dir: Path, base_svg: Path) -> None:
    """G1.4: Style 1 (N=80, Med), Michroma 72pt, Pure White."""
    boundary = load_rabbit_boundary(base_svg, num_points=80)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.024)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a"],
        stroke_color="#10b981", stroke_width=1.2,
        vertex_color="#a7f3d0", vertex_radius=2.0,
        font_family="Michroma", font_size=72.0,
    )
    render_svg_file(
        out_dir / "logo_01_var4_emerald_michroma_72pt.svg",
        w, h, "#070b0e", elems
    )


def gen_group1_var5(out_dir: Path, base_svg: Path) -> None:
    """G1.5: Style 1 (N=88, Med-Fine), Prosto One 84pt, Pure White."""
    boundary = load_rabbit_boundary(base_svg, num_points=88)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.021)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a"],
        stroke_color="#10b981", stroke_width=1.1,
        vertex_color="#a7f3d0", vertex_radius=1.8,
        font_family="Prosto One", font_size=84.0,
    )
    render_svg_file(
        out_dir / "logo_01_var5_emerald_prosto_one_84pt.svg",
        w, h, "#070b0e", elems
    )


def gen_group1_var6(out_dir: Path, base_svg: Path) -> None:
    """G1.6: Style 1 (N=104, Superfine), Zen Dots 80pt, Pure White."""
    boundary = load_rabbit_boundary(base_svg, num_points=104)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.017)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a"],
        stroke_color="#10b981", stroke_width=0.9,
        vertex_color="#a7f3d0", vertex_radius=1.5,
        font_family="Zen Dots", font_size=80.0,
    )
    render_svg_file(
        out_dir / "logo_01_var6_emerald_zen_dots_superfine_80pt.svg",
        w, h, "#070b0e", elems
    )


# -------------------------------------------------------------------------
# Group 2: Style 5 (Precision CAD Theme)
# -------------------------------------------------------------------------

def gen_group2_var1(out_dir: Path, base_svg: Path) -> None:
    """G2.1: Style 5 (N=88, Med-Fine), Zen Dots 80pt, Precision CAD."""
    boundary = load_rabbit_boundary(base_svg, num_points=88)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.020)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#0f172a"],
        stroke_color="#34d399", stroke_width=1.1,
        vertex_color="#ffffff", vertex_radius=1.8,
        font_family="Zen Dots", font_size=80.0,
    )
    render_svg_file(
        out_dir / "logo_05_var1_cad_zen_dots_80pt.svg",
        w, h, "#090f14", elems
    )


def gen_group2_var2(out_dir: Path, base_svg: Path) -> None:
    """G2.2: Style 5 (N=96, Fine), Goldman 84pt, Precision CAD."""
    boundary = load_rabbit_boundary(base_svg, num_points=96)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.019)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#0f172a"],
        stroke_color="#34d399", stroke_width=1.0,
        vertex_color="#ffffff", vertex_radius=1.6,
        font_family="Goldman", font_size=84.0,
    )
    render_svg_file(
        out_dir / "logo_05_var2_cad_goldman_84pt.svg",
        w, h, "#090f14", elems
    )


def gen_group2_var3(out_dir: Path, base_svg: Path) -> None:
    """G2.3: Style 5 (N=88, Med-Fine), Audiowide 80pt, Precision CAD."""
    boundary = load_rabbit_boundary(base_svg, num_points=88)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.020)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#0f172a"],
        stroke_color="#34d399", stroke_width=1.1,
        vertex_color="#ffffff", vertex_radius=1.8,
        font_family="Audiowide", font_size=80.0,
    )
    render_svg_file(
        out_dir / "logo_05_var3_cad_audiowide_80pt.svg",
        w, h, "#090f14", elems
    )


def gen_group2_var4(out_dir: Path, base_svg: Path) -> None:
    """G2.4: Style 5 (N=84, Med), Michroma 74pt, Precision CAD."""
    boundary = load_rabbit_boundary(base_svg, num_points=84)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.022)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#0f172a"],
        stroke_color="#34d399", stroke_width=1.2,
        vertex_color="#ffffff", vertex_radius=1.9,
        font_family="Michroma", font_size=74.0,
    )
    render_svg_file(
        out_dir / "logo_05_var4_cad_michroma_74pt.svg",
        w, h, "#090f14", elems
    )


def gen_group2_var5(out_dir: Path, base_svg: Path) -> None:
    """G2.5: Style 5 (N=88, Med-Fine), Prosto One 82pt, Precision CAD."""
    boundary = load_rabbit_boundary(base_svg, num_points=88)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.020)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#0f172a"],
        stroke_color="#34d399", stroke_width=1.1,
        vertex_color="#ffffff", vertex_radius=1.8,
        font_family="Prosto One", font_size=82.0,
    )
    render_svg_file(
        out_dir / "logo_05_var5_cad_prosto_one_82pt.svg",
        w, h, "#090f14", elems
    )


def gen_group2_var6(out_dir: Path, base_svg: Path) -> None:
    """G2.6: Style 5 (N=104, Superfine), Goldman 80pt, Precision CAD."""
    boundary = load_rabbit_boundary(base_svg, num_points=104)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.017)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#0f172a"],
        stroke_color="#34d399", stroke_width=0.9,
        vertex_color="#ffffff", vertex_radius=1.5,
        font_family="Goldman", font_size=80.0,
    )
    render_svg_file(
        out_dir / "logo_05_var6_cad_goldman_superfine_80pt.svg",
        w, h, "#090f14", elems
    )


# -------------------------------------------------------------------------
# Group 3: Style 18 (Slate Graphite Theme)
# -------------------------------------------------------------------------

def gen_group3_var1(out_dir: Path, base_svg: Path) -> None:
    """G3.1: Style 18 (N=80, Med), Zen Dots 78pt, Slate Graphite."""
    boundary = load_rabbit_boundary(base_svg, num_points=80)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.023)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#1f2937", "#111827", "#374151", "#1e293b"],
        stroke_color="#10b981", stroke_width=1.2,
        vertex_color="#6ee7b7", vertex_radius=1.9,
        font_family="Zen Dots", font_size=78.0,
    )
    render_svg_file(
        out_dir / "logo_18_var1_graphite_zen_dots_78pt.svg",
        w, h, "#0c1015", elems
    )


def gen_group3_var2(out_dir: Path, base_svg: Path) -> None:
    """G3.2: Style 18 (N=88, Med-Fine), Goldman 84pt, Slate Graphite."""
    boundary = load_rabbit_boundary(base_svg, num_points=88)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.021)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#1f2937", "#111827", "#374151", "#1e293b"],
        stroke_color="#10b981", stroke_width=1.1,
        vertex_color="#6ee7b7", vertex_radius=1.8,
        font_family="Goldman", font_size=84.0,
    )
    render_svg_file(
        out_dir / "logo_18_var2_graphite_goldman_84pt.svg",
        w, h, "#0c1015", elems
    )


def gen_group3_var3(out_dir: Path, base_svg: Path) -> None:
    """G3.3: Style 18 (N=76, Med), Audiowide 82pt, Slate Graphite."""
    boundary = load_rabbit_boundary(base_svg, num_points=76)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.024)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#1f2937", "#111827", "#374151", "#1e293b"],
        stroke_color="#10b981", stroke_width=1.3,
        vertex_color="#6ee7b7", vertex_radius=2.1,
        font_family="Audiowide", font_size=82.0,
    )
    render_svg_file(
        out_dir / "logo_18_var3_graphite_audiowide_82pt.svg",
        w, h, "#0c1015", elems
    )


def gen_group3_var4(out_dir: Path, base_svg: Path) -> None:
    """G3.4: Style 18 (N=80, Med), Michroma 72pt, Slate Graphite."""
    boundary = load_rabbit_boundary(base_svg, num_points=80)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.023)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#1f2937", "#111827", "#374151", "#1e293b"],
        stroke_color="#10b981", stroke_width=1.2,
        vertex_color="#6ee7b7", vertex_radius=1.9,
        font_family="Michroma", font_size=72.0,
    )
    render_svg_file(
        out_dir / "logo_18_var4_graphite_michroma_72pt.svg",
        w, h, "#0c1015", elems
    )


def gen_group3_var5(out_dir: Path, base_svg: Path) -> None:
    """G3.5: Style 18 (N=104, Superfine), Prosto One 84pt, Slate Graphite."""
    boundary = load_rabbit_boundary(base_svg, num_points=104)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.017)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#1f2937", "#111827", "#374151", "#1e293b"],
        stroke_color="#10b981", stroke_width=0.9,
        vertex_color="#6ee7b7", vertex_radius=1.5,
        font_family="Prosto One", font_size=84.0,
    )
    render_svg_file(
        out_dir / "logo_18_var5_graphite_prosto_one_84pt.svg",
        w, h, "#0c1015", elems
    )


def gen_group3_var6(out_dir: Path, base_svg: Path) -> None:
    """G3.6: Style 18 (N=92, Fine), Zen Dots 78pt, Slate Graphite."""
    boundary = load_rabbit_boundary(base_svg, num_points=92)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.020)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#1f2937", "#111827", "#374151", "#1e293b"],
        stroke_color="#10b981", stroke_width=1.1,
        vertex_color="#6ee7b7", vertex_radius=1.8,
        font_family="Zen Dots", font_size=78.0,
    )
    render_svg_file(
        out_dir / "logo_18_var6_graphite_zen_dots_fine_78pt.svg",
        w, h, "#0c1015", elems
    )


# -------------------------------------------------------------------------
# Group 4: Style 19 (Ultra-Density Mesh Theme)
# -------------------------------------------------------------------------

def gen_group4_var1(out_dir: Path, base_svg: Path) -> None:
    """G4.1: Style 19 (N=92, Fine), Zen Dots 80pt, Ultra-Density Mesh."""
    boundary = load_rabbit_boundary(base_svg, num_points=92)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.019)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a", "#059669"],
        stroke_color="#34d399", stroke_width=1.0,
        vertex_color="#ffffff", vertex_radius=1.7,
        font_family="Zen Dots", font_size=80.0,
    )
    render_svg_file(
        out_dir / "logo_19_var1_density_zen_dots_80pt.svg",
        w, h, "#081014", elems
    )


def gen_group4_var2(out_dir: Path, base_svg: Path) -> None:
    """G4.2: Style 19 (N=104, Superfine), Goldman 84pt, Density Mesh."""
    boundary = load_rabbit_boundary(base_svg, num_points=104)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.017)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a", "#059669"],
        stroke_color="#34d399", stroke_width=0.9,
        vertex_color="#ffffff", vertex_radius=1.5,
        font_family="Goldman", font_size=84.0,
    )
    render_svg_file(
        out_dir / "logo_19_var2_density_goldman_84pt.svg",
        w, h, "#081014", elems
    )


def gen_group4_var3(out_dir: Path, base_svg: Path) -> None:
    """G4.3: Style 19 (N=92, Fine), Audiowide 80pt, Density Mesh."""
    boundary = load_rabbit_boundary(base_svg, num_points=92)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.019)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a", "#059669"],
        stroke_color="#34d399", stroke_width=1.0,
        vertex_color="#ffffff", vertex_radius=1.7,
        font_family="Audiowide", font_size=80.0,
    )
    render_svg_file(
        out_dir / "logo_19_var3_density_audiowide_80pt.svg",
        w, h, "#081014", elems
    )


def gen_group4_var4(out_dir: Path, base_svg: Path) -> None:
    """G4.4: Style 19 (N=88, Med-Fine), Michroma 74pt, Density Mesh."""
    boundary = load_rabbit_boundary(base_svg, num_points=88)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.020)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a", "#059669"],
        stroke_color="#34d399", stroke_width=1.1,
        vertex_color="#ffffff", vertex_radius=1.8,
        font_family="Michroma", font_size=74.0,
    )
    render_svg_file(
        out_dir / "logo_19_var4_density_michroma_74pt.svg",
        w, h, "#081014", elems
    )


def gen_group4_var5(out_dir: Path, base_svg: Path) -> None:
    """G4.5: Style 19 (N=96, Fine), Prosto One 84pt, Density Mesh."""
    boundary = load_rabbit_boundary(base_svg, num_points=96)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.019)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a", "#059669"],
        stroke_color="#34d399", stroke_width=1.0,
        vertex_color="#ffffff", vertex_radius=1.6,
        font_family="Prosto One", font_size=84.0,
    )
    render_svg_file(
        out_dir / "logo_19_var5_density_prosto_one_84pt.svg",
        w, h, "#081014", elems
    )


def gen_group4_var6(out_dir: Path, base_svg: Path) -> None:
    """G4.6: Style 19 (N=112, Micro-Density), Zen Dots 80pt, Superfine."""
    boundary = load_rabbit_boundary(base_svg, num_points=112)
    w, h, scale, ox, oy = get_tight_viewport(boundary)
    coords, conn = build_triangle_chain_mesh(boundary, ribbon_width=0.016)
    svg_pts = transform_coords(coords, scale, ox, oy)
    elems = build_logo_elements(
        svg_pts, conn,
        shades=["#064e3b", "#0f766e", "#047857", "#134e4a", "#059669"],
        stroke_color="#34d399", stroke_width=0.8,
        vertex_color="#ffffff", vertex_radius=1.4,
        font_family="Zen Dots", font_size=80.0,
    )
    render_svg_file(
        out_dir / "logo_19_var6_density_zen_dots_superfine_80pt.svg",
        w, h, "#081014", elems
    )


def export_all_pngs(logo_dir: Path) -> None:
    """Export all SVG logos to Web and 300 DPI Print PNGs via Inkscape."""
    web_dir = logo_dir / "png" / "web"
    print_dir = logo_dir / "png" / "print"
    web_dir.mkdir(parents=True, exist_ok=True)
    print_dir.mkdir(parents=True, exist_ok=True)

    svg_files = sorted(logo_dir.glob("*.svg"))
    print(f"Exporting {len(svg_files)} logos to Web and Print PNGs...")

    for svg in svg_files:
        web_out = web_dir / f"{svg.stem}.png"
        print_out = print_dir / f"{svg.stem}.png"

        # Web resolution (1200px width)
        subprocess.run(
            [
                "inkscape",
                str(svg),
                f"--export-filename={web_out}",
                f"--export-width={PNG_WEB_WIDTH}",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        # Print resolution (300 DPI)
        subprocess.run(
            [
                "inkscape",
                str(svg),
                f"--export-filename={print_out}",
                f"--export-dpi={PNG_PRINT_DPI}",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def generate_gallery_html(logo_dir: Path) -> None:
    """Generate an interactive HTML catalog to view all generated SVG logos."""
    svg_files = sorted(logo_dir.glob("*.svg"))
    html_lines = [
        "<!DOCTYPE html>",
        '<html lang="en">',
        "<head>",
        '  <meta charset="UTF-8">',
        '  <meta name="viewport" '
        'content="width=device-width, initial-scale=1">',
        "  <title>Riley Refined Logo Variations (Custom Fonts)</title>",
        "  <style>",
        "    body {",
        "      margin: 0;",
        "      padding: 30px;",
        "      background-color: #080d12;",
        "      color: #e2e8f0;",
        "      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', "
        "sans-serif;",
        "    }",
        "    h1 { color: #10b981; margin-bottom: 8px; }",
        "    p.subtitle {",
        "      color: #94a3b8; margin-top: 0; margin-bottom: 25px;",
        "    }",
        "    .grid {",
        "      display: grid;",
        "      grid-template-columns: repeat(auto-fill, minmax(420px, 1fr));",
        "      gap: 24px;",
        "    }",
        "    .card {",
        "      background: #121922;",
        "      border: 1px solid #1e293b;",
        "      border-radius: 10px;",
        "      overflow: hidden;",
        "      display: flex;",
        "      flex-direction: column;",
        "    }",
        "    .card-header {",
        "      padding: 12px 16px;",
        "      background: #17212d;",
        "      border-bottom: 1px solid #1e293b;",
        "      font-size: 14px;",
        "      font-weight: 600;",
        "      color: #34d399;",
        "      display: flex;",
        "      justify-content: space-between;",
        "      align-items: center;",
        "    }",
        "    .img-box {",
        "      padding: 16px;",
        "      display: flex;",
        "      align-items: center;",
        "      justify-content: center;",
        "      flex-grow: 1;",
        "    }",
        "    img { max-width: 100%; height: auto; display: block; }",
        "    .card-footer {",
        "      padding: 10px 16px;",
        "      background: #0f151c;",
        "      border-top: 1px solid #1e293b;",
        "      font-size: 12px;",
        "      display: flex;",
        "      gap: 12px;",
        "    }",
        "    .card-footer a {",
        "      color: #38bdf8;",
        "      text-decoration: none;",
        "    }",
        "    .card-footer a:hover {",
        "      text-decoration: underline;",
        "    }",
        "  </style>",
        "</head>",
        "<body>",
        "  <h1>Riley Refined Logo Variations (Pure White Outlines)</h1>",
        '  <p class="subtitle">24 variations in pure white (#ffffff) '
        "ordered with Zen Dots first, Goldman second, then Audiowide, "
        "Michroma, and Prosto One across medium to superfine meshes</p>",
        '  <div class="grid">',
    ]

    for svg_file in svg_files:
        name = svg_file.name
        stem = svg_file.stem
        title = name.replace(".svg", "").replace("_", " ").title()
        html_lines.append('    <div class="card">')
        html_lines.append(
            f'      <div class="card-header"><span>{title}</span></div>'
        )
        html_lines.append('      <div class="img-box">')
        html_lines.append(f'        <img src="{name}" alt="{title}" />')
        html_lines.append('      </div>')
        html_lines.append('      <div class="card-footer">')
        html_lines.append(f'        <a href="{name}" download>SVG Vector</a>')
        html_lines.append(
            f'        <a href="png/web/{stem}.png" download>'
            f'Web PNG (1200px)</a>'
        )
        html_lines.append(
            f'        <a href="png/print/{stem}.png" download>'
            f'Print PNG (300 DPI)</a>'
        )
        html_lines.append('      </div>')
        html_lines.append('    </div>')

    html_lines.extend([
        "  </div>",
        "</body>",
        "</html>\n",
    ])

    (logo_dir / "index.html").write_text(
        "\n".join(html_lines), encoding="utf-8"
    )


def generate_all_logos() -> None:
    """Run all 24 refined logo generators and create the HTML catalog."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for old_svg in OUTPUT_DIR.glob("*.svg"):
        old_svg.unlink()

    generators = [
        # Group 1: Style 1 (Emerald Obsidian Theme)
        ("01.1 Emerald Zen Dots 78pt", gen_group1_var1),
        ("01.2 Emerald Goldman 82pt", gen_group1_var2),
        ("01.3 Emerald Audiowide 80pt", gen_group1_var3),
        ("01.4 Emerald Michroma 72pt", gen_group1_var4),
        ("01.5 Emerald Prosto One 84pt", gen_group1_var5),
        ("01.6 Emerald Zen Dots Superfine 80pt", gen_group1_var6),
        # Group 2: Style 5 (Precision CAD Theme)
        ("05.1 CAD Zen Dots 80pt", gen_group2_var1),
        ("05.2 CAD Goldman 84pt", gen_group2_var2),
        ("05.3 CAD Audiowide 80pt", gen_group2_var3),
        ("05.4 CAD Michroma 74pt", gen_group2_var4),
        ("05.5 CAD Prosto One 82pt", gen_group2_var5),
        ("05.6 CAD Goldman Superfine 80pt", gen_group2_var6),
        # Group 3: Style 18 (Slate Graphite Theme)
        ("18.1 Graphite Zen Dots 78pt", gen_group3_var1),
        ("18.2 Graphite Goldman 84pt", gen_group3_var2),
        ("18.3 Graphite Audiowide 82pt", gen_group3_var3),
        ("18.4 Graphite Michroma 72pt", gen_group3_var4),
        ("18.5 Graphite Prosto One 84pt", gen_group3_var5),
        ("18.6 Graphite Zen Dots Fine 78pt", gen_group3_var6),
        # Group 4: Style 19 (Ultra-Density Mesh Theme)
        ("19.1 Density Zen Dots 80pt", gen_group4_var1),
        ("19.2 Density Goldman 84pt", gen_group4_var2),
        ("19.3 Density Audiowide 80pt", gen_group4_var3),
        ("19.4 Density Michroma 74pt", gen_group4_var4),
        ("19.5 Density Prosto One 84pt", gen_group4_var5),
        ("19.6 Density Zen Dots Superfine 80pt", gen_group4_var6),
    ]

    for label, gen_func in generators:
        print(f"Generating [{label}]...")
        gen_func(OUTPUT_DIR, DEFAULT_SVG)

    if PNG_EXPORT_ENABLED:
        export_all_pngs(OUTPUT_DIR)

    generate_gallery_html(OUTPUT_DIR)
    print(
        f"Successfully generated {len(generators)} SVG logos in {OUTPUT_DIR}"
    )
    print(f"Interactive gallery available at: {OUTPUT_DIR / 'index.html'}")


if __name__ == "__main__":
    generate_all_logos()
