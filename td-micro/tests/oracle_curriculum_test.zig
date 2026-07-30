const std = @import("std");
const td = @import("td_micro");

const OraclePlayer = struct {
    id: u8,
    human: u8,
    credits: i32,
    power: i32,
    drain: i32,
    tiberium: i32,
    capacity: i32,
    harvested: u32,
};

const OracleEntity = struct {
    id: u16,
    kind: u8,
    owner: u8,
    active: u8,
    limbo: u8,
    cell: [2]i16,
    coord: [2]i32,
    health: i16,
    facing: i16,
    mission: i8,
    queued_mission: i8,
    status: i8,
    ammo: i16,
    second_shot: u8,
    cargo: u8,
    harvesting: u8,
};

const OracleAI = struct {
    active: u8,
};

const OracleSnapshot = struct {
    frame: u32,
    rng_state: u32,
    players: []const OraclePlayer,
    ai: OracleAI,
    entities: []const OracleEntity,
};

test "H0 E1 finish reset matches the Vanilla oracle" {
    try expectResetMatches(
        .h0_finish_e1,
        @embedFile("fixtures/vanilla_seed1_h0_finish_e1.jsonl"),
    );
}

test "H0 E3 finish reset matches the Vanilla oracle" {
    try expectResetMatches(
        .h0_finish_e3,
        @embedFile("fixtures/vanilla_seed1_h0_finish_e3.jsonl"),
    );
}

test "H0 mixed finish reset matches the Vanilla oracle" {
    try expectResetMatches(
        .h0_finish_mixed,
        @embedFile("fixtures/vanilla_seed1_h0_finish_mixed.jsonl"),
    );
}

test "every H1 assault package matches the Vanilla oracle" {
    const cases = [_]struct {
        profile: td.curriculum.Profile,
        trace: []const u8,
    }{
        .{ .profile = .h1_assault_e1, .trace = @embedFile("fixtures/vanilla_seed1_h1_assault_e1.jsonl") },
        .{ .profile = .h1_assault_e3, .trace = @embedFile("fixtures/vanilla_seed1_h1_assault_e3.jsonl") },
        .{ .profile = .h1_assault_mixed, .trace = @embedFile("fixtures/vanilla_seed1_h1_assault_mixed.jsonl") },
    };
    for (cases) |case| try expectResetMatches(case.profile, case.trace);
}

test "H2 through H4 base starts match the Vanilla oracle" {
    const cases = [_]struct {
        profile: td.curriculum.Profile,
        trace: []const u8,
    }{
        .{ .profile = .h2_mobilize, .trace = @embedFile("fixtures/vanilla_seed1_h2_mobilize.jsonl") },
        .{ .profile = .h3_economy, .trace = @embedFile("fixtures/vanilla_seed1_h3_economy.jsonl") },
        .{ .profile = .h4_opening, .trace = @embedFile("fixtures/vanilla_seed1_h4_opening.jsonl") },
    };
    for (cases) |case| try expectResetMatches(case.profile, case.trace);
}

test "reduced unit-count-6 start matches the Vanilla oracle" {
    var world = td.World.reset(1);
    td.curriculum.applyStartingForce(&world);
    try expectWorldMatches(&world, @embedFile("fixtures/vanilla_seed1_starting_force.jsonl"));
}

fn expectResetMatches(profile: td.curriculum.Profile, trace: []const u8) !void {
    const world = td.curriculum.reset(1, profile);
    try expectWorldMatches(&world, trace);
}

fn expectWorldMatches(world: *const td.World, trace: []const u8) !void {
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();
    const line = lines.next() orelse return error.MissingResetSnapshot;
    const parsed = try std.json.parseFromSlice(
        OracleSnapshot,
        std.testing.allocator,
        line,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    const oracle = parsed.value;

    try std.testing.expectEqual(@as(u32, 0), oracle.frame);
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
    try std.testing.expectEqual(oracle.rng_state, world.rng_state);
    try std.testing.expectEqual(@as(u8, 1), oracle.ai.active);
    for (oracle.players) |player| {
        try std.testing.expect(player.id < world.players.len);
        const actual = world.players[player.id];
        try std.testing.expectEqual(player.credits, actual.credits);
        try std.testing.expectEqual(player.power, actual.power);
        try std.testing.expectEqual(player.drain, actual.drain);
        try std.testing.expectEqual(player.tiberium, actual.tiberium);
        try std.testing.expectEqual(player.capacity, actual.capacity);
        try std.testing.expectEqual(player.harvested, actual.harvested_credits);
        try std.testing.expectEqual(player.id == @intFromEnum(td.Owner.player), player.human != 0);
    }

    var expected_active: usize = 0;
    for (oracle.entities) |entity| {
        if (entity.active == 0 or entity.limbo != 0) continue;
        expected_active += 1;
        const kind: td.ObjectType = @enumFromInt(entity.kind);
        const owner: td.Owner = @enumFromInt(entity.owner);
        if (kind == .mcv or kind == .harvester) {
            const unit = findUnit(world, owner, kind) orelse return error.MissingOracleUnit;
            try std.testing.expectEqual(entity.cell[0], @as(i16, unit.position.x));
            try std.testing.expectEqual(entity.cell[1], @as(i16, unit.position.y));
            try std.testing.expectEqual(entity.coord[0], @as(i32, unit.coord_x));
            try std.testing.expectEqual(entity.coord[1], @as(i32, unit.coord_y));
            try std.testing.expectEqual(entity.health, unit.health);
            try std.testing.expectEqual(entity.facing, @as(i16, unit.facing));
            try std.testing.expectEqual(entity.mission, unit.mission);
            try std.testing.expectEqual(entity.status, @as(i8, @intCast(unit.status)));
            try std.testing.expectEqual(entity.cargo, unit.cargo_steps);
            try std.testing.expectEqual(entity.harvesting != 0, unit.harvesting);
            continue;
        }
        if (kind == .e1 or kind == .e3) {
            try std.testing.expect(entity.id < world.infantry_count);
            const infantry = world.infantry[entity.id];
            try std.testing.expect(infantry.active);
            try std.testing.expectEqual(kind, infantry.kind);
            try std.testing.expectEqual(owner, infantry.owner);
            try std.testing.expectEqual(entity.cell[0], @as(i16, infantry.position.x));
            try std.testing.expectEqual(entity.cell[1], @as(i16, infantry.position.y));
            try std.testing.expectEqual(entity.coord[0], @as(i32, infantry.coord_x));
            try std.testing.expectEqual(entity.coord[1], @as(i32, infantry.coord_y));
            try std.testing.expectEqual(entity.health, infantry.health);
            try std.testing.expectEqual(entity.facing, @as(i16, infantry.facing));
            try std.testing.expectEqual(entity.mission, infantry.mission);
            try std.testing.expectEqual(entity.queued_mission, infantry.queued_mission);
            try std.testing.expectEqual(entity.ammo, infantry.ammo);
            try std.testing.expectEqual(entity.second_shot != 0, infantry.second_shot);
            continue;
        }
        const building = findBuilding(world, owner, kind, entity.cell) orelse
            return error.MissingOracleBuilding;
        try std.testing.expect(building.operational);
        try std.testing.expectEqual(entity.health, building.health);
        if (kind == .refinery) try std.testing.expect(building.grand_opened);
    }
    try std.testing.expectEqual(expected_active, countActiveObjects(world));
}

fn findUnit(world: *const td.World, owner: td.Owner, kind: td.ObjectType) ?*const td.state.Unit {
    for (&world.units) |*unit| {
        if (unit.active and unit.owner == owner and unit.kind == kind) return unit;
    }
    return null;
}

fn findBuilding(
    world: *const td.World,
    owner: td.Owner,
    kind: td.ObjectType,
    cell: [2]i16,
) ?*const td.state.Building {
    for (&world.buildings) |*building| {
        if (building.active and building.owner == owner and building.kind == kind and
            building.position.x == cell[0] and building.position.y == cell[1]) return building;
    }
    return null;
}

fn countActiveObjects(world: *const td.World) usize {
    var count: usize = 0;
    for (world.units) |unit| if (unit.active) {
        count += 1;
    };
    for (world.buildings) |building| if (building.active) {
        count += 1;
    };
    for (world.infantry) |infantry| if (infantry.active) {
        count += 1;
    };
    return count;
}
