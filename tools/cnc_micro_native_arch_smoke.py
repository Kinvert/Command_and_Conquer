#!/usr/bin/env python3
"""Exercise one native CUDA rollout/update and verify the selected policy layout."""

from __future__ import annotations

import argparse
import json
import math
import sys
import tempfile
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def load_fixed_eval(root: Path):
    import importlib.util

    path = root / "tools/cnc_micro_fixed_eval.py"
    spec = importlib.util.spec_from_file_location("cnc_micro_fixed_eval_smoke", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--network", choices=("MinGRU", "MLP"), required=True)
    parser.add_argument("--hidden-size", type=int, choices=(32, 64, 128), default=64)
    parser.add_argument("--num-layers", type=int, default=1)
    parser.add_argument("--action-scheme", type=int, choices=(0, 1), default=0)
    args = parser.parse_args()
    if args.num_layers <= 0:
        parser.error("--num-layers must be positive")

    root = repo_root()
    puffer_root = root / "PufferLib"
    sys.path.insert(0, str(puffer_root))
    import numpy
    import pufferlib.pufferl as pufferl

    fixed_eval = load_fixed_eval(root)
    caller_argv = sys.argv
    try:
        sys.argv = [caller_argv[0]]
        config = pufferl.load_config("cnc_micro")
    finally:
        sys.argv = caller_argv

    config["wandb"] = False
    config["slowly"] = False
    config["seed"] = 3187
    config["reset_state"] = False
    config["cudagraphs"] = 10
    config["env"]["max_decisions"] = 1
    config["env"]["action_scheme"] = args.action_scheme
    config["env"]["action_abi"] = 0
    config["vec"].update(
        {"total_agents": 64, "num_buffers": 1, "num_threads": 4}
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
            "horizon": 32,
            "minibatch_size": 2048,
            "total_timesteps": 2048,
            "replay_ratio": 1.0,
        }
    )

    backend = pufferl._resolve_backend(config)
    runtime = backend.create_pufferl(config)
    expected_bytes = fixed_eval.checkpoint_size(
        args.hidden_size, args.network, args.num_layers, args.action_scheme
    )
    expected_parameters = expected_bytes // fixed_eval.CHECKPOINT_ELEMENT_SIZE
    try:
        actual_parameters = runtime.num_params()
        if actual_parameters != expected_parameters:
            raise RuntimeError(
                f"native {args.network} parameter mismatch: "
                f"{actual_parameters} != {expected_parameters}"
            )
        backend.rollouts(runtime)
        action_bytes, _, _ = backend.read_env_step(runtime)
        spec = fixed_eval.action_spec(args.action_scheme)
        actions = numpy.frombuffer(action_bytes, dtype="<f4").reshape(
            config["vec"]["total_agents"], len(spec.head_sizes)
        )
        rounded_actions = numpy.rint(actions)
        if not numpy.isfinite(actions).all() or not numpy.allclose(
            actions, rounded_actions, rtol=0.0, atol=1.0e-4
        ):
            raise RuntimeError(f"native ABI{spec.abi} sampler emitted non-integral actions")
        sampled_actions = rounded_actions.astype(numpy.uint8)
        sampled_attack_count = int((sampled_actions[:, 0] == 6).sum())
        if spec.abi == 14:
            commands = sampled_actions[:, 0]
            attacks = commands == 6
            selectors = sampled_actions[:, 7:]
            if not numpy.any(attacks):
                raise RuntimeError("native ABI14 smoke did not exercise an attack action")
            if not numpy.isin(selectors, (0, 1)).all():
                raise RuntimeError("native ABI14 sampler emitted a non-binary selector")
            if numpy.any(selectors[~attacks] != 0):
                raise RuntimeError("native ABI14 sampler activated selectors outside attack")
            forced = numpy.array([64, 0, 3, 0, 0], dtype=numpy.uint8)
            if numpy.any(sampled_actions[attacks, 1:6] != forced):
                raise RuntimeError("native ABI14 sampler violated forced attack fields")
            empty_attacks = attacks & (selectors.sum(axis=1) == 0)
            if numpy.any(sampled_actions[empty_attacks, 6] != 0):
                raise RuntimeError("native ABI14 sampler did not canonicalize empty targets")
        backend.train(runtime)
        flat_eval = dict(pufferl.unroll_nested_dict(backend.eval_log(runtime)))
        env_log = {
            key.removeprefix("env/"): float(value)
            for key, value in flat_eval.items()
            if key.startswith("env/")
        }
        for key in ("start_failures", "failures"):
            if float(env_log.get(key, math.inf)) != 0.0:
                raise RuntimeError(f"env/{key}={env_log.get(key)}")
        with tempfile.NamedTemporaryFile(
            prefix=f"cnc-{args.network.lower()}-", suffix=".bin", delete=False
        ) as stream:
            checkpoint = Path(stream.name)
        try:
            backend.save_weights(runtime, str(checkpoint))
            actual_bytes = checkpoint.stat().st_size
        finally:
            checkpoint.unlink(missing_ok=True)
        if actual_bytes != expected_bytes:
            raise RuntimeError(
                f"native {args.network} checkpoint mismatch: "
                f"{actual_bytes} != {expected_bytes}"
            )
    finally:
        backend.close(runtime)

    print(
        json.dumps(
            {
                "valid": True,
                "network": args.network,
                "action_scheme": args.action_scheme,
                "action_abi": fixed_eval.action_spec(args.action_scheme).abi,
                "hidden_size": args.hidden_size,
                "num_layers": args.num_layers,
                "parameters": actual_parameters,
                "checkpoint_bytes": actual_bytes,
                "sampled_attack_count": sampled_attack_count,
                "start_failures": env_log["start_failures"],
                "failures": env_log["failures"],
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
