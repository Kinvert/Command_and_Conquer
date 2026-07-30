/* Generated from rules/td_micro_v1.json. Do not edit by hand. */
#ifndef TD_MICRO_V1_H
#define TD_MICRO_V1_H
#include <stdint.h>
#define TD_MICRO_RULESET_ID "td_micro_v1"
#define TD_MICRO_MANIFEST_SHA256 "f9cf1827cb80c3fe29ebddffa11453a4d9bcf42929005fb45573a3bb612b367b"
#define TD_MICRO_DECISION_FRAMES 4
#define TD_MICRO_INITIAL_CREDITS 10000
#define TD_MICRO_STARTING_CREDITS_CONSTRAINED 2300
#define TD_MICRO_STARTING_CREDITS_CONSTRAINED_PERCENT 35
#define TD_MICRO_STARTING_CREDITS_RANDOM_MIN 2400
#define TD_MICRO_STARTING_CREDITS_RANDOM_MAX 10000
#define TD_MICRO_STARTING_CREDITS_STEP 100
#define TD_MICRO_STARTING_FORCE_PERCENT 50
#define TD_MICRO_STARTING_FORCE_UNIT_COUNT 6
#define TD_MICRO_STARTING_FORCE_E1_COUNT 3
#define TD_MICRO_STARTING_FORCE_E3_COUNT 3
#define TD_MICRO_ATTACK_DELAY 1
typedef struct TdMicroFixedRatio {
    uint32_t numerator;
    uint32_t denominator;
} TdMicroFixedRatio;

typedef struct TdMicroDifficultyHandicap {
    TdMicroFixedRatio firepower_bias;
    TdMicroFixedRatio groundspeed_bias;
    TdMicroFixedRatio airspeed_bias;
    TdMicroFixedRatio armor_bias;
    TdMicroFixedRatio rof_bias;
    TdMicroFixedRatio cost_bias;
    TdMicroFixedRatio build_speed_bias;
    TdMicroFixedRatio repair_delay;
    TdMicroFixedRatio build_delay;
    uint8_t build_slowdown;
    uint8_t wall_destroyer;
    uint8_t content_scan;
} TdMicroDifficultyHandicap;

#define TD_MICRO_DIFFICULTY_HANDICAP_COUNT 3
static const TdMicroDifficultyHandicap
    TD_MICRO_DIFFICULTY_HANDICAPS[TD_MICRO_DIFFICULTY_HANDICAP_COUNT] = {
    {{11, 10}, {11, 10}, {11, 10}, {1, 1}, {4, 5}, {4, 5}, {3, 5}, {1, 1000}, {1, 500}, 0, 1, 1},
    {{1, 1}, {1, 1}, {1, 1}, {1, 1}, {1, 1}, {1, 1}, {1, 1}, {1, 50}, {3, 100}, 1, 1, 1},
    {{9, 10}, {9, 10}, {9, 10}, {21, 20}, {21, 20}, {1, 1}, {1, 1}, {1, 20}, {1, 10}, 1, 1, 1},
};
#define TD_MICRO_HARVESTER_CAPACITY_STEPS 28
#define TD_MICRO_HARVEST_INTERVAL_FRAMES 15
#define TD_MICRO_PLAYER_TIBERIUM_STEP_CREDITS 25
#define TD_MICRO_AI_TIBERIUM_STEP_CREDITS 33
#define TD_MICRO_REFINERY_CAPACITY 1000
#define TD_MICRO_PLAYER_COUNT 2
#define TD_MICRO_SCENARIO_ID 1
#define TD_MICRO_MAX_MAP_WIDTH 64
#define TD_MICRO_MAX_MAP_HEIGHT 64
#define TD_MICRO_MAX_UNITS 16
#define TD_MICRO_MAX_BUILDINGS 64
#define TD_MICRO_MAX_INFANTRY 128
#define TD_MICRO_MAX_PROJECTILES 256
#define TD_MICRO_SPAWN_PROFILE_COUNT 2

typedef enum TdMicroSpawnBucket {
    TD_MICRO_SPAWN_CLOSE = 0,
    TD_MICRO_SPAWN_MEDIUM = 1,
} TdMicroSpawnBucket;

typedef struct TdMicroSpawnProfile {
    uint8_t id;
    uint8_t bucket;
    uint8_t player_waypoint;
    uint8_t opponent_waypoint;
    uint8_t player_x;
    uint8_t player_y;
    uint8_t opponent_x;
    uint8_t opponent_y;
} TdMicroSpawnProfile;

static const TdMicroSpawnProfile TD_MICRO_SPAWN_PROFILES[TD_MICRO_SPAWN_PROFILE_COUNT] = {
    {0, TD_MICRO_SPAWN_CLOSE, 0, 1, 2, 8, 15, 1},
    {1, TD_MICRO_SPAWN_MEDIUM, 0, 3, 2, 8, 37, 23},
};

typedef enum TdMicroObjectType {
    TD_MICRO_OBJECT_NONE = 0,
    TD_MICRO_OBJECT_MCV = 1,
    TD_MICRO_OBJECT_CONSTRUCTION_YARD = 2,
    TD_MICRO_OBJECT_POWER_PLANT = 3,
    TD_MICRO_OBJECT_BARRACKS = 4,
    TD_MICRO_OBJECT_E1 = 5,
    TD_MICRO_OBJECT_E3 = 6,
    TD_MICRO_OBJECT_REFINERY = 7,
    TD_MICRO_OBJECT_HARVESTER = 8,
    TD_MICRO_OBJECT_WEAPONS_FACTORY = 9,
    TD_MICRO_OBJECT_MEDIUM_TANK = 10,
    TD_MICRO_OBJECT_HUMVEE = 11,
} TdMicroObjectType;

#endif
