const std = @import("std");
const td = @import("td_micro");

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
    cooldown: u8,
    firing: u8,
    target: u64,
    animation: i8,
    animation_stage: u16,
    animation_timer: u8,
    animation_rate: u8,
    prone: u8,
    fear: u8,
    ammo: i16,
    kills: u16,
    second_shot: u8,
};

const OracleProjectile = struct {
    id: u16,
    type: u8,
    active: u8,
    limbo: u8,
    coord: [2]i32,
    fuse: [2]i32,
    strength: i16,
    facing: i16,
    desired_facing: u8 = 0,
    speed: u8,
    speed_accum: u16 = 0,
    timer: u8,
    arming: u8 = 0,
    proximity: i16 = 0,
    source_owner: u8,
    source_kind: u8,
    source_id: u16,
    target_owner: u8,
    target_kind: u8,
    target_id: u16,
};

const OracleSnapshot = struct {
    decision: u32,
    frame: u32,
    rng_state: u32,
    players: []const OraclePlayer = &.{},
    entities: []const OracleEntity,
    projectiles: []const OracleProjectile,
};

const OraclePlayer = struct {
    id: u8,
    defeated: u8,
};

fn oracleE1(snapshot: OracleSnapshot, owner: td.Owner) ?OracleEntity {
    for (snapshot.entities) |entity| {
        if (entity.kind == @intFromEnum(td.ObjectType.e1) and entity.owner == @intFromEnum(owner) and entity.active != 0 and entity.limbo == 0) return entity;
    }
    return null;
}

fn zigE1(world: *const td.World, owner: td.Owner) ?td.state.Infantry {
    for (world.infantry) |infantry| {
        if (infantry.active and infantry.kind == .e1 and infantry.owner == owner) return infantry;
    }
    return null;
}

fn oracleE3(snapshot: OracleSnapshot, owner: td.Owner) ?OracleEntity {
    for (snapshot.entities) |entity| {
        if (entity.kind == @intFromEnum(td.ObjectType.e3) and entity.owner == @intFromEnum(owner) and entity.active != 0 and entity.limbo == 0) return entity;
    }
    return null;
}

fn zigE3(world: *const td.World, owner: td.Owner) ?td.state.Infantry {
    for (world.infantry) |infantry| {
        if (infantry.active and infantry.kind == .e3 and infantry.owner == owner) return infantry;
    }
    return null;
}

fn oracleMcv(snapshot: OracleSnapshot, owner: td.Owner) ?OracleEntity {
    for (snapshot.entities) |entity| {
        if (entity.kind == @intFromEnum(td.ObjectType.mcv) and entity.owner == @intFromEnum(owner) and entity.active != 0 and entity.limbo == 0) return entity;
    }
    return null;
}

fn zigMcv(world: *const td.World, owner: td.Owner) ?td.state.Unit {
    for (world.units) |unit| {
        if (unit.active and unit.kind == .mcv and unit.owner == owner) return unit;
    }
    return null;
}

fn oracleDefeated(snapshot: OracleSnapshot, owner: td.Owner) bool {
    for (snapshot.players) |player| {
        if (player.id == @intFromEnum(owner)) return player.defeated != 0;
    }
    return false;
}

fn expectInfantry(expected: OracleEntity, actual: td.state.Infantry) !void {
    try std.testing.expectEqual(expected.cell[0], @as(i16, actual.position.x));
    try std.testing.expectEqual(expected.cell[1], @as(i16, actual.position.y));
    try std.testing.expectEqual(expected.coord[0], actual.coord_x);
    try std.testing.expectEqual(expected.coord[1], actual.coord_y);
    try std.testing.expectEqual(expected.health, actual.health);
    try std.testing.expectEqual(expected.facing, actual.facing);
    try std.testing.expectEqual(expected.mission, actual.mission);
    try std.testing.expectEqual(expected.queued_mission, actual.queued_mission);
    try std.testing.expectEqual(expected.cooldown, actual.weapon_cooldown);
    try std.testing.expectEqual(expected.firing != 0, actual.firing);
    try std.testing.expectEqual(expected.target != 0, actual.target.valid());
    try std.testing.expectEqual(expected.animation, actual.animation);
    try std.testing.expectEqual(expected.animation_stage, actual.animation_stage);
    try std.testing.expectEqual(expected.animation_timer, actual.animation_timer);
    try std.testing.expectEqual(expected.animation_rate, actual.animation_rate);
    try std.testing.expectEqual(expected.prone != 0, actual.prone);
    try std.testing.expectEqual(expected.fear, actual.fear);
    try std.testing.expectEqual(expected.ammo, actual.ammo);
    try std.testing.expectEqual(expected.kills, actual.kills);
    try std.testing.expectEqual(expected.second_shot != 0, actual.second_shot);
}

fn expectProjectiles(expected: []const OracleProjectile, world: *const td.World) !void {
    var active: usize = 0;
    for (world.projectiles) |projectile| {
        if (!projectile.active) continue;
        if (active >= expected.len) return error.UnexpectedProjectile;
        const oracle = expected[active];
        try std.testing.expectEqual(oracle.id, projectile.id);
        try std.testing.expectEqual(oracle.type, @intFromEnum(projectile.kind));
        try std.testing.expectEqual(oracle.coord[0], projectile.coord_x);
        try std.testing.expectEqual(oracle.coord[1], projectile.coord_y);
        try std.testing.expectEqual(oracle.fuse[0], projectile.fuse_x);
        try std.testing.expectEqual(oracle.fuse[1], projectile.fuse_y);
        try std.testing.expectEqual(oracle.strength, projectile.strength);
        try std.testing.expectEqual(oracle.facing, projectile.facing);
        try std.testing.expectEqual(oracle.desired_facing, projectile.desired_facing);
        try std.testing.expectEqual(oracle.speed, projectile.speed);
        try std.testing.expectEqual(oracle.speed_accum, projectile.speed_accum);
        try std.testing.expectEqual(oracle.timer, projectile.timer);
        try std.testing.expectEqual(oracle.arming, projectile.arming);
        try std.testing.expectEqual(oracle.proximity, projectile.proximity);
        try std.testing.expectEqual(oracle.source_owner, @intFromEnum(projectile.source.owner));
        try std.testing.expectEqual(oracle.source_kind, @intFromEnum(projectile.source.kind));
        try std.testing.expectEqual(oracle.source_id, projectile.source.index);
        try std.testing.expectEqual(oracle.target_owner, @intFromEnum(projectile.target.owner));
        try std.testing.expectEqual(oracle.target_kind, @intFromEnum(projectile.target.kind));
        try std.testing.expectEqual(oracle.target_id, projectile.target.index);
        active += 1;
    }
    try std.testing.expectEqual(expected.len, active);
}

fn expectDifficultyE1Trace(
    trace: []const u8,
    selected: td.difficulty.Requested,
) !void {
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.combat.e1DuelFixture();
    td.difficulty.enable(&world, selected);
    var action_applied = false;
    var compared: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const parsed = try std.json.parseFromSlice(
            OracleSnapshot,
            std.testing.allocator,
            line,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        const oracle = parsed.value;

        if (oracle.decision != 0 and !action_applied) {
            try std.testing.expect(td.input.apply(&world, .player, .{
                .command = .attack,
                .actor = 1,
                .target_kind = .visible_enemy,
                .target_slot = 1,
            }));
            action_applied = true;
        }
        while (world.frame < oracle.frame) td.step.tickFrame(&world);
        try std.testing.expectEqual(oracle.frame, world.frame);
        try std.testing.expectEqual(oracle.rng_state, world.rng_state);

        inline for (.{ td.Owner.player, td.Owner.opponent }) |owner| {
            if (oracleE1(oracle, owner)) |expected| {
                const actual = zigE1(&world, owner) orelse return error.MissingE1;
                expectInfantry(expected, actual) catch |err| {
                    std.debug.print(
                        "{s} E1 difficulty divergence at frame {d}, owner {d}\n",
                        .{ @tagName(selected), oracle.frame, @intFromEnum(owner) },
                    );
                    return err;
                };
            } else {
                try std.testing.expect(zigE1(&world, owner) == null);
            }
        }
        try expectProjectiles(oracle.projectiles, &world);
        compared += 1;
    }
    try std.testing.expectEqual(@as(usize, 41), compared);
}

test "E1 duel matches Vanilla at every stock opponent difficulty" {
    try expectDifficultyE1Trace(
        @embedFile("fixtures/vanilla_seed1_difficulty_easy_e1_duel.jsonl"),
        .easy,
    );
    try expectDifficultyE1Trace(
        @embedFile("fixtures/vanilla_seed1_difficulty_normal_e1_duel.jsonl"),
        .normal,
    );
    try expectDifficultyE1Trace(
        @embedFile("fixtures/vanilla_seed1_difficulty_hard_e1_duel.jsonl"),
        .hard,
    );
}

test "E1 duel matches Vanilla frame by frame through both deaths" {
    const trace = @embedFile("fixtures/vanilla_seed1_e1_duel_frame.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.combat.e1DuelFixture();
    var compared: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const parsed = try std.json.parseFromSlice(
            OracleSnapshot,
            std.testing.allocator,
            line,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        const oracle = parsed.value;

        if (oracle.decision == 1) {
            try std.testing.expect(td.input.apply(&world, .player, .{
                .command = .attack,
                .actor = 1,
                .target_kind = .visible_enemy,
                .target_slot = 1,
            }));
        }
        if (oracle.decision != 0) td.step.tickFrame(&world);
        try std.testing.expectEqual(oracle.frame, world.frame);
        try std.testing.expectEqual(oracle.rng_state, world.rng_state);

        inline for (.{ td.Owner.player, td.Owner.opponent }) |owner| {
            if (oracleE1(oracle, owner)) |expected| {
                const actual = zigE1(&world, owner) orelse return error.MissingE1;
                expectInfantry(expected, actual) catch |err| {
                    std.debug.print("E1 combat divergence at frame {d}, owner {d}\n", .{ oracle.frame, @intFromEnum(owner) });
                    return err;
                };
            } else {
                try std.testing.expect(zigE1(&world, owner) == null);
            }
        }
        try expectProjectiles(oracle.projectiles, &world);
        compared += 1;
    }
    try std.testing.expectEqual(@as(usize, 161), compared);
}

test "E3 duel matches Vanilla RNG, rocket flight, damage, and death frame by frame" {
    const trace = @embedFile("fixtures/vanilla_seed1_e3_duel_frame.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.combat.e3DuelFixture();
    var compared: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const parsed = try std.json.parseFromSlice(
            OracleSnapshot,
            std.testing.allocator,
            line,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        const oracle = parsed.value;

        if (oracle.decision == 1) {
            try std.testing.expect(td.input.apply(&world, .player, .{
                .command = .attack,
                .actor = 1,
                .target_kind = .visible_enemy,
                .target_slot = 1,
            }));
        }
        if (oracle.decision != 0) td.step.tickFrame(&world);
        try std.testing.expectEqual(oracle.frame, world.frame);
        try std.testing.expectEqual(oracle.rng_state, world.rng_state);

        inline for (.{ td.Owner.player, td.Owner.opponent }) |owner| {
            if (oracleE3(oracle, owner)) |expected| {
                const actual = zigE3(&world, owner) orelse return error.MissingE3;
                expectInfantry(expected, actual) catch |err| {
                    std.debug.print("E3 combat divergence at frame {d}, owner {d}\n", .{ oracle.frame, @intFromEnum(owner) });
                    return err;
                };
            } else {
                try std.testing.expect(zigE3(&world, owner) == null);
            }
        }
        try expectProjectiles(oracle.projectiles, &world);
        compared += 1;
    }
    try std.testing.expectEqual(@as(usize, 401), compared);
}

test "distant E1 attack chases and destroys the opponent MCV like Vanilla" {
    const trace = @embedFile("fixtures/vanilla_seed1_e1_attack_mcv.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.combat.e1DuelFixture();
    var compared: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const parsed = try std.json.parseFromSlice(
            OracleSnapshot,
            std.testing.allocator,
            line,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        const oracle = parsed.value;

        if (oracle.decision == 1) {
            try std.testing.expect(td.input.apply(&world, .player, .{
                .command = .attack,
                .actor = 1,
                .target_kind = .visible_enemy,
                .target_slot = 0,
            }));
        }
        while (world.frame < oracle.frame and !td.step.isTerminal(&world)) td.step.tickFrame(&world);
        if (oracleDefeated(oracle, .opponent) and !td.step.isTerminal(&world)) td.step.tickFrame(&world);

        try std.testing.expectEqual(oracle.frame, world.frame);
        try std.testing.expectEqual(
            oracleDefeated(oracle, .opponent),
            world.players[@intFromEnum(td.Owner.opponent)].defeated,
        );
        if (oracleE1(oracle, .player)) |expected| {
            const actual = zigE1(&world, .player) orelse return error.MissingE1;
            expectInfantry(expected, actual) catch |err| {
                std.debug.print("E1 attack-chase divergence at frame {d}\n", .{oracle.frame});
                return err;
            };
        }
        if (oracleMcv(oracle, .opponent)) |expected| {
            const actual = zigMcv(&world, .opponent) orelse return error.MissingMcv;
            try std.testing.expectEqual(expected.cell[0], @as(i16, actual.position.x));
            try std.testing.expectEqual(expected.cell[1], @as(i16, actual.position.y));
            try std.testing.expectEqual(expected.health, actual.health);
        } else {
            try std.testing.expect(zigMcv(&world, .opponent) == null);
        }
        const opponent_player = world.players[@intFromEnum(td.Owner.opponent)];
        // Vanilla consumes one extra idle-animation draw during the irreversible
        // early-win shutdown. Command-visible parity remains strict before it.
        if (!opponent_player.defeat_pending and !opponent_player.defeated) {
            if (oracle.rng_state != world.rng_state) {
                std.debug.print(
                    "E1 attack-chase RNG divergence at frame {d}: expected {d}, found {d}\n",
                    .{ oracle.frame, oracle.rng_state, world.rng_state },
                );
            }
            try std.testing.expectEqual(oracle.rng_state, world.rng_state);
        }
        compared += 1;
    }

    try std.testing.expectEqual(@as(usize, 668), compared);
    try std.testing.expect(world.players[@intFromEnum(td.Owner.opponent)].defeated);
}

test "policy attack win trace has a stable deterministic digest" {
    const command: td.Action = .{
        .command = .attack,
        .actor = 1,
        .target_kind = .visible_enemy,
        .target_slot = 0,
    };
    var first = td.combat.e1DuelFixture();
    var second = td.combat.e1DuelFixture();
    try std.testing.expect(td.input.apply(&first, .player, command));
    try std.testing.expect(td.input.apply(&second, .player, command));

    var trace = std.crypto.hash.sha2.Sha256.init(.{});
    var logic_steps: usize = 0;
    while (true) {
        const first_digest = td.digest.canonical(&first);
        const second_digest = td.digest.canonical(&second);
        try std.testing.expectEqualSlices(u8, &first_digest, &second_digest);
        trace.update(&first_digest);
        if (td.step.isTerminal(&first)) break;
        td.step.tickFrame(&first);
        td.step.tickFrame(&second);
        logic_steps += 1;
        try std.testing.expect(logic_steps < 3000);
    }

    var actual: [32]u8 = undefined;
    trace.final(&actual);
    const expected = [_]u8{
        0x10, 0x81, 0x43, 0xf0, 0xbc, 0x56, 0x31, 0x53,
        0x4a, 0xed, 0xe8, 0x7f, 0x93, 0x85, 0x26, 0x06,
        0x3b, 0xfb, 0x8b, 0x4d, 0xac, 0x64, 0x76, 0x68,
        0xf8, 0x66, 0x2b, 0x6f, 0x6b, 0xba, 0xab, 0xff,
    };
    try std.testing.expectEqualSlices(u8, &expected, &actual);
    try std.testing.expectEqual(@as(u32, 2665), first.frame);
    try std.testing.expect(first.players[@intFromEnum(td.Owner.opponent)].defeated);
}

test "DestroyStructures defeats a side with infantry but no building or MCV" {
    var world = td.combat.e1DuelFixture();
    world.units[1].active = false;
    world.units[1].health = 0;

    td.step.tickFrame(&world);

    try std.testing.expect(world.infantry[1].active);
    try std.testing.expect(world.players[@intFromEnum(td.Owner.opponent)].defeat_pending);
    try std.testing.expect(!world.players[@intFromEnum(td.Owner.opponent)].defeated);
    for (0..31) |_| td.step.tickFrame(&world);

    try std.testing.expectEqual(@as(i16, 0), world.infantry[1].health);
    try std.testing.expect(world.players[@intFromEnum(td.Owner.opponent)].defeated);
    try std.testing.expect(td.step.isTerminal(&world));
}

test "queued attack event clears navigation without stopping the active segment" {
    var world = td.combat.e1DuelFixture();
    const infantry = &world.infantry[0];
    infantry.mission = 1;
    infantry.mission_timer_due = 123;
    infantry.position = .{ .x = 5, .y = 11 };
    infantry.coord_x = 1_428;
    infantry.coord_y = 2_862;
    infantry.head_coord_x = 1_600;
    infantry.head_coord_y = 2_752;
    infantry.speed = 255;
    infantry.path_facing = 1;
    infantry.path = .{ 1, 1, 1, -1, -1, -1, -1, -1, -1 };
    infantry.destination = .{ .x = 14, .y = 0 };
    infantry.destination_valid = true;
    infantry.moving = true;
    infantry.animation = 3;

    try std.testing.expect(td.combat.apply(&world, .player, .{
        .command = .attack,
        .actor = 1,
        .target_kind = .visible_enemy,
        .target_slot = 1,
    }));
    td.combat.tickAfterUnitMissions(&world, null);

    try std.testing.expect(infantry.moving);
    try std.testing.expectEqual(@as(i16, 1_600), infantry.head_coord_x);
    try std.testing.expectEqual(@as(i16, 2_752), infantry.head_coord_y);
    try std.testing.expect(!infantry.destination_valid);
    try std.testing.expectEqual(@as(i8, -1), infantry.path_facing);
    try std.testing.expectEqual(@as(i8, -1), infantry.path[0]);
    try std.testing.expectEqual(@as(i8, 1), infantry.mission);
    try std.testing.expectEqual(@as(i8, -1), infantry.queued_mission);
    try std.testing.expectEqual(@as(u32, 123), infantry.mission_timer_due);

    _ = td.movement.tick(&world);
    try std.testing.expectEqual(@as(i16, 1_434), infantry.coord_x);
    try std.testing.expectEqual(@as(i16, 2_859), infantry.coord_y);
    try std.testing.expect(infantry.moving);
    try std.testing.expect(!infantry.destination_valid);
}

test "queued attack waits for active Barracks egress to reach a cell center" {
    var world = td.combat.e1DuelFixture();
    const infantry = &world.infantry[0];
    infantry.mission = 2;
    infantry.coord_x = 1_428;
    infantry.coord_y = 2_862;
    infantry.head_coord_x = 1_600;
    infantry.head_coord_y = 2_752;
    infantry.speed = 255;
    infantry.path_facing = 1;
    infantry.path = .{ 1, 1, 1, -1, -1, -1, -1, -1, -1 };
    infantry.destination = .{ .x = 14, .y = 0 };
    infantry.destination_valid = true;
    infantry.moving = true;
    infantry.tethered = true;

    try std.testing.expect(td.combat.apply(&world, .player, .{
        .command = .attack,
        .actor = 1,
        .target_kind = .visible_enemy,
        .target_slot = 1,
    }));
    td.combat.tickAfterUnitMissions(&world, null);
    td.combat.tickAfterUnitMissions(&world, null);

    try std.testing.expectEqual(@as(i8, 2), infantry.mission);
    try std.testing.expectEqual(@as(i8, 1), infantry.queued_mission);

    var entered = [_]bool{false} ** td.rules.max_infantry;
    entered[0] = true;
    infantry.moving = false;
    td.combat.perCellProcess(&world, &entered);
    td.combat.tickAfterUnitMissions(&world, null);
    try std.testing.expectEqual(@as(i8, 1), infantry.mission);
    try std.testing.expectEqual(@as(i8, -1), infantry.queued_mission);
}

test "Barracks arrival preserves a queued attack over the default guard mission" {
    var world = td.combat.e1DuelFixture();
    const infantry = &world.infantry[0];
    infantry.mission = 2;
    infantry.queued_mission = 1;
    infantry.position = .{ .x = 5, .y = 11 };
    infantry.coord_x = 1_594;
    infantry.coord_y = 2_755;
    infantry.head_coord_x = 1_600;
    infantry.head_coord_y = 2_752;
    infantry.speed = 255;
    infantry.path_facing = 1;
    infantry.path = .{ 1, -1, -1, -1, -1, -1, -1, -1, -1 };
    infantry.destination = .{ .x = 6, .y = 10 };
    infantry.destination_valid = true;
    infantry.moving = true;
    infantry.tethered = true;
    infantry.arrival_mission = 4;
    infantry.arrival_mission_delay = 7;

    const movement_frame = td.movement.tick(&world);
    try std.testing.expect(movement_frame.entered_cell[0]);
    try std.testing.expectEqual(@as(i8, 1), infantry.queued_mission);

    td.combat.tickAfterUnitMissions(&world, &movement_frame.moving_at_frame_start);
    try std.testing.expectEqual(@as(i8, 1), infantry.mission);
    try std.testing.expectEqual(@as(i8, -1), infantry.queued_mission);
}

test "ordinary movement arrival preserves a queued attack over the default guard mission" {
    var world = td.combat.e1DuelFixture();
    const infantry = &world.infantry[0];
    infantry.mission = 2;
    infantry.queued_mission = 1;
    infantry.position = .{ .x = 5, .y = 11 };
    infantry.coord_x = 1_594;
    infantry.coord_y = 2_755;
    infantry.head_coord_x = 1_600;
    infantry.head_coord_y = 2_752;
    infantry.speed = 255;
    infantry.path_facing = 1;
    infantry.path = .{ 1, -1, -1, -1, -1, -1, -1, -1, -1 };
    infantry.destination = .{ .x = 6, .y = 10 };
    infantry.destination_valid = true;
    infantry.moving = true;
    infantry.arrival_mission = 4;
    infantry.arrival_mission_delay = 7;

    const movement_frame = td.movement.tick(&world);
    try std.testing.expect(movement_frame.entered_cell[0]);
    try std.testing.expectEqual(@as(i8, 1), infantry.queued_mission);

    td.combat.tickAfterUnitMissions(&world, &movement_frame.moving_at_frame_start);
    try std.testing.expectEqual(@as(i8, 1), infantry.mission);
    try std.testing.expectEqual(@as(i8, -1), infantry.queued_mission);
}

test "TD defender advantage prevents infantry from firing while moving" {
    var world = td.combat.e1DuelFixture();
    world.infantry[0].target = .{ .kind = .e1, .owner = .opponent, .index = 1 };
    world.infantry[0].moving = true;
    world.infantry[0].animation = 3;
    const facing = world.infantry[0].facing;

    td.combat.tickAfterUnitMissions(&world, null);

    try std.testing.expect(!world.infantry[0].firing);
    try std.testing.expectEqual(facing, world.infantry[0].facing);
}

test "TD defender advantage delays fire until the frame after movement stops" {
    var world = td.combat.e1DuelFixture();
    const attacker = &world.infantry[0];
    attacker.target = .{ .kind = .e1, .owner = .opponent, .index = 1 };
    attacker.destination = attacker.position;
    attacker.destination_valid = true;
    attacker.head_coord_x = attacker.coord_x;
    attacker.head_coord_y = attacker.coord_y;
    attacker.facing = 0;
    attacker.speed = 255;
    attacker.moving = true;
    attacker.animation = 3;

    td.step.tickFrame(&world);

    try std.testing.expect(!attacker.moving);
    try std.testing.expect(!attacker.firing);
    try std.testing.expect(!attacker.destination_valid);
    try std.testing.expect(attacker.target.valid());
    try std.testing.expectEqual(@as(u8, 0), attacker.facing);

    td.step.tickFrame(&world);

    try std.testing.expect(attacker.firing);
    try std.testing.expectEqual(@as(u8, 64), attacker.facing);
}

test "Vanilla re-arms an interrupted fire animation without restarting it" {
    var world = td.combat.e1DuelFixture();
    const attacker = &world.infantry[0];
    attacker.target = .{ .kind = .e1, .owner = .opponent, .index = 1 };
    attacker.animation = 4;
    attacker.animation_stage = 0;
    attacker.animation_timer = 1;
    attacker.animation_rate = 1;
    attacker.firing = false;

    td.combat.tickAfterUnitMissions(&world, null);

    try std.testing.expect(attacker.firing);
    try std.testing.expectEqual(@as(i8, 4), attacker.animation);
    try std.testing.expectEqual(@as(u16, 1), attacker.animation_stage);
}

test "E1 instant bullet damages Vanilla aluminum MCV and consumes impact scatter RNG" {
    var world = td.World.reset(1);
    world.rng_state = 3_052_056_610;
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .opponent,
        .position = .{ .x = 3, .y = 8 },
        .health = 50,
        .coord_x = 960,
        .coord_y = 2240,
        .facing = 192,
        .mission = 13,
        .target = .{ .kind = .mcv, .owner = .player, .index = 0 },
        .animation = 4,
        .animation_stage = 1,
        .animation_timer = 1,
        .animation_rate = 1,
        .ammo = -1,
        .firing = true,
        .second_shot = true,
    };
    world.infantry_count = 1;

    td.combat.tickAfterUnitMissions(&world, null);

    try std.testing.expectEqual(@as(i16, 592), world.units[0].health);
    try std.testing.expectEqual(@as(u32, 3_538_127_539), world.rng_state);
    try std.testing.expectEqual(@as(u16, 0), world.projectile_count);
    try std.testing.expectEqual(td.state.Failure.none, world.failure);
}

test "E3 TOW against a vehicle is accurate and consumes no launch RNG" {
    var world = td.World.reset(1);
    world.rng_state = 2_387_194_449;
    world.infantry[0] = .{
        .active = true,
        .kind = .e3,
        .owner = .opponent,
        .position = .{ .x = 5, .y = 9 },
        .health = 25,
        .coord_x = 1472,
        .coord_y = 2496,
        .facing = 192,
        .mission = 13,
        .target = .{ .kind = .mcv, .owner = .player, .index = 0 },
        .animation = 4,
        .animation_stage = 2,
        .animation_timer = 1,
        .animation_rate = 1,
        .ammo = -1,
        .firing = true,
        .second_shot = true,
    };
    world.infantry_count = 1;

    td.combat.tickAfterUnitMissions(&world, null);

    try std.testing.expectEqual(@as(u32, 2_387_194_449), world.rng_state);
    try std.testing.expectEqual(@as(u16, 1), world.projectile_count);
    try std.testing.expectEqual(@as(i32, 640), world.projectiles[0].fuse_x);
    try std.testing.expectEqual(@as(i32, 2176), world.projectiles[0].fuse_y);
}

test "Vanilla advances an older TOW before a later bullet reuses a lower pool slot" {
    var world = td.World.reset(1);
    world.frame = 8195;
    world.projectiles[1] = .{
        .active = true,
        .id = 1,
        .kind = .tow,
        .source = .{ .kind = .e3, .owner = .opponent, .index = 5 },
        .target = .{ .kind = .mcv, .owner = .player, .index = 0 },
        .coord_x = 840,
        .coord_y = 2284,
        .fuse_x = 640,
        .fuse_y = 2176,
        .strength = 30,
        .facing = 206,
        .desired_facing = 206,
        .speed = 60,
        .timer = 9,
        .proximity = 254,
    };
    world.projectiles[0] = .{
        .active = true,
        .id = 0,
        .kind = .bullet,
        .source = .{ .kind = .e1, .owner = .opponent, .index = 6 },
        .target = .{ .kind = .mcv, .owner = .player, .index = 0 },
        .coord_x = 640,
        .coord_y = 2176,
        .fuse_x = 640,
        .fuse_y = 2176,
        .strength = 8,
        .timer = 4,
    };
    world.projectile_order[0] = 1;
    world.projectile_order[1] = 0;
    world.projectile_count = 2;

    td.combat.tickAfterUnitMissions(&world, null);

    try std.testing.expect(world.projectiles[1].active);
    try std.testing.expectEqual(@as(i32, 785), world.projectiles[1].coord_x);
    try std.testing.expectEqual(@as(i32, 2261), world.projectiles[1].coord_y);
    try std.testing.expectEqual(@as(i16, 209), world.projectiles[1].facing);
    try std.testing.expectEqual(@as(u8, 8), world.projectiles[1].timer);
    try std.testing.expectEqual(@as(i16, 187), world.projectiles[1].proximity);
    try std.testing.expect(!world.projectiles[0].active);
    try std.testing.expectEqual(@as(u16, 1), world.projectile_count);
}

test "Vanilla defeat tick destroys the last object without advancing Frame" {
    var world = td.World.reset(1);
    world.frame = 8358;
    world.rng_state = 3_005_779_518;
    world.easy_ai.active = false;
    world.units[0].health = 7;
    world.units[0].mission_timer_due = 9000;
    world.units[1].mission_timer_due = 9000;
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .opponent,
        .position = .{ .x = 3, .y = 8 },
        .health = 50,
        .coord_x = 960,
        .coord_y = 2240,
        .facing = 192,
        .mission = 13,
        .target = .{ .kind = .mcv, .owner = .player, .index = 0 },
        .animation = 4,
        .animation_stage = 1,
        .animation_timer = 1,
        .animation_rate = 1,
        .ammo = -1,
        .firing = true,
        .second_shot = true,
    };
    world.infantry_count = 1;

    _ = td.step.stepEasyAIFrame(&world);

    try std.testing.expectEqual(@as(u32, 8358), world.frame);
    try std.testing.expect(!world.units[0].active);
    try std.testing.expectEqual(@as(i16, 0), world.units[0].health);
    try std.testing.expect(world.players[@intFromEnum(td.Owner.player)].defeated);
    try std.testing.expectEqual(@as(u16, 1), world.infantry[0].kills);
    try std.testing.expectEqual(@as(u32, 3_024_861_676), world.rng_state);
}

test "HUNT does not assign navigation while its target is already in weapon range" {
    var world = td.combat.e1DuelFixture();
    const attacker = &world.infantry[0];
    attacker.mission = 13;
    attacker.mission_timer_due = 0;
    attacker.target = .{ .kind = .e1, .owner = .opponent, .index = 1 };
    attacker.destination_valid = false;

    td.combat.tickInfantryMissions(&world);

    try std.testing.expect(!attacker.destination_valid);
    try std.testing.expect(attacker.target.valid());
}

test "E1 weapon range includes the target building footprint" {
    var world = td.World.reset(1);
    for (&world.units) |*unit| unit.active = false;
    try std.testing.expect(world.addBuilding(.player, .construction_yard, .{ .x = 1, .y = 7 }));
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .opponent,
        .position = .{ .x = 4, .y = 6 },
        .coord_x = 1_216,
        .coord_y = 1_728,
        .health = 50,
        .mission = 13,
        .target = .{ .kind = .construction_yard, .owner = .player, .index = 0 },
        .animation = 0,
        .ammo = -1,
    };
    world.infantry_count = 1;

    td.combat.tickAfterUnitMissions(&world, null);

    try std.testing.expect(world.infantry[0].firing);
    try std.testing.expectEqual(@as(i8, 4), world.infantry[0].animation);

    td.combat.tickAfterUnitMissions(&world, null);
    td.combat.tickAfterUnitMissions(&world, null);
    try std.testing.expectEqual(@as(i16, 792), world.buildings[0].health);

    world.infantry[0].weapon_cooldown = 0;
    world.infantry[0].animation = 0;
    world.infantry[0].animation_stage = 0;
    world.infantry[0].animation_timer = 0;
    world.infantry[0].animation_rate = 0;
    td.combat.tickAfterUnitMissions(&world, null);
    td.combat.tickAfterUnitMissions(&world, null);
    td.combat.tickAfterUnitMissions(&world, null);
    try std.testing.expectEqual(@as(i16, 784), world.buildings[0].health);
    try std.testing.expectEqual(@as(i16, 29), world.players[@intFromEnum(td.Owner.player)].power);
}

test "building half-health damage consumes Vanilla fire-effect RNG" {
    var world = td.World.reset(1);
    for (&world.units) |*unit| unit.active = false;
    try std.testing.expect(world.addBuilding(.player, .construction_yard, .{ .x = 1, .y = 7 }));
    world.buildings[0].health = 400;
    world.players[@intFromEnum(td.Owner.player)].power = 15;
    world.rng_state = 0x12345678;
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .opponent,
        .position = .{ .x = 4, .y = 6 },
        .coord_x = 1_216,
        .coord_y = 1_728,
        .health = 50,
        .mission = 13,
        .target = .{ .kind = .construction_yard, .owner = .player, .index = 0 },
        .animation = 0,
        .ammo = -1,
    };
    world.infantry_count = 1;

    td.combat.tickAfterUnitMissions(&world, null);
    td.combat.tickAfterUnitMissions(&world, null);
    td.combat.tickAfterUnitMissions(&world, null);

    try std.testing.expectEqual(@as(i16, 392), world.buildings[0].health);
    try std.testing.expectEqual(@as(u32, 1_319_661_479), world.rng_state);

    world.infantry[0].active = false;
    for (0..41) |_| td.combat.tickAfterUnitMissions(&world, null);
    try std.testing.expectEqual(@as(i16, 392), world.buildings[0].health);
    td.combat.tickAfterUnitMissions(&world, null);
    try std.testing.expectEqual(@as(i16, 391), world.buildings[0].health);
}

test "Vanilla GUARD checks idle animation before rolling its next mission delay" {
    var world = td.World.reset(1);
    world.frame = 0;
    world.rng_state = 3_387_319_283;
    world.infantry[0] = .{
        .active = true,
        .kind = .e1,
        .owner = .player,
        .position = .{ .x = 7, .y = 9 },
        .health = 50,
        .coord_x = 1_856,
        .coord_y = 2_368,
        .facing = 128,
        .mission = 4,
        .mission_timer_due = 0,
        .animation = 0,
        .ammo = -1,
    };
    world.infantry_count = 1;

    td.combat.tickInfantryMissions(&world);

    try std.testing.expectEqual(@as(u32, 2_705_408_809), world.rng_state);
    try std.testing.expectEqual(@as(u32, 15), world.infantry[0].mission_timer_due);
    try std.testing.expectEqual(@as(i8, 0), world.infantry[0].animation);
    try std.testing.expectEqual(@as(u8, 128), world.infantry[0].facing);
}
