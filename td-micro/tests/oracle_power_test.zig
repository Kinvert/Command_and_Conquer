const std = @import("std");
const td = @import("td_micro");

const OraclePlayer = struct {
    id: u8,
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

const OracleSnapshot = struct {
    decision: u32,
    action: u8,
    actor: u8,
    product: u8,
    frame: u32,
    players: []const OraclePlayer,
    queues: []const OracleQueue,
};

fn structureQueue(snapshot: OracleSnapshot, owner: td.Owner) ?OracleQueue {
    for (snapshot.queues) |queue| {
        if (queue.owner == @intFromEnum(owner) and queue.category == 0) return queue;
    }
    return null;
}

test "player power production matches every recorded Vanilla installment" {
    const trace = @embedFile("fixtures/vanilla_seed1_player_power.jsonl");
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

        var player_action = td.Action{};
        if (oracle.action == @intFromEnum(td.Command.deploy)) {
            player_action = .{ .command = .deploy, .actor = oracle.actor };
        } else if (oracle.action == @intFromEnum(td.Command.start_build)) {
            try std.testing.expectEqual(@as(u8, @intFromEnum(td.ObjectType.power_plant)), oracle.product);
            player_action = .{ .command = .start_build, .product = .power_plant };
        }
        const opponent_action = td.Action{
            .command = if (oracle.decision == 1) .deploy else .noop,
            .actor = 0,
        };
        td.step.step(&world, player_action, opponent_action);

        try std.testing.expectEqual(oracle.frame, world.frame);
        try std.testing.expectEqual(oracle.players[0].credits, world.players[0].credits);
        try std.testing.expectEqual(oracle.players[0].power, world.players[0].power);
        try std.testing.expectEqual(oracle.players[0].drain, world.players[0].drain);

        const expected = structureQueue(oracle, .player) orelse return error.MissingPlayerStructureQueue;
        const actual = world.queues[0][@intFromEnum(td.state.QueueKind.structure)];
        try std.testing.expectEqual(expected.active != 0, actual.active);
        try std.testing.expectEqual(expected.completed != 0, actual.completed);
        try std.testing.expectEqual(expected.product, @intFromEnum(actual.product));
        try std.testing.expectEqual(expected.stage, actual.stage);
        try std.testing.expectEqual(expected.timer, actual.stage_timer);
        try std.testing.expectEqual(expected.rate, actual.rate);
        try std.testing.expectEqual(expected.balance, actual.balance);
    }
}
