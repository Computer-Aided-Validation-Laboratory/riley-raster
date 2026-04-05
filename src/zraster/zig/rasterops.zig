const cfg = @import("buildconfig.zig").config;
const impl = if (cfg.simd == .on)
    @import("rasterops_simd.zig")
else
    @import("rasterops_scalar.zig");
const simd_impl = @import("rasterops_simd.zig");

pub const buildAdaptiveHulls = impl.buildAdaptiveHulls;
pub const ElemBBox = impl.ElemBBox;
pub const OverlapBBox = impl.OverlapBBox;
pub const ActiveTile = impl.ActiveTile;
pub const TilingOverlaps = impl.TilingOverlaps;
pub const OverlapTarget = impl.OverlapTarget;
pub const MeshInput = impl.MeshInput;

pub const edgeFun = impl.edgeFun;
pub const edgeFun3Slices = impl.edgeFun3Slices;
pub const edgeFun3 = impl.edgeFun3;
pub const edgeFun3SIMD = simd_impl.edgeFun3SIMD;
pub const boundIndexMin = impl.boundIndexMin;
pub const boundIndexMax = impl.boundIndexMax;
pub const boundIndMin = impl.boundIndMin;
pub const boundIndMax = impl.boundIndMax;
pub const worldToRasterCoords = impl.worldToRasterCoords;
pub const Vec3OfSlices = impl.Vec3OfSlices;
pub const RasterContext = impl.RasterContext;
pub const loadVec3SlicesFromElemArray = impl.loadVec3SlicesFromElemArray;
pub const worldToRasterSIMD = impl.worldToRasterSIMD;
pub const elemsToRasterSIMD = impl.elemsToRasterSIMD;
pub const elemsToClipPxLengSIMD = impl.elemsToClipPxLengSIMD;
pub const countElemsCalcBBoxes = impl.countElemsCalcBBoxes;
pub const countElemsCalcBBoxesTri3 = impl.countElemsCalcBBoxesTri3;
pub const prepareSceneGeometry = impl.prepareSceneGeometry;
pub const sceneTileElemOverlap = impl.sceneTileElemOverlap;
