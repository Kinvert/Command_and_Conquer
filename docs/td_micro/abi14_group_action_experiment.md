# ABI14 Group-Action Experiment

Date: 2026-07-23

Status: native implementation, deterministic validation, and Protein launch gates complete;
CNC24 learning comparison and visible Vanilla transfer pending.

## Purpose

ABI9 can command only one actor per policy decision. ABI14 preserves ABI9's shared command and
argument heads, then adds 64 separate binary selector heads so one attack command can order any
subset of eligible E1/E3 infantry before the next four simulation frames advance.

This is an experimental alternative, not a replacement for ABI9:

```ini
[env]
# 0 = ABI9 single actor, 1 = ABI14 64 binary selectors
action_scheme = 0
```

Protein sweeps `env.action_scheme` categorically over `0, 1`. The technical `env.action_abi`
override defaults to `0` (derive from the scheme), accepts explicit `9`, `13`, or `14` for
compatibility, and is excluded from sweeps.

## Frozen Contract

| Property | ABI9 | ABI14 |
| --- | ---: | ---: |
| Action heads | 7 | 71 |
| Decoder logits | 279 | 407 |
| Action-mask bytes | 279 | 471 |
| Raw-action bytes | 7 | 71 |
| MinGRU H64/L1 parameters | 187,392 | 195,584 |
| Checkpoint bytes | 749,568 | 782,336 |

ABI14 head order is:

```text
command, actor, product, target_kind, x, y, target_slot,
select_00, select_01, ..., select_63
```

The 471-byte mask contains the 279 ABI9 mask entries, 128 selector entries, and a separate
64-entry attack-target mask. The separate target mask prevents the ABI9 union target mask from
making owned refineries legal attack targets.

For non-attack commands all selectors must be zero and ABI9 behavior is unchanged. For attack:

- `actor`, `product`, `target_kind`, `x`, and `y` are forced to canonical values;
- only live, owned E1/E3 observation slots may select `1`;
- all selected actors and the target are validated before any world mutation;
- selected orders are applied in ascending observation-slot order before simulation advancement;
- an empty selected set is an accepted no-effect action; and
- malformed or partly invalid groups are rejected atomically.

The native sampler and PPO scorer include only semantically active variables:

```text
P(command | state)
* P(eligible selectors | attack, state)
* P(target | attack, nonempty selected set, state)
```

Inactive/ineligible selectors and an empty group's target contribute exactly zero log-probability,
entropy, and gradient. This required a dedicated ABI14 CUDA sampler/loss because Puffer's generic
categorical path supports at most 16 action heads.

## PPO Update Semantics

Multiplying up to 66 active sub-action probabilities into one PPO importance ratio makes the
ratio increasingly likely to leave the clipping interval. It can also overflow when old and new
joint log-probabilities separate. This is the compound-action failure described by
[Joint action loss for proximal policy optimization](https://arxiv.org/abs/2301.10919) and is
closely related to the high-dimensional clipping bias studied in
[Dimension-Wise Importance Sampling Weight Clipping](https://proceedings.mlr.press/v97/han19b.html).

ABI14 therefore stores each active head's rollout log-probability and applies PPO clipping to each
active head separately. The summed head loss is centered so its scalar value and local gradient at
ratio 1 match the original joint-action loss. Per-head log-ratios are bounded to `[-10, 10]` before
exponentiation. KL is summed over active heads, while clip fraction is averaged over active heads.
The scalar joint log-probability remains available for rollout accounting and V-trace.

This path is strictly gated on `action_abi == 14`. ABI9 uses PufferLib's existing PPO path and does
not allocate the optional component-log-probability buffers.

## Determinism And Correctness

The focused Zig suite covers shape freezing, selector masks, attack-only targets, sparse group
attacks, empty groups, malformed selectors, and atomic rejection. The repeated 128-decision group
trace has canonical world digest:

```text
294be02cc1bd0b3672df4c42f7f03dc7a7f07d8178d1da9801384e9492eab425
```

The CUDA test matches CPU log-probability, entropy, and every logit gradient, checks finite
differences for an active selector and target, checks exact zero gradients for inactive variables,
and covers neutral, clipped, and extreme finite per-head PPO ratios.

Validation commands:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-abi14-final \
ZIG_LOCAL_CACHE_DIR=/tmp/zig-local-abi14-final zig build test

cd /home/claude/cnc/.worktrees/td-micro-v1
cc -O2 -std=c11 -I PufferLib/ocean/cnc_micro -I td-micro/include \
  PufferLib/ocean/cnc_micro/test_cnc_micro.c \
  td-micro/zig-out/lib/libtd_micro.a -lm -lpthread -o /tmp/test_cnc_micro_abi14
/tmp/test_cnc_micro_abi14

c++ -O2 -std=c++17 PufferLib/ocean/cnc_micro/test_group_action_spec.cpp \
  -o /tmp/test_group_action_spec
/tmp/test_group_action_spec

/usr/local/cuda-12.8/bin/nvcc -O2 -std=c++17 \
  PufferLib/ocean/cnc_micro/test_group_action_cuda.cu \
  -o /tmp/test_group_action_cuda
/tmp/test_group_action_cuda

python3 -m unittest tools/test_cnc_micro_fixed_eval.py
```

All commands pass. Native architecture smokes report zero failures and `start_failures=0` for both
schemes.

## Intrinsic Environment Cost

`td-micro/tools/action_abi_benchmark.c` runs the same no-op actions from the same seeds. Thus both
ABIs execute identical simulation trajectories while retaining their real mask and action buffers:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
zig build -Doptimize=ReleaseFast lib
cc -O3 -std=c11 -I include tools/action_abi_benchmark.c \
  zig-out/lib/libtd_micro.a -lm -lpthread -o /tmp/td_micro_action_abi_benchmark
taskset -c 0 /tmp/td_micro_action_abi_benchmark 9 64 32768
taskset -c 0 /tmp/td_micro_action_abi_benchmark 14 64 32768
```

| ABI | Decisions | Episodes | SPS | Failures |
| --- | ---: | ---: | ---: | ---: |
| 9 | 2,097,152 | 939 | 190,221.810 | 0 |
| 14 | 2,097,152 | 939 | 178,493.925 | 0 |

Both end at:

```text
8814cd2df3976c88bda246c141394402158d81c80b2ba6e75ccc444bf170ecf6
```

ABI14 is 6.2% slower in this adjacent fixed-workload pair. That is the measured intrinsic cost of the
larger mask, action buffer, and bounded selector scan on this machine.

## End-To-End GPU Result

The matched training command was:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
source .venv/bin/activate
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 1 \
  --vec.num-threads 4 \
  --train.total-timesteps 65536 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --env.action-scheme SCHEME \
  --checkpoint-interval 100000000
```

| Scheme | ABI | SPS | Start failures | Valid |
| --- | ---: | ---: | ---: | --- |
| 0 | 9 | 35,734 | 0 | yes |
| 1 | 14 | 20,514 | 0 | yes |

Logs:

- `PufferLib/logs/cnc_micro/1784843696045.json`
- `PufferLib/logs/cnc_micro/1784843793450.json`

This 42.6% end-to-end difference is behavior-dependent. The random ABI14 policy issues multi-unit
attacks, completes substantially shorter episodes, and resets far more frequently than ABI9.
Normalized Puffer timers show:

| Component | ABI9 us/step | ABI14 us/step | Share of added time |
| --- | ---: | ---: | ---: |
| Environment | 19.35 | 33.67 | 69.0% |
| GPU rollout/sampling | 4.58 | 8.65 | 19.6% |
| PPO training | 2.63 | 3.40 | 3.7% |
| Other | 1.43 | 3.03 | 7.7% |
| Total | 27.99 | 48.75 | 100% |

The model is only 4.4% larger. Wider decoder computation and conditional 71-head sampling matter,
but most of this short-run gap comes from changed gameplay workload, not from slowing every game
step. Learning-quality comparisons must use multiple matched seeds and report SPS separately.

## Protein Launch Gate

CUDA-graph creation performs warm-up training passes and restores weights, optimizer state, and
RNG state afterward. The loss-reporting accumulator was not restored or cleared. Interactive
`train` runs accidentally hid this because their step-zero dashboard calls `log()` and clears the
accumulator; silent Protein subprocesses retained warm-up loss values. Protein interpreted the
resulting first-report NaNs as bad trials and early-stopped ABI14 around 55K-78K steps even though
the policy had not diverged.

The regression first reproduced a dirty fresh-trainer metric:

```text
loss/policy = 0.0183855053
loss/old_kl = non-finite
```

After clearing only the reporting accumulator at the end of CUDA-graph warm-up:

- the fresh-trainer regression reports finite zeros;
- the formerly failing `p3gop650` configuration completes 262,144 steps through Protein with
  finite loss/KL, 57,285 SPS, and `start_failures=0`; and
- a 12-trial mixed Protein gate completes all 12 trials: seven ABI9 and five ABI14, with all 11
  optimizer-active trials finite and every trial at `start_failures=0`.

The one trial without loss fields sampled `replay_ratio=0.6682` and legitimately completed without
an optimizer update. Gate tag:

```text
action-scheme-subaction-protein-gate-postfix-12
```

Gate command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
source .venv/bin/activate
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc24 \
  --tag action-scheme-subaction-protein-gate-postfix-12 \
  --eval-episodes 0 \
  --sweep.max-runs 12 \
  --sweep.gpus 1 \
  --sweep.workers-per-gpu 3 \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 1 \
  --vec.num-threads 4 \
  --train.total-timesteps 262144 \
  --train.schedule-timesteps 10485760 \
  --train.horizon 32 \
  --train.minibatch-size 2048
```

This fix changes telemetry initialization only. It does not change policy weights, optimizer
state, actions, observations, rewards, simulation state, or deterministic hashes.

## Remaining Gates

- Run the CNC24 Protein sweep with `env.action_scheme` as a categorical hyperparameter.
- Promote candidates using matched multi-seed ABI9/ABI14 evaluation with unchanged rewards and
  curriculum.
- Compare fixed-suite balanced performance and curve stability, not one sweep endpoint.
- Instrument empty-group frequency before changing its no-effect semantics.
- Implement ABI14 in the visible Vanilla controller and prove action/decision parity before using
  an ABI14 checkpoint for human-visible inference.
