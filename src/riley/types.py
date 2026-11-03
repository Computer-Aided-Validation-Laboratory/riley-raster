# Riley scene inputs and configuration. These are ordinary Python objects;
# the Cython layer only adapts their buffers and calls the public C ABI.
from __future__ import annotations

from dataclasses import dataclass, field
from enum import IntEnum
from numbers import Integral
from typing import Any
import numpy as np

class EPolyMode(IntEnum):
    coordinate = 0
    displacement = 1


@dataclass(slots=True)
class PolyMap:
    """Forward normalized-coordinate map with paired coefficients.

    Parameters
    ----------
    degree
        Total degree, from 1 through 7.
    mode
        Coordinate output or identity-plus-displacement interpretation.
    coeffs
        Shape (term_count, 2), ordered by total degree, descending x exponent.
        Bindings take an owned contiguous float64 snapshot for each native
        call.
    """

    degree: int
    mode: EPolyMode
    coeffs: np.ndarray


class RenderFormat(IntEnum):
    mono = 0
    rgb = 1
    ir = 2
    multifield = 3


class CodePacking(IntEnum):
    spread = 0
    lower = 1
    upper = 2


@dataclass(slots=True)
class ImageSaveOpts:
    format: int = 3
    file_bits: int | None = 8
    adc_bits: int | None = None
    scaling: int = 0
    scaling_min: float = 0.0
    scaling_max: float = 1.0
    packing: CodePacking = CodePacking.spread


@dataclass(slots=True)
class Camera:
    pixels_num: tuple[int, int]
    pixels_size: tuple[float, float]
    pos_world: tuple[float, float, float]
    rot_world: tuple[float, float, float]
    roi_cent_world: tuple[float, float, float]
    focal_length: float
    sub_sample: int
    background_value: float = 0.0
    distort_model: int = 0
    distort_k1: float = 0.0
    distort_k2: float = 0.0
    distort_k3: float = 0.0
    distort_k4: float = 0.0
    distort_k5: float = 0.0
    distort_k6: float = 0.0
    distort_p1: float = 0.0
    distort_p2: float = 0.0
    distort_s1: float = 0.0
    distort_s2: float = 0.0
    distort_s3: float = 0.0
    distort_s4: float = 0.0
    distort_tau_x: float = 0.0
    distort_tau_y: float = 0.0
    distort_poly: PolyMap | None = None
    coord_sys: int = 0
    subpixel_center_map: int = 1
    psf_type: int = 0
    psf_sigma_x: float = 0.0
    psf_sigma_y: float = 0.0
    psf_theta: float = 0.0
    psf_support_rad: float = 0.0
    psf_separable: int = 1
    render_format: Any = RenderFormat.mono
    render_channels: int = 1
    output_files: tuple[ImageSaveOpts, ...] | list[ImageSaveOpts] | None = None

    def __post_init__(self) -> None:
        self.render_format = RenderFormat(self.render_format)
        if self.render_format in (RenderFormat.mono, RenderFormat.ir):
            self.render_channels = 1
        elif self.render_format == RenderFormat.rgb:
            self.render_channels = 3


@dataclass(slots=True)
class FuncShaderParams:
    coord_scale: tuple[float, float] = (1.0, 1.0)
    coord_offset: tuple[float, float] = (0.0, 0.0)
    constant_value: float = 0.5
    constant_value_rgb: tuple[float, float, float] = (0.2, 0.5, 0.8)
    linear_coeffs: tuple[float, float, float] = (0.5, 0.25, 0.2)
    linear_coeffs_rgb: tuple[
        tuple[float, float, float],
        tuple[float, float, float],
        tuple[float, float, float],
    ] = (
        (0.5, 0.25, 0.0),
        (0.5, 0.0, 0.25),
        (0.5, 0.15, -0.15),
    )
    quadratic_coeffs: tuple[float, float, float, float, float, float] = (
        0.35,
        0.2,
        0.15,
        0.1,
        -0.08,
        0.06,
    )
    quadratic_coeffs_rgb: tuple[
        tuple[float, float, float, float, float, float],
        tuple[float, float, float, float, float, float],
        tuple[float, float, float, float, float, float],
    ] = (
        (0.3, 0.0, 0.0, 0.2, 0.0, 0.0),
        (0.3, 0.0, 0.0, 0.0, 0.0, 0.2),
        (0.3, 0.0, 0.0, 0.0, 0.12, 0.0),
    )
    wave_num_scalar: tuple[float, float] = (6.0, 5.0)
    wave_num_rgb: tuple[float, float, float] = (6.0, 6.0, 4.0)
    sinusoidal_bias: float = 0.5
    sinusoidal_amplitudes: tuple[float, float] = (0.25, 0.2)
    sinusoidal_bias_rgb: tuple[float, float, float] = (0.5, 0.5, 0.5)
    sinusoidal_amplitudes_rgb: tuple[float, float, float] = (
        0.25,
        0.25,
        0.2,
    )
    checker_levels: tuple[float, float] = (0.0, 1.0)
    checker_smooth_frequency: float = 8.0
    lambertian_coeffs: tuple[float, float] = (0.5, 0.5)
    lambertian_coeffs_rgb: tuple[
        tuple[float, float],
        tuple[float, float],
        tuple[float, float],
    ] = (
        (0.5, 0.5),
        (0.375, 0.375),
        (0.25, 0.25),
    )
    eggbox_mean: float = 0.5
    eggbox_contrast: float = 0.4
    eggbox_pitch: tuple[float, float] = (1.0, 1.0)
    eggbox_phase: tuple[float, float] = (0.0, 0.0)


class RenderMode(IntEnum):
    in_order = 0
    offline = 1


@dataclass(slots=True)
class RasterConfig:
    """Raster settings; ``parallel=None`` delegates thread planning to Zig.

    Use 1 for serial rendering or a positive integer for an explicit thread
    budget. The count includes group caller threads, not disk-save workers.
    """

    render_mode: int = RenderMode.offline
    # Keep this untyped at the Cython boundary until strict validation runs.
    parallel: Any = None
    save_strategy: int = 1
    oneroot_hull_mode: int = 1
    oneroot_newton_seed_mode: int = 0
    oneroot_newton_seed_reuse: int = 0
    oneroot_edge_fun_mode: int = 0
    multiroot_mode: int = 0
    multiroot_edge_fun_mode: int = 1
    validate_input: int = 1
    report_perf: int = 0
    report_console: bool = False
    tile_size_min: int = 1
    tile_size_max: int = 256
    disk_save_overlap: bool = False
    tile_size_override: int = 0
    global_subpx_tile_size_min: int = 64
    global_subpx_tile_size_max: int = 1024
    global_subpx_tile_size_override: int = 0
    global_subpx_stripe_size_min: int = 256
    global_subpx_stripe_size_max: int = 4096
    global_subpx_stripe_size_override: int = 0
    raster_halo_px_override: int = 0
    save_frame_buffer_count: int = 3
    buffer_mode: int = 0
    output_name_format: str = "cam{camera}_frame{frame}_field{field}"
    edge_spacing_px: float = 1.0

    def __post_init__(self) -> None:
        _check_parallel(self.parallel)


def _check_parallel(parallel: Any) -> None:
    if parallel is None:
        return
    if isinstance(parallel, bool) or not isinstance(parallel, Integral):
        raise TypeError("parallel must be an integer thread budget or None.")
    if parallel < 1 or parallel > 65535:
        raise ValueError("parallel must be between 1 and 65535.")


class MeshType(IntEnum):
    tri3 = 0
    tri3opt = 1
    tri6 = 2
    quad4 = 4
    quad8 = 5
    quad9 = 6


class ShaderType(IntEnum):
    tex = 0
    tex_rgb = 1
    nodal = 2
    func = 3
    func_rgb = 4
    nodal_rgb = 5
    func_multi = 6
    tex_multi = 7


class TextureStorage(IntEnum):
    u8 = 0
    u16 = 1
    floating = 2


class SaveStrategy(IntEnum):
    disk = 0
    memory = 1
    both = 2
    none = 3


class ReportMode(IntEnum):
    off = 0
    bench = 1


class BufferMode(IntEnum):
    tile_local = 0
    global_subpx_full = 1
    global_subpx_stripe = 2


class SubPixelCenterMap(IntEnum):
    full_in_mem = 0
    per_tile = 1


class TextureSample(IntEnum):
    nearest = 0
    linear = 1
    cubic_catmull_rom = 2
    cubic_mitchell_netravali = 3
    lanczos3 = 4
    cubic_bspline = 5
    quintic_bspline = 6
    lanczos2 = 7


class TextureSampleMode(IntEnum):
    direct = 0
    lut = 1
    lut_lerp = 2


class ScaleStrategy(IntEnum):
    none = 0
    auto = 1
    fixed = 2
    frac = 3


class ScaleOver(IntEnum):
    within_frames = 0
    over_frames = 1


class FuncShaderBuiltin(IntEnum):
    constant = 0
    linear = 1
    quadratic = 2
    sinusoidal = 3
    sinusoidal_approx = 4
    checker = 5
    checker_smooth = 6
    lambertian_normal_z = 7
    eggbox = 8


class FuncCoordMode(IntEnum):
    uv = 0
    parametric = 1
    world_reference = 2
    world_deformed = 3


class NormalType(IntEnum):
    none = 0
    exact = 1
    averaged = 2


class HullMode(IntEnum):
    on_no_fallback = 1
    on_convex_fallback = 2


class NewtonSeedMode(IntEnum):
    centroid = 0
    hull = 1


class NewtonSeedReuse(IntEnum):
    off = 0
    last_converged = 1


class MultirootSolverMode(IntEnum):
    fast = 0
    robust = 1


class EdgeFunMode(IntEnum):
    on_the_fly = 0
    pre_calc = 1


class ValidateInput(IntEnum):
    off = 0
    fast = 1
    full = 2


class CameraCoordSys(IntEnum):
    opengl = 0
    opencv = 1


class PsfType(IntEnum):
    pixel_box = 0
    gaussian = 1
    anisotropic_gaussian = 2


@dataclass(slots=True)
class TextureShader:
    """Configure a monochrome or RGB texture shader."""

    uvs: np.ndarray
    texture: np.ndarray
    sample: TextureSample = TextureSample.cubic_catmull_rom
    sample_mode: TextureSampleMode = TextureSampleMode.direct
    bits: int = 8
    output_gain: float = 1.0
    output_offset: float = 0.0
    scaling_type: ScaleStrategy = ScaleStrategy.none
    scaling_min: float = 0.0
    scaling_max: float = 0.0


@dataclass(slots=True)
class NodalShader:
    """Configure a scalar or RGB nodal-field shader."""

    field: np.ndarray
    bits: int = 8
    output_gain: float = 1.0
    output_offset: float = 0.0
    scaling_type: ScaleStrategy = ScaleStrategy.auto
    scaling_min: float = 0.0
    scaling_max: float = 0.0
    scale_over: ScaleOver = ScaleOver.over_frames


@dataclass(slots=True)
class FunctionShader:
    """Configure a scalar or RGB procedural function shader."""

    builtin: FuncShaderBuiltin
    coord_mode: FuncCoordMode = FuncCoordMode.parametric
    params: FuncShaderParams = field(default_factory=FuncShaderParams)
    uvs: np.ndarray | None = None
    channels: int = 1
    bits: int = 8
    output_gain: float = 1.0
    output_offset: float = 0.0
    scaling_type: ScaleStrategy = ScaleStrategy.auto
    scaling_min: float = 0.0
    scaling_max: float = 0.0


@dataclass(slots=True)
class FunctionChannel:
    """One independently configured scalar channel of a function source."""

    builtin: FuncShaderBuiltin
    params: FuncShaderParams = field(default_factory=FuncShaderParams)
    output_gain: float = 1.0
    output_offset: float = 0.0
    scaling_type: ScaleStrategy = ScaleStrategy.none
    scaling_min: float = 0.0
    scaling_max: float = 0.0


@dataclass(slots=True)
class FunctionMultiShader:
    """A pipe source with one to eight independently configured channels."""

    channels: tuple[FunctionChannel, ...] | list[FunctionChannel]
    coord_mode: FuncCoordMode = FuncCoordMode.parametric
    uvs: np.ndarray | None = None


class SlotKind(IntEnum):
    channel = 0
    field = 1
    parameter = 2
    constant = 3


class ResolverKind(IntEnum):
    identity = 0
    sum = 1
    modulate = 2
    weighted_sum = 3
    greybody_bolometric = 4
    greybody_band = 5
    expression = 6
    greybody_band_apparent_c = 7


class OperationKind(IntEnum):
    load = 0
    add = 1
    subtract = 2
    multiply = 3
    divide = 4
    power4 = 5
    clamp01 = 6
    clamp = 7
    lut = 8
    store = 9


@dataclass(frozen=True, slots=True)
class Slot:
    kind: SlotKind
    index: int


@dataclass(frozen=True, slots=True)
class Operation:
    kind: OperationKind
    slot: Slot = Slot(SlotKind.channel, 0)
    lower: float = 0.0
    upper: float = 1.0


@dataclass(slots=True)
class ShaderResolver:
    kind: ResolverKind
    slots: tuple[Slot, ...] = ()
    weights: tuple[float, ...] = ()
    factor: Slot = Slot(SlotKind.parameter, 0)
    temperature: Slot = Slot(SlotKind.field, 0)
    emissivity: Slot = Slot(SlotKind.parameter, 0)
    ambient: float = 0.0
    gain: float = 1.0
    lookup_first: float = 0.0
    lookup_step: float = 1.0
    lookup_values: np.ndarray | None = None
    operations: tuple[Operation, ...] = ()


@dataclass(slots=True)
class ShaderSource:
    shader: TextureShader | NodalShader | FunctionShader | FunctionMultiShader
    destination: Slot


@dataclass(slots=True)
class GreyToEmissivity:
    source: Slot
    destination: Slot
    black: float
    white: float
    grey_black: float = 0.0
    grey_white: float = 1.0


@dataclass(slots=True)
class ClampStage:
    source: Slot
    destination: Slot
    lower: float
    upper: float


@dataclass(slots=True)
class AffineMap:
    source: Slot
    destination: Slot
    gain: float
    offset: float


@dataclass(slots=True)
class LUTMap:
    source: Slot
    destination: Slot
    first: float
    step: float
    values: np.ndarray


@dataclass(slots=True)
class Blend:
    a: Slot
    b: Slot
    destination: Slot
    alpha: float | Slot


@dataclass(slots=True)
class Normalise:
    source: Slot
    destination: Slot
    components: int


@dataclass(slots=True)
class ShaderPipe:
    stages: tuple[
        ShaderSource | GreyToEmissivity | ClampStage | AffineMap | LUTMap |
        Blend | Normalise, ...
    ]
    resolver: ShaderResolver
    channels: int = 0
    constants: tuple[float, ...] = ()


RileyShader = TextureShader | NodalShader | FunctionShader | FunctionMultiShader
Shader = RileyShader


@dataclass(slots=True)
class MeshShaderSet:
    mono: Any | None = None
    rgb: Any | None = None
    ir: Any | None = None
    multifield: Any | None = None
    def __post_init__(self) -> None:
        # Zig's RGB and multifield inputs are always pipes. Normalise the
        # convenient Python source form before it crosses the C boundary.
        for role in ("rgb", "multifield"):
            source = getattr(self, role)
            if source is None or isinstance(source, ShaderPipe):
                continue
            if role == "rgb":
                count = 3
            elif isinstance(source, NodalShader):
                count = 1 if source.field.ndim == 2 else source.field.shape[2]
            elif isinstance(source, TextureShader):
                count = source.texture.shape[0]
            elif isinstance(source, FunctionMultiShader):
                count = len(source.channels)
            else:
                count = source.channels
            slots = tuple(Slot(SlotKind.channel, index) for index in range(count))
            setattr(self, role, ShaderPipe(
                stages=(ShaderSource(source, Slot(SlotKind.channel, 0)),),
                resolver=ShaderResolver(ResolverKind.identity, slots=slots),
            ))


@dataclass(slots=True)
class Mesh:
    """Hold one renderer-ready Riley surface mesh."""

    mesh_type: MeshType
    coords: np.ndarray
    connect: np.ndarray
    disp: np.ndarray | None
    shaders: MeshShaderSet
    normal_type: NormalType = NormalType.exact


class ImageFormat(IntEnum):
    csv = 0
    fimg = 1
    ppm = 2
    bmp = 3
    tiff = 4


class FrameFitMode(IntEnum):
    contain = 0
    cover = 1
    horizontal = 2
    vertical = 3



def _fit_mode_to_int(fit_mode: FrameFitMode | str | int) -> int:
    if isinstance(fit_mode, (FrameFitMode, int)):
        return int(fit_mode)
    if isinstance(fit_mode, str):
        fit_lower = fit_mode.lower()
        if fit_lower in ("contain", "fit_max", "max"):
            return int(FrameFitMode.contain)
        if fit_lower in ("cover", "fit_min", "min"):
            return int(FrameFitMode.cover)
        if fit_lower in ("horizontal", "x", "width"):
            return int(FrameFitMode.horizontal)
        if fit_lower in ("vertical", "y", "height"):
            return int(FrameFitMode.vertical)
        raise ValueError(f"Unknown fit_mode: '{fit_mode}'")
    raise TypeError(f"Invalid fit_mode type: {type(fit_mode)}")


