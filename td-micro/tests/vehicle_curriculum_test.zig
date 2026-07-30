const std = @import("std");
const td = @import("td_micro");

// CNC26 task 14: a curriculum stage that drills vehicle production.
//
// Measured across 116 sweep trials with reward_weapons_factory searched over 0 to 0.8: not one
// built a Weapons Factory, so weapons_factories_built and medium_tanks_built stayed at exactly
// 0.000. No price can pay for an action never attempted. Reaching armour requires refinery ->
// factory -> tank on top of surviving the opening, and the agent never completes that by chance.
//
// This profile starts with the tech already standing so a tank is one decision away, exactly as
// h2_mobilize does for infantry.

test "the armour profile starts with the factory standing and money for a tank" {
    var world = td.curriculum.resetForScheduledEpisode(
        1,
        .h2_armour,
        .reverse_curriculum,
        0,
        0,
        0,
        8192,
    );
    try std.testing.expect(world.failure == .none);

    const player = td.state.Owner.player;
    var has_yard = false;
    var has_power = false;
    var has_refinery = false;
    var has_factory = false;
    for (world.buildings[0..world.building_count]) |b| {
        if (!b.active or b.owner != player) continue;
        switch (b.kind) {
            .construction_yard => has_yard = true,
            .power_plant => has_power = true,
            .refinery => has_refinery = true,
            .weapons_factory => has_factory = true,
            else => {},
        }
    }
    try std.testing.expect(has_yard);
    try std.testing.expect(has_power);
    try std.testing.expect(has_refinery);
    try std.testing.expect(has_factory);
    // A medium tank is 800; the stage is pointless if it cannot afford one immediately.
    try std.testing.expect(world.players[@intFromEnum(player)].credits >= 800);
}

test "a tank is legal on the first decision of the armour profile" {
    var world = td.curriculum.resetForScheduledEpisode(1, .h2_armour, .reverse_curriculum, 0, 0, 0, 8192);
    try std.testing.expect(world.failure == .none);

    var mask: [td.policy_abi9.action_mask_size]u8 = undefined;
    td.policy_abi9.actionMask(&world, &mask);
    const product_base = 12 + 65;
    try std.testing.expect(mask[product_base + @intFromEnum(td.policy_abi9.Product.medium_tank)] != 0);
    try std.testing.expect(mask[product_base + @intFromEnum(td.policy_abi9.Product.humvee)] != 0);
}

test "the armour profile is a curriculum stage, not a full match" {
    // It shares h2_mobilize's horizon deliberately: same depth, armour instead of infantry.
    try std.testing.expect(td.curriculum.horizon(.h2_armour) != td.curriculum.horizon(.full_match));
    try std.testing.expectEqual(td.curriculum.horizon(.h2_mobilize), td.curriculum.horizon(.h2_armour));
}

test "the weapons factory has a placement footprint at all" {
    // It had none. placement.footprint() fell through to `else => null`, so isLegal returned false
    // on its first line for every cell on every map, and the Weapons Factory was unplaceable
    // everywhere, always. That is why weapons_factories_built was exactly 0.000 across every
    // training run and all 116 sweep trials -- not exploration depth, and not reward price.
    const fp = td.placement.footprint(.weapons_factory);
    try std.testing.expect(fp != null);
    // Vanilla's ListWeap is two rows of three starting one row down:
    //   {MCW, MCW+1, MCW+2, MCW*2, MCW*2+1, MCW*2+2}
    try std.testing.expectEqual(@as(usize, 6), fp.?.len);
    for (fp.?) |cell| {
        try std.testing.expect(cell.y == 1 or cell.y == 2);
        try std.testing.expect(cell.x >= 0 and cell.x <= 2);
    }
}

test "a built-up base has somewhere to put a weapons factory" {
    var world = td.curriculum.resetForScheduledEpisode(1, .h3_economy, .reverse_curriculum, 0, 0, 0, 8192);
    try std.testing.expect(world.failure == .none);
    var legal: usize = 0;
    for (0..world.map_height) |y| {
        for (0..world.map_width) |x| {
            if (td.placement.isLegal(&world, .player, .weapons_factory, .{ .x = @intCast(x), .y = @intCast(y) })) legal += 1;
        }
    }
    try std.testing.expect(legal > 0);
}

test "the armour stage is actually reachable from the schedule" {
    // Adding a profile is not enough: profileForProgress is what training samples, and a profile
    // missing from that table is dead code. The agent has to meet tanks repeatedly to learn they
    // are worth building.
    var seen_armour = false;
    var seen_full = false;
    var stage: u64 = 0;
    while (stage < 5) : (stage += 1) {
        var lane: usize = 0;
        while (lane < 100) : (lane += 1) {
            const p = td.curriculum.profileForProgress(
                .reverse_curriculum,
                1,
                lane,
                0,
                stage * 4096,
                4096,
            );
            if (p == .h2_armour) seen_armour = true;
            if (p == .full_match) seen_full = true;
        }
    }
    try std.testing.expect(seen_armour);
    try std.testing.expect(seen_full);
}
