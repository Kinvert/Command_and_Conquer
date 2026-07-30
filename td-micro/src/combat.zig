const action = @import("action.zig");
const difficulty = @import("difficulty.zig");
const movement = @import("movement.zig");
const production = @import("production.zig");
const random = @import("random.zig");
const rules = @import("rules.zig");
const state = @import("state.zig");

const mission_attack: i8 = 1;
const mission_move: i8 = 2;
const mission_guard: i8 = 4;
const mission_guard_area: i8 = 9;
const mission_hunt: i8 = 13;

const do_nothing: i8 = -1;
const do_stand_ready: i8 = 0;
const do_prone: i8 = 2;
const do_walk: i8 = 3;
const do_fire_weapon: i8 = 4;
const do_lie_down: i8 = 5;
const do_crawl: i8 = 6;
const do_get_up: i8 = 7;
const do_fire_prone: i8 = 8;
const do_idle1: i8 = 9;
const do_idle2: i8 = 10;
const do_gun_death: i8 = 22;
const do_grenade_death: i8 = 25;
const do_gesture1: i8 = 27;
const do_salute1: i8 = 28;
const do_gesture2: i8 = 29;
const do_salute2: i8 = 30;

const fear_anxious: u8 = 10;
const fear_scared: u8 = 100;

const speed_accumulator_base: u16 = 10;
const fuse_timer_padding: i32 = 4;
const direct_fuse_distance: i32 = 16;
const overshoot_fuse_distance: i32 = 256;
const explosion_radius: i32 = 384;
const fire_small_stages: u8 = 15;
const fire_small_damage: u16 = 8;

const Coord = struct {
    x: i32,
    y: i32,
};

const Weapon = struct {
    projectile: state.ProjectileKind,
    damage: i16,
    rof: u8,
    range: u16,
    fire_launch: u8,
    prone_launch: u8,
    projectile_speed: u8,
    arming_frames: u8,
};

pub fn e1DuelFixture() state.World {
    return duelFixture(.e1);
}

pub fn e3DuelFixture() state.World {
    return duelFixture(.e3);
}

pub fn tankDuelFixture() state.World {
    var world = state.World.reset(1);
    world.players[@intFromEnum(state.Owner.opponent)].controller = .policy;
    world.easy_ai.active = false;
    _ = random.next(&world.rng_state);
    _ = random.next(&world.rng_state);
    // Added, not substituted: overwriting the player MCV leaves the player with no MCV and no
    // buildings, which flags them defeated and destroys their units within a few frames.
    world.units[2] = .{
        .active = true,
        .kind = .medium_tank,
        .owner = .player,
        .position = .{ .x = 20, .y = 20 },
        .health = rules.object(.medium_tank).?.strength,
        .coord_x = 5248,
        .coord_y = 5248,
        .facing = 64,
        .turret_facing = 64,
        .mission = mission_guard,
    };
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .opponent,
        .position = .{ .x = 21, .y = 20 },
        .health = rules.object(.e1).?.strength,
        .coord_x = 5504,
        .coord_y = 5248,
        .facing = 192,
        .ammo = -1,
        .second_shot = true,
    };
    world.infantry_count = 1;
    return world;
}

/// True when the unit currently holds a live target reference.
pub fn hasTarget(unit: state.Unit) bool {
    return unit.target.kind != .none;
}

fn duelFixture(kind: rules.ObjectType) state.World {
    var world = state.World.reset(1);
    world.players[@intFromEnum(state.Owner.opponent)].controller = .policy;
    world.easy_ai.active = false;
    _ = random.next(&world.rng_state);
    _ = random.next(&world.rng_state);
    world.infantry[0] = .{
        .active = true,
        .kind = kind,
        .owner = .player,
        .position = .{ .x = 20, .y = 20 },
        .health = rules.object(kind).?.strength,
        .coord_x = 5248,
        .coord_y = 5248,
        .facing = 64,
        .ammo = -1,
        .second_shot = true,
    };
    world.infantry[1] = .{
        .active = true,
        .kind = kind,
        .owner = .opponent,
        .position = .{ .x = 21, .y = 20 },
        .health = rules.object(kind).?.strength,
        .coord_x = 5504,
        .coord_y = 5248,
        .facing = 192,
        .ammo = -1,
        .second_shot = true,
    };
    world.infantry_count = 2;
    return world;
}

pub fn apply(world: *state.World, owner: state.Owner, command: action.Action) bool {
    const resolved = resolveAttack(world, owner, command) orelse return false;
    const actor_index = resolved.actor_index;
    const target = resolved.target;
    recordPlayerAttackMatchup(world, owner, resolved);
    if (resolved.is_vehicle) {
        // A vehicle only needs its target set: tickUnitTurrets steers and tickUnitWeapons fires.
        world.units[actor_index].target = target;
        return true;
    }
    const infantry = &world.infantry[actor_index];

    infantry.target = target;
    // MissionClass ignores a repeated assignment of the active mission. FootClass still
    // invalidates the path, which is applied when the queued command reaches tickInfantry.
    if (infantry.mission != mission_attack) infantry.queued_mission = mission_attack;
    infantry.attack_pending = true;
    infantry.attack_delay = 1;
    return true;
}

fn recordPlayerAttackMatchup(
    world: *state.World,
    owner: state.Owner,
    resolved: ResolvedAttack,
) void {
    if (owner != .player) return;
    const actor_kind = if (resolved.is_vehicle)
        world.units[resolved.actor_index].kind
    else
        world.infantry[resolved.actor_index].kind;
    switch (actor_kind) {
        .e1 => {
            world.metrics_player_e1_attack_orders +|= 1;
            if (resolved.target.kind == .e1 or resolved.target.kind == .e3) {
                world.metrics_player_e1_infantry_targets +|= 1;
            }
        },
        .e3 => {
            world.metrics_player_e3_attack_orders +|= 1;
            if (resolved.target.kind == .mcv or
                resolved.target.kind == .harvester or
                resolved.target.kind == .medium_tank or
                resolved.target.kind == .humvee)
            {
                world.metrics_player_e3_vehicle_targets +|= 1;
            }
        },
        .medium_tank => {
            world.metrics_player_tank_attack_orders +|= 1;
            if (resolved.target.kind == .e3) {
                world.metrics_player_tank_e3_targets +|= 1;
            }
        },
        else => {},
    }
}

pub fn canApply(world: *const state.World, owner: state.Owner, command: action.Action) bool {
    return resolveAttack(world, owner, command) != null;
}

pub fn attackTargetValid(world: *const state.World, owner: state.Owner, slot: u8) bool {
    return enemyBySlot(world, owner, slot) != null;
}

const ResolvedAttack = struct {
    actor_index: usize,
    target: state.EntityRef,
    /// CNC26: attack actors can be vehicles now, which live in world.units rather than
    /// world.infantry. Without this the caller cannot tell which array to index.
    is_vehicle: bool = false,
};

fn resolveAttack(
    world: *const state.World,
    owner: state.Owner,
    command: action.Action,
) ?ResolvedAttack {
    if (command.command != .attack or command.target_kind != .visible_enemy) return null;
    const target = enemyBySlot(world, owner, command.target_slot) orelse return null;
    if (actorInfantryBySlot(world, owner, command.actor)) |actor_index| {
        if (weapon(world.infantry[actor_index].kind) == null) return null;
        return .{ .actor_index = actor_index, .target = target };
    }
    // A combat vehicle in the same slot space. Vehicles carry their own weapon table.
    if (actorVehicleBySlot(world, owner, command.actor)) |actor_index| {
        if (unitWeapon(world.units[actor_index].kind) == null) return null;
        return .{ .actor_index = actor_index, .target = target, .is_vehicle = true };
    }
    return null;
}

pub fn tick(world: *state.World) void {
    tickObjectMissions(world);
    tickAfterUnitMissions(world, null);
}

pub fn perCellProcess(world: *state.World, entered_cell: *const movement.InfantryFrameFlags) void {
    for (world.infantry[0..world.infantry_count], 0..) |*infantry, index| {
        if (!entered_cell[index] or !infantry.active or !targetAlive(world, infantry.target)) continue;
        if (infantry.mission != mission_guard_area and infantry.mission != mission_attack and infantry.mission != mission_hunt) continue;
        if (!targetInWeaponRange(world, infantry.*)) continue;

        infantry.destination_valid = false;
        infantry.new_destination = false;
        infantry.path_facing = -1;
        @memset(&infantry.path, -1);
    }
}

pub fn tickAfterUnitMissions(world: *state.World, moving_at_frame_start: ?*const movement.InfantryFrameFlags) void {
    tickBuildingFires(world);
    tickUnitWeapons(world);
    for (0..world.infantry_count) |index| {
        if (!world.infantry[index].active) continue;
        const was_moving = if (moving_at_frame_start) |snapshot| snapshot[index] else world.infantry[index].moving;
        tickInfantry(world, index, was_moving);
    }
    tickProjectiles(world);
}

pub fn tickObjectMissions(world: *state.World) void {
    tickUnitMissions(world);
    tickUnitTurrets(world);
    tickInfantryMissions(world);
}

/// Port of the turret half of Vanilla's `TurretClass::AI`. The turret steers toward its target
/// when it has one and otherwise realigns with the hull, always at the unit's stock `ROT + 1`.
pub fn tickUnitTurrets(world: *state.World) void {
    for (&world.units, 0..) |*unit, index| {
        if (!unit.active or unit.health == 0) continue;
        const rate = rules.turretRate(unit.kind) orelse continue;
        const desired = unitTurretDesired(world, index) orelse continue;
        unit.turret_facing = rotateFacing(unit.turret_facing, desired, rate);
    }
}

/// The turret's desired facing, or null when the unit has no turret at all.
fn unitTurretDesired(world: *const state.World, index: usize) ?u8 {
    const unit = world.units[index];
    if (rules.turretRate(unit.kind) == null) return null;
    if (!targetAlive(world, unit.target)) return unit.facing;
    const target = entityCoord(world, unit.target) orelse return unit.facing;
    return movement.desiredFacing256(
        @intCast(unit.coord_x),
        @intCast(unit.coord_y),
        @intCast(target.x),
        @intCast(target.y),
    );
}

pub const unitTurretDesiredForTest = unitTurretDesired;

fn unitWeapon(kind: rules.ObjectType) ?Weapon {
    const rule: rules.WeaponRule = switch (kind) {
        .medium_tank => rules.weapon_105mm,
        .humvee => rules.weapon_m60mg,
        else => return null,
    };
    return .{
        .projectile = @enumFromInt(rule.projectile_id),
        .damage = rule.damage,
        .rof = @intCast(rule.reload_frames),
        .range = rule.range_leptons,
        .fire_launch = rule.fire_launch,
        .prone_launch = rule.prone_launch,
        .projectile_speed = rule.projectile_speed,
        .arming_frames = rule.arming_frames,
    };
}

/// Port of `TurretClass::Fire_Coord` for the two supported vehicles: lift the center coordinate
/// north by 0x30, then run out along the turret facing by the barrel length.
fn unitFireCoord(unit: state.Unit) Coord {
    const barrel: u16 = switch (unit.kind) {
        .medium_tank => 0x00C0,
        .humvee => 0x0030,
        else => 0,
    };
    const lifted = movement.coordMove(unit.coord_x, unit.coord_y, 0, 0x0030);
    const muzzle = movement.coordMove(lifted.x, lifted.y, unit.turret_facing, barrel);
    return .{ .x = muzzle.x, .y = muzzle.y };
}

fn unitTargetInWeaponRange(world: *const state.World, unit: state.Unit) bool {
    const spec = unitWeapon(unit.kind) orelse return false;
    const source = unitFireCoord(unit);
    const target = entityCoord(world, unit.target) orelse return false;
    var range: u16 = spec.range;
    if (rules.object(unit.target.kind)) |target_rule| {
        if (target_rule.category == .building) {
            range += @as(u16, target_rule.footprint_width + target_rule.footprint_height) * 64;
        }
    }
    return distance(source, target) <= range;
}

/// Port of the turret arm of `TurretClass::Can_Fire`. Neither supported vehicle carries a homing
/// weapon, so both must hold fire while the turret is still slewing, and the residual angle to the
/// target must be under 8 facing units.
fn canUnitFire(world: *const state.World, index: usize) bool {
    const unit = world.units[index];
    if (!unit.active or unit.health == 0 or unit.weapon_cooldown != 0) return false;
    if (unitWeapon(unit.kind) == null) return false;
    if (!targetAlive(world, unit.target)) return false;
    const desired = unitTurretDesired(world, index) orelse return false;
    if (unit.turret_facing != desired) return false;
    const difference: i8 = @bitCast(desired -% unit.turret_facing);
    const magnitude: u8 = @intCast(if (difference < 0) -@as(i16, difference) else difference);
    if (magnitude >= 8) return false;
    return unitTargetInWeaponRange(world, unit);
}

pub fn tickUnitWeapons(world: *state.World) void {
    for (&world.units, 0..) |*unit, index| {
        if (!unit.active) continue;
        if (unit.weapon_cooldown != 0) unit.weapon_cooldown -= 1;
        if (!canUnitFire(world, index)) continue;
        const spec = unitWeapon(unit.kind) orelse continue;
        fireUnit(world, index, spec);
    }
}

fn fireUnit(world: *state.World, unit_index: usize, spec: Weapon) void {
    const unit = &world.units[unit_index];
    if (unit.owner == .player and unit.kind == .medium_tank) world.metrics_tank_shots +|= 1;
    unit.weapon_cooldown = difficulty.rof(world, unit.owner, spec.rof);
    const target_coord = entityCoord(world, unit.target) orelse return;
    const source_ref = unitRef(unit_index, unit.*);
    const muzzle = unitFireCoord(unit.*);

    for (&world.projectiles, 0..) |*projectile, projectile_index| {
        if (projectile.active) continue;
        if (spec.projectile == .bullet) {
            // Invisible near-instant small arms, the same path the M16 already uses.
            const facing = movement.desiredFacing256(
                @intCast(muzzle.x),
                @intCast(muzzle.y),
                @intCast(target_coord.x),
                @intCast(target_coord.y),
            );
            projectile.* = .{
                .active = true,
                .id = @intCast(projectile_index),
                .kind = spec.projectile,
                .source = source_ref,
                .target = unit.target,
                .coord_x = target_coord.x,
                .coord_y = target_coord.y,
                .fuse_x = target_coord.x,
                .fuse_y = target_coord.y,
                .strength = difficulty.firepower(world, unit.owner, spec.damage),
                .facing = facing,
                .desired_facing = facing,
                .timer = 4,
            };
        } else {
            const facing = movement.desiredFacing256(
                @intCast(muzzle.x),
                @intCast(muzzle.y),
                @intCast(target_coord.x),
                @intCast(target_coord.y),
            );
            const fuse_distance = distance(muzzle, target_coord);
            projectile.* = .{
                .active = true,
                .id = @intCast(projectile_index),
                .kind = spec.projectile,
                .source = source_ref,
                .target = unit.target,
                .coord_x = muzzle.x,
                .coord_y = muzzle.y,
                .fuse_x = target_coord.x,
                .fuse_y = target_coord.y,
                .strength = difficulty.firepower(world, unit.owner, spec.damage),
                .facing = facing,
                .desired_facing = facing,
                .speed = spec.projectile_speed,
                .timer = @intCast(@min(255, @divTrunc(fuse_distance, @as(i32, spec.projectile_speed)) + fuse_timer_padding)),
                .arming = spec.arming_frames,
                .proximity = @intCast(fuse_distance),
            };
        }
        world.projectile_order[world.projectile_count] = @intCast(projectile_index);
        world.projectile_count += 1;
        return;
    }
    world.failure = .capacity_overflow;
}

pub const canUnitFireForTest = canUnitFire;
pub const unitFireCoordForTest = unitFireCoord;

pub fn tickUnitMissions(world: *state.World) void {
    for (0..world.units.len) |index| {
        const unit = &world.units[index];
        if (!unit.active or unit.health == 0 or unit.mission != mission_guard or world.frame < unit.mission_timer_due) continue;
        // Acquire like infantry on guard. tickUnitWeapons, turret aiming and fireUnit were all
        // already in place; unit.target was simply never set, so a vehicle drove around with a
        // working gun and never fired it.
        if (!targetAlive(world, unit.target)) {
            unit.target = nearestEnemyInRangeOfUnit(world, index) orelse .{};
        }
        unit.mission_timer_due = world.frame + 15 + @as(u32, @intCast(random.pick(&world.rng_state, 0, 4)));
    }
}

/// Nearest live enemy within this vehicle's weapon range, mirroring nearestEnemyInRange for
/// infantry but scanning both infantry and units so tanks can engage armour.
fn nearestEnemyInRangeOfUnit(world: *const state.World, source_index: usize) ?state.EntityRef {
    const source = world.units[source_index];
    const spec = unitWeapon(source.kind) orelse return null;
    const source_coord = Coord{ .x = source.coord_x, .y = source.coord_y };
    var best: ?state.EntityRef = null;
    var best_distance: i32 = 0;
    for (world.infantry, 0..) |candidate, candidate_index| {
        if (!candidate.active or candidate.health == 0 or candidate.owner == source.owner) continue;
        const d = distance(source_coord, .{ .x = candidate.coord_x, .y = candidate.coord_y });
        if (d > spec.range) continue;
        if (best == null or d < best_distance) {
            best = infantryRef(candidate_index, candidate);
            best_distance = d;
        }
    }
    for (world.units, 0..) |candidate, candidate_index| {
        if (!candidate.active or candidate.health == 0 or candidate.owner == source.owner) continue;
        if (candidate_index == source_index) continue;
        const d = distance(source_coord, .{ .x = candidate.coord_x, .y = candidate.coord_y });
        if (d > spec.range) continue;
        if (best == null or d < best_distance) {
            best = unitRef(candidate_index, candidate);
            best_distance = d;
        }
    }
    return best;
}

pub fn tickInfantryMissions(world: *state.World) void {
    tickInfantryMissionsUntil(world, world.infantry.len);
}

pub fn tickInfantryMissionsUntil(world: *state.World, limit: usize) void {
    for (0..@min(limit, world.infantry.len)) |index| {
        if (world.infantry[index].active) tickInfantryMission(world, index);
    }
}

pub fn prepareAttackMissions(world: *state.World) void {
    for (0..world.infantry.len) |index| {
        const infantry = &world.infantry[index];
        if (!infantry.active or infantry.health == 0 or infantry.mission != mission_attack or world.frame < infantry.mission_timer_due) continue;
        missionAttack(world, index);
    }
}

pub fn commenceQueuedInfantryMissions(world: *state.World, limit: usize, transitioned: *[rules.max_infantry]u8) usize {
    var count: usize = 0;
    for (0..@min(limit, world.infantry.len)) |index| {
        const infantry = &world.infantry[index];
        if (!infantry.active or infantry.moving or infantry.queued_mission != mission_hunt) continue;
        if (infantry.animation != do_nothing and !interruptible(infantry.animation)) continue;

        infantry.mission = infantry.queued_mission;
        infantry.queued_mission = -1;
        infantry.mission_timer_due = world.frame + 1;
        transitioned[count] = @intCast(index);
        count += 1;
    }
    return count;
}

fn tickInfantryMission(world: *state.World, index: usize) void {
    const infantry = &world.infantry[index];
    if (infantry.health == 0 or world.frame < infantry.mission_timer_due) return;
    switch (infantry.mission) {
        mission_guard => {
            if (targetAlive(world, infantry.target) and
                infantry.queued_mission != mission_attack and
                !infantry.attack_pending and
                !targetInWeaponRange(world, infantry.*))
            {
                infantry.target = .{};
            }
            if (!targetAlive(world, infantry.target)) {
                infantry.target = nearestEnemyInRange(world, index) orelse .{};
            }
            if (!targetAlive(world, infantry.target)) randomAnimate(world, infantry);
            infantry.mission_timer_due = world.frame + 15 + @as(u32, @intCast(random.pick(&world.rng_state, 0, 4)));
        },
        mission_guard_area => {
            if (!infantry.destination_valid and !targetAlive(world, infantry.target) and infantry.home_valid) {
                const current = Coord{ .x = infantry.coord_x, .y = infantry.coord_y };
                if (distance(current, cellCenter(infantry.home)) > 0x0200) {
                    movement.assignNavigation(infantry, infantry.home);
                }
            }
            if (!targetAlive(world, infantry.target)) {
                infantry.target = nearestEnemyInRange(world, index) orelse .{};
                infantry.path[0] = -1;
                infantry.path_facing = -1;
            }
            randomAnimate(world, infantry);
            const mission_delay = random.pick(&world.rng_state, 0, 4);
            infantry.mission_timer_due = world.frame + 15 + @as(u32, @intCast(mission_delay));
        },
        mission_attack => missionAttack(world, index),
        mission_hunt => {
            if (!targetAlive(world, infantry.target)) {
                infantry.target = firstEnemyTarget(world, infantry.owner) orelse .{};
                infantry.path[0] = -1;
                infantry.path_facing = -1;
            }
            if (targetAlive(world, infantry.target)) {
                if (entityPosition(world, infantry.target)) |position| {
                    const destination_changed = infantry.destination_valid and
                        (infantry.destination.x != position.x or infantry.destination.y != position.y);
                    if (destination_changed or (!infantry.destination_valid and !targetInWeaponRange(world, infantry.*))) {
                        movement.assignNavigation(infantry, position);
                    }
                }
            } else {
                randomAnimate(world, infantry);
            }
            infantry.mission_timer_due = world.frame + rules.ticks_per_second + 5;
        },
        mission_move => {
            if (infantry.owner == .opponent and !targetAlive(world, infantry.target)) {
                infantry.target = nearestEnemyInRange(world, index) orelse .{};
                // InfantryClass::Assign_Target invalidates the pending path even on a miss.
                infantry.path[0] = -1;
                infantry.path_facing = -1;
            }
            infantry.mission_timer_due = world.frame + rules.ticks_per_second + 3;
        },
        else => infantry.mission_timer_due = world.frame + 15,
    }
}

fn missionAttack(world: *state.World, index: usize) void {
    const infantry = &world.infantry[index];
    if (!targetAlive(world, infantry.target)) {
        infantry.target = .{};
        infantry.destination_valid = false;
        infantry.new_destination = false;
        infantry.path_facing = -1;
        @memset(&infantry.path, -1);
        infantry.mission = mission_guard;
        infantry.queued_mission = -1;
        infantry.mission_timer_due = world.frame + 1;
        return;
    }

    if (entityPosition(world, infantry.target)) |position| {
        const destination_changed = infantry.destination_valid and
            (infantry.destination.x != position.x or infantry.destination.y != position.y);
        if (destination_changed or (!infantry.destination_valid and !targetInWeaponRange(world, infantry.*))) {
            movement.assignNavigation(infantry, position);
        }
    }
    infantry.mission_timer_due = world.frame + rules.ticks_per_second + 2;
}

fn randomAnimate(world: *state.World, infantry: *state.Infantry) void {
    if (infantry.moving or infantry.prone or infantry.firing or (infantry.animation != do_stand_ready and infantry.animation != 1)) return;

    randomAnimateStanding(world, infantry);
}

pub fn randomAnimateStanding(world: *state.World, infantry: *state.Infantry) void {
    const roll = random.pick(&world.rng_state, 0, 55);
    switch (roll) {
        10 => _ = doAction(infantry, do_salute1, false),
        11 => _ = doAction(infantry, do_salute2, false),
        12 => _ = doAction(infantry, do_gesture1, false),
        13 => _ = doAction(infantry, do_gesture2, false),
        0, 3, 4 => randomFacing(world, infantry),
        1 => {
            _ = doAction(infantry, do_idle1, false);
            randomFacing(world, infantry);
        },
        2 => {
            _ = doAction(infantry, do_idle2, false);
            randomFacing(world, infantry);
        },
        else => {},
    }
}

fn randomFacing(world: *state.World, infantry: *state.Infantry) void {
    infantry.facing = @as(u8, @intCast(random.pick(&world.rng_state, 0, 7))) * 32;
}

fn tickInfantry(world: *state.World, index: usize, was_moving: bool) void {
    const infantry = &world.infantry[index];
    graphicTick(infantry);
    if (infantry.weapon_cooldown != 0) infantry.weapon_cooldown -= 1;

    if (infantry.attack_pending) {
        if (infantry.attack_delay != 0) {
            infantry.attack_delay -= 1;
            if (infantry.attack_delay == 0) {
                infantry.destination_valid = false;
                infantry.new_destination = false;
                infantry.pending_move = false;
                infantry.command_delay = 0;
                infantry.path_facing = -1;
                @memset(&infantry.path, -1);
            }
        } else {
            infantry.attack_pending = false;
        }
    }
    if (!infantry.attack_pending and !infantry.moving and
        infantry.mission != mission_attack and infantry.queued_mission == mission_attack)
    {
        infantry.mission = mission_attack;
        infantry.queued_mission = -1;
        infantry.mission_timer_due = world.frame + 1;
    }

    if (infantry.fear != 0) {
        infantry.fear -= 1;
        if (infantry.prone) {
            if (infantry.fear < fear_anxious) _ = doAction(infantry, do_get_up, false);
        } else if (infantry.fear >= fear_anxious and !infantry.moving and !infantry.destination_valid) {
            _ = doAction(infantry, do_lie_down, false);
        }
    }

    if (infantry.health != 0) {
        if (!targetAlive(world, infantry.target)) infantry.target = .{};
        if (canFire(world, infantry.*, was_moving)) {
            const firing_action: i8 = if (infantry.prone) do_fire_prone else do_fire_weapon;
            _ = doAction(infantry, firing_action, false);
            infantry.firing = true;
            faceTarget(world, infantry);
        }

        if (infantry.firing) {
            const spec = weapon(infantry.kind).?;
            const launch = if (infantry.prone) spec.prone_launch else spec.fire_launch;
            if (infantry.animation_stage == launch) fire(world, index, spec);
        }
    }

    finishAnimation(infantry);
}

fn graphicTick(infantry: *state.Infantry) void {
    if (infantry.animation_rate == 0) return;
    infantry.animation_timer -= 1;
    if (infantry.animation_timer != 0) return;
    infantry.animation_stage += 1;
    infantry.animation_timer = infantry.animation_rate;
}

fn doAction(infantry: *state.Infantry, next: i8, force: bool) bool {
    if (next == infantry.animation) return false;
    if (infantry.animation != do_nothing and !force and !interruptible(infantry.animation)) return false;

    infantry.animation = next;
    infantry.animation_stage = 0;
    infantry.animation_rate = animationRate(next);
    infantry.animation_timer = infantry.animation_rate;
    switch (next) {
        do_lie_down => infantry.prone = true,
        do_get_up => infantry.prone = false,
        else => {},
    }
    return true;
}

fn finishAnimation(infantry: *state.Infantry) void {
    if (infantry.animation == do_walk and infantry.moving) return;
    if (infantry.animation != do_nothing and infantry.animation_stage < animationCount(infantry.kind, infantry.animation)) return;
    if (infantry.animation == do_gun_death or infantry.animation == do_grenade_death) {
        infantry.active = false;
        return;
    }
    const next = if (infantry.moving)
        if (infantry.prone) do_crawl else do_walk
    else if (infantry.prone)
        do_prone
    else
        do_stand_ready;
    _ = doAction(infantry, next, true);
}

fn interruptible(animation: i8) bool {
    return switch (animation) {
        do_stand_ready, 1, do_prone, do_walk, do_fire_weapon, 6, do_fire_prone, do_idle1, do_idle2, 12 => true,
        else => false,
    };
}

fn animationRate(animation: i8) u8 {
    return switch (animation) {
        do_fire_weapon, do_fire_prone => 1,
        do_walk, do_lie_down, do_crawl, do_idle1, do_idle2, do_gun_death, do_grenade_death, do_gesture1, do_salute1, do_gesture2, do_salute2 => 2,
        do_get_up => 3,
        else => 0,
    };
}

fn animationCount(kind: rules.ObjectType, animation: i8) u16 {
    return switch (animation) {
        do_stand_ready, do_prone => 1,
        do_walk, do_crawl => 6,
        do_fire_weapon => 8,
        do_lie_down, do_get_up => 2,
        do_fire_prone => if (kind == .e3) 10 else 6,
        do_idle1, do_idle2 => 16,
        do_gesture1, do_salute1, do_gesture2, do_salute2 => 3,
        do_gun_death => 8,
        do_grenade_death => 12,
        else => 1,
    };
}

fn canFire(world: *const state.World, infantry: state.Infantry, was_moving: bool) bool {
    if (!infantry.target.valid() or infantry.weapon_cooldown != 0 or infantry.firing or infantry.moving or was_moving) return false;
    if (infantry.animation != do_nothing and !interruptible(infantry.animation)) return false;
    return targetInWeaponRange(world, infantry);
}

fn targetInWeaponRange(world: *const state.World, infantry: state.Infantry) bool {
    const spec = weapon(infantry.kind) orelse return false;
    const source = Coord{ .x = infantry.coord_x, .y = infantry.coord_y - 53 };
    const target = entityCoord(world, infantry.target) orelse return false;
    var range: u16 = spec.range;
    if (rules.object(infantry.target.kind)) |target_rule| {
        if (target_rule.category == .building) {
            range += @as(u16, target_rule.footprint_width + target_rule.footprint_height) * 64;
        }
    }
    return distance(source, target) <= range;
}

fn faceTarget(world: *const state.World, infantry: *state.Infantry) void {
    const target = entityCoord(world, infantry.target) orelse return;
    const desired = movement.desiredFacing256(
        @intCast(infantry.coord_x),
        @intCast(infantry.coord_y),
        @intCast(target.x),
        @intCast(target.y),
    );
    infantry.facing = (@as(u8, @intCast((@as(u16, desired) + 16) >> 5)) << 5);
}

fn fire(world: *state.World, infantry_index: usize, spec: Weapon) void {
    const infantry = &world.infantry[infantry_index];
    infantry.firing = false;
    infantry.weapon_cooldown = difficulty.rof(world, infantry.owner, spec.rof) + 3;
    const target_coord = entityCoord(world, infantry.target) orelse return;
    const source_ref = infantryRef(infantry_index, infantry.*);

    for (&world.projectiles, 0..) |*projectile, projectile_index| {
        if (projectile.active) continue;
        const fire_x = infantry.coord_x;
        const fire_y = infantry.coord_y - 53;
        if (spec.projectile == .bullet) {
            const facing = movement.desiredFacing256(
                fire_x,
                fire_y,
                @intCast(target_coord.x),
                @intCast(target_coord.y),
            );
            projectile.* = .{
                .active = true,
                .id = @intCast(projectile_index),
                .kind = spec.projectile,
                .source = source_ref,
                .target = infantry.target,
                .coord_x = target_coord.x,
                .coord_y = target_coord.y,
                .fuse_x = target_coord.x,
                .fuse_y = target_coord.y,
                .strength = difficulty.firepower(world, infantry.owner, spec.damage),
                .facing = facing,
                .desired_facing = facing,
                .timer = 4,
            };
        } else {
            const target_x: i16 = @intCast(target_coord.x);
            const target_y: i16 = @intCast(target_coord.y);
            var initial_facing = infantry.facing;
            var fuse_x = target_x;
            var fuse_y = target_y;
            if (infantry.target.kind == .e1 or infantry.target.kind == .e3) {
                const scatter_distance: i32 = @min(512, @divTrunc(distance(
                    .{ .x = fire_x, .y = fire_y },
                    target_coord,
                ), 3));
                const adjustment = random.pick(&world.rng_state, 0, 10) - 5;
                initial_facing = @intCast((@as(i32, infantry.facing) + adjustment) & 255);
                const scatter_radius: u16 = @intCast(random.pick(&world.rng_state, 0, scatter_distance));
                const scatter_facing: u8 = @intCast(random.pick(&world.rng_state, 0, 254));
                const fuse = movement.coordMove(target_x, target_y, scatter_facing, scatter_radius);
                fuse_x = fuse.x;
                fuse_y = fuse.y;
            }
            const fuse_distance = distance(
                .{ .x = fire_x, .y = fire_y },
                .{ .x = fuse_x, .y = fuse_y },
            );
            projectile.* = .{
                .active = true,
                .id = @intCast(projectile_index),
                .kind = spec.projectile,
                .source = source_ref,
                .target = infantry.target,
                .coord_x = fire_x,
                .coord_y = fire_y,
                .fuse_x = fuse_x,
                .fuse_y = fuse_y,
                .strength = difficulty.firepower(world, infantry.owner, spec.damage),
                .facing = initial_facing,
                .desired_facing = initial_facing,
                .speed = spec.projectile_speed,
                .timer = @intCast(@min(255, @divTrunc(fuse_distance, @as(i32, spec.projectile_speed)) + fuse_timer_padding)),
                .arming = spec.arming_frames,
                .proximity = @intCast(fuse_distance),
            };
        }
        world.projectile_order[world.projectile_count] = @intCast(projectile_index);
        world.projectile_count += 1;
        return;
    }
    world.failure = .capacity_overflow;
}

fn tickProjectiles(world: *state.World) void {
    var order_index: usize = 0;
    while (order_index < world.projectile_count) {
        const projectile_index: usize = world.projectile_order[order_index];
        if (projectile_index >= world.projectiles.len or !world.projectiles[projectile_index].active) {
            world.failure = .unsupported_content;
            return;
        }
        const detonated = switch (world.projectiles[projectile_index].kind) {
            .bullet => blk: {
                const projectile = world.projectiles[projectile_index];
                explode(world, projectile, .{ .x = projectile.coord_x, .y = projectile.coord_y });
                // Invisible TD bullets scatter their impact animation after applying damage.
                _ = random.pick(&world.rng_state, 0, 254);
                break :blk true;
            },
            .apds => tickApds(world, projectile_index),
            .tow => tickTow(world, projectile_index),
        };
        if (detonated) {
            world.projectiles[projectile_index].active = false;
            removeProjectileOrder(world, order_index);
            // The impact animation replaces the deleted bullet in TD's Logic count, so the
            // object shifted into this position is skipped by the for-loop increment.
            order_index += 1;
        } else {
            order_index += 1;
        }
    }
}

fn removeProjectileOrder(world: *state.World, order_index: usize) void {
    const count: usize = world.projectile_count;
    var index = order_index;
    while (index + 1 < count) : (index += 1) {
        world.projectile_order[index] = world.projectile_order[index + 1];
    }
    world.projectile_order[count - 1] = 0;
    world.projectile_count -= 1;
}

fn tickTow(world: *state.World, index: usize) bool {
    return tickTravelingProjectile(world, index, true, rules.weapon_dragon.turn_rate);
}

/// BULLET_APDS travels at MPH_VERY_FAST but has ROT 0 and `IsHoming` false, so it flies the
/// heading it was launched on and never re-aims. Everything after the steering step is identical
/// to the homing case, so both share this routine rather than drifting apart in two copies.
fn tickApds(world: *state.World, index: usize) bool {
    return tickTravelingProjectile(world, index, false, 0);
}

fn tickTravelingProjectile(world: *state.World, index: usize, homing: bool, turn_rate: u8) bool {
    const projectile = &world.projectiles[index];
    if (homing) {
        if ((world.frame & 1) != 0) {
            if (entityCoord(world, projectile.target)) |target_coord| {
                projectile.desired_facing = movement.desiredFacing256(
                    @intCast(projectile.coord_x),
                    @intCast(projectile.coord_y),
                    @intCast(target_coord.x),
                    @intCast(target_coord.y),
                );
            }
        }
        projectile.facing = rotateFacing(@intCast(projectile.facing), projectile.desired_facing, turn_rate);
    }

    const actual = @as(u32, projectile.speed) + projectile.speed_accum;
    const speed_accum: u16 = @intCast(actual % speed_accumulator_base);
    const move_distance: u16 = @intCast(actual - speed_accum);
    projectile.speed_accum = speed_accum;
    const moved = movement.coordMove(
        @intCast(projectile.coord_x),
        @intCast(projectile.coord_y),
        @intCast(projectile.facing),
        move_distance,
    );

    if (projectile.timer != 0) projectile.timer -= 1;
    var detonated = false;
    if (projectile.arming != 0) {
        projectile.arming -= 1;
    } else if (projectile.timer == 0) {
        detonated = true;
    } else {
        const proximity = distance(
            .{ .x = moved.x, .y = moved.y },
            .{ .x = projectile.fuse_x, .y = projectile.fuse_y },
        );
        if (proximity < direct_fuse_distance or (proximity < overshoot_fuse_distance and proximity > projectile.proximity)) {
            detonated = true;
        } else {
            projectile.proximity = @intCast(proximity);
        }
    }

    if (detonated) {
        const snapshot = projectile.*;
        // Vanilla's homing impact uses the prior stored coordinate when the moved fuse trips.
        explode(world, snapshot, .{ .x = snapshot.coord_x, .y = snapshot.coord_y });
        return true;
    }
    projectile.coord_x = moved.x;
    projectile.coord_y = moved.y;
    return false;
}

/// Test-only alias. `rotateFacing` is the port of Vanilla's `FacingClass::Rotation_Adjust`; the
/// vehicle turret tests assert it directly against the stock algorithm.
pub const rotateFacingForTest = rotateFacing;

fn rotateFacing(current: u8, desired: u8, rate: u8) u8 {
    const difference: i8 = @bitCast(desired -% current);
    if (difference == 0) return current;
    const magnitude: u8 = @intCast(if (difference < 0) -@as(i16, difference) else difference);
    if (magnitude < rate) return desired;
    return if (difference < 0) current -% rate else current +% rate;
}

fn explode(world: *state.World, projectile: state.Projectile, origin: Coord) void {
    for (world.units, 0..) |unit, index| {
        if (!unit.active or unit.health == 0) continue;
        const candidate = unitRef(index, unit);
        if (sameRef(candidate, projectile.source)) continue;
        const impact_distance = distance(origin, cellCenter(unit.position));
        if (impact_distance >= explosion_radius) continue;
        takeDamage(world, candidate, projectile.source, projectile.strength, projectile.kind, impact_distance);
    }
    for (world.buildings, 0..) |building, index| {
        if (!building.active or building.health == 0) continue;
        const candidate = buildingRef(index, building);
        if (sameRef(candidate, projectile.source)) continue;
        const impact_distance = if (buildingOccupies(building, positionForCoord(origin)))
            0
        else
            distance(origin, buildingTargetCoord(building));
        if (impact_distance >= explosion_radius) continue;
        takeDamage(world, candidate, projectile.source, projectile.strength, projectile.kind, impact_distance);
    }
    for (world.infantry, 0..) |infantry, index| {
        if (!infantry.active or infantry.health == 0) continue;
        const candidate = infantryRef(index, infantry);
        if (sameRef(candidate, projectile.source)) continue;
        const impact_distance = distance(origin, .{ .x = infantry.coord_x, .y = infantry.coord_y });
        if (impact_distance >= explosion_radius) continue;
        takeDamage(world, candidate, projectile.source, projectile.strength, projectile.kind, impact_distance);
    }
}

fn takeDamage(
    world: *state.World,
    target: state.EntityRef,
    source: state.EntityRef,
    raw_damage: i16,
    projectile_kind: state.ProjectileKind,
    impact_distance: i32,
) void {
    const target_rule = rules.object(target.kind) orelse {
        world.failure = .unsupported_content;
        return;
    };
    var damage = raw_damage;
    if (target.kind == .e1 or target.kind == .e3) {
        const index: usize = target.index;
        if (index >= world.infantry.len) return;
        const infantry = &world.infantry[index];
        if (!infantry.active or infantry.owner != target.owner or infantry.health == 0) return;
        infantry.firing = false;
        if (infantry.prone and damage != 0) damage >>= 1;
    }
    damage = difficulty.armorDamage(world, target.owner, damage);

    const projectile_rule = projectileRule(projectile_kind);
    const modifier: i32 = projectile_rule.armorModifier(target_rule.armor);
    damage = @intCast((@as(i32, damage) * modifier + 128) >> 8);
    const spread: u5 = @intCast(projectile_rule.spread_factor);
    const attenuation: u5 = @intCast(@min(16, impact_distance >> spread));
    damage = if (attenuation == 16) 0 else damage >> @as(u4, @intCast(attenuation));
    if (damage == 0) return;

    switch (target.kind) {
        .mcv, .harvester, .medium_tank, .humvee => {
            const index: usize = target.index;
            if (index >= world.units.len) return;
            const unit = &world.units[index];
            if (!unit.active or unit.owner != target.owner or unit.health == 0) return;
            if (damage < unit.health) {
                unit.health -= damage;
                return;
            }
            if (target.kind == .medium_tank and target.owner == .player) {
                world.metrics_player_tank_losses +|= 1;
                if (source.kind == .e3 and source.owner == .opponent) {
                    world.metrics_player_tank_losses_to_e3 +|= 1;
                }
            }
            unit.health = 0;
            recordInfantryKill(world, source);
            unit.active = false;
            detachTarget(world, target);
        },
        .construction_yard, .power_plant, .barracks, .refinery, .weapons_factory => {
            const index: usize = target.index;
            if (index >= world.buildings.len) return;
            const building = &world.buildings[index];
            if (!building.active or building.owner != target.owner or building.health == 0) return;
            const old_health = building.health;
            const old_output = buildingPowerOutput(target_rule, building.health);
            building.health = if (damage < building.health) building.health - damage else 0;
            const new_output = buildingPowerOutput(target_rule, building.health);
            world.players[@intFromEnum(building.owner)].power += new_output - old_output;
            if (old_health >= @divTrunc(target_rule.strength, 2) and
                building.health < @divTrunc(target_rule.strength, 2) and
                building.health != 0)
            {
                consumeBuildingHalfDamageEffects(world, target);
            }
            if (building.health != 0) return;
            recordInfantryKill(world, source);
            building.active = false;
            world.markBuildingChanged(building.owner);
            production.abandonUnavailableProduction(world, target.owner, target.kind);
            detachTarget(world, target);
        },
        .e1, .e3 => {
            const index: usize = target.index;
            const infantry = &world.infantry[index];
            if (damage >= infantry.health) {
                infantry.health = 0;
                recordInfantryKill(world, source);
                killInfantry(world, index, projectile_kind);
                return;
            }
            infantry.health -= damage;
            if (source.valid() and infantry.fear < fear_scared) {
                infantry.fear = fear_scared;
            } else {
                var more_fear: u8 = fear_anxious;
                const maximum = rules.object(infantry.kind).?.strength;
                if (@divTrunc(@as(i32, infantry.health) * 256, maximum) > 128) more_fear /= 4;
                infantry.fear +|= more_fear;
            }
        },
        .none => world.failure = .unsupported_content,
    }
}

fn recordInfantryKill(world: *state.World, source: state.EntityRef) void {
    recordTankKill(world, source);
    if (source.kind != .e1 and source.kind != .e3) return;
    const index: usize = source.index;
    if (index >= world.infantry.len) return;
    const infantry = &world.infantry[index];
    if (!infantry.active or infantry.owner != source.owner or infantry.health == 0) return;

    // InfantryClass::Made_A_Kill checks morale before CrewClass increments Kills.
    _ = random.pick(&world.rng_state, 0, 5);
    infantry.kills +%= 1;
}

/// Called from every kill site via recordInfantryKill, which is reached for units, buildings and
/// infantry alike. Counting only, with no RNG draw, so it cannot perturb the deterministic stream.
fn recordTankKill(world: *state.World, source: state.EntityRef) void {
    if (source.kind != .medium_tank or source.owner != .player) return;
    const index: usize = source.index;
    if (index >= world.units.len) return;
    const unit = &world.units[index];
    if (!unit.active or unit.owner != source.owner) return;
    world.metrics_tank_kills +|= 1;
}

fn killInfantry(world: *state.World, index: usize, projectile_kind: state.ProjectileKind) void {
    const victim = infantryRef(index, world.infantry[index]);
    const infantry = &world.infantry[index];
    infantry.target = .{};
    infantry.firing = false;
    infantry.moving = false;
    infantry.mission = mission_guard;
    infantry.queued_mission = -1;
    _ = doAction(infantry, if (projectile_kind == .bullet) do_gun_death else do_grenade_death, true);

    for (&world.infantry) |*other| {
        if (sameRef(other.target, victim)) other.target = .{};
    }
    for (&world.projectiles) |*projectile| {
        if (projectile.active and sameRef(projectile.source, victim)) projectile.source = .{};
    }
}

pub fn blowupOwner(world: *state.World, owner: state.Owner) void {
    var destroyed_building = false;
    for (&world.units, 0..) |*unit, index| {
        if (!unit.active or unit.health == 0 or unit.owner != owner) continue;
        const victim = unitRef(index, unit.*);
        unit.health = 0;
        unit.active = false;
        detachTarget(world, victim);
    }
    for (&world.buildings, 0..) |*building, index| {
        if (!building.active or building.health == 0 or building.owner != owner) continue;
        const victim = buildingRef(index, building.*);
        building.health = 0;
        building.active = false;
        destroyed_building = true;
        production.abandonUnavailableProduction(world, owner, building.kind);
        detachTarget(world, victim);
    }
    if (destroyed_building) world.markBuildingChanged(owner);
    for (&world.infantry, 0..) |*infantry, index| {
        if (!infantry.active or infantry.health == 0 or infantry.owner != owner) continue;
        infantry.health = 0;
        killInfantry(world, index, .tow);
    }
}

fn detachTarget(world: *state.World, victim: state.EntityRef) void {
    for (&world.infantry) |*infantry| {
        if (sameRef(infantry.target, victim)) infantry.target = .{};
    }
    for (&world.projectiles) |*projectile| {
        if (!projectile.active) continue;
        if (sameRef(projectile.target, victim)) projectile.target = .{};
        if (sameRef(projectile.source, victim)) projectile.source = .{};
    }
}

fn nearestEnemyInRange(world: *const state.World, source_index: usize) ?state.EntityRef {
    const source = world.infantry[source_index];
    const spec = weapon(source.kind) orelse return null;
    const source_coord = Coord{ .x = source.coord_x, .y = source.coord_y };
    var best: ?state.EntityRef = null;
    var best_distance: i32 = 0;
    for (world.infantry, 0..) |candidate, candidate_index| {
        if (!candidate.active or candidate.health == 0 or candidate.owner == source.owner) continue;
        const candidate_distance = distance(source_coord, .{ .x = candidate.coord_x, .y = candidate.coord_y });
        if (candidate_distance > spec.range) continue;
        if (best == null or candidate_distance < best_distance) {
            best = infantryRef(candidate_index, candidate);
            best_distance = candidate_distance;
        }
    }
    return best;
}

/// The unit index for `slot`, when that slot holds a combat vehicle. Walks the same
/// units -> buildings -> infantry ordering as actorInfantryBySlot so the two agree on slot numbers.
fn actorVehicleBySlot(world: *const state.World, owner: state.Owner, slot: u8) ?usize {
    var candidate: u8 = 0;
    for (world.units, 0..) |unit, index| {
        if (!unit.active or unit.owner != owner) continue;
        if (candidate == slot) {
            return if (unit.kind == .medium_tank or unit.kind == .humvee) index else null;
        }
        candidate += 1;
    }
    return null;
}

fn actorInfantryBySlot(world: *const state.World, owner: state.Owner, slot: u8) ?usize {
    var candidate: u8 = 0;
    for (world.units) |unit| {
        if (!unit.active or unit.owner != owner) continue;
        if (candidate == slot) return null;
        candidate += 1;
    }
    for (world.buildings) |building| {
        if (!building.active or building.owner != owner) continue;
        if (candidate == slot) return null;
        candidate += 1;
    }
    for (world.infantry, 0..) |infantry, index| {
        if (!infantry.active or infantry.owner != owner) continue;
        if (candidate == slot) return index;
        candidate += 1;
    }
    return null;
}

fn enemyBySlot(world: *const state.World, owner: state.Owner, slot: u8) ?state.EntityRef {
    var candidate: u8 = 0;
    for (world.units, 0..) |unit, index| {
        if (!unit.active or unit.owner == owner) continue;
        if (candidate == slot) return .{ .kind = unit.kind, .owner = unit.owner, .index = @intCast(index) };
        candidate += 1;
    }
    for (world.buildings, 0..) |building, index| {
        if (!building.active or building.owner == owner) continue;
        if (candidate == slot) return .{ .kind = building.kind, .owner = building.owner, .index = @intCast(index) };
        candidate += 1;
    }
    for (world.infantry, 0..) |infantry, index| {
        if (!infantry.active or infantry.owner == owner) continue;
        if (candidate == slot) return infantryRef(index, infantry);
        candidate += 1;
    }
    return null;
}

fn firstEnemyTarget(world: *const state.World, owner: state.Owner) ?state.EntityRef {
    for (world.units, 0..) |unit, index| {
        if (unit.active and unit.health != 0 and unit.owner != owner) {
            return .{ .kind = unit.kind, .owner = unit.owner, .index = @intCast(index) };
        }
    }
    for (world.buildings, 0..) |building, index| {
        if (building.active and building.health != 0 and building.owner != owner) {
            return .{ .kind = building.kind, .owner = building.owner, .index = @intCast(index) };
        }
    }
    for (world.infantry, 0..) |infantry, index| {
        if (infantry.active and infantry.health != 0 and infantry.owner != owner) return infantryRef(index, infantry);
    }
    return null;
}

fn entityPosition(world: *const state.World, target: state.EntityRef) ?state.Position {
    if (!targetAlive(world, target)) return null;
    const index: usize = target.index;
    return switch (target.kind) {
        .mcv, .harvester, .medium_tank, .humvee => world.units[index].position,
        .construction_yard, .power_plant, .barracks, .refinery, .weapons_factory => positionForCoord(buildingTargetCoord(world.buildings[index])),
        .e1, .e3 => world.infantry[index].position,
        .none => null,
    };
}

fn targetAlive(world: *const state.World, target: state.EntityRef) bool {
    if (!target.valid()) return false;
    const index: usize = target.index;
    return switch (target.kind) {
        .mcv, .harvester, .medium_tank, .humvee => index < world.units.len and world.units[index].active and world.units[index].owner == target.owner and world.units[index].health != 0,
        .construction_yard, .power_plant, .barracks, .refinery, .weapons_factory => index < world.buildings.len and world.buildings[index].active and world.buildings[index].owner == target.owner and world.buildings[index].health != 0,
        .e1, .e3 => index < world.infantry.len and world.infantry[index].active and world.infantry[index].owner == target.owner and world.infantry[index].health != 0,
        .none => false,
    };
}

fn entityCoord(world: *const state.World, target: state.EntityRef) ?Coord {
    if (!targetAlive(world, target)) return null;
    const index: usize = target.index;
    return switch (target.kind) {
        .mcv, .harvester, .medium_tank, .humvee => cellCenter(world.units[index].position),
        .construction_yard, .power_plant, .barracks, .refinery, .weapons_factory => buildingTargetCoord(world.buildings[index]),
        .e1, .e3 => .{ .x = world.infantry[index].coord_x, .y = world.infantry[index].coord_y },
        .none => null,
    };
}

fn cellCenter(position: state.Position) Coord {
    return .{ .x = @as(i32, position.x) * 256 + 128, .y = @as(i32, position.y) * 256 + 128 };
}

fn buildingTargetCoord(building: state.Building) Coord {
    const offset: Coord = switch (building.kind) {
        .construction_yard => .{ .x = 384, .y = 255 },
        .power_plant, .barracks => .{ .x = 255, .y = 255 },
        .refinery => .{ .x = 384, .y = 384 },
        else => .{ .x = 0, .y = 0 },
    };
    return .{
        .x = @as(i32, building.position.x) * 256 + offset.x,
        .y = @as(i32, building.position.y) * 256 + offset.y,
    };
}

fn positionForCoord(coord: Coord) state.Position {
    return .{ .x = coordinateCell(coord.x), .y = coordinateCell(coord.y) };
}

fn coordinateCell(value: i32) u8 {
    // TD stores each COORDINATE component as an unsigned 16-bit LEPTON.
    const raw: u16 = @bitCast(@as(i16, @truncate(value)));
    return @truncate(raw >> 8);
}

fn buildingOccupies(building: state.Building, position: state.Position) bool {
    if (position.x < building.position.x or position.y < building.position.y) return false;
    const x = position.x - building.position.x;
    const y = position.y - building.position.y;
    return switch (building.kind) {
        .construction_yard => x < 3 and y < 2,
        .power_plant => (x == 0 and y < 2) or (x == 1 and y == 1),
        .barracks => x < 2 and y == 0,
        .refinery => (x == 1 and y == 0) or (y == 1 and x < 3),
        else => false,
    };
}

fn buildingPowerOutput(object_rule: *const rules.ObjectRule, health: i16) i16 {
    if (object_rule.power <= 0 or health <= 0 or object_rule.strength <= 0) return 0;
    const fixed_health = (@as(u32, @intCast(health)) << 8) / @as(u32, @intCast(object_rule.strength));
    return @intCast((@as(u32, @intCast(object_rule.power)) * fixed_health + 128) >> 8);
}

fn consumeBuildingHalfDamageEffects(world: *state.World, target: state.EntityRef) void {
    // BuildingClass::Take_Damage creates cosmetic fires over Occupy_List(true).
    // Their fixed-point damage and RNG remain part of the headless simulation.
    const occupied_cells: usize = switch (target.kind) {
        .construction_yard => 6,
        .power_plant => 3,
        .barracks => 2,
        .refinery => 4,
        else => return,
    };
    for (0..occupied_cells) |_| {
        if (random.pick(&world.rng_state, 0, 99) >= 50) continue;
        _ = random.pick(&world.rng_state, 0, 254);
        const delay: u8 = @intCast(random.pick(&world.rng_state, 0, 7));
        const loops: u8 = @intCast(random.pick(&world.rng_state, 1, 3) * 2);
        addBuildingFireEffect(world, target, delay, loops);
    }
}

fn addBuildingFireEffect(world: *state.World, target: state.EntityRef, delay: u8, loops: u8) void {
    for (&world.building_fires, 0..) |*effect, index| {
        if (effect.active) continue;
        effect.* = .{
            .active = true,
            .target = target,
            .delay = delay,
            .loops = loops,
            .brand_new = true,
        };
        world.building_fire_count = @max(world.building_fire_count, @as(u16, @intCast(index + 1)));
        return;
    }
    world.failure = .capacity_overflow;
}

fn tickBuildingFires(world: *state.World) void {
    for (world.building_fires[0..world.building_fire_count]) |*effect| {
        if (!effect.active) continue;
        if (!targetAlive(world, effect.target)) {
            effect.active = false;
            continue;
        }
        if (effect.brand_new) {
            effect.brand_new = false;
            continue;
        }
        if (effect.delay != 0) {
            effect.delay -= 1;
            continue;
        }

        effect.stage += 1;
        if (effect.stage < fire_small_stages) {
            const accum = @as(u16, effect.accum) + fire_small_damage;
            effect.accum = @truncate(accum);
            if (accum > 255) applyBuildingFireDamage(world, effect.target);
        }
        if (effect.stage < fire_small_stages) continue;

        if (effect.loops != 0) effect.loops -= 1;
        if (effect.loops == 0) {
            effect.active = false;
        } else {
            effect.stage = 0;
        }
    }
    while (world.building_fire_count != 0 and
        !world.building_fires[world.building_fire_count - 1].active)
    {
        world.building_fire_count -= 1;
    }
}

fn applyBuildingFireDamage(world: *state.World, target: state.EntityRef) void {
    const index: usize = target.index;
    if (index >= world.buildings.len) return;
    const building = &world.buildings[index];
    if (!building.active or building.owner != target.owner or building.kind != target.kind or building.health == 0) return;
    const object_rule = rules.object(building.kind) orelse return;
    const old_output = buildingPowerOutput(object_rule, building.health);
    building.health -= 1;
    const new_output = buildingPowerOutput(object_rule, building.health);
    world.players[@intFromEnum(building.owner)].power += new_output - old_output;
    if (building.health != 0) return;

    building.active = false;
    world.markBuildingChanged(building.owner);
    production.abandonUnavailableProduction(world, building.owner, building.kind);
    detachTarget(world, target);
}

fn infantryRef(index: usize, infantry: state.Infantry) state.EntityRef {
    return .{ .kind = infantry.kind, .owner = infantry.owner, .index = @intCast(index) };
}

fn unitRef(index: usize, unit: state.Unit) state.EntityRef {
    return .{ .kind = unit.kind, .owner = unit.owner, .index = @intCast(index) };
}

fn buildingRef(index: usize, building: state.Building) state.EntityRef {
    return .{ .kind = building.kind, .owner = building.owner, .index = @intCast(index) };
}

fn sameRef(left: state.EntityRef, right: state.EntityRef) bool {
    return left.kind == right.kind and left.owner == right.owner and left.index == right.index;
}

fn distance(left: Coord, right: Coord) i32 {
    const x_delta = left.x - right.x;
    const y_delta = left.y - right.y;
    const x = if (x_delta < 0) -x_delta else x_delta;
    const y = if (y_delta < 0) -y_delta else y_delta;
    return @max(x, y) + @divTrunc(@min(x, y), 2);
}

fn weapon(kind: rules.ObjectType) ?Weapon {
    const rule: rules.WeaponRule = switch (kind) {
        .e1 => rules.weapon_m16,
        .e3 => rules.weapon_dragon,
        else => return null,
    };
    return .{
        .projectile = @enumFromInt(rule.projectile_id),
        .damage = rule.damage,
        .rof = @intCast(rule.reload_frames),
        .range = rule.range_leptons,
        .fire_launch = rule.fire_launch,
        .prone_launch = rule.prone_launch,
        .projectile_speed = rule.projectile_speed,
        .arming_frames = rule.arming_frames,
    };
}

fn projectileRule(kind: state.ProjectileKind) rules.WeaponRule {
    // Maps a projectile back to a weapon rule carrying the same stock warhead, which is what
    // supplies the armor modifier table and spread factor. BULLET_BULLET (M16 and M60MG) both
    // carry WARHEAD_SA, and BULLET_APDS (105mm) carries WARHEAD_AP exactly like BULLET_TOW, so
    // these rows are interchangeable for damage resolution.
    return switch (kind) {
        .bullet => rules.weapon_m16,
        .apds => rules.weapon_105mm,
        .tow => rules.weapon_dragon,
    };
}

test "coordinate cells preserve TD unsigned 16-bit wrapping" {
    const testing = @import("std").testing;
    try testing.expectEqual(state.Position{ .x = 0, .y = 20 }, positionForCoord(.{ .x = 128, .y = 5248 }));
    try testing.expectEqual(state.Position{ .x = 255, .y = 0 }, positionForCoord(.{ .x = -1, .y = 0 }));
    try testing.expectEqual(state.Position{ .x = 0, .y = 255 }, positionForCoord(.{ .x = 65_536, .y = -256 }));
}
