#!/usr/bin/env python3

import copy
import tempfile
import unittest
from pathlib import Path

from pufferlib import pufferl


def base_args() -> dict:
    return {
        "env_name": "cnc_micro",
        "seed": 73,
        "reset_state": True,
        "cudagraphs": 10,
        "rank": 0,
        "world_size": 1,
        "gpu_id": 0,
        "vec": {
            "total_agents": 64,
            "num_buffers": 1,
            "num_threads": 4,
        },
        "env": {
            "seed": 1,
            "action_abi": 9,
            "reward_invalid_action": 0.0,
        },
        "policy": {
            "hidden_size": 64,
            "num_layers": 1,
            "expansion_factor": 1,
        },
        "torch": {
            "network": "MinGRU",
            "encoder": "Normalize255Encoder",
            "decoder": "DefaultDecoder",
        },
        "train": {
            "gpus": 1,
            "seed": 42,
            "total_timesteps": 2_097_152,
            "schedule_timesteps": 8_388_608,
            "horizon": 32,
            "minibatch_size": 2048,
            "learning_rate": 0.001,
            "anneal_lr": 1,
            "gamma": 0.99,
        },
        "selfplay": {"enabled": 0},
        "checkpoint_dir": "checkpoints-a",
        "log_dir": "logs-a",
        "wandb": False,
        "tag": "first",
        "load_model_path": None,
        "load_training_state_path": None,
    }


class TrainingStateContractTest(unittest.TestCase):
    def test_weight_only_warm_start_loads_policy(self):
        class Backend:
            def __init__(self):
                self.weight_paths = []
                self.state_paths = []

            def load_weights(self, trainer, path):
                self.weight_paths.append((trainer, path))

            def load_training_state(self, trainer, path):
                self.state_paths.append((trainer, path))

        args = base_args()
        args["load_model_path"] = "source.bin"
        backend = Backend()
        trainer = object()

        pufferl._load_training_start(args, backend, trainer)

        self.assertEqual([(trainer, "source.bin")], backend.weight_paths)
        self.assertEqual([], backend.state_paths)

    def test_stop_rung_and_output_paths_do_not_change_fingerprint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backend = root / "backend.so"
            trainer = root / "pufferl.py"
            backend.write_bytes(b"native-v1")
            trainer.write_bytes(b"trainer-v1")
            first = base_args()
            second = copy.deepcopy(first)
            second["train"]["total_timesteps"] = 4_194_304
            second["checkpoint_dir"] = "checkpoints-b"
            second["log_dir"] = "logs-b"
            second["tag"] = "resume"
            second["load_training_state_path"] = "split.state"
            self.assertEqual(
                pufferl._training_state_fingerprint(first, backend, trainer),
                pufferl._training_state_fingerprint(second, backend, trainer),
            )

    def test_trajectory_or_executable_change_changes_fingerprint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backend = root / "backend.so"
            trainer = root / "pufferl.py"
            backend.write_bytes(b"native-v1")
            trainer.write_bytes(b"trainer-v1")
            args = base_args()
            expected = pufferl._training_state_fingerprint(args, backend, trainer)
            for section, key, value in (
                (None, "seed", 42),
                ("env", "reward_invalid_action", -0.0001),
                ("policy", "hidden_size", 32),
                ("train", "schedule_timesteps", 16_777_216),
                ("train", "gamma", 0.97),
            ):
                changed = copy.deepcopy(args)
                target = changed if section is None else changed[section]
                target[key] = value
                self.assertNotEqual(
                    expected,
                    pufferl._training_state_fingerprint(changed, backend, trainer),
                    (section, key),
                )
            backend.write_bytes(b"native-v2")
            self.assertNotEqual(
                expected,
                pufferl._training_state_fingerprint(args, backend, trainer),
            )

    def test_schedule_must_cover_stop_rung_and_align_to_epoch(self):
        args = base_args()
        pufferl.validate_config(args)

        too_short = copy.deepcopy(args)
        too_short["train"]["schedule_timesteps"] = 1_048_576
        with self.assertRaisesRegex(ValueError, "schedule_timesteps"):
            pufferl.validate_config(too_short)

        misaligned = copy.deepcopy(args)
        misaligned["train"]["schedule_timesteps"] += 1
        with self.assertRaisesRegex(ValueError, "schedule_timesteps"):
            pufferl.validate_config(misaligned)

    def test_zero_schedule_resolves_to_current_stop_for_legacy_runs(self):
        args = base_args()
        args["train"]["schedule_timesteps"] = 0
        self.assertEqual(
            args["train"]["total_timesteps"],
            pufferl._resolve_schedule_timesteps(args),
        )

    def test_legacy_unaligned_stop_remains_valid_without_explicit_schedule(self):
        args = base_args()
        args["train"]["schedule_timesteps"] = 0
        args["train"]["total_timesteps"] += 1
        pufferl.validate_config(args)

    def test_normal_training_does_not_pay_for_a_state_fingerprint(self):
        with tempfile.TemporaryDirectory() as directory:
            backend_path = Path(directory) / "backend.so"
            backend_path.write_bytes(b"native")

            class Backend:
                __file__ = str(backend_path)

            args = base_args()
            pufferl._prepare_training_state_contract(args, Backend)
            self.assertNotIn("training_state_fingerprint", args)


if __name__ == "__main__":
    unittest.main()
