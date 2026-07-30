# CNC6 ABI-9 Two-Million-Step Sweep

Date: 2026-07-18

Status: complete, 1,000/1,000 trials finished

W&B project: [cnc6](https://wandb.ai/kinvert-k/cnc6)

## Purpose

Retune the compact ABI-9 observation policy on the current early-force, close/medium TD Micro
curriculum. This campaign fixes every trial at 2,097,152 timesteps and searches 28 rollout,
optimizer, policy, vectorization, and reward dimensions.

## Launch

The sweep ran in detached tmux session `cnc6-abi9-2m`. It has no W&B group and used three concurrent
CUDA trainers on physical GPU 0.

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc6 --wandb-group '' \
  --tag abi9-2m-sweep-1000 \
  --sweep.max-runs 1000 \
  --sweep.gpus 1 --sweep.workers-per-gpu 3 \
  --train.gpus 1 --train.total-timesteps 2097152 \
  --vec.total-agents 64 --vec.num-threads 4 \
  --train.minibatch-size 2048
```

Fixed shape: 64 agents, 4 threads, minibatch 2,048, CUDA training. Swept shape: horizon 32-128,
buffers 1-8, hidden size 32-1,024, and 1-8 MinGRU layers. `train.total_timesteps` is explicitly
excluded from the sweep search space. Sweep trials do not retain checkpoints; reproduce the best
configuration after completion to retain and evaluate its model.

Console log:
`PufferLib/logs/cnc_micro/cnc6_abi9_2m_sweep_1000.console.log`.

## Completion

- Finished trials: 1,000/1,000; all reached exactly 2,097,152 training steps.
- Total training steps: 2,097,152,000.
- Wall time: 8h 46m 11s, from 01:32:22 to 10:18:33 PDT.
- Whole-campaign effective training throughput: about 66,427 SPS. This includes orchestration and
  evaluation wall time and is not a controlled single-trial simulator benchmark.
- Start failures: zero in every trial.
- Final balanced-performance maximum: 0.418841; median: 0.009573.

See [the completed sweep analysis](cnc6_abi9_2m_sweep_analysis.md) for candidate rankings,
uncertainty, behavior, throughput validity, and the recommended reproduction sequence.

## Launch Gates

- Zig test suite: pass.
- Sweep worker-slot tests: 6/6 pass.
- Fixed-timestep exclusion test: pass.
- Rebuilt Puffer extension: `compiled_env=cnc_micro`.
- 262,144-step CUDA smoke: valid, zero start/engine failures, about 88K final displayed SPS.
- Largest allowed 1,024x8 model smoke: valid, 28.0M parameters, about 2.0/8 GB reported VRAM.
- Post-launch GPU sample: three CUDA worker processes, 95% utilization, 3.37/8.15 GB VRAM.

## First Batch

All three initial trials completed 2,097,152 steps and were replaced by the next three workers.

| Run | Configuration | SPS | Balanced perf | Start failures | Engine failures |
| --- | --- | ---: | ---: | ---: | ---: |
| `p9fx0zle` | default bootstrap | 47,565 | 0.005495 | 0 | 0 |
| `ihui2kg5` | default bootstrap repeat | 47,325 | 0.005495 | 0 | 0 |
| `33l86c9l` | first sampled proposal | 50,433 | 0.004587 | 0 | 0 |

The duplicate bootstrap trials produced the same final gameplay metrics, providing a useful launch
determinism check. Their displayed SPS differs slightly because three trainers share the GPU.

## Source Record

Branch `td-micro-v1`, base commit `83dea42d017aab29d88f38d321ea44def8d68b45`. The launch includes
the documented uncommitted scheduler/config and visible-inference work present in the research
worktree; unrelated historical capture files are outside this worktree.

```text
cnc_micro.ini      cf29814d176cf4df2852c13111b6c60c14dcce06fa6456bdace4bd026193edf0
sweep.py           ae19b2ba07c6337b9b82484a5f4444db40fea1a2b296a7a8ad924d1a6d61c0d4
pufferl.py         5abcacbd8639937486904ebb34c689a760728eb86bdabbd2bd156a5eec0ea578
Puffer extension   a845fbd30c0a83dd2afcdbe890ef950a1c4c5302ed84d8fc541970fe26052010
Zig static core    b31fe149c3a31d064cbfc5bd5817e7da3b81b494bce5de4e7410643c8078b09b
TD Micro API       37cde4b26b45bb909f8e0b70dfa1e08c2197e351442199e312c69c7e87a0781d
```
