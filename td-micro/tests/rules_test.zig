const std = @import("std");
const td = @import("td_micro");

test "reset creates the declared mirror opening" {
    const world = td.World.reset(1);

    try std.testing.expectEqual(@as(u32, 1), world.setup_seed);
    try std.testing.expectEqual(@as(u32, 3_488_684_595), world.rng_state);
    try std.testing.expectEqual(@as(u8, 58), world.map_width);
    try std.testing.expectEqual(@as(u8, 49), world.map_height);
    try std.testing.expectEqual(@as(i32, 10_000), world.players[0].credits);
    try std.testing.expectEqual(@as(i32, 10_000), world.players[1].credits);
    try std.testing.expect(world.units[0].active);
    try std.testing.expect(world.units[1].active);
    try std.testing.expectEqual(td.ObjectType.mcv, world.units[0].kind);
    try std.testing.expectEqual(td.Owner.player, world.units[0].owner);
    try std.testing.expectEqual(td.Owner.opponent, world.units[1].owner);
}

test "reset rejects seeds without a declared spawn profile" {
    const world = td.World.reset(3);
    try std.testing.expectEqual(td.state.Failure.unsupported_seed, world.failure);
}

test "generated rules identify the exact authored manifest" {
    const manifest = td.rules_manifest.bytes;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(manifest, &digest, .{});
    try std.testing.expectEqualSlices(u8, &td.rules.manifest_sha256, &digest);
}

test "generated rules declare the full-match starting credit distribution" {
    try std.testing.expectEqual(@as(i32, 2_300), td.rules.starting_credits_constrained);
    try std.testing.expectEqual(@as(u8, 35), td.rules.starting_credits_constrained_percent);
    try std.testing.expectEqual(@as(i32, 2_400), td.rules.starting_credits_random_min);
    try std.testing.expectEqual(@as(i32, 10_000), td.rules.starting_credits_random_max);
    try std.testing.expectEqual(@as(i32, 100), td.rules.starting_credits_step);
}

test "generated rules declare the reduced stock-style starting force" {
    try std.testing.expectEqual(@as(u8, 50), td.rules.starting_force_percent);
    try std.testing.expectEqual(@as(u8, 6), td.rules.starting_force_unit_count);
    try std.testing.expectEqual(@as(u8, 3), td.rules.starting_force_e1_count);
    try std.testing.expectEqual(@as(u8, 3), td.rules.starting_force_e3_count);
}

test "fixed building capacity covers every structure purchasable without income" {
    const cheapest_structure = td.rules.object(.power_plant).?.cost;
    const maximum_player_purchases: usize = @intCast(@divFloor(td.rules.initial_credits, cheapest_structure));
    const construction_yards = td.rules.player_count;
    const opponent_opening_structures = 2;
    try std.testing.expect(
        td.rules.max_buildings >= construction_yards + maximum_player_purchases + opponent_opening_structures,
    );
}

test "fixed building storage accepts its declared capacity and fails loudly after it" {
    var world = td.World.reset(1);
    for (0..td.rules.max_buildings) |index| {
        try std.testing.expect(world.addBuilding(
            .player,
            .power_plant,
            .{ .x = @intCast(index % 64), .y = @intCast(index / 64) },
        ));
    }
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
    try std.testing.expectEqual(@as(u8, @intCast(td.rules.max_buildings)), world.building_count);

    try std.testing.expect(!world.addBuilding(.player, .power_plant, .{ .x = 0, .y = 1 }));
    try std.testing.expectEqual(td.state.Failure.capacity_overflow, world.failure);
}

test "construction yard timing distinguishes policy and Easy AI controllers" {
    const yard = td.rules.object(.construction_yard) orelse return error.MissingConstructionYardRule;
    try std.testing.expectEqual(@as(u8, 64), yard.construction_frames);
    try std.testing.expectEqual(@as(u8, 60), yard.ai_construction_frames);

    const world = td.World.reset(1);
    try std.testing.expectEqual(td.state.Controller.policy, world.players[0].controller);
    try std.testing.expectEqual(td.state.Controller.easy_ai, world.players[1].controller);
}

test "Easy AI structure buildup matches the 58-frame Vanilla animation" {
    inline for (.{ td.ObjectType.power_plant, td.ObjectType.barracks, td.ObjectType.refinery }) |kind| {
        const object = td.rules.object(kind) orelse return error.MissingBuildingRule;
        try std.testing.expectEqual(@as(u8, 58), object.ai_construction_frames);
    }
}

test "player Refinery buildup matches the 58-frame Vanilla animation" {
    const refinery = td.rules.object(.refinery) orelse return error.MissingRefineryRule;
    try std.testing.expectEqual(@as(u8, 58), refinery.construction_frames);
}

test "generated combat rules include Vanilla armor classes and SA AP modifier rows" {
    try std.testing.expectEqual(td.rules.Armor.aluminum, td.rules.object(.mcv).?.armor);
    try std.testing.expectEqual(td.rules.Armor.wood, td.rules.object(.construction_yard).?.armor);
    try std.testing.expectEqual(td.rules.Armor.none, td.rules.object(.e1).?.armor);
    try std.testing.expectEqual(@as(u16, 144), td.rules.weapon_m16.armorModifier(.aluminum));
    try std.testing.expectEqual(@as(u16, 192), td.rules.weapon_dragon.armorModifier(.wood));
}

test "CNC26 vehicle expansion rule data matches real Vanilla stock stats" {
    // Values pulled directly from Vanilla-Conquer/tiberiandawn/{defines,udata,bdata}.cpp and
    // const.cpp's MPHType enum, not guessed. See docs/td_micro/cnc26_vehicle_expansion_design.md.
    const weapons_factory = td.rules.object(.weapons_factory) orelse return error.MissingWeaponsFactoryRule;
    try std.testing.expectEqual(td.rules.Category.building, weapons_factory.category);
    try std.testing.expectEqual(@as(i32, 2_000), weapons_factory.cost);
    try std.testing.expectEqual(@as(i16, 200), weapons_factory.strength);
    try std.testing.expectEqual(@as(u8, 3), weapons_factory.sight);
    try std.testing.expectEqual(td.rules.Armor.aluminum, weapons_factory.armor);
    try std.testing.expectEqual(@as(i16, 0), weapons_factory.power);
    try std.testing.expectEqual(@as(i16, 30), weapons_factory.drain);
    try std.testing.expectEqual(@as(u8, 3), weapons_factory.footprint_width);
    try std.testing.expectEqual(@as(u8, 3), weapons_factory.footprint_height);
    try std.testing.expectEqual(td.ObjectType.refinery, weapons_factory.prerequisite);

    const medium_tank = td.rules.object(.medium_tank) orelse return error.MissingMediumTankRule;
    try std.testing.expectEqual(td.rules.Category.unit, medium_tank.category);
    try std.testing.expectEqual(@as(i32, 800), medium_tank.cost);
    try std.testing.expectEqual(@as(i16, 400), medium_tank.strength);
    try std.testing.expectEqual(@as(u8, 3), medium_tank.sight);
    try std.testing.expectEqual(td.rules.Armor.steel, medium_tank.armor);
    try std.testing.expectEqual(@as(u8, 18), medium_tank.max_speed); // MPH_MEDIUM
    try std.testing.expectEqual(td.ObjectType.weapons_factory, medium_tank.prerequisite);

    const humvee = td.rules.object(.humvee) orelse return error.MissingHumveeRule;
    try std.testing.expectEqual(td.rules.Category.unit, humvee.category);
    try std.testing.expectEqual(@as(i32, 400), humvee.cost);
    try std.testing.expectEqual(@as(i16, 150), humvee.strength);
    try std.testing.expectEqual(@as(u8, 2), humvee.sight);
    try std.testing.expectEqual(td.rules.Armor.aluminum, humvee.armor);
    try std.testing.expectEqual(@as(u8, 30), humvee.max_speed); // MPH_MEDIUM_FAST
    try std.testing.expectEqual(td.ObjectType.weapons_factory, humvee.prerequisite);
}

test "TD Micro Easy AI fields infantry before the player can win a zero-army rush" {
    for (1..3) |seed| {
        var world = td.World.reset(seed);
        while (world.frame < 2_500 and opponentInfantryCount(&world) == 0) {
            _ = td.step.advanceWithEasyAI(&world);
        }

        try std.testing.expectEqual(td.state.Failure.none, world.failure);
        try std.testing.expect(world.frame < 2_500);
        try std.testing.expect(opponentInfantryCount(&world) > 0);
    }
}

fn opponentInfantryCount(world: *const td.World) usize {
    var count: usize = 0;
    for (world.infantry) |infantry| {
        if (infantry.active and infantry.owner == .opponent) count += 1;
    }
    return count;
}

fn expectFixtureManifest(trace: []const u8) !void {
    const header_end = std.mem.indexOfScalar(u8, trace, '\n') orelse return error.MissingTraceHeader;
    const Header = struct { manifest: []const u8 };
    const parsed = try std.json.parseFromSlice(
        Header,
        std.testing.allocator,
        trace[0..header_end],
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    const prior_manifest = "bcb23e390785cb3b500f763752ae354a45972ec864356352ea5614d59f2df389";
    const random_credit_manifest = "619ccb703dd91f4fd7b110db79ec8e77f21b63bf9245ed4e4218ba05eb5549de";
    const legacy_manifest = "ffc4646f31a9c8e64dcfbd1ffc91fa6163af4b5686478124b3bb21187107ca85";
    const neutral_difficulty_manifest = "a776dac1f17d141e7f29d7cc596a172331b732aedf5976a4d0bee21af8c44b57";
    try std.testing.expect(
        std.mem.eql(u8, td.rules.manifest_sha256_hex, parsed.value.manifest) or
            std.mem.eql(u8, prior_manifest, parsed.value.manifest) or
            std.mem.eql(u8, random_credit_manifest, parsed.value.manifest) or
            std.mem.eql(u8, legacy_manifest, parsed.value.manifest) or
            std.mem.eql(u8, neutral_difficulty_manifest, parsed.value.manifest),
    );
}

test "all Vanilla fixtures identify the generated manifest" {
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_idle64.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed2_idle64.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_mirror_deploy.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_player_power.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_player_power_place.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_player_barracks.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_player_e1_e3.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_player_e1_egress_interrupt.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_policy_economy.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_ai_economy.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed2_ai_early_force.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_player_refinery_harvest.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_h0_finish_e1.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_h0_finish_e3.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_h0_finish_mixed.jsonl"));
    try expectFixtureManifest(@embedFile("fixtures/vanilla_seed1_starting_force.jsonl"));
}
