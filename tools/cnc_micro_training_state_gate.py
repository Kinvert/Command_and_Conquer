#!/usr/bin/env python3
"""Prove exact native CUDA training continuation for TD Micro."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PUFFER_ROOT = ROOT / "PufferLib"
EPOCHS_FINAL = 128
EPOCHS_SPLIT = 64
TOTAL_AGENTS = 64
HORIZON = 32
EPOCH_STEPS = TOTAL_AGENTS * HORIZON


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def configured_args(stop_epochs: int, mismatch: str = "") -> tuple[dict, object]:
    os.chdir(PUFFER_ROOT)
    from pufferlib import _C as backend
    from pufferlib import pufferl

    original_argv = sys.argv
    try:
        sys.argv = [original_argv[0]]
        args = pufferl.load_config("cnc_micro")
    finally:
        sys.argv = original_argv
    args["seed"] = 73
    args["rank"] = 0
    args["world_size"] = 1
    args["gpu_id"] = 0
    args["nccl_id"] = b""
    args["cudagraphs"] = 10
    args["reset_state"] = True
    args["save_training_state"] = True
    args["vec"].update(
        total_agents=TOTAL_AGENTS,
        num_buffers=1,
        num_threads=4,
    )
    args["train"].update(
        gpus=1,
        total_timesteps=stop_epochs * EPOCH_STEPS,
        schedule_timesteps=EPOCHS_FINAL * EPOCH_STEPS,
        horizon=HORIZON,
        minibatch_size=EPOCH_STEPS,
        replay_ratio=1.0,
    )
    if mismatch == "seed":
        args["seed"] = 42
    elif mismatch == "schedule":
        args["train"]["schedule_timesteps"] = (EPOCHS_FINAL + 1) * EPOCH_STEPS
    elif mismatch == "reward":
        args["env"]["reward_invalid_action"] = -0.0001
    pufferl.validate_config(args)
    pufferl._prepare_training_state_contract(args, backend)
    return args, backend


def run_phase(parsed: argparse.Namespace) -> dict:
    args, backend = configured_args(parsed.stop_epochs, parsed.mismatch)
    trainer = backend.create_pufferl(args)
    trace = hashlib.sha256()
    boundary_environment = None
    try:
        if parsed.load_state:
            backend.load_training_state(trainer, str(parsed.load_state))
        while int(trainer.epoch) < parsed.stop_epochs:
            epoch = int(trainer.epoch)
            backend.rollouts(trainer)
            action_bytes, reward_bytes, terminal_bytes = backend.read_env_step(trainer)
            if epoch >= EPOCHS_SPLIT:
                trace.update(action_bytes)
                trace.update(reward_bytes)
                trace.update(terminal_bytes)
            backend.train(trainer)
            if parsed.split_state and int(trainer.epoch) == EPOCHS_SPLIT:
                boundary_environment = dict(backend.eval_log(trainer)).get("env", {})
                backend.save_training_state(trainer, str(parsed.split_state))
        env_metrics = dict(backend.eval_log(trainer)).get("env", {})
        if int(trainer.epoch) == EPOCHS_SPLIT and boundary_environment is not None:
            env_metrics = boundary_environment
        backend.save_weights(trainer, str(parsed.weights))
        backend.save_training_state(trainer, str(parsed.final_state))
        return {
            "epoch": int(trainer.epoch),
            "global_step": int(trainer.global_step),
            "fingerprint": args["training_state_fingerprint"],
            "weights_sha256": sha256(parsed.weights),
            "state_sha256": sha256(parsed.final_state),
            "trace_sha256": trace.hexdigest(),
            "environment": dict(env_metrics),
        }
    finally:
        backend.close(trainer)


def child_command(work: Path, name: str, stop_epochs: int, **options: object) -> list[str]:
    command = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--phase",
        "--stop-epochs",
        str(stop_epochs),
        "--weights",
        str(work / f"{name}.bin"),
        "--final-state",
        str(work / f"{name}.state"),
    ]
    for key, value in options.items():
        if value is None:
            continue
        command.extend((f"--{key.replace('_', '-')}", str(value)))
    return command


def run_child(command: list[str], expect_failure: str = "") -> dict:
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"
    result = subprocess.run(command, cwd=PUFFER_ROOT, env=env, text=True, capture_output=True)
    if expect_failure:
        combined = result.stdout + result.stderr
        if result.returncode == 0 or expect_failure not in combined:
            raise RuntimeError(
                f"Expected failure containing {expect_failure!r}; rc={result.returncode}\n{combined}"
            )
        return {"rejected": True, "message": expect_failure}
    if result.returncode != 0:
        raise RuntimeError(result.stdout + result.stderr)
    lines = [line for line in result.stdout.splitlines() if line.startswith("TRAINING_STATE_PHASE=")]
    if len(lines) != 1:
        raise RuntimeError(f"Missing phase result:\n{result.stdout}\n{result.stderr}")
    return json.loads(lines[0].split("=", 1)[1])


def orchestrate(work: Path, output: Path) -> dict:
    work.mkdir(parents=True, exist_ok=True)
    full = run_child(
        child_command(
            work,
            "full-final",
            EPOCHS_FINAL,
            split_state=work / "full-split.state",
        )
    )
    split = run_child(child_command(work, "split", EPOCHS_SPLIT))
    resumed = run_child(
        child_command(
            work,
            "resumed-final",
            EPOCHS_FINAL,
            load_state=work / "split.state",
        )
    )

    comparisons = {
        "split_state_exact": sha256(work / "full-split.state") == split["state_sha256"],
        "final_state_exact": full["state_sha256"] == resumed["state_sha256"],
        "final_weights_exact": full["weights_sha256"] == resumed["weights_sha256"],
        "post_split_trace_exact": full["trace_sha256"] == resumed["trace_sha256"],
        "environment_metrics_exact": full["environment"] == resumed["environment"],
        "fingerprint_exact": full["fingerprint"] == split["fingerprint"] == resumed["fingerprint"],
    }
    failed = [name for name, matches in comparisons.items() if not matches]
    if failed:
        raise RuntimeError(f"Continuation mismatch: {', '.join(failed)}")

    environment = full["environment"]
    validity = {
        "episodes_completed": float(environment.get("n", 0.0)) > 0.0,
        "start_failures_zero": float(environment.get("start_failures", -1.0)) == 0.0,
        "failures_zero": float(environment.get("failures", -1.0)) == 0.0,
    }
    invalid = [name for name, passed in validity.items() if not passed]
    if invalid:
        raise RuntimeError(f"Invalid continuation run: {', '.join(invalid)}")

    truncated = work / "truncated.state"
    data = (work / "split.state").read_bytes()
    truncated.write_bytes(data[:-17])
    corrupted = work / "corrupted.state"
    corrupted_data = bytearray(data)
    corrupted_data[0] ^= 0xFF
    corrupted.write_bytes(corrupted_data)
    payload_corrupted = work / "payload-corrupted.state"
    payload_data = bytearray(data)
    payload_data[len(payload_data) // 3] ^= 0x01
    payload_corrupted.write_bytes(payload_data)

    rejection_cases = {
        "truncated": (truncated, "Truncated training state", ""),
        "corrupted": (corrupted, "Invalid training state header", ""),
        "payload_corrupted": (
            payload_corrupted,
            "Training state checksum mismatch",
            "",
        ),
        "seed_mismatch": (work / "split.state", "Training state fingerprint mismatch", "seed"),
        "schedule_mismatch": (
            work / "split.state",
            "Training state fingerprint mismatch",
            "schedule",
        ),
        "reward_mismatch": (
            work / "split.state",
            "Training state fingerprint mismatch",
            "reward",
        ),
    }
    rejected = {}
    for name, (state, message, mismatch) in rejection_cases.items():
        rejected[name] = run_child(
            child_command(
                work,
                f"reject-{name}",
                EPOCHS_FINAL,
                load_state=state,
                mismatch=mismatch or None,
            ),
            expect_failure=message,
        )

    report = {
        "suite": "cnc-micro-training-state-v1",
        "shape": {
            "total_agents": TOTAL_AGENTS,
            "num_buffers": 1,
            "num_threads": 4,
            "horizon": HORIZON,
            "minibatch_size": EPOCH_STEPS,
            "split_epochs": EPOCHS_SPLIT,
            "final_epochs": EPOCHS_FINAL,
            "split_timesteps": EPOCHS_SPLIT * EPOCH_STEPS,
            "final_timesteps": EPOCHS_FINAL * EPOCH_STEPS,
            "schedule_timesteps": EPOCHS_FINAL * EPOCH_STEPS,
            "gpu_train_mode": True,
        },
        "full": full,
        "split": split,
        "resumed": resumed,
        "comparisons": comparisons,
        "validity": validity,
        "rejections": rejected,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", type=Path, default=Path("/tmp/cnc-training-state-gate"))
    parser.add_argument(
        "--output",
        type=Path,
        default=PUFFER_ROOT / "logs/cnc_micro/training_state_gate/report.json",
    )
    parser.add_argument("--phase", action="store_true")
    parser.add_argument("--stop-epochs", type=int, default=EPOCHS_FINAL)
    parser.add_argument("--weights", type=Path)
    parser.add_argument("--final-state", type=Path)
    parser.add_argument("--split-state", type=Path)
    parser.add_argument("--load-state", type=Path)
    parser.add_argument("--mismatch", choices=("", "seed", "schedule", "reward"), default="")
    return parser.parse_args()


def main() -> None:
    parsed = parse_args()
    if parsed.phase:
        if parsed.weights is None or parsed.final_state is None:
            raise ValueError("--phase requires --weights and --final-state")
        parsed.weights.parent.mkdir(parents=True, exist_ok=True)
        print("TRAINING_STATE_PHASE=" + json.dumps(run_phase(parsed), sort_keys=True))
        return
    if parsed.work.exists():
        shutil.rmtree(parsed.work)
    report = orchestrate(parsed.work, parsed.output)
    print(json.dumps(report["comparisons"], sort_keys=True))
    print(parsed.output)


if __name__ == "__main__":
    main()
