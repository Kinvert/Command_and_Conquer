const std = @import("std");
const td = @import("td_micro");

test "static pathfinder follows Vanilla clockwise tie around scenario obstacle" {
    var path: [td.pathfinder.path_capacity]i8 = undefined;
    try std.testing.expect(td.pathfinder.findStatic(.{ .x = 7, .y = 9 }, .{ .x = 18, .y = 9 }, &path));
    try std.testing.expectEqualSlices(i8, &.{ 2, 2, 2, 2, 2, 2, 2, 3, 1 }, &path);
}

test "static pathfinder preserves unobstructed direct route" {
    var path: [td.pathfinder.path_capacity]i8 = undefined;
    try std.testing.expect(td.pathfinder.findStatic(.{ .x = 7, .y = 9 }, .{ .x = 10, .y = 9 }, &path));
    try std.testing.expectEqualSlices(i8, &.{ 2, 2, 2, -1, -1, -1, -1, -1, -1 }, &path);
}

test "static pathfinder applies Vanilla move optimization to first AI HUNT route" {
    var world = td.World.reset(1);
    world.units[1].active = false;
    try std.testing.expect(world.addBuilding(.opponent, .construction_yard, .{ .x = 14, .y = 0 }));
    try std.testing.expect(world.addBuilding(.opponent, .power_plant, .{ .x = 13, .y = 2 }));
    try std.testing.expect(world.addBuilding(.opponent, .barracks, .{ .x = 17, .y = 1 }));

    var path: [td.pathfinder.path_capacity]i8 = undefined;
    try std.testing.expect(td.pathfinder.find(&world, .opponent, .{ .x = 19, .y = 3 }, .{ .x = 2, .y = 8 }, &path));
    try std.testing.expectEqualSlices(i8, &.{ 6, 6, 6, 6, 4, 3, 2, 1, 2 }, &path);
}

test "static pathfinder matches Vanilla second AI HUNT path window" {
    var world = td.World.reset(1);
    world.units[1].active = false;
    try std.testing.expect(world.addBuilding(.opponent, .construction_yard, .{ .x = 14, .y = 0 }));
    try std.testing.expect(world.addBuilding(.opponent, .power_plant, .{ .x = 13, .y = 2 }));
    try std.testing.expect(world.addBuilding(.opponent, .barracks, .{ .x = 17, .y = 1 }));

    var path: [td.pathfinder.path_capacity]i8 = undefined;
    try std.testing.expect(td.pathfinder.find(&world, .opponent, .{ .x = 19, .y = 4 }, .{ .x = 2, .y = 8 }, &path));
    try std.testing.expectEqualSlices(i8, &.{ 3, 2, 3, 4, 4, 5, 5, 5, 7 }, &path);
}

test "static pathfinder selects Vanilla low-cost route stopping before enemy MCV" {
    var world = td.World.reset(1);
    world.units[1].active = false;
    try std.testing.expect(world.addBuilding(.opponent, .construction_yard, .{ .x = 14, .y = 0 }));
    try std.testing.expect(world.addBuilding(.opponent, .power_plant, .{ .x = 13, .y = 2 }));
    try std.testing.expect(world.addBuilding(.opponent, .barracks, .{ .x = 17, .y = 1 }));

    var path: [td.pathfinder.path_capacity]i8 = undefined;
    try std.testing.expect(td.pathfinder.find(&world, .opponent, .{ .x = 9, .y = 10 }, .{ .x = 2, .y = 8 }, &path));
    try std.testing.expectEqualSlices(i8, &.{ 6, 6, 6, 7, 6, 7, -1, -1, -1 }, &path);
}

test "pathfinder terminates at Vanilla's edge-follow budget after route backtracking" {
    var world = td.World.reset(1);
    world.units[0].active = false;
    world.units[1].active = false;
    try std.testing.expect(world.addBuilding(.opponent, .barracks, .{ .x = 22, .y = 41 }));

    var path: [td.pathfinder.path_capacity]i8 = undefined;
    try std.testing.expect(td.pathfinder.find(
        &world,
        .opponent,
        .{ .x = 23, .y = 42 },
        .{ .x = 1, .y = 13 },
        &path,
    ));
    try std.testing.expectEqualSlices(i8, &.{ 1, 7, 6, 6, 7, 7, 7, 7, 7 }, &path);
}
