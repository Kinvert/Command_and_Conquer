const std = @import("std");
const map = @import("map.zig");
const rules = @import("rules.zig");
const state = @import("state.zig");

pub const CellOffset = struct {
    x: i8,
    y: i8,
};

const construction_yard_footprint = [_]CellOffset{
    .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 0 },
    .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 },
    .{ .x = 0, .y = 2 }, .{ .x = 1, .y = 2 }, .{ .x = 2, .y = 2 },
};

const power_plant_footprint = [_]CellOffset{
    .{ .x = 0, .y = 0 },
    .{ .x = 0, .y = 1 },
    .{ .x = 1, .y = 1 },
    .{ .x = 0, .y = 2 },
    .{ .x = 1, .y = 2 },
};

const barracks_footprint = [_]CellOffset{
    .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 0 },
    .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 },
    .{ .x = 0, .y = 2 }, .{ .x = 1, .y = 2 },
};

/// Vanilla's ListWeap: {MCW, MCW+1, MCW+2, MCW*2, MCW*2+1, MCW*2+2} -- two rows of three, offset
/// one row down from the anchor. Without this the Weapons Factory had no footprint at all,
/// placement.footprint returned null, and isLegal rejected every cell on every map.
const weapons_factory_footprint = [_]CellOffset{
    .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 },
    .{ .x = 0, .y = 2 }, .{ .x = 1, .y = 2 }, .{ .x = 2, .y = 2 },
};

const refinery_footprint = [_]CellOffset{
    .{ .x = 1, .y = 0 },
    .{ .x = 0, .y = 1 },
    .{ .x = 1, .y = 1 },
    .{ .x = 2, .y = 1 },
};

const refinery_placement_footprint = [_]CellOffset{
    .{ .x = 1, .y = 0 },
    .{ .x = 0, .y = 1 },
    .{ .x = 1, .y = 1 },
    .{ .x = 2, .y = 1 },
    .{ .x = 0, .y = 2 },
    .{ .x = 1, .y = 2 },
    .{ .x = 2, .y = 2 },
    .{ .x = 0, .y = 3 },
    .{ .x = 1, .y = 3 },
    .{ .x = 2, .y = 3 },
};

const adjacent_offsets = [_]CellOffset{
    .{ .x = 0, .y = -1 },
    .{ .x = 1, .y = -1 },
    .{ .x = 1, .y = 0 },
    .{ .x = 1, .y = 1 },
    .{ .x = 0, .y = 1 },
    .{ .x = -1, .y = 1 },
    .{ .x = -1, .y = 0 },
    .{ .x = -1, .y = -1 },
};

const row_count: usize = 64;
const permanently_blocked_rows = buildPermanentlyBlockedRows();

// Active foundation cells used by occupancy and policy-state packing.
pub fn footprint(product: rules.ObjectType) ?[]const CellOffset {
    return switch (product) {
        .construction_yard => &construction_yard_footprint,
        .power_plant => &power_plant_footprint,
        .barracks => &barracks_footprint,
        .refinery => &refinery_footprint,
        .weapons_factory => &weapons_factory_footprint,
        else => null,
    };
}

// Vanilla's Occupy_List(true) combines the active foundation with the owned bib.
pub fn placementFootprint(product: rules.ObjectType) ?[]const CellOffset {
    if (product == .refinery) return &refinery_placement_footprint;
    return footprint(product);
}

pub fn isLegal(
    world: *const state.World,
    owner: state.Owner,
    product: rules.ObjectType,
    position: state.Position,
) bool {
    const occupied_cells = placementFootprint(product) orelse return false;
    for (occupied_cells) |offset| {
        const candidate = offsetPosition(world, position, offset) orelse return false;
        const cell = map.at(candidate) orelse return false;
        const depleted_tiberium = cell.land_type == 5 and !world.hasTiberium(candidate);
        if ((!cell.ground_buildable and !depleted_tiberium) or
            cell.static_blocked or cellOccupied(world, candidate))
        {
            return false;
        }
    }
    return passesProximity(world, owner, position, occupied_cells);
}

pub fn legalOriginRows(
    world: *const state.World,
    owner: state.Owner,
    product: rules.ObjectType,
    output: *[row_count]u64,
) void {
    @memset(output, 0);
    const product_cells = placementFootprint(product) orelse return;

    var blocked = permanently_blocked_rows;
    for (0..world.map_height) |y| blocked[y] |= world.tiberium_present[y];
    markDynamicOccupancy(world, &blocked);

    var proximity = [_]u64{0} ** row_count;
    markOwnerProximity(world, owner, &proximity);

    for (0..world.map_height) |y| {
        var clear_origins = lowBitMask(world.map_width);
        var touching_origins: u64 = 0;
        for (product_cells) |offset| {
            const candidate_y = @as(i16, @intCast(y)) + @as(i16, offset.y);
            if (candidate_y < 0 or candidate_y >= world.map_height) {
                clear_origins = 0;
                break;
            }

            const origin_mask = validOriginMask(world.map_width, offset.x);
            const row_index: usize = @intCast(candidate_y);
            clear_origins &= origin_mask & ~alignCandidateRow(blocked[row_index], offset.x);
            touching_origins |= alignCandidateRow(proximity[row_index], offset.x);
        }
        output[y] = clear_origins & touching_origins;
    }
}

pub fn offsetPosition(
    world: *const state.World,
    origin: state.Position,
    offset: CellOffset,
) ?state.Position {
    const x = @as(i16, origin.x) + offset.x;
    const y = @as(i16, origin.y) + offset.y;
    if (x < 0 or y < 0 or x >= world.map_width or y >= world.map_height) return null;
    return .{ .x = @intCast(x), .y = @intCast(y) };
}

fn cellOccupied(world: *const state.World, position: state.Position) bool {
    for (world.units) |unit| {
        if (!unit.active or unit.health <= 0) continue;
        if (samePosition(unit.position, position) or unitReservesHeadCell(unit, position)) return true;
    }
    for (world.buildings[0..world.building_count]) |building| {
        if (building.active and building.health > 0 and buildingOccupies(world, building, position)) return true;
    }
    for (world.infantry[0..world.infantry_count]) |infantry| {
        if (infantry.active and infantry.health > 0 and samePosition(infantry.position, position)) return true;
    }
    return false;
}

fn unitReservesHeadCell(unit: state.Unit, position: state.Position) bool {
    if (unit.head_coord_x == 0 and unit.head_coord_y == 0) return false;
    return @divFloor(unit.head_coord_x, 256) == position.x and
        @divFloor(unit.head_coord_y, 256) == position.y;
}

fn passesProximity(
    world: *const state.World,
    owner: state.Owner,
    position: state.Position,
    occupied_cells: []const CellOffset,
) bool {
    for (occupied_cells) |foundation_offset| {
        const foundation = offsetPosition(world, position, foundation_offset) orelse return false;
        for (adjacent_offsets) |adjacent_offset| {
            const adjacent = offsetPosition(world, foundation, adjacent_offset) orelse continue;
            for (world.buildings[0..world.building_count]) |building| {
                if (!building.active or building.health <= 0 or building.owner != owner) continue;
                if (buildingOccupies(world, building, adjacent)) return true;
            }
        }
    }
    return false;
}

fn buildingOccupies(
    world: *const state.World,
    building: state.Building,
    position: state.Position,
) bool {
    const occupied_cells = footprint(building.kind) orelse return false;
    for (occupied_cells) |offset| {
        const occupied = offsetPosition(world, building.position, offset) orelse continue;
        if (samePosition(occupied, position)) return true;
    }
    return false;
}

fn samePosition(a: state.Position, b: state.Position) bool {
    return a.x == b.x and a.y == b.y;
}

fn buildPermanentlyBlockedRows() [row_count]u64 {
    @setEvalBranchQuota(20_000);
    var rows = [_]u64{0} ** row_count;
    for (0..map.height) |y| {
        for (0..map.width) |x| {
            const cell = map.cells[y * @as(usize, map.width) + x];
            if (cell.static_blocked or (!cell.ground_buildable and cell.land_type != 5)) {
                rows[y] |= @as(u64, 1) << @intCast(x);
            }
        }
    }
    return rows;
}

fn markDynamicOccupancy(world: *const state.World, rows: *[row_count]u64) void {
    for (world.units) |unit| {
        if (!unit.active or unit.health <= 0) continue;
        markPosition(world, rows, unit.position);
        if (unit.head_coord_x != 0 or unit.head_coord_y != 0) {
            markCoordinate(world, rows, unit.head_coord_x, unit.head_coord_y);
        }
    }
    for (world.buildings[0..world.building_count]) |building| {
        if (!building.active or building.health <= 0) continue;
        const occupied_cells = footprint(building.kind) orelse continue;
        for (occupied_cells) |offset| {
            const occupied = offsetPosition(world, building.position, offset) orelse continue;
            markPosition(world, rows, occupied);
        }
    }
    for (world.infantry[0..world.infantry_count]) |infantry| {
        if (!infantry.active or infantry.health <= 0) continue;
        markPosition(world, rows, infantry.position);
    }
}

fn markOwnerProximity(
    world: *const state.World,
    owner: state.Owner,
    rows: *[row_count]u64,
) void {
    for (world.buildings[0..world.building_count]) |building| {
        if (!building.active or building.health <= 0 or building.owner != owner) continue;
        const occupied_cells = footprint(building.kind) orelse continue;
        for (occupied_cells) |foundation_offset| {
            const foundation = offsetPosition(world, building.position, foundation_offset) orelse continue;
            for (adjacent_offsets) |adjacent_offset| {
                const adjacent = offsetPosition(world, foundation, adjacent_offset) orelse continue;
                markPosition(world, rows, adjacent);
            }
        }
    }
}

fn markPosition(
    world: *const state.World,
    rows: *[row_count]u64,
    position: state.Position,
) void {
    if (position.x >= world.map_width or position.y >= world.map_height) return;
    rows[position.y] |= @as(u64, 1) << @intCast(position.x);
}

fn markCoordinate(world: *const state.World, rows: *[row_count]u64, x: i16, y: i16) void {
    const cell_x = @divFloor(x, 256);
    const cell_y = @divFloor(y, 256);
    if (cell_x < 0 or cell_y < 0 or cell_x >= world.map_width or cell_y >= world.map_height) return;
    markPosition(world, rows, .{ .x = @intCast(cell_x), .y = @intCast(cell_y) });
}

fn validOriginMask(width: u8, offset: i8) u64 {
    if (offset >= 0) {
        const shift: u8 = @intCast(offset);
        if (shift >= width) return 0;
        return lowBitMask(width - shift);
    }

    const shift: u8 = @intCast(-@as(i16, offset));
    if (shift >= width) return 0;
    return lowBitMask(width) & ~lowBitMask(shift);
}

fn alignCandidateRow(row: u64, offset: i8) u64 {
    if (offset >= 0) return row >> @intCast(offset);
    return row << @intCast(-@as(i16, offset));
}

fn lowBitMask(count: u8) u64 {
    if (count == 0) return 0;
    if (count >= 64) return std.math.maxInt(u64);
    return (@as(u64, 1) << @intCast(count)) - 1;
}
