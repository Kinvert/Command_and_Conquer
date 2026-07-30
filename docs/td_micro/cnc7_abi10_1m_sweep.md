# CNC7 ABI10 One-Million-Step Sweep

Date: 2026-07-18

Status: complete, 100/100 trials reached the full budget

W&B project: [cnc7](https://wandb.ai/kinvert-k/cnc7)

## Purpose

Retune PPO, rollout, network, vectorization, and reward hyperparameters after the intentional ABI10
checkpoint break. Every trial is fixed at 1,048,576 timesteps. This is a screening sweep, not a
policy-promotion run: promising configurations must be reproduced at 2M and then 5M timesteps.

Primary ranking is `balanced_perf`. If terminal wins are too sparse to separate candidates, dense
episode return plus economy and combat metrics may select candidates for longer reproduction, but
they do not replace win rate as the promotion criterion.

## Launch

The sweep uses three concurrent native CUDA trainers on physical GPU 0, no W&B group, and no
`--slowly` path.

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc7 --wandb-group '' \
  --tag abi10-1m-screen-100 \
  --sweep.max-runs 100 \
  --sweep.gpus 1 --sweep.workers-per-gpu 3 \
  --train.gpus 1 --train.total-timesteps 1048576 \
  --vec.total-agents 64 --vec.num-threads 4 \
  --train.minibatch-size 2048
```

Fixed shape: 64 agents, 4 environment threads, minibatch 2,048, CUDA training, and 1,048,576
timesteps. `train.total_timesteps` is excluded from the sweep search space. The inherited search
space includes the PPO optimizer and return parameters, hidden size, layers, horizon, buffers, and
the current reward ranges.

Console log: `PufferLib/logs/cnc_micro/cnc7_abi10_1m_sweep_100.console.log`.

Detached session: `cnc7-abi10-1m`.

## First Batch

The first three trials completed exactly 1,048,576 steps and the scheduler launched replacements.
All reported `invalid_actions=0`, `start_failures=0`, and engine `failures=0`.

| Run | Role | SPS | Balanced perf |
| --- | --- | ---: | ---: |
| `klp6t1x1` | default bootstrap | 18,613 | 0.101742 |
| `9fgpabc5` | default bootstrap repeat | 19,183 | 0.101742 |
| `2rcckur1` | first sampled proposal | 20,988 | 0.000000 |

The duplicate bootstrap result is an early deterministic launch check. SPS is lower than a
single-trainer benchmark because three trainers share one GPU and sampled model/vector shapes vary.

## Completion

- Completed trials: 100/100 at exactly 1,048,576 timesteps.
- Total transitions: 104,857,600.
- Final balanced-performance maximum: 0.396091.
- Mean: 0.027947; median: 0; 90th percentile: 0.099531.
- Nonzero final score: 32/100; at least 0.2: 4/100; at least 0.3: 2/100.
- `start_failures`: zero in every trial.
- `invalid_actions`: zero in every trial.
- Engine failures: zero in 98 trials. Runs `iop6vizk` and `sxxqvs3k` reported nonzero engine
  failures and are invalid for throughput or promotion claims; both scored zero.
- Aggregate SPS median: 19,072 across varied model/vector shapes sharing one GPU.

## Leading Trials

| Run | Balanced | Close win | Medium win | Overall win | Final-window W/L/D |
| --- | ---: | ---: | ---: | ---: | ---: |
| `6y3jrp5w` | **0.396091** | 0.328767 | 0.463415 | 0.400000 | 62/92/1 |
| `0gor2tys` | 0.331015 | 0.275362 | 0.386667 | 0.333333 | 48/95/1 |
| `fzxwruru` | 0.287650 | 0.040816 | 0.534483 | 0.308411 | 33/74/0 |
| `j22shswz` | 0.245218 | 0.013514 | 0.476923 | 0.308824 | spawn-imbalanced |

`6y3jrp5w` is both the raw winner and the best two-spawn result. Its 62 wins include 24/73 close
and 38/82 medium episodes. It reached those wins with zero invalid/start/engine failures. Its
logged balanced curve was `0, 0, 0, 0.231019, 0.396091`, so useful learning occurred late in the
1M budget rather than being present at initialization.

## Comparison With Earlier Setups

| Campaign or fixed run | Budget and search | Balanced result |
| --- | --- | ---: |
| Historical ABI8 default | 1M, one fixed run | about 0.296 |
| ABI9 compact default | 1M, one fixed run | 0.155449 |
| ABI10 default duplicate | 1M, two exact repeats | 0.101742 |
| CNC4 ABI8 winner | 100 x 1M, three reward dimensions | 0.295712 |
| **CNC7 ABI10 winner** | **100 x 1M, full search** | **0.396091** |
| CNC6 ABI9 raw winner | 1,000 x 2M, full search | 0.418841 |
| CNC6 ABI9 robust winner | 1,000 x 2M, full search | 0.397582 |

The typical CNC7 proposal is worse than CNC4: CNC7 median/mean are 0/0.027947 versus CNC4's
0.063461/0.088007, and its nonzero hit rate is 32/100 versus 80/100. CNC4 held known-good
PPO/network settings fixed and swept only three rewards, while CNC7 searched the full
28-dimensional space after a checkpoint break, so that population comparison is confounded.
However, the matched-default comparison below confirms that the weakness is not only wider search.

Computational throughput is worse under ABI10. The fixed same-shape ABI9 CUDA baseline was 66,319
SPS, while valid ABI10 2M repeats are about 30,945 SPS. This is the known 15,027-output conditional
decoder cost.

More importantly, ABI10's bootstrap defaults are exactly the former strong ABI9 `qj7bux1j`
environment, reward, network, vector, PPO, and seed configuration. ABI9 reached 0.251 balanced
performance by about 0.81M steps and 0.422 at 2M. ABI10's exact 1M duplicates reached only 0.102,
and both exact 2M repeats ended at zero. ABI10 entropy fell from roughly 3.1 to 1.2 by 1M and to
0.27 by 2M. This is a real sample-efficiency and collapse regression in the current decoder.

The full matched analysis is in `abi9_vs_abi10_learning_assessment.md`.

## Decision

Do not claim that the current ABI10 decoder is a healthy replacement based on its best-of-100
score. Preserve ABI10's conditional grammar and exact legality contract rather than reverting to
ABI9's 44.943% rejected-action path, but treat the 15,027-output decoder as an unsuccessful first
performance/learning implementation.

Reproduce `6y3jrp5w` and `0gor2tys` at 2M as a bounded sanity check. In parallel, replace the dense
prefix-row decoder with a compact shared conditional decoder under the same action, mask,
observation, reward, terminal, and simulator contracts. Do not spend another large broad sweep on
the current decoder before that adjacent A/B.

## Acceptance

- Exactly 100 completed trials at 1,048,576 timesteps each.
- Zero `start_failures` and engine failures in every retained trial.
- Sampled `invalid_actions` remains zero under ABI10.
- Record balanced performance, episode return, W/L/D, economy/combat behavior, and SPS.
- Select a small candidate set for exact-hyperparameter 2M reproductions.

## Source Record

Branch `td-micro-v1`, commit `cd456b1`.

```text
cnc_micro.ini      071026939b26562f8e31c8aa1f35b4ec48da69502164013ac866b021d449200b
sweep.py           ae19b2ba07c6337b9b82484a5f4444db40fea1a2b296a7a8ad924d1a6d61c0d4
pufferl.py         5abcacbd8639937486904ebb34c689a760728eb86bdabbd2bd156a5eec0ea578
Puffer extension   2aeb448e90ca61603763c0d22a233fa953cbd3eee1c511c62ee69a92eda691f0
Zig static core    48d53fa53525a1a0e0b008983da927391c00f56c3c3a1b18b67f280c18d452a5
TD Micro API       fe2d270a797552bc2621eae88b369c2b30a0115f1e7fca7280d51f3d73dcaa29
```
