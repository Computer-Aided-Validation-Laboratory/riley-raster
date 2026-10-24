// Ordered shader-pipe output slots and prepared, sample-domain resolution.
// Slot and program bounds are checked during preparation, not during rasterisation.
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;

pub const max_slots = 16;
pub const max_operations = 64;
pub const max_stack = 16;
pub const max_channels = buildconfig.config.max_image_channels;

pub const SlotKind = enum { channel, field, parameter, constant };
pub const Slot = struct { kind: SlotKind, index: u8 };

pub const GreyToEmissivityStage = struct {
    source: Slot,
    destination: Slot,
    black: F,
    white: F,
    grey_black: F = 0,
    grey_white: F = 1,
};

pub const ClampStage = struct {
    source: Slot,
    destination: Slot,
    lower: F,
    upper: F,
};

pub const AffineMapStage = struct {
    source: Slot,
    destination: Slot,
    gain: F,
    offset: F,

    pub inline fn apply(self: @This(), outputs: anytype) void {
        const T = @TypeOf(outputs.get(self.source));
        outputs.set(self.destination, outputs.get(self.source) * splat(T, self.gain) +
            splat(T, self.offset));
    }
};

pub const LUTMapStage = struct {
    source: Slot,
    destination: Slot,
    lookup: Lookup,

    pub inline fn apply(self: @This(), outputs: anytype, active: anytype) void {
        const T = @TypeOf(outputs.get(self.source));
        if (T == F) {
            outputs.set(self.destination, self.lookup.sample(outputs.get(self.source)));
        } else {
            const values: [buildconfig.SimdWidth]F = @bitCast(outputs.get(self.source));
            const mask: [buildconfig.SimdWidth]bool = active;
            var result: [buildconfig.SimdWidth]F = undefined;
            for (&result, values, mask) |*dest, value, enabled| {
                dest.* = self.lookup.sample(if (enabled) value else self.lookup.first);
            }
            outputs.set(self.destination, @bitCast(result));
        }
    }
};

pub const BlendAlpha = union(enum) { fixed: F, slot: Slot };

pub const BlendStage = struct {
    a: Slot,
    b: Slot,
    destination: Slot,
    alpha: BlendAlpha,

    pub inline fn apply(self: @This(), outputs: anytype) void {
        const T = @TypeOf(outputs.get(self.a));
        const alpha = switch (self.alpha) {
            .fixed => |value| splat(T, value),
            .slot => |slot| outputs.get(slot),
        };
        const a = outputs.get(self.a);
        const b = outputs.get(self.b);
        outputs.set(self.destination, (splat(T, 1) - alpha) * a + alpha * b);
    }
};

pub const NormaliseStage = struct {
    source: Slot,
    destination: Slot,
    components: u8,

    pub inline fn apply(self: @This(), outputs: anytype) void {
        const T = @TypeOf(outputs.get(self.source));
        var values: [3]T = undefined;
        var squared: T = splat(T, 0);
        for (0..self.components) |i| {
            var slot = self.source;
            slot.index += @intCast(i);
            values[i] = outputs.get(slot);
            squared += values[i] * values[i];
        }
        if (T == F) {
            const inv_norm: F = if (squared == 0) 0 else 1 / @sqrt(squared);
            for (0..self.components) |i| {
                var dest = self.destination;
                dest.index += @intCast(i);
                outputs.set(dest, values[i] * inv_norm);
            }
        } else {
            const positive = squared > splat(T, 0);
            const safe_squared = @select(F, positive, squared, splat(T, 1));
            const inv_norm = @select(F, positive, splat(T, 1) / @sqrt(safe_squared), splat(T, 0));
            for (0..self.components) |i| {
                var dest = self.destination;
                dest.index += @intCast(i);
                outputs.set(dest, values[i] * inv_norm);
            }
        }
    }
};

pub fn Outputs(comptime T: type) type {
    return struct {
        channel: [max_slots]T = undefined,
        field: [max_slots]T = undefined,
        parameter: [max_slots]T = undefined,

        pub inline fn get(self: *const @This(), slot: Slot) T {
            return switch (slot.kind) {
                .channel => self.channel[slot.index],
                .field => self.field[slot.index],
                .parameter => self.parameter[slot.index],
                .constant => unreachable,
            };
        }

        pub inline fn set(self: *@This(), slot: Slot, value: T) void {
            switch (slot.kind) {
                .channel => self.channel[slot.index] = value,
                .field => self.field[slot.index] = value,
                .parameter => self.parameter[slot.index] = value,
                .constant => unreachable,
            }
        }
    };
}

pub const ScalarOutputs = Outputs(F);
pub const VectorOutputs = Outputs(buildconfig.VecSF);

pub const Op = union(enum) {
    load: Slot,
    add,
    subtract,
    multiply,
    divide,
    power4,
    clamp01,
    clamp: struct { lower: F, upper: F },
    lut: u8,
    store: u8,
};

pub const Lookup = struct {
    first: F,
    step: F,
    values: []const F,

    pub fn validate(self: Lookup) !void {
        if (!std.math.isFinite(self.first) or !std.math.isFinite(self.step) or
            self.step <= 0 or self.values.len < 2) return error.InvalidLookup;
        for (self.values) |value| {
            if (!std.math.isFinite(value)) return error.InvalidLookup;
        }
    }

    pub inline fn sample(self: Lookup, value: F) F {
        const max_val = @as(F, @floatFromInt(self.values.len - 1));
        const x = std.math.clamp((value - self.first) / self.step, 0, max_val);
        const i: usize = @intFromFloat(x);
        if (i == self.values.len - 1) return self.values[i];
        const t = x - @as(F, @floatFromInt(i));
        return self.values[i] + t * (self.values[i + 1] - self.values[i]);
    }

    pub fn inverseMonotonic(self: Lookup, value: F) F {
        if (value <= self.values[0]) return self.first;
        const last = self.values.len - 1;
        if (value >= self.values[last]) {
            return self.first + self.step * @as(F, @floatFromInt(last));
        }
        var lo: usize = 0;
        var hi: usize = last;
        while (lo + 1 < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.values[mid] <= value) lo = mid else hi = mid;
        }
        const fraction = (value - self.values[lo]) / (self.values[hi] - self.values[lo]);
        return self.first + self.step * (@as(F, @floatFromInt(lo)) + fraction);
    }
};

/// Integrates blackbody spectral radiance against an absolute, dimensionless
/// camera response. Wavelengths are metres; values are W/(m² sr).
pub const BandResponse = struct {
    wavelengths_m: []const F,
    response: []const F,

    pub fn prepareRadianceLookup(
        self: BandResponse,
        allocator: std.mem.Allocator,
        temp_first_k: F,
        temp_last_k: F,
        temp_step_k: F,
    ) !Lookup {
        if (self.wavelengths_m.len < 2 or self.wavelengths_m.len != self.response.len or
            !std.math.isFinite(temp_first_k) or !std.math.isFinite(temp_last_k) or
            !std.math.isFinite(temp_step_k) or temp_first_k <= 0 or
            temp_last_k <= temp_first_k or temp_step_k <= 0)
            return error.InvalidBandResponse;
        var any_response = false;
        for (self.wavelengths_m, self.response, 0..) |lambda, weight, i| {
            if (!std.math.isFinite(lambda) or !std.math.isFinite(weight) or
                lambda <= 0 or weight < 0 or
                (i > 0 and lambda <= self.wavelengths_m[i - 1]))
                return error.InvalidBandResponse;
            any_response = any_response or weight > 0;
        }
        if (!any_response) return error.InvalidBandResponse;
        const count_f = @ceil((temp_last_k - temp_first_k) / temp_step_k);
        const count: usize = @as(usize, @intFromFloat(count_f)) + 1;
        if (count < 2 or count > 65536) return error.InvalidBandResponse;
        const values = try allocator.alloc(F, count);
        for (values, 0..) |*result, ti| {
            const temp = temp_first_k + @as(F, @floatFromInt(ti)) * temp_step_k;
            var total: F = 0;
            for (1..self.wavelengths_m.len) |wi| {
                const a = self.wavelengths_m[wi - 1];
                const b = self.wavelengths_m[wi];
                total += (b - a) * 0.5 *
                    (self.response[wi - 1] * planckSpectralRadiance(a, temp) +
                        self.response[wi] * planckSpectralRadiance(b, temp));
            }
            result.* = total;
        }
        return .{ .first = temp_first_k, .step = temp_step_k, .values = values };
    }
};

pub fn planckSpectralRadiance(wavelength_m: F, temperature_k: F) F {
    const h: F = 6.62607015e-34;
    const c: F = 299792458.0;
    const k: F = 1.380649e-23;
    const lambda2 = wavelength_m * wavelength_m;
    const lambda5 = lambda2 * lambda2 * wavelength_m;
    const denom = lambda5 * @exp(h * c / (wavelength_m * k * temperature_k)) - lambda5;
    return (2 * h * c * c) / denom;
}

pub const Written = struct {
    channel: u16 = 0,
    field: u16 = 0,
    parameter: u16 = 0,

    pub fn has(self: Written, slot: Slot) bool {
        if (slot.index >= max_slots or slot.kind == .constant) return false;
        const mask: u16 = @as(u16, 1) << @intCast(slot.index);
        return switch (slot.kind) {
            .channel => self.channel & mask != 0,
            .field => self.field & mask != 0,
            .parameter => self.parameter & mask != 0,
            .constant => unreachable,
        };
    }

    pub fn add(self: *Written, slot: Slot) !void {
        if (slot.index >= max_slots or slot.kind == .constant) return error.InvalidSlot;
        if (self.has(slot)) return error.RepeatedWriter;
        const mask: u16 = @as(u16, 1) << @intCast(slot.index);
        switch (slot.kind) {
            .channel => self.channel |= mask,
            .field => self.field |= mask,
            .parameter => self.parameter |= mask,
            .constant => unreachable,
        }
    }
};

pub const Program = struct {
    operations: []const Op,
    constants: []const F = &.{},
    lookups: []const Lookup = &.{},

    pub fn validate(self: Program, written: Written, channels: u8) !void {
        if (channels == 0 or channels > max_channels or self.operations.len == 0 or
            self.operations.len > max_operations or self.constants.len > max_slots)
            return error.InvalidProgram;
        for (self.constants) |value| {
            if (!std.math.isFinite(value)) return error.InvalidConstant;
        }
        for (self.lookups) |lut| try lut.validate();
        var depth: usize = 0;
        var stored: u16 = 0;
        for (self.operations) |op| switch (op) {
            .load => |slot| {
                if (slot.kind == .constant) {
                    if (slot.index >= self.constants.len) return error.InvalidSlot;
                } else if (!written.has(slot)) return error.UnwrittenSlot;
                depth += 1;
                if (depth > max_stack) return error.InvalidProgram;
            },
            .add, .subtract, .multiply, .divide => {
                if (depth < 2) return error.InvalidProgram;
                depth -= 1;
            },
            .power4, .clamp01 => {
                if (depth < 1) return error.InvalidProgram;
            },
            .clamp => |bounds| {
                if (depth < 1 or !std.math.isFinite(bounds.lower) or
                    !std.math.isFinite(bounds.upper) or bounds.lower > bounds.upper)
                    return error.InvalidProgram;
            },
            .lut => |idx| {
                if (depth < 1 or idx >= self.lookups.len) return error.InvalidProgram;
            },
            .store => |idx| {
                if (depth != 1 or idx >= channels) return error.InvalidProgram;
                const bit: u16 = @as(u16, 1) << @intCast(idx);
                if (stored & bit != 0) return error.InvalidProgram;
                stored |= bit;
                depth = 0;
            },
        };
        if (depth != 0 or stored != (@as(u16, 1) << @intCast(channels)) - 1)
            return error.InvalidProgram;
    }

    pub fn evaluate(self: Program, inputs: anytype, channels: u8, out: anytype) void {
        const T = @TypeOf(out.*[0]);
        var stack: [max_stack]T = undefined;
        var depth: usize = 0;
        for (self.operations) |op| switch (op) {
            .load => |slot| {
                stack[depth] = if (slot.kind == .constant)
                    splat(T, self.constants[slot.index])
                else
                    inputs.get(slot);
                depth += 1;
            },
            .add => {
                depth -= 1;
                stack[depth - 1] += stack[depth];
            },
            .subtract => {
                depth -= 1;
                stack[depth - 1] -= stack[depth];
            },
            .multiply => {
                depth -= 1;
                stack[depth - 1] *= stack[depth];
            },
            .divide => {
                depth -= 1;
                stack[depth - 1] /= stack[depth];
            },
            .power4 => {
                const v = stack[depth - 1];
                stack[depth - 1] = (v * v) * (v * v);
            },
            .clamp01 => {
                stack[depth - 1] = @min(splat(T, 1), @max(splat(T, 0), stack[depth - 1]));
            },
            .clamp => |bounds| {
                const lower = splat(T, bounds.lower);
                const upper = splat(T, bounds.upper);
                stack[depth - 1] = @min(upper, @max(lower, stack[depth - 1]));
            },
            .lut => |idx| {
                if (T == F) {
                    stack[depth - 1] = self.lookups[idx].sample(stack[depth - 1]);
                } else {
                    var lanes: [buildconfig.SimdWidth]F = @bitCast(stack[depth - 1]);
                    for (&lanes) |*lane| lane.* = self.lookups[idx].sample(lane.*);
                    stack[depth - 1] = @bitCast(lanes);
                }
            },
            .store => |idx| {
                out.*[idx] = stack[0];
                depth = 0;
            },
        };
        _ = channels;
    }
};

inline fn splat(comptime T: type, value: F) T {
    return if (T == F) value else @splat(value);
}

pub const Resolver = union(enum) {
    identity: []const Slot,
    sum: []const Slot,
    modulate: struct {
        sources: []const Slot,
        factor: Slot,
        ambient: F = 0,
        gain: F = 1,
    },
    weighted_sum: struct {
        sources: []const Slot,
        weights: []const F,
    },
    greybody_bolometric: struct {
        temperature: Slot,
        emissivity: Slot,
    },
    greybody_band: struct {
        temperature: Slot,
        emissivity: Slot,
        radiance: Lookup,
    },
    greybody_band_apparent_c: struct {
        temperature: Slot,
        emissivity: Slot,
        radiance: Lookup,
        ambient_k: F,
    },
    expression: Program,

    pub fn validate(
        self: Resolver,
        written: Written,
        constants: []const F,
        channels: u8,
    ) !void {
        if (channels == 0 or channels > max_channels) {
            return error.InvalidChannels;
        }
        switch (self) {
            .identity => |slots| {
                if (slots.len != channels) return error.InvalidChannels;
                for (slots) |slot| {
                    if (slot.kind != .channel) return error.InvalidResolver;
                    try checkSlot(slot, written, constants.len);
                }
            },
            .sum => |slots| {
                if (slots.len < channels or slots.len % channels != 0) {
                    return error.InvalidChannels;
                }
                for (slots) |slot| {
                    if (slot.kind != .channel) return error.InvalidResolver;
                    try checkSlot(slot, written, constants.len);
                }
            },
            .modulate => |m| {
                if (m.sources.len != channels or !std.math.isFinite(m.ambient) or
                    !std.math.isFinite(m.gain)) return error.InvalidResolver;
                for (m.sources) |slot| {
                    if (slot.kind != .channel) return error.InvalidResolver;
                    try checkSlot(slot, written, constants.len);
                }
                if (m.factor.kind != .parameter) return error.InvalidResolver;
                try checkSlot(m.factor, written, constants.len);
            },
            .weighted_sum => |w| {
                if (w.sources.len < channels or w.sources.len % channels != 0 or
                    w.sources.len != w.weights.len) return error.InvalidResolver;
                for (w.sources) |slot| {
                    if (slot.kind != .channel) return error.InvalidResolver;
                    try checkSlot(slot, written, constants.len);
                }
                for (w.weights) |weight| {
                    if (!std.math.isFinite(weight)) return error.InvalidResolver;
                }
            },
            .greybody_bolometric => |g| {
                if (channels != 1 or g.temperature.kind != .field or
                    g.emissivity.kind != .parameter) return error.InvalidResolver;
                try checkSlot(g.temperature, written, constants.len);
                try checkSlot(g.emissivity, written, constants.len);
            },
            .greybody_band => |g| {
                if (channels != 1 or g.temperature.kind != .field or
                    g.emissivity.kind != .parameter) return error.InvalidResolver;
                try checkSlot(g.temperature, written, constants.len);
                try checkSlot(g.emissivity, written, constants.len);
                try g.radiance.validate();
            },
            .greybody_band_apparent_c => |g| {
                if (channels != 1 or
                    g.temperature.kind != .field or
                    g.emissivity.kind != .parameter or
                    !std.math.isFinite(g.ambient_k))
                {
                    return error.InvalidResolver;
                }
                try checkSlot(g.temperature, written, constants.len);
                try checkSlot(g.emissivity, written, constants.len);
                try g.radiance.validate();
                const num_vals = @as(F, @floatFromInt(g.radiance.values.len - 1));
                const last_k = g.radiance.first + g.radiance.step * num_vals;
                if (g.ambient_k < g.radiance.first or g.ambient_k > last_k) {
                    return error.InvalidResolver;
                }
                for (1..g.radiance.values.len) |ii| {
                    if (g.radiance.values[ii] <= g.radiance.values[ii - 1]) {
                        return error.InvalidResolver;
                    }
                }
            },
            .expression => |p| try p.validate(written, channels),
        }
    }

    pub fn evaluate(
        self: Resolver,
        inputs: anytype,
        constants: []const F,
        channels: u8,
        out: anytype,
    ) void {
        const T = @TypeOf(out.*[0]);
        switch (self) {
            .identity => |slots| for (slots, 0..) |slot, ii| {
                out.*[ii] = readSlot(T, inputs, constants, slot);
            },
            .sum => |slots| {
                for (0..channels) |ch| out.*[ch] = splat(T, 0);
                for (slots, 0..) |slot, ii| {
                    out.*[ii % channels] += readSlot(T, inputs, constants, slot);
                }
            },
            .modulate => |m| {
                const factor = readSlot(T, inputs, constants, m.factor);
                const ambient_splat = splat(T, m.ambient);
                const gain_splat = splat(T, m.gain);
                for (m.sources, 0..) |slot, ii| {
                    const src_val = readSlot(T, inputs, constants, slot);
                    out.*[ii] = (src_val * factor + ambient_splat) * gain_splat;
                }
            },
            .weighted_sum => |w| {
                for (0..channels) |ch| out.*[ch] = splat(T, 0);
                for (w.sources, w.weights, 0..) |slot, weight, ii| {
                    const src_val = readSlot(T, inputs, constants, slot);
                    out.*[ii % channels] += src_val * splat(T, weight);
                }
            },
            .greybody_bolometric => |g| {
                const temp = readSlot(T, inputs, constants, g.temperature);
                const square = temp * temp;
                const em_val = readSlot(T, inputs, constants, g.emissivity);
                const stefan_boltzmann = splat(T, 5.670374419e-8);
                out.*[0] = em_val * stefan_boltzmann * square * square;
            },
            .greybody_band => |g| {
                const temp = readSlot(T, inputs, constants, g.temperature);
                var radiant: T = undefined;
                if (T == F) {
                    radiant = g.radiance.sample(temp);
                } else {
                    var lanes: [buildconfig.SimdWidth]F = @bitCast(temp);
                    for (&lanes) |*lane| lane.* = g.radiance.sample(lane.*);
                    radiant = @bitCast(lanes);
                }
                out.*[0] = readSlot(T, inputs, constants, g.emissivity) * radiant;
            },
            .greybody_band_apparent_c => |g| {
                const temp = readSlot(T, inputs, constants, g.temperature);
                const emissivity = readSlot(T, inputs, constants, g.emissivity);
                const ambient = g.radiance.sample(g.ambient_k);
                if (T == F) {
                    const rad_temp = g.radiance.sample(temp);
                    const measured = emissivity * rad_temp + (1 - emissivity) * ambient;
                    out.*[0] = g.radiance.inverseMonotonic(measured) - 273.15;
                } else {
                    const temp_lanes: [buildconfig.SimdWidth]F = @bitCast(temp);
                    const emissivity_lanes: [buildconfig.SimdWidth]F = @bitCast(emissivity);
                    var result: [buildconfig.SimdWidth]F = undefined;
                    for (&result, temp_lanes, emissivity_lanes) |*lane, t, e| {
                        const measured = e * g.radiance.sample(t) + (1 - e) * ambient;
                        lane.* = g.radiance.inverseMonotonic(measured) - 273.15;
                    }
                    out.*[0] = @bitCast(result);
                }
            },
            .expression => |p| p.evaluate(inputs, channels, out),
        }
    }
};

fn checkSlot(slot: Slot, written: Written, constant_count: usize) !void {
    if (slot.kind == .constant) {
        if (slot.index >= constant_count) return error.InvalidSlot;
    } else if (!written.has(slot)) return error.UnwrittenSlot;
}

fn readSlot(comptime T: type, inputs: anytype, constants: []const F, slot: Slot) T {
    return if (slot.kind == .constant)
        splat(T, constants[slot.index])
    else
        inputs.get(slot);
}

test "resolver arithmetic retains earlier outputs" {
    var written: Written = .{};
    try written.add(.{ .kind = .channel, .index = 0 });
    try written.add(.{ .kind = .channel, .index = 1 });
    try written.add(.{ .kind = .parameter, .index = 0 });
    try std.testing.expectError(
        error.RepeatedWriter,
        written.add(.{ .kind = .channel, .index = 0 }),
    );
    const ops = [_]Op{
        .{ .load = .{ .kind = .channel, .index = 0 } },
        .{ .load = .{ .kind = .parameter, .index = 0 } },
        .multiply,
        .{ .load = .{ .kind = .channel, .index = 1 } },
        .add,
        .{ .store = 0 },
        .{ .load = .{ .kind = .channel, .index = 0 } },
        .{ .load = .{ .kind = .channel, .index = 1 } },
        .subtract,
        .{ .store = 1 },
    };
    const resolver: Resolver = .{ .expression = .{ .operations = &ops } };
    try resolver.validate(written, &.{}, 2);
    var inputs: ScalarOutputs = .{};
    inputs.channel[0] = 0.75;
    inputs.channel[1] = 0.25;
    inputs.parameter[0] = 0.5;
    var out: [2]F = undefined;
    resolver.evaluate(&inputs, &.{}, 2, &out);
    try std.testing.expectApproxEqAbs(@as(F, 0.625), out[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(F, 0.5), out[1], 1e-12);
    try std.testing.expectEqual(@as(F, 0.75), inputs.channel[0]);
}

test "bolometric emission and LUT agree with independent values" {
    var written: Written = .{};
    try written.add(.{ .kind = .field, .index = 0 });
    try written.add(.{ .kind = .parameter, .index = 0 });
    var inputs: ScalarOutputs = .{};
    inputs.field[0] = 300;
    inputs.parameter[0] = 0.8;
    var out: [1]F = undefined;
    const bolometric: Resolver = .{ .greybody_bolometric = .{
        .temperature = .{ .kind = .field, .index = 0 },
        .emissivity = .{ .kind = .parameter, .index = 0 },
    } };
    try bolometric.validate(written, &.{}, 1);
    bolometric.evaluate(&inputs, &.{}, 1, &out);
    const tol: F = if (F == f32) 1e-4 else 1e-9;
    try std.testing.expectApproxEqAbs(@as(F, 367.4402623512), out[0], tol);

    const lut = Lookup{ .first = 290, .step = 20, .values = &.{ 10, 30 } };
    const band: Resolver = .{ .greybody_band = .{
        .temperature = .{ .kind = .field, .index = 0 },
        .emissivity = .{ .kind = .parameter, .index = 0 },
        .radiance = lut,
    } };
    try band.validate(written, &.{}, 1);
    band.evaluate(&inputs, &.{}, 1, &out);
    try std.testing.expectApproxEqAbs(@as(F, 16), out[0], 1e-12);
}

test "resolver rejects missing writers and outputs" {
    const missing = [_]Op{
        .{ .load = .{ .kind = .field, .index = 0 } },
        .{ .store = 0 },
    };
    const prog_missing = Program{ .operations = &missing };
    try std.testing.expectError(error.UnwrittenSlot, prog_missing.validate(.{}, 1));
    const incomplete = [_]Op{
        .{ .load = .{ .kind = .constant, .index = 0 } },
        .{ .store = 0 },
    };
    const prog_incomplete = Program{
        .operations = &incomplete,
        .constants = &.{1},
    };
    try std.testing.expectError(
        error.InvalidProgram,
        prog_incomplete.validate(.{}, 2),
    );
}

test "band Planck LUT is positive, temperature ordered, and interpolates" {
    const rel_tol: F = if (F == f32) 1e-5 else 1e-12;
    try std.testing.expectApproxEqRel(
        @as(F, 9_924_033.330070695),
        planckSpectralRadiance(10e-6, 300),
        rel_tol,
    );
    const response: BandResponse = .{
        .wavelengths_m = &.{ 8e-6, 9e-6, 10e-6, 11e-6, 12e-6 },
        .response = &.{ 0, 1, 1, 1, 0 },
    };
    const lut = try response.prepareRadianceLookup(
        std.testing.allocator,
        280,
        320,
        1,
    );
    defer std.testing.allocator.free(lut.values);
    try std.testing.expect(lut.values[0] > 0);
    try std.testing.expect(lut.values[40] > lut.values[0]);
    const midpoint = lut.sample(300.5);
    const interp_tol: F = if (F == f32) 1e-6 else 1e-12;
    const avg_val = (lut.values[20] + lut.values[21]) / 2;
    try std.testing.expectApproxEqRel(avg_val, midpoint, interp_tol);
    const bad_response = BandResponse{
        .wavelengths_m = &.{ 10e-6, 9e-6 },
        .response = &.{ 1, 1 },
    };
    try std.testing.expectError(
        error.InvalidBandResponse,
        bad_response.prepareRadianceLookup(std.testing.allocator, 280, 320, 1),
    );
}

test "apparent temperature includes reflected ambient and inverts band radiance" {
    var written: Written = .{};
    try written.add(.{ .kind = .field, .index = 0 });
    try written.add(.{ .kind = .parameter, .index = 0 });
    const values = [_]F{ 10, 20, 30, 40, 50 };
    const resolver: Resolver = .{ .greybody_band_apparent_c = .{
        .temperature = .{ .kind = .field, .index = 0 },
        .emissivity = .{ .kind = .parameter, .index = 0 },
        .radiance = .{ .first = 280, .step = 10, .values = &values },
        .ambient_k = 290,
    } };
    try resolver.validate(written, &.{}, 1);
    var inputs: ScalarOutputs = .{};
    inputs.field[0] = 310;
    inputs.parameter[0] = 0.8;
    var output: [1]F = undefined;
    resolver.evaluate(&inputs, &.{}, 1, &output);
    try std.testing.expectApproxEqAbs(@as(F, 32.85), output[0], 1e-10);
    inputs.parameter[0] = 1;
    resolver.evaluate(&inputs, &.{}, 1, &output);
    try std.testing.expectApproxEqAbs(@as(F, 36.85), output[0], 1e-10);
    inputs.parameter[0] = 0;
    resolver.evaluate(&inputs, &.{}, 1, &output);
    try std.testing.expectApproxEqAbs(@as(F, 16.85), output[0], 1e-10);
    var bad = values;
    bad[2] = bad[1];
    const invalid: Resolver = .{ .greybody_band_apparent_c = .{
        .temperature = .{ .kind = .field, .index = 0 },
        .emissivity = .{ .kind = .parameter, .index = 0 },
        .radiance = .{ .first = 280, .step = 10, .values = &bad },
        .ambient_k = 290,
    } };
    try std.testing.expectError(error.InvalidResolver, invalid.validate(written, &.{}, 1));
}

test "generic pipe stages compose with fixed and slot alpha" {
    const c0 = Slot{ .kind = .channel, .index = 0 };
    const c1 = Slot{ .kind = .channel, .index = 1 };
    const f0 = Slot{ .kind = .field, .index = 0 };
    const f1 = Slot{ .kind = .field, .index = 1 };
    const f2 = Slot{ .kind = .field, .index = 2 };
    const p0 = Slot{ .kind = .parameter, .index = 0 };
    var outputs: ScalarOutputs = .{};
    outputs.set(c0, 0.25);
    outputs.set(c1, 0.75);
    outputs.set(p0, 0.5);
    (AffineMapStage{ .source = c0, .destination = f0, .gain = 2, .offset = 0.1 })
        .apply(&outputs);
    const values = [_]F{ 0, 10 };
    const lut = LUTMapStage{ .source = f0, .destination = f1, .lookup = .{ .first = 0, .step = 1, .values = &values } };
    lut.apply(&outputs, true);
    (BlendStage{ .a = f1, .b = c1, .destination = f2, .alpha = .{ .slot = p0 } })
        .apply(&outputs);
    try std.testing.expectApproxEqAbs(@as(F, 3.375), outputs.get(f2), 1e-6);
    (BlendStage{ .a = c0, .b = c1, .destination = .{ .kind = .field, .index = 3 }, .alpha = .{ .fixed = -1 } }).apply(&outputs);
    try std.testing.expectApproxEqAbs(@as(F, -0.25), outputs.field[3], 1e-6);
    outputs.set(f0, -2);
    lut.apply(&outputs, true);
    try std.testing.expectEqual(@as(F, 0), outputs.get(f1));
    outputs.set(f0, 3);
    lut.apply(&outputs, true);
    try std.testing.expectEqual(@as(F, 10), outputs.get(f1));
}

test "normalise handles 2D and 3D vectors including zero" {
    var outputs: ScalarOutputs = .{};
    outputs.field[0] = 3;
    outputs.field[1] = 4;
    outputs.field[2] = 0;
    const src = Slot{ .kind = .field, .index = 0 };
    const dst = Slot{ .kind = .channel, .index = 0 };
    (NormaliseStage{ .source = src, .destination = dst, .components = 2 }).apply(&outputs);
    try std.testing.expectApproxEqAbs(@as(F, 0.6), outputs.channel[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(F, 0.8), outputs.channel[1], 1e-6);
    (NormaliseStage{ .source = src, .destination = .{ .kind = .channel, .index = 2 }, .components = 3 }).apply(&outputs);
    try std.testing.expectEqual(@as(F, 0), outputs.channel[4]);
    outputs.field[0] = 0;
    outputs.field[1] = 0;
    outputs.field[2] = 0;
    (NormaliseStage{ .source = src, .destination = .{ .kind = .channel, .index = 5 }, .components = 3 }).apply(&outputs);
    try std.testing.expectEqual(@as(F, 0), outputs.channel[5]);
    try std.testing.expectEqual(@as(F, 0), outputs.channel[6]);
    try std.testing.expectEqual(@as(F, 0), outputs.channel[7]);
}

test "generic pipe stages match scalar values on SIMD lanes" {
    const S = buildconfig.SimdWidth;
    var outputs: VectorOutputs = .{};
    var x: [S]F = undefined;
    var y: [S]F = undefined;
    var alpha: [S]F = undefined;
    var active: buildconfig.VecSB = @splat(true);
    for (0..S) |lane| {
        x[lane] = @as(F, @floatFromInt(lane)) / @as(F, @floatFromInt(S));
        y[lane] = 0.75;
        alpha[lane] = 0.25;
    }
    active[S - 1] = false;
    x[S - 1] = std.math.nan(F);
    outputs.channel[0] = @bitCast(x);
    outputs.channel[1] = @bitCast(y);
    outputs.parameter[0] = @bitCast(alpha);
    (AffineMapStage{ .source = .{ .kind = .channel, .index = 0 }, .destination = .{ .kind = .field, .index = 0 }, .gain = 2, .offset = 0.1 })
        .apply(&outputs);
    const values = [_]F{ 0, 10 };
    (LUTMapStage{ .source = .{ .kind = .field, .index = 0 }, .destination = .{ .kind = .field, .index = 1 }, .lookup = .{ .first = 0, .step = 1, .values = &values } })
        .apply(&outputs, active);
    (BlendStage{ .a = .{ .kind = .field, .index = 1 }, .b = .{ .kind = .channel, .index = 1 }, .destination = .{ .kind = .field, .index = 2 }, .alpha = .{ .slot = .{ .kind = .parameter, .index = 0 } } })
        .apply(&outputs);
    const result: [S]F = @bitCast(outputs.field[2]);
    for (0..S - 1) |lane| {
        const lut_val = @min(@as(F, 10), (2 * x[lane] + 0.1) * 10);
        const expected = 0.75 * lut_val + 0.25 * y[lane];
        try std.testing.expectApproxEqAbs(expected, result[lane], 1e-5);
    }
    var vx: [S]F = undefined;
    var vy: [S]F = undefined;
    var vz: [S]F = undefined;
    for (0..S) |lane| {
        vx[lane] = if (lane == 0) 0 else 3;
        vy[lane] = if (lane == 0) 0 else 4;
        vz[lane] = 0;
    }
    outputs.field[3] = @bitCast(vx);
    outputs.field[4] = @bitCast(vy);
    outputs.field[5] = @bitCast(vz);
    (NormaliseStage{ .source = .{ .kind = .field, .index = 3 }, .destination = .{ .kind = .channel, .index = 3 }, .components = 3 })
        .apply(&outputs);
    const nx: [S]F = @bitCast(outputs.channel[3]);
    const ny: [S]F = @bitCast(outputs.channel[4]);
    const nz: [S]F = @bitCast(outputs.channel[5]);
    for (0..S) |lane| {
        try std.testing.expectApproxEqAbs(if (lane == 0) @as(F, 0) else 0.6, nx[lane], 1e-6);
        try std.testing.expectApproxEqAbs(if (lane == 0) @as(F, 0) else 0.8, ny[lane], 1e-6);
        try std.testing.expectEqual(@as(F, 0), nz[lane]);
    }
}
