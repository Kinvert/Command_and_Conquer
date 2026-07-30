# TD Micro Refinery, Harvester, And Tiberium Economy

Recorded: 2026-07-16

Status: implemented and accepted for ABI 7, with an ABI-8 reward-config split. The retained ABI-6
champion remains unchanged; this work establishes the economy simulation, Vanilla transfer contract,
and valid training path, not a new policy-quality champion.

## Scope

The supported TD Micro ruleset now includes:

- building and placing a GDI Refinery;
- the source-faithful bundled Harvester and Refinery-only build-time accounting;
- Harvester move, harvest, and return-cargo policy commands;
- vehicle pathfinding and TD track-based turns;
- Tiberium search, exact overlay-step depletion, and depleted-cell buildability;
- Refinery approach, backup, unload, and exit tracks;
- player and multiplayer-Easy-AI income rates;
- stored Tiberium, storage capacity, and production spending from stored Tiberium;
- Easy AI Power/Refinery/Barracks opening selection; and
- matching Zig, C ABI, PufferLib, Vanilla policy, and Vanilla oracle surfaces.

No Weapons Factory, producible combat vehicle, normal/hard AI, new map, or far-spawn work is part of
this change.

## Rules Contract

| Item | Value |
| --- | ---: |
| Refinery cost | 2,000 |
| Refinery effective build-time cost | 600 |
| Refinery strength | 900 |
| Refinery power/drain | +10 / 40 |
| Refinery storage | 1,000 |
| Harvester bundled value | 1,400 |
| Harvester strength | 600 |
| Harvester maximum speed | 12 |
| Full cargo | 28 Tiberium steps |
| Harvest interval | 15 TD frames |
| Player unload value | 25 credits/step |
| Easy-AI unload value | 33 credits/step |

The authored manifest is schema 6. It remains ruleset id `td_micro_v1`; compatibility is enforced by
the manifest hash and ABI rather than by silently accepting an older checkpoint.

## ABI And Policy Surface

ABI 8 retains observation version 4 and the 6,208-byte observation transport. The ABI bump changes
`TdMicroRewardConfig` only; action, observation, and checkpoint tensor dimensions are unchanged.

```text
action heads: 12, 65, 6, 4, 64, 64, 64
action mask:  279 bytes
commands:     +harvest, +return_cargo
products:     +refinery
```

Globals now expose player stored Tiberium, capacity, cumulative harvested credits, opponent stored
Tiberium/capacity, and total remaining map Tiberium. Map bytes change Tiberium land to clear,
buildable land after depletion. Harvester entity records expose cargo fraction, mission status,
movement/harvesting flags, and harvest timer.

The Puffer log surface stays at 31 environment fields. It adds Refinery count, Harvester count,
Tiberium income, and the Refinery/Harvester/first-delivery milestones while removing lower-value
train-action and already-redundant milestone fields. `units_built` now includes Harvesters.

Reward configuration exposes `reward_refinery=0.4`, `reward_first_delivery=0.2`, and
`reward_tiberium_income=0.01` per 100 delivered credits, capped at the first 5,000 credits per
episode. The automatic bundled Harvester remains a logged milestone but has no separate reward,
preventing a hidden double reward for the same Refinery completion.

## Oracle And Determinism

`tools/record_td_micro_fixtures.sh` launches every fixture twice in fresh Vanilla processes and
byte-compares the outputs before installation. The final recorder pass completed without a
difference.

| Fixture | Decisions / frame | SHA-256 |
| --- | --- | --- |
| Easy-AI economy opening | 1,100 / 4,400 | `9c6f250da6075b421fac0e9e39b72dff75334f3f002e1487879024862c26bdd8` |
| Scripted player Refinery harvest | 1,100 / 4,400 | `e09a5f4b27038889380e5962d5ae84e3d40653a0c374749f10d7037c9c1eb9bb` |
| Easy-AI opening | 160 / 640 | `d8128959be3c6101838df956c9a533df9a43870ba34fd457a6690498c518bb28` |
| Player E1/E3 opening | 258 / 1,032 | `502dd81c7978a4e2cbd2bafb7a2c8c4cf82c4473614a6ea5d5450162c32e955b` |

Focused Zig tests compare exact Vanilla frame, RNG, economy, Tiberium-map, unit mission, destination,
track, cargo, docking, queue, and AI state. The final suite has 118 tests and passes in Debug,
ReleaseSafe, and ReleaseFast.

Final artifact hashes:

```text
rules/td_micro_v1.json    1dc2ff0a28076c0cf2e1fb3c85ac35ea0704c794cee1f89703a56b950c90b6ae
generated/td_micro_v1.zig 07395a64afb84bab2413ee2b7df91e1899cd3c34d827126a7a0595c00e9d824e
generated/td_micro_v1.h   473b5b88c1d77290313912e8e578e1b0f880bf5b3e6c6f5ff6493215f7d28536
```

## Capacity Failure Audit

The first 1M diagnostic was rejected because some episodes reached the 128-entry lifetime infantry
pool. The active policy limit was only 64 and Easy AI held at most 10 active infantry; the failure
came from completed death animations never releasing append-only entries.

The accepted implementation compacts inactive infantry at RL decision boundaries after death and
kill metrics are recorded. Active relative order is preserved, infantry/projectile references are
remapped, and death-ledger bits move with their entities. Destroyed Harvester slots above the two
reserved MCV slots are likewise reclaimed after unit-loss accounting. Regression tests cover both
paths. Hard simultaneous-capacity exhaustion remains an engine failure.

## Scripted End-To-End Rollout

`td-micro/tools/economy_c_api_smoke.c` drives the public batch ABI through MCV deployment, Power
Plant construction/placement, Refinery construction/placement, bundled Harvester automation, first
delivery, and timeout.

```text
decisions=900 refinery=1 harvester=1 income=675 first_delivery=1 invalid=0 failures=0
```

The generic ABI smoke also passes:

```text
abi=8 obs=6208 mask=279 worlds=2 decisions=2
digest=7b12c606e590f9f35de2a353b38af28953a10217f5f7853995ad691d1622eb92
```

The standalone Puffer binding smoke reports:

```text
episode_return=0.250 draw_rate=1
```

## GPU Training Acceptance

Command, from `PufferLib/`:

```bash
OMP_NUM_THREADS=4 \
LD_LIBRARY_PATH=/usr/lib/wsl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib \
PYTHONUNBUFFERED=1 \
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
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

Result:

| Field | Value |
| --- | ---: |
| Puffer run | `1784219726695` |
| Total agent steps | 1,048,576 |
| Uptime | 22.881 s |
| Aggregate SPS | 45,827 |
| Final sampled SPS | 42,450 |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| GPU mode | `--train.gpus 1` |
| `start_failures` | `[0, 0, 0, 0, 0]` |
| Engine `failures` | `[0, 0, 0, 0, 0]` |
| Valid | yes |

The final windows contain nonzero Refinery, Harvester, Tiberium-income, and first-delivery metrics.
The run JSON is `PufferLib/logs/cnc_micro/1784219726695.json`, SHA-256
`94d8ad84a021504048de77eac3c1d52f008905ac487da7ed584d1c0a7585befa`.

This workload is below the long-term 50,000-SPS target and is not a speedup claim. It is
behavior-dependent and sustains substantially more infantry/economy activity than the old
finite-budget task. The current goal required a valid end-to-end economy smoke; profiling and
structured-observation work remain the next throughput levers.

## Verification Commands

```bash
cd td-micro
zig build --cache-dir /tmp/tdmicro-zig-cache-final-debug \
  --global-cache-dir /tmp/tdmicro-zig-global-final-debug test
zig build --cache-dir /tmp/tdmicro-zig-cache-final-rs \
  --global-cache-dir /tmp/tdmicro-zig-global-final-rs -Doptimize=ReleaseSafe test
zig build --cache-dir /tmp/tdmicro-zig-cache-final-rf \
  --global-cache-dir /tmp/tdmicro-zig-global-final-rf -Doptimize=ReleaseFast test
zig build --cache-dir /tmp/tdmicro-zig-cache-final-lib \
  --global-cache-dir /tmp/tdmicro-zig-global-final-lib -Doptimize=ReleaseFast lib

cd ../Vanilla-Conquer
cmake --build build-remastertd --target TiberianDawn -j 10
cmake --build build-td --target VanillaTD -j 10
ctest --test-dir build-td --output-on-failure

cd ..
bash tools/record_td_micro_fixtures.sh
```

The Vanilla builds pass and `ctest` reports 14/14 tests passed. The native/CUDA Puffer extension
also rebuilds successfully with `./build.sh cnc_micro`.

## Remaining Limits

- Only scenario 1 and the declared close/medium starts are supported.
- Tiberium is fully modeled internally, but the policy map byte exposes presence rather than exact
  per-cell overlay amount; exact levels remain in the oracle/digest state.
- The 64-slot per-owner entity observation/action surface can still truncate a legal state with
  many buildings plus infantry.
- Easy AI economy behavior is covered; normal/hard AI and policy-quality retraining are not.
- No new economy checkpoint has been promoted. The ABI-6 champion and its evidence remain untouched.
