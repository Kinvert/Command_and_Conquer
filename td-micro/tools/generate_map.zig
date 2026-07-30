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

    const source = "tests/fixtures/vanilla_seed1_scenario1_map.json";
    const bytes = try Io.Dir.cwd().readFileAlloc(io, source, gpa, .limited(1024 * 1024));
    defer gpa.free(bytes);
    const parsed = try std.json.parseFromSlice(OracleMap, gpa, bytes, .{});
    defer parsed.deinit();
    try validate(parsed.value);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    try writeZig(io, parsed.value, digest, &digest_hex);
    try writeC(io, parsed.value);
}

fn writeC(io: Io, map: OracleMap) !void {
    var file = try Io.Dir.cwd().createFile(io, "generated/scenario1_tiberium.h", .{});
    defer file.close(io);
    var buffer: [16 * 1024]u8 = undefined;
    var file_writer: Io.File.Writer = .init(file, io, &buffer);
    const writer = &file_writer.interface;

    var count: usize = 0;
    for (map.cells) |cell| {
        if (cell[0] == 5) count += 1;
    }

    try writer.writeAll(
        "/* Generated from tests/fixtures/vanilla_seed1_scenario1_map.json. Do not edit by hand. */\n" ++
            "#ifndef TD_MICRO_SCENARIO1_TIBERIUM_H\n" ++
            "#define TD_MICRO_SCENARIO1_TIBERIUM_H\n" ++
            "#include <stdint.h>\n",
    );
    try writer.print("#define TD_MICRO_INITIAL_TIBERIUM_CELL_COUNT {d}u\n", .{count});
    try writer.writeAll(
        "static const uint16_t TD_MICRO_INITIAL_TIBERIUM_CELLS[TD_MICRO_INITIAL_TIBERIUM_CELL_COUNT] = {\n",
    );
    var emitted: usize = 0;
    const width: usize = @intCast(map.map[2]);
    for (map.cells, 0..) |cell, source_index| {
        if (cell[0] != 5) continue;
        if (emitted % 12 == 0) try writer.writeAll("    ");
        const x = source_index % width;
        const y = source_index / width;
        try writer.print("{d},", .{y * 64 + x});
        emitted += 1;
        if (emitted % 12 == 0 or emitted == count) {
            try writer.writeByte('\n');
        } else {
            try writer.writeByte(' ');
        }
    }
    try writer.writeAll("};\n");
    try writer.writeAll(
        "static const uint8_t TD_MICRO_INITIAL_TIBERIUM_OVERLAYS[TD_MICRO_INITIAL_TIBERIUM_CELL_COUNT] = {\n",
    );
    emitted = 0;
    for (map.cells) |cell| {
        if (cell[0] != 5) continue;
        if (emitted % 16 == 0) try writer.writeAll("    ");
        try writer.print("{d},", .{cell[5]});
        emitted += 1;
        if (emitted % 16 == 0 or emitted == count) {
            try writer.writeByte('\n');
        } else {
            try writer.writeByte(' ');
        }
    }
    try writer.writeAll("};\n");
    try writer.writeAll(
        "static const uint8_t TD_MICRO_INITIAL_TIBERIUM_DATA[TD_MICRO_INITIAL_TIBERIUM_CELL_COUNT] = {\n",
    );
    emitted = 0;
    for (map.cells) |cell| {
        if (cell[0] != 5) continue;
        if (emitted % 16 == 0) try writer.writeAll("    ");
        try writer.print("{d},", .{cell[6]});
        emitted += 1;
        if (emitted % 16 == 0 or emitted == count) {
            try writer.writeByte('\n');
        } else {
            try writer.writeByte(' ');
        }
    }
    try writer.writeAll("};\n#endif\n");
    try writer.flush();
}

fn validate(map: OracleMap) !void {
    if (map.map_schema != 1) return error.UnsupportedSchema;
    if (map.map[2] <= 0 or map.map[3] <= 0 or map.map[2] > 64 or map.map[3] > 64) {
        return error.InvalidDimensions;
    }
    const expected_cells: usize = @intCast(map.map[2] * map.map[3]);
    if (map.cells.len != expected_cells) return error.InvalidCellCount;

    const expected_fields = [_][]const u8{
        "land",
        "foot_cost",
        "ground_buildable",
        "static_blocked",
        "foot_passable",
        "overlay",
        "overlay_data",
    };
    if (map.cell_fields.len != expected_fields.len) return error.InvalidCellFields;
    for (map.cell_fields, expected_fields) |actual, expected| {
        if (!std.mem.eql(u8, actual, expected)) return error.InvalidCellFields;
    }
    for (map.cells) |cell| {
        if (cell[0] < 0 or cell[0] > 255 or cell[1] < 0 or cell[1] > 255 or cell[2] < 0 or cell[2] > 1 or cell[3] < 0 or cell[3] > 1 or cell[4] < 0 or cell[4] > 1 or cell[6] < 0 or cell[6] > 255) {
            return error.InvalidCellValue;
        }
    }
}

fn writeZig(io: Io, map: OracleMap, digest: [32]u8, digest_hex: []const u8) !void {
    var file = try Io.Dir.cwd().createFile(io, "generated/scenario1_map.zig", .{});
    defer file.close(io);
    var buffer: [64 * 1024]u8 = undefined;
    var file_writer: Io.File.Writer = .init(file, io, &buffer);
    const writer = &file_writer.interface;

    try writer.writeAll("// Generated from tests/fixtures/vanilla_seed1_scenario1_map.json. Do not edit by hand.\n");
    try writer.print("pub const fixture_sha256_hex = \"{s}\";\n", .{digest_hex});
    try writer.writeAll("pub const fixture_sha256 = [_]u8{\n");
    for (digest, 0..) |byte, index| {
        if (index % 8 == 0) try writer.writeAll("    ");
        try writer.print("0x{x:0>2},", .{byte});
        if (index % 8 == 7) try writer.writeByte('\n') else try writer.writeByte(' ');
    }
    try writer.writeAll("};\n\n");
    try writer.print("pub const origin_x: i16 = {d};\n", .{map.map[0]});
    try writer.print("pub const origin_y: i16 = {d};\n", .{map.map[1]});
    try writer.print("pub const width: u8 = {d};\n", .{map.map[2]});
    try writer.print("pub const height: u8 = {d};\n\n", .{map.map[3]});
    try writer.writeAll(
        \\pub const Cell = struct {
        \\    land_type: u8,
        \\    foot_cost: u8,
        \\    ground_buildable: bool,
        \\    static_blocked: bool,
        \\    foot_passable: bool,
        \\    overlay: i16,
        \\    overlay_data: u8,
        \\};
        \\
        \\pub const cells = [_]Cell{
        \\
    );
    for (map.cells) |cell| {
        try writer.print(
            "    .{{ .land_type = {d}, .foot_cost = {d}, .ground_buildable = {s}, .static_blocked = {s}, .foot_passable = {s}, .overlay = {d}, .overlay_data = {d} }},\n",
            .{
                cell[0],
                cell[1],
                if (cell[2] != 0) "true" else "false",
                if (cell[3] != 0) "true" else "false",
                if (cell[4] != 0) "true" else "false",
                cell[5],
                cell[6],
            },
        );
    }
    try writer.writeAll(
        \\};
        \\
        \\pub fn at(x: u8, y: u8) ?Cell {
        \\    if (x >= width or y >= height) return null;
        \\    return cells[@as(usize, y) * width + x];
        \\}
        \\
    );
    try writer.flush();
}
