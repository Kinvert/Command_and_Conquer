#!/usr/bin/env python3

import copy
import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("cnc16_architecture_ablation.py")
SPEC = importlib.util.spec_from_file_location("cnc16_architecture_ablation", SCRIPT)
ablation = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = ablation
SPEC.loader.exec_module(ablation)


class Cnc16ArchitectureAblationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.protocol, cls.snapshot, _ = ablation.load_protocol(
            ablation.default_manifest_path()
        )

    def test_protocol_is_two_architectures_by_three_seeds(self):
        specs = ablation.experiment_specs(self.protocol)
        self.assertEqual(self.protocol["version"], 2)
        self.assertEqual(self.protocol["suite_id"], "cnc16-architecture-v2")
        self.assertEqual(self.protocol["eval_seed"], 39173)
        self.assertEqual(len(specs), 6)
        self.assertEqual({spec.network for spec in specs}, {"MinGRU", "MLP"})
        self.assertEqual({spec.seed for spec in specs}, {173, 174, 175})
        self.assertEqual({spec.total_timesteps for spec in specs}, {2_097_152})

    def test_only_network_changes_between_matched_configs(self):
        specs = ablation.experiment_specs(self.protocol)
        mingru = ablation.resolved_config(self.snapshot, specs[0])
        mlp_spec = next(spec for spec in specs if spec.network == "MLP")
        mlp = ablation.resolved_config(self.snapshot, mlp_spec)

        expected = copy.deepcopy(mingru)
        expected["torch"]["network"] = "MLP"
        self.assertEqual(mlp, expected)

    def test_mlp_command_is_native_gpu_train_without_sweep(self):
        spec = next(
            spec
            for spec in ablation.experiment_specs(self.protocol)
            if spec.network == "MLP"
        )
        command = ablation.CONFIRMATION.build_train_command(
            Path("/tmp/PufferLib"),
            ablation.project_for(self.protocol, spec),
            ablation.resolved_config(self.snapshot, spec),
            spec,
        )

        self.assertIn("--wandb-project=cnc16", command)
        self.assertIn("--torch.network=MLP", command)
        self.assertIn("--train.gpus=1", command)
        self.assertIn("--train.total-timesteps=2097152", command)
        self.assertIn("--policy.hidden-size=64", command)
        self.assertIn("--policy.num-layers=1", command)
        self.assertNotIn("sweep", command)
        self.assertNotIn("--slowly", command)
        self.assertNotIn("--cpu", command)

    def test_mingru_reuses_frozen_cnc14_confirmation_tags(self):
        specs = [
            spec
            for spec in ablation.experiment_specs(self.protocol)
            if spec.network == "MinGRU"
        ]
        self.assertEqual(
            [spec.tag for spec in specs],
            [
                "cnc13-confirm-vqsw4ned-2m-s173",
                "cnc13-confirm-vqsw4ned-2m-s174",
                "cnc13-confirm-vqsw4ned-2m-s175",
            ],
        )
        self.assertTrue(
            all(ablation.project_for(self.protocol, spec) == "cnc14" for spec in specs)
        )

    def test_native_mlp_saves_the_biased_gelu_argument_for_backward(self):
        source = (ablation.ROOT / "PufferLib/src/models.cu").read_text()
        forward_kernel = source.split(
            "__global__ void mlp_bias_gelu_kernel", 1
        )[1].split("__global__ void mlp_gelu_backward_kernel", 1)[0]

        bias_expression = (
            "float x = to_float(pre_activation[idx]) "
            "+ to_float(bias[idx % hidden]);"
        )
        self.assertIn(bias_expression, forward_kernel)
        self.assertIn("pre_activation[idx] = from_float(x);", forward_kernel)


if __name__ == "__main__":
    unittest.main()
