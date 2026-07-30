const economy = @import("economy.zig");
const map = @import("map.zig");
const movement = @import("movement.zig");
const placement = @import("placement.zig");
const random = @import("random.zig");
const rules = @import("rules.zig");
const state = @import("state.zig");

const reverse_force_start_percent: u8 = 25;
const reverse_force_final_percent: u8 = 75;

pub const Schedule = enum(u32) {
    full_match = 0,
    reverse_curriculum = 1,
    h0_test = 0xffff_ffff,
};

pub const Horizon = enum(u8) {
    h0_finish = 0,
    h1_assault = 1,
    h2_mobilize = 2,
    h3_economy = 3,
    h4_opening = 4,
    h5_full_match = 5,
};

pub const Profile = enum(u8) {
    full_match = 0,
    h0_finish_e1 = 1,
    h0_finish_e3 = 2,
    h0_finish_mixed = 3,
    h1_assault_e1 = 4,
    h1_assault_e3 = 5,
    h1_assault_mixed = 6,
    h2_mobilize = 7,
    h3_economy = 8,
    h4_opening = 9,
    /// CNC26 armour drill. Appended so the existing profile encodings are untouched.
    h2_armour = 10,
    /// Counter drills are appended so existing profile IDs remain replay-compatible.
    h1_e3_vs_tank = 11,
    h1_tank_vs_e3 = 12,
};

pub fn scheduleFromInt(value: u32) ?Schedule {
    return switch (value) {
        0 => .full_match,
        1 => .reverse_curriculum,
        else => null,
    };
}

pub fn configValid(
    schedule: Schedule,
    stage_decisions: u64,
    starting_force_ramp_decisions: u64,
) bool {
    return switch (schedule) {
        .full_match => true,
        .reverse_curriculum, .h0_test => stage_decisions != 0 and
            starting_force_ramp_decisions != 0,
    };
}

pub fn horizon(profile: Profile) Horizon {
    return switch (profile) {
        .h0_finish_e1, .h0_finish_e3, .h0_finish_mixed => .h0_finish,
        .h1_assault_e1,
        .h1_assault_e3,
        .h1_assault_mixed,
        .h1_e3_vs_tank,
        .h1_tank_vs_e3,
        => .h1_assault,
        // Same depth as h2_mobilize -- the tech is standing and the fight is next -- so it shares
        // that horizon rather than widening the taxonomy.
        .h2_mobilize, .h2_armour => .h2_mobilize,
        .h3_economy => .h3_economy,
        .h4_opening => .h4_opening,
        .full_match => .h5_full_match,
    };
}

pub fn profileForProgress(
    schedule: Schedule,
    setup_seed: u64,
    lane_index: usize,
    episode_ordinal: u64,
    curriculum_decisions: u64,
    stage_decisions: u64,
) Profile {
    return switch (schedule) {
        .full_match => .full_match,
        .reverse_curriculum => reverseProfile(
            setup_seed,
            lane_index,
            episode_ordinal,
            curriculum_decisions,
            stage_decisions,
        ),
        .h0_test => forceProfile(.h0_finish, setup_seed, lane_index, episode_ordinal),
    };
}

fn reverseProfile(
    setup_seed: u64,
    lane_index: usize,
    episode_ordinal: u64,
    curriculum_decisions: u64,
    stage_decisions: u64,
) Profile {
    if (stage_decisions == 0) return .full_match;
    const phase = @min(@as(u64, 5), curriculum_decisions / stage_decisions);
    const slot = ((@as(u64, @intCast(lane_index % 100)) * 37) + (episode_ordinal *% 53)) % 100;
    return switch (phase) {
        0 => if (slot < 3)
            forceProfile(.h0_finish, setup_seed, lane_index, episode_ordinal)
        else if (slot < 80)
            forceProfile(.h1_assault, setup_seed, lane_index, episode_ordinal)
        else
            .full_match,
        1 => if (slot < 20)
            forceProfile(.h1_assault, setup_seed, lane_index, episode_ordinal)
        else if (slot < 80)
            .h2_mobilize
        else
            .full_match,
        // CNC26: h2_armour is threaded through the middle and late stages so the agent keeps
        // meeting vehicles. Seeing them once is not enough to learn they are worth the detour.
        2 => if (slot < 20) .h2_mobilize else if (slot < 60) .h2_armour else if (slot < 80) .h3_economy else .full_match,
        3 => if (slot < 20) .h2_armour else if (slot < 60) .h3_economy else if (slot < 80) .h4_opening else .full_match,
        4 => if (slot < 20) .h4_opening else if (slot < 40) .h2_armour else .full_match,
        else => .full_match,
    };
}

fn forceProfile(
    target_horizon: Horizon,
    setup_seed: u64,
    lane_index: usize,
    episode_ordinal: u64,
) Profile {
    const value = sampleValue(setup_seed, lane_index, episode_ordinal);
    return switch (target_horizon) {
        .h0_finish => switch (value % 3) {
            0 => .h0_finish_e1,
            1 => .h0_finish_e3,
            2 => .h0_finish_mixed,
            else => unreachable,
        },
        .h1_assault => switch (value % 5) {
            0 => .h1_assault_e1,
            1 => .h1_assault_e3,
            2 => .h1_assault_mixed,
            3 => .h1_e3_vs_tank,
            4 => .h1_tank_vs_e3,
            else => unreachable,
        },
        else => .full_match,
    };
}

fn sampleValue(setup_seed: u64, lane_index: usize, episode_ordinal: u64) u64 {
    var value = setup_seed ^
        (@as(u64, @intCast(lane_index)) *% 0x9e3779b97f4a7c15) ^
        (episode_ordinal *% 0xbf58476d1ce4e5b9);
    value = (value ^ (value >> 30)) *% 0xbf58476d1ce4e5b9;
    value = (value ^ (value >> 27)) *% 0x94d049bb133111eb;
    value ^= value >> 31;
    return value;
}

pub fn startingCredits(setup_seed: u64, lane_index: usize, episode_ordinal: u64) i32 {
    const slot = ((@as(u64, @intCast(lane_index % 100)) * 37) +% (episode_ordinal *% 53)) % 100;
    if (slot < rules.starting_credits_constrained_percent) {
        return rules.starting_credits_constrained;
    }
    const value_count: u64 = @intCast(
        @divExact(
            rules.starting_credits_random_max - rules.starting_credits_random_min,
            rules.starting_credits_step,
        ) + 1,
    );
    const offset: i32 = @intCast(sampleValue(setup_seed, lane_index, episode_ordinal) % value_count);
    return rules.starting_credits_random_min + offset * rules.starting_credits_step;
}

pub fn startingForce(lane_index: usize, episode_ordinal: u64) state.StartingForce {
    return startingForceAtPercent(lane_index, episode_ordinal, rules.starting_force_percent);
}

pub fn startingForceForProgress(
    schedule: Schedule,
    lane_index: usize,
    episode_ordinal: u64,
    curriculum_decisions: u64,
    starting_force_ramp_decisions: u64,
) state.StartingForce {
    const percent = if (schedule == .reverse_curriculum and
        starting_force_ramp_decisions != 0)
        reverseStartingForcePercent(
            curriculum_decisions,
            starting_force_ramp_decisions,
        )
    else
        rules.starting_force_percent;
    return startingForceAtPercent(lane_index, episode_ordinal, percent);
}

fn reverseStartingForcePercent(
    curriculum_decisions: u64,
    starting_force_ramp_decisions: u64,
) u8 {
    const ramp_decisions = @as(u128, starting_force_ramp_decisions);
    const elapsed = @min(@as(u128, curriculum_decisions), ramp_decisions);
    const percent_range = reverse_force_final_percent - reverse_force_start_percent;
    const percent_delta = elapsed * @as(u128, percent_range) / ramp_decisions;
    return reverse_force_start_percent + @as(u8, @intCast(percent_delta));
}

fn startingForceAtPercent(
    lane_index: usize,
    episode_ordinal: u64,
    force_percent: u8,
) state.StartingForce {
    const slot =
        ((@as(u64, @intCast(lane_index % 100)) * 61) +% (episode_ordinal *% 47) +% 17) % 100;
    return if (slot < force_percent)
        .reduced_unit_count_6
    else
        .mcv_only;
}

pub fn reset(setup_seed: u64, profile: Profile) state.World {
    var world = state.World.reset(setup_seed);
    if (world.failure != .none or profile == .full_match) return world;

    const player_start = world.units[0].position;
    const opponent_start = world.units[1].position;
    switch (horizon(profile)) {
        .h0_finish => setupCombat(&world, profile, player_start, opponent_start, false),
        .h1_assault => setupCombat(&world, profile, player_start, opponent_start, true),
        // h2_armour shares this horizon, so the profile decides which base is built.
        .h2_mobilize => if (profile == .h2_armour)
            setupArmourBase(&world, player_start)
        else
            setupBase(&world, player_start, true),
        .h3_economy => setupBase(&world, player_start, false),
        .h4_opening => setupOpening(&world, player_start),
        .h5_full_match => unreachable,
    }
    return world;
}

pub fn resetForEpisode(
    setup_seed: u64,
    profile: Profile,
    lane_index: usize,
    episode_ordinal: u64,
) state.World {
    return resetForEpisodeWithForce(
        setup_seed,
        profile,
        lane_index,
        episode_ordinal,
        startingForce(lane_index, episode_ordinal),
    );
}

pub fn resetForScheduledEpisode(
    setup_seed: u64,
    profile: Profile,
    schedule: Schedule,
    lane_index: usize,
    episode_ordinal: u64,
    curriculum_decisions: u64,
    starting_force_ramp_decisions: u64,
) state.World {
    return resetForEpisodeWithForce(
        setup_seed,
        profile,
        lane_index,
        episode_ordinal,
        startingForceForProgress(
            schedule,
            lane_index,
            episode_ordinal,
            curriculum_decisions,
            starting_force_ramp_decisions,
        ),
    );
}

fn resetForEpisodeWithForce(
    setup_seed: u64,
    profile: Profile,
    lane_index: usize,
    episode_ordinal: u64,
    starting_force: state.StartingForce,
) state.World {
    var world = reset(setup_seed, profile);
    if (world.failure != .none or profile != .full_match) return world;
    const credits = startingCredits(setup_seed, lane_index, episode_ordinal);
    world.players[@intFromEnum(state.Owner.player)].credits = credits;
    world.players[@intFromEnum(state.Owner.opponent)].credits = credits;
    world.starting_force = starting_force;
    if (world.starting_force == .reduced_unit_count_6) {
        applyStartingForce(&world);
    }
    return world;
}

pub fn applyStartingForce(world: *state.World) void {
    const gameplay_rng_state = world.rng_state;
    defer world.rng_state = gameplay_rng_state;
    world.starting_force = .reduced_unit_count_6;
    const player_start = world.units[0].position;
    const opponent_start = world.units[1].position;
    if (!addInfantryRing(
        world,
        .player,
        .e1,
        rules.starting_force_e1_count,
        player_start,
        opponent_start,
        3,
        6,
    ) or !addInfantryRing(
        world,
        .player,
        .e3,
        rules.starting_force_e3_count,
        player_start,
        opponent_start,
        3,
        6,
    ) or !addInfantryRing(
        world,
        .opponent,
        .e1,
        rules.starting_force_e1_count,
        opponent_start,
        player_start,
        3,
        6,
    ) or !addInfantryRing(
        world,
        .opponent,
        .e3,
        rules.starting_force_e3_count,
        opponent_start,
        player_start,
        3,
        6,
    )) {
        return;
    }
}

fn setupCombat(
    world: *state.World,
    profile: Profile,
    player_start: state.Position,
    opponent_start: state.Position,
    assault: bool,
) void {
    @memset(&world.units, .{});
    world.players[@intFromEnum(state.Owner.player)].credits = 0;
    world.players[@intFromEnum(state.Owner.opponent)].credits = 0;
    world.players[@intFromEnum(state.Owner.player)].tiberium = 0;
    world.players[@intFromEnum(state.Owner.opponent)].tiberium = 0;
    world.easy_ai.max_infantry = 0;
    world.easy_ai.build_infantry = .none;

    const player_yard = deployedYardPosition(world, player_start) orelse return;
    const opponent_yard = deployedYardPosition(world, opponent_start) orelse return;
    if (!addOperationalBuilding(world, .player, .construction_yard, player_yard) or
        !addOperationalBuilding(world, .opponent, .construction_yard, opponent_yard))
    {
        return;
    }

    const min_radius: i16 = if (assault) 11 else 3;
    const max_radius: i16 = if (assault) 22 else 10;
    if (profile == .h1_e3_vs_tank) {
        if (!addInfantryRing(
            world,
            .player,
            .e3,
            12,
            opponent_start,
            opponent_start,
            min_radius,
            max_radius,
        ) or !addUnitRing(
            world,
            .opponent,
            .medium_tank,
            2,
            opponent_start,
            player_start,
            3,
            7,
        )) return;
        return;
    }
    if (profile == .h1_tank_vs_e3) {
        if (!addUnitRing(
            world,
            .player,
            .medium_tank,
            2,
            opponent_start,
            opponent_start,
            min_radius,
            max_radius,
        ) or !addInfantryRing(
            world,
            .opponent,
            .e3,
            8,
            opponent_start,
            player_start,
            3,
            7,
        )) return;
        return;
    }

    const counts = packageCounts(profile);
    if (!addInfantryRing(
        world,
        .player,
        .e1,
        counts.e1,
        opponent_start,
        opponent_start,
        min_radius,
        max_radius,
    ) or !addInfantryRing(
        world,
        .player,
        .e3,
        counts.e3,
        opponent_start,
        opponent_start,
        min_radius,
        max_radius,
    )) {
        return;
    }
    if (assault and (!addInfantryRing(
        world,
        .opponent,
        .e1,
        2,
        opponent_start,
        player_start,
        3,
        7,
    ) or !addInfantryRing(
        world,
        .opponent,
        .e3,
        2,
        opponent_start,
        player_start,
        3,
        7,
    ))) return;
}

fn setupOpening(world: *state.World, player_start: state.Position) void {
    removeOwnedUnits(world, .player);
    const yard = deployedYardPosition(world, player_start) orelse return;
    _ = addOperationalBuilding(world, .player, .construction_yard, yard);
}

/// Armour drill: the whole tech tree is already standing, so a Medium Tank or Humvee is one
/// decision away. 116 sweep trials searching reward_weapons_factory over 0 to 0.8 never once built
/// a factory, so the agent cannot be paid into armour -- it has to be shown one first.
fn setupArmourBase(world: *state.World, player_start: state.Position) void {
    setupOpening(world, player_start);
    if (world.failure != .none) return;
    // The Weapons Factory is 3x3 and loses the space race if it goes last, so it is placed first,
    // while the area around the yard is still clear. No barracks: an armour drill should push
    // vehicles rather than infantry.
    if (!addOperationalBuildingAtLegalPosition(world, .player, .weapons_factory) or
        !addOperationalBuildingAtLegalPosition(world, .player, .power_plant) or
        !addOperationalBuildingAtLegalPosition(world, .player, .refinery))
    {
        return;
    }
    // A medium tank is 800 and a humvee 400; this affords several without waiting on harvesting.
    world.players[@intFromEnum(state.Owner.player)].credits = 3_000;
}

fn setupBase(world: *state.World, player_start: state.Position, mobilize: bool) void {
    setupOpening(world, player_start);
    if (world.failure != .none) return;
    if (!addOperationalBuildingAtLegalPosition(world, .player, .power_plant) or
        !addOperationalBuildingAtLegalPosition(world, .player, .refinery))
    {
        return;
    }
    if (mobilize and !addOperationalBuildingAtLegalPosition(world, .player, .barracks)) return;
    world.players[@intFromEnum(state.Owner.player)].credits = if (mobilize) 1_200 else 300;
}

const PackageCounts = struct {
    e1: u8,
    e3: u8,
};

fn packageCounts(profile: Profile) PackageCounts {
    return switch (profile) {
        .h0_finish_e1, .h1_assault_e1 => .{ .e1 = 16, .e3 = 0 },
        .h0_finish_e3, .h1_assault_e3 => .{ .e1 = 0, .e3 = 16 },
        .h0_finish_mixed, .h1_assault_mixed => .{ .e1 = 8, .e3 = 8 },
        .h1_e3_vs_tank, .h1_tank_vs_e3 => .{ .e1 = 0, .e3 = 0 },
        .h2_mobilize, .h2_armour, .h3_economy, .h4_opening, .full_match => .{ .e1 = 0, .e3 = 0 },
    };
}

fn addOperationalBuilding(
    world: *state.World,
    owner: state.Owner,
    kind: rules.ObjectType,
    position: state.Position,
) bool {
    _ = random.next(&world.rng_state);
    const index: usize = world.building_count;
    if (!world.addBuilding(owner, kind, position)) return false;
    const building = &world.buildings[index];
    building.construction_frames = 0;
    building.operational = true;
    const object_rule = rules.object(kind) orelse {
        world.failure = .unsupported_content;
        return false;
    };
    world.players[@intFromEnum(owner)].drain += object_rule.drain;
    if (kind == .refinery) {
        building.grand_opened = true;
        world.players[@intFromEnum(owner)].capacity += rules.refinery_capacity;
        economy.grandOpenRefinery(world, index);
    }
    return true;
}

fn addOperationalBuildingAtLegalPosition(
    world: *state.World,
    owner: state.Owner,
    kind: rules.ObjectType,
) bool {
    for (0..world.map_height) |y| {
        for (0..world.map_width) |x| {
            const position: state.Position = .{ .x = @intCast(x), .y = @intCast(y) };
            if (!placement.isLegal(world, owner, kind, position)) continue;
            return addOperationalBuilding(world, owner, kind, position);
        }
    }
    world.failure = .unsupported_content;
    return false;
}

fn removeOwnedUnits(world: *state.World, owner: state.Owner) void {
    for (&world.units) |*unit| {
        if (unit.active and unit.owner == owner) unit.* = .{};
    }
}

fn addInfantryRing(
    world: *state.World,
    owner: state.Owner,
    kind: rules.ObjectType,
    count: u8,
    center: state.Position,
    facing_target: state.Position,
    min_radius: i16,
    max_radius: i16,
) bool {
    var added: u8 = 0;
    var radius = min_radius;
    while (radius <= max_radius and added < count) : (radius += 1) {
        var y_offset: i16 = -radius;
        while (y_offset <= radius and added < count) : (y_offset += 1) {
            var x_offset: i16 = -radius;
            while (x_offset <= radius and added < count) : (x_offset += 1) {
                if (@max(abs(x_offset), abs(y_offset)) != radius) continue;
                const x = @as(i16, center.x) + x_offset;
                const y = @as(i16, center.y) + y_offset;
                if (x < 0 or y < 0 or x >= world.map_width or y >= world.map_height) continue;
                const position: state.Position = .{ .x = @intCast(x), .y = @intCast(y) };
                if (!map.footPassable(position) or occupied(world, position)) continue;
                if (!addInfantry(world, owner, kind, position, facing_target)) return false;
                added += 1;
            }
        }
    }
    if (added == count) return true;
    world.failure = .capacity_overflow;
    return false;
}

fn addInfantry(
    world: *state.World,
    owner: state.Owner,
    kind: rules.ObjectType,
    position: state.Position,
    target: state.Position,
) bool {
    if (world.infantry_count >= rules.max_infantry) {
        world.failure = .capacity_overflow;
        return false;
    }
    const object_rule = rules.object(kind) orelse {
        world.failure = .unsupported_content;
        return false;
    };
    if (object_rule.category != .infantry) {
        world.failure = .unsupported_content;
        return false;
    }
    const index: usize = world.infantry_count;
    const coord_x: i16 = @as(i16, position.x) * 256 + 128;
    const coord_y: i16 = @as(i16, position.y) * 256 + 128;
    world.infantry[index] = .{
        .active = true,
        .kind = kind,
        .owner = owner,
        .position = position,
        .health = object_rule.strength,
        .coord_x = coord_x,
        .coord_y = coord_y,
        .facing = facing8(coord_x, coord_y, target),
        .mission = 4,
        .queued_mission = -1,
        .ammo = -1,
        .second_shot = true,
    };
    _ = random.next(&world.rng_state);
    world.infantry_count += 1;
    return true;
}

fn addUnitRing(
    world: *state.World,
    owner: state.Owner,
    kind: rules.ObjectType,
    count: u8,
    center: state.Position,
    facing_target: state.Position,
    min_radius: i16,
    max_radius: i16,
) bool {
    var added: u8 = 0;
    var radius = min_radius;
    while (radius <= max_radius and added < count) : (radius += 1) {
        var y_offset: i16 = -radius;
        while (y_offset <= radius and added < count) : (y_offset += 1) {
            var x_offset: i16 = -radius;
            while (x_offset <= radius and added < count) : (x_offset += 1) {
                if (@max(abs(x_offset), abs(y_offset)) != radius) continue;
                const x = @as(i16, center.x) + x_offset;
                const y = @as(i16, center.y) + y_offset;
                if (x < 0 or y < 0 or x >= world.map_width or y >= world.map_height) continue;
                const position: state.Position = .{ .x = @intCast(x), .y = @intCast(y) };
                if (!map.footPassable(position) or occupied(world, position)) continue;
                if (!addCombatUnit(world, owner, kind, position, facing_target)) return false;
                added += 1;
            }
        }
    }
    if (added == count) return true;
    world.failure = .capacity_overflow;
    return false;
}

fn addCombatUnit(
    world: *state.World,
    owner: state.Owner,
    kind: rules.ObjectType,
    position: state.Position,
    target: state.Position,
) bool {
    const index = world.addUnit(owner, kind, position) orelse return false;
    const facing = facing8(world.units[index].coord_x, world.units[index].coord_y, target);
    world.units[index].facing = facing;
    world.units[index].turret_facing = facing;
    world.units[index].mission = 4;
    _ = random.next(&world.rng_state);
    return true;
}

fn deployedYardPosition(world: *state.World, mcv: state.Position) ?state.Position {
    if (mcv.x == 0 or mcv.y == 0) {
        world.failure = .unsupported_content;
        return null;
    }
    return .{ .x = mcv.x - 1, .y = mcv.y - 1 };
}

fn facing8(coord_x: i16, coord_y: i16, target: state.Position) u8 {
    const desired = movement.desiredFacing256(
        coord_x,
        coord_y,
        @as(i16, target.x) * 256 + 128,
        @as(i16, target.y) * 256 + 128,
    );
    return @intCast((@as(u16, desired) + 16) & 0xe0);
}

fn occupied(world: *const state.World, position: state.Position) bool {
    for (world.units) |unit| {
        if (unit.active and unit.position.x == position.x and unit.position.y == position.y) return true;
    }
    for (world.buildings[0..world.building_count]) |building| {
        if (!building.active) continue;
        const width: u8 = if (building.kind == .construction_yard) 3 else 1;
        const height: u8 = if (building.kind == .construction_yard) 2 else 1;
        if (position.x >= building.position.x and position.y >= building.position.y and
            position.x - building.position.x < width and position.y - building.position.y < height)
        {
            return true;
        }
    }
    for (world.infantry[0..world.infantry_count]) |infantry| {
        if (infantry.active and infantry.position.x == position.x and infantry.position.y == position.y) return true;
    }
    return false;
}

fn abs(value: i16) i16 {
    return if (value < 0) -value else value;
}
