const std = @import("std");
const td = @import("td_micro");

const OraclePlayer = struct {
    id: u8,
    human: u8,
    difficulty: u8,
    credits: i32,
};

const OracleEntity = struct {
    kind: u8,
    owner: u8,
    active: u8,
    limbo: u8,
    cell: [2]i16,
    health: i16,
};

const OracleSnapshot = struct {
    decision: u32,
    frame: u32,
    setup_seed: u32,
    rng_state: u32,
    map: [4]i16,
    players: []const OraclePlayer,
    entities: []const OracleEntity,
};

fn resetSnapshot(allocator: std.mem.Allocator, trace: []const u8) !std.json.Parsed(OracleSnapshot) {
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();
    const reset_line = lines.next() orelse return error.MissingResetSnapshot;
    return std.json.parseFromSlice(OracleSnapshot, allocator, reset_line, .{ .ignore_unknown_fields = true });
}

fn oracleMcv(snapshot: OracleSnapshot, owner: td.Owner) ?OracleEntity {
    for (snapshot.entities) |entity| {
        if (entity.kind == @intFromEnum(td.ObjectType.mcv) and entity.owner == @intFromEnum(owner)) return entity;
    }
    return null;
}

fn expectResetMatchesOracle(seed: u64, bucket: td.map.SpawnBucket, trace: []const u8) !void {
    const parsed = try resetSnapshot(std.testing.allocator, trace);
    defer parsed.deinit();
    const oracle = parsed.value;
    const world = td.World.reset(seed);

    try std.testing.expectEqual(@as(u32, 0), oracle.decision);
    try std.testing.expectEqual(@as(u32, 0), oracle.frame);
    try std.testing.expectEqual(oracle.setup_seed, world.setup_seed);
    try std.testing.expectEqual(bucket, world.spawn_bucket);
    try std.testing.expectEqual(oracle.rng_state, world.rng_state);
    try std.testing.expectEqual(oracle.map[0], world.map_origin_x);
    try std.testing.expectEqual(oracle.map[1], world.map_origin_y);
    try std.testing.expectEqual(@as(u8, @intCast(oracle.map[2])), world.map_width);
    try std.testing.expectEqual(@as(u8, @intCast(oracle.map[3])), world.map_height);
    for (oracle.players, 0..) |player, index| {
        try std.testing.expectEqual(@as(u8, @intCast(index)), player.id);
        try std.testing.expectEqual(player.credits, world.players[index].credits);
    }

    const player_mcv = oracleMcv(oracle, .player) orelse return error.MissingPlayerMcv;
    const opponent_mcv = oracleMcv(oracle, .opponent) orelse return error.MissingOpponentMcv;
    try std.testing.expectEqual(@as(u8, @intCast(player_mcv.cell[0])), world.units[0].position.x);
    try std.testing.expectEqual(@as(u8, @intCast(player_mcv.cell[1])), world.units[0].position.y);
    try std.testing.expectEqual(player_mcv.health, world.units[0].health);
    try std.testing.expectEqual(@as(u8, @intCast(opponent_mcv.cell[0])), world.units[1].position.x);
    try std.testing.expectEqual(@as(u8, @intCast(opponent_mcv.cell[1])), world.units[1].position.y);
    try std.testing.expectEqual(opponent_mcv.health, world.units[1].health);
}

test "close reset matches the Vanilla oracle fixture" {
    try expectResetMatchesOracle(1, .close, @embedFile("fixtures/vanilla_seed1_idle64.jsonl"));
}

test "medium reset matches the Vanilla oracle fixture" {
    try expectResetMatchesOracle(2, .medium, @embedFile("fixtures/vanilla_seed2_idle64.jsonl"));
}
