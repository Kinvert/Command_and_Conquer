#!/usr/bin/env python3
"""Evaluate the ABI9 penalty-study checkpoints on one paired episode set.

Unlike the trainer's post-update evaluation window, every checkpoint starts from
fresh worlds and the same held-out policy-sampling seed. Results are written after
each checkpoint, so an interrupted 15-checkpoint campaign is resumable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import statistics
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path

import analyze_abi9_penalty_study as analysis
import run_abi9_penalty_study as study


DEFAULT_EVAL_SEED = 173
DEFAULT_EPISODES = 256
DEFAULT_MAX_TRANSITIONS = 4_194_304


@dataclass(frozen=True)
class EvaluationResult:
    penalty: float
    train_seed: int
    run_id: str
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
    failures: float
    start_failures: float


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def result_key(penalty: float, train_seed: int) -> str:
    return f"{study.penalty_slug(penalty)}-seed{train_seed}"


def result_is_complete(
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


def configured_args(pufferl, penalty: float, eval_seed: int) -> dict:
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
    for path, value in analysis.FIXED_CONFIG.items():
        section, key = path.split(".", 1)
        args[section][key] = value
    args["env"]["reward_invalid_action"] = penalty
    return args


def evaluate_checkpoint(
    pufferl,
    checkpoint: Path,
    spec: study.ExperimentSpec,
    eval_seed: int,
    requested_episodes: int,
    max_transitions: int,
) -> EvaluationResult:
    args = configured_args(pufferl, spec.penalty, eval_seed)
    backend = pufferl._resolve_backend(args)
    runtime = backend.create_pufferl(args)
    transitions = 0
    started = time.perf_counter()
    logs: dict[str, float] = {}
    try:
        backend.load_weights(runtime, str(checkpoint))
        while int(logs.get("env/n", 0)) < requested_episodes:
            backend.rollouts(runtime)
            transitions += args["vec"]["total_agents"] * args["train"]["horizon"]
            logs = dict(pufferl.unroll_nested_dict(backend.eval_log(runtime)))
            if (int(logs.get("env/n", 0)) < requested_episodes
                    and transitions >= max_transitions):
                raise RuntimeError(
                    f"{spec.tag} reached {transitions} transitions with only "
                    f"{int(logs.get('env/n', 0))}/{requested_episodes} episodes"
                )
    finally:
        backend.close(runtime)
    elapsed = time.perf_counter() - started

    def metric(name: str) -> float:
        return float(logs.get(f"env/{name}", 0.0))

    result = EvaluationResult(
        penalty=spec.penalty,
        train_seed=spec.run_seed,
        run_id=checkpoint.parent.name,
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
        failures=metric("failures"),
        start_failures=metric("start_failures"),
    )
    if result.failures != 0 or result.start_failures != 0:
        raise RuntimeError(
            f"{spec.tag} evaluation failed: failures={result.failures}, "
            f"start_failures={result.start_failures}"
        )
    return result


def print_summary(results: list[EvaluationResult]) -> None:
    print("penalty,seed,run,balanced,close,medium,perf,invalid,units,SPS,n")
    for result in sorted(results, key=lambda item: (item.penalty, item.train_seed), reverse=True):
        print(
            f"{result.penalty:.6f},{result.train_seed},{result.run_id},"
            f"{result.balanced_perf:.9f},{result.close_win_rate:.9f},"
            f"{result.medium_win_rate:.9f},{result.perf:.9f},"
            f"{result.invalid_actions:.3f},{result.units_built:.3f},"
            f"{result.sps:.0f},{result.episodes}"
        )
    print("\npenalty,median,worst,mean,scores")
    for penalty in study.DEFAULT_PENALTIES:
        group = sorted(
            (result for result in results if result.penalty == penalty),
            key=lambda result: result.train_seed,
        )
        if not group:
            continue
        scores = [result.balanced_perf for result in group]
        print(
            f"{penalty:.6f},{statistics.median(scores):.9f},{min(scores):.9f},"
            f"{statistics.fmean(scores):.9f},"
            + "/".join(f"{score:.9f}" for score in scores)
        )


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--puffer-root", type=Path, default=repo_root / "PufferLib")
    parser.add_argument("--project", default="cnc9")
    parser.add_argument("--eval-seed", type=int, default=DEFAULT_EVAL_SEED)
    parser.add_argument("--episodes", type=int, default=DEFAULT_EPISODES)
    parser.add_argument("--max-transitions", type=int, default=DEFAULT_MAX_TRANSITIONS)
    parser.add_argument("--state-file", type=Path, default=None)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.episodes <= 0 or args.max_transitions <= 0:
        raise ValueError("episodes and max-transitions must be positive")
    puffer_root = args.puffer_root.resolve()
    state_path = args.state_file or (
        puffer_root
        / "logs/cnc_micro"
        / f"abi9_penalty_fixed_eval_seed{args.eval_seed}.json"
    )
    state = load_state(state_path)
    rows, missing = analysis.load_results(
        puffer_root, args.project, study.DEFAULT_PENALTIES, study.DEFAULT_SEEDS
    )
    if missing:
        raise RuntimeError("missing training runs: " + ", ".join(spec.tag for spec in missing))
    training = {(row.penalty, row.run_seed): row for row in rows}
    specs = study.experiment_specs(study.DEFAULT_PENALTIES, study.DEFAULT_SEEDS)
    if args.limit > 0:
        specs = specs[: args.limit]

    sys.path.insert(0, str(puffer_root))
    import pufferlib.pufferl as pufferl

    completed: list[EvaluationResult] = []
    for index, spec in enumerate(specs, 1):
        row = training[(spec.penalty, spec.run_seed)]
        checkpoint = (
            puffer_root
            / "checkpoints/cnc_micro"
            / row.run_id
            / f"{study.TOTAL_TIMESTEPS:016d}.bin"
        )
        checkpoint_hash = sha256(checkpoint)
        if checkpoint_hash != row.checkpoint_sha256:
            raise RuntimeError(
                f"checkpoint changed after training-log validation: {checkpoint}"
            )
        key = result_key(spec.penalty, spec.run_seed)
        raw = state["results"].get(key, {})
        if not args.force and result_is_complete(
            raw, checkpoint_hash, args.eval_seed, args.episodes
        ):
            result = EvaluationResult(**raw)
            print(f"[{index:02d}/{len(specs):02d}] skip {spec.tag}: n={result.episodes}")
        else:
            print(f"[{index:02d}/{len(specs):02d}] evaluate {spec.tag}", flush=True)
            result = evaluate_checkpoint(
                pufferl,
                checkpoint,
                spec,
                args.eval_seed,
                args.episodes,
                args.max_transitions,
            )
            state["results"][key] = asdict(result)
            save_state(state_path, state)
            print(
                f"[{index:02d}/{len(specs):02d}] complete n={result.episodes} "
                f"balanced={result.balanced_perf:.6f} SPS={result.sps:.0f}",
                flush=True,
            )
        completed.append(result)

    print_summary(completed)
    print(f"\nstate={state_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
