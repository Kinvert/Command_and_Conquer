pub fn next(state: *u32) u15 {
    state.* = state.* *% 0x41C64E6D +% 0x00003039;
    return @truncate(state.* >> 10);
}

pub fn pick(state: *u32, first: i32, second: i32) i32 {
    if (first == second) return first;
    const minimum = @min(first, second);
    const maximum = @max(first, second);
    const magnitude: u32 = @intCast(maximum - minimum);

    var high_bit: u5 = 14;
    while (high_bit > 0 and magnitude & (@as(u32, 1) << high_bit) == 0) high_bit -= 1;
    const mask = (@as(u32, 1) << (high_bit + 1)) - 1;

    while (true) {
        const candidate = @as(u32, next(state)) & mask;
        if (candidate <= magnitude) return @as(i32, @intCast(candidate)) + minimum;
    }
}

test "RandomClass ranged rejection sequence matches Vanilla" {
    const std = @import("std");
    var state: u32 = 3_149_398_903;
    try std.testing.expectEqual(@as(i32, 2), pick(&state, 0, 4));
    try std.testing.expectEqual(@as(i32, 0), pick(&state, 0, 4));
    try std.testing.expectEqual(@as(i32, 0), pick(&state, 0, 4));
    try std.testing.expectEqual(@as(i32, 3), pick(&state, 0, 4));
    try std.testing.expectEqual(@as(u32, 4_035_701_833), state);
}
