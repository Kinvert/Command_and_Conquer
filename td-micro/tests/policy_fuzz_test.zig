const std = @import("std");
const td = @import("td_micro");

test "masked policy tuples never cause an implementation failure" {
    for (0..16) |trajectory| {
        var world = td.World.reset(1);
        var random_state: u64 = 0x9e3779b97f4a7c15 +% trajectory;
        for (0..td.batch.training_max_decisions) |decision| {
            var mask: [td.policy.action_mask_size]u8 = undefined;
            td.policy.actionMask(&world, &mask);
            var raw: td.policy.RawAction = .{};
            raw.command = pickCommand(&random_state, &mask);
            const command_kind: td.Command = @enumFromInt(raw.command);
            raw.arg0 = pickArgument(&random_state, &mask, command_kind, 0, td.policy.pad_token);
            raw.arg1 = pickArgument(&random_state, &mask, command_kind, 1, raw.arg0);
            raw.arg2 = pickArgument(&random_state, &mask, command_kind, 2, raw.arg1);
            const command = td.policy.decode(&world, raw).?;
            if (!td.input.apply(&world, .player, command)) return error.MaskExposedInvalidAction;
            _ = td.step.advanceWithEasyAI(&world);
            if (world.failure != .none) {
                std.debug.print(
                    "trajectory={} decision={} frame={} failure={s} action={any} "
                    ++ "free_units={} buildings={} infantry={} projectiles={} fires={}\n",
                    .{
                        trajectory,
                        decision,
                        world.frame,
                        @tagName(world.failure),
                        raw,
                        world.freeUnitSlots(),
                        world.building_count,
                        world.infantry_count,
                        world.projectile_count,
                        world.building_fire_count,
                    },
                );
                return error.ImplementationFailure;
            }
            if (td.step.isTerminal(&world)) world = td.World.reset(1);
        }
    }
}

fn pickCommand(random_state: *u64, mask: *const [td.policy.action_mask_size]u8) u8 {
    var legal_count: usize = 0;
    for (0..td.policy.command_count) |command| {
        legal_count += @intFromBool(td.policy.commandAllowed(mask, @enumFromInt(command)));
    }
    std.debug.assert(legal_count != 0);
    const pick = next(random_state) % legal_count;
    var legal_index: usize = 0;
    for (0..td.policy.command_count) |command| {
        if (!td.policy.commandAllowed(mask, @enumFromInt(command))) continue;
        if (legal_index == pick) return @intCast(command);
        legal_index += 1;
    }
    unreachable;
}

fn pickArgument(
    random_state: *u64,
    mask: *const [td.policy.action_mask_size]u8,
    command: td.Command,
    argument_index: u2,
    prior_token: u8,
) u8 {
    var legal_count: usize = 0;
    for (0..td.policy.token_count) |token| {
        legal_count += @intFromBool(td.policy.argumentAllowed(
            mask,
            command,
            argument_index,
            prior_token,
            @intCast(token),
        ));
    }
    std.debug.assert(legal_count != 0);
    const pick = next(random_state) % legal_count;
    var legal_index: usize = 0;
    for (0..td.policy.token_count) |token| {
        if (!td.policy.argumentAllowed(
            mask,
            command,
            argument_index,
            prior_token,
            @intCast(token),
        )) continue;
        if (legal_index == pick) return @intCast(token);
        legal_index += 1;
    }
    unreachable;
}

fn next(random_state: *u64) usize {
    random_state.* = random_state.* *% 6364136223846793005 +% 1442695040888963407;
    return @truncate(random_state.* >> 32);
}
