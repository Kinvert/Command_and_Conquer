const std = @import("std");
const td = @import("td_micro");

test "declared training timeout is 48000 frames and 12000 decisions" {
    try std.testing.expectEqual(@as(u32, 48000), td.batch.training_timeout_frames);
    try std.testing.expectEqual(@as(u32, 12000), td.batch.training_max_decisions);
    try std.testing.expectEqual(
        td.batch.training_timeout_frames,
        td.batch.training_max_decisions * td.rules.decision_frames,
    );
}

test "declared enemy destruction reward scale is stable" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), td.batch.enemy_unit_loss_reward, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), td.batch.enemy_building_loss_reward, 0.000001);
    try std.testing.expectEqual(@as(u64, 10), td.batch.rewarded_enemy_unit_loss_cap);
    try std.testing.expectEqual(@as(u64, 3), td.batch.rewarded_enemy_building_loss_cap);
}

test "default reward configuration preserves the economy reward contract" {
    const config: td.batch.RewardConfig = .{};
    try std.testing.expect(config.valid());
    try std.testing.expectEqual(@as(f32, 0.1), config.reward_milestone);
    try std.testing.expectEqual(@as(f32, 0.01), config.reward_player_infantry);
    try std.testing.expectEqual(@as(f32, 0.1), config.reward_enemy_unit_loss);
    try std.testing.expectEqual(@as(f32, 0.5), config.reward_enemy_building_loss);
    try std.testing.expectEqual(@as(f32, -0.001), config.reward_player_unit_loss);
    try std.testing.expectEqual(@as(f32, 0.2), config.reward_refinery);
    try std.testing.expectEqual(@as(f32, 0.1), config.reward_first_delivery);
    try std.testing.expectEqual(@as(f32, 0.01), config.reward_tiberium_income);
    try std.testing.expectEqual(@as(f32, 0.0), config.reward_invalid_action);
    try std.testing.expectEqual(@as(f32, 0.0), config.reward_first_tank);
    try std.testing.expectEqual(@as(f32, 0.0), config.reward_first_tank_shot);
    try std.testing.expectEqual(@as(f32, -1.0), config.reward_qualified_loss);
}

test "reward configuration rejects non-finite, out-of-range, and wrong-sign values" {
    var config: td.batch.RewardConfig = .{};
    config.reward_milestone = -0.001;
    try std.testing.expect(!config.valid());

    config = .{};
    config.reward_enemy_building_loss = 1.001;
    try std.testing.expect(!config.valid());

    config = .{};
    config.reward_player_unit_loss = 0.001;
    try std.testing.expect(!config.valid());

    config = .{};
    config.reward_player_infantry = std.math.nan(f32);
    try std.testing.expect(!config.valid());

    config = .{};
    config.reward_tiberium_income = 1.001;
    try std.testing.expect(!config.valid());

    config = .{};
    config.reward_refinery = -0.001;
    try std.testing.expect(!config.valid());

    config = .{};
    config.reward_first_delivery = std.math.nan(f32);
    try std.testing.expect(!config.valid());

    config = .{};
    config.reward_invalid_action = 0.001;
    try std.testing.expect(!config.valid());

    config = .{};
    config.reward_qualified_loss = 0.001;
    try std.testing.expect(!config.valid());

    config = .{};
    config.reward_first_tank_shot = -0.001;
    try std.testing.expect(!config.valid());
}

test "custom shaping changes reward without changing simulation state" {
    var custom_config: td.batch.RewardConfig = .{};
    custom_config.reward_milestone = 0.25;

    var default_batch = try td.batch.Batch.init(std.testing.allocator, 1, 4096);
    defer default_batch.deinit(std.testing.allocator);
    var custom_batch = try td.batch.Batch.initWithRewardConfig(
        std.testing.allocator,
        1,
        4096,
        custom_config,
    );
    defer custom_batch.deinit(std.testing.allocator);
    try default_batch.reset(&[_]u64{1});
    try custom_batch.reset(&[_]u64{1});

    const actions = [_]td.policy.RawAction{.{
        .command = @intFromEnum(td.Command.deploy),
        .arg0 = 0,
    }};
    var default_observation: [td.policy.observation_size]u8 = undefined;
    var custom_observation: [td.policy.observation_size]u8 = undefined;
    var default_mask: [td.policy.action_mask_size]u8 = undefined;
    var custom_mask: [td.policy.action_mask_size]u8 = undefined;
    var default_rewards = [_]f32{0};
    var custom_rewards = [_]f32{0};
    var default_terminals = [_]u8{0};
    var custom_terminals = [_]u8{0};

    default_batch.step(
        &actions,
        &default_observation,
        &default_mask,
        &default_rewards,
        &default_terminals,
    );
    custom_batch.step(
        &actions,
        &custom_observation,
        &custom_mask,
        &custom_rewards,
        &custom_terminals,
    );

    try std.testing.expectEqual(@as(f32, 0.1), default_rewards[0]);
    try std.testing.expectEqual(@as(f32, 0.25), custom_rewards[0]);
    try std.testing.expectEqualSlices(
        u8,
        &td.digest.canonical(&default_batch.worlds[0]),
        &td.digest.canonical(&custom_batch.worlds[0]),
    );
}

test "contiguous batch path exactly matches scalar Easy AI stepping" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), td.batch.milestone_reward, 0.000001);

    var batch = try td.batch.Batch.init(std.testing.allocator, 2, 4096);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{ 1, 1 });

    const actions = [_]td.policy.RawAction{
        .{ .command = @intFromEnum(td.Command.deploy), .arg0 = 0 },
        .{},
    };
    var observations: [2 * td.policy.observation_size]u8 = undefined;
    var masks: [2 * td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0} ** 2;
    var terminals = [_]u8{0} ** 2;
    batch.step(&actions, &observations, &masks, &rewards, &terminals);

    var deployed = td.curriculum.resetForEpisode(1, .full_match, 0, 0);
    _ = td.step.stepWithEasyAI(&deployed, .{ .command = .deploy, .actor = 0 });
    var idle = td.curriculum.resetForEpisode(1, .full_match, 1, 0);
    _ = td.step.stepWithEasyAI(&idle, .{});

    try std.testing.expectEqualSlices(u8, &td.digest.canonical(&deployed), &td.digest.canonical(&batch.worlds[0]));
    try std.testing.expectEqualSlices(u8, &td.digest.canonical(&idle), &td.digest.canonical(&batch.worlds[1]));
    try std.testing.expectEqual(@as(u64, 0), batch.stats.invalid_actions);
    try std.testing.expectEqual(td.batch.milestone_reward, rewards[0]);
    try std.testing.expectEqual(@as(f32, 0), rewards[1]);
    try std.testing.expectEqual(@as(u8, 0), terminals[0]);

    var scalar_obs: [td.policy.observation_size]u8 = undefined;
    td.policy.observe(&deployed, &scalar_obs);
    try std.testing.expectEqualSlices(u8, &scalar_obs, observations[0..td.policy.observation_size]);
}

test "invalid raw tuple is a deterministic no-op with a diagnostic" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 4096);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{ .command = 255 }}, &observations, &masks, &rewards, &terminals);

    var expected = td.curriculum.resetForEpisode(1, .full_match, 0, 0);
    _ = td.step.stepWithEasyAI(&expected, .{});
    try std.testing.expectEqualSlices(u8, &td.digest.canonical(&expected), &td.digest.canonical(&batch.worlds[0]));
    try std.testing.expectEqual(@as(u64, 1), batch.stats.invalid_actions);
}

test "ABI9 invalid penalty charges rejected tuples but not explicit noop" {
    var config: td.batch.RewardConfig = .{};
    config.reward_invalid_action = -0.0001;
    var rejected_batch = try td.batch.Batch.initWithRewardConfig(
        std.testing.allocator,
        1,
        4096,
        config,
    );
    defer rejected_batch.deinit(std.testing.allocator);
    var noop_batch = try td.batch.Batch.initWithRewardConfig(
        std.testing.allocator,
        1,
        4096,
        config,
    );
    defer noop_batch.deinit(std.testing.allocator);
    try rejected_batch.reset(&[_]u64{1});
    try noop_batch.reset(&[_]u64{1});

    var rejected_observation: [td.policy.observation_size]u8 = undefined;
    var noop_observation: [td.policy.observation_size]u8 = undefined;
    var rejected_mask: [td.policy_abi9.action_mask_size]u8 = undefined;
    var noop_mask: [td.policy_abi9.action_mask_size]u8 = undefined;
    var rejected_reward = [_]f32{0};
    var noop_reward = [_]f32{0};
    var rejected_terminal = [_]u8{0};
    var noop_terminal = [_]u8{0};
    rejected_batch.stepAbi9(
        &[_]td.policy_abi9.RawAction{.{
            .command = @intFromEnum(td.Command.deploy),
            .actor = td.policy_abi9.actor_none,
        }},
        &rejected_observation,
        &rejected_mask,
        &rejected_reward,
        &rejected_terminal,
    );
    noop_batch.stepAbi9(
        &[_]td.policy_abi9.RawAction{.{}},
        &noop_observation,
        &noop_mask,
        &noop_reward,
        &noop_terminal,
    );

    try std.testing.expectApproxEqAbs(config.reward_invalid_action, rejected_reward[0], 0.0000001);
    try std.testing.expectEqual(@as(f32, 0), noop_reward[0]);
    try std.testing.expectEqual(@as(u64, 1), rejected_batch.stats.invalid_actions);
    try std.testing.expectEqual(@as(u64, 0), noop_batch.stats.invalid_actions);
    try std.testing.expectEqualSlices(
        u8,
        &td.digest.canonical(&rejected_batch.worlds[0]),
        &td.digest.canonical(&noop_batch.worlds[0]),
    );
}

test "invalid action penalty is capped at minus one half per episode" {
    var config: td.batch.RewardConfig = .{};
    config.reward_invalid_action = -0.25;
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 4096, config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    var observation: [td.policy.observation_size]u8 = undefined;
    var mask: [td.policy_abi9.action_mask_size]u8 = undefined;
    var reward = [_]f32{0};
    var terminal = [_]u8{0};
    const invalid = [_]td.policy_abi9.RawAction{.{
        .command = @intFromEnum(td.Command.deploy),
        .actor = td.policy_abi9.actor_none,
    }};

    batch.stepAbi9(&invalid, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(f32, -0.25), reward[0]);
    batch.stepAbi9(&invalid, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(f32, -0.25), reward[0]);
    batch.stepAbi9(&invalid, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(f32, 0), reward[0]);
    try std.testing.expectEqual(td.batch.invalid_action_penalty_floor, batch.invalid_action_penalties[0]);
}

test "terminal reward replacement excludes the terminal-step invalid penalty" {
    var config: td.batch.RewardConfig = .{};
    config.reward_invalid_action = -0.1;
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 2, config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    var observation: [td.policy.observation_size]u8 = undefined;
    var mask: [td.policy_abi9.action_mask_size]u8 = undefined;
    var reward = [_]f32{0};
    var terminal = [_]u8{0};
    const invalid = [_]td.policy_abi9.RawAction{.{
        .command = @intFromEnum(td.Command.deploy),
        .actor = td.policy_abi9.actor_none,
    }};

    batch.stepAbi9(&invalid, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(f32, -0.1), reward[0]);
    try std.testing.expectEqual(@as(u8, 0), terminal[0]);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.completed_invalid_actions);

    batch.stepAbi9(&invalid, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(f32, 0), reward[0]);
    try std.testing.expectEqual(@as(u8, 1), terminal[0]);
    try std.testing.expectEqual(@as(u64, 2), batch.stats.completed_invalid_actions);
    try std.testing.expectApproxEqAbs(@as(f64, -0.1), batch.stats.invalid_action_penalty, 0.000001);
}

test "timeout emits terminal reward then auto-resets the world" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 1);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{99};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(u8, 1), terminals[0]);
    try std.testing.expectEqual(@as(f32, 0), rewards[0]);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.episodes);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.draws);
    try std.testing.expectEqual(@as(u32, 0), batch.worlds[0].frame);

    var reset_obs: [td.policy.observation_size]u8 = undefined;
    const reset_world = td.curriculum.resetForEpisode(1, .full_match, 0, 1);
    td.policy.observe(&reset_world, &reset_obs);
    try std.testing.expectEqualSlices(u8, &reset_obs, &observations);
}

test "batch reset exposes deterministic equal starting credits in observations" {
    const count = 100;
    var batch = try td.batch.Batch.init(std.testing.allocator, count, 4096);
    defer batch.deinit(std.testing.allocator);
    var seeds: [count]u64 = undefined;
    for (&seeds, 0..) |*seed, lane| seed.* = if (lane % 2 == 0) 1 else 2;
    try batch.reset(&seeds);

    const observations = try std.testing.allocator.alloc(u8, count * td.policy.observation_size);
    defer std.testing.allocator.free(observations);
    const masks = try std.testing.allocator.alloc(u8, count * td.policy.action_mask_size);
    defer std.testing.allocator.free(masks);
    batch.observe(observations, masks);

    var constrained_count: usize = 0;
    var force_count: usize = 0;
    for (0..count) |lane| {
        const expected = td.curriculum.startingCredits(seeds[lane], lane, 0);
        try std.testing.expectEqual(expected, batch.starting_credits[lane]);
        try std.testing.expectEqual(expected, batch.worlds[lane].players[0].credits);
        try std.testing.expectEqual(expected, batch.worlds[lane].players[1].credits);
        try std.testing.expectEqual(
            @as(u8, @intCast(@divExact(expected, 100))),
            observations[lane * td.policy.observation_size + 4],
        );
        if (expected == td.rules.starting_credits_constrained) constrained_count += 1;
        if (batch.worlds[lane].starting_force == .reduced_unit_count_6) {
            force_count += 1;
            try std.testing.expectEqual(@as(u8, 12), batch.worlds[lane].infantry_count);
        } else {
            try std.testing.expectEqual(@as(u8, 0), batch.worlds[lane].infantry_count);
        }
    }
    try std.testing.expectEqual(@as(usize, 35), constrained_count);
    try std.testing.expectEqual(@as(usize, 50), force_count);
}

test "starting forces provide no free milestone or production reward" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 4096);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});
    try std.testing.expectEqual(td.state.StartingForce.reduced_unit_count_6, batch.worlds[0].starting_force);

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{99};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(f32, 0), rewards[0]);
    try std.testing.expectEqual(@as(u64, 0), batch.episode_metrics[0].player_e1_built);
    try std.testing.expectEqual(@as(u64, 0), batch.episode_metrics[0].player_e3_built);
    try std.testing.expectEqual(@as(u64, 0), batch.episode_metrics[0].e1_milestones);
    try std.testing.expectEqual(@as(u64, 0), batch.episode_metrics[0].e3_milestones);
}

test "terminal stats separate close and medium outcomes" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 4, 0);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{ 1, 1, 2, 2 });

    for (batch.worlds) |*world| world.easy_ai.active = false;
    batch.worlds[0].starting_force = .mcv_only;
    batch.worlds[1].starting_force = .reduced_unit_count_6;
    batch.worlds[2].starting_force = .mcv_only;
    batch.worlds[3].starting_force = .reduced_unit_count_6;
    batch.worlds[0].players[@intFromEnum(td.Owner.opponent)].defeated = true;
    batch.worlds[1].players[@intFromEnum(td.Owner.player)].defeated = true;
    batch.worlds[2].players[@intFromEnum(td.Owner.opponent)].defeated = true;
    batch.worlds[3].players[@intFromEnum(td.Owner.player)].defeated = true;

    var observations: [4 * td.policy.observation_size]u8 = undefined;
    var masks: [4 * td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0} ** 4;
    var terminals = [_]u8{0} ** 4;
    batch.step(&([_]td.policy.RawAction{.{}} ** 4), &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual([_]u8{1} ** 4, terminals);
    try std.testing.expectEqual(@as(u64, 4), batch.stats.episodes);
    try std.testing.expectEqual(@as(u64, 2), batch.stats.wins);
    try std.testing.expectEqual(@as(u64, 2), batch.stats.losses);
    try std.testing.expectEqual(@as(u64, 2), batch.stats.close_episodes);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.close_wins);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.close_losses);
    try std.testing.expectEqual(@as(u64, 2), batch.stats.medium_episodes);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.medium_wins);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.medium_losses);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.close_mcv_episodes);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.close_mcv_wins);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.close_mcv_losses);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.close_force_episodes);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.close_force_wins);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.close_force_losses);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.medium_mcv_episodes);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.medium_mcv_wins);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.medium_mcv_losses);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.medium_force_episodes);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.medium_force_wins);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.medium_force_losses);
}

test "placing beyond the player building limit is a loss rather than an engine failure" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 4096);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].easy_ai.active = false;
    batch.worlds[0].units[0].active = false;
    try std.testing.expect(batch.worlds[0].addBuilding(
        .player,
        .construction_yard,
        .{ .x = 1, .y = 7 },
    ));
    for (0..td.batch.player_building_limit - 1) |index| {
        try std.testing.expect(batch.worlds[0].addBuilding(
            .player,
            .power_plant,
            .{ .x = @intCast(10 + index * 2), .y = 30 },
        ));
    }
    batch.worlds[0].queues[0][@intFromEnum(td.state.QueueKind.structure)] = .{
        .active = true,
        .completed = true,
        .product = .power_plant,
    };

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{
        .command = @intFromEnum(td.Command.place),
        .arg0 = 4,
        .arg1 = 7,
    }}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(u8, 1), terminals[0]);
    try std.testing.expectEqual(@as(f32, -1), rewards[0]);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.episodes);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.losses);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.building_limit_losses);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.failures);
    try std.testing.expectEqual(@as(u8, 0), batch.worlds[0].building_count);
    try std.testing.expectEqual(@as(u32, 0), batch.worlds[0].frame);
}

test "exceeding the player infantry limit is a loss rather than an engine failure" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 4096);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    for (0..td.batch.player_infantry_limit + 1) |index| {
        batch.worlds[0].infantry[index] = .{
            .active = true,
            .kind = .e1,
            .owner = .player,
            .position = .{ .x = @intCast(index % 8), .y = @intCast(16 + index / 8) },
            .health = 50,
        };
    }
    batch.worlds[0].infantry_count = @intCast(td.batch.player_infantry_limit + 1);

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(u8, 1), terminals[0]);
    try std.testing.expectEqual(@as(f32, -1), rewards[0]);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.episodes);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.losses);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.infantry_limit_losses);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.building_limit_losses);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.invalid_streak_losses);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.failures);
    try std.testing.expectEqual(@as(u8, 0), batch.worlds[0].infantry_count);
    try std.testing.expectEqual(@as(u32, 0), batch.worlds[0].frame);
}

test "decision-boundary compaction reclaims infantry slots and remaps targets" {
    var world = td.World.reset(1);
    world.infantry[0] = .{ .kind = .e1, .owner = .player };
    world.infantry[1] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .health = 50,
        .target = .{ .kind = .e3, .owner = .opponent, .index = 3 },
    };
    world.infantry[2] = .{ .kind = .e3, .owner = .opponent };
    world.infantry[3] = .{
        .active = true,
        .kind = .e3,
        .owner = .opponent,
        .health = 50,
        .target = .{ .kind = .e1, .owner = .player, .index = 0 },
    };
    world.infantry_count = 4;
    world.projectiles[0] = .{
        .active = true,
        .source = .{ .kind = .e1, .owner = .player, .index = 1 },
        .target = .{ .kind = .e3, .owner = .opponent, .index = 3 },
    };

    var observed_deaths = [_]bool{false} ** td.rules.max_infantry;
    observed_deaths[1] = true;
    td.batch.compactInactiveInfantry(&world, &observed_deaths);

    try std.testing.expectEqual(@as(u8, 2), world.infantry_count);
    try std.testing.expectEqual(td.Owner.player, world.infantry[0].owner);
    try std.testing.expectEqual(td.Owner.opponent, world.infantry[1].owner);
    try std.testing.expectEqual(@as(u16, 1), world.infantry[0].target.index);
    try std.testing.expect(!world.infantry[1].target.valid());
    try std.testing.expectEqual(@as(u16, 0), world.projectiles[0].source.index);
    try std.testing.expectEqual(@as(u16, 1), world.projectiles[0].target.index);
    try std.testing.expect(observed_deaths[0]);
    try std.testing.expect(!observed_deaths[1]);
    try std.testing.expectEqual(td.ObjectType.none, world.infantry[2].kind);
}

test "infantry_count bounds every active slot through seeded Easy AI play" {
    for ([_]u64{ 1, 2 }) |seed| {
        var world = td.World.reset(seed);
        for (0..3_000) |_| {
            _ = td.step.stepEasyAIFrame(&world);
            for (world.infantry[world.infantry_count..]) |infantry| {
                try std.testing.expect(!infantry.active);
            }
            if (td.step.isTerminal(&world)) break;
        }
    }
}

test "building_count bounds every active slot through seeded Easy AI play" {
    for ([_]u64{ 1, 2 }) |seed| {
        var world = td.World.reset(seed);
        for (0..3_000) |_| {
            _ = td.step.stepEasyAIFrame(&world);
            for (world.buildings[world.building_count..]) |building| {
                try std.testing.expect(!building.active);
            }
            if (td.step.isTerminal(&world)) break;
        }
    }
}

test "Easy AI base geometry follows opponent building changes" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(
        .opponent,
        .construction_yard,
        .{ .x = 10, .y = 10 },
    ));
    td.ai.finishFrame(&world);
    try std.testing.expect(world.easy_ai.has_center);
    const yard_center = .{ world.easy_ai.center_x, world.easy_ai.center_y };
    const yard_radius = world.easy_ai.radius;

    for (0..8) |_| td.ai.finishFrame(&world);
    try std.testing.expectEqual(yard_center, .{ world.easy_ai.center_x, world.easy_ai.center_y });
    try std.testing.expectEqual(yard_radius, world.easy_ai.radius);

    try std.testing.expect(world.addBuilding(
        .opponent,
        .power_plant,
        .{ .x = 20, .y = 20 },
    ));
    td.ai.finishFrame(&world);
    try std.testing.expect(!std.meta.eql(
        yard_center,
        .{ world.easy_ai.center_x, world.easy_ai.center_y },
    ));

    td.combat.blowupOwner(&world, .opponent);
    td.ai.finishFrame(&world);
    try std.testing.expect(!world.easy_ai.has_center);
    try std.testing.expectEqual(@as(i16, 0), world.easy_ai.center_x);
    try std.testing.expectEqual(@as(i16, 0), world.easy_ai.center_y);
    try std.testing.expectEqual(@as(u16, 0), world.easy_ai.radius);
}

test "projectile destruction invalidates Easy AI base geometry" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(
        .opponent,
        .construction_yard,
        .{ .x = 10, .y = 10 },
    ));
    try std.testing.expect(world.addBuilding(
        .opponent,
        .power_plant,
        .{ .x = 20, .y = 20 },
    ));
    td.ai.finishFrame(&world);
    const two_building_center = .{ world.easy_ai.center_x, world.easy_ai.center_y };
    try std.testing.expect(!world.easy_ai.base_dirty);

    world.buildings[1].health = 1;
    world.projectiles[0] = .{
        .active = true,
        .kind = .bullet,
        .target = .{ .kind = .power_plant, .owner = .opponent, .index = 1 },
        .coord_x = 20 * 256 + 128,
        .coord_y = 20 * 256 + 128,
        .strength = 100,
    };
    world.projectile_order[0] = 0;
    world.projectile_count = 1;
    td.combat.tickAfterUnitMissions(&world, null);

    try std.testing.expect(!world.buildings[1].active);
    try std.testing.expect(world.easy_ai.base_dirty);
    td.ai.finishFrame(&world);
    try std.testing.expect(!world.easy_ai.base_dirty);
    try std.testing.expect(!std.meta.eql(
        two_building_center,
        .{ world.easy_ai.center_x, world.easy_ai.center_y },
    ));
}

test "building fire destruction invalidates Easy AI base geometry" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(
        .opponent,
        .construction_yard,
        .{ .x = 10, .y = 10 },
    ));
    try std.testing.expect(world.addBuilding(
        .opponent,
        .power_plant,
        .{ .x = 20, .y = 20 },
    ));
    td.ai.finishFrame(&world);
    try std.testing.expect(!world.easy_ai.base_dirty);

    world.buildings[1].health = 1;
    world.building_fires[0] = .{
        .active = true,
        .target = .{ .kind = .power_plant, .owner = .opponent, .index = 1 },
        .loops = 1,
        .accum = 255,
    };
    world.building_fire_count = 1;
    td.combat.tickAfterUnitMissions(&world, null);

    try std.testing.expect(!world.buildings[1].active);
    try std.testing.expect(world.easy_ai.base_dirty);
    td.ai.finishFrame(&world);
    try std.testing.expect(!world.easy_ai.base_dirty);
    try std.testing.expect(world.easy_ai.has_center);
}

test "decision-boundary reclamation reuses destroyed Harvester slots" {
    var world = td.World.reset(1);
    world.units[0].active = false;
    world.units[2] = .{
        .kind = .harvester,
        .owner = .player,
        .health = 0,
    };
    var observed_deaths = [_]bool{false} ** td.rules.max_units;
    observed_deaths[2] = true;

    td.batch.reclaimDestroyedUnits(&world, &observed_deaths);

    try std.testing.expectEqual(td.ObjectType.mcv, world.units[0].kind);
    try std.testing.expectEqual(td.ObjectType.none, world.units[2].kind);
    try std.testing.expect(!observed_deaths[2]);
    const reused = world.addUnit(.player, .harvester, .{ .x = 4, .y = 9 }) orelse
        return error.MissingReusedUnitSlot;
    try std.testing.expectEqual(@as(usize, 2), reused);
}

test "invalid commands remain diagnostic no-ops instead of artificial losses" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 4096);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    const invalid = [_]td.policy.RawAction{.{ .command = 255 }};

    for (0..129) |_| {
        batch.step(&invalid, &observations, &masks, &rewards, &terminals);
        try std.testing.expectEqual(@as(u8, 0), terminals[0]);
        try std.testing.expectEqual(@as(f32, 0), rewards[0]);
    }
    try std.testing.expectEqual(@as(u64, 0), batch.stats.episodes);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.losses);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.invalid_streak_losses);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.building_limit_losses);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.infantry_limit_losses);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.failures);
    try std.testing.expectEqual(@as(u64, 129), batch.stats.invalid_actions);
    try std.testing.expectEqual(@as(u16, 129), batch.invalid_action_streaks[0]);
    try std.testing.expectEqual(@as(u32, 129 * td.rules.decision_frames), batch.worlds[0].frame);
}

test "curriculum rewards each completed economy milestone exactly once" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 4096);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});
    batch.worlds[0] = td.curriculum.resetForEpisode(1, .full_match, 0, 1);
    batch.milestones[0] = 0;
    try std.testing.expectEqual(td.state.StartingForce.mcv_only, batch.worlds[0].starting_force);

    batch.worlds[0].easy_ai.active = false;
    batch.worlds[0].units[0].active = false;
    try std.testing.expect(batch.worlds[0].addBuilding(.player, .construction_yard, .{ .x = 2, .y = 8 }));
    try std.testing.expect(batch.worlds[0].addBuilding(.player, .power_plant, .{ .x = 4, .y = 7 }));
    try std.testing.expect(batch.worlds[0].addBuilding(.player, .barracks, .{ .x = 6, .y = 7 }));
    batch.worlds[0].infantry[0] = .{ .active = true, .kind = .e1, .owner = .player, .health = 50 };
    batch.worlds[0].infantry[1] = .{ .active = true, .kind = .e3, .owner = .player, .health = 25 };
    batch.worlds[0].infantry_count = 2;

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectApproxEqAbs(@as(f32, 5) * td.batch.milestone_reward, rewards[0], 0.0001);
    try std.testing.expectEqual(@as(u8, 0), terminals[0]);

    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectEqual(@as(f32, 0), rewards[0]);
}

test "Refinery Harvester and first delivery rewards are deterministic" {
    var reward_config: td.batch.RewardConfig = .{};
    reward_config.reward_milestone = 0.13;
    reward_config.reward_refinery = 0.37;
    reward_config.reward_first_delivery = 0.19;
    reward_config.reward_tiberium_income = 0.02;
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 4096, reward_config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].easy_ai.active = false;
    try std.testing.expect(batch.worlds[0].addBuilding(.player, .refinery, .{ .x = 4, .y = 7 }));
    batch.worlds[0].buildings[0].construction_frames = 0;
    td.production.tick(&batch.worlds[0]);

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectApproxEqAbs(
        reward_config.reward_refinery,
        rewards[0],
        0.0001,
    );
    try std.testing.expectEqual(@as(u64, 1), batch.episode_metrics[0].refinery_milestones);
    try std.testing.expectEqual(@as(u64, 1), batch.episode_metrics[0].harvester_milestones);

    const unit = &batch.worlds[0].units[2];
    unit.cargo_steps = 4;
    unit.position = .{ .x = 4, .y = 9 };
    unit.coord_x = 4 * 256 + 128;
    unit.coord_y = 9 * 256 + 128;
    unit.mission = 6;
    unit.moving = false;
    unit.destination_valid = false;
    var delivery_reward: f32 = 0;
    for (0..512) |_| {
        batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
        delivery_reward += rewards[0];
        if (batch.worlds[0].players[0].harvested_credits == 100) break;
    }

    try std.testing.expectEqual(@as(u32, 100), batch.worlds[0].players[0].harvested_credits);
    try std.testing.expectApproxEqAbs(
        reward_config.reward_first_delivery + reward_config.reward_tiberium_income,
        delivery_reward,
        0.0001,
    );
    try std.testing.expectEqual(@as(u64, 100), batch.episode_metrics[0].player_tiberium_income);
}

test "owned infantry death is penalized exactly once" {
    var reward_config: td.batch.RewardConfig = .{};
    reward_config.reward_player_unit_loss = -0.125;
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 4096, reward_config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].easy_ai.active = false;
    batch.milestones[0] = 0xff;
    batch.worlds[0].infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 20, .y = 20 },
        .health = 1,
        .coord_x = 5248,
        .coord_y = 5248,
    };
    batch.worlds[0].infantry_count = 1;
    batch.worlds[0].projectiles[0] = .{
        .active = true,
        .kind = .bullet,
        .coord_x = 5248,
        .coord_y = 5248,
        .strength = 100,
    };
    batch.worlds[0].projectile_order[0] = 0;
    batch.worlds[0].projectile_count = 1;

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(i16, 0), batch.worlds[0].infantry[0].health);
    try std.testing.expectApproxEqAbs(reward_config.reward_player_unit_loss, rewards[0], 0.000001);
    try std.testing.expectEqual(@as(u8, 0), terminals[0]);

    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectEqual(@as(f32, 0), rewards[0]);
}

test "opponent infantry death earns combat reward" {
    var reward_config: td.batch.RewardConfig = .{};
    reward_config.reward_enemy_unit_loss = 0.25;
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 4096, reward_config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].easy_ai.active = false;
    batch.milestones[0] = 0xff;
    batch.worlds[0].infantry[0] = .{
        .active = true,
        .kind = .e3,
        .owner = .opponent,
        .position = .{ .x = 20, .y = 20 },
        .health = 1,
        .coord_x = 5248,
        .coord_y = 5248,
    };
    batch.worlds[0].infantry_count = 1;
    batch.worlds[0].projectiles[0] = .{
        .active = true,
        .kind = .bullet,
        .coord_x = 5248,
        .coord_y = 5248,
        .strength = 100,
    };
    batch.worlds[0].projectile_order[0] = 0;
    batch.worlds[0].projectile_count = 1;

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(i16, 0), batch.worlds[0].infantry[0].health);
    try std.testing.expectApproxEqAbs(reward_config.reward_enemy_unit_loss, rewards[0], 0.000001);
    try std.testing.expectEqual(@as(u8, 0), terminals[0]);
}

test "new infantry rewards are small and capped per episode" {
    var reward_config: td.batch.RewardConfig = .{};
    reward_config.reward_player_infantry = 0.03;
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 4096, reward_config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].easy_ai.active = false;
    batch.milestones[0] = 0xff;
    batch.episode_metrics[0].player_e1_built = td.batch.rewarded_player_infantry_cap - 1;
    try std.testing.expect(batch.worlds[0].addBuilding(.player, .barracks, .{ .x = 8, .y = 8 }));
    batch.worlds[0].buildings[0].operational = true;
    batch.worlds[0].queues[0][@intFromEnum(td.state.QueueKind.infantry)] = .{
        .active = true,
        .completed = true,
        .product = .e1,
    };

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectApproxEqAbs(reward_config.reward_player_infantry, rewards[0], 0.000001);
    try std.testing.expectEqual(@as(u8, 0), terminals[0]);

    batch.worlds[0].queues[0][@intFromEnum(td.state.QueueKind.infantry)] = .{
        .active = true,
        .completed = true,
        .product = .e3,
    };
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectEqual(@as(f32, 0), rewards[0]);
}

test "destroying an opponent building earns bounded combat shaping" {
    var reward_config: td.batch.RewardConfig = .{};
    reward_config.reward_enemy_building_loss = 0.75;
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 4096, reward_config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].easy_ai.active = false;
    batch.milestones[0] = 0xff;
    try std.testing.expect(batch.worlds[0].addBuilding(.opponent, .power_plant, .{ .x = 20, .y = 20 }));
    batch.worlds[0].buildings[0].health = 1;
    batch.worlds[0].infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 5, .y = 5 },
        .health = 50,
        .coord_x = 1344,
        .coord_y = 1344,
    };
    batch.worlds[0].infantry_count = 1;
    batch.worlds[0].projectiles[0] = .{
        .active = true,
        .kind = .bullet,
        .source = .{ .kind = .e1, .owner = .player, .index = 0 },
        .target = .{ .kind = .power_plant, .owner = .opponent, .index = 0 },
        .coord_x = 5248,
        .coord_y = 5248,
        .strength = 100,
    };
    batch.worlds[0].projectile_order[0] = 0;
    batch.worlds[0].projectile_count = 1;

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectApproxEqAbs(reward_config.reward_enemy_building_loss, rewards[0], 0.000001);
    try std.testing.expectEqual(@as(u8, 0), terminals[0]);
}

test "masked policy attack action can win a real episode" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 1000);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});
    batch.worlds[0] = td.combat.e1DuelFixture();
    batch.worlds[0].easy_ai.active = false;
    batch.milestones[0] = 0xff;

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    batch.observe(&observations, &masks);
    try std.testing.expect(td.policy.commandAllowed(&masks, .attack));
    try std.testing.expect(td.policy.argumentAllowed(&masks, .attack, 0, td.policy.pad_token, 1));
    try std.testing.expect(td.policy.argumentAllowed(&masks, .attack, 1, 1, 0));

    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{
        .command = @intFromEnum(td.Command.attack),
        .arg0 = 1,
        .arg1 = 0,
    }}, &observations, &masks, &rewards, &terminals);
    for (0..700) |_| {
        if (terminals[0] != 0) break;
        batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    }

    try std.testing.expectEqual(@as(u8, 1), terminals[0]);
    // Wins are graded now: this episode wins without mining, so it is a rush win and pays
    // reward_partial_win rather than the full reward_full_win.
    const graded: td.batch.RewardConfig = .{};
    try std.testing.expectEqual(graded.reward_partial_win, rewards[0]);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.wins);
    try std.testing.expectEqual(@as(u64, 0), batch.stats.losses);
}

test "episode metrics count newly produced infantry by owner and kind" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 1);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].easy_ai.active = false;
    try std.testing.expect(batch.worlds[0].addBuilding(.player, .barracks, .{ .x = 8, .y = 8 }));
    try std.testing.expect(batch.worlds[0].addBuilding(.opponent, .barracks, .{ .x = 40, .y = 40 }));
    batch.worlds[0].buildings[0].operational = true;
    batch.worlds[0].buildings[1].operational = true;
    batch.worlds[0].queues[@intFromEnum(td.Owner.player)][@intFromEnum(td.state.QueueKind.infantry)] = .{
        .active = true,
        .completed = true,
        .product = .e1,
    };
    batch.worlds[0].queues[@intFromEnum(td.Owner.opponent)][@intFromEnum(td.state.QueueKind.infantry)] = .{
        .active = true,
        .completed = true,
        .product = .e3,
    };

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(u8, 1), terminals[0]);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.player_e1_built);
    try std.testing.expectEqual(@as(u64, 0), batch.metrics.player_e3_built);
    try std.testing.expectEqual(@as(u64, 0), batch.metrics.opponent_e1_built);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.opponent_e3_built);
}

test "episode metrics count credited kills and infantry losses without netting" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 1);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].easy_ai.active = false;
    batch.milestones[0] = 0xff;
    batch.worlds[0].infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 5, .y = 5 },
        .health = 50,
        .coord_x = 1344,
        .coord_y = 1344,
    };
    batch.worlds[0].infantry[1] = .{
        .active = true,
        .kind = .e3,
        .owner = .opponent,
        .position = .{ .x = 20, .y = 20 },
        .health = 1,
        .coord_x = 5248,
        .coord_y = 5248,
    };
    batch.worlds[0].infantry[2] = .{
        .active = true,
        .kind = .e3,
        .owner = .opponent,
        .position = .{ .x = 50, .y = 40 },
        .health = 25,
        .coord_x = 12864,
        .coord_y = 10304,
    };
    batch.worlds[0].infantry[3] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 40, .y = 20 },
        .health = 1,
        .coord_x = 10304,
        .coord_y = 5248,
    };
    batch.worlds[0].infantry_count = 4;
    batch.worlds[0].projectiles[0] = .{
        .active = true,
        .kind = .bullet,
        .source = .{ .kind = .e1, .owner = .player, .index = 0 },
        .target = .{ .kind = .e3, .owner = .opponent, .index = 1 },
        .coord_x = 5248,
        .coord_y = 5248,
        .strength = 100,
    };
    batch.worlds[0].projectiles[1] = .{
        .active = true,
        .kind = .bullet,
        .source = .{ .kind = .e3, .owner = .opponent, .index = 2 },
        .target = .{ .kind = .e1, .owner = .player, .index = 3 },
        .coord_x = 10304,
        .coord_y = 5248,
        .strength = 100,
    };
    batch.worlds[0].projectile_order[0] = 0;
    batch.worlds[0].projectile_order[1] = 1;
    batch.worlds[0].projectile_count = 2;

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(u8, 1), terminals[0]);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.player_unit_kills);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.opponent_unit_kills);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.player_unit_losses);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.opponent_unit_losses);
}

test "episode metrics distinguish accepted and rejected train commands" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 2);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].easy_ai.active = false;
    try std.testing.expect(batch.worlds[0].addBuilding(.player, .barracks, .{ .x = 8, .y = 8 }));
    batch.worlds[0].buildings[0].operational = true;

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{
        .command = @intFromEnum(td.Command.train),
        .arg0 = @intFromEnum(td.policy.Product.e1),
    }}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectEqual(@as(u8, 0), terminals[0]);

    batch.step(&[_]td.policy.RawAction{.{
        .command = @intFromEnum(td.Command.train),
        .arg0 = @intFromEnum(td.policy.Product.e3),
    }}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(u8, 1), terminals[0]);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.accepted_train_actions);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.rejected_train_actions);
}

test "episode metrics count destroyed buildings for both sides" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 1);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].easy_ai.active = false;
    batch.milestones[0] = 0xff;
    try std.testing.expect(batch.worlds[0].addBuilding(.opponent, .power_plant, .{ .x = 20, .y = 20 }));
    try std.testing.expect(batch.worlds[0].addBuilding(.player, .barracks, .{ .x = 40, .y = 20 }));
    batch.worlds[0].buildings[0].health = 1;
    batch.worlds[0].buildings[1].health = 1;
    batch.worlds[0].infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 5, .y = 5 },
        .health = 50,
        .coord_x = 1344,
        .coord_y = 1344,
    };
    batch.worlds[0].infantry[1] = .{
        .active = true,
        .kind = .e3,
        .owner = .opponent,
        .position = .{ .x = 50, .y = 40 },
        .health = 25,
        .coord_x = 12864,
        .coord_y = 10304,
    };
    batch.worlds[0].infantry_count = 2;
    batch.worlds[0].projectiles[0] = .{
        .active = true,
        .kind = .bullet,
        .source = .{ .kind = .e1, .owner = .player, .index = 0 },
        .target = .{ .kind = .power_plant, .owner = .opponent, .index = 0 },
        .coord_x = 5248,
        .coord_y = 5248,
        .strength = 100,
    };
    batch.worlds[0].projectiles[1] = .{
        .active = true,
        .kind = .bullet,
        .source = .{ .kind = .e3, .owner = .opponent, .index = 1 },
        .target = .{ .kind = .barracks, .owner = .player, .index = 1 },
        .coord_x = 10368,
        .coord_y = 5248,
        .strength = 100,
    };
    batch.worlds[0].projectile_order[0] = 0;
    batch.worlds[0].projectile_order[1] = 1;
    batch.worlds[0].projectile_count = 2;

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(u8, 1), terminals[0]);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.player_buildings_lost);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.opponent_buildings_lost);
}

test "episode metrics count explicit Easy AI hunt orders" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 1);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .opponent,
        .position = .{ .x = 40, .y = 40 },
        .health = 50,
        .coord_x = 10304,
        .coord_y = 10304,
        .queued_mission = 13,
    };
    batch.worlds[0].infantry_count = 1;

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(u8, 1), terminals[0]);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.enemy_attack_orders);
}

test "episode metrics count an MCV as a lost unit" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 1);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    batch.worlds[0].easy_ai.active = false;
    batch.milestones[0] = 0xff;
    batch.worlds[0].units[0].health = 1;
    batch.worlds[0].infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .opponent,
        .position = .{ .x = 40, .y = 40 },
        .health = 50,
        .coord_x = 10304,
        .coord_y = 10304,
    };
    batch.worlds[0].infantry_count = 1;
    batch.worlds[0].projectiles[0] = .{
        .active = true,
        .kind = .bullet,
        .source = .{ .kind = .e1, .owner = .opponent, .index = 0 },
        .target = .{ .kind = .mcv, .owner = .player, .index = 0 },
        .coord_x = 640,
        .coord_y = 2176,
        .strength = 100,
    };
    batch.worlds[0].projectile_order[0] = 0;
    batch.worlds[0].projectile_count = 1;

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual(@as(u8, 1), terminals[0]);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.player_unit_losses);
}

test "batch snapshot restores an exact mid-episode continuation" {
    const count = 2;
    const config: td.batch.RewardConfig = .{ .reward_invalid_action = -0.0001 };
    var source = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, count, 4096, config);
    defer source.deinit(std.testing.allocator);
    var restored = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, count, 4096, config);
    defer restored.deinit(std.testing.allocator);
    try source.reset(&[_]u64{ 1, 2 });
    try restored.reset(&[_]u64{ 1, 2 });

    const actions = [_]td.policy_abi9.RawAction{ .{}, .{} };
    var source_observations: [count * td.policy.observation_size]u8 = undefined;
    var restored_observations: [count * td.policy.observation_size]u8 = undefined;
    var source_masks: [count * td.policy_abi9.action_mask_size]u8 = undefined;
    var restored_masks: [count * td.policy_abi9.action_mask_size]u8 = undefined;
    var source_rewards = [_]f32{0} ** count;
    var restored_rewards = [_]f32{0} ** count;
    var source_terminals = [_]u8{0} ** count;
    var restored_terminals = [_]u8{0} ** count;

    for (0..37) |_| source.stepAbi9(
        &actions,
        &source_observations,
        &source_masks,
        &source_rewards,
        &source_terminals,
    );

    const source_snapshot = try std.testing.allocator.alloc(u8, source.snapshotSize());
    defer std.testing.allocator.free(source_snapshot);
    const restored_snapshot = try std.testing.allocator.alloc(u8, restored.snapshotSize());
    defer std.testing.allocator.free(restored_snapshot);
    try source.writeSnapshot(source_snapshot);
    try restored.readSnapshot(source_snapshot);
    try restored.writeSnapshot(restored_snapshot);
    try std.testing.expectEqualSlices(u8, source_snapshot, restored_snapshot);

    for (0..128) |_| {
        source.stepAbi9(&actions, &source_observations, &source_masks, &source_rewards, &source_terminals);
        restored.stepAbi9(
            &actions,
            &restored_observations,
            &restored_masks,
            &restored_rewards,
            &restored_terminals,
        );
        try std.testing.expectEqualSlices(u8, &source_observations, &restored_observations);
        try std.testing.expectEqualSlices(u8, &source_masks, &restored_masks);
        try std.testing.expectEqualSlices(f32, &source_rewards, &restored_rewards);
        try std.testing.expectEqualSlices(u8, &source_terminals, &restored_terminals);
    }
    try source.writeSnapshot(source_snapshot);
    try restored.writeSnapshot(restored_snapshot);
    try std.testing.expectEqualSlices(u8, source_snapshot, restored_snapshot);
}

test "full-match snapshot preserves credit and starting-force continuation across terminal reset" {
    var source = try td.batch.Batch.init(std.testing.allocator, 2, 1);
    defer source.deinit(std.testing.allocator);
    var restored = try td.batch.Batch.init(std.testing.allocator, 2, 1);
    defer restored.deinit(std.testing.allocator);
    try source.reset(&[_]u64{ 1, 2 });
    try restored.reset(&[_]u64{ 1, 2 });

    source.episode_ordinals[0] = 7;
    source.episode_ordinals[1] = 11;
    const snapshot = try std.testing.allocator.alloc(u8, source.snapshotSize());
    defer std.testing.allocator.free(snapshot);
    try source.writeSnapshot(snapshot);
    try restored.readSnapshot(snapshot);
    try std.testing.expectEqualSlices(u64, source.episode_ordinals, restored.episode_ordinals);
    try std.testing.expectEqualSlices(i32, source.starting_credits, restored.starting_credits);

    const actions = [_]td.policy.RawAction{ .{}, .{} };
    var source_observations: [2 * td.policy.observation_size]u8 = undefined;
    var restored_observations: [2 * td.policy.observation_size]u8 = undefined;
    var source_masks: [2 * td.policy.action_mask_size]u8 = undefined;
    var restored_masks: [2 * td.policy.action_mask_size]u8 = undefined;
    var source_rewards = [_]f32{0} ** 2;
    var restored_rewards = [_]f32{0} ** 2;
    var source_terminals = [_]u8{0} ** 2;
    var restored_terminals = [_]u8{0} ** 2;
    source.step(&actions, &source_observations, &source_masks, &source_rewards, &source_terminals);
    restored.step(&actions, &restored_observations, &restored_masks, &restored_rewards, &restored_terminals);

    try std.testing.expectEqualSlices(u8, &source_observations, &restored_observations);
    try std.testing.expectEqualSlices(u8, &source_masks, &restored_masks);
    try std.testing.expectEqualSlices(f32, &source_rewards, &restored_rewards);
    try std.testing.expectEqualSlices(u8, &source_terminals, &restored_terminals);
    try std.testing.expectEqualSlices(i32, source.starting_credits, restored.starting_credits);
    for (source.starting_credits, 0..) |credits, lane| {
        try std.testing.expectEqual(
            td.curriculum.startingCredits(source.seeds[lane], lane, source.episode_ordinals[lane]),
            credits,
        );
        try std.testing.expectEqual(
            td.curriculum.startingForce(lane, source.episode_ordinals[lane]),
            source.worlds[lane].starting_force,
        );
        try std.testing.expectEqual(source.worlds[lane].starting_force, restored.worlds[lane].starting_force);
    }
}

test "the vehicle bounty counts tanks only, not the cheaper humvee" {
    // vehicle_gain summed tanks and humvees. A humvee costs 400 against the medium tank's 800, so
    // the cheap unit collected a bounty meant to pay for reaching armour -- against a full_perf
    // criterion that specifically requires a tank.
    //
    // Asserted against recordEconomyEvents directly: the gains are deltas of active counts taken
    // inside a step, so placing units between steps produces no delta at all and would make this
    // pass for the wrong reason.
    var world = td.state.World.reset(1);
    _ = world.addUnit(.player, .humvee, .{ .x = 6, .y = 9 });
    _ = world.addUnit(.player, .humvee, .{ .x = 7, .y = 9 });

    var metrics: td.batch.Metrics = .{};
    var factory_gain: u64 = 0;
    var vehicle_gain: u64 = 0;
    td.batch.recordEconomyEventsForTest(
        &world,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        &metrics,
        &factory_gain,
        &vehicle_gain,
    );
    try std.testing.expectEqual(@as(u64, 0), vehicle_gain);
    try std.testing.expectEqual(@as(u64, 2), metrics.player_humvees_built);

    _ = world.addUnit(.player, .medium_tank, .{ .x = 8, .y = 9 });
    metrics = .{};
    td.batch.recordEconomyEventsForTest(
        &world,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        &metrics,
        &factory_gain,
        &vehicle_gain,
    );
    try std.testing.expectEqual(@as(u64, 1), vehicle_gain);
    try std.testing.expectEqual(@as(u64, 1), metrics.player_medium_tanks_built);
}

test "the armour bounty is paid per tank kill, not for owning a tank" {
    // Paying heavily to BUILD the first tank invites rushing one out to be deleted by rocket
    // infantry. The tank has to survive to contact and do work before the large reward lands.
    var reward_config: td.batch.RewardConfig = .{};
    reward_config.reward_milestone = 0.0;
    reward_config.reward_refinery = 0.0;
    reward_config.reward_vehicle = 0.0;
    reward_config.reward_tank_kill = 0.75;
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 4096, reward_config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});
    batch.worlds[0].easy_ai.active = false;

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};

    // Owning a tank pays nothing on its own.
    _ = batch.worlds[0].addUnit(.player, .medium_tank, .{ .x = 7, .y = 9 });
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectApproxEqAbs(@as(f32, 0), rewards[0], 0.0001);

    batch.worlds[0].metrics_tank_kills = 1;
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectApproxEqAbs(reward_config.reward_tank_kill, rewards[0], 0.0001);

    // Paid per kill, so three further kills pay three times -- a kill costs a real engagement and
    // cannot be manufactured the way an active-count delta could.
    batch.worlds[0].metrics_tank_kills = 4;
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectApproxEqAbs(3 * reward_config.reward_tank_kill, rewards[0], 0.0001);

    // A step with no new kill pays nothing.
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectApproxEqAbs(@as(f32, 0), rewards[0], 0.0001);
}

test "first tank and first tank shot rewards are each paid once per episode" {
    const reward_config: td.batch.RewardConfig = .{
        .reward_milestone = 0,
        .reward_player_infantry = 0,
        .reward_enemy_unit_loss = 0,
        .reward_enemy_building_loss = 0,
        .reward_player_unit_loss = 0,
        .reward_refinery = 0,
        .reward_first_delivery = 0,
        .reward_weapons_factory = 0,
        .reward_vehicle = 0,
        .reward_tiberium_income = 0,
        .reward_tank_kill = 0,
        .reward_first_tank = 0.2,
        .reward_first_tank_shot = 0.3,
    };
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 4096, reward_config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});
    batch.worlds[0].easy_ai.active = false;
    batch.milestones[0] = 0xffff;
    try std.testing.expect(batch.worlds[0].addBuilding(
        .player,
        .weapons_factory,
        .{ .x = 18, .y = 10 },
    ));
    for (&batch.worlds[0].buildings) |*building| {
        if (building.active) building.operational = true;
    }

    const player = @intFromEnum(td.Owner.player);
    const unit_queue = @intFromEnum(td.state.QueueKind.unit);
    batch.worlds[0].queues[player][unit_queue] = .{
        .active = true,
        .completed = true,
        .product = .medium_tank,
    };

    var observations: [td.policy.observation_size]u8 = undefined;
    var masks: [td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0};
    var terminals = [_]u8{0};
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectApproxEqAbs(reward_config.reward_first_tank, rewards[0], 0.0001);
    try std.testing.expectEqual(@as(u64, 1), batch.episode_metrics[0].first_tank_milestones);

    // Remove the first tank and finish a replacement. The lifetime built count, not the active
    // count, is the latch, so replacement cannot collect the reward again.
    for (&batch.worlds[0].units) |*unit| {
        if (unit.active and unit.owner == .player and unit.kind == .medium_tank) {
            unit.active = false;
        }
    }
    batch.worlds[0].queues[player][unit_queue] = .{
        .active = true,
        .completed = true,
        .product = .medium_tank,
    };
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectApproxEqAbs(@as(f32, 0), rewards[0], 0.0001);
    try std.testing.expectEqual(@as(u64, 1), batch.episode_metrics[0].first_tank_milestones);

    batch.worlds[0].metrics_tank_shots = 1;
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectApproxEqAbs(reward_config.reward_first_tank_shot, rewards[0], 0.0001);
    try std.testing.expectEqual(@as(u64, 1), batch.episode_metrics[0].first_tank_shot_milestones);

    batch.worlds[0].metrics_tank_shots = 2;
    batch.step(&[_]td.policy.RawAction{.{}}, &observations, &masks, &rewards, &terminals);
    try std.testing.expectApproxEqAbs(@as(f32, 0), rewards[0], 0.0001);
    try std.testing.expectEqual(@as(u64, 1), batch.episode_metrics[0].first_tank_shot_milestones);
}

test "only a real full-match loss after using a tank receives the qualified penalty" {
    const reward_config: td.batch.RewardConfig = .{ .reward_qualified_loss = -0.5 };
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 2, 4096, reward_config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{ 1, 2 });

    for (batch.worlds) |*world| {
        world.easy_ai.active = false;
        world.players[@intFromEnum(td.Owner.player)].defeated = true;
        world.players[@intFromEnum(td.Owner.player)].harvested_credits =
            reward_config.economy_win_credits;
    }
    batch.episode_metrics[0].player_medium_tanks_built = reward_config.full_win_min_tanks;
    batch.worlds[0].metrics_tank_shots = reward_config.full_win_min_tank_shots;
    // Lane one mined enough but never built or fired a tank, so it remains an ordinary loss.

    var observations: [2 * td.policy.observation_size]u8 = undefined;
    var masks: [2 * td.policy.action_mask_size]u8 = undefined;
    var rewards = [_]f32{0} ** 2;
    var terminals = [_]u8{0} ** 2;
    batch.step(&([_]td.policy.RawAction{.{}} ** 2), &observations, &masks, &rewards, &terminals);

    try std.testing.expectEqual([_]u8{1} ** 2, terminals);
    try std.testing.expectApproxEqAbs(reward_config.reward_qualified_loss, rewards[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -1), rewards[1], 0.0001);
    try std.testing.expectEqual(@as(u64, 2), batch.stats.losses);
    try std.testing.expectEqual(@as(u64, 1), batch.metrics.qualified_losses);
}
