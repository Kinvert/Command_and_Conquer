const std = @import("std");
const td = @import("td_micro");

test "reverse curriculum traverses H0 through H5 with fixed full-match anchors" {
    // CNC26 threads the h2_armour drill through phases 2, 3 and 4. It shares h2_mobilize's
    // horizon (index 2), so that column carries both and the mid-ladder mix shifted deliberately.
    // Phase 4's full-match share drops from 80 to 60 because armour takes a slice there; the
    // per-phase anchors themselves still exist, which is the property this test protects.
    const expected = [_][6]usize{
        .{ 3, 77, 0, 0, 0, 20 },
        .{ 0, 20, 60, 0, 0, 20 },
        .{ 0, 0, 60, 20, 0, 20 },
        .{ 0, 0, 20, 40, 20, 20 },
        .{ 0, 0, 20, 0, 20, 60 },
        .{ 0, 0, 0, 0, 0, 100 },
    };
    const stage_decisions: u64 = 1_000;
    for (expected, 0..) |expected_counts, phase| {
        var counts = [_]usize{0} ** 6;
        for (0..100) |lane| {
            const profile = td.curriculum.profileForProgress(
                .reverse_curriculum,
                if (lane % 2 == 0) 1 else 2,
                lane,
                0,
                @as(u64, @intCast(phase)) * stage_decisions,
                stage_decisions,
            );
            counts[@intFromEnum(td.curriculum.horizon(profile))] += 1;
        }
        try std.testing.expectEqualSlices(usize, &expected_counts, &counts);
    }
}

test "full-match anchors are present in the real 64-lane training shape" {
    const stage_decisions: u64 = 1_000;
    for (0..5) |phase| {
        var full_matches: usize = 0;
        for (0..64) |lane| {
            const profile = td.curriculum.profileForProgress(
                .reverse_curriculum,
                if (lane % 2 == 0) 1 else 2,
                lane,
                0,
                @as(u64, @intCast(phase)) * stage_decisions,
                stage_decisions,
            );
            if (profile == .full_match) full_matches += 1;
        }
        try std.testing.expect(full_matches > 0);
    }
}

test "curriculum configuration and pure H0 path are deterministic and bounded" {
    try std.testing.expect(td.curriculum.scheduleFromInt(0) == .full_match);
    try std.testing.expect(td.curriculum.scheduleFromInt(1) == .reverse_curriculum);
    try std.testing.expect(td.curriculum.scheduleFromInt(@intFromEnum(td.curriculum.Schedule.h0_test)) == null);
    try std.testing.expect(td.curriculum.configValid(.full_match, 0, 0));
    try std.testing.expect(td.curriculum.configValid(.full_match, 4_096, 99));
    try std.testing.expect(!td.curriculum.configValid(.reverse_curriculum, 0, 8_192));
    try std.testing.expect(!td.curriculum.configValid(.reverse_curriculum, 4_096, 0));
    try std.testing.expect(td.curriculum.configValid(.reverse_curriculum, 4_096, 2_048));
    try std.testing.expect(td.curriculum.configValid(.reverse_curriculum, 4_096, 12_288));

    const first = td.curriculum.profileForProgress(.h0_test, 1, 7, 11, 99, 1);
    const second = td.curriculum.profileForProgress(.h0_test, 1, 7, 11, 99, 1);
    try std.testing.expectEqual(td.curriculum.Horizon.h0_finish, td.curriculum.horizon(first));
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(
        td.curriculum.Profile.full_match,
        td.curriculum.profileForProgress(.full_match, 1, 7, 99, 10_000, 0),
    );
}

test "full-match starting credits use the declared deterministic 35/65 distribution" {
    var constrained_count: usize = 0;
    var constrained_close: usize = 0;
    var constrained_medium: usize = 0;
    for (0..100) |lane| {
        const seed: u64 = if (lane % 2 == 0) 1 else 2;
        const credits = td.curriculum.startingCredits(seed, lane, 0);
        try std.testing.expectEqual(credits, td.curriculum.startingCredits(seed, lane, 0));
        try std.testing.expectEqual(@as(i32, 0), @mod(credits, td.rules.starting_credits_step));
        if (credits == td.rules.starting_credits_constrained) {
            constrained_count += 1;
            if (seed == 1) constrained_close += 1 else constrained_medium += 1;
        } else {
            try std.testing.expect(credits >= td.rules.starting_credits_random_min);
            try std.testing.expect(credits <= td.rules.starting_credits_random_max);
        }
    }
    try std.testing.expectEqual(@as(usize, 35), constrained_count);
    try std.testing.expect(@abs(@as(isize, @intCast(constrained_close)) - @as(isize, @intCast(constrained_medium))) <= 1);
}

test "random full-match credit branch can reach every declared 100-credit value" {
    const value_count: usize = @intCast(
        @divExact(
            td.rules.starting_credits_random_max - td.rules.starting_credits_random_min,
            td.rules.starting_credits_step,
        ) + 1,
    );
    var seen = [_]bool{false} ** value_count;
    for (0..256) |episode_ordinal| {
        for (0..100) |lane| {
            const credits = td.curriculum.startingCredits(1, lane, episode_ordinal);
            if (credits == td.rules.starting_credits_constrained) continue;
            const value_index: usize = @intCast(@divExact(
                credits - td.rules.starting_credits_random_min,
                td.rules.starting_credits_step,
            ));
            seen[value_index] = true;
        }
    }
    for (seen) |was_seen| try std.testing.expect(was_seen);
}

test "starting credit sampling remains bounded at ordinal wraparound" {
    const credits = td.curriculum.startingCredits(
        std.math.maxInt(u64),
        std.math.maxInt(usize),
        std.math.maxInt(u64),
    );
    try std.testing.expect(
        credits == td.rules.starting_credits_constrained or
            (credits >= td.rules.starting_credits_random_min and
                credits <= td.rules.starting_credits_random_max),
    );
}

test "full-match starting forces use an exact independent 50/50 distribution" {
    var force_count: usize = 0;
    var force_close: usize = 0;
    var force_medium: usize = 0;
    var constrained_force: usize = 0;
    for (0..100) |lane| {
        const seed: u64 = if (lane % 2 == 0) 1 else 2;
        const force = td.curriculum.startingForce(lane, 0);
        try std.testing.expectEqual(force, td.curriculum.startingForce(lane, 0));
        if (force == .reduced_unit_count_6) {
            force_count += 1;
            if (seed == 1) force_close += 1 else force_medium += 1;
            if (td.curriculum.startingCredits(seed, lane, 0) ==
                td.rules.starting_credits_constrained)
            {
                constrained_force += 1;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 50), force_count);
    try std.testing.expectEqual(@as(usize, 25), force_close);
    try std.testing.expectEqual(@as(usize, 25), force_medium);
    try std.testing.expect(constrained_force > 0);
    try std.testing.expect(constrained_force < td.rules.starting_credits_constrained_percent);

    var constrained_mcv_cycle: usize = 0;
    var constrained_force_cycle: usize = 0;
    var random_mcv_cycle: usize = 0;
    var random_force_cycle: usize = 0;
    for (0..100) |lane| {
        for (0..100) |episode_ordinal| {
            const constrained =
                td.curriculum.startingCredits(1, lane, episode_ordinal) ==
                td.rules.starting_credits_constrained;
            const has_force =
                td.curriculum.startingForce(lane, episode_ordinal) ==
                .reduced_unit_count_6;
            if (constrained and has_force) {
                constrained_force_cycle += 1;
            } else if (constrained) {
                constrained_mcv_cycle += 1;
            } else if (has_force) {
                random_force_cycle += 1;
            } else {
                random_mcv_cycle += 1;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 1_750), constrained_mcv_cycle);
    try std.testing.expectEqual(@as(usize, 1_750), constrained_force_cycle);
    try std.testing.expectEqual(@as(usize, 3_250), random_mcv_cycle);
    try std.testing.expectEqual(@as(usize, 3_250), random_force_cycle);
}

test "reverse curriculum force ramp uses an independent decision clock" {
    const cases = [_]struct {
        ramp_decisions: u64,
        decisions: u64,
        expected_force_count: usize,
    }{
        .{ .ramp_decisions = 500, .decisions = 0, .expected_force_count = 25 },
        .{ .ramp_decisions = 500, .decisions = 250, .expected_force_count = 50 },
        .{ .ramp_decisions = 500, .decisions = 500, .expected_force_count = 75 },
        .{ .ramp_decisions = 2_000, .decisions = 1_000, .expected_force_count = 50 },
        .{ .ramp_decisions = 2_000, .decisions = 2_000, .expected_force_count = 75 },
        .{ .ramp_decisions = 3_000, .decisions = 1_500, .expected_force_count = 50 },
        .{ .ramp_decisions = 3_000, .decisions = 3_000, .expected_force_count = 75 },
        .{ .ramp_decisions = 3_000, .decisions = 5_000, .expected_force_count = 75 },
    };
    for (cases) |case| {
        var force_count: usize = 0;
        for (0..100) |lane| {
            const force = td.curriculum.startingForceForProgress(
                .reverse_curriculum,
                lane,
                0,
                case.decisions,
                case.ramp_decisions,
            );
            if (force == .reduced_unit_count_6) force_count += 1;
        }
        try std.testing.expectEqual(case.expected_force_count, force_count);
    }

    try std.testing.expect(
        td.curriculum.profileForProgress(.reverse_curriculum, 1, 0, 0, 1_000, 500) !=
            td.curriculum.profileForProgress(.reverse_curriculum, 1, 0, 0, 1_000, 5_000),
    );
}

test "full-match evaluation keeps the fixed 50/50 force distribution" {
    var force_count: usize = 0;
    for (0..100) |lane| {
        const force = td.curriculum.startingForceForProgress(
            .full_match,
            lane,
            0,
            std.math.maxInt(u64),
            0,
        );
        if (force == .reduced_unit_count_6) force_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 50), force_count);
}

test "each lane receives exactly half force starts over one hundred episodes" {
    for (0..8) |lane| {
        var force_count: usize = 0;
        for (0..100) |episode_ordinal| {
            if (td.curriculum.startingForce(lane, episode_ordinal) ==
                .reduced_unit_count_6)
            {
                force_count += 1;
            }
        }
        try std.testing.expectEqual(@as(usize, 50), force_count);
    }
}

test "episode reset randomizes only full matches and gives both sides equal credits" {
    const fixed = td.curriculum.reset(1, .full_match);
    try std.testing.expectEqual(td.rules.initial_credits, fixed.players[0].credits);
    try std.testing.expectEqual(td.rules.initial_credits, fixed.players[1].credits);
    try std.testing.expectEqual(td.state.StartingForce.mcv_only, fixed.starting_force);
    try std.testing.expectEqual(@as(usize, 0), countPlayerInfantry(&fixed));

    const full = td.curriculum.resetForEpisode(1, .full_match, 0, 0);
    try std.testing.expectEqual(td.curriculum.startingCredits(1, 0, 0), full.players[0].credits);
    try std.testing.expectEqual(full.players[0].credits, full.players[1].credits);
    try std.testing.expectEqual(td.curriculum.startingForce(0, 0), full.starting_force);
    const full_counts = countActiveInfantry(&full);
    try std.testing.expectEqual(@as(usize, 3), full_counts.player_e1);
    try std.testing.expectEqual(@as(usize, 3), full_counts.player_e3);
    try std.testing.expectEqual(@as(usize, 3), full_counts.opponent_e1);
    try std.testing.expectEqual(@as(usize, 3), full_counts.opponent_e3);

    const authored = td.curriculum.reset(1, .h3_economy);
    const scheduled = td.curriculum.resetForEpisode(1, .h3_economy, 0, 0);
    try std.testing.expectEqualSlices(u8, &td.digest.canonical(&authored), &td.digest.canonical(&scheduled));
    try std.testing.expectEqual(td.state.StartingForce.mcv_only, scheduled.starting_force);
}

test "starting infantry are symmetric legal idle guards outside both MCV footprints" {
    const world = td.curriculum.resetForEpisode(1, .full_match, 0, 0);
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
    try std.testing.expectEqual(td.state.StartingForce.reduced_unit_count_6, world.starting_force);

    for (world.infantry[0..world.infantry_count]) |infantry| {
        try std.testing.expect(infantry.active);
        try std.testing.expect(infantry.kind == .e1 or infantry.kind == .e3);
        try std.testing.expectEqual(@as(i8, 4), infantry.mission);
        try std.testing.expectEqual(@as(i8, -1), infantry.queued_mission);
        try std.testing.expect(!infantry.target.valid());
        try std.testing.expect(td.map.footPassable(infantry.position));
        const mcv = if (infantry.owner == .player) world.units[0] else world.units[1];
        const dx = @abs(@as(i16, infantry.position.x) - @as(i16, mcv.position.x));
        const dy = @abs(@as(i16, infantry.position.y) - @as(i16, mcv.position.y));
        try std.testing.expect(@max(dx, dy) >= 3);
    }
}

test "reverse curriculum is applied per batch lane and advances by decisions" {
    var batch = try td.batch.Batch.initWithCurriculum(
        std.testing.allocator,
        100,
        2,
        .{},
        .reverse_curriculum,
        2,
        4,
    );
    defer batch.deinit(std.testing.allocator);

    var seeds: [100]u64 = undefined;
    for (&seeds, 0..) |*seed, lane| seed.* = if (lane % 2 == 0) 1 else 2;
    try batch.reset(&seeds);

    var initial_counts = [_]usize{0} ** 6;
    for (batch.profiles, 0..) |profile, lane| {
        initial_counts[@intFromEnum(td.curriculum.horizon(profile))] += 1;
        if (profile == .full_match) {
            try std.testing.expectEqual(
                td.curriculum.startingForceForProgress(
                    .reverse_curriculum,
                    lane,
                    0,
                    0,
                    4,
                ),
                batch.worlds[lane].starting_force,
            );
        }
    }
    try std.testing.expectEqualSlices(usize, &[_]usize{ 3, 77, 0, 0, 0, 20 }, &initial_counts);

    const observations = try std.testing.allocator.alloc(u8, 100 * td.policy.observation_size);
    defer std.testing.allocator.free(observations);
    const masks = try std.testing.allocator.alloc(u8, 100 * td.policy_abi9.action_mask_size);
    defer std.testing.allocator.free(masks);
    const actions = try std.testing.allocator.alloc(td.policy_abi9.RawAction, 100);
    defer std.testing.allocator.free(actions);
    const rewards = try std.testing.allocator.alloc(f32, 100);
    defer std.testing.allocator.free(rewards);
    const terminals = try std.testing.allocator.alloc(u8, 100);
    defer std.testing.allocator.free(terminals);
    @memset(actions, .{});
    batch.stepAbi9(actions, observations, masks, rewards, terminals);
    batch.stepAbi9(actions, observations, masks, rewards, terminals);

    try std.testing.expectEqualSlices(u64, &([_]u64{2} ** 100), batch.curriculum_decisions);
    var next_counts = [_]usize{0} ** 6;
    for (batch.profiles, 0..) |profile, lane| {
        next_counts[@intFromEnum(td.curriculum.horizon(profile))] += 1;
        if (profile == .full_match) {
            try std.testing.expectEqual(
                td.curriculum.startingForceForProgress(
                    .reverse_curriculum,
                    lane,
                    1,
                    2,
                    4,
                ),
                batch.worlds[lane].starting_force,
            );
        }
    }
    try std.testing.expectEqualSlices(usize, &[_]usize{ 0, 20, 60, 0, 0, 20 }, &next_counts);
    try std.testing.expectEqual(@as(u64, 20), batch.stats.close_episodes + batch.stats.medium_episodes);
}

test "all H0 through H5 reset recipes expose their declared starting capability" {
    const cases = [_]struct {
        profile: td.curriculum.Profile,
        player_buildings: usize,
        player_infantry: usize,
        opponent_infantry: usize,
        player_harvesters: usize,
        player_mcv: usize,
        expected_credits: i32,
    }{
        .{ .profile = .h0_finish_mixed, .player_buildings = 1, .player_infantry = 16, .opponent_infantry = 0, .player_harvesters = 0, .player_mcv = 0, .expected_credits = 0 },
        .{ .profile = .h1_assault_mixed, .player_buildings = 1, .player_infantry = 16, .opponent_infantry = 4, .player_harvesters = 0, .player_mcv = 0, .expected_credits = 0 },
        .{ .profile = .h2_mobilize, .player_buildings = 4, .player_infantry = 0, .opponent_infantry = 0, .player_harvesters = 1, .player_mcv = 0, .expected_credits = 1_200 },
        .{ .profile = .h3_economy, .player_buildings = 3, .player_infantry = 0, .opponent_infantry = 0, .player_harvesters = 1, .player_mcv = 0, .expected_credits = 300 },
        .{ .profile = .h4_opening, .player_buildings = 1, .player_infantry = 0, .opponent_infantry = 0, .player_harvesters = 0, .player_mcv = 0, .expected_credits = td.rules.initial_credits },
        .{ .profile = .full_match, .player_buildings = 0, .player_infantry = 0, .opponent_infantry = 0, .player_harvesters = 0, .player_mcv = 1, .expected_credits = td.rules.initial_credits },
    };

    for (cases) |case| {
        const first = td.curriculum.reset(2, case.profile);
        const second = td.curriculum.reset(2, case.profile);
        try std.testing.expectEqual(td.state.Failure.none, first.failure);
        try std.testing.expectEqualSlices(u8, &td.digest.canonical(&first), &td.digest.canonical(&second));
        try std.testing.expectEqual(case.player_buildings, countActiveBuildings(&first, .player));
        try std.testing.expectEqual(case.player_infantry, countPlayerInfantry(&first));
        const infantry = countActiveInfantry(&first);
        try std.testing.expectEqual(case.opponent_infantry, infantry.opponent_e1 + infantry.opponent_e3);
        try std.testing.expectEqual(case.player_harvesters, countActiveUnits(&first, .player, .harvester));
        try std.testing.expectEqual(case.player_mcv, countActiveUnits(&first, .player, .mcv));
        try std.testing.expectEqual(case.expected_credits, first.players[@intFromEnum(td.Owner.player)].credits);
    }
}

test "counter-matchup assault profiles are deterministic and expose legal typed attacks" {
    const e3_first = td.curriculum.reset(2, .h1_e3_vs_tank);
    const e3_second = td.curriculum.reset(2, .h1_e3_vs_tank);
    try std.testing.expectEqual(td.state.Failure.none, e3_first.failure);
    try std.testing.expectEqualSlices(
        u8,
        &td.digest.canonical(&e3_first),
        &td.digest.canonical(&e3_second),
    );
    try std.testing.expectEqual(@as(usize, 12), countActiveInfantry(&e3_first).player_e3);
    try std.testing.expectEqual(
        @as(usize, 2),
        countActiveUnits(&e3_first, .opponent, .medium_tank),
    );

    var e3_mask: [td.policy.action_mask_size]u8 = undefined;
    td.policy.actionMask(&e3_first, &e3_mask);
    try std.testing.expect(td.policy.commandAllowed(&e3_mask, .attack));
    // Player slot 0 is the yard; the first E3 is slot 1. Enemy slot 0 is a Medium Tank.
    try std.testing.expect(td.policy.argumentAllowed(&e3_mask, .attack, 0, 0, 1));
    try std.testing.expect(td.policy.argumentAllowed(&e3_mask, .attack, 1, 1, 0));
    try std.testing.expect(td.policy.decode(&e3_first, .{
        .command = @intFromEnum(td.action.Command.attack),
        .arg0 = 1,
        .arg1 = 0,
        .arg2 = td.policy.pad_token,
    }) != null);

    const tank_first = td.curriculum.reset(2, .h1_tank_vs_e3);
    const tank_second = td.curriculum.reset(2, .h1_tank_vs_e3);
    try std.testing.expectEqual(td.state.Failure.none, tank_first.failure);
    try std.testing.expectEqualSlices(
        u8,
        &td.digest.canonical(&tank_first),
        &td.digest.canonical(&tank_second),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        countActiveUnits(&tank_first, .player, .medium_tank),
    );
    try std.testing.expectEqual(@as(usize, 8), countActiveInfantry(&tank_first).opponent_e3);

    var tank_mask: [td.policy.action_mask_size]u8 = undefined;
    td.policy.actionMask(&tank_first, &tank_mask);
    try std.testing.expect(td.policy.commandAllowed(&tank_mask, .attack));
    // Player slot 0 is a Medium Tank. Enemy slot 0 is the yard and slot 1 is the first E3.
    try std.testing.expect(td.policy.argumentAllowed(&tank_mask, .attack, 0, 0, 0));
    try std.testing.expect(td.policy.argumentAllowed(&tank_mask, .attack, 1, 0, 1));
    try std.testing.expect(td.policy.decode(&tank_first, .{
        .command = @intFromEnum(td.action.Command.attack),
        .arg0 = 0,
        .arg1 = 1,
        .arg2 = td.policy.pad_token,
    }) != null);
}

test "H0 finish reset is deterministic and starts every attacker idle" {
    const first = td.curriculum.reset(2, .h0_finish_mixed);
    const second = td.curriculum.reset(2, .h0_finish_mixed);
    try std.testing.expectEqualSlices(u8, &td.digest.canonical(&first), &td.digest.canonical(&second));
    try std.testing.expectEqual(td.state.Failure.none, first.failure);
    try std.testing.expectEqual(@as(u32, 0), first.frame);
    try std.testing.expectEqual(@as(u16, 0), first.projectile_count);

    const counts = countActiveInfantry(&first);
    try std.testing.expectEqual(@as(usize, 8), counts.player_e1);
    try std.testing.expectEqual(@as(usize, 8), counts.player_e3);
    try std.testing.expectEqual(@as(usize, 0), counts.opponent_e1 + counts.opponent_e3);
    try std.testing.expectEqual(@as(usize, 1), countActiveBuildings(&first, .player));
    try std.testing.expectEqual(@as(usize, 1), countActiveBuildings(&first, .opponent));

    for (first.infantry[0..first.infantry_count]) |infantry| {
        if (!infantry.active or infantry.owner != .player) continue;
        try std.testing.expectEqual(@as(i8, 4), infantry.mission);
        try std.testing.expectEqual(@as(i8, -1), infantry.queued_mission);
        try std.testing.expect(!infantry.target.valid());
        try std.testing.expect(!infantry.attack_pending);
        try std.testing.expect(!infantry.firing);
    }
}

test "H0 finish no-op cannot inherit a free win or setup reward" {
    var batch = try td.batch.Batch.initWithCurriculum(
        std.testing.allocator,
        1,
        512,
        .{},
        .h0_test,
        1,
        1,
    );
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy_abi9.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    for (0..256) |_| {
        batch.stepAbi9(
            &[_]td.policy_abi9.RawAction{.{}},
            &observations,
            &masks,
            &rewards,
            &terminals,
        );
        try std.testing.expectEqual(@as(f32, 0), rewards[0]);
        try std.testing.expectEqual(@as(u8, 0), terminals[0]);
    }
    try std.testing.expectEqual(@as(u64, 0), batch.stats.wins);
    try std.testing.expect(!batch.worlds[0].players[@intFromEnum(td.Owner.opponent)].defeated);
}

test "every H0 force package can earn a legitimate terminal win" {
    for ([_]td.curriculum.Profile{ .h0_finish_e1, .h0_finish_e3, .h0_finish_mixed }) |profile| {
        var world = td.curriculum.reset(2, profile);
        try std.testing.expectEqual(td.state.Failure.none, world.failure);

        const attacker_count = countPlayerInfantry(&world);
        for (0..attacker_count) |attacker| {
            _ = td.step.stepWithEasyAI(&world, .{
                .command = .attack,
                .actor = @intCast(attacker + 1),
                .target_kind = .visible_enemy,
                .target_slot = 0,
            });
        }
        for (0..2_000) |_| {
            if (td.step.isTerminal(&world)) break;
            _ = td.step.stepWithEasyAI(&world, .{});
        }

        try std.testing.expect(world.players[@intFromEnum(td.Owner.opponent)].defeated);
        try std.testing.expect(!world.players[@intFromEnum(td.Owner.player)].defeated);
        try std.testing.expectEqual(td.state.Failure.none, world.failure);
    }
}

test "H0 batch snapshot restores profile and episode sampler state exactly" {
    var source = try td.batch.Batch.initWithCurriculum(
        std.testing.allocator,
        2,
        512,
        .{},
        .h0_test,
        1,
        1,
    );
    defer source.deinit(std.testing.allocator);
    var restored = try td.batch.Batch.initWithCurriculum(
        std.testing.allocator,
        2,
        512,
        .{},
        .h0_test,
        1,
        1,
    );
    defer restored.deinit(std.testing.allocator);
    var incompatible = try td.batch.Batch.initWithCurriculum(
        std.testing.allocator,
        2,
        512,
        .{},
        .h0_test,
        1,
        2,
    );
    defer incompatible.deinit(std.testing.allocator);
    try source.reset(&[_]u64{ 1, 2 });
    try restored.reset(&[_]u64{ 1, 2 });

    source.episode_ordinals[0] = 7;
    source.episode_ordinals[1] = 11;
    source.curriculum_decisions[0] = 17;
    source.curriculum_decisions[1] = 29;
    source.profiles[0] = .h0_finish_e3;
    source.profiles[1] = .h0_finish_mixed;
    const snapshot = try std.testing.allocator.alloc(u8, source.snapshotSize());
    defer std.testing.allocator.free(snapshot);
    try source.writeSnapshot(snapshot);
    try restored.readSnapshot(snapshot);
    try std.testing.expectError(error.IncompatibleSnapshot, incompatible.readSnapshot(snapshot));

    try std.testing.expectEqualSlices(u64, source.episode_ordinals, restored.episode_ordinals);
    try std.testing.expectEqualSlices(u64, source.curriculum_decisions, restored.curriculum_decisions);
    try std.testing.expectEqualSlices(td.curriculum.Profile, source.profiles, restored.profiles);
    const restored_snapshot = try std.testing.allocator.alloc(u8, restored.snapshotSize());
    defer std.testing.allocator.free(restored_snapshot);
    try restored.writeSnapshot(restored_snapshot);
    try std.testing.expectEqualSlices(u8, snapshot, restored_snapshot);
}

const InfantryCounts = struct {
    player_e1: usize = 0,
    player_e3: usize = 0,
    opponent_e1: usize = 0,
    opponent_e3: usize = 0,
};

fn countActiveInfantry(world: *const td.World) InfantryCounts {
    var counts: InfantryCounts = .{};
    for (world.infantry) |infantry| {
        if (!infantry.active) continue;
        switch (infantry.owner) {
            .player => if (infantry.kind == .e1) {
                counts.player_e1 += 1;
            } else if (infantry.kind == .e3) {
                counts.player_e3 += 1;
            },
            .opponent => if (infantry.kind == .e1) {
                counts.opponent_e1 += 1;
            } else if (infantry.kind == .e3) {
                counts.opponent_e3 += 1;
            },
            .none => {},
        }
    }
    return counts;
}

fn countPlayerInfantry(world: *const td.World) usize {
    const counts = countActiveInfantry(world);
    return counts.player_e1 + counts.player_e3;
}

fn countActiveBuildings(world: *const td.World, owner: td.Owner) usize {
    var count: usize = 0;
    for (world.buildings) |building| {
        if (building.active and building.owner == owner) count += 1;
    }
    return count;
}

fn countActiveUnits(world: *const td.World, owner: td.Owner, kind: td.ObjectType) usize {
    var count: usize = 0;
    for (world.units) |unit| {
        if (unit.active and unit.owner == owner and unit.kind == kind) count += 1;
    }
    return count;
}
