#!/usr/bin/env python3
"""Evaluate an ABI9 or ABI14 CNC Micro checkpoint on an exact native-CUDA suite."""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import math
import struct
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, replace
from pathlib import Path


OBSERVATION_SIZE = 2_456
OBSERVATION_VERSION = 6
CREDITS_OBSERVATION_OFFSET = 4
DIFFICULTY_OBSERVATION_OFFSET = 33
ENTITY_RECORD_SIZE = 16
ENTITY_PRESENCE = 0
ENTITY_TYPE = 1
OWN_ENTITIES_OFFSET = 64 + 344
OWN_ENTITY_COUNT = 64
OBJECT_E1 = 5
OBJECT_E3 = 6
CHECKPOINT_ELEMENT_SIZE = 4
DEFAULT_POLICY_RESET_HORIZON = 32
ROBUST_EPSILON = 0.01
CREDIT_BAND_RANGES = (
    ("constrained", 2_300, 2_300),
    ("low", 2_400, 4_900),
    ("mid", 5_000, 7_400),
    ("rich", 7_500, 10_000),
)
CREDIT_BAND_NAMES = tuple(name for name, _, _ in CREDIT_BAND_RANGES)
SPAWN_PROFILES = ("close", "medium")
STARTING_FORCE_VARIANTS = ("mcv_only", "unit_count_6")
DIFFICULTY_SCHEDULE_IDS = {"easy": 0, "normal": 2, "hard": 3}
DIFFICULTY_OBSERVATION_VALUES = {"easy": 0, "normal": 1, "hard": 2}


@dataclass(frozen=True)
class ActionSpec:
    scheme: int
    abi: int
    head_sizes: tuple[int, ...]
    action_mask_size: int
    decoder_logit_count: int


ACTION_SPECS = {
    0: ActionSpec(
        scheme=0,
        abi=9,
        head_sizes=(12, 65, 6, 4, 64, 64, 64),
        action_mask_size=279,
        decoder_logit_count=279,
    ),
    1: ActionSpec(
        scheme=1,
        abi=14,
        head_sizes=(12, 65, 6, 4, 64, 64, 64) + (2,) * 64,
        action_mask_size=471,
        decoder_logit_count=407,
    ),
}


def action_spec(action_scheme: int) -> ActionSpec:
    try:
        return ACTION_SPECS[action_scheme]
    except KeyError as error:
        raise ValueError(f"unsupported action_scheme: {action_scheme}") from error


@dataclass(frozen=True)
class SuiteRow:
    lane: int
    profile: str
    setup_seed: int
    buffer: int
    sampling_seed: int
    sampling_sequence: int
    starting_credits: int | None = None
    credit_band: str | None = None
    starting_force: str | None = None


@dataclass(frozen=True)
class EpisodeResult:
    lane: int
    profile: str
    setup_seed: int
    buffer: int
    sampling_seed: int
    sampling_sequence: int
    starting_credits: int
    credit_band: str
    starting_force: str
    result: str
    terminal_reward: float
    decisions: int
    action_sha256: str


def checkpoint_size(
    hidden_size: int,
    network: str = "MinGRU",
    num_layers: int = 1,
    action_scheme: int = 0,
) -> int:
    if hidden_size <= 0:
        raise ValueError("hidden_size must be positive")
    if num_layers <= 0:
        raise ValueError("num_layers must be positive")
    encoder = hidden_size * OBSERVATION_SIZE
    spec = action_spec(action_scheme)
    decoder = hidden_size * (spec.decoder_logit_count + 1)
    if network == "MinGRU":
        network_parameters = num_layers * 3 * hidden_size * hidden_size
    elif network == "MLP":
        network_parameters = num_layers * (hidden_size * hidden_size + hidden_size)
    else:
        raise ValueError(f"unsupported network: {network}")
    return (encoder + decoder + network_parameters) * CHECKPOINT_ELEMENT_SIZE


def infer_policy_shape(
    size: int,
    hidden_size: int | None = None,
    network: str | None = None,
    num_layers: int | None = None,
    action_scheme: int = 0,
) -> tuple[int, str, int]:
    hidden_sizes = (hidden_size,) if hidden_size is not None else (32, 64, 128)
    networks = (network,) if network is not None else ("MinGRU", "MLP")
    layer_counts = (num_layers,) if num_layers is not None else (1,)
    candidates = [
        (hidden, architecture, layers)
        for hidden in hidden_sizes
        for architecture in networks
        for layers in layer_counts
        if checkpoint_size(hidden, architecture, layers, action_scheme) == size
    ]
    if len(candidates) == 1:
        return candidates[0]
    expected = ", ".join(
        f"{architecture}-H{hidden}-L{layers}="
        f"{checkpoint_size(hidden, architecture, layers, action_scheme)}"
        for hidden in hidden_sizes
        for architecture in networks
        for layers in layer_counts
    )
    spec = action_spec(action_scheme)
    raise ValueError(
        f"unsupported ABI{spec.abi} checkpoint size {size}; expected {expected}"
    )


def infer_hidden_size(size: int, action_scheme: int = 0) -> int:
    hidden_size, _, _ = infer_policy_shape(
        size,
        network="MinGRU",
        num_layers=1,
        action_scheme=action_scheme,
    )
    return hidden_size


def build_suite(
    episodes_per_profile: int,
    eval_seed: int,
    num_buffers: int,
) -> list[SuiteRow]:
    if episodes_per_profile <= 0:
        raise ValueError("episodes_per_profile must be positive")
    total_agents = 2 * episodes_per_profile
    if num_buffers <= 0 or total_agents % num_buffers != 0:
        raise ValueError("num_buffers must evenly divide the exact suite")
    agents_per_buffer = total_agents // num_buffers
    rows = []
    for lane in range(total_agents):
        setup_seed = 1 + lane % 2
        buffer = lane // agents_per_buffer
        rows.append(
            SuiteRow(
                lane=lane,
                profile="close" if setup_seed == 1 else "medium",
                setup_seed=setup_seed,
                buffer=buffer,
                sampling_seed=eval_seed + buffer,
                sampling_sequence=lane % agents_per_buffer,
            )
        )
    return rows


def credit_band(starting_credits: int) -> str:
    if starting_credits % 100 != 0:
        raise ValueError(f"invalid starting credits: {starting_credits}")
    for name, minimum, maximum in CREDIT_BAND_RANGES:
        if minimum <= starting_credits <= maximum:
            return name
    raise ValueError(f"invalid starting credits: {starting_credits}")


def attach_starting_credits(
    suite: list[SuiteRow], observations, expected_difficulty: str | None = None
) -> list[SuiteRow]:
    if len(observations) != len(suite):
        raise ValueError(
            f"initial observation count {len(observations)} != suite size {len(suite)}"
        )
    labeled = []
    for row in suite:
        observation = observations[row.lane]
        if len(observation) != OBSERVATION_SIZE:
            raise ValueError(
                f"lane {row.lane} observation size {len(observation)} != {OBSERVATION_SIZE}"
            )
        version = int(observation[0])
        if version != OBSERVATION_VERSION:
            raise ValueError(
                f"lane {row.lane} observation version {version} != {OBSERVATION_VERSION}"
            )
        if expected_difficulty is not None:
            actual_difficulty = int(observation[DIFFICULTY_OBSERVATION_OFFSET])
            expected_value = DIFFICULTY_OBSERVATION_VALUES[expected_difficulty]
            if actual_difficulty != expected_value:
                raise ValueError(
                    f"lane {row.lane} difficulty {actual_difficulty} != "
                    f"{expected_difficulty} ({expected_value})"
                )
        starting_credits = int(observation[CREDITS_OBSERVATION_OFFSET]) * 100
        e1_count = 0
        e3_count = 0
        for slot in range(OWN_ENTITY_COUNT):
            offset = OWN_ENTITIES_OFFSET + slot * ENTITY_RECORD_SIZE
            if not observation[offset + ENTITY_PRESENCE]:
                continue
            kind = int(observation[offset + ENTITY_TYPE])
            e1_count += kind == OBJECT_E1
            e3_count += kind == OBJECT_E3
        if e1_count == 0 and e3_count == 0:
            starting_force = "mcv_only"
        elif e1_count == 3 and e3_count == 3:
            starting_force = "unit_count_6"
        else:
            raise ValueError(
                f"lane {row.lane} invalid starting force: E1={e1_count} E3={e3_count}"
            )
        labeled.append(
            replace(
                row,
                starting_credits=starting_credits,
                credit_band=credit_band(starting_credits),
                starting_force=starting_force,
            )
        )
    return labeled


def harmonic_robust_perf(win_rates) -> float:
    win_rates = tuple(float(rate) for rate in win_rates)
    if not win_rates:
        raise ValueError("at least one win rate is required")
    if any(not 0.0 <= rate <= 1.0 for rate in win_rates):
        raise ValueError("win rates must be in [0, 1]")
    shifted = len(win_rates) / sum(
        1.0 / (rate + ROBUST_EPSILON) for rate in win_rates
    )
    return max(0.0, shifted - ROBUST_EPSILON)


def robust_perf(close_win_rate: float, medium_win_rate: float) -> float:
    return harmonic_robust_perf((close_win_rate, medium_win_rate))


def _outcome_counts(episodes: list[EpisodeResult]) -> dict[str, float | int]:
    if not episodes:
        raise ValueError("cannot summarize an empty episode group")
    wins = sum(episode.result == "win" for episode in episodes)
    losses = sum(episode.result == "loss" for episode in episodes)
    draws = len(episodes) - wins - losses
    return {
        "episodes": len(episodes),
        "wins": wins,
        "losses": losses,
        "draws": draws,
        "win_rate": wins / len(episodes),
    }


def summarize_results(episodes: list[EpisodeResult]) -> dict:
    if not episodes:
        raise ValueError("cannot summarize an empty fixed suite")
    for episode in episodes:
        if episode.profile not in SPAWN_PROFILES:
            raise ValueError(f"unsupported spawn profile: {episode.profile}")
        if episode.starting_force not in STARTING_FORCE_VARIANTS:
            raise ValueError(
                f"unsupported starting force: {episode.starting_force}"
            )
        expected_band = credit_band(episode.starting_credits)
        if episode.credit_band != expected_band:
            raise ValueError(
                f"lane {episode.lane} credit band {episode.credit_band!r} "
                f"does not match {expected_band!r}"
            )

    profiles = {
        profile: _outcome_counts(
            [episode for episode in episodes if episode.profile == profile]
        )
        for profile in SPAWN_PROFILES
    }
    credit_bands = {
        band: _outcome_counts(
            [episode for episode in episodes if episode.credit_band == band]
        )
        for band in CREDIT_BAND_NAMES
    }
    starting_forces = {
        starting_force: _outcome_counts(
            [
                episode
                for episode in episodes
                if episode.starting_force == starting_force
            ]
        )
        for starting_force in STARTING_FORCE_VARIANTS
    }
    spawn_force_cells = {}
    missing_force_cells = []
    force_cell_win_rates = []
    for profile in SPAWN_PROFILES:
        spawn_force_cells[profile] = {}
        for starting_force in STARTING_FORCE_VARIANTS:
            rows = [
                episode
                for episode in episodes
                if episode.profile == profile
                and episode.starting_force == starting_force
            ]
            if not rows:
                missing_force_cells.append(f"{profile}/{starting_force}")
                continue
            stats = _outcome_counts(rows)
            spawn_force_cells[profile][starting_force] = stats
            force_cell_win_rates.append(stats["win_rate"])
    if missing_force_cells:
        raise ValueError(
            f"missing spawn-force cells: {', '.join(missing_force_cells)}"
        )

    spawn_credit_cells = {}
    missing_credit_cells = []
    for profile in SPAWN_PROFILES:
        spawn_credit_cells[profile] = {}
        for band in CREDIT_BAND_NAMES:
            rows = [
                episode
                for episode in episodes
                if episode.profile == profile and episode.credit_band == band
            ]
            if not rows:
                missing_credit_cells.append(f"{profile}/{band}")
                continue
            stats = _outcome_counts(rows)
            spawn_credit_cells[profile][band] = stats
    if missing_credit_cells:
        raise ValueError(
            f"missing spawn-credit cells: {', '.join(missing_credit_cells)}"
        )

    spawn_force_credit_cells = {}
    missing_force_credit_cells = []
    force_credit_cell_win_rates = []
    for profile in SPAWN_PROFILES:
        spawn_force_credit_cells[profile] = {}
        for starting_force in STARTING_FORCE_VARIANTS:
            spawn_force_credit_cells[profile][starting_force] = {}
            for band in CREDIT_BAND_NAMES:
                rows = [
                    episode
                    for episode in episodes
                    if episode.profile == profile
                    and episode.starting_force == starting_force
                    and episode.credit_band == band
                ]
                if not rows:
                    missing_force_credit_cells.append(
                        f"{profile}/{starting_force}/{band}"
                    )
                    continue
                stats = _outcome_counts(rows)
                spawn_force_credit_cells[profile][starting_force][band] = stats
                force_credit_cell_win_rates.append(stats["win_rate"])
    if missing_force_credit_cells:
        raise ValueError(
            "missing spawn-force-credit cells: "
            + ", ".join(missing_force_credit_cells)
        )

    profile_win_rates = [profiles[profile]["win_rate"] for profile in SPAWN_PROFILES]
    return {
        "profiles": profiles,
        "starting_forces": starting_forces,
        "credit_bands": credit_bands,
        "spawn_force_cells": spawn_force_cells,
        "spawn_credit_cells": spawn_credit_cells,
        "spawn_force_credit_cells": spawn_force_credit_cells,
        "spawn_balanced_perf": sum(profile_win_rates) / len(profile_win_rates),
        "spawn_robust_perf": harmonic_robust_perf(profile_win_rates),
        "balanced_perf": sum(force_cell_win_rates) / len(force_cell_win_rates),
        "robust_perf": harmonic_robust_perf(force_cell_win_rates),
        "credit_balanced_perf": (
            sum(force_credit_cell_win_rates) / len(force_credit_cell_win_rates)
        ),
        "credit_robust_perf": harmonic_robust_perf(
            force_credit_cell_win_rates
        ),
    }


def validate_native_log(log: dict, expected_episodes: int) -> None:
    episodes = round(float(log.get("n", 0.0)))
    if episodes < expected_episodes:
        raise RuntimeError(
            f"native evaluator must complete at least {expected_episodes} episodes; got {episodes}"
        )
    failures = float(log.get("failures", 0.0))
    if failures != 0.0:
        raise RuntimeError(f"native evaluator reported failures={failures}")
    start_failures = float(log.get("start_failures", 0.0))
    if start_failures != 0.0:
        raise RuntimeError(f"native evaluator reported start_failures={start_failures}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _git_head(root: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def _load_config(pufferl, total_agents: int, num_buffers: int, args) -> dict:
    caller_argv = sys.argv
    try:
        sys.argv = [caller_argv[0]]
        config = pufferl.load_config("cnc_micro")
    finally:
        sys.argv = caller_argv

    config["wandb"] = False
    config["slowly"] = False
    config["seed"] = args.eval_seed
    config["reset_state"] = False
    config["cudagraphs"] = 10
    config["env"].update(
        {
            "seed": 1,
            "max_decisions": args.max_decisions,
            "action_scheme": args.action_scheme,
            "action_abi": 0,
            "curriculum_schedule_id": 0,
            "curriculum_stage_decisions": 0,
            "starting_force_ramp_decisions": 0,
            "difficulty_schedule_id": DIFFICULTY_SCHEDULE_IDS[args.difficulty],
            "difficulty_ramp_decisions": 0,
            "reward_milestone": 0.0,
            "reward_player_infantry": 0.0,
            "reward_enemy_unit_loss": 0.0,
            "reward_enemy_building_loss": 0.0,
            "reward_player_unit_loss": 0.0,
            "reward_refinery": 0.0,
            "reward_first_delivery": 0.0,
            "reward_tiberium_income": 0.0,
            "reward_invalid_action": 0.0,
        }
    )
    config["vec"].update(
        {
            "total_agents": total_agents,
            "num_buffers": num_buffers,
            "num_threads": min(args.num_threads, num_buffers),
        }
    )
    config["policy"].update(
        {
            "hidden_size": args.hidden_size,
            "num_layers": args.num_layers,
            "expansion_factor": 1,
        }
    )
    config["torch"]["network"] = args.network
    config["train"].update(
        {
            "gpus": 1,
            "horizon": 1,
            "minibatch_size": total_agents,
            "total_timesteps": total_agents,
        }
    )
    return config


def _trajectory_hash(row: SuiteRow, decisions: int, actions) -> str:
    digest = hashlib.sha256()
    digest.update(
        struct.pack(
            "<QQQQI",
            row.setup_seed,
            row.buffer,
            row.sampling_seed,
            row.sampling_sequence,
            decisions,
        )
    )
    digest.update(actions[:decisions].tobytes(order="C"))
    return digest.hexdigest()


def _result_label(reward: float) -> str:
    if reward > 0.5:
        return "win"
    if reward < -0.5:
        return "loss"
    return "draw"


def _native_env_log(pufferl, backend, runtime) -> dict[str, float]:
    flat = dict(pufferl.unroll_nested_dict(backend.eval_log(runtime)))
    return {
        key.removeprefix("env/"): float(value)
        for key, value in flat.items()
        if key.startswith("env/")
    }


def _capture_initial_observations(backend, config: dict, total_agents: int):
    vec = backend.create_vec(config, 0)
    try:
        if vec.total_agents != total_agents:
            raise RuntimeError(
                f"native vector agents {vec.total_agents} != expected {total_agents}"
            )
        if (
            vec.obs_size != OBSERVATION_SIZE
            or vec.obs_elem_size != 1
            or vec.obs_dtype not in ("ByteTensor", "uint8")
        ):
            raise RuntimeError(
                f"unexpected native observation layout: {vec.obs_dtype}[{vec.obs_size}]"
            )
        vec.reset()
        size = total_agents * OBSERVATION_SIZE
        raw = (ctypes.c_uint8 * size).from_address(vec.obs_ptr)
        return [
            bytes(raw[lane * OBSERVATION_SIZE : (lane + 1) * OBSERVATION_SIZE])
            for lane in range(total_agents)
        ]
    finally:
        vec.close()


def evaluate(args: argparse.Namespace) -> tuple[dict, list[EpisodeResult]]:
    import numpy

    root = _repo_root()
    puffer_root = args.puffer_root.resolve()
    sys.path.insert(0, str(puffer_root))
    import pufferlib.pufferl as pufferl

    checkpoint = args.checkpoint.resolve()
    spec = action_spec(args.action_scheme)
    args.hidden_size, args.network, args.num_layers = infer_policy_shape(
        checkpoint.stat().st_size,
        hidden_size=args.hidden_size,
        network=args.network,
        num_layers=args.num_layers,
        action_scheme=args.action_scheme,
    )
    expected_checkpoint_size = checkpoint_size(
        args.hidden_size, args.network, args.num_layers, args.action_scheme
    )
    if checkpoint.stat().st_size != expected_checkpoint_size:
        raise ValueError(
            f"checkpoint size does not match hidden_size={args.hidden_size}: "
            f"{checkpoint.stat().st_size} != {expected_checkpoint_size}"
        )

    total_agents = 2 * args.episodes_per_profile
    num_buffers = args.num_buffers
    suite = build_suite(args.episodes_per_profile, args.eval_seed, num_buffers)
    config = _load_config(pufferl, total_agents, num_buffers, args)
    backend = pufferl._resolve_backend(config)
    for required in ("read_env_step", "reset_recurrent_state"):
        if not hasattr(backend, required):
            raise RuntimeError(f"native backend is missing {required}; rebuild cnc_micro")

    suite = attach_starting_credits(
        suite,
        _capture_initial_observations(backend, config, total_agents),
        expected_difficulty=args.difficulty,
    )

    runtime = backend.create_pufferl(config)
    action_trace = numpy.zeros(
        (total_agents, args.max_decisions, len(spec.head_sizes)), dtype=numpy.uint8
    )
    active = numpy.ones(total_agents, dtype=numpy.bool_)
    terminal_rewards = numpy.zeros(total_agents, dtype=numpy.float32)
    lengths = numpy.zeros(total_agents, dtype=numpy.uint32)
    executed_decisions = 0
    started = time.perf_counter()
    try:
        backend.load_weights(runtime, str(checkpoint))
        for decision in range(args.max_decisions):
            if decision % args.policy_reset_horizon == 0:
                backend.reset_recurrent_state(runtime)
            backend.rollouts(runtime)
            action_bytes, reward_bytes, terminal_bytes = backend.read_env_step(runtime)
            actions = numpy.frombuffer(action_bytes, dtype="<f4").reshape(
                total_agents, len(spec.head_sizes)
            )
            rounded_actions = numpy.rint(actions)
            if not numpy.isfinite(actions).all() or not numpy.allclose(
                actions, rounded_actions, rtol=0.0, atol=1.0e-4
            ):
                raise RuntimeError(
                    f"native sampler produced a non-integral ABI{spec.abi} action"
                )
            action_values = rounded_actions.astype(numpy.uint8)
            action_trace[active, decision, :] = action_values[active]

            rewards = numpy.frombuffer(reward_bytes, dtype="<f4")
            terminals = numpy.frombuffer(terminal_bytes, dtype="<f4") != 0.0
            finished = active & terminals
            if finished.any():
                terminal_rewards[finished] = rewards[finished]
                lengths[finished] = decision + 1
                active[finished] = False
            executed_decisions = decision + 1
            if not active.any():
                break
        if active.any():
            raise RuntimeError(
                f"{int(active.sum())} lanes did not terminate by max_decisions={args.max_decisions}"
            )
        native_log = _native_env_log(pufferl, backend, runtime)
        validate_native_log(native_log, total_agents)
    finally:
        backend.close(runtime)
    elapsed = time.perf_counter() - started

    episodes = []
    for row in suite:
        reward = float(terminal_rewards[row.lane])
        decisions = int(lengths[row.lane])
        episodes.append(
            EpisodeResult(
                **asdict(row),
                result=_result_label(reward),
                terminal_reward=reward,
                decisions=decisions,
                action_sha256=_trajectory_hash(row, decisions, action_trace[row.lane]),
            )
        )

    result_summary = summarize_results(episodes)

    suite_json = json.dumps([asdict(row) for row in suite], sort_keys=True, separators=(",", ":"))
    episode_jsonl = "".join(
        json.dumps(asdict(episode), sort_keys=True, separators=(",", ":")) + "\n"
        for episode in episodes
    )
    native_episodes = round(native_log["n"])
    executed_transitions = total_agents * executed_decisions
    outcome_transitions = sum(episode.decisions for episode in episodes)
    summary = {
        "version": 4,
        "valid": True,
        "checkpoint": str(checkpoint),
        "checkpoint_sha256": sha256(checkpoint),
        "source_commit": _git_head(root),
        "command": sys.argv,
        "action_scheme": spec.scheme,
        "action_abi": spec.abi,
        "action_head_sizes": spec.head_sizes,
        "action_mask_size": spec.action_mask_size,
        "decoder_logit_count": spec.decoder_logit_count,
        "observation_size": OBSERVATION_SIZE,
        "difficulty": args.difficulty,
        "hidden_size": args.hidden_size,
        "network": args.network,
        "num_layers": args.num_layers,
        "policy_reset_horizon": args.policy_reset_horizon,
        "backend_horizon": 1,
        "eval_seed": args.eval_seed,
        "sampling": "native_curand_philox4x32_10",
        "episodes_per_profile": args.episodes_per_profile,
        "episodes": len(episodes),
        **result_summary,
        "credit_band_definition": [
            {"name": name, "minimum": minimum, "maximum": maximum}
            for name, minimum, maximum in CREDIT_BAND_RANGES
        ],
        "outcome_transitions": outcome_transitions,
        "executed_transitions": executed_transitions,
        "elapsed_seconds": elapsed,
        "evaluator_sps": executed_transitions / elapsed,
        "start_failures": native_log["start_failures"],
        "failures": native_log["failures"],
        "native_completed_episodes": native_episodes,
        "native_extra_episodes": native_episodes - len(episodes),
        "suite_sha256": hashlib.sha256(suite_json.encode()).hexdigest(),
        "episodes_sha256": hashlib.sha256(episode_jsonl.encode()).hexdigest(),
        "num_buffers": num_buffers,
        "num_threads": min(args.num_threads, num_buffers),
        "native_log": native_log,
    }
    summary["_episode_jsonl"] = episode_jsonl
    return summary, episodes


def _default_output(args: argparse.Namespace) -> Path:
    root = _repo_root()
    return (
        root
        / "PufferLib/logs/cnc_micro/fixed_eval"
        / (
            f"{args.checkpoint.parent.name}-{args.checkpoint.stem}"
            f"-abi{action_spec(args.action_scheme).abi}-{args.difficulty}"
            f"-seed{args.eval_seed}.json"
        )
    )


def write_result(path: Path, summary: dict) -> tuple[Path, Path]:
    path.parent.mkdir(parents=True, exist_ok=True)
    episode_path = path.with_suffix(".episodes.jsonl")
    episode_jsonl = summary.pop("_episode_jsonl")
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)
    temporary_episodes = episode_path.with_suffix(episode_path.suffix + ".tmp")
    temporary_episodes.write_text(episode_jsonl)
    temporary_episodes.replace(episode_path)
    return path, episode_path


def parse_args() -> argparse.Namespace:
    root = _repo_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--puffer-root", type=Path, default=root / "PufferLib")
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--episodes-per-profile", type=int, default=512)
    parser.add_argument("--eval-seed", type=int, default=173)
    parser.add_argument("--hidden-size", type=int, choices=(32, 64, 128), default=None)
    parser.add_argument("--network", choices=("MinGRU", "MLP"), default=None)
    parser.add_argument("--num-layers", type=int, default=None)
    parser.add_argument("--action-scheme", type=int, choices=tuple(ACTION_SPECS), default=0)
    parser.add_argument(
        "--difficulty",
        choices=tuple(DIFFICULTY_SCHEDULE_IDS),
        default="easy",
        help="fixed opponent difficulty; run Easy and Normal separately for CNC25 promotion",
    )
    parser.add_argument("--max-decisions", type=int, default=12_000)
    parser.add_argument(
        "--policy-reset-horizon", type=int, default=DEFAULT_POLICY_RESET_HORIZON
    )
    parser.add_argument("--num-buffers", type=int, default=4)
    parser.add_argument("--num-threads", type=int, default=4)
    args = parser.parse_args()
    for name in (
        "episodes_per_profile",
        "max_decisions",
        "policy_reset_horizon",
        "num_buffers",
        "num_threads",
    ):
        if getattr(args, name) <= 0:
            parser.error(f"--{name.replace('_', '-')} must be positive")
    if (2 * args.episodes_per_profile) % args.num_buffers != 0:
        parser.error("--num-buffers must divide the total exact episode count")
    if args.num_layers is not None and args.num_layers <= 0:
        parser.error("--num-layers must be positive")
    if not args.checkpoint.is_file():
        parser.error(f"checkpoint does not exist: {args.checkpoint}")
    return args


def main() -> int:
    args = parse_args()
    summary, _ = evaluate(args)
    output = args.output or _default_output(args)
    summary_path, episode_path = write_result(output.resolve(), summary)
    print(
        json.dumps(
            {
                "valid": summary["valid"],
                "robust_perf": summary["robust_perf"],
                "balanced_perf": summary["balanced_perf"],
                "credit_robust_perf": summary["credit_robust_perf"],
                "credit_balanced_perf": summary["credit_balanced_perf"],
                "profiles": summary["profiles"],
                "starting_forces": summary["starting_forces"],
                "credit_bands": summary["credit_bands"],
                "episodes": summary["episodes"],
                "evaluator_sps": summary["evaluator_sps"],
                "native_extra_episodes": summary["native_extra_episodes"],
                "episodes_sha256": summary["episodes_sha256"],
                "summary": str(summary_path),
                "episode_rows": str(episode_path),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
