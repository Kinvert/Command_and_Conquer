const std = @import("std");
const td = @import("td_micro");

// full_perf: a win only counts fully when the game was actually played out.
//
// Optimising win rate produced a rusher. Optimising economy_win_rate produced a strong economy that
// never built a tank, because armour cost 2000 plus 800 a unit and infantry already won. So the
// criteria go in the objective: win, mine a real amount, and field at least one vehicle. Anything
// else that wins is worth half.

test "full-win criteria default to win + income + one tank that fired" {
    const c: td.batch.RewardConfig = .{};
    try std.testing.expectEqual(@as(f32, 1.0), c.reward_full_win);
    try std.testing.expectEqual(@as(f32, 0.5), c.reward_partial_win);
    try std.testing.expect(c.reward_partial_win < c.reward_full_win);
    try std.testing.expect(c.economy_win_credits > 0);
    try std.testing.expectEqual(@as(u32, 1), c.full_win_min_tanks);
    // Humvees are opt-in: the rock-paper-scissors goal wants them, but requiring them from the
    // start makes an already sparse conjunction sparser.
    try std.testing.expectEqual(@as(u32, 0), c.full_win_min_humvees);
    // A tank must actually have fired: counting tanks built lets a policy park one and collect the
    // full reward without ever fighting.
    try std.testing.expectEqual(@as(u32, 1), c.full_win_min_tank_shots);
    try std.testing.expectEqual(@as(f32, 0), c.reward_first_tank);
    try std.testing.expectEqual(@as(f32, 0), c.reward_first_tank_shot);
    try std.testing.expectEqual(@as(f32, -1), c.reward_qualified_loss);
    try std.testing.expect(c.valid());
}

test "every criterion is necessary for a full win" {
    const c: td.batch.RewardConfig = .{};
    const t = c.economy_win_credits;
    // income, tank, and a shot fired
    try std.testing.expect(td.batch.isFullWin(c, t, 1, 0, 1));
    // income short
    try std.testing.expect(!td.batch.isFullWin(c, t - 1, 1, 0, 1));
    // no tank
    try std.testing.expect(!td.batch.isFullWin(c, t, 0, 0, 1));
    // tank built but never fired -- the parked-tank case
    try std.testing.expect(!td.batch.isFullWin(c, t, 1, 0, 0));
    // nothing
    try std.testing.expect(!td.batch.isFullWin(c, 0, 0, 0, 0));
    // more of everything still qualifies
    try std.testing.expect(td.batch.isFullWin(c, t * 3, 4, 2, 9));
}

test "the humvee requirement binds when enabled" {
    var c: td.batch.RewardConfig = .{};
    c.full_win_min_humvees = 1;
    const t = c.economy_win_credits;
    try std.testing.expect(!td.batch.isFullWin(c, t, 1, 0, 1));
    try std.testing.expect(td.batch.isFullWin(c, t, 1, 1, 1));
}

test "a partial win must be worth less than a full one" {
    var c: td.batch.RewardConfig = .{};
    c.reward_partial_win = 1.5;
    try std.testing.expect(!c.valid());
}

test "qualified loss reward is bounded to a non-positive penalty" {
    var c: td.batch.RewardConfig = .{};
    c.reward_qualified_loss = -0.5;
    try std.testing.expect(c.valid());
    c.reward_qualified_loss = 0.001;
    try std.testing.expect(!c.valid());
    c.reward_qualified_loss = -1.001;
    try std.testing.expect(!c.valid());
}
