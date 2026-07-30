const std = @import("std");
const td = @import("td_micro");

test "policy ABI has a frozen multidiscrete and byte-observation shape" {
    try std.testing.expectEqual(@as(u32, 13), td.policy.abi_version);
    try std.testing.expectEqual(@as(u8, 7), td.policy.observation_version);
    try std.testing.expectEqualSlices(
        u16,
        &[_]u16{ 12, 65, 65, 65 },
        &td.policy.action_head_sizes,
    );
    try std.testing.expectEqual(@as(usize, 4), td.policy.action_head_count);
    try std.testing.expectEqual(@as(usize, 1_156), td.policy.action_mask_size);
    try std.testing.expectEqual(@as(usize, 344), td.policy.tiberium_cell_count);
    try std.testing.expectEqual(@as(usize, 3_992), td.policy.observation_size);
    try std.testing.expectEqual(@as(u8, 64), td.policy.actor_none);
}

test "raw policy products decode to stable TD object ids" {
    const world = td.World.reset(1);
    const power = td.policy.decode(&world, .{
        .command = @intFromEnum(td.Command.start_build),
        .arg0 = @intFromEnum(td.policy.Product.power_plant),
    }).?;
    try std.testing.expectEqual(td.Command.start_build, power.command);
    try std.testing.expectEqual(td.ObjectType.power_plant, power.product);

    try std.testing.expect(td.policy.decode(&world, .{ .command = 12 }) == null);
    try std.testing.expect(td.policy.decode(&world, .{
        .command = @intFromEnum(td.Command.deploy),
        .arg0 = 65,
    }) == null);
    try std.testing.expect(td.policy.decode(&world, .{
        .command = @intFromEnum(td.Command.move),
        .arg0 = 0,
        .arg1 = 64,
        .arg2 = 0,
    }) == null);
}

test "economy observation exposes Harvester state while the action mask protects it" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(.player, .construction_yard, .{ .x = 1, .y = 7 }));
    world.buildings[0].construction_frames = 0;
    world.buildings[0].operational = true;
    world.players[0].power = 30;
    try std.testing.expect(world.addBuilding(.player, .power_plant, .{ .x = 4, .y = 7 }));
    world.buildings[1].construction_frames = 0;
    td.production.tick(&world);

    var mask: [td.policy.action_mask_size]u8 = undefined;
    td.policy.actionMask(&world, &mask);
    try std.testing.expect(td.policy.argumentAllowed(
        &mask,
        .start_build,
        0,
        td.policy.pad_token,
        @intFromEnum(td.policy.Product.refinery),
    ));

    try std.testing.expect(world.addBuilding(.player, .refinery, .{ .x = 7, .y = 7 }));
    world.buildings[2].construction_frames = 0;
    td.production.tick(&world);
    const harvester = &world.units[2];
    harvester.cargo_steps = 14;
    harvester.harvesting = true;
    world.players[0].tiberium = 125;
    world.players[0].harvested_credits = 250;

    var observation: [td.policy.observation_size]u8 = undefined;
    td.policy.observe(&world, &observation);
    try std.testing.expectEqual(@as(u8, 5), observation[26]);
    try std.testing.expectEqual(@as(u8, 40), observation[27]);
    try std.testing.expectEqual(@as(u8, 10), observation[28]);
    const own = td.policy.ownEntityBytes(&observation);
    const record = own[td.policy.entity_record_size..][0..td.policy.entity_record_size];
    try std.testing.expectEqual(@intFromEnum(td.ObjectType.harvester), record[td.policy.entity_type]);
    try std.testing.expectEqual(@as(u8, 127), record[td.policy.entity_progress]);
    try std.testing.expect(record[td.policy.entity_flags] & 4 != 0);

    td.policy.actionMask(&world, &mask);
    try std.testing.expect(!td.policy.commandAllowed(&mask, .move));
    try std.testing.expect(!td.policy.commandAllowed(&mask, .harvest));
    try std.testing.expect(!td.policy.commandAllowed(&mask, .return_cargo));
}

test "observation is deterministic and excludes private Easy AI state" {
    var first = td.World.reset(1);
    var second = first;
    second.easy_ai.attack_timer +%= 17;
    second.easy_ai.build_infantry = .e3;
    second.players[1].credits -= 777;

    var first_obs: [td.policy.observation_size]u8 = undefined;
    var second_obs: [td.policy.observation_size]u8 = undefined;
    td.policy.observe(&first, &first_obs);
    td.policy.observe(&second, &second_obs);
    try std.testing.expectEqualSlices(u8, &first_obs, &second_obs);

    first.units[1].health -= 1;
    td.policy.observe(&first, &first_obs);
    try std.testing.expect(!std.mem.eql(u8, &first_obs, &second_obs));
}

test "compact map observation preserves canonical Tiberium presence" {
    var world = td.World.reset(1);
    var observation: [td.policy.observation_size]u8 = undefined;
    td.policy.observe(&world, &observation);
    try std.testing.expectEqual(td.map.scenario_id, observation[td.policy.scenario_id_offset]);

    const cells = td.policy.tiberiumBytes(&observation);
    try std.testing.expectEqual(@as(usize, 344), cells.len);
    for (cells) |present| try std.testing.expectEqual(@as(u8, 45), present);

    const first = td.policy.initial_tiberium_positions[0];
    const last = td.policy.initial_tiberium_positions[td.policy.tiberium_cell_count - 1];
    try std.testing.expect(first.y < last.y or (first.y == last.y and first.x < last.x));

    world.clearTiberium(first);
    td.policy.observe(&world, &observation);
    try std.testing.expectEqual(@as(u8, 56), td.policy.tiberiumBytes(&observation)[0]);

    world.setTiberium(first, 1);
    td.policy.observe(&world, &observation);
    try std.testing.expectEqual(@as(u8, 45), td.policy.tiberiumBytes(&observation)[0]);
}

test "compact observation is a deterministic projection of the executable-validated legacy ABI" {
    var world = td.World.reset(2);
    _ = td.step.stepWithEasyAI(&world, .{ .command = .deploy, .actor = 0 });
    world.clearTiberium(td.policy.initial_tiberium_positions[17]);

    const before = td.digest.canonical(&world);
    var compact: [td.policy.observation_size]u8 = undefined;
    var legacy: [td.policy.legacy_observation_size]u8 = undefined;
    td.policy.observe(&world, &compact);
    td.policy.observeLegacyV4(&world, &legacy);
    const after = td.digest.canonical(&world);

    try std.testing.expectEqualSlices(u8, &before, &after);
    const compact_own = td.policy.ownEntityBytes(&compact);
    const compact_enemy = td.policy.enemyEntityBytes(&compact);
    const legacy_own = td.policy.legacyOwnEntityBytes(&legacy);
    const legacy_enemy = td.policy.legacyEnemyEntityBytes(&legacy);
    for (0..td.policy.entity_slot_count) |slot| {
        try std.testing.expectEqualSlices(
            u8,
            legacy_own[slot * td.policy.legacy_entity_record_size ..][0..td.policy.legacy_entity_record_size],
            compact_own[slot * td.policy.entity_record_size ..][0..td.policy.legacy_entity_record_size],
        );
        try std.testing.expectEqualSlices(
            u8,
            legacy_enemy[slot * td.policy.legacy_entity_record_size ..][0..td.policy.legacy_entity_record_size],
            compact_enemy[slot * td.policy.entity_record_size ..][0..td.policy.legacy_entity_record_size],
        );
    }
    for (td.policy.initial_tiberium_positions, 0..) |position, index| {
        const legacy_index = td.policy.legacy_map_offset +
            @as(usize, position.y) * td.policy.map_side + position.x;
        const expected: u8 = if ((legacy[legacy_index] & td.policy.map_land_mask) == 5) 45 else 56;
        try std.testing.expectEqual(expected, td.policy.tiberiumBytes(&compact)[index]);
    }
}

test "reset action mask exposes deploy and pads coordinates outside the map" {
    const world = td.World.reset(1);
    var mask: [td.policy.action_mask_size]u8 = undefined;
    td.policy.actionMask(&world, &mask);

    try std.testing.expect(td.policy.commandAllowed(&mask, .noop));
    try std.testing.expect(td.policy.commandAllowed(&mask, .deploy));
    try std.testing.expect(!td.policy.commandAllowed(&mask, .start_build));
    try std.testing.expect(!td.policy.commandAllowed(&mask, .train));

    try std.testing.expect(td.policy.argumentAllowed(&mask, .deploy, 0, td.policy.pad_token, 0));
    try std.testing.expect(!td.policy.argumentAllowed(&mask, .deploy, 0, td.policy.pad_token, 1));
    try std.testing.expect(!td.policy.argumentAllowed(
        &mask,
        .deploy,
        0,
        td.policy.pad_token,
        td.policy.actor_none,
    ));

    try std.testing.expect(td.policy.argumentAllowed(&mask, .move, 1, 0, world.map_width - 1));
    try std.testing.expect(!td.policy.argumentAllowed(&mask, .move, 1, 0, world.map_width));
    try std.testing.expect(td.policy.argumentAllowed(&mask, .move, 2, 0, world.map_height - 1));
    try std.testing.expect(!td.policy.argumentAllowed(&mask, .move, 2, 0, world.map_height));
}

test "entity slots use stable unit building infantry order" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(.player, .power_plant, .{ .x = 4, .y = 7 }));
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 8, .y = 9 },
        .health = 50,
    };
    world.infantry_count = 1;

    var obs: [td.policy.observation_size]u8 = undefined;
    td.policy.observe(&world, &obs);
    const own = td.policy.ownEntityBytes(&obs);
    try std.testing.expectEqual(@as(u8, 1), own[0 * td.policy.entity_record_size + td.policy.entity_presence]);
    try std.testing.expectEqual(
        @intFromEnum(td.ObjectType.mcv),
        own[0 * td.policy.entity_record_size + td.policy.entity_type],
    );
    try std.testing.expectEqual(
        @intFromEnum(td.ObjectType.power_plant),
        own[1 * td.policy.entity_record_size + td.policy.entity_type],
    );
    try std.testing.expectEqual(
        @intFromEnum(td.ObjectType.e1),
        own[2 * td.policy.entity_record_size + td.policy.entity_type],
    );
    for ([_]td.ObjectType{ .mcv, .power_plant, .e1 }, 0..) |kind, slot| {
        const record = own[slot * td.policy.entity_record_size ..][0..td.policy.entity_record_size];
        for (0..td.policy.entity_type_count) |type_index| {
            const expected: u8 = if (type_index == @intFromEnum(kind)) 255 else 0;
            try std.testing.expectEqual(
                expected,
                record[td.policy.entity_type_one_hot_offset + type_index],
            );
        }
    }
}

test "vehicle observation exposes target reload turret and firing state" {
    var world = td.World.reset(1);
    world.units[2] = .{
        .active = true,
        .kind = .medium_tank,
        .owner = .player,
        .position = .{ .x = 20, .y = 20 },
        .health = td.rules.object(.medium_tank).?.strength,
        .target = .{ .kind = .e3, .owner = .opponent, .index = 0 },
        .turret_facing = 93,
        .weapon_cooldown = 17,
        .firing = true,
    };
    world.infantry[0] = .{
        .active = true,
        .kind = .e3,
        .owner = .opponent,
        .position = .{ .x = 21, .y = 20 },
        .health = td.rules.object(.e3).?.strength,
    };
    world.infantry_count = 1;

    var observation: [td.policy.observation_size]u8 = undefined;
    td.policy.observe(&world, &observation);
    const tank = td.policy.ownEntityBytes(&observation)[td.policy.entity_record_size..][0..td.policy.entity_record_size];
    try std.testing.expectEqual(@intFromEnum(td.ObjectType.medium_tank), tank[td.policy.entity_type]);
    try std.testing.expectEqual(@as(u8, 3), tank[td.policy.entity_target_kind]);
    try std.testing.expectEqual(@as(u8, 1), tank[td.policy.entity_target_slot]);
    try std.testing.expectEqual(@as(u8, 17), tank[td.policy.entity_cooldown]);
    try std.testing.expectEqual(@as(u8, 93), tank[td.policy.entity_progress]);
    try std.testing.expect(tank[td.policy.entity_flags] & 8 != 0);
}

test "ABI13 exposes Weapons Factory and vehicle production" {
    var world = td.curriculum.reset(1, .h2_armour);
    try std.testing.expectEqual(td.state.Failure.none, world.failure);

    var mask: [td.policy.action_mask_size]u8 = undefined;
    td.policy.actionMask(&world, &mask);
    try std.testing.expect(td.policy.commandAllowed(&mask, .start_build));
    try std.testing.expect(td.policy.argumentAllowed(
        &mask,
        .start_build,
        0,
        td.policy.pad_token,
        @intFromEnum(td.policy.Product.medium_tank),
    ));
    try std.testing.expect(td.policy.argumentAllowed(
        &mask,
        .start_build,
        0,
        td.policy.pad_token,
        @intFromEnum(td.policy.Product.humvee),
    ));

    const decoded_tank = td.policy.decode(&world, .{
        .command = @intFromEnum(td.action.Command.start_build),
        .arg0 = @intFromEnum(td.policy.Product.medium_tank),
        .arg1 = td.policy.pad_token,
        .arg2 = td.policy.pad_token,
    }).?;
    try std.testing.expectEqual(td.ObjectType.medium_tank, decoded_tank.product);
    try std.testing.expect(td.production.apply(&world, .player, decoded_tank));
    try std.testing.expectEqual(
        td.ObjectType.medium_tank,
        world.queues[@intFromEnum(td.Owner.player)][@intFromEnum(td.state.QueueKind.unit)].product,
    );
}

test "Easy AI building progress uses Vanilla construction animation phase" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(.opponent, .power_plant, .{ .x = 16, .y = 3 }));
    world.buildings[0].construction_frames = 54;

    var observation: [td.policy.observation_size]u8 = undefined;
    td.policy.observe(&world, &observation);
    const enemy = td.policy.enemyEntityBytes(&observation);
    const power = enemy[td.policy.entity_record_size..][0..td.policy.entity_record_size];
    try std.testing.expectEqual(@intFromEnum(td.ObjectType.power_plant), power[td.policy.entity_type]);
    try std.testing.expectEqual(@as(u8, 13), power[td.policy.entity_progress]);

    try std.testing.expect(world.addBuilding(.opponent, .refinery, .{ .x = 19, .y = 3 }));
    world.buildings[1].construction_frames = 54;
    td.policy.observe(&world, &observation);
    const refinery = td.policy.enemyEntityBytes(&observation)[2 * td.policy.entity_record_size ..][0..td.policy.entity_record_size];
    try std.testing.expectEqual(@intFromEnum(td.ObjectType.refinery), refinery[td.policy.entity_type]);
    try std.testing.expectEqual(@as(u8, 13), refinery[td.policy.entity_progress]);
}

test "compact entity records include the Vanilla Refinery anchor" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(.opponent, .refinery, .{ .x = 19, .y = 3 }));

    var observation: [td.policy.observation_size]u8 = undefined;
    td.policy.observe(&world, &observation);
    const refinery = td.policy.enemyEntityBytes(&observation)[td.policy.entity_record_size..][0..td.policy.entity_record_size];
    try std.testing.expectEqual(@intFromEnum(td.ObjectType.refinery), refinery[td.policy.entity_type]);
    try std.testing.expectEqual(@as(u8, 19), refinery[td.policy.entity_x]);
    try std.testing.expectEqual(@as(u8, 3), refinery[td.policy.entity_y]);
}

test "opponent yard progress reflects whether the player yard already exists" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(.opponent, .construction_yard, .{ .x = 14, .y = 0 }));
    world.buildings[0].construction_frames = 60;

    var observation: [td.policy.observation_size]u8 = undefined;
    td.policy.observe(&world, &observation);
    var enemy_yard = td.policy.enemyEntityBytes(&observation)[td.policy.entity_record_size..][0..td.policy.entity_record_size];
    try std.testing.expectEqual(@as(u8, 20), enemy_yard[td.policy.entity_progress]);

    try std.testing.expect(world.addBuilding(.player, .construction_yard, .{ .x = 1, .y = 7 }));
    td.policy.observe(&world, &observation);
    enemy_yard = td.policy.enemyEntityBytes(&observation)[td.policy.entity_record_size..][0..td.policy.entity_record_size];
    try std.testing.expectEqual(@as(u8, 16), enemy_yard[td.policy.entity_progress]);
}
