# Balanced-Spawn Stability Sweep: 100 x 1M

Date: 2026-07-15

Status: completed and analyzed

## Purpose

The immutable `lqkwukxi` checkpoint transfers to both close and medium ABI-6 spawns, but three
fresh train-seed-42 runs with the same effective hyperparameters collapse to the same final weights.
This sweep keeps the exact `lqkwukxi` reward vector, observation path, policy architecture, and
vector shape fixed while searching only training-stability controls.

## Fixed Contract

- 1,048,576 timesteps per trial
- 64 agents / 4 buffers / 4 threads
- minibatch 2,048
- `MinGRU`, hidden size 64, one layer, `Normalize255Encoder`
- deterministic 32-close / 32-medium world assignment
- exact `lqkwukxi` reward vector
- one CUDA training GPU
- W&B project `cnc2`, group `balanced-stability-100-20260715`

## Objective

`env/balanced_perf` is the equal-weight mean of close and medium win rates:

```text
balanced_perf = 0.5 * (close_win_rate + medium_win_rate)
```

It replaces the redundant `medium_episode_share` export, preserving PufferLib's 31-field log limit.
Overall `perf`, close/medium win/loss rates, and close episode share remain logged. Final promotion
still requires nonzero performance on both profiles and retained-checkpoint evaluation.

## Search Space

| Parameter | Distribution | Range |
| --- | --- | ---: |
| Horizon | power of two | 32-128 |
| Learning rate | log normal | 0.0001-0.02 |
| Entropy coefficient | log normal | 0.0001-0.02 |
| Maximum gradient norm | uniform | 0.25-2.0 |
| Priority alpha | uniform | 0.0-1.0 |
| Priority beta0 | uniform | 0.0-1.0 |

Rewards, gamma, GAE lambda, replay ratio, clipping, value coefficient, optimizer betas/epsilon,
network dimensions, vectorization, and minibatch size are fixed to the authoritative W&B
`lqkwukxi` values.

## Preflight

The C metric test passed with warnings treated as errors. The rebuilt native/CUDA extension then
completed this default-hyperparameter smoke:

| Metric | Value |
| --- | ---: |
| Timesteps | 262,144 |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| GPU mode | one GPU |
| SPS | 78,171 |
| Start failures / engine failures | 0 / 0 |
| Completed evaluation episodes | 58 |
| Overall win rate | 0.569 |
| Close / medium win rate | 0.323 / 0.852 |
| Balanced performance | 0.587 |

Local smoke record: `PufferLib/logs/cnc_micro/1784176161155.json`.

## Command

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc2 \
  --wandb-group balanced-stability-100-20260715 \
  --tag lqk-fixed-stability-100 \
  --sweep.max-runs 100 --sweep.gpus 1 --train.gpus 1
```

Raw launcher log: `docs/td_micro/benchmarks/cnc2_balanced_stability_sweep_100.log`.

## Results

- 100 trials completed the requested 1,048,576 timesteps.
- 99 trials were valid with zero start failures and zero engine failures.
- Run `a09in73s` reported nonzero engine failures and is excluded.
- 84 valid trials had nonzero final balanced performance.
- 29 reached at least 0.50, 10 reached 0.75, 6 reached 0.90, 4 reached 0.95, and 2 reached 0.99.

Top valid trials:

| Run | Balanced | Close | Medium | LR | Entropy | Horizon | Grad norm | Priority alpha / beta0 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| [`w1swzimb`](https://wandb.ai/kinvert-k/cnc2/runs/w1swzimb) | **1.0000** | **1.0000** | **1.0000** | 0.00866862 | 0.000958278 | 32 | 0.651600 | 0.221002 / 0.985908 |
| [`xg21gx9c`](https://wandb.ai/kinvert-k/cnc2/runs/xg21gx9c) | 0.9960 | 0.9920 | 1.0000 | 0.00740815 | 0.000705695 | 32 | 0.678909 | 0 / 1 |
| [`e1mpnieq`](https://wandb.ai/kinvert-k/cnc2/runs/e1mpnieq) | 0.9838 | 0.9718 | 0.9957 | 0.00771634 | 0.000563531 | 32 | 0.664438 | 0.121594 / 1 |
| [`dwmk35hn`](https://wandb.ai/kinvert-k/cnc2/runs/dwmk35hn) | 0.9778 | 0.9557 | 1.0000 | 0.00722696 | 0.000604410 | 32 | 0.759688 | 0.017139 / 1 |
| [`0xddxm0f`](https://wandb.ai/kinvert-k/cnc2/runs/0xddxm0f) | 0.9420 | 0.9042 | 0.9799 | 0.00746380 | 0.000376553 | 32 | 1.077421 | 0.180012 / 0.902057 |

The winning run is W&B `cosmic-puddle-57`. Its final evaluation completed 505 episodes:

```text
close:  257 wins / 0 losses / 0 draws
medium: 248 wins / 0 losses / 0 draws
overall: 505 wins / 0 losses / 0 draws
```

It used 64 agents, 4 buffers, 4 threads, horizon 32, minibatch 2,048, 1,048,576 timesteps, and one
GPU. Final throughput was 73,263 SPS with `start_failures=0` and engine `failures=0`, so the run is
valid. The learning curve improved rather than collapsing:

| Approximate step | Balanced | Close | Medium |
| ---: | ---: | ---: | ---: |
| 234K | 0.333 | 0.000 | 0.667 |
| 415K | 0.631 | 0.432 | 0.830 |
| 687K | 0.937 | 0.940 | 0.935 |
| 955K | 0.989 | 0.978 | 1.000 |
| 1,048,576 | **1.000** | **1.000** | **1.000** |

The final entropy remained 9.422, compared with 2.882 in the collapsed default run. Production
remained active at 28.57 units per episode, and the policy destroyed all three opponent buildings
per episode while losing no buildings.

## Interpretation

The sweep found a narrow but repeatedly successful stability region:

- horizon 32;
- learning rate around 0.0072-0.0087 instead of 0.015;
- maximum gradient norm around 0.65-0.76 for the top four;
- low priority alpha; and
- priority beta0 near 1.0.

Entropy coefficient remained near the old 0.001 value, so entropy regularization alone was not the
root cause. The old prioritized-replay settings (`alpha=0.8`, `beta0=0.2`), high learning rate, and
larger gradient cap were the important differences. Horizon 32 also dominated: its best/median
balanced scores were 1.000/0.243 across 86 valid trials, versus 0.459/0.105 for horizon 64 and
0.185/0.097 for horizon 128.

## Retained Reproduction And Promotion

Official PufferLib sweep workers did not save checkpoints, so `w1swzimb` was followed by normal
training run [`lwgwyjl7` / `cool-surf-104`](https://wandb.ai/kinvert-k/cnc2/runs/lwgwyjl7).
The reproduction used the exact winning settings and retained checkpoint SHA-256
`46695237efbb6d350971e1163a54c57877a897d487c2b9f7873f3b16dce275e7`.

The valid one-GPU run completed 1,048,576 timesteps at 97,772 SPS with zero start and engine
failures. Its final evaluation reproduced every `w1swzimb` environment outcome:

```text
close:  257 wins / 0 losses / 0 draws
medium: 248 wins / 0 losses / 0 draws
overall: 505 wins / 0 losses / 0 draws
```

Fixed-seed close and medium native traces each replayed byte-identically through a win. The exact
checkpoint then controlled the player side to a real medium-spawn Vanilla win at frame 4,168.
The source/config state is frozen at `1625e88`. Full hashes, commands, metrics, and scope limits are
in `docs/td_micro/lwgwyjl7_balanced_champion.md`.
