const rules = @import("rules.zig");

pub const Command = enum(u8) {
    noop,
    deploy,
    start_build,
    place,
    train,
    move,
    attack,
    guard,
    stop,
    hunt,
    harvest,
    return_cargo,
};

pub const TargetKind = enum(u8) {
    none,
    cell,
    own_entity,
    visible_enemy,
};

pub const Action = extern struct {
    command: Command = .noop,
    actor: u8 = 0,
    product: rules.ObjectType = .none,
    target_kind: TargetKind = .none,
    target_x: u8 = 0,
    target_y: u8 = 0,
    target_slot: u8 = 0,
};
