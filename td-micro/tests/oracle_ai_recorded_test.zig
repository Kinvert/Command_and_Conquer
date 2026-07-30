const std = @import("std");
const td = @import("td_micro");

const OraclePlayer = struct {
    credits: i32,
    power: i32,
    drain: i32,
    tiberium: i32 = 0,
    capacity: i32 = 0,
    harvested: u32 = 0,
    defeated: u8,
};

const OracleQueue = struct {
    owner: u8,
    category: u8,
    active: u8,
    completed: u8,
    product: u8,
    stage: u16,
    timer: u8,
    rate: u8,
    balance: i32,
};

const OracleEntity = struct {
    id: u16,
    kind: u8,
    owner: u8,
    active: u8,
    limbo: u8,
    cell: [2]i16,
    coord: [2]i32,
    head_coord: [2]i32,
    health: i16,
    facing: i16,
    mission: i8,
    queued_mission: i8,
    status: i8,
    cooldown: u8,
    moving: u8,
    firing: u8,
    deploying: u8,
    target: u64,
    speed: u8,
    path_facing: i8,
    new_destination: u8,
    animation: i8,
    animation_stage: u16,
    animation_timer: u8,
    animation_rate: u8,
    prone: u8,
    fear: u8,
    ammo: i16,
    kills: u16,
    second_shot: u8,
    cargo: u8 = 0,
    harvesting: u8 = 0,
    destination: u64,
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
    desired_facing: u8,
    speed: u8,
    speed_accum: u16,
    timer: u8,
    arming: u8,
    proximity: i16,
    source_owner: u8,
    source_kind: u8,
    source_id: u16,
    target_owner: u8,
    target_kind: u8,
    target_id: u16,
};

const OracleAICommand = struct {
    frame: u32,
    command: u8,
    actor_id: u16,
    product: u8,
    target_kind: u8,
    target: [2]i16,
};

const OracleAI = struct {
    active: u8,
    state: i8,
    started: u8,
    alerted: u8,
    base_building: u8,
    tiberium_short: u8,
    difficulty: u8,
    enemy: u8,
    ai_timer: u16,
    attack_timer: u32,
    build_structure: u8,
    build_infantry: u8,
    has_center: u8,
    center: [2]i16,
    radius: u16,
    maximum: [3]u16,
};

const OracleSnapshot = struct {
    decision: u32,
    frame: u32,
    rng_state: u32,
    players: []const OraclePlayer,
    ai: OracleAI,
    queues: []const OracleQueue,
    entities: []const OracleEntity,
    projectiles: []const OracleProjectile,
    ai_commands: []const OracleAICommand,
    tiberium: []const [2]u16 = &.{},
};

fn expectAI(expected: OracleAI, actual: td.state.EasyAIState) !void {
    try std.testing.expectEqual(expected.active != 0, actual.active);
    try std.testing.expectEqual(expected.state, actual.state);
    try std.testing.expectEqual(expected.started != 0, actual.started);
    try std.testing.expectEqual(expected.alerted != 0, actual.alerted);
    try std.testing.expectEqual(expected.base_building != 0, actual.base_building);
    try std.testing.expectEqual(expected.tiberium_short != 0, actual.tiberium_short);
    try std.testing.expectEqual(expected.difficulty, actual.difficulty);
    try std.testing.expectEqual(expected.enemy, @intFromEnum(actual.enemy));
    try std.testing.expectEqual(expected.ai_timer, actual.ai_timer);
    try std.testing.expectEqual(expected.attack_timer, actual.attack_timer);
    try std.testing.expectEqual(expected.build_structure, @intFromEnum(actual.build_structure));
    try std.testing.expectEqual(expected.build_infantry, @intFromEnum(actual.build_infantry));
    try std.testing.expectEqual(expected.has_center != 0, actual.has_center);
    try std.testing.expectEqual(expected.center[0], actual.center_x);
    try std.testing.expectEqual(expected.center[1], actual.center_y);
    try std.testing.expectEqual(expected.radius, actual.radius);
    try std.testing.expectEqual(expected.maximum[0], actual.max_units);
    try std.testing.expectEqual(expected.maximum[1], actual.max_buildings);
    try std.testing.expectEqual(expected.maximum[2], actual.max_infantry);
}

fn actionFromOracle(command: OracleAICommand) td.step.TimedAction {
    return .{
        .frame = command.frame,
        .action = .{
            .command = @enumFromInt(command.command),
            .actor = @intCast(command.actor_id),
            .product = @enumFromInt(command.product),
            .target_kind = @enumFromInt(command.target_kind),
            .target_x = @intCast(command.target[0]),
            .target_y = @intCast(command.target[1]),
        },
    };
}

fn oracleQueue(snapshot: OracleSnapshot, category: u8) ?OracleQueue {
    for (snapshot.queues) |queue| {
        if (queue.owner == @intFromEnum(td.Owner.opponent) and queue.category == category) return queue;
    }
    return null;
}

fn expectQueue(expected: OracleQueue, actual: td.state.ProductionQueue) !void {
    try std.testing.expectEqual(expected.active != 0, actual.active);
    try std.testing.expectEqual(expected.completed != 0, actual.completed);
    try std.testing.expectEqual(expected.product, @intFromEnum(actual.product));
    try std.testing.expectEqual(expected.stage, actual.stage);
    try std.testing.expectEqual(expected.timer, actual.stage_timer);
    try std.testing.expectEqual(expected.rate, actual.rate);
    try std.testing.expectEqual(expected.balance, actual.balance);
}

fn expectEntities(world: *const td.World, snapshot: OracleSnapshot) !void {
    var expected_count: usize = 0;
    for (snapshot.entities) |entity| {
        const kind: td.ObjectType = @enumFromInt(entity.kind);
        if (entity.active == 0 or (entity.limbo != 0 and kind != .harvester)) continue;
        expected_count += 1;
        const owner: td.Owner = @enumFromInt(entity.owner);
        if (kind == .mcv) {
            const actual = world.units[@intFromEnum(owner)];
            try std.testing.expect(actual.active);
            try std.testing.expectEqual(owner, actual.owner);
            try std.testing.expectEqual(@as(u8, @intCast(entity.cell[0])), actual.position.x);
            try std.testing.expectEqual(@as(u8, @intCast(entity.cell[1])), actual.position.y);
            try std.testing.expectEqual(entity.health, actual.health);
            try std.testing.expectEqual(@as(u8, @intCast(entity.facing)), actual.facing);
            try std.testing.expectEqual(entity.mission, actual.mission);
            try std.testing.expectEqual(@as(u8, @intCast(entity.status)), actual.status);
            try std.testing.expectEqual(entity.deploying != 0, actual.deploying);
            continue;
        }

        if (kind == .harvester) {
            var found: ?td.state.Unit = null;
            for (world.units) |unit| {
                if (unit.active and unit.owner == owner and unit.kind == .harvester) {
                    found = unit;
                    break;
                }
            }
            const actual = found orelse return error.MissingHarvester;
            try std.testing.expectEqual(entity.health, actual.health);
            try std.testing.expectEqual(entity.mission, actual.mission);
            try std.testing.expectEqual(@as(u8, @intCast(entity.status)), actual.status);
            try std.testing.expectEqual(entity.cargo, actual.cargo_steps);
            try std.testing.expectEqual(entity.harvesting != 0, actual.harvesting);
            if (entity.limbo == 0) {
                if (entity.cell[0] != actual.position.x or entity.cell[1] != actual.position.y) {
                    std.debug.print(
                        "harvester expected cell=[{d},{d}] coord=[{d},{d}] facing={d} path={d}; found cell=[{d},{d}] coord=[{d},{d}] facing={d} path={d} track={d}:{d} head=[{d},{d}] dest={}[{d},{d}] archive={}[{d},{d}]\n",
                        .{
                            entity.cell[0],
                            entity.cell[1],
                            entity.coord[0],
                            entity.coord[1],
                            entity.facing,
                            entity.path_facing,
                            actual.position.x,
                            actual.position.y,
                            actual.coord_x,
                            actual.coord_y,
                            actual.facing,
                            actual.path_facing,
                            actual.track_number,
                            actual.track_index,
                            actual.head_coord_x,
                            actual.head_coord_y,
                            actual.destination_valid,
                            actual.destination.x,
                            actual.destination.y,
                            actual.archive_destination_valid,
                            actual.archive_destination.x,
                            actual.archive_destination.y,
                        },
                    );
                }
                try std.testing.expectEqual(@as(u8, @intCast(entity.cell[0])), actual.position.x);
                try std.testing.expectEqual(@as(u8, @intCast(entity.cell[1])), actual.position.y);
            }
            continue;
        }

        if (kind == .e1 or kind == .e3) {
            try std.testing.expect(entity.id < world.infantry.len);
            const actual = world.infantry[entity.id];
            if (entity.coord[0] != actual.coord_x or entity.coord[1] != actual.coord_y) {
                std.debug.print(
                    "infantry[{d}] expected coord=[{d},{d}] head=[{d},{d}] moving={d} path={d}; found coord=[{d},{d}] head=[{d},{d}] moving={} path={d}\n",
                    .{
                        entity.id,
                        entity.coord[0],
                        entity.coord[1],
                        entity.head_coord[0],
                        entity.head_coord[1],
                        entity.moving,
                        entity.path_facing,
                        actual.coord_x,
                        actual.coord_y,
                        actual.head_coord_x,
                        actual.head_coord_y,
                        actual.moving,
                        actual.path_facing,
                    },
                );
            }
            if (entity.health != actual.health or
                entity.animation != actual.animation or
                (entity.prone != 0) != actual.prone or
                entity.fear != actual.fear)
            {
                std.debug.print(
                    "infantry[{d}] expected health={d} animation={d}:{d}/{d} prone={d} fear={d}; found health={d} animation={d}:{d}/{d} prone={} fear={d}\n",
                    .{
                        entity.id,
                        entity.health,
                        entity.animation,
                        entity.animation_stage,
                        entity.animation_timer,
                        entity.prone,
                        entity.fear,
                        actual.health,
                        actual.animation,
                        actual.animation_stage,
                        actual.animation_timer,
                        actual.prone,
                        actual.fear,
                    },
                );
            }
            try std.testing.expect(actual.active);
            try std.testing.expectEqual(owner, actual.owner);
            try std.testing.expectEqual(kind, actual.kind);
            try std.testing.expectEqual(@as(u8, @intCast(entity.cell[0])), actual.position.x);
            try std.testing.expectEqual(@as(u8, @intCast(entity.cell[1])), actual.position.y);
            try std.testing.expectEqual(@as(i16, @intCast(entity.coord[0])), actual.coord_x);
            try std.testing.expectEqual(@as(i16, @intCast(entity.coord[1])), actual.coord_y);
            try std.testing.expectEqual(@as(i16, @intCast(entity.head_coord[0])), actual.head_coord_x);
            try std.testing.expectEqual(@as(i16, @intCast(entity.head_coord[1])), actual.head_coord_y);
            try std.testing.expectEqual(entity.health, actual.health);
            try std.testing.expectEqual(@as(u8, @intCast(entity.facing)), actual.facing);
            try std.testing.expectEqual(entity.mission, actual.mission);
            try std.testing.expectEqual(entity.queued_mission, actual.queued_mission);
            try std.testing.expectEqual(entity.cooldown, actual.weapon_cooldown);
            try std.testing.expectEqual(entity.moving != 0, actual.moving);
            try std.testing.expectEqual(entity.firing != 0, actual.firing);
            try std.testing.expectEqual(entity.target != 0, actual.target.valid());
            try std.testing.expectEqual(entity.speed, actual.speed);
            try std.testing.expectEqual(entity.path_facing, actual.path_facing);
            try std.testing.expectEqual(entity.new_destination != 0, actual.new_destination);
            try std.testing.expectEqual(entity.animation, actual.animation);
            try std.testing.expectEqual(entity.animation_stage, actual.animation_stage);
            try std.testing.expectEqual(entity.animation_timer, actual.animation_timer);
            try std.testing.expectEqual(entity.animation_rate, actual.animation_rate);
            try std.testing.expectEqual(entity.prone != 0, actual.prone);
            try std.testing.expectEqual(entity.fear, actual.fear);
            try std.testing.expectEqual(entity.ammo, actual.ammo);
            try std.testing.expectEqual(entity.kills, actual.kills);
            try std.testing.expectEqual(entity.second_shot != 0, actual.second_shot);
            try std.testing.expectEqual(entity.destination != 0, actual.destination_valid);
            continue;
        }

        var found = false;
        for (world.buildings) |building| {
            if (!building.active or building.owner != owner or building.kind != kind) continue;
            if (entity.health != building.health) {
                std.debug.print(
                    "{s} {s} at [{d},{d}] expected health={d}; found health={d}\n",
                    .{ @tagName(owner), @tagName(kind), building.position.x, building.position.y, entity.health, building.health },
                );
            }
            try std.testing.expectEqual(@as(u8, @intCast(entity.cell[0])), building.position.x);
            try std.testing.expectEqual(@as(u8, @intCast(entity.cell[1])), building.position.y);
            try std.testing.expectEqual(entity.health, building.health);
            try std.testing.expectEqual(entity.mission != 17, building.operational);
            found = true;
            break;
        }
        try std.testing.expect(found);
    }

    var actual_count: usize = 0;
    for (world.units) |unit| {
        if (unit.active) actual_count += 1;
    }
    for (world.buildings) |building| {
        if (building.active) actual_count += 1;
    }
    for (world.infantry) |infantry| {
        if (infantry.active) actual_count += 1;
    }
    try std.testing.expectEqual(expected_count, actual_count);
}

fn expectProjectiles(expected: []const OracleProjectile, world: *const td.World) !void {
    var active: usize = 0;
    for (world.projectiles) |projectile| {
        if (!projectile.active) continue;
        if (active >= expected.len) return error.UnexpectedProjectile;
        const oracle = expected[active];
        try std.testing.expectEqual(oracle.active != 0, projectile.active);
        try std.testing.expectEqual(@as(u8, 0), oracle.limbo);
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
        if (projectile.target.kind == .mcv) {
            try std.testing.expectEqual(@as(u16, @intFromEnum(projectile.target.owner)), projectile.target.index);
        } else {
            try std.testing.expectEqual(oracle.target_id, projectile.target.index);
        }
        active += 1;
    }
    try std.testing.expectEqual(expected.len, active);
}

fn expectSnapshot(world: *const td.World, oracle: OracleSnapshot, compare_rng: bool) !void {
    try std.testing.expectEqual(oracle.frame, world.frame);
    if (compare_rng) try std.testing.expectEqual(oracle.rng_state, world.rng_state);
    inline for (.{ td.Owner.player, td.Owner.opponent }) |owner| {
        const expected_player = oracle.players[@intFromEnum(owner)];
        const actual_player = world.players[@intFromEnum(owner)];
        try std.testing.expectEqual(expected_player.credits, actual_player.credits);
        try std.testing.expectEqual(expected_player.power, actual_player.power);
        try std.testing.expectEqual(expected_player.drain, actual_player.drain);
        try std.testing.expectEqual(expected_player.tiberium, actual_player.tiberium);
        try std.testing.expectEqual(expected_player.capacity, actual_player.capacity);
        try std.testing.expectEqual(expected_player.harvested, actual_player.harvested_credits);
        try std.testing.expectEqual(expected_player.defeated != 0, actual_player.defeated);
    }
    if (compare_rng) try expectAI(oracle.ai, world.easy_ai);
    try expectQueue(
        oracleQueue(oracle, 0) orelse return error.MissingStructureQueue,
        world.queues[@intFromEnum(td.Owner.opponent)][@intFromEnum(td.state.QueueKind.structure)],
    );
    try expectQueue(
        oracleQueue(oracle, 1) orelse return error.MissingInfantryQueue,
        world.queues[@intFromEnum(td.Owner.opponent)][@intFromEnum(td.state.QueueKind.infantry)],
    );
    try expectEntities(world, oracle);
    try expectProjectiles(oracle.projectiles, world);
    if (oracle.tiberium.len != 0) {
        var expected = [_]u8{0} ** (64 * 64);
        var present = [_]u64{0} ** 64;
        for (0..world.map_height) |y| {
            for (0..world.map_width) |x| {
                const position = td.state.Position{ .x = @intCast(x), .y = @intCast(y) };
                const cell = td.map.at(position).?;
                if (cell.land_type == 5 and cell.overlay_data == 0) {
                    const index = y * 64 + x;
                    present[index / 64] |= @as(u64, 1) << @intCast(index % 64);
                }
            }
        }
        for (oracle.tiberium) |cell| {
            expected[cell[0]] = @intCast(cell[1]);
            present[cell[0] / 64] |= @as(u64, 1) << @intCast(cell[0] % 64);
        }
        try std.testing.expectEqualSlices(u8, &expected, &world.tiberium_steps);
        try std.testing.expectEqualSlices(u64, &present, &world.tiberium_present);
    }
}

fn expectCommands(expected: []const OracleAICommand, actual: []const td.step.TimedAction) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |expected_command, actual_command| {
        if (expected_command.product != @intFromEnum(actual_command.action.product)) {
            std.debug.print("command frame {d}: expected product {d}, found {d}\n", .{
                expected_command.frame,
                expected_command.product,
                @intFromEnum(actual_command.action.product),
            });
        }
        if (expected_command.target[0] != actual_command.action.target_x or expected_command.target[1] != actual_command.action.target_y) {
            std.debug.print("command frame {d}: expected target ({d},{d}), found ({d},{d})\n", .{
                expected_command.frame,
                expected_command.target[0],
                expected_command.target[1],
                actual_command.action.target_x,
                actual_command.action.target_y,
            });
        }
        try std.testing.expectEqual(expected_command.frame, actual_command.frame);
        try std.testing.expectEqual(expected_command.command, @intFromEnum(actual_command.action.command));
        try std.testing.expectEqual(expected_command.actor_id, actual_command.action.actor);
        try std.testing.expectEqual(expected_command.product, @intFromEnum(actual_command.action.product));
        try std.testing.expectEqual(expected_command.target_kind, @intFromEnum(actual_command.action.target_kind));
        try std.testing.expectEqual(@as(u8, @intCast(expected_command.target[0])), actual_command.action.target_x);
        try std.testing.expectEqual(@as(u8, @intCast(expected_command.target[1])), actual_command.action.target_y);
    }
}

fn expectDifficultyOpening(trace: []const u8, requested: td.difficulty.Requested) !void {
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.World.reset(1);
    td.difficulty.enable(&world, requested);
    var prior_decision: u32 = 0;
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

        var commands: [32]td.step.TimedAction = undefined;
        var command_count: usize = 0;
        while (prior_decision < oracle.decision) {
            prior_decision += 1;
            const frame_commands = td.step.stepWithEasyAI(&world, .{});
            for (frame_commands.slice()) |command| {
                try std.testing.expect(command_count < commands.len);
                commands[command_count] = command;
                command_count += 1;
            }
        }

        expectCommands(oracle.ai_commands, commands[0..command_count]) catch |err| {
            std.debug.print(
                "{s} opening command divergence at decision {d}, frame {d}\n",
                .{ @tagName(requested), oracle.decision, oracle.frame },
            );
            return err;
        };
        expectSnapshot(&world, oracle, true) catch |err| {
            std.debug.print(
                "{s} opening state divergence at decision {d}, frame {d}\n",
                .{ @tagName(requested), oracle.decision, oracle.frame },
            );
            return err;
        };
    }
    try std.testing.expectEqual(@as(u32, 24), prior_decision);
}

test "autonomous AI opening matches Vanilla at every requested difficulty" {
    try expectDifficultyOpening(
        @embedFile("fixtures/vanilla_seed1_difficulty_easy_ai_opening.jsonl"),
        .easy,
    );
    try expectDifficultyOpening(
        @embedFile("fixtures/vanilla_seed1_difficulty_normal_ai_opening.jsonl"),
        .normal,
    );
    try expectDifficultyOpening(
        @embedFile("fixtures/vanilla_seed1_difficulty_hard_ai_opening.jsonl"),
        .hard,
    );
}

test "recorded Vanilla Easy AI opening commands replay through Barracks construction" {
    const trace = @embedFile("fixtures/vanilla_seed1_ai_opening.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();
    _ = lines.next();

    var world = td.World.reset(1);
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

        var commands: [8]td.step.TimedAction = undefined;
        try std.testing.expect(oracle.ai_commands.len <= commands.len);
        for (oracle.ai_commands, 0..) |command, index| commands[index] = actionFromOracle(command);
        td.step.stepWithOpponentCommands(&world, .{}, commands[0..oracle.ai_commands.len]);

        try expectSnapshot(&world, oracle, false);
    }
}

test "autonomous Zig Easy AI emits and executes the Vanilla opening" {
    const trace = @embedFile("fixtures/vanilla_seed1_ai_economy.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();
    _ = lines.next();

    var world = td.World.reset(1);
    var prior_decision: u32 = 0;
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
        if (oracle.decision > 320) break;

        var commands: [32]td.step.TimedAction = undefined;
        var command_count: usize = 0;
        var decision = prior_decision + 1;
        while (decision <= oracle.decision) : (decision += 1) {
            const frame_commands = td.step.stepWithEasyAI(&world, .{});
            for (frame_commands.slice()) |command| {
                try std.testing.expect(command_count < commands.len);
                commands[command_count] = command;
                command_count += 1;
            }
        }
        prior_decision = oracle.decision;
        expectCommands(oracle.ai_commands, commands[0..command_count]) catch |err| {
            std.debug.print(
                "autonomous AI command state at frame {d}: center=[{d},{d}] radius={d} rng={d}\n",
                .{ oracle.frame, world.easy_ai.center_x, world.easy_ai.center_y, world.easy_ai.radius, world.rng_state },
            );
            return err;
        };
        expectSnapshot(&world, oracle, true) catch |err| {
            std.debug.print(
                "autonomous AI divergence at frame {d}: center={} attack={d} max_i={d} build_i={s} ai_timer={d} rng={d}\n",
                .{
                    oracle.frame,
                    world.easy_ai.has_center,
                    world.easy_ai.attack_timer,
                    world.easy_ai.max_infantry,
                    @tagName(world.easy_ai.build_infantry),
                    world.easy_ai.ai_timer,
                    world.rng_state,
                },
            );
            return err;
        };
    }
}

test "reduced Unit Count 6 opening matches autonomous Vanilla for 256 decisions" {
    const trace = @embedFile("fixtures/vanilla_seed1_starting_force.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.World.reset(1);
    td.curriculum.applyStartingForce(&world);
    var prior_decision: u32 = 0;
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

        var commands: [32]td.step.TimedAction = undefined;
        var command_count: usize = 0;
        while (prior_decision < oracle.decision) {
            prior_decision += 1;
            const frame_commands = td.step.stepWithEasyAI(&world, .{});
            for (frame_commands.slice()) |command| {
                try std.testing.expect(command_count < commands.len);
                commands[command_count] = command;
                command_count += 1;
            }
        }
        try expectCommands(oracle.ai_commands, commands[0..command_count]);
        expectSnapshot(&world, oracle, false) catch |err| {
            std.debug.print(
                "Unit Count 6 state divergence at decision {d}, frame {d}\n",
                .{ oracle.decision, oracle.frame },
            );
            return err;
        };
        expectAI(oracle.ai, world.easy_ai) catch |err| {
            std.debug.print(
                "Unit Count 6 AI-state divergence at decision {d}, frame {d}\n",
                .{ oracle.decision, oracle.frame },
            );
            return err;
        };
        std.testing.expectEqual(oracle.rng_state, world.rng_state) catch |err| {
            std.debug.print(
                "Unit Count 6 RNG divergence at decision {d}, frame {d}\n",
                .{ oracle.decision, oracle.frame },
            );
            return err;
        };
    }
    try std.testing.expectEqual(@as(u32, 256), prior_decision);
}

test "scripted player Refinery and free Harvester reach the first Vanilla delivery" {
    const trace = @embedFile("fixtures/vanilla_seed1_player_refinery_harvest.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();
    _ = lines.next();

    var world = td.World.reset(1);
    var delivered = false;
    var prior_decision: u32 = 0;
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
        if (oracle.decision > 800) break;
        var commands: [32]td.step.TimedAction = undefined;
        var command_count: usize = 0;
        var decision = prior_decision + 1;
        while (decision <= oracle.decision) : (decision += 1) {
            const player_action = switch (decision) {
                1 => td.Action{ .command = .deploy, .actor = 0 },
                23 => td.Action{ .command = .start_build, .product = .power_plant },
                77 => td.Action{ .command = .place, .product = .power_plant, .target_kind = .cell, .target_x = 4, .target_y = 7 },
                92 => td.Action{ .command = .start_build, .product = .refinery },
                579 => td.Action{ .command = .place, .product = .refinery, .target_kind = .cell, .target_x = 6, .target_y = 7 },
                else => td.Action{},
            };
            const frame_commands = td.step.stepWithEasyAI(&world, player_action);
            for (frame_commands.slice()) |command| {
                try std.testing.expect(command_count < commands.len);
                commands[command_count] = command;
                command_count += 1;
            }
        }
        prior_decision = oracle.decision;
        try expectCommands(oracle.ai_commands, commands[0..command_count]);
        expectSnapshot(&world, oracle, true) catch |err| {
            std.debug.print("scripted Refinery economy divergence at frame {d}\n", .{oracle.frame});
            for (world.infantry, 0..) |infantry, index| {
                if (!infantry.active) continue;
                std.debug.print(
                    "  infantry[{d}] coord=[{d},{d}] head=[{d},{d}] mission={d} due={d} target={s}/{s}/{d} destination=[{d},{d}] cooldown={d} firing={} animation={d}:{d}/{d} path_delay={d} path_facing={d} path={any}\n",
                    .{
                        index,
                        infantry.coord_x,
                        infantry.coord_y,
                        infantry.head_coord_x,
                        infantry.head_coord_y,
                        infantry.mission,
                        infantry.mission_timer_due,
                        @tagName(infantry.target.owner),
                        @tagName(infantry.target.kind),
                        infantry.target.index,
                        infantry.destination.x,
                        infantry.destination.y,
                        infantry.weapon_cooldown,
                        infantry.firing,
                        infantry.animation,
                        infantry.animation_stage,
                        infantry.animation_timer,
                        infantry.path_delay,
                        infantry.path_facing,
                        infantry.path,
                    },
                );
            }
            return err;
        };
        if (world.players[@intFromEnum(td.Owner.player)].harvested_credits != 0) delivered = true;
    }
    try std.testing.expect(delivered);
}

test "recorded legacy AI commands replay while the player builds the infantry opening" {
    const trace = @embedFile("fixtures/vanilla_seed1_policy_economy.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();
    _ = lines.next();

    var world = td.World.reset(1);
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
        if (oracle.decision > 160) break;
        const player_action = switch (oracle.decision) {
            1 => td.Action{ .command = .deploy, .actor = 0 },
            23 => td.Action{ .command = .start_build, .product = .power_plant },
            77 => td.Action{ .command = .place, .product = .power_plant, .target_kind = .cell, .target_x = 4, .target_y = 7 },
            92 => td.Action{ .command = .start_build, .product = .barracks },
            146 => td.Action{ .command = .place, .product = .barracks, .target_kind = .cell, .target_x = 6, .target_y = 7 },
            161 => td.Action{ .command = .train, .product = .e1 },
            189 => td.Action{ .command = .train, .product = .e3 },
            else => td.Action{},
        };

        var commands: [8]td.step.TimedAction = undefined;
        try std.testing.expect(oracle.ai_commands.len <= commands.len);
        for (oracle.ai_commands, 0..) |command, index| commands[index] = actionFromOracle(command);
        td.step.stepWithOpponentCommands(&world, player_action, commands[0..oracle.ai_commands.len]);
        expectSnapshot(&world, oracle, false) catch |err| {
            std.debug.print("scripted-player recorded-command divergence at frame {d}\n", .{oracle.frame});
            for (world.infantry, 0..) |infantry, index| {
                if (!infantry.active or infantry.owner != .player) continue;
                std.debug.print(
                    "  player infantry[{d}] mission={d} queued={d} due={d} move_delay={d} moving={} animation={d}:{d}/{d} facing={d} rng={d}\n",
                    .{
                        index,
                        infantry.mission,
                        infantry.queued_mission,
                        infantry.mission_timer_due,
                        infantry.mission_delay,
                        infantry.moving,
                        infantry.animation,
                        infantry.animation_stage,
                        infantry.animation_timer,
                        infantry.facing,
                        world.rng_state,
                    },
                );
            }
            return err;
        };
    }
}

test "Vanilla object combat consumes shared RNG before Easy house AI" {
    var world = td.World.reset(1);
    world.frame = 7885;
    world.rng_state = 3_365_199_594;
    world.units[0].mission_timer_due = 7900;
    world.units[1].mission = 13;
    world.units[1].mission_timer_due = 7900;
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
        .mission_timer_due = 7900,
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
    world.easy_ai.ai_timer = 0;
    world.easy_ai.alert_timer = 10;
    world.easy_ai.attack_timer = 3327;

    _ = td.step.stepEasyAIFrame(&world);

    try std.testing.expectEqual(@as(u32, 7886), world.frame);
    try std.testing.expectEqual(@as(i16, 592), world.units[0].health);
    try std.testing.expectEqual(@as(u32, 2_755_369_809), world.rng_state);
    try std.testing.expectEqual(@as(u16, 77), world.easy_ai.ai_timer);
}

test "autonomous Zig Easy AI matches Vanilla through the economy opening" {
    const trace = @embedFile("fixtures/vanilla_seed1_ai_economy.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.World.reset(1);
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

        var commands: [32]td.step.TimedAction = undefined;
        var command_count: usize = 0;
        while (world.frame < oracle.frame or
            ((oracle.players[0].defeated != 0 or oracle.players[1].defeated != 0) and !td.step.isTerminal(&world)))
        {
            const frame_commands = td.step.stepEasyAIFrame(&world);
            for (frame_commands.slice()) |command| {
                try std.testing.expect(command_count < commands.len);
                commands[command_count] = command;
                command_count += 1;
            }
        }

        expectCommands(oracle.ai_commands, commands[0..command_count]) catch |err| {
            std.debug.print("long autonomous AI command divergence at frame {d}\n", .{oracle.frame});
            return err;
        };
        expectSnapshot(&world, oracle, true) catch |err| {
            std.debug.print("long autonomous AI divergence at frame {d}\n", .{oracle.frame});
            for (world.infantry, 0..) |infantry, index| {
                if (!infantry.active) continue;
                std.debug.print(
                    "  infantry[{d}] {s} coord=[{d},{d}] head=[{d},{d}] facing={d} mission={d} due={d} path={d} animation={d}:{d}/{d}\n",
                    .{ index, @tagName(infantry.kind), infantry.coord_x, infantry.coord_y, infantry.head_coord_x, infantry.head_coord_y, infantry.facing, infantry.mission, infantry.mission_timer_due, infantry.path_facing, infantry.animation, infantry.animation_stage, infantry.animation_timer },
                );
            }
            return err;
        };
    }
}
