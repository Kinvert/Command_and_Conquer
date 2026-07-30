const std = @import("std");
const td = @import("td_micro");

const OracleAIState = struct {
    owner: u8,
    state: i8,
    started: u8,
    alerted: u8,
    base_building: u8,
    difficulty: u8,
    ai_timer: i32,
    attack_timer: i32,
    build_structure: u8,
    build_infantry: u8,
    maximum: [3]u16,
};

const OracleEntity = struct {
    kind: u8,
    owner: u8,
    active: u8,
    limbo: u8,
};

const OracleAICommand = struct {
    frame: u32,
    sequence: u16,
    owner: u8,
    command: u8,
    actor_kind: u8,
    actor_id: u16,
    product: u8,
    target: [2]i16,
};

const OracleSnapshot = struct {
    decision: u32,
    frame: u32,
    ai: OracleAIState,
    ai_commands: []const OracleAICommand,
    entities: []const OracleEntity,
};

test "Vanilla Easy AI opening exports state and its deploy command" {
    const trace = @embedFile("fixtures/vanilla_seed1_idle64.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    const reset_line = lines.next() orelse return error.MissingResetSnapshot;
    const reset = try std.json.parseFromSlice(
        OracleSnapshot,
        std.testing.allocator,
        reset_line,
        .{ .ignore_unknown_fields = true },
    );
    defer reset.deinit();
    try std.testing.expectEqual(@as(u32, 0), reset.value.decision);
    try std.testing.expectEqual(@as(u8, @intFromEnum(td.Owner.opponent)), reset.value.ai.owner);
    try std.testing.expectEqual(@as(u8, 0), reset.value.ai.started);
    try std.testing.expectEqual(@as(u8, 0), reset.value.ai.alerted);
    try std.testing.expectEqual(@as(u8, 1), reset.value.ai.base_building);
    try std.testing.expectEqual(@as(u8, 2), reset.value.ai.difficulty);
    try std.testing.expectEqual(@as(u8, @intFromEnum(td.ObjectType.none)), reset.value.ai.build_structure);
    try std.testing.expectEqual(@as(u8, @intFromEnum(td.ObjectType.none)), reset.value.ai.build_infantry);
    try std.testing.expectEqual(@as(usize, 0), reset.value.ai_commands.len);

    const first_line = lines.next() orelse return error.MissingFirstDecision;
    const first = try std.json.parseFromSlice(
        OracleSnapshot,
        std.testing.allocator,
        first_line,
        .{ .ignore_unknown_fields = true },
    );
    defer first.deinit();
    try std.testing.expectEqual(@as(u32, 1), first.value.decision);
    try std.testing.expectEqual(@as(u8, 1), first.value.ai.started);
    try std.testing.expectEqual(@as(u8, 1), first.value.ai.alerted);
    try std.testing.expectEqual(@as(u8, @intFromEnum(td.ObjectType.power_plant)), first.value.ai.build_structure);
    try std.testing.expectEqual(@as(usize, 1), first.value.ai_commands.len);
    const deploy = first.value.ai_commands[0];
    try std.testing.expectEqual(@as(u8, @intFromEnum(td.Owner.opponent)), deploy.owner);
    try std.testing.expectEqual(@as(u8, @intFromEnum(td.Command.deploy)), deploy.command);
    try std.testing.expectEqual(@as(u8, @intFromEnum(td.ObjectType.mcv)), deploy.actor_kind);
    try std.testing.expectEqual(@as(u16, 0), deploy.actor_id);
    try std.testing.expectEqual(@as(u8, @intFromEnum(td.ObjectType.none)), deploy.product);
    try std.testing.expectEqual(@as(u32, 1), deploy.frame);
}

test "Vanilla Easy AI opening commands retain source phase order" {
    const trace = @embedFile("fixtures/vanilla_seed1_ai_opening.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    const expected = [_]OracleAICommand{
        .{ .frame = 1, .sequence = 0, .owner = 1, .command = 1, .actor_kind = 1, .actor_id = 0, .product = 0, .target = .{ 0, 0 } },
        .{ .frame = 84, .sequence = 0, .owner = 1, .command = 2, .actor_kind = 0, .actor_id = 0, .product = 3, .target = .{ 0, 0 } },
        .{ .frame = 300, .sequence = 0, .owner = 1, .command = 3, .actor_kind = 0, .actor_id = 0, .product = 3, .target = .{ 13, 3 } },
        .{ .frame = 300, .sequence = 1, .owner = 1, .command = 2, .actor_kind = 0, .actor_id = 0, .product = 7, .target = .{ 0, 0 } },
    };
    var command_index: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const parsed = try std.json.parseFromSlice(
            OracleSnapshot,
            std.testing.allocator,
            line,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        for (parsed.value.ai_commands) |actual| {
            try std.testing.expect(command_index < expected.len);
            const wanted = expected[command_index];
            try std.testing.expectEqual(wanted.frame, actual.frame);
            try std.testing.expectEqual(wanted.sequence, actual.sequence);
            try std.testing.expectEqual(wanted.command, actual.command);
            try std.testing.expectEqual(wanted.product, actual.product);
            try std.testing.expectEqual(wanted.target, actual.target);
            command_index += 1;
        }
    }
    try std.testing.expectEqual(expected.len, command_index);
}

test "Vanilla Easy AI deploy command is assigned at frame 1" {
    const trace = @embedFile("fixtures/vanilla_seed1_ai_deploy_frame.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    while (lines.next()) |line| {
        if (line.len == 0) break;
        const parsed = try std.json.parseFromSlice(
            OracleSnapshot,
            std.testing.allocator,
            line,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        if (parsed.value.frame == 0) {
            try std.testing.expectEqual(@as(usize, 0), parsed.value.ai_commands.len);
        } else if (parsed.value.frame == 1) {
            try std.testing.expectEqual(@as(usize, 1), parsed.value.ai_commands.len);
            try std.testing.expectEqual(@as(u32, 1), parsed.value.ai_commands[0].frame);
            try std.testing.expectEqual(@as(u8, @intFromEnum(td.Command.deploy)), parsed.value.ai_commands[0].command);
        } else {
            try std.testing.expectEqual(@as(usize, 0), parsed.value.ai_commands.len);
        }
    }
}

test "Vanilla Easy AI fields an early infantry force on the medium spawn" {
    const trace = @embedFile("fixtures/vanilla_seed2_ai_early_force.jsonl");
    var lines = std.mem.splitScalar(u8, trace, '\n');
    _ = lines.next();

    var initial_attack_timer: ?i32 = null;
    var infantry_cap_frame: ?u32 = null;
    var first_train_frame: ?u32 = null;
    var first_completed_frame: ?u32 = null;
    var maximum_completed: usize = 0;

    while (lines.next()) |line| {
        if (line.len == 0) break;
        const parsed = try std.json.parseFromSlice(
            OracleSnapshot,
            std.testing.allocator,
            line,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        const snapshot = parsed.value;

        if (snapshot.decision == 0) initial_attack_timer = snapshot.ai.attack_timer;
        if (snapshot.ai.maximum[2] > 0 and infantry_cap_frame == null) {
            infantry_cap_frame = snapshot.frame;
        }
        for (snapshot.ai_commands) |command| {
            const is_infantry = command.product == @intFromEnum(td.ObjectType.e1) or
                command.product == @intFromEnum(td.ObjectType.e3);
            if (command.owner == @intFromEnum(td.Owner.opponent) and
                command.command == @intFromEnum(td.Command.train) and is_infantry and
                first_train_frame == null)
            {
                first_train_frame = command.frame;
            }
        }

        var completed: usize = 0;
        for (snapshot.entities) |entity| {
            const is_infantry = entity.kind == @intFromEnum(td.ObjectType.e1) or
                entity.kind == @intFromEnum(td.ObjectType.e3);
            if (entity.owner == @intFromEnum(td.Owner.opponent) and
                entity.active != 0 and entity.limbo == 0 and is_infantry)
            {
                completed += 1;
            }
        }
        if (completed > 0 and first_completed_frame == null) first_completed_frame = snapshot.frame;
        maximum_completed = @max(maximum_completed, completed);
    }

    try std.testing.expectEqual(@as(?i32, 1_396), initial_attack_timer);
    try std.testing.expect((infantry_cap_frame orelse return error.MissingInfantryCap) <= 1_432);
    try std.testing.expect((first_train_frame orelse return error.MissingInfantryTrain) <= 1_430);
    try std.testing.expect((first_completed_frame orelse return error.MissingCompletedInfantry) <= 1_648);
    try std.testing.expect(maximum_completed >= 4);
}
