const action = @import("action.zig");
const combat = @import("combat.zig");
const economy = @import("economy.zig");
const movement = @import("movement.zig");
const production = @import("production.zig");
const state = @import("state.zig");

pub fn apply(world: *state.World, owner: state.Owner, command: action.Action) bool {
    return switch (command.command) {
        .noop, .deploy, .start_build, .place, .train => production.apply(world, owner, command),
        .move => economy.apply(world, owner, command) or movement.apply(world, owner, command),
        .harvest, .return_cargo => economy.apply(world, owner, command),
        .attack => combat.apply(world, owner, command),
        else => false,
    };
}

pub fn applyAI(world: *state.World, owner: state.Owner, command: action.Action) bool {
    return switch (command.command) {
        .noop, .deploy, .start_build, .place, .train => production.applyAI(world, owner, command),
        .move => economy.apply(world, owner, command) or movement.apply(world, owner, command),
        .harvest, .return_cargo => economy.apply(world, owner, command),
        .attack => combat.apply(world, owner, command),
        else => false,
    };
}
