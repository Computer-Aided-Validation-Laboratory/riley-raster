# Riley scene inputs and configuration. These are ordinary Python objects;
# the Cython layer only adapts their buffers and calls the public C ABI.
from __future__ import annotations

from dataclasses import dataclass, field
from enum import IntEnum
from numbers import Integral
from typing import Any
import numpy as np

from riley import _speckle_defaults


class EPolyMode(IntEnum):
    """Use polynomial values as output coordinates or add them to the input."""

    coordinate = 0
    displacement = 1


@dataclass(slots=True)
class PolyMap:
    """Map normalized sensor coordinates through a forward polynomial.

    Parameters
    ----------
    degree : int
        Total degree, from 1 through 7.
    mode : EPolyMode
        Interpret the polynomial as coordinates or displacements.
    coeffs : numpy.ndarray
        Finite real coefficients of shape ``((degree + 1) * (degree + 2) // 2, 2)``.
        Columns are the x and y components. Rows follow increasing total
        degree, then decreasing x exponent: ``1, x, y, x**2, x*y, y**2, ...``.
        The bindings copy them to contiguous float64 for each native call.
    """

    degree: int
    mode: EPolyMode
    coeffs: np.ndarray


class RenderFormat(IntEnum):
    """Select the camera's shader role and output channel layout.

    ``mono`` and ``ir`` have one channel, ``rgb`` has three, and ``multifield``
    uses the :class:`Camera`'s ``render_channels``.
    """

    mono = 0
    rgb = 1
    ir = 2
    multifield = 3


class CodePacking(IntEnum):
    """Spread ADC codes across the file range or align them to the low or high bits."""

    spread = 0
    lower = 1
    upper = 2


@dataclass(slots=True)
class ImageSaveOpts:
    """Configure one camera output file format without changing the in-memory image.

    Parameters
    ----------
    format : ImageFormat
        Output file format. Render input validation rejects TIFF for
        ``RenderFormat.rgb`` cameras, even with ``SaveStrategy.memory``.
    file_bits : int or None
        Use 8 or 16 for BMP, PPM, TIFF, or integer CSV. Floating-point CSV
        and FIMG use ``None`` and require ``adc_bits=None`` and
        ``packing=CodePacking.spread``.
    adc_bits : int or None
        Integer quantisation depth, from 1 through ``file_bits``. ``None``
        uses ``file_bits`` for integer output.
    scaling : ScaleStrategy
        Mapping applied before writing, except for FIMG, which writes the
        raw rendered floating-point samples regardless of this setting.
        For floating-point CSV, ``none`` writes the rendered values as-is;
        ``auto`` and ``fixed`` map the input bounds to 0 and 1, and ``frac``
        maps the observed bounds to ``scaling_min`` and ``scaling_max``.
        Floating-point CSV does not clip or quantise the mapped values, so
        values outside the ``fixed`` input bounds can fall outside [0, 1].
    scaling_min, scaling_max : float
        Input bounds for ``fixed`` or fractions of the output range for
        ``frac``. File scaling uses observed bounds per frame and channel
        for ``auto`` and ``frac``. When the input bounds coincide, scaling
        uses a span of 1 instead of dividing by zero.
    packing : CodePacking
        How the quantised ADC code fills an integer file sample.
    """

    format: int = 3
    file_bits: int | None = 8
    adc_bits: int | None = None
    scaling: int = 0
    scaling_min: float = 0.0
    scaling_max: float = 1.0
    packing: CodePacking = CodePacking.spread


@dataclass(slots=True)
class Camera:
    """Set the camera pose, sensor, lens and render outputs.

    Use consistent length units for pixel pitch, focal length and world coordinates.

    Parameters
    ----------
    pixels_num : tuple of int
        Sensor dimensions in pixels, ``(width, height)``.
    pixels_size : tuple of float
        Pixel pitch along ``(x, y)``.
    pos_world : tuple of float
        Camera centre ``(x, y, z)`` in world coordinates, regardless of ``coord_sys``.
    rot_world : tuple of float
        OpenGL-style camera-to-world rotation as intrinsic Euler angles
        ``(alpha_z, beta_y, gamma_x)`` in radians, regardless of ``coord_sys``.
    roi_cent_world : tuple of float
        World-space ROI centre ``(x, y, z)`` used to set the imaging distance.
    focal_length : float
        Lens focal length, in the same units as pixel pitch.
    sub_sample : int
        Positive number of samples per pixel axis. Render input validation
        rejects zero.
    coord_sys : CameraCoordSys, optional
        Pose convention for camera CSV files. It does not change how rendering
        interprets the in-memory pose.
    distort_model : int
        No distortion (0), Brown–Conrady (1), extended Brown–Conrady (2),
        polynomial (3), or either Brown–Conrady model followed by a polynomial
        (4 and 5, respectively).
    distort_poly : PolyMap or None
        Forward map required by distortion models 3–5.
    psf_sigma_x : float, optional
        Gaussian width along x in pixels; also the width for an isotropic Gaussian.
    psf_sigma_y : float, optional
        Gaussian width along y in pixels for an anisotropic kernel.
    psf_theta : float
        Anisotropic Gaussian kernel angle in radians.
    psf_support_rad : float
        Gaussian support radius in pixels.
    render_channels : int
        Channel count for ``multifield``. Other formats fix the count.
    output_files : sequence of ImageSaveOpts or None
        Disk output formats. An omitted or empty sequence defaults to 8-bit BMP
        with no scaling.
    """

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
    """Supply coordinate transforms and parameters for procedural shaders.

    Each :class:`FuncShaderBuiltin` uses a subset of these fields.

    Parameters
    ----------
    coord_scale, coord_offset : tuple of float
        Shape ``(2,)`` in input coordinate order. The componentwise transform
        ``scale * coord + offset`` produces ``(u, v)``.
    constant_value_rgb, sinusoidal_bias_rgb, sinusoidal_amplitudes_rgb : tuple of float
        Shape ``(3,)`` in red, green, blue order.
    linear_coeffs : tuple of float
        Shape ``(3,)`` for terms ``(1, u, v)``.
    quadratic_coeffs : tuple of float
        Shape ``(6,)`` for terms ``(1, u, v, u**2, u*v, v**2)``.
    linear_coeffs_rgb, quadratic_coeffs_rgb : tuple of tuple of float
        Shapes ``(3, 3)`` and ``(3, 6)``, respectively. Rows are red, green,
        blue; columns follow the corresponding scalar coefficient order.
    wave_num_scalar, sinusoidal_amplitudes : tuple of float
        Shape ``(2,)`` for the sine term in ``u`` and the cosine term in ``v``.
    wave_num_rgb : tuple of float
        Shape ``(3,)`` in red, green, blue order, for terms in ``u``, ``v``
        and ``u + v``, respectively.
    checker_levels : tuple of float
        Shape ``(2,)`` for even and odd cells of the scalar checker, respectively.
    lambertian_coeffs : tuple of float
        Shape ``(2,)``: ``(bias, normal_z_weight)``.
    lambertian_coeffs_rgb : tuple of tuple of float
        Shape ``(3, 2)``: red, green, blue rows and the same columns as
        ``lambertian_coeffs``.
    eggbox_pitch, eggbox_phase : tuple of float
        Shape ``(2,)`` in ``(u, v)`` order, in transformed coordinate units.
    """

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
    """Finish all cameras per frame in order, or allow jobs across frames."""

    in_order = 0
    offline = 1


@dataclass(slots=True)
class RasterConfig:
    """Control render scheduling, output, validation and raster tuning.

    Parameters
    ----------
    parallel : int or None
        ``None`` lets Zig plan threading, 1 selects serial rendering, and 2
        through 65535 set an explicit thread budget. The budget includes group
        caller threads but not disk-save workers.
    save_strategy : SaveStrategy
        Select disk output, in-memory output, both or neither.
    buffer_mode : BufferMode
        Choose how subpixel render data is stored.
    output_name_format : str
        File name template supporting ``{camera}``, ``{frame}`` and ``{field}``.

    Notes
    -----
    Tile, stripe, and halo overrides are in pixels; 0 lets the renderer choose.
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
    """Select triangle or quadrilateral connectivity, including optimised ``tri3opt``."""

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
    speckle = 8


class TextureStorage(IntEnum):
    u8 = 0
    u16 = 1
    floating = 2


class SaveStrategy(IntEnum):
    """Save images to disk, return them in memory, do both, or do neither."""

    disk = 0
    memory = 1
    both = 2
    none = 3


class ReportMode(IntEnum):
    """Disable performance reporting or enable benchmark timings."""

    off = 0
    bench = 1


class BufferMode(IntEnum):
    """Store subpixel render data per tile, for the full image, or by stripe."""

    tile_local = 0
    global_subpx_full = 1
    global_subpx_stripe = 2


class SubPixelCenterMap(IntEnum):
    """Precompute ideal subpixel centres for the image or generate them per tile."""

    full_in_mem = 0
    per_tile = 1


class TextureSample(IntEnum):
    """Select the interpolation kernel used to sample textures."""

    nearest = 0
    linear = 1
    cubic_catmull_rom = 2
    cubic_mitchell_netravali = 3
    lanczos3 = 4
    cubic_bspline = 5
    quintic_bspline = 6
    lanczos2 = 7


class TextureSampleMode(IntEnum):
    """Evaluate texture weights directly, via lookup, or via interpolated lookup."""

    direct = 0
    lut = 1
    lut_lerp = 2


class ScaleStrategy(IntEnum):
    """Select an intensity mapping, independently of rounding or clipping.

    ``none`` leaves values unchanged by the scaling step. ``auto`` maps
    the source bounds to the full output range. ``fixed`` uses explicit
    input bounds where supported, and ``frac`` maps the source bounds to
    an interval expressed as fractions of full scale. Source bounds may
    be observed or nominal, depending on where the mapping is applied.
    """

    none = 0
    auto = 1
    fixed = 2
    frac = 3


class ScaleOver(IntEnum):
    """Compute nodal ``auto`` or ``frac`` bounds per frame or across all frames."""

    within_frames = 0
    over_frames = 1


class FuncShaderBuiltin(IntEnum):
    """Select a built-in procedural function for a shader or shader channel."""

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
    """Use mesh UVs, element-local coordinates, or world x and y before or after deformation."""

    uv = 0
    parametric = 1
    world_reference = 2
    world_deformed = 3


class NormalType(IntEnum):
    """Disable surface normals or use exact or averaged nodal normals."""

    none = 0
    exact = 1
    averaged = 2


class HullMode(IntEnum):
    """Choose whether adaptive hull construction may fall back to a convex hull."""

    on_no_fallback = 1
    on_convex_fallback = 2


class NewtonSeedMode(IntEnum):
    """Choose a centroid or a hull-derived starting point for one-root Newton solves."""

    centroid = 0
    hull = 1


class NewtonSeedReuse(IntEnum):
    """Allow one-root Newton solves to reuse the last converged solution as a seed."""

    off = 0
    last_converged = 1


class MultirootSolverMode(IntEnum):
    """Use child-patch centres alone or also try bounded fallback seeds."""

    fast = 0
    robust = 1


class EdgeFunMode(IntEnum):
    """Evaluate hull edge functions on demand or precompute their coefficients."""

    on_the_fly = 0
    pre_calc = 1


class ValidateInput(IntEnum):
    """Skip validation, run standard checks, or also check mesh array contents."""

    off = 0
    fast = 1
    full = 2


class CameraCoordSys(IntEnum):
    """Select the camera CSV pose convention without changing the render pose.

    ``opengl`` stores the camera centre and camera-to-world rotation (+y up,
    −z forward). ``opencv`` stores world-to-camera extrinsics (+y down,
    +z forward). Loading an OpenCV CSV converts its pose to the OpenGL-style
    in-memory pose while retaining the ``opencv`` tag; saving converts back.
    """

    opengl = 0
    opencv = 1


class PsfType(IntEnum):
    """Select a pixel box, isotropic Gaussian, or anisotropic Gaussian filter."""

    pixel_box = 0
    gaussian = 1
    anisotropic_gaussian = 2


@dataclass(slots=True)
class TextureShader:
    """Sample an image texture at interpolated nodal UVs.

    Parameters
    ----------
    uvs : numpy.ndarray
        Floating-point array of shape ``(nodes, 2)`` with ``(u, v)`` columns.
    texture : numpy.ndarray
        Image planes in ``(channels, rows, columns)`` order, with dtype
        ``uint8``, ``uint16``, ``float32``, or ``float64``. Use one plane for
        monochrome or three in RGB order; a pipe source accepts one to eight.
        The ``meshio`` helpers use the same channel-first layout.

    Notes
    -----
    ``auto`` and ``frac`` take their input bounds from the texture, across
    all channels. The shader applies ``output_gain`` and ``output_offset``
    after scaling, with no integer quantisation. If scaling is enabled and
    ``output_gain`` is 1, the Python binding uses ``2**bits - 1`` as the gain.
    """

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
    """Interpolate time-dependent nodal values across the mesh.

    Parameters
    ----------
    field : numpy.ndarray
        Floating-point values in ``(frames, nodes, fields)`` order for a
        renderer-ready :class:`Mesh`. The last axis indexes the one to eight
        scalar fields and is required even for one field. The ``meshio`` mesh
        helpers instead take ``(nodes, frames)`` for one field or
        ``(nodes, frames, fields)`` and convert to frame-first order.
    scale_over : ScaleOver, optional
        Compute ``auto`` or ``frac`` bounds across all fields separately
        per frame or across all frames.

    Notes
    -----
    The shader applies ``output_gain`` and ``output_offset`` after scaling,
    with no integer quantisation. If scaling is enabled and ``output_gain``
    is 1, the Python binding uses ``2**bits - 1`` as the gain.
    """

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
    """Evaluate one built-in function on the mesh.

    Parameters
    ----------
    builtin : FuncShaderBuiltin
        Function to evaluate.
    coord_mode : FuncCoordMode, optional
        Coordinate system in which the function is evaluated.
    uvs : numpy.ndarray or None, optional
        Floating-point array of shape ``(nodes, 2)`` with ``(u, v)`` columns,
        required in UV mode.
    channels : int, optional
        Use 1 for scalar output or 3 for RGB.

    Notes
    -----
    Scaling uses the nominal input range [0, 1], not observed function
    values. Only ``frac`` changes the mapping before gain and offset;
    ``fixed`` does not use the supplied bounds for function sources. If
    scaling is enabled and ``output_gain`` is 1, the Python binding uses
    ``2**bits - 1`` as the gain. Output remains floating-point.
    """

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
    """Configure one scalar channel of a :class:`FunctionMultiShader`.

    As with :class:`FunctionShader`, scaling uses the nominal input range
    [0, 1]. The channel applies its own ``output_gain`` and ``output_offset``
    after scaling, with no bit-depth multiplier or integer quantisation.
    """

    builtin: FuncShaderBuiltin
    params: FuncShaderParams = field(default_factory=FuncShaderParams)
    output_gain: float = 1.0
    output_offset: float = 0.0
    scaling_type: ScaleStrategy = ScaleStrategy.none
    scaling_min: float = 0.0
    scaling_max: float = 0.0


@dataclass(slots=True)
class FunctionMultiShader:
    """Evaluate independently configured functions in a shared coordinate system.

    This shader is a :class:`ShaderPipe` source, not a direct mono or IR
    shader. :class:`MeshShaderSet` automatically wraps a compatible source
    assigned to ``rgb`` or ``multifield``; for ``mono`` or ``ir``, put it in
    a :class:`ShaderSource` stage and resolve a single output channel.

    Parameters
    ----------
    channels : tuple or list of FunctionChannel
        One to eight channel configurations in source output order.
    uvs : numpy.ndarray or None, optional
        Shared floating-point array of shape ``(nodes, 2)`` with ``(u, v)``
        columns, required when ``coord_mode`` selects UV coordinates.
    """

    channels: tuple[FunctionChannel, ...] | list[FunctionChannel]
    coord_mode: FuncCoordMode = FuncCoordMode.parametric
    uvs: np.ndarray | None = None


@dataclass(slots=True, kw_only=True)
class _Speckle2DParams:
    seed: int = _speckle_defaults.RILEY_SPECKLE_DEFAULT_SEED
    foreground: float = 0.0
    background: float = 1.0


@dataclass(slots=True, kw_only=True)
class _Dot2DParams(_Speckle2DParams):
    coverage: float
    radius: float
    occupancy: float = 1.0
    jitter: float = 0.0


@dataclass(slots=True, kw_only=True)
class Disk2DParams(_Dot2DParams):
    """Disk speckles with a specified expected coverage and spot radius.

    ``radius``, ``jitter``, and ``edge_softness`` are in reference-mesh units.
    Zero ``edge_softness`` gives a hard edge.
    """

    edge_softness: float = 0.0


@dataclass(slots=True, kw_only=True)
class Gaussian2DParams(_Dot2DParams):
    """Gaussian spots with a specified expected coverage and support radius.

    ``coverage`` describes nominal spot support area, not mean opacity.
    ``radius`` and ``jitter`` are in reference-mesh units.
    """

    pass


@dataclass(slots=True, kw_only=True)
class Perlin2DParams(_Speckle2DParams):
    """Thresholded Perlin noise with ``cell_size`` in reference-mesh units.

    ``threshold`` and ``transition_width`` are in noise units. A transition
    width of zero gives a hard threshold.
    """

    cell_size: float
    threshold: float = 0.0
    transition_width: float = _speckle_defaults.RILEY_PERLIN_DEFAULT_TRANSITION_WIDTH


@dataclass(slots=True)
class SpeckleShader:
    """Generate a monochrome speckle pattern from nodal UVs.

    Parameters
    ----------
    uvs : numpy.ndarray
        Floating-point array of shape ``(nodes, 2)`` with ``(u, v)`` columns.
        The interpolated map must stay within the unit square, up to
        numerical tolerance.
    params : Disk2DParams, Gaussian2DParams, or Perlin2DParams
        Pattern configuration. Sizes are in reference-mesh units, so the
        pattern follows the deforming surface.
    bits : int or None, optional
        For scaling modes other than ``none``, multiply the scaled value by
        ``2**bits - 1``. ``None`` omits the multiplier. Samples remain
        floating-point, with no clipping or quantisation at this stage.

    Notes
    -----
    The shader applies ``sample * output_gain + output_offset`` before
    scaling. ``auto`` and ``frac`` use nominal input bounds [0, 1];
    ``fixed`` uses ``scaling_min`` and ``scaling_max`` after gain and offset.
    Shader scaling is independent of file scaling in :class:`ImageSaveOpts`.
    """

    uvs: np.ndarray
    params: Disk2DParams | Gaussian2DParams | Perlin2DParams
    bits: int | None = 8
    output_gain: float = 1.0
    output_offset: float = 0.0
    scaling_type: ScaleStrategy = ScaleStrategy.none
    scaling_min: float = 0.0
    scaling_max: float = 0.0


#: Union of the supported Python shader source types.
RileyShader = TextureShader | NodalShader | FunctionShader | FunctionMultiShader | SpeckleShader
#: Alias for :data:`RileyShader`.
Shader = RileyShader


class RegisterKind(IntEnum):
    """Register banks for shader pipe values and read-only constants."""

    channel = 0
    field = 1
    parameter = 2
    constant = 3


class ResolverKind(IntEnum):
    """Select how pipe registers become output channels.

    Options include passthrough, sums, modulation, greybody calculations,
    and a stack-based expression.
    """

    identity = 0
    sum = 1
    modulate = 2
    weighted_sum = 3
    greybody_bolometric = 4
    greybody_band = 5
    expression = 6
    greybody_band_apparent_c = 7


class ResolverOpKind(IntEnum):
    """Instruction codes for stack-based shader resolver expressions."""

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
class Register:
    """An immutable address: a register bank and its zero-based index."""

    kind: RegisterKind
    index: int


@dataclass(frozen=True, slots=True)
class ResolverOp:
    """One instruction in a shader resolver expression.

    ``load`` pushes the value of ``register_ref``. ``store`` pops the sole
    stack value into the output channel at ``register_ref.index``; it does
    not write a pipe register. ``lut`` uses the resolver's lookup table at
    index zero. ``clamp`` uses ``lower`` and ``upper`` as bounds.
    """

    kind: ResolverOpKind
    register_ref: Register = Register(RegisterKind.channel, 0)
    lower: float = 0.0
    upper: float = 1.0


@dataclass(slots=True)
class ShaderResolver:
    """Convert values produced by a shader pipe into image channels.

    Parameters
    ----------
    registers : tuple of Register, optional
        Channel registers in output order for ``identity`` and ``modulate``.
        For ``sum`` and ``weighted_sum``, repeat that order once per term:
        with two outputs, successive registers feed outputs 0, 1, 0, 1, etc.
    weights : tuple of float, optional
        For ``weighted_sum``, one weight per entry in ``registers``, in the
        same order.
    factor : Register, optional
        Parameter register for ``modulate``, which computes
        ``(value * factor + ambient) * gain``.
    temperature, emissivity : Register, optional
        Field register for temperature (kelvin) and parameter register for
        emissivity. Greybody modes produce one output channel.
    ambient : float, optional
        Additive term for ``modulate``. For ``greybody_band_apparent_c``,
        ambient temperature in kelvin determines reflected radiation; the
        output is apparent temperature in Celsius.
    lookup_values : array_like or None, optional
        One-dimensional table of at least two values. Entry ``i`` samples
        ``lookup_first + i * lookup_step``, with positive ``lookup_step``.
        Required for greybody band modes (radiance on a kelvin grid) and
        expression ``lut`` operations. Apparent-temperature mode requires
        strictly increasing radiance and an ambient temperature within the
        table's temperature range.
    operations : tuple of ResolverOp, optional
        Instructions in execution order for ``expression``. Store each
        output exactly once.
    """

    kind: ResolverKind
    registers: tuple[Register, ...] = ()
    weights: tuple[float, ...] = ()
    factor: Register = Register(RegisterKind.parameter, 0)
    temperature: Register = Register(RegisterKind.field, 0)
    emissivity: Register = Register(RegisterKind.parameter, 0)
    ambient: float = 0.0
    gain: float = 1.0
    lookup_first: float = 0.0
    lookup_step: float = 1.0
    lookup_values: np.ndarray | None = None
    operations: tuple[ResolverOp, ...] = ()


@dataclass(slots=True)
class ShaderSource:
    """Evaluate a shader and write its outputs starting at ``register_dest``.

    Multiple outputs occupy consecutive indices in the same register bank.
    """

    shader: RileyShader
    register_dest: Register


@dataclass(slots=True)
class GreyToEmissivity:
    """Map a grey channel register to an emissivity parameter register.

    Interpolate linearly between the black and white endpoints, clamping
    grey values outside that interval to the endpoint emissivities.
    """

    register_source: Register
    register_dest: Register
    emissivity_at_black: float
    emissivity_at_white: float
    greylevel_at_black: float = 0.0
    greylevel_at_white: float = 1.0


@dataclass(slots=True)
class ClampStage:
    """Clamp a source register to ``[lower, upper]`` and write the result."""

    register_source: Register
    register_dest: Register
    lower: float
    upper: float


@dataclass(slots=True)
class AffineMap:
    """Write ``source * gain + offset`` to the destination register."""

    register_source: Register
    register_dest: Register
    gain: float
    offset: float


@dataclass(slots=True)
class LUTMap:
    """Map a source register through a uniformly spaced lookup table.

    Parameters
    ----------
    values : array_like
        One-dimensional table of at least two values. Entry ``i`` samples
        ``first + i * step``, with positive ``step``. Sampling is linear
        between entries and clamps to the endpoints outside the table.
    """

    register_source: Register
    register_dest: Register
    first: float
    step: float
    values: np.ndarray


@dataclass(slots=True)
class Blend:
    """Write ``(1 - alpha) * a + alpha * b`` using two source registers.

    ``alpha`` is a scalar or a register value and is not clamped.
    """

    a: Register
    b: Register
    register_dest: Register
    alpha: float | Register


@dataclass(slots=True)
class Normalise:
    """Normalise a two- or three-component vector to unit length.

    Read and write consecutive registers starting at the respective source
    and destination addresses. A zero vector remains zero.
    """

    register_source: Register
    register_dest: Register
    components: int


@dataclass(slots=True)
class ShaderPipe:
    """Run one to eight ordered shading stages, then resolve image channels.

    Parameters
    ----------
    stages : tuple
        Shader stages in execution order. Each stage can read only registers
        written by earlier stages, and each destination register may be
        written only once.
    resolver : ShaderResolver
        Maps stage registers to image channels.
    constants : tuple of float, optional
        Values indexed by constant registers in resolver expressions.
    """

    stages: tuple[
        ShaderSource | GreyToEmissivity | ClampStage | AffineMap | LUTMap |
        Blend | Normalise, ...
    ]
    resolver: ShaderResolver
    constants: tuple[float, ...] = ()


@dataclass(slots=True)
class MeshShaderSet:
    """Assign shaders or shader pipes to a mesh by camera render format.

    ``mono`` and ``ir`` accept a supported direct single-channel shader or
    a pipe that resolves to one channel. :class:`FunctionMultiShader` is
    pipe-only, even with one channel. Compatible sources assigned directly
    to ``rgb`` (three channels) or ``multifield`` are wrapped in identity
    pipes by Python. Use an explicit pipe to select or combine channels.
    Leave unused formats as ``None``.
    """

    mono: Any | None = None
    rgb: Any | None = None
    ir: Any | None = None
    multifield: Any | None = None

    def __post_init__(self) -> None:
        self._normalise_sources()

    def _normalise_sources(self) -> None:
        # Zig's RGB and multifield inputs are always pipes. Normalise the
        # convenient Python source form before it crosses the C boundary.
        for role in ("rgb", "multifield"):
            source = getattr(self, role)
            if source is None or isinstance(source, ShaderPipe):
                continue
            if isinstance(source, SpeckleShader):
                if role == "rgb":
                    raise ValueError(
                        "SpeckleShader produces one channel; use an explicit ShaderPipe for RGB."
                    )
                count = 1
            elif role == "rgb":
                count = 3
            elif isinstance(source, NodalShader):
                count = 1 if source.field.ndim == 2 else source.field.shape[2]
            elif isinstance(source, TextureShader):
                count = source.texture.shape[0]
            elif isinstance(source, FunctionMultiShader):
                count = len(source.channels)
            else:
                count = source.channels
            registers = tuple(Register(RegisterKind.channel, index) for index in range(count))
            setattr(self, role, ShaderPipe(
                stages=(ShaderSource(source, Register(RegisterKind.channel, 0)),),
                resolver=ShaderResolver(ResolverKind.identity, registers=registers),
            ))


@dataclass(slots=True)
class Mesh:
    """A renderer-ready surface mesh in Riley's element node order.

    Parameters
    ----------
    coords : numpy.ndarray
        Reference positions of shape ``(nodes, 3)`` with ``(x, y, z)`` columns.
    connect : numpy.ndarray
        Integer array of shape ``(elements, nodes_per_element)``. Each row
        contains zero-based row indices into ``coords`` in the local node
        order for ``mesh_type``.
    disp : numpy.ndarray or None
        Displacements in ``(frames, nodes, 3)`` order, with ``(dx, dy, dz)``
        on the last axis. Use ``None`` for no displacement. The ``meshio``
        mesh helpers instead take a tuple ``(disp_x, disp_y, disp_z)`` of
        floating-point arrays, each shaped ``(nodes,)`` for one frame or
        ``(nodes, frames)`` for multiple frames.
    shaders : MeshShaderSet
        All nodal data must follow the row order of ``coords``. The ``meshio``
        helpers ``create_mesh`` and ``create_mesh_from_conversion`` instead
        take nodal data (including UVs and displacement components) in source
        node order and remap it; ``create_mesh_from_prepared`` takes it in
        converted node order.
    """

    mesh_type: MeshType
    coords: np.ndarray
    connect: np.ndarray
    disp: np.ndarray | None
    shaders: MeshShaderSet
    normal_type: NormalType = NormalType.exact


class ImageFormat(IntEnum):
    """Output file formats selectable through ``ImageSaveOpts``."""

    csv = 0
    fimg = 1
    ppm = 2
    bmp = 3
    tiff = 4


class FrameFitMode(IntEnum):
    """Select which image dimension controls the camera framing distance.

    ``contain`` fits the bounds on both axes, while ``cover`` fits the less
    restrictive axis and may crop the other. ``horizontal`` and ``vertical``
    fit only the named axis.
    """

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


