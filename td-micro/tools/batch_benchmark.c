#define _POSIX_C_SOURCE 200809L

#include "td_micro_api.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double seconds(struct timespec start, struct timespec end)
{
    return (double)(end.tv_sec - start.tv_sec) + (double)(end.tv_nsec - start.tv_nsec) / 1000000000.0;
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

static uint32_t parse_schedule(const char* value)
{
    char* end = NULL;
    const unsigned long parsed = strtoul(value, &end, 10);
    if (end == value || *end != '\0' || parsed > UINT32_MAX
        || !td_micro_curriculum_schedule_valid((uint32_t)parsed)) {
        fprintf(stderr, "invalid curriculum schedule: %s\n", value);
        exit(2);
    }
    return (uint32_t)parsed;
}

static uint64_t parse_stage_decisions(const char* value)
{
    char* end = NULL;
    const unsigned long long parsed = strtoull(value, &end, 10);
    if (end == value || *end != '\0') {
        fprintf(stderr, "invalid curriculum stage decisions: %s\n", value);
        exit(2);
    }
    return (uint64_t)parsed;
}

int main(int argc, char** argv)
{
    if (argc > 6) {
        fprintf(stderr,
            "usage: %s [WORLDS] [ITERATIONS] [CURRICULUM_SCHEDULE_ID] "
            "[STAGE_DECISIONS] [STARTING_FORCE_RAMP_DECISIONS]\n",
            argv[0]);
        return 2;
    }
    const uint32_t worlds = argc > 1 ? parse_u32(argv[1], "world count") : 64;
    const uint32_t iterations = argc > 2 ? parse_u32(argv[2], "iteration count") : 16384;
    const uint32_t curriculum_schedule_id = argc > 3
        ? parse_schedule(argv[3])
        : TD_MICRO_CURRICULUM_FULL_MATCH;
    const uint64_t curriculum_stage_decisions = argc > 4
        ? parse_stage_decisions(argv[4])
        : 0;
    const uint64_t starting_force_ramp_decisions = argc > 5
        ? parse_stage_decisions(argv[5])
        : (curriculum_schedule_id == TD_MICRO_CURRICULUM_REVERSE ? 8192 : 0);
    if (!td_micro_curriculum_config_valid(
            curriculum_schedule_id,
            curriculum_stage_decisions,
            starting_force_ramp_decisions)) {
        fprintf(stderr, "invalid curriculum schedule/length combination\n");
        return 2;
    }

    TdMicroRewardConfig reward_config;
    if (!td_micro_default_reward_config(&reward_config)) return 1;
    TdMicroBatch* batch = td_micro_batch_create_with_configs(
        worlds,
        TD_MICRO_TRAINING_MAX_DECISIONS,
        &reward_config,
        curriculum_schedule_id,
        curriculum_stage_decisions,
        starting_force_ramp_decisions);
    uint64_t* seeds = calloc(worlds, sizeof(*seeds));
    TdMicroPolicyAction* actions = calloc(worlds, sizeof(*actions));
    uint8_t* observations = malloc((size_t)worlds * TD_MICRO_OBSERVATION_SIZE);
    uint8_t* masks = malloc((size_t)worlds * TD_MICRO_ACTION_MASK_SIZE);
    float* rewards = calloc(worlds, sizeof(*rewards));
    uint8_t* terminals = calloc(worlds, sizeof(*terminals));
    if (batch == NULL || seeds == NULL || actions == NULL || observations == NULL || masks == NULL
        || rewards == NULL || terminals == NULL) {
        fprintf(stderr, "allocation failed\n");
        return 1;
    }
    for (uint32_t index = 0; index < worlds; ++index) {
        seeds[index] = td_micro_balanced_spawn_seed(1, index);
        actions[index].command = 0;
        actions[index].arg0 = TD_MICRO_POLICY_PAD_TOKEN;
        actions[index].arg1 = TD_MICRO_POLICY_PAD_TOKEN;
        actions[index].arg2 = TD_MICRO_POLICY_PAD_TOKEN;
    }
    if (!td_micro_reset_batch(batch, seeds, worlds)
        || !td_micro_observe_batch(batch, observations, masks, worlds)) {
        fprintf(stderr, "batch initialization failed\n");
        return 1;
    }

    struct timespec start;
    struct timespec end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (uint32_t iteration = 0; iteration < iterations; ++iteration) {
        if (!td_micro_step_batch(batch, actions, observations, masks, rewards, terminals, worlds)) {
            fprintf(stderr, "batch step failed at iteration %u\n", iteration);
            return 1;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &end);

    TdMicroBatchStats stats = {0};
    uint8_t digest[32];
    if (!td_micro_batch_stats(batch, &stats)
        || td_micro_batch_world_digest(batch, 0, digest, sizeof(digest)) != sizeof(digest)) {
        fprintf(stderr, "batch result read failed\n");
        return 1;
    }
    const uint64_t decisions = (uint64_t)worlds * iterations;
    const double elapsed = seconds(start, end);
    printf("worlds=%u iterations=%u curriculum_schedule=%u curriculum_stage_decisions=%" PRIu64
           " starting_force_ramp_decisions=%" PRIu64
           " decisions=%" PRIu64
           " seconds=%.6f sps=%.3f "
           "episodes=%" PRIu64 " wins=%" PRIu64 " losses=%" PRIu64 " draws=%" PRIu64
           " failures=%" PRIu64 " digest=",
           worlds,
           iterations,
           curriculum_schedule_id,
           curriculum_stage_decisions,
           starting_force_ramp_decisions,
           decisions,
           elapsed,
           (double)decisions / elapsed,
           stats.episodes,
           stats.wins,
           stats.losses,
           stats.draws,
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
