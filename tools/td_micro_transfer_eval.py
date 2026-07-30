#!/usr/bin/env python3
"""Run matched fresh-process Zig and Vanilla TD Micro policy evaluations."""

from __future__ import annotations

import argparse
from collections import Counter
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OBSERVATION_SIZE = 3992
ACTION_MASK_SIZE = 1156
RECORD_SIZE = OBSERVATION_SIZE + ACTION_MASK_SIZE
ACTION_RECORD_SIZE = 4
GLOBAL_SIZE = 64
TIBERIUM_COUNT = 344
ENTITY_SLOT_COUNT = 64
ENTITY_RECORD_SIZE = 28
OWN_ENTITIES_OFFSET = GLOBAL_SIZE + TIBERIUM_COUNT
ENEMY_ENTITIES_OFFSET = OWN_ENTITIES_OFFSET + ENTITY_SLOT_COUNT * ENTITY_RECORD_SIZE
DECISION_FRAMES = 4
PROFILES = {"close": 1, "medium": 2}
RESULT_LOCK = threading.Lock()


class EvaluationError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_metadata() -> dict[str, Any]:
    commit = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    diff = subprocess.run(
        ["git", "diff", "--binary", "HEAD"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    ).stdout
    return {
        "commit": commit,
        "dirty": bool(diff),
        "tracked_diff_sha256": hashlib.sha256(diff).hexdigest() if diff else None,
    }


def describe_record_offset(offset: int) -> str:
    if offset < 0 or offset >= RECORD_SIZE:
        return "outside_record"
    if offset < GLOBAL_SIZE:
        return f"observation.global[{offset}]"
    if offset < OWN_ENTITIES_OFFSET:
        return f"observation.tiberium[{offset - GLOBAL_SIZE}]"
    if offset < ENEMY_ENTITIES_OFFSET:
        entity = offset - OWN_ENTITIES_OFFSET
        return f"observation.own_entity[{entity // ENTITY_RECORD_SIZE}].byte[{entity % ENTITY_RECORD_SIZE}]"
    if offset < OBSERVATION_SIZE:
        entity = offset - ENEMY_ENTITIES_OFFSET
        return f"observation.enemy_entity[{entity // ENTITY_RECORD_SIZE}].byte[{entity % ENTITY_RECORD_SIZE}]"
    return f"action_mask[{offset - OBSERVATION_SIZE}]"


def trace_metadata(path: Path, record_size: int = RECORD_SIZE) -> dict[str, Any]:
    size = path.stat().st_size
    if size % record_size != 0:
        raise EvaluationError(f"malformed trace {path}: {size} bytes")
    return {
        "bytes": size,
        "records": size // record_size,
        "sha256": sha256_file(path),
    }


def compare_traces(native_path: Path, vanilla_path: Path) -> dict[str, Any] | None:
    with native_path.open("rb") as native, vanilla_path.open("rb") as vanilla:
        decision = 0
        while True:
            left = native.read(RECORD_SIZE)
            right = vanilla.read(RECORD_SIZE)
            if not left and not right:
                return None
            if len(left) != RECORD_SIZE or len(right) != RECORD_SIZE:
                return {
                    "decision": decision,
                    "frame": decision * DECISION_FRAMES,
                    "kind": "record_count",
                    "native_record_present": len(left) == RECORD_SIZE,
                    "vanilla_record_present": len(right) == RECORD_SIZE,
                }
            if left != right:
                offset = next(index for index, pair in enumerate(zip(left, right)) if pair[0] != pair[1])
                return {
                    "decision": decision,
                    "frame": decision * DECISION_FRAMES,
                    "kind": "byte",
                    "byte_offset": offset,
                    "field": describe_record_offset(offset),
                    "native": left[offset],
                    "vanilla": right[offset],
                }
            decision += 1


def compare_action_traces(native_path: Path, vanilla_path: Path) -> dict[str, Any] | None:
    native = native_path.read_bytes()
    vanilla = vanilla_path.read_bytes()
    common_records = min(len(native), len(vanilla)) // ACTION_RECORD_SIZE
    for decision in range(common_records):
        start = decision * ACTION_RECORD_SIZE
        left = native[start : start + ACTION_RECORD_SIZE]
        right = vanilla[start : start + ACTION_RECORD_SIZE]
        if left != right:
            return {
                "decision": decision,
                "frame": decision * DECISION_FRAMES,
                "kind": "action",
                "native": list(left),
                "vanilla": list(right),
            }
    if len(native) != len(vanilla):
        return {
            "decision": common_records,
            "frame": common_records * DECISION_FRAMES,
            "kind": "record_count",
            "native_records": len(native) // ACTION_RECORD_SIZE,
            "vanilla_records": len(vanilla) // ACTION_RECORD_SIZE,
        }
    return None


def key_values(line: str) -> dict[str, str]:
    return dict(re.findall(r"(?:^|\s)([A-Za-z_]+)=([^\s]+)", line))


def parse_native(stdout: str, expected_checkpoint: str, expected_rules: str) -> dict[str, Any]:
    lines = stdout.splitlines()
    header = next((line for line in lines if line.startswith("checkpoint=")), None)
    episode = next((line for line in lines if line.startswith("episode ")), None)
    metrics_line = next((line for line in lines if line.startswith("metrics ")), None)
    if header is None or episode is None or metrics_line is None:
        raise EvaluationError("native evaluator omitted header, episode, or metrics")
    header_values = key_values(header)
    episode_values = key_values(episode)
    metrics = key_values(metrics_line)
    if header_values.get("checkpoint") != expected_checkpoint:
        raise EvaluationError("native checkpoint hash mismatch")
    if header_values.get("rules") != expected_rules:
        raise EvaluationError("native rules hash mismatch")
    if int(header_values.get("hidden", "0")) not in (64, 128):
        raise EvaluationError("native ABI13 hidden size mismatch")
    wins = int(episode_values["wins"])
    losses = int(episode_values["losses"])
    draws = int(episode_values["draws"])
    if wins + losses + draws != 1:
        raise EvaluationError("native evaluator did not finish exactly one episode")
    result = "win" if wins else "loss" if losses else "draw"
    decisions = int(episode_values["decisions"])
    return {
        "result": result,
        "reason": result,
        "decisions": decisions,
        "frame": decisions * DECISION_FRAMES,
        "invalid_actions": int(episode_values["invalid"]),
        "full_perf": int(episode_values["full_wins"]),
        "failures": int(episode_values["failures"]),
        "checkpoint_sha256": header_values["checkpoint"],
        "rules_sha256": header_values["rules"],
        "metrics": {key: int(value) for key, value in metrics.items()},
    }


def parse_vanilla(text: str, expected_checkpoint: str, expected_rules: str, expected_seed: int) -> dict[str, Any]:
    loaded_matches = re.findall(
        r"TD Micro policy: loaded checkpoint=([0-9a-f]{64}) abi=(\d+) hidden=(\d+) "
        r"rules=([0-9a-f]{64}) obs=(\d+) mask=(\d+) sampling=categorical seed=(\d+)",
        text,
    )
    terminal_matches = re.findall(
        r"terminal reason=(win|loss|draw|timeout) frame=(\d+) decisions=(\d+) "
        r"accepted=(\d+) changed=(\d+) player_defeated=(\d+) opponent_defeated=(\d+) failed=(\d+) "
        r"harvested=(\d+) tanks_built=(\d+) tanks_alive=(\d+) tank_shots=(\d+) full_perf=(\d+)",
        text,
    )
    if not loaded_matches:
        raise EvaluationError("Vanilla omitted policy-loaded telemetry")
    if not terminal_matches:
        raise EvaluationError("Vanilla omitted terminal telemetry")
    checkpoint, abi, hidden, rules, observation_size, mask_size, sampling_seed = loaded_matches[-1]
    if checkpoint != expected_checkpoint or rules != expected_rules:
        raise EvaluationError("Vanilla checkpoint or rules hash mismatch")
    if int(abi) != 13 or int(hidden) not in (64, 128):
        raise EvaluationError("Vanilla evaluator did not load an ABI13 checkpoint")
    if int(observation_size) != OBSERVATION_SIZE or int(mask_size) != ACTION_MASK_SIZE:
        raise EvaluationError("Vanilla policy schema mismatch")
    if int(sampling_seed) != expected_seed:
        raise EvaluationError("Vanilla sampling-seed override mismatch")
    (
        reason,
        frame,
        decisions,
        accepted,
        changed,
        player_defeated,
        opponent_defeated,
        failed,
        harvested,
        tanks_built,
        tanks_alive,
        tank_shots,
        full_perf,
    ) = terminal_matches[-1]
    decisions_value = int(decisions)
    accepted_value = int(accepted)
    return {
        "result": "draw" if reason == "timeout" else reason,
        "reason": reason,
        "frame": int(frame),
        "decisions": decisions_value,
        "accepted_actions": accepted_value,
        "changed_actions": int(changed),
        "rejected_actions": decisions_value - accepted_value,
        "player_defeated": bool(int(player_defeated)),
        "opponent_defeated": bool(int(opponent_defeated)),
        "failures": int(failed),
        "checkpoint_sha256": checkpoint,
        "rules_sha256": rules,
        "abi": int(abi),
        "hidden_size": int(hidden),
        "full_perf": int(full_perf),
        "metrics": {
            "tiberium_income": int(harvested),
            "medium_tanks_built": int(tanks_built),
            "medium_tanks_alive": int(tanks_alive),
            "tank_shots": int(tank_shots),
        },
    }


def write_configs(
    runtime: Path,
    data_path: Path,
    checkpoint: Path,
    environment_seed: int,
    vanilla: Path,
    opponent_difficulty: int = 0,
) -> Path:
    startup = runtime / "startup"
    user = runtime / "user"
    startup.mkdir(parents=True)
    user.mkdir(parents=True)
    (startup / "CONQUER.INI").write_text(
        f"[Paths]\nDataPath={data_path}\nUserPath={user}\n",
        encoding="ascii",
    )
    (user / "conquer.ini").write_text(
        "[Intro]\nPlayIntro=no\n\n"
        "[Options]\nGameSpeed=0\n\n"
        "[Video]\nWindowed=yes\nWindowWidth=640\nWindowHeight=400\nFrameLimit=0\n"
        "HardwareCursor=no\nDriver=software\n\n"
        "[Mouse]\nRawInput=no\n\n"
        "[TDMicro]\nRuleset=td_micro_v1\nPlayerBrain=PufferPolicy\n"
        f"OpponentBrain=OriginalAI\nOpponentDifficulty={opponent_difficulty}\n"
        f"Seed={environment_seed}\nPolicyPath={checkpoint}\n",
        encoding="ascii",
    )
    launcher = startup / "vanillatd"
    launcher.symlink_to(vanilla)
    return launcher


def run_process(command: list[str], cwd: Path, env: dict[str, str], timeout: int) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise EvaluationError(f"process timed out after {timeout}s: {command[0]}") from error


def run_vanilla(
    command: list[str],
    cwd: Path,
    env: dict[str, str],
    timeout: int,
    telemetry_path: Path,
) -> subprocess.CompletedProcess[str]:
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    deadline = time.monotonic() + timeout
    telemetry = ""
    terminal_seen = False
    failure_seen = False
    timed_out = False
    while process.poll() is None:
        if telemetry_path.exists():
            telemetry = telemetry_path.read_text(encoding="utf-8", errors="replace")
            terminal_seen = "terminal reason=" in telemetry
            failure_seen = "failure reason=" in telemetry
            if terminal_seen or failure_seen:
                process.terminate()
                break
        if time.monotonic() >= deadline:
            timed_out = True
            process.kill()
            break
        time.sleep(0.05)

    try:
        stdout, stderr = process.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        stdout, stderr = process.communicate()
    if telemetry_path.exists():
        telemetry = telemetry_path.read_text(encoding="utf-8", errors="replace")
    completed = subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
    completed.telemetry = telemetry
    completed.terminal_seen = terminal_seen or "terminal reason=" in telemetry
    completed.failure_seen = failure_seen or "failure reason=" in telemetry
    completed.timed_out = timed_out
    completed.terminated_after_marker = (terminal_seen or failure_seen) and process.returncode != 0
    return completed


def evaluate_tuple(
    profile: str,
    sampling_seed: int,
    args: argparse.Namespace,
    checkpoint_hash: str,
    rules_hash: str,
    source: dict[str, Any],
) -> dict[str, Any]:
    environment_seed = PROFILES[profile]
    runtime = args.work_root / f"{profile}-{sampling_seed}"
    if runtime.exists():
        shutil.rmtree(runtime)
    runtime.mkdir(parents=True)
    native_trace = runtime / "native-state.bin"
    native_actions = runtime / "native-actions.bin"
    vanilla_trace = runtime / "td_micro_policy_state_live.bin"
    vanilla_actions = runtime / "vanilla-actions.bin"
    record: dict[str, Any] = {
        "schema": 1,
        "profile": profile,
        "environment_seed": environment_seed,
        "sampling_seed": sampling_seed,
        "checkpoint_sha256": checkpoint_hash,
        "rules_sha256": rules_hash,
        "source": source,
        "valid": False,
    }
    try:
        native_process = run_process(
            [
                str(args.native_evaluator),
                str(args.checkpoint),
                str(native_trace),
                "--seed",
                str(environment_seed),
                "--sample-seed",
                str(sampling_seed),
                "--action-trace",
                str(native_actions),
            ],
            runtime,
            os.environ.copy(),
            args.timeout_seconds,
        )
        if native_process.returncode != 0:
            raise EvaluationError(f"native evaluator exited {native_process.returncode}")
        native_result = parse_native(native_process.stdout, checkpoint_hash, rules_hash)
        native_result["trace"] = trace_metadata(native_trace)
        native_result["actions"] = trace_metadata(native_actions, ACTION_RECORD_SIZE)
        if native_result["trace"]["records"] != native_result["actions"]["records"]:
            raise EvaluationError("native state/action trace length mismatch")
        with native_trace.open("rb") as stream:
            first_observation = stream.read(OBSERVATION_SIZE)
        if len(first_observation) != OBSERVATION_SIZE:
            raise EvaluationError("native trace omitted its initial observation")
        starting_credits = first_observation[4] * 100
        if starting_credits <= 0:
            raise EvaluationError("native trace reported invalid starting credits")
        starting_infantry = first_observation[22]
        if starting_infantry not in (0, 6):
            raise EvaluationError(f"unsupported native starting infantry count: {starting_infantry}")
        opponent_difficulty = first_observation[33]
        if opponent_difficulty not in (0, 1, 2):
            raise EvaluationError(f"unsupported native opponent difficulty: {opponent_difficulty}")
        record["starting_credits"] = starting_credits
        record["starting_units"] = starting_infantry
        record["opponent_difficulty"] = opponent_difficulty

        argv0 = write_configs(
            runtime,
            args.data,
            args.checkpoint,
            environment_seed,
            args.vanilla,
            opponent_difficulty,
        )
        environment = os.environ.copy()
        environment.update(
            {
                "SDL_VIDEODRIVER": "dummy",
                "SDL_AUDIODRIVER": "dummy",
                "ALSOFT_DRIVERS": "null",
                "VANILLA_CONQUER_ARGV0": str(argv0),
                "TD_MICRO_POLICY_SAMPLE_SEED": str(sampling_seed),
                "TD_MICRO_POLICY_ACTION_TRACE": str(vanilla_actions),
                "TD_MICRO_STARTING_CREDITS": str(starting_credits),
                "TD_MICRO_STARTING_UNITS": str(starting_infantry),
            }
        )
        telemetry_path = runtime / "td_micro_policy.log"
        vanilla_process = run_vanilla(
            [str(argv0), "-XQ"],
            runtime,
            environment,
            args.timeout_seconds,
            telemetry_path,
        )
        vanilla_text = vanilla_process.stdout + "\n" + vanilla_process.stderr + "\n" + vanilla_process.telemetry
        if vanilla_process.timed_out:
            raise EvaluationError(f"Vanilla timed out after {args.timeout_seconds}s")
        if vanilla_process.failure_seen:
            raise EvaluationError("Vanilla reported policy failure")
        if not vanilla_process.terminal_seen:
            raise EvaluationError(f"Vanilla exited {vanilla_process.returncode} without terminal telemetry")
        if vanilla_process.returncode != 0 and not vanilla_process.terminated_after_marker:
            raise EvaluationError(f"Vanilla exited {vanilla_process.returncode}")
        vanilla_result = parse_vanilla(vanilla_text, checkpoint_hash, rules_hash, sampling_seed)
        vanilla_result["process_exit"] = vanilla_process.returncode
        vanilla_result["terminated_after_terminal"] = vanilla_process.terminated_after_marker
        vanilla_result["trace"] = trace_metadata(vanilla_trace)
        vanilla_result["actions"] = trace_metadata(vanilla_actions, ACTION_RECORD_SIZE)
        if vanilla_result["trace"]["records"] != vanilla_result["actions"]["records"]:
            raise EvaluationError("Vanilla state/action trace length mismatch")

        record["native"] = native_result
        record["vanilla"] = vanilla_result
        record["terminal_agreement"] = native_result["result"] == vanilla_result["result"]
        record["first_divergence"] = compare_traces(native_trace, vanilla_trace)
        record["exact_trace"] = record["first_divergence"] is None
        record["first_action_divergence"] = compare_action_traces(native_actions, vanilla_actions)
        record["exact_actions"] = record["first_action_divergence"] is None
        record["valid"] = native_result["failures"] == 0 and vanilla_result["failures"] == 0
        if record["valid"] and not args.keep_artifacts:
            shutil.rmtree(runtime)
    except Exception as error:  # Keep artifacts and continue the broad evaluation.
        record["error"] = str(error)
        for name, content in (
            ("native.stdout.log", locals().get("native_process").stdout if "native_process" in locals() else ""),
            ("native.stderr.log", locals().get("native_process").stderr if "native_process" in locals() else ""),
            ("vanilla.stdout.log", locals().get("vanilla_process").stdout if "vanilla_process" in locals() else ""),
            ("vanilla.stderr.log", locals().get("vanilla_process").stderr if "vanilla_process" in locals() else ""),
        ):
            (runtime / name).write_text(content, encoding="utf-8", errors="replace")
        record["artifacts"] = str(runtime)
    return record


def aggregate(records: list[dict[str, Any]], checkpoint_hash: str, rules_hash: str) -> dict[str, Any]:
    valid_records = [record for record in records if record.get("valid")]
    summary: dict[str, Any] = {
        "schema": 1,
        "episodes": len(records),
        "checkpoint_sha256": checkpoint_hash,
        "rules_sha256": rules_hash,
        "valid_episodes": sum(record.get("valid", False) for record in records),
        "infrastructure_failures": sum(not record.get("valid", False) for record in records),
        "terminal_agreements": sum(record.get("terminal_agreement", False) for record in records),
        "exact_traces": sum(record.get("exact_trace", False) for record in records),
        "exact_action_traces": sum(record.get("exact_actions", False) for record in records),
        "failures": {
            "infrastructure": sum(not record.get("valid", False) for record in records),
            "native_engine": sum(record.get("native", {}).get("failures", 0) for record in records),
            "vanilla_engine": sum(record.get("vanilla", {}).get("failures", 0) for record in records),
        },
        "profiles": {},
    }
    summary["overall"] = {}
    for engine in ("native", "vanilla"):
        counts = {
            result: sum(record[engine]["result"] == result for record in valid_records)
            for result in ("win", "loss", "draw")
        }
        counts["win_rate"] = counts["win"] / len(valid_records) if valid_records else 0.0
        summary["overall"][engine] = counts
    balanced_native = 0.0
    balanced_vanilla = 0.0
    for profile in PROFILES:
        selected = [record for record in records if record["profile"] == profile and record.get("valid")]
        profile_result: dict[str, Any] = {"episodes": len(selected)}
        for engine in ("native", "vanilla"):
            counts = {
                result: sum(record[engine]["result"] == result for record in selected)
                for result in ("win", "loss", "draw")
            }
            counts["win_rate"] = counts["win"] / len(selected) if selected else 0.0
            profile_result[engine] = counts
        profile_result["terminal_agreements"] = sum(record["terminal_agreement"] for record in selected)
        profile_result["exact_traces"] = sum(record["exact_trace"] for record in selected)
        profile_result["exact_action_traces"] = sum(record.get("exact_actions", False) for record in selected)
        profile_result["first_divergence_decisions"] = [
            record["first_divergence"]["decision"]
            for record in selected
            if record["first_divergence"] is not None
        ]
        divergences = profile_result["first_divergence_decisions"]
        profile_result["first_divergence_summary"] = {
            "count": len(divergences),
            "min": min(divergences) if divergences else None,
            "median": statistics.median(divergences) if divergences else None,
            "max": max(divergences) if divergences else None,
            "fields": dict(
                sorted(
                    Counter(
                        record["first_divergence"].get("field", record["first_divergence"]["kind"])
                        for record in selected
                        if record["first_divergence"] is not None
                    ).items()
                )
            ),
        }
        summary["profiles"][profile] = profile_result
        balanced_native += profile_result["native"]["win_rate"] / len(PROFILES)
        balanced_vanilla += profile_result["vanilla"]["win_rate"] / len(PROFILES)
    summary["balanced_native_win_rate"] = balanced_native
    summary["balanced_vanilla_win_rate"] = balanced_vanilla
    return summary


def load_existing(path: Path) -> dict[tuple[str, int], dict[str, Any]]:
    if not path.exists():
        return {}
    records: dict[tuple[str, int], dict[str, Any]] = {}
    with path.open("r", encoding="utf-8") as stream:
        for line in stream:
            if line.strip():
                record = json.loads(line)
                records[(record["profile"], record["sampling_seed"])] = record
    return records


def pending_requests(
    requested: list[tuple[str, int]],
    existing: dict[tuple[str, int], dict[str, Any]],
) -> list[tuple[str, int]]:
    return [item for item in requested if not existing.get(item, {}).get("valid", False)]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--native-evaluator", type=Path, required=True)
    parser.add_argument("--vanilla", type=Path, default=ROOT / "Vanilla-Conquer/build-td/vanillatd")
    parser.add_argument("--data", type=Path, default=ROOT.parents[1] / "td-data")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work-root", type=Path)
    parser.add_argument("--samples-per-profile", type=int, default=100)
    parser.add_argument("--sample-seed-start", type=int, default=1000)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--timeout-seconds", type=int, default=180)
    parser.add_argument("--keep-artifacts", action="store_true")
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    for name in ("checkpoint", "native_evaluator", "vanilla", "data"):
        value = getattr(args, name).resolve()
        if not value.exists():
            parser.error(f"--{name.replace('_', '-')} does not exist: {value}")
        setattr(args, name, value)
    args.output = args.output.resolve()
    args.work_root = args.work_root.resolve() if args.work_root else args.output / "work"
    if args.samples_per_profile <= 0 or args.jobs <= 0 or args.timeout_seconds <= 0:
        parser.error("sample count, jobs, and timeout must be positive")
    return args


def main() -> int:
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    args.work_root.mkdir(parents=True, exist_ok=True)
    results_path = args.output / "episodes.jsonl"
    if results_path.exists() and not args.resume:
        raise EvaluationError(f"result file exists; pass --resume or choose another output: {results_path}")

    checkpoint_hash = sha256_file(args.checkpoint)
    manifest = (ROOT / "td-micro/generated/td_micro_v1.h").read_text(encoding="ascii")
    match = re.search(r'TD_MICRO_MANIFEST_SHA256 "([0-9a-f]{64})"', manifest)
    if match is None:
        raise EvaluationError("cannot read generated rules hash")
    rules_hash = match.group(1)
    source = source_metadata()
    existing = load_existing(results_path) if args.resume else {}
    requested = [
        (profile, sampling_seed)
        for profile in PROFILES
        for sampling_seed in range(args.sample_seed_start, args.sample_seed_start + args.samples_per_profile)
    ]
    pending = pending_requests(requested, existing)
    completed = len(requested) - len(pending)
    print(
        f"TD Micro transfer eval: episodes={len(requested)} pending={len(pending)} jobs={args.jobs} "
        f"checkpoint={checkpoint_hash[:12]} rules={rules_hash[:12]}",
        flush=True,
    )

    def complete(record: dict[str, Any]) -> None:
        nonlocal completed
        with RESULT_LOCK:
            with results_path.open("a", encoding="utf-8") as output:
                output.write(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n")
            existing[(record["profile"], record["sampling_seed"])] = record
            completed += 1
            status = "ok" if record["valid"] else f"ERROR {record.get('error', 'invalid')}"
            print(
                f"[{completed}/{len(requested)}] {record['profile']} "
                f"sample={record['sampling_seed']} {status}",
                flush=True,
            )

    if args.jobs == 1:
        for profile, sampling_seed in pending:
            complete(evaluate_tuple(profile, sampling_seed, args, checkpoint_hash, rules_hash, source))
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as executor:
            futures = [
                executor.submit(
                    evaluate_tuple,
                    profile,
                    sampling_seed,
                    args,
                    checkpoint_hash,
                    rules_hash,
                    source,
                )
                for profile, sampling_seed in pending
            ]
            for future in concurrent.futures.as_completed(futures):
                complete(future.result())

    records = [existing[key] for key in requested]
    summary = aggregate(records, checkpoint_hash, rules_hash)
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["infrastructure_failures"] == 0 else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvaluationError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
