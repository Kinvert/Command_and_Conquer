const action = @import("action.zig");
const ai = @import("ai.zig");
const combat = @import("combat.zig");
const economy = @import("economy.zig");
const input = @import("input.zig");
const movement = @import("movement.zig");
const production = @import("production.zig");
const random = @import("random.zig");
const rules = @import("rules.zig");
const state = @import("state.zig");

const early_win_delay_frames: u8 = rules.ticks_per_second * 2 + 1;

pub const TimedAction = struct {
    frame: u32,
    action: action.Action,
};

pub const CommandBuffer = struct {
    len: usize = 0,
    items: [32]TimedAction = [_]TimedAction{.{ .frame = 0, .action = .{} }} ** 32,

    pub fn slice(self: *const CommandBuffer) []const TimedAction {
        return self.items[0..self.len];
    }

    fn append(self: *CommandBuffer, frame: u32, command: action.Action) void {
        if (self.len == self.items.len) return;
        self.items[self.len] = .{ .frame = frame, .action = command };
        self.len += 1;
    }
};

pub fn step(world: *state.World, player_action: action.Action, opponent_action: action.Action) void {
    _ = input.apply(world, .player, player_action);
    _ = input.apply(world, .opponent, opponent_action);
    for (0..rules.decision_frames) |_| {
        if (isTerminal(world)) break;
        tickFrame(world);
    }
}

pub fn stepWithOpponentCommands(
    world: *state.World,
    player_action: action.Action,
    opponent_actions: []const TimedAction,
) void {
    _ = input.apply(world, .player, player_action);
    for (0..rules.decision_frames) |_| {
        if (isTerminal(world)) break;
        const next_frame = world.frame + 1;
        applyOpponentCommands(world, opponent_actions, next_frame, true);
        applyOpponentCommands(world, opponent_actions, next_frame, false);
        tickFrame(world);
    }
}

pub fn stepWithEasyAI(world: *state.World, player_action: action.Action) CommandBuffer {
    _ = input.apply(world, .player, player_action);
    return advanceWithEasyAI(world);
}

pub fn advanceWithEasyAI(world: *state.World) CommandBuffer {
    var commands: CommandBuffer = .{};

    for (0..rules.decision_frames) |_| {
        if (isTerminal(world)) break;
        tickEasyAIFrameInto(world, &commands);
    }
    return commands;
}

pub fn stepEasyAIFrame(world: *state.World) CommandBuffer {
    var commands: CommandBuffer = .{};
    tickEasyAIFrameInto(world, &commands);
    return commands;
}

fn tickEasyAIFrameInto(world: *state.World, commands: *CommandBuffer) void {
    if (isTerminal(world)) return;
    const next_frame = world.frame + 1;
    if (ai.unitPhase(world)) |command| commands.append(next_frame, command);
    combat.tickUnitMissions(world);
    economy.tickCombatVehicles(world);
    const frame_start_harvesters = economy.captureActiveHarvesters(world);
    economy.tickMatchingHarvesters(world, &frame_start_harvesters, true, .opponent, false);
    const existing_infantry_count = world.infantry_count;
    const infantry_precedes_factories = world.starting_force == .reduced_unit_count_6;
    var transitioned: [rules.max_infantry]u8 = undefined;
    var transition_count: usize = 0;
    if (infantry_precedes_factories) {
        combat.tickInfantryMissionsUntil(world, existing_infantry_count);
        transition_count = combat.commenceQueuedInfantryMissions(world, existing_infantry_count, &transitioned);
    }
    if (ai.factoryPhase(world)) |command| commands.append(next_frame, command);
    if (!infantry_precedes_factories) {
        combat.tickInfantryMissionsUntil(world, existing_infantry_count);
        transition_count = combat.commenceQueuedInfantryMissions(world, existing_infantry_count, &transitioned);
    }
    for (transitioned[0..transition_count]) |index| {
        commands.append(next_frame, .{ .command = .hunt, .actor = index });
    }
    economy.tickMatchingHarvesters(world, &frame_start_harvesters, true, .opponent, true);
    economy.tickMatchingHarvesters(world, &frame_start_harvesters, true, .player, null);
    if (world.infantry_count > existing_infantry_count) ai.initializeReleasedInfantry(world);

    var building_commands: [2]action.Action = undefined;
    const building_command_count = ai.buildingPhase(world, &building_commands);
    for (building_commands[0..building_command_count]) |command| commands.append(next_frame, command);

    production.tick(world);
    economy.tickMatchingHarvesters(world, &frame_start_harvesters, false, null, null);
    const movement_frame = movement.tick(world);
    combat.perCellProcess(world, &movement_frame.entered_cell);
    // Turrets steer before weapons fire, matching tickFrame's ordering. This path omitted the
    // turret tick entirely, so a vehicle turret never rotated during training: canUnitFire
    // requires turret_facing to equal the desired facing, and it sat one unit off forever.
    combat.tickUnitTurrets(world);
    combat.tickAfterUnitMissions(world, &movement_frame.moving_at_frame_start);
    if (updateDefeated(world)) return;
    ai.housePhase(world);
    ai.finishFrame(world);
    world.frame = next_frame;
    skirmishMessageRoll(world);
}

fn applyOpponentCommands(
    world: *state.World,
    opponent_actions: []const TimedAction,
    frame: u32,
    placement_phase: bool,
) void {
    for (opponent_actions) |opponent_action| {
        if (opponent_action.frame != frame) continue;
        const is_placement = opponent_action.action.command == .place;
        if (is_placement != placement_phase) continue;
        _ = input.applyAI(world, .opponent, opponent_action.action);
    }
}

pub fn tickFrame(world: *state.World) void {
    if (isTerminal(world)) return;
    production.tick(world);
    economy.tick(world);
    // Vanilla runs an eligible ATTACK mission before the infantry drive pass.
    combat.prepareAttackMissions(world);
    const movement_frame = movement.tick(world);
    combat.perCellProcess(world, &movement_frame.entered_cell);
    combat.tickObjectMissions(world);
    combat.tickAfterUnitMissions(world, &movement_frame.moving_at_frame_start);
    if (updateDefeated(world)) return;
    world.frame += 1;
    skirmishMessageRoll(world);
}

fn skirmishMessageRoll(world: *state.World) void {
    if (random.pick(&world.rng_state, 0, 10_000) != 1) return;
    if (world.players[@intFromEnum(state.Owner.opponent)].controller != .easy_ai) return;

    // Computer_Message consumes one branch draw and one message/garble draw.
    const echoes_player = random.pick(&world.rng_state, 0, 3) == 2;
    _ = random.pick(&world.rng_state, 0, if (echoes_player) 2 else 12);
}

pub fn isTerminal(world: *const state.World) bool {
    for (world.players) |player| {
        if (player.defeated) return true;
    }
    return false;
}

fn updateDefeated(world: *state.World) bool {
    for (0..rules.player_count) |owner_index| {
        const owner: state.Owner = @enumFromInt(owner_index);
        const player = &world.players[owner_index];
        if (player.defeated) continue;
        if (!ownerHasActiveObject(world, owner)) {
            player.defeated = true;
            continue;
        }
        if (ownerHasPertinentStructure(world, owner)) {
            player.defeat_pending = false;
            player.defeat_timer = 0;
            continue;
        }
        if (!player.defeat_pending) {
            player.defeat_pending = true;
            player.defeat_timer = early_win_delay_frames;
            continue;
        }
        if (player.defeat_timer != 0) player.defeat_timer -= 1;
        if (player.defeat_timer == 0) {
            combat.blowupOwner(world, owner);
            player.defeat_pending = false;
            player.defeated = true;
        }
    }
    return isTerminal(world);
}

fn ownerHasActiveObject(world: *const state.World, owner: state.Owner) bool {
    for (world.units) |unit| {
        if (unit.active and unit.health != 0 and unit.owner == owner) return true;
    }
    for (world.buildings) |building| {
        if (building.active and building.health != 0 and building.owner == owner) return true;
    }
    for (world.infantry) |infantry| {
        if (infantry.active and infantry.health != 0 and infantry.owner == owner) return true;
    }
    return false;
}

fn ownerHasPertinentStructure(world: *const state.World, owner: state.Owner) bool {
    for (world.units) |unit| {
        if (unit.active and unit.health != 0 and unit.owner == owner and unit.kind == .mcv) return true;
    }
    for (world.buildings) |building| {
        if (building.active and building.health != 0 and building.owner == owner) return true;
    }
    return false;
}
