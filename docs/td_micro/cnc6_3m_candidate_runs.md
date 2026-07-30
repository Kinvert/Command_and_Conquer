# CNC6 Three-Million-Step Candidate Runs

Date: 2026-07-18

## Correct Training Path

Use the TD Micro worktree and the `cnc_micro` environment. Do not launch the unrelated root
`/home/claude/cnc/PufferLib/config/cnc_build.ini`; that is the older full-TD environment and is not
the CNC6 ABI-9 training target.

Put the complete fixed candidate configuration in:

```text
/home/claude/cnc/.worktrees/td-micro-v1/PufferLib/config/cnc_micro.ini
```

Then use the normal PufferLib CUDA command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc6 --tag <unique-tag>
```

W&B needs its local socket and network access, so run this command outside the restricted Codex
sandbox. A valid result must use CUDA and report both `start_failures=0` and `failures=0`.

Shared 3M shape: 64 agents, one buffer, four environment threads, horizon 32, minibatch 2,048,
MinGRU with `Normalize255Encoder`, training seed 42, environment seed 1, and base seed 73. The
requested 3,000,000 budget finishes at 2,998,272 agent steps because updates are rollout-aligned.

## Results

| Candidate | Source 2M run | 3M run | Balanced | Close | Medium | Perf | SPS | Valid |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `u6` | `u6ul1umm` / replay `xft8oqj9` | [`a2jtyybi`](https://wandb.ai/kinvert-k/cnc6/runs/a2jtyybi) | 0.075381 | 0.051471 | 0.099291 | 0.075812 | 29,268 | yes |
| exact `8fc` | `8fcw2lp9` / replay `05t9n1ci` | [`str0e5r4`](https://wandb.ai/kinvert-k/cnc6/runs/str0e5r4) | 0.108344 | 0.029940 | 0.186747 | 0.108108 | 33,276 | yes |
| `8fc` milestone `0.2` | `qj7bux1j` | [`ls487b0h`](https://wandb.ai/kinvert-k/cnc6/runs/ls487b0h) | 0.065476 | 0.000000 | 0.130952 | 0.064706 | 51,545 | yes |
| `gta` | `gtaoyvpn` | [`i003u1xx`](https://wandb.ai/kinvert-k/cnc6/runs/i003u1xx) | 0.139606 | 0.188889 | 0.090323 | 0.143284 | 35,158 | yes |
| `gta`, 2/3 learning rate | derived from `gtaoyvpn` | [`zwx5u05q`](https://wandb.ai/kinvert-k/cnc6/runs/zwx5u05q) | 0.047397 | 0.035971 | 0.058824 | 0.047945 | 39,679 | yes |
| exact `8fc`, 2/3 learning rate | derived from `05t9n1ci` | [`1m174x56`](https://wandb.ai/kinvert-k/cnc6/runs/1m174x56) | 0.037731 | 0.040000 | 0.035461 | 0.037801 | 32,299 | yes |

The `u6` scalar values were copied exactly from its retained 2M replay and only the budget changed.
It regressed from 0.418841 balanced at 2M to 0.075381 at 3M. Because `anneal_lr=1`, increasing
`total_timesteps` changes the learning-rate schedule throughout training; a 3M run is not an exact
continuation of the original 2M optimization trajectory.

Exact `8fc` also regressed, from 0.397582 balanced at 2M to 0.108344 at 3M. It completed 2,998,272
aligned training steps with 64 agents, one buffer, four threads, horizon 32, minibatch 2,048,
CUDA enabled, `start_failures=0`, and `failures=0`. Its training checkpoint is
`PufferLib/checkpoints/cnc_micro/str0e5r4/0000000002998272.bin`.

The milestone-`0.2` variant regressed from 0.421753 balanced at 2M to 0.065476 at 3M, with zero
close-spawn wins in 172 close evaluations. It was valid with `start_failures=0` and `failures=0`.
Its training checkpoint is
`PufferLib/checkpoints/cnc_micro/ls487b0h/0000000002998272.bin`.

The independent `gta` family regressed from 0.379108 balanced at 2M to 0.139606 at 3M after
showing stronger windows during training. It was valid with `start_failures=0` and `failures=0`.
Its training checkpoint is
`PufferLib/checkpoints/cnc_micro/i003u1xx/0000000002998272.bin`.

All three exact 2M candidates regressed when only the budget changed. With cosine learning-rate
annealing to zero, changing the budget from 2M to 3M raises cumulative optimizer exposure by 50%.
The next controlled test scales the initial learning rate by `2/3`, preserving approximately the
same integrated learning-rate area over the longer schedule while retaining all other candidate
values.

That scaling did not rescue `gta`: its 3M balanced result fell further from 0.139606 to 0.047397.
It was valid with `start_failures=0` and `failures=0`. Its training checkpoint is
`PufferLib/checkpoints/cnc_micro/zwx5u05q/0000000002998272.bin`.

The same scaling did not rescue exact `8fc`: its 3M balanced result was 0.037731. It was valid with
`start_failures=0` and `failures=0`. Its training checkpoint is
`PufferLib/checkpoints/cnc_micro/1m174x56/0000000002998272.bin`.

At this point six valid 3M runs across three source families and two learning-rate schedules all
underperformed their 2M parents. Do not spend more runs blindly extending 2M sweep winners. First
evaluate retained intermediate checkpoints and add best-checkpoint selection or a schedule with an
explicit anneal horizon; final-only evaluation hides policies that improve and later collapse.

## Intermediate Checkpoint Audit

The `gta` run briefly displayed `balanced_perf=0.75` near 1.94M steps, then collapsed. That point
was a rolling metric from only a few recently completed episodes, not a full deterministic
evaluation. To test whether the run had actually learned a useful policy before collapsing, its
retained 2,099,200-step checkpoint was loaded with `learning_rate=0` and evaluated for a complete
3M-step run:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc6 \
  --tag cnc6-gta-checkpoint-2099200-frozen-eval \
  --load-model-path checkpoints/cnc_micro/i003u1xx/0000000002099200.bin \
  --train.total-timesteps 3000000 --train.learning-rate 0
```

Run [`uh1rrjig`](https://wandb.ai/kinvert-k/cnc6/runs/uh1rrjig) evaluated 439 episodes and returned
`balanced_perf=0`, `close_win_rate=0`, `medium_win_rate=0`, and `perf=0`, with
`start_failures=0` and `failures=0`. The apparent 0.75 result was therefore sampling noise, not a
hidden good checkpoint.

An earlier 2,048-step probe (`0yffebg6`) produced no evaluation metrics because that budget creates
one training epoch and zero evaluation epochs. Do not use short probes of this shape to score
checkpoints.

## Decision

Keep 2,097,152 steps as the known-good default horizon. The next 3M attempt should be either a
3M-specific hyperparameter sweep or a code change that decouples the learning-rate anneal horizon
from `total_timesteps` and evaluates checkpoints over a fixed, adequately sized episode set. Do not
promote a model from transient W&B rolling metrics.

## Candidate Sources

Exact source configurations are retained locally in each run's `files/config.yaml`:

```text
PufferLib/wandb/run-20260718_123007-05t9n1ci/files/config.yaml
PufferLib/wandb/run-20260718_115643-qj7bux1j/files/config.yaml
PufferLib/wandb/run-20260718_101640-gtaoyvpn/files/config.yaml
```

Copy every environment reward, vector setting, policy setting, and train setting from the source.
Change only `train.total_timesteps` to `3_000_000`. Do not mix blocks between candidates; CNC6
testing showed that reward and optimizer blocks are co-adapted and mixed configurations collapse.
