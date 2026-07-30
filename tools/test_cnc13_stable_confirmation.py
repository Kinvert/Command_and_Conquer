#!/usr/bin/env python3

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("cnc13_stable_confirmation.py")
SPEC = importlib.util.spec_from_file_location("cnc13_stable_confirmation", SCRIPT)
confirmation = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = confirmation
SPEC.loader.exec_module(confirmation)


class Cnc13StableConfirmationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.snapshot = confirmation.load_snapshot(confirmation.default_snapshot_path())

    def test_manifest_resolves_five_complete_candidates(self):
        self.assertEqual(len(self.snapshot["candidates"]), 5)
        for candidate_id in self.snapshot["candidates"]:
            candidate = confirmation.resolved_candidate(self.snapshot, candidate_id)
            self.assertEqual(candidate["env"]["action_abi"], 9)
            self.assertEqual(candidate["policy"]["hidden_size"], 64)
            self.assertEqual(candidate["train"]["total_timesteps"], 2_097_152)
            self.assertEqual(candidate["train"]["horizon"], 32)
            self.assertEqual(candidate["vec"]["total_agents"], 64)

    def test_confirmation_matrix_is_five_by_three_fresh_seeds(self):
        specs = confirmation.experiment_specs(self.snapshot)
        self.assertEqual(len(specs), 15)
        self.assertEqual({spec.seed for spec in specs}, {173, 174, 175})
        self.assertEqual(len({spec.tag for spec in specs}), 15)

    def test_promotion_suite_is_predeclared_three_by_three(self):
        promotion = confirmation.promotion_protocol(self.snapshot)
        specs = confirmation.promotion_specs(self.snapshot)

        self.assertEqual(promotion["suite_id"], "cnc14-promotion-v1")
        self.assertEqual(promotion["eval_seed"], 19173)
        self.assertEqual(promotion["episodes_per_profile"], 512)
        self.assertNotEqual(
            promotion["eval_seed"],
            self.snapshot["protocol"]["validation_eval_seed"],
        )
        self.assertEqual(
            promotion["candidate_ids"],
            ["vqsw4ned", "o5e9lorj", "4pkdtoqj"],
        )
        self.assertEqual(len(specs), 9)
        self.assertEqual({spec.seed for spec in specs}, {173, 174, 175})
        self.assertEqual(
            {spec.candidate_id for spec in specs},
            {"vqsw4ned", "o5e9lorj", "4pkdtoqj"},
        )

    def test_promotion_outputs_cannot_overwrite_validation(self):
        spec = confirmation.promotion_specs(self.snapshot)[0]
        puffer_root = Path("/tmp/PufferLib")
        validation = confirmation.validation_eval_output(puffer_root, spec)
        promotion = confirmation.promotion_eval_output(
            puffer_root,
            self.snapshot["promotion"]["suite_id"],
            spec,
        )

        self.assertNotEqual(validation, promotion)
        self.assertEqual(
            promotion,
            Path("/tmp/PufferLib/logs/cnc_micro/cnc14_promotion_v1")
            / f"{spec.tag}.json",
        )

    def test_promotion_eval_command_pins_untouched_protocol(self):
        promotion = confirmation.promotion_protocol(self.snapshot)
        command = confirmation.build_eval_command(
            Path("/tmp/root"),
            Path("/tmp/PufferLib"),
            Path("/tmp/checkpoint.bin"),
            Path("/tmp/result.json"),
            promotion["episodes_per_profile"],
            promotion["eval_seed"],
        )

        self.assertIn("--episodes-per-profile=512", command)
        self.assertIn("--eval-seed=19173", command)
        self.assertIn("--num-buffers=4", command)
        self.assertIn("--num-threads=4", command)

    def test_train_command_pins_gpu_protocol_and_has_no_sweep(self):
        spec = confirmation.experiment_specs(self.snapshot)[0]
        candidate = confirmation.resolved_candidate(self.snapshot, spec.candidate_id)
        command = confirmation.build_train_command(
            Path("/tmp/PufferLib"), "cnc14", candidate, spec
        )

        self.assertEqual(command[:5], [
            "/tmp/PufferLib/.venv/bin/python",
            "-m",
            "pufferlib.pufferl",
            "train",
            "cnc_micro",
        ])
        self.assertIn("--wandb-project=cnc14", command)
        self.assertIn(f"--seed={spec.seed}", command)
        self.assertIn("--train.gpus=1", command)
        self.assertIn("--train.total-timesteps=2097152", command)
        self.assertIn("--env.action-abi=9", command)
        self.assertIn("--vec.total-agents=64", command)
        self.assertIn("--train.horizon=32", command)
        self.assertIn("--train.minibatch-size=2048", command)
        self.assertNotIn("sweep", command)
        self.assertNotIn("--slowly", command)
        self.assertNotIn("--cpu", command)

    def test_unstable_zero_seed_is_ineligible_even_with_higher_median(self):
        stable = [
            confirmation.EvalScore("stable", seed, 0.4, 0.4, 0.4)
            for seed in (173, 174, 175)
        ]
        spiky = [
            confirmation.EvalScore("spiky", 173, 0.8, 0.8, 0.8),
            confirmation.EvalScore("spiky", 174, 0.0, 0.0, 0.8),
            confirmation.EvalScore("spiky", 175, 0.8, 0.8, 0.8),
        ]

        ranking = confirmation.rank_scores(stable + spiky)
        self.assertEqual(ranking[0]["candidate_id"], "stable")
        self.assertTrue(ranking[0]["eligible"])
        self.assertFalse(ranking[1]["eligible"])


if __name__ == "__main__":
    unittest.main()
