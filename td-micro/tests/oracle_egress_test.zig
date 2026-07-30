const std = @import("std");
const td = @import("td_micro");

const OracleEntity = struct {
    kind: u8,
    owner: u8,
    active: u8,
    limbo: u8,
    cell: [2]i16,
    coord: [2]i32,
    head_coord: [2]i32,
    facing: i16,
    mission: i8,
    queued_mission: i8,
    moving: u8,
    speed: u8,
    path_facing: i8,
    destination: u64,
};

const OracleSnapshot = struct {
    decision: u32,
    action: u8,
    actor: u8,
    product: u8,
    target_x: u8,
    target_y: u8,
    frame: u32,
    rng_state: u32,
    entities: []const OracleEntity,
};

const InterruptSnapshot = struct {
    decision: u32,
    frame: u32,
    rng_state: u32,
    cell: [2]i16,
    coord: [2]i16,
    head_coord: [2]i16,
    facing: u8,
    mission: i8,
    queued_mission: i8,
    moving: u8,
    speed: u8,
    path_facing: i8,
    animation: i8,
    animation_stage: u16,
    animation_timer: u8,
    animation_rate: u8,
};

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

fn oracleE1(snapshot: OracleSnapshot) ?OracleEntity {
    for (snapshot.entities) |entity| {
        if (entity.owner == 0 and entity.kind == @intFromEnum(td.ObjectType.e1) and entity.active != 0 and entity.limbo == 0) return entity;
    }
    return null;
}

fn zigE1(world: *const td.World) ?td.state.Infantry {
    for (world.infantry) |infantry| {
        if (infantry.active and infantry.owner == .player and infantry.kind == .e1) return infantry;
    }
    return null;
}

fn expectEgress(expected: OracleEntity, actual: td.state.Infantry) !void {
    try std.testing.expectEqual(expected.cell[0], @as(i16, actual.position.x));
    try std.testing.expectEqual(expected.cell[1], @as(i16, actual.position.y));
    try std.testing.expectEqual(expected.coord[0], actual.coord_x);
    try std.testing.expectEqual(expected.coord[1], actual.coord_y);
    try std.testing.expectEqual(expected.head_coord[0], actual.head_coord_x);
    try std.testing.expectEqual(expected.head_coord[1], actual.head_coord_y);
    try std.testing.expectEqual(expected.facing, actual.facing);
    try std.testing.expectEqual(expected.mission, actual.mission);
    try std.testing.expectEqual(expected.queued_mission, actual.queued_mission);
    try std.testing.expectEqual(expected.moving != 0, actual.moving);
    try std.testing.expectEqual(expected.speed, actual.speed);
    try std.testing.expectEqual(expected.path_facing, actual.path_facing);
    try std.testing.expectEqual(expected.destination != 0, actual.destination_valid);
}

test "first E1 Barracks egress matches Vanilla through arrival" {
    const trace = @embedFile("fixtures/vanilla_seed1_player_e1_e3.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.World.reset(1);
    var compared: usize = 0;
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

        _ = td.step.stepWithEasyAI(&world, try playerAction(oracle));
        if (oracle.rng_state != world.rng_state) {
            std.debug.print(
                "first E1 trace RNG divergence at decision {d}, frame {d}: expected {d}, actual {d}\n",
                .{ oracle.decision, oracle.frame, oracle.rng_state, world.rng_state },
            );
            return error.RngDivergence;
        }
        if (oracle.decision < 188) continue;
        if (oracle.decision > 197) break;

        try std.testing.expectEqual(oracle.frame, world.frame);
        const expected = oracleE1(oracle) orelse return error.MissingOracleE1;
        const actual = zigE1(&world) orelse return error.MissingZigE1;
        expectEgress(expected, actual) catch |err| {
            std.debug.print(
                "E1 egress divergence at decision {d}, frame {d}: expected coord {any}, head {any}, moving {d}, rng {d}; actual coord [{d},{d}], head [{d},{d}], moving {}, rng {d}\n",
                .{
                    oracle.decision,
                    oracle.frame,
                    expected.coord,
                    expected.head_coord,
                    expected.moving,
                    oracle.rng_state,
                    actual.coord_x,
                    actual.coord_y,
                    actual.head_coord_x,
                    actual.head_coord_y,
                    actual.moving,
                    world.rng_state,
                },
            );
            return err;
        };
        compared += 1;
    }
    try std.testing.expectEqual(@as(usize, 10), compared);
}

test "move order interrupts active Barracks egress on Vanilla timing" {
    const trace = @embedFile("fixtures/vanilla_seed1_player_e1_egress_interrupt.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.World.reset(1);
    var decision: u32 = 0;
    var compared: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const parsed = try std.json.parseFromSlice(
            InterruptSnapshot,
            std.testing.allocator,
            line,
            .{},
        );
        defer parsed.deinit();
        const expected = parsed.value;

        while (decision < expected.decision) {
            decision += 1;
            const command: td.Action = switch (decision) {
                1 => .{ .command = .deploy, .actor = 0 },
                23 => .{ .command = .start_build, .product = .power_plant },
                77 => .{ .command = .place, .product = .power_plant, .target_kind = .cell, .target_x = 4, .target_y = 7 },
                92 => .{ .command = .start_build, .product = .barracks },
                146 => .{ .command = .place, .product = .barracks, .target_kind = .cell, .target_x = 6, .target_y = 7 },
                161 => .{ .command = .train, .product = .e1 },
                189 => .{ .command = .move, .actor = 3, .target_kind = .cell, .target_x = 39, .target_y = 21 },
                else => .{},
            };
            _ = td.step.stepWithEasyAI(&world, command);
        }

        const actual = zigE1(&world) orelse return error.MissingZigE1;
        try std.testing.expectEqual(expected.frame, world.frame);
        try std.testing.expectEqual(expected.rng_state, world.rng_state);
        try std.testing.expectEqual(expected.cell[0], @as(i16, actual.position.x));
        try std.testing.expectEqual(expected.cell[1], @as(i16, actual.position.y));
        try std.testing.expectEqual(expected.coord[0], actual.coord_x);
        try std.testing.expectEqual(expected.coord[1], actual.coord_y);
        try std.testing.expectEqual(expected.head_coord[0], actual.head_coord_x);
        try std.testing.expectEqual(expected.head_coord[1], actual.head_coord_y);
        try std.testing.expectEqual(expected.facing, actual.facing);
        try std.testing.expectEqual(expected.mission, actual.mission);
        try std.testing.expectEqual(expected.queued_mission, actual.queued_mission);
        try std.testing.expectEqual(expected.moving != 0, actual.moving);
        try std.testing.expectEqual(expected.speed, actual.speed);
        try std.testing.expectEqual(expected.path_facing, actual.path_facing);
        try std.testing.expectEqual(expected.animation, actual.animation);
        try std.testing.expectEqual(expected.animation_stage, actual.animation_stage);
        try std.testing.expectEqual(expected.animation_timer, actual.animation_timer);
        try std.testing.expectEqual(expected.animation_rate, actual.animation_rate);
        compared += 1;
    }
    try std.testing.expectEqual(@as(usize, 8), compared);
}
