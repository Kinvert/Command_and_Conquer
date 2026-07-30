const action = @import("action.zig");
const difficulty = @import("difficulty.zig");
const map = @import("map.zig");
const pathfinder = @import("pathfinder.zig");
const random = @import("random.zig");
const rules = @import("rules.zig");
const state = @import("state.zig");

const mission_move: i8 = 2;
const mission_attack: i8 = 1;
const mission_guard: i8 = 4;
const do_walk: i8 = 3;
const do_prone: i8 = 2;
const do_unload: i8 = 29;
const no_path: i8 = -1;
const full_speed: u8 = 255;
const arrival_distance: i16 = 16;
const path_delay_frames: u8 = 15;

pub const InfantryFrameFlags = [rules.max_infantry]bool;

pub const FrameResult = struct {
    moving_at_frame_start: InfantryFrameFlags = [_]bool{false} ** rules.max_infantry,
    entered_cell: InfantryFrameFlags = [_]bool{false} ** rules.max_infantry,
};

const SubSpot = struct {
    x: i16,
    y: i16,
};

const stopping_spots = [_]SubSpot{
    .{ .x = 128, .y = 128 },
    .{ .x = 64, .y = 64 },
    .{ .x = 192, .y = 64 },
    .{ .x = 64, .y = 192 },
    .{ .x = 192, .y = 192 },
};

const closest_spot_order = [5][4]u8{
    .{ 1, 2, 3, 4 },
    .{ 0, 2, 3, 4 },
    .{ 0, 1, 4, 3 },
    .{ 0, 1, 4, 2 },
    .{ 0, 2, 3, 1 },
};

// Byte-for-byte copy of TD's CosTable in tiberiandawn/coord.cpp.
const cosine_table = [256]u8{
    0x00, 0x03, 0x06, 0x09, 0x0c, 0x0f, 0x12, 0x15, 0x18, 0x1b, 0x1e, 0x21, 0x24, 0x27, 0x2a, 0x2d,
    0x30, 0x33, 0x36, 0x39, 0x3b, 0x3e, 0x41, 0x43, 0x46, 0x49, 0x4b, 0x4e, 0x50, 0x52, 0x55, 0x57,
    0x59, 0x5b, 0x5e, 0x60, 0x62, 0x64, 0x65, 0x67, 0x69, 0x6b, 0x6c, 0x6e, 0x6f, 0x71, 0x72, 0x74,
    0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7b, 0x7c, 0x7d, 0x7d, 0x7e, 0x7e, 0x7e, 0x7e, 0x7e,
    0x7f, 0x7e, 0x7e, 0x7e, 0x7e, 0x7e, 0x7d, 0x7d, 0x7c, 0x7b, 0x7b, 0x7a, 0x79, 0x78, 0x77, 0x76,
    0x75, 0x74, 0x72, 0x71, 0x70, 0x6e, 0x6c, 0x6b, 0x69, 0x67, 0x66, 0x64, 0x62, 0x60, 0x5e, 0x5b,
    0x59, 0x57, 0x55, 0x52, 0x50, 0x4e, 0x4b, 0x49, 0x46, 0x43, 0x41, 0x3e, 0x3b, 0x39, 0x36, 0x33,
    0x30, 0x2d, 0x2a, 0x27, 0x24, 0x21, 0x1e, 0x1b, 0x18, 0x15, 0x12, 0x0f, 0x0c, 0x09, 0x06, 0x03,
    0x00, 0xfd, 0xfa, 0xf7, 0xf4, 0xf1, 0xee, 0xeb, 0xe8, 0xe5, 0xe2, 0xdf, 0xdc, 0xd9, 0xd6, 0xd3,
    0xd0, 0xcd, 0xca, 0xc7, 0xc5, 0xc2, 0xbf, 0xbd, 0xba, 0xb7, 0xb5, 0xb2, 0xb0, 0xae, 0xab, 0xa9,
    0xa7, 0xa5, 0xa2, 0xa0, 0x9e, 0x9c, 0x9a, 0x99, 0x97, 0x95, 0x94, 0x92, 0x91, 0x8f, 0x8e, 0x8c,
    0x8b, 0x8a, 0x89, 0x88, 0x87, 0x86, 0x85, 0x85, 0x84, 0x83, 0x83, 0x82, 0x82, 0x82, 0x82, 0x82,
    0x82, 0x82, 0x82, 0x82, 0x82, 0x82, 0x83, 0x83, 0x84, 0x85, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a,
    0x8b, 0x8c, 0x8e, 0x8f, 0x90, 0x92, 0x94, 0x95, 0x97, 0x99, 0x9a, 0x9c, 0x9e, 0xa0, 0xa2, 0xa5,
    0xa7, 0xa9, 0xab, 0xae, 0xb0, 0xb2, 0xb5, 0xb7, 0xba, 0xbd, 0xbf, 0xc2, 0xc5, 0xc7, 0xca, 0xcd,
    0xd0, 0xd3, 0xd6, 0xd9, 0xdc, 0xdf, 0xe2, 0xe5, 0xe8, 0xeb, 0xee, 0xf1, 0xf4, 0xf7, 0xfa, 0xfd,
};

pub fn apply(world: *state.World, owner: state.Owner, command: action.Action) bool {
    if (command.command != .move or command.target_kind != .cell or command.target_x >= world.map_width or command.target_y >= world.map_height) return false;

    const infantry = infantryByActorSlot(world, owner, command.actor) orelse return false;
    const object_rule = rules.object(infantry.kind) orelse return false;
    if (object_rule.category != .infantry or object_rule.max_speed == 0) return false;

    infantry.target = .{};
    infantry.destination = .{ .x = command.target_x, .y = command.target_y };
    infantry.destination_valid = true;
    infantry.pending_move = true;
    infantry.command_delay = 1;
    infantry.arrival_mission_delay = 1;
    infantry.queued_mission = -1;
    clearPath(infantry);
    return true;
}

pub fn assignNavigation(infantry: *state.Infantry, destination: state.Position) void {
    stopDriver(infantry);
    infantry.destination = destination;
    infantry.destination_valid = true;
    infantry.pending_move = false;
    infantry.command_delay = 0;
    infantry.new_destination = true;
    clearPath(infantry);
}

pub fn tick(world: *state.World) FrameResult {
    var result: FrameResult = .{};
    for (world.infantry[0..world.infantry_count], 0..) |infantry, index| {
        result.moving_at_frame_start[index] = infantry.active and infantry.moving;
    }

    for (0..world.infantry_count) |infantry_index| {
        const infantry = &world.infantry[infantry_index];
        if (!infantry.active) continue;
        if (infantry.path_delay != 0) infantry.path_delay -= 1;

        if (infantry.mission_delay != 0) {
            infantry.mission_delay -= 1;
            if (infantry.mission_delay == 0) {
                infantry.mission = infantry.arrival_mission;
                infantry.queued_mission = -1;
                infantry.mission_timer_due = world.frame + 1;
            }
        }

        if (infantry.pending_move) {
            if (infantry.command_delay != 0) {
                infantry.command_delay -= 1;
                if (infantry.command_delay == 0 and infantry.moving) {
                    result.entered_cell[infantry_index] = advance(world, infantry_index);
                    stopDriver(infantry);
                }
                continue;
            }
            const can_commence = scatterInterruptible(infantry.animation);
            if (!can_commence and infantry.mission == mission_guard) continue;
            infantry.pending_move = false;
            if (can_commence) {
                infantry.mission = mission_move;
                infantry.queued_mission = -1;
                infantry.mission_timer_due = world.frame + 1;
            }
            infantry.new_destination = true;
        }

        if (infantry.moving) {
            result.entered_cell[infantry_index] = advance(world, infantry_index);
            continue;
        }
        if (!infantry.destination_valid) continue;
        startSegment(world, infantry_index);
        infantry.new_destination = false;
    }
    return result;
}

fn infantryByActorSlot(world: *state.World, owner: state.Owner, slot: u8) ?*state.Infantry {
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
    for (&world.infantry) |*infantry| {
        if (!infantry.active or infantry.owner != owner) continue;
        if (candidate == slot) return infantry;
        candidate += 1;
    }
    return null;
}

fn startSegment(world: *state.World, infantry_index: usize) void {
    const infantry = &world.infantry[infantry_index];
    if (infantry.position.x == infantry.destination.x and infantry.position.y == infantry.destination.y) {
        arrive(world, infantry_index);
        return;
    }

    if (infantry.path[0] != no_path) {
        const next = adjacentCell(infantry.position, @intCast(infantry.path[0]));
        if (next == null or !pathfinder.infantryCanEnter(world, infantry.owner, next.?)) {
            infantry.path[0] = no_path;
            infantry.path_facing = no_path;
        }
    }

    if (infantry.path[0] == no_path) {
        if (infantry.path_delay != 0) return;
        const found = pathfinder.find(world, infantry.owner, infantry.position, infantry.destination, &infantry.path);
        infantry.path_delay = path_delay_frames;
        if (!found) return;
    }
    const facing: u8 = @intCast(infantry.path[0]);

    const step_x: i16 = switch (facing) {
        1, 2, 3 => 1,
        5, 6, 7 => -1,
        else => 0,
    };
    const step_y: i16 = switch (facing) {
        3, 4, 5 => 1,
        0, 1, 7 => -1,
        else => 0,
    };
    const next_x = @as(i16, infantry.position.x) + step_x;
    const next_y = @as(i16, infantry.position.y) + step_y;
    const center_x = next_x * 256 + 128;
    const center_y = next_y * 256 + 128;
    const approach = desiredFacing256(infantry.coord_x, infantry.coord_y, center_x, center_y);
    const offset = coordMove(center_x, center_y, approach +% 128, 124);
    const preferred_spot = spotIndex(@mod(offset.x, 256), @mod(offset.y, 256));
    const free_spot = closestFreeSpot(world, infantry_index, next_x, next_y, preferred_spot) orelse return;

    infantry.head_coord_x = next_x * 256 + free_spot.x;
    infantry.head_coord_y = next_y * 256 + free_spot.y;
    infantry.path_facing = @intCast(facing);
    const head_direction = desiredFacing256(
        infantry.coord_x,
        infantry.coord_y,
        infantry.head_coord_x,
        infantry.head_coord_y,
    );
    infantry.facing = @intCast((((@as(u16, head_direction) + 16) >> 5) & 7) << 5);
    infantry.speed = full_speed;
    infantry.moving = true;
    if (scatterInterruptible(infantry.animation)) {
        infantry.animation = do_walk;
        infantry.animation_stage = 0;
        infantry.animation_rate = 2;
        infantry.animation_timer = 3;
    }
}

fn stopDriver(infantry: *state.Infantry) void {
    infantry.head_coord_x = 0;
    infantry.head_coord_y = 0;
    infantry.speed = 0;
    infantry.moving = false;
    infantry.animation = if (infantry.prone) do_prone else 0;
    infantry.animation_stage = 0;
    infantry.animation_rate = 0;
    infantry.animation_timer = 0;
}

fn advance(world: *state.World, infantry_index: usize) bool {
    const infantry = &world.infantry[infantry_index];
    const distance_x = abs(infantry.head_coord_x - infantry.coord_x);
    const distance_y = abs(infantry.head_coord_y - infantry.coord_y);
    if (tdDistance(distance_x, distance_y) < arrival_distance) {
        infantry.coord_x = infantry.head_coord_x;
        infantry.coord_y = infantry.head_coord_y;
        infantry.position = positionFor(infantry.coord_x, infantry.coord_y);
        infantry.head_coord_x = 0;
        infantry.head_coord_y = 0;
        infantry.speed = 0;
        infantry.moving = false;
        if (infantry.position.x == infantry.destination.x and infantry.position.y == infantry.destination.y) {
            arrive(world, infantry_index);
        } else {
            if (infantry.tethered) {
                scatterCrowdedCell(world, infantry_index);
                infantry.tethered = false;
            }
            shiftPath(infantry);
            infantry.path_facing = infantry.path[0];
        }
        return true;
    }

    const object_rule = rules.object(infantry.kind) orelse return false;
    const max_speed = difficulty.groundSpeed(world, infantry.owner, object_rule.max_speed);
    const distance = fixedToCardinal(max_speed, infantry.speed);
    const direction = desiredFacing256(
        infantry.coord_x,
        infantry.coord_y,
        infantry.head_coord_x,
        infantry.head_coord_y,
    );
    const cosine: i8 = @bitCast(cosine_table[direction]);
    const sine: i8 = @bitCast(cosine_table[(direction +% 64)]);
    const next_x = @as(i32, infantry.coord_x) + movementComponent(cosine, distance);
    const next_y = @as(i32, infantry.coord_y) - movementComponent(sine, distance);
    infantry.coord_x = @intCast(next_x);
    infantry.coord_y = @intCast(next_y);
    infantry.position = positionFor(infantry.coord_x, infantry.coord_y);
    return false;
}

fn closestFreeSpot(
    world: *const state.World,
    infantry_index: usize,
    cell_x: i16,
    cell_y: i16,
    preferred_spot: u8,
) ?SubSpot {
    if (isSpotFree(world, infantry_index, cell_x, cell_y, preferred_spot)) {
        return stopping_spots[preferred_spot];
    }
    for (closest_spot_order[preferred_spot]) |candidate| {
        if (isSpotFree(world, infantry_index, cell_x, cell_y, candidate)) {
            return stopping_spots[candidate];
        }
    }
    return null;
}

fn isSpotFree(
    world: *const state.World,
    infantry_index: usize,
    cell_x: i16,
    cell_y: i16,
    spot: u8,
) bool {
    for (world.infantry, 0..) |other, other_index| {
        if (other_index == infantry_index or !other.active) continue;
        const reserved_x = if (other.moving) other.head_coord_x else other.coord_x;
        const reserved_y = if (other.moving) other.head_coord_y else other.coord_y;
        if (@divFloor(reserved_x, 256) != cell_x or @divFloor(reserved_y, 256) != cell_y) continue;
        if (spotIndex(@mod(reserved_x, 256), @mod(reserved_y, 256)) == spot) return false;
    }
    return true;
}

fn spotIndex(x: i16, y: i16) u8 {
    if (tdDistance(abs(x - 128), abs(y - 128)) < 60) return 0;
    var index: u8 = 1;
    if (x > 128) index += 1;
    if (y > 128) index += 2;
    return index;
}

pub fn desiredFacing256(x1: i16, y1: i16, x2: i16, y2: i16) u8 {
    var quadrant: i32 = 0;
    var x_diff = @as(i32, x2) - @as(i32, x1);
    if (x_diff < 0) {
        x_diff = -x_diff;
        quadrant = -64;
    }

    var y_diff = @as(i32, y1) - @as(i32, y2);
    if (y_diff < 0) {
        quadrant ^= 64;
        y_diff = -y_diff;
    }
    if (x_diff == 0 and y_diff == 0) return 255;

    const small = @min(x_diff, y_diff);
    const large = @max(x_diff, y_diff);
    var scaled = @divTrunc(32 * small, large);
    var ranged = quadrant & 64;
    if (x_diff > y_diff) ranged ^= 64;
    if (ranged != 0) scaled = ranged - scaled - 1;
    return @intCast((scaled + quadrant) & 255);
}

fn movementComponent(coefficient: i8, distance: u16) i32 {
    return @divFloor(@as(i32, coefficient) * @as(i32, distance), 128);
}

pub fn coordMove(x: i16, y: i16, direction: u8, distance: u16) struct { x: i16, y: i16 } {
    const cosine: i8 = @bitCast(cosine_table[direction]);
    const sine: i8 = @bitCast(cosine_table[direction +% 64]);
    return .{
        .x = @intCast(@as(i32, x) + movementComponent(cosine, distance)),
        .y = @intCast(@as(i32, y) - movementComponent(sine, distance)),
    };
}

fn arrive(world: *state.World, infantry_index: usize) void {
    const was_tethered = world.infantry[infantry_index].tethered;
    if (was_tethered) scatterCrowdedCell(world, infantry_index);

    const infantry = &world.infantry[infantry_index];
    infantry.tethered = false;
    infantry.destination_valid = false;
    infantry.new_destination = false;
    infantry.pending_move = false;
    infantry.moving = false;
    infantry.speed = 0;
    infantry.path_facing = no_path;
    clearPath(infantry);
    infantry.head_coord_x = 0;
    infantry.head_coord_y = 0;
    if (was_tethered) {
        infantry.mission = mission_move;
        if (infantry.queued_mission != mission_attack) {
            infantry.queued_mission = infantry.arrival_mission;
            infantry.mission_delay = infantry.arrival_mission_delay;
        }
    } else if (infantry.mission == mission_move and infantry.queued_mission != mission_attack) {
        infantry.queued_mission = infantry.arrival_mission;
        infantry.mission_delay = infantry.arrival_mission_delay;
    }
    infantry.animation = if (was_tethered) do_unload else 0;
    infantry.animation_stage = 0;
    infantry.animation_rate = if (was_tethered) 2 else 0;
    infantry.animation_timer = if (was_tethered) 3 else 0;
}

fn scatterCrowdedCell(world: *state.World, entering_index: usize) void {
    const cell = world.infantry[entering_index].position;
    var occupants: usize = 0;
    for (world.infantry) |infantry| {
        if (infantry.active and samePosition(infantry.position, cell)) occupants += 1;
    }
    if (occupants < stopping_spots.len) return;

    var reverse_index = world.infantry.len;
    while (reverse_index != 0) {
        reverse_index -= 1;
        if (reverse_index == entering_index) continue;
        scatterInfantry(world, reverse_index, .opponent, cell);
    }
}

pub fn scatterInfantryAt(world: *state.World, owner: state.Owner, cell: state.Position) void {
    var reverse_index = world.infantry.len;
    while (reverse_index != 0) {
        reverse_index -= 1;
        scatterInfantry(world, reverse_index, owner, cell);
    }
}

fn scatterInfantry(world: *state.World, infantry_index: usize, owner: state.Owner, cell: state.Position) void {
    const infantry = &world.infantry[infantry_index];
    if (!infantry.active or infantry.owner != owner or !samePosition(infantry.position, cell)) return;
    if (infantry.moving or infantry.destination_valid or !scatterInterruptible(infantry.animation)) return;

    const fraction_x: i16 = @mod(infantry.coord_x, 256);
    const fraction_y: i16 = @mod(infantry.coord_y, 256);
    var facing: i16 = if (fraction_x == 128 and fraction_y == 128)
        infantry.facing >> 5
    else
        (@as(i16, desiredFacing256(128, 128, fraction_x, fraction_y)) + 16) >> 5;
    facing = (facing + @as(i16, @intCast(random.pick(&world.rng_state, 0, 4))) - 2) & 7;

    var destination: ?state.Position = null;
    for (0..8) |offset| {
        const direction: u8 = @intCast((facing + @as(i16, @intCast(offset))) & 7);
        const candidate = adjacentCell(cell, direction) orelse continue;
        if (cellEnterable(world, candidate)) destination = candidate;
    }
    const target = destination orelse return;

    infantry.destination = target;
    infantry.destination_valid = true;
    infantry.pending_move = true;
    infantry.command_delay = 0;
    infantry.queued_mission = mission_move;
    infantry.arrival_mission_delay = 1;
    infantry.new_destination = false;
    infantry.animation = 0;
    infantry.animation_stage = 0;
    infantry.animation_timer = 0;
    infantry.animation_rate = 0;
    clearPath(infantry);
}

fn scatterInterruptible(animation: i8) bool {
    return switch (animation) {
        -1, 0, 1, 2, 3, 4, 6, 8, 9, 10, 12 => true,
        else => false,
    };
}

fn adjacentCell(position: state.Position, direction: u8) ?state.Position {
    const x_delta = [_]i8{ 0, 1, 1, 1, 0, -1, -1, -1 };
    const y_delta = [_]i8{ -1, -1, 0, 1, 1, 1, 0, -1 };
    const x = @as(i16, position.x) + x_delta[direction];
    const y = @as(i16, position.y) + y_delta[direction];
    if (x < 0 or y < 0 or x >= map.width or y >= map.height) return null;
    return .{ .x = @intCast(x), .y = @intCast(y) };
}

fn cellEnterable(world: *const state.World, position: state.Position) bool {
    if (!map.footPassable(position)) return false;
    for (world.buildings) |building| {
        if (!building.active or building.health == 0) continue;
        if (buildingOccupies(building, position)) return false;
    }
    return true;
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

fn samePosition(left: state.Position, right: state.Position) bool {
    return left.x == right.x and left.y == right.y;
}

fn shiftPath(infantry: *state.Infantry) void {
    for (0..infantry.path.len - 1) |index| infantry.path[index] = infantry.path[index + 1];
    infantry.path[infantry.path.len - 1] = no_path;
}

fn clearPath(infantry: *state.Infantry) void {
    infantry.path = [_]i8{no_path} ** pathfinder.path_capacity;
    infantry.path_facing = no_path;
}

fn fixedToCardinal(base: u8, fixed: u8) u8 {
    return @intCast((@as(u16, base) * @as(u16, fixed) + 128) >> 8);
}

fn positionFor(x: i16, y: i16) state.Position {
    return .{ .x = @intCast(@divFloor(x, 256)), .y = @intCast(@divFloor(y, 256)) };
}

fn tdDistance(x: i16, y: i16) i16 {
    const major = @max(x, y);
    const minor = @min(x, y);
    return major + @divTrunc(minor, 2);
}

fn abs(value: i16) i16 {
    return if (value < 0) -value else value;
}
