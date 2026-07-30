const map = @import("map.zig");
const state = @import("state.zig");
const tracks = @import("vehicle_tracks.zig");

pub const path_capacity: usize = 9;
const work_capacity: usize = 400;
const max_edge_follow_steps: usize = 400;
const no_path: i8 = -1;
const empty_path: i8 = -2;
const move_cloak: u8 = 1;
const move_moving_block: u8 = 2;
const move_destroyable: u8 = 3;

const MoveType = enum(u8) {
    ok,
    cloak,
    moving_block,
    destroyable,
    temp,
    no,
};

const Route = struct {
    commands: [work_capacity]i8 = [_]i8{no_path} ** work_capacity,
    length: usize = 0,
    cost: u32 = 0,
    start: state.Position = .{},
    last_overlap: ?state.Position = null,
};

pub fn findStatic(source: state.Position, destination: state.Position, output: *[path_capacity]i8) bool {
    output.* = [_]i8{no_path} ** path_capacity;
    if (!inBounds(source) or !inBounds(destination)) return false;
    if (same(source, destination)) return true;
    const route = findRoute(.{}, source, destination, move_cloak) orelse return false;
    return copyRoute(route, output);
}

pub fn find(
    world: *const state.World,
    mover_owner: state.Owner,
    source: state.Position,
    destination: state.Position,
    output: *[path_capacity]i8,
) bool {
    return findForMover(world, mover_owner, source, destination, output, .infantry);
}

pub fn findVehicle(
    world: *const state.World,
    mover_owner: state.Owner,
    source: state.Position,
    destination: state.Position,
    output: *[path_capacity]i8,
) bool {
    return findForMover(world, mover_owner, source, destination, output, .vehicle);
}

pub fn infantryCanEnter(world: *const state.World, mover_owner: state.Owner, position: state.Position) bool {
    const context: Context = .{ .world = world, .mover_owner = mover_owner, .mover_kind = .infantry };
    return context.movementType(position) == .ok;
}

const MoverKind = enum {
    infantry,
    vehicle,
};

fn findForMover(
    world: *const state.World,
    mover_owner: state.Owner,
    source: state.Position,
    destination: state.Position,
    output: *[path_capacity]i8,
    mover_kind: MoverKind,
) bool {
    output.* = [_]i8{no_path} ** path_capacity;
    if (!inBounds(source) or !inBounds(destination)) return false;
    if (same(source, destination)) return true;

    const context: Context = .{ .world = world, .mover_owner = mover_owner, .mover_kind = mover_kind };
    const aggressive = findRoute(context, source, destination, move_destroyable) orelse return false;
    if (aggressive.cost == 0) return false;
    var selected = aggressive;
    const acceptable_cost = @max(aggressive.cost + aggressive.cost / 2, 3);
    var selected_easy_route = false;
    if (findRoute(context, source, destination, move_cloak)) |easy| {
        if (easy.cost != 0 and easy.cost < acceptable_cost) {
            selected = easy;
            selected_easy_route = true;
        }
    }
    if (!selected_easy_route) {
        if (findRoute(context, source, destination, move_moving_block)) |moving| {
            if (moving.cost != 0 and moving.cost < acceptable_cost) selected = moving;
        }
    }
    return copyRoute(selected, output);
}

const Context = struct {
    world: ?*const state.World = null,
    mover_owner: state.Owner = .none,
    mover_kind: MoverKind = .infantry,

    fn movementType(self: Context, position: state.Position) MoveType {
        if (!map.footPassable(position)) return .no;
        const world = self.world orelse return .ok;
        for (world.buildings[0..world.building_count]) |building| {
            if (!building.active or building.health <= 0 or !buildingOccupies(building, position)) continue;
            return if (building.owner == self.mover_owner or building.owner == .none) .no else .destroyable;
        }
        for (world.units) |unit| {
            if (!unit.active or unit.health <= 0 or !same(unit.position, position)) continue;
            return if (unit.owner == self.mover_owner) .temp else .destroyable;
        }
        for (world.units) |unit| {
            if (vehicleReserves(unit, position)) return .no;
        }
        var allied_infantry: u8 = 0;
        var stationary_allied_infantry = false;
        for (world.infantry[0..world.infantry_count]) |infantry| {
            if (!infantry.active or infantry.health <= 0 or !same(infantry.position, position)) continue;
            if (infantry.owner != self.mover_owner) return .destroyable;
            allied_infantry += 1;
            if (!infantry.destination_valid and !infantry.moving) stationary_allied_infantry = true;
        }
        if (self.mover_kind == .vehicle and stationary_allied_infantry) return .temp;
        return if (allied_infantry >= 5) .moving_block else .ok;
    }

    fn entryCost(self: Context, position: state.Position, threshold: u8) u8 {
        const movement_type = self.movementType(position);
        if (@intFromEnum(movement_type) > threshold) return 0;
        return switch (movement_type) {
            .ok, .cloak => 1,
            .moving_block => 3,
            .destroyable => 8,
            .temp => 10,
            .no => 0,
        };
    }

    fn passable(self: Context, position: state.Position, threshold: u8) bool {
        return self.entryCost(position, threshold) != 0;
    }
};

fn vehicleReserves(unit: state.Unit, position: state.Position) bool {
    if (!unit.active or unit.health <= 0 or !unit.moving or unit.head_coord_x == 0 or unit.head_coord_y == 0) return false;

    const head = state.Position{
        .x = @intCast(@divFloor(unit.head_coord_x, 256)),
        .y = @intCast(@divFloor(unit.head_coord_y, 256)),
    };
    if (same(head, position)) return true;
    if (unit.track_number < 0 or unit.track_number >= tracks.controls.len) return false;

    const control = tracks.controls[@intCast(unit.track_number)];
    if (control.track == 0 or control.flags & tracks.flag_double == 0) return false;
    const raw = tracks.raw_tracks[control.track - 1];
    if (raw.cell < 0 or unit.track_index >= raw.cell) return false;

    const second_facing: i8 = @intCast(unit.track_number & 7);
    const midpoint = adjacent(head, opposite(second_facing)) orelse return false;
    return same(midpoint, position);
}

fn findRoute(
    context: Context,
    source: state.Position,
    destination: state.Position,
    threshold: u8,
) ?Route {
    var route: Route = .{ .start = source };
    var current = source;
    while (route.length < work_capacity - 1 and !same(current, destination)) {
        const direction = cellFacing(current, destination);
        var next = adjacent(current, direction) orelse return null;
        if (context.passable(next, threshold)) {
            if (!append(&route, direction)) return null;
            current = next;
            continue;
        }
        if (same(next, destination)) break;

        var scans: usize = 0;
        while (!context.passable(next, threshold) and !same(next, destination)) : (scans += 1) {
            if (scans == work_capacity) return null;
            next = adjacent(next, cellFacing(next, destination)) orelse return null;
        }

        const left = followEdge(context, threshold, route, current, next, -1, direction);
        const right = followEdge(context, threshold, route, current, next, 1, direction);
        const detour = if (right) |right_route|
            if (left) |left_route|
                if (left_route.length < right_route.length) left_route else right_route
            else
                right_route
        else
            left orelse break;

        route = detour;
        current = next;
    }

    optimizeMoves(context, threshold, &route, source);
    route.cost = routeCost(context, threshold, route);
    return route;
}

fn optimizeMoves(context: Context, threshold: u8, route: *Route, start: state.Position) void {
    if (route.length <= 1) return;

    const transition = [_]i8{ 0, 0, 1, 2, 3, -2, -1, 0 };
    var cell = start;
    var second: usize = 1;
    while (second < route.length) {
        var first = second - 1;
        while (route.commands[first] == empty_path and first != 0) first -= 1;
        if (route.commands[first] == empty_path) {
            second += 1;
            continue;
        }

        const difference: usize = @intCast((route.commands[second] - route.commands[first] + 8) & 7);
        const adjustment = transition[difference];
        if (adjustment == 3) {
            route.commands[first] = empty_path;
            route.commands[second] = empty_path;
            second += 1;
            continue;
        }

        if (adjustment != 0) {
            var new_direction: i8 = undefined;
            if (route.commands[first] & 1 != 0) {
                new_direction = nextDirection(route.commands[first], if (adjustment < 0) -1 else 1);
                if (adjustment == -1 or adjustment == 1) {
                    if (adjacent(cell, new_direction)) |next| {
                        if (context.passable(next, threshold)) {
                            route.commands[first] = new_direction;
                            route.commands[second] = new_direction;
                        }
                    }
                    cell = adjacent(cell, route.commands[first]) orelse break;
                    second += 1;
                    continue;
                }
            } else {
                new_direction = nextDirection(route.commands[first], adjustment);
            }

            route.commands[second] = new_direction;
            route.commands[first] = empty_path;
            while (route.commands[first] == empty_path and first != 0) first -= 1;
            if (route.commands[first] != empty_path) {
                cell = adjacent(cell, nextDirection(route.commands[first], 4)) orelse break;
            } else {
                cell = start;
            }
            continue;
        }

        cell = adjacent(cell, route.commands[first]) orelse break;
        second += 1;
    }

    var write: usize = 0;
    for (route.commands[0..route.length]) |command| {
        if (command == empty_path) continue;
        route.commands[write] = command;
        write += 1;
    }
    @memset(route.commands[write..route.length], no_path);
    route.length = write;
}

fn followEdge(
    context: Context,
    threshold: u8,
    base_route: Route,
    start: state.Position,
    target: state.Position,
    search: i8,
    old_direction: i8,
) ?Route {
    var route = base_route;
    route.last_overlap = null;

    var old_cell = start;
    var old_dir = old_direction;
    var first_cell: ?state.Position = null;
    var first_dir: i8 = no_path;
    var online = true;
    var old_value: i32 = 0;
    var edge_steps: usize = 0;

    while (route.length < work_capacity) {
        var new_dir = old_dir;
        var new_cell: state.Position = undefined;
        var force_out = false;
        var attempts: usize = 0;
        while (attempts < 8) : (attempts += 1) {
            new_dir = nextDirection(new_dir, search);
            var force_fail = false;

            if (new_dir & 1 != 0) {
                const corner_dir = nextDirection(new_dir, search);
                const corner = adjacent(old_cell, corner_dir) orelse return null;
                if (same(corner, target) and context.passable(corner, threshold)) {
                    new_dir = corner_dir;
                    new_cell = corner;
                    break;
                }

                const diagonal = adjacent(old_cell, new_dir) orelse return null;
                const value = pointRelativeToLine(diagonal, start, target);
                if (value != 0 and !online) force_fail = (value < 0) != (old_value < 0);
                if (force_fail and route.length != 0 and opposite(new_dir) == route.commands[route.length - 1]) force_fail = false;
            }

            new_cell = adjacent(old_cell, new_dir) orelse return null;
            if (!force_fail and context.passable(new_cell, threshold)) break;
            if (same(new_cell, target)) {
                force_out = true;
                break;
            }
        }
        if (attempts == 8) return null;

        if (!force_out) {
            if (!registerCell(&route, new_cell, new_dir)) return null;

            const value = pointRelativeToLine(new_cell, start, target);
            if (value != 0) {
                old_value = value;
                online = false;
            } else {
                online = true;
            }
            if (consumeEdgeFollowStep(&edge_steps)) return null;
        }

        if (same(new_cell, target)) return route;
        if (first_cell) |first| {
            if (same(new_cell, first) and new_dir == first_dir) return null;
        } else {
            first_cell = new_cell;
            first_dir = new_dir;
        }

        old_dir = nextDirection(new_dir, -search * 3);
        old_cell = new_cell;
    }
    return null;
}

fn consumeEdgeFollowStep(edge_steps: *usize) bool {
    edge_steps.* += 1;
    return edge_steps.* == max_edge_follow_steps;
}

fn append(route: *Route, direction: i8) bool {
    if (route.length == route.commands.len) return false;
    route.commands[route.length] = direction;
    route.length += 1;
    return true;
}

fn registerCell(route: *Route, cell: state.Position, direction: i8) bool {
    const retained = commandsToCell(route, cell) orelse return append(route, direction);

    if (route.length != 0 and route.commands[route.length - 1] == opposite(direction)) {
        route.length -= 1;
        route.commands[route.length] = no_path;
        return true;
    }
    if (route.last_overlap) |previous| {
        if (same(previous, cell)) return false;
    }
    route.last_overlap = cell;
    const old_length = route.length;
    route.length = retained;
    @memset(route.commands[retained..old_length], no_path);
    return true;
}

fn commandsToCell(route: *const Route, target: state.Position) ?usize {
    var cell = route.start;
    if (same(cell, target)) return 0;
    for (route.commands[0..route.length], 0..) |direction, index| {
        cell = adjacent(cell, direction) orelse return null;
        if (same(cell, target)) return index + 1;
    }
    return null;
}

fn routeCost(context: Context, threshold: u8, route: Route) u32 {
    var cost: u32 = 0;
    var cell = route.start;
    for (route.commands[0..route.length]) |direction| {
        cell = adjacent(cell, direction) orelse return 0;
        cost += context.entryCost(cell, threshold);
    }
    return cost;
}

fn copyRoute(route: Route, output: *[path_capacity]i8) bool {
    const count = @min(path_capacity, route.length);
    @memcpy(output[0..count], route.commands[0..count]);
    return count != 0;
}

fn cellFacing(source: state.Position, destination: state.Position) i8 {
    var x_diff = @as(i16, destination.x) - @as(i16, source.x);
    var direction: u8 = 0;
    if (x_diff < 0) {
        direction = 192;
        x_diff = -x_diff;
    }

    var y_diff = @as(i16, source.y) - @as(i16, destination.y);
    if (y_diff < 0) {
        direction ^= 64;
        y_diff = -y_diff;
    }

    const lower = if (x_diff >= y_diff) y_diff else x_diff;
    const upper = @max(x_diff, y_diff);
    const desired: u8 = if ((@as(u16, @intCast(upper)) + 1) >> 1 > @as(u16, @intCast(lower))) blk: {
        var ranged = direction & 64;
        if (x_diff == upper) ranged ^= 64;
        break :blk direction +% ranged;
    } else direction +% 32;
    return @intCast((desired +% 16) >> 5);
}

fn adjacent(position: state.Position, direction: i8) ?state.Position {
    const x_delta = [_]i8{ 0, 1, 1, 1, 0, -1, -1, -1 };
    const y_delta = [_]i8{ -1, -1, 0, 1, 1, 1, 0, -1 };
    const index: usize = @intCast(direction & 7);
    const x = @as(i16, position.x) + x_delta[index];
    const y = @as(i16, position.y) + y_delta[index];
    if (x < 0 or y < 0 or x >= map.width or y >= map.height) return null;
    return .{ .x = @intCast(x), .y = @intCast(y) };
}

fn nextDirection(direction: i8, amount: i8) i8 {
    return @intCast((@as(i16, direction) + amount) & 7);
}

fn opposite(direction: i8) i8 {
    return direction ^ 4;
}

fn pointRelativeToLine(point: state.Position, start: state.Position, target: state.Position) i32 {
    return ((@as(i32, point.x) - target.x) * (@as(i32, start.y) - target.y)) - ((@as(i32, point.y) - target.y) * (@as(i32, start.x) - target.x));
}

fn inBounds(position: state.Position) bool {
    return position.x < map.width and position.y < map.height;
}

fn same(left: state.Position, right: state.Position) bool {
    return left.x == right.x and left.y == right.y;
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
