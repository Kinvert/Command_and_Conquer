# Reward Sweep: 10 x 1M Steps

Date: 2026-07-15

Status: completed and synced to [W&B project `cnc1`](https://wandb.ai/kinvert-k/cnc1).

## Fixed Training Shape

- 10 runs, 1,048,576 timesteps each
- 64 agents / 4 buffers / 4 threads
- horizon 32 / minibatch 2,048
- hidden size 64 / one hidden layer
- CUDA training with `--train.gpus 1`
- full 12,000-decision timeout
- only the five configured reward coefficients varied

Command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export EXTRA_LIBS="$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib:/usr/lib/wsl/lib"
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc1 --wandb-group reward-sweep-10 \
  --tag reward-sweep-10x1m \
  --sweep.max-runs 10 --sweep.gpus 1 --train.gpus 1 \
  --env.max-decisions 12000 \
  --vec.total-agents 64 --vec.num-buffers 4 --vec.num-threads 4 \
  --train.total-timesteps 1048576 --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

## Results

`W/L/D` is the final reporting window, not a deterministic evaluation set.

| # | W&B | Milestone | Infantry | Enemy unit | Enemy building | Own loss | Score | W/L/D | SPS |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`28a1mnns`](https://wandb.ai/kinvert-k/cnc1/runs/28a1mnns) | 0.1000 | 0.0100 | 0.1000 | 0.5000 | -0.0010 | -0.915 | 0/65/6 | 51,482 |
| 2 | [`64xujvdo`](https://wandb.ai/kinvert-k/cnc1/runs/64xujvdo) | 0.1000 | 0.0100 | 0.1000 | 0.5000 | -0.0010 | -0.915 | 0/65/6 | 53,717 |
| 3 | [`hbvj2y5r`](https://wandb.ai/kinvert-k/cnc1/runs/hbvj2y5r) | 0.1820 | 0.0393 | 0.1661 | 0.9783 | -0.0097 | -0.991 | 0/109/1 | 81,319 |
| 4 | [`bzojokr5`](https://wandb.ai/kinvert-k/cnc1/runs/bzojokr5) | 0.0590 | 0.0123 | 0.0711 | 0.0885 | -0.0013 | -0.819 | **6/83/5** | 73,938 |
| 5 | [`vllns5dm`](https://wandb.ai/kinvert-k/cnc1/runs/vllns5dm) | 0.0355 | 0.0281 | 0.1164 | 0.6208 | -0.0041 | -0.947 | 0/89/5 | 47,985 |
| 6 | [`s5de39j5`](https://wandb.ai/kinvert-k/cnc1/runs/s5de39j5) | 0.1110 | 0.0238 | 0.0214 | 0.4460 | -0.0069 | **-0.192** | **1/11/40** | 33,199 |
| 7 | [`z7m2gv91`](https://wandb.ai/kinvert-k/cnc1/runs/z7m2gv91) | 0.1342 | 0.0353 | 0.0853 | 0.3256 | -0.0050 | -0.960 | 0/97/4 | 71,213 |
| 8 | [`v6up7dtd`](https://wandb.ai/kinvert-k/cnc1/runs/v6up7dtd) | 0.0068 | 0.0130 | 0.1776 | 0.7484 | -0.0035 | -0.969 | 0/94/3 | 76,483 |
| 9 | [`di2p2sj1`](https://wandb.ai/kinvert-k/cnc1/runs/di2p2sj1) | 0.0861 | 0.0475 | 0.0349 | 0.2182 | -0.0006 | -0.270 | 0/20/54 | 21,983 |
| 10 | [`r2mnrrwn`](https://wandb.ai/kinvert-k/cnc1/runs/r2mnrrwn) | 0.1603 | 0.0010 | 0.1272 | 0.8559 | -0.0078 | -1.000 | 0/160/0 | 82,734 |

Every run had `start_failures=0` and engine `failures=0`, so all ten are valid.

## Interpretation

Run 4 recorded six real simulator terminal wins in its final 94-episode reporting window. Run 6
recorded one win and forty draws in 52 episodes, giving it the best sweep score. These are genuine
stochastic training-rollout outcomes, but they do not yet prove a stable winning policy: one million
steps is short, and exploratory actions remain active during collection.

The follow-up in `docs/td_micro/win_legitimacy_audit.md` reproduced run 4's final metrics exactly,
captured nine wins from the same configuration, and replayed every winning action trace twice.

This sweep disabled practical checkpoint retention, so its corresponding checkpoints cannot be
replayed greedily. A checkpointed run 4 reproduction found no greedy seed-1 win at any retained
snapshot, confirming that real rollout wins do not yet imply a stable winning policy.

SPS varied from 21,983 to 82,734 because policy behavior changes simulation cost. Long matches and
draw-heavy runs advance far more combat/pathfinding state than policies that lose quickly.
