#!/usr/bin/env python3

import copy
import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("cnc11_abi9_tournament.py")
SPEC = importlib.util.spec_from_file_location("cnc11_tournament", SCRIPT)
tournament = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = tournament
SPEC.loader.exec_module(tournament)


class Cnc11TournamentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.snapshot = tournament.load_snapshot(tournament.default_snapshot_path())

    def test_matrix_has_three_reproductions_and_twelve_tournament_runs(self):
        reproductions = tournament.experiment_specs(self.snapshot, "reproduce")
        tournament_runs = tournament.experiment_specs(self.snapshot, "tournament")

        self.assertEqual(len(reproductions), 3)
        self.assertEqual(len(tournament_runs), 12)
        self.assertEqual(len({spec.tag for spec in tournament_runs}), 12)
        self.assertEqual({spec.run_seed for spec in tournament_runs}, {73, 74, 75})
        self.assertEqual(
            {spec.candidate_id for spec in tournament_runs},
            {"5lk552uq", "xlidr1ce", "mnglsikv", "qj7bux1j"},
        )

    def test_command_pins_full_candidate_and_normal_gpu_training(self):
        candidate = self.snapshot["candidates"]["5lk552uq"]
        spec = tournament.RunSpec("tournament", "5lk552uq", 74, tournament.TOURNAMENT_STEPS)
        command = tournament.build_command(Path("/tmp/PufferLib"), "cnc11", candidate, spec)

        self.assertEqual(command[0], "/tmp/PufferLib/.venv/bin/python")
        self.assertIn("train", command)
        self.assertIn("cnc_micro", command)
        self.assertIn("--wandb-project=cnc11", command)
        self.assertIn("--seed=74", command)
        self.assertIn("--train.gpus=1", command)
        self.assertIn("--train.total-timesteps=2097152", command)
        self.assertIn("--env.action-abi=9", command)
        self.assertIn("--env.reward-invalid-action=0.0", command)
        self.assertIn("--vec.total-agents=64", command)
        self.assertIn("--vec.num-buffers=1", command)
        self.assertIn("--vec.num-threads=4", command)
        self.assertIn("--train.horizon=32", command)
        self.assertIn("--train.minibatch-size=2048", command)
        self.assertIn("--policy.hidden-size=64", command)
        self.assertIn("--policy.num-layers=1", command)
        self.assertNotIn("--slowly", command)
        self.assertNotIn("--cpu", command)
        self.assertNotIn("sweep", command)

    def test_exact_config_validation_rejects_drift(self):
        candidate = self.snapshot["candidates"]["mnglsikv"]
        spec = tournament.RunSpec("tournament", "mnglsikv", 75, tournament.TOURNAMENT_STEPS)
        data = {
            "wandb_project": "cnc11",
            "tag": spec.tag,
            "seed": 75,
            "slowly": False,
            **{
                section: copy.deepcopy(candidate[section])
                for section in ("env", "vec", "policy", "torch", "train")
            },
        }
        data["train"]["total_timesteps"] = tournament.TOURNAMENT_STEPS

        tournament.validate_run_config(data, "cnc11", candidate, spec)
        data["train"]["learning_rate"] *= 2
        with self.assertRaisesRegex(ValueError, "learning_rate"):
            tournament.validate_run_config(data, "cnc11", candidate, spec)

    def test_completion_requires_exact_steps_and_zero_failures(self):
        candidate = self.snapshot["candidates"]["xlidr1ce"]
        spec = tournament.RunSpec("reproduce", "xlidr1ce", 73, tournament.REPRO_STEPS)
        data = {
            "wandb_project": "cnc11",
            "tag": spec.tag,
            "seed": 73,
            "slowly": False,
            **{
                section: copy.deepcopy(candidate[section])
                for section in ("env", "vec", "policy", "torch", "train")
            },
            "metrics": {
                "agent_steps": [tournament.REPRO_STEPS],
                "env/start_failures": [0.0],
                "env/failures": [0.0],
            },
        }
        data["train"]["total_timesteps"] = tournament.REPRO_STEPS

        self.assertTrue(tournament.run_is_complete(data, "cnc11", candidate, spec))
        data["metrics"]["env/failures"] = [1.0]
        self.assertFalse(tournament.run_is_complete(data, "cnc11", candidate, spec))

    def test_evaluation_state_requires_matching_checkpoint_and_clean_run(self):
        raw = {
            "checkpoint_sha256": "abc",
            "eval_seed": tournament.DEFAULT_EVAL_SEED,
            "requested_episodes": tournament.DEFAULT_EVAL_EPISODES,
            "episodes": tournament.DEFAULT_EVAL_EPISODES,
            "failures": 0.0,
            "start_failures": 0.0,
        }

        self.assertTrue(
            tournament.evaluation_is_complete(
                raw,
                "abc",
                tournament.DEFAULT_EVAL_SEED,
                tournament.DEFAULT_EVAL_EPISODES,
            )
        )
        raw["checkpoint_sha256"] = "different"
        self.assertFalse(
            tournament.evaluation_is_complete(
                raw,
                "abc",
                tournament.DEFAULT_EVAL_SEED,
                tournament.DEFAULT_EVAL_EPISODES,
            )
        )


if __name__ == "__main__":
    unittest.main()
