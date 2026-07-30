#ifndef PUFFERLIB_CNC_MICRO_H
#define PUFFERLIB_CNC_MICRO_H

#include "td_micro_api.h"

#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define CNC_MICRO_EXPORTED_LOG_COUNT 30
#define CNC_MICRO_LOG_FLOAT_COUNT 76
#define CNC_MICRO_WIN_TRACE_VERSION 4u

typedef struct Log {
    float perf;
    float episode_return;
    float episode_length;
    float loss_rate;
    float draw_rate;
    float invalid_actions;
    float building_limit_losses;
    float failures;
    float start_failures;
    float units_built;
    float gunners_built;
    float rocket_soldiers_built;
    float unit_kills;
    float unit_losses;
    float buildings_lost;
    float buildings_destroyed;
    float enemy_attack_orders;
    float power_plant_milestones;
    float barracks_milestones;
    float refineries_built;
    float weapons_factories_built;
    float medium_tanks_built;
    float tank_shots;
    float tank_kills;
    float harvesters_spawned;
    float tiberium_income;
    float refinery_milestones;
    float invalid_action_penalty;
    float first_delivery_milestones;
    float close_episodes;
    float close_wins;
    float close_losses;
    float medium_episodes;
    float medium_wins;
    float medium_losses;
    float close_mcv_episodes;
    float close_mcv_wins;
    float close_force_episodes;
    float close_force_wins;
    float medium_mcv_episodes;
    float medium_mcv_wins;
    float medium_force_episodes;
    float medium_force_wins;
    float easy_close_mcv_episodes;
    float easy_close_mcv_wins;
    float easy_close_force_episodes;
    float easy_close_force_wins;
    float easy_medium_mcv_episodes;
    float easy_medium_mcv_wins;
    float easy_medium_force_episodes;
    float easy_medium_force_wins;
    float normal_close_mcv_episodes;
    float normal_close_mcv_wins;
    float normal_close_force_episodes;
    float normal_close_force_wins;
    float normal_medium_mcv_episodes;
    float normal_medium_mcv_wins;
    float normal_medium_force_episodes;
    float normal_medium_force_wins;
    /* Constrained 2300-credit starts, reported on their own: they are the bucket the build-order
       shaping targets, and blending them into balanced_perf hides whether it worked. */
    float full_wins;
    float constrained_episodes;
    float constrained_wins;
    float build_order_violations;
    float attacks_attempted;
    float attacks_applied;
    float first_tank_milestones;
    float first_tank_shot_milestones;
    float qualified_losses;
    float player_e1_attack_orders;
    float player_e1_infantry_targets;
    float player_e3_attack_orders;
    float player_e3_vehicle_targets;
    float player_tank_attack_orders;
    float player_tank_e3_targets;
    float player_tank_losses;
    float player_tank_losses_to_e3;
    float n;
} Log;

typedef struct CncMicro {
    Log log;
    uint8_t* observations;
    float* actions;
    float* rewards;
    float* terminals;
    uint8_t* action_mask;
    unsigned int rng;
    int num_agents;
    int action_abi;
    uint32_t action_head_count;
    size_t policy_action_size;
    uint32_t max_decisions;
    uint32_t curriculum_schedule_id;
    uint64_t curriculum_stage_decisions;
    uint64_t starting_force_ramp_decisions;
    uint32_t difficulty_schedule_id;
    uint64_t difficulty_ramp_decisions;
    uint64_t seed;
    TdMicroBatch* batch;
    void* decoded_actions;
    uint8_t* terminal_bytes;
    uint64_t* seeds;
    float* episode_returns;
    TdMicroRewardConfig reward_config;
    const char* win_trace_prefix;
    void* episode_action_traces;
    uint32_t* episode_trace_lengths;
    uint64_t win_trace_serial;
    TdMicroBatchStatsV2 logged_stats;
    TdMicroBatchMetrics logged_metrics;
} CncMicro;

typedef struct CncMicroStateHeader {
    uint8_t magic[8];
    uint32_t version;
    uint32_t num_agents;
    uint32_t action_abi;
    uint32_t policy_action_size;
    uint32_t max_decisions;
    uint32_t curriculum_schedule_id;
    uint32_t difficulty_schedule_id;
    uint32_t trace_enabled;
    uint64_t curriculum_stage_decisions;
    uint64_t starting_force_ramp_decisions;
    uint64_t difficulty_ramp_decisions;
    uint64_t seed;
    uint64_t batch_state_size;
    uint64_t trace_data_size;
    uint64_t win_trace_serial;
    TdMicroRewardConfig reward_config;
    Log log;
    TdMicroBatchStatsV2 logged_stats;
    TdMicroBatchMetrics logged_metrics;
} CncMicroStateHeader;

static inline size_t cnc_micro_state_size(const CncMicro* env)
{
    const size_t count = (size_t)env->num_agents;
    const size_t trace_data_size = env->episode_action_traces == NULL
        ? 0
        : count * env->max_decisions * env->policy_action_size;
    return sizeof(CncMicroStateHeader)
        + td_micro_batch_snapshot_size(env->batch)
        + count * sizeof(*env->seeds)
        + count * sizeof(*env->episode_returns)
        + count * sizeof(*env->terminal_bytes)
        + (env->episode_trace_lengths == NULL ? 0 : count * sizeof(*env->episode_trace_lengths))
        + trace_data_size;
}

static inline int cnc_micro_state_append(
    uint8_t** cursor,
    size_t* remaining,
    const void* source,
    size_t size)
{
    if (*remaining < size) return 0;
    memcpy(*cursor, source, size);
    *cursor += size;
    *remaining -= size;
    return 1;
}

static inline int cnc_micro_write_state(const CncMicro* env, uint8_t* output, size_t capacity)
{
    const size_t required = cnc_micro_state_size(env);
    const size_t count = (size_t)env->num_agents;
    const size_t batch_state_size = td_micro_batch_snapshot_size(env->batch);
    const size_t trace_data_size = env->episode_action_traces == NULL
        ? 0
        : count * env->max_decisions * env->policy_action_size;
    if (output == NULL || capacity != required || batch_state_size == 0) return 0;
    CncMicroStateHeader header = {0};
    memcpy(header.magic, "CNCMIC01", sizeof(header.magic));
    header.version = 7;
    header.num_agents = (uint32_t)env->num_agents;
    header.action_abi = (uint32_t)env->action_abi;
    header.policy_action_size = (uint32_t)env->policy_action_size;
    header.max_decisions = env->max_decisions;
    header.curriculum_schedule_id = env->curriculum_schedule_id;
    header.difficulty_schedule_id = env->difficulty_schedule_id;
    header.trace_enabled = env->episode_action_traces != NULL;
    header.curriculum_stage_decisions = env->curriculum_stage_decisions;
    header.starting_force_ramp_decisions = env->starting_force_ramp_decisions;
    header.difficulty_ramp_decisions = env->difficulty_ramp_decisions;
    header.seed = env->seed;
    header.batch_state_size = batch_state_size;
    header.trace_data_size = trace_data_size;
    header.win_trace_serial = env->win_trace_serial;
    header.reward_config = env->reward_config;
    header.log = env->log;
    header.logged_stats = env->logged_stats;
    header.logged_metrics = env->logged_metrics;
    uint8_t* cursor = output;
    size_t remaining = capacity;
    if (!cnc_micro_state_append(&cursor, &remaining, &header, sizeof(header))) return 0;
    if (!td_micro_batch_write_snapshot(env->batch, cursor, batch_state_size)) return 0;
    cursor += batch_state_size;
    remaining -= batch_state_size;
    if (!cnc_micro_state_append(&cursor, &remaining, env->seeds, count * sizeof(*env->seeds))
        || !cnc_micro_state_append(&cursor, &remaining, env->episode_returns,
            count * sizeof(*env->episode_returns))
        || !cnc_micro_state_append(&cursor, &remaining, env->terminal_bytes,
            count * sizeof(*env->terminal_bytes))) return 0;
    if (header.trace_enabled
        && (!cnc_micro_state_append(&cursor, &remaining, env->episode_trace_lengths,
                count * sizeof(*env->episode_trace_lengths))
            || !cnc_micro_state_append(&cursor, &remaining, env->episode_action_traces,
                trace_data_size))) return 0;
    return remaining == 0;
}

static inline int cnc_micro_state_take(
    const uint8_t** cursor,
    size_t* remaining,
    void* destination,
    size_t size)
{
    if (*remaining < size) return 0;
    memcpy(destination, *cursor, size);
    *cursor += size;
    *remaining -= size;
    return 1;
}

static inline int cnc_micro_read_state(CncMicro* env, const uint8_t* input, size_t size)
{
    const size_t count = (size_t)env->num_agents;
    if (input == NULL || size < sizeof(CncMicroStateHeader)) return 0;
    const uint8_t* cursor = input;
    size_t remaining = size;
    CncMicroStateHeader header;
    if (!cnc_micro_state_take(&cursor, &remaining, &header, sizeof(header))) return 0;
    const uint32_t trace_enabled = env->episode_action_traces != NULL;
    const size_t expected_batch_size = td_micro_batch_snapshot_size(env->batch);
    const size_t expected_trace_size = trace_enabled
        ? count * env->max_decisions * env->policy_action_size
        : 0;
    if (memcmp(header.magic, "CNCMIC01", sizeof(header.magic)) != 0
        || header.version != 7
        || header.num_agents != (uint32_t)env->num_agents
        || header.action_abi != (uint32_t)env->action_abi
        || header.policy_action_size != env->policy_action_size
        || header.max_decisions != env->max_decisions
        || header.curriculum_schedule_id != env->curriculum_schedule_id
        || header.difficulty_schedule_id != env->difficulty_schedule_id
        || header.trace_enabled != trace_enabled
        || header.curriculum_stage_decisions != env->curriculum_stage_decisions
        || header.starting_force_ramp_decisions != env->starting_force_ramp_decisions
        || header.difficulty_ramp_decisions != env->difficulty_ramp_decisions
        || header.seed != env->seed
        || header.batch_state_size != expected_batch_size
        || header.trace_data_size != expected_trace_size
        || memcmp(&header.reward_config, &env->reward_config, sizeof(env->reward_config)) != 0
        || size != cnc_micro_state_size(env)) return 0;
    if (!td_micro_batch_read_snapshot(env->batch, cursor, expected_batch_size)) return 0;
    cursor += expected_batch_size;
    remaining -= expected_batch_size;
    if (!cnc_micro_state_take(&cursor, &remaining, env->seeds, count * sizeof(*env->seeds))
        || !cnc_micro_state_take(&cursor, &remaining, env->episode_returns,
            count * sizeof(*env->episode_returns))
        || !cnc_micro_state_take(&cursor, &remaining, env->terminal_bytes,
            count * sizeof(*env->terminal_bytes))) return 0;
    if (trace_enabled
        && (!cnc_micro_state_take(&cursor, &remaining, env->episode_trace_lengths,
                count * sizeof(*env->episode_trace_lengths))
            || !cnc_micro_state_take(&cursor, &remaining, env->episode_action_traces,
                expected_trace_size))) return 0;
    env->win_trace_serial = header.win_trace_serial;
    env->log = header.log;
    env->logged_stats = header.logged_stats;
    env->logged_metrics = header.logged_metrics;
    return remaining == 0;
}

static inline int cnc_micro_init(
    CncMicro* env,
    int num_agents,
    int action_abi,
    uint32_t max_decisions,
    uint64_t seed,
    uint64_t seed_offset,
    uint32_t curriculum_schedule_id,
    uint64_t curriculum_stage_decisions,
    uint64_t starting_force_ramp_decisions,
    uint32_t difficulty_schedule_id,
    uint64_t difficulty_ramp_decisions,
    const TdMicroRewardConfig* reward_config)
{
    if (!td_micro_reward_config_valid(reward_config)) return 0;
    if (!td_micro_curriculum_config_valid(
            curriculum_schedule_id,
            curriculum_stage_decisions,
            starting_force_ramp_decisions)) return 0;
    if (!td_micro_difficulty_config_valid(
            difficulty_schedule_id,
            difficulty_ramp_decisions)) return 0;
    if (action_abi != 9
        && action_abi != (int)TD_MICRO_ABI_VERSION
        && action_abi != 14) return 0;
    env->num_agents = num_agents;
    env->action_abi = action_abi;
    if (action_abi == 9) {
        env->action_head_count = TD_MICRO_ABI9_ACTION_HEAD_COUNT;
        env->policy_action_size = sizeof(TdMicroPolicyActionAbi9);
    } else if (action_abi == 14) {
        env->action_head_count = TD_MICRO_ABI14_ACTION_HEAD_COUNT;
        env->policy_action_size = sizeof(TdMicroPolicyActionAbi14);
    } else {
        env->action_head_count = TD_MICRO_ACTION_HEAD_COUNT;
        env->policy_action_size = sizeof(TdMicroPolicyAction);
    }
    env->max_decisions = max_decisions;
    env->curriculum_schedule_id = curriculum_schedule_id;
    env->curriculum_stage_decisions = curriculum_stage_decisions;
    env->starting_force_ramp_decisions = starting_force_ramp_decisions;
    env->difficulty_schedule_id = difficulty_schedule_id;
    env->difficulty_ramp_decisions = difficulty_ramp_decisions;
    env->seed = seed;
    env->reward_config = *reward_config;
    env->batch = td_micro_batch_create_with_configs_v2(
        (uint32_t)num_agents,
        max_decisions,
        reward_config,
        curriculum_schedule_id,
        curriculum_stage_decisions,
        starting_force_ramp_decisions,
        difficulty_schedule_id,
        difficulty_ramp_decisions);
    env->decoded_actions = calloc((size_t)num_agents, env->policy_action_size);
    env->terminal_bytes = calloc((size_t)num_agents, sizeof(*env->terminal_bytes));
    env->seeds = calloc((size_t)num_agents, sizeof(*env->seeds));
    env->episode_returns = calloc((size_t)num_agents, sizeof(*env->episode_returns));
    env->win_trace_prefix = getenv("CNC_MICRO_WIN_TRACE_PREFIX");
    if (env->win_trace_prefix != NULL && env->win_trace_prefix[0] == '\0') {
        env->win_trace_prefix = NULL;
    }
    if (env->win_trace_prefix != NULL
        && difficulty_schedule_id == TD_MICRO_DIFFICULTY_EASY_TO_NORMAL) {
        fprintf(
            stderr,
            "cnc_micro: win-trace v4 is disabled for the difficulty curriculum; "
            "use fixed Easy/Normal evaluation artifacts\n");
        env->win_trace_prefix = NULL;
    }
    if (env->win_trace_prefix != NULL) {
        if (max_decisions == 0
            || (size_t)num_agents > SIZE_MAX / (size_t)max_decisions) return 0;
        env->episode_action_traces = calloc(
            (size_t)num_agents * max_decisions,
            env->policy_action_size);
        env->episode_trace_lengths = calloc(
            (size_t)num_agents,
            sizeof(*env->episode_trace_lengths));
    }
    if (env->batch == NULL || env->decoded_actions == NULL || env->terminal_bytes == NULL
        || env->seeds == NULL || env->episode_returns == NULL
        || (env->win_trace_prefix != NULL
            && (env->episode_action_traces == NULL || env->episode_trace_lengths == NULL))) {
        return 0;
    }
    for (int index = 0; index < num_agents; ++index) {
        env->seeds[index] = td_micro_balanced_spawn_seed(seed, seed_offset + (uint64_t)index);
        if (env->seeds[index] == 0) return 0;
    }
    return 1;
}

static inline int cnc_micro_resolve_action_abi(int action_scheme, int action_abi_override)
{
    if (action_scheme != 0 && action_scheme != 1) return -1;
    if (action_abi_override != 0) {
        return action_abi_override == 9
            || action_abi_override == (int)TD_MICRO_ABI_VERSION
            || action_abi_override == 14
            ? action_abi_override
            : -1;
    }
    return action_scheme == 0 ? 9 : 14;
}

static inline float cnc_micro_rate(float count, float episodes)
{
    return episodes > 0.0f ? count / episodes : 0.0f;
}

static inline float cnc_micro_full_match_episodes(const Log* log)
{
    return log->close_episodes + log->medium_episodes;
}

static inline float cnc_micro_full_match_episode_share(const Log* log)
{
    return cnc_micro_rate(cnc_micro_full_match_episodes(log), log->n);
}

static inline float cnc_micro_full_match_perf(const Log* log)
{
    return cnc_micro_rate(log->perf, cnc_micro_full_match_episodes(log));
}

static inline float cnc_micro_full_match_loss_rate(const Log* log)
{
    return cnc_micro_rate(log->loss_rate, cnc_micro_full_match_episodes(log));
}

static inline float cnc_micro_full_match_draw_rate(const Log* log)
{
    return cnc_micro_rate(log->draw_rate, cnc_micro_full_match_episodes(log));
}

static inline float cnc_micro_four_cell_perf(
    float close_mcv_wins,
    float close_mcv_episodes,
    float close_force_wins,
    float close_force_episodes,
    float medium_mcv_wins,
    float medium_mcv_episodes,
    float medium_force_wins,
    float medium_force_episodes)
{
    const float close_mcv = cnc_micro_rate(close_mcv_wins, close_mcv_episodes);
    const float close_force = cnc_micro_rate(close_force_wins, close_force_episodes);
    const float medium_mcv = cnc_micro_rate(medium_mcv_wins, medium_mcv_episodes);
    const float medium_force = cnc_micro_rate(medium_force_wins, medium_force_episodes);
    return 0.25f * (close_mcv + close_force + medium_mcv + medium_force);
}

static inline float cnc_micro_easy_balanced_perf(const Log* log)
{
    return cnc_micro_four_cell_perf(
        log->easy_close_mcv_wins,
        log->easy_close_mcv_episodes,
        log->easy_close_force_wins,
        log->easy_close_force_episodes,
        log->easy_medium_mcv_wins,
        log->easy_medium_mcv_episodes,
        log->easy_medium_force_wins,
        log->easy_medium_force_episodes);
}

static inline float cnc_micro_normal_balanced_perf(const Log* log)
{
    return cnc_micro_four_cell_perf(
        log->normal_close_mcv_wins,
        log->normal_close_mcv_episodes,
        log->normal_close_force_wins,
        log->normal_close_force_episodes,
        log->normal_medium_mcv_wins,
        log->normal_medium_mcv_episodes,
        log->normal_medium_force_wins,
        log->normal_medium_force_episodes);
}

static inline float cnc_micro_difficulty_episodes(const Log* log)
{
    return log->easy_close_mcv_episodes
        + log->easy_close_force_episodes
        + log->easy_medium_mcv_episodes
        + log->easy_medium_force_episodes
        + log->normal_close_mcv_episodes
        + log->normal_close_force_episodes
        + log->normal_medium_mcv_episodes
        + log->normal_medium_force_episodes;
}

static inline float cnc_micro_normal_episode_share(const Log* log)
{
    const float normal = log->normal_close_mcv_episodes
        + log->normal_close_force_episodes
        + log->normal_medium_mcv_episodes
        + log->normal_medium_force_episodes;
    return cnc_micro_rate(normal, cnc_micro_difficulty_episodes(log));
}

static inline float cnc_micro_balanced_perf(const Log* log)
{
    return 0.5f
        * (cnc_micro_easy_balanced_perf(log) + cnc_micro_normal_balanced_perf(log));
}

/* Win rate restricted to constrained 2300-credit starts. */
/* Share of full matches won with a real economy behind them. balanced_perf cannot tell a played-out
   game from a rush, so optimising it produced a rusher; this is the objective the sweep should
   maximise instead. */
/* Share of full matches won while satisfying every criterion: a real mining economy and the
   required armour. This is the sweep objective. Win rate alone selected a rusher; grading on
   income alone selected a strong economy that never built a tank. */
static inline float cnc_micro_full_perf(const Log* log)
{
    return cnc_micro_rate(log->full_wins, cnc_micro_full_match_episodes(log));
}

static inline float cnc_micro_qualified_loss_rate(const Log* log)
{
    return cnc_micro_rate(log->qualified_losses, cnc_micro_full_match_episodes(log));
}

/* Of the episodes that both reached and used armour, how often did the policy convert that state
   into a full win rather than merely receiving the softer qualified-loss terminal reward? */
static inline float cnc_micro_qualified_loss_conversion(const Log* log)
{
    return cnc_micro_rate(log->full_wins, log->full_wins + log->qualified_losses);
}


static inline float cnc_micro_constrained_win_rate(const Log* log)
{
    return cnc_micro_rate(log->constrained_wins, log->constrained_episodes);
}

static inline float cnc_micro_constrained_episode_share(const Log* log)
{
    return cnc_micro_rate(log->constrained_episodes, cnc_micro_full_match_episodes(log));
}

static inline float cnc_micro_starting_force_episode_share(const Log* log)
{
    return cnc_micro_rate(
        log->close_force_episodes + log->medium_force_episodes,
        cnc_micro_full_match_episodes(log));
}

static inline uint8_t cnc_micro_action_value(float value, uint16_t size)
{
    if (!isfinite(value) || value < 0.0f || value >= (float)size) return UINT8_MAX;
    return (uint8_t)value;
}

static inline void cnc_micro_decode_actions(CncMicro* env)
{
    static const uint16_t abi9_sizes[TD_MICRO_ABI9_ACTION_HEAD_COUNT] = {12, 65, TD_MICRO_POLICY_PRODUCT_COUNT, 4, 64, 64, 64};
    static const uint16_t abi13_sizes[TD_MICRO_ACTION_HEAD_COUNT] = {12, 65, 65, 65};
    for (int agent = 0; agent < env->num_agents; ++agent) {
        const float* input = &env->actions[(size_t)agent * env->action_head_count];
        uint8_t* output = (uint8_t*)env->decoded_actions + (size_t)agent * env->policy_action_size;
        for (uint32_t head = 0; head < env->action_head_count; ++head) {
            const uint16_t size = env->action_abi == 9
                ? abi9_sizes[head]
                : env->action_abi == 14
                    ? (head < TD_MICRO_ABI9_ACTION_HEAD_COUNT ? abi9_sizes[head] : 2)
                    : abi13_sizes[head];
            output[head] = cnc_micro_action_value(input[head], size);
        }
    }
}

static inline int cnc_micro_write_win_trace(CncMicro* env, int agent)
{
    static const uint8_t magic[8] = {'T', 'D', 'M', 'W', 'I', 'N', '0', '4'};
    char path[4096];
    const unsigned long long serial = (unsigned long long)env->win_trace_serial++;
    const int path_size = snprintf(
        path,
        sizeof(path),
        "%s-b%u-a%d-w%llu.bin",
        env->win_trace_prefix,
        env->rng,
        agent,
        serial);
    if (path_size < 0 || (size_t)path_size >= sizeof(path)) return 0;

    uint8_t ruleset_hash[TD_MICRO_RULESET_HASH_SIZE];
    const uint32_t action_count = env->episode_trace_lengths[agent];
    const uint32_t buffer_index = env->rng;
    const uint32_t agent_index = (uint32_t)agent;
    if (td_micro_ruleset_hash(ruleset_hash, sizeof(ruleset_hash)) != sizeof(ruleset_hash)) return 0;

    FILE* output = fopen(path, "wb");
    if (output == NULL) return 0;
    const int write_ok = fwrite(magic, 1, sizeof(magic), output) == sizeof(magic)
        && fwrite(&(uint32_t){CNC_MICRO_WIN_TRACE_VERSION}, sizeof(uint32_t), 1, output) == 1
        && fwrite(&(uint32_t){(uint32_t)env->action_abi}, sizeof(uint32_t), 1, output) == 1
        && fwrite(&action_count, sizeof(action_count), 1, output) == 1
        && fwrite(&env->seeds[agent], sizeof(env->seeds[agent]), 1, output) == 1
        && fwrite(&env->max_decisions, sizeof(env->max_decisions), 1, output) == 1
        && fwrite(&buffer_index, sizeof(buffer_index), 1, output) == 1
        && fwrite(&agent_index, sizeof(agent_index), 1, output) == 1
        && fwrite(&env->reward_config, sizeof(env->reward_config), 1, output) == 1
        && fwrite(ruleset_hash, 1, sizeof(ruleset_hash), output) == sizeof(ruleset_hash)
        && fwrite(
            (const uint8_t*)env->episode_action_traces
                + (size_t)agent * env->max_decisions * env->policy_action_size,
            env->policy_action_size,
            action_count,
            output) == action_count;
    const int close_ok = fclose(output) == 0;
    const int ok = write_ok && close_ok;
    if (!ok) {
        fprintf(stderr, "cnc_micro: failed to write win trace %s\n", path);
        return 0;
    }
    fprintf(stderr, "cnc_micro: wrote winning rollout %s (%u actions)\n", path, action_count);
    return 1;
}

static inline void cnc_micro_accumulate_completed_episodes(
    CncMicro* env,
    const TdMicroBatchStatsV2* current,
    const TdMicroBatchMetrics* metrics)
{
    const uint64_t episodes = current->episodes - env->logged_stats.episodes;
    if (episodes == 0) return;

    const uint64_t close_episodes = current->close_episodes - env->logged_stats.close_episodes;
    const uint64_t close_wins = current->close_wins - env->logged_stats.close_wins;
    const uint64_t close_losses = current->close_losses - env->logged_stats.close_losses;
    const uint64_t medium_episodes = current->medium_episodes - env->logged_stats.medium_episodes;
    const uint64_t medium_wins = current->medium_wins - env->logged_stats.medium_wins;
    const uint64_t medium_losses = current->medium_losses - env->logged_stats.medium_losses;
    const uint64_t close_mcv_episodes =
        current->close_mcv_episodes - env->logged_stats.close_mcv_episodes;
    const uint64_t close_mcv_wins =
        current->close_mcv_wins - env->logged_stats.close_mcv_wins;
    const uint64_t close_force_episodes =
        current->close_force_episodes - env->logged_stats.close_force_episodes;
    const uint64_t close_force_wins =
        current->close_force_wins - env->logged_stats.close_force_wins;
    const uint64_t medium_mcv_episodes =
        current->medium_mcv_episodes - env->logged_stats.medium_mcv_episodes;
    const uint64_t medium_mcv_wins =
        current->medium_mcv_wins - env->logged_stats.medium_mcv_wins;
    const uint64_t full_wins =
        current->full_wins - env->logged_stats.full_wins;
    const uint64_t constrained_episodes =
        current->constrained_episodes - env->logged_stats.constrained_episodes;
    const uint64_t constrained_wins =
        current->constrained_wins - env->logged_stats.constrained_wins;
    const uint64_t build_order_violations =
        current->build_order_violations - env->logged_stats.build_order_violations;
    const uint64_t attacks_attempted =
        current->attacks_attempted - env->logged_stats.attacks_attempted;
    const uint64_t attacks_applied =
        current->attacks_applied - env->logged_stats.attacks_applied;
    const uint64_t medium_force_episodes =
        current->medium_force_episodes - env->logged_stats.medium_force_episodes;
    const uint64_t medium_force_wins =
        current->medium_force_wins - env->logged_stats.medium_force_wins;
    const uint64_t full_match_episodes = close_episodes + medium_episodes;
    const uint64_t full_match_wins = close_wins + medium_wins;
    const uint64_t full_match_losses = close_losses + medium_losses;
    const uint64_t full_match_decided = full_match_wins + full_match_losses;
    const uint64_t full_match_draws = full_match_episodes >= full_match_decided
        ? full_match_episodes - full_match_decided
        : 0;
    env->log.perf += (float)full_match_wins;
    env->log.episode_length +=
        (float)(current->episode_decisions - env->logged_stats.episode_decisions);
    env->log.loss_rate += (float)full_match_losses;
    env->log.draw_rate += (float)full_match_draws;
    env->log.invalid_actions +=
        (float)(current->completed_invalid_actions - env->logged_stats.completed_invalid_actions);
    env->log.invalid_action_penalty +=
        (float)(current->invalid_action_penalty - env->logged_stats.invalid_action_penalty);
    env->log.building_limit_losses +=
        (float)(current->building_limit_losses - env->logged_stats.building_limit_losses);
    env->log.failures += (float)(current->failures - env->logged_stats.failures);
    const uint64_t gunners_built = metrics->player_e1_built - env->logged_metrics.player_e1_built;
    const uint64_t rocket_soldiers_built =
        metrics->player_e3_built - env->logged_metrics.player_e3_built;
    const uint64_t harvesters_spawned =
        metrics->player_harvesters_spawned - env->logged_metrics.player_harvesters_spawned;
    env->log.units_built += (float)(gunners_built + rocket_soldiers_built + harvesters_spawned);
    env->log.gunners_built += (float)gunners_built;
    env->log.rocket_soldiers_built +=
        (float)rocket_soldiers_built;
    env->log.unit_kills +=
        (float)(metrics->player_unit_kills - env->logged_metrics.player_unit_kills);
    env->log.unit_losses +=
        (float)(metrics->player_unit_losses - env->logged_metrics.player_unit_losses);
    env->log.buildings_lost +=
        (float)(metrics->player_buildings_lost - env->logged_metrics.player_buildings_lost);
    env->log.buildings_destroyed +=
        (float)(metrics->opponent_buildings_lost - env->logged_metrics.opponent_buildings_lost);
    env->log.enemy_attack_orders +=
        (float)(metrics->enemy_attack_orders - env->logged_metrics.enemy_attack_orders);
    env->log.power_plant_milestones +=
        (float)(metrics->power_plant_milestones - env->logged_metrics.power_plant_milestones);
    env->log.barracks_milestones +=
        (float)(metrics->barracks_milestones - env->logged_metrics.barracks_milestones);
    env->log.refineries_built +=
        (float)(metrics->player_refineries_built - env->logged_metrics.player_refineries_built);
    env->log.weapons_factories_built += (float)(
        metrics->player_weapons_factories_built - env->logged_metrics.player_weapons_factories_built);
    env->log.medium_tanks_built +=
        (float)(metrics->player_medium_tanks_built - env->logged_metrics.player_medium_tanks_built);
    env->log.tank_shots +=
        (float)(metrics->player_tank_shots - env->logged_metrics.player_tank_shots);
    env->log.tank_kills +=
        (float)(metrics->player_tank_kills - env->logged_metrics.player_tank_kills);
    env->log.harvesters_spawned += (float)harvesters_spawned;
    env->log.tiberium_income +=
        (float)(metrics->player_tiberium_income - env->logged_metrics.player_tiberium_income);
    env->log.refinery_milestones +=
        (float)(metrics->refinery_milestones - env->logged_metrics.refinery_milestones);
    env->log.first_delivery_milestones += (float)(
        metrics->first_delivery_milestones - env->logged_metrics.first_delivery_milestones);
    env->log.first_tank_milestones += (float)(
        metrics->first_tank_milestones - env->logged_metrics.first_tank_milestones);
    env->log.first_tank_shot_milestones += (float)(
        metrics->first_tank_shot_milestones - env->logged_metrics.first_tank_shot_milestones);
    env->log.qualified_losses +=
        (float)(metrics->qualified_losses - env->logged_metrics.qualified_losses);
    env->log.player_e1_attack_orders +=
        (float)(metrics->player_e1_attack_orders - env->logged_metrics.player_e1_attack_orders);
    env->log.player_e1_infantry_targets += (float)(
        metrics->player_e1_infantry_targets - env->logged_metrics.player_e1_infantry_targets);
    env->log.player_e3_attack_orders +=
        (float)(metrics->player_e3_attack_orders - env->logged_metrics.player_e3_attack_orders);
    env->log.player_e3_vehicle_targets += (float)(
        metrics->player_e3_vehicle_targets - env->logged_metrics.player_e3_vehicle_targets);
    env->log.player_tank_attack_orders +=
        (float)(metrics->player_tank_attack_orders - env->logged_metrics.player_tank_attack_orders);
    env->log.player_tank_e3_targets +=
        (float)(metrics->player_tank_e3_targets - env->logged_metrics.player_tank_e3_targets);
    env->log.player_tank_losses +=
        (float)(metrics->player_tank_losses - env->logged_metrics.player_tank_losses);
    env->log.player_tank_losses_to_e3 += (float)(
        metrics->player_tank_losses_to_e3 - env->logged_metrics.player_tank_losses_to_e3);
    env->log.close_episodes += (float)close_episodes;
    env->log.close_wins += (float)close_wins;
    env->log.close_losses += (float)close_losses;
    env->log.medium_episodes += (float)medium_episodes;
    env->log.medium_wins += (float)medium_wins;
    env->log.medium_losses += (float)medium_losses;
    env->log.close_mcv_episodes += (float)close_mcv_episodes;
    env->log.close_mcv_wins += (float)close_mcv_wins;
    env->log.close_force_episodes += (float)close_force_episodes;
    env->log.close_force_wins += (float)close_force_wins;
    env->log.full_wins += (float)full_wins;
    env->log.constrained_episodes += (float)constrained_episodes;
    env->log.constrained_wins += (float)constrained_wins;
    env->log.build_order_violations += (float)build_order_violations;
    env->log.attacks_attempted += (float)attacks_attempted;
    env->log.attacks_applied += (float)attacks_applied;
    env->log.medium_mcv_episodes += (float)medium_mcv_episodes;
    env->log.medium_mcv_wins += (float)medium_mcv_wins;
    env->log.medium_force_episodes += (float)medium_force_episodes;
    env->log.medium_force_wins += (float)medium_force_wins;
    env->log.easy_close_mcv_episodes += (float)(
        current->easy_close_mcv_episodes - env->logged_stats.easy_close_mcv_episodes);
    env->log.easy_close_mcv_wins += (float)(
        current->easy_close_mcv_wins - env->logged_stats.easy_close_mcv_wins);
    env->log.easy_close_force_episodes += (float)(
        current->easy_close_force_episodes - env->logged_stats.easy_close_force_episodes);
    env->log.easy_close_force_wins += (float)(
        current->easy_close_force_wins - env->logged_stats.easy_close_force_wins);
    env->log.easy_medium_mcv_episodes += (float)(
        current->easy_medium_mcv_episodes - env->logged_stats.easy_medium_mcv_episodes);
    env->log.easy_medium_mcv_wins += (float)(
        current->easy_medium_mcv_wins - env->logged_stats.easy_medium_mcv_wins);
    env->log.easy_medium_force_episodes += (float)(
        current->easy_medium_force_episodes - env->logged_stats.easy_medium_force_episodes);
    env->log.easy_medium_force_wins += (float)(
        current->easy_medium_force_wins - env->logged_stats.easy_medium_force_wins);
    env->log.normal_close_mcv_episodes += (float)(
        current->normal_close_mcv_episodes - env->logged_stats.normal_close_mcv_episodes);
    env->log.normal_close_mcv_wins += (float)(
        current->normal_close_mcv_wins - env->logged_stats.normal_close_mcv_wins);
    env->log.normal_close_force_episodes += (float)(
        current->normal_close_force_episodes - env->logged_stats.normal_close_force_episodes);
    env->log.normal_close_force_wins += (float)(
        current->normal_close_force_wins - env->logged_stats.normal_close_force_wins);
    env->log.normal_medium_mcv_episodes += (float)(
        current->normal_medium_mcv_episodes - env->logged_stats.normal_medium_mcv_episodes);
    env->log.normal_medium_mcv_wins += (float)(
        current->normal_medium_mcv_wins - env->logged_stats.normal_medium_mcv_wins);
    env->log.normal_medium_force_episodes += (float)(
        current->normal_medium_force_episodes - env->logged_stats.normal_medium_force_episodes);
    env->log.normal_medium_force_wins += (float)(
        current->normal_medium_force_wins - env->logged_stats.normal_medium_force_wins);
    env->log.n += (float)episodes;
    env->logged_stats = *current;
    env->logged_metrics = *metrics;
}

static inline void cnc_micro_log_episodes(CncMicro* env)
{
    TdMicroBatchStatsV2 current;
    TdMicroBatchMetrics metrics;
    if (!td_micro_batch_stats_v2(env->batch, &current)
        || !td_micro_batch_metrics(env->batch, &metrics)) return;
    cnc_micro_accumulate_completed_episodes(env, &current, &metrics);
}

static inline void c_reset(CncMicro* env)
{
    memset(env->rewards, 0, (size_t)env->num_agents * sizeof(*env->rewards));
    memset(env->terminals, 0, (size_t)env->num_agents * sizeof(*env->terminals));
    memset(env->episode_returns, 0, (size_t)env->num_agents * sizeof(*env->episode_returns));
    if (env->episode_trace_lengths != NULL) {
        memset(
            env->episode_trace_lengths,
            0,
            (size_t)env->num_agents * sizeof(*env->episode_trace_lengths));
    }
    memset(&env->logged_stats, 0, sizeof(env->logged_stats));
    memset(&env->logged_metrics, 0, sizeof(env->logged_metrics));
    int ok = env->batch != NULL
        && td_micro_reset_batch(env->batch, env->seeds, (uint32_t)env->num_agents);
    if (ok) {
        if (env->action_abi == 9) {
            ok = td_micro_observe_batch_abi9(
                env->batch,
                env->observations,
                env->action_mask,
                (uint32_t)env->num_agents);
        } else if (env->action_abi == 14) {
            ok = td_micro_observe_batch_abi14(
                env->batch,
                env->observations,
                env->action_mask,
                (uint32_t)env->num_agents);
        } else {
            ok = td_micro_observe_batch(
                env->batch,
                env->observations,
                env->action_mask,
                (uint32_t)env->num_agents);
        }
    }
    if (!ok) {
        env->log.start_failures += (float)env->num_agents;
        env->log.n += (float)env->num_agents;
    }
}

static inline void c_step(CncMicro* env)
{
    cnc_micro_decode_actions(env);
    if (env->episode_action_traces != NULL) {
        for (int agent = 0; agent < env->num_agents; ++agent) {
            const uint32_t length = env->episode_trace_lengths[agent];
            if (length < env->max_decisions) {
                memcpy(
                    (uint8_t*)env->episode_action_traces
                        + ((size_t)agent * env->max_decisions + length) * env->policy_action_size,
                    (const uint8_t*)env->decoded_actions + (size_t)agent * env->policy_action_size,
                    env->policy_action_size);
                env->episode_trace_lengths[agent] = length + 1;
            }
        }
    }
    int ok;
    if (env->action_abi == 9) {
        ok = td_micro_step_batch_abi9(
            env->batch,
            (const TdMicroPolicyActionAbi9*)env->decoded_actions,
            env->observations,
            env->action_mask,
            env->rewards,
            env->terminal_bytes,
            (uint32_t)env->num_agents);
    } else if (env->action_abi == 14) {
        ok = td_micro_step_batch_abi14(
            env->batch,
            (const TdMicroPolicyActionAbi14*)env->decoded_actions,
            env->observations,
            env->action_mask,
            env->rewards,
            env->terminal_bytes,
            (uint32_t)env->num_agents);
    } else {
        ok = td_micro_step_batch(
            env->batch,
            (const TdMicroPolicyAction*)env->decoded_actions,
            env->observations,
            env->action_mask,
            env->rewards,
            env->terminal_bytes,
            (uint32_t)env->num_agents);
    }
    if (!ok) {
        for (int index = 0; index < env->num_agents; ++index) {
            env->rewards[index] = 0.0f;
            env->terminals[index] = 1.0f;
        }
        env->log.failures += (float)env->num_agents;
        env->log.n += (float)env->num_agents;
        return;
    }
    for (int index = 0; index < env->num_agents; ++index) {
        env->terminals[index] = (float)env->terminal_bytes[index];
        env->episode_returns[index] += env->rewards[index];
        if (env->terminal_bytes[index]) {
            env->log.episode_return += env->episode_returns[index];
            if (env->episode_action_traces != NULL && env->rewards[index] == 1.0f) {
                (void)cnc_micro_write_win_trace(env, index);
            }
            if (env->episode_trace_lengths != NULL) env->episode_trace_lengths[index] = 0;
            env->episode_returns[index] = 0.0f;
        }
    }
    cnc_micro_log_episodes(env);
}

static inline void c_render(CncMicro* env)
{
    (void)env;
}

static inline void c_close(CncMicro* env)
{
    td_micro_batch_destroy(env->batch);
    free(env->decoded_actions);
    free(env->terminal_bytes);
    free(env->seeds);
    free(env->episode_returns);
    free(env->episode_action_traces);
    free(env->episode_trace_lengths);
    env->batch = NULL;
    env->decoded_actions = NULL;
    env->terminal_bytes = NULL;
    env->seeds = NULL;
    env->episode_returns = NULL;
    env->episode_action_traces = NULL;
    env->episode_trace_lengths = NULL;
}

#endif
