const action = @import("action.zig");
const combat = @import("combat.zig");
const current_policy = @import("policy.zig");
const input = @import("input.zig");
const policy_abi9 = @import("policy_abi9.zig");
const state = @import("state.zig");

pub const abi_version: u32 = 14;
pub const observation_size = current_policy.observation_size;
pub const selector_count: usize = current_policy.entity_slot_count;
pub const actor_none = policy_abi9.actor_none;
pub const base_head_count = policy_abi9.action_head_count;
pub const action_head_count = base_head_count + selector_count;
pub const action_head_sizes = buildActionHeadSizes();
pub const base_action_mask_size = policy_abi9.action_mask_size;
pub const action_logit_count = sum(action_head_sizes);
pub const attack_target_mask_offset = action_logit_count;
pub const action_mask_size = attack_target_mask_offset + current_policy.entity_slot_count;

pub const RawAction = extern struct {
    command: u8 = @intFromEnum(action.Command.noop),
    actor: u8 = actor_none,
    product: u8 = 0,
    target_kind: u8 = @intFromEnum(action.TargetKind.none),
    target_x: u8 = 0,
    target_y: u8 = 0,
    target_slot: u8 = 0,
    selectors: [selector_count]u8 = [_]u8{0} ** selector_count,
};

pub fn observe(world: *const state.World, output: *[observation_size]u8) void {
    current_policy.observe(world, output);
}

// The first seven rows retain ABI9's independent masks. Each selector then
// contributes a distinct binary head: zero is always valid, one is valid only
// for an observable player infantry slot.
pub fn actionMask(world: *const state.World, output: *[action_mask_size]u8) void {
    var base: [base_action_mask_size]u8 = undefined;
    policy_abi9.actionMask(world, &base);
    @memcpy(output[0..base_action_mask_size], &base);
    @memset(output[base_action_mask_size..], 0);

    for (0..selector_count) |slot| selectorMask(output, slot)[0] = 1;

    var own_slot: usize = 0;
    for (world.units) |unit| {
        if (!unit.active or unit.owner != .player) continue;
        // Vehicles are selectable now that combat.resolveAttack accepts vehicle actors, so a tank
        // can be committed to a wave alongside infantry.
        if (own_slot < selector_count and (unit.kind == .medium_tank or unit.kind == .humvee)) {
            selectorMask(output, own_slot)[1] = 1;
        }
        own_slot += 1;
    }
    for (world.buildings) |building| {
        if (!building.active or building.owner != .player) continue;
        own_slot += 1;
    }
    for (world.infantry) |infantry| {
        if (!infantry.active or infantry.owner != .player) continue;
        if (own_slot < selector_count and (infantry.kind == .e1 or infantry.kind == .e3)) {
            selectorMask(output, own_slot)[1] = 1;
        }
        own_slot += 1;
    }
    const enemy_count = @min(activeEntityCount(world, .opponent), current_policy.entity_slot_count);
    for (0..enemy_count) |slot| attackTargetMask(output)[slot] = 1;
}

pub fn selectorMask(mask: *[action_mask_size]u8, slot: usize) []u8 {
    const offset = base_action_mask_size + slot * 2;
    return mask[offset .. offset + 2];
}

pub fn attackTargetMask(mask: *[action_mask_size]u8) []u8 {
    return mask[attack_target_mask_offset..action_mask_size];
}

pub fn apply(world: *state.World, owner: state.Owner, raw: RawAction) bool {
    if (!selectorsValid(raw.selectors)) return false;
    if (raw.command != @intFromEnum(action.Command.attack)) {
        // Selectors are attack-only and carry no meaning here, so they are ignored rather than
        // treated as invalid. Rejecting on them made the contract self-contradictory: PufferLib
        // samples all 71 heads every step, so build and move actions routinely arrive with
        // selectors set, and the only way to keep those working was to drive every selector to
        // zero -- which left attacks with nothing selected and made the group attack unusable.
        const decoded = policy_abi9.decode(world, .{
            .command = raw.command,
            .actor = raw.actor,
            .product = raw.product,
            .target_kind = raw.target_kind,
            .target_x = raw.target_x,
            .target_y = raw.target_y,
            .target_slot = raw.target_slot,
        }) orelse return false;
        return input.apply(world, owner, decoded);
    }

    // A group attack takes its actors from the selectors and its target from target_slot, so
    // actor, product, target_x and target_y carry no meaning here. Requiring them to hold exact
    // sentinel values made the command unreachable: the seven heads are sampled independently and
    // the mask constrains none of those four, so a trained policy landed 0 valid attacks in 140.
    // Only the fields the command actually uses are validated.
    if (raw.target_slot >= current_policy.entity_slot_count or
        !combat.attackTargetValid(world, owner, raw.target_slot))
    {
        return false;
    }

    const command = action.Action{
        .command = .attack,
        .target_kind = .visible_enemy,
        .target_slot = raw.target_slot,
    };
    // Apply the valid subset rather than rejecting the whole group. All-or-nothing made the command
    // unreachable: with 64 independently sampled selector heads, a fully valid random selection
    // essentially never occurs, so the policy never executed one and could never learn from it.
    // Still two passes, so a group either applies wholly-valid selections or nothing at all -- no
    // partially mutated world if a later selection turns out invalid.
    var applicable: usize = 0;
    for (raw.selectors, 0..) |selected, slot| {
        if (selected == 0) continue;
        var actor_command = command;
        actor_command.actor = @intCast(slot);
        if (combat.canApply(world, owner, actor_command)) applicable += 1;
    }
    // Nothing happened, so this is an invalid action; accepting it would teach the policy that
    // attacking is free.
    if (applicable == 0) return false;

    for (raw.selectors, 0..) |selected, slot| {
        if (selected == 0) continue;
        var actor_command = command;
        actor_command.actor = @intCast(slot);
        if (!combat.canApply(world, owner, actor_command)) continue;
        if (!combat.apply(world, owner, actor_command)) unreachable;
    }
    return true;
}

fn selectorsValid(selectors: [selector_count]u8) bool {
    for (selectors) |selected| if (selected > 1) return false;
    return true;
}

fn selectorsEmpty(selectors: [selector_count]u8) bool {
    for (selectors) |selected| if (selected != 0) return false;
    return true;
}

fn buildActionHeadSizes() [action_head_count]u16 {
    var result = [_]u16{2} ** action_head_count;
    for (policy_abi9.action_head_sizes, 0..) |size, index| result[index] = size;
    return result;
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

fn sum(values: anytype) usize {
    var result: usize = 0;
    for (values) |value| result += value;
    return result;
}
