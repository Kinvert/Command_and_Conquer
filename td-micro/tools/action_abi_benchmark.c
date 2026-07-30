#define _POSIX_C_SOURCE 200809L

#include "td_micro_api.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double seconds(struct timespec start, struct timespec end)
{
    return (double)(end.tv_sec - start.tv_sec)
        + (double)(end.tv_nsec - start.tv_nsec) / 1000000000.0;
}

static uint32_t parse_u32(const char* value, const char* name)
{
    char* end = NULL;
    const unsigned long parsed = strtoul(value, &end, 10);
    if (end == value || *end != '\0' || parsed == 0 || parsed > UINT32_MAX) {
        fprintf(stderr, "invalid %s: %s\n", name, value);
        exit(2);
    }
    return (uint32_t)parsed;
}

int main(int argc, char** argv)
{
    if (argc > 4) {
        fprintf(stderr, "usage: %s ABI [WORLDS] [ITERATIONS]\n", argv[0]);
        return 2;
    }
    const uint32_t action_abi = argc > 1 ? parse_u32(argv[1], "action ABI") : 9;
    const uint32_t worlds = argc > 2 ? parse_u32(argv[2], "world count") : 64;
    const uint32_t iterations = argc > 3 ? parse_u32(argv[3], "iteration count") : 16384;
    if (action_abi != 9 && action_abi != 14) {
        fprintf(stderr, "action ABI must be 9 or 14\n");
        return 2;
    }

    TdMicroRewardConfig reward_config;
    if (!td_micro_default_reward_config(&reward_config)) return 1;
    TdMicroBatch* batch = td_micro_batch_create_with_configs(
        worlds,
        TD_MICRO_TRAINING_MAX_DECISIONS,
        &reward_config,
        TD_MICRO_CURRICULUM_FULL_MATCH,
        0,
        0);
    const size_t action_size = action_abi == 9
        ? sizeof(TdMicroPolicyActionAbi9)
        : sizeof(TdMicroPolicyActionAbi14);
    const size_t mask_size = action_abi == 9
        ? TD_MICRO_ABI9_ACTION_MASK_SIZE
        : TD_MICRO_ABI14_ACTION_MASK_SIZE;
    uint64_t* seeds = calloc(worlds, sizeof(*seeds));
    uint8_t* actions = calloc(worlds, action_size);
    uint8_t* observations = malloc((size_t)worlds * TD_MICRO_OBSERVATION_SIZE);
    uint8_t* masks = malloc((size_t)worlds * mask_size);
    float* rewards = calloc(worlds, sizeof(*rewards));
    uint8_t* terminals = calloc(worlds, sizeof(*terminals));
    if (batch == NULL || seeds == NULL || actions == NULL || observations == NULL || masks == NULL
        || rewards == NULL || terminals == NULL) {
        fprintf(stderr, "allocation failed\n");
        return 1;
    }
    for (uint32_t index = 0; index < worlds; ++index) {
        seeds[index] = td_micro_balanced_spawn_seed(1, index);
        if (action_abi == 9) {
            ((TdMicroPolicyActionAbi9*)actions)[index].actor = TD_MICRO_POLICY_ACTOR_NONE;
        } else {
            ((TdMicroPolicyActionAbi14*)actions)[index].actor = TD_MICRO_POLICY_ACTOR_NONE;
        }
    }

    if (!td_micro_reset_batch(batch, seeds, worlds)) {
        fprintf(stderr, "batch initialization failed\n");
        return 1;
    }
    const int observed = action_abi == 9
        ? td_micro_observe_batch_abi9(batch, observations, masks, worlds)
        : td_micro_observe_batch_abi14(batch, observations, masks, worlds);
    if (!observed) {
        fprintf(stderr, "batch initialization failed\n");
        return 1;
    }

    struct timespec start;
    struct timespec end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (uint32_t iteration = 0; iteration < iterations; ++iteration) {
        const int stepped = action_abi == 9
            ? td_micro_step_batch_abi9(
                batch,
                (const TdMicroPolicyActionAbi9*)actions,
                observations,
                masks,
                rewards,
                terminals,
                worlds)
            : td_micro_step_batch_abi14(
                batch,
                (const TdMicroPolicyActionAbi14*)actions,
                observations,
                masks,
                rewards,
                terminals,
                worlds);
        if (!stepped) {
            fprintf(stderr, "batch step failed at iteration %u\n", iteration);
            return 1;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &end);

    TdMicroBatchStats stats = {0};
    uint8_t digest[TD_MICRO_RULESET_HASH_SIZE];
    if (!td_micro_batch_stats(batch, &stats)
        || td_micro_batch_world_digest(batch, 0, digest, sizeof(digest)) != sizeof(digest)) {
        fprintf(stderr, "batch result read failed\n");
        return 1;
    }
    const uint64_t decisions = (uint64_t)worlds * iterations;
    const double elapsed = seconds(start, end);
    printf(
        "action_abi=%u worlds=%u iterations=%u decisions=%" PRIu64
        " seconds=%.6f sps=%.3f episodes=%" PRIu64 " failures=%" PRIu64 " digest=",
        action_abi,
        worlds,
        iterations,
        decisions,
        elapsed,
        (double)decisions / elapsed,
        stats.episodes,
        stats.failures);
    for (size_t index = 0; index < sizeof(digest); ++index) printf("%02x", digest[index]);
    putchar('\n');

    td_micro_batch_destroy(batch);
    free(terminals);
    free(rewards);
    free(masks);
    free(observations);
    free(actions);
    free(seeds);
    return stats.failures == 0 ? 0 : 1;
}
