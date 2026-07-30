#!/usr/bin/env python3
"""Analyze the completed cnc6 TD Micro sweep from local PufferLib JSON logs."""

from __future__ import annotations

import argparse
import json
import math
from collections import defaultdict
from pathlib import Path

import numpy as np
from scipy.stats import spearmanr
from sklearn.ensemble import ExtraTreesRegressor, RandomForestClassifier
from sklearn.inspection import permutation_importance
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split


HYPER_PATHS = (
    "train.horizon",
    "train.learning_rate",
    "train.ent_coef",
    "train.gamma",
    "train.gae_lambda",
    "train.vtrace_rho_clip",
    "train.vtrace_c_clip",
    "train.replay_ratio",
    "train.clip_coef",
    "train.vf_clip_coef",
    "train.vf_coef",
    "train.max_grad_norm",
    "train.beta1",
    "train.beta2",
    "train.eps",
    "train.prio_alpha",
    "train.prio_beta0",
    "policy.hidden_size",
    "policy.num_layers",
    "vec.num_buffers",
    "env.reward_milestone",
    "env.reward_player_infantry",
    "env.reward_enemy_unit_loss",
    "env.reward_enemy_building_loss",
    "env.reward_player_unit_loss",
    "env.reward_refinery",
    "env.reward_first_delivery",
    "env.reward_tiberium_income",
)

OUTCOME_METRICS = (
    "env/balanced_perf",
    "env/perf",
    "env/close_episode_share",
    "env/close_win_rate",
    "env/close_loss_rate",
    "env/medium_win_rate",
    "env/medium_loss_rate",
    "env/loss_rate",
    "env/draw_rate",
    "env/n",
)

BEHAVIOR_METRICS = (
    "env/episode_return",
    "env/episode_length",
    "env/invalid_actions",
    "env/building_limit_losses",
    "env/units_built",
    "env/gunners_built",
    "env/rocket_soldiers_built",
    "env/unit_kills",
    "env/unit_losses",
    "env/buildings_lost",
    "env/buildings_destroyed",
    "env/enemy_attack_orders",
    "env/power_plant_milestones",
    "env/barracks_milestones",
    "env/refineries_built",
    "env/harvesters_spawned",
    "env/tiberium_income",
    "env/refinery_milestones",
    "env/harvester_milestones",
    "env/first_delivery_milestones",
)

DERIVED_METRICS = (
    "min_spawn_win_rate",
    "spawn_win_rate_gap",
    "invalid_action_fraction",
    "e1_fraction",
    "kill_loss_ratio",
)

BEHAVIOR_DERIVED_METRICS = (
    "invalid_action_fraction",
    "e1_fraction",
    "kill_loss_ratio",
)


def nested(config: dict, path: str):
    value = config
    for key in path.split("."):
        value = value[key]
    return value


def final(metrics: dict, key: str, default=float("nan")) -> float:
    values = metrics.get(key)
    if not values:
        return default
    return float(values[-1])


def max_metric(metrics: dict, key: str, default=0.0) -> float:
    values = metrics.get(key)
    if not values:
        return default
    return float(max(values))


def shaping_budget(config: dict) -> float:
    env = config["env"]
    return (
        5 * env["reward_milestone"]
        + 10 * env["reward_player_infantry"]
        + 10 * env["reward_enemy_unit_loss"]
        + 3 * env["reward_enemy_building_loss"]
        + env["reward_refinery"]
        + env["reward_first_delivery"]
        + 50 * env["reward_tiberium_income"]
    )


def reconstruct_counts(row: dict) -> dict:
    n = round(row["env/n"])
    close_n = round(n * row["env/close_episode_share"])
    medium_n = n - close_n
    close_w = round(close_n * row["env/close_win_rate"])
    close_l = round(close_n * row["env/close_loss_rate"])
    medium_w = round(medium_n * row["env/medium_win_rate"])
    medium_l = round(medium_n * row["env/medium_loss_rate"])
    return {
        "n": n,
        "wins": close_w + medium_w,
        "losses": close_l + medium_l,
        "draws": n - close_w - close_l - medium_w - medium_l,
        "close_n": close_n,
        "close_wins": close_w,
        "close_losses": close_l,
        "close_draws": close_n - close_w - close_l,
        "medium_n": medium_n,
        "medium_wins": medium_w,
        "medium_losses": medium_l,
        "medium_draws": medium_n - medium_w - medium_l,
    }


def balanced_posterior(counts: dict, rng: np.random.Generator, samples=100_000):
    close = rng.beta(
        counts["close_wins"] + 1,
        counts["close_n"] - counts["close_wins"] + 1,
        samples,
    )
    medium = rng.beta(
        counts["medium_wins"] + 1,
        counts["medium_n"] - counts["medium_wins"] + 1,
        samples,
    )
    return np.quantile(0.5 * (close + medium), [0.025, 0.5, 0.975]).tolist()


def load_rows(log_dir: Path, project: str, tag: str) -> list[dict]:
    rows = []
    for path in sorted(log_dir.glob("*.json")):
        try:
            config = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if config.get("wandb_project") != project or config.get("tag") != tag:
            continue
        metrics = config.get("metrics", {})
        row = {
            "run_id": path.stem,
            "path": str(path),
            "total_timesteps": int(config["train"]["total_timesteps"]),
            "agent_steps": final(metrics, "agent_steps", 0),
            "uptime": final(metrics, "uptime", 0),
            "SPS": final(metrics, "SPS", 0),
            "aggregate_SPS": (
                final(metrics, "agent_steps", 0) / final(metrics, "uptime", 1)
            ),
            "max_start_failures": max_metric(metrics, "env/start_failures"),
            "max_failures": max_metric(metrics, "env/failures"),
            "shaping_budget": shaping_budget(config),
        }
        for key in HYPER_PATHS:
            row[key] = float(nested(config, key))
        for key in OUTCOME_METRICS + BEHAVIOR_METRICS:
            row[key] = final(metrics, key)
        row["final_failures"] = final(metrics, "env/failures", 0.0)
        row["min_spawn_win_rate"] = min(
            row["env/close_win_rate"], row["env/medium_win_rate"]
        )
        row["spawn_win_rate_gap"] = abs(
            row["env/close_win_rate"] - row["env/medium_win_rate"]
        )
        row["invalid_action_fraction"] = (
            row["env/invalid_actions"] / row["env/episode_length"]
            if row["env/episode_length"] > 0
            else float("nan")
        )
        infantry_built = row["env/gunners_built"] + row["env/rocket_soldiers_built"]
        row["e1_fraction"] = (
            row["env/gunners_built"] / infantry_built
            if infantry_built > 0
            else float("nan")
        )
        row["kill_loss_ratio"] = (
            row["env/unit_kills"] / row["env/unit_losses"]
            if row["env/unit_losses"] > 0
            else float("nan")
        )
        row["peak_logged_balanced"] = max_metric(metrics, "env/balanced_perf")
        row["balanced_curve"] = [float(v) for v in metrics.get("env/balanced_perf", [])]
        row["counts"] = reconstruct_counts(row)
        rows.append(row)
    return rows


def quantiles(values) -> dict:
    values = np.asarray(values, dtype=float)
    values = values[np.isfinite(values)]
    return {
        "min": float(np.min(values)),
        "p10": float(np.quantile(values, 0.10)),
        "p25": float(np.quantile(values, 0.25)),
        "median": float(np.median(values)),
        "mean": float(np.mean(values)),
        "p75": float(np.quantile(values, 0.75)),
        "p90": float(np.quantile(values, 0.90)),
        "p95": float(np.quantile(values, 0.95)),
        "p99": float(np.quantile(values, 0.99)),
        "max": float(np.max(values)),
    }


def group_summary(rows: list[dict], key: str) -> list[dict]:
    groups = defaultdict(list)
    for row in rows:
        groups[row[key]].append(row["env/balanced_perf"])
    result = []
    for value, scores in sorted(groups.items()):
        result.append(
            {
                "value": value,
                "n": len(scores),
                "mean": float(np.mean(scores)),
                "median": float(np.median(scores)),
                "p90": float(np.quantile(scores, 0.9)),
                "max": float(np.max(scores)),
                "success_ge_0.2": float(np.mean(np.asarray(scores) >= 0.2)),
            }
        )
    return result


def unique_signature(row: dict) -> tuple:
    return tuple(row[key] for key in HYPER_PATHS)


def successful_basin(rows: list[dict], cutoff: float = 0.2) -> dict:
    successful = [row for row in rows if row["env/balanced_perf"] >= cutoff]
    result = {"cutoff": cutoff, "runs": len(successful), "hyperparameters": {}}
    for key in HYPER_PATHS:
        values = np.asarray([row[key] for row in successful], dtype=float)
        result["hyperparameters"][key] = {
            "p10": float(np.quantile(values, 0.10)),
            "p25": float(np.quantile(values, 0.25)),
            "median": float(np.median(values)),
            "p75": float(np.quantile(values, 0.75)),
            "p90": float(np.quantile(values, 0.90)),
        }
    return result


def completion_blocks(rows: list[dict], block_size: int = 100) -> list[dict]:
    ordered = sorted(rows, key=lambda row: Path(row["path"]).stat().st_mtime_ns)
    result = []
    for start in range(0, len(ordered), block_size):
        block = ordered[start : start + block_size]
        scores = np.asarray([row["env/balanced_perf"] for row in block])
        result.append(
            {
                "completed_runs": [start + 1, start + len(block)],
                "mean": float(np.mean(scores)),
                "median": float(np.median(scores)),
                "max": float(np.max(scores)),
                "ge_0.2": int(np.sum(scores >= 0.2)),
            }
        )
    return result


def model_importance(rows: list[dict]) -> dict:
    # Collapse exact duplicate configurations before random splitting to avoid leakage.
    groups = defaultdict(list)
    for row in rows:
        groups[unique_signature(row)].append(row["env/balanced_perf"])
    signatures = list(groups)
    X = np.asarray(signatures, dtype=float)
    y = np.asarray([np.mean(groups[sig]) for sig in signatures], dtype=float)
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.25, random_state=20260718
    )
    model = ExtraTreesRegressor(
        n_estimators=500,
        min_samples_leaf=3,
        max_features=0.8,
        n_jobs=-1,
        random_state=20260718,
    )
    model.fit(X_train, y_train)
    r2 = float(model.score(X_test, y_test))
    perm = permutation_importance(
        model, X_test, y_test, n_repeats=20, random_state=20260718, n_jobs=-1
    )
    ranked = sorted(
        (
            {
                "hyperparameter": key,
                "mean_importance": float(mean),
                "std": float(std),
            }
            for key, mean, std in zip(HYPER_PATHS, perm.importances_mean, perm.importances_std)
        ),
        key=lambda item: item["mean_importance"],
        reverse=True,
    )

    labels = y >= 0.2
    classification = {"positives": int(labels.sum())}
    if labels.sum() >= 10 and (~labels).sum() >= 10:
        X_train, X_test, y_train, y_test = train_test_split(
            X, labels, test_size=0.25, random_state=20260718, stratify=labels
        )
        classifier = RandomForestClassifier(
            n_estimators=500,
            min_samples_leaf=3,
            class_weight="balanced",
            n_jobs=-1,
            random_state=20260718,
        )
        classifier.fit(X_train, y_train)
        classification["test_auc"] = float(
            roc_auc_score(y_test, classifier.predict_proba(X_test)[:, 1])
        )
    return {
        "unique_configs": len(signatures),
        "test_r2": r2,
        "permutation_importance": ranked,
        "classification_ge_0.2": classification,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log_dir", type=Path)
    parser.add_argument("--project", default="cnc6")
    parser.add_argument("--tag", default="abi9-2m-sweep-1000")
    parser.add_argument("--top", type=int, default=20)
    args = parser.parse_args()

    rows = load_rows(args.log_dir, args.project, args.tag)
    if not rows:
        raise SystemExit("No matching logs found")

    scores = np.asarray([row["env/balanced_perf"] for row in rows])
    full = [row for row in rows if row["agent_steps"] >= row["total_timesteps"]]
    signatures = defaultdict(list)
    for row in rows:
        signatures[unique_signature(row)].append(row)
    duplicate_groups = [group for group in signatures.values() if len(group) > 1]
    duplicate_score_spreads = [
        max(row["env/balanced_perf"] for row in group)
        - min(row["env/balanced_perf"] for row in group)
        for group in duplicate_groups
    ]

    ranked = sorted(rows, key=lambda row: row["env/balanced_perf"], reverse=True)
    rng = np.random.default_rng(20260718)
    top_rows = []
    for row in ranked[: args.top]:
        item = {
            key: row[key]
            for key in (
                "run_id",
                "env/balanced_perf",
                "env/perf",
                "env/close_win_rate",
                "env/medium_win_rate",
                "env/loss_rate",
                "env/draw_rate",
                "env/episode_return",
                "env/episode_length",
                "env/units_built",
                "env/gunners_built",
                "env/rocket_soldiers_built",
                "env/unit_kills",
                "env/unit_losses",
                "env/buildings_lost",
                "env/buildings_destroyed",
                "env/invalid_actions",
                "env/refineries_built",
                "env/tiberium_income",
                "SPS",
                "aggregate_SPS",
                "shaping_budget",
                "min_spawn_win_rate",
                "spawn_win_rate_gap",
                "invalid_action_fraction",
                "e1_fraction",
                "kill_loss_ratio",
            )
        }
        item["counts"] = row["counts"]
        item["balanced_posterior_95"] = balanced_posterior(row["counts"], rng)
        item["hypers"] = {key: row[key] for key in HYPER_PATHS}
        item["curve"] = row["balanced_curve"]
        top_rows.append(item)

    robust_rows = []
    for row in sorted(rows, key=lambda item: item["min_spawn_win_rate"], reverse=True)[: args.top]:
        robust_rows.append(
            {
                "run_id": row["run_id"],
                "balanced_perf": row["env/balanced_perf"],
                "close_win_rate": row["env/close_win_rate"],
                "medium_win_rate": row["env/medium_win_rate"],
                "min_spawn_win_rate": row["min_spawn_win_rate"],
                "spawn_win_rate_gap": row["spawn_win_rate_gap"],
                "counts": row["counts"],
            }
        )

    spearman = []
    for key in HYPER_PATHS:
        correlation, pvalue = spearmanr([row[key] for row in rows], scores)
        spearman.append(
            {
                "hyperparameter": key,
                "rho": float(correlation),
                "pvalue": float(pvalue),
            }
        )
    spearman.sort(key=lambda item: abs(item["rho"]), reverse=True)

    behavior_spearman = []
    for key in BEHAVIOR_METRICS + BEHAVIOR_DERIVED_METRICS + ("shaping_budget",):
        pairs = [
            (row[key], row["env/balanced_perf"])
            for row in rows
            if math.isfinite(row[key]) and math.isfinite(row["env/balanced_perf"])
        ]
        correlation, pvalue = spearmanr(
            [pair[0] for pair in pairs], [pair[1] for pair in pairs]
        )
        behavior_spearman.append(
            {"metric": key, "rho": float(correlation), "pvalue": float(pvalue)}
        )
    behavior_spearman.sort(key=lambda item: abs(item["rho"]), reverse=True)

    cutoff = float(np.quantile(scores, 0.9))
    top_decile = [row for row in rows if row["env/balanced_perf"] >= cutoff]
    top_decile_comparison = {}
    for key in BEHAVIOR_METRICS + BEHAVIOR_DERIVED_METRICS + ("shaping_budget",):
        all_values = [row[key] for row in rows if math.isfinite(row[key])]
        top_values = [row[key] for row in top_decile if math.isfinite(row[key])]
        top_decile_comparison[key] = {
            "all_mean": float(np.mean(all_values)),
            "top_decile_mean": float(np.mean(top_values)),
            "all_median": float(np.median(all_values)),
            "top_decile_median": float(np.median(top_values)),
        }

    curve_lengths = {len(row["balanced_curve"]) for row in rows}
    curve_summary = {"lengths": sorted(curve_lengths)}
    if len(curve_lengths) == 1:
        curves = np.asarray([row["balanced_curve"] for row in rows])
        curve_summary.update(
            {
                "median": np.median(curves, axis=0).tolist(),
                "p90": np.quantile(curves, 0.9, axis=0).tolist(),
                "p99": np.quantile(curves, 0.99, axis=0).tolist(),
                "max": np.max(curves, axis=0).tolist(),
            }
        )

    result = {
        "campaign": {
            "runs": len(rows),
            "full_budget_runs": len(full),
            "pruned_runs": len(rows) - len(full),
            "requested_steps_per_run": sorted({row["total_timesteps"] for row in rows}),
            "actual_total_agent_steps": int(sum(row["agent_steps"] for row in rows)),
            "summed_uptime_seconds": float(sum(row["uptime"] for row in rows)),
            "max_start_failures": float(max(row["max_start_failures"] for row in rows)),
            "max_engine_failures": float(max(row["max_failures"] for row in rows)),
            "score": quantiles(scores),
            "nonzero": int(np.sum(scores > 0)),
            "ge_0.1": int(np.sum(scores >= 0.1)),
            "ge_0.2": int(np.sum(scores >= 0.2)),
            "ge_0.3": int(np.sum(scores >= 0.3)),
            "final_displayed_sps": quantiles([row["SPS"] for row in rows]),
            "aggregate_sps": quantiles([row["aggregate_SPS"] for row in rows]),
            "episode_count": quantiles([row["env/n"] for row in rows]),
            "peak_to_final_drop_ge_0.05": int(
                sum(
                    row["peak_logged_balanced"] - row["env/balanced_perf"] >= 0.05
                    for row in rows
                )
            ),
            "peak_to_final_drop_ge_0.1": int(
                sum(
                    row["peak_logged_balanced"] - row["env/balanced_perf"] >= 0.1
                    for row in rows
                )
            ),
        },
        "duplicates": {
            "unique_configs": len(signatures),
            "duplicate_groups": len(duplicate_groups),
            "runs_in_duplicate_groups": sum(len(group) for group in duplicate_groups),
            "max_final_score_spread": max(duplicate_score_spreads, default=0.0),
            "nonzero_spread_groups": sum(spread != 0 for spread in duplicate_score_spreads),
        },
        "top_runs": top_rows,
        "robust_runs": robust_rows,
        "robustness": {
            "both_spawn_rates_ge_0.2": int(
                sum(row["min_spawn_win_rate"] >= 0.2 for row in rows)
            ),
            "both_spawn_rates_ge_0.25": int(
                sum(row["min_spawn_win_rate"] >= 0.25 for row in rows)
            ),
            "both_spawn_rates_ge_0.3": int(
                sum(row["min_spawn_win_rate"] >= 0.3 for row in rows)
            ),
            "score_ge_0.2_with_spawn_gap_ge_0.4": int(
                sum(
                    row["env/balanced_perf"] >= 0.2
                    and row["spawn_win_rate_gap"] >= 0.4
                    for row in rows
                )
            ),
        },
        "successful_basin": successful_basin(rows),
        "completion_order_blocks": completion_blocks(rows),
        "failure_runs": [
            {
                "run_id": row["run_id"],
                "balanced_perf": row["env/balanced_perf"],
                "max_failures": row["max_failures"],
                "final_failures": row["final_failures"],
            }
            for row in rows
            if row["max_failures"] > 0
        ],
        "grouped_architecture": {
            key: group_summary(rows, key)
            for key in (
                "train.horizon",
                "policy.hidden_size",
                "policy.num_layers",
                "vec.num_buffers",
            )
        },
        "hyperparameter_spearman": spearman,
        "behavior_spearman": behavior_spearman,
        "top_decile_cutoff": cutoff,
        "top_decile_comparison": top_decile_comparison,
        "learning_curve": curve_summary,
        "predictive_model": model_importance(rows),
    }
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
