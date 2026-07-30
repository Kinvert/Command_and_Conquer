from pufferlib.sweep import _params_from_puffer_sweep, unroll_nested_dict


def _uniform(minimum, maximum):
    return {
        "distribution": "uniform",
        "min": minimum,
        "max": maximum,
        "scale": "auto",
    }


def test_sweep_exclude_removes_only_the_named_nested_parameter():
    config = {
        "metric": "score",
        "goal": "maximize",
        "sweep_exclude": "train.total_timesteps",
        "train": {
            "total_timesteps": _uniform(1_000, 10_000),
            "learning_rate": _uniform(0.001, 0.01),
        },
        "env": {
            "reward": _uniform(0.0, 1.0),
        },
    }

    spaces = _params_from_puffer_sweep(config)
    names = set(dict(unroll_nested_dict(spaces)))

    assert names == {"train/learning_rate", "env/reward"}
