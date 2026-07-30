#!/usr/bin/env python3
"""Search categorical sampling seeds for a replayable Vanilla TD Micro full win."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import re
import shutil
import threading
from typing import Any

from td_micro_transfer_eval import (
    EvaluationError,
    parse_vanilla,
    run_vanilla,
    sha256_file,
    write_configs,
)


ROOT = Path(__file__).resolve().parents[1]
RESULT_LOCK = threading.Lock()


def evaluate_seed(
    sampling_seed: int,
    args: argparse.Namespace,
    checkpoint_hash: str,
    rules_hash: str,
) -> dict[str, Any]:
    runtime = args.work_root / f"seed-{sampling_seed}"
    if runtime.exists():
        shutil.rmtree(runtime)
    runtime.mkdir(parents=True)
    record: dict[str, Any] = {
        "sampling_seed": sampling_seed,
        "environment_seed": args.environment_seed,
        "starting_credits": args.starting_credits,
        "starting_units": args.starting_units,
        "opponent_difficulty": args.opponent_difficulty,
        "opponent_starting_credits": args.opponent_starting_credits,
        "checkpoint_sha256": checkpoint_hash,
        "rules_sha256": rules_hash,
        "valid": False,
    }
    try:
        argv0 = write_configs(
            runtime,
            args.data,
            args.checkpoint,
            args.environment_seed,
            args.vanilla,
            args.opponent_difficulty,
        )
        environment = os.environ.copy()
        environment.update(
            {
                "SDL_VIDEODRIVER": "dummy",
                "SDL_AUDIODRIVER": "dummy",
                "ALSOFT_DRIVERS": "null",
                "VANILLA_CONQUER_ARGV0": str(argv0),
                "TD_MICRO_POLICY_SAMPLE_SEED": str(sampling_seed),
                "TD_MICRO_STARTING_CREDITS": str(args.starting_credits),
                "TD_MICRO_STARTING_UNITS": str(args.starting_units),
            }
        )
        if args.opponent_starting_credits is not None:
            environment["TD_MICRO_OPPONENT_STARTING_CREDITS"] = str(args.opponent_starting_credits)
        telemetry_path = runtime / "td_micro_policy.log"
        process = run_vanilla(
            [str(argv0), "-XQ"],
            runtime,
            environment,
            args.timeout_seconds,
            telemetry_path,
        )
        text = process.stdout + "\n" + process.stderr + "\n" + process.telemetry
        if process.timed_out:
            raise EvaluationError(f"Vanilla timed out after {args.timeout_seconds}s")
        if process.failure_seen:
            raise EvaluationError("Vanilla reported policy failure")
        if not process.terminal_seen:
            raise EvaluationError(f"Vanilla exited {process.returncode} without terminal telemetry")
        if process.returncode != 0 and not process.terminated_after_marker:
            raise EvaluationError(f"Vanilla exited {process.returncode}")
        record["vanilla"] = parse_vanilla(text, checkpoint_hash, rules_hash, sampling_seed)
        record["valid"] = record["vanilla"]["failures"] == 0
        record["artifacts"] = str(runtime)
        if record["vanilla"]["full_perf"] == 0 and not args.keep_all_artifacts:
            shutil.rmtree(runtime)
            record.pop("artifacts")
    except Exception as error:
        record["error"] = str(error)
        record["artifacts"] = str(runtime)
    return record


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--vanilla", type=Path, default=ROOT / "Vanilla-Conquer/build-td/vanillatd")
    parser.add_argument("--data", type=Path, default=ROOT.parents[1] / "td-data")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work-root", type=Path)
    parser.add_argument("--environment-seed", type=int, default=1)
    parser.add_argument("--sample-seed-start", type=int, default=1000)
    parser.add_argument("--sample-count", type=int, default=100)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--timeout-seconds", type=int, default=180)
    parser.add_argument("--starting-credits", type=int, default=2300)
    parser.add_argument("--starting-units", type=int, choices=(0, 6), default=6)
    parser.add_argument("--opponent-difficulty", type=int, choices=(0, 1, 2), default=1)
    parser.add_argument("--opponent-starting-credits", type=int)
    parser.add_argument("--keep-all-artifacts", action="store_true")
    args = parser.parse_args()
    for name in ("checkpoint", "vanilla", "data"):
        value = getattr(args, name).resolve()
        if not value.exists():
            parser.error(f"--{name.replace('_', '-')} does not exist: {value}")
        setattr(args, name, value)
    args.output = args.output.resolve()
    args.work_root = args.work_root.resolve() if args.work_root else args.output / "work"
    if args.sample_count <= 0 or args.jobs <= 0 or args.timeout_seconds <= 0:
        parser.error("sample count, jobs, and timeout must be positive")
    if args.starting_credits <= 0:
        parser.error("starting credits must be positive")
    if (
        args.opponent_starting_credits is not None
        and not 0 <= args.opponent_starting_credits <= args.starting_credits
    ):
        parser.error("opponent starting credits must be between zero and player starting credits")
    return args


def main() -> int:
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    args.work_root.mkdir(parents=True, exist_ok=True)
    results_path = args.output / "episodes.jsonl"
    if results_path.exists():
        raise EvaluationError(f"result file exists: {results_path}")

    checkpoint_hash = sha256_file(args.checkpoint)
    manifest = (ROOT / "td-micro/generated/td_micro_v1.h").read_text(encoding="ascii")
    match = re.search(r'TD_MICRO_MANIFEST_SHA256 "([0-9a-f]{64})"', manifest)
    if match is None:
        raise EvaluationError("cannot read generated rules hash")
    rules_hash = match.group(1)
    seeds = range(args.sample_seed_start, args.sample_seed_start + args.sample_count)
    records: list[dict[str, Any]] = []
    print(
        f"Vanilla seed search: samples={args.sample_count} jobs={args.jobs} "
        f"checkpoint={checkpoint_hash[:12]} rules={rules_hash[:12]}",
        flush=True,
    )

    def complete(record: dict[str, Any]) -> None:
        with RESULT_LOCK:
            with results_path.open("a", encoding="utf-8") as output:
                output.write(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
            records.append(record)
            if record.get("valid"):
                result = record["vanilla"]
                metrics = result["metrics"]
                status = (
                    f"{result['result']} full={result['full_perf']} income={metrics['tiberium_income']} "
                    f"tanks={metrics['medium_tanks_built']} shots={metrics['tank_shots']}"
                )
            else:
                status = f"ERROR {record.get('error', 'invalid')}"
            print(f"[{len(records)}/{args.sample_count}] seed={record['sampling_seed']} {status}", flush=True)

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as executor:
        futures = [
            executor.submit(evaluate_seed, seed, args, checkpoint_hash, rules_hash)
            for seed in seeds
        ]
        for future in concurrent.futures.as_completed(futures):
            complete(future.result())

    valid = [record for record in records if record.get("valid")]
    full = [record for record in valid if record["vanilla"]["full_perf"]]
    wins = [record for record in valid if record["vanilla"]["result"] == "win"]
    summary = {
        "episodes": len(records),
        "valid_episodes": len(valid),
        "infrastructure_failures": len(records) - len(valid),
        "wins": len(wins),
        "full_wins": len(full),
        "full_win_seeds": sorted(record["sampling_seed"] for record in full),
        "checkpoint_sha256": checkpoint_hash,
        "rules_sha256": rules_hash,
    }
    (args.output / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["infrastructure_failures"] == 0 else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvaluationError as error:
        print(f"error: {error}")
        raise SystemExit(2)
