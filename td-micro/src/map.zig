const state = @import("state.zig");
const generated = @import("generated_map");
const generated_rules = @import("generated_rules");

pub const scenario_id: u8 = 1;
pub const origin_x = generated.origin_x;
pub const origin_y = generated.origin_y;
pub const width = generated.width;
pub const height = generated.height;
pub const fixture_sha256_hex = generated.fixture_sha256_hex;
pub const fixture_sha256 = generated.fixture_sha256;
pub const Cell = generated.Cell;
pub const cells = generated.cells;
pub const mcv_deploy_frames: u8 = 24;
pub const SpawnBucket = generated_rules.SpawnBucket;
pub const spawn_profile_count = generated_rules.spawn_profiles.len;

pub const SpawnProfile = struct {
    id: u8,
    bucket: SpawnBucket,
    player_mcv: state.Position,
    opponent_mcv: state.Position,

    pub fn distanceSquared(self: SpawnProfile) u16 {
        const dx = @as(i16, self.opponent_mcv.x) - @as(i16, self.player_mcv.x);
        const dy = @as(i16, self.opponent_mcv.y) - @as(i16, self.player_mcv.y);
        return @intCast(dx * dx + dy * dy);
    }
};

pub fn at(position: state.Position) ?Cell {
    return generated.at(position.x, position.y);
}

pub fn footPassable(position: state.Position) bool {
    const cell = at(position) orelse return false;
    return cell.foot_passable;
}

pub fn profileForSeed(seed: anytype) ?SpawnProfile {
    if (seed < 1 or seed > spawn_profile_count) return null;
    const profile = generated_rules.spawn_profiles[@intCast(seed - 1)];
    return .{
        .id = profile.id,
        .bucket = profile.bucket,
        .player_mcv = .{ .x = profile.player_x, .y = profile.player_y },
        .opponent_mcv = .{ .x = profile.opponent_x, .y = profile.opponent_y },
    };
}

pub fn balancedSeed(base_seed: u64, ordinal: usize) u64 {
    const count: u64 = spawn_profile_count;
    const base_index = if (base_seed == 0) 0 else (base_seed - 1) % count;
    return (base_index + @as(u64, @intCast(ordinal)) % count) % count + 1;
}

pub const SeedReset = struct {
    rng_state: u32,
    opponent_attack_timer: u32,
    bucket: SpawnBucket,
    player_mcv: state.Position,
    opponent_mcv: state.Position,
};

pub fn resetForSeed(seed: u32) ?SeedReset {
    const profile = profileForSeed(seed) orelse return null;
    const attack_roll: u32 = switch (seed) {
        1 => 623,
        2 => 1_396,
        else => unreachable,
    };
    return .{
        .rng_state = switch (seed) {
            1 => 3_488_684_595,
            2 => 2_093_743_367,
            else => unreachable,
        },
        .opponent_attack_timer = @as(u32, generated_rules.attack_delay) * attack_roll,
        .bucket = profile.bucket,
        .player_mcv = profile.player_mcv,
        .opponent_mcv = profile.opponent_mcv,
    };
}
