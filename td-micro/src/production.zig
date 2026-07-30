const std = @import("std");
const action = @import("action.zig");
const difficulty = @import("difficulty.zig");
const economy = @import("economy.zig");
const placement = @import("placement.zig");
const random = @import("random.zig");
const rules = @import("rules.zig");
const state = @import("state.zig");

const mcv_rotation_rate: u8 = 5;
const mcv_rotation_span: u16 = 96;
const mcv_non_rotation_frames: u16 = 4;

/// Which queue a `start_build` command targets. Structures go to the Construction Yard queue and
/// vehicles to the Weapons Factory queue; infantry keep their own explicit `train` command, so
/// they are not reachable here. Routing by category is purely additive: before the vehicle
/// expansion a non-building product simply failed `start`'s category check.
fn buildQueueKind(product: rules.ObjectType) ?state.QueueKind {
    const object_rule = rules.object(product) orelse return null;
    return switch (object_rule.category) {
        .building => .structure,
        .unit => .unit,
        .infantry, .none => null,
    };
}

pub fn apply(world: *state.World, owner: state.Owner, command: action.Action) bool {
    return switch (command.command) {
        .noop => true,
        .deploy => deploy(world, owner, command.actor),
        .start_build => start(world, owner, command.product, buildQueueKind(command.product) orelse return false, false),
        .place => command.target_kind == .cell and place(world, owner, command.product, .{
            .x = command.target_x,
            .y = command.target_y,
        }),
        .train => start(world, owner, command.product, .infantry, false),
        else => false,
    };
}

pub fn applyAI(world: *state.World, owner: state.Owner, command: action.Action) bool {
    return switch (command.command) {
        .noop, .deploy, .place => apply(world, owner, command),
        .start_build => start(world, owner, command.product, buildQueueKind(command.product) orelse return false, true),
        .train => start(world, owner, command.product, .infantry, true),
        else => false,
    };
}

pub fn tick(world: *state.World) void {
    tickInfantryExits(world);
    for (0..rules.player_count) |owner_index| {
        const owner: state.Owner = @enumFromInt(owner_index);
        for (0..state.queue_count) |queue_index| {
            const queue_kind: state.QueueKind = @enumFromInt(queue_index);
            tickQueue(
                world,
                owner,
                queue_kind,
                &world.queues[owner_index][queue_index],
                &world.players[owner_index],
            );
        }
    }
    tickBuildings(world);
    tickDeployments(world);
}

fn tickInfantryExits(world: *state.World) void {
    for (0..rules.player_count) |owner_index| {
        _ = releaseCompletedInfantry(world, @enumFromInt(owner_index));
        _ = releaseCompletedUnit(world, @enumFromInt(owner_index));
    }
}

/// Stock `ExitWeap`, the Weapons Factory's preferred exit cell list, as cell offsets from the
/// building origin. Vanilla walks this list in order and takes the first usable cell.
const weapons_factory_exits = [_]struct { dx: i16, dy: i16 }{
    .{ .dx = -1, .dy = 3 },
    .{ .dx = 0, .dy = 3 },
    .{ .dx = -1, .dy = 2 },
    .{ .dx = 1, .dy = 3 },
    .{ .dx = -1, .dy = 1 },
    .{ .dx = 3, .dy = 1 },
    .{ .dx = 3, .dy = 2 },
    .{ .dx = 3, .dy = 3 },
};

pub fn releaseCompletedUnit(world: *state.World, owner: state.Owner) bool {
    const queue = &world.queues[@intFromEnum(owner)][@intFromEnum(state.QueueKind.unit)];
    if (!queue.active or !queue.completed) return false;
    const object_rule = rules.object(queue.product) orelse {
        world.failure = .unsupported_content;
        return false;
    };
    if (object_rule.category != .unit) {
        world.failure = .unsupported_content;
        return false;
    }

    const factory = weaponsFactoryOrigin(world, owner) orelse return false;
    const position = state.Position{ .x = factory.x, .y = factory.y + exit_cell_dy };
    // Deliberately tryAddUnit: a full unit array holds the vehicle in the bay for a later frame
    // rather than scoring the episode an engine failure.
    const index = world.tryAddUnit(owner, queue.product, position) orelse return false;
    const unit = &world.units[index];
    // Vanilla drops the vehicle on the building's exit coordinate, not the centre of a cell, and
    // faces it DIR_SW. Confirmed against a full-resolution trace: a Weapons Factory at (2,9)
    // produces a Humvee at cell [2,10], coord [746, 2720], hull and turret 160.
    unit.coord_x = @as(i16, factory.x) * 256 + exit_coord_x;
    unit.coord_y = @as(i16, factory.y) * 256 + exit_coord_y;
    unit.facing = exit_facing;
    unit.turret_facing = exit_facing;
    // It then drives itself clear of the bay toward the preferred stock exit cell.
    if (weaponsFactoryDriveOut(world, factory)) |target| {
        _ = economy.assignExitDrive(world, index, target);
    }
    queue.* = .{};
    return true;
}

/// Stock `ExitWeap` exit point from bdata.cpp, `XYP_COORD(10 + CELL_PIXEL_W / 2,
/// (CELL_PIXEL_H * 3) - CELL_PIXEL_H / 2 - 21)` = (22, 39) pixels, converted at 256 leptons per
/// 24-pixel cell. These reproduce the observed Vanilla coordinates exactly.
const exit_coord_x: i16 = 234;
const exit_coord_y: i16 = 416;
const exit_cell_dy: u8 = 1;
/// DIR_SW (5 << 5): the direction a finished vehicle faces as it clears the bay.
const exit_facing: u8 = 160;

fn weaponsFactoryOrigin(world: *const state.World, owner: state.Owner) ?state.Position {
    for (world.buildings) |building| {
        if (!building.active or !building.operational) continue;
        if (building.owner != owner or building.kind != .weapons_factory) continue;
        return building.position;
    }
    return null;
}

fn weaponsFactoryDriveOut(world: *const state.World, factory: state.Position) ?state.Position {
    for (weapons_factory_exits) |offset| {
        const x = @as(i16, factory.x) + offset.dx;
        const y = @as(i16, factory.y) + offset.dy;
        if (x < 0 or y < 0 or x >= world.map_width or y >= world.map_height) continue;
        const candidate = state.Position{ .x = @intCast(x), .y = @intCast(y) };
        if (cellOccupied(world, candidate)) continue;
        return candidate;
    }
    return null;
}

fn cellOccupied(world: *const state.World, position: state.Position) bool {
    for (world.units) |unit| {
        if (unit.active and unit.position.x == position.x and unit.position.y == position.y) return true;
    }
    for (world.buildings) |building| {
        if (!building.active) continue;
        const object_rule = rules.object(building.kind) orelse continue;
        if (position.x >= building.position.x and
            position.x < building.position.x + object_rule.footprint_width and
            position.y >= building.position.y and
            position.y < building.position.y + object_rule.footprint_height) return true;
    }
    return false;
}

pub fn releaseCompletedInfantry(world: *state.World, owner: state.Owner) bool {
    const queue = &world.queues[@intFromEnum(owner)][@intFromEnum(state.QueueKind.infantry)];
    if (!queue.active or !queue.completed) return false;
    const object_rule = rules.object(queue.product) orelse {
        world.failure = .unsupported_content;
        return false;
    };
    if (object_rule.category != .infantry) {
        world.failure = .unsupported_content;
        return false;
    }
    // A completed queue can race the other player's release into the last global infantry slot.
    // Like a vehicle waiting in its factory bay, hold the completed infantry until capacity frees
    // instead of turning a normal production stall into an engine failure.
    if (world.infantry_count >= rules.max_infantry) return false;

    var exit: ?state.Position = null;
    var has_operational_barracks = false;
    for (world.buildings) |building| {
        if (building.active and building.operational and building.owner == owner and building.kind == .barracks) {
            has_operational_barracks = true;
            if (building.position.x == std.math.maxInt(u8) or building.position.y == std.math.maxInt(u8)) {
                world.failure = .unsupported_content;
                return false;
            }
            const candidate = state.Position{ .x = building.position.x + 1, .y = building.position.y + 1 };
            if (barracksIsTethered(world, owner, candidate)) continue;
            exit = candidate;
        }
    }
    const position = exit orelse {
        if (!has_operational_barracks) world.failure = .unsupported_content;
        return false;
    };
    const index: usize = world.infantry_count;
    world.infantry[index] = .{
        .active = true,
        .kind = queue.product,
        .owner = owner,
        .position = position,
        .home = position,
        .home_valid = true,
        .health = object_rule.strength,
        .coord_x = @as(i16, position.x) * 256 + 64,
        .coord_y = @as(i16, position.y) * 256 + 64,
        .facing = 96,
        .queued_mission = 2,
        .destination = .{ .x = position.x, .y = position.y + 1 },
        .destination_valid = true,
        .pending_move = true,
        .command_delay = 1,
        .arrival_mission_delay = 7,
        .arrival_mission = if (owner == .opponent) 9 else 4,
        .tethered = true,
        .ammo = -1,
        .second_shot = true,
    };
    world.infantry_count += 1;
    queue.* = .{};
    return true;
}

fn barracksIsTethered(world: *const state.World, owner: state.Owner, exit: state.Position) bool {
    for (world.infantry) |infantry| {
        if (!infantry.active or infantry.owner != owner or !infantry.tethered or !infantry.home_valid) continue;
        if (infantry.home.x == exit.x and infantry.home.y == exit.y) return true;
    }
    return false;
}

pub fn abandonUnavailableProduction(world: *state.World, owner: state.Owner, producer: rules.ObjectType) void {
    const queue_kind: state.QueueKind = switch (producer) {
        .construction_yard => .structure,
        .barracks => .infantry,
        else => return,
    };
    for (world.buildings) |building| {
        if (building.active and building.operational and building.owner == owner and building.kind == producer) {
            return;
        }
    }

    const queue = &world.queues[@intFromEnum(owner)][@intFromEnum(queue_kind)];
    if (!queue.active) return;
    if (rules.object(queue.product)) |object_rule| {
        const purchase_cost = difficulty.cost(world, owner, object_rule.cost);
        world.players[@intFromEnum(owner)].credits += @max(0, purchase_cost - queue.balance);
    }
    queue.* = .{};
}

fn deploy(world: *state.World, owner: state.Owner, actor: u8) bool {
    const unit = ownedUnitBySlot(world, owner, actor) orelse return false;
    if (unit.kind != .mcv) return false;

    if (unit.deploying) return false;
    unit.deploying = true;
    const rotation_rate = difficulty.rotationRate(world, owner, mcv_rotation_rate);
    const rotation_frames = (mcv_rotation_span + rotation_rate - 1) / rotation_rate;
    unit.deploy_frames = @intCast(mcv_non_rotation_frames + rotation_frames);
    return true;
}

fn ownedUnitBySlot(world: *state.World, owner: state.Owner, slot: u8) ?*state.Unit {
    var candidate: u8 = 0;
    for (&world.units) |*unit| {
        if (!unit.active or unit.owner != owner) continue;
        if (candidate == slot) return unit;
        candidate += 1;
    }
    return null;
}

fn tickDeployments(world: *state.World) void {
    var skip_player_rotation_tick = false;
    for (world.units) |unit| {
        if (unit.active and unit.kind == .mcv and unit.owner == .opponent and unit.deploying and unit.deploy_frames == 1) {
            for (world.units) |player_unit| {
                if (player_unit.active and player_unit.kind == .mcv and player_unit.owner == .player and
                    player_unit.deploying and player_unit.deploy_frames > 1)
                {
                    // Vanilla compacts Units when the earlier opponent MCV deletes itself,
                    // so the shifted player MCV misses this frame's UnitClass::AI call.
                    skip_player_rotation_tick = true;
                    break;
                }
            }
            break;
        }
    }

    for (&world.units) |*unit| {
        if (!unit.active or !unit.deploying or unit.deploy_frames == 0) continue;
        unit.mission = 15;
        unit.status = 2;
        unit.deploy_frames -= 1;

        const skip_rotation = skip_player_rotation_tick and unit.kind == .mcv and unit.owner == .player;
        const rotation_rate = difficulty.rotationRate(world, unit.owner, mcv_rotation_rate);
        const rotation_frames: u8 = @intCast((mcv_rotation_span + rotation_rate - 1) / rotation_rate);
        if (!skip_rotation and
            unit.deploy_frames <= rotation_frames + 1 and
            unit.deploy_frames != 0 and
            unit.facing != 160)
        {
            unit.facing = if (unit.facing == 0)
                0 -% rotation_rate
            else
                @max(160, unit.facing -| rotation_rate);
        }
        if (unit.deploy_frames != 0) continue;

        if (unit.position.x == 0 or unit.position.y == 0) {
            world.failure = .unsupported_content;
            return;
        }
        const owner = unit.owner;
        const position = state.Position{ .x = unit.position.x - 1, .y = unit.position.y - 1 };
        _ = random.pick(&world.rng_state, 0, 255);
        if (!world.addBuilding(owner, .construction_yard, position)) return;
        unit.active = false;
        unit.deploying = false;
    }
}

fn tickBuildings(world: *state.World) void {
    const player_has_yard = hasPlacedBuilding(world, .player, .construction_yard);
    for (&world.buildings) |*building| {
        if (!building.active or building.operational) continue;
        if (building.construction_frames != 0) {
            building.construction_frames -= 1;
            if (building.construction_frames != 0) continue;
            if (player_has_yard and building.owner == .opponent and building.kind == .construction_yard) {
                // With both mirror yards present, Vanilla reports complete buildup for one
                // frame before transitioning the second yard out of construction mission.
                continue;
            }
        }

        building.operational = true;
        const object_rule = rules.object(building.kind) orelse {
            world.failure = .unsupported_content;
            return;
        };
        world.players[@intFromEnum(building.owner)].drain += object_rule.drain;
        if (building.kind == .refinery and !building.grand_opened) {
            building.grand_opened = true;
            world.players[@intFromEnum(building.owner)].capacity += rules.refinery_capacity;
            economy.grandOpenRefinery(world, @intCast(building - &world.buildings[0]));
        }
    }
}

fn start(
    world: *state.World,
    owner: state.Owner,
    product: rules.ObjectType,
    queue_kind: state.QueueKind,
    easy_ai: bool,
) bool {
    const object_rule = rules.object(product) orelse return false;
    const expected_category: rules.Category = switch (queue_kind) {
        .structure => .building,
        .infantry => .infantry,
        .unit => .unit,
    };
    if (object_rule.category != expected_category) return false;

    const producer: rules.ObjectType = switch (queue_kind) {
        .structure => .construction_yard,
        .infantry => .barracks,
        .unit => .weapons_factory,
    };
    if (easy_ai) {
        if (!hasAIProducer(world, owner, producer)) return false;
        if (object_rule.prerequisite != .none and !hasPlacedBuilding(world, owner, object_rule.prerequisite)) return false;
    } else {
        if (!world.hasBuilding(owner, producer)) return false;
        if (object_rule.prerequisite != .none and !hasPlacedBuilding(world, owner, object_rule.prerequisite)) return false;
    }

    const queue_index: usize = @intFromEnum(queue_kind);
    const queue = &world.queues[@intFromEnum(owner)][queue_index];
    if (queue.active) return false;

    _ = random.pick(&world.rng_state, 0, 255);
    const build_time = effectiveBuildTime(world, owner, product, object_rule.cost);
    const purchase_cost = if (easy_ai)
        difficulty.cost(world, owner, object_rule.cost)
    else
        object_rule.cost;
    const raw_rate = @divTrunc(build_time, @as(i32, rules.production_steps));
    const rate: u8 = @intCast(@max(1, @min(255, raw_rate)));
    queue.* = .{
        .active = true,
        .product = product,
        .stage_timer = rate,
        .rate = rate,
        .balance = purchase_cost,
    };
    return true;
}

fn hasAIProducer(world: *const state.World, owner: state.Owner, kind: rules.ObjectType) bool {
    const player_has_yard = hasPlacedBuilding(world, .player, .construction_yard);
    for (world.buildings) |building| {
        if (!building.active or building.owner != owner or building.kind != kind) continue;
        if (building.operational or building.construction_frames == 0) return true;
        const delayed_mirror_yard = player_has_yard and owner == .opponent and kind == .construction_yard;
        if (building.construction_frames == 1 and !delayed_mirror_yard) return true;
    }
    return false;
}

fn hasPlacedBuilding(world: *const state.World, owner: state.Owner, kind: rules.ObjectType) bool {
    for (world.buildings) |building| {
        if (building.active and building.owner == owner and building.kind == kind) return true;
    }
    return false;
}

fn effectiveBuildTime(
    world: *const state.World,
    owner: state.Owner,
    product: rules.ObjectType,
    purchase_cost: i32,
) i32 {
    // BuildingTypeClass::Raw_Cost excludes the bundled Harvester from Refinery build time.
    const base_cost = if (product == .refinery)
        purchase_cost - rules.object(.harvester).?.cost
    else
        purchase_cost;
    const player = world.players[@intFromEnum(owner)];
    if (player.power == 0) return base_cost * 4;
    if (player.power * 2 < player.drain) return @divTrunc(base_cost * 5, 2);
    if (player.power < player.drain) return @divTrunc(base_cost * 3, 2);
    return base_cost;
}

fn tickQueue(
    world: *const state.World,
    owner: state.Owner,
    queue_kind: state.QueueKind,
    queue: *state.ProductionQueue,
    player: *state.Player,
) void {
    const producer: rules.ObjectType = switch (queue_kind) {
        .structure => .construction_yard,
        .infantry => .barracks,
        .unit => .weapons_factory,
    };
    const stages = if (player.controller == .policy)
        @max(@as(usize, 1), placedProducerCount(world, owner, producer))
    else
        1;

    // Vanilla's human-player FactoryClass advances once per placed producer.
    for (0..stages) |_| {
        tickQueueOnce(queue, player);
        if (queue.completed) break;
    }
}

fn placedProducerCount(world: *const state.World, owner: state.Owner, producer: rules.ObjectType) usize {
    var count: usize = 0;
    for (world.buildings) |building| {
        if (building.active and building.owner == owner and building.kind == producer) count += 1;
    }
    return count;
}

fn tickQueueOnce(queue: *state.ProductionQueue, player: *state.Player) void {
    if (!queue.active or queue.completed or queue.rate == 0) return;

    queue.stage_timer -= 1;
    if (queue.stage_timer != 0) return;
    queue.stage += 1;
    queue.stage_timer = queue.rate;

    const remaining_steps = rules.production_steps - queue.stage;
    const cost = if (remaining_steps == 0)
        queue.balance
    else
        @divTrunc(queue.balance, @as(i32, remaining_steps));
    if (cost > player.credits + player.tiberium) {
        queue.stage -= 1;
        return;
    }
    const from_tiberium = @min(player.tiberium, cost);
    player.tiberium -= from_tiberium;
    player.credits -= cost - from_tiberium;
    queue.balance -= cost;

    if (queue.stage == rules.production_steps) {
        queue.completed = true;
        queue.rate = 0;
        queue.stage_timer = 0;
    }
}

fn place(world: *state.World, owner: state.Owner, product: rules.ObjectType, position: state.Position) bool {
    const queue = &world.queues[@intFromEnum(owner)][@intFromEnum(state.QueueKind.structure)];
    if (!queue.active or !queue.completed or queue.product != product) return false;
    if (!placement.isLegal(world, owner, product, position)) return false;
    if (!world.addBuilding(owner, product, position)) return false;
    queue.* = .{};
    return true;
}
