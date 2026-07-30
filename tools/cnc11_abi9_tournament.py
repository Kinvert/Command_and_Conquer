#!/usr/bin/env python3
"""Run and evaluate the CNC11 ABI9 multi-seed promotion tournament."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shlex
import statistics
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass
from pathlib import Path


REPRO_STEPS = 1_048_576
TOURNAMENT_STEPS = 2_097_152
TOURNAMENT_SEEDS = (73, 74, 75)
DEFAULT_PROJECT = "cnc11"
DEFAULT_EVAL_SEED = 173
DEFAULT_EVAL_EPISODES = 512
DEFAULT_MAX_TRANSITIONS = 8_388_608


@dataclass(frozen=True)
class RunSpec:
    phase: str
    candidate_id: str
    run_seed: int
    total_timesteps: int

    @property
    def tag(self) -> str:
        if self.phase == "reproduce":
            return f"cnc11-abi9-{self.candidate_id}-repro-1m-s{self.run_seed}"
        return f"cnc11-abi9-{self.candidate_id}-2m-s{self.run_seed}"


@dataclass(frozen=True)
class TrainingResult:
    phase: str
    candidate_id: str
    run_seed: int
    run_id: str
    balanced_perf: float
    perf: float
    close_win_rate: float
    medium_win_rate: float
    episodes: int
    sps: float
    checkpoint_sha256: str


@dataclass(frozen=True)
class EvaluationResult:
    phase: str
    candidate_id: str
    train_seed: int
    run_id: str
    train_steps: int
    checkpoint_sha256: str
    eval_seed: int
    requested_episodes: int
    episodes: int
    transitions: int
    elapsed_seconds: float
    sps: float
    balanced_perf: float
    close_win_rate: float
    medium_win_rate: float
    perf: float
    invalid_actions: float
    units_built: float
    unit_kills: float
    unit_losses: float
    buildings_destroyed: float
    buildings_lost: float
    failures: float
    start_failures: float


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def default_snapshot_path() -> Path:
    return Path(__file__).with_name("cnc11_abi9_candidates.json")


def load_snapshot(path: Path) -> dict:
    data = json.loads(path.read_text())
    if data.get("version") != 1:
        raise ValueError(f"unsupported candidate snapshot: {path}")
    candidates = data.get("candidates")
    if not isinstance(candidates, dict) or len(candidates) != 4:
        raise ValueError("candidate snapshot must contain exactly four candidates")
    return data


def experiment_specs(snapshot: dict, phase: str) -> list[RunSpec]:
    if phase == "reproduce":
        return [
            RunSpec("reproduce", candidate_id, 73, REPRO_STEPS)
            for candidate_id, candidate in snapshot["candidates"].items()
            if candidate.get("reproduce")
        ]
    if phase == "tournament":
        return [
            RunSpec("tournament", candidate_id, seed, TOURNAMENT_STEPS)
            for candidate_id in snapshot["candidates"]
            for seed in TOURNAMENT_SEEDS
        ]
    raise ValueError(f"unsupported phase: {phase}")


def format_value(value) -> str:
    if isinstance(value, bool):
        return "1" if value else "0"
    return str(value)


def build_command(
    puffer_root: Path,
    project: str,
    candidate: dict,
    spec: RunSpec,
) -> list[str]:
    command = [
        str(puffer_root / ".venv/bin/python"),
        "-m",
        "pufferlib.pufferl",
        "train",
        "cnc_micro",
        "--wandb",
        f"--wandb-project={project}",
        f"--tag={spec.tag}",
        f"--seed={spec.run_seed}",
        "--checkpoint-interval=512",
        "--eval-episodes=10000",
        "--cudagraphs=10",
    ]
    for section in ("env", "vec", "policy", "torch", "train"):
        values = dict(candidate[section])
        if section == "train":
            values["total_timesteps"] = spec.total_timesteps
        for key, value in values.items():
            option = key.replace("_", "-")
            command.append(f"--{section}.{option}={format_value(value)}")
    return command


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


def values_equal(actual, expected) -> bool:
    if isinstance(expected, float):
        return math.isclose(float(actual), expected, rel_tol=0, abs_tol=1e-12)
    return actual == expected


def nested(data: dict, path: str):
    value = data
    for component in path.split("."):
        value = value[component]
    return value


def validate_run_config(data: dict, project: str, candidate: dict, spec: RunSpec) -> None:
    errors = []
    expected_paths = {
        f"{section}.{key}": value
        for section in ("env", "vec", "policy", "torch", "train")
        for key, value in candidate[section].items()
    }
    expected_paths["train.total_timesteps"] = spec.total_timesteps
    for path, expected in expected_paths.items():
        try:
            actual = nested(data, path)
        except KeyError:
            errors.append(f"{path}=<missing>, expected {expected!r}")
            continue
        if not values_equal(actual, expected):
            errors.append(f"{path}={actual!r}, expected {expected!r}")
    if data.get("wandb_project") != project:
        errors.append(f"wandb_project={data.get('wandb_project')!r}, expected {project!r}")
    if data.get("tag") != spec.tag:
        errors.append(f"tag={data.get('tag')!r}, expected {spec.tag!r}")
    if data.get("seed") != spec.run_seed:
        errors.append(f"seed={data.get('seed')!r}, expected {spec.run_seed}")
    if data.get("slowly"):
        errors.append("slowly must be false")
    if errors:
        raise ValueError("configuration drift:\n  " + "\n  ".join(errors))


def max_metric(metrics: dict, key: str) -> float:
    values = metrics.get(key, ())
    return max((float(value) for value in values), default=math.inf)


def run_is_complete(data: dict, project: str, candidate: dict, spec: RunSpec) -> bool:
    try:
        validate_run_config(data, project, candidate, spec)
    except (KeyError, TypeError, ValueError):
        return False
    metrics = data.get("metrics", {})
    steps = metrics.get("agent_steps", ())
    return (
        bool(steps)
        and int(steps[-1]) == spec.total_timesteps
        and max_metric(metrics, "env/start_failures") == 0
        and max_metric(metrics, "env/failures") == 0
    )


def find_completed_run(
    log_dir: Path,
    project: str,
    candidate: dict,
    spec: RunSpec,
) -> Path | None:
    candidates = sorted(
        log_dir.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True
    )
    for path in candidates:
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if run_is_complete(data, project, candidate, spec):
            return path
    return None


def run_one(
    puffer_root: Path,
    project: str,
    candidate_id: str,
    candidate: dict,
    spec: RunSpec,
    force: bool,
) -> Path:
    log_dir = puffer_root / "logs/cnc_micro"
    existing = None if force else find_completed_run(log_dir, project, candidate, spec)
    if existing is not None:
        print(f"skip {spec.tag}: {existing.name}", flush=True)
        return existing

    console_dir = log_dir / "cnc11_tournament_console"
    console_dir.mkdir(parents=True, exist_ok=True)
    console_path = console_dir / f"{spec.tag}.log"
    command = build_command(puffer_root, project, candidate, spec)
    print(f"run {spec.tag}", flush=True)
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
    completed = find_completed_run(log_dir, project, candidate, spec)
    if completed is None:
        raise RuntimeError(
            f"{spec.tag} exited without an exact zero-failure record; inspect {console_path}"
        )
    print(f"complete {spec.tag}: {completed.name}", flush=True)
    return completed


def run_phase(args: argparse.Namespace, snapshot: dict) -> int:
    puffer_root = args.puffer_root.resolve()
    specs = experiment_specs(snapshot, args.phase)
    if args.limit > 0:
        specs = specs[: args.limit]
    if not args.execute:
        for spec in specs:
            candidate = snapshot["candidates"][spec.candidate_id]
            print(shlex.join(build_command(puffer_root, args.project, candidate, spec)))
        return 0

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(
                run_one,
                puffer_root,
                args.project,
                spec.candidate_id,
                snapshot["candidates"][spec.candidate_id],
                spec,
                args.force,
            ): spec
            for spec in specs
        }
        for future in as_completed(futures):
            future.result()
    return 0


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def final_metric(data: dict, key: str) -> float:
    return float(data["metrics"][key][-1])


def checkpoint_path(puffer_root: Path, run_id: str, steps: int) -> Path:
    return puffer_root / "checkpoints/cnc_micro" / run_id / f"{steps:016d}.bin"


def load_training_results(
    puffer_root: Path,
    project: str,
    snapshot: dict,
    phase: str,
) -> tuple[list[TrainingResult], list[RunSpec]]:
    results = []
    missing = []
    for spec in experiment_specs(snapshot, phase):
        candidate = snapshot["candidates"][spec.candidate_id]
        path = find_completed_run(
            puffer_root / "logs/cnc_micro", project, candidate, spec
        )
        if path is None:
            missing.append(spec)
            continue
        data = json.loads(path.read_text())
        checkpoint = checkpoint_path(puffer_root, path.stem, spec.total_timesteps)
        if not checkpoint.exists():
            raise FileNotFoundError(f"missing final checkpoint: {checkpoint}")
        results.append(
            TrainingResult(
                phase=phase,
                candidate_id=spec.candidate_id,
                run_seed=spec.run_seed,
                run_id=path.stem,
                balanced_perf=final_metric(data, "env/balanced_perf"),
                perf=final_metric(data, "env/perf"),
                close_win_rate=final_metric(data, "env/close_win_rate"),
                medium_win_rate=final_metric(data, "env/medium_win_rate"),
                episodes=round(final_metric(data, "env/n")),
                sps=final_metric(data, "SPS"),
                checkpoint_sha256=sha256(checkpoint),
            )
        )
    return results, missing


def print_training_report(
    results: list[TrainingResult], snapshot: dict, phase: str
) -> None:
    print("candidate,seed,run,balanced,close,medium,perf,SPS,n,sha256")
    for result in sorted(results, key=lambda row: (row.candidate_id, row.run_seed)):
        print(
            f"{result.candidate_id},{result.run_seed},{result.run_id},"
            f"{result.balanced_perf:.9f},{result.close_win_rate:.9f},"
            f"{result.medium_win_rate:.9f},{result.perf:.9f},"
            f"{result.sps:.0f},{result.episodes},{result.checkpoint_sha256}"
        )
    if phase == "reproduce":
        print("\nsource reproduction deltas")
        for result in sorted(results, key=lambda row: row.candidate_id):
            expected = snapshot["candidates"][result.candidate_id]["expected"]
            print(
                f"{result.candidate_id}: balanced="
                f"{result.balanced_perf - expected['balanced_perf']:+.9f} "
                f"close={result.close_win_rate - expected['close_win_rate']:+.9f} "
                f"medium={result.medium_win_rate - expected['medium_win_rate']:+.9f}"
            )
        return

    print("\nrobustness ranking: median, then worst seed, then mean")
    grouped = {}
    for result in results:
        grouped.setdefault(result.candidate_id, []).append(result)
    ranking = []
    for candidate_id, group in grouped.items():
        scores = [row.balanced_perf for row in group]
        ranking.append(
            (
                statistics.median(scores),
                min(scores),
                statistics.fmean(scores),
                candidate_id,
                group,
            )
        )
    for median, worst, mean, candidate_id, group in sorted(ranking, reverse=True):
        scores = "/".join(
            f"{row.balanced_perf:.6f}" for row in sorted(group, key=lambda row: row.run_seed)
        )
        print(
            f"{candidate_id}: median={median:.6f} worst={worst:.6f} "
            f"mean={mean:.6f} scores={scores}"
        )


def analyze_phase(args: argparse.Namespace, snapshot: dict) -> int:
    results, missing = load_training_results(
        args.puffer_root.resolve(), args.project, snapshot, args.phase
    )
    print_training_report(results, snapshot, args.phase)
    if missing:
        print("\nmissing: " + ", ".join(spec.tag for spec in missing))
        return 0 if args.allow_incomplete else 2
    return 0


def evaluation_key(phase: str, candidate_id: str, train_seed: int, train_steps: int) -> str:
    return f"{phase}-{candidate_id}-s{train_seed}-{train_steps}"


def evaluation_is_complete(
    raw: dict,
    checkpoint_sha256: str,
    eval_seed: int,
    requested_episodes: int,
) -> bool:
    return (
        raw.get("checkpoint_sha256") == checkpoint_sha256
        and raw.get("eval_seed") == eval_seed
        and raw.get("requested_episodes") == requested_episodes
        and raw.get("episodes", 0) >= requested_episodes
        and raw.get("failures") == 0
        and raw.get("start_failures") == 0
    )


def load_state(path: Path) -> dict:
    if not path.exists():
        return {"version": 1, "results": {}}
    data = json.loads(path.read_text())
    if data.get("version") != 1 or not isinstance(data.get("results"), dict):
        raise ValueError(f"unsupported evaluation state: {path}")
    return data


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def configured_eval_args(pufferl, candidate: dict, eval_seed: int) -> dict:
    caller_argv = sys.argv
    try:
        sys.argv = [caller_argv[0]]
        args = pufferl.load_config("cnc_micro")
    finally:
        sys.argv = caller_argv
    args["wandb"] = False
    args["slowly"] = False
    args["seed"] = eval_seed
    args["reset_state"] = False
    for section in ("env", "vec", "policy", "torch", "train"):
        args[section].update(candidate[section])
    return args


def evaluate_checkpoint(
    pufferl,
    candidate_id: str,
    candidate: dict,
    phase: str,
    train_seed: int,
    train_steps: int,
    run_id: str,
    checkpoint: Path,
    eval_seed: int,
    requested_episodes: int,
    max_transitions: int,
) -> EvaluationResult:
    args = configured_eval_args(pufferl, candidate, eval_seed)
    backend = pufferl._resolve_backend(args)
    runtime = backend.create_pufferl(args)
    transitions = 0
    logs: dict[str, float] = {}
    started = time.perf_counter()
    try:
        backend.load_weights(runtime, str(checkpoint))
        while int(logs.get("env/n", 0)) < requested_episodes:
            backend.rollouts(runtime)
            transitions += args["vec"]["total_agents"] * args["train"]["horizon"]
            logs = dict(pufferl.unroll_nested_dict(backend.eval_log(runtime)))
            if (
                int(logs.get("env/n", 0)) < requested_episodes
                and transitions >= max_transitions
            ):
                raise RuntimeError(
                    f"{candidate_id} reached {transitions} transitions with only "
                    f"{int(logs.get('env/n', 0))}/{requested_episodes} episodes"
                )
    finally:
        backend.close(runtime)
    elapsed = time.perf_counter() - started

    def metric(name: str) -> float:
        return float(logs.get(f"env/{name}", 0.0))

    result = EvaluationResult(
        phase=phase,
        candidate_id=candidate_id,
        train_seed=train_seed,
        run_id=run_id,
        train_steps=train_steps,
        checkpoint_sha256=sha256(checkpoint),
        eval_seed=eval_seed,
        requested_episodes=requested_episodes,
        episodes=round(metric("n")),
        transitions=transitions,
        elapsed_seconds=elapsed,
        sps=transitions / elapsed,
        balanced_perf=metric("balanced_perf"),
        close_win_rate=metric("close_win_rate"),
        medium_win_rate=metric("medium_win_rate"),
        perf=metric("perf"),
        invalid_actions=metric("invalid_actions"),
        units_built=(
            metric("gunners_built")
            + metric("rocket_soldiers_built")
            # Each Refinery bundles one Harvester in the current ruleset.
            + metric("refineries_built")
        ),
        unit_kills=metric("unit_kills"),
        unit_losses=metric("unit_losses"),
        buildings_destroyed=metric("buildings_destroyed"),
        buildings_lost=metric("buildings_lost"),
        failures=metric("failures"),
        start_failures=metric("start_failures"),
    )
    if result.failures != 0 or result.start_failures != 0:
        raise RuntimeError(
            f"{candidate_id} evaluation failed: failures={result.failures}, "
            f"start_failures={result.start_failures}"
        )
    return result


def evaluation_targets(
    puffer_root: Path,
    project: str,
    snapshot: dict,
    phase: str,
) -> list[tuple[str, int, int, str, Path]]:
    targets = []
    if phase == "pre":
        results, missing = load_training_results(
            puffer_root, project, snapshot, "reproduce"
        )
        if missing:
            raise RuntimeError(
                "missing reproduction runs: " + ", ".join(spec.tag for spec in missing)
            )
        for result in results:
            targets.append(
                (
                    result.candidate_id,
                    result.run_seed,
                    REPRO_STEPS,
                    result.run_id,
                    checkpoint_path(puffer_root, result.run_id, REPRO_STEPS),
                )
            )
        control = snapshot["candidates"]["qj7bux1j"]
        targets.append(
            (
                "qj7bux1j",
                73,
                TOURNAMENT_STEPS,
                "qj7bux1j",
                puffer_root / control["control_checkpoint"],
            )
        )
        return targets
    if phase == "final":
        results, missing = load_training_results(
            puffer_root, project, snapshot, "tournament"
        )
        if missing:
            raise RuntimeError(
                "missing tournament runs: " + ", ".join(spec.tag for spec in missing)
            )
        for result in results:
            targets.append(
                (
                    result.candidate_id,
                    result.run_seed,
                    TOURNAMENT_STEPS,
                    result.run_id,
                    checkpoint_path(puffer_root, result.run_id, TOURNAMENT_STEPS),
                )
            )
        return targets
    raise ValueError(f"unsupported evaluation phase: {phase}")


def print_evaluation_report(results: list[EvaluationResult], phase: str) -> None:
    print("candidate,seed,run,steps,balanced,close,medium,perf,invalid,units,kills,SPS,n")
    for result in sorted(results, key=lambda row: (row.candidate_id, row.train_seed)):
        print(
            f"{result.candidate_id},{result.train_seed},{result.run_id},{result.train_steps},"
            f"{result.balanced_perf:.9f},{result.close_win_rate:.9f},"
            f"{result.medium_win_rate:.9f},{result.perf:.9f},"
            f"{result.invalid_actions:.3f},{result.units_built:.3f},"
            f"{result.unit_kills:.3f},{result.sps:.0f},{result.episodes}"
        )
    if phase != "final":
        return
    print("\npaired robustness ranking: median, then worst seed, then mean")
    grouped = {}
    for result in results:
        grouped.setdefault(result.candidate_id, []).append(result)
    ranking = []
    for candidate_id, group in grouped.items():
        scores = [result.balanced_perf for result in group]
        ranking.append(
            (
                statistics.median(scores),
                min(scores),
                statistics.fmean(scores),
                candidate_id,
                group,
            )
        )
    for median, worst, mean, candidate_id, group in sorted(ranking, reverse=True):
        scores = "/".join(
            f"{result.balanced_perf:.6f}"
            for result in sorted(group, key=lambda row: row.train_seed)
        )
        print(
            f"{candidate_id}: median={median:.6f} worst={worst:.6f} "
            f"mean={mean:.6f} scores={scores}"
        )


def evaluate_phase(args: argparse.Namespace, snapshot: dict) -> int:
    if args.episodes <= 0 or args.max_transitions <= 0:
        raise ValueError("episodes and max-transitions must be positive")
    puffer_root = args.puffer_root.resolve()
    state_path = args.state_file or (
        puffer_root
        / "logs/cnc_micro"
        / f"cnc11_{args.phase}_eval_seed{args.eval_seed}.json"
    )
    state = load_state(state_path)
    targets = evaluation_targets(puffer_root, args.project, snapshot, args.phase)

    sys.path.insert(0, str(puffer_root))
    import pufferlib.pufferl as pufferl

    completed = []
    for index, (candidate_id, train_seed, train_steps, run_id, checkpoint) in enumerate(
        targets, 1
    ):
        if not checkpoint.exists():
            raise FileNotFoundError(f"missing checkpoint: {checkpoint}")
        checkpoint_hash = sha256(checkpoint)
        key = evaluation_key(args.phase, candidate_id, train_seed, train_steps)
        raw = state["results"].get(key, {})
        if not args.force and evaluation_is_complete(
            raw, checkpoint_hash, args.eval_seed, args.episodes
        ):
            result = EvaluationResult(**raw)
            print(f"[{index:02d}/{len(targets):02d}] skip {key}: n={result.episodes}")
        else:
            print(f"[{index:02d}/{len(targets):02d}] evaluate {key}", flush=True)
            result = evaluate_checkpoint(
                pufferl,
                candidate_id,
                snapshot["candidates"][candidate_id],
                args.phase,
                train_seed,
                train_steps,
                run_id,
                checkpoint,
                args.eval_seed,
                args.episodes,
                args.max_transitions,
            )
            state["results"][key] = asdict(result)
            save_state(state_path, state)
            print(
                f"[{index:02d}/{len(targets):02d}] complete n={result.episodes} "
                f"balanced={result.balanced_perf:.6f} SPS={result.sps:.0f}",
                flush=True,
            )
        completed.append(result)
    print_evaluation_report(completed, args.phase)
    print(f"\nstate={state_path}")
    return 0


def parse_args() -> argparse.Namespace:
    root = repo_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path, default=default_snapshot_path())
    parser.add_argument("--puffer-root", type=Path, default=root / "PufferLib")
    parser.add_argument("--project", default=DEFAULT_PROJECT)
    subparsers = parser.add_subparsers(dest="command", required=True)

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--phase", choices=("reproduce", "tournament"), required=True)
    run_parser.add_argument("--execute", action="store_true")
    run_parser.add_argument("--force", action="store_true")
    run_parser.add_argument("--workers", type=int, default=3)
    run_parser.add_argument("--limit", type=int, default=0)

    analyze_parser = subparsers.add_parser("analyze")
    analyze_parser.add_argument(
        "--phase", choices=("reproduce", "tournament"), required=True
    )
    analyze_parser.add_argument("--allow-incomplete", action="store_true")

    evaluate_parser = subparsers.add_parser("evaluate")
    evaluate_parser.add_argument("--phase", choices=("pre", "final"), required=True)
    evaluate_parser.add_argument("--eval-seed", type=int, default=DEFAULT_EVAL_SEED)
    evaluate_parser.add_argument("--episodes", type=int, default=DEFAULT_EVAL_EPISODES)
    evaluate_parser.add_argument(
        "--max-transitions", type=int, default=DEFAULT_MAX_TRANSITIONS
    )
    evaluate_parser.add_argument("--state-file", type=Path, default=None)
    evaluate_parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if getattr(args, "workers", 1) <= 0:
        raise ValueError("workers must be positive")
    snapshot = load_snapshot(args.snapshot.resolve())
    if args.command == "run":
        return run_phase(args, snapshot)
    if args.command == "analyze":
        return analyze_phase(args, snapshot)
    if args.command == "evaluate":
        return evaluate_phase(args, snapshot)
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
