#include "td_micro_api.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum {
    COMMAND_NOOP = 0,
    COMMAND_DEPLOY = 1,
    COMMAND_START_BUILD = 2,
    COMMAND_PLACE = 3,
};

static TdMicroPolicyAction scripted_action(uint32_t decision)
{
    TdMicroPolicyAction action = {
        .command = COMMAND_NOOP,
        .arg0 = TD_MICRO_POLICY_PAD_TOKEN,
        .arg1 = TD_MICRO_POLICY_PAD_TOKEN,
        .arg2 = TD_MICRO_POLICY_PAD_TOKEN,
    };
    switch (decision) {
    case 1:
        action.command = COMMAND_DEPLOY;
        action.arg0 = 0;
        break;
    case 23:
        action.command = COMMAND_START_BUILD;
        action.arg0 = TD_MICRO_POLICY_PRODUCT_POWER_PLANT;
        break;
    case 77:
        action.command = COMMAND_PLACE;
        action.arg0 = 4;
        action.arg1 = 7;
        break;
    case 92:
        action.command = COMMAND_START_BUILD;
        action.arg0 = TD_MICRO_POLICY_PRODUCT_REFINERY;
        break;
    case 579:
        action.command = COMMAND_PLACE;
        action.arg0 = 6;
        action.arg1 = 7;
        break;
    default:
        break;
    }
    return action;
}

int main(void)
{
    const uint32_t max_decisions = 900;
    const uint64_t seed = 1;
    TdMicroBatch* batch = td_micro_batch_create(1, max_decisions);
    uint8_t* observation = calloc(TD_MICRO_OBSERVATION_SIZE, 1);
    uint8_t* mask = calloc(TD_MICRO_ACTION_MASK_SIZE, 1);
    float reward = 0.0f;
    uint8_t terminal = 0;
    if (batch == NULL || observation == NULL || mask == NULL
        || !td_micro_reset_batch(batch, &seed, 1)
        || !td_micro_observe_batch(batch, observation, mask, 1)) {
        free(mask);
        free(observation);
        td_micro_batch_destroy(batch);
        return 1;
    }

    uint32_t terminal_decision = 0;
    for (uint32_t decision = 1; decision <= max_decisions; ++decision) {
        const TdMicroPolicyAction action = scripted_action(decision);
        if (!td_micro_step_batch(
                batch,
                &action,
                observation,
                mask,
                &reward,
                &terminal,
                1)) {
            free(mask);
            free(observation);
            td_micro_batch_destroy(batch);
            return 2;
        }
        if (terminal != 0) {
            terminal_decision = decision;
            break;
        }
    }

    TdMicroBatchStats stats = {0};
    TdMicroBatchMetrics metrics = {0};
    const int ok = terminal_decision == max_decisions
        && td_micro_batch_stats(batch, &stats)
        && td_micro_batch_metrics(batch, &metrics)
        && stats.episodes == 1
        && stats.draws == 1
        && stats.invalid_actions == 0
        && stats.failures == 0
        && metrics.player_refineries_built == 1
        && metrics.player_harvesters_spawned == 1
        && metrics.player_tiberium_income > 0
        && metrics.refinery_milestones == 1
        && metrics.harvester_milestones == 1
        && metrics.first_delivery_milestones == 1;
    if (ok) {
        printf(
            "decisions=%u refinery=%llu harvester=%llu income=%llu first_delivery=%llu "
            "invalid=%llu failures=%llu\n",
            terminal_decision,
            (unsigned long long)metrics.player_refineries_built,
            (unsigned long long)metrics.player_harvesters_spawned,
            (unsigned long long)metrics.player_tiberium_income,
            (unsigned long long)metrics.first_delivery_milestones,
            (unsigned long long)stats.invalid_actions,
            (unsigned long long)stats.failures);
    }

    free(mask);
    free(observation);
    td_micro_batch_destroy(batch);
    return ok ? 0 : 3;
}
