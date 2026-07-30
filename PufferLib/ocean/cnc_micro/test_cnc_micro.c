#include "cnc_micro.h"

#include <stdio.h>

_Static_assert(sizeof(TdMicroRewardConfig) == 24 * sizeof(float), "reward config ABI size");
_Static_assert(sizeof(TdMicroPolicyActionAbi9) == 7, "ABI9 action size");
_Static_assert(sizeof(TdMicroPolicyActionAbi14) == 71, "ABI14 action size");
_Static_assert(sizeof(TdMicroBatchStats) == 31 * sizeof(uint64_t), "legacy stats ABI size");
_Static_assert(sizeof(TdMicroBatchStatsV2) == 53 * sizeof(uint64_t), "v2 stats ABI size");
_Static_assert(sizeof(TdMicroBatchMetrics) == 43 * sizeof(uint64_t), "metrics ABI size");
_Static_assert(CNC_MICRO_EXPORTED_LOG_COUNT <= 31, "Puffer log field limit");
_Static_assert(
    sizeof(Log) == (CNC_MICRO_LOG_FLOAT_COUNT + 1) * sizeof(float),
    "stored log count must match Log fields before n");

enum {
    COMMAND_NOOP = 0,
    COMMAND_DEPLOY = 1,
};

int main(void)
{
    if (cnc_micro_resolve_action_abi(0, 0) != 9
        || cnc_micro_resolve_action_abi(1, 0) != 14
        || cnc_micro_resolve_action_abi(0, 13) != 13
        || cnc_micro_resolve_action_abi(1, 9) != 9
        || cnc_micro_resolve_action_abi(2, 0) != -1
        || cnc_micro_resolve_action_abi(0, 10) != -1) {
        return 15;
    }
    CncMicro env = {0};
    uint8_t observations[TD_MICRO_OBSERVATION_SIZE] = {0};
    float actions[TD_MICRO_ACTION_HEAD_COUNT] = {0};
    float rewards[1] = {0};
    float terminals[1] = {0};
    uint8_t action_mask[TD_MICRO_ACTION_MASK_SIZE] = {0};
    TdMicroRewardConfig reward_config;

    if (!td_micro_default_reward_config(&reward_config)) return 5;
    if (reward_config.reward_refinery != 0.2f
        || reward_config.reward_first_delivery != 0.1f
        || reward_config.reward_tiberium_income != 0.01f
        || reward_config.reward_invalid_action != 0.0f
        || reward_config.reward_first_tank != 0.0f
        || reward_config.reward_first_tank_shot != 0.0f
        || reward_config.reward_qualified_loss != -1.0f) {
        return 8;
    }
    if (!td_micro_curriculum_schedule_valid(TD_MICRO_CURRICULUM_FULL_MATCH)
        || !td_micro_curriculum_schedule_valid(TD_MICRO_CURRICULUM_REVERSE)
        || td_micro_curriculum_schedule_valid(2)
        || td_micro_curriculum_schedule_valid(UINT32_MAX)) {
        return 10;
    }
    if (!td_micro_curriculum_config_valid(TD_MICRO_CURRICULUM_FULL_MATCH, 0, 0)
        || td_micro_curriculum_config_valid(TD_MICRO_CURRICULUM_REVERSE, 0, 8192)
        || td_micro_curriculum_config_valid(TD_MICRO_CURRICULUM_REVERSE, 4096, 0)
        || !td_micro_curriculum_config_valid(TD_MICRO_CURRICULUM_REVERSE, 4096, 2048)
        || !td_micro_curriculum_config_valid(TD_MICRO_CURRICULUM_REVERSE, 4096, 12288)) {
        return 13;
    }
    if (!td_micro_difficulty_schedule_valid(TD_MICRO_DIFFICULTY_FIXED_EASY)
        || !td_micro_difficulty_schedule_valid(TD_MICRO_DIFFICULTY_EASY_TO_NORMAL)
        || !td_micro_difficulty_schedule_valid(TD_MICRO_DIFFICULTY_FIXED_NORMAL)
        || !td_micro_difficulty_schedule_valid(TD_MICRO_DIFFICULTY_FIXED_HARD)
        || td_micro_difficulty_schedule_valid(4)
        || !td_micro_difficulty_config_valid(TD_MICRO_DIFFICULTY_FIXED_EASY, 0)
        || td_micro_difficulty_config_valid(TD_MICRO_DIFFICULTY_FIXED_EASY, 1)
        || td_micro_difficulty_config_valid(TD_MICRO_DIFFICULTY_FIXED_NORMAL, 1)
        || td_micro_difficulty_config_valid(TD_MICRO_DIFFICULTY_FIXED_HARD, 1)
        || td_micro_difficulty_config_valid(TD_MICRO_DIFFICULTY_EASY_TO_NORMAL, 0)
        || !td_micro_difficulty_config_valid(TD_MICRO_DIFFICULTY_EASY_TO_NORMAL, 8192)) {
        return 17;
    }
    TdMicroBatch* curriculum_batch = td_micro_batch_create_with_configs_v2(
        1,
        512,
        &reward_config,
        TD_MICRO_CURRICULUM_REVERSE,
        2,
        4,
        TD_MICRO_DIFFICULTY_FIXED_NORMAL,
        0);
    if (curriculum_batch == NULL) return 11;
    const uint64_t curriculum_seed = 1;
    uint8_t curriculum_observation[TD_MICRO_OBSERVATION_SIZE] = {0};
    uint8_t curriculum_mask[TD_MICRO_ABI9_ACTION_MASK_SIZE] = {0};
    const TdMicroPolicyActionAbi9 curriculum_noop = {0};
    float curriculum_reward = 0.0f;
    uint8_t curriculum_terminal = 0;
    TdMicroBatchStatsV2 curriculum_stats = {0};
    struct {
        TdMicroBatchStats stats;
        uint64_t canary;
    } legacy_stats = {{0}, UINT64_C(0x0123456789abcdef)};
    const int curriculum_ok = td_micro_reset_batch(curriculum_batch, &curriculum_seed, 1)
        && td_micro_observe_batch_abi9(
            curriculum_batch,
            curriculum_observation,
            curriculum_mask,
            1)
        && td_micro_step_batch_abi9(
            curriculum_batch,
            &curriculum_noop,
            curriculum_observation,
            curriculum_mask,
            &curriculum_reward,
            &curriculum_terminal,
            1)
        && td_micro_batch_stats_v2(curriculum_batch, &curriculum_stats)
        && td_micro_batch_stats(curriculum_batch, &legacy_stats.stats)
        && legacy_stats.canary == UINT64_C(0x0123456789abcdef)
        && curriculum_reward == 0.0f
        && curriculum_terminal == 0
        && curriculum_observation[TD_MICRO_OBSERVATION_DIFFICULTY_OFFSET] == 1
        && curriculum_stats.wins == 0;
    td_micro_batch_destroy(curriculum_batch);
    if (!curriculum_ok) return 12;
    TdMicroRewardConfig invalid_config = reward_config;
    invalid_config.reward_milestone = -0.01f;
    CncMicro invalid_env = {0};
    if (cnc_micro_init(
            &invalid_env,
            1,
            13,
            2,
            1,
            0,
            TD_MICRO_CURRICULUM_FULL_MATCH,
            0,
            0,
            TD_MICRO_DIFFICULTY_FIXED_EASY,
            0,
            &invalid_config)) {
        c_close(&invalid_env);
        return 6;
    }

    reward_config.reward_milestone = 0.25f;
    if (!cnc_micro_init(
            &env,
            1,
            13,
            2,
            1,
            0,
            TD_MICRO_CURRICULUM_FULL_MATCH,
            0,
            0,
            TD_MICRO_DIFFICULTY_FIXED_EASY,
            0,
            &reward_config)) return 1;
    env.observations = observations;
    env.actions = actions;
    env.rewards = rewards;
    env.terminals = terminals;
    env.action_mask = action_mask;
    c_reset(&env);
    if (observations[0] != TD_MICRO_OBSERVATION_VERSION) return 4;
    if (observations[4] != 23) return 14;
    if (env.log.n != 0.0f) return 7;

    actions[0] = COMMAND_DEPLOY;
    actions[1] = 0;
    actions[2] = TD_MICRO_POLICY_PAD_TOKEN;
    actions[3] = TD_MICRO_POLICY_PAD_TOKEN;
    c_step(&env);
    if (rewards[0] != 0.25f || terminals[0] != 0.0f) return 2;

    actions[0] = COMMAND_NOOP;
    actions[1] = TD_MICRO_POLICY_PAD_TOKEN;
    actions[2] = TD_MICRO_POLICY_PAD_TOKEN;
    actions[3] = TD_MICRO_POLICY_PAD_TOKEN;
    c_step(&env);
    const int ok = terminals[0] == 1.0f
        && env.log.episode_return == 0.25f
        && env.log.perf == 0.0f
        && env.log.draw_rate == 1.0f
        && env.log.n == 1.0f;
    if (ok) {
        printf("episode_return=%.3f draw_rate=%.0f\n",
               env.log.episode_return,
               env.log.draw_rate);
    }

    CncMicro aggregate = {0};
    const TdMicroBatchStatsV2 stats = {
        .episodes = 5,
        .wins = 3,
        .losses = 1,
        .draws = 1,
        .episode_decisions = 30,
        .close_episodes = 2,
        .close_wins = 1,
        .close_losses = 1,
        .medium_episodes = 1,
        .medium_wins = 0,
        .medium_losses = 0,
        .close_mcv_episodes = 1,
        .close_mcv_wins = 1,
        .close_force_episodes = 1,
        .close_force_losses = 1,
        .medium_force_episodes = 1,
        .completed_invalid_actions = 6,
        .invalid_action_penalty = -0.25,
        .full_wins = 1,
    };
    const TdMicroBatchMetrics metrics = {
        .player_e1_built = 2,
        .player_e3_built = 1,
        .player_unit_kills = 4,
        .player_unit_losses = 5,
        .player_buildings_lost = 2,
        .opponent_buildings_lost = 3,
        .player_refineries_built = 1,
        .player_harvesters_spawned = 1,
        .player_tiberium_income = 700,
        .refinery_milestones = 1,
        .harvester_milestones = 1,
        .first_delivery_milestones = 1,
        .first_tank_milestones = 2,
        .first_tank_shot_milestones = 1,
        .qualified_losses = 1,
        .player_e1_attack_orders = 4,
        .player_e1_infantry_targets = 3,
        .player_e3_attack_orders = 5,
        .player_e3_vehicle_targets = 2,
        .player_tank_attack_orders = 6,
        .player_tank_e3_targets = 1,
        .player_tank_losses = 4,
        .player_tank_losses_to_e3 = 3,
    };
    cnc_micro_accumulate_completed_episodes(&aggregate, &stats, &metrics);
    const Log difficulty_log = {
        .easy_close_mcv_episodes = 1,
        .easy_close_mcv_wins = 1,
        .easy_close_force_episodes = 1,
        .easy_close_force_wins = 1,
        .easy_medium_mcv_episodes = 1,
        .easy_medium_mcv_wins = 1,
        .easy_medium_force_episodes = 1,
        .easy_medium_force_wins = 1,
        .normal_close_mcv_episodes = 1,
        .normal_close_force_episodes = 1,
        .normal_medium_mcv_episodes = 1,
        .normal_medium_force_episodes = 1,
    };
    const int aggregate_ok = aggregate.log.n == 5.0f
        && aggregate.log.perf == 1.0f
        && aggregate.log.loss_rate == 1.0f
        && aggregate.log.draw_rate == 1.0f
        && aggregate.log.invalid_actions == 6.0f
        && aggregate.log.units_built == 4.0f
        && aggregate.log.gunners_built == 2.0f
        && aggregate.log.rocket_soldiers_built == 1.0f
        && aggregate.log.unit_kills == 4.0f
        && aggregate.log.unit_losses == 5.0f
        && aggregate.log.buildings_lost == 2.0f
        && aggregate.log.buildings_destroyed == 3.0f
        && aggregate.log.refineries_built == 1.0f
        && aggregate.log.harvesters_spawned == 1.0f
        && aggregate.log.tiberium_income == 700.0f
        && aggregate.log.refinery_milestones == 1.0f
        && aggregate.log.invalid_action_penalty == -0.25f
        && aggregate.log.first_delivery_milestones == 1.0f
        && aggregate.log.first_tank_milestones == 2.0f
        && aggregate.log.first_tank_shot_milestones == 1.0f
        && aggregate.log.qualified_losses == 1.0f
        && aggregate.log.player_e1_attack_orders == 4.0f
        && aggregate.log.player_e1_infantry_targets == 3.0f
        && aggregate.log.player_e3_attack_orders == 5.0f
        && aggregate.log.player_e3_vehicle_targets == 2.0f
        && aggregate.log.player_tank_attack_orders == 6.0f
        && aggregate.log.player_tank_e3_targets == 1.0f
        && aggregate.log.player_tank_losses == 4.0f
        && aggregate.log.player_tank_losses_to_e3 == 3.0f
        && aggregate.log.close_episodes == 2.0f
        && cnc_micro_rate(aggregate.log.close_wins, aggregate.log.close_episodes) == 0.5f
        && aggregate.log.medium_episodes == 1.0f
        && cnc_micro_rate(aggregate.log.medium_losses, aggregate.log.medium_episodes) == 0.0f
        && fabsf(cnc_micro_starting_force_episode_share(&aggregate.log) - (2.0f / 3.0f)) < 0.000001f
        && cnc_micro_rate(aggregate.log.close_mcv_wins, aggregate.log.close_mcv_episodes) == 1.0f
        && cnc_micro_rate(aggregate.log.close_force_wins, aggregate.log.close_force_episodes) == 0.0f
        && cnc_micro_rate(aggregate.log.medium_force_wins, aggregate.log.medium_force_episodes) == 0.0f
        && fabsf(cnc_micro_full_match_episode_share(&aggregate.log) - 0.6f) < 0.000001f
        && fabsf(cnc_micro_full_match_perf(&aggregate.log) - (1.0f / 3.0f)) < 0.000001f
        && fabsf(cnc_micro_full_match_loss_rate(&aggregate.log) - (1.0f / 3.0f)) < 0.000001f
        && fabsf(cnc_micro_full_match_draw_rate(&aggregate.log) - (1.0f / 3.0f)) < 0.000001f
        && fabsf(cnc_micro_full_perf(&aggregate.log) - (1.0f / 3.0f)) < 0.000001f
        && fabsf(cnc_micro_qualified_loss_rate(&aggregate.log) - (1.0f / 3.0f)) < 0.000001f
        && cnc_micro_qualified_loss_conversion(&aggregate.log) == 0.5f
        && cnc_micro_balanced_perf(&aggregate.log) == 0.0f
        && cnc_micro_easy_balanced_perf(&difficulty_log) == 1.0f
        && cnc_micro_normal_balanced_perf(&difficulty_log) == 0.0f
        && cnc_micro_balanced_perf(&difficulty_log) == 0.5f
        && cnc_micro_normal_episode_share(&difficulty_log) == 0.5f
        && td_micro_balanced_spawn_seed(73, 0) == 1
        && td_micro_balanced_spawn_seed(73, 1) == 2
        && td_micro_balanced_spawn_seed(73, 62) == 1
        && td_micro_balanced_spawn_seed(73, 63) == 2;
    if (!aggregate_ok) {
        fprintf(stderr,
            "aggregate n=%.0f perf=%.0f losses=%.0f draws=%.0f full=%.0f "
            "first_tank=%.0f first_shot=%.0f qualified=%.0f conversion=%.3f\n",
            aggregate.log.n,
            aggregate.log.perf,
            aggregate.log.loss_rate,
            aggregate.log.draw_rate,
            aggregate.log.full_wins,
            aggregate.log.first_tank_milestones,
            aggregate.log.first_tank_shot_milestones,
            aggregate.log.qualified_losses,
            cnc_micro_qualified_loss_conversion(&aggregate.log));
    }

    CncMicro abi9 = {0};
    uint8_t abi9_observation[TD_MICRO_OBSERVATION_SIZE] = {0};
    float abi9_actions[TD_MICRO_ABI9_ACTION_HEAD_COUNT] = {0};
    float abi9_rewards[1] = {0};
    float abi9_terminals[1] = {0};
    uint8_t abi9_mask[TD_MICRO_ABI9_ACTION_MASK_SIZE] = {0};
    reward_config.reward_invalid_action = -0.0001f;
    if (!cnc_micro_init(
            &abi9,
            1,
            9,
            2,
            1,
            0,
            TD_MICRO_CURRICULUM_FULL_MATCH,
            0,
            0,
            TD_MICRO_DIFFICULTY_FIXED_EASY,
            0,
            &reward_config)) return 9;
    abi9.observations = abi9_observation;
    abi9.actions = abi9_actions;
    abi9.rewards = abi9_rewards;
    abi9.terminals = abi9_terminals;
    abi9.action_mask = abi9_mask;
    c_reset(&abi9);
    abi9_actions[0] = COMMAND_DEPLOY;
    abi9_actions[1] = TD_MICRO_POLICY_ACTOR_NONE;
    c_step(&abi9);
    const int abi9_ok = abi9_rewards[0] == reward_config.reward_invalid_action
        && abi9.log.n == 0.0f;

    CncMicro abi14 = {0};
    uint8_t abi14_observation[TD_MICRO_OBSERVATION_SIZE] = {0};
    float abi14_actions[TD_MICRO_ABI14_ACTION_HEAD_COUNT] = {0};
    float abi14_rewards[1] = {0};
    float abi14_terminals[1] = {0};
    uint8_t abi14_mask[TD_MICRO_ABI14_ACTION_MASK_SIZE] = {0};
    if (!cnc_micro_init(
            &abi14,
            1,
            14,
            2,
            1,
            0,
            TD_MICRO_CURRICULUM_FULL_MATCH,
            0,
            0,
            TD_MICRO_DIFFICULTY_FIXED_EASY,
            0,
            &reward_config)) return 16;
    abi14.observations = abi14_observation;
    abi14.actions = abi14_actions;
    abi14.rewards = abi14_rewards;
    abi14.terminals = abi14_terminals;
    abi14.action_mask = abi14_mask;
    c_reset(&abi14);
    const int abi14_mask_ok =
        abi14_mask[TD_MICRO_ABI14_SELECTOR_MASK_OFFSET] == 1
        && abi14_mask[TD_MICRO_ABI14_SELECTOR_MASK_OFFSET + 1] == 0;
    abi14_actions[0] = COMMAND_DEPLOY;
    abi14_actions[1] = 0;
    c_step(&abi14);
    const int abi14_ok = abi14_rewards[0] == reward_config.reward_milestone
        && abi14_terminals[0] == 0.0f
        && abi14.log.n == 0.0f;

    c_close(&env);
    c_close(&abi9);
    c_close(&abi14);
    if (!(ok && aggregate_ok && abi9_ok && abi14_mask_ok && abi14_ok)) {
        fprintf(stderr,
            "checks ok=%d aggregate=%d abi9=%d abi14_mask=%d abi14=%d "
            "abi14_reward=%.6f expected=%.6f\n",
            ok,
            aggregate_ok,
            abi9_ok,
            abi14_mask_ok,
            abi14_ok,
            abi14_rewards[0],
            reward_config.reward_milestone);
    }
    return ok && aggregate_ok && abi9_ok && abi14_mask_ok && abi14_ok ? 0 : 3;
}
