const std = @import("std");
const td = @import("td_micro");

test "policy inference ABI pins the native Puffer weight layout" {
    try std.testing.expectEqual(@as(usize, 64), td.inference.hidden_size);
    try std.testing.expectEqualSlices(usize, &.{ 64, 128 }, &td.inference.hidden_sizes);
    try std.testing.expectEqual(@as(usize, 4_913), td.inference.decoder_size);
    try std.testing.expectEqual(@as(usize, 255_488), td.inference.encoder_weight_count);
    try std.testing.expectEqual(@as(usize, 314_432), td.inference.decoder_weight_count);
    try std.testing.expectEqual(@as(usize, 12_288), td.inference.mingru_weight_count);
    try std.testing.expectEqual(@as(usize, 582_208), td.inference.weight_count);
    try std.testing.expectEqual(@as(usize, 2_328_832), td.inference.checkpoint_size);
    try std.testing.expectEqual(@as(usize, 1_188_992), td.inference.weightCountForHidden(128));
    try std.testing.expectEqual(@as(usize, 4_755_968), td.inference.checkpointSizeForHidden(128));
    try std.testing.expectEqual(@as(?usize, 64), td.inference.hiddenForCheckpointSize(2_328_832));
    try std.testing.expectEqual(@as(?usize, 128), td.inference.hiddenForCheckpointSize(4_755_968));
    try std.testing.expectEqual(@as(?usize, null), td.inference.hiddenForCheckpointSize(4_755_964));
    for (td.inference.hidden_sizes) |hidden| {
        try std.testing.expectEqual(
            @as(?usize, null),
            td.inference.abi14HiddenForCheckpointSize(td.inference.checkpointSizeForHidden(hidden)),
        );
    }
    for (td.inference.abi14_hidden_sizes) |hidden| {
        try std.testing.expectEqual(
            @as(?usize, null),
            td.inference.hiddenForCheckpointSize(td.inference.abi14CheckpointSize(hidden)),
        );
    }
}

test "compact policy rejects an observation-v4 checkpoint by exact size" {
    const allocator = std.testing.allocator;
    const legacy = try allocator.alloc(u8, 1_710_080);
    defer allocator.free(legacy);
    try std.testing.expectError(
        error.InvalidCheckpointSize,
        td.inference.Model.initBytes(allocator, legacy),
    );
}

test "ABI13 hidden-128 checkpoint loads, acts, samples deterministically, and resets" {
    const allocator = std.testing.allocator;
    const weights = try allocator.alloc(f32, td.inference.weightCountForHidden(128));
    defer allocator.free(weights);
    @memset(weights, 0);

    var first_model = try td.inference.Model.init(allocator, weights);
    defer first_model.deinit();
    var second_model = try td.inference.Model.init(allocator, weights);
    defer second_model.deinit();
    try std.testing.expectEqual(@as(usize, 128), first_model.hidden);

    const observation = [_]u8{0} ** td.policy.observation_size;
    var mask = [_]u8{0} ** td.policy.action_mask_size;
    enableMask(&mask, td.policy.command_mask_offset, @intFromEnum(td.Command.noop));
    enableMask(&mask, td.policy.command_mask_offset, @intFromEnum(td.Command.deploy));
    enableMask(&mask, td.policy.pad_mask_offset, td.policy.pad_token);
    enableMask(&mask, td.policy.deploy_actor_mask_offset, 0);
    enableMask(&mask, td.policy.deploy_actor_mask_offset, 2);

    first_model.seedSampling(1_337);
    second_model.seedSampling(1_337);
    for (0..4) |_| {
        const first = try first_model.actSampled(&observation, &mask);
        const second = try second_model.actSampled(&observation, &mask);
        try std.testing.expectEqualSlices(u8, std.mem.asBytes(&first), std.mem.asBytes(&second));
    }
    first_model.reset();
    try std.testing.expectEqual(@as(f32, 0.0), first_model.state[127]);
}

test "masked greedy inference uses encoder decoder MinGRU order and resets state" {
    const allocator = std.testing.allocator;
    const weights = try allocator.alloc(f32, td.inference.weight_count);
    defer allocator.free(weights);
    @memset(weights, 0);

    // Decoder is registered before MinGRU in the native Puffer checkpoint.
    const command_two_row = td.inference.decoder_offset + 2 * td.inference.hidden_size;
    weights[command_two_row] = 8.0;

    var model = try td.inference.Model.init(allocator, weights);
    defer model.deinit();

    var observation = [_]u8{0} ** td.policy.observation_size;
    observation[0] = 1;
    var mask = [_]u8{0} ** td.policy.action_mask_size;
    enableMask(&mask, td.policy.command_mask_offset, @intFromEnum(td.Command.start_build));
    enableMask(&mask, td.policy.build_product_mask_offset, @intFromEnum(td.policy.Product.power_plant));
    enableMask(&mask, td.policy.pad_mask_offset, td.policy.pad_token);
    const expected = [_]u8{ @intFromEnum(td.Command.start_build), @intFromEnum(td.policy.Product.power_plant), 64, 64 };

    const first = try model.act(&observation, &mask);
    try std.testing.expectEqualSlices(u8, &expected, std.mem.asBytes(&first));
    try std.testing.expectEqual(@as(f32, 0.25), model.state[0]);

    _ = try model.act(&observation, &mask);
    try std.testing.expect(model.state[0] > 0.25);
    model.reset();
    try std.testing.expectEqual(@as(f32, 0.0), model.state[0]);
}

test "policy inference rejects malformed weights and reports the raw checkpoint hash" {
    const allocator = std.testing.allocator;
    const short = try allocator.alloc(f32, td.inference.weight_count - 1);
    defer allocator.free(short);
    try std.testing.expectError(error.InvalidCheckpointSize, td.inference.Model.init(allocator, short));

    const weights = try allocator.alloc(f32, td.inference.weight_count);
    defer allocator.free(weights);
    @memset(weights, 0);
    weights[123] = std.math.nan(f32);
    try std.testing.expectError(error.NonFiniteWeight, td.inference.Model.init(allocator, weights));

    weights[123] = 1.0;
    var model = try td.inference.Model.init(allocator, weights);
    defer model.deinit();
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(std.mem.sliceAsBytes(weights), &expected, .{});
    try std.testing.expectEqualSlices(u8, &expected, &model.checkpoint_sha256);
}

test "policy inference rounds checkpoint and recurrent values to BF16" {
    try std.testing.expectEqual(@as(f32, 1.0), td.inference.roundBf16(1.0));
    try std.testing.expectEqual(@as(f32, 1.0078125), td.inference.roundBf16(1.006));
    try std.testing.expectEqual(@as(f32, -2.0), td.inference.roundBf16(-2.001));
}

test "policy inference scales byte observations to Puffer normalized floats" {
    const allocator = std.testing.allocator;
    const weights = try allocator.alloc(f32, td.inference.weight_count);
    defer allocator.free(weights);
    @memset(weights, 0);
    weights[0] = 1.0;

    var model = try td.inference.Model.init(allocator, weights);
    defer model.deinit();

    var observation = [_]u8{0} ** td.policy.observation_size;
    observation[0] = 255;
    var mask = [_]u8{0} ** td.policy.action_mask_size;
    enableMask(&mask, td.policy.command_mask_offset, @intFromEnum(td.Command.noop));
    enableMask(&mask, td.policy.pad_mask_offset, td.policy.pad_token);

    _ = try model.act(&observation, &mask);
    try std.testing.expectEqual(@as(f32, 1.0), model.encoded[0]);
}

test "actor-target logits choose different attack targets for different actors" {
    const allocator = std.testing.allocator;
    const weights = try allocator.alloc(f32, td.inference.weight_count);
    defer allocator.free(weights);
    @memset(weights, 0);

    weights[0] = 1.0;
    const actor_one_query = td.policy.actorQueryOffset(.attack, 1).?;
    const actor_two_query = td.policy.actorQueryOffset(.attack, 2).?;
    const target_zero_key = td.policy.targetKeyOffset(.attack, 1, 0).?;
    const target_one_key = td.policy.targetKeyOffset(.attack, 1, 1).?;
    setDecoderWeight(weights, actor_one_query, 8.0);
    setDecoderWeight(weights, actor_two_query, -8.0);
    setDecoderWeight(weights, target_zero_key, 1.0);
    setDecoderWeight(weights, target_one_key, -1.0);

    var actor_one_model = try td.inference.Model.init(allocator, weights);
    defer actor_one_model.deinit();
    var actor_two_model = try td.inference.Model.init(allocator, weights);
    defer actor_two_model.deinit();

    var observation = [_]u8{0} ** td.policy.observation_size;
    observation[0] = 255;
    var actor_one_mask = attackMask(1);
    var actor_two_mask = attackMask(2);

    const actor_one_action = try actor_one_model.act(&observation, &actor_one_mask);
    const actor_two_action = try actor_two_model.act(&observation, &actor_two_mask);
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ @intFromEnum(td.Command.attack), 1, 0, td.policy.pad_token },
        std.mem.asBytes(&actor_one_action),
    );
    try std.testing.expectEqualSlices(
        u8,
        &[_]u8{ @intFromEnum(td.Command.attack), 2, 1, td.policy.pad_token },
        std.mem.asBytes(&actor_two_action),
    );
}

test "sampled inference is seed deterministic and respects masks" {
    const allocator = std.testing.allocator;
    const weights = try allocator.alloc(f32, td.inference.weight_count);
    defer allocator.free(weights);
    @memset(weights, 0);

    var first_model = try td.inference.Model.init(allocator, weights);
    defer first_model.deinit();
    var second_model = try td.inference.Model.init(allocator, weights);
    defer second_model.deinit();
    first_model.seedSampling(74);
    second_model.seedSampling(74);

    const observation = [_]u8{0} ** td.policy.observation_size;
    var mask = [_]u8{0} ** td.policy.action_mask_size;
    enableMask(&mask, td.policy.command_mask_offset, @intFromEnum(td.Command.noop));
    enableMask(&mask, td.policy.command_mask_offset, @intFromEnum(td.Command.deploy));
    enableMask(&mask, td.policy.pad_mask_offset, td.policy.pad_token);
    enableMask(&mask, td.policy.deploy_actor_mask_offset, 0);
    enableMask(&mask, td.policy.deploy_actor_mask_offset, 2);

    for (0..32) |_| {
        const first = try first_model.actSampled(&observation, &mask);
        const second = try second_model.actSampled(&observation, &mask);
        try std.testing.expectEqualSlices(u8, std.mem.asBytes(&first), std.mem.asBytes(&second));

        const bytes = std.mem.asBytes(&first);
        const command: td.Command = @enumFromInt(bytes[0]);
        try std.testing.expect(td.policy.commandAllowed(&mask, command));
        try std.testing.expect(td.policy.argumentAllowed(&mask, command, 0, td.policy.pad_token, bytes[1]));
        try std.testing.expect(td.policy.argumentAllowed(&mask, command, 1, bytes[1], bytes[2]));
        try std.testing.expect(td.policy.argumentAllowed(&mask, command, 2, bytes[2], bytes[3]));
    }
}

fn enableMask(mask: *[td.policy.action_mask_size]u8, offset: usize, value: u8) void {
    const bit = offset + value;
    mask[bit / 8] |= @as(u8, 1) << @intCast(bit % 8);
}

fn setDecoderWeight(weights: []f32, logit: usize, value: f32) void {
    weights[td.inference.decoder_offset + logit * td.inference.hidden_size] = value;
}

fn attackMask(actor: u8) [td.policy.action_mask_size]u8 {
    var mask = [_]u8{0} ** td.policy.action_mask_size;
    enableMask(&mask, td.policy.command_mask_offset, @intFromEnum(td.Command.attack));
    enableMask(&mask, td.policy.attack_actor_mask_offset, actor);
    enableMask(&mask, td.policy.attack_target_mask_offset, 0);
    enableMask(&mask, td.policy.attack_target_mask_offset, 1);
    enableMask(&mask, td.policy.pad_mask_offset, td.policy.pad_token);
    return mask;
}
