#!/usr/bin/env python3
"""Run and evaluate explicit weights-only ABI9 continuation experiments."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shlex
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path


SOURCE_STEPS = 1_048_576
CONTINUATION_STEPS = 1_048_576
CONTINUATION_SEEDS = (73, 74, 75)
CONTINUATION_RATES = (0.00006, 0.00012, 0.00024)
PROJECT = "cnc12"
EVAL_SEED = 173
EVAL_EPISODES = 512


@dataclass(frozen=True)
class RunSpec:
    rate: float
    seed: int

    @property
    def rate_tag(self) -> str:
        return f"lr{self.rate:.5f}".replace(".", "p")

    @property
    def tag(self) -> str:
        return f"cnc12-abi9-5lk-continue-{self.rate_tag}-s{self.seed}"


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def snapshot_path() -> Path:
    return Path(__file__).with_name("cnc11_abi9_candidates.json")


def load_candidate() -> dict:
    snapshot = json.loads(snapshot_path().read_text())
    candidate = snapshot["candidates"]["5lk552uq"]
    if candidate["env"]["action_abi"] != 9:
        raise ValueError("continuation requires ABI9")
    if candidate["env"]["reward_invalid_action"] != 0.0:
        raise ValueError("continuation requires zero invalid-action penalty")
    return candidate


def source_checkpoint(puffer_root: Path) -> Path:
    return puffer_root / "checkpoints/cnc_micro/v9q3vd6v/0000000001048576.bin"


def specs() -> list[RunSpec]:
    return [RunSpec(rate, seed) for rate in CONTINUATION_RATES for seed in CONTINUATION_SEEDS]


def build_command(
    puffer_root: Path, candidate: dict, spec: RunSpec, checkpoint: Path
) -> list[str]:
    command = [
        str(puffer_root / ".venv/bin/python"),
        "-m",
        "pufferlib.pufferl",
        "train",
        "cnc_micro",
        "--wandb",
        f"--wandb-project={PROJECT}",
        f"--tag={spec.tag}",
        f"--seed={spec.seed}",
        f"--load-model-path={checkpoint}",
        "--checkpoint-interval=512",
        "--eval-episodes=10000",
        "--cudagraphs=10",
    ]
    for section in ("env", "vec", "policy", "torch", "train"):
        values = dict(candidate[section])
        if section == "train":
            values["total_timesteps"] = CONTINUATION_STEPS
            values["learning_rate"] = spec.rate
            values["anneal_lr"] = 0
        for key, value in values.items():
            command.append(f"--{section}.{key.replace('_', '-')}={value}")
    return command


def training_environment(puffer_root: Path) -> dict[str, str]:
    import os

    environment = os.environ.copy()
    nvidia = puffer_root / ".venv/lib/python3.12/site-packages/nvidia"
    libraries = [
        "/usr/lib/wsl/lib",
        str(nvidia / "cu13/lib"),
        str(nvidia / "nccl/lib"),
        str(nvidia / "cudnn/lib"),
        "/usr/local/cuda-12.8/targets/x86_64-linux/lib",
    ]
    if environment.get("LD_LIBRARY_PATH"):
        libraries.append(environment["LD_LIBRARY_PATH"])
    environment.update(
        {
            "PYTHONUNBUFFERED": "1",
            "OMP_NUM_THREADS": "4",
            "LD_LIBRARY_PATH": ":".join(libraries),
        }
    )
    return environment


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def nested(data: dict, path: str):
    value = data
    for component in path.split("."):
        value = value[component]
    return value


def close_enough(actual, expected) -> bool:
    if isinstance(expected, float):
        return math.isclose(float(actual), expected, rel_tol=0, abs_tol=1e-12)
    return actual == expected


def valid_training_log(
    path: Path,
    candidate: dict,
    spec: RunSpec,
    source: Path,
    output_checkpoint: Path,
) -> bool:
    try:
        data = json.loads(path.read_text())
        expected = {
            "wandb_project": PROJECT,
            "tag": spec.tag,
            "seed": spec.seed,
            "slowly": False,
            "load_model_path": str(source),
            "train.total_timesteps": CONTINUATION_STEPS,
            "train.learning_rate": spec.rate,
            "train.anneal_lr": 0,
            "env.action_abi": 9,
            "env.reward_invalid_action": 0.0,
            "vec.total_agents": 64,
            "vec.num_buffers": 1,
            "vec.num_threads": 4,
            "train.horizon": 32,
            "train.minibatch_size": 2048,
            "train.gpus": 1,
        }
        for path_key, expected_value in expected.items():
            if not close_enough(nested(data, path_key), expected_value):
                return False
        metrics = data["metrics"]
        if int(metrics["agent_steps"][-1]) != CONTINUATION_STEPS:
            return False
        if max(float(x) for x in metrics.get("env/start_failures", (0,))) != 0:
            return False
        if max(float(x) for x in metrics.get("env/failures", (0,))) != 0:
            return False
        return output_checkpoint.exists()
    except (KeyError, TypeError, ValueError, json.JSONDecodeError, OSError):
        return False


def find_completed_run(puffer_root: Path, candidate: dict, spec: RunSpec) -> Path | None:
    log_dir = puffer_root / "logs/cnc_micro"
    source = source_checkpoint(puffer_root)
    for path in sorted(log_dir.glob("*.json"), key=lambda item: item.stat().st_mtime, reverse=True):
        output_checkpoint = puffer_root / "checkpoints/cnc_micro" / path.stem / f"{CONTINUATION_STEPS:016d}.bin"
        if valid_training_log(path, candidate, spec, source, output_checkpoint):
            return path
    return None


def run_one(puffer_root: Path, candidate: dict, spec: RunSpec, force: bool) -> Path:
    source = source_checkpoint(puffer_root)
    if not source.exists():
        raise FileNotFoundError(f"missing source checkpoint: {source}")
    existing = None if force else find_completed_run(puffer_root, candidate, spec)
    if existing is not None:
        print(f"skip {spec.tag}: {existing.name}", flush=True)
        return existing

    console_dir = puffer_root / "logs/cnc_micro/cnc12_continuation_console"
    console_dir.mkdir(parents=True, exist_ok=True)
    console_path = console_dir / f"{spec.tag}.log"
    command = build_command(puffer_root, candidate, spec, source)
    print(f"run {spec.tag}", flush=True)
    with console_path.open("w") as console:
        console.write(f"$ {shlex.join(command)}\n")
        console.flush()
        subprocess.run(
            command,
            cwd=puffer_root,
            env=training_environment(puffer_root),
            stdout=console,
            stderr=subprocess.STDOUT,
            check=True,
        )
    completed = find_completed_run(puffer_root, candidate, spec)
    if completed is None:
        raise RuntimeError(f"{spec.tag} exited without an exact zero-failure record")
    return completed


def run_phase(puffer_root: Path, workers: int, force: bool) -> None:
    candidate = load_candidate()
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(run_one, puffer_root, candidate, spec, force): spec
            for spec in specs()
        }
        for future in as_completed(futures):
            spec = futures[future]
            path = future.result()
            print(f"complete {spec.tag}: {path.stem}", flush=True)


def load_results(puffer_root: Path) -> list[dict]:
    candidate = load_candidate()
    results = []
    for spec in specs():
        path = find_completed_run(puffer_root, candidate, spec)
        if path is None:
            raise RuntimeError(f"missing completed run: {spec.tag}")
        data = json.loads(path.read_text())
        checkpoint = puffer_root / "checkpoints/cnc_micro" / path.stem / f"{CONTINUATION_STEPS:016d}.bin"
        results.append(
            {
                "rate": spec.rate,
                "seed": spec.seed,
                "run_id": path.stem,
                "balanced": float(data["metrics"]["env/balanced_perf"][-1]),
                "close": float(data["metrics"]["env/close_win_rate"][-1]),
                "medium": float(data["metrics"]["env/medium_win_rate"][-1]),
                "perf": float(data["metrics"]["env/perf"][-1]),
                "sps": float(data["metrics"]["SPS"][-1]),
                "sha256": sha256(checkpoint),
            }
        )
    return sorted(results, key=lambda row: (row["rate"], row["seed"]))


def evaluate_phase(puffer_root: Path, results: list[dict]) -> list[dict]:
    tools_root = repo_root() / "tools"
    sys.path.insert(0, str(tools_root))
    import cnc11_abi9_tournament as tournament
    import pufferlib.pufferl as pufferl

    candidate = load_candidate()
    evaluated = []
    for row in results:
        checkpoint = puffer_root / "checkpoints/cnc_micro" / row["run_id"] / f"{CONTINUATION_STEPS:016d}.bin"
        result = tournament.evaluate_checkpoint(
            pufferl,
            f"lr{row['rate']}-s{row['seed']}",
            candidate,
            "continuation",
            row["seed"],
            CONTINUATION_STEPS,
            row["run_id"],
            checkpoint,
            EVAL_SEED,
            EVAL_EPISODES,
            8_388_608,
        )
        evaluated.append({
            "rate": row["rate"],
            "seed": row["seed"],
            "run_id": row["run_id"],
            "balanced": result.balanced_perf,
            "close": result.close_win_rate,
            "medium": result.medium_win_rate,
            "perf": result.perf,
            "invalid": result.invalid_actions,
            "units": result.units_built,
            "kills": result.unit_kills,
            "sps": result.sps,
            "episodes": result.episodes,
            "sha256": result.checkpoint_sha256,
            "failures": result.failures,
            "start_failures": result.start_failures,
        })
    return evaluated


def print_report(title: str, rows: list[dict]) -> None:
    print(title)
    for row in rows:
        print(
            f"lr={row['rate']:.5f} seed={row['seed']} run={row['run_id']} "
            f"balanced={row['balanced']:.9f} close={row['close']:.9f} "
            f"medium={row['medium']:.9f} perf={row['perf']:.9f} "
            f"SPS={row['sps']:.0f} sha256={row['sha256']}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("print", "train", "evaluate"))
    parser.add_argument("--puffer-root", type=Path, default=repo_root() / "PufferLib")
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    puffer_root = args.puffer_root.resolve()
    candidate = load_candidate()
    if args.command == "print":
        for spec in specs():
            print(shlex.join(build_command(puffer_root, candidate, spec, source_checkpoint(puffer_root))))
        return 0
    if args.command == "train":
        run_phase(puffer_root, args.workers, args.force)
        return 0
    results = load_results(puffer_root)
    evaluated = evaluate_phase(puffer_root, results)
    output = puffer_root / "logs/cnc_micro/cnc12_continuation_eval_seed173.json"
    output.write_text(json.dumps({"results": evaluated}, indent=2, sort_keys=True) + "\n")
    print_report("training", results)
    print_report("evaluation", evaluated)
    print(f"state={output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
