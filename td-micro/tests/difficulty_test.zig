const std = @import("std");
const td = @import("td_micro");

test "requested skirmish difficulty maps to Westwood computer handicap" {
    try std.testing.expectEqual(@as(u8, 2), td.difficulty.internalHandicap(.easy));
    try std.testing.expectEqual(@as(u8, 1), td.difficulty.internalHandicap(.normal));
    try std.testing.expectEqual(@as(u8, 0), td.difficulty.internalHandicap(.hard));

    try std.testing.expectEqual(td.difficulty.Requested.easy, td.difficulty.fromInternalHandicap(2).?);
    try std.testing.expectEqual(td.difficulty.Requested.normal, td.difficulty.fromInternalHandicap(1).?);
    try std.testing.expectEqual(td.difficulty.Requested.hard, td.difficulty.fromInternalHandicap(0).?);
    try std.testing.expectEqual(@as(?td.difficulty.Requested, null), td.difficulty.fromInternalHandicap(3));
}

test "Westwood 16.16 difficulty multiplication preserves constructor truncation" {
    // fixed(9, 10) is just below 0.9, so this tie rounds down in Vanilla.
    try std.testing.expectEqual(@as(i32, 13), td.difficulty.scale(15, td.rules.difficulty_handicaps[2].firepower_bias));
    try std.testing.expectEqual(@as(i32, 15), td.difficulty.scale(15, td.rules.difficulty_handicaps[1].firepower_bias));
    try std.testing.expectEqual(@as(i32, 16), td.difficulty.scale(15, td.rules.difficulty_handicaps[0].firepower_bias));
    try std.testing.expectEqual(@as(i32, 80), td.difficulty.scale(100, td.rules.difficulty_handicaps[0].cost_bias));
    try std.testing.expectEqual(@as(i32, 105), td.difficulty.scale(100, td.rules.difficulty_handicaps[2].armor_bias));
}

test "CNC25 difficulty curriculum retains anchors and ramps deterministically" {
    const ramp = 10_000;
    try std.testing.expectEqual(@as(u8, 10), td.difficulty.normalPercent(0, ramp));
    try std.testing.expectEqual(@as(u8, 50), td.difficulty.normalPercent(ramp / 2, ramp));
    try std.testing.expectEqual(@as(u8, 90), td.difficulty.normalPercent(ramp, ramp));
    try std.testing.expectEqual(@as(u8, 90), td.difficulty.normalPercent(ramp * 2, ramp));

    const checkpoints = [_]struct { decisions: u64, expected_normal: usize }{
        .{ .decisions = 0, .expected_normal = 10 },
        .{ .decisions = ramp / 2, .expected_normal = 50 },
        .{ .decisions = ramp, .expected_normal = 90 },
    };
    for (checkpoints) |checkpoint| {
        var normal_count: usize = 0;
        for (0..100) |episode| {
            const selected = td.difficulty.forProgress(
                .easy_to_normal,
                1,
                0,
                episode,
                checkpoint.decisions,
                ramp,
            );
            normal_count += @intFromBool(selected == .normal);
        }
        try std.testing.expectEqual(checkpoint.expected_normal, normal_count);
    }
}

test "fixed difficulty schedules select exactly one requested level" {
    try std.testing.expectEqual(
        td.difficulty.Requested.easy,
        td.difficulty.forProgress(.fixed_easy, 1, 7, 11, 999, 1),
    );
    try std.testing.expectEqual(
        td.difficulty.Requested.normal,
        td.difficulty.forProgress(.fixed_normal, 1, 7, 11, 999, 1),
    );
    try std.testing.expectEqual(
        td.difficulty.Requested.hard,
        td.difficulty.forProgress(.fixed_hard, 1, 7, 11, 999, 1),
    );
    try std.testing.expect(td.difficulty.configValid(.fixed_easy, 0));
    try std.testing.expect(td.difficulty.configValid(.fixed_normal, 0));
    try std.testing.expect(td.difficulty.configValid(.fixed_hard, 0));
    try std.testing.expect(!td.difficulty.configValid(.fixed_easy, 1));
    try std.testing.expect(!td.difficulty.configValid(.fixed_normal, 1));
    try std.testing.expect(!td.difficulty.configValid(.fixed_hard, 1));
    try std.testing.expect(!td.difficulty.configValid(.easy_to_normal, 0));
    try std.testing.expect(td.difficulty.configValid(.easy_to_normal, 1));
}

test "difficulty scaling is enabled explicitly and only handicaps the opponent" {
    var world = td.World.reset(1);
    try std.testing.expect(!td.difficulty.isEnabled(&world));
    try std.testing.expectEqual(@as(i32, 300), td.difficulty.cost(&world, .opponent, 300));
    try std.testing.expectEqual(@as(u8, 5), td.difficulty.rotationRate(&world, .opponent, 5));

    td.difficulty.enable(&world, .easy);
    try std.testing.expect(td.difficulty.isEnabled(&world));
    try std.testing.expectEqual(td.difficulty.Requested.easy, td.difficulty.requested(&world));
    try std.testing.expectEqual(@as(i16, 13), td.difficulty.firepower(&world, .opponent, 15));
    try std.testing.expectEqual(@as(u8, 18), td.difficulty.groundSpeed(&world, .opponent, 20));
    try std.testing.expectEqual(@as(u8, 21), td.difficulty.rof(&world, .opponent, 20));
    try std.testing.expectEqual(@as(i16, 16), td.difficulty.armorDamage(&world, .opponent, 15));
    try std.testing.expectEqual(@as(i32, 300), td.difficulty.cost(&world, .opponent, 300));
    try std.testing.expectEqual(@as(i16, 15), td.difficulty.firepower(&world, .player, 15));
    try std.testing.expectEqual(@as(u8, 4), td.difficulty.rotationRate(&world, .opponent, 5));
    try std.testing.expectEqual(@as(u8, 5), td.difficulty.rotationRate(&world, .player, 5));

    td.difficulty.enable(&world, .hard);
    try std.testing.expectEqual(td.difficulty.Requested.hard, td.difficulty.requested(&world));
    try std.testing.expectEqual(@as(i16, 16), td.difficulty.firepower(&world, .opponent, 15));
    try std.testing.expectEqual(@as(u8, 22), td.difficulty.groundSpeed(&world, .opponent, 20));
    try std.testing.expectEqual(@as(u8, 16), td.difficulty.rof(&world, .opponent, 20));
    try std.testing.expectEqual(@as(i32, 240), td.difficulty.cost(&world, .opponent, 300));
    // FacingClass receives an integer conversion of 5 * 1.1, which truncates to 5.
    try std.testing.expectEqual(@as(u8, 5), td.difficulty.rotationRate(&world, .opponent, 5));
}

test "AI production queue charges the selected stock difficulty cost" {
    var world = td.World.reset(1);
    td.difficulty.enable(&world, .hard);
    try std.testing.expect(world.addBuilding(.opponent, .construction_yard, .{ .x = 20, .y = 20 }));
    world.buildings[0].operational = true;

    try std.testing.expect(td.production.applyAI(&world, .opponent, .{
        .command = .start_build,
        .product = .power_plant,
    }));
    try std.testing.expectEqual(@as(i32, 240), world.queues[1][0].balance);
    // Time_To_Build uses raw cost; difficulty changes purchase price, not this rate.
    try std.testing.expectEqual(@as(u8, 2), world.queues[1][0].rate);
}

test "opponent combat uses selected firepower ROF and armor biases" {
    var easy = td.combat.e1DuelFixture();
    td.difficulty.enable(&easy, .easy);
    try std.testing.expect(td.input.apply(&easy, .opponent, .{
        .command = .attack,
        .actor = 1,
        .target_kind = .visible_enemy,
        .target_slot = 1,
    }));
    const player_health = easy.infantry[0].health;
    for (0..32) |_| {
        td.step.tickFrame(&easy);
        if (easy.infantry[0].health != player_health) break;
    }
    try std.testing.expectEqual(player_health - 13, easy.infantry[0].health);
    try std.testing.expect(easy.infantry[1].weapon_cooldown <= 24);

    var armored = td.combat.e1DuelFixture();
    td.difficulty.enable(&armored, .easy);
    try std.testing.expect(td.input.apply(&armored, .player, .{
        .command = .attack,
        .actor = 1,
        .target_kind = .visible_enemy,
        .target_slot = 1,
    }));
    const opponent_health = armored.infantry[1].health;
    for (0..32) |_| {
        td.step.tickFrame(&armored);
        if (armored.infantry[1].health != opponent_health) break;
    }
    try std.testing.expectEqual(opponent_health - 16, armored.infantry[1].health);
}

test "CNC25 observation identifies requested opponent difficulty" {
    var world = td.World.reset(1);
    td.difficulty.enable(&world, .normal);
    var observation: [td.policy.observation_size]u8 = undefined;
    td.policy.observe(&world, &observation);

    try std.testing.expectEqual(@as(u8, 7), td.policy.observation_version);
    try std.testing.expectEqual(
        @as(u8, @intFromEnum(td.difficulty.Requested.normal)),
        observation[td.policy.opponent_difficulty_offset],
    );

    var neutral = td.World.reset(1);
    td.policy.observe(&neutral, &observation);
    try std.testing.expectEqual(
        @as(u8, @intFromEnum(td.difficulty.Requested.normal)),
        observation[td.policy.opponent_difficulty_offset],
    );
}

test "CNC25 batch assigns exact deterministic Easy and Normal episode shares" {
    const count = 100;
    var batch = try td.batch.Batch.initWithConfigs(
        std.testing.allocator,
        count,
        12_000,
        .{},
        .reverse_curriculum,
        4_096,
        8_192,
        .easy_to_normal,
        10_000,
    );
    defer batch.deinit(std.testing.allocator);
    var seeds = [_]u64{1} ** count;
    try batch.reset(&seeds);

    var easy_count: usize = 0;
    var normal_count: usize = 0;
    for (batch.worlds) |world| {
        try std.testing.expect(td.difficulty.isEnabled(&world));
        switch (td.difficulty.requested(&world)) {
            .easy => easy_count += 1,
            .normal => normal_count += 1,
            .hard => return error.UnexpectedHardEpisode,
        }
    }
    try std.testing.expectEqual(@as(usize, 90), easy_count);
    try std.testing.expectEqual(@as(usize, 10), normal_count);
}

test "difficulty snapshot preserves exact ramp continuation and rejects mismatched config" {
    var source = try td.batch.Batch.initWithConfigs(
        std.testing.allocator,
        2,
        512,
        .{},
        .reverse_curriculum,
        4_096,
        8_192,
        .easy_to_normal,
        20_000,
    );
    defer source.deinit(std.testing.allocator);
    var restored = try td.batch.Batch.initWithConfigs(
        std.testing.allocator,
        2,
        512,
        .{},
        .reverse_curriculum,
        4_096,
        8_192,
        .easy_to_normal,
        20_000,
    );
    defer restored.deinit(std.testing.allocator);
    var incompatible = try td.batch.Batch.initWithConfigs(
        std.testing.allocator,
        2,
        512,
        .{},
        .reverse_curriculum,
        4_096,
        8_192,
        .easy_to_normal,
        20_001,
    );
    defer incompatible.deinit(std.testing.allocator);
    try source.reset(&[_]u64{ 1, 2 });
    try restored.reset(&[_]u64{ 1, 2 });
    source.difficulty_decisions[0] = 7_777;
    source.difficulty_decisions[1] = 12_345;

    const snapshot = try std.testing.allocator.alloc(u8, source.snapshotSize());
    defer std.testing.allocator.free(snapshot);
    try source.writeSnapshot(snapshot);
    try restored.readSnapshot(snapshot);
    try std.testing.expectError(error.IncompatibleSnapshot, incompatible.readSnapshot(snapshot));
    try std.testing.expectEqualSlices(
        u64,
        source.difficulty_decisions,
        restored.difficulty_decisions,
    );
}

test "full-match terminal stats retain four balanced cells per difficulty" {
    var batch = try td.batch.Batch.initWithConfigs(
        std.testing.allocator,
        8,
        0,
        .{},
        .full_match,
        0,
        0,
        .fixed_easy,
        0,
    );
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{ 1, 1, 2, 2, 1, 1, 2, 2 });

    for (batch.worlds, 0..) |*world, index| {
        world.easy_ai.active = false;
        world.starting_force = if (index % 2 == 0) .mcv_only else .reduced_unit_count_6;
        td.difficulty.enable(world, if (index < 4) .easy else .normal);
        world.players[@intFromEnum(td.Owner.opponent)].defeated = true;
    }

    var observations: [8 * td.policy.observation_size]u8 = undefined;
    var masks: [8 * td.policy_abi14.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0} ** 8;
    var terminals = [_]u8{0} ** 8;
    batch.stepAbi14(
        &([_]td.policy_abi14.RawAction{.{}} ** 8),
        &observations,
        &masks,
        &rewards,
        &terminals,
    );

    inline for (.{
        batch.stats.easy_close_mcv_episodes,
        batch.stats.easy_close_mcv_wins,
        batch.stats.easy_close_force_episodes,
        batch.stats.easy_close_force_wins,
        batch.stats.easy_medium_mcv_episodes,
        batch.stats.easy_medium_mcv_wins,
        batch.stats.easy_medium_force_episodes,
        batch.stats.easy_medium_force_wins,
        batch.stats.normal_close_mcv_episodes,
        batch.stats.normal_close_mcv_wins,
        batch.stats.normal_close_force_episodes,
        batch.stats.normal_close_force_wins,
        batch.stats.normal_medium_mcv_episodes,
        batch.stats.normal_medium_mcv_wins,
        batch.stats.normal_medium_force_episodes,
        batch.stats.normal_medium_force_wins,
    }) |value| {
        try std.testing.expectEqual(@as(u64, 1), value);
    }
}
