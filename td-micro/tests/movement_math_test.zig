const std = @import("std");
const td = @import("td_micro");

test "Desired_Facing256 matches Vanilla source vectors" {
    const cases = [_]struct { x1: i16, y1: i16, x2: i16, y2: i16, expected: u8 }{
        .{ .x1 = 0, .y1 = 0, .x2 = 0, .y2 = 0, .expected = 255 },
        .{ .x1 = 5, .y1 = 5, .x2 = 20, .y2 = 20, .expected = 95 },
        .{ .x1 = -5, .y1 = -5, .x2 = 20, .y2 = 20, .expected = 95 },
        .{ .x1 = 5, .y1 = 5, .x2 = -20, .y2 = -20, .expected = 223 },
        .{ .x1 = 1000, .y1 = 5, .x2 = 20, .y2 = 20, .expected = 191 },
        .{ .x1 = 5, .y1 = 1000, .x2 = 20, .y2 = 20, .expected = 0 },
        .{ .x1 = 5, .y1 = 5, .x2 = 5, .y2 = 9, .expected = 127 },
        .{ .x1 = 5, .y1 = 5, .x2 = 9, .y2 = 5, .expected = 63 },
        .{ .x1 = 5, .y1 = 9, .x2 = 5, .y2 = 5, .expected = 0 },
        .{ .x1 = 9, .y1 = 5, .x2 = 5, .y2 = 5, .expected = 192 },
    };
    for (cases) |case| {
        try std.testing.expectEqual(
            case.expected,
            td.movement.desiredFacing256(case.x1, case.y1, case.x2, case.y2),
        );
    }
}
