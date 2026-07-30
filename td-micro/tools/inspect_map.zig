const std = @import("std");
const Io = std.Io;

const OracleMap = struct {
    map_schema: u32,
    map: [4]i16,
    cell_fields: []const []const u8,
    cells: []const [7]i16,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const bytes = try Io.Dir.cwd().readFileAlloc(
        io,
        "tests/fixtures/vanilla_seed1_scenario1_map.json",
        gpa,
        .limited(1024 * 1024),
    );
    defer gpa.free(bytes);
    const parsed = try std.json.parseFromSlice(OracleMap, gpa, bytes, .{});
    defer parsed.deinit();

    const width: usize = @intCast(parsed.value.map[2]);
    const height: usize = @intCast(parsed.value.map[3]);
    std.debug.print("    ", .{});
    for (0..width) |x| std.debug.print("{d}", .{x % 10});
    std.debug.print("\n", .{});
    for (0..height) |y| {
        std.debug.print("{d:0>2}  ", .{y});
        for (0..width) |x| {
            const cell = parsed.value.cells[y * width + x];
            const marker: u8 = if (x == 7 and y == 9)
                'S'
            else if (cell[4] == 0)
                '#'
            else if (cell[2] == 0)
                ','
            else
                '.';
            std.debug.print("{c}", .{marker});
        }
        std.debug.print("\n", .{});
    }
}
