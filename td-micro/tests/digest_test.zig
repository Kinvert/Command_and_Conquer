const std = @import("std");
const td = @import("td_micro");

test "canonical opening trace has a stable digest" {
    var first = td.World.reset(1);
    var second = td.World.reset(1);
    const deploy = td.Action{ .command = .deploy, .actor = 0 };
    td.step.step(&first, deploy, .{});
    td.step.step(&second, deploy, .{});

    const first_digest = td.digest.canonical(&first);
    const second_digest = td.digest.canonical(&second);
    try std.testing.expectEqualSlices(u8, &first_digest, &second_digest);

    const expected = [_]u8{
        0x0f, 0xc9, 0xbb, 0x84, 0x49, 0x07, 0x84, 0xda,
        0x46, 0xb9, 0xf2, 0x9f, 0x44, 0xbd, 0x59, 0x35,
        0xd1, 0xa6, 0xbe, 0x69, 0x27, 0x9a, 0x51, 0x22,
        0x59, 0x0f, 0x9b, 0xad, 0xee, 0x21, 0x17, 0xed,
    };
    try std.testing.expectEqualSlices(u8, &expected, &first_digest);
}

test "canonical digest changes when command-visible state changes" {
    var idle = td.World.reset(1);
    var deployed = td.World.reset(1);
    td.step.step(&idle, .{}, .{});
    td.step.step(&deployed, .{ .command = .deploy, .actor = 0 }, .{});

    const idle_digest = td.digest.canonical(&idle);
    const deployed_digest = td.digest.canonical(&deployed);
    try std.testing.expect(!std.mem.eql(u8, &idle_digest, &deployed_digest));
}

test "canonical digest includes episode classification metadata" {
    const baseline = td.World.reset(1);

    var medium = baseline;
    medium.spawn_bucket = .medium;
    try std.testing.expect(!std.mem.eql(
        u8,
        &td.digest.canonical(&baseline),
        &td.digest.canonical(&medium),
    ));

    var starting_force = baseline;
    starting_force.starting_force = .reduced_unit_count_6;
    try std.testing.expect(!std.mem.eql(
        u8,
        &td.digest.canonical(&baseline),
        &td.digest.canonical(&starting_force),
    ));
}
