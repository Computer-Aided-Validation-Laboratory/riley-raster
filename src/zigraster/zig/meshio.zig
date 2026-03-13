const std = @import("std");
const print = std.debug.print;
const time = std.time;
const assert = std.debug.assert;

const Vec3f = @import("vecstack.zig").Vec3f;
const slice = @import("sliceops.zig");

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

pub const Coords = struct {
    mat: MatSlice(f64),
    mem: []f64,

    const Self: type = @This();
    
    pub fn init(mem: []f64, coords_num: usize) !Self {
        assert(mem.len == coords_num*3);
        const mat_coords = MatSlice(f64).init(mem,coords_num,3); 
        
        return .{
            .mat = mat_coords,
            .mem = mem,
        };
    }

    pub fn initAlloc(outer_alloc: std.mem.Allocator, coords_num: usize) !Self {
        const mat_mem = try outer_alloc.alloc(f64,coords_num*3);

        return init(mat_mem,coords_num);
    }


    pub inline fn x(self: *const Self, ind: usize) f64 {
        return self.mat.get(ind,0);
    }

    pub inline fn y(self: *const Self, ind: usize) f64 {
        return self.mat.get(ind,1);
    }
    
    pub inline fn z(self: *const Self, ind: usize) f64 {
        return self.mat.get(ind,2);
    }

    pub fn getVecSlice(self: *const Self, ind: usize) []f64 {
        return self.mat.getSlice(ind);
    }

    pub fn getVec3(self: *const Coords, ind: usize) Vec3f {
        const vec_slice = self.mat.getSlice(ind);
        const vec = Vec3f.initSlice(vec_slice);
        return vec;
    }
};

pub const Connect = struct {
    table: MatSlice(usize),
    table_mem: []usize,

    const Self: type = @This();

    pub fn init(mem: []usize, elems_num: usize, nodes_per_elem: usize) Self {
        assert(mem.len == elems_num*nodes_per_elem);

        const mat_table = MatSlice(usize).init(mem, elems_num, nodes_per_elem); 

        return .{
          .table = mat_table,
          .table_mem = mem,  
        };      
    }

    pub fn initAlloc(outer_alloc: std.mem.Allocator, 
                     elems_num: usize, 
                     nodes_per_elem: usize) !Self {
                 
        const mat_mem = try outer_alloc.alloc(usize, elems_num*nodes_per_elem);
        
        return init(mat_mem, elems_num, nodes_per_elem);
    }

    pub inline fn getElemsNum(self: Self) usize {
        return self.table.rows_num;
    }

    pub inline  fn getNodesPerElem(self: Self) usize {
        return self.table.cols_num;
    }

    pub fn deinit(self: *Self, outer_alloc: std.mem.Allocator) void {
        outer_alloc.free(self.table_mem);
    }
    
    pub fn getElem(self: *const Self, elem_num: usize) []usize {
        const ind_start: usize = elem_num * self.getNodesPerElem();
        const ind_end: usize = ind_start + self.getNodesPerElem();
        return self.table_mem[ind_start..ind_end];
    }
};


pub const Field = struct {
    array: NDArray(f64),
    array_mem: []f64,

    const Self = @This();

    pub fn initAlloc(alloc: std.mem.Allocator, 
                     time_n: usize, 
                     coord_n: usize,
                     fields_n: usize) !Self {

        const mem_array = try alloc.alloc(f64, time_n*coord_n*fields_n);
        @memset(mem_array,0.0);

        const mem_dims = [3]usize{time_n,coord_n,fields_n};        
        const arr = try NDArray(f64).init(alloc,mem_array,mem_dims[0..]);
        
        return .{
            .array = arr, 
            .array_mem = mem_array,
        };
    }

    pub inline fn getTimeN(self: *const Self) usize {return self.array.dims[0];}
    pub inline fn getCoordN(self: *const Self) usize {return self.array.dims[1];}
    pub inline fn getFieldsN(self: *const Self) usize {return self.array.dims[2];}

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.array_mem);
        self.array.deinit(allocator);
    }
};

pub fn readCsvToList(outer_alloc: std.mem.Allocator, 
                     io: std.Io,
                     path: []const u8
                     ) !std.ArrayList([]const u8) {

    const cwd: std.Io.Dir = std.Io.Dir.cwd();
    var file: std.Io.File = try cwd.openFile(io, path, .{ .mode = .read_only});
    defer file.close(io);

    var read_buff: [65536]u8 = undefined;    
    var file_reader: std.Io.File.Reader = file.reader(io, &read_buff); 
    const reader = &file_reader.interface;

    // Read lines without the trailing '\n' (exclusive).
    var lines: std.ArrayList([]const u8) = .{};

    while (try reader.takeDelimiter('\n')) |line| {
        const line_trimmed = std.mem.trim(u8, line, " \r\t");
        if (line_trimmed.len == 0) continue;
        const line_dup = try outer_alloc.dupe(u8, line_trimmed);
        try lines.append(outer_alloc, line_dup);
    }
    
    return lines;
}

pub fn parseCoords(outer_alloc: std.mem.Allocator,
                   csv_lines: *const std.ArrayList([]const u8), 
                   ) !Coords {

    const coord_count: usize = csv_lines.items.len;
    var coords = try Coords.initAlloc(outer_alloc, coord_count);

    const num_coords: u8 = 3;
    var num_count: u8 = 0;

    for (csv_lines.items, 0..) |line_str, ii| {
        //print("\nParsing line: {}\n", .{ii});
        var split_iter = std.mem.splitScalar(u8, line_str, ',');

        while (split_iter.next()) |num_str| {
            const num: f64 = try std.fmt.parseFloat(f64, num_str);

            coords.mat.set(ii,num_count,num);

            num_count += 1;
            if (num_count >= num_coords) {
                num_count = 0;
                break;
            }
        }
    }

    return coords;
}

pub fn parseConnect(outer_alloc: std.mem.Allocator, 
                    csv_lines: *const std.ArrayList([]const u8)) !Connect {

    const elem_count = csv_lines.items.len;

    var split_iter = std.mem.splitScalar(u8, csv_lines.items[0], ',');
    var nodes_per_elem: u8 = 0;
    while (split_iter.next()) |num_str| {
        _ = num_str;
        nodes_per_elem += 1;
    }

    const connect = try Connect.initAlloc(outer_alloc, elem_count, nodes_per_elem);

    var elem: usize = 0;
    var node: usize = 0;
    for (csv_lines.items, 0..) |line_str, ii| {
        elem = ii;
        node = 0;

        split_iter = std.mem.splitScalar(u8, line_str, ',');

        while (split_iter.next()) |num_str| {
            const num_f: f64 = try std.fmt.parseFloat(f64, num_str);
            const num_i: usize = @intFromFloat(num_f);

            connect.table_mem[elem * nodes_per_elem + node] = num_i;

            node += 1;
        }
    }
    return connect;
}

pub fn getFieldTimeN(csv_lines: *const std.ArrayList([]const u8)) usize {

    var split_iter = std.mem.splitScalar(u8, csv_lines.items[0], ',');
    var time_n: usize = 0;
    while (split_iter.next()) |num_str| {
        _ = num_str;
        time_n += 1;
    }

    return time_n;
}

pub fn parseField(csv_lines: *const std.ArrayList([]const u8), 
                  field: *Field,
                  field_n: usize) !void {

    // Each row is a coordinate
    // Each field csv has row where each column in the row is a time step
    var inds = [_]usize{0,0,0}; // time_n,coord_n,field_n
    inds[2] = field_n;

    for (csv_lines.items, 0..) |line_str, ii| {
        inds[0] = 0;     // time_n
        inds[1] = ii;    // coord_n, each row is a new coord

        var split_iter = std.mem.splitScalar(u8, line_str, ',');

        while (split_iter.next()) |num_str| {
            
            const num_f: f64 = try std.fmt.parseFloat(f64, num_str);
            
            field.array.set(inds[0..],num_f);
          
            inds[0] += 1; // increment time_n as we step along the row
        }
    }
}

pub const SimData = struct {
    coords: Coords,
    connect: Connect,
    field: Field,
};

pub fn load_sim_data(outer_alloc: std.mem.Allocator,
                     io: std.Io,
                     coord_path: []const u8,
                     connect_path: []const u8,
                     field_paths: []const []const u8,
                     ) !SimData {
                     
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const field_n: usize = field_paths.len;
    var time_start = std.Io.Clock.Timestamp.now(io, .awake);
    var time_end = std.Io.Clock.Timestamp.now(io, .awake);

    //--------------------------------------------------------------------------
    // Read and parse coordinates csv file

    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    var lines = try readCsvToList(arena_alloc, io, coord_path);
    const coords = try parseCoords(outer_alloc, &lines);

    time_end = std.Io.Clock.Timestamp.now(io, .awake);

    lines.clearRetainingCapacity();

    //--------------------------------------------------------------------------
    // Read and parse the connectivity table csv file

    // Read the csv file into an array list
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    lines = try readCsvToList(arena_alloc, io, connect_path);
    const connect = try parseConnect(outer_alloc, &lines);

    time_end = std.Io.Clock.Timestamp.now(io, .awake);

    lines.clearRetainingCapacity();

    //--------------------------------------------------------------------------
    // Parse fields

    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    lines = try readCsvToList(arena_alloc, io, field_paths[0]);

    const time_n: usize = getFieldTimeN(&lines);
    const coord_n: usize = lines.items.len;
    var field = try Field.initAlloc(outer_alloc,time_n,coord_n,field_n);   

    try parseField(&lines,&field,0);
    time_end = std.Io.Clock.Timestamp.now(io, .awake);

    lines.clearRetainingCapacity();

    const remaining_field_paths = field_paths[1..];
    for (remaining_field_paths,1..) |field_path,ii| {
    
        time_start = std.Io.Clock.Timestamp.now(io, .awake);

        lines = try readCsvToList(arena_alloc, io, field_path);
        try parseField(&lines,&field,ii);

        time_end = std.Io.Clock.Timestamp.now(io, .awake);

        lines.clearRetainingCapacity();      
    }

    return .{
      .coords = coords,
      .connect = connect,
      .field = field,  
    };
}
