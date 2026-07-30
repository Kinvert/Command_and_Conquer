const std = @import("std");
const td = @import("td_micro");

// Vehicles had a complete firing path -- tickUnitWeapons, turret aiming, cooldown, fireUnit,
// projectile flight -- and no way to ever acquire a target. unit.target was never set, so a tank
// drove around with a working gun and never used it.
//
// Infantry get this from mission_guard calling nearestEnemyInRange. Units get the same.

test "a vehicle acquires a target on its own, like infantry on guard" {
    var world = td.combat.tankDuelFixture();
    var armed = false;
    var frame: usize = 0;
    while (frame < 600 and !armed) : (frame += 1) {
        _ = td.step.advanceWithEasyAI(&world);
        for (world.units) |u| {
            if (u.active and u.owner == .player and u.kind == .medium_tank and
                td.combat.hasTarget(u)) armed = true;
        }
    }
    try std.testing.expect(armed);
}

test "a vehicle that acquires a target actually fires" {
    var world = td.combat.tankDuelFixture();
    var frame: usize = 0;
    while (frame < 1200) : (frame += 1) {
        _ = td.step.advanceWithEasyAI(&world);
        if (world.metrics_tank_shots > 0) break;
    }
    try std.testing.expect(world.metrics_tank_shots > 0);
}

test "shots fired are counted per world so training can see them" {
    var world = td.combat.tankDuelFixture();
    try std.testing.expectEqual(@as(u32, 0), world.metrics_tank_shots);
}

test "tanks beat humvees, end to end through the simulator" {
    // Rock-paper-scissors sanity: a medium tank is 400hp with a 30-damage 105mm; a humvee is 150hp
    // with an m60. Equal numbers should end with the tanks alive and the humvees dead. If this
    // fails, vehicle combat is not working regardless of what the policy does.
    var world = td.World.reset(1);
    world.players[@intFromEnum(td.state.Owner.opponent)].controller = .policy;
    world.easy_ai.active = false;

    var slot: usize = 2; // 0 and 1 are the starting MCVs; removing them flags a side defeated
    for (0..3) |i| {
        world.units[slot] = .{
            .active = true,
            .kind = .medium_tank,
            .owner = .player,
            .position = .{ .x = 20, .y = @intCast(20 + i) },
            .health = td.rules.object(.medium_tank).?.strength,
            .coord_x = 5248,
            .coord_y = @intCast(5248 + i * 256),
            .facing = 64,
            .turret_facing = 64,
            .mission = 4,
        };
        slot += 1;
    }
    for (0..3) |i| {
        world.units[slot] = .{
            .active = true,
            .kind = .humvee,
            .owner = .opponent,
            .position = .{ .x = 22, .y = @intCast(20 + i) },
            .health = td.rules.object(.humvee).?.strength,
            .coord_x = 5760,
            .coord_y = @intCast(5248 + i * 256),
            .facing = 192,
            .turret_facing = 192,
            .mission = 4,
        };
        slot += 1;
    }

    var frame: usize = 0;
    while (frame < 4000) : (frame += 1) {
        _ = td.step.advanceWithEasyAI(&world);
        var humvees: usize = 0;
        for (world.units) |u| if (u.active and u.owner == .opponent and u.kind == .humvee) {
            humvees += 1;
        };
        if (humvees == 0) break;
    }

    var tanks: usize = 0;
    var humvees: usize = 0;
    for (world.units) |u| {
        if (!u.active) continue;
        if (u.owner == .player and u.kind == .medium_tank) tanks += 1;
        if (u.owner == .opponent and u.kind == .humvee) humvees += 1;
    }
    std.debug.print("\n  tanks vs humvees after {d} frames: tanks={d} humvees={d} shots={d}\n", .{ frame, tanks, humvees, world.metrics_tank_shots });
    try std.testing.expect(world.metrics_tank_shots > 0);
    try std.testing.expectEqual(@as(usize, 0), humvees);
    try std.testing.expect(tanks > 0);
}

test "a tank can be commanded to attack and joins an ABI14 group wave" {
    // Auto-engage alone means tanks only defend. Commanded attacks are what put armour in a wave.
    var world = td.combat.tankDuelFixture();
    // The slot walk counts only this owner's active units, so the tank follows the player MCV at
    // slot 1 even though it occupies units[2].
    const cmd = td.Action{ .command = .attack, .target_kind = .visible_enemy, .actor = 1, .target_slot = 0 };
    try std.testing.expect(td.combat.canApply(&world, .player, cmd));
    try std.testing.expect(td.combat.apply(&world, .player, cmd));
    try std.testing.expect(td.combat.hasTarget(world.units[2]));

    var mask: [td.policy_abi14.action_mask_size]u8 = undefined;
    td.policy_abi14.actionMask(&world, &mask);
    var selectable: usize = 0;
    for (0..td.policy_abi14.selector_count) |slot| {
        if (td.policy_abi14.selectorMask(&mask, slot)[1] != 0) selectable += 1;
    }
    try std.testing.expect(selectable > 0);
}

test "applied attack telemetry records actor and target types" {
    var e1_world = td.combat.e1DuelFixture();
    try std.testing.expect(!td.combat.apply(&e1_world, .player, .{
        .command = .attack,
        .actor = 1,
        .target_kind = .visible_enemy,
        .target_slot = 63,
    }));
    try std.testing.expectEqual(@as(u32, 0), e1_world.metrics_player_e1_attack_orders);
    try std.testing.expect(td.combat.apply(&e1_world, .player, .{
        .command = .attack,
        .actor = 1,
        .target_kind = .visible_enemy,
        .target_slot = 1,
    }));
    try std.testing.expectEqual(@as(u32, 1), e1_world.metrics_player_e1_attack_orders);
    try std.testing.expectEqual(@as(u32, 1), e1_world.metrics_player_e1_infantry_targets);

    var e3_world = td.combat.e3DuelFixture();
    try std.testing.expect(td.combat.apply(&e3_world, .player, .{
        .command = .attack,
        .actor = 1,
        .target_kind = .visible_enemy,
        .target_slot = 0,
    }));
    try std.testing.expectEqual(@as(u32, 1), e3_world.metrics_player_e3_attack_orders);
    try std.testing.expectEqual(@as(u32, 1), e3_world.metrics_player_e3_vehicle_targets);

    var tank_world = td.combat.tankDuelFixture();
    tank_world.infantry[0].kind = .e3;
    tank_world.infantry[0].health = td.rules.object(.e3).?.strength;
    try std.testing.expect(td.combat.apply(&tank_world, .player, .{
        .command = .attack,
        .actor = 1,
        .target_kind = .visible_enemy,
        .target_slot = 1,
    }));
    try std.testing.expectEqual(@as(u32, 1), tank_world.metrics_player_tank_attack_orders);
    try std.testing.expectEqual(@as(u32, 1), tank_world.metrics_player_tank_e3_targets);
}

test "tank deaths caused by E3 are attributed separately" {
    var world = td.combat.tankDuelFixture();
    world.infantry[0].kind = .e3;
    world.infantry[0].health = td.rules.object(.e3).?.strength;
    world.units[2].health = 1;
    // Keep the tank from killing its attacker; only the opponent E3 should fire.
    world.units[2].mission = 2;
    try std.testing.expect(td.combat.apply(&world, .opponent, .{
        .command = .attack,
        .actor = 1,
        .target_kind = .visible_enemy,
        .target_slot = 1,
    }));

    var frame: usize = 0;
    while (frame < 1_000 and world.units[2].active) : (frame += 1) {
        _ = td.step.advanceWithEasyAI(&world);
    }
    try std.testing.expect(!world.units[2].active);
    try std.testing.expectEqual(@as(u32, 1), world.metrics_player_tank_losses);
    try std.testing.expectEqual(@as(u32, 1), world.metrics_player_tank_losses_to_e3);
}

test "a tank fires at a moving target, not just a stationary one" {
    // canUnitFire required turret_facing to equal the desired facing exactly, which made the
    // |difference| < 8 tolerance below it unreachable. A stationary duel converges exactly and
    // fires; a moving enemy changes the desired facing every frame, so the turret chases and never
    // matches. Five million steps of real games produced zero shots because of it.
    var world = td.combat.tankDuelFixture();
    // Push the enemy out to a distance it must close, so it is moving when engaged.
    world.infantry[0].coord_x = 5248 + 900;
    world.infantry[0].position = .{ .x = 23, .y = 20 };
    world.infantry[0].mission = 13; // hunt: walk at the player

    var frame: usize = 0;
    while (frame < 2000 and world.metrics_tank_shots == 0) : (frame += 1) {
        _ = td.step.advanceWithEasyAI(&world);
    }
    std.debug.print("\n  moving-target shots after {d} frames: {d}\n", .{ frame, world.metrics_tank_shots });
    try std.testing.expect(world.metrics_tank_shots > 0);
}

test "tank shots reach the episode metrics, not just the world" {
    // player_tank_shots was declared in Metrics and summed in add() but never assigned, so the
    // reported metric was 0 across a full 5M run while tanks were demonstrably firing.
    var batch = try td.batch.Batch.init(std.testing.allocator, 1, 4096);
    defer batch.deinit(std.testing.allocator);
    try batch.reset(&[_]u64{1});
    batch.worlds[0].metrics_tank_shots = 7;

    var observation: [td.policy.observation_size]u8 = undefined;
    var mask: [td.policy_abi9.action_mask_size]u8 = undefined;
    var reward = [_]f32{0};
    var terminal = [_]u8{0};
    const noop = [_]td.policy_abi9.RawAction{.{ .command = @intFromEnum(td.Command.noop), .actor = td.policy_abi9.actor_none }};
    batch.stepAbi9(&noop, &observation, &mask, &reward, &terminal);

    try std.testing.expect(batch.episode_metrics[0].player_tank_shots >= 7);
}
