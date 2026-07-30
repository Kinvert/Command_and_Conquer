# CNC24 Action-Scheme 5 Mi Sweep

Date: 2026-07-23

Status: 1,000-run Protein sweep launched at 2026-07-23 16:44 PDT.

## Purpose

CNC24 compares the established ABI9 single-actor action scheme against ABI14 group attack
selection while jointly searching the existing optimizer, reward, H0-H5 curriculum, defended-start
ramp, and H64/H128 model ranges. Rewards, observations, simulation rules, and the H5-only
`balanced_perf` objective are unchanged.

## Fixed Contract

- implementation commit: `8ef8143`
- W&B project: `cnc24`
- launcher: `tools/run_cnc24_action_scheme_5mi_sweep.sh`
- maximum trials: 1,000
- native CUDA workers: three concurrent workers on one GPU
- stop: 5,242,880 transitions per trial
- immutable continuation schedule: 10,485,760 transitions
- vector: 64 agents, one buffer, four threads
- PPO horizon/minibatch: 32/2,048
- policy: native MinGRU, one layer, H64 or H128
- action scheme: Protein categorical choice, `0` = ABI9 and `1` = ABI14
- observation: unchanged byte observation v5 with GPU normalization
- objective: H5-only close/medium `balanced_perf`
- `sweep_only`: absent
- policy, training, environment, and canonical seeds: unchanged

## Launch Gates

Before launch:

- Zig Debug, ReleaseSafe, and ReleaseFast suites passed.
- C binding, C++ schema, CUDA CPU/GPU gradient, fixed evaluation, and sweep-config tests passed.
- ABI9 and ABI14 produced the same fixed-workload world digest:
  `8814cd2df3976c88bda246c141394402158d81c80b2ba6e75ccc444bf170ecf6`.
- The canonical ABI14 group trace remained
  `294be02cc1bd0b3672df4c42f7f03dc7a7f07d8178d1da9801384e9492eab425`.
- A 12-trial mixed Protein gate completed all trials. Seven used ABI9 and five used ABI14; every
  optimizer-active trial had finite loss/KL, and every trial had `start_failures=0`.

The PPO and Protein warm-up findings are in `abi14_group_action_experiment.md`.

## Launch

```bash
tools/run_cnc24_action_scheme_5mi_sweep.sh 1000
```

Persistent session:

```text
cnc24-sweep
```

Console log:

```text
PufferLib/logs/cnc_micro/cnc24_action_scheme_5mi_sweep_1000.console.log
```

Initial W&B runs:

- `gallant-jazz-41` (`mtfqjob9`)
- `graceful-grass-41` (`kshivdk9`)
- `swept-eon-43` (`flqt8rjm`)

The initial workers detected 7, 71, and 7 action heads respectively, proving that Protein samples
one fixed action scheme per complete training trial.

## Promotion Rule

Do not select an action scheme from one terminal training bucket. Analyze curves and stratify
results by action scheme, then reproduce leading configurations across multiple training seeds and
the fixed close/medium, MCV/force, and credit evaluation cells. Report learning quality and SPS
separately because ABI14 changes gameplay workload.
