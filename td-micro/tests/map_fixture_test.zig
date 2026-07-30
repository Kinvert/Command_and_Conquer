const std = @import("std");
const td = @import("td_micro");

const OracleMap = struct {
    map_schema: u32,
    map: [4]i16,
    cell_fields: []const []const u8,
    cells: []const [7]i16,
};

test "generated scenario 1 map matches every Vanilla oracle cell" {
    const fixture = @embedFile("fixtures/vanilla_seed1_scenario1_map.json");
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(fixture, &digest, .{});
    try std.testing.expectEqualSlices(u8, &td.map.fixture_sha256, &digest);
    try std.testing.expectEqualStrings(
        "4bb31ef19fd7e091d3d12812b82f39df2aa8530d17af1dbc52d86e0f07078383",
        td.map.fixture_sha256_hex,
    );

    const parsed = try std.json.parseFromSlice(OracleMap, std.testing.allocator, fixture, .{});
    defer parsed.deinit();
    const oracle = parsed.value;
    try std.testing.expectEqual(@as(u32, 1), oracle.map_schema);
    try std.testing.expectEqual(oracle.map[0], td.map.origin_x);
    try std.testing.expectEqual(oracle.map[1], td.map.origin_y);
    try std.testing.expectEqual(@as(u8, @intCast(oracle.map[2])), td.map.width);
    try std.testing.expectEqual(@as(u8, @intCast(oracle.map[3])), td.map.height);
    try std.testing.expectEqual(oracle.cells.len, td.map.cells.len);

    var passable: usize = 0;
    var blocked: usize = 0;
    for (oracle.cells, td.map.cells) |expected, actual| {
        try std.testing.expectEqual(@as(u8, @intCast(expected[0])), actual.land_type);
        try std.testing.expectEqual(@as(u8, @intCast(expected[1])), actual.foot_cost);
        try std.testing.expectEqual(expected[2] != 0, actual.ground_buildable);
        try std.testing.expectEqual(expected[3] != 0, actual.static_blocked);
        try std.testing.expectEqual(expected[4] != 0, actual.foot_passable);
        try std.testing.expectEqual(expected[5], actual.overlay);
        try std.testing.expectEqual(@as(u8, @intCast(expected[6])), actual.overlay_data);
        if (actual.foot_passable) passable += 1 else blocked += 1;
    }
    try std.testing.expect(passable != 0);
    try std.testing.expect(blocked != 0);
}
