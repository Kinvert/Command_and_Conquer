const std = @import("std");
const action = @import("action.zig");
const difficulty = @import("difficulty.zig");
const movement = @import("movement.zig");
const pathfinder = @import("pathfinder.zig");
const random = @import("random.zig");
const rules = @import("rules.zig");
const state = @import("state.zig");
const tracks = @import("vehicle_tracks.zig");

const mission_move: i8 = 2;
const mission_guard: i8 = 4;
const mission_enter: i8 = 6;
const mission_harvest: i8 = 8;
const no_path: i8 = -1;

const looking: u8 = 0;
const harvesting: u8 = 1;
const find_home: u8 = 2;
const heading_home: u8 = 3;

const docking_wait: u8 = 1;
const docking_backup: u8 = 2;
const docking_unload: u8 = 3;
const docking_exit: u8 = 4;
const path_delay_frames: u8 = 15;

pub const HarvesterFrameSet = struct {
    active: [rules.max_units]bool,
    after_infantry: [rules.max_units]bool,
};

pub fn apply(world: *state.World, owner: state.Owner, command: action.Action) bool {
    const unit_index = unitIndexByActorSlot(world, owner, command.actor) orelse return false;
    return switch (command.command) {
        .move => if (command.target_kind == .cell)
            assignMove(world, unit_index, .{ .x = command.target_x, .y = command.target_y })
        else
            false,
        .harvest => if (command.target_kind == .cell)
            assignHarvest(world, unit_index, .{ .x = command.target_x, .y = command.target_y })
        else
            false,
        .return_cargo => if (command.target_kind == .own_entity)
            if (buildingIndexByOwnerSlot(world, owner, command.target_slot)) |building_index|
                assignReturn(world, unit_index, building_index)
            else
                false
        else
            false,
        else => false,
    };
}

pub fn grandOpenRefinery(world: *state.World, building_index: usize) void {
    if (building_index >= world.buildings.len) return;
    const building = world.buildings[building_index];
    if (!building.active or building.kind != .refinery) return;
    const preferred = state.Position{
        .x = building.position.x,
        .y = building.position.y +| 2,
    };
    const spawn = nearestFreeCell(world, preferred) orelse {
        world.players[@intFromEnum(building.owner)].credits += rules.object(.harvester).?.cost;
        return;
    };
    if (world.freeUnitSlots() == 0) {
        // The Refinery has already charged for its bundled Harvester. Match the blocked-exit path:
        // refund that component when the shared unit array cannot accept the spawn.
        world.players[@intFromEnum(building.owner)].credits += rules.object(.harvester).?.cost;
        return;
    }
    // UnitClass construction inherits TechnoClass's deterministic lemon check.
    _ = random.pick(&world.rng_state, 0, 255);
    const index = world.tryAddUnit(building.owner, .harvester, spawn) orelse return;
    const unit = &world.units[index];
    unit.facing = 160;
    unit.mission = mission_harvest;
    unit.status = looking;
    unit.home_refinery = @intCast(building_index);
}

pub fn tick(world: *state.World) void {
    for (0..world.units.len) |index| {
        if (!world.units[index].active or world.units[index].kind != .harvester or world.units[index].health <= 0) continue;
        tickHarvester(world, index);
    }
    tickCombatVehicles(world);
}

/// Combat vehicles reuse the harvester's Vanilla-validated driving engine but have no harvest or
/// docking behaviour, so they get their own pass. Keeping it separate leaves the harvester
/// ordering in `step.tickEasyAIFrameInto` exactly as it was validated.
pub fn tickCombatVehicles(world: *state.World) void {
    for (0..world.units.len) |index| {
        const unit = &world.units[index];
        if (!unit.active or unit.health <= 0 or !isCombatVehicle(unit.kind)) continue;
        if (unit.path_delay != 0) unit.path_delay -= 1;
        if (world.frame >= unit.mission_timer_due) {
            const delay = switch (unit.mission) {
                mission_move => tickMoveMission(unit),
                else => rules.ticks_per_second,
            };
            unit.mission_timer_due = world.frame + delay;
        }
        if (unit.moving) {
            advanceMovement(world, index);
        } else if (unit.destination_valid) {
            startMovement(world, index, true);
        }
    }
}

pub fn captureActiveHarvesters(world: *const state.World) HarvesterFrameSet {
    var active = [_]bool{false} ** rules.max_units;
    var after_infantry = [_]bool{false} ** rules.max_units;
    for (world.units, 0..) |unit, index| {
        active[index] = unit.active and unit.kind == .harvester and unit.health > 0;
        after_infantry[index] = unit.logic_after_infantry;
    }
    return .{ .active = active, .after_infantry = after_infantry };
}

pub fn tickMatchingHarvesters(
    world: *state.World,
    frame_start: *const HarvesterFrameSet,
    matching: bool,
    owner: ?state.Owner,
    after_infantry: ?bool,
) void {
    for (0..world.units.len) |index| {
        if (frame_start.active[index] != matching) continue;
        if (after_infantry) |expected| {
            if (frame_start.after_infantry[index] != expected) continue;
        }
        if (!world.units[index].active or world.units[index].kind != .harvester or world.units[index].health <= 0) continue;
        if (owner) |expected_owner| {
            if (world.units[index].owner != expected_owner) continue;
        }
        tickHarvester(world, index);
    }
}

/// Vehicles that drive under their own orders. The MCV is excluded: it only deploys.
pub fn isDrivable(kind: rules.ObjectType) bool {
    return switch (kind) {
        .harvester, .medium_tank, .humvee => true,
        else => false,
    };
}

fn isCombatVehicle(kind: rules.ObjectType) bool {
    return isDrivable(kind) and kind != .harvester;
}

/// Give a vehicle a destination without touching its mission. Vanilla's factory exit drives the
/// new vehicle clear of the bay while it stays on the guard mission, so this is deliberately not
/// `assignMove`, which would switch it to the move mission and diverge from the recorded trace.
pub fn assignExitDrive(world: *state.World, unit_index: usize, destination: state.Position) bool {
    if (unit_index >= world.units.len) return false;
    const unit = &world.units[unit_index];
    if (!unit.active or !isDrivable(unit.kind)) return false;
    setDestination(unit, destination);
    return true;
}

pub fn assignMove(world: *state.World, unit_index: usize, destination: state.Position) bool {
    if (unit_index >= world.units.len or destination.x >= world.map_width or destination.y >= world.map_height) return false;
    const unit = &world.units[unit_index];
    if (!unit.active or !isDrivable(unit.kind)) return false;
    unit.mission = mission_move;
    unit.status = 0;
    unit.harvesting = false;
    unit.mission_timer_due = world.frame;
    setDestination(unit, destination);
    return true;
}

pub fn assignHarvest(world: *state.World, unit_index: usize, destination: state.Position) bool {
    if (unit_index >= world.units.len or !world.hasTiberium(destination)) return false;
    const unit = &world.units[unit_index];
    if (!unit.active or unit.kind != .harvester) return false;
    unit.mission = mission_harvest;
    unit.status = harvesting;
    unit.harvesting = false;
    unit.mission_timer_due = world.frame;
    unit.archive_destination_valid = false;
    setDestination(unit, destination);
    return true;
}

pub fn assignReturn(world: *state.World, unit_index: usize, refinery_index: usize) bool {
    if (unit_index >= world.units.len or refinery_index >= world.buildings.len) return false;
    const unit = &world.units[unit_index];
    const refinery = world.buildings[refinery_index];
    if (!unit.active or unit.kind != .harvester or !refinery.active or !refinery.operational or
        refinery.kind != .refinery or refinery.owner != unit.owner)
    {
        return false;
    }
    unit.home_refinery = @intCast(refinery_index);
    unit.mission = mission_enter;
    unit.status = 0;
    unit.harvesting = false;
    unit.mission_timer_due = world.frame;
    setDestination(unit, refineryApproach(refinery));
    return true;
}

fn tickHarvester(world: *state.World, unit_index: usize) void {
    const unit = &world.units[unit_index];
    if (unit.path_delay != 0) unit.path_delay -= 1;
    if (unit.harvest_timer != 0) unit.harvest_timer -= 1;
    if (unit.docking_phase != 0) {
        tickDocking(world, unit_index);
        if (unit.docking_phase == docking_exit and world.frame >= unit.mission_timer_due) {
            const delay = tickHarvestMission(world, unit_index);
            unit.mission_timer_due = world.frame + delay;
        }
        return;
    }

    if (world.frame >= unit.mission_timer_due) {
        const delay = switch (unit.mission) {
            mission_move => tickMoveMission(unit),
            mission_enter => tickEnterMission(world, unit_index),
            mission_harvest => tickHarvestMission(world, unit_index),
            else => rules.ticks_per_second,
        };
        unit.mission_timer_due = world.frame + delay;
        if (unit.docking_phase != 0) return;
    }

    if (unit.moving) {
        advanceMovement(world, unit_index);
    } else if (unit.destination_valid) {
        startMovement(world, unit_index, true);
    }
}

fn tickMoveMission(unit: *state.Unit) u32 {
    if (!unit.destination_valid or same(unit.position, unit.destination)) {
        unit.destination_valid = false;
        unit.mission = mission_guard;
    }
    return rules.ticks_per_second;
}

fn tickHarvestMission(world: *state.World, unit_index: usize) u32 {
    const unit = &world.units[unit_index];
    switch (unit.status) {
        looking => {
            if (unit.destination_valid) {
                return rules.ticks_per_second;
            }
            if (world.hasTiberium(unit.position)) {
                unit.status = harvesting;
                unit.harvesting = true;
                unit.archive_destination = unit.position;
                unit.archive_destination_valid = true;
                return 1;
            }
            if (findTiberium(world, unit_index)) |destination| {
                setDestination(unit, destination);
            } else if (unit.cargo_steps != 0) {
                unit.status = find_home;
            } else {
                unit.mission = mission_guard;
            }
            return rules.ticks_per_second;
        },
        harvesting => {
            if (unit.destination_valid or unit.moving or unit.harvest_timer != 0) {
                return rules.ticks_per_second;
            }
            const level = world.tiberiumAt(unit.position);
            if (unit.cargo_steps < rules.harvester_capacity_steps and world.hasTiberium(unit.position)) {
                unit.harvesting = true;
                const requested: u8 = level % 6 + 1;
                const remaining = rules.harvester_capacity_steps - unit.cargo_steps;
                const removed = world.reduceTiberium(unit.position, @min(requested, remaining));
                unit.cargo_steps += removed;
                unit.harvest_timer = rules.harvest_interval_frames - 1;
                return rules.ticks_per_second;
            }
            unit.harvesting = false;
            if (unit.cargo_steps == rules.harvester_capacity_steps) {
                unit.status = find_home;
            } else if (findTiberium(world, unit_index)) |destination| {
                setDestination(unit, destination);
                unit.harvesting = true;
            } else {
                unit.status = find_home;
            }
            return 1;
        },
        find_home => {
            const refinery_index = bestRefinery(world, unit.owner, unit.home_refinery) orelse {
                unit.mission = mission_guard;
                return rules.ticks_per_second;
            };
            unit.home_refinery = @intCast(refinery_index);
            unit.status = heading_home;
            return rules.ticks_per_second;
        },
        heading_home => {
            unit.mission = mission_enter;
            unit.status = 0;
            return 1;
        },
        else => {
            unit.status = looking;
            return rules.ticks_per_second;
        },
    }
}

fn tickEnterMission(world: *state.World, unit_index: usize) u32 {
    const retry_delay = rules.ticks_per_second / 2;
    const unit = &world.units[unit_index];
    const refinery_index = bestRefinery(world, unit.owner, unit.home_refinery) orelse {
        unit.mission = mission_guard;
        return retry_delay;
    };
    const refinery = world.buildings[refinery_index];
    const approach = refineryApproach(refinery);
    if (!same(unit.position, approach)) {
        if (!unit.destination_valid) setDestination(unit, approach);
        return retry_delay;
    }
    const approach_x = @as(i16, approach.x) * 256 + 128;
    const approach_y = @as(i16, approach.y) * 256 + 128;
    if (unit.moving or unit.coord_x != approach_x or unit.coord_y != approach_y) {
        return retry_delay;
    }
    unit.destination_valid = false;
    unit.docking_phase = docking_wait;
    unit.docking_timer = 0;
    tickDocking(world, unit_index);
    return retry_delay;
}

fn tickDocking(world: *state.World, unit_index: usize) void {
    const unit = &world.units[unit_index];
    switch (unit.docking_phase) {
        docking_wait => {
            if (unit.docking_timer != 0) {
                unit.docking_timer -= 1;
                if (unit.docking_timer != 0) return;
            }
            if (unit.facing != 160) {
                unit.facing = rotateFacing(unit.facing, 160, 5);
                return;
            }
            const refinery_index = bestRefinery(world, unit.owner, unit.home_refinery) orelse {
                cancelDocking(unit);
                return;
            };
            const dock = refineryDock(world.buildings[refinery_index]);
            unit.docking_phase = docking_backup;
            startSpecialTrack(unit, dock, 64);
            advanceSpecialTrack(world, unit_index);
        },
        docking_backup, docking_exit => advanceSpecialTrack(world, unit_index),
        docking_unload => {
            if (unit.docking_timer != 0) {
                unit.docking_timer -= 1;
                if (unit.docking_timer != 0) return;
            }
            if (unit.cargo_steps != 0) {
                unit.cargo_steps -= 1;
                creditTiberium(world, unit.owner);
                unit.docking_timer = 20;
                return;
            }
            const refinery_index = bestRefinery(world, unit.owner, unit.home_refinery) orelse {
                cancelDocking(unit);
                return;
            };
            const approach = refineryApproach(world.buildings[refinery_index]);
            unit.docking_phase = docking_exit;
            unit.logic_after_infantry = true;
            unit.mission = mission_harvest;
            unit.status = looking;
            unit.harvesting = false;
            unit.mission_timer_due = world.frame + rules.ticks_per_second;
            if (findTiberium(world, unit_index)) |destination| {
                unit.destination = destination;
                unit.destination_valid = true;
                clearPath(unit);
            }
            startSpecialTrack(unit, approach, 65);
            applySpecialPoint(unit, tracks.refinery_exit[0]);
            unit.track_index = 1;
            unit.movement_accum = 1;
            unit.docking_timer = 1;
        },
        else => cancelDocking(unit),
    }
}

fn startSpecialTrack(unit: *state.Unit, head: state.Position, track_number: i8) void {
    unit.head_coord_x = @as(i16, head.x) * 256 + 128;
    unit.head_coord_y = @as(i16, head.y) * 256 + 128;
    unit.movement_accum = 0;
    unit.track_number = track_number;
    unit.track_index = 0;
    unit.speed = 128;
    unit.moving = true;
}

fn advanceSpecialTrack(world: *state.World, unit_index: usize) void {
    const unit = &world.units[unit_index];
    if (unit.docking_phase == docking_exit and unit.docking_timer != 0) {
        unit.docking_timer -= 1;
        return;
    }
    const points = if (unit.docking_phase == docking_backup)
        tracks.refinery_backup[0..]
    else
        tracks.refinery_exit[0..];
    const max_speed = difficulty.groundSpeed(world, unit.owner, rules.object(unit.kind).?.max_speed);
    var actual = unit.movement_accum + fixedToCardinal(max_speed, unit.speed);
    while (actual > 10) {
        actual -= 10;
        const point = points[unit.track_index];
        if (point.offset == 0 and unit.track_index != 0) {
            unit.coord_x = unit.head_coord_x;
            unit.coord_y = unit.head_coord_y;
            unit.position = positionFor(unit.coord_x, unit.coord_y);
            unit.head_coord_x = 0;
            unit.head_coord_y = 0;
            unit.movement_accum = 0;
            unit.track_number = -1;
            unit.track_index = 0;
            unit.speed = 0;
            unit.moving = false;
            if (unit.docking_phase == docking_backup) {
                unit.docking_phase = docking_unload;
                unit.docking_timer = 40;
                unit.path_facing = 4;
            } else {
                unit.docking_phase = 0;
                unit.docking_timer = 0;
                unit.path_facing = 3;
                if (unit.archive_destination_valid) {
                    unit.destination = unit.archive_destination;
                    unit.destination_valid = true;
                    unit.archive_destination_valid = false;
                    clearPath(unit);
                }
            }
            return;
        }
        applySpecialPoint(unit, point);
        unit.track_index += 1;
    }
    unit.movement_accum = actual;
}

fn applySpecialPoint(unit: *state.Unit, point: tracks.Point) void {
    const x: i16 = @bitCast(@as(u16, @truncate(point.offset)));
    const y: i16 = @bitCast(@as(u16, @truncate(point.offset >> 16)));
    unit.coord_x = unit.head_coord_x + x;
    unit.coord_y = unit.head_coord_y + y;
    unit.position = positionFor(unit.coord_x, unit.coord_y);
    unit.facing = point.facing;
}

fn creditTiberium(world: *state.World, owner: state.Owner) void {
    const amount: u16 = if (owner == .player)
        rules.player_tiberium_step_credits
    else
        rules.ai_tiberium_step_credits;
    const player = &world.players[@intFromEnum(owner)];
    player.harvested_credits +|= amount;
    player.tiberium = @min(player.capacity, player.tiberium + amount);
}

fn cancelDocking(unit: *state.Unit) void {
    unit.docking_phase = 0;
    unit.docking_timer = 0;
    unit.mission = mission_guard;
    stopTrack(unit);
}

fn findTiberium(world: *state.World, unit_index: usize) ?state.Position {
    const center = world.units[unit_index].position;
    if (world.hasTiberium(center)) return center;
    for (1..64) |radius_usize| {
        const radius: i16 = @intCast(radius_usize);
        var best: ?state.Position = null;
        var best_tiberium: u8 = 0;
        var x: i16 = -radius;
        while (x <= radius) : (x += 1) {
            var corners = [4][2]i16{
                .{ x, -radius },
                .{ x, radius },
                .{ -radius, x },
                .{ radius, x },
            };
            for (0..3) |shuffle_index| {
                const divisor = @divTrunc(0x7fff, @as(i32, @intCast(4 - shuffle_index))) + 1;
                const offset: usize = @intCast(@divTrunc(random.pick(&world.rng_state, 0, 0x7fff), divisor));
                const other = shuffle_index + offset;
                const swap = corners[other];
                corners[other] = corners[shuffle_index];
                corners[shuffle_index] = swap;
            }
            for (corners) |corner| {
                const candidate = offsetPosition(world, center, corner[0], corner[1]) orelse continue;
                const amount = tiberiumCheck(world, unit_index, candidate);
                if (amount > best_tiberium) {
                    best = candidate;
                    best_tiberium = amount;
                }
            }
        }
        if (best) |destination| return destination;
    }
    return null;
}

fn tiberiumCheck(world: *const state.World, unit_index: usize, position: state.Position) u8 {
    if (!world.hasTiberium(position) or cellOccupiedExcept(world, position, unit_index)) return 0;
    const amount = world.tiberiumAt(position);
    return amount +| 1;
}

fn startMovement(world: *state.World, unit_index: usize, apply_rotation: bool) void {
    const unit = &world.units[unit_index];
    if (!unit.destination_valid or same(unit.position, unit.destination)) {
        stopTrack(unit);
        return;
    }
    if (unit.path[0] == no_path) {
        if (unit.path_delay != 0) return;
        if (!pathfinder.findVehicle(world, unit.owner, unit.position, unit.destination, &unit.path)) {
            unit.path_delay = path_delay_frames;
            scatterFailedPathBlocker(world, unit_index);
            return;
        }
        unit.path_delay = path_delay_frames;
    }
    const facing = unit.path[0];
    if (facing == no_path) return;

    const desired: u8 = @intCast(@as(u8, @bitCast(facing)) * 32);
    if (unit.facing != desired) {
        if (apply_rotation) unit.facing = rotateFacing(unit.facing, desired, 5);
        unit.movement_accum = 0;
        unit.speed = 0;
        return;
    }

    const next_facing = if (unit.path[1] == no_path) facing else unit.path[1];
    const control_index: usize = @as(usize, @intCast(facing)) * 8 + @as(usize, @intCast(next_facing));
    const control = tracks.controls[control_index];
    if (control.track == 0) {
        clearPath(unit);
        return;
    }

    var head = adjacent(unit.position, facing) orelse {
        clearPath(unit);
        return;
    };
    if (scatterStationaryAlliedInfantry(world, unit_index, head)) return;

    var consumed: usize = 1;
    if (control.flags & tracks.flag_double != 0) {
        head = adjacent(head, next_facing) orelse {
            clearPath(unit);
            return;
        };
        if (scatterStationaryAlliedInfantry(world, unit_index, head)) return;
        consumed = 2;
    }

    unit.head_coord_x = @as(i16, head.x) * 256 + 128;
    unit.head_coord_y = @as(i16, head.y) * 256 + 128;
    unit.track_number = @intCast(control_index);
    unit.track_index = 0;
    unit.speed = 160;
    unit.moving = true;
    shiftPathBy(unit, consumed);
    unit.path_facing = unit.path[0];
    advanceMovement(world, unit_index);
}

fn advanceMovement(world: *state.World, unit_index: usize) void {
    const unit = &world.units[unit_index];
    if (!unit.moving or unit.track_number < 0) {
        unit.movement_accum = 0;
        return;
    }

    const max_speed = difficulty.groundSpeed(world, unit.owner, rules.object(unit.kind).?.max_speed);
    var actual = unit.movement_accum + fixedToCardinal(max_speed, unit.speed);
    while (actual > 10) {
        actual -= 10;
        const control = tracks.controls[@intCast(unit.track_number)];
        const raw = tracks.raw_tracks[control.track - 1];
        const point = raw.points[unit.track_index];
        if (point.offset == 0 and unit.track_index != 0) {
            unit.coord_x = unit.head_coord_x;
            unit.coord_y = unit.head_coord_y;
            unit.position = positionFor(unit.coord_x, unit.coord_y);
            actual = 0;
            stopTrack(unit);
            if (same(unit.position, unit.destination)) {
                unit.destination_valid = false;
                clearPath(unit);
            } else {
                startMovement(world, unit_index, false);
            }
            return;
        }

        const transformed = smoothTurn(point, control, unit.head_coord_x, unit.head_coord_y);
        unit.coord_x = transformed.x;
        unit.coord_y = transformed.y;
        unit.facing = transformed.facing;
        unit.position = positionFor(unit.coord_x, unit.coord_y);
        if (raw.jump >= 0 and unit.track_index == @as(u8, @intCast(raw.jump)) and unit.path[0] != no_path) {
            const completed_facing: i8 = @intCast(control.facing >> 5);
            const next_facing = unit.path[0];
            if (completed_facing != next_facing) {
                const next_control_index: usize =
                    @as(usize, @intCast(completed_facing)) * 8 + @as(usize, @intCast(next_facing));
                const next_control = tracks.controls[next_control_index];
                if (next_control.track != 0) {
                    const next_raw = tracks.raw_tracks[next_control.track - 1];
                    if (next_raw.entry != 0) {
                        const prior_head = positionFor(unit.head_coord_x, unit.head_coord_y);
                        if (adjacent(prior_head, next_facing)) |next_head| {
                            unit.head_coord_x = @as(i16, next_head.x) * 256 + 128;
                            unit.head_coord_y = @as(i16, next_head.y) * 256 + 128;
                            unit.track_number = @intCast(next_control_index);
                            unit.track_index = next_raw.entry;
                            shiftPathBy(unit, 1);
                            unit.path_facing = unit.path[0];
                            continue;
                        }
                    }
                }
            }
        }
        unit.track_index += 1;
    }
    unit.movement_accum = actual;
}

fn setDestination(unit: *state.Unit, destination: state.Position) void {
    unit.destination = destination;
    unit.destination_valid = true;
    unit.docking_phase = 0;
    unit.docking_timer = 0;
    stopTrack(unit);
    clearPath(unit);
}

fn clearPath(unit: *state.Unit) void {
    unit.path = [_]i8{no_path} ** unit.path.len;
    unit.path_facing = no_path;
}

fn shiftPathBy(unit: *state.Unit, count: usize) void {
    std.debug.assert(count <= unit.path.len);
    for (0..unit.path.len - count) |index| unit.path[index] = unit.path[index + count];
    @memset(unit.path[unit.path.len - count ..], no_path);
}

fn stopTrack(unit: *state.Unit) void {
    unit.head_coord_x = 0;
    unit.head_coord_y = 0;
    unit.movement_accum = 0;
    unit.track_number = -1;
    unit.track_index = 0;
    unit.speed = 0;
    unit.moving = false;
}

fn smoothTurn(
    point: tracks.Point,
    control: tracks.Control,
    head_x: i16,
    head_y: i16,
) struct { x: i16, y: i16, facing: u8 } {
    var x: i16 = @bitCast(@as(u16, @truncate(point.offset)));
    var y: i16 = @bitCast(@as(u16, @truncate(point.offset >> 16)));
    var facing = point.facing;
    if (control.flags & tracks.flag_transpose != 0) {
        const swap = x;
        x = y;
        y = swap;
        facing = 192 -% facing;
    }
    if (control.flags & tracks.flag_reverse_x != 0) {
        x = -x;
        facing = 0 -% facing;
    }
    if (control.flags & tracks.flag_reverse_y != 0) {
        y = -y;
        facing = 128 -% facing;
    }
    return .{
        .x = head_x + x,
        .y = head_y + y,
        .facing = facing,
    };
}

fn rotateFacing(current: u8, desired: u8, rate: u8) u8 {
    const difference: i8 = @bitCast(desired -% current);
    if (difference == 0) return current;
    const magnitude: u8 = @intCast(if (difference < 0) -@as(i16, difference) else difference);
    if (magnitude < rate) return desired;
    return if (difference < 0) current -% rate else current +% rate;
}

fn fixedToCardinal(base: u8, fixed: u8) u16 {
    return (@as(u16, base) * @as(u16, fixed) + 128) >> 8;
}

fn positionFor(x: i16, y: i16) state.Position {
    return .{
        .x = @intCast(@divFloor(x, 256)),
        .y = @intCast(@divFloor(y, 256)),
    };
}

fn bestRefinery(world: *const state.World, owner: state.Owner, preferred: u16) ?usize {
    if (preferred < world.buildings.len) {
        const building = world.buildings[preferred];
        if (building.active and building.operational and building.health > 0 and building.owner == owner and
            building.kind == .refinery)
        {
            return preferred;
        }
    }
    for (world.buildings, 0..) |building, index| {
        if (building.active and building.operational and building.health > 0 and building.owner == owner and
            building.kind == .refinery)
        {
            return index;
        }
    }
    return null;
}

fn unitIndexByActorSlot(world: *const state.World, owner: state.Owner, slot: u8) ?usize {
    var candidate: u8 = 0;
    for (world.units, 0..) |unit, index| {
        if (!unit.active or unit.owner != owner) continue;
        if (candidate == slot) return if (isDrivable(unit.kind)) index else null;
        candidate +|= 1;
    }
    return null;
}

fn buildingIndexByOwnerSlot(world: *const state.World, owner: state.Owner, slot: u8) ?usize {
    var candidate: u8 = 0;
    for (world.units) |unit| {
        if (!unit.active or unit.owner != owner) continue;
        if (candidate == slot) return null;
        candidate +|= 1;
    }
    for (world.buildings, 0..) |building, index| {
        if (!building.active or building.owner != owner) continue;
        if (candidate == slot) return index;
        candidate +|= 1;
    }
    return null;
}

fn refineryDock(building: state.Building) state.Position {
    return .{ .x = building.position.x, .y = building.position.y +| 1 };
}

fn refineryApproach(building: state.Building) state.Position {
    return .{ .x = building.position.x, .y = building.position.y +| 2 };
}

fn nearestFreeCell(world: *const state.World, preferred: state.Position) ?state.Position {
    if (preferred.x < world.map_width and preferred.y < world.map_height and
        !cellOccupiedExcept(world, preferred, std.math.maxInt(usize)))
    {
        return preferred;
    }
    for (1..8) |radius_usize| {
        const radius: i16 = @intCast(radius_usize);
        var y: i16 = -radius;
        while (y <= radius) : (y += 1) {
            var x: i16 = -radius;
            while (x <= radius) : (x += 1) {
                if (@abs(x) != radius and @abs(y) != radius) continue;
                const candidate = offsetPosition(world, preferred, x, y) orelse continue;
                if (!cellOccupiedExcept(world, candidate, std.math.maxInt(usize))) return candidate;
            }
        }
    }
    return null;
}

fn cellOccupiedExcept(world: *const state.World, position: state.Position, ignored_unit: usize) bool {
    for (world.units, 0..) |unit, index| {
        if (index == ignored_unit or !unit.active or unit.health <= 0) continue;
        if (same(unit.position, position)) return true;
    }
    for (world.buildings) |building| {
        if (!building.active or building.health <= 0) continue;
        if (buildingOccupies(building, position)) return true;
    }
    for (world.infantry) |infantry| {
        if (infantry.active and infantry.health > 0 and same(infantry.position, position)) return true;
    }
    return false;
}

fn hasStationaryAlliedInfantry(world: *const state.World, owner: state.Owner, position: state.Position) bool {
    for (world.infantry) |infantry| {
        if (!infantry.active or infantry.health <= 0 or infantry.owner != owner or !same(infantry.position, position)) continue;
        if (!infantry.destination_valid and !infantry.moving) return true;
    }
    return false;
}

fn scatterStationaryAlliedInfantry(world: *state.World, unit_index: usize, position: state.Position) bool {
    const owner = world.units[unit_index].owner;
    if (!hasStationaryAlliedInfantry(world, owner, position)) return false;

    movement.scatterInfantryAt(world, owner, position);
    const unit = &world.units[unit_index];
    unit.movement_accum = 0;
    unit.speed = 0;
    unit.track_number = -1;
    clearPath(unit);
    return true;
}

fn scatterFailedPathBlocker(world: *state.World, unit_index: usize) void {
    const unit = world.units[unit_index];
    const facing: i8 = @intCast(unit.facing >> 5);
    const position = adjacent(unit.position, facing) orelse return;
    if (!hasStationaryAlliedInfantry(world, unit.owner, position)) return;
    movement.scatterInfantryAt(world, unit.owner, position);
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

fn adjacent(position: state.Position, direction: i8) ?state.Position {
    if (direction < 0) return null;
    const x_delta = [_]i8{ 0, 1, 1, 1, 0, -1, -1, -1 };
    const y_delta = [_]i8{ -1, -1, 0, 1, 1, 1, 0, -1 };
    const index: usize = @intCast(direction & 7);
    const x = @as(i16, position.x) + x_delta[index];
    const y = @as(i16, position.y) + y_delta[index];
    if (x < 0 or y < 0 or x >= 64 or y >= 64) return null;
    return .{ .x = @intCast(x), .y = @intCast(y) };
}

fn offsetPosition(world: *const state.World, origin: state.Position, dx: i16, dy: i16) ?state.Position {
    const x = @as(i16, origin.x) + dx;
    const y = @as(i16, origin.y) + dy;
    if (x < 0 or y < 0 or x >= world.map_width or y >= world.map_height) return null;
    return .{ .x = @intCast(x), .y = @intCast(y) };
}

fn same(a: state.Position, b: state.Position) bool {
    return a.x == b.x and a.y == b.y;
}
