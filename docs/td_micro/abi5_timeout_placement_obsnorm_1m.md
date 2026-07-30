# TD Micro ABI 5 Timeout, Placement, And Observation Smoke

Date: 2026-07-14

Status: implemented and verified. The conditional action protocol remains intentionally deferred.

## Changes

- Raised the episode cap from 12,000 to 48,000 TD frames, or from 3,000 to 12,000 policy decisions.
- Added one shared placement predicate for player and Easy AI structure placement. It checks the
  Vanilla `Occupy_List(true)`-style foundation plus bib, map bounds, terrain, static blockers, live
  object occupancy, and adjacency to a friendly building.
- Made map observation occupancy use those same exact structure footprints.
- Kept the compact observation ABI and Puffer transport as a 6,208-element `ByteTensor`. The native
  CUDA rollout fuses byte-to-training-precision conversion with `1/255` scaling. Zig checkpoint
  inference performs the same scaling, and the PyTorch fallback uses `Normalize255Encoder`.
- Bumped the policy ABI to 5 and observation version to 3. Older checkpoints have the same physical
  shape but different input semantics and are not valid initialization checkpoints for ABI 5.
- Fixed a reachable long-combat producer-destruction failure found while auditing the first smoke.
  When the last Construction Yard or Barracks is destroyed, its production is now abandoned and
  spent cost is refunded, as Vanilla does in `BuildingClass::Detach_All` and
  `FactoryClass::Abandon`.

## Placement Evidence

The shared predicate accepts the recorded Vanilla power-plant placement `(4,7)` and rejects the
distant `(14,32)` placement. Tests also reject out-of-map footprints, infantry occupancy,
enemy-only proximity, and a terrain-blocked bib cell. An illegal placement leaves the completed
queue intact.

The current independent `target_x` and `target_y` masks remain broad. They cannot encode an exact
set of legal coordinate pairs; that requires the deferred conditional action protocol.

## Observation Transport Audit

The first normalization implementation expanded every 6,208-byte observation into 6,208 CPU
floats before Puffer copied it to the GPU. For 64 agents, that changed observation transport from
397,312 bytes to 1,589,248 bytes per vector step and added a CPU conversion loop. That design was
unnecessary because Puffer's native CUDA backend already transfers byte observations and casts
them into rollout precision on the GPU.

The CPU-float implementation is rejected. The current implementation keeps the compact byte ABI
through the env boundary and adds an optional env scale to Puffer's existing CUDA cast. A focused
CUDA test checks `{0, 1, 127, 255}` against `{0, 1/255, 127/255, 1}`.

The uniform scale is a stabilization bridge, not a final observation representation. It fixes the
measured recurrent-gate saturation caused by feeding raw 0-255 bytes into the dense encoder, but the
schema mixes incompatible meanings and ranges:

- boolean fields such as presence, defeat, queue state, and operational state become `1/255`;
- categorical type, mission, product, target-kind, and category fields remain ordinal scalars;
- coordinates and counts occupy roughly `[0, 0.25]`, while health and progress occupy `[0, 1]`;
- each packed map byte combines land type, passability, buildability, visibility, and occupancy, so
  one dense input coefficient cannot independently weight those semantic channels.

The next serious observation ABI should retain compact byte transport but decode field-aware
features on the GPU: separate map planes, normalized continuous values, explicit booleans, and
one-hot or embedded categorical entity/global fields. That change needs its own parity tests,
checkpoint ABI bump, and controlled learning benchmark. It should not be conflated with the current
transport correction.

## GPU Command

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export PYTHONUNBUFFERED=1
export OMP_NUM_THREADS=4
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc1 \
  --tag abi5-byteobs-gpu-normalize-1m \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 4 \
  --vec.num-threads 4 \
  --train.total-timesteps 1048576 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 100000000 \
  --eval-episodes 1
```

## GPU Result

| Field | Result |
| --- | ---: |
| W&B run | `7woxruky` (`exalted-mountain-11`) |
| Timesteps | 1,048,576 |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| Hidden network | 64 x 1 |
| GPU mode | `--train.gpus 1` |
| Uptime | 18.1929 s |
| Aggregate SPS | 57,636 |
| Final dashboard SPS | 51,153 |
| `start_failures` | 0.000 in every log window |
| Engine `failures` | 0.000 in every log window |
| Maximum logged win rate | 0.0286 |
| Maximum logged draw rate | 0.0857 |
| Valid throughput run | yes |

The run exercised real combat rather than only build logic. Logged windows contain player and
opponent infantry production, attack orders, unit kills and losses, building losses, real win/loss
outcomes, and 48,000-frame timeout draws. The final window averaged 45.0 E1 and 6.0 E3 releases,
22.5 player kill credits, 22.83 opponent unit losses, 0.5 opponent buildings lost, and 16.33 enemy
attack orders per reported episode sample.

This is the clean number for the current full workload. It must not be compared causally with old
economy-heavy runs without holding the action/state trajectory fixed: simulation cost changes as a
policy creates units, pathfinding, and combat.

Artifacts:

- W&B: `https://wandb.ai/kinvert-k/cnc1/runs/7woxruky`
- local config/metrics record: `PufferLib/logs/cnc_micro/7woxruky.json`
- record SHA-256: `146827f479b371291fbcee12a24b69922c4e5311e3e2a0d8da9dd2f339cc7411`
- final checkpoint: `PufferLib/checkpoints/cnc_micro/7woxruky/0000000001048576.bin`
- checkpoint SHA-256: `49bc0fafc8ebf9826c7b04150c4a9ae7b7261f56d491c7d5c73438c261d851da`

## CPU-Float Versus GPU-Byte A/B

All training hyperparameters, seed, timeout, and implementation state were held fixed. Only the
observation transport and normalization location changed.

| Path | Run | Aggregate SPS | Final SPS | Start/engine failures | Final checkpoint SHA-256 |
| --- | --- | ---: | ---: | ---: | --- |
| CPU expands bytes to normalized `FloatTensor` (rejected) | `4075qjkl` | 59,254 | 56,081 | 0 / 0 | `49bc0faf...d851da` |
| `ByteTensor`, fused GPU cast and scale (current) | `7woxruky` | 57,636 | 51,153 | 0 / 0 | `49bc0faf...d851da` |

The current path was 2.7% slower in this pair, which is not a meaningful optimization signal at
this run length. The byte-for-byte identical final checkpoint proves that both paths supplied the
same normalized training inputs and update sequence. The audit fixes a bad data path and cuts host
transport by 4x, but it does **not** explain the roughly 2x gap from some historical runs.

A second diagnostic restored only the old 3,000-decision cap while retaining byte transport and all
training hyperparameters. Run `tfj9yzch` completed at 51,998 aggregate SPS, 25,697 final SPS, with
zero start or engine failures. Its final reporting window averaged 70.6 E1 releases and ended through
the infantry-limit terminal, so shortening the cap did not recreate the old economy-only workload.
This rejects timeout length as a sufficient explanation. Isolating the remaining gap requires a
fixed action/state trajectory benchmark rather than comparing independently learning policies.

## Failure Found And Fixed

The first ABI 5 smoke, W&B run `ypc8o51n`, reached 67,644 aggregate SPS and had
`start_failures=0`, but engine-failure windows were nonzero (`0.3333`, `0.0462`, and `0.1167`). A
code audit found a reachable producer-destruction case that shorter episodes rarely reached: a
completed infantry queue could survive the destruction of its last Barracks and fail on the next
release attempt.

A failing regression was added first. The implementation now abandons the queue when the final
producer is destroyed and refunds the amount already spent. The repeated run `4075qjkl` had zero
engine failures in every window. The aggregate logger did not retain failure subtypes, so this is a
source-audit and regression-backed diagnosis, not proof that every failure in `ypc8o51n` had that
single cause. The first diagnostic is not a valid clean SPS claim.

## Determinism

The canonical two-world C ABI smoke produced the same digest twice and retained the established
ABI 5 baseline:

```text
721b67018cbc2096602e52c74b6312443cb3b82fc8b2bb8b24e3721b0448eb52
```

Two independent seed-1 greedy replays of the final checkpoint produced byte-identical 39,507,402-byte
observation/action-mask traces:

```text
7e88329d1fb6ba124913370e0a5b504e9f6ab1bc2fc40a95e5ffdd73ab5adb9a
```

Both replays lost legitimately at decision 6,094 with zero engine failures. Each recorded reward
sum `-0.80`, two positive milestones, two player buildings lost, seven enemy attack orders, and the
same command sequence.

## Deferred Action Issue

The deterministic replay made 5,883 invalid actions in 6,094 decisions. The dominant pattern is a
legal `place` command and individually legal coordinate-head values that form an illegal `(x,y)`
pair. More generally, command, actor, product, coordinates, target kind, and target slot are sampled
independently even though their legality is conditional on each other.

No action ABI change was made in this work. Before the next long quality run, review a conditional
action protocol that can guarantee complete legal commands and define both protocol-token SPS and
semantic-game-decision SPS.

## Verification

```text
Zig tests:              94/94 Debug, ReleaseSafe, and ReleaseFast
Masked-action fuzz:     16 trajectories x 12,000 decisions, no engine failures
Vanilla CTest:          14/14
Puffer C smoke:         raw-byte observation and reward/log assertions passed
CUDA byte-scale test:   exact 0, 1/255, 127/255, and 1 outputs
PyTorch fallback:       Normalize255Encoder smoke passed
Puffer native/CUDA:     rebuilt successfully
Vanilla/Zig fixture:    exact byte parity through the 258-decision economy trace
GPU smoke:              1,048,576 steps; start_failures=0; failures=0
Deterministic replay:   byte-identical traces and matching C ABI digest
```
