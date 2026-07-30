// TEMPORARY DIAGNOSTIC -- not part of the parity suite. Drives a batch under the sweep's env
// configuration with mask-legal random actions and prints the census at the first failures, so
// "which capacity overflowed" is a measurement rather than a hypothesis.
const std = @import("std");
const td = @import("td_micro");

const world_count = 64;

test "failure census probe" {
    var batch = try td.batch.Batch.initWithConfigs(
        std.testing.allocator,
        world_count,
        12000, // env.max_decisions
        .{},
        .reverse_curriculum, // env.curriculum_schedule_id = 1
        512, // env.curriculum_stage_decisions
        2048, // env.starting_force_ramp_decisions
        .easy_to_normal, // env.difficulty_schedule_id = 1
        32768, // env.difficulty_ramp_decisions
    );
    defer batch.deinit(std.testing.allocator);

    var seeds: [world_count]u64 = undefined;
    // Scenario 1 defines only the close (1) and medium (2) spawn profiles.
    for (&seeds, 0..) |*s, i| s.* = if (i % 2 == 0) 1 else 2;
    try batch.reset(&seeds);

    const obs = try std.testing.allocator.alloc(u8, world_count * td.policy.observation_size);
    defer std.testing.allocator.free(obs);
    const masks = try std.testing.allocator.alloc(u8, world_count * td.policy_abi14.action_mask_size);
    defer std.testing.allocator.free(masks);
    var rewards = [_]f32{0} ** world_count;
    var terminals = [_]u8{0} ** world_count;
    var actions = [_]td.policy_abi14.RawAction{.{}} ** world_count;

    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rand = prng.random();

    var reported: usize = 0;
    var steps: usize = 0;
    while (steps < 200_000 and reported < 12) : (steps += 1) {
        for (&actions, 0..) |*act, index| {
            const mask = masks[index * td.policy_abi14.action_mask_size ..][0..td.policy_abi14.action_mask_size];
            act.* = randomLegalAction(rand, mask);
        }
        const before = batch.stats.failures;
        batch.stepAbi14(&actions, obs, masks, &rewards, &terminals);
        if (batch.stats.failures != before) {
            const c = batch.last_failure;
            std.debug.print(
                "FAILURE {s}: free_units={d} buildings={d}/{d} infantry={d}/{d} proj={d}/{d} fires={d} frame={d}\n",
                .{
                    @tagName(c.kind),        c.free_unit_slots, c.buildings, td.rules.max_buildings,
                    c.infantry,              td.rules.max_infantry, c.projectiles, td.rules.max_projectiles,
                    c.building_fires,        c.frame,
                },
            );
            reported += 1;
        }
    }
    std.debug.print("probe done: steps={d} failures={d}\n", .{ steps, batch.stats.failures });
}

fn randomLegalAction(rand: std.Random, mask: []const u8) td.policy_abi14.RawAction {
    var act = td.policy_abi14.RawAction{};
    // The seven ABI9 heads are contiguous and sized by action_head_sizes; pick uniformly among
    // the legal entries of each. Deriving the layout here keeps the probe honest if a head resizes.
    const sizes = td.policy_abi9.action_head_sizes;
    var picks: [sizes.len]u8 = undefined;
    var offset: usize = 0;
    for (sizes, 0..) |size, head| {
        picks[head] = @intCast(pickLegal(rand, mask[offset..][0..size], 0));
        offset += size;
    }
    // Uniform random play barely builds, and the failures under investigation only appear under
    // trained behaviour that produces hard. Bias strongly toward the production commands so the
    // probe drives the capacities the way a real policy does.
    const build_commands = [_]u8{
        @intFromEnum(td.action.Command.deploy),
        @intFromEnum(td.action.Command.start_build),
        @intFromEnum(td.action.Command.place),
        @intFromEnum(td.action.Command.train),
    };
    // A trained policy both produces hard and attacks constantly; the attack side is what drives
    // the projectile pool, so the probe has to exercise both to be a fair reproduction.
    const attack_commands = [_]u8{
        @intFromEnum(td.action.Command.attack),
        @intFromEnum(td.action.Command.hunt),
        @intFromEnum(td.action.Command.move),
    };
    act.command = picks[0];
    const roll = rand.uintLessThan(u8, 100);
    const wanted = if (roll < 50)
        build_commands[rand.uintLessThan(usize, build_commands.len)]
    else if (roll < 85)
        attack_commands[rand.uintLessThan(usize, attack_commands.len)]
    else
        act.command;
    if (mask[wanted] != 0) act.command = wanted;
    act.actor = picks[1];
    act.product = picks[2];
    act.target_kind = picks[3];
    act.target_x = picks[4];
    act.target_y = picks[5];
    act.target_slot = picks[6];
    // Selector head: one bit per addressable slot, legal only where the mask says so.
    for (&act.selectors, 0..) |*s, slot| {
        const legal = mask[offset + slot] != 0;
        s.* = if (legal) rand.uintLessThan(u8, 2) else 0;
    }
    return act;
}

fn pickLegal(rand: std.Random, head: []const u8, fallback: usize) usize {
    var legal: usize = 0;
    for (head) |v| {
        if (v != 0) legal += 1;
    }
    if (legal == 0) return fallback;
    var choice = rand.uintLessThan(usize, legal);
    for (head, 0..) |v, i| {
        if (v == 0) continue;
        if (choice == 0) return i;
        choice -= 1;
    }
    return fallback;
}
