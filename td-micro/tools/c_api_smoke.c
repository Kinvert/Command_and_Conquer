#include "td_micro_api.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(TdMicroBatchMetrics) == 43 * sizeof(uint64_t), "metrics ABI size");

int main(void)
{
    const uint32_t count = 2;
    const uint64_t seeds[2] = {1, 1};
    TdMicroBatch* batch = td_micro_batch_create(count, 4096);
    if (batch == NULL || td_micro_reset_batch(batch, seeds, count) == 0) return 1;

    uint8_t* observations = calloc(count, TD_MICRO_OBSERVATION_SIZE);
    uint8_t* masks = calloc(count, TD_MICRO_ACTION_MASK_SIZE);
    float rewards[2] = {0};
    uint8_t terminals[2] = {0};
    TdMicroPolicyAction actions[2] = {
        {.command = 1, .arg0 = 0, .arg1 = TD_MICRO_POLICY_PAD_TOKEN, .arg2 = TD_MICRO_POLICY_PAD_TOKEN},
        {.command = 0, .arg0 = TD_MICRO_POLICY_PAD_TOKEN, .arg1 = TD_MICRO_POLICY_PAD_TOKEN, .arg2 = TD_MICRO_POLICY_PAD_TOKEN},
    };
    uint8_t digest[32];
    uint8_t abi9_digest[32];
    TdMicroBatchStats stats = {0};
    TdMicroBatchMetrics metrics = {0};

    int ok = observations != NULL && masks != NULL
        && td_micro_abi_version() == TD_MICRO_ABI_VERSION
        && td_micro_player_building_limit() == TD_MICRO_PLAYER_BUILDING_LIMIT
        && td_micro_player_infantry_limit() == TD_MICRO_PLAYER_INFANTRY_LIMIT
        && td_micro_consecutive_invalid_action_limit() == TD_MICRO_CONSECUTIVE_INVALID_ACTION_LIMIT
        && td_micro_training_timeout_frames() == TD_MICRO_TRAINING_TIMEOUT_FRAMES
        && td_micro_training_max_decisions() == TD_MICRO_TRAINING_MAX_DECISIONS
        && td_micro_observe_batch(batch, observations, masks, count)
        && td_micro_step_batch(batch, actions, observations, masks, rewards, terminals, count)
        && td_micro_batch_stats(batch, &stats)
        && td_micro_batch_metrics(batch, &metrics)
        && td_micro_batch_world_digest(batch, 0, digest, sizeof(digest)) == sizeof(digest);
    TdMicroBatch* abi9_batch = td_micro_batch_create(count, 4096);
    uint8_t* abi9_observations = calloc(count, TD_MICRO_OBSERVATION_SIZE);
    uint8_t* abi9_masks = calloc(count, TD_MICRO_ABI9_ACTION_MASK_SIZE);
    float abi9_rewards[2] = {0};
    uint8_t abi9_terminals[2] = {0};
    TdMicroPolicyActionAbi9 abi9_actions[2] = {
        {.command = 1, .actor = 0},
        {.command = 0, .actor = TD_MICRO_POLICY_ACTOR_NONE},
    };
    ok = ok && abi9_batch != NULL && abi9_observations != NULL && abi9_masks != NULL
        && td_micro_action_head_count_abi9() == TD_MICRO_ABI9_ACTION_HEAD_COUNT
        && td_micro_action_mask_size_abi9() == TD_MICRO_ABI9_ACTION_MASK_SIZE
        && td_micro_reset_batch(abi9_batch, seeds, count)
        && td_micro_observe_batch_abi9(abi9_batch, abi9_observations, abi9_masks, count)
        && td_micro_step_batch_abi9(
            abi9_batch,
            abi9_actions,
            abi9_observations,
            abi9_masks,
            abi9_rewards,
            abi9_terminals,
            count)
        && td_micro_batch_world_digest(abi9_batch, 0, abi9_digest, sizeof(abi9_digest)) ==
            sizeof(abi9_digest)
        && memcmp(digest, abi9_digest, sizeof(digest)) == 0;
    if (ok) {
        printf("abi=%u obs=%u mask=%u abi9_mask=%u worlds=%u decisions=%llu digest=",
               td_micro_abi_version(),
               td_micro_observation_size(),
               td_micro_action_mask_size(),
               td_micro_action_mask_size_abi9(),
               td_micro_batch_count(batch),
               (unsigned long long)stats.decisions);
        for (size_t i = 0; i < sizeof(digest); ++i) printf("%02x", digest[i]);
        putchar('\n');
    }

    free(abi9_masks);
    free(abi9_observations);
    td_micro_batch_destroy(abi9_batch);
    free(masks);
    free(observations);
    td_micro_batch_destroy(batch);
    return ok ? 0 : 1;
}
