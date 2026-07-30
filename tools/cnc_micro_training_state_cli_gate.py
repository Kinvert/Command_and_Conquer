#!/usr/bin/env python3
"""Exercise exact continuation through the normal PufferLib CLI."""

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
EPOCH_STEPS = 64 * 32
SPLIT_STEPS = 4 * EPOCH_STEPS
FINAL_STEPS = 8 * EPOCH_STEPS


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command(checkpoint_root: Path, log_root: Path, stop: int, load: Path | None = None) -> list[str]:
    result = [
        sys.executable,
        "-m",
        "pufferlib.pufferl",
        "train",
        "cnc_micro",
        "--seed",
        "73",
        "--save-training-state",
        "--checkpoint-dir",
        str(checkpoint_root),
        "--log-dir",
        str(log_root),
        "--checkpoint-interval",
        "3",
        "--eval-episodes",
        "0",
        "--cudagraphs",
        "10",
        "--train.gpus",
        "1",
        "--train.total-timesteps",
        str(stop),
        "--train.schedule-timesteps",
        str(FINAL_STEPS),
        "--train.horizon",
        "32",
        "--train.minibatch-size",
        "2048",
        "--train.replay-ratio",
        "1.0",
        "--vec.total-agents",
        "64",
        "--vec.num-buffers",
        "1",
        "--vec.num-threads",
        "4",
    ]
    if load is not None:
        result.extend(("--load-training-state-path", str(load)))
    return result


def execute(name: str, command_line: list[str], work: Path) -> None:
    result = subprocess.run(
        command_line,
        cwd=PUFFER_ROOT,
        env={**os.environ, "PYTHONUNBUFFERED": "1"},
        text=True,
        capture_output=True,
    )
    (work / f"{name}.console.txt").write_text(result.stdout + result.stderr)
    if result.returncode != 0:
        raise RuntimeError(f"{name} failed with {result.returncode}\n{result.stdout}\n{result.stderr}")


def one_file(root: Path, step: int, suffix: str) -> Path:
    matches = list(root.glob(f"cnc_micro/*/{step:016d}.{suffix}"))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one step-{step} {suffix} under {root}, found {matches}")
    return matches[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", type=Path, default=Path("/tmp/cnc-training-state-cli-gate"))
    parser.add_argument(
        "--output",
        type=Path,
        default=PUFFER_ROOT / "logs/cnc_micro/training_state_cli_gate/report.json",
    )
    args = parser.parse_args()
    if args.work.exists():
        shutil.rmtree(args.work)
    args.work.mkdir(parents=True)

    full_root = args.work / "full-checkpoints"
    split_root = args.work / "split-checkpoints"
    resume_root = args.work / "resume-checkpoints"
    log_root = args.work / "logs"
    execute("full", command(full_root, log_root / "full", FINAL_STEPS), args.work)
    execute("split", command(split_root, log_root / "split", SPLIT_STEPS), args.work)
    split_state = one_file(split_root, SPLIT_STEPS, "state")
    execute(
        "resume",
        command(resume_root, log_root / "resume", FINAL_STEPS, split_state),
        args.work,
    )

    paths = {
        "full_split_state": one_file(full_root, SPLIT_STEPS, "state"),
        "split_state": split_state,
        "full_final_state": one_file(full_root, FINAL_STEPS, "state"),
        "resume_final_state": one_file(resume_root, FINAL_STEPS, "state"),
        "full_final_weights": one_file(full_root, FINAL_STEPS, "bin"),
        "resume_final_weights": one_file(resume_root, FINAL_STEPS, "bin"),
    }
    hashes = {name: sha256(path) for name, path in paths.items()}
    comparisons = {
        "split_state_exact": hashes["full_split_state"] == hashes["split_state"],
        "final_state_exact": hashes["full_final_state"] == hashes["resume_final_state"],
        "final_weights_exact": hashes["full_final_weights"] == hashes["resume_final_weights"],
    }
    report = {
        "suite": "cnc-micro-training-state-cli-v1",
        "command": command(Path("CHECKPOINTS"), Path("LOGS"), FINAL_STEPS),
        "shape": {
            "total_agents": 64,
            "num_buffers": 1,
            "num_threads": 4,
            "horizon": 32,
            "minibatch_size": 2048,
            "replay_ratio": 1.0,
            "split_timesteps": SPLIT_STEPS,
            "final_timesteps": FINAL_STEPS,
            "schedule_timesteps": FINAL_STEPS,
            "gpu_train_mode": True,
        },
        "hashes": hashes,
        "comparisons": comparisons,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    failed = [name for name, value in comparisons.items() if not value]
    if failed:
        raise RuntimeError(f"CLI continuation mismatch: {', '.join(failed)}")
    print(json.dumps(comparisons, sort_keys=True))
    print(args.output)


if __name__ == "__main__":
    main()
