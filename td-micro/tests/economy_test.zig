const std = @import("std");
const td = @import("td_micro");

fn operationalRefinery(world: *td.World, owner: td.Owner, position: td.state.Position) !usize {
    try std.testing.expect(world.addBuilding(owner, .refinery, position));
    const index: usize = world.building_count - 1;
    world.buildings[index].construction_frames = 0;
    td.production.tick(world);
    try std.testing.expect(world.buildings[index].operational);
    return index;
}

fn harvester(world: *td.World, owner: td.Owner) ?*td.state.Unit {
    for (&world.units) |*unit| {
        if (unit.active and unit.owner == owner and unit.kind == .harvester) return unit;
    }
    return null;
}

test "Refinery grand opening adds capacity and one free Harvester" {
    var world = td.World.reset(1);
    const rng_before = world.rng_state;
    const refinery_index = try operationalRefinery(&world, .player, .{ .x = 4, .y = 7 });

    try std.testing.expect(world.buildings[refinery_index].grand_opened);
    try std.testing.expectEqual(td.rules.refinery_capacity, world.players[0].capacity);
    try std.testing.expectEqual(@as(i16, 10), world.players[0].power);
    try std.testing.expectEqual(@as(i16, 40), world.players[0].drain);

    const unit = harvester(&world, .player) orelse return error.MissingHarvester;
    try std.testing.expectEqual(td.state.Position{ .x = 4, .y = 9 }, unit.position);
    try std.testing.expectEqual(@as(i8, 8), unit.mission);
    try std.testing.expectEqual(@as(u8, 0), unit.cargo_steps);
    var expected_rng = rng_before;
    _ = td.random.pick(&expected_rng, 0, 255);
    try std.testing.expectEqual(expected_rng, world.rng_state);

    td.production.tick(&world);
    var count: usize = 0;
    for (world.units) |candidate| {
        if (candidate.active and candidate.owner == .player and candidate.kind == .harvester) count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "Refinery refunds its bundled Harvester when the unit array is full" {
    var world = td.World.reset(1);
    for (&world.units) |*unit| unit.kind = .mcv;
    const credits_before = world.players[0].credits;
    const refinery_index = try operationalRefinery(&world, .player, .{ .x = 4, .y = 7 });

    try std.testing.expect(world.buildings[refinery_index].grand_opened);
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
    try std.testing.expectEqual(
        credits_before + td.rules.object(.harvester).?.cost,
        world.players[0].credits,
    );
}

test "Harvester removes exact overlay steps and unloads player credits" {
    var world = td.World.reset(1);
    _ = try operationalRefinery(&world, .player, .{ .x = 4, .y = 7 });
    const unit = harvester(&world, .player) orelse return error.MissingHarvester;

    world.clearAllTiberium();
    const harvest_cell = td.state.Position{ .x = 4, .y = 9 };
    world.setTiberium(harvest_cell, 4);
    unit.position = harvest_cell;
    unit.coord_x = @as(i16, harvest_cell.x) * 256 + 128;
    unit.coord_y = @as(i16, harvest_cell.y) * 256 + 128;

    td.step.tickFrame(&world);
    td.step.tickFrame(&world);
    try std.testing.expectEqual(@as(u8, 4), unit.cargo_steps);
    try std.testing.expectEqual(@as(u8, 0), world.tiberiumAt(harvest_cell));

    unit.cargo_steps = td.rules.harvester_capacity_steps;
    unit.harvest_timer = 0;
    unit.mission = 8;
    unit.status = 2;
    for (0..2048) |_| {
        if (unit.cargo_steps == 0) break;
        td.step.tickFrame(&world);
    }

    try std.testing.expectEqual(@as(u8, 0), unit.cargo_steps);
    try std.testing.expectEqual(
        @as(i32, td.rules.harvester_capacity_steps) * td.rules.player_tiberium_step_credits,
        world.players[0].tiberium,
    );
    try std.testing.expectEqual(
        @as(u32, td.rules.harvester_capacity_steps) * td.rules.player_tiberium_step_credits,
        world.players[0].harvested_credits,
    );
}

test "Harvester countdown includes the frame when harvesting starts" {
    var world = td.World.reset(1);
    world.clearAllTiberium();
    const harvest_cell = td.state.Position{ .x = 4, .y = 9 };
    world.setTiberium(harvest_cell, 4);
    const unit_index = world.addUnit(.player, .harvester, harvest_cell) orelse
        return error.MissingHarvester;
    const unit = &world.units[unit_index];
    unit.mission = 8;
    unit.status = 1;
    unit.mission_timer_due = 0;

    td.step.tickFrame(&world);

    try std.testing.expectEqual(@as(u8, 4), unit.cargo_steps);
    try std.testing.expectEqual(@as(u8, td.rules.harvest_interval_frames - 1), unit.harvest_timer);
}

test "original AI unload receives the Vanilla multiplayer bonus" {
    var world = td.World.reset(1);
    _ = try operationalRefinery(&world, .opponent, .{ .x = 30, .y = 20 });
    const unit = harvester(&world, .opponent) orelse return error.MissingHarvester;
    world.clearAllTiberium();
    unit.cargo_steps = 2;
    unit.position = .{ .x = 30, .y = 22 };
    unit.coord_x = 30 * 256 + 128;
    unit.coord_y = 22 * 256 + 128;
    unit.mission = 8;
    unit.status = 2;

    for (0..2048) |_| {
        if (unit.cargo_steps == 0) break;
        td.step.tickFrame(&world);
    }

    try std.testing.expectEqual(@as(u8, 0), unit.cargo_steps);
    try std.testing.expectEqual(@as(i32, 66), world.players[1].tiberium);
    try std.testing.expectEqual(@as(u32, 66), world.players[1].harvested_credits);
}

test "policy commands move, harvest, and return the selected Harvester" {
    var world = td.World.reset(1);
    _ = try operationalRefinery(&world, .player, .{ .x = 4, .y = 7 });
    const unit = harvester(&world, .player) orelse return error.MissingHarvester;
    world.clearAllTiberium();
    world.setTiberium(.{ .x = 8, .y = 9 }, 6);

    try std.testing.expect(td.input.apply(&world, .player, .{
        .command = .move,
        .actor = 1,
        .target_kind = .cell,
        .target_x = 7,
        .target_y = 9,
    }));
    try std.testing.expectEqual(@as(i8, 2), unit.mission);

    try std.testing.expect(td.input.apply(&world, .player, .{
        .command = .harvest,
        .actor = 1,
        .target_kind = .cell,
        .target_x = 8,
        .target_y = 9,
    }));
    try std.testing.expectEqual(@as(i8, 8), unit.mission);

    unit.cargo_steps = 3;
    try std.testing.expect(td.input.apply(&world, .player, .{
        .command = .return_cargo,
        .actor = 1,
        .target_kind = .own_entity,
        .target_slot = 2,
    }));
    try std.testing.expectEqual(@as(i8, 6), unit.mission);
}

test "depleted Tiberium becomes buildable terrain" {
    var world = td.World.reset(1);
    world.clearAllTiberium();
    try std.testing.expect(world.addBuilding(.player, .construction_yard, .{}));
    world.buildings[0].operational = true;

    var placement: ?td.state.Position = null;
    var tiberium_cell: ?td.state.Position = null;
    outer: for (0..world.map_height) |y| {
        for (3..world.map_width) |x| {
            const candidate = td.state.Position{ .x = @intCast(x), .y = @intCast(y) };
            world.buildings[0].position = .{ .x = @intCast(x - 3), .y = @intCast(y) };
            if (!td.placement.isLegal(&world, .player, .refinery, candidate)) continue;
            const occupied = td.placement.placementFootprint(.refinery) orelse
                return error.MissingRefineryFootprint;
            for (occupied) |offset| {
                const cell = td.placement.offsetPosition(&world, candidate, offset) orelse continue;
                if (td.map.at(cell).?.land_type == 5) {
                    placement = candidate;
                    tiberium_cell = cell;
                    break :outer;
                }
            }
        }
    }

    const position = placement orelse return error.MissingDepletedTiberiumPlacement;
    const resource = tiberium_cell orelse return error.MissingTiberiumCell;
    world.setTiberium(resource, 1);
    try std.testing.expect(!td.placement.isLegal(&world, .player, .refinery, position));
    world.clearTiberium(resource);
    try std.testing.expect(td.placement.isLegal(&world, .player, .refinery, position));
}

test "zero-step Tiberium remains present until reduced" {
    var world = td.World.reset(1);
    const resource = td.state.Position{ .x = 40, .y = 48 };

    try std.testing.expect(world.hasTiberium(resource));
    try std.testing.expectEqual(@as(u8, 0), world.tiberiumAt(resource));
    try std.testing.expectEqual(@as(u8, 0), world.reduceTiberium(resource, 1));
    try std.testing.expect(!world.hasTiberium(resource));
}
