const action = @import("action.zig");
const current_policy = @import("policy.zig");
const rules = @import("rules.zig");
const state = @import("state.zig");

pub const abi_version: u32 = 9;
pub const observation_size = current_policy.observation_size;
pub const actor_none: u8 = 64;

pub const Head = enum(u8) {
    command,
    actor,
    product,
    target_kind,
    target_x,
    target_y,
    target_slot,
};

pub const Product = enum(u8) {
    none,
    power_plant,
    barracks,
    e1,
    e3,
    refinery,
    // CNC26. Appended so the existing five keep their encodings and older traces stay readable.
    weapons_factory,
    medium_tank,
    humvee,
};

pub const action_head_sizes = [_]u16{ 12, 65, 9, 4, 64, 64, 64 };
pub const action_head_count = action_head_sizes.len;
pub const action_mask_size = sum(action_head_sizes);

pub const RawAction = extern struct {
    command: u8 = 0,
    actor: u8 = actor_none,
    product: u8 = 0,
    target_kind: u8 = 0,
    target_x: u8 = 0,
    target_y: u8 = 0,
    target_slot: u8 = 0,
};

pub fn decode(world: *const state.World, raw: RawAction) ?action.Action {
    _ = world;
    if (raw.command >= action_head_sizes[@intFromEnum(Head.command)] or
        raw.actor >= action_head_sizes[@intFromEnum(Head.actor)] or
        raw.product >= action_head_sizes[@intFromEnum(Head.product)] or
        raw.target_kind >= action_head_sizes[@intFromEnum(Head.target_kind)] or
        raw.target_x >= action_head_sizes[@intFromEnum(Head.target_x)] or
        raw.target_y >= action_head_sizes[@intFromEnum(Head.target_y)] or
        raw.target_slot >= action_head_sizes[@intFromEnum(Head.target_slot)])
    {
        return null;
    }

    return .{
        .command = @enumFromInt(raw.command),
        .actor = raw.actor,
        .product = decodeProduct(@enumFromInt(raw.product)),
        .target_kind = @enumFromInt(raw.target_kind),
        .target_x = raw.target_x,
        .target_y = raw.target_y,
        .target_slot = raw.target_slot,
    };
}

pub fn observe(world: *const state.World, output: *[observation_size]u8) void {
    current_policy.observe(world, output);
}

// ABI9 masks each head independently. Cross-head mismatches are intentionally
// left for the simulator to reject as deterministic no-op decisions.
pub fn actionMask(world: *const state.World, output: *[action_mask_size]u8) void {
    @memset(output, 0);
    const commands = headMask(output, .command);
    const actors = headMask(output, .actor);
    const products = headMask(output, .product);
    const target_kinds = headMask(output, .target_kind);
    const target_x = headMask(output, .target_x);
    const target_y = headMask(output, .target_y);
    const target_slots = headMask(output, .target_slot);

    commands[@intFromEnum(action.Command.noop)] = 1;
    actors[actor_none] = 1;
    products[@intFromEnum(Product.none)] = 1;
    target_kinds[@intFromEnum(action.TargetKind.none)] = 1;

    for (0..world.map_width) |x| target_x[x] = 1;
    for (0..world.map_height) |y| target_y[y] = 1;

    var own_slot: usize = 0;
    // The policy cannot control harvesters, so they never enable a command.
    const has_harvester = false;
    var has_vehicle = false;
    var has_refinery = false;
    for (world.units) |unit| {
        if (!unit.active or unit.owner != .player) continue;
        if (own_slot < current_policy.entity_slot_count and unit.kind == .mcv and !unit.deploying) {
            actors[own_slot] = 1;
            commands[@intFromEnum(action.Command.deploy)] = 1;
        } else if (own_slot < current_policy.entity_slot_count and
            (unit.kind == .medium_tank or unit.kind == .humvee))
        {
            // CNC26 combat vehicles are controllable exactly like infantry. Without an actor slot
            // a purchased tank could never be moved or ordered to fire -- 800 credits for a unit
            // that only ever auto-engaged whatever wandered into range.
            actors[own_slot] = 1;
            has_vehicle = true;
        } else if (own_slot < current_policy.entity_slot_count and unit.kind == .harvester) {
            // The policy cannot control the harvester at all: no actor slot, and it enables no
            // commands. economy.zig gives a new harvester mission_harvest and it mines the nearest
            // tiberium unaided, exactly as Vanilla does. Exposing it let the policy issue move
            // orders -- over a thousand per game -- which pulled it off the field and destroyed the
            // economy. With it excluded, harvest and return_cargo have no actor and are never
            // offered, so mining is always left to the simulator.
        }
        own_slot += 1;
    }
    for (world.buildings) |building| {
        if (!building.active or building.owner != .player) continue;
        if (building.kind == .refinery and building.operational and
            own_slot < current_policy.entity_slot_count)
        {
            target_slots[own_slot] = 1;
            has_refinery = true;
        }
        own_slot += 1;
    }

    const enemy_count = activeEntityCount(world, .opponent);
    var has_infantry = false;
    for (world.infantry) |infantry| {
        if (!infantry.active or infantry.owner != .player) continue;
        if (own_slot < current_policy.entity_slot_count) actors[own_slot] = 1;
        own_slot += 1;
        has_infantry = true;
    }
    if (has_infantry or has_vehicle or has_harvester) {
        commands[@intFromEnum(action.Command.move)] = 1;
        target_kinds[@intFromEnum(action.TargetKind.cell)] = 1;
    }
    if (has_harvester) {
        commands[@intFromEnum(action.Command.harvest)] = 1;
        target_kinds[@intFromEnum(action.TargetKind.cell)] = 1;
        if (has_refinery) {
            commands[@intFromEnum(action.Command.return_cargo)] = 1;
            target_kinds[@intFromEnum(action.TargetKind.own_entity)] = 1;
        }
    }
    if ((has_infantry or has_vehicle) and enemy_count != 0) {
        commands[@intFromEnum(action.Command.attack)] = 1;
        target_kinds[@intFromEnum(action.TargetKind.visible_enemy)] = 1;
    }

    if (canStart(world, .power_plant, .structure)) {
        commands[@intFromEnum(action.Command.start_build)] = 1;
        products[@intFromEnum(Product.power_plant)] = 1;
    }
    if (canStart(world, .barracks, .structure)) {
        commands[@intFromEnum(action.Command.start_build)] = 1;
        products[@intFromEnum(Product.barracks)] = 1;
    }
    if (canStart(world, .refinery, .structure)) {
        commands[@intFromEnum(action.Command.start_build)] = 1;
        products[@intFromEnum(Product.refinery)] = 1;
    }
    if (canStart(world, .weapons_factory, .structure)) {
        commands[@intFromEnum(action.Command.start_build)] = 1;
        products[@intFromEnum(Product.weapons_factory)] = 1;
    }
    // production.buildQueueKind routes start_build by category: structures to the Construction
    // Yard queue, vehicles to the Weapons Factory queue. Infantry keep the separate train command.
    // Offering vehicles under train made every such action fail.
    if (canStart(world, .medium_tank, .unit)) {
        commands[@intFromEnum(action.Command.start_build)] = 1;
        products[@intFromEnum(Product.medium_tank)] = 1;
    }
    if (canStart(world, .humvee, .unit)) {
        commands[@intFromEnum(action.Command.start_build)] = 1;
        products[@intFromEnum(Product.humvee)] = 1;
    }
    if (canStart(world, .e1, .infantry)) {
        commands[@intFromEnum(action.Command.train)] = 1;
        products[@intFromEnum(Product.e1)] = 1;
    }
    if (canStart(world, .e3, .infantry)) {
        commands[@intFromEnum(action.Command.train)] = 1;
        products[@intFromEnum(Product.e3)] = 1;
    }

    const structure_queue = world.queues[@intFromEnum(state.Owner.player)][@intFromEnum(state.QueueKind.structure)];
    if (structure_queue.active and structure_queue.completed) {
        if (encodeProduct(structure_queue.product)) |product| {
            commands[@intFromEnum(action.Command.place)] = 1;
            products[@intFromEnum(product)] = 1;
            target_kinds[@intFromEnum(action.TargetKind.cell)] = 1;
        }
    }

    const usable_target_count = @min(enemy_count, current_policy.entity_slot_count);
    for (0..usable_target_count) |slot| target_slots[slot] = 1;
    var has_target_slot = false;
    for (target_slots) |enabled| has_target_slot = has_target_slot or enabled != 0;
    if (!has_target_slot) target_slots[0] = 1;
}

pub fn headMask(mask: *[action_mask_size]u8, head: Head) []u8 {
    const index: usize = @intFromEnum(head);
    const offset = headOffset(index);
    return mask[offset .. offset + action_head_sizes[index]];
}

fn canStart(world: *const state.World, product: rules.ObjectType, queue_kind: state.QueueKind) bool {
    const object_rule = rules.object(product) orelse return false;
    const expected: rules.Category = switch (queue_kind) {
        .structure => .building,
        .infantry => .infantry,
        .unit => .unit,
    };
    if (object_rule.category != expected) return false;
    const producer: rules.ObjectType = switch (queue_kind) {
        .structure => .construction_yard,
        .infantry => .barracks,
        .unit => .weapons_factory,
    };
    if (!world.hasBuilding(.player, producer)) return false;
    // Economy gate: the barracks is withheld until a refinery exists, so the opening is forced to
    // power plant -> refinery -> barracks -> army. Reward shaping could not achieve this -- the
    // refinery loses to infantry at every weighting tried -- and penalising the alternative taught
    // avoidance instead of ordering. Making the wrong opening unavailable leaves nothing to trade off.
    if (product == .barracks and !hasPlacedBuilding(world, .player, .refinery)) return false;
    // max_units is shared by both players and holds MCVs and harvesters as well as vehicles. A
    // full array no longer fails the episode -- production.releaseCompletedUnit holds the vehicle
    // in the bay -- but spending on armour that cannot roll out is still wasted, so vehicles stop
    // being offered while headroom is thin. The reserve leaves room for a harvester to spawn.
    if (queue_kind == .unit and world.freeUnitSlots() <= unit_capacity_reserve) return false;
    if (object_rule.prerequisite != .none and
        !hasPlacedBuilding(world, .player, object_rule.prerequisite)) return false;
    return !world.queues[@intFromEnum(state.Owner.player)][@intFromEnum(queue_kind)].active;
}

/// Slots held back so a refinery's harvester can still arrive when armour is being produced.
const unit_capacity_reserve: usize = 3;

fn hasPlacedBuilding(world: *const state.World, owner: state.Owner, kind: rules.ObjectType) bool {
    for (world.buildings) |building| {
        if (building.active and building.owner == owner and building.kind == kind) return true;
    }
    return false;
}

fn activeEntityCount(world: *const state.World, owner: state.Owner) usize {
    var count: usize = 0;
    for (world.units) |unit| if (unit.active and unit.owner == owner) {
        count += 1;
    };
    for (world.buildings) |building| if (building.active and building.owner == owner) {
        count += 1;
    };
    for (world.infantry) |infantry| if (infantry.active and infantry.owner == owner) {
        count += 1;
    };
    return count;
}

fn decodeProduct(product: Product) rules.ObjectType {
    return switch (product) {
        .none => .none,
        .power_plant => .power_plant,
        .barracks => .barracks,
        .e1 => .e1,
        .e3 => .e3,
        .refinery => .refinery,
        .weapons_factory => .weapons_factory,
        .medium_tank => .medium_tank,
        .humvee => .humvee,
    };
}

fn encodeProduct(product: rules.ObjectType) ?Product {
    return switch (product) {
        .power_plant => .power_plant,
        .barracks => .barracks,
        .e1 => .e1,
        .e3 => .e3,
        .refinery => .refinery,
        .weapons_factory => .weapons_factory,
        .medium_tank => .medium_tank,
        .humvee => .humvee,
        else => null,
    };
}

fn headOffset(head_index: usize) usize {
    var offset: usize = 0;
    for (action_head_sizes[0..head_index]) |size| offset += size;
    return offset;
}

fn sum(values: anytype) usize {
    var result: usize = 0;
    for (values) |value| result += value;
    return result;
}
