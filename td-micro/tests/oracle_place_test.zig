const std = @import("std");
const td = @import("td_micro");

const OraclePlayer = struct {
    credits: i32,
    power: i32,
    drain: i32,
};

const OracleQueue = struct {
    owner: u8,
    category: u8,
    active: u8,
};

const OracleEntity = struct {
    kind: u8,
    owner: u8,
    active: u8,
    limbo: u8,
    cell: [2]i16,
    health: i16,
    mission: i8,
};

const OracleSnapshot = struct {
    decision: u32,
    action: u8,
    actor: u8,
    product: u8,
    target_kind: u8,
    target_x: u8,
    target_y: u8,
    frame: u32,
    players: []const OraclePlayer,
    queues: []const OracleQueue,
    entities: []const OracleEntity,
};

fn playerPower(snapshot: OracleSnapshot) ?OracleEntity {
    for (snapshot.entities) |entity| {
        if (entity.owner == 0 and entity.kind == @intFromEnum(td.ObjectType.power_plant) and entity.active != 0 and entity.limbo == 0) return entity;
    }
    return null;
}

fn zigPower(world: *const td.World) ?td.state.Building {
    for (world.buildings) |building| {
        if (building.active and building.owner == .player and building.kind == .power_plant) return building;
    }
    return null;
}

fn playerAction(snapshot: OracleSnapshot) !td.Action {
    return switch (snapshot.action) {
        @intFromEnum(td.Command.noop) => .{},
        @intFromEnum(td.Command.deploy) => .{ .command = .deploy, .actor = snapshot.actor },
        @intFromEnum(td.Command.start_build) => .{ .command = .start_build, .product = .power_plant },
        @intFromEnum(td.Command.place) => .{
            .command = .place,
            .product = .power_plant,
            .target_kind = .cell,
            .target_x = snapshot.target_x,
            .target_y = snapshot.target_y,
        },
        else => error.UnsupportedRecordedAction,
    };
}

test "Power Plant placement and construction match Vanilla" {
    const trace = @embedFile("fixtures/vanilla_seed1_player_power_place.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
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
        if (oracle.decision == 0) continue;

        const opponent_action = td.Action{
            .command = if (oracle.decision == 1) .deploy else .noop,
            .actor = 0,
        };
        td.step.step(&world, try playerAction(oracle), opponent_action);
        try std.testing.expectEqual(oracle.frame, world.frame);
        try std.testing.expectEqual(oracle.players[0].credits, world.players[0].credits);
        try std.testing.expectEqual(oracle.players[0].power, world.players[0].power);
        try std.testing.expectEqual(oracle.players[0].drain, world.players[0].drain);

        if (playerPower(oracle)) |expected| {
            const actual = zigPower(&world) orelse return error.MissingPowerPlant;
            try std.testing.expectEqual(@as(u8, @intCast(expected.cell[0])), actual.position.x);
            try std.testing.expectEqual(@as(u8, @intCast(expected.cell[1])), actual.position.y);
            try std.testing.expectEqual(expected.health, actual.health);
            try std.testing.expectEqual(expected.mission != 17, actual.operational);
        } else {
            try std.testing.expect(zigPower(&world) == null);
        }
    }
}
