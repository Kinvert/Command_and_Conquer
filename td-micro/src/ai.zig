const action = @import("action.zig");
const combat = @import("combat.zig");
const input = @import("input.zig");
const movement = @import("movement.zig");
const placement = @import("placement.zig");
const production = @import("production.zig");
const random = @import("random.zig");
const rules = @import("rules.zig");
const state = @import("state.zig");

const mission_guard: i8 = 4;
const mission_guard_area: i8 = 9;
const mission_hunt: i8 = 13;
const mission_unload: i8 = 15;
const state_buildup: i8 = 0;
const state_attacked: i8 = 3;
const cell_leptons: i32 = 256;
const minimum_base_radius: i32 = 2 * cell_leptons;
const ticks_per_minute: u32 = 900;
const attack_interval: u32 = 3;

pub fn unitPhase(world: *state.World) ?action.Action {
    if (!world.easy_ai.active) return null;

    for (&world.units) |*unit| {
        if (!unit.active or unit.owner != .opponent or unit.kind != .mcv or unit.mission != mission_guard or unit.deploying) continue;

        // UnitClass::Mission_Guard rolls its next delay even though MISSION_UNLOAD replaces guard.
        _ = random.pick(&world.rng_state, 0, 2);
        const command: action.Action = .{ .command = .deploy, .actor = 0 };
        if (!input.applyAI(world, .opponent, command)) return null;
        unit.mission = mission_unload;
        return command;
    }
    return null;
}

pub fn housePhase(world: *state.World) void {
    const ai = &world.easy_ai;
    if (!ai.active) return;

    ai.started = true;
    ai.alerted = true;

    if (ai.alert_timer == 0) {
        _ = random.pick(&world.rng_state, 2, 3);
        ai.alert_timer = @as(u32, @intCast(random.pick(&world.rng_state, 5, 20))) * 900;
    }
    if (ai.ai_timer == 0) expertAI(world);
    chooseStructure(world);
    chooseInfantry(world);
}

pub fn factoryPhase(world: *state.World) ?action.Action {
    if (!world.easy_ai.active) return null;

    _ = production.releaseCompletedInfantry(world, .opponent);
    const queue = world.queues[@intFromEnum(state.Owner.opponent)][@intFromEnum(state.QueueKind.infantry)];
    var emitted: ?action.Action = null;
    if (!queue.active and world.easy_ai.build_infantry != .none) {
        const command: action.Action = .{ .command = .train, .product = world.easy_ai.build_infantry };
        if (input.applyAI(world, .opponent, command)) {
            world.easy_ai.build_infantry = .none;
            emitted = command;
        }
    }
    return emitted;
}

pub fn initializeReleasedInfantry(world: *state.World) void {
    if (world.infantry_count == 0) return;
    const infantry = &world.infantry[world.infantry_count - 1];

    // The newly inserted infantry receives its first object-AI pass before HouseClass::AI.
    combat.randomAnimateStanding(world, infantry);
    const mission_delay = random.pick(&world.rng_state, 0, 4);
    infantry.mission = mission_guard_area;
    infantry.mission_timer_due = world.frame + 15 + @as(u32, @intCast(mission_delay));
    infantry.command_delay = 0;
}

fn expertAI(world: *state.World) void {
    const ai = &world.easy_ai;
    if (ai.has_center and ai.attack_timer == 0) {
        // The TDMicro policy house remains human and never enters HouseClass::IsStarted.
        // Expert_AI therefore stops before counting its infantry, but still applies the
        // stock minimum headroom after the empty candidate scan.
        ai.max_infantry = @max(ai.max_infantry, 10);
    }

    if (ai.state == state_attacked and ticks_per_minute < world.frame) {
        ai.state = state_buildup;
    } else if (ai.state != state_attacked and ticks_per_minute > world.frame) {
        ai.state = state_attacked;
    }

    if (world.frame > ticks_per_minute and ai.attack_timer == 0) {
        aiAttack(world);
    }
    const delay_pick = random.pick(&world.rng_state, 1, 7);
    ai.ai_timer = @intCast(75 + delay_pick);
}

fn aiAttack(world: *state.World) void {
    const shuffle = !percentChance(world, 33);
    for (&world.units) |*unit| {
        if (!unit.active or unit.owner != .opponent or unit.health == 0 or unit.docking_phase != 0) continue;

        // Supported vehicles are unarmed, so Westwood's fallback shuffle path applies.
        if (percentChance(world, 20) and unit.mission == mission_guard_area and insideBaseZone(world, unit.position)) {
            const zone: u8 = @intCast(random.pick(&world.rng_state, 1, 4));
            if (randomCellInZone(world, zone)) |position| {
                unit.archive_destination = position;
                unit.archive_destination_valid = true;
            }
        }
    }
    for (&world.infantry) |*infantry| {
        if (!infantry.active or infantry.owner != .opponent or infantry.health == 0) continue;

        if (!shuffle and percentChance(world, 75)) {
            infantry.queued_mission = mission_hunt;
        } else if (percentChance(world, 20) and infantry.mission == mission_guard_area and insideBaseZone(world, infantry.position)) {
            const zone: u8 = @intCast(random.pick(&world.rng_state, 1, 4));
            if (randomCellInZone(world, zone)) |position| {
                infantry.home = position;
                infantry.home_valid = true;
            }
        }
    }
    world.easy_ai.attack_timer = @intCast(attack_interval * @as(u32, @intCast(random.pick(&world.rng_state, 450, 1800))));
}

fn percentChance(world: *state.World, percent: i32) bool {
    return random.pick(&world.rng_state, 0, 99) < percent;
}

fn chooseInfantry(world: *state.World) void {
    if (world.easy_ai.build_infantry != .none) return;

    var count: u16 = 0;
    for (world.infantry) |infantry| {
        if (infantry.active and infantry.owner == .opponent) count += 1;
    }
    const queue = world.queues[@intFromEnum(state.Owner.opponent)][@intFromEnum(state.QueueKind.infantry)];
    if (queue.active) count += 1;
    if (count >= world.easy_ai.max_infantry) return;

    const pick = random.pick(&world.rng_state, 0, 4);
    world.easy_ai.build_infantry = if (pick < 3) .e1 else .e3;
}

fn hasPlacedBuilding(world: *const state.World, kind: rules.ObjectType) bool {
    for (world.buildings) |building| {
        if (building.active and building.owner == .opponent and building.kind == kind) return true;
    }
    return false;
}

pub fn buildingPhase(world: *state.World, commands: *[2]action.Action) usize {
    if (!world.easy_ai.active) return 0;

    var count: usize = 0;
    const queue = &world.queues[@intFromEnum(state.Owner.opponent)][@intFromEnum(state.QueueKind.structure)];
    if (queue.active and queue.completed) {
        const product = queue.product;
        const position = findBuildLocation(world, product) orelse return count;
        const command: action.Action = .{
            .command = .place,
            .product = product,
            .target_kind = .cell,
            .target_x = position.x,
            .target_y = position.y,
        };
        if (input.applyAI(world, .opponent, command)) {
            commands[count] = command;
            count += 1;
            recalcBase(world);
        }
    }

    const refreshed_queue = &world.queues[@intFromEnum(state.Owner.opponent)][@intFromEnum(state.QueueKind.structure)];
    if (!refreshed_queue.active and world.easy_ai.build_structure != .none) {
        const product = world.easy_ai.build_structure;
        const command: action.Action = .{ .command = .start_build, .product = product };
        if (input.applyAI(world, .opponent, command)) {
            commands[count] = command;
            count += 1;
            world.easy_ai.build_structure = .none;
            chooseStructure(world);
        }
    }
    return count;
}

pub fn finishFrame(world: *state.World) void {
    const ai = &world.easy_ai;
    if (!ai.active) return;
    if (ai.ai_timer != 0) ai.ai_timer -= 1;
    if (ai.alert_timer != 0) ai.alert_timer -= 1;
    if (ai.attack_timer != 0) ai.attack_timer -= 1;
    if (ai.base_dirty) recalcBase(world);
}

fn chooseStructure(world: *state.World) void {
    if (world.easy_ai.build_structure != .none) return;
    if (!hasStructureOrProduct(world, .power_plant)) {
        world.easy_ai.build_structure = .power_plant;
        return;
    }

    const needs_refinery = !hasStructureOrProduct(world, .refinery);
    const needs_barracks = !hasStructureOrProduct(world, .barracks);
    if (needs_refinery and needs_barracks) {
        // Vanilla gives both first-tech structures URGENCY_HIGH and breaks the tie with Random_Pick.
        world.easy_ai.build_structure = if (random.pick(&world.rng_state, 0, 1) == 0)
            .refinery
        else
            .barracks;
    } else if (needs_refinery) {
        world.easy_ai.build_structure = .refinery;
    } else if (needs_barracks) {
        world.easy_ai.build_structure = .barracks;
    }
}

fn hasStructureOrProduct(world: *const state.World, kind: rules.ObjectType) bool {
    for (world.buildings) |building| {
        if (building.active and building.owner == .opponent and building.kind == kind) return true;
    }
    const queue = world.queues[@intFromEnum(state.Owner.opponent)][@intFromEnum(state.QueueKind.structure)];
    return queue.active and queue.product == kind;
}

fn recalcBase(world: *state.World) void {
    var weighted_x: i32 = 0;
    var weighted_y: i32 = 0;
    var total_weight: i32 = 0;
    for (world.buildings[0..world.building_count]) |building| {
        if (!building.active or building.owner != .opponent or building.health <= 0) continue;
        const object_rule = rules.object(building.kind) orelse continue;
        const weight = @divTrunc(object_rule.cost, 1000) + 1;
        const center = buildingCenter(building);
        weighted_x += center.x * weight;
        weighted_y += center.y * weight;
        total_weight += weight;
    }

    const ai = &world.easy_ai;
    ai.base_dirty = false;
    if (total_weight == 0) {
        ai.has_center = false;
        ai.center_x = 0;
        ai.center_y = 0;
        ai.radius = 0;
        return;
    }

    const center_x = @divTrunc(weighted_x, total_weight);
    const center_y = @divTrunc(weighted_y, total_weight);
    ai.has_center = true;
    ai.center_x = @intCast(center_x);
    ai.center_y = @intCast(center_y);

    var radius: i32 = 0;
    for (world.buildings[0..world.building_count]) |building| {
        if (!building.active or building.owner != .opponent or building.health <= 0) continue;
        const center = buildingCenter(building);
        radius += distance(center_x - center.x, center_y - center.y);
    }
    ai.radius = @intCast(@max(minimum_base_radius, @divTrunc(radius, total_weight)));
}

const Coord = struct { x: i32, y: i32 };

fn buildingCenter(building: state.Building) Coord {
    const offset = switch (building.kind) {
        .construction_yard => Coord{ .x = 384, .y = 255 },
        .power_plant, .barracks => Coord{ .x = 255, .y = 255 },
        .refinery => Coord{ .x = 384, .y = 384 },
        else => Coord{ .x = 128, .y = 128 },
    };
    return .{
        .x = @as(i32, building.position.x) * cell_leptons + offset.x,
        .y = @as(i32, building.position.y) * cell_leptons + offset.y,
    };
}

fn findBuildLocation(world: *state.World, product: rules.ObjectType) ?state.Position {
    if (!world.easy_ai.has_center) return null;
    const zone: u8 = @intCast(random.pick(&world.rng_state, 0, 4));
    const sample = randomCellInZone(world, zone) orelse return null;
    var best: ?state.Position = null;
    var best_distance: i32 = std.math.maxInt(i32);
    for (0..world.map_height) |y| {
        for (0..world.map_width) |x| {
            const candidate: state.Position = .{ .x = @intCast(x), .y = @intCast(y) };
            if (!insideBaseZone(world, candidate) or !placement.isLegal(world, .opponent, product, candidate)) continue;
            const candidate_distance = cellDistance(candidate, sample);
            if (candidate_distance < best_distance) {
                best = candidate;
                best_distance = candidate_distance;
            }
        }
    }
    return best;
}

const std = @import("std");

fn randomCellInZone(world: *state.World, zone: u8) ?state.Position {
    const ai = world.easy_ai;
    const radius: i32 = ai.radius;
    var coord: ?Coord = null;
    switch (zone) {
        0 => coord = scatterCore(world),
        1 => {
            const maximum = @min(radius * 3, @as(i32, ai.center_y) - cell_leptons);
            if (maximum >= 0) coord = scatterEdge(world, 0, 64, maximum, -32);
        },
        2 => {
            const edge = @as(i32, world.map_width) * cell_leptons;
            const maximum = @min(radius * 3, edge - @as(i32, ai.center_x) - cell_leptons);
            if (maximum >= 0) coord = scatterEdge(world, 32, 96, maximum, 0);
        },
        3 => {
            const edge = @as(i32, world.map_height) * cell_leptons;
            const maximum = @min(radius * 3, edge - @as(i32, ai.center_y) - cell_leptons);
            if (maximum >= 0) coord = scatterEdge(world, 96, 160, maximum, 0);
        },
        4 => {
            const maximum = @min(radius * 3, @as(i32, ai.center_x) - cell_leptons);
            if (maximum >= 0) coord = scatterEdge(world, 160, 224, maximum, 0);
        },
        else => return null,
    }
    if (coord == null) coord = scatterCore(world);
    const selected = coord orelse return null;
    if (!coordInMap(world, selected)) {
        if (zone != 0) return randomCellInZone(world, 0);
        return .{
            .x = @intCast(@divFloor(@as(i32, ai.center_x), cell_leptons)),
            .y = @intCast(@divFloor(@as(i32, ai.center_y), cell_leptons)),
        };
    }
    const x = @divFloor(selected.x, cell_leptons);
    const y = @divFloor(selected.y, cell_leptons);
    return .{
        .x = @intCast(std.math.clamp(x, 0, @as(i32, world.map_width) - 1)),
        .y = @intCast(std.math.clamp(y, 0, @as(i32, world.map_height) - 1)),
    };
}

fn coordInMap(world: *const state.World, coord: Coord) bool {
    return coord.x >= 0 and coord.y >= 0 and
        coord.x < @as(i32, world.map_width) * cell_leptons and
        coord.y < @as(i32, world.map_height) * cell_leptons;
}

fn scatterCore(world: *state.World) Coord {
    const ai = world.easy_ai;
    const radius: u16 = @intCast(random.pick(&world.rng_state, 0, ai.radius));
    const direction: u8 = @intCast(random.pick(&world.rng_state, 0, 254));
    return moveCoord(ai.center_x, ai.center_y, direction, radius);
}

fn scatterEdge(world: *state.World, first: i32, last: i32, maximum: i32, direction_adjustment: i32) Coord {
    const ai = world.easy_ai;
    const minimum_distance = @min(@as(i32, ai.radius) * 2, maximum);
    const maximum_distance = @min(@as(i32, ai.radius) * 3, maximum);
    const travel: u16 = @intCast(random.pick(&world.rng_state, minimum_distance, maximum_distance));
    const picked_direction = random.pick(&world.rng_state, first, last) + direction_adjustment;
    const direction: u8 = @intCast(@mod(picked_direction, 256));
    return moveCoord(ai.center_x, ai.center_y, direction, travel);
}

fn moveCoord(x: i16, y: i16, direction: u8, travel: u16) Coord {
    const moved = movement.coordMove(x, y, direction, travel);
    return .{ .x = moved.x, .y = moved.y };
}

fn insideBaseZone(world: *const state.World, position: state.Position) bool {
    const center_x = @as(i32, position.x) * cell_leptons + 128;
    const center_y = @as(i32, position.y) * cell_leptons + 128;
    return distance(center_x - world.easy_ai.center_x, center_y - world.easy_ai.center_y) <= @as(i32, world.easy_ai.radius) * 4;
}

fn cellDistance(a: state.Position, b: state.Position) i32 {
    return distance(
        (@as(i32, a.x) - @as(i32, b.x)) * cell_leptons,
        (@as(i32, a.y) - @as(i32, b.y)) * cell_leptons,
    );
}

fn distance(x: i32, y: i32) i32 {
    const abs_x: u32 = @abs(x);
    const abs_y: u32 = @abs(y);
    return @intCast(@max(abs_x, abs_y) + @divTrunc(@min(abs_x, abs_y), 2));
}
