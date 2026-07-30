const std = @import("std");
const td = @import("td_micro");

test "ABI13 keeps one command plus three bounded conditional tokens" {
    try std.testing.expectEqual(@as(u32, 13), td.policy.abi_version);
    try std.testing.expectEqualSlices(u16, &[_]u16{ 12, 65, 65, 65 }, &td.policy.action_head_sizes);
    try std.testing.expectEqual(@as(usize, 4), td.policy.action_head_count);
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(td.policy.RawAction));
    try std.testing.expectEqual(@as(u8, 64), td.policy.pad_token);
    try std.testing.expectEqual(@as(usize, 4), td.policy.actor_target_rank);
    try std.testing.expectEqual(@as(usize, 2_352), td.policy.actor_query_logits_offset);
    try std.testing.expectEqual(@as(usize, 3_376), td.policy.target_key_logits_offset);
    try std.testing.expectEqual(@as(usize, 4_912), td.policy.action_logit_count);
    try std.testing.expectEqual(@as(usize, 9_242), td.policy.action_mask_bit_count);
    try std.testing.expectEqual(@as(usize, 1_156), td.policy.action_mask_size);
}

test "ABI13 preserves the ABI10 command grammar" {
    var world = td.World.reset(1);
    const pad = td.policy.pad_token;

    const noop = td.policy.decode(&world, .{ .command = @intFromEnum(td.Command.noop) }).?;
    try std.testing.expectEqual(td.Command.noop, noop.command);

    const deploy = td.policy.decode(&world, .{
        .command = @intFromEnum(td.Command.deploy),
        .arg0 = 0,
        .arg1 = pad,
        .arg2 = pad,
    }).?;
    try std.testing.expectEqual(td.Command.deploy, deploy.command);
    try std.testing.expectEqual(@as(u8, 0), deploy.actor);

    const build = td.policy.decode(&world, .{
        .command = @intFromEnum(td.Command.start_build),
        .arg0 = @intFromEnum(td.policy.Product.power_plant),
        .arg1 = pad,
        .arg2 = pad,
    }).?;
    try std.testing.expectEqual(td.ObjectType.power_plant, build.product);

    const move = td.policy.decode(&world, .{
        .command = @intFromEnum(td.Command.move),
        .arg0 = 3,
        .arg1 = 17,
        .arg2 = 23,
    }).?;
    try std.testing.expectEqual(@as(u8, 3), move.actor);
    try std.testing.expectEqual(td.action.TargetKind.cell, move.target_kind);
    try std.testing.expectEqual(@as(u8, 17), move.target_x);
    try std.testing.expectEqual(@as(u8, 23), move.target_y);

    world.queues[0][@intFromEnum(td.state.QueueKind.structure)] = .{
        .active = true,
        .completed = true,
        .product = .power_plant,
    };
    const place = td.policy.decode(&world, .{
        .command = @intFromEnum(td.Command.place),
        .arg0 = 4,
        .arg1 = 7,
        .arg2 = pad,
    }).?;
    try std.testing.expectEqual(td.ObjectType.power_plant, place.product);
    try std.testing.expectEqual(@as(u8, 4), place.target_x);
    try std.testing.expectEqual(@as(u8, 7), place.target_y);
}

test "ABI13 rejects noncanonical padding and out-of-domain tokens" {
    const world = td.World.reset(1);
    const pad = td.policy.pad_token;

    try std.testing.expect(td.policy.decode(&world, .{
        .command = @intFromEnum(td.Command.noop),
        .arg0 = 0,
        .arg1 = pad,
        .arg2 = pad,
    }) == null);
    try std.testing.expect(td.policy.decode(&world, .{
        .command = @intFromEnum(td.Command.deploy),
        .arg0 = 0,
        .arg1 = 0,
        .arg2 = pad,
    }) == null);
    try std.testing.expect(td.policy.decode(&world, .{
        .command = @intFromEnum(td.Command.move),
        .arg0 = 0,
        .arg1 = 65,
        .arg2 = 0,
    }) == null);
    try std.testing.expect(td.policy.decode(&world, .{
        .command = 12,
        .arg0 = pad,
        .arg1 = pad,
        .arg2 = pad,
    }) == null);
}

test "reset masks expose only legal command prefixes and canonical padding" {
    const world = td.World.reset(1);
    var mask: [td.policy.action_mask_size]u8 = undefined;
    td.policy.actionMask(&world, &mask);

    try std.testing.expect(td.policy.commandAllowed(&mask, .noop));
    try std.testing.expect(td.policy.commandAllowed(&mask, .deploy));
    try std.testing.expect(!td.policy.commandAllowed(&mask, .move));

    try expectOnlyArgument(&mask, .noop, 0, td.policy.pad_token, td.policy.pad_token);
    try expectOnlyArgument(&mask, .noop, 1, td.policy.pad_token, td.policy.pad_token);

    try expectOnlyArgument(&mask, .deploy, 0, td.policy.pad_token, 0);
    try expectOnlyArgument(&mask, .deploy, 1, 0, td.policy.pad_token);
}

test "placement masks select exact legal y rows after x" {
    var world = td.World.reset(1);
    try std.testing.expect(world.addBuilding(.player, .construction_yard, .{ .x = 1, .y = 7 }));
    world.buildings[0].construction_frames = 0;
    world.buildings[0].operational = true;
    world.queues[0][@intFromEnum(td.state.QueueKind.structure)] = .{
        .active = true,
        .completed = true,
        .product = .power_plant,
    };

    var mask: [td.policy.action_mask_size]u8 = undefined;
    td.policy.actionMask(&world, &mask);
    try std.testing.expect(td.policy.commandAllowed(&mask, .place));

    var legal_x: ?u8 = null;
    for (0..64) |x| {
        if (td.policy.argumentAllowed(&mask, .place, 0, td.policy.pad_token, @intCast(x))) {
            legal_x = @intCast(x);
            break;
        }
    }
    const x = legal_x orelse return error.NoLegalPlacement;
    for (0..64) |y| {
        try std.testing.expectEqual(
            td.placement.isLegal(&world, .player, .power_plant, .{ .x = x, .y = @intCast(y) }),
            td.policy.argumentAllowed(&mask, .place, 1, x, @intCast(y)),
        );
    }
    try std.testing.expect(!td.policy.argumentAllowed(&mask, .place, 1, x, td.policy.pad_token));
    try expectOnlyArgument(&mask, .place, 2, x, td.policy.pad_token);
}

test "ABI13 does not expose the autonomous Harvester as an actor" {
    var world = td.World.reset(1);
    world.units[0].kind = .harvester;
    var mask: [td.policy.action_mask_size]u8 = undefined;
    td.policy.actionMask(&world, &mask);

    try std.testing.expect(!td.policy.commandAllowed(&mask, .move));
    try std.testing.expect(!td.policy.commandAllowed(&mask, .harvest));
    try std.testing.expect(!td.policy.commandAllowed(&mask, .return_cargo));
    try std.testing.expect(!td.policy.argumentAllowed(&mask, .move, 0, td.policy.pad_token, 0));
    try std.testing.expect(!td.policy.argumentAllowed(&mask, .harvest, 0, td.policy.pad_token, 0));
    try std.testing.expect(!td.policy.argumentAllowed(&mask, .return_cargo, 0, td.policy.pad_token, 0));
}

fn expectOnlyArgument(
    mask: *const [td.policy.action_mask_size]u8,
    command: td.Command,
    argument_index: u2,
    prior_token: u8,
    expected: u8,
) !void {
    for (0..td.policy.token_count) |value| {
        try std.testing.expectEqual(
            value == expected,
            td.policy.argumentAllowed(mask, command, argument_index, prior_token, @intCast(value)),
        );
    }
}
