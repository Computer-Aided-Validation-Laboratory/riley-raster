pub const SubpxDomain = struct {
    step: f64,
    offset: f64,
    tile_size: usize,
    x_off: f64,
    y_off: f64,
};

pub const RasterBounds = struct {
    start_x: usize,
    end_x: usize,
    start_y: usize,
    end_y: usize,
    x_min_f: f64,
    y_min_f: f64,
};
