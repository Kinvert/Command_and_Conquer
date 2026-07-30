# ABI-8 Broad Policy-Path Parity Corrections

Date: 2026-07-16

Status: `TASK-2A` partial; the decision-6 and decision-76 mismatch classes are fixed, but the broad
acceptance gate is not met

## Scope

This candidate ports additional Vanilla Tiberian Dawn frame ordering, mission, production,
movement, and animation behavior into TD Micro. It changes no Vanilla source, policy checkpoint,
rules, rewards, starts, action ABI, or training hyperparameters.

The real `VanillaTD` executable remains the oracle. The retained ABI-8 policy is evaluated with the
same checkpoint, setup profile, and categorical sampling seed in Zig and Vanilla.

## Provenance

| Item | Value |
| --- | --- |
| Checkpoint commit | `eb27ca8d23dd75e17f588c63647ca7325ed8b06e` |
| Checkpoint | `PufferLib/checkpoints/cnc_micro/lqn5ogu8/0000000001048576.bin` |
| Checkpoint SHA-256 | `d1d283876cb05113eefe9436add60d52677a1905c9ab00b25ea770ef52664a05` |
| Rules SHA-256 | `1dc2ff0a28076c0cf2e1fb3c85ac35ea0704c794cee1f89703a56b950c90b6ae` |
| Tracked source/test patch SHA-256 | `0e0b384b550dd0676c33628890fda2a3e1caefa77fccda822d2eace7c323a310` |
| New Vanilla fixture SHA-256 | `26859f88a8ee19bbb746d080e02ece0c21ff397a47c7bd058b6b2243ff2672d0` |

The patch SHA is `git diff -- td-micro/src td-micro/tests | sha256sum` before this report was
authored. The new untracked fixture is identified separately because Git does not include it in a
working-tree diff.

## Corrections

The implementation was developed by adding a failing differential or focused regression test for
each exposed mismatch, then porting the corresponding Vanilla behavior into Zig.

Production and frame ordering:

- MCV deployment rotation skips one player tick when an earlier opponent-MCV deletion compacts
  Vanilla's unit list.
- Player and opponent construction progress now use Vanilla's canonical policy-visible timeline.
- Human production advances once per placed producer; the Easy AI retains its single production
  stream.
- Completed infantry exits the last available operational Barracks, matching Vanilla's producer
  selection without the unsupported primary-building override.
- A completed infantry unit waits while its Barracks radio tether is occupied, and releases the
  tether on first cell entry.

Movement and mission state:

- Infantry now carries Vanilla's 15-frame path retry delay in simulation state and deterministic
  digests.
- Command interruption advances an active movement segment by one tick before stopping its driver.
- The stop-driver path, current-segment completion, ordinary arrival, and queued ATTACK precedence
  match the source behavior.
- MOVE clears the current combat target immediately; repeated ATTACK clears navigation and path
  state without restarting the active ATTACK mission timer.
- ATTACK and production egress honor current segment, queued mission, and unload ordering.

Animation, economy, and policy encoding:

- Newly spawned player E1 infantry in GUARD waits for an uninterruptible salute/gesture before
  commencing queued MOVE. Easy-AI infantry already in GUARD_AREA may continue driving during that
  animation, matching the distinct Vanilla path.
- Harvester countdown starts at assignment-frame `interval - 1`.
- Structure policy occupancy uses the placement footprint and bib; construction progress follows
  the 60-frame Vanilla interval.
- `.place` accepts only a cell target.

## Focused Determinism

The final focused seed-1017 close trace moved its first mismatch from decision 175 to decision 316,
and both engines won. The medium trace remains divergent at decision 179 and still ends Zig win,
Vanilla loss.

An independent focused run and the broad run produced the same result tuple, state-trace hash,
action-trace hash, and first-divergence record for both seed-1017 profiles. Representative state
trace hashes are:

| Profile | Zig state trace | Vanilla state trace |
| --- | --- | --- |
| Close | `337f9728c707a57f520ba33aef3b245314f42da96fb465ba7111000b5596018d` | `bf3a897c49260957b25de4f6a7708b77957e7f310613c2de09446bd18c29b9cb` |
| Medium | `ab1eac4ce30740833670e4777bbb1f290ed53671106de86845a9a01b671a1df4` | `afba4a2b9f48116a3cc255a73400b1a201433c73d0f8682ab339b0d3cc190fcb` |

The native benchmark also repeated one identical current world digest:
`40d2b1f231900149e01f4a7c6af0189122609f59b32c65d95dccdac715537e02`.
The exact checkpoint source repeated its own digest:
`918b90598f784ff5c45a51d28ee21e509c6369d9d5178b8bfa81fc8e23ff4180`.
The hashes differ across versions because the corrections intentionally change simulation state;
repeat stability within each version is the determinism check.

## Broad Transfer Gate

Command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1
python3 tools/td_micro_transfer_eval.py \
  --checkpoint PufferLib/checkpoints/cnc_micro/lqn5ogu8/0000000001048576.bin \
  --native-evaluator /tmp/td_micro_policy_c_api_smoke \
  --output /tmp/td-micro-transfer-repro-fixed19-100x2 \
  --work-root /tmp/td-micro-transfer-repro-fixed19-100x2-work \
  --samples-per-profile 100 \
  --sample-seed-start 1000 \
  --jobs 10 \
  --timeout-seconds 180
```

All 200 episodes were valid. Infrastructure, native-engine, and Vanilla-engine failures were zero.
Vanilla results are exactly unchanged from the baseline, confirming that this candidate changes
only Zig behavior.

| Profile | Engine | Baseline W/L/D | Candidate W/L/D | Baseline win rate | Candidate win rate |
| --- | --- | ---: | ---: | ---: | ---: |
| Close | Zig | 78/22/0 | 86/14/0 | 78% | 86% |
| Close | Vanilla | 25/75/0 | 25/75/0 | 25% | 25% |
| Medium | Zig | 100/0/0 | 89/11/0 | 100% | 89% |
| Medium | Vanilla | 59/41/0 | 59/41/0 | 59% | 59% |
| Overall | Zig | 178/22/0 | 175/25/0 | 89% | 87.5% |
| Overall | Vanilla | 84/116/0 | 84/116/0 | 42% | 42% |

| Parity metric | Baseline | Candidate |
| --- | ---: | ---: |
| Terminal agreement | 98/200 | 83/200 |
| Exact state traces | 0/200 | 0/200 |
| Exact action traces | not recorded | 0/200 |
| Close first divergence | min 6, median 76, max 76 | min 180, median 268, max 643 |
| Medium first divergence | min 6, median 76, max 76 | min 179, median 230.5, max 434 |

The intended early-state correction worked: the universal decision-6 MCV-facing and decision-76
construction-progress mismatches no longer occur. The next first mismatches are distributed among
player-infantry facing, mission, position, flags, and map occupancy from decision 179 onward.

### Current Root-Cause Assessment

This is deterministic cross-engine disagreement, not nondeterminism inside either engine. Repeated
Zig runs match each other, and repeated fresh Vanilla processes match each other.

The earliest retained mismatch is medium profile/sample seed 1017 at decision 179, frame 716. Own
entity slot 3 is encoded with mission byte 3 in Zig and 2 in Vanilla. Because mission bytes are the
engine mission plus one, Zig still has that first player infantry on `MISSION_MOVE` while Vanilla
has commenced `MISSION_ATTACK`. Another sample reaches the same mismatch at decision 180. The
first sampled policy action then diverges later, at decision 193 or 196, after the differing state
has changed policy logits.

Across the 200 broad traces, mission and facing are the dominant first-difference families. Flags,
position/map occupancy, health, fear/progress, Tiberium state, and object counts appear less often.
The evidence supports this investigation order:

1. Barracks infantry egress, radio tether release, and unload/salute animation interruption.
2. The frame ordering for active movement interruption and queued ATTACK commencement.
3. Infantry subcell reservation, scatter order, and dynamic list insertion/compaction order.
4. Combat/projectile and harvesting timing for the remaining health and Tiberium mismatch families.

Shared RNG call-order drift can magnify any first mismatch into different facing, animation, target,
and combat choices, but it is unlikely to explain the earliest deterministic MOVE-versus-ATTACK
transition. The next focused differential should record every game frame around 680-730 for sample
seed 1017, including incoming action, mission/queue, NavCom/TarCom, coordinate/head coordinate,
driving/path state, animation, tether, and mission timers. Port one demonstrated Vanilla transition
at a time and retain it as a focused fixture before rerunning the 200-tuple gate.

This is not outcome parity. Terminal agreement regressed from 49% to 41.5%, and Zig still overstates
the balanced Vanilla win rate by 45.5 percentage points. `TASK-2A` therefore remains open.

Raw evidence:

- `docs/td_micro/results/abi8_parity_corrections_100x2/episodes.jsonl`
  (`5dfbc0d97bbc29fa14bead81dd74b0fad65235c0ab7d2c098cd54f0d5e99c7f0`)
- `docs/td_micro/results/abi8_parity_corrections_100x2/summary.json`
  (`6b9eb9a909b3c49007ae7fb5755e9f16af7ad0ae4bf101d00372f275887f7273`)

## Verification

- Zig Debug tests: 138/138 passed.
- Zig `ReleaseFast` tests: 138/138 passed with fresh local caches.
- VanillaTD rebuilt from an unchanged source tree.
- Vanilla CTest suite: 14/14 passed.
- Broad transfer episodes: 200/200 valid, with zero infrastructure or engine failures.
- PufferLib native/CUDA extension rebuilt from the candidate Zig source.

Current canonical test digests:

- opening: `5a3cef3d26167fea6910b52ad9a855f15434bb32532fb5b1dcc3afe414dcc76b`
- combat: `3baf599e0451474c0cdcc748b76e2bf0f557f17f48e10ed677dde28948246903`

## Native Throughput

Both versions were built and run on the same machine during this audit:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
zig build --cache-dir /tmp/tdmicro-zig-cache \
  --global-cache-dir /tmp/tdmicro-zig-global -Doptimize=ReleaseFast
cc -O3 -std=c11 -I include tools/batch_benchmark.c \
  zig-out/lib/libtd_micro.a -lm -lpthread -o /tmp/td_micro_batch_benchmark
/tmp/td_micro_batch_benchmark 64 16384
```

| Version | Run 1 SPS | Run 2 SPS | Mean SPS | Failures | Valid |
| --- | ---: | ---: | ---: | ---: | --- |
| Exact `eb27ca8` source | 100,730.860 | 100,681.632 | 100,706.246 | 0 | yes |
| Parity candidate | 95,583.053 | 95,884.045 | 95,733.549 | 0 | yes |

The fixed-action native workload is 4.94% slower. This is a real regression on this benchmark and
must not be hidden by the full-training result below.

## PufferLib Throughput

Both versions used the same normal GPU-training command and were run twice:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
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

| Version | Run 1 SPS | Run 2 SPS | Mean SPS | Start failures | Engine failures | Valid |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Exact `eb27ca8` extension | 71,753.134 | 71,351.592 | 71,552.363 | 0 | 0 | yes |
| Parity candidate extension | 76,583.852 | 76,028.966 | 76,306.409 | 0 | 0 | yes |

The candidate is 6.64% faster on the full PufferLib workload at constant hyperparameters. Policy
trajectories changed, so this measures actual end-to-end training throughput but does not prove the
new frame logic itself is faster. The fixed-action native A/B above is the direct simulator-cost
comparison.

Puffer logs:

- exact checkpoint source: `1784265799067.json`, `1784265857499.json`
- parity candidate: `1784265311125.json`, `1784265562717.json`

## Decision

Retain this candidate for the next parity iteration because it removes both known universal early
mismatch classes and gives much longer exact prefixes. Do not mark `TASK-2A` complete, add the far
spawn, retrain, or promote a policy from this state yet. The next work is to reduce the decision-179+
infantry movement, mission, facing, and occupancy mismatch families and rerun the same 200 tuples.
