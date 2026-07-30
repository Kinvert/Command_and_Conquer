const std = @import("std");
const td = @import("td_micro");

test "economy rules pin the Vanilla Refinery and Harvester contract" {
    try std.testing.expect(td.rules.max_units >= 4);
    try std.testing.expectEqual(@as(u8, 7), @intFromEnum(td.ObjectType.refinery));
    try std.testing.expectEqual(@as(u8, 8), @intFromEnum(td.ObjectType.harvester));

    const refinery = td.rules.object(.refinery).?;
    try std.testing.expectEqual(td.rules.Category.building, refinery.category);
    try std.testing.expectEqual(@as(i32, 2000), refinery.cost);
    try std.testing.expectEqual(@as(i16, 900), refinery.strength);
    try std.testing.expectEqual(@as(i16, 10), refinery.power);
    try std.testing.expectEqual(@as(i16, 40), refinery.drain);
    try std.testing.expectEqual(td.ObjectType.power_plant, refinery.prerequisite);

    const harvester = td.rules.object(.harvester).?;
    try std.testing.expectEqual(td.rules.Category.unit, harvester.category);
    try std.testing.expectEqual(@as(i32, 1400), harvester.cost);
    try std.testing.expectEqual(@as(i16, 600), harvester.strength);
    try std.testing.expectEqual(@as(u8, 12), harvester.max_speed);
    try std.testing.expectEqual(td.ObjectType.refinery, harvester.prerequisite);

    try std.testing.expectEqual(@as(u8, 28), td.rules.harvester_capacity_steps);
    try std.testing.expectEqual(@as(u8, 15), td.rules.harvest_interval_frames);
    try std.testing.expectEqual(@as(u16, 25), td.rules.player_tiberium_step_credits);
    try std.testing.expectEqual(@as(u16, 33), td.rules.ai_tiberium_step_credits);
    try std.testing.expectEqual(@as(i32, 1000), td.rules.refinery_capacity);
}
