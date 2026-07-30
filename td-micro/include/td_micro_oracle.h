#ifndef TD_MICRO_ORACLE_H
#define TD_MICRO_ORACLE_H

#include <stdint.h>

#include "td_micro_v1.h"

#define TD_MICRO_ORACLE_SCHEMA_VERSION 8
#define TD_MICRO_ORACLE_QUEUE_COUNT (TD_MICRO_PLAYER_COUNT * 2)
#define TD_MICRO_ORACLE_MAX_ENTITIES \
    (TD_MICRO_MAX_UNITS + TD_MICRO_MAX_BUILDINGS + TD_MICRO_MAX_INFANTRY)
#define TD_MICRO_ORACLE_MAX_AI_COMMANDS (TD_MICRO_MAX_INFANTRY + 8)
#define TD_MICRO_ORACLE_MAP_SCHEMA_VERSION 1
#define TD_MICRO_ORACLE_MAX_MAP_CELLS (TD_MICRO_MAX_MAP_WIDTH * TD_MICRO_MAX_MAP_HEIGHT)

typedef enum TdMicroCommand {
    TD_MICRO_COMMAND_NOOP = 0,
    TD_MICRO_COMMAND_DEPLOY = 1,
    TD_MICRO_COMMAND_START_BUILD = 2,
    TD_MICRO_COMMAND_PLACE = 3,
    TD_MICRO_COMMAND_TRAIN = 4,
    TD_MICRO_COMMAND_MOVE = 5,
    TD_MICRO_COMMAND_ATTACK = 6,
    TD_MICRO_COMMAND_GUARD = 7,
    TD_MICRO_COMMAND_STOP = 8,
    TD_MICRO_COMMAND_HUNT = 9,
    TD_MICRO_COMMAND_HARVEST = 10,
    TD_MICRO_COMMAND_RETURN_CARGO = 11,
} TdMicroCommand;

typedef enum TdMicroTargetKind {
    TD_MICRO_TARGET_NONE = 0,
    TD_MICRO_TARGET_CELL = 1,
    TD_MICRO_TARGET_OWN_ENTITY = 2,
    TD_MICRO_TARGET_VISIBLE_ENEMY = 3,
} TdMicroTargetKind;

typedef enum TdMicroOracleAICommandKind {
    TD_MICRO_AI_COMMAND_NOOP = TD_MICRO_COMMAND_NOOP,
    TD_MICRO_AI_COMMAND_DEPLOY = TD_MICRO_COMMAND_DEPLOY,
    TD_MICRO_AI_COMMAND_START_BUILD = TD_MICRO_COMMAND_START_BUILD,
    TD_MICRO_AI_COMMAND_PLACE = TD_MICRO_COMMAND_PLACE,
    TD_MICRO_AI_COMMAND_TRAIN = TD_MICRO_COMMAND_TRAIN,
    TD_MICRO_AI_COMMAND_MOVE = TD_MICRO_COMMAND_MOVE,
    TD_MICRO_AI_COMMAND_ATTACK = TD_MICRO_COMMAND_ATTACK,
    TD_MICRO_AI_COMMAND_GUARD = TD_MICRO_COMMAND_GUARD,
    TD_MICRO_AI_COMMAND_STOP = TD_MICRO_COMMAND_STOP,
    TD_MICRO_AI_COMMAND_HUNT = TD_MICRO_COMMAND_HUNT,
    TD_MICRO_AI_COMMAND_HARVEST = TD_MICRO_COMMAND_HARVEST,
    TD_MICRO_AI_COMMAND_RETURN_CARGO = TD_MICRO_COMMAND_RETURN_CARGO,
} TdMicroOracleAICommandKind;

#pragma pack(push, 1)

typedef struct TdMicroAction {
    uint8_t command;
    uint8_t actor;
    uint8_t product;
    uint8_t target_kind;
    uint8_t target_x;
    uint8_t target_y;
    uint8_t target_slot;
} TdMicroAction;

typedef struct TdMicroOraclePlayer {
    int32_t credits;
    int32_t power;
    int32_t drain;
    int32_t tiberium;
    int32_t capacity;
    uint32_t harvested_credits;
    uint8_t logical_id;
    uint8_t house;
    uint8_t act_like;
    uint8_t is_human;
    uint8_t difficulty;
    uint8_t defeated;
} TdMicroOraclePlayer;

typedef struct TdMicroOracleQueue {
    uint8_t owner;
    uint8_t category;
    uint8_t active;
    uint8_t completed;
    uint8_t product;
    uint8_t suspended;
    uint16_t stage;
    uint8_t stage_timer;
    uint8_t rate;
    int32_t balance;
} TdMicroOracleQueue;

typedef struct TdMicroOracleAIState {
    uint8_t active;
    uint8_t owner;
    int8_t state;
    uint8_t started;
    uint8_t alerted;
    uint8_t base_building;
    uint8_t tiberium_short;
    uint8_t difficulty;
    uint8_t enemy;
    uint8_t build_structure;
    uint8_t build_infantry;
    uint8_t unsupported_choice;
    uint8_t has_center;
    int32_t ai_timer;
    int32_t attack_timer;
    int32_t center_x;
    int32_t center_y;
    int32_t radius;
    uint32_t current_units;
    uint32_t current_buildings;
    uint32_t current_infantry;
    uint32_t max_units;
    uint32_t max_buildings;
    uint32_t max_infantry;
    uint16_t construction_yards;
    uint16_t power_plants;
    uint16_t barracks;
    uint16_t refineries;
    uint16_t harvesters;
    uint16_t e1;
    uint16_t e3;
    uint32_t building_scan;
    uint32_t active_building_scan;
    uint32_t infantry_scan;
    uint32_t active_infantry_scan;
} TdMicroOracleAIState;

typedef struct TdMicroOracleAICommand {
    uint32_t frame;
    uint16_t sequence;
    uint8_t owner;
    uint8_t command;
    uint8_t actor_kind;
    uint16_t actor_id;
    uint8_t product;
    uint8_t target_kind;
    int16_t target_x;
    int16_t target_y;
    uint8_t target_owner;
    uint8_t target_entity_kind;
    uint16_t target_id;
} TdMicroOracleAICommand;

typedef struct TdMicroOracleEntity {
    uint16_t id;
    uint8_t kind;
    uint8_t owner;
    uint8_t active;
    uint8_t in_limbo;
    int16_t cell_x;
    int16_t cell_y;
    int32_t coord_x;
    int32_t coord_y;
    int32_t head_coord_x;
    int32_t head_coord_y;
    int16_t health;
    int16_t max_health;
    int16_t facing;
    int8_t mission;
    int8_t queued_mission;
    int8_t status;
    uint8_t weapon_cooldown;
    uint8_t moving;
    uint8_t firing;
    uint8_t deploying;
    uint8_t speed;
    int8_t path_facing;
    uint8_t new_destination;
    int8_t animation;
    uint16_t animation_stage;
    uint8_t animation_timer;
    uint8_t animation_rate;
    uint8_t prone;
    uint8_t fear;
    int16_t ammo;
    uint16_t kills;
    uint8_t second_shot;
    uint8_t cargo_steps;
    uint8_t harvesting;
    uint64_t target;
    uint64_t destination;
    /* CNC26: Vanilla's TurretClass::SecondaryFacing, which rotates independently of the hull.
       Left at 0 for anything without a combat turret. */
    int16_t turret_facing;
    uint8_t has_turret;
} TdMicroOracleEntity;

typedef struct TdMicroOracleProjectile {
    uint16_t id;
    uint8_t type;
    uint8_t active;
    uint8_t in_limbo;
    int32_t coord_x;
    int32_t coord_y;
    int32_t fuse_x;
    int32_t fuse_y;
    int16_t strength;
    int16_t facing;
    uint8_t desired_facing;
    uint8_t speed;
    uint16_t speed_accum;
    uint8_t timer;
    uint8_t arming;
    int16_t proximity;
    uint8_t source_owner;
    uint8_t source_kind;
    uint16_t source_id;
    uint8_t target_owner;
    uint8_t target_kind;
    uint16_t target_id;
    uint64_t target;
} TdMicroOracleProjectile;

typedef struct TdMicroOracleMapCell {
    uint8_t land_type;
    uint8_t foot_cost;
    uint8_t ground_buildable;
    uint8_t static_blocked;
    uint8_t foot_passable;
    int16_t overlay;
    uint8_t overlay_data;
} TdMicroOracleMapCell;

typedef struct TdMicroOracleMap {
    uint32_t schema_version;
    int16_t map_x;
    int16_t map_y;
    uint16_t map_width;
    uint16_t map_height;
    TdMicroOracleMapCell cells[TD_MICRO_ORACLE_MAX_MAP_CELLS];
} TdMicroOracleMap;

typedef struct TdMicroOracleSnapshot {
    uint32_t schema_version;
    uint32_t frame;
    uint32_t setup_seed;
    uint32_t rng_state;
    int16_t map_x;
    int16_t map_y;
    uint16_t map_width;
    uint16_t map_height;
    uint8_t player_count;
    uint8_t content_violation;
    uint16_t entity_count;
    uint16_t projectile_count;
    uint16_t ai_command_count;
    TdMicroOraclePlayer players[TD_MICRO_PLAYER_COUNT];
    TdMicroOracleAIState ai;
    TdMicroOracleQueue queues[TD_MICRO_ORACLE_QUEUE_COUNT];
    TdMicroOracleAICommand ai_commands[TD_MICRO_ORACLE_MAX_AI_COMMANDS];
    TdMicroOracleEntity entities[TD_MICRO_ORACLE_MAX_ENTITIES];
    TdMicroOracleProjectile projectiles[TD_MICRO_MAX_PROJECTILES];
    uint8_t tiberium_steps[TD_MICRO_ORACLE_MAX_MAP_CELLS];
    uint64_t tiberium_present[TD_MICRO_ORACLE_MAX_MAP_CELLS / 64];
} TdMicroOracleSnapshot;

#pragma pack(pop)

#endif
