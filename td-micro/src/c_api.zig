const std = @import("std");
const batch_mod = @import("batch.zig");
const curriculum = @import("curriculum.zig");
const difficulty = @import("difficulty.zig");
const digest = @import("digest.zig");
const inference = @import("inference.zig");
const map = @import("map.zig");
const policy = @import("policy.zig");
const policy_abi9 = @import("policy_abi9.zig");
const policy_abi14 = @import("policy_abi14.zig");
const rules = @import("rules.zig");

const Batch = batch_mod.Batch;
const LegacyStats = extern struct {
    decisions: u64,
    episodes: u64,
    wins: u64,
    losses: u64,
    draws: u64,
    invalid_actions: u64,
    building_limit_losses: u64,
    infantry_limit_losses: u64,
    invalid_streak_losses: u64,
    failures: u64,
    episode_decisions: u64,
    close_episodes: u64,
    close_wins: u64,
    close_losses: u64,
    medium_episodes: u64,
    medium_wins: u64,
    medium_losses: u64,
    close_mcv_episodes: u64,
    close_mcv_wins: u64,
    close_mcv_losses: u64,
    close_force_episodes: u64,
    close_force_wins: u64,
    close_force_losses: u64,
    medium_mcv_episodes: u64,
    medium_mcv_wins: u64,
    medium_mcv_losses: u64,
    medium_force_episodes: u64,
    medium_force_wins: u64,
    medium_force_losses: u64,
    completed_invalid_actions: u64,
    invalid_action_penalty: f64,
};

pub export fn td_micro_abi_version() u32 {
    return policy.abi_version;
}

pub export fn td_micro_observation_size() u32 {
    return policy.observation_size;
}

pub export fn td_micro_action_head_count() u32 {
    return policy.action_head_count;
}

pub export fn td_micro_action_mask_size() u32 {
    return policy.action_mask_size;
}

pub export fn td_micro_action_head_count_abi9() u32 {
    return policy_abi9.action_head_count;
}

pub export fn td_micro_action_mask_size_abi9() u32 {
    return policy_abi9.action_mask_size;
}

pub export fn td_micro_action_head_count_abi14() u32 {
    return policy_abi14.action_head_count;
}

pub export fn td_micro_action_mask_size_abi14() u32 {
    return policy_abi14.action_mask_size;
}

pub export fn td_micro_player_building_limit() u32 {
    return batch_mod.player_building_limit;
}

pub export fn td_micro_player_infantry_limit() u32 {
    return batch_mod.player_infantry_limit;
}

pub export fn td_micro_consecutive_invalid_action_limit() u32 {
    return batch_mod.consecutive_invalid_action_limit;
}

pub export fn td_micro_training_timeout_frames() u32 {
    return batch_mod.training_timeout_frames;
}

pub export fn td_micro_training_max_decisions() u32 {
    return batch_mod.training_max_decisions;
}

pub export fn td_micro_default_reward_config(output: ?*batch_mod.RewardConfig) c_int {
    const config = output orelse return 0;
    config.* = batch_mod.default_reward_config;
    return 1;
}

pub export fn td_micro_reward_config_valid(config: ?*const batch_mod.RewardConfig) c_int {
    const reward_config = config orelse return 0;
    return @intFromBool(reward_config.valid());
}

pub export fn td_micro_curriculum_schedule_valid(schedule_id: u32) c_int {
    return @intFromBool(curriculum.scheduleFromInt(schedule_id) != null);
}

pub export fn td_micro_curriculum_config_valid(
    schedule_id: u32,
    stage_decisions: u64,
    starting_force_ramp_decisions: u64,
) c_int {
    const schedule = curriculum.scheduleFromInt(schedule_id) orelse return 0;
    return @intFromBool(curriculum.configValid(
        schedule,
        stage_decisions,
        starting_force_ramp_decisions,
    ));
}

pub export fn td_micro_difficulty_schedule_valid(schedule_id: u32) c_int {
    return @intFromBool(difficulty.scheduleFromInt(schedule_id) != null);
}

pub export fn td_micro_difficulty_config_valid(
    schedule_id: u32,
    ramp_decisions: u64,
) c_int {
    const schedule = difficulty.scheduleFromInt(schedule_id) orelse return 0;
    return @intFromBool(difficulty.configValid(schedule, ramp_decisions));
}

pub export fn td_micro_action_head_sizes(output: ?[*]u16, capacity: u32) u32 {
    const pointer = output orelse return policy.action_head_count;
    const count = @min(@as(usize, capacity), policy.action_head_count);
    @memcpy(pointer[0..count], policy.action_head_sizes[0..count]);
    return policy.action_head_count;
}

pub export fn td_micro_action_head_sizes_abi9(output: ?[*]u16, capacity: u32) u32 {
    const pointer = output orelse return policy_abi9.action_head_count;
    const count = @min(@as(usize, capacity), policy_abi9.action_head_count);
    @memcpy(pointer[0..count], policy_abi9.action_head_sizes[0..count]);
    return policy_abi9.action_head_count;
}

pub export fn td_micro_action_head_sizes_abi14(output: ?[*]u16, capacity: u32) u32 {
    const pointer = output orelse return policy_abi14.action_head_count;
    const count = @min(@as(usize, capacity), policy_abi14.action_head_count);
    @memcpy(pointer[0..count], policy_abi14.action_head_sizes[0..count]);
    return policy_abi14.action_head_count;
}

pub export fn td_micro_ruleset_hash(output: ?[*]u8, capacity: u32) u32 {
    const pointer = output orelse return rules.manifest_sha256.len;
    const count = @min(@as(usize, capacity), rules.manifest_sha256.len);
    @memcpy(pointer[0..count], rules.manifest_sha256[0..count]);
    return rules.manifest_sha256.len;
}

pub export fn td_micro_balanced_spawn_seed(base_seed: u64, ordinal: u64) u64 {
    const agent_ordinal = std.math.cast(usize, ordinal) orelse return 0;
    return map.balancedSeed(base_seed, agent_ordinal);
}

pub export fn td_micro_policy_weight_count() u32 {
    return inference.weight_count;
}

pub export fn td_micro_policy_checkpoint_size() u32 {
    return inference.checkpoint_size;
}

pub export fn td_micro_policy_hidden_for_checkpoint_size(bytes: u32) u32 {
    const hidden = inference.hiddenForCheckpointSize(bytes) orelse return 0;
    return @intCast(hidden);
}

pub export fn td_micro_policy_hidden_size(instance: ?*const inference.Model) u32 {
    const model = instance orelse return 0;
    return @intCast(model.hidden);
}

pub export fn td_micro_policy_create(checkpoint: ?[*]const u8, checkpoint_size: u32) ?*inference.Model {
    const checkpoint_pointer = checkpoint orelse return null;
    if (inference.hiddenForCheckpointSize(checkpoint_size) == null) return null;
    const allocator = std.heap.c_allocator;
    const instance = allocator.create(inference.Model) catch return null;
    instance.* = inference.Model.initBytes(allocator, checkpoint_pointer[0..checkpoint_size]) catch {
        allocator.destroy(instance);
        return null;
    };
    return instance;
}

pub export fn td_micro_policy_destroy(instance: ?*inference.Model) void {
    const model = instance orelse return;
    const allocator = std.heap.c_allocator;
    model.deinit();
    allocator.destroy(model);
}

pub export fn td_micro_policy_reset(instance: ?*inference.Model) c_int {
    const model = instance orelse return 0;
    model.reset();
    return 1;
}

pub export fn td_micro_policy_seed_sampling(instance: ?*inference.Model, seed: u64) c_int {
    const model = instance orelse return 0;
    model.seedSampling(seed);
    return 1;
}

pub export fn td_micro_policy_checkpoint_sha256(
    instance: ?*const inference.Model,
    output: ?[*]u8,
    capacity: u32,
) u32 {
    const model = instance orelse return 0;
    const pointer = output orelse return model.checkpoint_sha256.len;
    if (capacity < model.checkpoint_sha256.len) return model.checkpoint_sha256.len;
    @memcpy(pointer[0..model.checkpoint_sha256.len], &model.checkpoint_sha256);
    return model.checkpoint_sha256.len;
}

pub export fn td_micro_policy_act(
    instance: ?*inference.Model,
    observation: ?[*]const u8,
    observation_size: u32,
    action_mask: ?[*]const u8,
    action_mask_size: u32,
    output: ?*policy.RawAction,
) c_int {
    const model = instance orelse return 0;
    const observation_pointer = observation orelse return 0;
    const mask_pointer = action_mask orelse return 0;
    const action_pointer = output orelse return 0;
    if (observation_size != policy.observation_size or action_mask_size != policy.action_mask_size) return 0;
    const observation_array: *const [policy.observation_size]u8 = @ptrCast(observation_pointer);
    const mask_array: *const [policy.action_mask_size]u8 = @ptrCast(mask_pointer);
    action_pointer.* = model.act(observation_array, mask_array) catch return 0;
    return 1;
}

pub export fn td_micro_policy_act_sampled(
    instance: ?*inference.Model,
    observation: ?[*]const u8,
    observation_size: u32,
    action_mask: ?[*]const u8,
    action_mask_size: u32,
    output: ?*policy.RawAction,
) c_int {
    const model = instance orelse return 0;
    const observation_pointer = observation orelse return 0;
    const mask_pointer = action_mask orelse return 0;
    const action_pointer = output orelse return 0;
    if (observation_size != policy.observation_size or action_mask_size != policy.action_mask_size) return 0;
    const observation_array: *const [policy.observation_size]u8 = @ptrCast(observation_pointer);
    const mask_array: *const [policy.action_mask_size]u8 = @ptrCast(mask_pointer);
    action_pointer.* = model.actSampled(observation_array, mask_array) catch return 0;
    return 1;
}

// --- ABI14 policy inference ------------------------------------------------------------------
// Mirrors the ABI13 entry points above against Abi14Model. Separate handles rather than a mode flag
// on one type, so a caller cannot accidentally feed an ABI14 checkpoint to the ABI13 decode: the
// checkpoint sizes differ and each create rejects the wrong one.

pub export fn td_micro_policy_weight_count_abi14() u32 {
    return inference.abi14_weight_count;
}

pub export fn td_micro_policy_checkpoint_size_abi14() u32 {
    return inference.abi14_checkpoint_size;
}

/// Hidden size implied by a checkpoint length, or 0 if the length is not a valid ABI14 checkpoint.
/// Lets C consumers identify an ABI14 artifact without hardcoding one hidden size.
pub export fn td_micro_policy_abi14_hidden_for_checkpoint_size(bytes: u32) u32 {
    const hidden = inference.abi14HiddenForCheckpointSize(bytes) orelse return 0;
    return @intCast(hidden);
}

pub export fn td_micro_policy_hidden_size_abi14(instance: ?*const inference.Abi14Model) u32 {
    const model = instance orelse return 0;
    return @intCast(model.hidden);
}

pub export fn td_micro_policy_create_abi14(
    checkpoint: ?[*]const u8,
    checkpoint_size: u32,
) ?*inference.Abi14Model {
    const checkpoint_pointer = checkpoint orelse return null;
    if (inference.abi14HiddenForCheckpointSize(checkpoint_size) == null) return null;
    const allocator = std.heap.c_allocator;
    const instance = allocator.create(inference.Abi14Model) catch return null;
    instance.* = inference.Abi14Model.initBytes(allocator, checkpoint_pointer[0..checkpoint_size]) catch {
        allocator.destroy(instance);
        return null;
    };
    return instance;
}

pub export fn td_micro_policy_destroy_abi14(instance: ?*inference.Abi14Model) void {
    const model = instance orelse return;
    const allocator = std.heap.c_allocator;
    model.deinit();
    allocator.destroy(model);
}

pub export fn td_micro_policy_reset_abi14(instance: ?*inference.Abi14Model) c_int {
    const model = instance orelse return 0;
    model.reset();
    return 1;
}

pub export fn td_micro_policy_seed_sampling_abi14(instance: ?*inference.Abi14Model, seed: u64) c_int {
    const model = instance orelse return 0;
    model.seedSampling(seed);
    return 1;
}

pub export fn td_micro_policy_checkpoint_sha256_abi14(
    instance: ?*const inference.Abi14Model,
    output: ?[*]u8,
    capacity: u32,
) u32 {
    const model = instance orelse return 0;
    const pointer = output orelse return model.checkpoint_sha256.len;
    if (capacity < model.checkpoint_sha256.len) return model.checkpoint_sha256.len;
    @memcpy(pointer[0..model.checkpoint_sha256.len], &model.checkpoint_sha256);
    return model.checkpoint_sha256.len;
}

pub export fn td_micro_policy_act_sampled_abi14(
    instance: ?*inference.Abi14Model,
    observation: ?[*]const u8,
    observation_size: u32,
    action_mask: ?[*]const u8,
    action_mask_size: u32,
    output: ?*policy_abi14.RawAction,
) c_int {
    const model = instance orelse return 0;
    const observation_pointer = observation orelse return 0;
    const mask_pointer = action_mask orelse return 0;
    const action_pointer = output orelse return 0;
    if (observation_size != policy_abi14.observation_size or
        action_mask_size != policy_abi14.action_mask_size) return 0;
    const observation_array: *const [policy_abi14.observation_size]u8 = @ptrCast(observation_pointer);
    const mask_array: *const [policy_abi14.action_mask_size]u8 = @ptrCast(mask_pointer);
    action_pointer.* = model.actSampled(observation_array, mask_array) catch return 0;
    return 1;
}

pub export fn td_micro_batch_create(count: u32, max_decisions: u32) ?*Batch {
    return createBatch(count, max_decisions, batch_mod.default_reward_config, .full_match, 0, 0, null, 0);
}

pub export fn td_micro_batch_create_with_reward_config(
    count: u32,
    max_decisions: u32,
    reward_config: ?*const batch_mod.RewardConfig,
) ?*Batch {
    const config = reward_config orelse return null;
    return createBatch(count, max_decisions, config.*, .full_match, 0, 0, null, 0);
}

pub export fn td_micro_batch_create_with_configs(
    count: u32,
    max_decisions: u32,
    reward_config: ?*const batch_mod.RewardConfig,
    curriculum_schedule_id: u32,
    curriculum_stage_decisions: u64,
    starting_force_ramp_decisions: u64,
) ?*Batch {
    const config = reward_config orelse return null;
    const schedule = curriculum.scheduleFromInt(curriculum_schedule_id) orelse return null;
    return createBatch(
        count,
        max_decisions,
        config.*,
        schedule,
        curriculum_stage_decisions,
        starting_force_ramp_decisions,
        null,
        0,
    );
}

pub export fn td_micro_batch_create_with_configs_v2(
    count: u32,
    max_decisions: u32,
    reward_config: ?*const batch_mod.RewardConfig,
    curriculum_schedule_id: u32,
    curriculum_stage_decisions: u64,
    starting_force_ramp_decisions: u64,
    difficulty_schedule_id: u32,
    difficulty_ramp_decisions: u64,
) ?*Batch {
    const config = reward_config orelse return null;
    const schedule = curriculum.scheduleFromInt(curriculum_schedule_id) orelse return null;
    const difficulty_schedule = difficulty.scheduleFromInt(difficulty_schedule_id) orelse return null;
    return createBatch(
        count,
        max_decisions,
        config.*,
        schedule,
        curriculum_stage_decisions,
        starting_force_ramp_decisions,
        difficulty_schedule,
        difficulty_ramp_decisions,
    );
}

fn createBatch(
    count: u32,
    max_decisions: u32,
    reward_config: batch_mod.RewardConfig,
    curriculum_schedule: curriculum.Schedule,
    curriculum_stage_decisions: u64,
    starting_force_ramp_decisions: u64,
    difficulty_schedule: ?difficulty.Schedule,
    difficulty_ramp_decisions: u64,
) ?*Batch {
    if (count == 0) return null;
    const allocator = std.heap.c_allocator;
    const instance = allocator.create(Batch) catch return null;
    instance.* = if (difficulty_schedule) |selected|
        Batch.initWithConfigs(
            allocator,
            count,
            max_decisions,
            reward_config,
            curriculum_schedule,
            curriculum_stage_decisions,
            starting_force_ramp_decisions,
            selected,
            difficulty_ramp_decisions,
        ) catch {
            allocator.destroy(instance);
            return null;
        }
    else
        Batch.initWithCurriculum(
            allocator,
            count,
            max_decisions,
            reward_config,
            curriculum_schedule,
            curriculum_stage_decisions,
            starting_force_ramp_decisions,
        ) catch {
            allocator.destroy(instance);
            return null;
        };
    return instance;
}

pub export fn td_micro_batch_destroy(instance: ?*Batch) void {
    const batch = instance orelse return;
    const allocator = std.heap.c_allocator;
    batch.deinit(allocator);
    allocator.destroy(batch);
}

pub export fn td_micro_batch_count(instance: ?*const Batch) u32 {
    const batch = instance orelse return 0;
    return @intCast(batch.worlds.len);
}

pub export fn td_micro_batch_snapshot_size(instance: ?*const Batch) usize {
    const batch = instance orelse return 0;
    return batch.snapshotSize();
}

pub export fn td_micro_batch_write_snapshot(
    instance: ?*const Batch,
    output: ?[*]u8,
    capacity: usize,
) c_int {
    const batch = instance orelse return 0;
    const pointer = output orelse return 0;
    if (capacity != batch.snapshotSize()) return 0;
    batch.writeSnapshot(pointer[0..capacity]) catch return 0;
    return 1;
}

pub export fn td_micro_batch_read_snapshot(
    instance: ?*Batch,
    input: ?[*]const u8,
    size: usize,
) c_int {
    const batch = instance orelse return 0;
    const pointer = input orelse return 0;
    if (size != batch.snapshotSize()) return 0;
    batch.readSnapshot(pointer[0..size]) catch return 0;
    return 1;
}

pub export fn td_micro_reset_batch(instance: ?*Batch, seeds: ?[*]const u64, count: u32) c_int {
    const batch = instance orelse return 0;
    const seed_pointer = seeds orelse return 0;
    if (count != batch.worlds.len) return 0;
    batch.reset(seed_pointer[0..count]) catch return 0;
    return 1;
}

pub export fn td_micro_observe_batch(
    instance: ?*const Batch,
    observations: ?[*]u8,
    action_masks: ?[*]u8,
    count: u32,
) c_int {
    const batch = instance orelse return 0;
    const observation_pointer = observations orelse return 0;
    const mask_pointer = action_masks orelse return 0;
    if (count != batch.worlds.len) return 0;
    batch.observe(
        observation_pointer[0 .. @as(usize, count) * policy.observation_size],
        mask_pointer[0 .. @as(usize, count) * policy.action_mask_size],
    );
    return 1;
}

pub export fn td_micro_observe_batch_abi9(
    instance: ?*const Batch,
    observations: ?[*]u8,
    action_masks: ?[*]u8,
    count: u32,
) c_int {
    const batch = instance orelse return 0;
    const observation_pointer = observations orelse return 0;
    const mask_pointer = action_masks orelse return 0;
    if (count != batch.worlds.len) return 0;
    batch.observeAbi9(
        observation_pointer[0 .. @as(usize, count) * policy.observation_size],
        mask_pointer[0 .. @as(usize, count) * policy_abi9.action_mask_size],
    );
    return 1;
}

pub export fn td_micro_observe_batch_abi14(
    instance: ?*const Batch,
    observations: ?[*]u8,
    action_masks: ?[*]u8,
    count: u32,
) c_int {
    const batch = instance orelse return 0;
    const observation_pointer = observations orelse return 0;
    const mask_pointer = action_masks orelse return 0;
    if (count != batch.worlds.len) return 0;
    batch.observeAbi14(
        observation_pointer[0 .. @as(usize, count) * policy.observation_size],
        mask_pointer[0 .. @as(usize, count) * policy_abi14.action_mask_size],
    );
    return 1;
}

pub export fn td_micro_step_batch(
    instance: ?*Batch,
    actions: ?[*]const policy.RawAction,
    observations: ?[*]u8,
    action_masks: ?[*]u8,
    rewards: ?[*]f32,
    terminals: ?[*]u8,
    count: u32,
) c_int {
    const batch = instance orelse return 0;
    const action_pointer = actions orelse return 0;
    const observation_pointer = observations orelse return 0;
    const mask_pointer = action_masks orelse return 0;
    const reward_pointer = rewards orelse return 0;
    const terminal_pointer = terminals orelse return 0;
    if (count != batch.worlds.len) return 0;
    batch.step(
        action_pointer[0..count],
        observation_pointer[0 .. @as(usize, count) * policy.observation_size],
        mask_pointer[0 .. @as(usize, count) * policy.action_mask_size],
        reward_pointer[0..count],
        terminal_pointer[0..count],
    );
    return 1;
}

pub export fn td_micro_step_batch_abi9(
    instance: ?*Batch,
    actions: ?[*]const policy_abi9.RawAction,
    observations: ?[*]u8,
    action_masks: ?[*]u8,
    rewards: ?[*]f32,
    terminals: ?[*]u8,
    count: u32,
) c_int {
    const batch = instance orelse return 0;
    const action_pointer = actions orelse return 0;
    const observation_pointer = observations orelse return 0;
    const mask_pointer = action_masks orelse return 0;
    const reward_pointer = rewards orelse return 0;
    const terminal_pointer = terminals orelse return 0;
    if (count != batch.worlds.len) return 0;
    batch.stepAbi9(
        action_pointer[0..count],
        observation_pointer[0 .. @as(usize, count) * policy.observation_size],
        mask_pointer[0 .. @as(usize, count) * policy_abi9.action_mask_size],
        reward_pointer[0..count],
        terminal_pointer[0..count],
    );
    return 1;
}

pub export fn td_micro_step_batch_abi14(
    instance: ?*Batch,
    actions: ?[*]const policy_abi14.RawAction,
    observations: ?[*]u8,
    action_masks: ?[*]u8,
    rewards: ?[*]f32,
    terminals: ?[*]u8,
    count: u32,
) c_int {
    const batch = instance orelse return 0;
    const action_pointer = actions orelse return 0;
    const observation_pointer = observations orelse return 0;
    const mask_pointer = action_masks orelse return 0;
    const reward_pointer = rewards orelse return 0;
    const terminal_pointer = terminals orelse return 0;
    if (count != batch.worlds.len) return 0;
    batch.stepAbi14(
        action_pointer[0..count],
        observation_pointer[0 .. @as(usize, count) * policy.observation_size],
        mask_pointer[0 .. @as(usize, count) * policy_abi14.action_mask_size],
        reward_pointer[0..count],
        terminal_pointer[0..count],
    );
    return 1;
}

pub export fn td_micro_batch_stats(instance: ?*const Batch, output: ?*LegacyStats) c_int {
    const batch = instance orelse return 0;
    const stats = output orelse return 0;
    @memcpy(std.mem.asBytes(stats), std.mem.asBytes(&batch.stats)[0..@sizeOf(LegacyStats)]);
    return 1;
}

pub export fn td_micro_batch_stats_v2(instance: ?*const Batch, output: ?*batch_mod.Stats) c_int {
    const batch = instance orelse return 0;
    const stats = output orelse return 0;
    stats.* = batch.stats;
    return 1;
}

pub export fn td_micro_batch_metrics(instance: ?*const Batch, output: ?*batch_mod.Metrics) c_int {
    const batch = instance orelse return 0;
    const metrics = output orelse return 0;
    metrics.* = batch.metrics;
    return 1;
}

pub export fn td_micro_batch_world_digest(
    instance: ?*const Batch,
    world_index: u32,
    output: ?[*]u8,
    capacity: u32,
) u32 {
    const batch = instance orelse return 0;
    const pointer = output orelse return 0;
    if (world_index >= batch.worlds.len or capacity < 32) return 0;
    const value = digest.canonical(&batch.worlds[world_index]);
    @memcpy(pointer[0..value.len], &value);
    return value.len;
}

comptime {
    std.debug.assert(@sizeOf(policy.RawAction) == 4);
    std.debug.assert(@sizeOf(policy_abi9.RawAction) == 7);
    std.debug.assert(@sizeOf(policy_abi14.RawAction) == 71);
    std.debug.assert(@sizeOf(LegacyStats) == 248);
    // 416 = CNC26's 376 plus five appended u64 counters (constrained pair, build-order violations,
    // attack attempted/applied). They sit after the difficulty split so the legacy prefix is intact.
    // 424 = 416 plus economy_wins (CNC26 win grading).
    std.debug.assert(@sizeOf(batch_mod.Stats) == 424);
    std.debug.assert(@offsetOf(batch_mod.Stats, "easy_close_mcv_episodes") == @sizeOf(LegacyStats));
    // 56 = 48 plus reward_weapons_factory and reward_vehicle (CNC26).
    // 64 = 56 plus reward_economy_win, reward_rush_win and economy_win_credits.
    // 84 = 80 plus reward_tank_kill. The two one-time armour rewards and qualified-loss terminal
    // value append three more ABI words.
    std.debug.assert(@sizeOf(batch_mod.RewardConfig) == 96);
    std.debug.assert(@offsetOf(batch_mod.RewardConfig, "reward_qualified_loss") ==
        @sizeOf(batch_mod.RewardConfig) - @sizeOf(f32));
    std.debug.assert(@sizeOf(batch_mod.Metrics) == 344);
}
