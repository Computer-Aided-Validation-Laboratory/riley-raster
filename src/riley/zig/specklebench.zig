// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: James Panayis
// --------------------------------------------------------------------------------------
//! Isolated native catalog-evaluator workload. No production render defaults change.
//! Geometry, nodal UVs, hulls, tile overlaps and worker storage are prepared once.
//! Timed evaluation retains traversal, backface/coverage tests, Newton solves,
//! UV interpolation and normal depth rejection/updates. Tile depth is reset inside
//! every frame's evaluation. There are no sampled UV, colour or resolved-image buffers.
const std = @import("std");
const build = @import("buildconfig.zig");
const F = build.F;
const S = build.SimdWidth;
const VecSF = build.VecSF;
const VecSB = build.VecSB;
const VecBits = @Vector(S, std.meta.Int(.unsigned, @bitSizeOf(F)));
const VecSum = @Vector(S, u64);
const camera = @import("camera.zig");
const meshio = @import("meshio.zig");
const ndarray = @import("ndarray.zig");
const frontend = @import("rasterfrontend.zig");
const elemtilebin = @import("elemtilebinning.zig");
const meshpipe = @import("meshpipeline.zig");
const HullAdaptive = @import("hulladaptive.zig").HullAdaptive;
const HullMultiRoot = @import("hullmultiroot.zig").HullMultiRoot;
const geom = @import("geometrykernels.zig");
const shaderops = @import("shaderops.zig");
const speckle = @import("speckleops.zig");
const policy = @import("scalingpolicy.zig");
const pce = @import("parachunkexec.zig");
const report = @import("report.zig");
const config = @import("rasterconfig.zig");
const simd = @import("rasterengine_simd.zig");
const backend = if (build.config.simd == .on) simd else @import("rasterengine_scalar.zig");
const GK = geom.Tri6Kernel();
const N = GK.nodes_num;
const NH = geom.MeshType.tri6.getNumHullPoints();

pub const workload_mode = "static-geometry-depth-accumulator-v2";

pub const Result = struct {
    checksum: u64 = 0,
    shaded_samples: u64 = 0,
    backface_rejections: u64 = 0,

    pub fn merge(self: *Result, other: Result) void {
        self.checksum +%= other.checksum;
        self.shaded_samples += other.shaded_samples;
        self.backface_rejections += other.backface_rejections;
    }
};

/// Wrapping integer sums of evaluated IEEE bits are independent of worker/tile
/// scheduling and floating-point reduction order. Keep lanes separate until the
/// final reduction, avoiding a serial reduction or atomic operation per sample.
pub const Accumulator = struct {
    rows_num: usize = 1,
    sums: VecSum = @splat(0),
    counts: VecSum = @splat(0),

    pub inline fn consumeScal(self: *Accumulator, value: F) void {
        self.sums[0] +%= @as(std.meta.Int(.unsigned, @bitSizeOf(F)), @bitCast(value));
        self.counts[0] += 1;
    }

    pub inline fn consumeSIMD(self: *Accumulator, values: VecSF, active: VecSB) void {
        const bits: VecBits = @bitCast(values);
        const wide: VecSum = bits;
        self.sums +%= @select(u64, active, wide, @as(VecSum, @splat(0)));
        self.counts += @select(u64, active, @as(VecSum, @splat(1)), @as(VecSum, @splat(0)));
    }

    pub fn result(self: Accumulator) Result {
        var out: Result = .{};
        const sums: [S]u64 = self.sums;
        const counts: [S]u64 = self.counts;
        for (sums, counts) |sum, count| {
            out.checksum +%= sum;
            out.shaded_samples += count;
        }
        return out;
    }
};

/// RasterEngine only needs row metadata and a shade target. The target here
/// is an accumulator, not an image. All geometry/depth scratch matches production.
const Scratch = struct {
    pub const exclusive_subpx_target = false;
    stride_subpx: usize,
    inv_z: []align(64) F,
    image: Accumulator = .{},
    simd_chunks: []simd.SubpxSimdChunk,
    multi_root_candidate_indices: []u32,
    multi_root_child_masks: []u8,
    mask: []align(64) bool,
    xi: []align(64) F,
    eta: []align(64) F,
    touched_min_x: []usize,
    touched_max_x: []usize,
    ideal_pix_cent: []align(64) F,

    pub inline fn resolveImageIdx(_: *const Scratch, _: usize, _: usize, local_idx: usize) usize {
        return local_idx;
    }

    fn init(alloc: std.mem.Allocator, stride: usize) !Scratch {
        const count = std.mem.alignForward(usize, stride * stride, S) + S;
        return .{
            .stride_subpx = stride,
            .inv_z = try alloc.alignedAlloc(F, .@"64", count),
            .simd_chunks = try alloc.alloc(simd.SubpxSimdChunk, @divFloor(count + S - 1, S)),
            .multi_root_candidate_indices = try alloc.alloc(u32, count),
            .multi_root_child_masks = try alloc.alloc(u8, count),
            .mask = try alloc.alignedAlloc(bool, .@"64", count),
            .xi = try alloc.alignedAlloc(F, .@"64", count),
            .eta = try alloc.alignedAlloc(F, .@"64", count),
            .touched_min_x = try alloc.alloc(usize, stride),
            .touched_max_x = try alloc.alloc(usize, stride),
            .ideal_pix_cent = try alloc.alignedAlloc(F, .@"64", count * 2),
        };
    }

    fn resetDepth(self: *Scratch) void {
        @memset(self.inv_z, -std.math.inf(F));
        @memset(self.touched_min_x, self.stride_subpx);
        @memset(self.touched_max_x, 0);
    }
};

/// The only shader difference is the output sink. UV interpolation uses the
/// same scalar helper and SIMD multiply/add order as the production UV shader.
const texops = @import("textureops.zig");
const TextureShader = shaderops.TexPrepared(u8, 1);

fn SinkKernel(comptime kernel_index: ?usize, comptime filter: texops.TexSampConfig) type {
    const Shader = if (kernel_index != null) shaderops.SpecklePrepared else TextureShader;
    return struct {
        pub inline fn shade(
            comptime coord_space: geom.CoordSpace,
            _: shaderops.ShadeContext,
            interp: shaderops.InterpData(N),
            buf: *const shaderops.LocalShaderBuff(N),
            shader: *const Shader,
            _: anytype,
            sink: *Accumulator,
        ) void {
            if (comptime coord_space != .clip_px_leng) @compileError("Benchmark requires tri6 clip coordinates");
            const u = buf.interpFuncCoord(0, interp.weights);
            const v = buf.interpFuncCoord(1, interp.weights);
            const value = if (kernel_index) |index| speckle.Kernel(index).sampleScal(u, v, shader.params, &shader.resources) else texops.sampScal(1, filter, &shader.tex, u, v)[0];
            sink.consumeScal(value);
        }

        pub inline fn shadeSIMD(
            comptime coord_space: geom.CoordSpace,
            _: shaderops.ShadeContext,
            _: anytype,
            active: VecSB,
            weights: [N]VecSF,
            _: VecSF,
            _: VecSF,
            _: [N]VecSF,
            _: VecSF,
            buf: *const shaderops.LocalShaderBuff(N),
            shader: *const Shader,
            sink: *Accumulator,
        ) void {
            if (comptime coord_space != .clip_px_leng) @compileError("Benchmark requires tri6 clip coordinates");
            var u: VecSF = @splat(0);
            var v: VecSF = @splat(0);
            inline for (0..N) |nn| {
                u += weights[nn] * @as(VecSF, @splat(buf.func_coords[nn]));
                v += weights[nn] * @as(VecSF, @splat(buf.func_coords[N + nn]));
            }
            const values = if (kernel_index) |index| speckle.Kernel(index).sampleSIMD(u, v, active, shader.params, &shader.resources) else texops.sampWide(1, filter, &shader.tex, u, v)[0];
            sink.consumeSIMD(values, active);
        }
    };
}

pub const Geometry = struct {
    coords: ndarray.NDArray(F),
    uvs: ndarray.NDArray(F),
    raster_hulls: ndarray.NDArray(F),
    tiling: elemtilebin.TileElemOverlaps,
    multiroot_hulls: ?meshpipe.MultiRootHulls,
    tile_size: u16,

    /// Fixed pinhole tri6 scenes only. Keep back-facing elements in the static
    /// overlaps so they are actually rejected during timed traversal, not setup.
    /// Allocations borrow the caller's geometry arena; this does not own input data.
    pub fn prepare(
        alloc: std.mem.Allocator,
        io: std.Io,
        cam: *const camera.CameraPrepared,
        coords_world: meshio.Coords,
        connect: meshio.Connect,
        uvs_nodes: ndarray.NDArray(F),
        raster_config: config.RasterConfig,
        requested_workers: u16,
    ) !Geometry {
        if (cam.sub_sample != 1 or cam.prep_psf.halo_px != 0 or cam.distort != .none) return error.UnsupportedBenchmarkCamera;
        if (connect.getNodesPerElem() != N) return error.BenchmarkRequiresTri6;
        var coords_nodes = try meshio.Coords.initAlloc(alloc, coords_world.mat.rows_num);
        @memcpy(coords_nodes.mat.slice, coords_world.mat.slice);
        frontend.nodesToClipPxLengRangeInPlace(cam, &coords_nodes, 0, coords_nodes.mat.rows_num);
        const elems = connect.getElemsNum();
        var coords = try ndarray.NDArray(F).initFlat(alloc, &.{ elems, 3, N });
        const uvs = try @import("meshpipeline.zig").prepUVs(alloc, &uvs_nodes, &connect);
        var raster_hulls = try ndarray.NDArray(F).initFlat(alloc, &.{ elems, 2, NH });
        const bboxes = try alloc.alloc(frontend.ElemBBox, elems);
        const root_classes = try alloc.alloc(frontend.ElemRootClass, elems);
        var has_multiroot = false;
        var on_screen: usize = 0;
        for (0..elems) |ee| {
            const nodes = frontend.gatherElemNodeCoords(N, &coords_nodes, &connect, ee);
            const facing = frontend.classifyElemFacing(.tri6, cam, &coords_nodes, &connect, ee);
            // Backfaces stay in the one-root bin for timed rejection.
            root_classes[ee] = facing orelse .one_root;
            has_multiroot = has_multiroot or facing == .multi_root;
            const points = HullAdaptive.buildPointsFromClip(N, cam, nodes, raster_config.advanced.solver.oneroot.hull_mode);
            for (points.x, points.y, 0..) |x, y, nn| {
                raster_hulls.set(&.{ ee, 0, nn }, x);
                raster_hulls.set(&.{ ee, 1, nn }, y);
            }
            for (0..N) |nn| {
                coords.set(&.{ ee, 0, nn }, nodes.x[nn]);
                coords.set(&.{ ee, 1, nn }, nodes.y[nn]);
                coords.set(&.{ ee, 2, nn }, nodes.z[nn]);
            }
            const multi_points = if (facing == .multi_root)
                HullMultiRoot.buildPointsFromClip(N, cam, nodes)
            else
                null;
            const hull_x = if (multi_points) |*points_multi| points_multi.x[0..points_multi.count] else &points.x;
            const hull_y = if (multi_points) |*points_multi| points_multi.y[0..points_multi.count] else &points.y;
            if (hull_x.len < 3) continue;
            const bbox: frontend.ElemBBox = .{
                .elem_idx = ee,
                .x_min = @min(@as(i32, @intCast(cam.pixels_num[0])), frontend.boundIndMin(i32, std.mem.min(F, hull_x))),
                .x_max = frontend.boundIndMax(i32, std.mem.max(F, hull_x), @intCast(cam.pixels_num[0])),
                .y_min = @min(@as(i32, @intCast(cam.pixels_num[1])), frontend.boundIndMin(i32, std.mem.min(F, hull_y))),
                .y_max = frontend.boundIndMax(i32, std.mem.max(F, hull_y), @intCast(cam.pixels_num[1])),
            };
            if (bbox.x_min < bbox.x_max and bbox.y_min < bbox.y_max) {
                bboxes[on_screen] = bbox;
                on_screen += 1;
            }
        }
        const tile_size = policy.tileSize(raster_config.advanced.raster.tile_size_override, raster_config.advanced.raster.tile_size_min, raster_config.advanced.raster.tile_size_max, cam.pixels_num, 1, 0);
        var exec = pce.ParaChunkExecutor.init(io, requested_workers);
        const tiling = try elemtilebin.binElemsInSceneTileLoc(
            alloc,
            &exec,
            requested_workers,
            tile_size,
            try std.math.divCeil(usize, cam.pixels_num[0], tile_size),
            try std.math.divCeil(usize, cam.pixels_num[1], tile_size),
            @intCast(cam.pixels_num[0]),
            @intCast(cam.pixels_num[1]),
            0,
            &.{on_screen},
            &.{bboxes[0..on_screen]},
            &.{null},
            &.{.tri6},
            &.{root_classes},
        );
        // Parallel binning uses atomic slots, so insertion order is not stable.
        // Fix element order outside the timers: depth updates (and therefore
        // which evaluated values reach the sink) must be reproducible across runs.
        for (tiling.active_tiles) |tile| {
            for (tile.bins) |range| {
                std.mem.sort(elemtilebin.OverlapBBox, tiling.overlaps[range.start .. range.start + range.count], {}, struct {
                    fn less(_: void, a: elemtilebin.OverlapBBox, b: elemtilebin.OverlapBBox) bool {
                        return a.elem_idx < b.elem_idx;
                    }
                }.less);
            }
        }

        // Reuse production multi-root preparation, including robust seed ordering.
        // Keep our unculled coordinates/overlaps so backface work remains timed.
        var multiroot_hulls: ?meshpipe.MultiRootHulls = null;
        if (has_multiroot) {
            const mesh_static: meshpipe.MeshStatic = .{
                .mesh_type = .tri6,
                .coords_orig = coords_world,
                .connect = connect,
                .disp = null,
                .shader = .{ .func = .{ .elem_uvs = null, .builtin = .constant, .bits = null } },
            };
            var times: meshpipe.GeomTimes = .{};
            const frame = try meshpipe.prepMeshFrame(alloc, &exec, requested_workers, cam, raster_config, &mesh_static, 0, null, &times);
            if (frame.hull_multiroot) |prepared| {
                var remapped = prepared;
                const slots = try alloc.alloc(u32, elems);
                @memset(slots, std.math.maxInt(u32));
                for (frame.frame_workspace.vis_orig_elem_inds, 0..) |original_idx, visible_idx| {
                    slots[original_idx] = prepared.slot_by_visible_elem.get(visible_idx);
                }
                remapped.slot_by_visible_elem = @import("vecslice.zig").VecSlice(u32).init(slots);
                multiroot_hulls = remapped;
            }
        }
        return .{ .coords = coords, .uvs = uvs, .raster_hulls = raster_hulls, .multiroot_hulls = multiroot_hulls, .tiling = tiling, .tile_size = tile_size };
    }
};

const Worker = struct {
    scratch: Scratch align(@max(64, @alignOf(Scratch))),
    backface_rejections: u64 = 0,
};

pub const Evaluation = struct {
    cam: *const camera.CameraPrepared,
    geometry: *const Geometry,
    raster_config: config.RasterConfig,
    workers: []Worker,
    exec: pce.ParaChunkExecutor,

    /// Worker allocations and setup are outside both measured intervals.
    pub fn init(alloc: std.mem.Allocator, io: std.Io, cam: *const camera.CameraPrepared, geometry: *const Geometry, raster_config: config.RasterConfig, requested_workers: u16) !Evaluation {
        const workers_num = policy.rasterWorkers(requested_workers, geometry.tiling.active_tiles.len);
        const workers = try alloc.alloc(Worker, workers_num);
        for (workers) |*worker| worker.* = .{ .scratch = try Scratch.init(alloc, geometry.tile_size) };
        return .{ .cam = cam, .geometry = geometry, .raster_config = raster_config, .workers = workers, .exec = pce.ParaChunkExecutor.init(io, @intCast(workers_num)) };
    }

    /// One invocation is one fresh measurement, with all frames inside the timer.
    pub fn evaluate(self: *Evaluation, params: speckle.Speckle2DParams, resources: speckle.Resources, frames: usize) !void {
        const index = resources.kernel_index orelse return error.MissingPreparedSpeckleKernel;
        inline for (speckle.kernel_configs, 0..) |_, ii| {
            if (index == ii) return self.evaluateKernel(ii, .{ .sample = .linear }, shaderops.SpecklePrepared{ .elem_uvs = self.geometry.uvs, .resources = resources, .params = params, .bits = null }, frames);
        }
        return error.UnsupportedBenchmarkEvaluator;
    }

    pub fn evaluateTexture(self: *Evaluation, shader: TextureShader, frames: usize) !void {
        if (shader.samp_cfg.mode != (if (shader.samp_cfg.sample == .cubic_catmull_rom) texops.TexSampMode.lut_lerp else texops.TexSampMode.direct)) return error.UnsupportedBenchmarkTextureMode;
        switch (shader.samp_cfg.sample) {
            .nearest => try self.evaluateKernel(null, .{ .sample = .nearest }, shader, frames),
            .linear => try self.evaluateKernel(null, .{ .sample = .linear }, shader, frames),
            .cubic_catmull_rom => try self.evaluateKernel(null, .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp }, shader, frames),
            else => return error.UnsupportedBenchmarkTextureFilter,
        }
    }

    fn evaluateKernel(self: *Evaluation, comptime index: ?usize, comptime filter: texops.TexSampConfig, shader: anytype, frames: usize) !void {
        for (self.workers) |*worker| {
            worker.scratch.image = .{};
            worker.backface_rejections = 0;
        }
        const Context = struct {
            evaluation: *Evaluation,
            shader: @TypeOf(shader),
            frame_idx: usize,

            fn run(ptr: *anyopaque, worker_idx: usize, start: usize, end: usize) anyerror!void {
                const ctx: *@This() = @ptrCast(@alignCast(ptr));
                const eval = ctx.evaluation;
                const geometry = eval.geometry;
                const worker = &eval.workers[worker_idx];
                var log: report.LogType(.off) = .{};
                const ctx_report: report.ReportContext(.off) = .{ .log = &log };
                const ctx_rast: frontend.RasterContext = .{ .camera = eval.cam, .config = eval.raster_config, .frame_idx = ctx.frame_idx, .tile_size = geometry.tile_size };
                for (start..end) |tile_idx| {
                    const tile = geometry.tiling.active_tiles[tile_idx];
                    // Tile-local ownership is unchanged: reset depth before all
                    // overlaps, never between elements. Repeated for every frame.
                    worker.scratch.resetDepth();
                    try eval.cam.fillTileIdealCentersPerTile(tile.scratch_px.x_min, tile.scratch_px.x_max, tile.scratch_px.y_min, tile.scratch_px.y_max, geometry.tile_size, worker.scratch.ideal_pix_cent);
                    inline for (.{ elemtilebin.ElemBin.tri6_one_root, elemtilebin.ElemBin.tri6_multi_root }) |bin| {
                        const root_class = comptime elemtilebin.binRootClass(bin);
                        const range = tile.bins[@intFromEnum(bin)];
                        const overlaps = geometry.tiling.overlaps[range.start .. range.start + range.count];
                        for (overlaps) |overlap| {
                            const nodes = try frontend.loadElemVec3Slices(N, F, &geometry.coords, overlap.elem_idx);
                            var raster_nodes: frontend.RasterCoords2D(N) = undefined;
                            const offsets = eval.cam.calcRasterOffsets();
                            for (0..N) |nn| {
                                raster_nodes.x[nn] = nodes.x[nn] / nodes.z[nn] + offsets.x_off;
                                raster_nodes.y[nn] = nodes.y[nn] / nodes.z[nn] + offsets.y_off;
                            }
                            if (frontend.isHighOrdBackface(N, raster_nodes)) {
                                worker.backface_rejections += 1;
                                continue;
                            }
                            var buf: shaderops.LocalShaderBuff(N) = .{};
                            buf.loadFuncCoords(geometry.uvs, overlap.elem_idx * 2 * N, 2);
                            const hulls = if (comptime root_class == .multi_root)
                                if (geometry.multiroot_hulls) |*prepared| prepared else return error.MissingMultiRootData
                            else
                                &geometry.raster_hulls;
                            _ = try backend.RasterEngine(Scratch, GK, SinkKernel(index, filter), @TypeOf(ctx.shader), root_class).rasterElemInTile(.off, ctx_rast, ctx_report, tile, overlap, &geometry.coords, hulls, &ctx.shader, &buf, &worker.scratch);
                        }
                    }
                }
            }
        };
        var ctx: Context = .{
            .evaluation = self,
            .shader = shader,
            .frame_idx = 0,
        };
        for (0..frames) |frame_idx| {
            ctx.frame_idx = frame_idx;
            try self.exec.runDynRangeWithWorkerErr(&ctx, Context.run, self.geometry.tiling.active_tiles.len, policy.rasterGrainSize(self.geometry.tiling.active_tiles.len, self.workers.len));
        }
    }

    /// Merge outside the evaluation timer; printing this value makes every
    /// worker's evaluated values observable, with no per-sample atomics or I/O.
    pub fn result(self: *const Evaluation) Result {
        var out: Result = .{};
        for (self.workers) |worker| {
            out.merge(worker.scratch.image.result());
            out.backface_rejections += worker.backface_rejections;
        }
        return out;
    }
};

test "speckle benchmark accumulator masks lanes and reduces deterministically" {
    var sink: Accumulator = .{};
    var active: [S]bool = @splat(false);
    active[0] = true;
    sink.consumeSIMD(@splat(0.5), active);
    var scalar: Accumulator = .{};
    scalar.consumeScal(0.5);
    try std.testing.expectEqualDeep(scalar.result(), sink.result());
    sink.consumeSIMD(@splat(std.math.nan(F)), @splat(false));
    try std.testing.expectEqualDeep(scalar.result(), sink.result());
}

test "speckle benchmark sink UV interpolation matches production grayscale shader" {
    const MatSlice = @import("matslice.zig").MatSlice;
    // Test this benchmark's interpolation/output boundary, not the evaluator accuracy matrix.
    inline for (speckle.kernel_configs, 0..) |cfg, index| {
        if (comptime cfg.pattern == .gaussian and cfg.evaluator == .list_indexed and cfg.neighbor_count == 9) {
            const params: speckle.Speckle2DParams = .{ .pattern = .gaussian, .cells_per_uv = .{ 3.25, 2.75 } };
            var resources = try speckle.generateResources(std.testing.allocator, params);
            defer resources.deinit(std.testing.allocator);
            const shader: shaderops.SpecklePrepared = .{ .elem_uvs = undefined, .resources = resources, .params = params, .bits = null };
            var buf: shaderops.LocalShaderBuff(N) = .{};
            buf.func_coords = .{ 0, 1, 0, 0.5, 0.5, 0, 0, 0, 1, 0, 0.5, 0.5, 0, 0, 0, 0, 0, 0 };
            const weights = [N]F{ 0.1, 0.2, 0.3, 0.1, 0.1, 0.2 };
            const ctx: shaderops.ShadeContext = .{ .frame_idx = 0, .elem_idx = 0, .fields_num = 1, .actual_fields = 1, .scratch_idx = 0, .global_subx = 0, .global_suby = 0 };
            var log: report.LogType(.off) = .{};
            const ctx_report: report.ReportContext(.off) = .{ .log = &log };
            const interp: shaderops.InterpData(N) = .{ .weights = weights, .nodes_inv_z = @splat(1), .sub_pixel_z = 1, .xi = 0.2, .eta = 0.3 };
            var storage: [S]F = @splat(-1);
            var image = MatSlice(F).init(&storage, 1, S);
            var expected: Accumulator = .{};
            var sink: Accumulator = .{};
            @import("shaderkernels_scalar.zig").SpeckleKernel(N, index).shade(.clip_px_leng, ctx, interp, &buf, &shader, ctx_report, &image);
            expected.consumeScal(storage[0]);
            SinkKernel(index, .{ .sample = .linear }).shade(.clip_px_leng, ctx, interp, &buf, &shader, ctx_report, &sink);
            try std.testing.expectEqualDeep(expected.result(), sink.result());
            var v_weights: [N]VecSF = undefined;
            inline for (0..N) |nn| v_weights[nn] = @splat(weights[nn]);
            var active: [S]bool = @splat(true);
            active[S - 1] = false;
            @import("shaderkernels_simd.zig").SpeckleKernel(N, index).shadeSIMD(.clip_px_leng, ctx, ctx_report, active, v_weights, @splat(0.2), @splat(0.3), @splat(@splat(1)), @splat(1), &buf, &shader, &image);
            expected = .{};
            expected.consumeSIMD(storage, active);
            sink = .{};
            SinkKernel(index, .{ .sample = .linear }).shadeSIMD(.clip_px_leng, ctx, ctx_report, active, v_weights, @splat(0.2), @splat(0.3), @splat(@splat(1)), @splat(1), &buf, &shader, &sink);
            try std.testing.expectEqualDeep(expected.result(), sink.result());
        }
    }
}
