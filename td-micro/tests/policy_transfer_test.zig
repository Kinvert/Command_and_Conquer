const std = @import("std");

test "ABI 6 policy-state fixture remains an immutable historical artifact" {
    const fixture = @embedFile("fixtures/vanilla_seed1_policy_state.bin");
    try std.testing.expectEqual(@as(usize, 259 * (6208 + 275)), fixture.len);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(fixture, &digest, .{});
    const expected = [_]u8{
        0x9b, 0x2b, 0xa4, 0x45, 0x8c, 0xc0, 0x67, 0x9a,
        0xa5, 0x7b, 0x16, 0x1d, 0xc3, 0xe6, 0x85, 0xa9,
        0x27, 0x12, 0xef, 0x19, 0x51, 0x33, 0x18, 0x36,
        0xef, 0xe7, 0x92, 0x1d, 0x59, 0x28, 0x6a, 0x38,
    };
    try std.testing.expectEqualSlices(u8, &expected, &digest);
}
