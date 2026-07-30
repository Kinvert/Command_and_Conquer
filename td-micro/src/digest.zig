const std = @import("std");
const rules = @import("rules.zig");
const state = @import("state.zig");

const Sha256 = std.crypto.hash.sha2.Sha256;

pub fn canonical(world: *const state.World) [Sha256.digest_length]u8 {
    var hasher = Sha256.init(.{});
    updateInt(&hasher, world.frame);
    updateInt(&hasher, world.setup_seed);
    updateInt(&hasher, @intFromEnum(world.spawn_bucket));
    updateInt(&hasher, @intFromEnum(world.starting_force));
    updateInt(&hasher, world.rng_state);
    updateInt(&hasher, world.map_origin_x);
    updateInt(&hasher, world.map_origin_y);
    updateInt(&hasher, world.map_width);
    updateInt(&hasher, world.map_height);

    for (world.players) |player| {
        updateInt(&hasher, player.credits);
        updateInt(&hasher, player.tiberium);
        updateInt(&hasher, player.capacity);
        updateInt(&hasher, player.harvested_credits);
        updateInt(&hasher, player.power);
        updateInt(&hasher, player.drain);
        updateInt(&hasher, @intFromEnum(player.controller));
        updateBool(&hasher, player.defeat_pending);
        updateInt(&hasher, player.defeat_timer);
        updateBool(&hasher, player.defeated);
    }
    updateBool(&hasher, world.easy_ai.active);
    updateInt(&hasher, world.easy_ai.state);
    updateBool(&hasher, world.easy_ai.started);
    updateBool(&hasher, world.easy_ai.alerted);
    updateBool(&hasher, world.easy_ai.base_building);
    updateBool(&hasher, world.easy_ai.tiberium_short);
    if (world.easy_ai.difficulty_active) updateBool(&hasher, true);
    updateInt(&hasher, world.easy_ai.difficulty);
    updateInt(&hasher, @intFromEnum(world.easy_ai.enemy));
    updateInt(&hasher, world.easy_ai.ai_timer);
    updateInt(&hasher, world.easy_ai.alert_timer);
    updateInt(&hasher, world.easy_ai.attack_timer);
    updateInt(&hasher, @intFromEnum(world.easy_ai.build_structure));
    updateInt(&hasher, @intFromEnum(world.easy_ai.build_infantry));
    updateBool(&hasher, world.easy_ai.has_center);
    updateInt(&hasher, world.easy_ai.center_x);
    updateInt(&hasher, world.easy_ai.center_y);
    updateInt(&hasher, world.easy_ai.radius);
    updateInt(&hasher, world.easy_ai.max_units);
    updateInt(&hasher, world.easy_ai.max_buildings);
    updateInt(&hasher, world.easy_ai.max_infantry);
    for (world.units) |unit| {
        if (unit.kind == .none) continue;
        updateBool(&hasher, unit.active);
        updateInt(&hasher, @intFromEnum(unit.kind));
        updateInt(&hasher, @intFromEnum(unit.owner));
        updateInt(&hasher, unit.position.x);
        updateInt(&hasher, unit.position.y);
        updateInt(&hasher, unit.destination.x);
        updateInt(&hasher, unit.destination.y);
        updateInt(&hasher, unit.archive_destination.x);
        updateInt(&hasher, unit.archive_destination.y);
        updateInt(&hasher, unit.health);
        updateInt(&hasher, unit.coord_x);
        updateInt(&hasher, unit.coord_y);
        updateInt(&hasher, unit.facing);
        updateInt(&hasher, unit.mission);
        updateInt(&hasher, unit.mission_timer_due);
        updateInt(&hasher, unit.status);
        updateInt(&hasher, unit.path_facing);
        for (unit.path) |path_facing| updateInt(&hasher, path_facing);
        updateInt(&hasher, unit.home_refinery);
        updateInt(&hasher, unit.head_coord_x);
        updateInt(&hasher, unit.head_coord_y);
        updateInt(&hasher, unit.movement_accum);
        updateInt(&hasher, unit.track_number);
        updateInt(&hasher, unit.track_index);
        updateInt(&hasher, unit.path_delay);
        updateInt(&hasher, unit.speed);
        updateInt(&hasher, unit.docking_phase);
        updateInt(&hasher, unit.docking_timer);
        updateInt(&hasher, unit.cargo_steps);
        updateInt(&hasher, unit.harvest_timer);
        updateInt(&hasher, unit.deploy_frames);
        updateBool(&hasher, unit.destination_valid);
        updateBool(&hasher, unit.archive_destination_valid);
        updateBool(&hasher, unit.logic_after_infantry);
        updateBool(&hasher, unit.moving);
        updateBool(&hasher, unit.harvesting);
        updateBool(&hasher, unit.deploying);
        // CNC26 vehicle combat state is hashed only for units that can actually carry it. No
        // turretless unit ever mutates these fields, so gating the hash this way keeps every
        // digest recorded before the vehicle expansion byte-identical while still making the new
        // state fully determinism-checked wherever it exists.
        if (rules.turretRate(unit.kind) != null) {
            updateInt(&hasher, @intFromEnum(unit.target.kind));
            updateInt(&hasher, @intFromEnum(unit.target.owner));
            updateInt(&hasher, unit.target.index);
            updateInt(&hasher, unit.turret_facing);
            updateInt(&hasher, unit.weapon_cooldown);
            updateBool(&hasher, unit.firing);
        }
    }
    for (world.buildings) |building| {
        updateBool(&hasher, building.active);
        updateInt(&hasher, @intFromEnum(building.kind));
        updateInt(&hasher, @intFromEnum(building.owner));
        updateInt(&hasher, building.position.x);
        updateInt(&hasher, building.position.y);
        updateInt(&hasher, building.health);
        updateInt(&hasher, building.construction_frames);
        updateBool(&hasher, building.operational);
        updateBool(&hasher, building.grand_opened);
    }
    for (world.infantry) |infantry| {
        updateBool(&hasher, infantry.active);
        updateInt(&hasher, @intFromEnum(infantry.kind));
        updateInt(&hasher, @intFromEnum(infantry.owner));
        updateInt(&hasher, infantry.position.x);
        updateInt(&hasher, infantry.position.y);
        updateInt(&hasher, infantry.home.x);
        updateInt(&hasher, infantry.home.y);
        updateInt(&hasher, infantry.health);
        updateInt(&hasher, infantry.coord_x);
        updateInt(&hasher, infantry.coord_y);
        updateInt(&hasher, infantry.head_coord_x);
        updateInt(&hasher, infantry.head_coord_y);
        updateInt(&hasher, infantry.facing);
        updateInt(&hasher, infantry.mission);
        updateInt(&hasher, infantry.queued_mission);
        updateInt(&hasher, infantry.mission_timer_due);
        updateInt(&hasher, infantry.speed);
        updateInt(&hasher, infantry.path_facing);
        for (infantry.path) |path_facing| updateInt(&hasher, path_facing);
        updateInt(&hasher, infantry.path_delay);
        updateInt(&hasher, @intFromEnum(infantry.target.kind));
        updateInt(&hasher, @intFromEnum(infantry.target.owner));
        updateInt(&hasher, infantry.target.index);
        updateInt(&hasher, infantry.weapon_cooldown);
        updateInt(&hasher, infantry.animation);
        updateInt(&hasher, infantry.animation_stage);
        updateInt(&hasher, infantry.animation_timer);
        updateInt(&hasher, infantry.animation_rate);
        updateInt(&hasher, infantry.fear);
        updateInt(&hasher, infantry.ammo);
        updateInt(&hasher, infantry.kills);
        updateInt(&hasher, infantry.command_delay);
        updateInt(&hasher, infantry.mission_delay);
        updateInt(&hasher, infantry.attack_delay);
        updateInt(&hasher, infantry.arrival_mission_delay);
        updateInt(&hasher, infantry.arrival_mission);
        updateBool(&hasher, infantry.tethered);
        updateBool(&hasher, infantry.home_valid);
        updateBool(&hasher, infantry.destination_valid);
        updateBool(&hasher, infantry.new_destination);
        updateInt(&hasher, infantry.destination.x);
        updateInt(&hasher, infantry.destination.y);
        updateBool(&hasher, infantry.pending_move);
        updateBool(&hasher, infantry.attack_pending);
        updateBool(&hasher, infantry.moving);
        updateBool(&hasher, infantry.firing);
        updateBool(&hasher, infantry.prone);
        updateBool(&hasher, infantry.second_shot);
    }
    for (world.projectiles) |projectile| {
        updateBool(&hasher, projectile.active);
        updateInt(&hasher, projectile.id);
        updateInt(&hasher, @intFromEnum(projectile.kind));
        updateInt(&hasher, @intFromEnum(projectile.source.kind));
        updateInt(&hasher, @intFromEnum(projectile.source.owner));
        updateInt(&hasher, projectile.source.index);
        updateInt(&hasher, @intFromEnum(projectile.target.kind));
        updateInt(&hasher, @intFromEnum(projectile.target.owner));
        updateInt(&hasher, projectile.target.index);
        updateInt(&hasher, projectile.coord_x);
        updateInt(&hasher, projectile.coord_y);
        updateInt(&hasher, projectile.fuse_x);
        updateInt(&hasher, projectile.fuse_y);
        updateInt(&hasher, projectile.strength);
        updateInt(&hasher, projectile.facing);
        updateInt(&hasher, projectile.desired_facing);
        updateInt(&hasher, projectile.speed);
        updateInt(&hasher, projectile.speed_accum);
        updateInt(&hasher, projectile.timer);
        updateInt(&hasher, projectile.arming);
        updateInt(&hasher, projectile.proximity);
    }
    for (world.projectile_order) |projectile_index| updateInt(&hasher, projectile_index);
    for (world.building_fires[0..world.building_fire_count]) |effect| {
        updateBool(&hasher, effect.active);
        updateInt(&hasher, @intFromEnum(effect.target.kind));
        updateInt(&hasher, @intFromEnum(effect.target.owner));
        updateInt(&hasher, effect.target.index);
        updateInt(&hasher, effect.delay);
        updateInt(&hasher, effect.stage);
        updateInt(&hasher, effect.loops);
        updateInt(&hasher, effect.accum);
        updateBool(&hasher, effect.brand_new);
    }
    for (world.queues) |owner_queues| {
        for (owner_queues, 0..) |queue, queue_index| {
            // The CNC26 vehicle queue is hashed only once it holds something. It cannot be
            // non-empty without a Weapons Factory, which no pre-expansion world has, so this
            // keeps every previously recorded digest byte-identical while still covering the new
            // queue wherever it is actually used. Same reasoning as the turret fields above.
            if (queue_index == @intFromEnum(state.QueueKind.unit) and
                !queue.active and queue.product == .none) continue;
            updateBool(&hasher, queue.active);
            updateBool(&hasher, queue.completed);
            updateInt(&hasher, @intFromEnum(queue.product));
            updateInt(&hasher, queue.stage);
            updateInt(&hasher, queue.stage_timer);
            updateInt(&hasher, queue.rate);
            updateInt(&hasher, queue.balance);
        }
    }
    for (world.tiberium_steps) |steps| updateInt(&hasher, steps);
    for (world.tiberium_present) |present| updateInt(&hasher, present);
    updateInt(&hasher, world.building_count);
    updateInt(&hasher, world.infantry_count);
    updateInt(&hasher, world.projectile_count);
    updateInt(&hasher, world.building_fire_count);
    updateInt(&hasher, @intFromEnum(world.failure));

    var result: [Sha256.digest_length]u8 = undefined;
    hasher.final(&result);
    return result;
}

fn updateBool(hasher: *Sha256, value: bool) void {
    updateInt(hasher, @as(u8, @intFromBool(value)));
}

fn updateInt(hasher: *Sha256, value: anytype) void {
    const T = @TypeOf(value);
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .little);
    hasher.update(&bytes);
}
