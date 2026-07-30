const std = @import("std");
const td = @import("td_micro");

test "spawn seeds select declared close and medium waypoint profiles" {
    const close = td.map.profileForSeed(1) orelse return error.MissingCloseSpawn;
    const medium = td.map.profileForSeed(2) orelse return error.MissingMediumSpawn;

    try std.testing.expectEqual(td.map.SpawnBucket.close, close.bucket);
    try std.testing.expectEqual(td.state.Position{ .x = 2, .y = 8 }, close.player_mcv);
    try std.testing.expectEqual(td.state.Position{ .x = 15, .y = 1 }, close.opponent_mcv);
    try std.testing.expectEqual(@as(u16, 218), close.distanceSquared());

    try std.testing.expectEqual(td.map.SpawnBucket.medium, medium.bucket);
    try std.testing.expectEqual(td.state.Position{ .x = 2, .y = 8 }, medium.player_mcv);
    try std.testing.expectEqual(td.state.Position{ .x = 37, .y = 23 }, medium.opponent_mcv);
    try std.testing.expectEqual(@as(u16, 1450), medium.distanceSquared());
}

test "every spawn profile is on-map, passable, distinct, and resettable" {
    for (1..td.map.spawn_profile_count + 1) |seed| {
        const profile = td.map.profileForSeed(seed) orelse return error.MissingSpawnProfile;
        try std.testing.expect(td.map.at(profile.player_mcv) != null);
        try std.testing.expect(td.map.at(profile.opponent_mcv) != null);
        try std.testing.expect(td.map.footPassable(profile.player_mcv));
        try std.testing.expect(td.map.footPassable(profile.opponent_mcv));
        try std.testing.expect(!std.meta.eql(profile.player_mcv, profile.opponent_mcv));

        const world = td.World.reset(seed);
        try std.testing.expectEqual(td.state.Failure.none, world.failure);
        try std.testing.expectEqual(profile.bucket, world.spawn_bucket);
        try std.testing.expectEqual(profile.player_mcv, world.units[0].position);
        try std.testing.expectEqual(profile.opponent_mcv, world.units[1].position);
    }
}

test "balanced seed assignment is exactly half close and half medium" {
    for ([_]u64{ 1, 2, 73 }) |base_seed| {
        var close_count: usize = 0;
        var medium_count: usize = 0;
        for (0..64) |ordinal| {
            const seed = td.map.balancedSeed(base_seed, ordinal);
            const profile = td.map.profileForSeed(seed) orelse return error.MissingSpawnProfile;
            switch (profile.bucket) {
                .close => close_count += 1,
                .medium => medium_count += 1,
            }
        }
        try std.testing.expectEqual(@as(usize, 32), close_count);
        try std.testing.expectEqual(@as(usize, 32), medium_count);
    }
}

test "same spawn seed and action stream produce identical states and terminal" {
    for (1..td.map.spawn_profile_count + 1) |seed| {
        var first = td.World.reset(seed);
        var second = td.World.reset(seed);
        var reached_terminal = false;

        for (0..td.batch.training_max_decisions) |decision| {
            const action = if (decision == 0)
                td.Action{ .command = .deploy, .actor = 0 }
            else
                td.Action{};
            _ = td.step.stepWithEasyAI(&first, action);
            _ = td.step.stepWithEasyAI(&second, action);
            try std.testing.expectEqualSlices(
                u8,
                &td.digest.canonical(&first),
                &td.digest.canonical(&second),
            );
            try std.testing.expectEqual(td.step.isTerminal(&first), td.step.isTerminal(&second));
            if (td.step.isTerminal(&first)) {
                reached_terminal = true;
                try std.testing.expectEqual(first.players[0].defeated, second.players[0].defeated);
                try std.testing.expectEqual(first.players[1].defeated, second.players[1].defeated);
                break;
            }
        }
        try std.testing.expect(reached_terminal);
    }
}
