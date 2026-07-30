# Reward Sweep: 100 x 1M Steps

Date: 2026-07-15

Status: completed, analyzed, and exactly reproduced.

## Verdict

The sweep found a strong stochastic TD Micro policy. Official sweep run
[`a1y38c6z`](https://wandb.ai/kinvert-k/cnc1/runs/a1y38c6z) finished its consolidated evaluation
window with **452 wins, 9 losses, and 1 draw in 462 episodes (97.84% wins)**. A normal checkpointed
training run, [`lqkwukxi`](https://wandb.ai/kinvert-k/cnc1/runs/lqkwukxi) (`autumn-tree-125`),
reproduced all final environment metrics exactly.

The retained checkpoint then won **768 of 770 episodes (99.74%)** under three fresh categorical
policy-sampling seeds. A captured win replayed twice with the same trajectory hash and legitimately
destroyed all three enemy structures. This is solid evidence for a winning policy in the reduced
Zig TD Micro environment. It is not yet evidence that the policy wins in full Vanilla TD.

## Fixed Sweep Shape

- 100 runs at 1,048,576 timesteps each
- 64 agents / 4 buffers / 4 threads
- horizon 32 / minibatch 2,048
- hidden size 64 / one hidden layer
- CUDA training with `--train.gpus 1`
- full 12,000-decision timeout
- only five reward coefficients varied

Command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export EXTRA_LIBS="$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib:/usr/lib/wsl/lib"
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc1 --wandb-group reward-sweep-100-20260715 \
  --tag reward-sweep-100x1m \
  --sweep.max-runs 100 --sweep.gpus 1 --train.gpus 1 \
  --env.max-decisions 12000 \
  --vec.total-agents 64 --vec.num-buffers 4 --vec.num-threads 4 \
  --train.total-timesteps 1048576 --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

## Sweep Population

- 100 runs completed the requested timestep budget.
- 88 runs were valid with zero `start_failures` and zero engine `failures`.
- 12 runs had engine failures and are excluded from performance claims.
- 46 runs had at least one win in the final reporting window.
- Among valid runs, median final `perf` was 0; the 90th percentile was 0.242, the 95th percentile
  was 0.607, and the maximum was 0.978.
- Valid-run thresholds: 36 reached at least 1% wins, 15 reached 10%, 9 reached 25%, 6 reached 50%,
  2 reached 75%, and 1 reached 90%.

The invalid run IDs were `sxrtyomx`, `5y3tvklx`, `fmttq9dm`, `4pooohq3`, `3uuruzp7`, `6bzs2zqr`,
`dgq6cj0l`, `uwyvkysr`, `1dai3rtq`, `2ft9ubt6`, `lamncbq7`, and `4mqhgora`.

## Winning Reward Vector

| Reward | Value |
| --- | ---: |
| First-time milestone | 0.2 |
| Player infantry built | 0.03030131620399178 |
| Enemy unit destroyed | 0.0054265722298487366 |
| Enemy building destroyed | 0.7301079315055825 |
| Player unit lost | 0.0 |

Final `a1y38c6z` environment metrics:

| Metric | Result |
| --- | ---: |
| Win/loss/draw | **452 / 9 / 1** |
| Win rate | **97.8355%** |
| Completed episodes | 462 |
| Mean decisions | 1,177.93 |
| Mean units built | 24.2446 |
| Mean E1 / E3 built | 23.5411 / 0.7035 |
| Mean unit kills / losses | 3.1277 / 2.9459 |
| Mean buildings destroyed / lost | 2.9610 / 0.2489 |
| Engine failures / start failures | 0 / 0 |
| Reported SPS | 105,762 |

SPS is valid for this run, but it is behavior-dependent: policies ending episodes quickly execute a
different simulation workload than policies that draw or fight long matches.

## Exact Checkpointed Reproduction

Run `lqkwukxi` used code commit `9616b9323fc2942cb9e03b6cadfcbe381d398e12`, the exact reward
vector above, the fixed sweep shape, and checkpoint interval 512. Its final evaluation again produced
**452/9/1 over 462 episodes**, with every reported environment metric equal to `a1y38c6z`.

Retained checkpoint:

```text
PufferLib/checkpoints/cnc_micro/lqkwukxi/0000000001048576.bin
SHA-256: 7c8734032f8a214c1108c8793f2013af2dc223acccdd87da13456fc65ec56a72
```

The trace-enabled reproduction reported 59,796 SPS. Tracing records every sampled seven-head action,
so that number is not a clean throughput baseline.

## Fresh Sampling Seeds

The retained checkpoint was evaluated with environment seed 1 and fresh Puffer categorical-action
sampling seeds. Each evaluation targeted at least 256 completed episodes; vector completion caused
seed 75 to finish with 258.

| Policy seed | Episodes | Win/loss/draw | Win rate | Mean decisions | Mean invalid actions | Failures |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 74 | 256 | 255 / 1 / 0 | 99.6094% | 1,095.00 | 361.28 | 0 |
| 75 | 258 | 257 / 1 / 0 | 99.6124% | 1,086.02 | 366.35 | 0 |
| 76 | 256 | 256 / 0 / 0 | 100.0000% | 1,059.32 | 344.98 | 0 |
| **Total** | **770** | **768 / 2 / 0** | **99.7403%** | | | **0** |

This rules out the original 97.84% result being one lucky policy RNG sequence.

## Deterministic Win Replay

One captured winning trace contained 2,106 actions and replayed twice with:

```text
terminal reward=+1
wins/losses/draws=1/0/0
E1/E3 built=32/1
unit kills/losses=6/11
buildings lost/destroyed=0/3
enemy attack orders=9
failures=0
trajectory hash=c6bfdff0a99314e7
```

The trace proves that the terminal was caused by combat and destruction of the enemy's three
pertinent structures, not a timeout, startup failure, empty opponent, or shaped reward.

## Visible Vanilla Transfer

The checkpoint is a strong **stochastic** policy. Independent argmax still loses after 6,073
decisions by selecting 5,882 invalid placements, but the visible adapter now uses seeded categorical
sampling instead. A corrected Vanilla replay against the original Easy GDI AI ended in a real win at
frame 3,402 after 851 policy decisions, with `opponent_defeated=1` and zero failures.

That replay also exposed and fixed an auto-skirmish bug that had skipped the AI ghost's entire house
tick. Full details are in `docs/td_micro/lqkwukxi_visible_vanilla_validation.md`. One Vanilla win is a
valid end-to-end transfer result, but broad Zig-to-Vanilla outcome-rate parity still requires a
multi-seed replay harness.
