#define _POSIX_C_SOURCE 200809L

#include "td_micro_api.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

enum {
    COMMAND_NOOP = 0,
    COMMAND_DEPLOY = 1,
    COMMAND_START_BUILD = 2,
    COMMAND_PLACE = 3,
};

static double elapsed_seconds(struct timespec start, struct timespec end)
{
    return (double)(end.tv_sec - start.tv_sec)
        + (double)(end.tv_nsec - start.tv_nsec) / 1000000000.0;
}

static void fill_actions(
    TdMicroPolicyAction* actions,
    uint32_t count,
    uint8_t command,
    uint8_t arg0)
{
    for (uint32_t index = 0; index < count; ++index) {
        actions[index] = (TdMicroPolicyAction){
            .command = command,
            .arg0 = arg0,
            .arg1 = TD_MICRO_POLICY_PAD_TOKEN,
            .arg2 = TD_MICRO_POLICY_PAD_TOKEN,
        };
    }
}

static int mask_bit(const uint8_t* mask, uint32_t bit)
{
    return (mask[bit / 8] & (uint8_t)(1u << (bit % 8))) != 0;
}

static double benchmark(int ready_queue)
{
    const uint32_t worlds = 64;
    const uint32_t iterations = 512;
    TdMicroBatch* batch = td_micro_batch_create(worlds, TD_MICRO_TRAINING_MAX_DECISIONS);
    uint64_t* seeds = calloc(worlds, sizeof(*seeds));
    TdMicroPolicyAction* actions = calloc(worlds, sizeof(*actions));
    uint8_t* observations = malloc((size_t)worlds * TD_MICRO_OBSERVATION_SIZE);
    uint8_t* masks = malloc((size_t)worlds * TD_MICRO_ACTION_MASK_SIZE);
    float* rewards = calloc(worlds, sizeof(*rewards));
    uint8_t* terminals = calloc(worlds, sizeof(*terminals));
    if (!batch || !seeds || !actions || !observations || !masks || !rewards || !terminals) exit(2);

    for (uint32_t index = 0; index < worlds; ++index) {
        seeds[index] = td_micro_balanced_spawn_seed(1, index);
    }
    if (!td_micro_reset_batch(batch, seeds, worlds)) exit(3);
    fill_actions(actions, worlds, COMMAND_NOOP, TD_MICRO_POLICY_PAD_TOKEN);
    if (!td_micro_observe_batch(batch, observations, masks, worlds)) exit(4);

    if (ready_queue) {
        for (uint32_t decision = 1; decision <= 77; ++decision) {
            fill_actions(actions, worlds, COMMAND_NOOP, TD_MICRO_POLICY_PAD_TOKEN);
            if (decision == 1) fill_actions(actions, worlds, COMMAND_DEPLOY, 0);
            if (decision == 23) {
                fill_actions(
                    actions,
                    worlds,
                    COMMAND_START_BUILD,
                    TD_MICRO_POLICY_PRODUCT_POWER_PLANT);
            }
            if (!td_micro_step_batch(
                    batch,
                    actions,
                    observations,
                    masks,
                    rewards,
                    terminals,
                    worlds)) {
                exit(5);
            }
        }
        for (uint32_t index = 0; index < worlds; ++index) {
            const uint8_t* mask = masks + (size_t)index * TD_MICRO_ACTION_MASK_SIZE;
            if (!mask_bit(mask, TD_MICRO_MASK_COMMAND_BIT_OFFSET + COMMAND_PLACE)) exit(6);
        }
    }

    fill_actions(actions, worlds, COMMAND_NOOP, TD_MICRO_POLICY_PAD_TOKEN);
    struct timespec start;
    struct timespec end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (uint32_t iteration = 0; iteration < iterations; ++iteration) {
        if (!td_micro_step_batch(
                batch,
                actions,
                observations,
                masks,
                rewards,
                terminals,
                worlds)) {
            exit(7);
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &end);

    if (ready_queue) {
        for (uint32_t index = 0; index < worlds; ++index) {
            const uint8_t* mask = masks + (size_t)index * TD_MICRO_ACTION_MASK_SIZE;
            if (!mask_bit(mask, TD_MICRO_MASK_COMMAND_BIT_OFFSET + COMMAND_PLACE)) exit(8);
        }
    }

    const double result = (double)worlds * iterations / elapsed_seconds(start, end);
    td_micro_batch_destroy(batch);
    free(terminals);
    free(rewards);
    free(masks);
    free(observations);
    free(actions);
    free(seeds);
    return result;
}

int main(void)
{
    printf("normal_sps=%.3f\n", benchmark(0));
    printf("ready_queue_sps=%.3f\n", benchmark(1));
    return 0;
}
