#!/usr/bin/env python3
"""Validate and summarize the matched ABI9 invalid-action penalty study."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import run_abi9_penalty_study as study


HISTORICAL_SEED73_FINAL_SHA256 = (
    "490064539416022a02179b47136a74219ed37a618fcfa6173cabc659510c7a37"
)

FIXED_CONFIG = {
    "vec.total_agents": 64,
    "vec.num_buffers": 1,
    "vec.num_threads": 4,
    "env.seed": 1,
    "env.max_decisions": 12000,
    "env.action_abi": 9,
    "env.reward_milestone": 0.2,
    "env.reward_player_infantry": 0.0,
    "env.reward_enemy_unit_loss": 0.03176472410973994,
    "env.reward_enemy_building_loss": 0.23219496897879333,
    "env.reward_player_unit_loss": -0.005791169896719446,
    "env.reward_refinery": 0.042555945418244596,
    "env.reward_first_delivery": 0.0,
    "env.reward_tiberium_income": 0.007081631623240768,
    "policy.hidden_size": 64,
    "policy.num_layers": 1,
    "policy.expansion_factor": 1,
    "torch.network": "MinGRU",
    "torch.encoder": "Normalize255Encoder",
    "torch.decoder": "DefaultDecoder",
    "train.gpus": 1,
    "train.seed": 42,
    "train.total_timesteps": study.TOTAL_TIMESTEPS,
    "train.learning_rate": 0.0009701129526611177,
    "train.anneal_lr": 1,
    "train.min_lr_ratio": 0.0,
    "train.gamma": 0.975977019771838,
    "train.gae_lambda": 0.9297988511653911,
    "train.replay_ratio": 4.0,
    "train.clip_coef": 1.0,
    "train.vf_coef": 4.241147435051642,
    "train.vf_clip_coef": 3.579431156424427,
    "train.max_grad_norm": 0.6691746653678212,
    "train.ent_coef": 0.0013548995888609634,
    "train.anneal_ent_coef": 0,
    "train.min_ent_coef_ratio": 0.1,
    "train.beta1": 0.9963317652430518,
    "train.beta2": 0.9989380402338324,
    "train.eps": 4.521619692179587e-07,
    "train.minibatch_size": 2048,
    "train.horizon": 32,
    "train.vtrace_rho_clip": 0.9780523042532735,
    "train.vtrace_c_clip": 0.1,
    "train.prio_alpha": 0.25053580595043257,
    "train.prio_beta0": 1.0,
}


@dataclass(frozen=True)
class RunResult:
    penalty: float
    run_seed: int
    run_id: str
    balanced: float
    close: float
    medium: float
    perf: float
    invalid_actions: float
    invalid_penalty: float
    sps: float
    episodes: int
    checkpoint_sha256: str = ""


@dataclass(frozen=True)
class PenaltySummary:
    penalty: float
    count: int
    seeds: tuple[int, ...]
    scores: tuple[float, ...]
    mean_balanced: float
    median_balanced: float
    worst_balanced: float
    best_balanced: float
    mean_close: float
    mean_medium: float
    mean_perf: float
    mean_invalid_actions: float
    mean_invalid_penalty: float
    median_sps: float
    episodes: int


def nested(data: dict, path: str):
    value = data
    for component in path.split("."):
        value = value[component]
    return value


def final(data: dict, key: str) -> float:
    values = data["metrics"][key]
    return float(values[-1])


def values_equal(actual, expected) -> bool:
    if isinstance(expected, float):
        return math.isclose(float(actual), expected, rel_tol=0, abs_tol=1e-12)
    return actual == expected


def validate_fixed_config(data: dict, spec: study.ExperimentSpec) -> None:
    errors = []
    for path, expected in FIXED_CONFIG.items():
        try:
            actual = nested(data, path)
        except KeyError:
            errors.append(f"{path}=<missing>, expected {expected!r}")
            continue
        if not values_equal(actual, expected):
            errors.append(f"{path}={actual!r}, expected {expected!r}")
    if data.get("seed") != spec.run_seed:
        errors.append(f"seed={data.get('seed')!r}, expected {spec.run_seed}")
    actual_penalty = data.get("env", {}).get("reward_invalid_action")
    if actual_penalty is None or not values_equal(actual_penalty, spec.penalty):
        errors.append(
            f"env.reward_invalid_action={actual_penalty!r}, expected {spec.penalty}"
        )
    if errors:
        raise ValueError(f"{data.get('tag', '<untagged>')} config drift:\n  " + "\n  ".join(errors))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_results(
    puffer_root: Path,
    project: str,
    penalties: tuple[float, ...],
    seeds: tuple[int, ...],
) -> tuple[list[RunResult], list[study.ExperimentSpec]]:
    log_dir = puffer_root / "logs/cnc_micro"
    rows = []
    missing = []
    for spec in study.experiment_specs(penalties, seeds):
        path = study.find_completed_run(log_dir, project, spec)
        if path is None:
            missing.append(spec)
            continue
        data = json.loads(path.read_text())
        validate_fixed_config(data, spec)
        checkpoint = (
            puffer_root
            / "checkpoints/cnc_micro"
            / path.stem
            / f"{study.TOTAL_TIMESTEPS:016d}.bin"
        )
        rows.append(
            RunResult(
                penalty=spec.penalty,
                run_seed=spec.run_seed,
                run_id=path.stem,
                balanced=final(data, "env/balanced_perf"),
                close=final(data, "env/close_win_rate"),
                medium=final(data, "env/medium_win_rate"),
                perf=final(data, "env/perf"),
                invalid_actions=final(data, "env/invalid_actions"),
                invalid_penalty=final(data, "env/invalid_action_penalty"),
                sps=final(data, "SPS"),
                episodes=round(final(data, "env/n")),
                checkpoint_sha256=sha256(checkpoint) if checkpoint.exists() else "",
            )
        )
    return rows, missing


def summarize(rows: list[RunResult]) -> list[PenaltySummary]:
    groups = defaultdict(list)
    for row in rows:
        groups[row.penalty].append(row)
    summaries = []
    for penalty, group in groups.items():
        group.sort(key=lambda row: row.run_seed)
        scores = tuple(row.balanced for row in group)
        summaries.append(
            PenaltySummary(
                penalty=penalty,
                count=len(group),
                seeds=tuple(row.run_seed for row in group),
                scores=scores,
                mean_balanced=statistics.fmean(scores),
                median_balanced=statistics.median(scores),
                worst_balanced=min(scores),
                best_balanced=max(scores),
                mean_close=statistics.fmean(row.close for row in group),
                mean_medium=statistics.fmean(row.medium for row in group),
                mean_perf=statistics.fmean(row.perf for row in group),
                mean_invalid_actions=statistics.fmean(
                    row.invalid_actions for row in group
                ),
                mean_invalid_penalty=statistics.fmean(
                    row.invalid_penalty for row in group
                ),
                median_sps=statistics.median(row.sps for row in group),
                episodes=sum(row.episodes for row in group),
            )
        )
    return sorted(
        summaries,
        key=lambda row: (
            row.median_balanced,
            row.worst_balanced,
            row.mean_balanced,
        ),
        reverse=True,
    )


def print_report(rows: list[RunResult], summaries: list[PenaltySummary]) -> None:
    print("Run results")
    print("penalty,seed,run,balanced,close,medium,perf,invalid,cost,SPS,n,sha256")
    for row in sorted(rows, key=lambda item: (item.penalty, item.run_seed), reverse=True):
        print(
            f"{row.penalty:.6f},{row.run_seed},{row.run_id},{row.balanced:.9f},"
            f"{row.close:.9f},{row.medium:.9f},{row.perf:.9f},"
            f"{row.invalid_actions:.3f},{row.invalid_penalty:.6f},"
            f"{row.sps:.0f},{row.episodes},{row.checkpoint_sha256}"
        )

    print("\nPenalty ranking: median, then worst seed, then mean")
    print("penalty,n,scores,median,worst,mean,best,close,medium,cost,SPS,episodes")
    for row in summaries:
        scores = "/".join(f"{score:.6f}" for score in row.scores)
        print(
            f"{row.penalty:.6f},{row.count},{scores},{row.median_balanced:.6f},"
            f"{row.worst_balanced:.6f},{row.mean_balanced:.6f},"
            f"{row.best_balanced:.6f},{row.mean_close:.6f},"
            f"{row.mean_medium:.6f},{row.mean_invalid_penalty:.6f},"
            f"{row.median_sps:.0f},{row.episodes}"
        )


def parse_csv(raw: str, cast) -> tuple:
    return tuple(cast(item.strip()) for item in raw.split(",") if item.strip())


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--puffer-root", type=Path, default=repo_root / "PufferLib")
    parser.add_argument("--project", default="cnc9")
    parser.add_argument("--seeds", default=",".join(map(str, study.DEFAULT_SEEDS)))
    parser.add_argument(
        "--penalties",
        default=",".join(f"{value:.8g}" for value in study.DEFAULT_PENALTIES),
    )
    parser.add_argument("--allow-incomplete", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    penalties = parse_csv(args.penalties, float)
    seeds = parse_csv(args.seeds, int)
    rows, missing = load_results(
        args.puffer_root.resolve(), args.project, penalties, seeds
    )
    summaries = summarize(rows)
    print_report(rows, summaries)
    if missing:
        print("\nMissing: " + ", ".join(spec.tag for spec in missing))
        return 0 if args.allow_incomplete else 2

    reference = next(
        row for row in rows if row.penalty == 0 and row.run_seed == 73
    )
    if reference.checkpoint_sha256 != HISTORICAL_SEED73_FINAL_SHA256:
        raise RuntimeError(
            "seed-73 zero-penalty checkpoint regression: "
            f"{reference.checkpoint_sha256} != {HISTORICAL_SEED73_FINAL_SHA256}"
        )
    print("\nHistorical seed-73 zero-penalty checkpoint: exact match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
