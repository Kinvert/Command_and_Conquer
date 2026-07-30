const std = @import("std");
const td = @import("td_micro");

// CNC26 vehicle expansion. Every constant below is ground truth from the real Vanilla-Conquer
// source, not tuned to make the simulator agree with itself:
//   - weapon damage/ROF/range: tiberiandawn/const.cpp `Weapons[]`
//   - projectile ids: tiberiandawn/defines.h `BulletType`
//   - projectile flight: tiberiandawn/bbdata.cpp `ClassAPDS` / `ClassBullet`
//   - warhead armor tables: tiberiandawn/const.cpp `Warheads[]`
//   - turret rotation: tiberiandawn/facing.cpp `FacingClass::Rotation_Adjust`
//   - turret rate: tiberiandawn/turret.cpp `TurretClass::AI` uses `Class->ROT + 1`
// See docs/td_micro/cnc26_vehicle_expansion_design.md.

test "CNC26 vehicle weapon rules match Vanilla const.cpp exactly" {
    // WEAPON_105MM: {BULLET_APDS, 30, 50, 0x04C0, ...}
    const gun = td.rules.weapon_105mm;
    try std.testing.expectEqual(@as(i16, 30), gun.damage);
    try std.testing.expectEqual(@as(u16, 50), gun.reload_frames);
    try std.testing.expectEqual(@as(u16, 0x04C0), gun.range_leptons);
    try std.testing.expectEqual(@as(u8, 2), gun.projectile_id); // BULLET_APDS
    try std.testing.expectEqual(@as(u8, 100), gun.projectile_speed); // MPH_VERY_FAST
    try std.testing.expectEqual(@as(u8, 0), gun.arming_frames);
    try std.testing.expectEqual(@as(u8, 0), gun.turn_rate); // APDS does not home

    // WEAPON_M60MG: {BULLET_BULLET, 15, 30, 0x0400, ...}
    const mg = td.rules.weapon_m60mg;
    try std.testing.expectEqual(@as(i16, 15), mg.damage);
    try std.testing.expectEqual(@as(u16, 30), mg.reload_frames);
    try std.testing.expectEqual(@as(u16, 0x0400), mg.range_leptons);
    try std.testing.expectEqual(@as(u8, 1), mg.projectile_id); // BULLET_BULLET
}

test "CNC26 vehicle warheads reuse the exact stock armor tables" {
    // ClassAPDS carries WARHEAD_AP, the same warhead as the E3 Dragon, so its armor row must be
    // byte-identical to the already-validated dragon row: {0x40, 0xC0, 0xC0, 0x100, 0x80}.
    const gun = td.rules.weapon_105mm;
    try std.testing.expectEqual(@as(u16, 0x40), gun.armorModifier(.none));
    try std.testing.expectEqual(@as(u16, 0xC0), gun.armorModifier(.wood));
    try std.testing.expectEqual(@as(u16, 0xC0), gun.armorModifier(.aluminum));
    try std.testing.expectEqual(@as(u16, 0x100), gun.armorModifier(.steel));
    try std.testing.expectEqual(@as(u16, 0x80), gun.armorModifier(.concrete));
    try std.testing.expectEqual(td.rules.weapon_dragon.spread_factor, gun.spread_factor);

    // ClassBullet carries WARHEAD_SA, identical to the E1 M16 row.
    const mg = td.rules.weapon_m60mg;
    try std.testing.expectEqual(td.rules.weapon_m16.armorModifier(.none), mg.armorModifier(.none));
    try std.testing.expectEqual(td.rules.weapon_m16.armorModifier(.steel), mg.armorModifier(.steel));
    try std.testing.expectEqual(td.rules.weapon_m16.spread_factor, mg.spread_factor);
}

test "CNC26 armor-piercing rounds beat small arms against steel and invert against infantry" {
    // This is the whole point of adding vehicles: a real rock-paper-scissors axis. Verified
    // against the stock warhead tables rather than asserted from intuition.
    const gun = td.rules.weapon_105mm;
    const mg = td.rules.weapon_m60mg;
    try std.testing.expect(gun.armorModifier(.steel) > mg.armorModifier(.steel));
    try std.testing.expect(mg.armorModifier(.none) > gun.armorModifier(.none));
}

test "CNC26 turret rotation reproduces Vanilla FacingClass::Rotation_Adjust" {
    const rotate = td.combat.rotateFacingForTest;

    // Already aligned: no movement.
    try std.testing.expectEqual(@as(u8, 64), rotate(64, 64, 6));

    // Difference smaller than the rate snaps exactly to desired (ABS(diff) < rate).
    try std.testing.expectEqual(@as(u8, 68), rotate(64, 68, 6));
    try std.testing.expectEqual(@as(u8, 60), rotate(64, 60, 6));

    // Difference at or above the rate steps by exactly the rate.
    try std.testing.expectEqual(@as(u8, 70), rotate(64, 96, 6));
    try std.testing.expectEqual(@as(u8, 58), rotate(64, 32, 6));

    // A difference exactly equal to the rate still steps (Vanilla uses strict <).
    try std.testing.expectEqual(@as(u8, 70), rotate(64, 70, 6));

    // Wraparound takes the short way around, both directions, exactly as the signed-char
    // difference in Vanilla does.
    try std.testing.expectEqual(@as(u8, 2), rotate(252, 20, 6));
    try std.testing.expectEqual(@as(u8, 250), rotate(0, 220, 6));

    // The 128 boundary is the deliberate tie: (signed char)128 is negative, so Vanilla turns
    // counter-clockwise here.
    try std.testing.expectEqual(@as(u8, 250), rotate(0, 128, 6));
}

test "CNC26 turret tracks a live target and recenters to the hull when idle" {
    var world = td.World.reset(1);
    world.easy_ai.active = false;

    const tank_index = world.addUnit(.player, .medium_tank, .{ .x = 20, .y = 20 }).?;
    const tank = &world.units[tank_index];
    tank.facing = 0;
    tank.turret_facing = 0;

    // Put an enemy due east. desiredFacing256 is the same helper the infantry path already uses.
    const target_index = world.addUnit(.opponent, .medium_tank, .{ .x = 26, .y = 20 }).?;
    tank.target = .{ .kind = .medium_tank, .owner = .opponent, .index = @intCast(target_index) };

    const desired = td.combat.unitTurretDesiredForTest(&world, tank_index).?;
    try std.testing.expect(desired != 0);

    // The turret closes on the target monotonically at exactly ROT+1 per tick, never overshooting.
    var previous_gap: u16 = 0xFFFF;
    var ticks: u32 = 0;
    while (ticks < 200) : (ticks += 1) {
        td.combat.tickUnitTurrets(&world);
        const facing = world.units[tank_index].turret_facing;
        const gap: u16 = @intCast(@min(
            @as(u16, desired -% facing),
            @as(u16, facing -% desired),
        ));
        try std.testing.expect(gap <= previous_gap);
        previous_gap = gap;
        if (facing == desired) break;
    }
    try std.testing.expectEqual(desired, world.units[tank_index].turret_facing);
    // 6 units per tick means a turret cannot snap instantly across a wide arc.
    try std.testing.expect(ticks > 1);

    // Vanilla's TurretClass::AI sets the desired facing back to the hull facing when there is no
    // target, so a turret parks itself forward again.
    world.units[target_index].active = false;
    world.units[target_index].health = 0;
    try std.testing.expectEqual(
        @as(?u8, world.units[tank_index].facing),
        td.combat.unitTurretDesiredForTest(&world, tank_index),
    );
    var settle: u32 = 0;
    while (settle < 200 and world.units[tank_index].turret_facing != world.units[tank_index].facing) : (settle += 1) {
        td.combat.tickUnitTurrets(&world);
    }
    try std.testing.expectEqual(world.units[tank_index].facing, world.units[tank_index].turret_facing);
}

test "CNC26 turretless units never acquire a turret facing" {
    var world = td.World.reset(1);
    world.easy_ai.active = false;

    // The reset opening already places both MCVs. They carry stock ROT 5 but no turret, so the
    // turret tick must leave them completely alone.
    const harvester_index = world.addUnit(.player, .harvester, .{ .x = 30, .y = 30 }).?;
    world.units[harvester_index].facing = 96;

    for (0..32) |_| td.combat.tickUnitTurrets(&world);

    try std.testing.expectEqual(@as(u8, 0), world.units[harvester_index].turret_facing);
    try std.testing.expectEqual(@as(?u8, null), td.combat.unitTurretDesiredForTest(&world, harvester_index));
}

fn duelWorld(kind: td.ObjectType, gap_cells: u8) struct { world: td.World, attacker: usize, victim: usize } {
    var world = td.World.reset(1);
    world.easy_ai.active = false;
    const attacker = world.addUnit(.player, kind, .{ .x = 20, .y = 20 }).?;
    const victim = world.addUnit(.opponent, .medium_tank, .{ .x = 20 + gap_cells, .y = 20 }).?;
    world.units[attacker].target = .{ .kind = .medium_tank, .owner = .opponent, .index = @intCast(victim) };
    return .{ .world = world, .attacker = attacker, .victim = victim };
}

test "CNC26 vehicles hold fire until the turret stops slewing" {
    var setup = duelWorld(.medium_tank, 3);
    var world = setup.world;
    const tank = &world.units[setup.attacker];
    tank.facing = 0;
    tank.turret_facing = 0; // pointing north, target is due east

    // Neither vehicle carries a homing weapon, so Vanilla's Can_Fire refuses while IsRotating.
    try std.testing.expect(!td.combat.canUnitFireForTest(&world, setup.attacker));

    var ticks: u32 = 0;
    while (ticks < 200 and !td.combat.canUnitFireForTest(&world, setup.attacker)) : (ticks += 1) {
        td.combat.tickUnitTurrets(&world);
    }
    try std.testing.expect(ticks > 0); // it genuinely had to wait for the turret
    try std.testing.expect(td.combat.canUnitFireForTest(&world, setup.attacker));
}

test "CNC26 Medium Tank launches a traveling APDS shell from the barrel tip" {
    var setup = duelWorld(.medium_tank, 3);
    var world = setup.world;
    for (0..64) |_| td.combat.tickUnitTurrets(&world);
    try std.testing.expect(td.combat.canUnitFireForTest(&world, setup.attacker));

    // The muzzle is offset from the hull centre, so a shell must not start at the cell centre.
    const muzzle = td.combat.unitFireCoordForTest(world.units[setup.attacker]);
    try std.testing.expect(muzzle.x != world.units[setup.attacker].coord_x or
        muzzle.y != world.units[setup.attacker].coord_y);

    td.combat.tickUnitWeapons(&world);
    try std.testing.expectEqual(@as(u8, 1), world.projectile_count);
    const shell = world.projectiles[world.projectile_order[0]];
    try std.testing.expectEqual(td.state.ProjectileKind.apds, shell.kind);
    try std.testing.expectEqual(@as(u8, 100), shell.speed); // MPH_VERY_FAST, it travels
    try std.testing.expectEqual(@as(i16, 30), shell.strength);
    try std.testing.expectEqual(muzzle.x, shell.coord_x);
    try std.testing.expectEqual(muzzle.y, shell.coord_y);

    // Reload is the stock 105mm ROF, and the gun stays silent for exactly that long.
    try std.testing.expectEqual(@as(u8, 50), world.units[setup.attacker].weapon_cooldown);
    try std.testing.expect(!td.combat.canUnitFireForTest(&world, setup.attacker));
}

test "CNC26 APDS flies a straight line and never re-aims at a moving target" {
    var setup = duelWorld(.medium_tank, 5);
    var world = setup.world;
    for (0..64) |_| td.combat.tickUnitTurrets(&world);
    td.combat.tickUnitWeapons(&world);
    try std.testing.expectEqual(@as(u8, 1), world.projectile_count);

    const launch_facing = world.projectiles[world.projectile_order[0]].facing;

    // Teleport the victim far away. A homing weapon would curve after it; APDS must not.
    world.units[setup.victim].position = .{ .x = 20, .y = 40 };
    world.units[setup.victim].coord_x = 20 * 256 + 128;
    world.units[setup.victim].coord_y = 40 * 256 + 128;

    for (0..6) |_| {
        if (world.projectile_count == 0) break;
        const shell = world.projectiles[world.projectile_order[0]];
        try std.testing.expectEqual(launch_facing, shell.facing);
        td.combat.tick(&world);
    }
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
}

test "CNC26 Humvee fires the same near-instant small arms as the M16" {
    var setup = duelWorld(.humvee, 2);
    var world = setup.world;
    for (0..64) |_| td.combat.tickUnitTurrets(&world);
    td.combat.tickUnitWeapons(&world);

    try std.testing.expectEqual(@as(u8, 1), world.projectile_count);
    const round = world.projectiles[world.projectile_order[0]];
    try std.testing.expectEqual(td.state.ProjectileKind.bullet, round.kind);
    try std.testing.expectEqual(@as(i16, 15), round.strength);
    try std.testing.expectEqual(@as(u8, 30), world.units[setup.attacker].weapon_cooldown);
}

test "CNC26 armour piercing shells hurt a tank more than machine gun fire does" {
    // Same target, same range, different weapon: the AP warhead should bite far harder into
    // steel than small arms do. This is the rock-paper-scissors axis actually taking effect in
    // the simulator rather than only in the rules table.
    var tank_setup = duelWorld(.medium_tank, 2);
    var tank_world = tank_setup.world;
    var mg_setup = duelWorld(.humvee, 2);
    var mg_world = mg_setup.world;

    const full_health = tank_world.units[tank_setup.victim].health;
    for (0..64) |_| {
        td.combat.tickUnitTurrets(&tank_world);
        td.combat.tickUnitTurrets(&mg_world);
    }
    for (0..24) |_| {
        td.combat.tick(&tank_world);
        td.combat.tick(&mg_world);
    }

    const ap_damage = full_health - tank_world.units[tank_setup.victim].health;
    const sa_damage = full_health - mg_world.units[mg_setup.victim].health;
    try std.testing.expect(ap_damage > 0);
    try std.testing.expect(ap_damage > sa_damage);
    try std.testing.expectEqual(td.state.Failure.none, tank_world.failure);
    try std.testing.expectEqual(td.state.Failure.none, mg_world.failure);
}

fn factoryWorld() td.World {
    var world = td.World.reset(1);
    world.easy_ai.active = false;
    _ = world.addBuilding(.player, .construction_yard, .{ .x = 10, .y = 10 });
    _ = world.addBuilding(.player, .refinery, .{ .x = 14, .y = 10 });
    _ = world.addBuilding(.player, .weapons_factory, .{ .x = 18, .y = 10 });
    for (&world.buildings) |*building| {
        if (building.active) building.operational = true;
    }
    return world;
}

test "CNC26 vehicle production needs a Weapons Factory and runs on its own queue" {
    var world = factoryWorld();
    const player = @intFromEnum(td.Owner.player);
    const unit_queue = @intFromEnum(td.state.QueueKind.unit);
    const infantry_queue = @intFromEnum(td.state.QueueKind.infantry);

    try std.testing.expect(td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .medium_tank,
    }));
    try std.testing.expect(world.queues[player][unit_queue].active);
    try std.testing.expectEqual(td.ObjectType.medium_tank, world.queues[player][unit_queue].product);
    try std.testing.expectEqual(@as(i32, 800), world.queues[player][unit_queue].balance);

    // The vehicle queue is genuinely independent: it must not disturb the infantry queue, and a
    // second vehicle cannot jump the same queue.
    try std.testing.expect(!world.queues[player][infantry_queue].active);
    try std.testing.expect(!td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .humvee,
    }));
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
}

test "CNC26 vehicle production is refused without the Weapons Factory" {
    var world = td.World.reset(1);
    world.easy_ai.active = false;
    _ = world.addBuilding(.player, .construction_yard, .{ .x = 10, .y = 10 });
    for (&world.buildings) |*building| {
        if (building.active) building.operational = true;
    }

    try std.testing.expect(!td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .medium_tank,
    }));
    try std.testing.expect(!world.queues[@intFromEnum(td.Owner.player)][@intFromEnum(td.state.QueueKind.unit)].active);
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
}

test "CNC26 Weapons Factory itself requires a Refinery, exactly as stock TD does" {
    var world = td.World.reset(1);
    world.easy_ai.active = false;
    _ = world.addBuilding(.player, .construction_yard, .{ .x = 10, .y = 10 });
    for (&world.buildings) |*building| {
        if (building.active) building.operational = true;
    }

    // STRUCTF_REFINERY is the stock prerequisite, so this must fail before a Refinery exists.
    try std.testing.expect(!td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .weapons_factory,
    }));

    _ = world.addBuilding(.player, .refinery, .{ .x = 14, .y = 10 });
    for (&world.buildings) |*building| {
        if (building.active) building.operational = true;
    }
    try std.testing.expect(td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .weapons_factory,
    }));
}

test "CNC26 vehicle queue drains credits and completes" {
    var world = factoryWorld();
    const player = @intFromEnum(td.Owner.player);
    const unit_queue = @intFromEnum(td.state.QueueKind.unit);
    world.players[player].credits = 5_000;

    try std.testing.expect(td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .humvee,
    }));

    var frames: u32 = 0;
    while (frames < 20_000 and !world.queues[player][unit_queue].completed) : (frames += 1) {
        td.production.tick(&world);
    }
    try std.testing.expect(world.queues[player][unit_queue].completed);
    try std.testing.expectEqual(@as(i32, 5_000 - 400), world.players[player].credits);
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
}

test "CNC26 a new vehicle appears at the exact Vanilla factory exit coordinate" {
    // Ground truth read off a real Vanilla trace (vanilla_seed1_humvee.jsonl recorded at full
    // resolution): with the Weapons Factory at (2,9) the Humvee leaves limbo at cell [2,10],
    // coord [746, 2720], hull and turret facing both 160, on the guard mission.
    //
    // Both numbers reproduce bdata.cpp exactly rather than being fitted to the trace:
    //   ExitWeap XYP_COORD(10 + 24/2, (24*3) - 24/2 - 21) = (22px, 39px)
    //   -> leptons (22*256/24, 39*256/24) = (234, 416), and 746-512 = 234, 2720-2304 = 416.
    //   Facing 160 is DIR_SW (5 << 5).
    var world = factoryWorld();
    const player = @intFromEnum(td.Owner.player);
    world.players[player].credits = 5_000;

    // Match the recorded Vanilla layout so the expected coordinates are directly comparable.
    for (&world.buildings) |*building| {
        if (building.active and building.kind == .weapons_factory) building.position = .{ .x = 2, .y = 9 };
    }

    try std.testing.expect(td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .humvee,
    }));
    var frames: u32 = 0;
    while (frames < 20_000 and findUnit(&world, .player, .humvee) == null) : (frames += 1) {
        td.production.tick(&world);
    }

    const humvee = findUnit(&world, .player, .humvee) orelse return error.HumveeNeverLeftTheFactory;
    try std.testing.expectEqual(@as(u8, 2), humvee.position.x);
    try std.testing.expectEqual(@as(u8, 10), humvee.position.y);
    try std.testing.expectEqual(@as(i16, 746), humvee.coord_x);
    try std.testing.expectEqual(@as(i16, 2_720), humvee.coord_y);
    try std.testing.expectEqual(@as(u8, 160), humvee.facing);
    try std.testing.expectEqual(@as(u8, 160), humvee.turret_facing);
    try std.testing.expectEqual(@as(i8, 4), humvee.mission);
    try std.testing.expectEqual(@as(i16, 150), humvee.health);
}

test "CNC26 completed vehicles roll out at the stock factory exit cell" {
    var world = factoryWorld();
    const player = @intFromEnum(td.Owner.player);
    const unit_queue = @intFromEnum(td.state.QueueKind.unit);
    world.players[player].credits = 5_000;

    const before = countUnits(&world, .player, .medium_tank);
    try std.testing.expect(td.production.apply(&world, .player, .{
        .command = .start_build,
        .product = .medium_tank,
    }));

    var frames: u32 = 0;
    while (frames < 20_000 and countUnits(&world, .player, .medium_tank) == before) : (frames += 1) {
        td.production.tick(&world);
    }

    try std.testing.expectEqual(before + 1, countUnits(&world, .player, .medium_tank));
    // The queue must clear so the factory can accept the next order.
    try std.testing.expect(!world.queues[player][unit_queue].active);
    try std.testing.expectEqual(td.state.Failure.none, world.failure);

    // The vehicle appears on the factory's exit coordinate, one cell below the 3x3 origin at
    // (18, 10). It does not teleport to the ExitWeap cell; it is given that cell as a destination
    // and drives there, which is what the Vanilla trace shows.
    const tank = findUnit(&world, .player, .medium_tank).?;
    try std.testing.expectEqual(@as(u8, 18), tank.position.x);
    try std.testing.expectEqual(@as(u8, 11), tank.position.y);
    try std.testing.expectEqual(@as(i16, 400), tank.health); // full stock strength
    try std.testing.expectEqual(@as(i16, 18 * 256 + 234), tank.coord_x);
    try std.testing.expectEqual(@as(i16, 10 * 256 + 416), tank.coord_y);
    // Stock ExitWeap prefers XYCELL(-1, 3), so it should be heading for (17, 13).
    try std.testing.expect(tank.destination_valid);
    try std.testing.expectEqual(@as(u8, 17), tank.destination.x);
    try std.testing.expectEqual(@as(u8, 13), tank.destination.y);
}

fn countUnits(world: *const td.World, owner: td.Owner, kind: td.ObjectType) usize {
    var count: usize = 0;
    for (world.units) |unit| {
        if (unit.active and unit.owner == owner and unit.kind == kind) count += 1;
    }
    return count;
}

fn findUnit(world: *const td.World, owner: td.Owner, kind: td.ObjectType) ?td.state.Unit {
    for (world.units) |unit| {
        if (unit.active and unit.owner == owner and unit.kind == kind) return unit;
    }
    return null;
}

fn driveTo(world: *td.World, unit_index: usize, destination: td.state.Position, budget: u32) u32 {
    try_move: {
        if (!td.economy.assignMove(world, unit_index, destination)) break :try_move;
    }
    var frames: u32 = 0;
    while (frames < budget) : (frames += 1) {
        if (world.units[unit_index].position.x == destination.x and
            world.units[unit_index].position.y == destination.y) break;
        td.step.tickFrame(world);
    }
    return frames;
}

test "CNC26 combat vehicles drive to an ordered destination" {
    var world = td.World.reset(1);
    world.easy_ai.active = false;
    const tank = world.addUnit(.player, .medium_tank, .{ .x = 20, .y = 20 }).?;

    const frames = driveTo(&world, tank, .{ .x = 24, .y = 20 }, 4_000);
    try std.testing.expectEqual(@as(u8, 24), world.units[tank].position.x);
    try std.testing.expectEqual(@as(u8, 20), world.units[tank].position.y);
    try std.testing.expect(frames > 0);
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
}

test "CNC26 a Humvee outruns a Medium Tank over the same ground" {
    // MPH_MEDIUM_FAST (30) versus MPH_MEDIUM (18). This proves the per-kind stock speed is
    // actually reaching the movement engine, not just sitting in the rules table.
    var tank_world = td.World.reset(1);
    tank_world.easy_ai.active = false;
    const tank = tank_world.addUnit(.player, .medium_tank, .{ .x = 20, .y = 20 }).?;

    var jeep_world = td.World.reset(1);
    jeep_world.easy_ai.active = false;
    const jeep = jeep_world.addUnit(.player, .humvee, .{ .x = 20, .y = 20 }).?;

    const destination = td.state.Position{ .x = 26, .y = 20 };
    const tank_frames = driveTo(&tank_world, tank, destination, 8_000);
    const jeep_frames = driveTo(&jeep_world, jeep, destination, 8_000);

    try std.testing.expectEqual(@as(u8, 26), tank_world.units[tank].position.x);
    try std.testing.expectEqual(@as(u8, 26), jeep_world.units[jeep].position.x);
    try std.testing.expect(jeep_frames < tank_frames);
}

test "CNC26 a moving tank keeps its turret on the target while the hull turns away" {
    var world = td.World.reset(1);
    world.easy_ai.active = false;
    const tank = world.addUnit(.player, .medium_tank, .{ .x = 20, .y = 20 }).?;
    const enemy = world.addUnit(.opponent, .medium_tank, .{ .x = 20, .y = 30 }).?;
    world.units[enemy].health = 400;
    world.units[tank].target = .{ .kind = .medium_tank, .owner = .opponent, .index = @intCast(enemy) };

    // Drive north, directly away from an enemy sitting to the south.
    _ = td.economy.assignMove(&world, tank, .{ .x = 20, .y = 14 });
    var hull_turned = false;
    for (0..2_000) |_| {
        td.step.tickFrame(&world);
        if (world.units[tank].facing != world.units[tank].turret_facing) hull_turned = true;
        if (world.units[tank].position.y == 14) break;
    }

    // The hull and turret must have genuinely diverged, which is the entire point of a turret.
    try std.testing.expect(hull_turned);
    const desired = td.combat.unitTurretDesiredForTest(&world, tank).?;
    const gap: u8 = @min(
        desired -% world.units[tank].turret_facing,
        world.units[tank].turret_facing -% desired,
    );
    try std.testing.expect(gap < 16);
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
}

test "CNC26 turret rates derive from stock ROT plus one" {
    // TurretClass::AI calls SecondaryFacing.Rotation_Adjust(Class->ROT + 1).
    try std.testing.expectEqual(@as(u8, 6), td.rules.turretRate(.medium_tank).?); // ROT 5
    try std.testing.expectEqual(@as(u8, 11), td.rules.turretRate(.humvee).?); // ROT 10
    try std.testing.expectEqual(@as(?u8, null), td.rules.turretRate(.e1));
    try std.testing.expectEqual(@as(?u8, null), td.rules.turretRate(.harvester));

    // A Medium Tank turret needs exactly 22 ticks to reverse a full 128-step half turn at rate 6
    // (127 travelled in 21 steps, then the final snap).
    var facing: u8 = 0;
    var ticks: u32 = 0;
    while (facing != 128 and ticks < 1_000) : (ticks += 1) {
        facing = td.combat.rotateFacingForTest(facing, 128, 6);
    }
    try std.testing.expectEqual(@as(u32, 22), ticks);
}
