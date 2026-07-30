const std = @import("std");
const action = @import("action.zig");
const difficulty = @import("difficulty.zig");
const map = @import("map.zig");
const placement = @import("placement.zig");
const rules = @import("rules.zig");
const state = @import("state.zig");

pub const abi_version: u32 = 13;
pub const observation_version: u8 = 7;

pub const Head = enum(u8) {
    command,
    arg0,
    arg1,
    arg2,
};

pub const Product = enum(u8) {
    none,
    power_plant,
    barracks,
    e1,
    e3,
    refinery,
    weapons_factory,
    medium_tank,
    humvee,
};

pub const command_count: usize = 12;
pub const token_count: usize = 65;
pub const coordinate_count: usize = 64;
pub const pad_token: u8 = 64;
pub const action_head_sizes = [_]u16{ command_count, token_count, token_count, token_count };
pub const action_head_count = action_head_sizes.len;
pub const actor_none: u8 = pad_token;
pub const actor_target_rank: usize = 4;
pub const actor_target_scale: f32 = 0.5;
pub const actor_target_bound: f32 = 2.0;
pub const actor_query_group_count: usize = 4;
pub const target_key_branch_count: usize = 6;

pub const command_logits_offset: usize = 0;
pub const arg0_command_logits_offset: usize = command_logits_offset + command_count;
pub const arg1_command_logits_offset: usize = arg0_command_logits_offset + command_count * token_count;
pub const arg2_command_logits_offset: usize = arg1_command_logits_offset + command_count * token_count;
pub const base_logit_count: usize = arg2_command_logits_offset + command_count * token_count;
pub const actor_query_logits_offset: usize = base_logit_count;
pub const target_key_logits_offset: usize = actor_query_logits_offset +
    actor_query_group_count * entity_slot_count * actor_target_rank;
pub const action_logit_count: usize = target_key_logits_offset +
    target_key_branch_count * entity_slot_count * actor_target_rank;
pub const decoder_size: usize = action_logit_count + 1;

pub const command_mask_offset: usize = 0;
pub const pad_mask_offset: usize = command_mask_offset + command_count;
pub const deploy_actor_mask_offset: usize = pad_mask_offset + token_count;
pub const build_product_mask_offset: usize = deploy_actor_mask_offset + token_count;
pub const place_x_mask_offset: usize = build_product_mask_offset + token_count;
pub const place_y_mask_offset: usize = place_x_mask_offset + token_count;
pub const train_product_mask_offset: usize = place_y_mask_offset + coordinate_count * token_count;
pub const move_actor_mask_offset: usize = train_product_mask_offset + token_count;
pub const move_x_mask_offset: usize = move_actor_mask_offset + token_count;
pub const move_y_mask_offset: usize = move_x_mask_offset + token_count;
pub const attack_actor_mask_offset: usize = move_y_mask_offset + token_count;
pub const attack_target_mask_offset: usize = attack_actor_mask_offset + token_count;
pub const harvest_actor_mask_offset: usize = attack_target_mask_offset + token_count;
pub const harvest_x_mask_offset: usize = harvest_actor_mask_offset + token_count;
pub const harvest_y_mask_offset: usize = harvest_x_mask_offset + token_count;
pub const return_actor_mask_offset: usize = harvest_y_mask_offset + coordinate_count * token_count;
pub const return_target_mask_offset: usize = return_actor_mask_offset + token_count;
pub const action_mask_bit_count: usize = return_target_mask_offset + token_count;
pub const action_mask_size: usize = (action_mask_bit_count + 7) / 8;

pub const map_side: usize = 64;
pub const map_cell_count = map_side * map_side;
pub const global_size: usize = 64;
pub const scenario_id_offset: usize = 32;
pub const opponent_difficulty_offset: usize = 33;
pub const entity_slot_count: usize = 64;
pub const legacy_entity_record_size: usize = 16;
pub const entity_type_count: usize = 12;
pub const entity_type_one_hot_offset: usize = legacy_entity_record_size;
pub const entity_record_size: usize = legacy_entity_record_size + entity_type_count;
pub const entity_presence: usize = 0;
pub const entity_type: usize = 1;
pub const entity_id_low: usize = 2;
pub const entity_id_high: usize = 3;
pub const entity_x: usize = 4;
pub const entity_y: usize = 5;
pub const entity_health: usize = 6;
pub const entity_facing: usize = 7;
pub const entity_mission: usize = 8;
pub const entity_target_kind: usize = 9;
pub const entity_target_slot: usize = 10;
pub const entity_cooldown: usize = 11;
pub const entity_flags: usize = 12;
pub const entity_progress: usize = 13;
pub const entity_category: usize = 14;
pub const entity_status: usize = 15;

pub const legacy_observation_version: u8 = 4;
pub const legacy_map_offset: usize = global_size;
pub const map_land_mask: u8 = 0x07;
pub const map_passable_bit: u8 = 0x08;
pub const map_buildable_bit: u8 = 0x10;
pub const map_visible_bit: u8 = 0x20;
pub const map_occupancy_mask: u8 = 0xc0;
pub const map_occupancy_shift: u3 = 6;
pub const tiberium_cell_count: usize = countInitialTiberiumCells();
const tiberium_offset = global_size;
const own_entities_offset = tiberium_offset + tiberium_cell_count;
const enemy_entities_offset = own_entities_offset + entity_slot_count * entity_record_size;
pub const observation_size = enemy_entities_offset + entity_slot_count * entity_record_size;

const legacy_own_entities_offset = legacy_map_offset + map_cell_count;
const legacy_enemy_entities_offset =
    legacy_own_entities_offset + entity_slot_count * legacy_entity_record_size;
pub const legacy_observation_size =
    legacy_enemy_entities_offset + entity_slot_count * legacy_entity_record_size;

const initial_map_template = buildMapTemplate(true);
const depleted_map_template = buildMapTemplate(false);
const initial_tiberium_rows = buildInitialTiberiumRows();
pub const initial_tiberium_positions = buildInitialTiberiumPositions();

pub const RawAction = extern struct {
    command: u8 = @intFromEnum(action.Command.noop),
    arg0: u8 = pad_token,
    arg1: u8 = pad_token,
    arg2: u8 = pad_token,
};

const ActorQueryGroup = enum(usize) {
    move,
    attack,
    harvest,
    return_cargo,
};

const TargetKeyBranch = enum(usize) {
    move_x,
    move_y,
    attack_target,
    harvest_x,
    harvest_y,
    return_target,
};

fn actorQueryGroup(command: action.Command) ?ActorQueryGroup {
    return switch (command) {
        .move => .move,
        .attack => .attack,
        .harvest => .harvest,
        .return_cargo => .return_cargo,
        else => null,
    };
}

fn targetKeyBranch(command: action.Command, argument_index: u2) ?TargetKeyBranch {
    return switch (argument_index) {
        1 => switch (command) {
            .move => .move_x,
            .attack => .attack_target,
            .harvest => .harvest_x,
            .return_cargo => .return_target,
            else => null,
        },
        2 => switch (command) {
            .move => .move_y,
            .harvest => .harvest_y,
            else => null,
        },
        else => null,
    };
}

pub fn actorQueryOffset(command: action.Command, actor_slot: u8) ?usize {
    if (actor_slot >= entity_slot_count) return null;
    const group = actorQueryGroup(command) orelse return null;
    return actor_query_logits_offset +
        (@intFromEnum(group) * entity_slot_count + actor_slot) * actor_target_rank;
}

pub fn targetKeyOffset(command: action.Command, argument_index: u2, target: u8) ?usize {
    if (target >= entity_slot_count) return null;
    const branch = targetKeyBranch(command, argument_index) orelse return null;
    return target_key_logits_offset +
        (@intFromEnum(branch) * entity_slot_count + target) * actor_target_rank;
}

pub fn decode(world: *const state.World, raw: RawAction) ?action.Action {
    if (raw.command >= command_count or raw.arg0 >= token_count or
        raw.arg1 >= token_count or raw.arg2 >= token_count)
    {
        return null;
    }

    const command: action.Command = @enumFromInt(raw.command);
    return switch (command) {
        .noop => if (canonicalPadding(raw, 0)) .{ .command = .noop } else null,
        .deploy => if (raw.arg0 < coordinate_count and canonicalPadding(raw, 1))
            .{ .command = .deploy, .actor = raw.arg0 }
        else
            null,
        .start_build => if (decodeBuildProduct(raw.arg0)) |product|
            if (canonicalPadding(raw, 1)) .{ .command = .start_build, .product = product } else null
        else
            null,
        .place => decodePlacement(world, raw),
        .train => if (decodeTrainProduct(raw.arg0)) |product|
            if (canonicalPadding(raw, 1)) .{ .command = .train, .product = product } else null
        else
            null,
        .move => if (raw.arg0 < coordinate_count and validCell(world, raw.arg1, raw.arg2))
            .{
                .command = .move,
                .actor = raw.arg0,
                .target_kind = .cell,
                .target_x = raw.arg1,
                .target_y = raw.arg2,
            }
        else
            null,
        .attack => if (raw.arg0 < coordinate_count and raw.arg1 < entity_slot_count and canonicalPadding(raw, 2))
            .{
                .command = .attack,
                .actor = raw.arg0,
                .target_kind = .visible_enemy,
                .target_slot = raw.arg1,
            }
        else
            null,
        .harvest => if (raw.arg0 < coordinate_count and validCell(world, raw.arg1, raw.arg2))
            .{
                .command = .harvest,
                .actor = raw.arg0,
                .target_kind = .cell,
                .target_x = raw.arg1,
                .target_y = raw.arg2,
            }
        else
            null,
        .return_cargo => if (raw.arg0 < coordinate_count and raw.arg1 < entity_slot_count and canonicalPadding(raw, 2))
            .{
                .command = .return_cargo,
                .actor = raw.arg0,
                .target_kind = .own_entity,
                .target_slot = raw.arg1,
            }
        else
            null,
        .guard, .stop, .hunt => null,
    };
}

pub fn observe(world: *const state.World, output: *[observation_size]u8) void {
    @memset(output, 0);
    encodeGlobals(world, output[0..global_size], observation_version, true);
    encodeTiberium(world, output[tiberium_offset..own_entities_offset]);
    encodeEntities(
        world,
        .player,
        entity_record_size,
        output[own_entities_offset..enemy_entities_offset],
    );
    encodeEntities(
        world,
        .opponent,
        entity_record_size,
        output[enemy_entities_offset..observation_size],
    );
}

pub fn observeLegacyV4(world: *const state.World, output: *[legacy_observation_size]u8) void {
    @memset(output, 0);
    encodeGlobals(world, output[0..global_size], legacy_observation_version, false);
    encodeLegacyMap(world, output[legacy_map_offset..legacy_own_entities_offset]);
    encodeEntities(
        world,
        .player,
        legacy_entity_record_size,
        output[legacy_own_entities_offset..legacy_enemy_entities_offset],
    );
    encodeEntities(
        world,
        .opponent,
        legacy_entity_record_size,
        output[legacy_enemy_entities_offset..legacy_observation_size],
    );
}

pub fn tiberiumBytes(observation: *const [observation_size]u8) []const u8 {
    return observation[tiberium_offset..own_entities_offset];
}

pub fn ownEntityBytes(observation: *const [observation_size]u8) []const u8 {
    return observation[own_entities_offset..enemy_entities_offset];
}

pub fn enemyEntityBytes(observation: *const [observation_size]u8) []const u8 {
    return observation[enemy_entities_offset..observation_size];
}

pub fn legacyOwnEntityBytes(observation: *const [legacy_observation_size]u8) []const u8 {
    return observation[legacy_own_entities_offset..legacy_enemy_entities_offset];
}

pub fn legacyEnemyEntityBytes(observation: *const [legacy_observation_size]u8) []const u8 {
    return observation[legacy_enemy_entities_offset..legacy_observation_size];
}

pub fn actionMask(world: *const state.World, output: *[action_mask_size]u8) void {
    @memset(output, 0);
    enableMaskValue(output, pad_mask_offset, pad_token);
    enableMaskValue(output, command_mask_offset, @intFromEnum(action.Command.noop));
    for (0..world.map_width) |x| enableMaskValue(output, move_x_mask_offset, x);
    for (0..world.map_height) |y| enableMaskValue(output, move_y_mask_offset, y);

    var own_slot: usize = 0;
    for (world.units) |unit| {
        if (!unit.active or unit.owner != .player) continue;
        if (own_slot < entity_slot_count and unit.kind == .mcv and !unit.deploying) {
            enableMaskValue(output, deploy_actor_mask_offset, own_slot);
        } else if (own_slot < entity_slot_count and
            (unit.kind == .medium_tank or unit.kind == .humvee))
        {
            enableMaskValue(output, move_actor_mask_offset, own_slot);
            enableMaskValue(output, attack_actor_mask_offset, own_slot);
        } else if (own_slot < entity_slot_count and unit.kind == .harvester) {
            // Harvesters already run the Vanilla-validated autonomous harvest/return loop.
            // Policy move orders replace that mission and strand the economy, so keep the entity
            // observable while withholding every actor command.
        }
        own_slot += 1;
    }
    for (world.buildings) |building| {
        if (!building.active or building.owner != .player) continue;
        if (building.kind == .refinery and building.operational and own_slot < entity_slot_count) {
            enableMaskValue(output, return_target_mask_offset, own_slot);
        }
        own_slot += 1;
    }

    for (world.infantry) |infantry| {
        if (!infantry.active or infantry.owner != .player) continue;
        if (own_slot < entity_slot_count) {
            enableMaskValue(output, move_actor_mask_offset, own_slot);
            if (infantry.kind == .e1 or infantry.kind == .e3) {
                enableMaskValue(output, attack_actor_mask_offset, own_slot);
            }
        }
        own_slot += 1;
    }

    if (canStart(world, .power_plant, .structure)) {
        enableMaskValue(output, build_product_mask_offset, @intFromEnum(Product.power_plant));
    }
    if (canStart(world, .barracks, .structure)) {
        enableMaskValue(output, build_product_mask_offset, @intFromEnum(Product.barracks));
    }
    if (canStart(world, .refinery, .structure)) {
        enableMaskValue(output, build_product_mask_offset, @intFromEnum(Product.refinery));
    }
    if (canStart(world, .weapons_factory, .structure)) {
        enableMaskValue(output, build_product_mask_offset, @intFromEnum(Product.weapons_factory));
    }
    if (canStart(world, .medium_tank, .unit)) {
        enableMaskValue(output, build_product_mask_offset, @intFromEnum(Product.medium_tank));
    }
    if (canStart(world, .humvee, .unit)) {
        enableMaskValue(output, build_product_mask_offset, @intFromEnum(Product.humvee));
    }
    if (canStart(world, .e1, .infantry)) {
        enableMaskValue(output, train_product_mask_offset, @intFromEnum(Product.e1));
    }
    if (canStart(world, .e3, .infantry)) {
        enableMaskValue(output, train_product_mask_offset, @intFromEnum(Product.e3));
    }

    const structure_queue = world.queues[@intFromEnum(state.Owner.player)][@intFromEnum(state.QueueKind.structure)];
    if (structure_queue.active and structure_queue.completed) {
        if (encodeProduct(structure_queue.product) != null) {
            var legal_origins: [map_side]u64 = undefined;
            placement.legalOriginRows(world, .player, structure_queue.product, &legal_origins);
            for (legal_origins, 0..) |row, y| {
                var remaining = row;
                while (remaining != 0) {
                    const x: usize = @intCast(@ctz(remaining));
                    enableMaskValue(output, place_x_mask_offset, x);
                    enableMaskValue(output, place_y_mask_offset + x * token_count, y);
                    remaining &= remaining - 1;
                }
            }
        }
    }

    const enemy_count = @min(activeEntityCount(world, .opponent), entity_slot_count);
    for (0..enemy_count) |slot| enableMaskValue(output, attack_target_mask_offset, slot);

    for (initial_tiberium_positions) |position| {
        if (!world.hasTiberium(position)) continue;
        enableMaskValue(output, harvest_x_mask_offset, position.x);
        enableMaskValue(
            output,
            harvest_y_mask_offset + @as(usize, position.x) * token_count,
            position.y,
        );
    }

    if (maskRangeHasAny(output, deploy_actor_mask_offset, token_count))
        enableMaskValue(output, command_mask_offset, @intFromEnum(action.Command.deploy));
    if (maskRangeHasAny(output, build_product_mask_offset, token_count))
        enableMaskValue(output, command_mask_offset, @intFromEnum(action.Command.start_build));
    if (maskRangeHasAny(output, place_x_mask_offset, token_count))
        enableMaskValue(output, command_mask_offset, @intFromEnum(action.Command.place));
    if (maskRangeHasAny(output, train_product_mask_offset, token_count))
        enableMaskValue(output, command_mask_offset, @intFromEnum(action.Command.train));
    if (maskRangeHasAny(output, move_actor_mask_offset, token_count))
        enableMaskValue(output, command_mask_offset, @intFromEnum(action.Command.move));
    if (maskRangeHasAny(output, attack_actor_mask_offset, token_count) and
        maskRangeHasAny(output, attack_target_mask_offset, token_count))
    {
        enableMaskValue(output, command_mask_offset, @intFromEnum(action.Command.attack));
    }
    if (maskRangeHasAny(output, harvest_actor_mask_offset, token_count) and
        maskRangeHasAny(output, harvest_x_mask_offset, token_count))
    {
        enableMaskValue(output, command_mask_offset, @intFromEnum(action.Command.harvest));
    }
    if (maskRangeHasAny(output, return_actor_mask_offset, token_count) and
        maskRangeHasAny(output, return_target_mask_offset, token_count))
    {
        enableMaskValue(output, command_mask_offset, @intFromEnum(action.Command.return_cargo));
    }
}

pub fn commandAllowed(mask: *const [action_mask_size]u8, command: action.Command) bool {
    return maskBitEnabled(mask, command_mask_offset + @intFromEnum(command));
}

pub fn argumentAllowed(
    mask: *const [action_mask_size]u8,
    command: action.Command,
    argument_index: u2,
    prior_token: u8,
    token: u8,
) bool {
    if (token >= token_count) return false;
    const offset = argumentMaskBitOffset(command, argument_index, prior_token) orelse return false;
    return maskBitEnabled(mask, offset + token);
}

pub fn argumentMaskBitOffset(
    command: action.Command,
    argument_index: u2,
    prior_token: u8,
) ?usize {
    return switch (command) {
        .noop => pad_mask_offset,
        .deploy => if (argument_index == 0) deploy_actor_mask_offset else pad_mask_offset,
        .start_build => if (argument_index == 0) build_product_mask_offset else pad_mask_offset,
        .place => switch (argument_index) {
            0 => place_x_mask_offset,
            1 => matrixRowOffset(place_y_mask_offset, prior_token) orelse return null,
            2 => pad_mask_offset,
            else => unreachable,
        },
        .train => if (argument_index == 0) train_product_mask_offset else pad_mask_offset,
        .move => switch (argument_index) {
            0 => move_actor_mask_offset,
            1 => move_x_mask_offset,
            2 => move_y_mask_offset,
            else => unreachable,
        },
        .attack => switch (argument_index) {
            0 => attack_actor_mask_offset,
            1 => attack_target_mask_offset,
            2 => pad_mask_offset,
            else => unreachable,
        },
        .harvest => switch (argument_index) {
            0 => harvest_actor_mask_offset,
            1 => harvest_x_mask_offset,
            2 => matrixRowOffset(harvest_y_mask_offset, prior_token) orelse return null,
            else => unreachable,
        },
        .return_cargo => switch (argument_index) {
            0 => return_actor_mask_offset,
            1 => return_target_mask_offset,
            2 => pad_mask_offset,
            else => unreachable,
        },
        .guard, .stop, .hunt => pad_mask_offset,
    };
}

fn canonicalPadding(raw: RawAction, used_arguments: u2) bool {
    return switch (used_arguments) {
        0 => raw.arg0 == pad_token and raw.arg1 == pad_token and raw.arg2 == pad_token,
        1 => raw.arg1 == pad_token and raw.arg2 == pad_token,
        2 => raw.arg2 == pad_token,
        3 => true,
    };
}

fn decodeBuildProduct(token: u8) ?rules.ObjectType {
    return switch (token) {
        @intFromEnum(Product.power_plant) => .power_plant,
        @intFromEnum(Product.barracks) => .barracks,
        @intFromEnum(Product.refinery) => .refinery,
        @intFromEnum(Product.weapons_factory) => .weapons_factory,
        @intFromEnum(Product.medium_tank) => .medium_tank,
        @intFromEnum(Product.humvee) => .humvee,
        else => null,
    };
}

fn decodeTrainProduct(token: u8) ?rules.ObjectType {
    return switch (token) {
        @intFromEnum(Product.e1) => .e1,
        @intFromEnum(Product.e3) => .e3,
        else => null,
    };
}

fn decodePlacement(world: *const state.World, raw: RawAction) ?action.Action {
    if (!canonicalPadding(raw, 2) or !validCell(world, raw.arg0, raw.arg1)) return null;
    const queue = world.queues[@intFromEnum(state.Owner.player)][@intFromEnum(state.QueueKind.structure)];
    if (!queue.active or !queue.completed or encodeProduct(queue.product) == null) return null;
    return .{
        .command = .place,
        .product = queue.product,
        .target_kind = .cell,
        .target_x = raw.arg0,
        .target_y = raw.arg1,
    };
}

fn validCell(world: *const state.World, x: u8, y: u8) bool {
    return x < world.map_width and y < world.map_height;
}

fn matrixRowOffset(base_offset: usize, coordinate: u8) ?usize {
    if (coordinate >= coordinate_count) return null;
    return base_offset + @as(usize, coordinate) * token_count;
}

fn enableMaskValue(mask: *[action_mask_size]u8, offset: usize, value: anytype) void {
    const bit_index = offset + @as(usize, @intCast(value));
    std.debug.assert(bit_index < action_mask_bit_count);
    mask[bit_index / 8] |= @as(u8, 1) << @intCast(bit_index % 8);
}

fn maskBitEnabled(mask: *const [action_mask_size]u8, bit_index: usize) bool {
    if (bit_index >= action_mask_bit_count) return false;
    return mask[bit_index / 8] & (@as(u8, 1) << @intCast(bit_index % 8)) != 0;
}

fn maskRangeHasAny(mask: *const [action_mask_size]u8, offset: usize, count: usize) bool {
    for (0..count) |value| if (maskBitEnabled(mask, offset + value)) return true;
    return false;
}

fn encodeGlobals(world: *const state.World, output: []u8, version: u8, include_scenario: bool) void {
    const player = world.players[@intFromEnum(state.Owner.player)];
    output[0] = version;
    output[1] = world.map_width;
    output[2] = world.map_height;
    output[3] = clippedU8(world.frame / 32);
    output[4] = clippedU8(@divFloor(@max(player.credits, 0), 100));
    output[5] = clippedU8(@max(player.power, 0));
    output[6] = clippedU8(@max(player.drain, 0));
    output[7] = @intFromBool(player.defeated);
    output[8] = @intFromBool(world.players[@intFromEnum(state.Owner.opponent)].defeated);
    output[9] = @intFromEnum(world.failure);

    encodeQueue(world.queues[0][@intFromEnum(state.QueueKind.structure)], output[10..15]);
    encodeQueue(world.queues[0][@intFromEnum(state.QueueKind.infantry)], output[15..20]);
    output[20] = clippedU8(activeCategoryCount(world, .player, .unit));
    output[21] = clippedU8(activeCategoryCount(world, .player, .building));
    output[22] = clippedU8(activeCategoryCount(world, .player, .infantry));
    output[23] = clippedU8(activeCategoryCount(world, .opponent, .unit));
    output[24] = clippedU8(activeCategoryCount(world, .opponent, .building));
    output[25] = clippedU8(activeCategoryCount(world, .opponent, .infantry));
    output[26] = clippedU8(@divFloor(@max(player.tiberium, 0), 25));
    output[27] = clippedU8(@divFloor(@max(player.capacity, 0), 25));
    output[28] = clippedU8(@divFloor(player.harvested_credits, 25));
    const opponent = world.players[@intFromEnum(state.Owner.opponent)];
    output[29] = clippedU8(@divFloor(@max(opponent.tiberium, 0), 25));
    output[30] = clippedU8(@divFloor(@max(opponent.capacity, 0), 25));
    output[31] = clippedU8(totalTiberiumSteps(world));
    if (include_scenario) output[scenario_id_offset] = map.scenario_id;
    if (version >= observation_version) {
        output[opponent_difficulty_offset] = @intFromEnum(difficulty.requested(world));
    }
}

fn encodeQueue(queue: state.ProductionQueue, output: []u8) void {
    output[0] = @intFromBool(queue.active);
    output[1] = @intFromBool(queue.completed);
    output[2] = @intFromEnum(queue.product);
    output[3] = @intCast(@divFloor(@as(u16, queue.stage) * 255, rules.production_steps));
    output[4] = queue.stage_timer;
}

fn encodeTiberium(world: *const state.World, output: []u8) void {
    for (initial_tiberium_positions, 0..) |position, index| {
        const row = world.tiberium_present[position.y];
        const map_index = @as(usize, position.y) * map_side + position.x;
        output[index] = if (row & (@as(u64, 1) << @intCast(position.x)) != 0)
            initial_map_template[map_index]
        else
            depleted_map_template[map_index];
    }
}

fn encodeLegacyMap(world: *const state.World, cells: []u8) void {
    @memcpy(cells, initial_map_template[0..]);

    for (0..map.height) |y| {
        var depleted = initial_tiberium_rows[y] & ~world.tiberium_present[y];
        while (depleted != 0) {
            const x: usize = @intCast(@ctz(depleted));
            const index = y * map_side + x;
            cells[index] = depleted_map_template[index];
            depleted &= depleted - 1;
        }
    }

    encodeOccupancy(world, cells);
}

fn countInitialTiberiumCells() usize {
    @setEvalBranchQuota(20_000);
    var count: usize = 0;
    for (map.cells) |cell| {
        if (cell.land_type == 5) count += 1;
    }
    return count;
}

fn buildInitialTiberiumPositions() [tiberium_cell_count]state.Position {
    @setEvalBranchQuota(20_000);
    var result: [tiberium_cell_count]state.Position = undefined;
    var index: usize = 0;
    for (0..map.height) |y| {
        for (0..map.width) |x| {
            if (map.cells[y * @as(usize, map.width) + x].land_type != 5) continue;
            result[index] = .{ .x = @intCast(x), .y = @intCast(y) };
            index += 1;
        }
    }
    return result;
}

fn buildMapTemplate(initial_tiberium: bool) [map_cell_count]u8 {
    @setEvalBranchQuota(20_000);
    var result = [_]u8{map_land_mask} ** map_cell_count;
    for (0..map.height) |y| {
        for (0..map.width) |x| {
            const cell = map.cells[y * @as(usize, map.width) + x];
            result[y * map_side + x] = encodeTerrain(cell, initial_tiberium and cell.land_type == 5);
        }
    }
    return result;
}

fn buildInitialTiberiumRows() [map_side]u64 {
    @setEvalBranchQuota(20_000);
    var result = [_]u64{0} ** map_side;
    for (0..map.height) |y| {
        for (0..map.width) |x| {
            const cell = map.cells[y * @as(usize, map.width) + x];
            if (cell.land_type == 5) result[y] |= @as(u64, 1) << @intCast(x);
        }
    }
    return result;
}

fn encodeTerrain(cell: map.Cell, has_tiberium: bool) u8 {
    const land_type: u8 = if (cell.land_type == 5 and !has_tiberium) 0 else cell.land_type;
    const buildable = (cell.ground_buildable or (cell.land_type == 5 and !has_tiberium)) and
        !cell.static_blocked;
    return (land_type & map_land_mask) |
        (if (cell.foot_passable) map_passable_bit else 0) |
        (if (buildable) map_buildable_bit else 0) |
        map_visible_bit;
}

fn encodeOccupancy(world: *const state.World, cells: []u8) void {
    for (world.units) |unit| {
        if (!unit.active or unit.health == 0) continue;
        setOccupancy(cells, unit.position, unit.owner);
    }
    for (world.buildings) |building| {
        if (!building.active or building.health == 0) continue;
        const occupied_cells = placement.placementFootprint(building.kind) orelse continue;
        for (occupied_cells) |offset| {
            const position = placement.offsetPosition(world, building.position, offset) orelse continue;
            setOccupancy(cells, position, building.owner);
        }
    }
    for (world.infantry) |infantry| {
        if (!infantry.active or infantry.health == 0) continue;
        setOccupancy(cells, infantry.position, infantry.owner);
    }
}

fn setOccupancy(cells: []u8, position: state.Position, owner: state.Owner) void {
    if (position.x >= map_side or position.y >= map_side) return;
    setOccupancyIndex(cells, @as(usize, position.y) * map_side + position.x, owner);
}

fn setOccupancyIndex(cells: []u8, index: usize, owner: state.Owner) void {
    const incoming: u8 = if (owner == .player) 1 else 2;
    const existing = (cells[index] & map_occupancy_mask) >> map_occupancy_shift;
    const occupancy: u8 = if (existing == 0 or existing == incoming) incoming else 3;
    cells[index] = (cells[index] & ~(map_occupancy_mask | map_buildable_bit)) |
        (occupancy << map_occupancy_shift);
}

fn encodeEntities(
    world: *const state.World,
    owner: state.Owner,
    comptime record_size: usize,
    output: []u8,
) void {
    var slot: usize = 0;
    var local_index: usize = 0;
    for (world.units) |unit| {
        if (!unit.active or unit.owner != owner or slot == entity_slot_count) continue;
        encodeUnit(
            world,
            unit,
            canonicalId(.unit, local_index),
            owner,
            output[slot * record_size ..][0..record_size],
        );
        slot += 1;
        local_index += 1;
    }
    local_index = 0;
    for (world.buildings) |building| {
        if (!building.active or building.owner != owner or slot == entity_slot_count) continue;
        encodeBuilding(
            world,
            building,
            canonicalId(.building, local_index),
            output[slot * record_size ..][0..record_size],
        );
        slot += 1;
        local_index += 1;
    }
    local_index = 0;
    for (world.infantry) |infantry| {
        if (!infantry.active or infantry.owner != owner or slot == entity_slot_count) continue;
        encodeInfantry(
            world,
            infantry,
            canonicalId(.infantry, local_index),
            owner,
            output[slot * record_size ..][0..record_size],
        );
        slot += 1;
        local_index += 1;
    }
}

fn encodeUnit(
    world: *const state.World,
    unit: state.Unit,
    id: u16,
    owner: state.Owner,
    output: []u8,
) void {
    encodeEntityBase(unit.kind, id, unit.position, unit.health, unit.facing, unit.mission, output);
    if (unit.target.valid()) {
        output[entity_target_kind] = if (unit.target.owner == owner)
            @intFromEnum(action.TargetKind.own_entity)
        else
            @intFromEnum(action.TargetKind.visible_enemy);
        output[entity_target_slot] = entitySlot(world, unit.target) orelse 0;
    }
    output[entity_cooldown] = if (unit.kind == .harvester)
        unit.harvest_timer
    else
        unit.weapon_cooldown;
    output[entity_flags] = (@as(u8, @intFromBool(unit.deploying)) << 0) |
        (@as(u8, @intFromBool(unit.moving)) << 1) |
        (@as(u8, @intFromBool(unit.harvesting)) << 2) |
        (@as(u8, @intFromBool(unit.firing)) << 3);
    output[entity_progress] = if (unit.kind == .harvester)
        @intCast(@divFloor(@as(u16, unit.cargo_steps) * 255, rules.harvester_capacity_steps))
    else if (unit.kind == .mcv and unit.deploying)
        if (unit.facing >= 146) @divFloor(unit.facing - 146, 5) else 0
    else if (unit.kind == .medium_tank or unit.kind == .humvee)
        unit.turret_facing
    else
        0;
    output[entity_category] = @intFromEnum(rules.Category.unit);
    output[entity_status] = unit.status;
}

fn encodeBuilding(world: *const state.World, building: state.Building, id: u16, output: []u8) void {
    encodeEntityBase(building.kind, id, building.position, building.health, 0, 0, output);
    const canonical_operational = building.operational or building.construction_frames == 0;
    output[entity_flags] = @intFromBool(canonical_operational);
    const object_rule = rules.object(building.kind).?;
    var canonical_remaining: u16 = building.construction_frames;
    if (building.kind == .construction_yard and building.owner == .opponent and canonical_remaining != 0 and
        !hasActiveBuilding(world, .player, .construction_yard))
    {
        canonical_remaining -= 1;
    } else if (building.kind != .construction_yard and canonical_remaining != 0) {
        // Easy AI construction uses a 58-frame internal countdown but Vanilla exposes
        // progress on the building's 60-frame animation timeline.
        const controller = world.players[@intFromEnum(building.owner)].controller;
        canonical_remaining += if (controller == .easy_ai) 3 else 1;
    }
    output[entity_progress] = if (canonical_operational or object_rule.construction_frames == 0)
        255
    else progress: {
        const total: u32 = if (building.kind == .construction_yard) 64 else 60;
        const remaining: u32 = @min(canonical_remaining, total);
        break :progress @intCast(255 - @divFloor(remaining * 255, total));
    };
    output[entity_category] = @intFromEnum(rules.Category.building);
}

fn hasActiveBuilding(world: *const state.World, owner: state.Owner, kind: rules.ObjectType) bool {
    for (world.buildings) |building| {
        if (building.active and building.owner == owner and building.kind == kind) return true;
    }
    return false;
}

fn encodeInfantry(
    world: *const state.World,
    infantry: state.Infantry,
    id: u16,
    owner: state.Owner,
    output: []u8,
) void {
    encodeEntityBase(infantry.kind, id, infantry.position, infantry.health, infantry.facing, infantry.mission, output);
    if (infantry.target.valid()) {
        output[entity_target_kind] = if (infantry.target.owner == owner)
            @intFromEnum(action.TargetKind.own_entity)
        else
            @intFromEnum(action.TargetKind.visible_enemy);
        output[entity_target_slot] = entitySlot(world, infantry.target) orelse 0;
    }
    output[entity_cooldown] = infantry.weapon_cooldown;
    output[entity_flags] = (@as(u8, @intFromBool(infantry.moving)) << 0) |
        (@as(u8, @intFromBool(infantry.firing)) << 1) |
        (@as(u8, @intFromBool(infantry.prone)) << 2);
    output[entity_progress] = infantry.fear;
    output[entity_category] = @intFromEnum(rules.Category.infantry);
}

fn encodeEntityBase(
    kind: rules.ObjectType,
    id: u16,
    position: state.Position,
    health: i16,
    facing: u8,
    mission: i8,
    output: []u8,
) void {
    const object_rule = rules.object(kind).?;
    output[entity_presence] = 1;
    output[entity_type] = @intFromEnum(kind);
    output[entity_id_low] = @truncate(id);
    output[entity_id_high] = @truncate(id >> 8);
    output[entity_x] = position.x;
    output[entity_y] = position.y;
    output[entity_health] = healthFraction(health, object_rule.strength);
    output[entity_facing] = facing;
    output[entity_mission] = @intCast(@as(i16, mission) + 1);
    if (output.len >= entity_record_size) {
        output[entity_type_one_hot_offset + @intFromEnum(kind)] = 255;
    }
}

fn entitySlot(world: *const state.World, reference: state.EntityRef) ?u8 {
    var slot: u8 = 0;
    for (world.units, 0..) |unit, index| {
        if (!unit.active or unit.owner != reference.owner) continue;
        if (rules.object(reference.kind).?.category == .unit and index == reference.index) return slot;
        slot += 1;
    }
    for (world.buildings, 0..) |building, index| {
        if (!building.active or building.owner != reference.owner) continue;
        if (rules.object(reference.kind).?.category == .building and index == reference.index) return slot;
        slot += 1;
    }
    for (world.infantry, 0..) |infantry, index| {
        if (!infantry.active or infantry.owner != reference.owner) continue;
        if (rules.object(reference.kind).?.category == .infantry and index == reference.index) return slot;
        slot += 1;
    }
    return null;
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
    if (queue_kind == .unit and world.freeUnitSlots() <= unit_capacity_reserve) return false;
    if (object_rule.prerequisite != .none and !hasPlacedBuilding(world, .player, object_rule.prerequisite)) return false;
    return !world.queues[@intFromEnum(state.Owner.player)][@intFromEnum(queue_kind)].active;
}

const unit_capacity_reserve: usize = 3;

fn hasPlacedBuilding(world: *const state.World, owner: state.Owner, kind: rules.ObjectType) bool {
    for (world.buildings) |building| {
        if (building.active and building.owner == owner and building.kind == kind) return true;
    }
    return false;
}

fn activeEntityCount(world: *const state.World, owner: state.Owner) usize {
    return activeCategoryCount(world, owner, .unit) +
        activeCategoryCount(world, owner, .building) +
        activeCategoryCount(world, owner, .infantry);
}

fn activeCategoryCount(world: *const state.World, owner: state.Owner, category: rules.Category) usize {
    var count: usize = 0;
    switch (category) {
        .unit => for (world.units) |unit| {
            if (unit.active and unit.owner == owner) count += 1;
        },
        .building => for (world.buildings) |building| {
            if (building.active and building.owner == owner) count += 1;
        },
        .infantry => for (world.infantry) |infantry| {
            if (infantry.active and infantry.owner == owner) count += 1;
        },
        .none => {},
    }
    return count;
}

fn canonicalId(category: rules.Category, index: usize) u16 {
    const legacy_unit_count: usize = 2;
    const additional_unit_base: usize = legacy_unit_count + rules.max_buildings + rules.max_infantry;
    const base: usize = switch (category) {
        .unit => if (index < legacy_unit_count) 0 else additional_unit_base - legacy_unit_count,
        .building => legacy_unit_count,
        .infantry => legacy_unit_count + rules.max_buildings,
        .none => return 0,
    };
    return @intCast(base + index);
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

fn totalTiberiumSteps(world: *const state.World) usize {
    var total: usize = 0;
    for (world.tiberium_steps) |steps| total += steps;
    return total;
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

fn healthFraction(health: i16, maximum: i16) u8 {
    if (health <= 0 or maximum <= 0) return 0;
    return @intCast(@min(255, @divFloor(@as(i32, health) * 255, maximum)));
}

fn clippedU8(value: anytype) u8 {
    return @intCast(@min(@as(@TypeOf(value), 255), value));
}
