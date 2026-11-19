"""Canonical native benchmark targets, installed names and experiment adapters."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BENCHMARKS = (
    "dicuq",
    "fullraster",
    "tiltraster",
    "geom",
    "sphere2000",
    "sphere2000zoom",
    "thread_geom",
    "dist_psf",
    "multiroot",
    "buffer_psf",
)
STUDIES = {
    "dicuq": "study_dicuq.py",
    "dist_psf": "study_dist_psf.py",
    "multiroot": "study_multiroot.py",
    "buffer_psf": "study_buffer_psf.py",
    "tiltraster": "study_tiltraster.py",
}
EXPERIMENTS = {
    name: {"hulls": (("--hull-mode", "on_convex_fallback"), ("--hull-mode", "on_no_fallback"))}
    for name in BENCHMARKS
    if name not in ("multiroot", "buffer_psf", "dist_psf")
}
EXPERIMENTS["multiroot"] = {
    "solver": (("--mode", "fast"), ("--mode", "robust")),
    "shaders": tuple(("--shader", shader) for shader in ("checker", "nodal", "texture", "pipe")),
}
EXPERIMENTS["buffer_psf"] = {
    "buffers": tuple(
        ("--buffer-mode", mode)
        for mode in ("tile_local", "global_subpx_full", "global_subpx_stripe")
    ),
}
EXPERIMENTS["dist_psf"] = {
    "distortion": tuple(
        ("--distort", mode)
        for mode in ("none", "brown_pincushion", "brown_ext_pincushion")
    ),
}


def binary_name(
    name: str, precision: str = "f64", simd: str = "on", lanes: int | None = None,
) -> str:
    suffix = "simd" if simd == "on" else "scalar"
    default_lanes = 8 if precision == "f64" else 16
    width = f"_v{lanes}" if simd == "on" and lanes and lanes != default_lanes else ""
    return f"bench_{name}_{precision}_{suffix}{width}"


def build_command(
    name: str, precision: str = "f64", simd: str = "on", lanes: int | None = None,
) -> list[str]:
    command = [
        "zig", "build", "install-bench-" + name.replace("_", "-"),
        "--prefix", ".", "-Doptimize=ReleaseFast",
        f"-Dprecision={precision}", f"-Dsimd={simd}",
    ]
    if lanes:
        command.append(f"-Dsimd-vector-width={lanes}")
    return command
