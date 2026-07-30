#!/usr/bin/env python3

import json
import tempfile
import unittest
from pathlib import Path

import analyze_abi9_penalty_study as analysis
import evaluate_abi9_penalty_study as evaluation
import run_abi9_penalty_study as study


class Abi9PenaltyStudyTest(unittest.TestCase):
    def test_default_matrix_is_complete_and_unique(self):
        specs = study.experiment_specs(study.DEFAULT_PENALTIES, study.DEFAULT_SEEDS)

        self.assertEqual(len(specs), 15)
        self.assertEqual(len({spec.tag for spec in specs}), 15)
        self.assertEqual({spec.run_seed for spec in specs}, {73, 74, 75})
        self.assertEqual(
            {spec.penalty for spec in specs},
            {0.0, -0.000025, -0.00005, -0.0001, -0.00025},
        )

    def test_command_pins_historical_qj_configuration(self):
        root = Path("/tmp/PufferLib")
        spec = study.ExperimentSpec(run_seed=74, penalty=-0.0001)
        command = study.build_command(root, "cnc9", spec)
        joined = " ".join(command)

        self.assertEqual(command[0], str(root / ".venv/bin/python"))
        self.assertIn("--train.gpus 1", joined)
        self.assertIn("--train.total-timesteps 2097152", joined)
        self.assertIn("--seed 74", joined)
        self.assertIn("--train.seed 42", joined)
        self.assertIn("--env.action-abi 9", joined)
        self.assertIn("--env.reward-invalid-action=-0.0001", joined)
        self.assertIn("--vec.total-agents 64", joined)
        self.assertIn("--vec.num-buffers 1", joined)
        self.assertIn("--vec.num-threads 4", joined)
        self.assertIn("--train.horizon 32", joined)
        self.assertIn("--train.minibatch-size 2048", joined)
        self.assertIn("--policy.hidden-size 64", joined)
        self.assertIn("--policy.num-layers 1", joined)
        self.assertIn("--train.learning-rate 0.0009701129526611177", joined)
        self.assertIn("--train.ent-coef 0.0013548995888609634", joined)
        self.assertNotIn("--slowly", command)
        self.assertNotIn("--cpu", command)
        self.assertNotIn("sweep", command)

    def test_completed_run_requires_exact_contract_and_clean_failures(self):
        spec = study.ExperimentSpec(run_seed=73, penalty=0.0)
        with tempfile.TemporaryDirectory() as directory:
            log_dir = Path(directory)
            path = log_dir / "complete.json"
            path.write_text(
                json.dumps(
                    {
                        "wandb_project": "cnc9",
                        "tag": spec.tag,
                        "seed": 73,
                        "env": {
                            "action_abi": 9,
                            "reward_invalid_action": 0.0,
                        },
                        "train": {
                            "seed": 42,
                            "total_timesteps": study.TOTAL_TIMESTEPS,
                        },
                        "metrics": {
                            "agent_steps": [study.TOTAL_TIMESTEPS],
                            "env/start_failures": [0.0],
                            "env/failures": [0.0],
                        },
                    }
                )
            )

            self.assertEqual(
                study.find_completed_run(log_dir, "cnc9", spec), path
            )

            data = json.loads(path.read_text())
            data["metrics"]["env/start_failures"] = [1.0]
            path.write_text(json.dumps(data))
            self.assertIsNone(study.find_completed_run(log_dir, "cnc9", spec))

    def test_analysis_ranks_median_then_worst_seed(self):
        rows = [
            analysis.RunResult(-0.0001, 73, "a", 0.4, 0.3, 0.5, 0.4, 100, -0.1, 50_000, 100),
            analysis.RunResult(-0.0001, 74, "b", 0.2, 0.1, 0.3, 0.2, 100, -0.1, 50_000, 100),
            analysis.RunResult(-0.0001, 75, "c", 0.3, 0.2, 0.4, 0.3, 100, -0.1, 50_000, 100),
            analysis.RunResult(-0.00005, 73, "d", 0.3, 0.2, 0.4, 0.3, 100, -0.1, 50_000, 100),
            analysis.RunResult(-0.00005, 74, "e", 0.3, 0.2, 0.4, 0.3, 100, -0.1, 50_000, 100),
            analysis.RunResult(-0.00005, 75, "f", 0.3, 0.2, 0.4, 0.3, 100, -0.1, 50_000, 100),
        ]

        summaries = analysis.summarize(rows)

        self.assertEqual(summaries[0].penalty, -0.00005)
        self.assertEqual(summaries[0].median_balanced, 0.3)
        self.assertEqual(summaries[0].worst_balanced, 0.3)

    def test_fixed_evaluation_completion_requires_matching_paired_contract(self):
        raw = {
            "checkpoint_sha256": "abc",
            "eval_seed": evaluation.DEFAULT_EVAL_SEED,
            "requested_episodes": evaluation.DEFAULT_EPISODES,
            "episodes": evaluation.DEFAULT_EPISODES + 1,
            "failures": 0.0,
            "start_failures": 0.0,
        }

        self.assertTrue(
            evaluation.result_is_complete(
                raw,
                "abc",
                evaluation.DEFAULT_EVAL_SEED,
                evaluation.DEFAULT_EPISODES,
            )
        )
        self.assertFalse(
            evaluation.result_is_complete(
                raw,
                "different",
                evaluation.DEFAULT_EVAL_SEED,
                evaluation.DEFAULT_EPISODES,
            )
        )
        raw["failures"] = 1.0
        self.assertFalse(
            evaluation.result_is_complete(
                raw,
                "abc",
                evaluation.DEFAULT_EVAL_SEED,
                evaluation.DEFAULT_EPISODES,
            )
        )

    def test_fixed_evaluation_keys_pair_penalty_and_training_seed(self):
        keys = {
            evaluation.result_key(spec.penalty, spec.run_seed)
            for spec in study.experiment_specs(
                study.DEFAULT_PENALTIES, study.DEFAULT_SEEDS
            )
        }

        self.assertEqual(len(keys), 15)
        self.assertIn("p0-seed73", keys)
        self.assertIn("m000250-seed75", keys)


if __name__ == "__main__":
    unittest.main()
