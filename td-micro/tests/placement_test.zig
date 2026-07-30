const std = @import("std");
const td = @import("td_micro");

const noop = td.Action{};

fn deployedWorld() td.World {
    var world = td.World.reset(1);
    td.step.step(&world, .{ .command = .deploy, .actor = 0 }, noop);
    for (0..21) |_| td.step.step(&world, noop, noop);
    return world;
}

test "recorded Vanilla power placement is legal and a distant placement is not" {
    const world = deployedWorld();

    try std.testing.expect(td.placement.isLegal(
        &world,
        .player,
        .power_plant,
        .{ .x = 4, .y = 7 },
    ));
    try std.testing.expect(!td.placement.isLegal(
        &world,
        .player,
        .power_plant,
        .{ .x = 14, .y = 32 },
    ));
}

test "placement rejects footprint cells outside the map or occupied by a unit" {
    var world = deployedWorld();

    try std.testing.expect(!td.placement.isLegal(
        &world,
        .player,
        .power_plant,
        .{ .x = world.map_width - 1, .y = world.map_height - 1 },
    ));

    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 4, .y = 7 },
        .health = 50,
    };
    world.infantry_count = 1;
    try std.testing.expect(!td.placement.isLegal(
        &world,
        .player,
        .power_plant,
        .{ .x = 4, .y = 7 },
    ));
}

test "placement rejects a vehicle-reserved head-to cell" {
    var world = deployedWorld();
    world.buildings[0].position = .{ .x = 14, .y = 0 };
    const harvester_index = world.addUnit(.player, .harvester, .{ .x = 14, .y = 5 }) orelse
        return error.MissingHarvester;
    world.units[harvester_index].head_coord_x = 15 * 256 + 128;
    world.units[harvester_index].head_coord_y = 5 * 256 + 128;

    try std.testing.expect(!td.placement.isLegal(
        &world,
        .player,
        .barracks,
        .{ .x = 15, .y = 3 },
    ));
}

test "proximity requires a friendly building" {
    var world = deployedWorld();
    world.buildings[0].owner = .opponent;

    try std.testing.expect(!td.placement.isLegal(
        &world,
        .player,
        .power_plant,
        .{ .x = 4, .y = 7 },
    ));
}

test "placement rejects a terrain-blocked Occupy List cell" {
    var world = deployedWorld();
    world.buildings[0].position = .{ .x = 2, .y = 3 };

    // The Power Plant is adjacent to this relocated yard, but its bib reaches blocked cells.
    try std.testing.expect(!td.placement.isLegal(
        &world,
        .player,
        .power_plant,
        .{ .x = 5, .y = 3 },
    ));
}

test "Refinery placement combines its four-cell foundation with the three-wide bib" {
    const active = td.placement.footprint(.refinery) orelse return error.MissingRefineryFootprint;
    const placement = td.placement.placementFootprint(.refinery) orelse
        return error.MissingRefineryPlacementFootprint;

    try std.testing.expectEqual(@as(usize, 4), active.len);
    try std.testing.expectEqual(@as(usize, 10), placement.len);
    try std.testing.expectEqual(td.placement.CellOffset{ .x = 1, .y = 0 }, placement[0]);
    try std.testing.expectEqual(td.placement.CellOffset{ .x = 2, .y = 3 }, placement[9]);
}

test "fast legal-origin rows match the scalar placement oracle" {
    var world = deployedWorld();
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 4, .y = 7 },
        .health = 50,
    };
    world.infantry_count = 1;
    const harvester_index = world.addUnit(.player, .harvester, .{ .x = 8, .y = 8 }) orelse
        return error.MissingHarvester;
    world.units[harvester_index].head_coord_x = 9 * 256 + 128;
    world.units[harvester_index].head_coord_y = 8 * 256 + 128;

    for ([_]td.ObjectType{ .power_plant, .barracks, .refinery }) |product| {
        var rows: [td.policy.map_side]u64 = undefined;
        td.placement.legalOriginRows(&world, .player, product, &rows);
        for (0..td.policy.map_side) |y| {
            for (0..td.policy.map_side) |x| {
                const expected = td.placement.isLegal(
                    &world,
                    .player,
                    product,
                    .{ .x = @intCast(x), .y = @intCast(y) },
                );
                const actual = rows[y] & (@as(u64, 1) << @intCast(x)) != 0;
                try std.testing.expectEqual(expected, actual);
            }
        }
    }
}
