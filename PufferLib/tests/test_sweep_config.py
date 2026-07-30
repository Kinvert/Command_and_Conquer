import pufferlib.sweep
from pufferlib.pufferl import load_config, validate_config


def test_match_metadata_is_not_a_hyperparameter():
    config = {
        "method": "Protein",
        "metric": "score",
        "metric_distribution": "normal",
        "goal": "maximize",
        "match_enemy_model_path": "enemy.pt",
        "match_num_games": 32,
        "match_enemy_hidden_size": 64,
        "match_enemy_num_layers": 1,
        "env": {
            "reward_milestone": {
                "distribution": "uniform",
                "min": 0.0,
                "max": 0.2,
                "scale": "auto",
            },
        },
    }

    spaces = pufferlib.sweep._params_from_puffer_sweep(config)

    assert list(spaces) == ["env"]
    assert list(spaces["env"]) == ["reward_milestone"]


def test_cnc_micro_sweep_reproduces_champion_and_retains_requested_range():
    loaded = load_config("cnc_micro")
    assert loaded["log_interval"] == 1.8
    assert loaded["eval_episodes"] == 10000
    assert loaded["env"]["action_scheme"] == 0
    assert loaded["env"]["action_abi"] == 13
    assert loaded["env"]["curriculum_schedule_id"] == 1
    assert loaded["env"]["curriculum_stage_decisions"] == 256
    assert loaded["env"]["starting_force_ramp_decisions"] == 2048
    assert loaded["env"]["difficulty_schedule_id"] == 1
    assert loaded["env"]["difficulty_ramp_decisions"] == 65536
    assert loaded["env"]["reward_invalid_action"] == 0
    assert loaded["env"]["reward_milestone"] == 0
    assert loaded["env"]["reward_player_infantry"] == 0
    assert loaded["env"]["reward_enemy_unit_loss"] == 0
    assert loaded["env"]["reward_tiberium_income"] == 0
    assert loaded["env"]["reward_vehicle"] == 0
    assert loaded["env"]["reward_tank_kill"] == 0
    assert loaded["env"]["reward_enemy_building_loss"] == 1.0
    assert loaded["env"]["reward_refinery"] == 0.41556156948208806
    assert loaded["env"]["reward_first_tank"] == 0.1
    assert loaded["env"]["reward_first_tank_shot"] == 0.1
    assert loaded["env"]["reward_qualified_loss"] == -1.0
    assert loaded["train"]["total_timesteps"] == 5_654_528
    assert loaded["train"]["schedule_timesteps"] == 10_485_760
    assert loaded["train"]["gamma"] == 0.8
    assert loaded["train"]["horizon"] == 32
    assert loaded["policy"]["hidden_size"] == 128
    assert loaded["policy"]["num_layers"] == 1
    assert loaded["vec"]["num_buffers"] == 1
    config = loaded["sweep"]
    assert config["downsample"] == 1
    assert config["sweep_only"] == "train.total_timesteps, env.reward_refinery"
    spaces = pufferlib.sweep._params_from_puffer_sweep(config)
    flat_spaces = dict(pufferlib.sweep.unroll_nested_dict(spaces))

    assert list(flat_spaces) == [
        "train/total_timesteps",
        "env/reward_refinery",
    ]
    assert flat_spaces["train/total_timesteps"].min == 5_242_880
    assert flat_spaces["train/total_timesteps"].max == 10_485_760
    assert flat_spaces["env/reward_refinery"].min == 0.3
    assert flat_spaces["env/reward_refinery"].max == 0.6


def test_log_interval_must_be_positive():
    loaded = load_config("cnc_micro")
    validate_config(loaded)
    loaded["log_interval"] = 0.0
    try:
        validate_config(loaded)
    except ValueError as error:
        assert str(error) == "log_interval must be positive"
    else:
        raise AssertionError("zero log_interval was accepted")
