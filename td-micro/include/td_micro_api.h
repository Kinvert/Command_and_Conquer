#ifndef TD_MICRO_API_H
#define TD_MICRO_API_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TD_MICRO_ABI_VERSION 13u
#define TD_MICRO_OBSERVATION_VERSION 7u
#define TD_MICRO_OBSERVATION_SIZE 3992u
#define TD_MICRO_OBSERVATION_GLOBAL_SIZE 64u
#define TD_MICRO_OBSERVATION_DIFFICULTY_OFFSET 33u
#define TD_MICRO_OBSERVATION_TIBERIUM_COUNT 344u
#define TD_MICRO_OBSERVATION_ENTITY_SLOT_COUNT 64u
#define TD_MICRO_OBSERVATION_ENTITY_LEGACY_SIZE 16u
#define TD_MICRO_OBSERVATION_ENTITY_TYPE_COUNT 12u
#define TD_MICRO_OBSERVATION_ENTITY_TYPE_ONE_HOT_OFFSET TD_MICRO_OBSERVATION_ENTITY_LEGACY_SIZE
#define TD_MICRO_OBSERVATION_ENTITY_SIZE \
    (TD_MICRO_OBSERVATION_ENTITY_LEGACY_SIZE + TD_MICRO_OBSERVATION_ENTITY_TYPE_COUNT)
#define TD_MICRO_ACTION_HEAD_COUNT 4u
#define TD_MICRO_ACTION_MASK_BIT_COUNT 9242u
#define TD_MICRO_ACTION_MASK_SIZE 1156u
#define TD_MICRO_ABI9_ACTION_HEAD_COUNT 7u
#define TD_MICRO_ABI9_ACTION_MASK_SIZE 282u
#define TD_MICRO_ABI14_ACTION_HEAD_COUNT 71u
#define TD_MICRO_ABI14_ACTION_MASK_SIZE 474u
#define TD_MICRO_ABI14_SELECTOR_COUNT 64u
/* ABI14 mask regions, mirroring policy_abi14.zig. The first ABI9_ACTION_MASK_SIZE bytes are the
 * ABI9 mask copied verbatim; each selector then owns two consecutive byte-per-entry slots; the
 * attack-target region follows the action logits. Consumers must derive offsets from these rather
 * than hardcoding, or they drift the way the ABI13 encoder did. */
#define TD_MICRO_ABI14_SELECTOR_MASK_OFFSET TD_MICRO_ABI9_ACTION_MASK_SIZE
#define TD_MICRO_ABI14_ATTACK_TARGET_MASK_OFFSET 410u
#define TD_MICRO_RULESET_HASH_SIZE 32u
#define TD_MICRO_PLAYER_BUILDING_LIMIT 16u
#define TD_MICRO_PLAYER_INFANTRY_LIMIT 64u
#define TD_MICRO_CONSECUTIVE_INVALID_ACTION_LIMIT 0u
#define TD_MICRO_TRAINING_TIMEOUT_FRAMES 48000u
#define TD_MICRO_TRAINING_MAX_DECISIONS 12000u
#define TD_MICRO_FULL_WIN_MIN_TIBERIUM_INCOME 1000u
#define TD_MICRO_FULL_WIN_MIN_MEDIUM_TANKS 1u
#define TD_MICRO_FULL_WIN_MIN_TANK_SHOTS 1u
#define TD_MICRO_CURRICULUM_FULL_MATCH 0u
#define TD_MICRO_CURRICULUM_REVERSE 1u
#define TD_MICRO_DIFFICULTY_FIXED_EASY 0u
#define TD_MICRO_DIFFICULTY_EASY_TO_NORMAL 1u
#define TD_MICRO_DIFFICULTY_FIXED_NORMAL 2u
#define TD_MICRO_DIFFICULTY_FIXED_HARD 3u
#define TD_MICRO_POLICY_HIDDEN_SIZE 64u
#define TD_MICRO_POLICY_LAYER_COUNT 1u
#define TD_MICRO_POLICY_DECODER_SIZE 4913u
#define TD_MICRO_POLICY_WEIGHT_COUNT 582208u
#define TD_MICRO_POLICY_CHECKPOINT_SIZE 2328832u

#define TD_MICRO_MAP_LAND_MASK 0x07u
#define TD_MICRO_MAP_PASSABLE_BIT 0x08u
#define TD_MICRO_MAP_BUILDABLE_BIT 0x10u
#define TD_MICRO_MAP_VISIBLE_BIT 0x20u
#define TD_MICRO_MAP_OCCUPANCY_MASK 0xc0u
#define TD_MICRO_MAP_OCCUPANCY_SHIFT 6u

#define TD_MICRO_POLICY_COMMAND_COUNT 12u
#define TD_MICRO_POLICY_TOKEN_COUNT 65u
#define TD_MICRO_POLICY_PAD_TOKEN 64u
#define TD_MICRO_POLICY_ACTOR_COUNT TD_MICRO_POLICY_TOKEN_COUNT
#define TD_MICRO_POLICY_ACTOR_NONE TD_MICRO_POLICY_PAD_TOKEN
#define TD_MICRO_POLICY_PRODUCT_COUNT 9u
#define TD_MICRO_POLICY_TARGET_KIND_COUNT 4u
#define TD_MICRO_POLICY_COORDINATE_COUNT 64u
#define TD_MICRO_POLICY_TARGET_SLOT_COUNT 64u

#define TD_MICRO_MASK_COMMAND_BIT_OFFSET 0u
#define TD_MICRO_MASK_PAD_BIT_OFFSET 12u
#define TD_MICRO_MASK_DEPLOY_ACTOR_BIT_OFFSET 77u
#define TD_MICRO_MASK_BUILD_PRODUCT_BIT_OFFSET 142u
#define TD_MICRO_MASK_PLACE_X_BIT_OFFSET 207u
#define TD_MICRO_MASK_PLACE_Y_BIT_OFFSET 272u
#define TD_MICRO_MASK_TRAIN_PRODUCT_BIT_OFFSET 4432u
#define TD_MICRO_MASK_MOVE_ACTOR_BIT_OFFSET 4497u
#define TD_MICRO_MASK_MOVE_X_BIT_OFFSET 4562u
#define TD_MICRO_MASK_MOVE_Y_BIT_OFFSET 4627u
#define TD_MICRO_MASK_ATTACK_ACTOR_BIT_OFFSET 4692u
#define TD_MICRO_MASK_ATTACK_TARGET_BIT_OFFSET 4757u
#define TD_MICRO_MASK_HARVEST_ACTOR_BIT_OFFSET 4822u
#define TD_MICRO_MASK_HARVEST_X_BIT_OFFSET 4887u
#define TD_MICRO_MASK_HARVEST_Y_BIT_OFFSET 4952u
#define TD_MICRO_MASK_RETURN_ACTOR_BIT_OFFSET 9112u
#define TD_MICRO_MASK_RETURN_TARGET_BIT_OFFSET 9177u

typedef enum TdMicroPolicyProduct {
    TD_MICRO_POLICY_PRODUCT_NONE = 0,
    TD_MICRO_POLICY_PRODUCT_POWER_PLANT = 1,
    TD_MICRO_POLICY_PRODUCT_BARRACKS = 2,
    TD_MICRO_POLICY_PRODUCT_E1 = 3,
    TD_MICRO_POLICY_PRODUCT_E3 = 4,
    TD_MICRO_POLICY_PRODUCT_REFINERY = 5,
    /* CNC26 vehicles, appended so the original five keep their encodings. */
    TD_MICRO_POLICY_PRODUCT_WEAPONS_FACTORY = 6,
    TD_MICRO_POLICY_PRODUCT_MEDIUM_TANK = 7,
    TD_MICRO_POLICY_PRODUCT_HUMVEE = 8,
} TdMicroPolicyProduct;

#pragma pack(push, 1)
typedef struct TdMicroPolicyAction {
    uint8_t command;
    uint8_t arg0;
    uint8_t arg1;
    uint8_t arg2;
} TdMicroPolicyAction;

typedef struct TdMicroPolicyActionAbi9 {
    uint8_t command;
    uint8_t actor;
    uint8_t product;
    uint8_t target_kind;
    uint8_t target_x;
    uint8_t target_y;
    uint8_t target_slot;
} TdMicroPolicyActionAbi9;

typedef struct TdMicroPolicyActionAbi14 {
    uint8_t command;
    uint8_t actor;
    uint8_t product;
    uint8_t target_kind;
    uint8_t target_x;
    uint8_t target_y;
    uint8_t target_slot;
    uint8_t selectors[TD_MICRO_ABI14_SELECTOR_COUNT];
} TdMicroPolicyActionAbi14;
#pragma pack(pop)

typedef struct TdMicroBatchStats {
    uint64_t decisions;
    uint64_t episodes;
    uint64_t wins;
    uint64_t losses;
    uint64_t draws;
    uint64_t invalid_actions;
    uint64_t building_limit_losses;
    uint64_t infantry_limit_losses;
    uint64_t invalid_streak_losses;
    uint64_t failures;
    uint64_t episode_decisions;
    uint64_t close_episodes;
    uint64_t close_wins;
    uint64_t close_losses;
    uint64_t medium_episodes;
    uint64_t medium_wins;
    uint64_t medium_losses;
    uint64_t close_mcv_episodes;
    uint64_t close_mcv_wins;
    uint64_t close_mcv_losses;
    uint64_t close_force_episodes;
    uint64_t close_force_wins;
    uint64_t close_force_losses;
    uint64_t medium_mcv_episodes;
    uint64_t medium_mcv_wins;
    uint64_t medium_mcv_losses;
    uint64_t medium_force_episodes;
    uint64_t medium_force_wins;
    uint64_t medium_force_losses;
    uint64_t completed_invalid_actions;
    double invalid_action_penalty;
} TdMicroBatchStats;

typedef struct TdMicroBatchStatsV2 {
    uint64_t decisions;
    uint64_t episodes;
    uint64_t wins;
    uint64_t losses;
    uint64_t draws;
    uint64_t invalid_actions;
    uint64_t building_limit_losses;
    uint64_t infantry_limit_losses;
    uint64_t invalid_streak_losses;
    uint64_t failures;
    uint64_t episode_decisions;
    uint64_t close_episodes;
    uint64_t close_wins;
    uint64_t close_losses;
    uint64_t medium_episodes;
    uint64_t medium_wins;
    uint64_t medium_losses;
    uint64_t close_mcv_episodes;
    uint64_t close_mcv_wins;
    uint64_t close_mcv_losses;
    uint64_t close_force_episodes;
    uint64_t close_force_wins;
    uint64_t close_force_losses;
    uint64_t medium_mcv_episodes;
    uint64_t medium_mcv_wins;
    uint64_t medium_mcv_losses;
    uint64_t medium_force_episodes;
    uint64_t medium_force_wins;
    uint64_t medium_force_losses;
    uint64_t completed_invalid_actions;
    double invalid_action_penalty;
    uint64_t easy_close_mcv_episodes;
    uint64_t easy_close_mcv_wins;
    uint64_t easy_close_force_episodes;
    uint64_t easy_close_force_wins;
    uint64_t easy_medium_mcv_episodes;
    uint64_t easy_medium_mcv_wins;
    uint64_t easy_medium_force_episodes;
    uint64_t easy_medium_force_wins;
    uint64_t normal_close_mcv_episodes;
    uint64_t normal_close_mcv_wins;
    uint64_t normal_close_force_episodes;
    uint64_t normal_close_force_wins;
    uint64_t normal_medium_mcv_episodes;
    uint64_t normal_medium_mcv_wins;
    uint64_t normal_medium_force_episodes;
    uint64_t normal_medium_force_wins;
    /* Appended after the difficulty split so the 248-byte legacy prefix stays intact.
     * Constrained (2300-credit) starts are tracked on their own rather than blended into
     * balanced_perf, and the attack counters measure group-attack reachability directly. */
    uint64_t constrained_episodes;
    uint64_t constrained_wins;
    uint64_t build_order_violations;
    uint64_t attacks_attempted;
    uint64_t attacks_applied;
    /* Must stay last, matching batch.Stats. A size assert cannot catch field-order drift: this was
       third from the end here and last in Zig, so economy_wins read constrained_episodes and the
       reported economy_win_rate was episode share, not a win rate. */
    uint64_t full_wins;
} TdMicroBatchStatsV2;

/* Event totals from completed episodes; reset by td_micro_reset_batch. */
typedef struct TdMicroBatchMetrics {
    uint64_t player_e1_built;
    uint64_t player_e3_built;
    uint64_t opponent_e1_built;
    uint64_t opponent_e3_built;
    uint64_t player_unit_kills;
    uint64_t opponent_unit_kills;
    uint64_t player_unit_losses;
    uint64_t opponent_unit_losses;
    uint64_t player_buildings_lost;
    uint64_t opponent_buildings_lost;
    uint64_t enemy_attack_orders;
    uint64_t accepted_train_actions;
    uint64_t rejected_train_actions;
    uint64_t construction_yard_milestones;
    uint64_t power_plant_milestones;
    uint64_t barracks_milestones;
    uint64_t e1_milestones;
    uint64_t e3_milestones;
    uint64_t player_refineries_built;
    uint64_t player_weapons_factories_built;
    uint64_t player_medium_tanks_built;
    uint64_t player_humvees_built;
    uint64_t player_tank_shots;
    uint64_t player_tank_kills;
    uint64_t opponent_refineries_built;
    uint64_t player_harvesters_spawned;
    uint64_t opponent_harvesters_spawned;
    uint64_t player_tiberium_income;
    uint64_t opponent_tiberium_income;
    uint64_t refinery_milestones;
    uint64_t harvester_milestones;
    uint64_t first_delivery_milestones;
    uint64_t first_tank_milestones;
    uint64_t first_tank_shot_milestones;
    uint64_t qualified_losses;
    uint64_t player_e1_attack_orders;
    uint64_t player_e1_infantry_targets;
    uint64_t player_e3_attack_orders;
    uint64_t player_e3_vehicle_targets;
    uint64_t player_tank_attack_orders;
    uint64_t player_tank_e3_targets;
    uint64_t player_tank_losses;
    uint64_t player_tank_losses_to_e3;
} TdMicroBatchMetrics;

typedef struct TdMicroRewardConfig {
    float reward_milestone;
    float reward_player_infantry;
    float reward_enemy_unit_loss;
    float reward_enemy_building_loss;
    float reward_player_unit_loss;
    float reward_refinery;
    float reward_first_delivery;
    /* CNC26: reaching armour costs 2000 for the factory and had no payoff of its own. */
    float reward_weapons_factory;
    float reward_vehicle;
    /* Win grading: a win that mined at least economy_win_credits pays reward_economy_win, any
       other win pays reward_rush_win. Puts "win a real game" in the objective itself. */
    float reward_full_win;
    float reward_partial_win;
    uint32_t economy_win_credits;
    uint32_t full_win_min_tanks;
    uint32_t full_win_min_humvees;
    uint32_t full_win_min_tank_shots;
    float reward_tiberium_income;
    float reward_invalid_action;
    /* Immediate, non-terminal penalty for queueing a barracks before committing to a refinery.
     * Charged at start_build so the credit assignment is one decision wide. */
    float reward_build_order_violation;
    float reward_build_order_violation_constrained;
    /* Paid once when power plant -> refinery -> barracks completes in order. */
    float reward_build_order_sequence;
    /* Paid per kill credited to a player medium tank. Gated on the kill rather than the purchase
     * so a large armour bounty cannot be collected by a tank that is rushed out and immediately
     * lost, and paid per kill rather than once because latching every armour reward left the
     * return too sparse to train. */
    float reward_tank_kill;
    /* One-time episode rewards for reaching and using armour. Lifetime counters are the latches,
     * so replacing a lost tank or firing again cannot collect either reward twice. */
    float reward_first_tank;
    float reward_first_tank_shot;
    /* Terminal reward for a real full-match loss after satisfying all full-win prerequisites.
     * Engine failures, curriculum soft deaths, and unqualified losses remain unchanged. */
    float reward_qualified_loss;
} TdMicroRewardConfig;

typedef struct TdMicroBatch TdMicroBatch;
typedef struct TdMicroPolicy TdMicroPolicy;

uint32_t td_micro_abi_version(void);
uint32_t td_micro_observation_size(void);
uint32_t td_micro_action_head_count(void);
uint32_t td_micro_action_mask_size(void);
uint32_t td_micro_action_head_count_abi9(void);
uint32_t td_micro_action_mask_size_abi9(void);
uint32_t td_micro_action_head_count_abi14(void);
uint32_t td_micro_action_mask_size_abi14(void);
uint32_t td_micro_player_building_limit(void);
uint32_t td_micro_player_infantry_limit(void);
uint32_t td_micro_consecutive_invalid_action_limit(void);
uint32_t td_micro_training_timeout_frames(void);
uint32_t td_micro_training_max_decisions(void);
int td_micro_default_reward_config(TdMicroRewardConfig* output);
int td_micro_reward_config_valid(const TdMicroRewardConfig* config);
int td_micro_curriculum_schedule_valid(uint32_t schedule_id);
int td_micro_curriculum_config_valid(
    uint32_t schedule_id,
    uint64_t stage_decisions,
    uint64_t starting_force_ramp_decisions);
int td_micro_difficulty_schedule_valid(uint32_t schedule_id);
int td_micro_difficulty_config_valid(uint32_t schedule_id, uint64_t ramp_decisions);
uint32_t td_micro_action_head_sizes(uint16_t* output, uint32_t capacity);
uint32_t td_micro_action_head_sizes_abi9(uint16_t* output, uint32_t capacity);
uint32_t td_micro_action_head_sizes_abi14(uint16_t* output, uint32_t capacity);
uint32_t td_micro_ruleset_hash(uint8_t* output, uint32_t capacity);
uint64_t td_micro_balanced_spawn_seed(uint64_t base_seed, uint64_t ordinal);

uint32_t td_micro_policy_weight_count(void);
uint32_t td_micro_policy_checkpoint_size(void);
/* ABI13 checkpoints identify their supported 64/128 hidden width by exact byte length. */
uint32_t td_micro_policy_hidden_for_checkpoint_size(uint32_t bytes);
uint32_t td_micro_policy_hidden_size(const TdMicroPolicy* policy);
TdMicroPolicy* td_micro_policy_create(const uint8_t* checkpoint, uint32_t checkpoint_size);
void td_micro_policy_destroy(TdMicroPolicy* policy);
int td_micro_policy_reset(TdMicroPolicy* policy);
int td_micro_policy_seed_sampling(TdMicroPolicy* policy, uint64_t seed);
uint32_t td_micro_policy_checkpoint_sha256(
    const TdMicroPolicy* policy,
    uint8_t* output,
    uint32_t capacity);
int td_micro_policy_act(
    TdMicroPolicy* policy,
    const uint8_t* observation,
    uint32_t observation_size,
    const uint8_t* action_mask,
    uint32_t action_mask_size,
    TdMicroPolicyAction* output);
int td_micro_policy_act_sampled(
    TdMicroPolicy* policy,
    const uint8_t* observation,
    uint32_t observation_size,
    const uint8_t* action_mask,
    uint32_t action_mask_size,
    TdMicroPolicyAction* output);

/* ABI14 deployment-side inference. A distinct opaque handle: the ABI14 model shares the ABI13
 * trunk but has its own decoder width, so the two checkpoint formats are not interchangeable. */
typedef struct TdMicroPolicyAbi14 TdMicroPolicyAbi14;
uint32_t td_micro_policy_weight_count_abi14(void);
uint32_t td_micro_policy_checkpoint_size_abi14(void);
/* Returns the hidden size a checkpoint of this length implies, or 0 if it is not a valid ABI14
 * checkpoint. ABI14 shipped at hidden 64 and 128 and their lengths differ, so the artifact
 * identifies itself. */
uint32_t td_micro_policy_abi14_hidden_for_checkpoint_size(uint32_t bytes);
uint32_t td_micro_policy_hidden_size_abi14(const TdMicroPolicyAbi14* policy);
TdMicroPolicyAbi14* td_micro_policy_create_abi14(const uint8_t* checkpoint, uint32_t checkpoint_size);
void td_micro_policy_destroy_abi14(TdMicroPolicyAbi14* policy);
int td_micro_policy_reset_abi14(TdMicroPolicyAbi14* policy);
int td_micro_policy_seed_sampling_abi14(TdMicroPolicyAbi14* policy, uint64_t seed);
uint32_t td_micro_policy_checkpoint_sha256_abi14(
    const TdMicroPolicyAbi14* policy,
    uint8_t* output,
    uint32_t capacity);
int td_micro_policy_act_sampled_abi14(
    TdMicroPolicyAbi14* policy,
    const uint8_t* observation,
    uint32_t observation_size,
    const uint8_t* action_mask,
    uint32_t action_mask_size,
    TdMicroPolicyActionAbi14* output);

TdMicroBatch* td_micro_batch_create(uint32_t count, uint32_t max_decisions);
TdMicroBatch* td_micro_batch_create_with_reward_config(
    uint32_t count,
    uint32_t max_decisions,
    const TdMicroRewardConfig* reward_config);
TdMicroBatch* td_micro_batch_create_with_configs(
    uint32_t count,
    uint32_t max_decisions,
    const TdMicroRewardConfig* reward_config,
    uint32_t curriculum_schedule_id,
    uint64_t curriculum_stage_decisions,
    uint64_t starting_force_ramp_decisions);
TdMicroBatch* td_micro_batch_create_with_configs_v2(
    uint32_t count,
    uint32_t max_decisions,
    const TdMicroRewardConfig* reward_config,
    uint32_t curriculum_schedule_id,
    uint64_t curriculum_stage_decisions,
    uint64_t starting_force_ramp_decisions,
    uint32_t difficulty_schedule_id,
    uint64_t difficulty_ramp_decisions);
void td_micro_batch_destroy(TdMicroBatch* batch);
uint32_t td_micro_batch_count(const TdMicroBatch* batch);
size_t td_micro_batch_snapshot_size(const TdMicroBatch* batch);
int td_micro_batch_write_snapshot(
    const TdMicroBatch* batch,
    uint8_t* output,
    size_t capacity);
int td_micro_batch_read_snapshot(
    TdMicroBatch* batch,
    const uint8_t* input,
    size_t size);
int td_micro_reset_batch(TdMicroBatch* batch, const uint64_t* seeds, uint32_t count);
int td_micro_observe_batch(
    const TdMicroBatch* batch,
    uint8_t* observations,
    uint8_t* action_masks,
    uint32_t count);
int td_micro_observe_batch_abi9(
    const TdMicroBatch* batch,
    uint8_t* observations,
    uint8_t* action_masks,
    uint32_t count);
int td_micro_observe_batch_abi14(
    const TdMicroBatch* batch,
    uint8_t* observations,
    uint8_t* action_masks,
    uint32_t count);
int td_micro_step_batch(
    TdMicroBatch* batch,
    const TdMicroPolicyAction* actions,
    uint8_t* observations,
    uint8_t* action_masks,
    float* rewards,
    uint8_t* terminals,
    uint32_t count);
int td_micro_step_batch_abi9(
    TdMicroBatch* batch,
    const TdMicroPolicyActionAbi9* actions,
    uint8_t* observations,
    uint8_t* action_masks,
    float* rewards,
    uint8_t* terminals,
    uint32_t count);
int td_micro_step_batch_abi14(
    TdMicroBatch* batch,
    const TdMicroPolicyActionAbi14* actions,
    uint8_t* observations,
    uint8_t* action_masks,
    float* rewards,
    uint8_t* terminals,
    uint32_t count);
int td_micro_batch_stats(const TdMicroBatch* batch, TdMicroBatchStats* output);
int td_micro_batch_stats_v2(const TdMicroBatch* batch, TdMicroBatchStatsV2* output);
int td_micro_batch_metrics(const TdMicroBatch* batch, TdMicroBatchMetrics* output);
uint32_t td_micro_batch_world_digest(
    const TdMicroBatch* batch,
    uint32_t world_index,
    uint8_t* output,
    uint32_t capacity);

#ifdef __cplusplus
}
#endif

#endif
