# CNC4 Schema-7 Early-Force Sweep

Date: 2026-07-17
Status: sweep complete; winner requires retained reproduction and held-out evaluation
Source snapshot commit: `0ee9239fb043de6ef6900290b2cb41414a46c6f6`
Historical parent: `f3b5a1cce7b6db0241601643f8d9e266051cba92`
Rules manifest SHA-256: `bcb23e390785cb3b500f763752ae354a45972ec864356352ea5614d59f2df389`

## Purpose

Retrain the one-million-step economy curriculum after changing the original AI opening from stock
`AttackDelay=5` to the TD Micro schema-7 `AttackDelay=1` contract. The earlier `cnc3` policies were
trained against an opponent that rarely fielded a useful infantry force before terminal and are not
comparable policy-quality baselines.

## Command

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc4 --wandb-group '' \
  --tag schema7-early-force-sweep-100x1m \
  --sweep.max-runs 100 \
  --sweep.gpus 1 \
  --train.gpus 1 \
  --train.total-timesteps 1048576
```

Fixed training shape: 64 agents, 4 buffers, 4 threads, horizon 32, minibatch 2,048, MinGRU hidden
64x1, and CUDA training. The sweep varied only `reward_refinery`, `reward_first_delivery`, and
`reward_tiberium_income`.

## Validity

- W&B project: [`cnc4`](https://wandb.ai/kinvert-k/cnc4)
- W&B reports 100/100 runs in the `finished` state.
- Local Puffer logs contain 100/100 runs at exactly 1,048,576 agent steps.
- All logged `start_failures` samples are zero.
- All logged engine `failures` samples are zero.
- Total trained transitions: 104,857,600.
- Eighty trials had nonzero final `balanced_perf`.
- Median final `balanced_perf`: 0.063461.
- Mean final `balanced_perf`: 0.088007.

The optimizer evaluated only 67 unique reward vectors. It repeated
`(refinery=0, first_delivery=0, income=0.02)` 27 times and
`(refinery=0, first_delivery=0.4, income=0)` seven times. This is 100 valid training runs, but not
100 unique reward experiments.

## Leading Trials

| Rank | Run | Balanced | Close win | Medium win | Overall win | Buildings destroyed | Enemy attack orders |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`qs7g6tml`](https://wandb.ai/kinvert-k/cnc4/runs/qs7g6tml) | 0.295712 | 0.230769 | 0.360656 | 0.300885 | 1.912 | 19.726 |
| 2 | [`222v0j8t`](https://wandb.ai/kinvert-k/cnc4/runs/222v0j8t) | 0.273810 | 0.214286 | 0.333333 | 0.275862 | 2.621 | 29.414 |
| 3 | [`yfvu3cip`](https://wandb.ai/kinvert-k/cnc4/runs/yfvu3cip) | 0.227246 | 0.148936 | 0.305556 | 0.216867 | 1.602 | 27.807 |
| 4 | [`6vn1go7r`](https://wandb.ai/kinvert-k/cnc4/runs/6vn1go7r) | 0.176604 | 0.113208 | 0.240000 | 0.174757 | 2.078 | 22.728 |
| 5 | [`tnbpdmd7`](https://wandb.ai/kinvert-k/cnc4/runs/tnbpdmd7) | 0.176282 | 0.102564 | 0.250000 | 0.177215 | 1.646 | 24.481 |

The first three independently sampled leaders all set Refinery reward to zero and First Delivery
reward near its 0.4 upper bound:

| Run | Refinery reward | First-delivery reward | Income reward per 100 credits |
| --- | ---: | ---: | ---: |
| `qs7g6tml` | 0 | 0.4 | 0.013985702789891426 |
| `222v0j8t` | 0 | 0.3961814257904424 | 0.013490065031120012 |
| `yfvu3cip` | 0 | 0.38009049323795985 | 0.0048563587840018815 |

This supports a real local optimum: rewarding the first functioning delivery is useful, while a
separate reward merely for constructing a Refinery appears unnecessary or counterproductive.

## Winner Detail

W&B run [`worthy-plant-97 / qs7g6tml`](https://wandb.ai/kinvert-k/cnc4/runs/qs7g6tml) completed
113 episodes in its final metric window:

- 34 wins, 76 losses, and 3 draws, inferred exactly from the reported rates and count;
- 12/52 close-spawn wins and 22/61 medium-spawn wins;
- 17.487 enemy units killed and 46.071 player units lost per completed-window episode;
- 1.912 enemy buildings destroyed and 19.726 enemy attack orders;
- 0.204 first-delivery milestones and 417.0 harvested credits;
- aggregate throughput 67,654 SPS over 15.499 seconds;
- final displayed SPS 65,978;
- zero start and engine failures.

These are final training-window measurements, not a held-out evaluation. The nonzero enemy attack
orders, kills, losses, and destroyed buildings show that the wins are occurring against an active
opponent rather than reproducing the old undefended-base exploit.

## Decision

`qs7g6tml` is the sweep candidate, but it is not yet a promoted model. Sweep trials do not retain
checkpoints. The next gate is an exact standalone one-million-step reproduction using its three
reward values, followed by deterministic native evaluation over a larger episode set and visible
Vanilla inference. Promotion requires the reproduced model to retain close and medium wins while
encountering nonzero enemy infantry and attack orders.
