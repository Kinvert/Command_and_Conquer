const std = @import("std");
const td = @import("td_micro");

const OraclePlayer = struct {
    id: u8,
    credits: i32,
    power: i32,
    drain: i32,
};

const OracleEntity = struct {
    kind: u8,
    owner: u8,
    active: u8,
    limbo: u8,
    cell: [2]i16,
    health: i16,
    facing: i16,
    mission: i8,
    status: i8,
    deploying: u8,
};

const OracleSnapshot = struct {
    decision: u32,
    action: u8,
    frame: u32,
    players: []const OraclePlayer,
    entities: []const OracleEntity,
};

fn entity(snapshot: OracleSnapshot, owner: td.Owner, kind: td.ObjectType) ?OracleEntity {
    for (snapshot.entities) |candidate| {
        if (candidate.owner == @intFromEnum(owner) and candidate.kind == @intFromEnum(kind) and
            candidate.active != 0 and candidate.limbo == 0) return candidate;
    }
    return null;
}

fn building(world: *const td.World, owner: td.Owner, kind: td.ObjectType) ?td.state.Building {
    for (world.buildings) |candidate| {
        if (candidate.active and candidate.owner == owner and candidate.kind == kind) return candidate;
    }
    return null;
}

fn expectOwnerState(world: *const td.World, oracle: OracleSnapshot, owner: td.Owner) !void {
    const owner_index: usize = @intFromEnum(owner);
    try std.testing.expectEqual(oracle.players[owner_index].credits, world.players[owner_index].credits);
    try std.testing.expectEqual(oracle.players[owner_index].power, world.players[owner_index].power);
    try std.testing.expectEqual(oracle.players[owner_index].drain, world.players[owner_index].drain);

    if (entity(oracle, owner, .mcv)) |expected| {
        const actual = world.units[owner_index];
        try std.testing.expect(actual.active);
        try std.testing.expectEqual(@as(u8, @intCast(expected.cell[0])), actual.position.x);
        try std.testing.expectEqual(@as(u8, @intCast(expected.cell[1])), actual.position.y);
        try std.testing.expectEqual(expected.health, actual.health);
        try std.testing.expectEqual(@as(u8, @intCast(expected.facing)), actual.facing);
        try std.testing.expectEqual(expected.mission, actual.mission);
        try std.testing.expectEqual(@as(u8, @intCast(expected.status)), actual.status);
        try std.testing.expectEqual(expected.deploying != 0, actual.deploying);
        try std.testing.expect(building(world, owner, .construction_yard) == null);
    } else if (entity(oracle, owner, .construction_yard)) |expected| {
        try std.testing.expect(!world.units[owner_index].active);
        const actual = building(world, owner, .construction_yard) orelse return error.MissingConstructionYard;
        try std.testing.expectEqual(@as(u8, @intCast(expected.cell[0])), actual.position.x);
        try std.testing.expectEqual(@as(u8, @intCast(expected.cell[1])), actual.position.y);
        try std.testing.expectEqual(expected.health, actual.health);
    } else {
        return error.MissingSupportedOwnerEntity;
    }
}

test "recorded mirror deploy matches Vanilla through structural completion" {
    const trace = @embedFile("fixtures/vanilla_seed1_mirror_deploy.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();
    _ = lines.next();

    var world = td.World.reset(1);
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const parsed = try std.json.parseFromSlice(
            OracleSnapshot,
            std.testing.allocator,
            line,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        const oracle = parsed.value;
        if (oracle.decision > 6) break;

        const command = td.Action{ .command = if (oracle.action == TD_MICRO_COMMAND_DEPLOY) .deploy else .noop };
        td.step.step(&world, command, command);
        try std.testing.expectEqual(oracle.frame, world.frame);
        try expectOwnerState(&world, oracle, .player);
        try expectOwnerState(&world, oracle, .opponent);
    }
}

const TD_MICRO_COMMAND_DEPLOY: u8 = 1;
