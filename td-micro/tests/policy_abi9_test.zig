const std = @import("std");
const td = @import("td_micro");

test "ABI9 adapter preserves the historical seven-head contract" {
    try std.testing.expectEqual(@as(u32, 9), td.policy_abi9.abi_version);
    try std.testing.expectEqualSlices(
        u16,
        &[_]u16{ 12, 65, 9, 4, 64, 64, 64 },
        &td.policy_abi9.action_head_sizes,
    );
    try std.testing.expectEqual(@as(usize, 7), td.policy_abi9.action_head_count);
    try std.testing.expectEqual(@as(usize, 282), td.policy_abi9.action_mask_size);
    try std.testing.expectEqual(td.policy.observation_size, td.policy_abi9.observation_size);
}

test "ABI9 broad head masks expose invalid cross-head tuples" {
    var world = td.World.reset(1);
    var mask: [td.policy_abi9.action_mask_size]u8 = undefined;
    td.policy_abi9.actionMask(&world, &mask);

    const commands = td.policy_abi9.headMask(&mask, .command);
    const actors = td.policy_abi9.headMask(&mask, .actor);
    try std.testing.expectEqual(@as(u8, 1), commands[@intFromEnum(td.Command.deploy)]);
    try std.testing.expectEqual(@as(u8, 1), actors[0]);
    try std.testing.expectEqual(@as(u8, 1), actors[td.policy_abi9.actor_none]);

    const decoded = td.policy_abi9.decode(&world, .{
        .command = @intFromEnum(td.Command.deploy),
        .actor = td.policy_abi9.actor_none,
    }).?;
    try std.testing.expectEqual(td.Command.deploy, decoded.command);
    try std.testing.expectEqual(td.policy_abi9.actor_none, decoded.actor);
    try std.testing.expect(!td.input.apply(&world, .player, decoded));
}
