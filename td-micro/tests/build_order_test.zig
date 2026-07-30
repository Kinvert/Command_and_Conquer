const std = @import("std");
const td = @import("td_micro");

// Build-order shaping.
//
// The trained ABI14 policy wins by producing infantry and walking them into contact, and it opens
// with whatever structure it likes. On constrained-credit starts (2300) there is not enough money to
// recover from a barracks-first opening, so the intended opening is power plant -> refinery.
//
// These tests pin an immediate, non-terminal penalty applied at the moment the wrong structure is
// queued -- start_build, not placement -- so the credit assignment is one decision wide. Queueing a
// refinery before a barracks is always fine and is never penalised.
//
// The detector is a pure function of world state rather than of the action encoding, so it behaves
// identically across ABI9/ABI13/ABI14 and cannot drift from whichever action shape is in use.

const player = td.state.Owner.player;
const structure_queue = @intFromEnum(td.state.QueueKind.structure);

fn queueOf(product: td.rules.ObjectType) td.state.ProductionQueue {
    return .{ .active = true, .completed = false, .product = product };
}

const idle_queue: td.state.ProductionQueue = .{};

test "build-order shaping is off by default" {
    // Every nonzero setting measured so far collapses balanced_perf from 0.588 to ~0.05, including
    // the -0.05/-0.2 floor. The mechanism stays available and sweepable, but must not be on by
    // default or it silently degrades every training run by 14x.
    const config: td.batch.RewardConfig = .{};
    try std.testing.expectEqual(@as(f32, 0.0), config.reward_build_order_violation_constrained);
    try std.testing.expectEqual(@as(f32, 0.0), config.reward_build_order_violation);
    try std.testing.expectEqual(@as(f32, 0.0), config.reward_build_order_sequence);
    try std.testing.expect(config.valid());
}

test "the ordered build sequence reward must be a reward, not a penalty" {
    const config: td.batch.RewardConfig = .{};
    try std.testing.expect(config.reward_build_order_sequence >= 0);
    try std.testing.expect(config.valid());

    var bad = config;
    bad.reward_build_order_sequence = -0.1;
    try std.testing.expect(!bad.valid());
}

test "build-order penalties must be penalties, not rewards" {
    var config: td.batch.RewardConfig = .{};
    config.reward_build_order_violation = 0.2;
    try std.testing.expect(!config.valid());

    config = .{};
    config.reward_build_order_violation_constrained = 0.75;
    try std.testing.expect(!config.valid());

    config = .{};
    config.reward_build_order_violation = std.math.nan(f32);
    try std.testing.expect(!config.valid());
}

test "queueing a barracks with no refinery is a violation" {
    var world = td.World.reset(1);
    // No refinery has been committed to, so a barracks is out of order.
    try std.testing.expect(td.batch.startedBarracksBeforeRefinery(&world, idle_queue, queueOf(.barracks)));
}

test "queueing a barracks after a refinery exists is not a violation" {
    var world = td.World.reset(1);
    // A refinery under construction still counts as committed: the player has paid for it.
    var placed = false;
    for (&world.buildings) |*building| {
        if (building.active) continue;
        building.* = .{
            .active = true,
            .owner = player,
            .kind = .refinery,
            .health = 1,
            .operational = false,
        };
        placed = true;
        break;
    }
    try std.testing.expect(placed);
    try std.testing.expect(!td.batch.startedBarracksBeforeRefinery(&world, idle_queue, queueOf(.barracks)));
}

test "queueing a refinery before a barracks is never a violation" {
    var world = td.World.reset(1);
    try std.testing.expect(!td.batch.startedBarracksBeforeRefinery(&world, idle_queue, queueOf(.refinery)));
    try std.testing.expect(!td.batch.startedBarracksBeforeRefinery(&world, idle_queue, queueOf(.power_plant)));
}

test "an unchanged barracks queue is not a fresh violation" {
    // The penalty fires on the start_build transition. A queue that was already building a barracks
    // must not be re-charged on every subsequent decision -- only a newly issued start_build counts.
    var world = td.World.reset(1);
    const already = queueOf(.barracks);
    try std.testing.expect(!td.batch.startedBarracksBeforeRefinery(&world, already, already));
}

test "an opponent refinery does not satisfy the player's build order" {
    var world = td.World.reset(1);
    var placed = false;
    for (&world.buildings) |*building| {
        if (building.active) continue;
        building.* = .{
            .active = true,
            .owner = .opponent,
            .kind = .refinery,
            .health = 1,
            .operational = true,
        };
        placed = true;
        break;
    }
    try std.testing.expect(placed);
    try std.testing.expect(td.batch.startedBarracksBeforeRefinery(&world, idle_queue, queueOf(.barracks)));
}

test "penalty magnitude is selected by the episode's starting credits" {
    const config = configured;
    // 2300 is the constrained bucket the curriculum uses; everything else is the ordinary rate.
    try std.testing.expectEqual(
        @as(f32, -0.2),
        td.batch.buildOrderPenalty(config, td.rules.starting_credits_constrained),
    );
    try std.testing.expectEqual(@as(f32, -0.05), td.batch.buildOrderPenalty(config, 2400));
    try std.testing.expectEqual(@as(f32, -0.05), td.batch.buildOrderPenalty(config, 10000));
}

test "constrained-start episodes are counted separately for win-rate reporting" {
    // The 2300 bucket is the one the shaping targets, so its win rate has to be visible on its own
    // rather than blended into balanced_perf.
    var stats: td.batch.Stats = .{};
    try std.testing.expectEqual(@as(u64, 0), stats.constrained_episodes);
    try std.testing.expectEqual(@as(u64, 0), stats.constrained_wins);
    try std.testing.expectEqual(@as(u64, 0), stats.build_order_violations);
}

// ---- Integration ------------------------------------------------------------------------------
//
// The pure-function tests above pin the rule; these prove it is actually wired into the step loop,
// which is where the equivalent ABI13 mask work went wrong (correct logic, never reached).

fn giveBuilding(world: *td.state.World, owner: td.state.Owner, kind: td.rules.ObjectType) void {
    // Uses the real constructor so building_count and power bookkeeping stay consistent; hand
    // injection leaves building_count stale and the building invisible to parts of the engine.
    std.debug.assert(world.addBuilding(owner, kind, .{ .x = 10, .y = 10 }));
    const placed = &world.buildings[world.building_count - 1];
    placed.operational = true;
    placed.construction_frames = 0;
}

/// Puts world 0 in a state where start_build(barracks) is legal: a construction yard to build from,
/// a placed power plant to satisfy the barracks prerequisite, and money.
fn readyToBuild(batch: *td.batch.Batch) void {
    const world = &batch.worlds[0];
    giveBuilding(world, .player, .construction_yard);
    giveBuilding(world, .player, .power_plant);
    world.players[@intFromEnum(td.state.Owner.player)].credits = 10_000;
}

const start_barracks = [_]td.policy_abi9.RawAction{.{
    .command = @intFromEnum(td.Command.start_build),
    .actor = td.policy_abi9.actor_none,
    .product = @intFromEnum(td.policy_abi9.Product.barracks),
}};

/// Runs the same scripted start_build(barracks) twice -- once with the build-order penalties zeroed
/// and once with `config` -- and returns the reward difference. Differencing isolates the penalty
/// from milestone and economy rewards, which the injected buildings also trigger; asserting on the
/// total reward would confound them.
fn penaltyDelta(config: td.batch.RewardConfig, starting_credits: i32, with_refinery: bool) !f32 {
    var control_config = config;
    control_config.reward_build_order_violation = 0;
    control_config.reward_build_order_violation_constrained = 0;

    var rewards: [2]f32 = undefined;
    for ([_]td.batch.RewardConfig{ control_config, config }, 0..) |cfg, run| {
        var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 4096, cfg);
        defer batch.deinit(std.testing.allocator);
        try batch.reset(&[_]u64{1});
        readyToBuild(&batch);
        if (with_refinery) giveBuilding(&batch.worlds[0], .player, .refinery);
        batch.starting_credits[0] = starting_credits;

        var observation: [td.policy.observation_size]u8 = undefined;
        var mask: [td.policy_abi9.action_mask_size]u8 = undefined;
        var reward = [_]f32{0};
        var terminal = [_]u8{0};
        batch.stepAbi9(&start_barracks, &observation, &mask, &reward, &terminal);
        try std.testing.expectEqual(@as(u8, 0), terminal[0]); // always non-terminal
        rewards[run] = reward[0];
    }
    return rewards[1] - rewards[0];
}

const configured: td.batch.RewardConfig = .{
    .reward_build_order_violation = -0.05,
    .reward_build_order_violation_constrained = -0.2,
};

test "an ordinary start pays the configured rate for queueing a barracks before a refinery" {
    const delta = try penaltyDelta(configured, 10_000, false);
    try std.testing.expectApproxEqAbs(@as(f32, -0.05), delta, 0.0001);
}

test "a constrained start pays the configured constrained rate for the same mistake" {
    const delta = try penaltyDelta(configured, td.rules.starting_credits_constrained, false);
    try std.testing.expectApproxEqAbs(@as(f32, -0.2), delta, 0.0001);
}

test "building a refinery first earns no build-order penalty" {
    const delta = try penaltyDelta(configured, td.rules.starting_credits_constrained, true);
    try std.testing.expectApproxEqAbs(@as(f32, 0), delta, 0.0001);
}

test "the violation is counted once per start_build, and repeats are charged again" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 4096);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});
    readyToBuild(&batch);
    batch.starting_credits[0] = td.rules.starting_credits_constrained;

    var observation: [td.policy.observation_size]u8 = undefined;
    var mask: [td.policy_abi9.action_mask_size]u8 = undefined;
    var reward = [_]f32{0};
    var terminal = [_]u8{0};

    batch.stepAbi9(&start_barracks, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.build_order_violations);
    // The queue is now busy, so a second start_build is rejected outright and must not re-charge.
    batch.stepAbi9(&start_barracks, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.build_order_violations);
}

// ---- Once per episode -------------------------------------------------------------------------

test "the build-order penalty is charged at most once per episode" {
    // Repeating the charge compounds the incentive to avoid barracks altogether, which is what
    // collapsed infantry production. One charge per episode still signals the mistake.
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 4096);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});
    readyToBuild(&batch);
    batch.starting_credits[0] = td.rules.starting_credits_constrained;

    var observation: [td.policy.observation_size]u8 = undefined;
    var mask: [td.policy_abi9.action_mask_size]u8 = undefined;
    var reward = [_]f32{0};
    var terminal = [_]u8{0};

    batch.stepAbi9(&start_barracks, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.build_order_violations);
    try std.testing.expect(batch.build_order_penalised[0]);

    // Clear the queue and offend again: the counter must not advance a second time.
    batch.worlds[0].queues[@intFromEnum(td.state.Owner.player)][@intFromEnum(td.state.QueueKind.structure)] = .{};
    batch.stepAbi9(&start_barracks, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(u64, 1), batch.stats.build_order_violations);
}

test "a fresh episode may be charged again" {
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 4096);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});
    batch.build_order_penalised[0] = true;
    batch.build_order_progress[0] = 2;
    batch.build_order_broken[0] = true;
    try batch.reset(&[_]u64{1});
    try std.testing.expect(!batch.build_order_penalised[0]);
    try std.testing.expectEqual(@as(u8, 0), batch.build_order_progress[0]);
    try std.testing.expect(!batch.build_order_broken[0]);
}

// ---- Ordered sequence reward ------------------------------------------------------------------

test "completing power plant -> refinery -> barracks in order pays the sequence reward once" {
    var config: td.batch.RewardConfig = .{};
    config.reward_build_order_sequence = 0.3;
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 4096, config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    const world = &batch.worlds[0];
    giveBuilding(world, .player, .construction_yard);
    world.players[@intFromEnum(td.state.Owner.player)].credits = 10_000;

    var observation: [td.policy.observation_size]u8 = undefined;
    var mask: [td.policy_abi9.action_mask_size]u8 = undefined;
    var reward = [_]f32{0};
    var terminal = [_]u8{0};
    const noop = [_]td.policy_abi9.RawAction{.{
        .command = @intFromEnum(td.Command.noop),
        .actor = td.policy_abi9.actor_none,
    }};

    giveBuilding(&batch.worlds[0], .player, .power_plant);
    batch.stepAbi9(&noop, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(u8, 1), batch.build_order_progress[0]);

    giveBuilding(&batch.worlds[0], .player, .refinery);
    batch.stepAbi9(&noop, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(u8, 2), batch.build_order_progress[0]);

    giveBuilding(&batch.worlds[0], .player, .barracks);
    batch.stepAbi9(&noop, &observation, &mask, &reward, &terminal);
    try std.testing.expectEqual(@as(u8, 3), batch.build_order_progress[0]);
    try std.testing.expect(reward[0] >= 0.3);

    // Already paid: a further step must not pay again.
    batch.stepAbi9(&noop, &observation, &mask, &reward, &terminal);
    try std.testing.expect(reward[0] < 0.3);
}

test "a barracks built before a refinery forfeits the sequence reward" {
    var config: td.batch.RewardConfig = .{};
    config.reward_build_order_sequence = 0.3;
    var batch = try td.batch.Batch.initWithRewardConfig(std.testing.allocator, 1, 4096, config);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});

    const world = &batch.worlds[0];
    giveBuilding(world, .player, .construction_yard);
    giveBuilding(world, .player, .power_plant);
    giveBuilding(world, .player, .barracks); // out of order

    var observation: [td.policy.observation_size]u8 = undefined;
    var mask: [td.policy_abi9.action_mask_size]u8 = undefined;
    var reward = [_]f32{0};
    var terminal = [_]u8{0};
    const noop = [_]td.policy_abi9.RawAction{.{
        .command = @intFromEnum(td.Command.noop),
        .actor = td.policy_abi9.actor_none,
    }};

    batch.stepAbi9(&noop, &observation, &mask, &reward, &terminal);
    giveBuilding(&batch.worlds[0], .player, .refinery);
    batch.stepAbi9(&noop, &observation, &mask, &reward, &terminal);
    // Progress stalls at the power plant: the sequence was broken and cannot be completed.
    try std.testing.expect(batch.build_order_progress[0] < 3);
    try std.testing.expect(reward[0] < 0.3);
}
