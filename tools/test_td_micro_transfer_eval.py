#!/usr/bin/env python3

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).with_name("td_micro_transfer_eval.py")
SPEC = importlib.util.spec_from_file_location("td_micro_transfer_eval", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class TransferEvaluationTest(unittest.TestCase):
    def test_source_metadata_hashes_binary_diff(self):
        metadata = MODULE.source_metadata()
        self.assertRegex(metadata["commit"], r"^[0-9a-f]{40}$")
        self.assertIsInstance(metadata["dirty"], bool)
        if metadata["dirty"]:
            self.assertRegex(metadata["tracked_diff_sha256"], r"^[0-9a-f]{64}$")

    def test_record_offset_descriptions(self):
        self.assertEqual(MODULE.describe_record_offset(0), "observation.global[0]")
        self.assertEqual(MODULE.describe_record_offset(64 + 40), "observation.tiberium[40]")
        self.assertEqual(
            MODULE.describe_record_offset(MODULE.OWN_ENTITIES_OFFSET + 2 * 28 + 17),
            "observation.own_entity[2].byte[17]",
        )
        self.assertEqual(MODULE.describe_record_offset(3992), "action_mask[0]")

    def test_trace_comparison_reports_first_byte(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            left = bytearray(MODULE.RECORD_SIZE * 2)
            right = bytearray(left)
            offset = MODULE.RECORD_SIZE + MODULE.OWN_ENTITIES_OFFSET + 7
            right[offset] = 9
            (root / "left.bin").write_bytes(left)
            (root / "right.bin").write_bytes(right)
            result = MODULE.compare_traces(root / "left.bin", root / "right.bin")
            self.assertEqual(
                result,
                {
                    "decision": 1,
                    "frame": 4,
                    "kind": "byte",
                    "byte_offset": MODULE.OWN_ENTITIES_OFFSET + 7,
                    "field": "observation.own_entity[0].byte[7]",
                    "native": 0,
                    "vanilla": 9,
                },
            )

    def test_trace_comparison_reports_length(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "left.bin").write_bytes(bytes(MODULE.RECORD_SIZE))
            (root / "right.bin").write_bytes(bytes(MODULE.RECORD_SIZE * 2))
            result = MODULE.compare_traces(root / "left.bin", root / "right.bin")
            self.assertEqual(result["kind"], "record_count")
            self.assertEqual(result["decision"], 1)

    def test_action_trace_comparison_reports_first_action(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            left = bytes([0, 64, 64, 64, 1, 2, 3, 64])
            right = bytearray(left)
            right[4] = 2
            (root / "left.bin").write_bytes(left)
            (root / "right.bin").write_bytes(right)
            result = MODULE.compare_action_traces(root / "left.bin", root / "right.bin")
            self.assertEqual(
                result,
                {
                    "decision": 1,
                    "frame": 4,
                    "kind": "action",
                    "native": [1, 2, 3, 64],
                    "vanilla": [2, 2, 3, 64],
                },
            )

    def test_isolated_launcher_and_configs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            vanilla = root / "real-vanillatd"
            vanilla.touch()
            checkpoint = root / "checkpoint.bin"
            launcher = MODULE.write_configs(root / "run", root / "data", checkpoint, 2, vanilla)
            self.assertTrue(launcher.is_symlink())
            self.assertEqual(launcher.resolve(), vanilla.resolve())
            user_ini = (root / "run/user/conquer.ini").read_text(encoding="ascii")
            self.assertIn("GameSpeed=0", user_ini)
            self.assertIn("Seed=2", user_ini)
            self.assertIn(f"PolicyPath={checkpoint}", user_ini)

    def test_parse_vanilla_terminal(self):
        checkpoint = "a" * 64
        rules = "b" * 64
        text = (
            f"TD Micro policy: loaded checkpoint={checkpoint} abi=13 hidden=128 rules={rules} "
            "obs=3992 mask=1156 sampling=categorical seed=1007\n"
            "terminal reason=timeout frame=48000 decisions=12000 accepted=9000 changed=300 "
            "player_defeated=0 opponent_defeated=0 failed=0 harvested=5000 "
            "tanks_built=2 tanks_alive=1 tank_shots=3 full_perf=0\n"
        )
        result = MODULE.parse_vanilla(text, checkpoint, rules, 1007)
        self.assertEqual(result["result"], "draw")
        self.assertEqual(result["rejected_actions"], 3000)

    def test_aggregate_reports_balanced_and_divergence(self):
        records = []
        for profile, native, vanilla in (("close", "win", "loss"), ("medium", "win", "win")):
            records.append(
                {
                    "profile": profile,
                    "valid": True,
                    "terminal_agreement": native == vanilla,
                    "exact_trace": False,
                    "first_divergence": {"decision": 76, "kind": "byte", "field": "enemy.progress"},
                    "native": {"result": native, "failures": 0},
                    "vanilla": {"result": vanilla, "failures": 0},
                }
            )
        summary = MODULE.aggregate(records, "a" * 64, "b" * 64)
        self.assertEqual(summary["overall"]["vanilla"]["win_rate"], 0.5)
        self.assertEqual(summary["balanced_vanilla_win_rate"], 0.5)
        self.assertEqual(
            summary["profiles"]["close"]["first_divergence_summary"]["fields"],
            {"enemy.progress": 1},
        )

    def test_resume_retries_only_invalid_requests(self):
        requested = [("close", 1000), ("close", 1001), ("medium", 1000)]
        existing = {
            ("close", 1000): {"valid": True},
            ("close", 1001): {"valid": False},
        }
        self.assertEqual(
            MODULE.pending_requests(requested, existing),
            [("close", 1001), ("medium", 1000)],
        )

    def test_run_vanilla_stops_after_terminal_telemetry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            telemetry = root / "policy.log"
            command = [
                "python3",
                "-c",
                (
                    "from pathlib import Path; import time; "
                    f"Path({str(telemetry)!r}).write_text('terminal reason=win\\n'); "
                    "time.sleep(30)"
                ),
            ]
            started = MODULE.time.monotonic()
            result = MODULE.run_vanilla(command, root, dict(MODULE.os.environ), 5, telemetry)
            self.assertLess(MODULE.time.monotonic() - started, 2)
            self.assertTrue(result.terminal_seen)
            self.assertFalse(result.timed_out)
            self.assertTrue(result.terminated_after_marker)
            self.assertEqual(result.returncode, -15)


if __name__ == "__main__":
    unittest.main()
