# TD Micro Next Throughput Levers

Date: 2026-07-17
Status: CPU sharding rejected; compact observation ABI and concurrent sweep workers implemented

## Pre-ABI-9 Clean Reference

A monitored four-thread run completed 1,048,576 PufferLib CUDA training steps in 10.638 seconds,
or **98,573 aggregate SPS**. Startup and engine failures were zero. GPU utilization was zero before
and after the run, no NVIDIA compute process remained, and the host process list showed no CFD
solver or other material CPU consumer.

This is a clean current-workload result, not a speedup claim against an adjacent historical binary.
At this rate, five million environment steps take about 51 seconds before sweep startup, evaluation,
checkpoint, and W&B overhead.

Configuration:

- native CPU environment with PufferLib CUDA training;
- 64 agents, 4 buffers, 4 threads;
- horizon 32, minibatch 2,048, 1,048,576 total timesteps;
- hidden size 64, one policy layer;
- log: `PufferLib/logs/cnc_micro/1784340401857.json`.

## Measured Sweep-Level Gain: Concurrent Trials

The native CUDA trainer used only about 46% sampled GPU utilization and 1.4 GB of its 8 GB VRAM in
a matched standalone run. Independent trials were therefore launched concurrently on GPU 0. Every
trial retained 64 agents, 4 buffers, 4 threads, horizon 32, minibatch 2,048, hidden size 64, one
layer, and 1,048,576 timesteps. All start and engine failure samples were zero.

| Concurrent trials | Full process wall time | Wall-clock aggregate SPS | Gain vs one | Steady-state aggregate SPS |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 13.777 s | 76,112 | baseline | 90,953 |
| 2 | 22.667 s | 92,519 | +21.56% | 117,604 |
| 3 | 28.418 s | **110,696** | **+45.44%** | **125,300** |
| 4 | 40.090 s | 104,623 | +37.46% | 115,589 |

Three concurrent trials are the measured optimum for this 8-core/16-thread CPU and 8 GB GPU. Four
trials saturate the physical cores and regress. The gain is aggregate search throughput, not higher
SPS for one model: each three-way trial ran at roughly 41-42K SPS. Five-million-step runs have less
relative startup overhead, so their expected gain is closer to the measured steady-state increase
of about 38%; this still needs a real 3x5M W&B acceptance run.

Logs:

- single: `PufferLib/logs/cnc_micro/1784341690437.json`;
- dual: `1784341437316.json`, `1784341437318.json`;
- triple: `1784341549795.json`, `1784341549822.json`, `1784341549824.json`;
- quad: `1784341884349.json`, `1784341884353.json`, `1784341884365.json`,
  `1784341884381.json`.

The retained scheduler now has a logical worker-slot ID separate from `gpu_id`, exposed as the
generic `sweep.workers_per_gpu` setting. A fixed three-slot CUDA characterization produced 133,524
aggregate SPS, 36.45% above the adjacent ABI-9 single-run result, with zero start/engine failures
and matching gameplay metric fingerprints across all slots. A post-review drain fix then passed a
three-slot 262,144-step CUDA integration and collected all final results before process exit. Three
simultaneous 512-1,024-wide deep policies may not fit even though three 64x1 policies do, so
model-size-aware admission remains a future scheduler improvement.

## Rejected Generic Versus Native CPU Build

The Zig simulator was also built with `-Dcpu=native` and compared A-B-A-B against the generic
x86-64 build on one pinned core. Generic and native means were about 200.5K and 201.4K native SPS.
The first pair favored native by 2.13%, while the second favored generic by 1.17%. All runs had zero
failures and digest `38cca161...718ce28`. The net 0.46% difference is noise-level; the generic build
was restored and no CPU-specific build mode was retained.

## Rejected CPU Sharding

The binding previously wrapped all 16 worlds in each GPU buffer in one Zig batch. A TDD prototype
split a buffer into deterministic CPU shards so Puffer's existing OpenMP loop could schedule more
workers. A characterization test required a monolithic batch and two shards to produce identical
observations, masks, rewards, terminals, and per-world digests through timeout resets.

The monitored adjacent comparison changed only `num_threads` and therefore the derived shard count:

| Layout | Agents | Buffers | Threads | Aggregate SPS | Uptime | Start/engine failures |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| One shard per buffer | 64 | 4 | 4 | 98,573 | 10.638 s | 0 / 0 |
| Two shards per buffer | 64 | 4 | 8 | 94,175 | 11.134 s | 0 / 0 |

The two-shard candidate was **4.46% slower**. Average sampled environment time fell from 0.221 to
0.162 seconds, but GPU evaluation time rose from 0.218 to 0.247 seconds and OpenMP/team scheduling
eliminated the CPU gain. A four-shard/16-thread diagnostic was slower still in absolute terms.

The final invalid-action metric also changed from 1,279.5 to 2,064.5 even though the other final
environment metrics matched. That means changing concurrent stream scheduling did not preserve the
full training fingerprint. The prototype was removed, no source change was retained, and the prior
extension was restored with SHA-256:

`2b11bbe0edf00f17b3b4e791cf5a8b4b279f00d0e750e3aef61f14042d0df52d`

Load snapshots are retained in `/tmp/cnc_micro_load_candidate_t{4,8}_{before,after}.log` for this
machine session. Both runs had zero start and engine failures. The eight-thread run is not a valid
speedup and must not be promoted.

## Implemented Lever: Compact Dynamic Observation

The pre-ABI-9 6,208-byte observation was:

| Region | Bytes |
| --- | ---: |
| Globals | 64 |
| Full 64x64 map | 4,096 |
| Owned entity records | 1,024 |
| Enemy entity records | 1,024 |

The map is mostly invariant. Occupancy is duplicated by entity records, and the map has only 344
initial Tiberium cells whose presence can change. With the current flat linear encoder, invariant map
bytes contribute the same constant vector to every sample and are mathematically equivalent to an
encoder bias. They do not communicate state-dependent terrain relationships before the recurrent
network.

ABI 9 replaces the full map with:

1. one byte per initial Tiberium cell, in fixed canonical order (344 bytes);
2. a one-hot scenario/map identifier when more than one map exists;
3. the existing global and owned/enemy entity records unchanged initially.

The implemented first version reduces observation size from 6,208 to **2,456 bytes**. At hidden size 64,
the dense encoder falls from 397,376 to 157,248 parameters, and the complete current policy falls
from 427,520 to about 187,392 parameters: a **56% model-size reduction**. It also removes runtime
construction and host-to-device transfer of the 4,096-byte map region.

The retained implementation uses 2,456 bytes and 187,392 complete policy weights at hidden size 64.
The final alternating fixed-action native A/B improved from 204,232 to 214,988 SPS, or 5.27%, with exact
outcomes and digest. The accepted 1M CUDA run produced 97,857 aggregate SPS, 8.21% above the adjacent
old-ABI mean, with zero start/engine failures. The CUDA comparison remains behavior-dependent.

### Compact-Observation Results

- ABI 9 / observation version 5 rejects old checkpoint sizes.
- The immutable Vanilla executable fixture projects into the compact representation.
- Fixed-action simulation/reward/terminal outcomes and world digests are exact.
- Tests cover canonical Tiberium order, depletion/reappearance, entity parity, scenario id, and
  observation purity.
- The first `0/255` resource encoding failed the learning gate and was rejected. Retaining the old
  packed values `45/56` restored nonzero 1M learning.
- A 5M comparison is not an appropriate current gate because both old and compact observations hit
  the independently documented long-schedule action/optimizer collapse.

Full evidence is in `docs/td_micro/compact_observation_and_sweep_slots.md`.

## Secondary Environment Lever: Event-Driven Bookkeeping

`Batch.step` and policy packing still rescan world arrays repeatedly on every decision:

- four pre-step Refinery/Harvester counts;
- infantry kill snapshots;
- post-step infantry, unit, and building death scans;
- milestone and active-category scans;
- separate observation, occupancy, entity, and action-mask scans.

Simulation events should update compact counters and dirty flags at creation, damage, destruction,
income, and queue transitions. Observation and action-mask packing can then consume those counters in
one canonical pass. This must be driven by a representative recorded policy-action trace; the fixed
no-op native benchmark does not represent trained policies with dozens of active units.

## Additional Simulator And Transport Candidates

These remain hypotheses until the representative trace attributes time to them.

1. **O(1) occupancy for pathfinding.** `pathfinder.Context.movementType` currently scans buildings,
   units twice, and infantry for every route cell query. Maintain canonical per-cell owner/type/count
   flags and update them on movement, creation, deployment, and death. Preserve the original route
   algorithm and tie-breaking; only replace occupancy lookup.
2. **Active-slot bitsets.** Units are sparse and cannot use the populated-prefix optimization.
   Ascending `ctz` iteration over active unit/projectile/effect bitsets can skip empty slots while
   preserving canonical slot order and references.
3. **Combat spatial index.** Nearest-target and in-range scans become quadratic as infantry counts
   rise. Per-cell owner bitsets can filter candidates while final selection still uses original slot
   order and distance/tie rules.
4. **Persistent CPU world workers.** The rejected sharding path created an OpenMP team every RL
   decision. A persistent Zig/C worker pool could parallelize independent worlds without that setup
   cost. This is higher risk because changed CPU/GPU stream timing altered the stochastic training
   fingerprint even though fixed-action world digests matched.
5. **Single packed CUDA transfer.** Each step currently launches separate host-to-device copies for
   observations, rewards, terminals, and action masks, plus an action copy and stream synchronize in
   the other direction. Packing small outputs into one pinned transfer and using CUDA events could
   reduce launch/synchronization overhead. Compact observations should land first because it changes
   the same transport boundary.
6. **Four-frame exact fast path.** A decision advances four frames. When no production, movement,
   combat, AI, RNG, or economy event can occur before the fourth frame, timers can advance in bulk;
   otherwise fall back to the existing frame loop. Differential tests must compare every skipped
   intermediate frame and RNG state.
7. **Hot/cold world-state split and SoA/SIMD.** Separate frequently ticked timers, positions, health,
   and missions from cold paths, archives, and static map/resource data. A later structure-of-arrays
   batch can vectorize simple timer and queue updates across worlds. This is a larger rewrite after
   the simpler lookup and observation wins.

## Sample-Efficiency Multipliers

These do not raise SPS, but can increase useful 5M-quality trials per day more than another small
simulator optimization.

- Add resumable successive halving: every candidate uses the five-million-step LR schedule, pauses
  at one million, and only promising candidates resume to five million. Persist model, optimizer,
  epoch, RNG, and scheduler state so promotion is continuation rather than a changed 1M run.
- Rank early candidates by combat/economy/milestone learning curves as well as win rate, since a
  one-million-step policy may not win yet.
- Behavior-clone translated original-AI state/action traces before PPO fine-tuning. This uses the
  existing oracle brain to teach legal build, economy, scouting, and attack behavior instead of
  requiring PPO to rediscover all of it from terminal rewards.
- Stage architecture search: establish reward/optimizer regions with 64-128-wide shallow policies,
  then spend larger-model compute only around configurations that already learn.

## Sweep Throughput Policy

The `cnc5` logs show that architecture choices themselves consume much of the sweep budget. Median
SPS falls sharply as hidden size and depth rise. For the initial five-million-step search, use the
fast architecture band first (64-128 hidden units and shallow recurrent depth), then run a smaller
promotion sweep over larger models only for reward/optimizer regions that already learn. This does
not count as a simulator speedup, but it prevents most sweep time from being spent on 512-1,024-wide,
deep policies before the learning signal is established.

## Recommended Order

1. Retune learning rate and optimizer settings for ABI 9 with three sweep workers on GPU 0.
2. Fix the independent-head action ABI / long-schedule collapse before spending another 5M run.
3. Add a representative fixed-action trace benchmark from an actual trained rollout.
4. Profile the remaining environment half with that representative trace.
5. Replace repeated reward/metric/policy scans with deterministic event counters if confirmed hot.
6. Implement O(1) route/target lookups only where the trace still attributes material time.
