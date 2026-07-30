#!/usr/bin/env python3

import ctypes
import importlib.util
import math
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace


SCRIPT = Path(__file__).with_name("cnc_micro_fixed_eval.py")
SPEC = importlib.util.spec_from_file_location("cnc_micro_fixed_eval", SCRIPT)
fixed_eval = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = fixed_eval
SPEC.loader.exec_module(fixed_eval)


class CncMicroFixedEvalTest(unittest.TestCase):
    def _episode(self, lane, profile, starting_force, credits, result):
        return fixed_eval.EpisodeResult(
            lane=lane,
            profile=profile,
            setup_seed=1 if profile == "close" else 2,
            buffer=0,
            sampling_seed=173,
            sampling_sequence=lane,
            starting_credits=credits,
            credit_band=fixed_eval.credit_band(credits),
            starting_force=starting_force,
            result=result,
            terminal_reward={"win": 1.0, "loss": -1.0, "draw": 0.0}[result],
            decisions=100,
            action_sha256="0" * 64,
        )

    @staticmethod
    def _set_starting_force(observation, enabled):
        if not enabled:
            return
        for slot, kind in enumerate(
            (fixed_eval.OBJECT_E1,) * 3 + (fixed_eval.OBJECT_E3,) * 3,
            start=1,
        ):
            offset = (
                fixed_eval.OWN_ENTITIES_OFFSET
                + slot * fixed_eval.ENTITY_RECORD_SIZE
            )
            observation[offset + fixed_eval.ENTITY_PRESENCE] = 1
            observation[offset + fixed_eval.ENTITY_TYPE] = kind

    def test_fixed_evaluator_forces_full_match_without_curriculum(self):
        class StubPuffer:
            @staticmethod
            def load_config(_):
                return {
                    "env": {
                        "curriculum_schedule_id": 1,
                        "curriculum_stage_decisions": 4096,
                        "starting_force_ramp_decisions": 8192,
                    },
                    "vec": {},
                    "policy": {},
                    "torch": {},
                    "train": {},
                }

        args = SimpleNamespace(
            eval_seed=173,
            max_decisions=12_000,
            num_threads=2,
            hidden_size=64,
            num_layers=1,
            network="MinGRU",
            action_scheme=0,
            difficulty="normal",
        )
        config = fixed_eval._load_config(StubPuffer, 8, 2, args)
        self.assertEqual(config["env"]["curriculum_schedule_id"], 0)
        self.assertEqual(config["env"]["curriculum_stage_decisions"], 0)
        self.assertEqual(config["env"]["starting_force_ramp_decisions"], 0)
        self.assertEqual(config["env"]["difficulty_schedule_id"], 2)
        self.assertEqual(config["env"]["difficulty_ramp_decisions"], 0)

    def test_fixed_evaluator_requires_cnc25_observation_version(self):
        self.assertEqual(fixed_eval.OBSERVATION_VERSION, 6)

    def test_abi9_checkpoint_layout_supports_current_hidden_sizes(self):
        self.assertEqual(fixed_eval.checkpoint_size(32, "MinGRU", 1), 362_496)
        self.assertEqual(fixed_eval.checkpoint_size(64, "MinGRU", 1), 749_568)
        self.assertEqual(fixed_eval.checkpoint_size(32, "MLP", 1), 354_432)
        self.assertEqual(fixed_eval.checkpoint_size(64, "MLP", 1), 717_056)
        self.assertEqual(fixed_eval.checkpoint_size(128, "MinGRU", 1), 1_597_440)
        self.assertEqual(fixed_eval.checkpoint_size(128, "MLP", 1), 1_466_880)
        self.assertEqual(fixed_eval.infer_hidden_size(362_496), 32)
        self.assertEqual(fixed_eval.infer_hidden_size(749_568), 64)
        self.assertEqual(fixed_eval.infer_hidden_size(1_597_440), 128)
        self.assertEqual(
            fixed_eval.infer_policy_shape(717_056),
            (64, "MLP", 1),
        )
        self.assertEqual(
            fixed_eval.infer_policy_shape(749_568),
            (64, "MinGRU", 1),
        )
        self.assertEqual(
            fixed_eval.infer_policy_shape(1_466_880),
            (128, "MLP", 1),
        )
        with self.assertRaisesRegex(ValueError, "ABI9 checkpoint size"):
            fixed_eval.infer_hidden_size(1_935_616)

    def test_abi14_checkpoint_layout_is_explicitly_selected(self):
        spec = fixed_eval.action_spec(1)
        self.assertEqual(spec.abi, 14)
        self.assertEqual(len(spec.head_sizes), 71)
        self.assertEqual(spec.action_mask_size, 471)
        self.assertEqual(spec.decoder_logit_count, 407)
        self.assertEqual(
            fixed_eval.checkpoint_size(64, "MinGRU", 1, action_scheme=1),
            782_336,
        )
        self.assertEqual(
            fixed_eval.infer_policy_shape(782_336, action_scheme=1),
            (64, "MinGRU", 1),
        )
        with self.assertRaisesRegex(ValueError, "ABI14 checkpoint size"):
            fixed_eval.infer_policy_shape(749_568, action_scheme=1)

    def test_policy_shape_rejects_architecture_mismatch(self):
        with self.assertRaisesRegex(ValueError, "unsupported ABI9 checkpoint size"):
            fixed_eval.infer_policy_shape(
                717_056,
                hidden_size=64,
                network="MinGRU",
                num_layers=1,
            )

    def test_suite_is_exact_balanced_and_has_explicit_sampling_seeds(self):
        suite = fixed_eval.build_suite(episodes_per_profile=4, eval_seed=173, num_buffers=2)

        self.assertEqual(len(suite), 8)
        self.assertEqual([row.setup_seed for row in suite], [1, 2] * 4)
        self.assertEqual([row.sampling_seed for row in suite], [173] * 4 + [174] * 4)
        self.assertEqual([row.sampling_sequence for row in suite], [0, 1, 2, 3] * 2)
        self.assertEqual(sum(row.profile == "close" for row in suite), 4)
        self.assertEqual(sum(row.profile == "medium" for row in suite), 4)
        self.assertEqual(suite, fixed_eval.build_suite(4, 173, 2))

    def test_credit_bands_cover_the_versioned_distribution(self):
        expected = {
            2_300: "constrained",
            2_400: "low",
            4_900: "low",
            5_000: "mid",
            7_400: "mid",
            7_500: "rich",
            10_000: "rich",
        }
        for credits, band in expected.items():
            with self.subTest(credits=credits):
                self.assertEqual(fixed_eval.credit_band(credits), band)

        for invalid in (2_200, 2_350, 10_100):
            with self.subTest(invalid=invalid):
                with self.assertRaisesRegex(ValueError, "starting credits"):
                    fixed_eval.credit_band(invalid)

    def test_suite_credits_are_read_from_actual_initial_observations(self):
        suite = fixed_eval.build_suite(episodes_per_profile=4, eval_seed=173, num_buffers=2)
        credit_hundreds = (23, 24, 49, 50, 74, 75, 100, 23)
        observations = []
        for value in credit_hundreds:
            observation = bytearray(fixed_eval.OBSERVATION_SIZE)
            observation[0] = fixed_eval.OBSERVATION_VERSION
            observation[fixed_eval.CREDITS_OBSERVATION_OFFSET] = value
            self._set_starting_force(observation, len(observations) % 2 == 0)
            observations.append(observation)

        labeled = fixed_eval.attach_starting_credits(suite, observations)

        self.assertEqual(
            [row.starting_credits for row in labeled],
            [value * 100 for value in credit_hundreds],
        )
        self.assertEqual(
            [row.credit_band for row in labeled],
            ["constrained", "low", "low", "mid", "mid", "rich", "rich", "constrained"],
        )
        self.assertEqual(
            [row.starting_force for row in labeled],
            ["unit_count_6", "mcv_only"] * 4,
        )
        self.assertTrue(all(row.starting_credits is None for row in suite))
        self.assertTrue(all(row.starting_force is None for row in suite))

        observations[0][0] = fixed_eval.OBSERVATION_VERSION - 1
        with self.assertRaisesRegex(ValueError, "observation version"):
            fixed_eval.attach_starting_credits(suite, observations)

        observations[0][0] = fixed_eval.OBSERVATION_VERSION
        first_e3 = (
            fixed_eval.OWN_ENTITIES_OFFSET
            + 4 * fixed_eval.ENTITY_RECORD_SIZE
            + fixed_eval.ENTITY_PRESENCE
        )
        observations[0][first_e3] = 0
        with self.assertRaisesRegex(ValueError, "starting force"):
            fixed_eval.attach_starting_credits(suite, observations)

    def test_native_credit_probe_accepts_puffer_bytetensor_layout(self):
        agents = 2
        storage = (ctypes.c_uint8 * (agents * fixed_eval.OBSERVATION_SIZE))()
        for lane, credit_hundreds in enumerate((23, 100)):
            offset = lane * fixed_eval.OBSERVATION_SIZE
            storage[offset] = fixed_eval.OBSERVATION_VERSION
            storage[offset + fixed_eval.CREDITS_OBSERVATION_OFFSET] = credit_hundreds

        class StubVec:
            total_agents = agents
            obs_size = fixed_eval.OBSERVATION_SIZE
            obs_dtype = "ByteTensor"
            obs_elem_size = 1
            obs_ptr = ctypes.addressof(storage)
            closed = False

            def reset(self):
                pass

            def close(self):
                self.closed = True

        vec = StubVec()

        class StubBackend:
            @staticmethod
            def create_vec(_config, gpu):
                self.assertEqual(gpu, 0)
                return vec

        observations = fixed_eval._capture_initial_observations(
            StubBackend, {}, agents
        )
        self.assertEqual(observations[0][fixed_eval.CREDITS_OBSERVATION_OFFSET], 23)
        self.assertEqual(observations[1][fixed_eval.CREDITS_OBSERVATION_OFFSET], 100)
        self.assertTrue(vec.closed)

    def test_credit_summary_reports_all_spawn_credit_cells(self):
        outcomes = {
            "close": {
                "constrained": (2_300, "win"),
                "low": (2_400, "loss"),
                "mid": (5_000, "draw"),
                "rich": (7_500, "win"),
            },
            "medium": {
                "constrained": (2_300, "win"),
                "low": (2_400, "win"),
                "mid": (5_000, "loss"),
                "rich": (7_500, "draw"),
            },
        }
        episodes = []
        lane = 0
        for profile, bands in outcomes.items():
            for starting_force in fixed_eval.STARTING_FORCE_VARIANTS:
                for credits, result in bands.values():
                    episodes.append(
                        self._episode(
                            lane, profile, starting_force, credits, result
                        )
                    )
                    lane += 1

        summary = fixed_eval.summarize_results(episodes)

        self.assertEqual(summary["profiles"]["close"]["wins"], 4)
        self.assertEqual(summary["profiles"]["medium"]["wins"], 4)
        self.assertEqual(summary["starting_forces"]["mcv_only"]["wins"], 4)
        self.assertEqual(summary["starting_forces"]["unit_count_6"]["wins"], 4)
        self.assertEqual(summary["credit_bands"]["constrained"]["wins"], 4)
        self.assertEqual(summary["credit_bands"]["mid"]["losses"], 2)
        self.assertEqual(summary["credit_bands"]["mid"]["draws"], 2)
        self.assertEqual(
            summary["spawn_credit_cells"]["close"]["low"]["losses"], 2
        )
        self.assertEqual(
            summary["spawn_credit_cells"]["medium"]["rich"]["draws"], 2
        )
        self.assertEqual(
            summary["spawn_force_cells"]["close"]["mcv_only"]["win_rate"],
            0.5,
        )
        self.assertEqual(
            summary["spawn_force_credit_cells"]["medium"]["unit_count_6"]["rich"]["draws"],
            1,
        )
        self.assertTrue(math.isclose(summary["balanced_perf"], 0.5))
        self.assertTrue(math.isclose(summary["credit_balanced_perf"], 0.5))
        self.assertLess(summary["credit_robust_perf"], 0.02)

        with self.assertRaisesRegex(ValueError, "missing spawn-force-credit cells"):
            fixed_eval.summarize_results(episodes[:-1])

    def test_robust_perf_is_shifted_harmonic_mean(self):
        self.assertTrue(math.isclose(fixed_eval.robust_perf(0.4, 0.4), 0.4))
        self.assertLess(fixed_eval.robust_perf(0.05, 0.75), 0.11)
        self.assertEqual(fixed_eval.robust_perf(0.0, 0.0), 0.0)
        self.assertEqual(
            fixed_eval.robust_perf(0.2, 0.6),
            fixed_eval.robust_perf(0.6, 0.2),
        )

    def test_native_log_gate_requires_exact_clean_episode_count(self):
        clean = {"n": 8.0, "failures": 0.0, "start_failures": 0.0}
        fixed_eval.validate_native_log(clean, expected_episodes=8)

        fixed_eval.validate_native_log({**clean, "n": 9.0}, 8)
        with self.assertRaisesRegex(RuntimeError, "at least 8"):
            fixed_eval.validate_native_log({**clean, "n": 7.0}, 8)
        with self.assertRaisesRegex(RuntimeError, "failures"):
            fixed_eval.validate_native_log({**clean, "failures": 1.0}, 8)
        with self.assertRaisesRegex(RuntimeError, "start_failures"):
            fixed_eval.validate_native_log({**clean, "start_failures": 1.0}, 8)


if __name__ == "__main__":
    unittest.main()
