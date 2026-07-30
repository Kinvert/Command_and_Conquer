const std = @import("std");
const policy = @import("policy.zig");

pub const hidden_size: usize = 64;
pub const hidden_sizes = [_]usize{ 64, 128 };
pub const max_hidden_size: usize = 128;
pub const decoder_size: usize = policy.decoder_size;
pub const encoder_weight_count: usize = hidden_size * policy.observation_size;
pub const decoder_weight_count: usize = decoder_size * hidden_size;
pub const mingru_weight_count: usize = 3 * hidden_size * hidden_size;
pub const decoder_offset: usize = encoder_weight_count;
pub const mingru_offset: usize = decoder_offset + decoder_weight_count;
pub const weight_count: usize = mingru_offset + mingru_weight_count;
pub const checkpoint_size: usize = weight_count * @sizeOf(f32);
pub const observation_scale: f32 = 1.0 / 255.0;

pub fn weightCountForHidden(hidden: usize) usize {
    return hidden * policy.observation_size + decoder_size * hidden + 3 * hidden * hidden;
}

pub fn checkpointSizeForHidden(hidden: usize) usize {
    return weightCountForHidden(hidden) * @sizeOf(f32);
}

pub fn hiddenForCheckpointSize(bytes: usize) ?usize {
    for (hidden_sizes) |hidden| {
        if (checkpointSizeForHidden(hidden) == bytes) return hidden;
    }
    return null;
}

pub const Model = struct {
    allocator: std.mem.Allocator,
    weights: []f32,
    checkpoint_sha256: [32]u8,
    hidden: usize,
    state: [max_hidden_size]f32,
    encoded: [max_hidden_size]f32,
    combined: [3 * max_hidden_size]f32,
    recurrent_output: [max_hidden_size]f32,
    logits: [decoder_size]f32,
    head_logits: [policy.token_count]f32,
    head_mask: [policy.token_count]u8,
    sampling_state: u64,

    pub fn init(allocator: std.mem.Allocator, source: []const f32) !Model {
        return initBytes(allocator, std.mem.sliceAsBytes(source));
    }

    pub fn initBytes(allocator: std.mem.Allocator, source: []const u8) !Model {
        const hidden = hiddenForCheckpointSize(source.len) orelse
            return error.InvalidCheckpointSize;
        var checkpoint_sha256: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(source, &checkpoint_sha256, .{});

        const weights = try allocator.alloc(f32, weightCountForHidden(hidden));
        errdefer allocator.free(weights);
        @memcpy(std.mem.sliceAsBytes(weights), source);
        for (weights) |*destination| {
            const value = destination.*;
            if (!std.math.isFinite(value)) return error.NonFiniteWeight;
            destination.* = roundBf16(value);
        }

        return .{
            .allocator = allocator,
            .weights = weights,
            .checkpoint_sha256 = checkpoint_sha256,
            .hidden = hidden,
            .state = [_]f32{0} ** max_hidden_size,
            .encoded = undefined,
            .combined = undefined,
            .recurrent_output = undefined,
            .logits = undefined,
            .head_logits = undefined,
            .head_mask = undefined,
            .sampling_state = 1,
        };
    }

    pub fn deinit(self: *Model) void {
        self.allocator.free(self.weights);
        self.weights = &.{};
    }

    pub fn reset(self: *Model) void {
        @memset(&self.state, 0);
    }

    pub fn seedSampling(self: *Model, seed: u64) void {
        self.sampling_state = if (seed == 0) 1 else seed;
    }

    pub fn act(
        self: *Model,
        observation: *const [policy.observation_size]u8,
        mask: *const [policy.action_mask_size]u8,
    ) !policy.RawAction {
        const prior_state = self.state;
        errdefer self.state = prior_state;
        try self.forward(observation);

        var result: policy.RawAction = .{};
        self.fillCommandMask(mask);
        result.command = try maskedArgmax(
            self.logits[policy.command_logits_offset .. policy.command_logits_offset + policy.command_count],
            self.head_mask[0..policy.command_count],
        );
        const command: @import("action.zig").Command = @enumFromInt(result.command);
        inline for (0..3) |argument_index| {
            const prior = priorToken(result, argument_index);
            self.fillArgumentMask(mask, command, argument_index, prior);
            self.argumentLogits(result, argument_index);
            const selected = try maskedArgmax(
                &self.head_logits,
                &self.head_mask,
            );
            setArgument(&result, argument_index, selected);
        }
        return result;
    }

    pub fn actSampled(
        self: *Model,
        observation: *const [policy.observation_size]u8,
        mask: *const [policy.action_mask_size]u8,
    ) !policy.RawAction {
        const prior_state = self.state;
        const prior_sampling_state = self.sampling_state;
        errdefer {
            self.state = prior_state;
            self.sampling_state = prior_sampling_state;
        }
        try self.forward(observation);

        var result: policy.RawAction = .{};
        self.fillCommandMask(mask);
        result.command = try maskedSample(
            self.logits[policy.command_logits_offset .. policy.command_logits_offset + policy.command_count],
            self.head_mask[0..policy.command_count],
            self.nextUniform(),
        );
        const command: @import("action.zig").Command = @enumFromInt(result.command);
        inline for (0..3) |argument_index| {
            const prior = priorToken(result, argument_index);
            self.fillArgumentMask(mask, command, argument_index, prior);
            self.argumentLogits(result, argument_index);
            const selected = try maskedSample(
                &self.head_logits,
                &self.head_mask,
                self.nextUniform(),
            );
            setArgument(&result, argument_index, selected);
        }
        return result;
    }

    fn forward(self: *Model, observation: *const [policy.observation_size]u8) !void {
        self.encode(observation);
        try self.recur();
        self.decode();
    }

    fn nextUniform(self: *Model) f32 {
        self.sampling_state +%= 0x9e3779b97f4a7c15;
        var bits = self.sampling_state;
        bits = (bits ^ (bits >> 30)) *% 0xbf58476d1ce4e5b9;
        bits = (bits ^ (bits >> 27)) *% 0x94d049bb133111eb;
        bits ^= bits >> 31;
        const sample: u24 = @truncate(bits >> 40);
        return (@as(f32, @floatFromInt(sample)) + 1.0) * (1.0 / 16_777_216.0);
    }

    fn encoderWeightCount(self: *const Model) usize {
        return self.hidden * policy.observation_size;
    }

    fn decoderOffset(self: *const Model) usize {
        return self.encoderWeightCount();
    }

    fn mingruOffset(self: *const Model) usize {
        return self.decoderOffset() + decoder_size * self.hidden;
    }

    fn encode(self: *Model, observation: *const [policy.observation_size]u8) void {
        const weights = self.weights[0..self.encoderWeightCount()];
        for (0..self.hidden) |output| {
            const row = weights[output * policy.observation_size ..][0..policy.observation_size];
            var sum: f32 = 0;
            for (observation, row) |value, weight| {
                sum += @as(f32, @floatFromInt(value)) * observation_scale * weight;
            }
            self.encoded[output] = roundBf16(sum);
        }
    }

    fn recur(self: *Model) !void {
        const weights = self.weights[self.mingruOffset()..];
        for (0..3 * self.hidden) |output| {
            const row = weights[output * self.hidden ..][0..self.hidden];
            var sum: f32 = 0;
            for (self.encoded[0..self.hidden], row) |value, weight| sum += value * weight;
            self.combined[output] = roundBf16(sum);
        }

        for (0..self.hidden) |index| {
            const hidden = self.combined[index];
            const gate = sigmoid(self.combined[self.hidden + index]);
            const highway = sigmoid(self.combined[2 * self.hidden + index]);
            const candidate = if (hidden >= 0) hidden + 0.5 else sigmoid(hidden);
            const next_state = self.state[index] + gate * (candidate - self.state[index]);
            const output = highway * next_state + (1.0 - highway) * self.encoded[index];
            if (!std.math.isFinite(next_state) or !std.math.isFinite(output)) return error.NonFiniteActivation;
            self.state[index] = roundBf16(next_state);
            self.recurrent_output[index] = roundBf16(output);
        }
    }

    fn decode(self: *Model) void {
        const weights = self.weights[self.decoderOffset()..self.mingruOffset()];
        for (0..decoder_size) |output| {
            const row = weights[output * self.hidden ..][0..self.hidden];
            var sum: f32 = 0;
            for (self.recurrent_output[0..self.hidden], row) |value, weight| sum += value * weight;
            self.logits[output] = roundBf16(sum);
        }
    }

    fn argumentLogits(self: *Model, raw: policy.RawAction, argument_index: usize) void {
        const stage_base = switch (argument_index) {
            0 => policy.arg0_command_logits_offset,
            1 => policy.arg1_command_logits_offset,
            2 => policy.arg2_command_logits_offset,
            else => unreachable,
        };
        const base = stage_base + @as(usize, raw.command) * policy.token_count;
        for (0..policy.token_count) |token| {
            var score = self.logits[base + token];
            const command: @import("action.zig").Command = @enumFromInt(raw.command);
            const query = policy.actorQueryOffset(command, raw.arg0);
            const key = policy.targetKeyOffset(command, @intCast(argument_index), @intCast(token));
            if (query != null and key != null) {
                var dot: f32 = 0;
                for (0..policy.actor_target_rank) |rank| {
                    dot += self.logits[query.? + rank] * self.logits[key.? + rank];
                }
                score += policy.actor_target_bound * std.math.tanh(
                    (policy.actor_target_scale / policy.actor_target_bound) * dot,
                );
            }
            self.head_logits[token] = score;
        }
    }

    fn fillCommandMask(self: *Model, mask: *const [policy.action_mask_size]u8) void {
        @memset(&self.head_mask, 0);
        for (0..policy.command_count) |command| {
            self.head_mask[command] = @intFromBool(policy.commandAllowed(mask, @enumFromInt(command)));
        }
    }

    fn fillArgumentMask(
        self: *Model,
        mask: *const [policy.action_mask_size]u8,
        command: @import("action.zig").Command,
        argument_index: u2,
        prior: u8,
    ) void {
        for (0..policy.token_count) |token| {
            self.head_mask[token] = @intFromBool(policy.argumentAllowed(
                mask,
                command,
                argument_index,
                prior,
                @intCast(token),
            ));
        }
    }
};

fn priorToken(raw: policy.RawAction, argument_index: usize) u8 {
    return switch (argument_index) {
        0 => policy.pad_token,
        1 => raw.arg0,
        2 => raw.arg1,
        else => unreachable,
    };
}

fn setArgument(raw: *policy.RawAction, argument_index: usize, value: u8) void {
    switch (argument_index) {
        0 => raw.arg0 = value,
        1 => raw.arg1 = value,
        2 => raw.arg2 = value,
        else => unreachable,
    }
}

pub fn roundBf16(value: f32) f32 {
    const bits: u32 = @bitCast(value);
    if ((bits & 0x7f80_0000) == 0x7f80_0000) return value;
    const rounded = bits +% 0x0000_7fff +% ((bits >> 16) & 1);
    return @bitCast(rounded & 0xffff_0000);
}

fn sigmoid(value: f32) f32 {
    return 1.0 / (1.0 + @exp(-value));
}

fn maskedArgmax(logits: []const f32, mask: []const u8) !u8 {
    std.debug.assert(logits.len == mask.len and logits.len <= std.math.maxInt(u8) + 1);
    var found = false;
    var selected: u8 = 0;
    var maximum: f32 = -std.math.inf(f32);
    for (logits, mask, 0..) |logit, allowed, index| {
        if (allowed == 0) continue;
        if (!std.math.isFinite(logit)) return error.NonFiniteActivation;
        if (!found or logit > maximum) {
            found = true;
            maximum = logit;
            selected = @intCast(index);
        }
    }
    if (!found) return error.EmptyActionMask;
    return selected;
}

fn maskedSample(logits: []const f32, mask: []const u8, uniform: f32) !u8 {
    std.debug.assert(logits.len == mask.len and logits.len <= std.math.maxInt(u8) + 1);
    var found = false;
    var maximum: f32 = -std.math.inf(f32);
    var last_legal: u8 = 0;
    for (logits, mask, 0..) |logit, allowed, index| {
        if (allowed == 0) continue;
        if (!std.math.isFinite(logit)) return error.NonFiniteActivation;
        found = true;
        last_legal = @intCast(index);
        maximum = @max(maximum, logit);
    }
    if (!found) return error.EmptyActionMask;

    var total: f32 = 0;
    for (logits, mask) |logit, allowed| {
        if (allowed != 0) total += @exp(logit - maximum);
    }
    if (!std.math.isFinite(total) or total <= 0) return error.NonFiniteActivation;

    const threshold = uniform * total;
    var cumulative: f32 = 0;
    for (logits, mask, 0..) |logit, allowed, index| {
        if (allowed == 0) continue;
        cumulative += @exp(logit - maximum);
        if (threshold < cumulative) return @intCast(index);
    }
    return last_legal;
}

// --- ABI14 deployment inference -------------------------------------------------------------
//
// ABI14 shares the trunk with the ABI13 model above: the encoder and MinGRU are identical and only
// the decoder width differs, because the action head layout changes. ABI13 decodes four heads
// autoregressively; ABI14 decodes the seven ABI9 heads independently and then 64 binary selector
// heads, which is what expresses a group attack in one action.
//
// Layout, from policy_abi14.action_head_sizes: [12, 65, 6, 4, 64, 64, 64] then 64 heads of size 2.
// Logit index and mask index coincide for the first action_logit_count entries, so a head occupying
// logits[o..o+s] is masked by mask[o..o+s].

const policy_abi14 = @import("policy_abi14.zig");

// +1 for the PPO value head, matching policy.decoder_size. Sizing this to the action logits alone
// yields a checkpoint 64 floats short of what training writes, and every real checkpoint is then
// rejected for size mismatch.
pub const abi14_decoder_size: usize = policy_abi14.action_logit_count + 1;
pub const abi14_decoder_weight_count: usize = abi14_decoder_size * hidden_size;
pub const abi14_decoder_offset: usize = encoder_weight_count;
pub const abi14_mingru_offset: usize = abi14_decoder_offset + abi14_decoder_weight_count;
pub const abi14_weight_count: usize = abi14_mingru_offset + mingru_weight_count;
pub const abi14_checkpoint_size: usize = abi14_weight_count * @sizeOf(f32);

/// Hidden sizes ABI14 training actually produced. 128 is the one that matters: every sweep run
/// that reached a useful balanced_perf used it, and hidden 64 tops out near 0.06.
pub const abi14_hidden_sizes = [_]usize{ 64, 128 };
pub const abi14_max_hidden: usize = 128;

pub fn abi14WeightCount(hidden: usize) usize {
    return hidden * policy_abi14.observation_size + abi14_decoder_size * hidden + 3 * hidden * hidden;
}

pub fn abi14CheckpointSize(hidden: usize) usize {
    return abi14WeightCount(hidden) * @sizeOf(f32);
}

/// Recovers the hidden size from a checkpoint's byte length. The candidate sizes produce distinct
/// lengths, so the artifact identifies itself and no external flag can contradict it.
pub fn abi14HiddenForCheckpointSize(bytes: usize) ?usize {
    for (abi14_hidden_sizes) |hidden| {
        if (abi14CheckpointSize(hidden) == bytes) return hidden;
    }
    return null;
}

/// Byte offset of each head within the logit vector, derived once at comptime from the head sizes
/// so it cannot drift from policy_abi14.
const abi14_head_offsets = blk: {
    var offsets: [policy_abi14.action_head_sizes.len]usize = undefined;
    var cursor: usize = 0;
    for (policy_abi14.action_head_sizes, 0..) |size, index| {
        offsets[index] = cursor;
        cursor += size;
    }
    break :blk offsets;
};

pub const Abi14Model = struct {
    allocator: std.mem.Allocator,
    weights: []f32,
    checkpoint_sha256: [32]u8,
    /// Taken from the checkpoint length, not assumed. Buffers are sized for the largest supported
    /// hidden size and used as prefixes; the waste is a few hundred floats.
    hidden: usize,
    state: [abi14_max_hidden]f32,
    encoded: [abi14_max_hidden]f32,
    combined: [3 * abi14_max_hidden]f32,
    recurrent_output: [abi14_max_hidden]f32,
    logits: [abi14_decoder_size]f32,
    sampling_state: u64,

    fn encoderWeightCount(self: *const Abi14Model) usize {
        return self.hidden * policy_abi14.observation_size;
    }

    fn decoderOffset(self: *const Abi14Model) usize {
        return self.encoderWeightCount();
    }

    fn mingruOffset(self: *const Abi14Model) usize {
        return self.decoderOffset() + abi14_decoder_size * self.hidden;
    }

    pub fn init(allocator: std.mem.Allocator, source: []const f32) !Abi14Model {
        return initBytes(allocator, std.mem.sliceAsBytes(source));
    }

    pub fn initBytes(allocator: std.mem.Allocator, source: []const u8) !Abi14Model {
        const hidden = abi14HiddenForCheckpointSize(source.len) orelse return error.InvalidCheckpointSize;
        var checkpoint_sha256: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(source, &checkpoint_sha256, .{});

        const weights = try allocator.alloc(f32, abi14WeightCount(hidden));
        errdefer allocator.free(weights);
        @memcpy(std.mem.sliceAsBytes(weights), source);
        for (weights) |weight| {
            if (!std.math.isFinite(weight)) return error.NonFiniteWeight;
        }

        return .{
            .allocator = allocator,
            .weights = weights,
            .checkpoint_sha256 = checkpoint_sha256,
            .hidden = hidden,
            .state = [_]f32{0} ** abi14_max_hidden,
            .encoded = undefined,
            .combined = undefined,
            .recurrent_output = undefined,
            .logits = undefined,
            .sampling_state = 1,
        };
    }

    pub fn deinit(self: *Abi14Model) void {
        self.allocator.free(self.weights);
        self.weights = &.{};
    }

    pub fn seedSampling(self: *Abi14Model, seed: u64) void {
        self.sampling_state = if (seed == 0) 1 else seed;
    }

    pub fn reset(self: *Abi14Model) void {
        self.state = [_]f32{0} ** abi14_max_hidden;
    }

    pub fn actSampled(
        self: *Abi14Model,
        observation: *const [policy_abi14.observation_size]u8,
        mask: *const [policy_abi14.action_mask_size]u8,
    ) !policy_abi14.RawAction {
        const prior_state = self.state;
        const prior_sampling_state = self.sampling_state;
        errdefer {
            self.state = prior_state;
            self.sampling_state = prior_sampling_state;
        }

        self.encode(observation);
        try self.recur();
        self.decode();

        var result: policy_abi14.RawAction = .{};

        // The seven ABI9 heads, sampled independently rather than autoregressively.
        inline for (0..policy_abi14.base_head_count) |head| {
            const offset = abi14_head_offsets[head];
            const size = policy_abi14.action_head_sizes[head];
            const selected = try maskedSample(
                self.logits[offset .. offset + size],
                mask[offset .. offset + size],
                self.nextUniform(),
            );
            switch (head) {
                0 => result.command = selected,
                1 => result.actor = selected,
                2 => result.product = selected,
                3 => result.target_kind = selected,
                4 => result.target_x = selected,
                5 => result.target_y = selected,
                6 => result.target_slot = selected,
                else => unreachable,
            }
        }

        // Selectors are only meaningful for a group attack. policy_abi14.apply rejects any
        // non-attack action carrying selectors, so leave them cleared rather than sampling noise
        // the simulator would then discard.
        const attack_command: u8 = @intFromEnum(@import("action.zig").Command.attack);
        if (result.command != attack_command) return result;

        for (0..policy_abi14.selector_count) |slot| {
            const head = policy_abi14.base_head_count + slot;
            const offset = abi14_head_offsets[head];
            const size = policy_abi14.action_head_sizes[head];
            result.selectors[slot] = try maskedSample(
                self.logits[offset .. offset + size],
                mask[offset .. offset + size],
                self.nextUniform(),
            );
        }
        return result;
    }

    fn nextUniform(self: *Abi14Model) f32 {
        self.sampling_state +%= 0x9e3779b97f4a7c15;
        var bits = self.sampling_state;
        bits = (bits ^ (bits >> 30)) *% 0xbf58476d1ce4e5b9;
        bits = (bits ^ (bits >> 27)) *% 0x94d049bb133111eb;
        bits ^= bits >> 31;
        const sample: u24 = @truncate(bits >> 40);
        return (@as(f32, @floatFromInt(sample)) + 1.0) * (1.0 / 16_777_216.0);
    }

    fn encode(self: *Abi14Model, observation: *const [policy_abi14.observation_size]u8) void {
        const weights = self.weights[0..self.encoderWeightCount()];
        for (0..self.hidden) |output| {
            const row = weights[output * policy_abi14.observation_size ..][0..policy_abi14.observation_size];
            var sum: f32 = 0;
            for (observation, row) |value, weight| {
                sum += @as(f32, @floatFromInt(value)) * observation_scale * weight;
            }
            self.encoded[output] = roundBf16(sum);
        }
    }

    fn recur(self: *Abi14Model) !void {
        const weights = self.weights[self.mingruOffset()..];
        for (0..3 * self.hidden) |output| {
            const row = weights[output * self.hidden ..][0..self.hidden];
            var sum: f32 = 0;
            for (self.encoded[0..self.hidden], row) |value, weight| sum += value * weight;
            self.combined[output] = roundBf16(sum);
        }
        for (0..self.hidden) |index| {
            const hidden = self.combined[index];
            const gate = sigmoid(self.combined[self.hidden + index]);
            const highway = sigmoid(self.combined[2 * self.hidden + index]);
            const candidate = if (hidden >= 0) hidden + 0.5 else sigmoid(hidden);
            const next_state = self.state[index] + gate * (candidate - self.state[index]);
            const output = highway * next_state + (1.0 - highway) * self.encoded[index];
            if (!std.math.isFinite(next_state) or !std.math.isFinite(output)) return error.NonFiniteActivation;
            self.state[index] = roundBf16(next_state);
            self.recurrent_output[index] = roundBf16(output);
        }
    }

    fn decode(self: *Abi14Model) void {
        const weights = self.weights[self.decoderOffset()..self.mingruOffset()];
        for (0..abi14_decoder_size) |output| {
            const row = weights[output * self.hidden ..][0..self.hidden];
            var sum: f32 = 0;
            for (self.recurrent_output[0..self.hidden], row) |value, weight| sum += value * weight;
            self.logits[output] = roundBf16(sum);
        }
    }
};
