#!/usr/bin/env python3
"""Run the matched ABI9 invalid-action penalty experiment.

This is deliberately a fixed factorial study rather than an adaptive sweep. Every
material setting is copied from the historical qj7bux1j 2M configuration; only
Puffer's top-level run seed and the invalid-action coefficient vary. The nested
``train.seed`` field stays at its historical value because it does not control
the native CUDA policy trajectory.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path


TOTAL_TIMESTEPS = 2_097_152
DEFAULT_SEEDS = (73, 74, 75)
DEFAULT_PENALTIES = (0.0, -0.000025, -0.00005, -0.0001, -0.00025)


@dataclass(frozen=True)
class ExperimentSpec:
    run_seed: int
    penalty: float

    @property
    def tag(self) -> str:
        return f"abi9-penalty-2m-{penalty_slug(self.penalty)}-seed{self.run_seed}"


def penalty_slug(value: float) -> str:
    if value == 0:
        return "p0"
    digits = f"{abs(value):.6f}".split(".", 1)[1]
    return f"m{digits}"


def experiment_specs(
    penalties: tuple[float, ...], seeds: tuple[int, ...]
) -> list[ExperimentSpec]:
    return [ExperimentSpec(seed, penalty) for penalty in penalties for seed in seeds]


def build_command(
    puffer_root: Path, project: str, spec: ExperimentSpec
) -> list[str]:
    return [
        str(puffer_root / ".venv/bin/python"),
        "-m",
        "pufferlib.pufferl",
        "train",
        "cnc_micro",
        "--wandb",
        "--wandb-project",
        project,
        "--tag",
        spec.tag,
        "--seed",
        str(spec.run_seed),
        "--checkpoint-interval",
        "512",
        "--eval-episodes",
        "10000",
        "--train.gpus",
        "1",
        "--train.seed",
        "42",
        "--train.total-timesteps",
        str(TOTAL_TIMESTEPS),
        "--vec.total-agents",
        "64",
        "--vec.num-buffers",
        "1",
        "--vec.num-threads",
        "4",
        "--env.seed",
        "1",
        "--env.max-decisions",
        "12000",
        "--env.action-abi",
        "9",
        "--env.reward-milestone",
        "0.2",
        "--env.reward-player-infantry",
        "0.0",
        "--env.reward-enemy-unit-loss",
        "0.03176472410973994",
        "--env.reward-enemy-building-loss",
        "0.23219496897879333",
        "--env.reward-player-unit-loss=-0.005791169896719446",
        "--env.reward-refinery",
        "0.042555945418244596",
        "--env.reward-first-delivery",
        "0.0",
        "--env.reward-tiberium-income",
        "0.007081631623240768",
        f"--env.reward-invalid-action={spec.penalty:.8g}",
        "--policy.hidden-size",
        "64",
        "--policy.num-layers",
        "1",
        "--policy.expansion-factor",
        "1",
        "--torch.network",
        "MinGRU",
        "--torch.encoder",
        "Normalize255Encoder",
        "--torch.decoder",
        "DefaultDecoder",
        "--train.learning-rate",
        "0.0009701129526611177",
        "--train.anneal-lr",
        "1",
        "--train.min-lr-ratio",
        "0.0",
        "--train.gamma",
        "0.975977019771838",
        "--train.gae-lambda",
        "0.9297988511653911",
        "--train.replay-ratio",
        "4.0",
        "--train.clip-coef",
        "1.0",
        "--train.vf-coef",
        "4.241147435051642",
        "--train.vf-clip-coef",
        "3.579431156424427",
        "--train.max-grad-norm",
        "0.6691746653678212",
        "--train.ent-coef",
        "0.0013548995888609634",
        "--train.anneal-ent-coef",
        "0",
        "--train.min-ent-coef-ratio",
        "0.1",
        "--train.beta1",
        "0.9963317652430518",
        "--train.beta2",
        "0.9989380402338324",
        "--train.eps",
        "4.521619692179587e-07",
        "--train.minibatch-size",
        "2048",
        "--train.horizon",
        "32",
        "--train.vtrace-rho-clip",
        "0.9780523042532735",
        "--train.vtrace-c-clip",
        "0.1",
        "--train.prio-alpha",
        "0.25053580595043257",
        "--train.prio-beta0",
        "1.0",
        "--train.checkpoint-interval",
        "512",
    ]


def _max_metric(metrics: dict, key: str) -> float:
    values = metrics.get(key, ())
    return max((float(value) for value in values), default=math.inf)


def _matches_completed_run(data: dict, project: str, spec: ExperimentSpec) -> bool:
    metrics = data.get("metrics", {})
    agent_steps = metrics.get("agent_steps", ())
    return (
        data.get("wandb_project") == project
        and data.get("tag") == spec.tag
        and data.get("seed") == spec.run_seed
        and data.get("env", {}).get("action_abi") == 9
        and math.isclose(
            float(data.get("env", {}).get("reward_invalid_action", math.inf)),
            spec.penalty,
            rel_tol=0,
            abs_tol=1e-12,
        )
        and data.get("train", {}).get("seed") == 42
        and data.get("train", {}).get("total_timesteps") == TOTAL_TIMESTEPS
        and agent_steps
        and int(agent_steps[-1]) == TOTAL_TIMESTEPS
        and _max_metric(metrics, "env/start_failures") == 0
        and _max_metric(metrics, "env/failures") == 0
    )


def find_completed_run(
    log_dir: Path, project: str, spec: ExperimentSpec
) -> Path | None:
    candidates = sorted(
        log_dir.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True
    )
    for path in candidates:
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if _matches_completed_run(data, project, spec):
            return path
    return None


def training_environment(puffer_root: Path) -> dict[str, str]:
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
            "LD_LIBRARY_PATH": os.pathsep.join(libraries),
        }
    )
    return environment


def parse_csv(raw: str, cast) -> tuple:
    return tuple(cast(item.strip()) for item in raw.split(",") if item.strip())


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--puffer-root", type=Path, default=repo_root / "PufferLib")
    parser.add_argument("--project", default="cnc9")
    parser.add_argument("--seeds", default=",".join(map(str, DEFAULT_SEEDS)))
    parser.add_argument(
        "--penalties", default=",".join(f"{value:.8g}" for value in DEFAULT_PENALTIES)
    )
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--console-log-dir", type=Path, default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    puffer_root = args.puffer_root.resolve()
    seeds = parse_csv(args.seeds, int)
    penalties = parse_csv(args.penalties, float)
    specs = experiment_specs(penalties, seeds)
    if args.limit > 0:
        specs = specs[: args.limit]

    log_dir = puffer_root / "logs/cnc_micro"
    console_log_dir = args.console_log_dir or log_dir / "abi9_penalty_study_console"
    print(
        f"ABI9 penalty study: project={args.project} runs={len(specs)} "
        f"timesteps={TOTAL_TIMESTEPS} execute={args.execute}"
    )
    for index, spec in enumerate(specs, 1):
        completed = None if args.force else find_completed_run(log_dir, args.project, spec)
        if completed is not None:
            print(f"[{index:02d}/{len(specs):02d}] skip {spec.tag}: {completed.name}")
            continue

        command = build_command(puffer_root, args.project, spec)
        print(f"[{index:02d}/{len(specs):02d}] run {spec.tag}")
        if not args.execute:
            print(shlex.join(command))
        if args.execute:
            console_log_dir.mkdir(parents=True, exist_ok=True)
            console_path = console_log_dir / f"{spec.tag}.log"
            with console_path.open("a") as console:
                console.write(f"\n$ {shlex.join(command)}\n")
                console.flush()
                subprocess.run(
                    command,
                    cwd=puffer_root,
                    env=training_environment(puffer_root),
                    stdout=console,
                    stderr=subprocess.STDOUT,
                    check=True,
                )
            completed = find_completed_run(log_dir, args.project, spec)
            if completed is None:
                raise RuntimeError(
                    f"{spec.tag} exited without a complete zero-failure JSON; "
                    f"inspect {console_path}"
                )
            print(f"[{index:02d}/{len(specs):02d}] complete {completed.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
