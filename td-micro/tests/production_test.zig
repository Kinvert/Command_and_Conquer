const std = @import("std");
const td = @import("td_micro");

const noop = td.Action{};

fn deployPlayer(world: *td.World) void {
    td.step.step(world, .{ .command = .deploy, .actor = 0 }, noop);
    for (0..21) |_| td.step.step(world, noop, noop);
}

test "deploy replaces the selected MCV with a construction yard" {
    var world = td.World.reset(1);
    const position = world.units[0].position;

    deployPlayer(&world);

    try std.testing.expect(!world.units[0].active);
    try std.testing.expect(world.hasBuilding(.player, .construction_yard));
    try std.testing.expectEqual(position.x - 1, world.buildings[0].position.x);
    try std.testing.expectEqual(position.y - 1, world.buildings[0].position.y);
    try std.testing.expect(world.buildings[0].operational);
    try std.testing.expectEqual(@as(i16, 30), world.players[0].power);
    try std.testing.expectEqual(@as(i16, 15), world.players[0].drain);
}

test "earlier opponent MCV removal skips one player deployment rotation tick" {
    var world = td.World.reset(1);

    _ = td.step.stepWithEasyAI(&world, noop);
    _ = td.step.stepWithEasyAI(&world, .{ .command = .deploy, .actor = 0 });
    try std.testing.expectEqual(@as(u8, 246), world.units[0].facing);

    for ([_]u8{ 226, 206, 186, 171 }) |expected_facing| {
        _ = td.step.stepWithEasyAI(&world, noop);
        try std.testing.expect(world.units[0].active);
        try std.testing.expectEqual(expected_facing, world.units[0].facing);
    }
    var observation: [td.policy.observation_size]u8 = undefined;
    td.policy.observe(&world, &observation);
    const own_mcv = td.policy.ownEntityBytes(&observation)[0..td.policy.entity_record_size];
    try std.testing.expectEqual(@as(u8, 5), own_mcv[td.policy.entity_progress]);

    _ = td.step.stepWithEasyAI(&world, noop);
    try std.testing.expect(!world.units[0].active);
    var has_player_yard = false;
    for (world.buildings) |building| {
        has_player_yard = has_player_yard or
            (building.active and building.owner == .player and building.kind == .construction_yard);
    }
    try std.testing.expect(has_player_yard);
}

test "barracks is rejected until a power plant exists" {
    var world = td.World.reset(1);
    deployPlayer(&world);

    const accepted = td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .barracks,
    });

    try std.testing.expect(!accepted);
    try std.testing.expect(!world.queues[0][0].active);
}

test "power production follows TD's 108 stage installment schedule" {
    var world = td.World.reset(1);
    deployPlayer(&world);

    try std.testing.expect(td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .power_plant,
    }));
    try std.testing.expectEqual(@as(u8, 2), world.queues[0][0].rate);
    try std.testing.expectEqual(@as(i32, 300), world.queues[0][0].balance);

    td.production.tick(&world);
    try std.testing.expectEqual(@as(u8, 0), world.queues[0][0].stage);
    try std.testing.expectEqual(@as(i32, 10_000), world.players[0].credits);

    td.production.tick(&world);
    try std.testing.expectEqual(@as(u8, 1), world.queues[0][0].stage);
    try std.testing.expectEqual(@as(i32, 9_998), world.players[0].credits);
    try std.testing.expectEqual(@as(i32, 298), world.queues[0][0].balance);

    for (0..214) |_| td.production.tick(&world);
    try std.testing.expect(world.queues[0][0].completed);
    try std.testing.expectEqual(@as(u8, 108), world.queues[0][0].stage);
    try std.testing.expectEqual(@as(i32, 9_700), world.players[0].credits);
}

test "Refinery build time excludes its bundled Harvester cost" {
    var world = td.World.reset(1);
    deployPlayer(&world);
    try std.testing.expect(world.addBuilding(.player, .power_plant, .{ .x = 4, .y = 7 }));
    world.buildings[1].operational = true;
    world.players[0].power = 130;
    world.players[0].drain = 15;

    try std.testing.expect(td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .refinery,
    }));
    try std.testing.expectEqual(@as(u8, 5), world.queues[0][0].rate);
    try std.testing.expectEqual(@as(i32, 2_000), world.queues[0][0].balance);
}

test "placing completed power immediately unlocks barracks production" {
    var world = td.World.reset(1);
    deployPlayer(&world);
    try std.testing.expect(td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .power_plant,
    }));
    for (0..216) |_| td.production.tick(&world);

    try std.testing.expect(td.production.apply(&world, .player, .{
        .command = .place,
        .product = .power_plant,
        .target_kind = .cell,
        .target_x = 4,
        .target_y = 7,
    }));
    try std.testing.expect(!world.hasBuilding(.player, .power_plant));
    try std.testing.expectEqual(@as(i16, 130), world.players[0].power);
    try std.testing.expectEqual(@as(i16, 15), world.players[0].drain);
    try std.testing.expect(td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .barracks,
    }));

    for (0..60) |_| td.production.tick(&world);
    try std.testing.expect(world.hasBuilding(.player, .power_plant));
    try std.testing.expect(world.queues[0][0].active);
    try std.testing.expectEqual(td.ObjectType.barracks, world.queues[0][0].product);
}

test "illegal placement preserves the completed production queue" {
    var world = td.World.reset(1);
    deployPlayer(&world);
    world.queues[0][@intFromEnum(td.state.QueueKind.structure)] = .{
        .active = true,
        .completed = true,
        .product = .power_plant,
    };

    try std.testing.expect(!td.production.apply(&world, .player, .{
        .command = .place,
        .product = .power_plant,
        .target_kind = .cell,
        .target_x = 14,
        .target_y = 32,
    }));
    try std.testing.expect(world.queues[0][@intFromEnum(td.state.QueueKind.structure)].completed);
    try std.testing.expectEqual(@as(u8, 1), world.building_count);
}

test "placement requires a cell target and preserves the completed queue" {
    var world = td.World.reset(1);
    deployPlayer(&world);
    world.queues[0][@intFromEnum(td.state.QueueKind.structure)] = .{
        .active = true,
        .completed = true,
        .product = .power_plant,
    };

    try std.testing.expect(!td.production.apply(&world, .player, .{
        .command = .place,
        .product = .power_plant,
        .target_kind = .none,
        .target_x = 4,
        .target_y = 7,
    }));
    try std.testing.expect(world.queues[0][@intFromEnum(td.state.QueueKind.structure)].completed);
    try std.testing.expectEqual(@as(u8, 1), world.building_count);
}

test "completed infantry waits while its Barracks is radio-tethered" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(.player, .barracks, .{ .x = 20, .y = 20 }));
    world.buildings[0].operational = true;
    world.queues[0][@intFromEnum(td.state.QueueKind.infantry)] = .{
        .active = true,
        .completed = true,
        .product = .e1,
    };
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .home = .{ .x = 21, .y = 21 },
        .home_valid = true,
        .tethered = true,
        .health = 50,
    };
    world.infantry_count = 1;

    try std.testing.expect(!td.production.releaseCompletedInfantry(&world, .player));
    try std.testing.expect(world.queues[0][@intFromEnum(td.state.QueueKind.infantry)].completed);
    try std.testing.expectEqual(@as(u8, 1), world.infantry_count);

    world.infantry[0].tethered = false;
    try std.testing.expect(td.production.releaseCompletedInfantry(&world, .player));
    try std.testing.expect(!world.queues[0][@intFromEnum(td.state.QueueKind.infantry)].active);
    try std.testing.expectEqual(@as(u8, 2), world.infantry_count);
}

test "completed infantry waits when the shared infantry array is full" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(.player, .barracks, .{ .x = 20, .y = 20 }));
    world.buildings[0].operational = true;
    world.queues[0][@intFromEnum(td.state.QueueKind.infantry)] = .{
        .active = true,
        .completed = true,
        .product = .e1,
    };
    world.infantry_count = @intCast(td.rules.max_infantry);

    try std.testing.expect(!td.production.releaseCompletedInfantry(&world, .player));
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
    try std.testing.expect(world.queues[0][@intFromEnum(td.state.QueueKind.infantry)].completed);

    world.infantry_count -= 1;
    try std.testing.expect(td.production.releaseCompletedInfantry(&world, .player));
    try std.testing.expect(!world.queues[0][@intFromEnum(td.state.QueueKind.infantry)].active);
    try std.testing.expectEqual(@as(u8, @intCast(td.rules.max_infantry)), world.infantry_count);
}

test "a newly placed second Barracks immediately accelerates player infantry production" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(.player, .barracks, .{ .x = 20, .y = 20 }));
    world.buildings[0].operational = true;
    try std.testing.expect(world.addBuilding(.player, .barracks, .{ .x = 24, .y = 20 }));
    try std.testing.expect(!world.buildings[1].operational);
    world.queues[0][@intFromEnum(td.state.QueueKind.infantry)] = .{
        .active = true,
        .product = .e1,
        .stage = 28,
        .stage_timer = 1,
        .rate = 1,
        .balance = 72,
    };

    td.production.tick(&world);

    try std.testing.expectEqual(
        @as(u8, 30),
        world.queues[0][@intFromEnum(td.state.QueueKind.infantry)].stage,
    );
}

test "completed player infantry exits the last available Barracks" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(.player, .barracks, .{ .x = 20, .y = 20 }));
    world.buildings[0].operational = true;
    try std.testing.expect(world.addBuilding(.player, .barracks, .{ .x = 24, .y = 20 }));
    world.buildings[1].operational = true;
    world.queues[0][@intFromEnum(td.state.QueueKind.infantry)] = .{
        .active = true,
        .completed = true,
        .product = .e1,
    };

    try std.testing.expect(td.production.releaseCompletedInfantry(&world, .player));

    try std.testing.expectEqual(td.state.Position{ .x = 25, .y = 21 }, world.infantry[0].position);
}

test "destroying the last barracks abandons infantry production" {
    var world = td.World.reset(1);
    world.easy_ai.active = false;
    try std.testing.expect(world.addBuilding(.player, .barracks, .{ .x = 20, .y = 20 }));
    world.buildings[0].operational = true;
    world.buildings[0].health = 1;
    world.players[0].credits = 9_901;
    world.queues[0][@intFromEnum(td.state.QueueKind.infantry)] = .{
        .active = true,
        .product = .e1,
        .stage = 107,
        .stage_timer = 1,
        .rate = 1,
        .balance = 1,
    };
    world.projectiles[0] = .{
        .active = true,
        .kind = .bullet,
        .target = .{ .kind = .barracks, .owner = .player, .index = 0 },
        .coord_x = 20 * 256 + 128,
        .coord_y = 20 * 256 + 128,
        .strength = 100,
    };
    world.projectile_order[0] = 0;
    world.projectile_count = 1;

    td.step.tickFrame(&world);

    try std.testing.expect(!world.buildings[0].active);
    try std.testing.expect(!world.queues[0][@intFromEnum(td.state.QueueKind.infantry)].active);
    try std.testing.expectEqual(@as(i32, 10_000), world.players[0].credits);
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
}
