const std = @import("std");
const Io = std.Io;

const Manifest = struct {
    schema_version: u32,
    ruleset_id: []const u8,
    decision_frames: u8,
    ticks_per_second: u8,
    players: u8,
    initial_credits: i32,
    starting_credits: StartingCredits,
    starting_force: StartingForce,
    production_steps: u8,
    ai: AI,
    difficulty_handicaps: []const DifficultyHandicap,
    economy: Economy,
    map: Map,
    capacities: Capacities,
    objects: []const Object,
    weapons: []const Weapon,

    const StartingCredits = struct {
        constrained: i32,
        constrained_percent: u8,
        random_min: i32,
        random_max: i32,
        step: i32,
    };

    const StartingForce = struct {
        percent: u8,
        unit_count: u8,
        e1_count: u8,
        e3_count: u8,
    };

    const AI = struct {
        attack_delay: u8,
    };

    const FixedRatio = struct {
        numerator: u32,
        denominator: u32,
    };

    const DifficultyHandicap = struct {
        id: u8,
        key: []const u8,
        firepower_bias: FixedRatio,
        groundspeed_bias: FixedRatio,
        airspeed_bias: FixedRatio,
        armor_bias: FixedRatio,
        rof_bias: FixedRatio,
        cost_bias: FixedRatio,
        build_speed_bias: FixedRatio,
        repair_delay: FixedRatio,
        build_delay: FixedRatio,
        build_slowdown: bool,
        wall_destroyer: bool,
        content_scan: bool,
    };

    const Map = struct {
        maximum_width: u8,
        maximum_height: u8,
        scenario_id: u8,
        spawn_profiles: []const SpawnProfile,

        const SpawnProfile = struct {
            id: u8,
            bucket: []const u8,
            player_waypoint: u8,
            opponent_waypoint: u8,
            player_x: u8,
            player_y: u8,
            opponent_x: u8,
            opponent_y: u8,
        };
    };

    const Capacities = struct {
        units: u16,
        buildings: u16,
        infantry: u16,
        projectiles: u16,
        queues_per_player: u8,
    };

    const Economy = struct {
        harvester_capacity_steps: u8,
        harvest_interval_frames: u8,
        player_tiberium_step_credits: u16,
        ai_tiberium_step_credits: u16,
        refinery_capacity: i32,
    };

    const Object = struct {
        id: u8,
        key: []const u8,
        category: []const u8,
        source_symbol: []const u8,
        armor: []const u8,
        cost: i32,
        strength: i16,
        sight: u8,
        max_speed: u8,
        power: i16,
        drain: i16,
        footprint_width: u8,
        footprint_height: u8,
        construction_frames: u8,
        ai_construction_frames: u8,
        prerequisite: []const u8,
        // Stock `ROT` (rate of turn, in 1/256 facing units per tick) and the stock "is it
        // equipped with a combat turret?" flag. Both default off because they currently model
        // vehicle rotation only: buildings genuinely do not rotate, and infantry facing is
        // driven by the separate infantry animation path rather than this field. Note MCV and
        // Harvester really do carry ROT 5 in Vanilla despite having no turret, so `rot` and
        // `has_turret` must stay independent.
        rot: u8 = 0,
        has_turret: bool = false,
    };

    const Weapon = struct {
        key: []const u8,
        source_symbol: []const u8,
        owner: []const u8,
        damage: i16,
        reload_frames: u16,
        range_leptons: u16,
        projectile_id: u8,
        projectile_source_symbol: []const u8,
        warhead_source_symbol: []const u8,
        fire_launch: u8,
        prone_launch: u8,
        projectile_speed: u8,
        arming_frames: u8,
        turn_rate: u8,
        armor_none_modifier: u16,
        armor_wood_modifier: u16,
        armor_aluminum_modifier: u16,
        armor_steel_modifier: u16,
        armor_concrete_modifier: u16,
        spread_factor: u8,
    };
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const bytes = try Io.Dir.cwd().readFileAlloc(io, "rules/td_micro_v1.json", gpa, .limited(1024 * 1024));
    defer gpa.free(bytes);
    const parsed = try std.json.parseFromSlice(Manifest, gpa, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try validate(parsed.value);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);

    try writeZig(io, parsed.value, digest, &digest_hex);
    try writeHeader(io, parsed.value, &digest_hex);
}

fn validate(manifest: Manifest) !void {
    if (manifest.schema_version != 13) return error.UnsupportedSchema;
    if (manifest.players != 2) return error.UnsupportedPlayerCount;
    const starting = manifest.starting_credits;
    if (starting.constrained < 0 or
        starting.constrained_percent > 100 or
        starting.random_min < 0 or
        starting.random_max < starting.random_min or
        starting.random_max > manifest.initial_credits or
        starting.step <= 0 or
        @mod(starting.constrained, starting.step) != 0 or
        @mod(starting.random_min, starting.step) != 0 or
        @mod(starting.random_max - starting.random_min, starting.step) != 0)
    {
        return error.InvalidStartingCredits;
    }
    const starting_force = manifest.starting_force;
    if (starting_force.percent > 100 or
        starting_force.unit_count == 0 or
        starting_force.e1_count + starting_force.e3_count != starting_force.unit_count)
    {
        return error.InvalidStartingForce;
    }
    if (manifest.ai.attack_delay == 0) return error.InvalidAIAttackDelay;
    if (manifest.difficulty_handicaps.len != 3) return error.UnsupportedDifficultyCount;
    const difficulty_keys = [_][]const u8{ "easy", "normal", "hard" };
    for (manifest.difficulty_handicaps, 0..) |difficulty, expected_id| {
        if (difficulty.id != expected_id or
            !std.mem.eql(u8, difficulty.key, difficulty_keys[expected_id]))
        {
            return error.InvalidDifficultyOrder;
        }
        inline for (.{
            difficulty.firepower_bias,
            difficulty.groundspeed_bias,
            difficulty.airspeed_bias,
            difficulty.armor_bias,
            difficulty.rof_bias,
            difficulty.cost_bias,
            difficulty.build_speed_bias,
            difficulty.repair_delay,
            difficulty.build_delay,
        }) |ratio| {
            if (ratio.denominator == 0 or ratio.numerator > ratio.denominator * 2) {
                return error.InvalidDifficultyRatio;
            }
        }
    }
    if (manifest.capacities.queues_per_player != 3) return error.UnsupportedQueueCount;
    if (manifest.capacities.units < 4) return error.InsufficientUnitCapacity;
    if (manifest.economy.harvester_capacity_steps == 0 or
        manifest.economy.harvest_interval_frames == 0 or
        manifest.economy.player_tiberium_step_credits == 0 or
        manifest.economy.ai_tiberium_step_credits == 0 or
        manifest.economy.refinery_capacity <= 0)
    {
        return error.InvalidEconomy;
    }
    if (manifest.map.spawn_profiles.len != 2) return error.UnsupportedSpawnProfileCount;
    for (manifest.map.spawn_profiles, 0..) |profile, expected_id| {
        if (profile.id != expected_id) return error.NonContiguousSpawnProfileIds;
        if (!std.mem.eql(u8, profile.bucket, "close") and
            !std.mem.eql(u8, profile.bucket, "medium")) return error.InvalidSpawnBucket;
        if (profile.player_waypoint == profile.opponent_waypoint) return error.DuplicateSpawnWaypoint;
        if (profile.player_x >= manifest.map.maximum_width or profile.opponent_x >= manifest.map.maximum_width or
            profile.player_y >= manifest.map.maximum_height or profile.opponent_y >= manifest.map.maximum_height)
        {
            return error.SpawnOutsideMap;
        }
    }
    if (manifest.objects.len == 0) return error.EmptyObjectSet;
    for (manifest.objects, 1..) |object, expected_id| {
        if (object.id != expected_id) return error.NonContiguousObjectIds;
        if (!validIdentifier(object.key) or !validIdentifier(object.prerequisite) or !validIdentifier(object.armor)) return error.InvalidIdentifier;
        if (!std.mem.eql(u8, object.category, "unit") and
            !std.mem.eql(u8, object.category, "building") and
            !std.mem.eql(u8, object.category, "infantry")) return error.InvalidCategory;
        if (!std.mem.eql(u8, object.armor, "none") and
            !std.mem.eql(u8, object.armor, "wood") and
            !std.mem.eql(u8, object.armor, "aluminum") and
            !std.mem.eql(u8, object.armor, "steel") and
            !std.mem.eql(u8, object.armor, "concrete")) return error.InvalidArmor;
    }
    if (manifest.weapons.len == 0) return error.EmptyWeaponSet;
    for (manifest.weapons) |weapon| {
        if (!validIdentifier(weapon.key) or !validIdentifier(weapon.owner)) return error.InvalidIdentifier;
        if (weapon.projectile_speed == 0 and weapon.arming_frames != 0) return error.InvalidWeaponTiming;
        // A projectile that does not travel cannot steer. The converse is NOT an error: stock TD
        // has traveling non-homing projectiles (BULLET_APDS is MPH_VERY_FAST with ROT 0), so
        // `projectile_speed != 0` with `turn_rate == 0` is a legitimate configuration.
        if (weapon.projectile_speed == 0 and weapon.turn_rate != 0) return error.InvalidProjectileTurnRate;
    }
}

fn validIdentifier(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

fn writeZig(io: Io, manifest: Manifest, digest: [32]u8, digest_hex: []const u8) !void {
    var file = try Io.Dir.cwd().createFile(io, "generated/td_micro_v1.zig", .{});
    defer file.close(io);
    var buffer: [16 * 1024]u8 = undefined;
    var file_writer: Io.File.Writer = .init(file, io, &buffer);
    const writer = &file_writer.interface;

    try writer.writeAll("// Generated from rules/td_micro_v1.json. Do not edit by hand.\n");
    try writer.print("pub const ruleset_id = \"{s}\";\n", .{manifest.ruleset_id});
    try writer.print("pub const manifest_sha256_hex = \"{s}\";\n", .{digest_hex});
    try writer.writeAll("pub const manifest_sha256 = [_]u8{\n");
    for (digest, 0..) |byte, index| {
        if (index % 8 == 0) try writer.writeAll("    ");
        try writer.print("0x{x:0>2},", .{byte});
        if (index % 8 == 7) try writer.writeByte('\n') else try writer.writeByte(' ');
    }
    try writer.writeAll("};\n\n");
    try writer.print("pub const decision_frames: usize = {d};\n", .{manifest.decision_frames});
    try writer.print("pub const ticks_per_second: u8 = {d};\n", .{manifest.ticks_per_second});
    try writer.print("pub const player_count: usize = {d};\n", .{manifest.players});
    try writer.print("pub const initial_credits: i32 = {d};\n", .{manifest.initial_credits});
    try writer.print("pub const starting_credits_constrained: i32 = {d};\n", .{manifest.starting_credits.constrained});
    try writer.print("pub const starting_credits_constrained_percent: u8 = {d};\n", .{manifest.starting_credits.constrained_percent});
    try writer.print("pub const starting_credits_random_min: i32 = {d};\n", .{manifest.starting_credits.random_min});
    try writer.print("pub const starting_credits_random_max: i32 = {d};\n", .{manifest.starting_credits.random_max});
    try writer.print("pub const starting_credits_step: i32 = {d};\n", .{manifest.starting_credits.step});
    try writer.print("pub const starting_force_percent: u8 = {d};\n", .{manifest.starting_force.percent});
    try writer.print("pub const starting_force_unit_count: u8 = {d};\n", .{manifest.starting_force.unit_count});
    try writer.print("pub const starting_force_e1_count: u8 = {d};\n", .{manifest.starting_force.e1_count});
    try writer.print("pub const starting_force_e3_count: u8 = {d};\n", .{manifest.starting_force.e3_count});
    try writer.print("pub const production_steps: u8 = {d};\n", .{manifest.production_steps});
    try writer.print("pub const attack_delay: u8 = {d};\n", .{manifest.ai.attack_delay});
    try writer.writeAll(
        \\pub const DifficultyHandicap = struct {
        \\    firepower_bias: u32,
        \\    groundspeed_bias: u32,
        \\    airspeed_bias: u32,
        \\    armor_bias: u32,
        \\    rof_bias: u32,
        \\    cost_bias: u32,
        \\    build_speed_bias: u32,
        \\    repair_delay: u32,
        \\    build_delay: u32,
        \\    build_slowdown: bool,
        \\    wall_destroyer: bool,
        \\    content_scan: bool,
        \\};
        \\
        \\pub const difficulty_handicaps = [_]DifficultyHandicap{
        \\
    );
    for (manifest.difficulty_handicaps) |difficulty| {
        try writer.print(
            "    .{{ .firepower_bias = {d}, .groundspeed_bias = {d}, .airspeed_bias = {d}, .armor_bias = {d}, .rof_bias = {d}, .cost_bias = {d}, .build_speed_bias = {d}, .repair_delay = {d}, .build_delay = {d}, .build_slowdown = {}, .wall_destroyer = {}, .content_scan = {} }},\n",
            .{
                fixedRaw(difficulty.firepower_bias),
                fixedRaw(difficulty.groundspeed_bias),
                fixedRaw(difficulty.airspeed_bias),
                fixedRaw(difficulty.armor_bias),
                fixedRaw(difficulty.rof_bias),
                fixedRaw(difficulty.cost_bias),
                fixedRaw(difficulty.build_speed_bias),
                fixedRaw(difficulty.repair_delay),
                fixedRaw(difficulty.build_delay),
                difficulty.build_slowdown,
                difficulty.wall_destroyer,
                difficulty.content_scan,
            },
        );
    }
    try writer.writeAll("};\n");
    try writer.print("pub const harvester_capacity_steps: u8 = {d};\n", .{manifest.economy.harvester_capacity_steps});
    try writer.print("pub const harvest_interval_frames: u8 = {d};\n", .{manifest.economy.harvest_interval_frames});
    try writer.print("pub const player_tiberium_step_credits: u16 = {d};\n", .{manifest.economy.player_tiberium_step_credits});
    try writer.print("pub const ai_tiberium_step_credits: u16 = {d};\n", .{manifest.economy.ai_tiberium_step_credits});
    try writer.print("pub const refinery_capacity: i32 = {d};\n", .{manifest.economy.refinery_capacity});
    try writer.print("pub const map_width: u8 = {d};\n", .{manifest.map.maximum_width});
    try writer.print("pub const map_height: u8 = {d};\n", .{manifest.map.maximum_height});
    try writer.print("pub const scenario_id: u8 = {d};\n", .{manifest.map.scenario_id});
    try writer.writeAll(
        \\pub const SpawnBucket = enum(u8) {
        \\    close,
        \\    medium,
        \\};
        \\
        \\pub const SpawnProfile = struct {
        \\    id: u8,
        \\    bucket: SpawnBucket,
        \\    player_waypoint: u8,
        \\    opponent_waypoint: u8,
        \\    player_x: u8,
        \\    player_y: u8,
        \\    opponent_x: u8,
        \\    opponent_y: u8,
        \\};
        \\
        \\pub const spawn_profiles = [_]SpawnProfile{
        \\
    );
    for (manifest.map.spawn_profiles) |profile| {
        try writer.print("    .{{ .id = {d}, .bucket = .{s}, .player_waypoint = {d}, .opponent_waypoint = {d}, .player_x = {d}, .player_y = {d}, .opponent_x = {d}, .opponent_y = {d} }},\n", .{
            profile.id,
            profile.bucket,
            profile.player_waypoint,
            profile.opponent_waypoint,
            profile.player_x,
            profile.player_y,
            profile.opponent_x,
            profile.opponent_y,
        });
    }
    try writer.writeAll("};\n");
    try writer.print("pub const max_units: usize = {d};\n", .{manifest.capacities.units});
    try writer.print("pub const max_buildings: usize = {d};\n", .{manifest.capacities.buildings});
    try writer.print("pub const max_infantry: usize = {d};\n", .{manifest.capacities.infantry});
    try writer.print("pub const max_projectiles: usize = {d};\n\n", .{manifest.capacities.projectiles});

    try writer.writeAll(
        \\pub const Category = enum(u8) {
        \\    none,
        \\    unit,
        \\    building,
        \\    infantry,
        \\};
        \\
        \\pub const ObjectType = enum(u8) {
        \\    none = 0,
        \\
    );
    for (manifest.objects) |object| try writer.print("    {s} = {d},\n", .{ object.key, object.id });
    try writer.writeAll(
        \\};
        \\
        \\pub const Armor = enum(u8) {
        \\    none,
        \\    wood,
        \\    aluminum,
        \\    steel,
        \\    concrete,
        \\};
        \\
        \\pub const ObjectRule = struct {
        \\    kind: ObjectType,
        \\    category: Category,
        \\    armor: Armor,
        \\    cost: i32,
        \\    strength: i16,
        \\    sight: u8,
        \\    max_speed: u8,
        \\    power: i16,
        \\    drain: i16,
        \\    footprint_width: u8,
        \\    footprint_height: u8,
        \\    construction_frames: u8,
        \\    ai_construction_frames: u8,
        \\    prerequisite: ObjectType,
        \\    rot: u8,
        \\    has_turret: bool,
        \\};
        \\
        \\pub const objects = [_]ObjectRule{
        \\
    );
    for (manifest.objects) |object| {
        try writer.print("    .{{ .kind = .{s}, .category = .{s}, .armor = .{s}, .cost = {d}, .strength = {d}, .sight = {d}, .max_speed = {d}, .power = {d}, .drain = {d}, .footprint_width = {d}, .footprint_height = {d}, .construction_frames = {d}, .ai_construction_frames = {d}, .prerequisite = .{s}, .rot = {d}, .has_turret = {} }},\n", .{
            object.key,
            object.category,
            object.armor,
            object.cost,
            object.strength,
            object.sight,
            object.max_speed,
            object.power,
            object.drain,
            object.footprint_width,
            object.footprint_height,
            object.construction_frames,
            object.ai_construction_frames,
            object.prerequisite,
            object.rot,
            object.has_turret,
        });
    }
    try writer.writeAll(
        \\};
        \\
        \\pub fn object(kind: ObjectType) ?*const ObjectRule {
        \\    if (kind == .none) return null;
        \\    return &objects[@intFromEnum(kind) - 1];
        \\}
        \\
        \\/// Turret rotation rate in facing units per tick, or null when the object has no
        \\/// independently rotating turret. Vanilla's TurretClass::AI rotates the secondary
        \\/// facing at `Class->ROT + 1`, not the raw ROT stat.
        \\pub fn turretRate(kind: ObjectType) ?u8 {
        \\    const rule = object(kind) orelse return null;
        \\    if (!rule.has_turret) return null;
        \\    return rule.rot +| 1;
        \\}
        \\
    );
    try writer.writeAll(
        \\pub const WeaponRule = struct {
        \\    damage: i16,
        \\    reload_frames: u16,
        \\    range_leptons: u16,
        \\    projectile_id: u8,
        \\    fire_launch: u8,
        \\    prone_launch: u8,
        \\    projectile_speed: u8,
        \\    arming_frames: u8,
        \\    turn_rate: u8,
        \\    armor_none_modifier: u16,
        \\    armor_wood_modifier: u16,
        \\    armor_aluminum_modifier: u16,
        \\    armor_steel_modifier: u16,
        \\    armor_concrete_modifier: u16,
        \\    spread_factor: u8,
        \\
        \\    pub fn armorModifier(self: WeaponRule, armor: Armor) u16 {
        \\        return switch (armor) {
        \\            .none => self.armor_none_modifier,
        \\            .wood => self.armor_wood_modifier,
        \\            .aluminum => self.armor_aluminum_modifier,
        \\            .steel => self.armor_steel_modifier,
        \\            .concrete => self.armor_concrete_modifier,
        \\        };
        \\    }
        \\};
        \\
    );
    for (manifest.weapons) |weapon| {
        try writer.print("\npub const weapon_{s} = WeaponRule{{ .damage = {d}, .reload_frames = {d}, .range_leptons = {d}, .projectile_id = {d}, .fire_launch = {d}, .prone_launch = {d}, .projectile_speed = {d}, .arming_frames = {d}, .turn_rate = {d}, .armor_none_modifier = {d}, .armor_wood_modifier = {d}, .armor_aluminum_modifier = {d}, .armor_steel_modifier = {d}, .armor_concrete_modifier = {d}, .spread_factor = {d} }};\n", .{
            weapon.key,
            weapon.damage,
            weapon.reload_frames,
            weapon.range_leptons,
            weapon.projectile_id,
            weapon.fire_launch,
            weapon.prone_launch,
            weapon.projectile_speed,
            weapon.arming_frames,
            weapon.turn_rate,
            weapon.armor_none_modifier,
            weapon.armor_wood_modifier,
            weapon.armor_aluminum_modifier,
            weapon.armor_steel_modifier,
            weapon.armor_concrete_modifier,
            weapon.spread_factor,
        });
    }
    try writer.flush();
}

fn writeHeader(io: Io, manifest: Manifest, digest_hex: []const u8) !void {
    var file = try Io.Dir.cwd().createFile(io, "generated/td_micro_v1.h", .{});
    defer file.close(io);
    var buffer: [16 * 1024]u8 = undefined;
    var file_writer: Io.File.Writer = .init(file, io, &buffer);
    const writer = &file_writer.interface;

    try writer.writeAll(
        \\/* Generated from rules/td_micro_v1.json. Do not edit by hand. */
        \\#ifndef TD_MICRO_V1_H
        \\#define TD_MICRO_V1_H
        \\#include <stdint.h>
        \\
    );
    try writer.print("#define TD_MICRO_RULESET_ID \"{s}\"\n", .{manifest.ruleset_id});
    try writer.print("#define TD_MICRO_MANIFEST_SHA256 \"{s}\"\n", .{digest_hex});
    try writer.print("#define TD_MICRO_DECISION_FRAMES {d}\n", .{manifest.decision_frames});
    try writer.print("#define TD_MICRO_INITIAL_CREDITS {d}\n", .{manifest.initial_credits});
    try writer.print("#define TD_MICRO_STARTING_CREDITS_CONSTRAINED {d}\n", .{manifest.starting_credits.constrained});
    try writer.print("#define TD_MICRO_STARTING_CREDITS_CONSTRAINED_PERCENT {d}\n", .{manifest.starting_credits.constrained_percent});
    try writer.print("#define TD_MICRO_STARTING_CREDITS_RANDOM_MIN {d}\n", .{manifest.starting_credits.random_min});
    try writer.print("#define TD_MICRO_STARTING_CREDITS_RANDOM_MAX {d}\n", .{manifest.starting_credits.random_max});
    try writer.print("#define TD_MICRO_STARTING_CREDITS_STEP {d}\n", .{manifest.starting_credits.step});
    try writer.print("#define TD_MICRO_STARTING_FORCE_PERCENT {d}\n", .{manifest.starting_force.percent});
    try writer.print("#define TD_MICRO_STARTING_FORCE_UNIT_COUNT {d}\n", .{manifest.starting_force.unit_count});
    try writer.print("#define TD_MICRO_STARTING_FORCE_E1_COUNT {d}\n", .{manifest.starting_force.e1_count});
    try writer.print("#define TD_MICRO_STARTING_FORCE_E3_COUNT {d}\n", .{manifest.starting_force.e3_count});
    try writer.print("#define TD_MICRO_ATTACK_DELAY {d}\n", .{manifest.ai.attack_delay});
    try writer.writeAll(
        \\typedef struct TdMicroFixedRatio {
        \\    uint32_t numerator;
        \\    uint32_t denominator;
        \\} TdMicroFixedRatio;
        \\
        \\typedef struct TdMicroDifficultyHandicap {
        \\    TdMicroFixedRatio firepower_bias;
        \\    TdMicroFixedRatio groundspeed_bias;
        \\    TdMicroFixedRatio airspeed_bias;
        \\    TdMicroFixedRatio armor_bias;
        \\    TdMicroFixedRatio rof_bias;
        \\    TdMicroFixedRatio cost_bias;
        \\    TdMicroFixedRatio build_speed_bias;
        \\    TdMicroFixedRatio repair_delay;
        \\    TdMicroFixedRatio build_delay;
        \\    uint8_t build_slowdown;
        \\    uint8_t wall_destroyer;
        \\    uint8_t content_scan;
        \\} TdMicroDifficultyHandicap;
        \\
        \\#define TD_MICRO_DIFFICULTY_HANDICAP_COUNT 3
        \\static const TdMicroDifficultyHandicap
        \\    TD_MICRO_DIFFICULTY_HANDICAPS[TD_MICRO_DIFFICULTY_HANDICAP_COUNT] = {
        \\
    );
    for (manifest.difficulty_handicaps) |difficulty| {
        try writer.print(
            "    {{{{{d}, {d}}}, {{{d}, {d}}}, {{{d}, {d}}}, {{{d}, {d}}}, {{{d}, {d}}}, {{{d}, {d}}}, {{{d}, {d}}}, {{{d}, {d}}}, {{{d}, {d}}}, {d}, {d}, {d}}},\n",
            .{
                difficulty.firepower_bias.numerator,
                difficulty.firepower_bias.denominator,
                difficulty.groundspeed_bias.numerator,
                difficulty.groundspeed_bias.denominator,
                difficulty.airspeed_bias.numerator,
                difficulty.airspeed_bias.denominator,
                difficulty.armor_bias.numerator,
                difficulty.armor_bias.denominator,
                difficulty.rof_bias.numerator,
                difficulty.rof_bias.denominator,
                difficulty.cost_bias.numerator,
                difficulty.cost_bias.denominator,
                difficulty.build_speed_bias.numerator,
                difficulty.build_speed_bias.denominator,
                difficulty.repair_delay.numerator,
                difficulty.repair_delay.denominator,
                difficulty.build_delay.numerator,
                difficulty.build_delay.denominator,
                @intFromBool(difficulty.build_slowdown),
                @intFromBool(difficulty.wall_destroyer),
                @intFromBool(difficulty.content_scan),
            },
        );
    }
    try writer.writeAll("};\n");
    try writer.print("#define TD_MICRO_HARVESTER_CAPACITY_STEPS {d}\n", .{manifest.economy.harvester_capacity_steps});
    try writer.print("#define TD_MICRO_HARVEST_INTERVAL_FRAMES {d}\n", .{manifest.economy.harvest_interval_frames});
    try writer.print("#define TD_MICRO_PLAYER_TIBERIUM_STEP_CREDITS {d}\n", .{manifest.economy.player_tiberium_step_credits});
    try writer.print("#define TD_MICRO_AI_TIBERIUM_STEP_CREDITS {d}\n", .{manifest.economy.ai_tiberium_step_credits});
    try writer.print("#define TD_MICRO_REFINERY_CAPACITY {d}\n", .{manifest.economy.refinery_capacity});
    try writer.print("#define TD_MICRO_PLAYER_COUNT {d}\n", .{manifest.players});
    try writer.print("#define TD_MICRO_SCENARIO_ID {d}\n", .{manifest.map.scenario_id});
    try writer.print("#define TD_MICRO_MAX_MAP_WIDTH {d}\n", .{manifest.map.maximum_width});
    try writer.print("#define TD_MICRO_MAX_MAP_HEIGHT {d}\n", .{manifest.map.maximum_height});
    try writer.print("#define TD_MICRO_MAX_UNITS {d}\n", .{manifest.capacities.units});
    try writer.print("#define TD_MICRO_MAX_BUILDINGS {d}\n", .{manifest.capacities.buildings});
    try writer.print("#define TD_MICRO_MAX_INFANTRY {d}\n", .{manifest.capacities.infantry});
    try writer.print("#define TD_MICRO_MAX_PROJECTILES {d}\n", .{manifest.capacities.projectiles});
    try writer.print("#define TD_MICRO_SPAWN_PROFILE_COUNT {d}\n\n", .{manifest.map.spawn_profiles.len});
    try writer.writeAll(
        \\typedef enum TdMicroSpawnBucket {
        \\    TD_MICRO_SPAWN_CLOSE = 0,
        \\    TD_MICRO_SPAWN_MEDIUM = 1,
        \\} TdMicroSpawnBucket;
        \\
        \\typedef struct TdMicroSpawnProfile {
        \\    uint8_t id;
        \\    uint8_t bucket;
        \\    uint8_t player_waypoint;
        \\    uint8_t opponent_waypoint;
        \\    uint8_t player_x;
        \\    uint8_t player_y;
        \\    uint8_t opponent_x;
        \\    uint8_t opponent_y;
        \\} TdMicroSpawnProfile;
        \\
        \\static const TdMicroSpawnProfile TD_MICRO_SPAWN_PROFILES[TD_MICRO_SPAWN_PROFILE_COUNT] = {
        \\
    );
    for (manifest.map.spawn_profiles) |profile| {
        try writer.writeAll("    {");
        try writer.print("{d}, TD_MICRO_SPAWN_", .{profile.id});
        try writeUpper(writer, profile.bucket);
        try writer.print(", {d}, {d}, {d}, {d}, {d}, {d}", .{
            profile.player_waypoint,
            profile.opponent_waypoint,
            profile.player_x,
            profile.player_y,
            profile.opponent_x,
            profile.opponent_y,
        });
        try writer.writeAll("},\n");
    }
    try writer.writeAll("};\n\n");
    try writer.writeAll("typedef enum TdMicroObjectType {\n    TD_MICRO_OBJECT_NONE = 0,\n");
    for (manifest.objects) |object| {
        try writer.writeAll("    TD_MICRO_OBJECT_");
        try writeUpper(writer, object.key);
        try writer.print(" = {d},\n", .{object.id});
    }
    try writer.writeAll("} TdMicroObjectType;\n\n#endif\n");
    try writer.flush();
}

fn fixedRaw(ratio: Manifest.FixedRatio) u32 {
    return @intCast((@as(u64, ratio.numerator) << 16) / ratio.denominator);
}

fn writeUpper(writer: anytype, value: []const u8) !void {
    for (value) |byte| try writer.writeByte(std.ascii.toUpper(byte));
}
