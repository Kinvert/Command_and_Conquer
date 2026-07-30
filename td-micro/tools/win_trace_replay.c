#include "td_micro_api.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WIN_TRACE_VERSION 4u
#define LEGACY_REWARD_CONFIG_FLOATS 8u
#define VERSION_3_REWARD_CONFIG_WORDS 21u

typedef struct WinTrace {
    uint32_t action_abi;
    uint32_t action_count;
    uint64_t seed;
    uint32_t max_decisions;
    uint32_t buffer_index;
    uint32_t agent_index;
    TdMicroRewardConfig reward_config;
    size_t action_size;
    void* actions;
} WinTrace;

typedef struct ReplayResult {
    TdMicroBatchStats stats;
    TdMicroBatchMetrics metrics;
    uint64_t trajectory_hash;
    float terminal_reward;
} ReplayResult;

static uint64_t fnv1a(uint64_t hash, const void* data, size_t size)
{
    const uint8_t* bytes = data;
    for (size_t index = 0; index < size; ++index) {
        hash ^= bytes[index];
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static int read_trace(const char* path, WinTrace* trace)
{
    static const uint8_t magic_prefix[7] = {'T', 'D', 'M', 'W', 'I', 'N', '0'};
    uint8_t magic[8];
    uint8_t recorded_ruleset[TD_MICRO_RULESET_HASH_SIZE];
    uint8_t current_ruleset[TD_MICRO_RULESET_HASH_SIZE];
    uint32_t version = 0;
    FILE* input = fopen(path, "rb");
    if (input == NULL) return 0;

    int ok = fread(magic, 1, sizeof(magic), input) == sizeof(magic)
        && fread(&version, sizeof(version), 1, input) == 1
        && version >= 1
        && version <= WIN_TRACE_VERSION
        && memcmp(magic, magic_prefix, sizeof(magic_prefix)) == 0
        && magic[7] == (uint8_t)('0' + version);
    if (ok) {
        if (version >= 3) {
            ok = fread(&trace->action_abi, sizeof(trace->action_abi), 1, input) == 1;
        } else {
            trace->action_abi = version == 1 ? 9u : TD_MICRO_ABI_VERSION;
        }
    }
    ok = ok
        && (trace->action_abi == 9u
            || trace->action_abi == TD_MICRO_ABI_VERSION
            || trace->action_abi == 14u)
        && fread(&trace->action_count, sizeof(trace->action_count), 1, input) == 1
        && fread(&trace->seed, sizeof(trace->seed), 1, input) == 1
        && fread(&trace->max_decisions, sizeof(trace->max_decisions), 1, input) == 1
        && fread(&trace->buffer_index, sizeof(trace->buffer_index), 1, input) == 1
        && fread(&trace->agent_index, sizeof(trace->agent_index), 1, input) == 1;
    memset(&trace->reward_config, 0, sizeof(trace->reward_config));
    const size_t reward_config_size =
        version == WIN_TRACE_VERSION
            ? sizeof(trace->reward_config)
            : version == 3
                ? VERSION_3_REWARD_CONFIG_WORDS * sizeof(uint32_t)
                : LEGACY_REWARD_CONFIG_FLOATS * sizeof(float);
    ok = ok
        && fread(&trace->reward_config, reward_config_size, 1, input) == 1
        && fread(recorded_ruleset, 1, sizeof(recorded_ruleset), input) == sizeof(recorded_ruleset)
        && td_micro_ruleset_hash(current_ruleset, sizeof(current_ruleset)) == sizeof(current_ruleset)
        && memcmp(recorded_ruleset, current_ruleset, sizeof(current_ruleset)) == 0
        && trace->action_count > 0
        && trace->action_count <= trace->max_decisions
        && td_micro_reward_config_valid(&trace->reward_config);
    if (ok) {
        trace->action_size = trace->action_abi == 9u
            ? sizeof(TdMicroPolicyActionAbi9)
            : trace->action_abi == 14u
                ? sizeof(TdMicroPolicyActionAbi14)
                : sizeof(TdMicroPolicyAction);
        trace->actions = calloc(trace->action_count, trace->action_size);
        ok = trace->actions != NULL
            && fread(
                trace->actions,
                trace->action_size,
                trace->action_count,
                input) == trace->action_count
            && fgetc(input) == EOF;
    }
    if (fclose(input) != 0) ok = 0;
    if (!ok) {
        free(trace->actions);
        memset(trace, 0, sizeof(*trace));
    }
    return ok;
}

static int replay(const WinTrace* trace, ReplayResult* result)
{
    uint8_t* observation = malloc(TD_MICRO_OBSERVATION_SIZE);
    const size_t mask_size = trace->action_abi == 9u
        ? TD_MICRO_ABI9_ACTION_MASK_SIZE
        : trace->action_abi == 14u
            ? TD_MICRO_ABI14_ACTION_MASK_SIZE
            : TD_MICRO_ACTION_MASK_SIZE;
    uint8_t* mask = malloc(mask_size);
    TdMicroBatch* batch = td_micro_batch_create_with_reward_config(
        1,
        trace->max_decisions,
        &trace->reward_config);
    uint8_t terminal = 0;
    float reward = 0.0f;
    uint64_t hash = UINT64_C(14695981039346656037);
    int ok = observation != NULL && mask != NULL && batch != NULL
        && td_micro_reset_batch(batch, &trace->seed, 1);
    if (ok) {
        if (trace->action_abi == 9u) {
            ok = td_micro_observe_batch_abi9(batch, observation, mask, 1);
        } else if (trace->action_abi == 14u) {
            ok = td_micro_observe_batch_abi14(batch, observation, mask, 1);
        } else {
            ok = td_micro_observe_batch(batch, observation, mask, 1);
        }
    }

    for (uint32_t index = 0; ok && index < trace->action_count; ++index) {
        if (terminal != 0) {
            ok = 0;
            break;
        }
        const uint8_t* action = (const uint8_t*)trace->actions + index * trace->action_size;
        if (trace->action_abi == 9u) {
            ok = td_micro_step_batch_abi9(
                batch,
                (const TdMicroPolicyActionAbi9*)action,
                observation,
                mask,
                &reward,
                &terminal,
                1);
        } else if (trace->action_abi == 14u) {
            ok = td_micro_step_batch_abi14(
                batch,
                (const TdMicroPolicyActionAbi14*)action,
                observation,
                mask,
                &reward,
                &terminal,
                1);
        } else {
            ok = td_micro_step_batch(
                batch,
                (const TdMicroPolicyAction*)action,
                observation,
                mask,
                &reward,
                &terminal,
                1);
        }
        hash = fnv1a(hash, action, trace->action_size);
        hash = fnv1a(hash, &reward, sizeof(reward));
        hash = fnv1a(hash, &terminal, sizeof(terminal));
        hash = fnv1a(hash, observation, TD_MICRO_OBSERVATION_SIZE);
    }

    memset(result, 0, sizeof(*result));
    if (ok) {
        result->trajectory_hash = hash;
        result->terminal_reward = reward;
        ok = terminal == 1
            && reward == 1.0f
            && td_micro_batch_stats(batch, &result->stats)
            && td_micro_batch_metrics(batch, &result->metrics)
            && result->stats.episodes == 1
            && result->stats.wins == 1
            && result->stats.losses == 0
            && result->stats.draws == 0
            && result->stats.failures == 0;
    }

    td_micro_batch_destroy(batch);
    free(mask);
    free(observation);
    return ok;
}

int main(int argc, char** argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s WIN_TRACE.bin [WIN_TRACE.bin ...]\n", argv[0]);
        return 2;
    }

    for (int argument = 1; argument < argc; ++argument) {
        WinTrace trace = {0};
        ReplayResult first = {0};
        ReplayResult second = {0};
        int ok = read_trace(argv[argument], &trace)
            && replay(&trace, &first)
            && replay(&trace, &second)
            && memcmp(&first, &second, sizeof(first)) == 0;
        if (!ok) {
            fprintf(stderr, "invalid or non-winning trace: %s\n", argv[argument]);
            free(trace.actions);
            return 1;
        }
        uint64_t command_counts[TD_MICRO_POLICY_COMMAND_COUNT] = {0};
        for (uint32_t index = 0; index < trace.action_count; ++index) {
            const uint8_t command = *((const uint8_t*)trace.actions + index * trace.action_size);
            if (command < TD_MICRO_POLICY_COMMAND_COUNT) {
                ++command_counts[command];
            }
        }
        printf(
            "trace=%s action_abi=%u buffer=%u agent=%u actions=%u reward=%.0f wins=%llu losses=%llu "
            "draws=%llu failures=%llu invalid=%llu gunners_built=%llu "
            "rocket_soldiers_built=%llu unit_kills=%llu unit_losses=%llu "
            "buildings_lost=%llu buildings_destroyed=%llu accepted_train=%llu "
            "rejected_train=%llu enemy_attack_orders=%llu trajectory_hash=%016llx commands=",
            argv[argument],
            trace.action_abi,
            trace.buffer_index,
            trace.agent_index,
            trace.action_count,
            first.terminal_reward,
            (unsigned long long)first.stats.wins,
            (unsigned long long)first.stats.losses,
            (unsigned long long)first.stats.draws,
            (unsigned long long)first.stats.failures,
            (unsigned long long)first.stats.invalid_actions,
            (unsigned long long)first.metrics.player_e1_built,
            (unsigned long long)first.metrics.player_e3_built,
            (unsigned long long)first.metrics.player_unit_kills,
            (unsigned long long)first.metrics.player_unit_losses,
            (unsigned long long)first.metrics.player_buildings_lost,
            (unsigned long long)first.metrics.opponent_buildings_lost,
            (unsigned long long)first.metrics.accepted_train_actions,
            (unsigned long long)first.metrics.rejected_train_actions,
            (unsigned long long)first.metrics.enemy_attack_orders,
            (unsigned long long)first.trajectory_hash);
        for (uint32_t command = 0; command < TD_MICRO_POLICY_COMMAND_COUNT; ++command) {
            printf("%s%llu", command == 0 ? "" : ",", (unsigned long long)command_counts[command]);
        }
        putchar('\n');
        free(trace.actions);
    }
    return 0;
}
