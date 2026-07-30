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
    head_coord: [2]i32,
    facing: i16,
    mission: i8,
    queued_mission: i8,
    moving: u8,
    speed: u8,
    path_facing: i8,
    destination: u64,
};

fn oracleOpponentInfantry(snapshot: OracleSnapshot, id: u16) ?OracleEntity {
    for (snapshot.entities) |entity| {
        if (entity.id == id and entity.owner == 1 and
            (entity.kind == @intFromEnum(td.ObjectType.e1) or entity.kind == @intFromEnum(td.ObjectType.e3)))
        {
            return entity;
        }
    }
    return null;
}

const OracleSnapshot = struct {
    decision: u32,
    action: u8,
    actor: u8,
    product: u8,
    target_x: u8,
    target_y: u8,
    frame: u32,
    rng_state: u32,
    entities: []const OracleEntity,
};

fn playerAction(snapshot: OracleSnapshot) !td.Action {
    const product: td.ObjectType = @enumFromInt(snapshot.product);
    return switch (snapshot.action) {
        @intFromEnum(td.Command.noop) => .{},
        @intFromEnum(td.Command.deploy) => .{ .command = .deploy, .actor = snapshot.actor },
        @intFromEnum(td.Command.start_build) => .{ .command = .start_build, .product = product },
        @intFromEnum(td.Command.place) => .{
            .command = .place,
            .product = product,
            .target_kind = .cell,
            .target_x = snapshot.target_x,
            .target_y = snapshot.target_y,
        },
        @intFromEnum(td.Command.train) => .{ .command = .train, .product = product },
        else => error.UnsupportedRecordedAction,
    };
}

fn oracleE3(snapshot: OracleSnapshot) ?OracleEntity {
    for (snapshot.entities) |entity| {
        if (entity.owner == 0 and entity.kind == @intFromEnum(td.ObjectType.e3) and entity.active != 0 and entity.limbo == 0) return entity;
    }
    return null;
}

fn zigE3(world: *const td.World) ?td.state.Infantry {
    for (world.infantry) |infantry| {
        if (infantry.active and infantry.owner == .player and infantry.kind == .e3) return infantry;
    }
    return null;
}

fn expectEgress(expected: OracleEntity, actual: td.state.Infantry) !void {
    try std.testing.expectEqual(expected.cell[0], @as(i16, actual.position.x));
    try std.testing.expectEqual(expected.cell[1], @as(i16, actual.position.y));
    try std.testing.expectEqual(expected.coord[0], actual.coord_x);
    try std.testing.expectEqual(expected.coord[1], actual.coord_y);
    try std.testing.expectEqual(expected.head_coord[0], actual.head_coord_x);
    try std.testing.expectEqual(expected.head_coord[1], actual.head_coord_y);
    try std.testing.expectEqual(expected.facing, actual.facing);
    try std.testing.expectEqual(expected.mission, actual.mission);
    try std.testing.expectEqual(expected.queued_mission, actual.queued_mission);
    try std.testing.expectEqual(expected.moving != 0, actual.moving);
    try std.testing.expectEqual(expected.speed, actual.speed);
    try std.testing.expectEqual(expected.path_facing, actual.path_facing);
    try std.testing.expectEqual(expected.destination != 0, actual.destination_valid);
}

test "E3 Barracks egress selects a free sub-cell and matches Vanilla" {
    const trace = @embedFile("fixtures/vanilla_seed1_player_e1_e3.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.World.reset(1);
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
        if (oracle.decision == 0) continue;

        _ = td.step.stepWithEasyAI(&world, try playerAction(oracle));
        if (oracle.decision < 243) continue;
        if (oracle.decision > 258) break;

        try std.testing.expectEqual(oracle.frame, world.frame);
        const expected = oracleE3(oracle) orelse return error.MissingOracleE3;
        const actual = zigE3(&world) orelse return error.MissingZigE3;
        expectEgress(expected, actual) catch |err| {
            std.debug.print(
                "E3 egress divergence at decision {d}, frame {d}: expected coord {any}, head {any}, moving {d}, rng {d}; actual coord [{d},{d}], head [{d},{d}], moving {}, rng {d}\n",
                .{
                    oracle.decision,
                    oracle.frame,
                    expected.coord,
                    expected.head_coord,
                    expected.moving,
                    oracle.rng_state,
                    actual.coord_x,
                    actual.coord_y,
                    actual.head_coord_x,
                    actual.head_coord_y,
                    actual.moving,
                    world.rng_state,
                },
            );
            return err;
        };
        compared += 1;
    }
    try std.testing.expectEqual(@as(usize, 16), compared);
}

test "Harvester route congestion scatters stationary allied infantry like Vanilla" {
    const trace = @embedFile("fixtures/vanilla_seed1_ai_economy.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var world = td.World.reset(1);
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
        if (oracle.frame > 2608) break;

        while (world.frame < oracle.frame) _ = td.step.stepEasyAIFrame(&world);
        if (oracle.frame != 2608) continue;

        inline for (.{ @as(u16, 8), @as(u16, 9) }) |id| {
            const expected = oracleOpponentInfantry(oracle, id) orelse return error.MissingOracleInfantry;
            const actual = world.infantry[id];
            try std.testing.expect(expected.moving != 0);
            try std.testing.expect(expected.destination != 0);
            expectEgress(expected, actual) catch |err| {
                std.debug.print(
                    "vehicle-blocker scatter divergence for infantry {d} at frame {d}: expected coord {any}, head {any}, mission {d}, moving {d}; actual coord [{d},{d}], head [{d},{d}], mission {d}, moving {}\n",
                    .{
                        id,
                        oracle.frame,
                        expected.coord,
                        expected.head_coord,
                        expected.mission,
                        expected.moving,
                        actual.coord_x,
                        actual.coord_y,
                        actual.head_coord_x,
                        actual.head_coord_y,
                        actual.mission,
                        actual.moving,
                    },
                );
                return err;
            };
            compared += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), compared);
}
