# ABI10 Placement-Mask Hotspot

Date: 2026-07-18

Status: fixed and validated. No reward, simulation rule, PPO hyperparameter, action grammar, or
decision-timing value changed.

## Symptom

The first 2,097,152-step ABI10 run used the normal native CUDA path:

- 64 agents, 1 buffer, 4 threads;
- horizon 32, minibatch 2,048;
- hidden size 64, one layer;
- one GPU; and
- no `--slowly`.

It initially ran normally, then fell to about 728 SPS near 434K steps. Environment evaluation was
98-99% of wall time and the projected remaining time rose to roughly 38 minutes. The run was
stopped. Its zero `start_failures`, engine failures, and invalid actions showed that this was a
valid but pathological environment state, not a failed-start artifact or bad training argument.

## Root Cause

ABI10 exports exact prefix masks. When a structure queue completed, the first implementation tested
all 4,096 map origins with the full scalar placement oracle on every decision. A policy that left a
completed building unplaced therefore converted every subsequent observation into thousands of
footprint, occupancy, Tiberium, and base-proximity checks.

The focused benchmark in `td-micro/tools/placement_mask_benchmark.c` constructs exactly that state,
then verifies that `place` remains enabled for every world before and after the timed loop. An
adjacent same-machine comparison measured:

| Implementation | Normal SPS | Ready-queue SPS | Ready/normal |
| --- | ---: | ---: | ---: |
| Original scalar scan | 175,380 | 1,015 | 0.58% |
| Final row-bitset mask, run 1 | 173,031 | 161,651 | 93.42% |
| Final row-bitset mask, run 2 | 174,441 | 163,882 | 93.95% |

The pathological state improved by about 161x in the adjacent A/B. An earlier original measurement
was 927.565 SPS, which independently exposed the same collapse.

## TDD Gate

The failing test `fast legal-origin rows match the scalar placement oracle` was added before the
new API. It compares every one of the 4,096 map origins for Power Plant, Barracks, and Refinery
against `placement.isLegal`. The fixture includes live Tiberium, dynamic infantry occupancy, a
Harvester body cell, its reserved head cell, and friendly-building proximity.

The final implementation:

1. starts from compile-time rows for permanently blocked terrain;
2. ORs live Tiberium and dynamic occupancy into 64-bit blocked rows;
3. builds 64-bit friendly-base proximity rows;
4. aligns one row per footprint offset with shifts; and
5. intersects clear origins with origins touching the friendly base.

There is no 64x64 origin loop in the ready-queue path. Both the exact `x` mask and the conditional
`y | x` mask are populated by iterating the resulting set bits.

## Commands

Focused mask benchmark:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
cc -O3 -std=c11 -I include tools/placement_mask_benchmark.c \
  zig-out/lib/libtd_micro.a -lm -lpthread \
  -o /tmp/td_micro_placement_mask_benchmark
/tmp/td_micro_placement_mask_benchmark
```

Final full CUDA repeat:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 \
LD_LIBRARY_PATH=/usr/lib/wsl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 1 \
  --vec.num-threads 4 \
  --train.total-timesteps 2097152 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

## Final Results

- All 160 Zig tests pass in Debug, ReleaseSafe, and ReleaseFast.
- The C ABI, scripted economy, Puffer binding, and shared host/device action-spec smokes pass.
- Native full-decision benchmark: 171,089.615 and 168,957.191 SPS, mean 170,023.403.
- Native digest in both runs: `38cca1613d27fcaa4500c25261cff6ea19d838ccd80d9c91fec4d045d718ce28`.
- Final 131,072-step CUDA smoke: 29,612 SPS, with all three failure counters at zero.
- Final 2,097,152-step CUDA repeat: 30,905 SPS in 55 seconds of training uptime, with
  `start_failures=0`, `failures=0`, and `invalid_actions=0`.
- The semantically identical W&B run reached 30,984 SPS:
  [`cnc6/ieuq9hu7`](https://wandb.ai/kinvert-k/cnc6/runs/ieuq9hu7).

The two complete 2M runs produced identical checkpoints:

```text
initial checkpoint  7dc37341b08d5213c29e5bdc5ee83c88ff397ceb9499d73bbd4ee7139913203f
final checkpoint    ffc1b1d453fd757e2a1745f1f15de3028497de6d49cd21c1db1c5ff12eaba2bf
```

This fixes the catastrophic state-dependent slowdown. It does not by itself solve ABI10's larger
15,027-output decoder cost: full training remains around 31K SPS, below the 50K target.
