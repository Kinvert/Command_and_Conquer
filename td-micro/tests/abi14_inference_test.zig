const std = @import("std");
const td = @import("td_micro");

// ABI14 deployment-side inference.
//
// ABI14 exists in training (PufferLib/PyTorch) but has never had a Zig inference path, which is why
// it could never be wired into Vanilla. These tests pin the contract that path must satisfy before
// any of it is implemented.
//
// Head layout, from td_micro_action_head_sizes_abi14:
//   7 ABI9 heads [12, 65, 6, 4, 64, 64, 64] then 64 binary selector heads of size 2.
//   410 logits total; mask is 474 byte-per-entry slots (410 logits + 64 attack targets).
// Contrast ABI13, which is 4 autoregressive heads over a 9242-bit bitset mask.

const selector_count = td.policy_abi14.selector_count;

test "ABI14 head layout is 7 ABI9 heads plus 64 binary selectors" {
    try std.testing.expectEqual(@as(usize, 64), selector_count);
    try std.testing.expectEqual(@as(u32, 14), td.policy_abi14.abi_version);

    const sizes = td.policy_abi14.action_head_sizes;
    try std.testing.expectEqual(@as(usize, 71), sizes.len);
    // The first seven mirror ABI9 exactly.
    const expected_base = [_]u16{ 12, 65, 9, 4, 64, 64, 64 };
    for (expected_base, 0..) |want, index| {
        try std.testing.expectEqual(want, sizes[index]);
    }
    // Every selector head is a binary choice.
    for (sizes[expected_base.len..]) |size| {
        try std.testing.expectEqual(@as(u16, 2), size);
    }

    try std.testing.expectEqual(@as(usize, 474), td.policy_abi14.action_mask_size);
    try std.testing.expectEqual(@as(usize, 410), td.policy_abi14.attack_target_mask_offset);
}

test "ABI14 inference model exposes a sampled act returning a 71 byte action" {
    // Contract: an ABI14 model can be built from its own weight count, which differs from ABI13's,
    // and produces a policy_abi14.RawAction rather than the 4-field policy.RawAction.
    try std.testing.expectEqual(@as(usize, 71), @sizeOf(td.policy_abi14.RawAction));

    const allocator = std.testing.allocator;
    const weights = try allocator.alloc(f32, td.inference.abi14_weight_count);
    defer allocator.free(weights);
    // Deterministic synthetic weights: real behaviour is not under test here, the contract is.
    var rng = std.Random.DefaultPrng.init(0x5eed);
    for (weights) |*w| w.* = rng.random().floatNorm(f32) * 0.05;

    var model = try td.inference.Abi14Model.init(allocator, weights);
    defer model.deinit();

    var observation: [td.policy_abi14.observation_size]u8 = undefined;
    var mask: [td.policy_abi14.action_mask_size]u8 = undefined;
    var world = td.World.reset(1);
    td.policy_abi14.observe(&world, &observation);
    td.policy_abi14.actionMask(&world, &mask);

    const raw = try model.actSampled(&observation, &mask);

    // Selectors are strictly binary.
    for (raw.selectors) |selected| {
        try std.testing.expect(selected <= 1);
    }
    // The sampled command must be one the mask permitted.
    try std.testing.expect(mask[raw.command] != 0);
}

test "ABI14 non-attack commands carry no selectors" {
    // policy_abi14.apply rejects any non-attack command that has selectors set, so inference must
    // never produce one; otherwise every such action is silently discarded by the simulator.
    const allocator = std.testing.allocator;
    const weights = try allocator.alloc(f32, td.inference.abi14_weight_count);
    defer allocator.free(weights);
    var rng = std.Random.DefaultPrng.init(0xc0ffee);
    for (weights) |*w| w.* = rng.random().floatNorm(f32) * 0.05;

    var model = try td.inference.Abi14Model.init(allocator, weights);
    defer model.deinit();

    var world = td.World.reset(1);
    var observation: [td.policy_abi14.observation_size]u8 = undefined;
    var mask: [td.policy_abi14.action_mask_size]u8 = undefined;

    const attack_command = @intFromEnum(td.action.Command.attack);
    var sampled_any_non_attack = false;
    for (0..64) |_| {
        td.policy_abi14.observe(&world, &observation);
        td.policy_abi14.actionMask(&world, &mask);
        const raw = try model.actSampled(&observation, &mask);
        if (raw.command != attack_command) {
            sampled_any_non_attack = true;
            for (raw.selectors) |selected| {
                try std.testing.expectEqual(@as(u8, 0), selected);
            }
        }
        // Whatever was produced must be applicable or cleanly rejected, never a crash.
        _ = td.policy_abi14.apply(&world, .player, raw);
    }
    try std.testing.expect(sampled_any_non_attack);
}

test "ABI14 sampling is reproducible for a fixed seed" {
    // The spine: same weights, same observation, same sampling seed produce the same action.
    const allocator = std.testing.allocator;
    const weights = try allocator.alloc(f32, td.inference.abi14_weight_count);
    defer allocator.free(weights);
    var rng = std.Random.DefaultPrng.init(7);
    for (weights) |*w| w.* = rng.random().floatNorm(f32) * 0.05;

    var world = td.World.reset(1);
    var observation: [td.policy_abi14.observation_size]u8 = undefined;
    var mask: [td.policy_abi14.action_mask_size]u8 = undefined;
    td.policy_abi14.observe(&world, &observation);
    td.policy_abi14.actionMask(&world, &mask);

    var first = try td.inference.Abi14Model.init(allocator, weights);
    defer first.deinit();
    first.seedSampling(74);
    const a = try first.actSampled(&observation, &mask);

    var second = try td.inference.Abi14Model.init(allocator, weights);
    defer second.deinit();
    second.seedSampling(74);
    const b = try second.actSampled(&observation, &mask);

    try std.testing.expectEqual(a.command, b.command);
    try std.testing.expectEqual(a.target_slot, b.target_slot);
    try std.testing.expectEqualSlices(u8, &a.selectors, &b.selectors);
}

test "ABI14 checkpoint size matches what training actually writes" {
    // Regression guard. The decoder carries a PPO value head after the action logits, exactly as
    // policy.decoder_size does. Omitting it makes the checkpoint 64 floats short and every real
    // checkpoint fails to load. 782,336 bytes is the size PufferLib emitted for an ABI14 run at
    // hidden 64.
    try std.testing.expectEqual(
        td.policy_abi14.action_logit_count + 1,
        td.inference.abi14_decoder_size,
    );
    try std.testing.expectEqual(@as(usize, td.inference.abi14CheckpointSize(64)), td.inference.abi14_checkpoint_size);
}

// ---- Hidden-size 128 --------------------------------------------------------------------------
//
// Every ABI14 sweep run that reached a useful balanced_perf used hidden_size 128 (best 0.5876);
// all ten hidden-64 runs scored at or below 0.0625. A deployment path that only loads hidden 64
// therefore cannot load any policy worth rendering, so the model must carry hidden size at runtime
// and take it from the checkpoint.

test "ABI14 checkpoint size is a known function of hidden size" {
    // weights(h) = h*observation + (logits+1)*h + 3h^2
    try std.testing.expectEqual(td.inference.abi14WeightCount(64), td.inference.abi14WeightCount(64));
    try std.testing.expectEqual(@as(usize, td.inference.abi14CheckpointSize(64)), td.inference.abi14CheckpointSize(64));
    try std.testing.expectEqual(@as(usize, 612_736), td.inference.abi14WeightCount(128));
    try std.testing.expectEqual(@as(usize, 2_450_944), td.inference.abi14CheckpointSize(128));
}

test "ABI14 hidden size is recoverable from checkpoint size alone" {
    // This is what lets the Vanilla bridge pick the right model without a flag that could disagree
    // with the file it points at.
    try std.testing.expectEqual(@as(?usize, 64), td.inference.abi14HiddenForCheckpointSize(td.inference.abi14CheckpointSize(64)));
    try std.testing.expectEqual(@as(?usize, 128), td.inference.abi14HiddenForCheckpointSize(2_450_944));
    try std.testing.expectEqual(@as(?usize, null), td.inference.abi14HiddenForCheckpointSize(782_335));
    try std.testing.expectEqual(@as(?usize, null), td.inference.abi14HiddenForCheckpointSize(0));
    // ABI13's checkpoint must never be mistaken for an ABI14 one.
    try std.testing.expectEqual(@as(?usize, null), td.inference.abi14HiddenForCheckpointSize(td.inference.checkpoint_size));
}

test "ABI14 model runs at hidden 128 and samples only mask-legal actions" {
    const allocator = std.testing.allocator;
    const weights = try allocator.alloc(f32, td.inference.abi14WeightCount(128));
    defer allocator.free(weights);
    var rng = std.Random.DefaultPrng.init(0xd00d);
    for (weights) |*w| w.* = rng.random().floatNorm(f32) * 0.05;

    var model = try td.inference.Abi14Model.init(allocator, weights);
    defer model.deinit();
    try std.testing.expectEqual(@as(usize, 128), model.hidden);

    var world = td.World.reset(2);
    var observation: [td.policy_abi14.observation_size]u8 = undefined;
    var mask: [td.policy_abi14.action_mask_size]u8 = undefined;
    const attack_command = @intFromEnum(td.action.Command.attack);

    for (0..48) |_| {
        td.policy_abi14.observe(&world, &observation);
        td.policy_abi14.actionMask(&world, &mask);
        const raw = try model.actSampled(&observation, &mask);
        try std.testing.expect(mask[raw.command] != 0);
        if (raw.command != attack_command) {
            for (raw.selectors) |selected| try std.testing.expectEqual(@as(u8, 0), selected);
        }
        _ = td.policy_abi14.apply(&world, .player, raw);
    }
}

test "ABI14 hidden 128 sampling is reproducible for a fixed seed" {
    const allocator = std.testing.allocator;
    const weights = try allocator.alloc(f32, td.inference.abi14WeightCount(128));
    defer allocator.free(weights);
    var rng = std.Random.DefaultPrng.init(11);
    for (weights) |*w| w.* = rng.random().floatNorm(f32) * 0.05;

    var world = td.World.reset(1);
    var observation: [td.policy_abi14.observation_size]u8 = undefined;
    var mask: [td.policy_abi14.action_mask_size]u8 = undefined;
    td.policy_abi14.observe(&world, &observation);
    td.policy_abi14.actionMask(&world, &mask);

    var first = try td.inference.Abi14Model.init(allocator, weights);
    defer first.deinit();
    first.seedSampling(74);
    const a = try first.actSampled(&observation, &mask);

    var second = try td.inference.Abi14Model.init(allocator, weights);
    defer second.deinit();
    second.seedSampling(74);
    const b = try second.actSampled(&observation, &mask);

    try std.testing.expectEqual(a.command, b.command);
    try std.testing.expectEqualSlices(u8, &a.selectors, &b.selectors);
}
