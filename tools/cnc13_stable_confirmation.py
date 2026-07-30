#!/usr/bin/env python3
"""Train and evaluate the CNC13 stable-candidate confirmation matrix."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
import shlex
import statistics
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path


DEFAULT_PROJECT = "cnc14"
SECTIONS = ("env", "vec", "policy", "torch", "train")


@dataclass(frozen=True)
class RunSpec:
    candidate_id: str
    seed: int
    total_timesteps: int

    @property
    def tag(self) -> str:
        return f"cnc13-confirm-{self.candidate_id}-2m-s{self.seed}"


@dataclass(frozen=True)
class EvalScore:
    candidate_id: str
    seed: int
    robust_perf: float
    close_win_rate: float
    medium_win_rate: float


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def default_snapshot_path() -> Path:
    return Path(__file__).with_name("cnc13_stable_candidates.json")


def load_snapshot(path: Path) -> dict:
    data = json.loads(path.read_text())
    if data.get("version") != 1:
        raise ValueError(f"unsupported candidate snapshot: {path}")
    candidates = data.get("candidates")
    if not isinstance(candidates, dict) or len(candidates) != 5:
        raise ValueError("candidate snapshot must contain exactly five candidates")
    seeds = data.get("protocol", {}).get("training_seeds")
    if not isinstance(seeds, list) or len(seeds) != 3 or len(set(seeds)) != 3:
        raise ValueError("candidate snapshot must contain three distinct training seeds")
    for candidate_id in candidates:
        resolved_candidate(data, candidate_id)
    promotion_protocol(data)
    return data


def promotion_protocol(snapshot: dict) -> dict:
    promotion = copy.deepcopy(snapshot.get("promotion"))
    if not isinstance(promotion, dict):
        raise ValueError("candidate snapshot must contain a promotion protocol")
    required = {"suite_id", "eval_seed", "episodes_per_profile", "candidate_ids"}
    if set(promotion) != required:
        raise ValueError(f"promotion protocol keys must be exactly {sorted(required)}")
    suite_id = promotion["suite_id"]
    if not isinstance(suite_id, str) or not suite_id or any(
        character not in "abcdefghijklmnopqrstuvwxyz0123456789-" for character in suite_id
    ):
        raise ValueError("promotion suite_id must use lowercase letters, digits, and hyphens")
    candidate_ids = promotion["candidate_ids"]
    if (
        not isinstance(candidate_ids, list)
        or len(candidate_ids) != 3
        or len(set(candidate_ids)) != 3
        or any(candidate_id not in snapshot["candidates"] for candidate_id in candidate_ids)
    ):
        raise ValueError("promotion protocol must name three distinct known candidates")
    eval_seed = promotion["eval_seed"]
    episodes = promotion["episodes_per_profile"]
    if not isinstance(eval_seed, int) or eval_seed <= 0:
        raise ValueError("promotion eval_seed must be a positive integer")
    if eval_seed == snapshot["protocol"]["validation_eval_seed"]:
        raise ValueError("promotion eval_seed must be untouched by validation")
    if not isinstance(episodes, int) or episodes <= 0:
        raise ValueError("promotion episodes_per_profile must be a positive integer")
    return promotion


def resolved_candidate(snapshot: dict, candidate_id: str) -> dict:
    raw = snapshot["candidates"][candidate_id]
    result = copy.deepcopy(snapshot["common"])
    for section in SECTIONS:
        result.setdefault(section, {})
        result[section].update(copy.deepcopy(raw.get(section, {})))
    required = {
        "env": ("seed", "max_decisions", "action_abi", "reward_invalid_action"),
        "vec": ("total_agents", "num_buffers", "num_threads"),
        "policy": ("hidden_size", "num_layers"),
        "torch": ("network", "encoder", "decoder"),
        "train": (
            "gpus",
            "total_timesteps",
            "learning_rate",
            "horizon",
            "minibatch_size",
        ),
    }
    for section, keys in required.items():
        missing = [key for key in keys if key not in result[section]]
        if missing:
            raise ValueError(f"{candidate_id}.{section} is missing {missing}")
    return result


def experiment_specs(snapshot: dict) -> list[RunSpec]:
    total_timesteps = int(snapshot["protocol"]["total_timesteps"])
    return [
        RunSpec(candidate_id, int(seed), total_timesteps)
        for candidate_id in snapshot["candidates"]
        for seed in snapshot["protocol"]["training_seeds"]
    ]


def promotion_specs(snapshot: dict) -> list[RunSpec]:
    promotion = promotion_protocol(snapshot)
    total_timesteps = int(snapshot["protocol"]["total_timesteps"])
    return [
        RunSpec(candidate_id, int(seed), total_timesteps)
        for candidate_id in promotion["candidate_ids"]
        for seed in snapshot["protocol"]["training_seeds"]
    ]


def _format_value(value) -> str:
    if isinstance(value, bool):
        return "1" if value else "0"
    return str(value)


def build_train_command(
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
        f"--seed={spec.seed}",
        "--checkpoint-interval=512",
        "--eval-episodes=10000",
        "--cudagraphs=10",
    ]
    for section in SECTIONS:
        values = copy.deepcopy(candidate[section])
        if section == "train":
            values["total_timesteps"] = spec.total_timesteps
        for key, value in values.items():
            option = key.replace("_", "-")
            command.append(f"--{section}.{option}={_format_value(value)}")
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


def _values_equal(actual, expected) -> bool:
    if isinstance(expected, float):
        return math.isclose(float(actual), expected, rel_tol=0.0, abs_tol=1.0e-12)
    return actual == expected


def validate_run_config(data: dict, project: str, candidate: dict, spec: RunSpec) -> None:
    errors = []
    for section in SECTIONS:
        expected_values = copy.deepcopy(candidate[section])
        if section == "train":
            expected_values["total_timesteps"] = spec.total_timesteps
        for key, expected in expected_values.items():
            actual = data.get(section, {}).get(key, "<missing>")
            if not _values_equal(actual, expected):
                errors.append(f"{section}.{key}={actual!r}, expected {expected!r}")
    for key, expected in (
        ("wandb_project", project),
        ("tag", spec.tag),
        ("seed", spec.seed),
    ):
        if data.get(key) != expected:
            errors.append(f"{key}={data.get(key)!r}, expected {expected!r}")
    if data.get("slowly"):
        errors.append("slowly must be false")
    if errors:
        raise ValueError("configuration drift:\n  " + "\n  ".join(errors))


def _max_metric(metrics: dict, key: str) -> float:
    values = metrics.get(key, ())
    return max((float(value) for value in values), default=math.inf)


def run_is_complete(data: dict, project: str, candidate: dict, spec: RunSpec) -> bool:
    try:
        validate_run_config(data, project, candidate, spec)
    except (TypeError, ValueError):
        return False
    metrics = data.get("metrics", {})
    steps = metrics.get("agent_steps", ())
    return (
        bool(steps)
        and int(steps[-1]) == spec.total_timesteps
        and _max_metric(metrics, "env/start_failures") == 0.0
        and _max_metric(metrics, "env/failures") == 0.0
    )


def find_completed_run(
    log_dir: Path,
    project: str,
    candidate: dict,
    spec: RunSpec,
) -> Path | None:
    paths = sorted(log_dir.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
    for path in paths:
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if run_is_complete(data, project, candidate, spec):
            return path
    return None


def checkpoint_path(puffer_root: Path, run_id: str, steps: int) -> Path:
    return puffer_root / "checkpoints/cnc_micro" / run_id / f"{steps:016d}.bin"


def _run_one(
    puffer_root: Path,
    project: str,
    candidate: dict,
    spec: RunSpec,
    force: bool,
) -> Path:
    log_dir = puffer_root / "logs/cnc_micro"
    existing = None if force else find_completed_run(log_dir, project, candidate, spec)
    if existing is not None:
        checkpoint = checkpoint_path(puffer_root, existing.stem, spec.total_timesteps)
        if checkpoint.exists():
            print(f"skip {spec.tag}: {existing.stem}", flush=True)
            return existing

    console_dir = log_dir / "cnc13_confirmation_console"
    console_dir.mkdir(parents=True, exist_ok=True)
    console_path = console_dir / f"{spec.tag}.log"
    command = build_train_command(puffer_root, project, candidate, spec)
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
        raise RuntimeError(f"no exact zero-failure result for {spec.tag}; inspect {console_path}")
    checkpoint = checkpoint_path(puffer_root, completed.stem, spec.total_timesteps)
    if not checkpoint.exists():
        raise FileNotFoundError(f"missing final checkpoint: {checkpoint}")
    print(f"complete {spec.tag}: {completed.stem}", flush=True)
    return completed


def run_matrix(args, snapshot: dict) -> int:
    puffer_root = args.puffer_root.resolve()
    specs = experiment_specs(snapshot)
    if args.limit:
        specs = specs[: args.limit]
    if not args.execute:
        for spec in specs:
            candidate = resolved_candidate(snapshot, spec.candidate_id)
            print(shlex.join(build_train_command(puffer_root, args.project, candidate, spec)))
        return 0
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(
                _run_one,
                puffer_root,
                args.project,
                resolved_candidate(snapshot, spec.candidate_id),
                spec,
                args.force,
            ): spec
            for spec in specs
        }
        for future in as_completed(futures):
            future.result()
    return 0


def _final_metric(data: dict, key: str) -> float:
    return float(data["metrics"][key][-1])


def _training_rows(puffer_root: Path, project: str, snapshot: dict) -> list[dict]:
    rows = []
    for spec in experiment_specs(snapshot):
        candidate = resolved_candidate(snapshot, spec.candidate_id)
        path = find_completed_run(puffer_root / "logs/cnc_micro", project, candidate, spec)
        if path is None:
            continue
        data = json.loads(path.read_text())
        checkpoint = checkpoint_path(puffer_root, path.stem, spec.total_timesteps)
        close = _final_metric(data, "env/close_win_rate")
        medium = _final_metric(data, "env/medium_win_rate")
        rows.append(
            {
                "candidate_id": spec.candidate_id,
                "seed": spec.seed,
                "run_id": path.stem,
                "balanced_perf": _final_metric(data, "env/balanced_perf"),
                "robust_perf": _robust(close, medium),
                "close_win_rate": close,
                "medium_win_rate": medium,
                "episodes": round(_final_metric(data, "env/n")),
                "sps": _final_metric(data, "SPS"),
                "checkpoint": str(checkpoint),
                "checkpoint_sha256": _sha256(checkpoint) if checkpoint.exists() else "missing",
            }
        )
    return rows


def _robust(close: float, medium: float, epsilon: float = 0.01) -> float:
    return max(0.0, 2.0 / (1.0 / (close + epsilon) + 1.0 / (medium + epsilon)) - epsilon)


def analyze_training(args, snapshot: dict) -> int:
    rows = _training_rows(args.puffer_root.resolve(), args.project, snapshot)
    print("candidate,seed,run,robust,balanced,close,medium,n,SPS,sha256")
    for row in sorted(rows, key=lambda value: (value["candidate_id"], value["seed"])):
        print(
            f"{row['candidate_id']},{row['seed']},{row['run_id']},"
            f"{row['robust_perf']:.6f},{row['balanced_perf']:.6f},"
            f"{row['close_win_rate']:.6f},{row['medium_win_rate']:.6f},"
            f"{row['episodes']},{row['sps']:.0f},{row['checkpoint_sha256']}"
        )
    print(f"\ncompleted={len(rows)}/{len(experiment_specs(snapshot))}")
    return 0


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validation_eval_output(puffer_root: Path, spec: RunSpec) -> Path:
    return puffer_root / "logs/cnc_micro/cnc13_confirmation_eval" / f"{spec.tag}.json"


def promotion_eval_output(puffer_root: Path, suite_id: str, spec: RunSpec) -> Path:
    directory = suite_id.replace("-", "_")
    return puffer_root / "logs/cnc_micro" / directory / f"{spec.tag}.json"


def promotion_manifest_output(puffer_root: Path, suite_id: str) -> Path:
    directory = suite_id.replace("-", "_")
    return puffer_root / "logs/cnc_micro" / directory / "suite_manifest.json"


def build_eval_command(
    root: Path,
    puffer_root: Path,
    checkpoint: Path,
    output: Path,
    episodes_per_profile: int,
    eval_seed: int,
) -> list[str]:
    return [
        str(puffer_root / ".venv/bin/python"),
        str(root / "tools/cnc_micro_fixed_eval.py"),
        str(checkpoint),
        f"--puffer-root={puffer_root}",
        f"--output={output}",
        f"--episodes-per-profile={episodes_per_profile}",
        f"--eval-seed={eval_seed}",
        "--num-buffers=4",
        "--num-threads=4",
    ]


def _evaluate_one(
    root: Path,
    puffer_root: Path,
    spec: RunSpec,
    run_path: Path,
    episodes_per_profile: int,
    eval_seed: int,
    force: bool,
    output: Path,
) -> Path:
    checkpoint = checkpoint_path(puffer_root, run_path.stem, spec.total_timesteps)
    if output.exists() and not force:
        data = json.loads(output.read_text())
        if (
            data.get("checkpoint_sha256") == _sha256(checkpoint)
            and data.get("eval_seed") == eval_seed
            and data.get("episodes_per_profile") == episodes_per_profile
            and data.get("valid") is True
        ):
            print(f"skip eval {spec.tag}", flush=True)
            return output
    output.parent.mkdir(parents=True, exist_ok=True)
    command = build_eval_command(
        root, puffer_root, checkpoint, output, episodes_per_profile, eval_seed
    )
    print(f"eval {spec.tag}", flush=True)
    subprocess.run(
        command,
        cwd=puffer_root,
        env=training_environment(puffer_root),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
        check=True,
    )
    return output


def _load_eval_scores(paths: list[tuple[RunSpec, Path]]) -> list[EvalScore]:
    scores = []
    for spec, path in paths:
        data = json.loads(path.read_text())
        scores.append(
            EvalScore(
                candidate_id=spec.candidate_id,
                seed=spec.seed,
                robust_perf=float(data["robust_perf"]),
                close_win_rate=float(data["profiles"]["close"]["win_rate"]),
                medium_win_rate=float(data["profiles"]["medium"]["win_rate"]),
            )
        )
    return scores


def rank_scores(scores: list[EvalScore]) -> list[dict]:
    grouped: dict[str, list[EvalScore]] = {}
    for score in scores:
        grouped.setdefault(score.candidate_id, []).append(score)
    ranking = []
    for candidate_id, rows in grouped.items():
        robust = [row.robust_perf for row in rows]
        minimum_profiles = [
            min(row.close_win_rate, row.medium_win_rate) for row in rows
        ]
        eligible = len(rows) == 3 and all(value > 0.0 for value in minimum_profiles)
        ranking.append(
            {
                "candidate_id": candidate_id,
                "eligible": eligible,
                "median_robust": statistics.median(robust),
                "worst_robust": min(robust),
                "mean_robust": statistics.fmean(robust),
                "worst_seed_profile": min(minimum_profiles),
                "scores": sorted(rows, key=lambda row: row.seed),
            }
        )
    return sorted(
        ranking,
        key=lambda row: (
            row["eligible"],
            row["median_robust"],
            row["worst_seed_profile"],
            row["worst_robust"],
            row["mean_robust"],
        ),
        reverse=True,
    )


def _print_eval_report(scores: list[EvalScore]) -> None:
    print("candidate,seed,robust,close,medium")
    for score in sorted(scores, key=lambda row: (row.candidate_id, row.seed)):
        print(
            f"{score.candidate_id},{score.seed},{score.robust_perf:.6f},"
            f"{score.close_win_rate:.6f},{score.medium_win_rate:.6f}"
        )
    print("\nstability ranking")
    for row in rank_scores(scores):
        values = "/".join(f"{score.robust_perf:.4f}" for score in row["scores"])
        print(
            f"{row['candidate_id']}: eligible={row['eligible']} "
            f"median={row['median_robust']:.4f} worst={row['worst_robust']:.4f} "
            f"worst_profile={row['worst_seed_profile']:.4f} scores={values}"
        )


def evaluate_matrix(args, snapshot: dict) -> int:
    root = repo_root()
    puffer_root = args.puffer_root.resolve()
    episodes = args.episodes_per_profile or int(
        snapshot["protocol"]["validation_episodes_per_profile"]
    )
    eval_seed = args.eval_seed or int(snapshot["protocol"]["validation_eval_seed"])
    targets = []
    missing = []
    for spec in experiment_specs(snapshot):
        candidate = resolved_candidate(snapshot, spec.candidate_id)
        run_path = find_completed_run(
            puffer_root / "logs/cnc_micro", args.project, candidate, spec
        )
        if run_path is None:
            missing.append(spec.tag)
        else:
            targets.append((spec, run_path))
    if missing:
        raise RuntimeError("missing confirmation runs: " + ", ".join(missing))

    if not args.execute:
        for spec, run_path in targets:
            checkpoint = checkpoint_path(puffer_root, run_path.stem, spec.total_timesteps)
            print(
                shlex.join(
                    build_eval_command(
                        root,
                        puffer_root,
                        checkpoint,
                        validation_eval_output(puffer_root, spec),
                        episodes,
                        eval_seed,
                    )
                )
            )
        return 0

    completed = []
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(
                _evaluate_one,
                root,
                puffer_root,
                spec,
                run_path,
                episodes,
                eval_seed,
                args.force,
                validation_eval_output(puffer_root, spec),
            ): spec
            for spec, run_path in targets
        }
        for future in as_completed(futures):
            path = future.result()
            completed.append((futures[future], path))
    scores = _load_eval_scores(completed)
    _print_eval_report(scores)
    return 0


def report_evaluations(args, snapshot: dict) -> int:
    paths = []
    for spec in experiment_specs(snapshot):
        path = validation_eval_output(args.puffer_root.resolve(), spec)
        if path.exists():
            paths.append((spec, path))
    scores = _load_eval_scores(paths)
    _print_eval_report(scores)
    print(f"\ncompleted={len(scores)}/{len(experiment_specs(snapshot))}")
    return 0


def _promotion_targets(puffer_root: Path, project: str, snapshot: dict):
    targets = []
    missing = []
    for spec in promotion_specs(snapshot):
        candidate = resolved_candidate(snapshot, spec.candidate_id)
        run_path = find_completed_run(
            puffer_root / "logs/cnc_micro", project, candidate, spec
        )
        if run_path is None:
            missing.append(spec.tag)
        else:
            targets.append((spec, run_path))
    if missing:
        raise RuntimeError("missing promotion runs: " + ", ".join(missing))
    return targets


def _promotion_manifest(
    snapshot_path: Path,
    puffer_root: Path,
    project: str,
    snapshot: dict,
    targets,
) -> dict:
    promotion = promotion_protocol(snapshot)
    rows = []
    for spec, run_path in targets:
        checkpoint = checkpoint_path(puffer_root, run_path.stem, spec.total_timesteps)
        if not checkpoint.exists():
            raise FileNotFoundError(f"missing promotion checkpoint: {checkpoint}")
        rows.append(
            {
                "candidate_id": spec.candidate_id,
                "training_seed": spec.seed,
                "run_id": run_path.stem,
                "training_steps": spec.total_timesteps,
                "checkpoint": str(checkpoint),
                "checkpoint_sha256": _sha256(checkpoint),
            }
        )
    return {
        "version": 1,
        "suite_id": promotion["suite_id"],
        "project": project,
        "source_snapshot": str(snapshot_path),
        "source_snapshot_sha256": _sha256(snapshot_path),
        "eval_seed": promotion["eval_seed"],
        "episodes_per_profile": promotion["episodes_per_profile"],
        "profiles": ["close", "medium"],
        "selection_rule": (
            "eligible(all seeds win both profiles), median robust, worst seed profile, "
            "worst robust, mean robust"
        ),
        "targets": rows,
    }


def _lock_promotion_manifest(path: Path, manifest: dict) -> None:
    if path.exists():
        existing = json.loads(path.read_text())
        if existing != manifest:
            raise RuntimeError(
                f"promotion suite is already locked to a different manifest: {path}"
            )
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def promote_matrix(args, snapshot: dict) -> int:
    root = repo_root()
    puffer_root = args.puffer_root.resolve()
    promotion = promotion_protocol(snapshot)
    targets = _promotion_targets(puffer_root, args.project, snapshot)
    manifest = _promotion_manifest(
        args.snapshot.resolve(), puffer_root, args.project, snapshot, targets
    )

    if not args.execute:
        print(json.dumps(manifest, indent=2, sort_keys=True))
        for spec, run_path in targets:
            checkpoint = checkpoint_path(puffer_root, run_path.stem, spec.total_timesteps)
            output = promotion_eval_output(puffer_root, promotion["suite_id"], spec)
            print(
                shlex.join(
                    build_eval_command(
                        root,
                        puffer_root,
                        checkpoint,
                        output,
                        promotion["episodes_per_profile"],
                        promotion["eval_seed"],
                    )
                )
            )
        return 0

    manifest_path = promotion_manifest_output(puffer_root, promotion["suite_id"])
    _lock_promotion_manifest(manifest_path, manifest)
    completed = []
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(
                _evaluate_one,
                root,
                puffer_root,
                spec,
                run_path,
                promotion["episodes_per_profile"],
                promotion["eval_seed"],
                args.force,
                promotion_eval_output(puffer_root, promotion["suite_id"], spec),
            ): spec
            for spec, run_path in targets
        }
        for future in as_completed(futures):
            completed.append((futures[future], future.result()))
    print(f"promotion_suite={promotion['suite_id']} manifest={manifest_path}")
    _print_eval_report(_load_eval_scores(completed))
    return 0


def report_promotion(args, snapshot: dict) -> int:
    puffer_root = args.puffer_root.resolve()
    promotion = promotion_protocol(snapshot)
    manifest_path = promotion_manifest_output(puffer_root, promotion["suite_id"])
    if not manifest_path.exists():
        raise FileNotFoundError(f"promotion suite has not been locked: {manifest_path}")
    targets = _promotion_targets(puffer_root, args.project, snapshot)
    expected_manifest = _promotion_manifest(
        args.snapshot.resolve(), puffer_root, args.project, snapshot, targets
    )
    if json.loads(manifest_path.read_text()) != expected_manifest:
        raise RuntimeError(f"promotion manifest drift: {manifest_path}")
    paths = []
    for spec in promotion_specs(snapshot):
        path = promotion_eval_output(puffer_root, promotion["suite_id"], spec)
        if path.exists():
            paths.append((spec, path))
    print(f"promotion_suite={promotion['suite_id']} manifest={manifest_path}")
    _print_eval_report(_load_eval_scores(paths))
    print(f"\ncompleted={len(paths)}/{len(promotion_specs(snapshot))}")
    return 0


def parse_args() -> argparse.Namespace:
    root = repo_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path, default=default_snapshot_path())
    parser.add_argument("--puffer-root", type=Path, default=root / "PufferLib")
    parser.add_argument("--project", default=DEFAULT_PROJECT)
    subparsers = parser.add_subparsers(dest="command", required=True)

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--execute", action="store_true")
    run_parser.add_argument("--force", action="store_true")
    run_parser.add_argument("--workers", type=int, default=3)
    run_parser.add_argument("--limit", type=int, default=0)

    subparsers.add_parser("analyze")

    eval_parser = subparsers.add_parser("evaluate")
    eval_parser.add_argument("--execute", action="store_true")
    eval_parser.add_argument("--force", action="store_true")
    eval_parser.add_argument("--workers", type=int, default=1)
    eval_parser.add_argument("--episodes-per-profile", type=int, default=0)
    eval_parser.add_argument("--eval-seed", type=int, default=0)

    subparsers.add_parser("report")
    promote_parser = subparsers.add_parser("promote")
    promote_parser.add_argument("--execute", action="store_true")
    promote_parser.add_argument("--force", action="store_true")
    promote_parser.add_argument("--workers", type=int, default=1)
    subparsers.add_parser("promotion-report")
    args = parser.parse_args()
    if getattr(args, "workers", 1) <= 0:
        parser.error("--workers must be positive")
    return args


def main() -> int:
    args = parse_args()
    snapshot = load_snapshot(args.snapshot.resolve())
    if args.command == "run":
        return run_matrix(args, snapshot)
    if args.command == "analyze":
        return analyze_training(args, snapshot)
    if args.command == "evaluate":
        return evaluate_matrix(args, snapshot)
    if args.command == "report":
        return report_evaluations(args, snapshot)
    if args.command == "promote":
        return promote_matrix(args, snapshot)
    if args.command == "promotion-report":
        return report_promotion(args, snapshot)
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
