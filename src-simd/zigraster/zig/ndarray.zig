const std = @import("std");
const print = std.debug.print;

const testing = std.testing;
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = testing.expectApproxEqAbs;
const expectEqualSlices = testing.expectEqualSlices;

const MatSlice = @import("matslice.zig").MatSlice;
const sliceops = @import("sliceops.zig");

pub fn NDArray(comptime EType: type) type {
    return struct {
        elems: []EType,
        dims: []usize,
        strides: []usize,

        const Self: type = @This();

        pub fn init(allocator: std.mem.Allocator, 
        			elems: []EType, 
        			dims: []const usize) !Self {
        			
            var dim_prod: usize = dims[0];
            for (1..dims.len) |dd| {
                dim_prod *= dims[dd];
            }

            assert(elems.len >= dim_prod);

            const dims_heap = try allocator.dupe(usize, dims);
            const strides_heap = try allocator.alloc(usize, dims.len);

            var ndarray = NDArray(EType){ .elems = elems, 
            							  .dims = dims_heap, 
            							  .strides = strides_heap };

            for (0..dims.len) |dd| {
                ndarray.strides[dd] = ndarray.calcFlatStride(dd);
            }

            return ndarray;
        }

        pub fn initFlat(allocator: std.mem.Allocator, dims: []const usize) !Self {
            var dim_prod: usize = 1;
            for (dims) |dd| {
                dim_prod *= dd;
            }
            
            const elems = try allocator.alloc(EType, dim_prod);

            return try Self.init(allocator, elems, dims);
        }
    
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.dims);
            allocator.free(self.strides);
        }

        pub fn set(self: *Self, indices: []const usize, in_val: EType) void {
            const ind: usize = self.getFlatInd(indices);
            self.elems[ind] = in_val;
        }

        pub fn get(self: *const Self, indices: []const usize) EType {
            const ind: usize = self.getFlatInd(indices);
            return self.elems[ind];
        }

        pub fn getFlatInd(self: *const Self, indices: []const usize) usize {
            assert(indices.len == self.dims.len);

            var flat: usize = 0;
            for (indices, 0..) |ind, dim| {
                assert(ind < self.dims[dim]);

                flat += ind * self.strides[dim];
            }

            return flat;
        }

        pub fn calcFlatStride(self: *const Self, dim_ind: usize) usize {
            // Row-major (C format) for flat NDArrays
            // stride = product of all dimensions to the right of the selected
            // dimension.
            assert(dim_ind < self.dims.len);

            var stride: usize = 1;

            var ii: usize = dim_ind + 1;
            while (ii < self.dims.len) : (ii += 1) {
                stride *= self.dims[ii];
            }

            return stride;
        }

        pub fn fill(self: *const Self, fill_val: EType) void {
            @memset(self.elems[0..], fill_val);
        }

        pub fn addInPlace(self: *const Self, to_add: *const Self) void {
            assert(matchArrayDims(EType, self, to_add));

            for (0..self.elems.len) |ii| {
                self.elems[ii] += to_add.elems[ii];
            }
        }

        pub fn subInPlace(self: *const Self, to_sub: *const Self) void {
            assert(matchArrayDims(EType, self, to_sub));

            for (0..self.elems.len) |ii| {
                self.elems[ii] -= to_sub.elems[ii];
            }
        }

        pub fn mulInPlace(self: *const Self, to_mul: *const Self) void {
            assert(matchArrayDims(EType, self, to_mul));

            for (0..self.elems.len) |ii| {
                self.elems[ii] *= to_mul.elems[ii];
            }
        }

        pub fn divInPlace(self: *const Self, to_div: *const Self) void {
            assert(matchArrayDims(EType, self, to_div));

            for (0..self.elems.len) |ii| {
                self.elems[ii] /= to_div.elems[ii];
            }
        }

        pub fn mulScalarInPlace(self: *const Self, scalar: EType) void {
            for (0..self.elems.len) |ii| {
                self.elems[ii] *= scalar;
            }
        }

        pub fn divScalarInPlace(self: *const Self, scalar: EType) void {
            for (0..self.elems.len) |ii| {
                self.elems[ii] /= scalar;
            }
        }

        pub fn max(self: *const Self) EType {
            return std.mem.max(EType, self.elems);
        }

        pub fn min(self: *const Self) EType {
            return std.mem.min(EType, self.elems);
        }

        pub fn getSlice(self: *const Self, indices: []const usize, slice_dim: usize) []EType {
            assert(indices.len == self.dims.len);
            const start_ind = self.getFlatInd(indices);
            const len = self.strides[slice_dim];
            return self.elems[start_ind .. start_ind + len];
        }
    };
}

pub fn MappedNDArray(comptime EType: type) type {
    return struct {
        array: NDArray(EType),
        map: []const usize,

        const Self = @This();

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.array.deinit(allocator);
            allocator.free(self.map);
        }
    };
}

pub fn matchArrayDims(comptime EType: type, array0: *const NDArray(EType), array1: *const NDArray(EType)) bool {
    if (array0.dims.len != array1.dims.len) {
        return false;
    }

    for (0..array0.dims.len) |ii| {
        if (array0.dims[ii] != array1.dims[ii]) {
            return false;
        }
    }

    return true;
}

test "NDArray.init" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 2, 3 };
    const elems = try allocator.alloc(f64, 6);
    defer allocator.free(elems);

    var ndarray = try NDArray(f64).init(allocator, elems, dims[0..]);
    defer ndarray.deinit(allocator);

    try expectEqual(ndarray.dims.len, 2);
    try expectEqual(ndarray.dims[0], 2);
    try expectEqual(ndarray.dims[1], 3);
    try expectEqual(ndarray.strides[0], 3);
    try expectEqual(ndarray.strides[1], 1);
}

test "NDArray.initFlat" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 2, 3 };

    var ndarray = try NDArray(f64).initFlat(allocator, dims[0..]);
    defer {
        allocator.free(ndarray.elems);
        ndarray.deinit(allocator);
    }

    try expectEqual(ndarray.elems.len, 6);
    try expectEqual(ndarray.dims[0], 2);
    try expectEqual(ndarray.dims[1], 3);
}

test "NDArray.getSet" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 2, 2 };
    var ndarray = try NDArray(f64).initFlat(allocator, dims[0..]);
    defer {
        allocator.free(ndarray.elems);
        ndarray.deinit(allocator);
    }

    ndarray.set(&[_]usize{ 0, 0 }, 1.0);
    ndarray.set(&[_]usize{ 0, 1 }, 2.0);
    ndarray.set(&[_]usize{ 1, 0 }, 3.0);
    ndarray.set(&[_]usize{ 1, 1 }, 4.0);

    try expectEqual(ndarray.get(&[_]usize{ 0, 0 }), 1.0);
    try expectEqual(ndarray.get(&[_]usize{ 0, 1 }), 2.0);
    try expectEqual(ndarray.get(&[_]usize{ 1, 0 }), 3.0);
    try expectEqual(ndarray.get(&[_]usize{ 1, 1 }), 4.0);
}

test "NDArray.InPlaceOps" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 2, 2 };
    var nd0 = try NDArray(f64).initFlat(allocator, dims[0..]);
    var nd1 = try NDArray(f64).initFlat(allocator, dims[0..]);
    defer {
        allocator.free(nd0.elems);
        nd0.deinit(allocator);
        allocator.free(nd1.elems);
        nd1.deinit(allocator);
    }

    nd0.fill(10.0);
    nd1.fill(2.0);

    nd0.addInPlace(&nd1);
    try expectEqual(nd0.elems[0], 12.0);

    nd0.subInPlace(&nd1);
    try expectEqual(nd0.elems[0], 10.0);

    nd0.mulInPlace(&nd1);
    try expectEqual(nd0.elems[0], 20.0);

    nd0.divInPlace(&nd1);
    try expectEqual(nd0.elems[0], 10.0);

    nd0.mulScalarInPlace(2.0);
    try expectEqual(nd0.elems[0], 20.0);

    nd0.divScalarInPlace(2.0);
    try expectEqual(nd0.elems[0], 10.0);
}

test "NDArray.minMax" {
    const allocator = std.testing.allocator;
    const dims = [_]usize{ 3 };
    var nd = try NDArray(f64).initFlat(allocator, dims[0..]);
    defer {
        allocator.free(nd.elems);
        nd.deinit(allocator);
    }

    nd.elems[0] = 5.0;
    nd.elems[1] = 10.0;
    nd.elems[2] = 2.0;

    try expectEqual(nd.max(), 10.0);
    try expectEqual(nd.min(), 2.0);
}
