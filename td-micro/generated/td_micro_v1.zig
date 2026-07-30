// Generated from rules/td_micro_v1.json. Do not edit by hand.
pub const ruleset_id = "td_micro_v1";
pub const manifest_sha256_hex = "f9cf1827cb80c3fe29ebddffa11453a4d9bcf42929005fb45573a3bb612b367b";
pub const manifest_sha256 = [_]u8{
    0xf9, 0xcf, 0x18, 0x27, 0xcb, 0x80, 0xc3, 0xfe,
    0x29, 0xeb, 0xdd, 0xff, 0xa1, 0x14, 0x53, 0xa4,
    0xd9, 0xbc, 0xf4, 0x29, 0x29, 0x00, 0x5f, 0xb4,
    0x55, 0x73, 0xa3, 0xbb, 0x61, 0x2b, 0x36, 0x7b,
};

pub const decision_frames: usize = 4;
pub const ticks_per_second: u8 = 15;
pub const player_count: usize = 2;
pub const initial_credits: i32 = 10000;
pub const starting_credits_constrained: i32 = 2300;
pub const starting_credits_constrained_percent: u8 = 35;
pub const starting_credits_random_min: i32 = 2400;
pub const starting_credits_random_max: i32 = 10000;
pub const starting_credits_step: i32 = 100;
pub const starting_force_percent: u8 = 50;
pub const starting_force_unit_count: u8 = 6;
pub const starting_force_e1_count: u8 = 3;
pub const starting_force_e3_count: u8 = 3;
pub const production_steps: u8 = 108;
pub const attack_delay: u8 = 1;
pub const DifficultyHandicap = struct {
    firepower_bias: u32,
    groundspeed_bias: u32,
    airspeed_bias: u32,
    armor_bias: u32,
    rof_bias: u32,
    cost_bias: u32,
    build_speed_bias: u32,
    repair_delay: u32,
    build_delay: u32,
    build_slowdown: bool,
    wall_destroyer: bool,
    content_scan: bool,
};

pub const difficulty_handicaps = [_]DifficultyHandicap{
    .{ .firepower_bias = 72089, .groundspeed_bias = 72089, .airspeed_bias = 72089, .armor_bias = 65536, .rof_bias = 52428, .cost_bias = 52428, .build_speed_bias = 39321, .repair_delay = 65, .build_delay = 131, .build_slowdown = false, .wall_destroyer = true, .content_scan = true },
    .{ .firepower_bias = 65536, .groundspeed_bias = 65536, .airspeed_bias = 65536, .armor_bias = 65536, .rof_bias = 65536, .cost_bias = 65536, .build_speed_bias = 65536, .repair_delay = 1310, .build_delay = 1966, .build_slowdown = true, .wall_destroyer = true, .content_scan = true },
    .{ .firepower_bias = 58982, .groundspeed_bias = 58982, .airspeed_bias = 58982, .armor_bias = 68812, .rof_bias = 68812, .cost_bias = 65536, .build_speed_bias = 65536, .repair_delay = 3276, .build_delay = 6553, .build_slowdown = true, .wall_destroyer = true, .content_scan = true },
};
pub const harvester_capacity_steps: u8 = 28;
pub const harvest_interval_frames: u8 = 15;
pub const player_tiberium_step_credits: u16 = 25;
pub const ai_tiberium_step_credits: u16 = 33;
pub const refinery_capacity: i32 = 1000;
pub const map_width: u8 = 64;
pub const map_height: u8 = 64;
pub const scenario_id: u8 = 1;
pub const SpawnBucket = enum(u8) {
    close,
    medium,
};

pub const SpawnProfile = struct {
    id: u8,
    bucket: SpawnBucket,
    player_waypoint: u8,
    opponent_waypoint: u8,
    player_x: u8,
    player_y: u8,
    opponent_x: u8,
    opponent_y: u8,
};

pub const spawn_profiles = [_]SpawnProfile{
    .{ .id = 0, .bucket = .close, .player_waypoint = 0, .opponent_waypoint = 1, .player_x = 2, .player_y = 8, .opponent_x = 15, .opponent_y = 1 },
    .{ .id = 1, .bucket = .medium, .player_waypoint = 0, .opponent_waypoint = 3, .player_x = 2, .player_y = 8, .opponent_x = 37, .opponent_y = 23 },
};
pub const max_units: usize = 16;
pub const max_buildings: usize = 64;
pub const max_infantry: usize = 128;
pub const max_projectiles: usize = 256;

pub const Category = enum(u8) {
    none,
    unit,
    building,
    infantry,
};

pub const ObjectType = enum(u8) {
    none = 0,
    mcv = 1,
    construction_yard = 2,
    power_plant = 3,
    barracks = 4,
    e1 = 5,
    e3 = 6,
    refinery = 7,
    harvester = 8,
    weapons_factory = 9,
    medium_tank = 10,
    humvee = 11,
};

pub const Armor = enum(u8) {
    none,
    wood,
    aluminum,
    steel,
    concrete,
};

pub const ObjectRule = struct {
    kind: ObjectType,
    category: Category,
    armor: Armor,
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
    prerequisite: ObjectType,
    rot: u8,
    has_turret: bool,
};

pub const objects = [_]ObjectRule{
    .{ .kind = .mcv, .category = .unit, .armor = .aluminum, .cost = 5000, .strength = 600, .sight = 2, .max_speed = 0, .power = 0, .drain = 0, .footprint_width = 1, .footprint_height = 1, .construction_frames = 0, .ai_construction_frames = 0, .prerequisite = .none, .rot = 5, .has_turret = false },
    .{ .kind = .construction_yard, .category = .building, .armor = .wood, .cost = 5000, .strength = 800, .sight = 3, .max_speed = 0, .power = 30, .drain = 15, .footprint_width = 3, .footprint_height = 2, .construction_frames = 64, .ai_construction_frames = 60, .prerequisite = .none, .rot = 0, .has_turret = false },
    .{ .kind = .power_plant, .category = .building, .armor = .wood, .cost = 300, .strength = 400, .sight = 2, .max_speed = 0, .power = 100, .drain = 0, .footprint_width = 2, .footprint_height = 2, .construction_frames = 60, .ai_construction_frames = 58, .prerequisite = .none, .rot = 0, .has_turret = false },
    .{ .kind = .barracks, .category = .building, .armor = .wood, .cost = 300, .strength = 800, .sight = 3, .max_speed = 0, .power = 0, .drain = 20, .footprint_width = 2, .footprint_height = 2, .construction_frames = 60, .ai_construction_frames = 58, .prerequisite = .power_plant, .rot = 0, .has_turret = false },
    .{ .kind = .e1, .category = .infantry, .armor = .none, .cost = 100, .strength = 50, .sight = 1, .max_speed = 8, .power = 0, .drain = 0, .footprint_width = 1, .footprint_height = 1, .construction_frames = 0, .ai_construction_frames = 0, .prerequisite = .barracks, .rot = 0, .has_turret = false },
    .{ .kind = .e3, .category = .infantry, .armor = .none, .cost = 300, .strength = 25, .sight = 2, .max_speed = 6, .power = 0, .drain = 0, .footprint_width = 1, .footprint_height = 1, .construction_frames = 0, .ai_construction_frames = 0, .prerequisite = .barracks, .rot = 0, .has_turret = false },
    .{ .kind = .refinery, .category = .building, .armor = .wood, .cost = 2000, .strength = 900, .sight = 4, .max_speed = 0, .power = 10, .drain = 40, .footprint_width = 3, .footprint_height = 3, .construction_frames = 58, .ai_construction_frames = 58, .prerequisite = .power_plant, .rot = 0, .has_turret = false },
    .{ .kind = .harvester, .category = .unit, .armor = .aluminum, .cost = 1400, .strength = 600, .sight = 2, .max_speed = 12, .power = 0, .drain = 0, .footprint_width = 1, .footprint_height = 1, .construction_frames = 0, .ai_construction_frames = 0, .prerequisite = .refinery, .rot = 5, .has_turret = false },
    .{ .kind = .weapons_factory, .category = .building, .armor = .aluminum, .cost = 2000, .strength = 200, .sight = 3, .max_speed = 0, .power = 0, .drain = 30, .footprint_width = 3, .footprint_height = 3, .construction_frames = 58, .ai_construction_frames = 58, .prerequisite = .refinery, .rot = 0, .has_turret = false },
    .{ .kind = .medium_tank, .category = .unit, .armor = .steel, .cost = 800, .strength = 400, .sight = 3, .max_speed = 18, .power = 0, .drain = 0, .footprint_width = 1, .footprint_height = 1, .construction_frames = 0, .ai_construction_frames = 0, .prerequisite = .weapons_factory, .rot = 5, .has_turret = true },
    .{ .kind = .humvee, .category = .unit, .armor = .aluminum, .cost = 400, .strength = 150, .sight = 2, .max_speed = 30, .power = 0, .drain = 0, .footprint_width = 1, .footprint_height = 1, .construction_frames = 0, .ai_construction_frames = 0, .prerequisite = .weapons_factory, .rot = 10, .has_turret = true },
};

pub fn object(kind: ObjectType) ?*const ObjectRule {
    if (kind == .none) return null;
    return &objects[@intFromEnum(kind) - 1];
}

/// Turret rotation rate in facing units per tick, or null when the object has no
/// independently rotating turret. Vanilla's TurretClass::AI rotates the secondary
/// facing at `Class->ROT + 1`, not the raw ROT stat.
pub fn turretRate(kind: ObjectType) ?u8 {
    const rule = object(kind) orelse return null;
    if (!rule.has_turret) return null;
    return rule.rot +| 1;
}
pub const WeaponRule = struct {
    damage: i16,
    reload_frames: u16,
    range_leptons: u16,
    projectile_id: u8,
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

    pub fn armorModifier(self: WeaponRule, armor: Armor) u16 {
        return switch (armor) {
            .none => self.armor_none_modifier,
            .wood => self.armor_wood_modifier,
            .aluminum => self.armor_aluminum_modifier,
            .steel => self.armor_steel_modifier,
            .concrete => self.armor_concrete_modifier,
        };
    }
};

pub const weapon_m16 = WeaponRule{ .damage = 15, .reload_frames = 20, .range_leptons = 512, .projectile_id = 1, .fire_launch = 2, .prone_launch = 2, .projectile_speed = 0, .arming_frames = 0, .turn_rate = 0, .armor_none_modifier = 256, .armor_wood_modifier = 128, .armor_aluminum_modifier = 144, .armor_steel_modifier = 64, .armor_concrete_modifier = 64, .spread_factor = 2 };

pub const weapon_dragon = WeaponRule{ .damage = 30, .reload_frames = 60, .range_leptons = 1024, .projectile_id = 7, .fire_launch = 3, .prone_launch = 3, .projectile_speed = 60, .arming_frames = 3, .turn_rate = 5, .armor_none_modifier = 64, .armor_wood_modifier = 192, .armor_aluminum_modifier = 192, .armor_steel_modifier = 256, .armor_concrete_modifier = 128, .spread_factor = 6 };

pub const weapon_105mm = WeaponRule{ .damage = 30, .reload_frames = 50, .range_leptons = 1216, .projectile_id = 2, .fire_launch = 0, .prone_launch = 0, .projectile_speed = 100, .arming_frames = 0, .turn_rate = 0, .armor_none_modifier = 64, .armor_wood_modifier = 192, .armor_aluminum_modifier = 192, .armor_steel_modifier = 256, .armor_concrete_modifier = 128, .spread_factor = 6 };

pub const weapon_m60mg = WeaponRule{ .damage = 15, .reload_frames = 30, .range_leptons = 1024, .projectile_id = 1, .fire_launch = 0, .prone_launch = 0, .projectile_speed = 0, .arming_frames = 0, .turn_rate = 0, .armor_none_modifier = 256, .armor_wood_modifier = 128, .armor_aluminum_modifier = 144, .armor_steel_modifier = 64, .armor_concrete_modifier = 64, .spread_factor = 2 };
