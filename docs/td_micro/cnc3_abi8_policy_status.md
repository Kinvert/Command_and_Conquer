# `cnc3` ABI-8 Policy Status

Date: 2026-07-16

Status: strong native candidate; policy-state parity gate closed; broad real-engine evaluation
still required

## Parity Update

The map, RNG, startup-order, facing, economy, movement, combat, and terminal mismatches described
below were resolved by the 2026-07-16 parity change. Fresh close-seed-1 and medium-seed-2
`VanillaTD` processes now produce byte-exact policy observations and masks matching Zig for all
declared early decisions, and the longer scripted oracle traces are exact and deterministic.

See `docs/td_micro/zig_vanilla_policy_parity.md` for hashes, tests, benchmark commands, and scope.
The historical single-seed policy outcomes in this document predate those fixes and must not be
treated as the current transfer result. Broad held-out Vanilla evaluation remains the next gate.

## Verdict

The ABI-8 economy sweep produced a policy that is good enough to inspect and run in Vanilla now.
Its retained reproduction wins about 95% of fresh native close/medium episodes, has zero startup or
engine failures, and completes a deterministic real Vanilla win from the medium spawn.

It is not yet a certified replacement for the ABI-6 champion:

- the learned strategy is primarily a starting-cash infantry rush, not a harvesting strategy;
- only one policy sampling seed per profile has been evaluated in real Vanilla; and
- its broad real-engine win rate and terminal agreement have not been measured after the parity
  fixes.

The next priority is therefore broad Vanilla evaluation, not another reward sweep.

## Scope

This result covers only `td_micro_v1`: scenario 1, GDI versus original-AI GDI, close and medium
spawns, MCV, Construction Yard, Power Plant, Refinery, bundled Harvester, Barracks, E1, and E3.
There is no Weapons Factory, producible combat vehicle, defense, additional map, or full tech tree.

The Vanilla launcher reports requested difficulty `Hard`, which stock multiplayer maps to the
computer's internal `DIFF_EASY` handicap. This is the strongest stock computer handicap, but the
tiny restricted matchup still permits an early base rush. It is not evidence that the project has
solved unrestricted hard-difficulty Tiberian Dawn.

## Sweep Result

The interrupted official sweep left **83 completed trials** on disk. Every trial reached exactly
1,048,576 timesteps with `start_failures=0` and engine `failures=0`. The winner remained
W&B [`cnc3/0bp4eeqr`](https://wandb.ai/kinvert-k/cnc3/runs/0bp4eeqr):

| Metric | Result |
| --- | ---: |
| Balanced close/medium performance | **0.944485** |
| Overall win rate | **0.946309** |
| Close win rate | **0.974684** |
| Medium win rate | **0.914286** |
| Completed evaluation episodes | 298 |
| Final displayed SPS | 70,988 |
| Refinery reward | 0.0 |
| First-delivery reward | 0.1785755657 |
| Income reward per 100 credits | 0.0097200221 |

The second-best trial reached balanced performance `0.817176`, so the winner was not a marginal
ranking result.

Sweep launcher:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc3 --wandb-group '' \
  --tag abi8-economy-reward-sweep-100x1m \
  --sweep.max-runs 100 \
  --sweep.gpus 1 \
  --train.gpus 1 \
  --train.total-timesteps 1048576
```

## Retained Reproduction

The winning reward vector was trained again from scratch through the normal PufferLib CUDA path.
W&B run [`cnc3/lqn5ogu8`](https://wandb.ai/kinvert-k/cnc3/runs/lqn5ogu8) reproduced the winner's
final behavior metrics exactly.

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc3 --wandb-group '' \
  --tag 0bp4eeqr-retained-reproduction \
  --train.gpus 1 \
  --train.total-timesteps 1048576 \
  --env.reward-refinery 0 \
  --env.reward-first-delivery 0.17857556565722282 \
  --env.reward-tiberium-income 0.009720022135411273
```

| Item | Value |
| --- | --- |
| Source/config commit | `627c5d57f69092fb7dca50a7b4fdec9f63711afe` |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| Policy | MinGRU, hidden 64, one layer |
| GPU mode | `--train.gpus 1` |
| Final displayed SPS | 46,135 |
| Start / engine failures | 0 / 0 |
| Checkpoint | `PufferLib/checkpoints/cnc_micro/lqn5ogu8/0000000001048576.bin` |
| Checkpoint bytes | 1,710,080 |
| Checkpoint SHA-256 | `d1d283876cb05113eefe9436add60d52677a1905c9ab00b25ea770ef52664a05` |

The sweep and reproduction have identical policy-quality metrics but different wall-clock SPS.
This workload is behavior- and machine-load-sensitive; the pair is not evidence of a simulator
speed change.

## Native Inference

A fresh categorical evaluation used environment seed 1 for close, seed 2 for medium, and sampling
seeds 1000 through 1255:

| Profile | Wins | Losses | Draws | Win rate | Mean decisions | Mean invalid actions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Close | 244 | 11 | 1 | 95.3125% | 1,802.50 | 807.22 |
| Medium | 241 | 15 | 0 | 94.1406% | 1,775.54 | 759.51 |
| Combined | **485** | **26** | **1** | **94.7266%** | 1,789.02 | 783.37 |

All 512 episodes had zero engine failures. Repeated sample-seed 74 traces were byte-identical within
each profile:

| Profile | Native result | Decisions | Trace SHA-256 | Log SHA-256 |
| --- | --- | ---: | --- | --- |
| Close | win | 1,518 | `574eec7caa66e8b595006e22554bc65fe888838a0577625a15fea59bf2638cf6` | `29450145dc0af6ca95015169618fd3278f7442126e65df0d2468e9a619b6afb8` |
| Medium | loss | 4,878 | `9be932863ff73660d9566e71320a403de4e96a96e9ec53e2c2f64ba4cd8e1539` | `51e2eedd1609aedaa4064f637c450dc40ce73cf58d3fe31ced05bec4989b5497` |

## Real Vanilla Inference

The exact retained checkpoint loaded in a fresh isolated Vanilla executable with the original AI,
unlimited simulation speed, dummy rendering, and categorical sampling seed 74.

```bash
SDL_VIDEODRIVER=dummy ALSOFT_DRIVERS=null timeout 180s ./vanillatd -XQ
```

| Profile | Vanilla result | Frame | Decisions | Accepted | Changed | Failed |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Close, seed 1 | loss | 12,881 | 3,221 | 1,555 | 71 | 0 |
| Medium, seed 2 | **win** | 4,151 | 1,038 | 632 | 57 | 0 |

The medium run was repeated twice. Its policy logs and packed-state traces were byte-identical:

```text
policy log:  618c042f96f5d854cb01d3605e6a78efe67ccc694c60b06e3b4f1f365d8579f4
state trace: 964824fefc0e7fd6a37a56bf69c66bea4597c65ab360507566a9062e45f7258f
```

This is enough for a visible inference demonstration now. It is not enough to estimate a Vanilla
win rate because Vanilla currently uses one hard-coded policy sampling seed.

## Historical Transfer-Parity Finding (Resolved)

The following was the pre-fix diagnosis that led to the parity work. It is retained as engineering
history; it no longer describes the current simulator.

The native and Vanilla traces use the same 6,487-byte observation-plus-mask record. At decision 0,
every byte matches except one map byte:

| Observation field | Zig | Vanilla |
| --- | ---: | ---: |
| Map cell `(40,48)`, packed offset 3,176 | `0x38` clear/buildable | `0x2d` Tiberium |

The source map fixture has Tiberium overlay 6 with `OverlayData=0` at this cell. Vanilla retains the
Tiberium overlay and land type until `Reduce_Tiberium` removes it. Zig currently treats zero steps
as already depleted and exposes clear/buildable terrain. The simulator needs a Tiberium-presence
bit distinct from harvestable step count.

After ignoring that byte, the next mismatch is decision 1, enemy entity facing at packed offset
5,191: Zig reports 246 and the real executable reports 236. This indicates an executable-loop
timing difference from the existing shared-library oracle path. Both mismatches must be covered by
an initial-observation and early-frame differential test.

## What The Policy Learned

The final evaluation averages:

```text
42.95 units built
39.55 E1
3.32 E3
18.16 unit kills
7.10 buildings destroyed
0.084 refineries
0.050 first deliveries
37.58 harvested credits
```

The policy can win from the initial 10,000 credits and usually ignores the Refinery. Reward search
alone cannot make economy mandatory when the reset permits a cheaper winning strategy.

## Upcoming Goals

The authoritative task boundaries, dependencies, and acceptance gates now live in
`docs/td_micro/TODO.md`. The summary below is retained for context.

1. **Build broad Vanilla evaluation.** Make the policy sampling seed configurable, run at least 200
   headless Vanilla episodes, and report per-profile win rate, terminal agreement, failures, and
   first divergence against Zig.
2. **Replace independent action heads.** A conditional legal-command protocol should remove the
   roughly 775 invalid tuples per episode before the action space expands.
3. **Make economy structurally necessary.** Use starting resources and/or a farther or pre-armed
   deterministic profile so a win requires at least one delivery. Keep terminal win/loss primary;
   do not rely on larger shaping rewards to hide an optional economy.
4. **Add controlled start diversity.** Randomize authored starting-credit buckets and introduce a
   long spawn through a deterministic close/medium/long curriculum. Preserve close starts so
   rushing remains valid when geometry favors it.
5. **Certify the restricted game.** Restore at least 50,000 valid training SPS on the
   economy-required workload, pass deterministic parity, and meet the 200-match Vanilla transfer
   gate.
6. **Expand content in small parity-checked versions.** Add Weapons Factory plus Humvee, then Medium
   Tank, then defenses/repair/sell. Retrain and repeat Vanilla transfer after every expansion.
7. **Expand maps and difficulty.** Add broader spawn sets and held-out stock maps, then certify
   user-facing Easy, Normal, and Hard against the original AI.

The long-term target is unrestricted skirmish play: all intended buildings and units enabled,
multiple factions if included in the declared scope, all supported stock skirmish maps and starts,
and a policy that reliably beats the original hard AI in real Vanilla. That is a multi-stage
program; the current result is a strong restricted vertical slice, not the endpoint.
