#include "cnc_micro.h"

#define OBS_SIZE TD_MICRO_OBSERVATION_SIZE
#define NUM_ATNS 4
#define ACT_SIZES {12, 65, 65, 65}
#define OBS_TENSOR_T ByteTensor
#define OBS_SCALE 0.0039215686274509804f
#define MY_ACTION_MASK TD_MICRO_ACTION_MASK_SIZE
#define MY_DYNAMIC_ACTION_SPEC
#define MY_VEC_INIT
#define MY_STATE

#define Env CncMicro
#include "vecenv.h"

static int selected_action_abi = 9;
static int abi9_action_sizes[] = {12, 65, TD_MICRO_POLICY_PRODUCT_COUNT, 4, 64, 64, 64};
static int abi13_action_sizes[] = {12, 65, 65, 65};
static int abi14_action_sizes[TD_MICRO_ABI14_ACTION_HEAD_COUNT];

static void init_abi14_action_sizes(void)
{
    for (int head = 0; head < TD_MICRO_ABI9_ACTION_HEAD_COUNT; ++head) {
        abi14_action_sizes[head] = abi9_action_sizes[head];
    }
    for (int head = TD_MICRO_ABI9_ACTION_HEAD_COUNT;
         head < TD_MICRO_ABI14_ACTION_HEAD_COUNT;
         ++head) {
        abi14_action_sizes[head] = 2;
    }
}

int get_num_atns(void)
{
    if (selected_action_abi == 9) return TD_MICRO_ABI9_ACTION_HEAD_COUNT;
    if (selected_action_abi == 14) return TD_MICRO_ABI14_ACTION_HEAD_COUNT;
    return TD_MICRO_ACTION_HEAD_COUNT;
}

int* get_act_sizes(void)
{
    if (selected_action_abi == 9) return abi9_action_sizes;
    if (selected_action_abi == 14) {
        init_abi14_action_sizes();
        return abi14_action_sizes;
    }
    return abi13_action_sizes;
}

int get_num_act_sizes(void)
{
    return get_num_atns();
}

int get_action_mask_size(void)
{
    if (selected_action_abi == 9) return TD_MICRO_ABI9_ACTION_MASK_SIZE;
    if (selected_action_abi == 14) return TD_MICRO_ABI14_ACTION_MASK_SIZE;
    return TD_MICRO_ACTION_MASK_SIZE;
}

int get_action_abi(void)
{
    return selected_action_abi;
}

void my_init(Env* env, Dict* kwargs)
{
    (void)env;
    (void)kwargs;
}

Env* my_vec_init(
    int* num_envs_out,
    int* buffer_env_starts,
    int* buffer_env_counts,
    Dict* vec_kwargs,
    Dict* env_kwargs)
{
    const int total_agents = (int)dict_get(vec_kwargs, "total_agents")->value;
    const int num_buffers = (int)dict_get(vec_kwargs, "num_buffers")->value;
    const int max_decisions = (int)dict_get(env_kwargs, "max_decisions")->value;
    const uint64_t seed = (uint64_t)dict_get(env_kwargs, "seed")->value;
    const int action_scheme = (int)dict_get(env_kwargs, "action_scheme")->value;
    const int action_abi_override = (int)dict_get(env_kwargs, "action_abi")->value;
    const int action_abi = cnc_micro_resolve_action_abi(action_scheme, action_abi_override);
    const uint32_t curriculum_schedule_id =
        (uint32_t)dict_get(env_kwargs, "curriculum_schedule_id")->value;
    const uint64_t curriculum_stage_decisions =
        (uint64_t)dict_get(env_kwargs, "curriculum_stage_decisions")->value;
    const uint64_t starting_force_ramp_decisions =
        (uint64_t)dict_get(env_kwargs, "starting_force_ramp_decisions")->value;
    const uint32_t difficulty_schedule_id =
        (uint32_t)dict_get(env_kwargs, "difficulty_schedule_id")->value;
    const uint64_t difficulty_ramp_decisions =
        (uint64_t)dict_get(env_kwargs, "difficulty_ramp_decisions")->value;
    const TdMicroRewardConfig reward_config = {
        .reward_milestone = (float)dict_get(env_kwargs, "reward_milestone")->value,
        .reward_player_infantry = (float)dict_get(env_kwargs, "reward_player_infantry")->value,
        .reward_enemy_unit_loss = (float)dict_get(env_kwargs, "reward_enemy_unit_loss")->value,
        .reward_enemy_building_loss = (float)dict_get(env_kwargs, "reward_enemy_building_loss")->value,
        .reward_player_unit_loss = (float)dict_get(env_kwargs, "reward_player_unit_loss")->value,
        .reward_refinery = (float)dict_get(env_kwargs, "reward_refinery")->value,
        .reward_first_delivery = (float)dict_get(env_kwargs, "reward_first_delivery")->value,
        .reward_weapons_factory = (float)dict_get(env_kwargs, "reward_weapons_factory")->value,
        .reward_full_win = (float)dict_get(env_kwargs, "reward_full_win")->value,
        .reward_partial_win = (float)dict_get(env_kwargs, "reward_partial_win")->value,
        .economy_win_credits = (unsigned int)dict_get(env_kwargs, "economy_win_credits")->value,
        .full_win_min_tanks = (unsigned int)dict_get(env_kwargs, "full_win_min_tanks")->value,
        .full_win_min_humvees = (unsigned int)dict_get(env_kwargs, "full_win_min_humvees")->value,
        .full_win_min_tank_shots = (unsigned int)dict_get(env_kwargs, "full_win_min_tank_shots")->value,
        .reward_vehicle = (float)dict_get(env_kwargs, "reward_vehicle")->value,
        .reward_tiberium_income = (float)dict_get(env_kwargs, "reward_tiberium_income")->value,
        .reward_invalid_action = (float)dict_get(env_kwargs, "reward_invalid_action")->value,
        .reward_build_order_violation =
            (float)dict_get(env_kwargs, "reward_build_order_violation")->value,
        .reward_build_order_violation_constrained =
            (float)dict_get(env_kwargs, "reward_build_order_violation_constrained")->value,
        .reward_build_order_sequence =
            (float)dict_get(env_kwargs, "reward_build_order_sequence")->value,
        .reward_tank_kill =
            (float)dict_get(env_kwargs, "reward_tank_kill")->value,
        .reward_first_tank =
            (float)dict_get(env_kwargs, "reward_first_tank")->value,
        .reward_first_tank_shot =
            (float)dict_get(env_kwargs, "reward_first_tank_shot")->value,
        .reward_qualified_loss =
            (float)dict_get(env_kwargs, "reward_qualified_loss")->value,
    };
    if (total_agents <= 0 || num_buffers <= 0 || total_agents % num_buffers != 0) return NULL;
    if (!td_micro_reward_config_valid(&reward_config)) {
        fprintf(stderr, "cnc_micro: invalid reward configuration\n");
        return NULL;
    }
    if (action_abi < 0) {
        fprintf(stderr,
            "cnc_micro: unsupported action scheme/ABI combination scheme=%d abi=%d\n",
            action_scheme,
            action_abi_override);
        return NULL;
    }
    selected_action_abi = action_abi;

    Env* envs = calloc((size_t)num_buffers, sizeof(*envs));
    if (envs == NULL) return NULL;
    const int agents_per_buffer = total_agents / num_buffers;
    for (int buffer = 0; buffer < num_buffers; ++buffer) {
        envs[buffer].rng = (unsigned int)buffer;
        if (!cnc_micro_init(
                &envs[buffer],
                agents_per_buffer,
                action_abi,
                (uint32_t)max_decisions,
                seed,
                (uint64_t)buffer * (uint64_t)agents_per_buffer,
                curriculum_schedule_id,
                curriculum_stage_decisions,
                starting_force_ramp_decisions,
                difficulty_schedule_id,
                difficulty_ramp_decisions,
                &reward_config)) {
            for (int prior = 0; prior <= buffer; ++prior) c_close(&envs[prior]);
            free(envs);
            return NULL;
        }
        buffer_env_starts[buffer] = buffer;
        buffer_env_counts[buffer] = 1;
    }
    *num_envs_out = num_buffers;
    return envs;
}

void my_log(Log* log, Dict* out)
{
    dict_set(out, "perf", cnc_micro_full_match_perf(log));
    dict_set(out, "episode_return", log->episode_return);
    dict_set(out, "invalid_actions", log->invalid_actions);
    dict_set(out, "failures", log->failures);
    dict_set(out, "start_failures", log->start_failures);
    dict_set(out, "unit_kills", log->unit_kills);
    dict_set(out, "buildings_destroyed", log->buildings_destroyed);
    dict_set(out, "refineries_built", log->refineries_built);
    dict_set(out, "weapons_factories_built", log->weapons_factories_built);
    dict_set(out, "medium_tanks_built", log->medium_tanks_built);
    dict_set(out, "tank_shots", log->tank_shots);
    dict_set(out, "tank_kills", log->tank_kills);
    dict_set(out, "tiberium_income", log->tiberium_income);
    dict_set(out, "e1_infantry_target_rate",
        cnc_micro_rate(log->player_e1_infantry_targets, log->player_e1_attack_orders));
    dict_set(out, "balanced_perf", cnc_micro_balanced_perf(log));
    dict_set(out, "easy_balanced_perf", cnc_micro_easy_balanced_perf(log));
    dict_set(out, "normal_balanced_perf", cnc_micro_normal_balanced_perf(log));
    dict_set(out, "medium_win_rate", cnc_micro_rate(log->medium_wins, log->medium_episodes));
    dict_set(out, "full_perf", cnc_micro_full_perf(log));
    dict_set(out, "attack_apply_rate", cnc_micro_rate(log->attacks_applied, log->attacks_attempted));
    dict_set(out, "e3_vehicle_target_rate",
        cnc_micro_rate(log->player_e3_vehicle_targets, log->player_e3_attack_orders));
    dict_set(out, "loss_rate", cnc_micro_full_match_loss_rate(log));
    dict_set(out, "tank_e3_target_rate",
        cnc_micro_rate(log->player_tank_e3_targets, log->player_tank_attack_orders));
    dict_set(out, "unit_losses", log->unit_losses);
    dict_set(out, "buildings_lost", log->buildings_lost);
    dict_set(out, "tank_e3_loss_share",
        cnc_micro_rate(log->player_tank_losses_to_e3, log->player_tank_losses));
    dict_set(out, "tank_build_rate", cnc_micro_rate(log->first_tank_milestones, log->n));
    dict_set(out, "tank_use_rate", cnc_micro_rate(log->first_tank_shot_milestones, log->n));
    dict_set(out, "qualified_loss_rate", cnc_micro_qualified_loss_rate(log));
    dict_set(out, "qualified_loss_conversion", cnc_micro_qualified_loss_conversion(log));
}
