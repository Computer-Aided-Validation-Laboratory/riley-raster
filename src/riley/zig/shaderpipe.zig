// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;

// --------------------------------------------------------------------------------------
// Shader Pipe Stages
// --------------------------------------------------------------------------------------

pub const GreyToEmissivityStage = struct {
    register_source: Register,
    register_dest: Register,
    emissivity_at_black: F,
    emissivity_at_white: F,
    greylevel_at_black: F = 0,
    greylevel_at_white: F = 1,
};

pub const ClampStage = struct {
    register_source: Register,
    register_dest: Register,
    lower: F,
    upper: F,
};

pub const AffineMapStage = struct {
    register_source: Register,
    register_dest: Register,
    gain: F,
    offset: F,

    pub inline fn apply(self: @This(), outputs: anytype) void {
        const T = @TypeOf(outputs.get(self.register_source));
        outputs.set(self.register_dest, outputs.get(self.register_source) * splat(T, self.gain) +
            splat(T, self.offset));
    }
};

pub const LUTMapStage = struct {
    register_source: Register,
    register_dest: Register,
    lookup: LookupTable,

    pub inline fn apply(self: @This(), outputs: anytype, active: anytype) void {
        const T = @TypeOf(outputs.get(self.register_source));
        if (T == F) {
            outputs.set(self.register_dest, self.lookup.sample(outputs.get(self.register_source)));
        } else {
            const values: [buildconfig.SimdWidth]F = @bitCast(outputs.get(self.register_source));
            const mask: [buildconfig.SimdWidth]bool = active;
            var result: [buildconfig.SimdWidth]F = undefined;
            for (&result, values, mask) |*dest, value, enabled| {
                dest.* = self.lookup.sample(if (enabled) value else self.lookup.first);
            }
            outputs.set(self.register_dest, @bitCast(result));
        }
    }
};

pub const BlendWeight = union(enum) { fixed: F, register: Register };

pub const BlendStage = struct {
    a: Register,
    b: Register,
    register_dest: Register,
    alpha: BlendWeight,

    pub inline fn apply(self: @This(), outputs: anytype) void {
        const T = @TypeOf(outputs.get(self.a));
        const alpha = switch (self.alpha) {
            .fixed => |value| splat(T, value),
            .register => |register_ref| outputs.get(register_ref),
        };
        const a = outputs.get(self.a);
        const b = outputs.get(self.b);
        outputs.set(self.register_dest, (splat(T, 1) - alpha) * a + alpha * b);
    }
};

pub const NormaliseStage = struct {
    register_source: Register,
    register_dest: Register,
    components: u8,

    pub inline fn apply(self: @This(), outputs: anytype) void {
        const T = @TypeOf(outputs.get(self.register_source));

        var values: [3]T = undefined;
        var squared: T = splat(T, 0);
        for (0..self.components) |i| {
            var register_ref = self.register_source;
            register_ref.index += @intCast(i);
            values[i] = outputs.get(register_ref);
            squared += values[i] * values[i];
        }

        if (T == F) {
            const inv_norm: F = if (squared == 0) 0 else 1 / @sqrt(squared);
            for (0..self.components) |i| {
                var dest = self.register_dest;
                dest.index += @intCast(i);
                outputs.set(dest, values[i] * inv_norm);
            }
        } else {
            const positive = squared > splat(T, 0);
            const safe_squared = @select(F, positive, squared, splat(T, 1));
            const inv_norm = @select(F, positive, splat(T, 1) / @sqrt(safe_squared), splat(T, 0));
            for (0..self.components) |i| {
                var dest = self.register_dest;
                dest.index += @intCast(i);
                outputs.set(dest, values[i] * inv_norm);
            }
        }
    }
};

// --------------------------------------------------------------------------------------
// Registers for Pipe Stage Outputs
// --------------------------------------------------------------------------------------

pub const RegisterKind = enum { channel, field, parameter, constant };
pub const Register = struct { kind: RegisterKind, index: u8 };

pub const identity_channels = blk: {
    var registers: [buildconfig.config.max_image_channels]Register = undefined;
    for (&registers, 0..) |*register_ref, index| {
        register_ref.* = .{ .kind = .channel, .index = @intCast(index) };
    }
    break :blk registers;
};

pub const identity_channels_1: []const Register = identity_channels[0..1];
pub const identity_channels_3: []const Register = identity_channels[0..3];

pub fn identityRegisters(channels: u8) []const Register {
    std.debug.assert(channels <= buildconfig.config.max_image_channels);
    return identity_channels[0..channels];
}

pub fn RegistersOutput(comptime T: type) type {
    return struct {
        channel: [buildconfig.config.shaderpipe.max_registers]T = undefined,
        field: [buildconfig.config.shaderpipe.max_registers]T = undefined,
        parameter: [buildconfig.config.shaderpipe.max_registers]T = undefined,

        pub inline fn get(self: *const @This(), register_ref: Register) T {
            return switch (register_ref.kind) {
                .channel => self.channel[register_ref.index],
                .field => self.field[register_ref.index],
                .parameter => self.parameter[register_ref.index],
                .constant => unreachable,
            };
        }

        pub inline fn set(self: *@This(), register_ref: Register, value: T) void {
            switch (register_ref.kind) {
                .channel => self.channel[register_ref.index] = value,
                .field => self.field[register_ref.index] = value,
                .parameter => self.parameter[register_ref.index] = value,
                .constant => unreachable,
            }
        }
    };
}

pub const RegistersOutputScalar = RegistersOutput(F);
pub const RegistersOutputSIMD = RegistersOutput(buildconfig.VecSF);

pub const RegistersWritten = struct {
    const Mask = std.meta.Int(.unsigned, buildconfig.config.shaderpipe.max_registers);
    channel: Mask = 0,
    field: Mask = 0,
    parameter: Mask = 0,

    pub fn isWritten(self: RegistersWritten, register_ref: Register) bool {
        if (register_ref.index >= buildconfig.config.shaderpipe.max_registers or register_ref.kind == .constant) return false;
        const mask: Mask = @as(Mask, 1) << @intCast(register_ref.index);
        return switch (register_ref.kind) {
            .channel => self.channel & mask != 0,
            .field => self.field & mask != 0,
            .parameter => self.parameter & mask != 0,
            .constant => unreachable,
        };
    }

    pub fn recordWrite(self: *RegistersWritten, register_ref: Register) !void {
        if (register_ref.index >= buildconfig.config.shaderpipe.max_registers or register_ref.kind == .constant) return error.InvalidRegister;
        if (self.isWritten(register_ref)) return error.RepeatedWriter;
        const mask: Mask = @as(Mask, 1) << @intCast(register_ref.index);
        switch (register_ref.kind) {
            .channel => self.channel |= mask,
            .field => self.field |= mask,
            .parameter => self.parameter |= mask,
            .constant => unreachable,
        }
    }
};

// --------------------------------------------------------------------------------------
// Resolver Programs
// --------------------------------------------------------------------------------------

pub const ResolverOp = union(enum) {
    load: Register,
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

pub const ResolverProgram = struct {
    operations: []const ResolverOp,
    constants: []const F = &.{},
    lookups: []const LookupTable = &.{},

    pub fn validate(self: ResolverProgram, written: RegistersWritten, channels: u8) !void {
        if (channels == 0 or channels > buildconfig.config.max_image_channels or self.operations.len == 0 or
            self.operations.len > buildconfig.config.shaderpipe.max_ops or self.constants.len > buildconfig.config.shaderpipe.max_registers)
            return error.InvalidProgram;
        for (self.constants) |value| {
            if (!std.math.isFinite(value)) return error.InvalidConstant;
        }
        for (self.lookups) |lut| try lut.validate();
        var depth: usize = 0;
        var stored: u16 = 0;
        for (self.operations) |op| switch (op) {
            .load => |register_ref| {
                if (register_ref.kind == .constant) {
                    if (register_ref.index >= self.constants.len) return error.InvalidRegister;
                } else if (!written.isWritten(register_ref)) return error.UnwrittenSlot;
                depth += 1;
                if (depth > buildconfig.config.shaderpipe.max_stack) return error.InvalidProgram;
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

    pub fn evaluate(self: ResolverProgram, inputs: anytype, channels: u8, out: anytype) void {
        const T = @TypeOf(out.*[0]);
        var stack: [buildconfig.config.shaderpipe.max_stack]T = undefined;
        var depth: usize = 0;
        for (self.operations) |op| switch (op) {
            .load => |register_ref| {
                stack[depth] = if (register_ref.kind == .constant)
                    splat(T, self.constants[register_ref.index])
                else
                    inputs.get(register_ref);
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

// --------------------------------------------------------------------------------------
// Output Resolution
// --------------------------------------------------------------------------------------

pub const Resolver = union(enum) {
    identity: []const Register,
    sum: []const Register,
    modulate: struct {
        register_sources: []const Register,
        factor: Register,
        ambient: F = 0,
        gain: F = 1,
    },
    weighted_sum: struct {
        register_sources: []const Register,
        weights: []const F,
    },
    greybody_bolometric: struct {
        temperature: Register,
        emissivity: Register,
    },
    greybody_band: struct {
        temperature: Register,
        emissivity: Register,
        radiance: LookupTable,
    },
    greybody_band_apparent_c: struct {
        temperature: Register,
        emissivity: Register,
        radiance: LookupTable,
        ambient_k: F,
    },
    expression: ResolverProgram,

    pub fn validate(
        self: Resolver,
        written: RegistersWritten,
        constants: []const F,
        channels: u8,
    ) !void {
        if (channels == 0 or channels > buildconfig.config.max_image_channels) {
            return error.InvalidChannels;
        }
        switch (self) {
            .identity => |registers| {
                if (registers.len != channels) return error.InvalidChannels;
                for (registers) |register_ref| {
                    if (register_ref.kind != .channel) return error.InvalidResolver;
                    try checkRegister(register_ref, written, constants.len);
                }
            },
            .sum => |registers| {
                if (registers.len < channels or registers.len % channels != 0) {
                    return error.InvalidChannels;
                }
                for (registers) |register_ref| {
                    if (register_ref.kind != .channel) return error.InvalidResolver;
                    try checkRegister(register_ref, written, constants.len);
                }
            },
            .modulate => |m| {
                if (m.register_sources.len != channels or !std.math.isFinite(m.ambient) or
                    !std.math.isFinite(m.gain)) return error.InvalidResolver;
                for (m.register_sources) |register_ref| {
                    if (register_ref.kind != .channel) return error.InvalidResolver;
                    try checkRegister(register_ref, written, constants.len);
                }
                if (m.factor.kind != .parameter) return error.InvalidResolver;
                try checkRegister(m.factor, written, constants.len);
            },
            .weighted_sum => |w| {
                if (w.register_sources.len < channels or w.register_sources.len % channels != 0 or
                    w.register_sources.len != w.weights.len) return error.InvalidResolver;
                for (w.register_sources) |register_ref| {
                    if (register_ref.kind != .channel) return error.InvalidResolver;
                    try checkRegister(register_ref, written, constants.len);
                }
                for (w.weights) |weight| {
                    if (!std.math.isFinite(weight)) return error.InvalidResolver;
                }
            },
            .greybody_bolometric => |g| {
                if (channels != 1 or g.temperature.kind != .field or
                    g.emissivity.kind != .parameter) return error.InvalidResolver;
                try checkRegister(g.temperature, written, constants.len);
                try checkRegister(g.emissivity, written, constants.len);
            },
            .greybody_band => |g| {
                if (channels != 1 or g.temperature.kind != .field or
                    g.emissivity.kind != .parameter) return error.InvalidResolver;
                try checkRegister(g.temperature, written, constants.len);
                try checkRegister(g.emissivity, written, constants.len);
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
                try checkRegister(g.temperature, written, constants.len);
                try checkRegister(g.emissivity, written, constants.len);
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
        const ambient = switch (self) {
            .greybody_band_apparent_c => |g| g.radiance.sample(g.ambient_k),
            else => 0,
        };
        evaluateResolver(false, self, inputs, constants, channels, out, ambient, 0, 0);
    }
};

pub fn resolverIdentity(channels: u8) Resolver {
    return .{ .identity = identityRegisters(channels) };
}

pub const ResolverPrepared = struct {
    value: Resolver,
    ambient_radiance: F = 0,
    lookup_last: usize = 0,
    lookup_max: F = 0,

    pub fn init(value: Resolver) ResolverPrepared {
        var result = ResolverPrepared{ .value = value };
        switch (value) {
            .greybody_band => |g| {
                result.lookup_last = g.radiance.values.len - 1;
                result.lookup_max = @floatFromInt(result.lookup_last);
            },
            .greybody_band_apparent_c => |g| {
                result.lookup_last = g.radiance.values.len - 1;
                result.lookup_max = @floatFromInt(result.lookup_last);
                result.ambient_radiance = g.radiance.sample(g.ambient_k);
            },
            else => {},
        }
        return result;
    }

    pub inline fn evaluate(
        self: ResolverPrepared,
        inputs: anytype,
        constants: []const F,
        channels: u8,
        out: anytype,
    ) void {
        evaluateResolver(true, self.value, inputs, constants, channels, out, self.ambient_radiance, self.lookup_last, self.lookup_max);
    }
};

fn evaluateResolver(
    comptime prepared: bool,
    self: Resolver,
    inputs: anytype,
    constants: []const F,
    channels: u8,
    out: anytype,
    ambient_radiance: F,
    lookup_last: usize,
    lookup_max: F,
) void {
    const T = @TypeOf(out.*[0]);
    switch (self) {
        .identity => |registers| for (registers, 0..) |register_ref, ii| {
            out.*[ii] = readRegister(T, inputs, constants, register_ref);
        },
        .sum => |registers| {
            for (0..channels) |ch| out.*[ch] = splat(T, 0);
            for (registers, 0..) |register_ref, ii| {
                out.*[ii % channels] += readRegister(T, inputs, constants, register_ref);
            }
        },
        .modulate => |m| {
            const factor = readRegister(T, inputs, constants, m.factor);
            const ambient_splat = splat(T, m.ambient);
            const gain_splat = splat(T, m.gain);

            for (m.register_sources, 0..) |register_ref, ii| {
                const src_val = readRegister(T, inputs, constants, register_ref);
                out.*[ii] = (src_val * factor + ambient_splat) * gain_splat;
            }
        },
        .weighted_sum => |w| {
            for (0..channels) |ch| out.*[ch] = splat(T, 0);

            for (w.register_sources, w.weights, 0..) |register_ref, weight, ii| {
                const src_val = readRegister(T, inputs, constants, register_ref);
                out.*[ii % channels] += src_val * splat(T, weight);
            }
        },
        .greybody_bolometric => |g| {
            const temp = readRegister(T, inputs, constants, g.temperature);
            const square = temp * temp;
            const em_val = readRegister(T, inputs, constants, g.emissivity);
            const stefan_boltzmann = splat(T, 5.670374419e-8);
            out.*[0] = em_val * stefan_boltzmann * square * square;
        },
        .greybody_band => |g| {
            const radiance = if (prepared) LookupTablePrepared.initMetadata(g.radiance, lookup_last, lookup_max) else g.radiance;
            const temp = readRegister(T, inputs, constants, g.temperature);

            var radiant: T = undefined;
            if (T == F) {
                radiant = radiance.sample(temp);
            } else {
                var lanes: [buildconfig.SimdWidth]F = @bitCast(temp);
                for (&lanes) |*lane| lane.* = radiance.sample(lane.*);
                radiant = @bitCast(lanes);
            }
            out.*[0] = readRegister(T, inputs, constants, g.emissivity) * radiant;
        },
        .greybody_band_apparent_c => |g| {
            const radiance = if (prepared) LookupTablePrepared.initMetadata(
                g.radiance,
                lookup_last,
                lookup_max,
            ) else g.radiance;
            const temp = readRegister(T, inputs, constants, g.temperature);
            const emissivity = readRegister(T, inputs, constants, g.emissivity);
            const ambient = ambient_radiance;

            if (T == F) {
                const rad_temp = radiance.sample(temp);
                const measured = emissivity * rad_temp + (1 - emissivity) * ambient;
                out.*[0] = g.radiance.inverseMonotonic(measured) - 273.15;
            } else {
                const temp_lanes: [buildconfig.SimdWidth]F = @bitCast(temp);
                const emissivity_lanes: [buildconfig.SimdWidth]F = @bitCast(emissivity);
                var result: [buildconfig.SimdWidth]F = undefined;
                for (&result, temp_lanes, emissivity_lanes) |*lane, t, e| {
                    const measured = e * radiance.sample(t) + (1 - e) * ambient;
                    lane.* = g.radiance.inverseMonotonic(measured) - 273.15;
                }
                out.*[0] = @bitCast(result);
            }
        },
        .expression => |p| p.evaluate(inputs, channels, out),
    }
}

// --------------------------------------------------------------------------------------
// Lookup Tables and Spectral Response
// --------------------------------------------------------------------------------------

pub const LookupTable = struct {
    first: F,
    step: F,
    values: []const F,

    pub fn validate(self: LookupTable) !void {
        if (!std.math.isFinite(self.first) or !std.math.isFinite(self.step) or
            self.step <= 0 or self.values.len < 2) return error.InvalidLookup;
        for (self.values) |value| {
            if (!std.math.isFinite(value)) return error.InvalidLookup;
        }
    }

    pub inline fn sample(self: LookupTable, value: F) F {
        const max_val = @as(F, @floatFromInt(self.values.len - 1));
        const x = std.math.clamp((value - self.first) / self.step, 0, max_val);
        const i: usize = @intFromFloat(x);
        if (i == self.values.len - 1) return self.values[i];
        const t = x - @as(F, @floatFromInt(i));
        return self.values[i] + t * (self.values[i + 1] - self.values[i]);
    }

    pub fn inverseMonotonic(self: LookupTable, value: F) F {
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

// Immutable engine-side metadata. User-facing descriptors keep their existing layout.
pub const LookupTablePrepared = struct {
    lookup: LookupTable,
    last: usize,
    max_index: F,

    pub fn init(lookup: LookupTable) LookupTablePrepared {
        return initMetadata(lookup, lookup.values.len - 1, @floatFromInt(lookup.values.len - 1));
    }

    fn initMetadata(lookup: LookupTable, last: usize, max_index: F) LookupTablePrepared {
        return .{ .lookup = lookup, .last = last, .max_index = max_index };
    }

    pub inline fn sample(self: LookupTablePrepared, value: F) F {
        const x = std.math.clamp((value - self.lookup.first) / self.lookup.step, 0, self.max_index);
        const index: usize = @intFromFloat(x);
        if (index == self.last) return self.lookup.values[index];
        const t = x - @as(F, @floatFromInt(index));
        return self.lookup.values[index] + t * (self.lookup.values[index + 1] - self.lookup.values[index]);
    }
};

/// Integrates blackbody spectral radiance against an absolute, dimensionless
/// camera response. Wavelengths are metres; values are W/(m² sr).
pub const SpectralBandResponse = struct {
    wavelengths_m: []const F,
    response: []const F,

    pub fn prepareRadianceLookup(
        self: SpectralBandResponse,
        allocator: std.mem.Allocator,
        temp_first_k: F,
        temp_last_k: F,
        temp_step_k: F,
    ) !LookupTable {
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

// --------------------------------------------------------------------------------------
// Shared Helpers
// --------------------------------------------------------------------------------------

fn checkRegister(register_ref: Register, written: RegistersWritten, constant_count: usize) !void {
    if (register_ref.kind == .constant) {
        if (register_ref.index >= constant_count) return error.InvalidRegister;
    } else if (!written.isWritten(register_ref)) return error.UnwrittenSlot;
}

fn readRegister(comptime T: type, inputs: anytype, constants: []const F, register_ref: Register) T {
    return if (register_ref.kind == .constant)
        splat(T, constants[register_ref.index])
    else
        inputs.get(register_ref);
}

inline fn splat(comptime T: type, value: F) T {
    return if (T == F) value else @splat(value);
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

test "resolver arithmetic retains earlier outputs" {
    var written: RegistersWritten = .{};
    try written.recordWrite(.{ .kind = .channel, .index = 0 });
    try written.recordWrite(.{ .kind = .channel, .index = 1 });
    try written.recordWrite(.{ .kind = .parameter, .index = 0 });
    try std.testing.expectError(
        error.RepeatedWriter,
        written.recordWrite(.{ .kind = .channel, .index = 0 }),
    );
    const ops = [_]ResolverOp{
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
    var inputs: RegistersOutputScalar = .{};
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
    var written: RegistersWritten = .{};
    try written.recordWrite(.{ .kind = .field, .index = 0 });
    try written.recordWrite(.{ .kind = .parameter, .index = 0 });
    var inputs: RegistersOutputScalar = .{};
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

    const lut = LookupTable{ .first = 290, .step = 20, .values = &.{ 10, 30 } };
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
    const missing = [_]ResolverOp{
        .{ .load = .{ .kind = .field, .index = 0 } },
        .{ .store = 0 },
    };
    const prog_missing = ResolverProgram{ .operations = &missing };
    try std.testing.expectError(error.UnwrittenSlot, prog_missing.validate(.{}, 1));
    const incomplete = [_]ResolverOp{
        .{ .load = .{ .kind = .constant, .index = 0 } },
        .{ .store = 0 },
    };
    const prog_incomplete = ResolverProgram{
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
    const response: SpectralBandResponse = .{
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
    const bad_response = SpectralBandResponse{
        .wavelengths_m = &.{ 10e-6, 9e-6 },
        .response = &.{ 1, 1 },
    };
    try std.testing.expectError(
        error.InvalidBandResponse,
        bad_response.prepareRadianceLookup(std.testing.allocator, 280, 320, 1),
    );
}

test "apparent temperature includes reflected ambient and inverts band radiance" {
    var written: RegistersWritten = .{};
    try written.recordWrite(.{ .kind = .field, .index = 0 });
    try written.recordWrite(.{ .kind = .parameter, .index = 0 });
    const values = [_]F{ 10, 20, 30, 40, 50 };
    const resolver: Resolver = .{ .greybody_band_apparent_c = .{
        .temperature = .{ .kind = .field, .index = 0 },
        .emissivity = .{ .kind = .parameter, .index = 0 },
        .radiance = .{ .first = 280, .step = 10, .values = &values },
        .ambient_k = 290,
    } };
    try resolver.validate(written, &.{}, 1);
    var inputs: RegistersOutputScalar = .{};
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

test "generic pipe stages compose with fixed and register blend weights" {
    const c0 = Register{ .kind = .channel, .index = 0 };
    const c1 = Register{ .kind = .channel, .index = 1 };
    const f0 = Register{ .kind = .field, .index = 0 };
    const f1 = Register{ .kind = .field, .index = 1 };
    const f2 = Register{ .kind = .field, .index = 2 };
    const p0 = Register{ .kind = .parameter, .index = 0 };
    var outputs: RegistersOutputScalar = .{};
    outputs.set(c0, 0.25);
    outputs.set(c1, 0.75);
    outputs.set(p0, 0.5);
    (AffineMapStage{ .register_source = c0, .register_dest = f0, .gain = 2, .offset = 0.1 })
        .apply(&outputs);
    const values = [_]F{ 0, 10 };
    const lut = LUTMapStage{ .register_source = f0, .register_dest = f1, .lookup = .{ .first = 0, .step = 1, .values = &values } };
    lut.apply(&outputs, true);
    (BlendStage{ .a = f1, .b = c1, .register_dest = f2, .alpha = .{ .register = p0 } })
        .apply(&outputs);
    try std.testing.expectApproxEqAbs(@as(F, 3.375), outputs.get(f2), 1e-6);
    (BlendStage{ .a = c0, .b = c1, .register_dest = .{ .kind = .field, .index = 3 }, .alpha = .{ .fixed = -1 } }).apply(&outputs);
    try std.testing.expectApproxEqAbs(@as(F, -0.25), outputs.field[3], 1e-6);
    outputs.set(f0, -2);
    lut.apply(&outputs, true);
    try std.testing.expectEqual(@as(F, 0), outputs.get(f1));
    outputs.set(f0, 3);
    lut.apply(&outputs, true);
    try std.testing.expectEqual(@as(F, 10), outputs.get(f1));
}

test "normalise handles 2D and 3D vectors including zero" {
    var outputs: RegistersOutputScalar = .{};
    outputs.field[0] = 3;
    outputs.field[1] = 4;
    outputs.field[2] = 0;
    const src = Register{ .kind = .field, .index = 0 };
    const dst = Register{ .kind = .channel, .index = 0 };
    (NormaliseStage{ .register_source = src, .register_dest = dst, .components = 2 }).apply(&outputs);
    try std.testing.expectApproxEqAbs(@as(F, 0.6), outputs.channel[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(F, 0.8), outputs.channel[1], 1e-6);
    (NormaliseStage{ .register_source = src, .register_dest = .{ .kind = .channel, .index = 2 }, .components = 3 }).apply(&outputs);
    try std.testing.expectEqual(@as(F, 0), outputs.channel[4]);
    outputs.field[0] = 0;
    outputs.field[1] = 0;
    outputs.field[2] = 0;
    (NormaliseStage{ .register_source = src, .register_dest = .{ .kind = .channel, .index = 5 }, .components = 3 }).apply(&outputs);
    try std.testing.expectEqual(@as(F, 0), outputs.channel[5]);
    try std.testing.expectEqual(@as(F, 0), outputs.channel[6]);
    try std.testing.expectEqual(@as(F, 0), outputs.channel[7]);
}

test "generic pipe stages match scalar values on SIMD lanes" {
    const S = buildconfig.SimdWidth;
    var outputs: RegistersOutputSIMD = .{};
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
    (AffineMapStage{ .register_source = .{ .kind = .channel, .index = 0 }, .register_dest = .{ .kind = .field, .index = 0 }, .gain = 2, .offset = 0.1 })
        .apply(&outputs);
    const values = [_]F{ 0, 10 };
    (LUTMapStage{ .register_source = .{ .kind = .field, .index = 0 }, .register_dest = .{ .kind = .field, .index = 1 }, .lookup = .{ .first = 0, .step = 1, .values = &values } })
        .apply(&outputs, active);
    (BlendStage{ .a = .{ .kind = .field, .index = 1 }, .b = .{ .kind = .channel, .index = 1 }, .register_dest = .{ .kind = .field, .index = 2 }, .alpha = .{ .register = .{ .kind = .parameter, .index = 0 } } })
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
    (NormaliseStage{ .register_source = .{ .kind = .field, .index = 3 }, .register_dest = .{ .kind = .channel, .index = 3 }, .components = 3 })
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

test "prepared resolver preserves lookup interpolation and ambient radiance" {
    const lookup = LookupTable{ .first = 280, .step = 20, .values = &.{ 10, 30, 70, 110 } };
    const cached = LookupTablePrepared.init(lookup);
    for ([_]F{ 270, 280, 294, 300, 310, 320, 340, 350 }) |value|
        try std.testing.expectEqual(lookup.sample(value), cached.sample(value));
    const input = Resolver{ .greybody_band_apparent_c = .{
        .temperature = .{ .kind = .field, .index = 0 },
        .emissivity = .{ .kind = .parameter, .index = 0 },
        .radiance = lookup,
        .ambient_k = 300,
    } };
    const prepared = ResolverPrepared.init(input);
    try std.testing.expectEqual(@as(F, 30), prepared.ambient_radiance);
    var values: RegistersOutputScalar = .{};
    values.field[0] = 320;
    values.parameter[0] = 0.5;
    var result: [1]F = undefined;
    prepared.evaluate(&values, &.{}, 1, &result);
    try std.testing.expectApproxEqAbs(@as(F, 310 - 273.15), result[0], 1e-12);
    var expected: [1]F = undefined;
    input.evaluate(&values, &.{}, 1, &expected);
    try std.testing.expectEqual(expected[0], result[0]);
    var vectors: RegistersOutputSIMD = .{};
    vectors.field[0] = @splat(320);
    vectors.parameter[0] = @splat(0.5);
    var vector_result: [1]buildconfig.VecSF = undefined;
    prepared.evaluate(&vectors, &.{}, 1, &vector_result);
    const lanes: [buildconfig.SimdWidth]F = @bitCast(vector_result[0]);
    for (lanes) |lane| try std.testing.expectEqual(result[0], lane);
}

test "register write tracking respects configured capacity and independent banks" {
    var written: RegistersWritten = .{};
    const last_index = buildconfig.config.shaderpipe.max_registers - 1;
    const channel = Register{ .kind = .channel, .index = last_index };
    const field = Register{ .kind = .field, .index = last_index };
    const parameter = Register{ .kind = .parameter, .index = last_index };
    try std.testing.expect(!written.isWritten(channel));
    try written.recordWrite(channel);
    try std.testing.expect(written.isWritten(channel));
    try std.testing.expect(!written.isWritten(field));
    try std.testing.expect(!written.isWritten(parameter));
    try written.recordWrite(field);
    try written.recordWrite(parameter);
    try std.testing.expect(written.isWritten(field));
    try std.testing.expect(written.isWritten(parameter));
    try std.testing.expectError(error.RepeatedWriter, written.recordWrite(channel));
    try std.testing.expectError(error.InvalidRegister, written.recordWrite(.{ .kind = .constant, .index = 0 }));
    if (comptime buildconfig.config.shaderpipe.max_registers < 256) {
        const outside = Register{
            .kind = .channel,
            .index = buildconfig.config.shaderpipe.max_registers,
        };
        try std.testing.expect(!written.isWritten(outside));
        try std.testing.expectError(error.InvalidRegister, written.recordWrite(outside));
    }
}
