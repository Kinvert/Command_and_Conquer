#include "td_micro_api.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Options {
    const char* checkpoint_path;
    const char* state_trace_path;
    const char* action_trace_path;
    uint64_t environment_seed;
    uint64_t sampling_seed;
    int sampled;
    int quiet_actions;
} Options;

static void print_hash(const uint8_t hash[TD_MICRO_RULESET_HASH_SIZE])
{
    for (size_t index = 0; index < TD_MICRO_RULESET_HASH_SIZE; ++index) printf("%02x", hash[index]);
}

static int parse_u64(const char* text, uint64_t* output)
{
    char* end = NULL;
    errno = 0;
    unsigned long long value = strtoull(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0') return 0;
    *output = (uint64_t)value;
    return 1;
}

static int parse_options(int argc, char** argv, Options* options)
{
    if (argc < 2) return 0;
    *options = (Options){.checkpoint_path = argv[1], .environment_seed = 1};
    for (int argument = 2; argument < argc; ++argument) {
        if (strcmp(argv[argument], "--seed") == 0) {
            if (++argument >= argc || !parse_u64(argv[argument], &options->environment_seed)) return 0;
        } else if (strcmp(argv[argument], "--sample-seed") == 0) {
            if (++argument >= argc || !parse_u64(argv[argument], &options->sampling_seed)) return 0;
            options->sampled = 1;
        } else if (strcmp(argv[argument], "--action-trace") == 0) {
            if (++argument >= argc) return 0;
            options->action_trace_path = argv[argument];
        } else if (strcmp(argv[argument], "--quiet-actions") == 0) {
            options->quiet_actions = 1;
        } else if (options->state_trace_path == NULL) {
            options->state_trace_path = argv[argument];
        } else {
            return 0;
        }
    }
    return 1;
}

static int policy_act(
    TdMicroPolicy* policy,
    const uint8_t* observation,
    const uint8_t* mask,
    int sampled,
    TdMicroPolicyAction* action)
{
    if (sampled) {
        return td_micro_policy_act_sampled(
            policy,
            observation,
            TD_MICRO_OBSERVATION_SIZE,
            mask,
            TD_MICRO_ACTION_MASK_SIZE,
            action);
    }
    return td_micro_policy_act(
        policy,
        observation,
        TD_MICRO_OBSERVATION_SIZE,
        mask,
        TD_MICRO_ACTION_MASK_SIZE,
        action);
}

int main(int argc, char** argv)
{
    Options options;
    if (!parse_options(argc, argv, &options)) {
        fprintf(
            stderr,
            "usage: %s CHECKPOINT.bin [STATE_TRACE.bin] [--seed N] [--sample-seed N] "
            "[--action-trace ACTION_TRACE.bin] [--quiet-actions]\n",
            argv[0]);
        return 2;
    }
    if (td_micro_policy_weight_count() != TD_MICRO_POLICY_WEIGHT_COUNT
        || td_micro_policy_checkpoint_size() != TD_MICRO_POLICY_CHECKPOINT_SIZE) {
        return 1;
    }

    FILE* file = fopen(options.checkpoint_path, "rb");
    uint32_t checkpoint_size = 0;
    uint8_t* checkpoint = NULL;
    int checkpoint_ok = file != NULL
        && fseek(file, 0, SEEK_END) == 0;
    long checkpoint_size_long = checkpoint_ok ? ftell(file) : -1;
    checkpoint_ok = checkpoint_size_long > 0
        && (uint64_t)checkpoint_size_long <= UINT32_MAX
        && fseek(file, 0, SEEK_SET) == 0;
    if (checkpoint_ok) {
        checkpoint_size = (uint32_t)checkpoint_size_long;
        checkpoint_ok = td_micro_policy_hidden_for_checkpoint_size(checkpoint_size) != 0;
    }
    if (checkpoint_ok) checkpoint = malloc(checkpoint_size);
    checkpoint_ok = checkpoint_ok && checkpoint != NULL
        && fread(checkpoint, 1, checkpoint_size, file) == checkpoint_size
        && fgetc(file) == EOF;
    if (file != NULL) fclose(file);

    TdMicroBatch* batch = td_micro_batch_create(1, TD_MICRO_TRAINING_MAX_DECISIONS);
    const uint64_t seed = options.environment_seed;
    uint8_t observation[TD_MICRO_OBSERVATION_SIZE];
    uint8_t mask[TD_MICRO_ACTION_MASK_SIZE];
    TdMicroPolicyAction first;
    TdMicroPolicyAction second;
    uint8_t hash[TD_MICRO_RULESET_HASH_SIZE];
    uint8_t rules_hash[TD_MICRO_RULESET_HASH_SIZE];
    TdMicroPolicy* policy = checkpoint_ok
        ? td_micro_policy_create(checkpoint, checkpoint_size)
        : NULL;
    FILE* state_trace = options.state_trace_path != NULL ? fopen(options.state_trace_path, "wb") : NULL;
    FILE* action_trace = options.action_trace_path != NULL ? fopen(options.action_trace_path, "wb") : NULL;
    int ok = checkpoint_ok && batch != NULL && policy != NULL
        && (options.state_trace_path == NULL || state_trace != NULL)
        && (options.action_trace_path == NULL || action_trace != NULL)
        && td_micro_reset_batch(batch, &seed, 1)
        && td_micro_observe_batch(batch, observation, mask, 1)
        && (!options.sampled || td_micro_policy_seed_sampling(policy, options.sampling_seed))
        && policy_act(policy, observation, mask, options.sampled, &first)
        && td_micro_policy_reset(policy)
        && (!options.sampled || td_micro_policy_seed_sampling(policy, options.sampling_seed))
        && policy_act(policy, observation, mask, options.sampled, &second)
        && memcmp(&first, &second, sizeof(first)) == 0
        && td_micro_policy_checkpoint_sha256(policy, hash, sizeof(hash)) == sizeof(hash)
        && td_micro_ruleset_hash(rules_hash, sizeof(rules_hash)) == sizeof(rules_hash);

    if (ok) {
        printf("checkpoint=");
        print_hash(hash);
        printf(" hidden=%u rules=", td_micro_policy_hidden_size(policy));
        print_hash(rules_hash);
        printf(" mode=%s environment_seed=%llu sampling_seed=%llu action=%u,%u,%u,%u\n",
               options.sampled ? "sampled" : "greedy",
               (unsigned long long)options.environment_seed,
               (unsigned long long)options.sampling_seed,
               first.command,
               first.arg0,
               first.arg1,
               first.arg2);

        float reward = 0.0f;
        uint8_t terminal = 0;
        uint64_t command_counts[TD_MICRO_POLICY_COMMAND_COUNT] = {0};
        TdMicroPolicyAction previous_action = {0};
        int has_previous_action = 0;
        uint32_t first_command_decision[TD_MICRO_POLICY_COMMAND_COUNT];
        for (size_t index = 0; index < TD_MICRO_POLICY_COMMAND_COUNT; ++index) {
            first_command_decision[index] = UINT32_MAX;
        }
        uint32_t positive_rewards = 0;
        float reward_sum = 0.0f;
        ok = td_micro_policy_reset(policy)
            && (!options.sampled || td_micro_policy_seed_sampling(policy, options.sampling_seed))
            && td_micro_reset_batch(batch, &seed, 1)
            && td_micro_observe_batch(batch, observation, mask, 1);
        uint32_t decisions = 0;
        while (ok && terminal == 0 && decisions <= TD_MICRO_TRAINING_MAX_DECISIONS) {
            TdMicroPolicyAction action;
            ok = (state_trace == NULL
                    || (fwrite(observation, 1, sizeof(observation), state_trace) == sizeof(observation)
                        && fwrite(mask, 1, sizeof(mask), state_trace) == sizeof(mask)))
                && policy_act(policy, observation, mask, options.sampled, &action)
                && action.command < TD_MICRO_POLICY_COMMAND_COUNT;
            if (!ok) break;
            const uint8_t action_record[4] = {
                action.command,
                action.arg0,
                action.arg1,
                action.arg2,
            };
            ok = action_trace == NULL || fwrite(action_record, 1, sizeof(action_record), action_trace) == sizeof(action_record);
            if (!ok) break;
            if (!options.quiet_actions && action.command != 0
                && (!has_previous_action || memcmp(&action, &previous_action, sizeof(action)) != 0)) {
                printf("decision_action=%u:%u,%u,%u,%u\n",
                       decisions,
                       action.command,
                       action.arg0,
                       action.arg1,
                       action.arg2);
            }
            previous_action = action;
            has_previous_action = 1;
            if (first_command_decision[action.command] == UINT32_MAX) {
                first_command_decision[action.command] = decisions;
            }
            ++command_counts[action.command];
            ok = td_micro_step_batch(batch, &action, observation, mask, &reward, &terminal, 1);
            if (reward > 0.0f) ++positive_rewards;
            reward_sum += reward;
            ++decisions;
        }

        TdMicroBatchStats stats = {0};
        TdMicroBatchStatsV2 stats_v2 = {0};
        TdMicroBatchMetrics metrics = {0};
        ok = ok && terminal != 0 && td_micro_batch_stats(batch, &stats)
            && td_micro_batch_stats_v2(batch, &stats_v2)
            && td_micro_batch_metrics(batch, &metrics)
            && stats.episodes == 1 && stats.failures == 0;
        if (ok) {
            printf("episode decisions=%u reward=%.1f reward_sum=%.2f positive_rewards=%u "
                   "wins=%llu full_wins=%llu losses=%llu draws=%llu "
                   "close=%llu,%llu,%llu medium=%llu,%llu,%llu "
                   "invalid=%llu building_limit_losses=%llu infantry_limit_losses=%llu "
                   "invalid_streak_losses=%llu failures=%llu commands=",
                   decisions,
                   reward,
                   reward_sum,
                   positive_rewards,
                   (unsigned long long)stats.wins,
                   (unsigned long long)stats_v2.full_wins,
                   (unsigned long long)stats.losses,
                   (unsigned long long)stats.draws,
                   (unsigned long long)stats.close_episodes,
                   (unsigned long long)stats.close_wins,
                   (unsigned long long)stats.close_losses,
                   (unsigned long long)stats.medium_episodes,
                   (unsigned long long)stats.medium_wins,
                   (unsigned long long)stats.medium_losses,
                   (unsigned long long)stats.invalid_actions,
                   (unsigned long long)stats.building_limit_losses,
                   (unsigned long long)stats.infantry_limit_losses,
                   (unsigned long long)stats.invalid_streak_losses,
                   (unsigned long long)stats.failures);
            for (size_t index = 0; index < TD_MICRO_POLICY_COMMAND_COUNT; ++index) {
                printf("%s%llu", index == 0 ? "" : ",", (unsigned long long)command_counts[index]);
            }
            printf(" first=");
            for (size_t index = 0; index < TD_MICRO_POLICY_COMMAND_COUNT; ++index) {
                if (first_command_decision[index] == UINT32_MAX) {
                    printf("%s-", index == 0 ? "" : ",");
                } else {
                    printf("%s%u", index == 0 ? "" : ",", first_command_decision[index]);
                }
            }
            putchar('\n');
            printf("metrics gunners_built=%llu rocket_soldiers_built=%llu "
                   "opponent_gunners_built=%llu opponent_rocket_soldiers_built=%llu "
                   "unit_kills=%llu opponent_unit_kills=%llu "
                   "unit_losses=%llu opponent_unit_losses=%llu "
                   "buildings_lost=%llu opponent_buildings_lost=%llu "
                   "enemy_attack_orders=%llu accepted_train_actions=%llu rejected_train_actions=%llu "
                   "refineries_built=%llu weapons_factories_built=%llu medium_tanks_built=%llu "
                   "tank_shots=%llu tank_kills=%llu tiberium_income=%llu\n",
                   (unsigned long long)metrics.player_e1_built,
                   (unsigned long long)metrics.player_e3_built,
                   (unsigned long long)metrics.opponent_e1_built,
                   (unsigned long long)metrics.opponent_e3_built,
                   (unsigned long long)metrics.player_unit_kills,
                   (unsigned long long)metrics.opponent_unit_kills,
                   (unsigned long long)metrics.player_unit_losses,
                   (unsigned long long)metrics.opponent_unit_losses,
                   (unsigned long long)metrics.player_buildings_lost,
                   (unsigned long long)metrics.opponent_buildings_lost,
                   (unsigned long long)metrics.enemy_attack_orders,
                   (unsigned long long)metrics.accepted_train_actions,
                   (unsigned long long)metrics.rejected_train_actions,
                   (unsigned long long)metrics.player_refineries_built,
                   (unsigned long long)metrics.player_weapons_factories_built,
                   (unsigned long long)metrics.player_medium_tanks_built,
                   (unsigned long long)metrics.player_tank_shots,
                   (unsigned long long)metrics.player_tank_kills,
                   (unsigned long long)metrics.player_tiberium_income);
        }
    }
    if (state_trace != NULL) fclose(state_trace);
    if (action_trace != NULL) fclose(action_trace);
    td_micro_policy_destroy(policy);
    td_micro_batch_destroy(batch);
    free(checkpoint);
    return ok ? 0 : 1;
}
