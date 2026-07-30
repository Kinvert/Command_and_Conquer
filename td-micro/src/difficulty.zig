const rules = @import("rules.zig");
const state = @import("state.zig");

const fixed_one: i64 = 1 << 16;
const fixed_half: i64 = fixed_one / 2;

pub const Requested = enum(u8) {
    easy = 0,
    normal = 1,
    hard = 2,
};

pub const Schedule = enum(u32) {
    fixed_easy = 0,
    easy_to_normal = 1,
    fixed_normal = 2,
    fixed_hard = 3,
};

pub fn scheduleFromInt(value: u32) ?Schedule {
    return switch (value) {
        0 => .fixed_easy,
        1 => .easy_to_normal,
        2 => .fixed_normal,
        3 => .fixed_hard,
        else => null,
    };
}

pub fn configValid(schedule: Schedule, ramp_decisions: u64) bool {
    return switch (schedule) {
        .easy_to_normal => ramp_decisions != 0,
        .fixed_easy, .fixed_normal, .fixed_hard => ramp_decisions == 0,
    };
}

// TD stores the skirmish opponent at the inverse internal handicap index.
pub fn internalHandicap(selected: Requested) u8 {
    return 2 - @intFromEnum(selected);
}

pub fn fromInternalHandicap(internal: u8) ?Requested {
    if (internal > 2) return null;
    return @enumFromInt(2 - internal);
}

pub fn handicap(internal: u8) *const rules.DifficultyHandicap {
    return &rules.difficulty_handicaps[internal];
}

pub fn enable(world: *state.World, selected: Requested) void {
    world.easy_ai.difficulty_active = true;
    world.easy_ai.difficulty = internalHandicap(selected);
}

pub fn isEnabled(world: *const state.World) bool {
    return world.easy_ai.difficulty_active;
}

pub fn requested(world: *const state.World) Requested {
    if (!world.easy_ai.difficulty_active) return .normal;
    return fromInternalHandicap(world.easy_ai.difficulty) orelse .normal;
}

fn forOwner(world: *const state.World, owner: state.Owner) *const rules.DifficultyHandicap {
    if (!world.easy_ai.difficulty_active or owner != .opponent) {
        return handicap(internalHandicap(.normal));
    }
    return handicap(world.easy_ai.difficulty);
}

pub fn scale(value: i32, bias_raw: u32) i32 {
    const product = @as(i64, value) * @as(i64, bias_raw);
    const rounded = if (product >= 0)
        product + fixed_half
    else
        product - fixed_half;
    return @intCast(@divTrunc(rounded, fixed_one));
}

pub fn firepower(world: *const state.World, owner: state.Owner, base: i16) i16 {
    return @intCast(scale(base, forOwner(world, owner).firepower_bias));
}

pub fn groundSpeed(world: *const state.World, owner: state.Owner, base: u8) u8 {
    return @intCast(@min(255, scale(base, forOwner(world, owner).groundspeed_bias)));
}

pub fn rotationRate(world: *const state.World, owner: state.Owner, base: u8) u8 {
    const product = @as(u64, base) * @as(u64, forOwner(world, owner).groundspeed_bias);
    const truncated = product / @as(u64, fixed_one);
    return @intCast(@max(1, @min(127, truncated)));
}

pub fn rof(world: *const state.World, owner: state.Owner, base: u8) u8 {
    return @intCast(@min(255, scale(base, forOwner(world, owner).rof_bias)));
}

pub fn armorDamage(world: *const state.World, owner: state.Owner, base: i16) i16 {
    if (base <= 0) return base;
    return @intCast(scale(base, forOwner(world, owner).armor_bias));
}

pub fn cost(world: *const state.World, owner: state.Owner, base: i32) i32 {
    return scale(base, forOwner(world, owner).cost_bias);
}

pub fn normalPercent(curriculum_decisions: u64, ramp_decisions: u64) u8 {
    if (ramp_decisions == 0) return 90;
    const elapsed = @min(curriculum_decisions, ramp_decisions);
    const delta = @as(u128, elapsed) * 80 / @as(u128, ramp_decisions);
    return 10 + @as(u8, @intCast(delta));
}

pub fn forProgress(
    schedule: Schedule,
    setup_seed: u64,
    lane_index: usize,
    episode_ordinal: u64,
    curriculum_decisions: u64,
    ramp_decisions: u64,
) Requested {
    return switch (schedule) {
        .fixed_easy => .easy,
        .fixed_normal => .normal,
        .fixed_hard => .hard,
        .easy_to_normal => blk: {
            const percent = normalPercent(curriculum_decisions, ramp_decisions);
            const slot = ((episode_ordinal *% 71) +%
                (@as(u64, @intCast(lane_index % 100)) *% 43) +%
                ((setup_seed % 100) *% 19) +% 29) % 100;
            break :blk if (slot < percent) .normal else .easy;
        },
    };
}
