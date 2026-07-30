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
    health: i16,
    facing: i16,
    mission: i8,
    queued_mission: i8,
    moving: u8,
    speed: u8,
    path_facing: i8,
    new_destination: u8,
    destination: u64,
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
    rng_state: u32,
    map: [4]i16,
    entities: []const OracleEntity,
};

fn oracleE1ForOwner(snapshot: OracleSnapshot, owner: td.Owner) ?OracleEntity {
    for (snapshot.entities) |entity| {
        if (entity.owner == @intFromEnum(owner) and entity.kind == @intFromEnum(td.ObjectType.e1) and entity.active != 0 and entity.limbo == 0) return entity;
    }
    return null;
}

fn oracleE1(snapshot: OracleSnapshot) ?OracleEntity {
    return oracleE1ForOwner(snapshot, .player);
}

fn zigE1ForOwner(world: *td.World, owner: td.Owner) ?*td.state.Infantry {
    for (&world.infantry) |*infantry| {
        if (infantry.active and infantry.owner == owner and infantry.kind == .e1) return infantry;
    }
    return null;
}

fn zigE1(world: *td.World) ?*td.state.Infantry {
    return zigE1ForOwner(world, .player);
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
        @intFromEnum(td.Command.move) => .{
            .command = .move,
            .actor = snapshot.actor,
            .target_kind = .cell,
            .target_x = snapshot.target_x,
            .target_y = snapshot.target_y,
        },
        else => error.UnsupportedRecordedAction,
    };
}

fn expectMovement(expected: OracleEntity, actual: td.state.Infantry) !void {
    try std.testing.expectEqual(expected.cell[0], @as(i16, actual.position.x));
    try std.testing.expectEqual(expected.cell[1], @as(i16, actual.position.y));
    try std.testing.expectEqual(expected.coord[0], actual.coord_x);
    try std.testing.expectEqual(expected.coord[1], actual.coord_y);
    try std.testing.expectEqual(expected.head_coord[0], actual.head_coord_x);
    try std.testing.expectEqual(expected.head_coord[1], actual.head_coord_y);
    // Guard can run RNG-driven Random_Animate after movement has completed.
    if (expected.mission != 4) try std.testing.expectEqual(expected.facing, actual.facing);
    try std.testing.expectEqual(expected.mission, actual.mission);
    try std.testing.expectEqual(expected.queued_mission, actual.queued_mission);
    try std.testing.expectEqual(expected.moving != 0, actual.moving);
    try std.testing.expectEqual(expected.speed, actual.speed);
    try std.testing.expectEqual(expected.path_facing, actual.path_facing);
    try std.testing.expectEqual(expected.destination != 0, actual.destination_valid);
}

fn expectTrace(trace: []const u8, first_decision: u32, last_decision: u32) !void {
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

        const opponent_action = td.Action{
            .command = if (oracle.decision == 1) .deploy else .noop,
            .actor = 0,
        };
        td.step.step(&world, try playerAction(oracle), opponent_action);

        const expected = oracleE1(oracle) orelse continue;
        const actual = zigE1(&world) orelse return error.MissingE1;
        if (oracle.decision >= first_decision) {
            try std.testing.expectEqual(oracle.frame, world.frame);
            expectMovement(expected, actual.*) catch |err| {
                std.debug.print("E1 movement divergence at decision {d}\n", .{oracle.decision});
                return err;
            };
            compared += 1;
        }
        if (oracle.decision == last_decision) break;
    }
    try std.testing.expectEqual(@as(usize, last_decision - first_decision + 1), compared);
}

fn expectDifficultyMovementTrace(
    trace: []const u8,
    selected: td.difficulty.Requested,
) !void {
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.combat.e1DuelFixture();
    td.difficulty.enable(&world, selected);
    var action_applied = false;
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

        if (oracle.decision != 0 and !action_applied) {
            try std.testing.expect(td.input.apply(&world, .opponent, .{
                .command = .move,
                .actor = 1,
                .target_kind = .cell,
                .target_x = 30,
                .target_y = 20,
            }));
            action_applied = true;
        }
        while (world.frame < oracle.frame) td.step.tickFrame(&world);

        const expected = oracleE1ForOwner(oracle, .opponent) orelse return error.MissingOracleE1;
        const actual = zigE1ForOwner(&world, .opponent) orelse return error.MissingE1;
        try std.testing.expectEqual(oracle.frame, world.frame);
        if (oracle.frame == 0) try std.testing.expectEqual(oracle.rng_state, world.rng_state);
        expectMovement(expected, actual.*) catch |err| {
            std.debug.print(
                "{s} E1 movement divergence at frame {d}\n",
                .{ @tagName(selected), oracle.frame },
            );
            return err;
        };
        compared += 1;
    }
    try std.testing.expectEqual(@as(usize, 26), compared);
}

test "opponent E1 movement matches Vanilla at every stock difficulty" {
    try expectDifficultyMovementTrace(
        @embedFile("fixtures/vanilla_seed1_difficulty_easy_e1_move.jsonl"),
        .easy,
    );
    try expectDifficultyMovementTrace(
        @embedFile("fixtures/vanilla_seed1_difficulty_normal_e1_move.jsonl"),
        .normal,
    );
    try expectDifficultyMovementTrace(
        @embedFile("fixtures/vanilla_seed1_difficulty_hard_e1_move.jsonl"),
        .hard,
    );
}

test "E1 straight movement matches Vanilla at every decision boundary" {
    try expectTrace(@embedFile("fixtures/vanilla_seed1_player_e1_move.jsonl"), 245, 275);
}

test "E1 obstacle route matches Vanilla at every decision boundary" {
    try expectTrace(@embedFile("fixtures/vanilla_seed1_player_e1_obstacle.jsonl"), 245, 350);
}

test "assigning a new attack destination stops the active infantry driver" {
    var infantry = td.state.Infantry{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 5, .y = 11 },
        .coord_x = 1_428,
        .coord_y = 2_862,
        .head_coord_x = 1_600,
        .head_coord_y = 2_752,
        .speed = 255,
        .path_facing = 1,
        .path = .{ 1, 1, 1, -1, -1, -1, -1, -1, -1 },
        .animation = 3,
        .animation_stage = 2,
        .animation_timer = 1,
        .animation_rate = 2,
        .destination = .{ .x = 14, .y = 0 },
        .destination_valid = true,
        .moving = true,
    };

    td.movement.assignNavigation(&infantry, .{ .x = 14, .y = 0 });

    try std.testing.expect(!infantry.moving);
    try std.testing.expectEqual(@as(i16, 0), infantry.head_coord_x);
    try std.testing.expectEqual(@as(i16, 0), infantry.head_coord_y);
    try std.testing.expectEqual(@as(u8, 0), infantry.speed);
    try std.testing.expectEqual(@as(i8, -1), infantry.path_facing);
    try std.testing.expectEqual(@as(i8, -1), infantry.path[0]);
    try std.testing.expectEqual(@as(i8, 0), infantry.animation);
    try std.testing.expectEqual(@as(u16, 0), infantry.animation_stage);
    try std.testing.expectEqual(@as(u8, 0), infantry.animation_timer);
    try std.testing.expectEqual(@as(u8, 0), infantry.animation_rate);
}

test "a player move command clears the infantry combat target" {
    var world = td.combat.e1DuelFixture();
    world.infantry[0].target = .{ .kind = .e1, .owner = .opponent, .index = 1 };

    try std.testing.expect(td.movement.apply(&world, .player, .{
        .command = .move,
        .actor = 1,
        .target_kind = .cell,
        .target_x = 10,
        .target_y = 10,
    }));

    try std.testing.expect(!world.infantry[0].target.valid());
}

test "entering the first cell releases an interrupted Barracks tether" {
    var world = td.World.reset(1);
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 5, .y = 11 },
        .coord_x = 1_594,
        .coord_y = 2_755,
        .head_coord_x = 1_600,
        .head_coord_y = 2_752,
        .speed = 255,
        .path_facing = 1,
        .path = .{ 1, 1, -1, -1, -1, -1, -1, -1, -1 },
        .destination = .{ .x = 14, .y = 0 },
        .moving = true,
        .tethered = true,
        .health = 50,
    };
    world.infantry_count = 1;

    const frame = td.movement.tick(&world);

    try std.testing.expect(frame.entered_cell[0]);
    try std.testing.expectEqual(td.state.Position{ .x = 6, .y = 10 }, world.infantry[0].position);
    try std.testing.expect(!world.infantry[0].tethered);
}

test "a tethered infantry waits for an uninterruptible animation before egress" {
    var world = td.World.reset(1);
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 5, .y = 11 },
        .coord_x = 1_344,
        .coord_y = 2_944,
        .facing = 96,
        .queued_mission = 2,
        .destination = .{ .x = 5, .y = 12 },
        .destination_valid = true,
        .pending_move = true,
        .tethered = true,
        .animation = 30,
        .animation_timer = 1,
        .animation_rate = 2,
        .health = 50,
    };
    world.infantry_count = 1;

    _ = td.movement.tick(&world);

    try std.testing.expect(world.infantry[0].pending_move);
    try std.testing.expect(!world.infantry[0].moving);
    try std.testing.expectEqual(@as(u8, 96), world.infantry[0].facing);
}

test "infantry replans when a Harvester reserves its cached next cell" {
    var world = td.World.reset(1);
    for (&world.units) |*unit| unit.active = false;
    try std.testing.expect(world.addBuilding(.opponent, .construction_yard, .{ .x = 14, .y = 0 }));
    try std.testing.expect(world.addBuilding(.opponent, .power_plant, .{ .x = 16, .y = 3 }));
    try std.testing.expect(world.addBuilding(.opponent, .barracks, .{ .x = 14, .y = 3 }));
    try std.testing.expect(world.addBuilding(.opponent, .refinery, .{ .x = 17, .y = 0 }));
    try std.testing.expect(world.addBuilding(.player, .construction_yard, .{ .x = 1, .y = 7 }));
    try std.testing.expect(world.addBuilding(.player, .power_plant, .{ .x = 4, .y = 7 }));
    try std.testing.expect(world.addBuilding(.player, .refinery, .{ .x = 6, .y = 7 }));

    world.units[0] = .{
        .active = true,
        .kind = .harvester,
        .owner = .opponent,
        .position = .{ .x = 17, .y = 2 },
        .coord_x = 4_480,
        .coord_y = 640,
        .head_coord_x = 4_736,
        .head_coord_y = 1_152,
        .health = 600,
        .facing = 128,
        .path_facing = 2,
        .track_number = 35,
        .track_index = 0,
        .speed = 160,
        .destination = .{ .x = 33, .y = 6 },
        .destination_valid = true,
        .moving = true,
    };
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .opponent,
        .position = .{ .x = 16, .y = 2 },
        .coord_x = 4_224,
        .coord_y = 640,
        .health = 50,
        .mission = 13,
        .path_facing = 3,
        .path = .{ 3, 3, 2, 3, -1, -1, -1, -1, -1 },
        .destination = .{ .x = 2, .y = 7 },
        .destination_valid = true,
    };
    world.infantry[1] = .{
        .active = true,
        .kind = .e1,
        .owner = .opponent,
        .position = .{ .x = 15, .y = 2 },
        .coord_x = 3_946,
        .coord_y = 698,
        .head_coord_x = 4_224,
        .head_coord_y = 640,
        .health = 50,
        .mission = 13,
        .path_facing = 2,
        .path = .{ 2, 3, 3, 2, 3, -1, -1, -1, -1 },
        .destination = .{ .x = 2, .y = 7 },
        .destination_valid = true,
        .moving = true,
    };
    world.infantry[2] = .{
        .active = true,
        .kind = .e1,
        .owner = .opponent,
        .position = .{ .x = 15, .y = 5 },
        .coord_x = 3_904,
        .coord_y = 1_344,
        .health = 50,
        .mission = 9,
    };
    world.infantry_count = 3;

    _ = td.movement.tick(&world);

    try std.testing.expect(world.infantry[0].moving);
    try std.testing.expectEqual(@as(i8, 6), world.infantry[0].path[0]);
    try std.testing.expectEqual(@as(i8, 6), world.infantry[0].path_facing);
}
