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
    completed: u8,
    product: u8,
    stage: u16,
    timer: u8,
    rate: u8,
    balance: i32,
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
    action: u8,
    actor: u8,
    product: u8,
    target_x: u8,
    target_y: u8,
    frame: u32,
    players: []const OraclePlayer,
    queues: []const OracleQueue,
    entities: []const OracleEntity,
};

fn queue(snapshot: OracleSnapshot, category: u8) ?OracleQueue {
    for (snapshot.queues) |candidate| {
        if (candidate.owner == 0 and candidate.category == category) return candidate;
    }
    return null;
}

fn playerAction(snapshot: OracleSnapshot) !td.Action {
    const product: td.ObjectType = @enumFromInt(snapshot.product);
    return switch (snapshot.action) {
        @intFromEnum(td.Command.noop) => .{},
        @intFromEnum(td.Command.deploy) => .{ .command = .deploy, .actor = snapshot.actor },
        @intFromEnum(td.Command.start_build) => .{ .command = .start_build, .product = product },
        @intFromEnum(td.Command.place) => .{
            .command = .place,
            .product = product,
            .target_kind = .cell,
            .target_x = snapshot.target_x,
            .target_y = snapshot.target_y,
        },
        @intFromEnum(td.Command.train) => .{ .command = .train, .product = product },
        else => error.UnsupportedRecordedAction,
    };
}

fn expectQueue(expected: OracleQueue, actual: td.state.ProductionQueue) !void {
    try std.testing.expectEqual(expected.active != 0, actual.active);
    try std.testing.expectEqual(expected.completed != 0, actual.completed);
    try std.testing.expectEqual(expected.product, @intFromEnum(actual.product));
    try std.testing.expectEqual(expected.stage, actual.stage);
    try std.testing.expectEqual(expected.timer, actual.stage_timer);
    try std.testing.expectEqual(expected.rate, actual.rate);
    try std.testing.expectEqual(expected.balance, actual.balance);
}

fn oracleInfantry(snapshot: OracleSnapshot, kind: td.ObjectType) ?OracleEntity {
    for (snapshot.entities) |entity| {
        if (entity.owner == 0 and entity.kind == @intFromEnum(kind) and entity.active != 0 and entity.limbo == 0) return entity;
    }
    return null;
}

fn zigInfantry(world: *const td.World, kind: td.ObjectType) ?td.state.Infantry {
    for (world.infantry) |infantry| {
        if (infantry.active and infantry.owner == .player and infantry.kind == kind) return infantry;
    }
    return null;
}

test "E1 and E3 production and first exit cells match Vanilla" {
    const trace = @embedFile("fixtures/vanilla_seed1_player_e1_e3.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.World.reset(1);
    var checked_e1_exit = false;
    var checked_e3_exit = false;
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
        try expectQueue(queue(oracle, 0) orelse return error.MissingStructureQueue, world.queues[0][0]);
        try expectQueue(queue(oracle, 1) orelse return error.MissingInfantryQueue, world.queues[0][1]);

        inline for (.{ td.ObjectType.e1, td.ObjectType.e3 }) |kind| {
            if (oracleInfantry(oracle, kind)) |expected| {
                const actual = zigInfantry(&world, kind) orelse return error.MissingInfantry;
                try std.testing.expectEqual(expected.health, actual.health);
                const checked = if (kind == .e1) &checked_e1_exit else &checked_e3_exit;
                if (!checked.*) {
                    try std.testing.expectEqual(@as(u8, @intCast(expected.cell[0])), actual.position.x);
                    try std.testing.expectEqual(@as(u8, @intCast(expected.cell[1])), actual.position.y);
                    checked.* = true;
                }
            } else {
                try std.testing.expect(zigInfantry(&world, kind) == null);
            }
        }
    }
    try std.testing.expect(checked_e1_exit);
    try std.testing.expect(checked_e3_exit);
}
