const std = @import("std");
const rules = @import("rules.zig");

pub const SpawnBucket = @import("generated_rules").SpawnBucket;

pub const Owner = enum(u8) {
    player = 0,
    opponent = 1,
    none = 255,
};

pub const Controller = enum(u8) {
    policy,
    easy_ai,
};

pub const StartingForce = enum(u8) {
    mcv_only,
    reduced_unit_count_6,
};

pub const Failure = enum(u8) {
    none,
    unsupported_seed,
    unsupported_content,
    capacity_overflow,
};

pub const Position = extern struct {
    x: u8 = 0,
    y: u8 = 0,
};

pub const EntityRef = extern struct {
    kind: rules.ObjectType = .none,
    owner: Owner = .none,
    index: u16 = 0,

    pub fn valid(self: EntityRef) bool {
        return self.kind != .none and self.owner != .none;
    }
};

/// Values are the real Vanilla `BulletType` enum ordinals from tiberiandawn/defines.h, so a
/// weapon rule's `projectile_id` maps straight onto this enum.
pub const ProjectileKind = enum(u8) {
    bullet = 1,
    apds = 2,
    tow = 7,
};

pub const Player = extern struct {
    credits: i32 = 0,
    tiberium: i32 = 0,
    capacity: i32 = 0,
    harvested_credits: u32 = 0,
    power: i16 = 0,
    drain: i16 = 0,
    controller: Controller = .policy,
    defeat_pending: bool = false,
    defeat_timer: u8 = 0,
    defeated: bool = false,
};

pub const Unit = extern struct {
    active: bool = false,
    kind: rules.ObjectType = .none,
    owner: Owner = .player,
    position: Position = .{},
    destination: Position = .{},
    archive_destination: Position = .{},
    health: i16 = 0,
    coord_x: i16 = 0,
    coord_y: i16 = 0,
    facing: u8 = 0,
    mission: i8 = 4,
    mission_timer_due: u32 = 0,
    status: u8 = 0,
    path_facing: i8 = -1,
    path: [9]i8 = [_]i8{-1} ** 9,
    home_refinery: u16 = std.math.maxInt(u16),
    head_coord_x: i16 = 0,
    head_coord_y: i16 = 0,
    movement_accum: u16 = 0,
    track_number: i8 = -1,
    track_index: u8 = 0,
    path_delay: u8 = 0,
    speed: u8 = 0,
    docking_phase: u8 = 0,
    docking_timer: u8 = 0,
    cargo_steps: u8 = 0,
    harvest_timer: u8 = 0,
    deploy_frames: u8 = 0,
    destination_valid: bool = false,
    archive_destination_valid: bool = false,
    logic_after_infantry: bool = false,
    moving: bool = false,
    harvesting: bool = false,
    deploying: bool = false,
    // CNC26 vehicle combat. Appended rather than interleaved so the existing field layout, and
    // therefore every recorded digest and snapshot, is untouched. `turret_facing` mirrors
    // Vanilla's TurretClass::SecondaryFacing and rotates independently of `facing`; it stays 0
    // for turretless units such as the MCV and Harvester.
    target: EntityRef = .{},
    turret_facing: u8 = 0,
    weapon_cooldown: u8 = 0,
    firing: bool = false,
};

pub const Building = extern struct {
    active: bool = false,
    kind: rules.ObjectType = .none,
    owner: Owner = .player,
    position: Position = .{},
    health: i16 = 0,
    construction_frames: u8 = 0,
    operational: bool = false,
    grand_opened: bool = false,
};

pub const Infantry = extern struct {
    active: bool = false,
    kind: rules.ObjectType = .none,
    owner: Owner = .player,
    position: Position = .{},
    destination: Position = .{},
    home: Position = .{},
    health: i16 = 0,
    coord_x: i16 = 0,
    coord_y: i16 = 0,
    head_coord_x: i16 = 0,
    head_coord_y: i16 = 0,
    facing: u8 = 0,
    mission: i8 = 4,
    queued_mission: i8 = -1,
    mission_timer_due: u32 = 0,
    speed: u8 = 0,
    path_facing: i8 = -1,
    path: [9]i8 = [_]i8{-1} ** 9,
    path_delay: u8 = 0,
    target: EntityRef = .{},
    weapon_cooldown: u8 = 0,
    animation: i8 = -1,
    animation_stage: u16 = 0,
    animation_timer: u8 = 0,
    animation_rate: u8 = 0,
    fear: u8 = 0,
    ammo: i16 = 0,
    kills: u16 = 0,
    command_delay: u8 = 0,
    mission_delay: u8 = 0,
    attack_delay: u8 = 0,
    arrival_mission_delay: u8 = 1,
    arrival_mission: i8 = 4,
    tethered: bool = false,
    home_valid: bool = false,
    destination_valid: bool = false,
    new_destination: bool = false,
    pending_move: bool = false,
    attack_pending: bool = false,
    moving: bool = false,
    firing: bool = false,
    prone: bool = false,
    second_shot: bool = false,
};

pub const Projectile = extern struct {
    active: bool = false,
    id: u16 = 0,
    kind: ProjectileKind = .bullet,
    source: EntityRef = .{},
    target: EntityRef = .{},
    coord_x: i32 = 0,
    coord_y: i32 = 0,
    fuse_x: i32 = 0,
    fuse_y: i32 = 0,
    strength: i16 = 0,
    facing: i16 = 0,
    desired_facing: u8 = 0,
    speed: u8 = 0,
    speed_accum: u16 = 0,
    timer: u8 = 0,
    arming: u8 = 0,
    proximity: i16 = 0,
};

pub const BuildingFireEffect = extern struct {
    active: bool = false,
    target: EntityRef = .{},
    delay: u8 = 0,
    stage: u8 = 0,
    loops: u8 = 0,
    accum: u8 = 0,
    brand_new: bool = false,
};

pub const QueueKind = enum(u8) {
    structure,
    infantry,
    /// CNC26. Vehicles built by the Weapons Factory run on their own queue, independent of the
    /// Construction Yard and Barracks queues, exactly as stock TD's separate factories do.
    unit,
};

pub const queue_count = @typeInfo(QueueKind).@"enum".fields.len;

pub const ProductionQueue = extern struct {
    active: bool = false,
    completed: bool = false,
    product: rules.ObjectType = .none,
    stage: u8 = 0,
    stage_timer: u8 = 0,
    rate: u8 = 0,
    balance: i32 = 0,
};

pub const EasyAIState = extern struct {
    active: bool = true,
    state: i8 = 0,
    started: bool = false,
    alerted: bool = false,
    base_building: bool = true,
    tiberium_short: bool = false,
    difficulty_active: bool = false,
    difficulty: u8 = 2,
    enemy: Owner = .none,
    ai_timer: u16 = 0,
    alert_timer: u32 = 0,
    attack_timer: u32 = 3910,
    build_structure: rules.ObjectType = .none,
    build_infantry: rules.ObjectType = .none,
    has_center: bool = false,
    base_dirty: bool = false,
    center_x: i16 = 0,
    center_y: i16 = 0,
    radius: u16 = 0,
    max_units: u16 = 150,
    max_buildings: u16 = 150,
    max_infantry: u16 = 0,
};

pub const World = extern struct {
    frame: u32 = 0,
    setup_seed: u32 = 0,
    spawn_bucket: SpawnBucket = .close,
    starting_force: StartingForce = .mcv_only,
    rng_state: u32 = 0,
    map_origin_x: i16 = 0,
    map_origin_y: i16 = 0,
    map_width: u8 = 0,
    map_height: u8 = 0,
    players: [rules.player_count]Player = [_]Player{.{}} ** rules.player_count,
    easy_ai: EasyAIState = .{},
    units: [rules.max_units]Unit = [_]Unit{.{}} ** rules.max_units,
    buildings: [rules.max_buildings]Building = [_]Building{.{}} ** rules.max_buildings,
    infantry: [rules.max_infantry]Infantry = [_]Infantry{.{}} ** rules.max_infantry,
    projectiles: [rules.max_projectiles]Projectile = [_]Projectile{.{}} ** rules.max_projectiles,
    projectile_order: [rules.max_projectiles]u16 = [_]u16{0} ** rules.max_projectiles,
    building_fires: [rules.max_buildings * 6]BuildingFireEffect = [_]BuildingFireEffect{.{}} ** (rules.max_buildings * 6),
    queues: [rules.player_count][queue_count]ProductionQueue = [_][queue_count]ProductionQueue{[_]ProductionQueue{.{}} ** queue_count} ** rules.player_count,
    tiberium_steps: [64 * 64]u8 = [_]u8{0} ** (64 * 64),
    tiberium_present: [64]u64 = [_]u64{0} ** 64,
    /// Shots fired by player medium tanks this episode; the world resets per episode so this is
    /// already per-episode. Distinguishes a tank that fought from one that was merely bought, which
    /// a build-count criterion cannot. One increment on fire, so no measurable step cost.
    metrics_tank_shots: u32 = 0,
    /// Kills credited to a player medium tank. A tank that fires has reached contact; a tank that
    /// kills has won it. Rewarding the kill rather than the purchase is what keeps a large armour
    /// bounty from paying for a tank rushed out to be deleted by rocket infantry.
    metrics_tank_kills: u32 = 0,
    /// Applied player attack orders split by the actor/target matchups that matter strategically.
    /// These are diagnostics only: they never enter reward calculation.
    metrics_player_e1_attack_orders: u32 = 0,
    metrics_player_e1_infantry_targets: u32 = 0,
    metrics_player_e3_attack_orders: u32 = 0,
    metrics_player_e3_vehicle_targets: u32 = 0,
    metrics_player_tank_attack_orders: u32 = 0,
    metrics_player_tank_e3_targets: u32 = 0,
    metrics_player_tank_losses: u32 = 0,
    metrics_player_tank_losses_to_e3: u32 = 0,
    building_count: u8 = 0,
    infantry_count: u8 = 0,
    projectile_count: u16 = 0,
    building_fire_count: u16 = 0,
    failure: Failure = .none,

    pub fn reset(seed: u64) World {
        const map = @import("map.zig");
        var world: World = .{};
        if (seed > std.math.maxInt(u32)) {
            world.failure = .unsupported_seed;
            return world;
        }
        world.setup_seed = @intCast(seed);
        world.map_origin_x = map.origin_x;
        world.map_origin_y = map.origin_y;
        world.map_width = map.width;
        world.map_height = map.height;
        for (0..map.height) |y| {
            for (0..map.width) |x| {
                const position: Position = .{ .x = @intCast(x), .y = @intCast(y) };
                const cell = map.at(position).?;
                if (cell.land_type == 5) world.setTiberium(position, cell.overlay_data);
            }
        }
        for (&world.players) |*player| player.credits = rules.initial_credits;
        world.players[@intFromEnum(Owner.opponent)].controller = .easy_ai;

        const fixture_reset = map.resetForSeed(world.setup_seed) orelse {
            world.failure = .unsupported_seed;
            return world;
        };
        world.rng_state = fixture_reset.rng_state;
        world.spawn_bucket = fixture_reset.bucket;
        world.easy_ai.attack_timer = fixture_reset.opponent_attack_timer;

        world.units[0] = .{
            .active = true,
            .kind = .mcv,
            .owner = .player,
            .position = fixture_reset.player_mcv,
            .health = rules.object(.mcv).?.strength,
            .coord_x = @as(i16, fixture_reset.player_mcv.x) * 256 + 128,
            .coord_y = @as(i16, fixture_reset.player_mcv.y) * 256 + 128,
        };
        world.units[1] = .{
            .active = true,
            .kind = .mcv,
            .owner = .opponent,
            .position = fixture_reset.opponent_mcv,
            .health = rules.object(.mcv).?.strength,
            .coord_x = @as(i16, fixture_reset.opponent_mcv.x) * 256 + 128,
            .coord_y = @as(i16, fixture_reset.opponent_mcv.y) * 256 + 128,
        };
        return world;
    }

    pub fn hasBuilding(self: *const World, owner: Owner, kind: rules.ObjectType) bool {
        for (self.buildings) |building| {
            if (building.active and building.operational and building.owner == owner and building.kind == kind) return true;
        }
        return false;
    }

    pub fn addBuilding(self: *World, owner: Owner, kind: rules.ObjectType, position: Position) bool {
        if (self.building_count >= rules.max_buildings) {
            self.failure = .capacity_overflow;
            return false;
        }
        const object_rule = rules.object(kind) orelse {
            self.failure = .unsupported_content;
            return false;
        };
        if (object_rule.category != .building) {
            self.failure = .unsupported_content;
            return false;
        }

        const index: usize = self.building_count;
        self.buildings[index] = .{
            .active = true,
            .kind = kind,
            .owner = owner,
            .position = position,
            .health = object_rule.strength,
            .construction_frames = if (self.players[@intFromEnum(owner)].controller == .easy_ai)
                object_rule.ai_construction_frames
            else
                object_rule.construction_frames,
        };
        self.building_count += 1;
        self.markBuildingChanged(owner);
        const player = &self.players[@intFromEnum(owner)];
        player.power += object_rule.power;
        return true;
    }

    pub fn markBuildingChanged(self: *World, owner: Owner) void {
        if (owner == .opponent) self.easy_ai.base_dirty = true;
    }

    pub fn addUnit(self: *World, owner: Owner, kind: rules.ObjectType, position: Position) ?usize {
        const object_rule = rules.object(kind) orelse {
            self.failure = .unsupported_content;
            return null;
        };
        if (object_rule.category != .unit) {
            self.failure = .unsupported_content;
            return null;
        }
        for (&self.units, 0..) |*unit, index| {
            if (unit.kind != .none) continue;
            unit.* = .{
                .active = true,
                .kind = kind,
                .owner = owner,
                .position = position,
                .destination = position,
                .health = object_rule.strength,
                .coord_x = @as(i16, position.x) * 256 + 128,
                .coord_y = @as(i16, position.y) * 256 + 128,
            };
            return index;
        }
        self.failure = .capacity_overflow;
        return null;
    }

    /// addUnit treats a full array as an engine failure, which is right for spawns the caller
    /// cannot postpone. A weapons factory can postpone: Vanilla holds a finished vehicle in the
    /// bay until it has somewhere to go. This returns null without condemning the episode so the
    /// completed vehicle stays queued and rolls out once a slot frees.
    pub fn tryAddUnit(self: *World, owner: Owner, kind: rules.ObjectType, position: Position) ?usize {
        if (self.freeUnitSlots() == 0) return null;
        return self.addUnit(owner, kind, position);
    }

    /// addUnit only reuses a slot once its `kind` is cleared, so a destroyed unit keeps occupying
    /// one. Counting live units instead undercounts the array and lets a caller walk into the
    /// capacity_overflow it was trying to avoid -- this must stay the same test addUnit applies.
    pub fn freeUnitSlots(self: *const World) usize {
        var count: usize = 0;
        for (self.units) |unit| {
            if (unit.kind == .none) count += 1;
        }
        return count;
    }

    pub fn activeUnitCount(self: *const World) usize {
        var count: usize = 0;
        for (self.units) |unit| {
            if (unit.active and unit.health > 0) count += 1;
        }
        return count;
    }

    pub fn tiberiumAt(self: *const World, position: Position) u8 {
        const index = self.tiberiumIndex(position) orelse return 0;
        return self.tiberium_steps[index];
    }

    pub fn hasTiberium(self: *const World, position: Position) bool {
        const index = self.tiberiumIndex(position) orelse return false;
        return self.tiberium_present[index / 64] & (@as(u64, 1) << @intCast(index % 64)) != 0;
    }

    pub fn setTiberium(self: *World, position: Position, steps: u8) void {
        const index = self.tiberiumIndex(position) orelse return;
        self.tiberium_steps[index] = steps;
        self.tiberium_present[index / 64] |= @as(u64, 1) << @intCast(index % 64);
    }

    pub fn clearTiberium(self: *World, position: Position) void {
        const index = self.tiberiumIndex(position) orelse return;
        self.tiberium_steps[index] = 0;
        self.tiberium_present[index / 64] &= ~(@as(u64, 1) << @intCast(index % 64));
    }

    pub fn clearAllTiberium(self: *World) void {
        @memset(&self.tiberium_steps, 0);
        @memset(&self.tiberium_present, 0);
    }

    pub fn reduceTiberium(self: *World, position: Position, levels: u8) u8 {
        if (levels == 0 or !self.hasTiberium(position)) return 0;
        const steps = self.tiberiumAt(position);
        if (steps > levels) {
            self.tiberium_steps[self.tiberiumIndex(position).?] = steps - levels;
            return levels;
        }
        self.clearTiberium(position);
        return steps;
    }

    fn tiberiumIndex(self: *const World, position: Position) ?usize {
        if (position.x >= self.map_width or position.y >= self.map_height) return null;
        return @as(usize, position.y) * 64 + position.x;
    }
};
