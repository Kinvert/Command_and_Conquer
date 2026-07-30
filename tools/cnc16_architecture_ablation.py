#!/usr/bin/env python3
"""Run the corrected locked native MLP-versus-MinGRU CNC architecture ablation."""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


ROOT = Path(__file__).resolve().parents[1]
CONFIRMATION = _load_module(
    "cnc13_stable_confirmation_arch", ROOT / "tools/cnc13_stable_confirmation.py"
)


@dataclass(frozen=True)
class ArchitectureSpec:
    candidate_id: str
    network: str
    seed: int
    total_timesteps: int

    @property
    def tag(self) -> str:
        if self.network == "MinGRU":
            return CONFIRMATION.RunSpec(
                self.candidate_id, self.seed, self.total_timesteps
            ).tag
        return (
            f"cnc16-arch-{self.candidate_id}-{self.network.lower()}-"
            f"2m-s{self.seed}"
        )


def default_manifest_path() -> Path:
    return Path(__file__).with_name("cnc16_architecture_ablation.json")


def _sha256(path: Path) -> str:
    return CONFIRMATION._sha256(path)


def load_protocol(path: Path) -> tuple[dict, dict, Path]:
    protocol = json.loads(path.read_text())
    required = {
        "version",
        "suite_id",
        "source_snapshot",
        "source_snapshot_sha256",
        "candidate_id",
        "networks",
        "training_seeds",
        "total_timesteps",
        "baseline_project",
        "experiment_project",
        "eval_seed",
        "episodes_per_profile",
    }
    if set(protocol) != required or protocol["version"] != 2:
        raise ValueError("invalid architecture protocol fields")
    if protocol["networks"] != ["MinGRU", "MLP"]:
        raise ValueError("architecture protocol must compare MinGRU and MLP")
    seeds = protocol["training_seeds"]
    if len(seeds) != 3 or len(set(seeds)) != 3:
        raise ValueError("architecture protocol requires three distinct seeds")
    source_path = path.with_name(protocol["source_snapshot"]).resolve()
    if _sha256(source_path) != protocol["source_snapshot_sha256"]:
        raise RuntimeError(f"locked source snapshot drift: {source_path}")
    snapshot = CONFIRMATION.load_snapshot(source_path)
    if protocol["candidate_id"] not in snapshot["candidates"]:
        raise ValueError("architecture candidate is absent from source snapshot")
    if int(protocol["total_timesteps"]) != int(
        snapshot["protocol"]["total_timesteps"]
    ):
        raise ValueError("architecture training budget differs from promoted run")
    return protocol, snapshot, source_path


def experiment_specs(protocol: dict) -> list[ArchitectureSpec]:
    return [
        ArchitectureSpec(
            protocol["candidate_id"],
            network,
            int(seed),
            int(protocol["total_timesteps"]),
        )
        for network in protocol["networks"]
        for seed in protocol["training_seeds"]
    ]


def resolved_config(snapshot: dict, spec: ArchitectureSpec) -> dict:
    config = copy.deepcopy(
        CONFIRMATION.resolved_candidate(snapshot, spec.candidate_id)
    )
    config["torch"]["network"] = spec.network
    return config


def project_for(protocol: dict, spec: ArchitectureSpec) -> str:
    if spec.network == "MinGRU":
        return protocol["baseline_project"]
    return protocol["experiment_project"]


def _find_run(
    puffer_root: Path, protocol: dict, snapshot: dict, spec: ArchitectureSpec
) -> Path | None:
    return CONFIRMATION.find_completed_run(
        puffer_root / "logs/cnc_micro",
        project_for(protocol, spec),
        resolved_config(snapshot, spec),
        spec,
    )


def _run_one(
    puffer_root: Path,
    protocol: dict,
    snapshot: dict,
    spec: ArchitectureSpec,
    force: bool,
) -> Path:
    project = project_for(protocol, spec)
    config = resolved_config(snapshot, spec)
    existing = None if force else _find_run(puffer_root, protocol, snapshot, spec)
    if existing is not None:
        checkpoint = CONFIRMATION.checkpoint_path(
            puffer_root, existing.stem, spec.total_timesteps
        )
        if checkpoint.exists():
            print(f"skip {spec.tag}: {existing.stem}", flush=True)
            return existing

    console_dir = puffer_root / "logs/cnc_micro/cnc16_architecture_console"
    console_dir.mkdir(parents=True, exist_ok=True)
    console_path = console_dir / f"{spec.tag}.log"
    command = CONFIRMATION.build_train_command(
        puffer_root, project, config, spec
    )
    print(f"run {spec.tag}", flush=True)
    with console_path.open("a") as console:
        console.write(f"\n$ {shlex.join(command)}\n")
        console.flush()
        subprocess.run(
            command,
            cwd=puffer_root,
            env=CONFIRMATION.training_environment(puffer_root),
            stdout=console,
            stderr=subprocess.STDOUT,
            check=True,
        )
    completed = _find_run(puffer_root, protocol, snapshot, spec)
    if completed is None:
        raise RuntimeError(f"no exact zero-failure result; inspect {console_path}")
    checkpoint = CONFIRMATION.checkpoint_path(
        puffer_root, completed.stem, spec.total_timesteps
    )
    if not checkpoint.exists():
        raise FileNotFoundError(f"missing final checkpoint: {checkpoint}")
    print(f"complete {spec.tag}: {completed.stem}", flush=True)
    return completed


def run_experiment(args, protocol: dict, snapshot: dict) -> int:
    puffer_root = args.puffer_root.resolve()
    specs = [spec for spec in experiment_specs(protocol) if spec.network == "MLP"]
    if not args.execute:
        for spec in specs:
            print(
                shlex.join(
                    CONFIRMATION.build_train_command(
                        puffer_root,
                        project_for(protocol, spec),
                        resolved_config(snapshot, spec),
                        spec,
                    )
                )
            )
        return 0
    for spec in specs:
        _run_one(puffer_root, protocol, snapshot, spec, args.force)
    return 0


def _output_dir(puffer_root: Path, protocol: dict) -> Path:
    return puffer_root / "logs/cnc_micro" / protocol["suite_id"].replace("-", "_")


def _eval_output(puffer_root: Path, protocol: dict, spec: ArchitectureSpec) -> Path:
    return _output_dir(puffer_root, protocol) / (
        f"{spec.network.lower()}-s{spec.seed}.json"
    )


def _targets(puffer_root: Path, protocol: dict, snapshot: dict):
    targets = []
    missing = []
    for spec in experiment_specs(protocol):
        run_path = _find_run(puffer_root, protocol, snapshot, spec)
        if run_path is None:
            missing.append(spec.tag)
            continue
        checkpoint = CONFIRMATION.checkpoint_path(
            puffer_root, run_path.stem, spec.total_timesteps
        )
        if not checkpoint.exists():
            missing.append(str(checkpoint))
            continue
        targets.append((spec, run_path, checkpoint))
    if missing:
        raise RuntimeError("missing architecture targets: " + ", ".join(missing))
    return targets


def _suite_manifest(
    manifest_path: Path,
    puffer_root: Path,
    protocol: dict,
    snapshot: dict,
) -> dict:
    targets = _targets(puffer_root, protocol, snapshot)
    return {
        "version": 1,
        "suite_id": protocol["suite_id"],
        "protocol": str(manifest_path),
        "protocol_sha256": _sha256(manifest_path),
        "source_snapshot_sha256": protocol["source_snapshot_sha256"],
        "candidate_id": protocol["candidate_id"],
        "only_variable": "torch.network",
        "eval_seed": protocol["eval_seed"],
        "episodes_per_profile": protocol["episodes_per_profile"],
        "targets": [
            {
                "network": spec.network,
                "training_seed": spec.seed,
                "training_project": project_for(protocol, spec),
                "run_id": run_path.stem,
                "training_steps": spec.total_timesteps,
                "checkpoint": str(checkpoint),
                "checkpoint_sha256": _sha256(checkpoint),
            }
            for spec, run_path, checkpoint in targets
        ],
    }


def _lock_manifest(path: Path, manifest: dict) -> None:
    if path.exists():
        if json.loads(path.read_text()) != manifest:
            raise RuntimeError(f"architecture suite manifest drift: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def _scores(puffer_root: Path, protocol: dict) -> list:
    scores = []
    for spec in experiment_specs(protocol):
        path = _eval_output(puffer_root, protocol, spec)
        if not path.exists():
            continue
        data = json.loads(path.read_text())
        if data.get("network") != spec.network or data.get("valid") is not True:
            raise RuntimeError(f"invalid architecture evaluation: {path}")
        scores.append(
            CONFIRMATION.EvalScore(
                spec.network,
                spec.seed,
                float(data["robust_perf"]),
                float(data["profiles"]["close"]["win_rate"]),
                float(data["profiles"]["medium"]["win_rate"]),
            )
        )
    return scores


def _print_report(scores: list) -> None:
    print("network,seed,robust,close,medium")
    for score in sorted(scores, key=lambda row: (row.candidate_id, row.seed)):
        print(
            f"{score.candidate_id},{score.seed},{score.robust_perf:.6f},"
            f"{score.close_win_rate:.6f},{score.medium_win_rate:.6f}"
        )
    print("\narchitecture ranking")
    for row in CONFIRMATION.rank_scores(scores):
        print(
            f"{row['candidate_id']}: eligible={row['eligible']} "
            f"median={row['median_robust']:.4f} worst={row['worst_robust']:.4f} "
            f"worst_profile={row['worst_seed_profile']:.4f}"
        )


def evaluate_experiment(
    args, manifest_path: Path, protocol: dict, snapshot: dict
) -> int:
    puffer_root = args.puffer_root.resolve()
    targets = _targets(puffer_root, protocol, snapshot)
    suite_manifest = _suite_manifest(
        manifest_path, puffer_root, protocol, snapshot
    )
    if not args.execute:
        print(json.dumps(suite_manifest, indent=2, sort_keys=True))
        for spec, _, checkpoint in targets:
            print(
                shlex.join(
                    CONFIRMATION.build_eval_command(
                        ROOT,
                        puffer_root,
                        checkpoint,
                        _eval_output(puffer_root, protocol, spec),
                        int(protocol["episodes_per_profile"]),
                        int(protocol["eval_seed"]),
                    )
                )
            )
        return 0

    locked_path = _output_dir(puffer_root, protocol) / "suite_manifest.json"
    _lock_manifest(locked_path, suite_manifest)
    for spec, run_path, _ in targets:
        CONFIRMATION._evaluate_one(
            ROOT,
            puffer_root,
            spec,
            run_path,
            int(protocol["episodes_per_profile"]),
            int(protocol["eval_seed"]),
            args.force,
            _eval_output(puffer_root, protocol, spec),
        )
    print(f"suite={protocol['suite_id']} manifest={locked_path}")
    _print_report(_scores(puffer_root, protocol))
    return 0


def report_experiment(args, protocol: dict) -> int:
    scores = _scores(args.puffer_root.resolve(), protocol)
    _print_report(scores)
    print(f"\ncompleted={len(scores)}/{len(experiment_specs(protocol))}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=default_manifest_path())
    parser.add_argument("--puffer-root", type=Path, default=ROOT / "PufferLib")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("run", "evaluate"):
        child = subparsers.add_parser(name)
        child.add_argument("--execute", action="store_true")
        child.add_argument("--force", action="store_true")
    subparsers.add_parser("report")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = args.manifest.resolve()
    protocol, snapshot, _ = load_protocol(manifest_path)
    if args.command == "run":
        return run_experiment(args, protocol, snapshot)
    if args.command == "evaluate":
        return evaluate_experiment(args, manifest_path, protocol, snapshot)
    if args.command == "report":
        return report_experiment(args, protocol)
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
