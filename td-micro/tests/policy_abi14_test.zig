const std = @import("std");
const td = @import("td_micro");

test "ABI14 adds 64 independent binary selectors to ABI9" {
    try std.testing.expectEqual(@as(u32, 14), td.policy_abi14.abi_version);
    try std.testing.expectEqual(@as(usize, 71), td.policy_abi14.action_head_count);
    try std.testing.expectEqual(@as(usize, 410), td.policy_abi14.action_logit_count);
    try std.testing.expectEqual(@as(usize, 474), td.policy_abi14.action_mask_size);
    try std.testing.expectEqual(@as(usize, 71), @sizeOf(td.policy_abi14.RawAction));
    try std.testing.expectEqualSlices(
        u16,
        &td.policy_abi9.action_head_sizes,
        td.policy_abi14.action_head_sizes[0..td.policy_abi9.action_head_count],
    );
    for (td.policy_abi14.action_head_sizes[td.policy_abi9.action_head_count..]) |size| {
        try std.testing.expectEqual(@as(u16, 2), size);
    }
}

test "ABI14 selectors follow observable entity slots" {
    var world = twoPlayerInfantryFixture();
    var mask: [td.policy_abi14.action_mask_size]u8 = undefined;
    td.policy_abi14.actionMask(&world, &mask);

    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 1, 0 },
        td.policy_abi14.selectorMask(&mask, 0),
    );
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 1, 1 },
        td.policy_abi14.selectorMask(&mask, 1),
    );
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 1, 1 },
        td.policy_abi14.selectorMask(&mask, 2),
    );
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ 1, 0 },
        td.policy_abi14.selectorMask(&mask, 3),
    );
    try std.testing.expectEqual(@as(u8, 1), td.policy_abi14.attackTargetMask(&mask)[0]);
    try std.testing.expectEqual(@as(u8, 1), td.policy_abi14.attackTargetMask(&mask)[1]);
    try std.testing.expectEqual(@as(u8, 0), td.policy_abi14.attackTargetMask(&mask)[2]);
}

test "ABI14 applies one target to a sparse selected group" {
    var world = twoPlayerInfantryFixture();
    var raw = attackRaw();
    raw.selectors[1] = 1;
    raw.selectors[2] = 1;

    try std.testing.expect(td.policy_abi14.apply(&world, .player, raw));
    try std.testing.expect(world.infantry[0].attack_pending);
    try std.testing.expect(world.infantry[2].attack_pending);
    try std.testing.expectEqual(world.infantry[0].target, world.infantry[2].target);
}

test "ABI14 rejects an empty group attack and leaves the world untouched" {
    // Previously accepted as a canonical no-op. That made attacking free: the action changed
    // nothing, cost nothing, and counted as accepted, so it carried no learning signal at all.
    // It is now an invalid action, while still mutating nothing.
    var world = twoPlayerInfantryFixture();
    const before = td.digest.canonical(&world);

    try std.testing.expect(!td.policy_abi14.apply(&world, .player, attackRaw()));
    try std.testing.expectEqualSlices(u8, &before, &td.digest.canonical(&world));
}

test "ABI14 applies the valid selections in a group and ignores ineligible slots" {
    // Previously the whole group was rejected if any selected slot was ineligible. With 64
    // independently sampled selector heads a fully valid random selection essentially never occurs,
    // so the command was unreachable during exploration and the policy could never learn it.
    // Slot 0 is an eligible player infantry here; slot 1 is not.
    var world = twoPlayerInfantryFixture();
    const before = td.digest.canonical(&world);
    var raw = attackRaw();
    raw.selectors[0] = 1;
    raw.selectors[1] = 1;

    try std.testing.expect(td.policy_abi14.apply(&world, .player, raw));
    // The eligible selection took effect, so the world must have changed.
    try std.testing.expect(!std.mem.eql(u8, &before, &td.digest.canonical(&world)));
    try std.testing.expect(world.infantry[0].attack_pending);
}

test "ABI14 rejects non-binary selector values" {
    var world = twoPlayerInfantryFixture();
    const before = td.digest.canonical(&world);
    var raw = attackRaw();
    raw.selectors[1] = 2;

    try std.testing.expect(!td.policy_abi14.apply(&world, .player, raw));
    try std.testing.expectEqualSlices(u8, &before, &td.digest.canonical(&world));
}

test "ABI14 group trace is deterministic across simulation decisions" {
    var first = twoPlayerInfantryFixture();
    var second = first;
    var raw = attackRaw();
    raw.selectors[1] = 1;
    raw.selectors[2] = 1;

    for (0..128) |decision| {
        if (decision == 0) {
            try std.testing.expect(td.policy_abi14.apply(&first, .player, raw));
            try std.testing.expect(td.policy_abi14.apply(&second, .player, raw));
        }
        _ = td.step.advanceWithEasyAI(&first);
        _ = td.step.advanceWithEasyAI(&second);
        try std.testing.expectEqualSlices(
            u8,
            &td.digest.canonical(&first),
            &td.digest.canonical(&second),
        );
    }
    const expected = [_]u8{
        0x29, 0x4b, 0xe0, 0x2c, 0xc1, 0xbd, 0x0b, 0x36,
        0x72, 0xdf, 0x4c, 0x42, 0xf7, 0xf0, 0x3d, 0xc7,
        0xa7, 0xf0, 0x7d, 0x81, 0x78, 0xd1, 0xda, 0x98,
        0x01, 0x38, 0x4e, 0x94, 0x92, 0xea, 0xb4, 0x25,
    };
    try std.testing.expectEqualSlices(u8, &expected, &td.digest.canonical(&first));
}

fn attackRaw() td.policy_abi14.RawAction {
    return .{
        .command = @intFromEnum(td.Command.attack),
        .actor = td.policy_abi14.actor_none,
        .product = 0,
        .target_kind = @intFromEnum(td.action.TargetKind.visible_enemy),
        .target_slot = 0,
    };
}

fn twoPlayerInfantryFixture() td.World {
    var world = td.combat.e1DuelFixture();
    world.infantry[2] = .{
        .active = true,
        .kind = .e3,
        .owner = .player,
        .position = .{ .x = 19, .y = 20 },
        .health = td.rules.object(.e3).?.strength,
        .coord_x = 4992,
        .coord_y = 5248,
        .facing = 64,
        .ammo = -1,
        .second_shot = true,
    };
    world.infantry_count = 3;
    return world;
}

// ---- Attack reachability ----------------------------------------------------------------------
//
// Measured on the trained 0.588 checkpoint: 0 of 140 sampled attacks were structurally valid, and
// 0 of 226 applied through the Vanilla bridge. apply required actor, product, target_x and
// target_y to hold exact sentinel values simultaneously, while the action mask constrained none of
// them, so the sampler had to hit one combination in roughly 6.4 million by chance. It never did,
// in training or in deployment -- the group-attack primitive was unreachable for its whole life.
//
// For a group attack the selectors carry the actors and the target slot carries the target, so
// those four fields are semantically unused. Ignoring them is what makes the command reachable.

test "a group attack is accepted regardless of the fields it does not use" {
    // A duel fixture is the smallest world with an attack-capable player infantry and a visible
    // enemy; a bare World.reset has neither, and the batch reset that does add a starting force
    // goes through the curriculum rather than World.reset.
    var world = td.combat.e1DuelFixture();
    var mask: [td.policy_abi14.action_mask_size]u8 = undefined;
    td.policy_abi14.actionMask(&world, &mask);

    var selected_any = false;
    var raw: td.policy_abi14.RawAction = .{
        .command = @intFromEnum(td.action.Command.attack),
        // Deliberately junk in every unused field.
        .actor = 7,
        .product = 3,
        .target_kind = @intFromEnum(td.action.TargetKind.visible_enemy),
        .target_x = 42,
        .target_y = 17,
        .target_slot = 0,
    };
    for (0..td.policy_abi14.selector_count) |slot| {
        if (td.policy_abi14.selectorMask(&mask, slot)[1] != 0) {
            raw.selectors[slot] = 1;
            selected_any = true;
            break;
        }
    }
    try std.testing.expect(selected_any);
    try std.testing.expect(td.policy_abi14.attackTargetMask(&mask)[0] != 0);

    try std.testing.expect(td.policy_abi14.apply(&world, .player, raw));
}

test "a group attack still requires a legal target and binary selectors" {
    var world = td.combat.e1DuelFixture();
    var raw: td.policy_abi14.RawAction = .{
        .command = @intFromEnum(td.action.Command.attack),
        .target_kind = @intFromEnum(td.action.TargetKind.visible_enemy),
        .target_slot = 200, // out of range
    };
    try std.testing.expect(!td.policy_abi14.apply(&world, .player, raw));

    raw.target_slot = 0;
    raw.selectors[0] = 2; // not binary
    try std.testing.expect(!td.policy_abi14.apply(&world, .player, raw));
}


// ---- Valid-subset group attack ----------------------------------------------------------------
//
// All-or-nothing made the command unreachable under exploration. Training samples 64 selector heads
// independently, so roughly half the slots get selected and nearly all point at entities that are
// not attack-capable infantry; requiring every one to be valid rejects the group essentially always.
// A policy cannot learn a primitive it has never once executed. Applying the valid subset makes a
// single good selection sufficient, which is what lets gradient reach the selector heads.

test "a group attack applies its valid selections and ignores the invalid ones" {
    var world = td.combat.e1DuelFixture();
    var mask: [td.policy_abi14.action_mask_size]u8 = undefined;
    td.policy_abi14.actionMask(&world, &mask);

    var raw: td.policy_abi14.RawAction = .{
        .command = @intFromEnum(td.action.Command.attack),
        .target_kind = @intFromEnum(td.action.TargetKind.visible_enemy),
        .target_slot = 0,
    };
    // One genuinely selectable slot, plus junk selections the mask forbids.
    var valid_slot: ?usize = null;
    for (0..td.policy_abi14.selector_count) |slot| {
        if (td.policy_abi14.selectorMask(&mask, slot)[1] != 0) {
            valid_slot = slot;
            break;
        }
    }
    try std.testing.expect(valid_slot != null);
    raw.selectors[valid_slot.?] = 1;
    // Slots far beyond anything the player owns: previously these sank the whole group.
    raw.selectors[60] = 1;
    raw.selectors[61] = 1;
    raw.selectors[62] = 1;

    try std.testing.expect(td.policy_abi14.apply(&world, .player, raw));
}

test "a group attack with no valid selection is rejected" {
    // Still an invalid action: nothing happened, so it must not be silently accepted as a no-op or
    // the policy learns that attacking is free.
    var world = td.combat.e1DuelFixture();
    var raw: td.policy_abi14.RawAction = .{
        .command = @intFromEnum(td.action.Command.attack),
        .target_kind = @intFromEnum(td.action.TargetKind.visible_enemy),
        .target_slot = 0,
    };
    raw.selectors[60] = 1;
    raw.selectors[61] = 1;
    try std.testing.expect(!td.policy_abi14.apply(&world, .player, raw));
}

test "a group attack selecting nothing at all is rejected" {
    var world = td.combat.e1DuelFixture();
    const raw: td.policy_abi14.RawAction = .{
        .command = @intFromEnum(td.action.Command.attack),
        .target_kind = @intFromEnum(td.action.TargetKind.visible_enemy),
        .target_slot = 0,
    };
    try std.testing.expect(!td.policy_abi14.apply(&world, .player, raw));
}

// ---- Selectors are attack-only ----------------------------------------------------------------
//
// PufferLib samples all 71 heads every step and cnc_micro_decode_actions copies them verbatim, so a
// build or move action routinely arrives with selectors set. Rejecting those made the two
// requirements contradictory: non-attack commands only worked with all-zero selectors, but attacks
// need non-zero selectors to do anything. Non-attack commands dominate, so the policy drove every
// selector to zero permanently and the group attack could never fire.
//
// Selectors carry no meaning outside an attack, so they are simply ignored there.

test "a non-attack command ignores selectors instead of being rejected by them" {
    var world = td.combat.e1DuelFixture();
    const before = td.digest.canonical(&world);

    var raw: td.policy_abi14.RawAction = .{ .command = @intFromEnum(td.action.Command.noop) };
    raw.selectors[0] = 1;
    raw.selectors[9] = 1;

    // A noop with stray selectors is still a valid noop.
    try std.testing.expect(td.policy_abi14.apply(&world, .player, raw));
    try std.testing.expectEqualSlices(u8, &before, &td.digest.canonical(&world));
}

test "non-binary selectors remain invalid for every command" {
    var world = td.combat.e1DuelFixture();
    var raw: td.policy_abi14.RawAction = .{ .command = @intFromEnum(td.action.Command.noop) };
    raw.selectors[2] = 3;
    try std.testing.expect(!td.policy_abi14.apply(&world, .player, raw));
}

// ---- Economy gate -----------------------------------------------------------------------------
//
// Reward shaping cannot make the agent build a refinery: at 2000 credits it is a worse buy than
// infantry under every weighting tried, up to the sweep maxima (refinery 0.6, first delivery 0.4),
// and the policy simply rushes instead. Penalising the alternative fails too -- that teaches
// avoidance of the penalised action rather than the intended ordering.
//
// So the barracks is withheld from the mask until a refinery exists. The wrong opening becomes
// unavailable rather than expensive, which produces no gradient to game and cannot be traded off.
// Enforced in the mask so it is identical in ABI9 and ABI14 and mirrors into the Vanilla bridge.

test "the barracks is not offered until a refinery exists" {
    var world = td.World.reset(1);
    // A construction yard so structures are buildable at all, and money for anything.
    std.debug.assert(world.addBuilding(.player, .construction_yard, .{ .x = 10, .y = 10 }));
    world.buildings[world.building_count - 1].operational = true;
    world.buildings[world.building_count - 1].construction_frames = 0;
    std.debug.assert(world.addBuilding(.player, .power_plant, .{ .x = 14, .y = 10 }));
    world.buildings[world.building_count - 1].operational = true;
    world.buildings[world.building_count - 1].construction_frames = 0;
    world.players[@intFromEnum(td.state.Owner.player)].credits = 10_000;

    var mask: [td.policy_abi14.action_mask_size]u8 = undefined;
    td.policy_abi14.actionMask(&world, &mask);
    const build_base = 12 + 65; // command(12) + actor(65) -> product head
    const barracks = @intFromEnum(td.policy_abi9.Product.barracks);
    const refinery = @intFromEnum(td.policy_abi9.Product.refinery);
    try std.testing.expectEqual(@as(u8, 0), mask[build_base + barracks]);
    try std.testing.expect(mask[build_base + refinery] != 0);

    // Once a refinery exists the barracks becomes available again.
    std.debug.assert(world.addBuilding(.player, .refinery, .{ .x = 18, .y = 10 }));
    world.buildings[world.building_count - 1].operational = true;
    world.buildings[world.building_count - 1].construction_frames = 0;
    td.policy_abi14.actionMask(&world, &mask);
    try std.testing.expect(mask[build_base + barracks] != 0);
}

test "the harvester is not selectable, so it keeps mining" {
    // economy.zig assigns mission_harvest the moment a refinery spawns a harvester, and it mines the
    // nearest tiberium on its own exactly as Vanilla does. Leaving it in the actor mask let the
    // policy issue move orders to it -- and it issues over a thousand per game -- which pulled it
    // off the field and killed the economy. Adding a harvester must not add anything selectable.
    var world = td.World.reset(1);
    var mask: [td.policy_abi14.action_mask_size]u8 = undefined;
    const actor_base = 12; // the command head is 12 wide; the actor head follows

    td.policy_abi14.actionMask(&world, &mask);
    var before: usize = 0;
    for (0..64) |slot| before += @intFromBool(mask[actor_base + slot] != 0);

    var added = false;
    for (&world.units) |*unit| {
        if (unit.active) continue;
        unit.* = .{ .active = true, .owner = .player, .kind = .harvester, .health = 100 };
        added = true;
        break;
    }
    try std.testing.expect(added);

    td.policy_abi14.actionMask(&world, &mask);
    var after: usize = 0;
    for (0..64) |slot| after += @intFromBool(mask[actor_base + slot] != 0);
    try std.testing.expectEqual(before, after);

    // And it enables no harvester-only commands.
    try std.testing.expectEqual(@as(u8, 0), mask[@intFromEnum(td.action.Command.harvest)]);
    try std.testing.expectEqual(@as(u8, 0), mask[@intFromEnum(td.action.Command.return_cargo)]);
}
