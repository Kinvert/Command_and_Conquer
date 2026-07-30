# CNC23 Defended-Curriculum 5 Mi Sweep

Date: 2026-07-23

Status: one-run integration gate passed; 1,000-run broad sweep launched at 2026-07-23 11:59 PDT.

## Purpose

CNC23 searches the optimizer, reward, H0-H5 curriculum pace, and defended-start ramp jointly on
the deterministic starting-force domain. The two clocks are independent:

- `curriculum_stage_decisions` controls the H0-H5 profile transitions.
- `starting_force_ramp_decisions` controls the linear 25%-75% armed-H5 share.

This removes the prior coupling between what state the reverse curriculum starts from and how
quickly full matches become defended. No seed, action ABI, observation, reward implementation, or
policy implementation changed for this campaign.

## Fixed Contract

- environment implementation commit: `797b377`
- W&B project: `cnc23`
- launcher: `tools/run_cnc23_defended_curriculum_5mi_sweep.sh`
- default maximum trials: 1,000
- native CUDA workers: three concurrent workers on one GPU
- stop: 5,242,880 transitions
- immutable schedule: 10,485,760 transitions
- vector: 64 agents, one buffer, four threads
- PPO horizon/minibatch: 32/2,048
- policy: native MinGRU, one layer, H64 or H128
- action/observation: ABI9 and observation v5
- objective: H5-only close/medium `balanced_perf`
- native environment metrics: 25; Puffer appends `env/n` for 26 total `env/*` fields
- `sweep_only`: absent
- canonical seed settings: unchanged

The optional positional argument changes only the maximum number of trials. The one-run gate and
the broad campaign therefore exercise the same launcher:

```bash
tools/run_cnc23_defended_curriculum_5mi_sweep.sh 1
tools/run_cnc23_defended_curriculum_5mi_sweep.sh 1000
```

## One-Run Gate

W&B run:

- name: `honest-silence-7`
- id: `ptrci58g`
- URL: <https://wandb.ai/kinvert-k/cnc23/runs/ptrci58g>

Result:

- agent steps: 5,242,880
- final displayed SPS: 36,434
- GPU training: yes
- failures: 0
- start failures: 0
- environment fields: 25, plus Puffer's `env/n`
- resolved H-profile clock: 4,096 decisions per lane
- resolved force-ramp clock: 8,192 decisions per lane
- resolved hidden size: 64
- balanced performance: 0

The gate is valid integration evidence, not a promoted learning result or a speedup claim. It
proves that the full budget completes, the CUDA path runs, W&B receives the intended independent
clock configuration, all starts succeed, and the logging surface remains under the 31-field limit.

## Broad Launch

The full campaign runs in persistent tmux session `cnc23-sweep`:

```bash
tools/run_cnc23_defended_curriculum_5mi_sweep.sh 1000
```

Observed launch state:

- Protein controller command contains `--sweep.max-runs 1000`, `--sweep.workers-per-gpu 3`, and
  `--train.gpus 1`.
- Three training workers registered in W&B project `cnc23`.
- Initial runs are `solar-energy-8` (`jimdysfk`), `exalted-lion-8` (`ctue239c`), and
  `vivid-butterfly-8` (`ohcz67c2`).
- All three workers detected the seven-head ABI9 action space and created four native vector
  workers.
- The canonical seed settings remain unchanged.

Live console log:

```text
PufferLib/logs/cnc_micro/cnc23_defended_curriculum_5mi_sweep_1000.console.log
```
