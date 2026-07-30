const std = @import("std");
const action = @import("action.zig");
const curriculum = @import("curriculum.zig");
const difficulty = @import("difficulty.zig");
const input = @import("input.zig");
const policy = @import("policy.zig");
const policy_abi9 = @import("policy_abi9.zig");
const policy_abi14 = @import("policy_abi14.zig");
const rules = @import("rules.zig");
const state = @import("state.zig");
const step_sim = @import("step.zig");

pub const player_building_limit: usize = 16;
pub const player_infantry_limit: usize = 64;
pub const consecutive_invalid_action_limit: u16 = 0;
pub const training_timeout_frames: u32 = 48000;
pub const training_max_decisions: u32 = training_timeout_frames / rules.decision_frames;

pub const RewardConfig = extern struct {
    reward_milestone: f32 = 0.1,
    reward_player_infantry: f32 = 0.01,
    reward_enemy_unit_loss: f32 = 0.1,
    reward_enemy_building_loss: f32 = 0.5,
    reward_player_unit_loss: f32 = -0.001,
    reward_refinery: f32 = 0.2,
    reward_first_delivery: f32 = 0.1,
    /// CNC26. A Weapons Factory costs 2000 and paid nothing, exactly as the refinery did before it
    /// was rewarded. Measured: where the agent builds a refinery the factory *is* offered (13 and 3
    /// decisions on two seeds) and simply declined, so this is a price problem, not reachability.
    reward_weapons_factory: f32 = 0.0,
    reward_vehicle: f32 = 0.0,
    /// Win grading. Win rate alone could not tell a played-out game from a rush, and grading on
    /// income alone produced a strong economy that never built a tank. A win pays reward_full_win
    /// only when it satisfies every criterion: mined at least economy_win_credits, and fielded at
    /// least full_win_min_tanks tanks and full_win_min_humvees humvees. Any other win pays
    /// reward_partial_win, which keeps the landscape from going flat while the conjunction is
    /// still rarely satisfied. Unqualified losses stay at -1; qualified full-match losses may use
    /// reward_qualified_loss to preserve credit for reaching and using armour.
    reward_full_win: f32 = 1.0,
    reward_partial_win: f32 = 0.5,
    economy_win_credits: u32 = 1000,
    full_win_min_tanks: u32 = 1,
    full_win_min_humvees: u32 = 0,
    /// A tank must have fired. Counting tanks built lets a policy buy one, park it, and collect a
    /// full win, which satisfies the metric without producing the behaviour it exists to select.
    full_win_min_tank_shots: u32 = 1,
    reward_tiberium_income: f32 = 0.01,
    reward_invalid_action: f32 = 0.0,
    /// Immediate penalty for queueing a barracks before committing to a refinery. Constrained
    /// (2300-credit) starts cannot afford to recover from that opening, so they are charged more.
    // Default off. Measured at 5M steps: any nonzero penalty collapses balanced_perf from 0.588 to
    // ~0.05 by teaching barracks avoidance rather than build reordering. PPO normalises advantages,
    // so the penalty's small magnitude does not bound its gradient -- it is immediate and perfectly
    // attributable to one action, while the +1 win is delayed and noisy. Kept sweepable so the
    // search can explore it, but it must be opt-in.
    reward_build_order_violation: f32 = 0.0,
    reward_build_order_violation_constrained: f32 = 0.0,
    /// Paid once when power plant -> refinery -> barracks completes in order. Gives the agent a
    /// target to move toward instead of only a mistake to avoid.
    reward_build_order_sequence: f32 = 0.0,
    /// Paid per kill credited to a player medium tank. Gated on the kill rather than the purchase
    /// because a large bounty for BUILDING a tank rewards rushing one out to be deleted by rocket
    /// infantry. Paid per kill rather than once because latching every armour reward left the
    /// return too sparse to train: measured against the previous build at identical settings, the
    /// all-latched version decayed to building nothing by 3.8M steps (refineries and factories
    /// 0.000, return -0.45) where the dense one held at refineries 0.375, factories 0.250, return
    /// +1.22. A kill cannot be farmed the way an active-count delta could -- it costs a real
    /// engagement -- so density here does not reopen that channel.
    reward_tank_kill: f32 = 0.0,
    /// Paid once per episode when the first player Medium Tank finishes production. The lifetime
    /// built counter is the latch, so losing and rebuilding the tank cannot collect it again.
    reward_first_tank: f32 = 0.0,
    /// Paid once per episode on the first shot actually fired by a player Medium Tank.
    reward_first_tank_shot: f32 = 0.0,
    /// Terminal reward for a real full-match defeat after satisfying the same economy, tank, and
    /// tank-shot conjunction as a full win. Engine failures and intentional soft deaths remain -1.
    reward_qualified_loss: f32 = -1.0,

    pub fn valid(self: RewardConfig) bool {
        return validReward(self.reward_milestone) and
            validReward(self.reward_player_infantry) and
            validReward(self.reward_enemy_unit_loss) and
            validReward(self.reward_enemy_building_loss) and
            validPenalty(self.reward_player_unit_loss) and
            validReward(self.reward_refinery) and
            validReward(self.reward_first_delivery) and
            validReward(self.reward_full_win) and
            validReward(self.reward_partial_win) and
            self.reward_partial_win <= self.reward_full_win and
            validReward(self.reward_weapons_factory) and
            validReward(self.reward_vehicle) and
            validReward(self.reward_tiberium_income) and
            validPenalty(self.reward_invalid_action) and
            validPenalty(self.reward_build_order_violation) and
            validPenalty(self.reward_build_order_violation_constrained) and
            validReward(self.reward_build_order_sequence) and
            validReward(self.reward_tank_kill) and
            validReward(self.reward_first_tank) and
            validReward(self.reward_first_tank_shot) and
            validPenalty(self.reward_qualified_loss);
    }
};

/// True when this decision newly queued a barracks while the player has no refinery committed.
///
/// Reads world state rather than the action encoding, so it is identical under ABI9, ABI13 and
/// ABI14. Only the start_build transition counts: a queue that was already building a barracks is
/// not re-charged on later decisions. A refinery under construction counts as committed, since the
/// player has already paid for it.
pub fn startedBarracksBeforeRefinery(
    world: *const state.World,
    queue_before: state.ProductionQueue,
    queue_after: state.ProductionQueue,
) bool {
    if (!queue_after.active or queue_after.product != .barracks) return false;
    const freshly_started = !queue_before.active or queue_before.product != .barracks;
    if (!freshly_started) return false;
    return activeKindCount(world, .player, .refinery) == 0;
}

/// Advances power plant -> refinery -> barracks progress and reports whether the sequence just
/// completed. `broken` latches when a barracks appears before the refinery, which forfeits the
/// reward permanently: the ordered opening cannot be un-broken later in the episode.
pub fn advanceBuildOrderProgress(
    world: *const state.World,
    progress: *u8,
    broken: *bool,
) bool {
    const has_power = activeKindCount(world, .player, .power_plant) > 0;
    const has_refinery = activeKindCount(world, .player, .refinery) > 0;
    const has_barracks = activeKindCount(world, .player, .barracks) > 0;

    if (has_barracks and !has_refinery) broken.* = true;
    if (broken.*) return false;

    switch (progress.*) {
        0 => if (has_power) {
            progress.* = 1;
        },
        1 => if (has_refinery) {
            progress.* = 2;
        },
        2 => if (has_barracks) {
            progress.* = 3;
            return true;
        },
        else => {},
    }
    return false;
}

/// True when a win satisfies every criterion: a real mining economy and the required armour.
/// Mining requires a refinery, which requires surviving the opening; the vehicle minimums require
/// the Weapons Factory on top of that, which is the whole tech tree.
pub fn isFullWin(
    config: RewardConfig,
    harvested_credits: u32,
    tanks_built: u64,
    humvees_built: u64,
    tank_shots: u32,
) bool {
    return harvested_credits >= config.economy_win_credits and
        tanks_built >= config.full_win_min_tanks and
        humvees_built >= config.full_win_min_humvees and
        tank_shots >= config.full_win_min_tank_shots;
}

/// Constrained starts are charged the heavier rate; every other start uses the ordinary one.
pub fn buildOrderPenalty(config: RewardConfig, starting_credits: i32) f32 {
    return if (starting_credits == rules.starting_credits_constrained)
        config.reward_build_order_violation_constrained
    else
        config.reward_build_order_violation;
}

pub const default_reward_config: RewardConfig = .{};
pub const milestone_reward: f32 = default_reward_config.reward_milestone;
pub const player_infantry_reward: f32 = default_reward_config.reward_player_infantry;
pub const rewarded_player_infantry_cap: u64 = 10;
pub const enemy_unit_loss_reward: f32 = default_reward_config.reward_enemy_unit_loss;
pub const rewarded_enemy_unit_loss_cap: u64 = 10;
pub const enemy_building_loss_reward: f32 = default_reward_config.reward_enemy_building_loss;
pub const rewarded_enemy_building_loss_cap: u64 = 3;
pub const unit_casualty_penalty: f32 = default_reward_config.reward_player_unit_loss;
pub const refinery_reward: f32 = default_reward_config.reward_refinery;
pub const first_delivery_reward: f32 = default_reward_config.reward_first_delivery;
pub const tiberium_income_reward: f32 = default_reward_config.reward_tiberium_income;
pub const rewarded_tiberium_income_cap: u64 = 5_000;
pub const invalid_action_penalty_floor: f32 = -0.5;

fn validReward(value: f32) bool {
    return std.math.isFinite(value) and value >= 0 and value <= 1;
}

fn validPenalty(value: f32) bool {
    return std.math.isFinite(value) and value >= -1 and value <= 0;
}

// Widened from u8 when the armour latches were added: all eight original bits were taken.
const milestone_construction_yard: u16 = 1 << 0;
const milestone_power_plant: u16 = 1 << 1;
const milestone_barracks: u16 = 1 << 2;
const milestone_e1: u16 = 1 << 3;
const milestone_e3: u16 = 1 << 4;
const milestone_refinery: u16 = 1 << 5;
const milestone_harvester: u16 = 1 << 6;
const milestone_first_delivery: u16 = 1 << 7;
const generic_reward_milestones: u16 = milestone_construction_yard |
    milestone_power_plant |
    milestone_barracks |
    milestone_e1 |
    milestone_e3;

comptime {
    std.debug.assert(training_timeout_frames % rules.decision_frames == 0);
}

fn applyCurrentPolicy(world: *state.World, raw: policy.RawAction) bool {
    const decoded = policy.decode(world, raw) orelse return false;
    return input.apply(world, .player, decoded);
}

fn applyAbi9Policy(world: *state.World, raw: policy_abi9.RawAction) bool {
    const decoded = policy_abi9.decode(world, raw) orelse return false;
    return input.apply(world, .player, decoded);
}

fn applyAbi14Policy(world: *state.World, raw: policy_abi14.RawAction) bool {
    return policy_abi14.apply(world, .player, raw);
}

const SoftDeath = enum {
    none,
    building_limit,
    infantry_limit,
};

pub const Stats = extern struct {
    decisions: u64 = 0,
    episodes: u64 = 0,
    wins: u64 = 0,
    losses: u64 = 0,
    draws: u64 = 0,
    invalid_actions: u64 = 0,
    building_limit_losses: u64 = 0,
    infantry_limit_losses: u64 = 0,
    invalid_streak_losses: u64 = 0,
    failures: u64 = 0,
    episode_decisions: u64 = 0,
    close_episodes: u64 = 0,
    close_wins: u64 = 0,
    close_losses: u64 = 0,
    medium_episodes: u64 = 0,
    medium_wins: u64 = 0,
    medium_losses: u64 = 0,
    close_mcv_episodes: u64 = 0,
    close_mcv_wins: u64 = 0,
    close_mcv_losses: u64 = 0,
    close_force_episodes: u64 = 0,
    close_force_wins: u64 = 0,
    close_force_losses: u64 = 0,
    medium_mcv_episodes: u64 = 0,
    medium_mcv_wins: u64 = 0,
    medium_mcv_losses: u64 = 0,
    medium_force_episodes: u64 = 0,
    medium_force_wins: u64 = 0,
    medium_force_losses: u64 = 0,
    completed_invalid_actions: u64 = 0,
    invalid_action_penalty: f64 = 0,
    easy_close_mcv_episodes: u64 = 0,
    easy_close_mcv_wins: u64 = 0,
    easy_close_force_episodes: u64 = 0,
    easy_close_force_wins: u64 = 0,
    easy_medium_mcv_episodes: u64 = 0,
    easy_medium_mcv_wins: u64 = 0,
    easy_medium_force_episodes: u64 = 0,
    easy_medium_force_wins: u64 = 0,
    normal_close_mcv_episodes: u64 = 0,
    normal_close_mcv_wins: u64 = 0,
    normal_close_force_episodes: u64 = 0,
    normal_close_force_wins: u64 = 0,
    normal_medium_mcv_episodes: u64 = 0,
    normal_medium_mcv_wins: u64 = 0,
    normal_medium_force_episodes: u64 = 0,
    normal_medium_force_wins: u64 = 0,
    // Appended after the difficulty split so the 248-byte legacy prefix and the offset of
    // easy_close_mcv_episodes stay exactly where CNC26's asserts pin them.
    constrained_episodes: u64 = 0,
    constrained_wins: u64 = 0,
    build_order_violations: u64 = 0,
    /// Direct instrumentation: how often the policy issues an attack, and how often it lands.
    /// Reasoning about attack reachability produced three wrong answers; this measures it.
    attacks_attempted: u64 = 0,
    attacks_applied: u64 = 0,
    /// Wins satisfying every criterion: income plus the required armour.
    full_wins: u64 = 0,
};

pub const Metrics = extern struct {
    player_e1_built: u64 = 0,
    player_e3_built: u64 = 0,
    opponent_e1_built: u64 = 0,
    opponent_e3_built: u64 = 0,
    player_unit_kills: u64 = 0,
    opponent_unit_kills: u64 = 0,
    player_unit_losses: u64 = 0,
    opponent_unit_losses: u64 = 0,
    player_buildings_lost: u64 = 0,
    opponent_buildings_lost: u64 = 0,
    enemy_attack_orders: u64 = 0,
    accepted_train_actions: u64 = 0,
    rejected_train_actions: u64 = 0,
    construction_yard_milestones: u64 = 0,
    power_plant_milestones: u64 = 0,
    barracks_milestones: u64 = 0,
    e1_milestones: u64 = 0,
    e3_milestones: u64 = 0,
    player_refineries_built: u64 = 0,
    /// CNC26. Needed to tell a rock-paper-scissors game from an infantry spam game; without these
    /// there is no way to check the agent actually reaches armour.
    player_weapons_factories_built: u64 = 0,
    player_medium_tanks_built: u64 = 0,
    player_humvees_built: u64 = 0,
    player_tank_shots: u64 = 0,
    player_tank_kills: u64 = 0,
    opponent_refineries_built: u64 = 0,
    player_harvesters_spawned: u64 = 0,
    opponent_harvesters_spawned: u64 = 0,
    player_tiberium_income: u64 = 0,
    opponent_tiberium_income: u64 = 0,
    refinery_milestones: u64 = 0,
    harvester_milestones: u64 = 0,
    first_delivery_milestones: u64 = 0,
    first_tank_milestones: u64 = 0,
    first_tank_shot_milestones: u64 = 0,
    qualified_losses: u64 = 0,
    player_e1_attack_orders: u64 = 0,
    player_e1_infantry_targets: u64 = 0,
    player_e3_attack_orders: u64 = 0,
    player_e3_vehicle_targets: u64 = 0,
    player_tank_attack_orders: u64 = 0,
    player_tank_e3_targets: u64 = 0,
    player_tank_losses: u64 = 0,
    player_tank_losses_to_e3: u64 = 0,

    fn add(self: *Metrics, other: Metrics) void {
        self.player_e1_built += other.player_e1_built;
        self.player_e3_built += other.player_e3_built;
        self.opponent_e1_built += other.opponent_e1_built;
        self.opponent_e3_built += other.opponent_e3_built;
        self.player_unit_kills += other.player_unit_kills;
        self.opponent_unit_kills += other.opponent_unit_kills;
        self.player_unit_losses += other.player_unit_losses;
        self.opponent_unit_losses += other.opponent_unit_losses;
        self.player_buildings_lost += other.player_buildings_lost;
        self.opponent_buildings_lost += other.opponent_buildings_lost;
        self.enemy_attack_orders += other.enemy_attack_orders;
        self.accepted_train_actions += other.accepted_train_actions;
        self.rejected_train_actions += other.rejected_train_actions;
        self.construction_yard_milestones += other.construction_yard_milestones;
        self.power_plant_milestones += other.power_plant_milestones;
        self.barracks_milestones += other.barracks_milestones;
        self.e1_milestones += other.e1_milestones;
        self.e3_milestones += other.e3_milestones;
        self.player_refineries_built += other.player_refineries_built;
        self.player_weapons_factories_built += other.player_weapons_factories_built;
        self.player_medium_tanks_built += other.player_medium_tanks_built;
        self.player_humvees_built += other.player_humvees_built;
        self.player_tank_shots += other.player_tank_shots;
        self.player_tank_kills += other.player_tank_kills;
        self.opponent_refineries_built += other.opponent_refineries_built;
        self.player_harvesters_spawned += other.player_harvesters_spawned;
        self.opponent_harvesters_spawned += other.opponent_harvesters_spawned;
        self.player_tiberium_income += other.player_tiberium_income;
        self.opponent_tiberium_income += other.opponent_tiberium_income;
        self.refinery_milestones += other.refinery_milestones;
        self.harvester_milestones += other.harvester_milestones;
        self.first_delivery_milestones += other.first_delivery_milestones;
        self.first_tank_milestones += other.first_tank_milestones;
        self.first_tank_shot_milestones += other.first_tank_shot_milestones;
        self.qualified_losses += other.qualified_losses;
        self.player_e1_attack_orders += other.player_e1_attack_orders;
        self.player_e1_infantry_targets += other.player_e1_infantry_targets;
        self.player_e3_attack_orders += other.player_e3_attack_orders;
        self.player_e3_vehicle_targets += other.player_e3_vehicle_targets;
        self.player_tank_attack_orders += other.player_tank_attack_orders;
        self.player_tank_e3_targets += other.player_tank_e3_targets;
        self.player_tank_losses += other.player_tank_losses;
        self.player_tank_losses_to_e3 += other.player_tank_losses_to_e3;
    }
};

const snapshot_magic = [8]u8{ 'T', 'D', 'M', 'B', 'A', 'T', '0', '1' };
// 7/9 append type-pair combat counters to World and Metrics.
const snapshot_version: u32 = 7;
const curriculum_snapshot_version: u32 = 9;

const SnapshotHeader = extern struct {
    magic: [8]u8,
    version: u32,
    count: u32,
    world_size: u32,
    metrics_size: u32,
    stats_size: u32,
    max_decisions: u32,
    difficulty_enabled: u32,
    difficulty_schedule_id: u32,
    difficulty_ramp_decisions: u64,
    ruleset_hash: [32]u8,
    reward_config: RewardConfig,
    stats: Stats,
    metrics: Metrics,
};

/// state.Failure records that a capacity was exceeded but not which one, and the world resets
/// before anything can be inspected. This captures the census at the failing step so a diagnosis
/// is a measurement instead of a guess -- the last two capacity_overflow hunts each cost two wrong
/// hypotheses for want of exactly this.
pub const FailureCensus = struct {
    kind: state.Failure = .none,
    free_unit_slots: u16 = 0,
    buildings: u16 = 0,
    infantry: u16 = 0,
    projectiles: u16 = 0,
    building_fires: u16 = 0,
    frame: u32 = 0,
};

pub const Batch = struct {
    last_failure: FailureCensus = .{},
    worlds: []state.World,
    seeds: []u64,
    episode_ordinals: []u64,
    starting_credits: []i32,
    curriculum_decisions: []u64,
    difficulty_decisions: []u64,
    profiles: []curriculum.Profile,
    episode_steps: []u32,
    invalid_action_streaks: []u16,
    episode_invalid_actions: []u32,
    invalid_action_penalties: []f32,
    /// Charged at most once per episode; repeating it compounds the incentive to avoid barracks.
    build_order_penalised: []bool,
    /// 0 none, 1 power plant, 2 + refinery, 3 + barracks (sequence complete and paid).
    build_order_progress: []u8,
    /// Set when a barracks appears before the refinery, which forfeits the sequence reward.
    build_order_broken: []bool,
    milestones: []u16,
    episode_metrics: []Metrics,
    observed_infantry_deaths: [][rules.max_infantry]bool,
    observed_unit_deaths: [][rules.max_units]bool,
    observed_building_deaths: [][rules.max_buildings]bool,
    max_decisions: u32,
    reward_config: RewardConfig,
    curriculum_schedule: curriculum.Schedule,
    curriculum_stage_decisions: u64,
    starting_force_ramp_decisions: u64,
    difficulty_enabled: bool,
    difficulty_schedule: difficulty.Schedule,
    difficulty_ramp_decisions: u64,
    stats: Stats = .{},
    metrics: Metrics = .{},

    pub fn snapshotSize(self: *const Batch) usize {
        const count = self.worlds.len;
        const curriculum_size = if (self.curriculum_schedule == .full_match)
            0
        else
            @sizeOf(u32) + @sizeOf(u64) + @sizeOf(u64) +
                count * @sizeOf(u64) +
                count * @sizeOf(curriculum.Profile);
        return @sizeOf(SnapshotHeader) +
            count * @sizeOf(state.World) +
            count * @sizeOf(u64) +
            count * @sizeOf(u64) +
            count * @sizeOf(i32) +
            count * @sizeOf(u64) +
            count * @sizeOf(u32) +
            count * @sizeOf(u16) +
            count * @sizeOf(u32) +
            count * @sizeOf(f32) +
            // build_order_penalised, build_order_progress, build_order_broken
            count * @sizeOf(bool) +
            count * @sizeOf(u8) +
            count * @sizeOf(bool) +
            count * @sizeOf(u16) +
            count * @sizeOf(Metrics) +
            count * @sizeOf([rules.max_infantry]bool) +
            count * @sizeOf([rules.max_units]bool) +
            count * @sizeOf([rules.max_buildings]bool) +
            curriculum_size;
    }

    pub fn writeSnapshot(self: *const Batch, output: []u8) !void {
        if (output.len != self.snapshotSize()) return error.SnapshotSizeMismatch;
        var header = std.mem.zeroes(SnapshotHeader);
        header.magic = snapshot_magic;
        header.version = if (self.curriculum_schedule == .full_match)
            snapshot_version
        else
            curriculum_snapshot_version;
        header.count = @intCast(self.worlds.len);
        header.world_size = @sizeOf(state.World);
        header.metrics_size = @sizeOf(Metrics);
        header.stats_size = @sizeOf(Stats);
        header.max_decisions = self.max_decisions;
        header.difficulty_enabled = @intFromBool(self.difficulty_enabled);
        header.difficulty_schedule_id = @intFromEnum(self.difficulty_schedule);
        header.difficulty_ramp_decisions = self.difficulty_ramp_decisions;
        header.ruleset_hash = rules.manifest_sha256;
        header.reward_config = self.reward_config;
        header.stats = self.stats;
        header.metrics = self.metrics;
        var remaining = output;
        try appendSnapshotBytes(&remaining, std.mem.asBytes(&header));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.worlds));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.seeds));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.episode_ordinals));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.starting_credits));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.difficulty_decisions));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.episode_steps));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.invalid_action_streaks));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.episode_invalid_actions));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.invalid_action_penalties));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.build_order_penalised));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.build_order_progress));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.build_order_broken));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.milestones));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.episode_metrics));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.observed_infantry_deaths));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.observed_unit_deaths));
        try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.observed_building_deaths));
        if (self.curriculum_schedule != .full_match) {
            const schedule_id: u32 = @intFromEnum(self.curriculum_schedule);
            try appendSnapshotBytes(&remaining, std.mem.asBytes(&schedule_id));
            try appendSnapshotBytes(&remaining, std.mem.asBytes(&self.curriculum_stage_decisions));
            try appendSnapshotBytes(&remaining, std.mem.asBytes(&self.starting_force_ramp_decisions));
            try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.curriculum_decisions));
            try appendSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.profiles));
        }
        std.debug.assert(remaining.len == 0);
    }

    pub fn readSnapshot(self: *Batch, snapshot: []const u8) !void {
        if (snapshot.len != self.snapshotSize()) return error.SnapshotSizeMismatch;
        var remaining = snapshot;
        var header: SnapshotHeader = undefined;
        try takeSnapshotBytes(&remaining, std.mem.asBytes(&header));
        const expected_version = if (self.curriculum_schedule == .full_match)
            snapshot_version
        else
            curriculum_snapshot_version;
        if (!std.mem.eql(u8, &header.magic, &snapshot_magic) or
            header.version != expected_version or
            header.count != self.worlds.len or
            header.world_size != @sizeOf(state.World) or
            header.metrics_size != @sizeOf(Metrics) or
            header.stats_size != @sizeOf(Stats) or
            header.max_decisions != self.max_decisions or
            header.difficulty_enabled != @intFromBool(self.difficulty_enabled) or
            header.difficulty_schedule_id != @intFromEnum(self.difficulty_schedule) or
            header.difficulty_ramp_decisions != self.difficulty_ramp_decisions or
            !std.mem.eql(u8, &header.ruleset_hash, &rules.manifest_sha256) or
            !std.mem.eql(u8, std.mem.asBytes(&header.reward_config), std.mem.asBytes(&self.reward_config)))
        {
            return error.IncompatibleSnapshot;
        }
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.worlds));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.seeds));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.episode_ordinals));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.starting_credits));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.difficulty_decisions));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.episode_steps));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.invalid_action_streaks));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.episode_invalid_actions));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.invalid_action_penalties));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.build_order_penalised));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.build_order_progress));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.build_order_broken));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.milestones));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.episode_metrics));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.observed_infantry_deaths));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.observed_unit_deaths));
        try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.observed_building_deaths));
        if (self.curriculum_schedule != .full_match) {
            var schedule_id: u32 = 0;
            try takeSnapshotBytes(&remaining, std.mem.asBytes(&schedule_id));
            if (schedule_id != @intFromEnum(self.curriculum_schedule)) return error.IncompatibleSnapshot;
            var stage_decisions: u64 = 0;
            try takeSnapshotBytes(&remaining, std.mem.asBytes(&stage_decisions));
            if (stage_decisions != self.curriculum_stage_decisions) return error.IncompatibleSnapshot;
            var starting_force_ramp_decisions: u64 = 0;
            try takeSnapshotBytes(&remaining, std.mem.asBytes(&starting_force_ramp_decisions));
            if (starting_force_ramp_decisions != self.starting_force_ramp_decisions) {
                return error.IncompatibleSnapshot;
            }
            try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.curriculum_decisions));
            try takeSnapshotBytes(&remaining, std.mem.sliceAsBytes(self.profiles));
        }
        self.stats = header.stats;
        self.metrics = header.metrics;
        std.debug.assert(remaining.len == 0);
    }

    pub fn init(allocator: std.mem.Allocator, count: usize, max_decisions: u32) !Batch {
        return initWithRewardConfig(allocator, count, max_decisions, default_reward_config);
    }

    pub fn initWithRewardConfig(
        allocator: std.mem.Allocator,
        count: usize,
        max_decisions: u32,
        reward_config: RewardConfig,
    ) !Batch {
        return initWithCurriculum(
            allocator,
            count,
            max_decisions,
            reward_config,
            .full_match,
            0,
            0,
        );
    }

    pub fn initWithCurriculum(
        allocator: std.mem.Allocator,
        count: usize,
        max_decisions: u32,
        reward_config: RewardConfig,
        curriculum_schedule: curriculum.Schedule,
        curriculum_stage_decisions: u64,
        starting_force_ramp_decisions: u64,
    ) !Batch {
        return initInternal(
            allocator,
            count,
            max_decisions,
            reward_config,
            curriculum_schedule,
            curriculum_stage_decisions,
            starting_force_ramp_decisions,
            false,
            .fixed_easy,
            0,
        );
    }

    pub fn initWithConfigs(
        allocator: std.mem.Allocator,
        count: usize,
        max_decisions: u32,
        reward_config: RewardConfig,
        curriculum_schedule: curriculum.Schedule,
        curriculum_stage_decisions: u64,
        starting_force_ramp_decisions: u64,
        difficulty_schedule: difficulty.Schedule,
        difficulty_ramp_decisions: u64,
    ) !Batch {
        return initInternal(
            allocator,
            count,
            max_decisions,
            reward_config,
            curriculum_schedule,
            curriculum_stage_decisions,
            starting_force_ramp_decisions,
            true,
            difficulty_schedule,
            difficulty_ramp_decisions,
        );
    }

    fn initInternal(
        allocator: std.mem.Allocator,
        count: usize,
        max_decisions: u32,
        reward_config: RewardConfig,
        curriculum_schedule: curriculum.Schedule,
        curriculum_stage_decisions: u64,
        starting_force_ramp_decisions: u64,
        difficulty_enabled: bool,
        difficulty_schedule: difficulty.Schedule,
        difficulty_ramp_decisions: u64,
    ) !Batch {
        if (count == 0) return error.EmptyBatch;
        if (!reward_config.valid()) return error.InvalidRewardConfig;
        if (!curriculum.configValid(
            curriculum_schedule,
            curriculum_stage_decisions,
            starting_force_ramp_decisions,
        )) {
            return error.InvalidCurriculumConfig;
        }
        if (difficulty_enabled and
            !difficulty.configValid(difficulty_schedule, difficulty_ramp_decisions))
        {
            return error.InvalidDifficultyConfig;
        }
        const worlds = try allocator.alloc(state.World, count);
        errdefer allocator.free(worlds);
        const seeds = try allocator.alloc(u64, count);
        errdefer allocator.free(seeds);
        const episode_ordinals = try allocator.alloc(u64, count);
        errdefer allocator.free(episode_ordinals);
        const starting_credits = try allocator.alloc(i32, count);
        errdefer allocator.free(starting_credits);
        const curriculum_decisions = try allocator.alloc(u64, count);
        errdefer allocator.free(curriculum_decisions);
        const difficulty_decisions = try allocator.alloc(u64, count);
        errdefer allocator.free(difficulty_decisions);
        const profiles = try allocator.alloc(curriculum.Profile, count);
        errdefer allocator.free(profiles);
        const episode_steps = try allocator.alloc(u32, count);
        errdefer allocator.free(episode_steps);
        const invalid_action_streaks = try allocator.alloc(u16, count);
        errdefer allocator.free(invalid_action_streaks);
        const episode_invalid_actions = try allocator.alloc(u32, count);
        errdefer allocator.free(episode_invalid_actions);
        const invalid_action_penalties = try allocator.alloc(f32, count);
        errdefer allocator.free(invalid_action_penalties);
        const build_order_penalised = try allocator.alloc(bool, count);
        errdefer allocator.free(build_order_penalised);
        const build_order_progress = try allocator.alloc(u8, count);
        errdefer allocator.free(build_order_progress);
        const build_order_broken = try allocator.alloc(bool, count);
        errdefer allocator.free(build_order_broken);
        const milestones = try allocator.alloc(u16, count);
        errdefer allocator.free(milestones);
        const episode_metrics = try allocator.alloc(Metrics, count);
        errdefer allocator.free(episode_metrics);
        const observed_infantry_deaths = try allocator.alloc([rules.max_infantry]bool, count);
        errdefer allocator.free(observed_infantry_deaths);
        const observed_unit_deaths = try allocator.alloc([rules.max_units]bool, count);
        errdefer allocator.free(observed_unit_deaths);
        const observed_building_deaths = try allocator.alloc([rules.max_buildings]bool, count);
        errdefer allocator.free(observed_building_deaths);
        @memset(worlds, .{});
        @memset(seeds, 0);
        @memset(episode_ordinals, 0);
        @memset(starting_credits, 0);
        @memset(curriculum_decisions, 0);
        @memset(difficulty_decisions, 0);
        @memset(profiles, .full_match);
        @memset(episode_steps, 0);
        @memset(invalid_action_streaks, 0);
        @memset(episode_invalid_actions, 0);
        @memset(invalid_action_penalties, 0);
        @memset(build_order_penalised, false);
        @memset(build_order_progress, 0);
        @memset(build_order_broken, false);
        @memset(milestones, 0);
        @memset(episode_metrics, .{});
        @memset(observed_infantry_deaths, [_]bool{false} ** rules.max_infantry);
        @memset(observed_unit_deaths, [_]bool{false} ** rules.max_units);
        @memset(observed_building_deaths, [_]bool{false} ** rules.max_buildings);
        return .{
            .worlds = worlds,
            .seeds = seeds,
            .episode_ordinals = episode_ordinals,
            .starting_credits = starting_credits,
            .curriculum_decisions = curriculum_decisions,
            .difficulty_decisions = difficulty_decisions,
            .profiles = profiles,
            .episode_steps = episode_steps,
            .invalid_action_streaks = invalid_action_streaks,
            .episode_invalid_actions = episode_invalid_actions,
            .invalid_action_penalties = invalid_action_penalties,
            .build_order_penalised = build_order_penalised,
            .build_order_progress = build_order_progress,
            .build_order_broken = build_order_broken,
            .milestones = milestones,
            .episode_metrics = episode_metrics,
            .observed_infantry_deaths = observed_infantry_deaths,
            .observed_unit_deaths = observed_unit_deaths,
            .observed_building_deaths = observed_building_deaths,
            .max_decisions = max_decisions,
            .reward_config = reward_config,
            .curriculum_schedule = curriculum_schedule,
            .curriculum_stage_decisions = curriculum_stage_decisions,
            .starting_force_ramp_decisions = starting_force_ramp_decisions,
            .difficulty_enabled = difficulty_enabled,
            .difficulty_schedule = difficulty_schedule,
            .difficulty_ramp_decisions = difficulty_ramp_decisions,
        };
    }

    pub fn deinit(self: *Batch, allocator: std.mem.Allocator) void {
        allocator.free(self.observed_building_deaths);
        allocator.free(self.observed_unit_deaths);
        allocator.free(self.observed_infantry_deaths);
        allocator.free(self.episode_metrics);
        allocator.free(self.milestones);
        allocator.free(self.invalid_action_streaks);
        allocator.free(self.episode_invalid_actions);
        allocator.free(self.invalid_action_penalties);
        allocator.free(self.build_order_penalised);
        allocator.free(self.build_order_progress);
        allocator.free(self.build_order_broken);
        allocator.free(self.episode_steps);
        allocator.free(self.profiles);
        allocator.free(self.difficulty_decisions);
        allocator.free(self.curriculum_decisions);
        allocator.free(self.starting_credits);
        allocator.free(self.episode_ordinals);
        allocator.free(self.seeds);
        allocator.free(self.worlds);
        self.* = undefined;
    }

    pub fn reset(self: *Batch, seeds: []const u64) !void {
        if (seeds.len != self.worlds.len) return error.CountMismatch;
        for (seeds) |seed| {
            const probe = state.World.reset(seed);
            if (probe.failure != .none) return error.UnsupportedSeed;
        }
        @memset(self.episode_ordinals, 0);
        @memset(self.curriculum_decisions, 0);
        @memset(self.difficulty_decisions, 0);
        for (seeds, 0..) |seed, index| self.resetOne(index, seed);
        self.stats = .{};
        self.metrics = .{};
    }

    pub fn observe(self: *const Batch, observations: []u8, masks: []u8) void {
        self.observeWithMask(policy.action_mask_size, policy.actionMask, observations, masks);
    }

    pub fn observeAbi9(self: *const Batch, observations: []u8, masks: []u8) void {
        self.observeWithMask(policy_abi9.action_mask_size, policy_abi9.actionMask, observations, masks);
    }

    pub fn observeAbi14(self: *const Batch, observations: []u8, masks: []u8) void {
        self.observeWithMask(policy_abi14.action_mask_size, policy_abi14.actionMask, observations, masks);
    }

    fn observeWithMask(
        self: *const Batch,
        comptime action_mask_size: usize,
        comptime actionMask: fn (*const state.World, *[action_mask_size]u8) void,
        observations: []u8,
        masks: []u8,
    ) void {
        std.debug.assert(observations.len == self.worlds.len * policy.observation_size);
        std.debug.assert(masks.len == self.worlds.len * action_mask_size);
        for (self.worlds, 0..) |*world, index| {
            const observation: *[policy.observation_size]u8 =
                observations[index * policy.observation_size ..][0..policy.observation_size];
            const mask: *[action_mask_size]u8 =
                masks[index * action_mask_size ..][0..action_mask_size];
            policy.observe(world, observation);
            actionMask(world, mask);
        }
    }

    pub fn step(
        self: *Batch,
        actions: []const policy.RawAction,
        observations: []u8,
        masks: []u8,
        rewards: []f32,
        terminals: []u8,
    ) void {
        self.stepWithPolicy(
            policy.RawAction,
            policy.action_mask_size,
            applyCurrentPolicy,
            policy.actionMask,
            actions,
            observations,
            masks,
            rewards,
            terminals,
        );
    }

    pub fn stepAbi9(
        self: *Batch,
        actions: []const policy_abi9.RawAction,
        observations: []u8,
        masks: []u8,
        rewards: []f32,
        terminals: []u8,
    ) void {
        self.stepWithPolicy(
            policy_abi9.RawAction,
            policy_abi9.action_mask_size,
            applyAbi9Policy,
            policy_abi9.actionMask,
            actions,
            observations,
            masks,
            rewards,
            terminals,
        );
    }

    pub fn stepAbi14(
        self: *Batch,
        actions: []const policy_abi14.RawAction,
        observations: []u8,
        masks: []u8,
        rewards: []f32,
        terminals: []u8,
    ) void {
        self.stepWithPolicy(
            policy_abi14.RawAction,
            policy_abi14.action_mask_size,
            applyAbi14Policy,
            policy_abi14.actionMask,
            actions,
            observations,
            masks,
            rewards,
            terminals,
        );
    }

    fn stepWithPolicy(
        self: *Batch,
        comptime RawAction: type,
        comptime action_mask_size: usize,
        comptime applyRaw: fn (*state.World, RawAction) bool,
        comptime actionMask: fn (*const state.World, *[action_mask_size]u8) void,
        actions: []const RawAction,
        observations: []u8,
        masks: []u8,
        rewards: []f32,
        terminals: []u8,
    ) void {
        const count = self.worlds.len;
        std.debug.assert(actions.len == count);
        std.debug.assert(observations.len == count * policy.observation_size);
        std.debug.assert(masks.len == count * action_mask_size);
        std.debug.assert(rewards.len == count);
        std.debug.assert(terminals.len == count);

        for (0..count) |index| {
            rewards[index] = 0;
            terminals[index] = 0;
            var invalid_penalty_delta: f32 = 0;
            const infantry_count_before = self.worlds[index].infantry_count;
            const player_refineries_before = activeKindCount(&self.worlds[index], .player, .refinery);
            var factory_gain: u64 = 0;
            var vehicle_gain: u64 = 0;
            const player_factories_before = activeKindCount(&self.worlds[index], .player, .weapons_factory);
            const player_tanks_before = activeKindCount(&self.worlds[index], .player, .medium_tank);
            const tanks_built_before = self.episode_metrics[index].player_medium_tanks_built;
            const player_humvees_before = activeKindCount(&self.worlds[index], .player, .humvee);
            const opponent_refineries_before = activeKindCount(&self.worlds[index], .opponent, .refinery);
            const player_harvesters_before = activeKindCount(&self.worlds[index], .player, .harvester);
            const opponent_harvesters_before = activeKindCount(&self.worlds[index], .opponent, .harvester);
            const player_income_before =
                self.worlds[index].players[@intFromEnum(state.Owner.player)].harvested_credits;
            const opponent_income_before =
                self.worlds[index].players[@intFromEnum(state.Owner.opponent)].harvested_credits;
            var kills_before = [_]u16{0} ** rules.max_infantry;
            for (self.worlds[index].infantry[0..infantry_count_before], 0..) |infantry, infantry_index| {
                kills_before[infantry_index] = infantry.kills;
            }
            const structure_queue_before = self.worlds[index].queues[@intFromEnum(state.Owner.player)][@intFromEnum(state.QueueKind.structure)];
            const accepted = applyRaw(&self.worlds[index], actions[index]);
            if (actions[index].command == @intFromEnum(action.Command.attack)) {
                self.stats.attacks_attempted += 1;
                if (accepted) self.stats.attacks_applied += 1;
            }
            // Build-order shaping: charged the moment the wrong structure is queued, so the penalty
            // lands on the decision that caused it rather than at episode end.
            if (accepted) {
                const structure_queue_after = self.worlds[index].queues[@intFromEnum(state.Owner.player)][@intFromEnum(state.QueueKind.structure)];
                if (!self.build_order_penalised[index] and
                    startedBarracksBeforeRefinery(&self.worlds[index], structure_queue_before, structure_queue_after))
                {
                    rewards[index] += buildOrderPenalty(self.reward_config, self.starting_credits[index]);
                    self.stats.build_order_violations += 1;
                    self.build_order_penalised[index] = true;
                }
            }
            if (actions[index].command == @intFromEnum(action.Command.train)) {
                if (accepted) {
                    self.episode_metrics[index].accepted_train_actions += 1;
                } else {
                    self.episode_metrics[index].rejected_train_actions += 1;
                }
            }
            if (accepted) {
                self.invalid_action_streaks[index] = 0;
            } else {
                self.stats.invalid_actions += 1;
                self.episode_invalid_actions[index] += 1;
                self.invalid_action_streaks[index] +|= 1;
                const prior_penalty = self.invalid_action_penalties[index];
                const next_penalty = @max(
                    invalid_action_penalty_floor,
                    prior_penalty + self.reward_config.reward_invalid_action,
                );
                invalid_penalty_delta = next_penalty - prior_penalty;
                rewards[index] += invalid_penalty_delta;
                self.invalid_action_penalties[index] = next_penalty;
            }

            const easy_ai_commands = step_sim.advanceWithEasyAI(&self.worlds[index]);
            self.episode_steps[index] += 1;
            self.stats.decisions += 1;
            if (self.curriculum_schedule != .full_match) self.curriculum_decisions[index] +%= 1;
            if (self.difficulty_enabled) self.difficulty_decisions[index] +%= 1;
            recordEnemyAttackOrders(easy_ai_commands, &self.episode_metrics[index]);
            // The world counter is authoritative and resets per episode. Its zero-to-nonzero
            // transition is the one-shot latch; later shots and replacement tanks cannot repay it.
            const tank_shots_before = self.episode_metrics[index].player_tank_shots;
            self.episode_metrics[index].player_tank_shots = self.worlds[index].metrics_tank_shots;
            if (tank_shots_before == 0 and
                self.episode_metrics[index].player_tank_shots != 0)
            {
                rewards[index] += self.reward_config.reward_first_tank_shot;
                self.episode_metrics[index].first_tank_shot_milestones += 1;
            }
            const tank_kills_before = self.episode_metrics[index].player_tank_kills;
            self.episode_metrics[index].player_tank_kills = self.worlds[index].metrics_tank_kills;
            self.episode_metrics[index].player_e1_attack_orders =
                self.worlds[index].metrics_player_e1_attack_orders;
            self.episode_metrics[index].player_e1_infantry_targets =
                self.worlds[index].metrics_player_e1_infantry_targets;
            self.episode_metrics[index].player_e3_attack_orders =
                self.worlds[index].metrics_player_e3_attack_orders;
            self.episode_metrics[index].player_e3_vehicle_targets =
                self.worlds[index].metrics_player_e3_vehicle_targets;
            self.episode_metrics[index].player_tank_attack_orders =
                self.worlds[index].metrics_player_tank_attack_orders;
            self.episode_metrics[index].player_tank_e3_targets =
                self.worlds[index].metrics_player_tank_e3_targets;
            self.episode_metrics[index].player_tank_losses =
                self.worlds[index].metrics_player_tank_losses;
            self.episode_metrics[index].player_tank_losses_to_e3 =
                self.worlds[index].metrics_player_tank_losses_to_e3;
            rewards[index] += @as(f32, @floatFromInt(
                self.episode_metrics[index].player_tank_kills -| tank_kills_before,
            )) * self.reward_config.reward_tank_kill;
            recordEconomyEvents(
                &self.worlds[index],
                player_refineries_before,
                player_factories_before,
                player_tanks_before,
                player_humvees_before,
                opponent_refineries_before,
                player_harvesters_before,
                opponent_harvesters_before,
                player_income_before,
                opponent_income_before,
                &self.episode_metrics[index],
                &factory_gain,
                &vehicle_gain,
            );
            if (tanks_built_before == 0 and
                self.episode_metrics[index].player_medium_tanks_built != 0)
            {
                rewards[index] += self.reward_config.reward_first_tank;
                self.episode_metrics[index].first_tank_milestones += 1;
            }
            // Paid per factory and per tank, not once. Latching both was tried and measured: at
            // identical settings across three seeds it drove weapons factories built to exactly
            // 0.000 and dragged refineries from 0.375 to ~0.11, because a single payment at the
            // end of a long tech path is too distal to pull the policy up it. The farming channel
            // that motivated the latch is real, but it is priced by the sweep -- CNC30 measured
            // the optimum for this dense reward in its second quartile -- rather than removed.
            rewards[index] += @as(f32, @floatFromInt(factory_gain)) * self.reward_config.reward_weapons_factory;
            rewards[index] += @as(f32, @floatFromInt(vehicle_gain)) * self.reward_config.reward_vehicle;
            if (advanceBuildOrderProgress(
                &self.worlds[index],
                &self.build_order_progress[index],
                &self.build_order_broken[index],
            )) {
                rewards[index] += self.reward_config.reward_build_order_sequence;
            }

            const player_income_after =
                self.worlds[index].players[@intFromEnum(state.Owner.player)].harvested_credits;
            rewards[index] += cappedCountReward(
                player_income_before,
                player_income_after,
                rewarded_tiberium_income_cap,
                self.reward_config.reward_tiberium_income / 100.0,
            );

            const player_infantry_built_before = self.episode_metrics[index].player_e1_built +
                self.episode_metrics[index].player_e3_built;
            recordNewInfantryBuilds(
                &self.worlds[index],
                infantry_count_before,
                &self.episode_metrics[index],
            );
            const player_infantry_built_after = self.episode_metrics[index].player_e1_built +
                self.episode_metrics[index].player_e3_built;
            rewards[index] += cappedCountReward(
                player_infantry_built_before,
                player_infantry_built_after,
                rewarded_player_infantry_cap,
                self.reward_config.reward_player_infantry,
            );
            recordNewUnitKills(&self.worlds[index], &kills_before, &self.episode_metrics[index]);
            const opponent_unit_losses_before = self.episode_metrics[index].opponent_unit_losses;
            const newly_lost_infantry = recordNewInfantryDeaths(
                &self.worlds[index],
                &self.observed_infantry_deaths[index],
            );
            self.episode_metrics[index].player_unit_losses += newly_lost_infantry.player;
            self.episode_metrics[index].opponent_unit_losses += newly_lost_infantry.opponent;
            const newly_lost_units = recordNewUnitDeaths(
                &self.worlds[index],
                &self.observed_unit_deaths[index],
            );
            self.episode_metrics[index].player_unit_losses += newly_lost_units.player;
            self.episode_metrics[index].opponent_unit_losses += newly_lost_units.opponent;
            reclaimDestroyedUnits(
                &self.worlds[index],
                &self.observed_unit_deaths[index],
            );
            rewards[index] += cappedCountReward(
                opponent_unit_losses_before,
                self.episode_metrics[index].opponent_unit_losses,
                rewarded_enemy_unit_loss_cap,
                self.reward_config.reward_enemy_unit_loss,
            );
            const player_unit_losses = newly_lost_infantry.player + newly_lost_units.player;
            rewards[index] += @as(f32, @floatFromInt(player_unit_losses)) *
                self.reward_config.reward_player_unit_loss;
            const opponent_buildings_lost_before = self.episode_metrics[index].opponent_buildings_lost;
            const newly_lost_buildings = recordNewBuildingDeaths(
                &self.worlds[index],
                &self.observed_building_deaths[index],
            );
            self.episode_metrics[index].player_buildings_lost += newly_lost_buildings.player;
            self.episode_metrics[index].opponent_buildings_lost += newly_lost_buildings.opponent;
            rewards[index] += cappedCountReward(
                opponent_buildings_lost_before,
                self.episode_metrics[index].opponent_buildings_lost,
                rewarded_enemy_building_loss_cap,
                self.reward_config.reward_enemy_building_loss,
            );
            compactInactiveInfantry(
                &self.worlds[index],
                &self.observed_infantry_deaths[index],
            );

            const completed = completedMilestones(&self.worlds[index]);
            const newly_completed = completed & ~self.milestones[index];
            self.milestones[index] |= completed;
            recordMilestones(&self.episode_metrics[index], newly_completed);
            rewards[index] += @as(f32, @floatFromInt(@popCount(newly_completed & generic_reward_milestones))) *
                self.reward_config.reward_milestone;
            if (newly_completed & milestone_refinery != 0) {
                rewards[index] += self.reward_config.reward_refinery;
            }
            if (newly_completed & milestone_first_delivery != 0) {
                rewards[index] += self.reward_config.reward_first_delivery;
            }

            const world = &self.worlds[index];
            const failed = world.failure != .none;
            // Captured here rather than at the stats increment below: the world resets in between,
            // and a census read after the reset describes a fresh world, not the failing one.
            if (failed) self.last_failure = .{
                .kind = world.failure,
                .free_unit_slots = @intCast(world.freeUnitSlots()),
                .buildings = @intCast(world.building_count),
                .infantry = @intCast(world.infantry_count),
                .projectiles = @intCast(world.projectile_count),
                .building_fires = @intCast(world.building_fire_count),
                .frame = @intCast(world.frame),
            };
            const soft_death = classifySoftDeath(world);
            const timed_out = self.max_decisions != 0 and self.episode_steps[index] >= self.max_decisions;
            const terminal = failed or soft_death != .none or step_sim.isTerminal(world) or timed_out;
            if (terminal) {
                terminals[index] = 1;
                // The terminal +/-1 or draw replaces all shaping on this step.
                self.invalid_action_penalties[index] -= invalid_penalty_delta;
                self.recordTerminal(index, failed, soft_death, timed_out, &rewards[index]);
                self.episode_ordinals[index] +%= 1;
                self.resetOne(index, self.seeds[index]);
            }
        }
        self.observeWithMask(action_mask_size, actionMask, observations, masks);
    }

    fn recordTerminal(
        self: *Batch,
        index: usize,
        failed: bool,
        soft_death: SoftDeath,
        timed_out: bool,
        reward: *f32,
    ) void {
        reward.* = 0;
        self.stats.completed_invalid_actions += self.episode_invalid_actions[index];
        self.stats.invalid_action_penalty += self.invalid_action_penalties[index];
        self.metrics.add(self.episode_metrics[index]);
        self.stats.episodes += 1;
        self.stats.episode_decisions += self.episode_steps[index];
        const is_full_match = self.profiles[index] == .full_match;
        if (is_full_match) {
            recordSpawnEpisode(&self.stats, self.worlds[index].spawn_bucket);
            recordStartCellEpisode(
                &self.stats,
                self.worlds[index].spawn_bucket,
                self.worlds[index].starting_force,
            );
            if (self.difficulty_enabled) {
                recordDifficultyEpisode(
                    &self.stats,
                    difficulty.requested(&self.worlds[index]),
                    self.worlds[index].spawn_bucket,
                    self.worlds[index].starting_force,
                );
            }
        }
        if (failed) {
            self.stats.failures += 1;
            return;
        }

        // Constrained (2300-credit) starts are the bucket the build-order shaping targets, so their
        // win rate is tracked on its own instead of being blended into balanced_perf.
        const constrained_start = is_full_match and
            self.starting_credits[index] == rules.starting_credits_constrained;
        if (constrained_start) self.stats.constrained_episodes += 1;

        const player_defeated = self.worlds[index].players[@intFromEnum(state.Owner.player)].defeated;
        const opponent_defeated = self.worlds[index].players[@intFromEnum(state.Owner.opponent)].defeated;
        if (player_defeated and !opponent_defeated) {
            const mined = self.worlds[index].players[@intFromEnum(state.Owner.player)].harvested_credits;
            const qualified = is_full_match and isFullWin(
                self.reward_config,
                mined,
                self.episode_metrics[index].player_medium_tanks_built,
                self.episode_metrics[index].player_humvees_built,
                self.worlds[index].metrics_tank_shots,
            );
            reward.* = if (qualified) self.reward_config.reward_qualified_loss else -1;
            if (qualified) {
                self.metrics.qualified_losses += 1;
            }
            self.stats.losses += 1;
            if (is_full_match) {
                recordSpawnLoss(&self.stats, self.worlds[index].spawn_bucket);
                recordStartCellLoss(
                    &self.stats,
                    self.worlds[index].spawn_bucket,
                    self.worlds[index].starting_force,
                );
            }
        } else if (opponent_defeated and !player_defeated) {
            const mined = self.worlds[index].players[@intFromEnum(state.Owner.player)].harvested_credits;
            const full = isFullWin(
                self.reward_config,
                mined,
                self.episode_metrics[index].player_medium_tanks_built,
                self.episode_metrics[index].player_humvees_built,
                self.worlds[index].metrics_tank_shots,
            );
            reward.* = if (full)
                self.reward_config.reward_full_win
            else
                self.reward_config.reward_partial_win;
            self.stats.wins += 1;
            // Only full matches, matching how close/medium wins are counted, or the rate divides
            // two different populations and can exceed the plain win rate.
            if (full and is_full_match) self.stats.full_wins += 1;
            if (constrained_start) self.stats.constrained_wins += 1;
            if (is_full_match) {
                recordSpawnWin(&self.stats, self.worlds[index].spawn_bucket);
                recordStartCellWin(
                    &self.stats,
                    self.worlds[index].spawn_bucket,
                    self.worlds[index].starting_force,
                );
                if (self.difficulty_enabled) {
                    recordDifficultyWin(
                        &self.stats,
                        difficulty.requested(&self.worlds[index]),
                        self.worlds[index].spawn_bucket,
                        self.worlds[index].starting_force,
                    );
                }
            }
        } else if (player_defeated and opponent_defeated) {
            self.stats.draws += 1;
        } else if (soft_death != .none) {
            reward.* = -1;
            self.stats.losses += 1;
            if (is_full_match) {
                recordSpawnLoss(&self.stats, self.worlds[index].spawn_bucket);
                recordStartCellLoss(
                    &self.stats,
                    self.worlds[index].spawn_bucket,
                    self.worlds[index].starting_force,
                );
            }
            switch (soft_death) {
                .building_limit => self.stats.building_limit_losses += 1,
                .infantry_limit => self.stats.infantry_limit_losses += 1,
                .none => unreachable,
            }
        } else if (timed_out) {
            self.stats.draws += 1;
        }
    }

    fn resetOne(self: *Batch, index: usize, seed: u64) void {
        self.seeds[index] = seed;
        const profile = curriculum.profileForProgress(
            self.curriculum_schedule,
            seed,
            index,
            self.episode_ordinals[index],
            self.curriculum_decisions[index],
            self.curriculum_stage_decisions,
        );
        self.profiles[index] = profile;
        self.episode_steps[index] = 0;
        self.invalid_action_streaks[index] = 0;
        self.episode_invalid_actions[index] = 0;
        self.invalid_action_penalties[index] = 0;
        self.build_order_penalised[index] = false;
        self.build_order_progress[index] = 0;
        self.build_order_broken[index] = false;
        self.milestones[index] = 0;
        self.episode_metrics[index] = .{};
        @memset(&self.observed_infantry_deaths[index], false);
        @memset(&self.observed_unit_deaths[index], false);
        @memset(&self.observed_building_deaths[index], false);
        self.worlds[index] = curriculum.resetForScheduledEpisode(
            seed,
            profile,
            self.curriculum_schedule,
            index,
            self.episode_ordinals[index],
            self.curriculum_decisions[index],
            self.starting_force_ramp_decisions,
        );
        if (self.difficulty_enabled) {
            difficulty.enable(&self.worlds[index], difficulty.forProgress(
                self.difficulty_schedule,
                seed,
                index,
                self.episode_ordinals[index],
                self.difficulty_decisions[index],
                self.difficulty_ramp_decisions,
            ));
        }
        self.starting_credits[index] =
            self.worlds[index].players[@intFromEnum(state.Owner.player)].credits;
        if (profile != .full_match) {
            self.milestones[index] = completedMilestones(&self.worlds[index]);
        } else if (self.worlds[index].starting_force == .reduced_unit_count_6) {
            self.milestones[index] = milestone_e1 | milestone_e3;
        }
    }
};

fn appendSnapshotBytes(remaining: *[]u8, source: []const u8) !void {
    if (remaining.*.len < source.len) return error.SnapshotSizeMismatch;
    @memcpy(remaining.*[0..source.len], source);
    remaining.* = remaining.*[source.len..];
}

fn takeSnapshotBytes(remaining: *[]const u8, destination: []u8) !void {
    if (remaining.*.len < destination.len) return error.SnapshotSizeMismatch;
    @memcpy(destination, remaining.*[0..destination.len]);
    remaining.* = remaining.*[destination.len..];
}

fn recordSpawnEpisode(stats: *Stats, bucket: state.SpawnBucket) void {
    switch (bucket) {
        .close => stats.close_episodes += 1,
        .medium => stats.medium_episodes += 1,
    }
}

fn recordSpawnWin(stats: *Stats, bucket: state.SpawnBucket) void {
    switch (bucket) {
        .close => stats.close_wins += 1,
        .medium => stats.medium_wins += 1,
    }
}

fn recordSpawnLoss(stats: *Stats, bucket: state.SpawnBucket) void {
    switch (bucket) {
        .close => stats.close_losses += 1,
        .medium => stats.medium_losses += 1,
    }
}

fn recordStartCellEpisode(
    stats: *Stats,
    bucket: state.SpawnBucket,
    starting_force: state.StartingForce,
) void {
    switch (bucket) {
        .close => switch (starting_force) {
            .mcv_only => stats.close_mcv_episodes += 1,
            .reduced_unit_count_6 => stats.close_force_episodes += 1,
        },
        .medium => switch (starting_force) {
            .mcv_only => stats.medium_mcv_episodes += 1,
            .reduced_unit_count_6 => stats.medium_force_episodes += 1,
        },
    }
}

fn recordStartCellWin(
    stats: *Stats,
    bucket: state.SpawnBucket,
    starting_force: state.StartingForce,
) void {
    switch (bucket) {
        .close => switch (starting_force) {
            .mcv_only => stats.close_mcv_wins += 1,
            .reduced_unit_count_6 => stats.close_force_wins += 1,
        },
        .medium => switch (starting_force) {
            .mcv_only => stats.medium_mcv_wins += 1,
            .reduced_unit_count_6 => stats.medium_force_wins += 1,
        },
    }
}

fn recordStartCellLoss(
    stats: *Stats,
    bucket: state.SpawnBucket,
    starting_force: state.StartingForce,
) void {
    switch (bucket) {
        .close => switch (starting_force) {
            .mcv_only => stats.close_mcv_losses += 1,
            .reduced_unit_count_6 => stats.close_force_losses += 1,
        },
        .medium => switch (starting_force) {
            .mcv_only => stats.medium_mcv_losses += 1,
            .reduced_unit_count_6 => stats.medium_force_losses += 1,
        },
    }
}

fn recordDifficultyEpisode(
    stats: *Stats,
    selected: difficulty.Requested,
    bucket: state.SpawnBucket,
    starting_force: state.StartingForce,
) void {
    const counter = difficultyCellCounter(stats, selected, bucket, starting_force, false) orelse return;
    counter.* += 1;
}

fn recordDifficultyWin(
    stats: *Stats,
    selected: difficulty.Requested,
    bucket: state.SpawnBucket,
    starting_force: state.StartingForce,
) void {
    const counter = difficultyCellCounter(stats, selected, bucket, starting_force, true) orelse return;
    counter.* += 1;
}

fn difficultyCellCounter(
    stats: *Stats,
    selected: difficulty.Requested,
    bucket: state.SpawnBucket,
    starting_force: state.StartingForce,
    win: bool,
) ?*u64 {
    return switch (selected) {
        .easy => switch (bucket) {
            .close => switch (starting_force) {
                .mcv_only => if (win) &stats.easy_close_mcv_wins else &stats.easy_close_mcv_episodes,
                .reduced_unit_count_6 => if (win) &stats.easy_close_force_wins else &stats.easy_close_force_episodes,
            },
            .medium => switch (starting_force) {
                .mcv_only => if (win) &stats.easy_medium_mcv_wins else &stats.easy_medium_mcv_episodes,
                .reduced_unit_count_6 => if (win) &stats.easy_medium_force_wins else &stats.easy_medium_force_episodes,
            },
        },
        .normal => switch (bucket) {
            .close => switch (starting_force) {
                .mcv_only => if (win) &stats.normal_close_mcv_wins else &stats.normal_close_mcv_episodes,
                .reduced_unit_count_6 => if (win) &stats.normal_close_force_wins else &stats.normal_close_force_episodes,
            },
            .medium => switch (starting_force) {
                .mcv_only => if (win) &stats.normal_medium_mcv_wins else &stats.normal_medium_mcv_episodes,
                .reduced_unit_count_6 => if (win) &stats.normal_medium_force_wins else &stats.normal_medium_force_episodes,
            },
        },
        .hard => null,
    };
}

const InfantryLosses = struct {
    player: u64 = 0,
    opponent: u64 = 0,
};

const BuildingLosses = struct {
    player: u64 = 0,
    opponent: u64 = 0,
};

fn recordNewInfantryBuilds(world: *const state.World, prior_count: u8, metrics: *Metrics) void {
    for (world.infantry[prior_count..world.infantry_count]) |infantry| {
        const counter = switch (infantry.owner) {
            .player => switch (infantry.kind) {
                .e1 => &metrics.player_e1_built,
                .e3 => &metrics.player_e3_built,
                else => continue,
            },
            .opponent => switch (infantry.kind) {
                .e1 => &metrics.opponent_e1_built,
                .e3 => &metrics.opponent_e3_built,
                else => continue,
            },
            .none => continue,
        };
        counter.* += 1;
    }
}

fn recordNewUnitKills(
    world: *const state.World,
    kills_before: *const [rules.max_infantry]u16,
    metrics: *Metrics,
) void {
    for (world.infantry[0..world.infantry_count], 0..) |infantry, index| {
        if (infantry.kind != .e1 and infantry.kind != .e3) continue;
        const new_kills: u64 = infantry.kills -% kills_before[index];
        switch (infantry.owner) {
            .player => metrics.player_unit_kills += new_kills,
            .opponent => metrics.opponent_unit_kills += new_kills,
            .none => {},
        }
    }
}

fn recordNewInfantryDeaths(
    world: *const state.World,
    observed_deaths: *[rules.max_infantry]bool,
) InfantryLosses {
    var losses: InfantryLosses = .{};
    for (world.infantry[0..world.infantry_count], 0..) |infantry, index| {
        if (observed_deaths[index] or infantry.health != 0) continue;
        if (infantry.kind != .e1 and infantry.kind != .e3) continue;
        observed_deaths[index] = true;
        switch (infantry.owner) {
            .player => losses.player += 1,
            .opponent => losses.opponent += 1,
            .none => {},
        }
    }
    return losses;
}

fn recordNewBuildingDeaths(
    world: *const state.World,
    observed_deaths: *[rules.max_buildings]bool,
) BuildingLosses {
    var losses: BuildingLosses = .{};
    for (world.buildings[0..world.building_count], 0..) |building, index| {
        if (observed_deaths[index] or building.health != 0) continue;
        observed_deaths[index] = true;
        switch (building.owner) {
            .player => losses.player += 1,
            .opponent => losses.opponent += 1,
            .none => {},
        }
    }
    return losses;
}

fn recordNewUnitDeaths(
    world: *const state.World,
    observed_deaths: *[rules.max_units]bool,
) InfantryLosses {
    var losses: InfantryLosses = .{};
    for (world.units, 0..) |unit, index| {
        if (observed_deaths[index] or unit.kind == .none or unit.health != 0) continue;
        observed_deaths[index] = true;
        switch (unit.owner) {
            .player => losses.player += 1,
            .opponent => losses.opponent += 1,
            .none => {},
        }
    }
    return losses;
}

fn recordEnemyAttackOrders(commands: step_sim.CommandBuffer, metrics: *Metrics) void {
    for (commands.slice()) |timed| {
        if (timed.action.command == .hunt or timed.action.command == .attack) {
            metrics.enemy_attack_orders += 1;
        }
    }
}

fn recordMilestones(metrics: *Metrics, newly_completed: u16) void {
    if (newly_completed & milestone_construction_yard != 0) metrics.construction_yard_milestones += 1;
    if (newly_completed & milestone_power_plant != 0) metrics.power_plant_milestones += 1;
    if (newly_completed & milestone_barracks != 0) metrics.barracks_milestones += 1;
    if (newly_completed & milestone_e1 != 0) metrics.e1_milestones += 1;
    if (newly_completed & milestone_e3 != 0) metrics.e3_milestones += 1;
    if (newly_completed & milestone_refinery != 0) metrics.refinery_milestones += 1;
    if (newly_completed & milestone_harvester != 0) metrics.harvester_milestones += 1;
    if (newly_completed & milestone_first_delivery != 0) metrics.first_delivery_milestones += 1;
}

/// Test-only alias. The tank-only rule for vehicle_gain lives here, and a delta of active
/// counts cannot be exercised by placing units between steps.
pub const recordEconomyEventsForTest = recordEconomyEvents;

fn recordEconomyEvents(
    world: *const state.World,
    player_refineries_before: u64,
    player_factories_before: u64,
    player_tanks_before: u64,
    player_humvees_before: u64,
    opponent_refineries_before: u64,
    player_harvesters_before: u64,
    opponent_harvesters_before: u64,
    player_income_before: u32,
    opponent_income_before: u32,
    metrics: *Metrics,
    factory_gain: *u64,
    vehicle_gain: *u64,
) void {
    const player_refineries_after = activeKindCount(world, .player, .refinery);
    const player_factories_after = activeKindCount(world, .player, .weapons_factory);
    const player_tanks_after = activeKindCount(world, .player, .medium_tank);
    const player_humvees_after = activeKindCount(world, .player, .humvee);
    const opponent_refineries_after = activeKindCount(world, .opponent, .refinery);
    const player_harvesters_after = activeKindCount(world, .player, .harvester);
    const opponent_harvesters_after = activeKindCount(world, .opponent, .harvester);
    metrics.player_refineries_built += player_refineries_after -| player_refineries_before;
    metrics.player_weapons_factories_built += player_factories_after -| player_factories_before;
    factory_gain.* = player_factories_after -| player_factories_before;
    // Tanks only. A humvee costs 400 against the medium tank's 800, so counting both let the
    // cheap unit collect a bounty meant to pay for reaching armour, against a full_perf criterion
    // that specifically requires a tank.
    vehicle_gain.* = player_tanks_after -| player_tanks_before;
    metrics.player_medium_tanks_built += player_tanks_after -| player_tanks_before;
    metrics.player_humvees_built += player_humvees_after -| player_humvees_before;
    metrics.opponent_refineries_built += opponent_refineries_after -| opponent_refineries_before;
    metrics.player_harvesters_spawned += player_harvesters_after -| player_harvesters_before;
    metrics.opponent_harvesters_spawned += opponent_harvesters_after -| opponent_harvesters_before;
    metrics.player_tiberium_income +=
        world.players[@intFromEnum(state.Owner.player)].harvested_credits -| player_income_before;
    metrics.opponent_tiberium_income +=
        world.players[@intFromEnum(state.Owner.opponent)].harvested_credits -| opponent_income_before;
}

fn classifySoftDeath(world: *const state.World) SoftDeath {
    if (activeBuildingCount(world, .player) > player_building_limit) return .building_limit;
    if (activeInfantryCount(world, .player) > player_infantry_limit) return .infantry_limit;
    return .none;
}

fn cappedCountReward(before: u64, after: u64, cap: u64, reward_per_item: f32) f32 {
    const rewarded_before = @min(before, cap);
    const rewarded_after = @min(after, cap);
    return @as(f32, @floatFromInt(rewarded_after - rewarded_before)) * reward_per_item;
}

fn activeBuildingCount(world: *const state.World, owner: state.Owner) usize {
    var count: usize = 0;
    for (world.buildings) |building| {
        if (building.active and building.health != 0 and building.owner == owner) count += 1;
    }
    return count;
}

pub fn compactInactiveInfantry(
    world: *state.World,
    observed_deaths: *[rules.max_infantry]bool,
) void {
    var has_inactive = false;
    for (world.infantry[0..world.infantry_count]) |infantry| {
        if (!infantry.active) {
            has_inactive = true;
            break;
        }
    }
    if (!has_inactive) return;

    var remap = [_]u16{std.math.maxInt(u16)} ** rules.max_infantry;
    var write_index: usize = 0;
    for (0..world.infantry_count) |read_index| {
        if (!world.infantry[read_index].active) continue;
        remap[read_index] = @intCast(write_index);
        if (write_index != read_index) {
            world.infantry[write_index] = world.infantry[read_index];
            observed_deaths[write_index] = observed_deaths[read_index];
        }
        write_index += 1;
    }
    if (write_index == world.infantry_count) return;

    for (write_index..world.infantry_count) |index| {
        world.infantry[index] = .{};
        observed_deaths[index] = false;
    }
    world.infantry_count = @intCast(write_index);

    for (world.infantry[0..write_index]) |*infantry| {
        remapInfantryRef(&infantry.target, &remap);
    }
    for (&world.projectiles) |*projectile| {
        if (!projectile.active) continue;
        remapInfantryRef(&projectile.source, &remap);
        remapInfantryRef(&projectile.target, &remap);
    }
}

pub fn reclaimDestroyedUnits(
    world: *state.World,
    observed_deaths: *[rules.max_units]bool,
) void {
    for (&world.units, 0..) |*unit, index| {
        if (index < rules.player_count or unit.kind == .none or unit.active or unit.health != 0) continue;
        unit.* = .{};
        observed_deaths[index] = false;
    }
}

fn remapInfantryRef(reference: *state.EntityRef, remap: *const [rules.max_infantry]u16) void {
    if (reference.kind != .e1 and reference.kind != .e3) return;
    const old_index: usize = reference.index;
    if (old_index >= remap.len or remap[old_index] == std.math.maxInt(u16)) {
        reference.* = .{};
        return;
    }
    reference.index = remap[old_index];
}

fn activeInfantryCount(world: *const state.World, owner: state.Owner) usize {
    var count: usize = 0;
    for (world.infantry) |infantry| {
        if (infantry.active and infantry.health != 0 and infantry.owner == owner) count += 1;
    }
    return count;
}

fn completedMilestones(world: *const state.World) u16 {
    var completed: u16 = 0;
    for (world.units) |unit| {
        if (unit.active and unit.health != 0 and unit.owner == .player and unit.kind == .mcv and unit.deploying) {
            completed |= milestone_construction_yard;
        }
    }
    for (world.buildings) |building| {
        if (!building.active or building.health == 0 or building.owner != .player) continue;
        completed |= switch (building.kind) {
            .construction_yard => milestone_construction_yard,
            .power_plant => milestone_power_plant,
            .barracks => milestone_barracks,
            .refinery => milestone_refinery,
            else => 0,
        };
    }
    for (world.units) |unit| {
        if (unit.active and unit.health != 0 and unit.owner == .player and unit.kind == .harvester) {
            completed |= milestone_harvester;
        }
    }
    for (world.infantry) |infantry| {
        if (!infantry.active or infantry.health == 0 or infantry.owner != .player) continue;
        completed |= switch (infantry.kind) {
            .e1 => milestone_e1,
            .e3 => milestone_e3,
            else => 0,
        };
    }
    if (world.players[@intFromEnum(state.Owner.player)].harvested_credits != 0) {
        completed |= milestone_first_delivery;
    }
    return completed;
}

fn activeKindCount(world: *const state.World, owner: state.Owner, kind: rules.ObjectType) u64 {
    var count: u64 = 0;
    const category = (rules.object(kind) orelse return 0).category;
    switch (category) {
        .unit => for (world.units) |unit| {
            if (unit.active and unit.health != 0 and unit.owner == owner and unit.kind == kind) count += 1;
        },
        .building => for (world.buildings) |building| {
            if (building.active and building.health != 0 and building.owner == owner and building.kind == kind) count += 1;
        },
        else => {},
    }
    return count;
}
