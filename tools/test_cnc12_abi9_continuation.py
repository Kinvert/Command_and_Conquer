#!/usr/bin/env python3

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("cnc12_abi9_continuation.py")
SPEC = importlib.util.spec_from_file_location("cnc12_continuation", SCRIPT)
continuation = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = continuation
SPEC.loader.exec_module(continuation)


class Cnc12ContinuationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.candidate = continuation.load_candidate()
        cls.checkpoint = Path("/tmp/cnc12-source.bin")

    def test_matrix_has_three_rates_and_three_seeds(self):
        self.assertEqual(len(continuation.specs()), 9)
        self.assertEqual({spec.rate for spec in continuation.specs()}, {0.00006, 0.00012, 0.00024})
        self.assertEqual({spec.seed for spec in continuation.specs()}, {73, 74, 75})

    def test_command_is_weights_only_fixed_lr_gpu_continuation(self):
        spec = continuation.RunSpec(0.00012, 74)
        command = continuation.build_command(Path("/tmp/PufferLib"), self.candidate, spec, self.checkpoint)
        self.assertIn("--load-model-path=/tmp/cnc12-source.bin", command)
        self.assertIn("--train.learning-rate=0.00012", command)
        self.assertIn("--train.anneal-lr=0", command)
        self.assertIn("--train.total-timesteps=1048576", command)
        self.assertIn("--train.gpus=1", command)
        self.assertNotIn("--cpu", command)
        self.assertNotIn("--slowly", command)
        self.assertNotIn("sweep", command)

    def test_command_keeps_environment_and_vector_contract(self):
        command = continuation.build_command(Path("/tmp/PufferLib"), self.candidate, continuation.RunSpec(0.00006, 73), self.checkpoint)
        self.assertIn("--env.action-abi=9", command)
        self.assertIn("--env.reward-invalid-action=0.0", command)
        self.assertIn("--vec.total-agents=64", command)
        self.assertIn("--vec.num-buffers=1", command)
        self.assertIn("--vec.num-threads=4", command)
        self.assertIn("--train.horizon=32", command)
        self.assertIn("--train.minibatch-size=2048", command)

    def test_tags_are_unique_and_explicitly_rate_seeded(self):
        tags = [spec.tag for spec in continuation.specs()]
        self.assertEqual(len(tags), len(set(tags)))
        self.assertIn("cnc12-abi9-5lk-continue-lr0p00006-s73", tags)
        self.assertIn("cnc12-abi9-5lk-continue-lr0p00024-s75", tags)

if __name__ == "__main__":
    unittest.main()
