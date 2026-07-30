# TD Micro Early Opponent Force

Date: 2026-07-16
Status: implemented, verified, and committed
Parent commit: `f3b5a1cce7b6db0241601643f8d9e266051cba92`
Implementation commit: `0ee9239fb043de6ef6900290b2cb41414a46c6f6`

## Outcome

The original GDI AI was not disabled. The schema-6 micro rules inherited TD's stock
`AttackDelay=5`, which held `Control.MaxInfantry` at zero for most of these short matches. The
retained policy could therefore dismantle the enemy base before the opponent fielded a useful
force.

TD Micro schema 7 now pins `ai.attack_delay=1` in the versioned rules manifest. Both real Vanilla
and the Zig environment consume the generated constant. This is not a selectable INI fast path and
does not replace the original AI algorithm.

The real-Vanilla seed-2 oracle now records:

| Event | Frame |
| --- | ---: |
| Initial attack countdown | 1,396 |
| First E3 train command | 1,430 |
| First completed infantry | 1,648 |
| Maximum live infantry by frame 2,800 | 7 |

This closes the specific no-army defect. It does not prove that a newly trained policy beats the
defending force; checkpoints from the previous rules contract are stale and must be retrained.

## TDD Sequence

Tests were added before each implementation correction:

1. A rules test required both supported seeds to field opponent infantry before frame 2,500.
2. A real-Vanilla fixture test pinned seed 2's countdown, first train, first release, and minimum
   live-force size.
3. Differential traces then exposed logic that the delayed AI rarely exercised: early queue
   selection, Harvester/infantry congestion, vehicle head-cell reservations, partial path reuse,
   building-footprint weapon range, building target coordinates, damaged-building power output,
   and half-health fire-effect RNG/state.
4. Each mismatch received a focused failing test before the Zig behavior changed.
5. The scripted Refinery/Harvester trace was extended through first delivery and required exact
   gameplay state and RNG parity.

The resulting implementation retains Westwood ordering. The AI opens its infantry cap when the
countdown expires and can select infantry before the Barracks is placed; the queue remains suspended
until the Barracks exists. Reordering that choice would change seeded RNG and subsequent behavior.

## Determinism And Parity

- Rules manifest SHA-256:
  `bcb23e390785cb3b500f763752ae354a45972ec864356352ea5614d59f2df389`
- Seed-2 early-force fixture SHA-256:
  `fb47e33853da91143cf60a7d2436dcd6ca6bac5f9fac669657d52695828f4510`
- Repeated native benchmark digest:
  `38cca1613d27fcaa4500c25261cff6ea19d838ccd80d9c91fec4d045d718ce28`
- Opening replay digest:
  `e272e32de4886ab9f46aa0df1d70b2a56bee47e7cc04c7b1aa6241f3835a4eef`
- Combat replay digest:
  `483cab85942327265e6fa6fbcc01d070f2c0a139bdac83e660dc51ed0a2b491f`

The new native digest intentionally differs from the parent candidate's
`40d2b1f231900149e01f4a7c6af0189122609f59b32c65d95dccdac715537e02` because the corrected world
state includes the early AI force and persistent building-fire effects. Determinism is established
by identical repeated candidate hashes; correctness is established separately by real-Vanilla
fixtures and focused differential tests.

## Verification

The following gates passed:

- `zig build test --summary all`: 145/145 tests in Debug.
- Repeated Debug test run: 145/145 tests with the same locks.
- `zig build test -Doptimize=ReleaseFast --summary all`: 145/145 tests.
- Remastered-style `TiberianDawn.so` rebuild.
- Human-play `VanillaTD` rebuild.
- `ctest --test-dir Vanilla-Conquer/build-td --output-on-failure`: 14/14 tests.
- PufferLib `cnc_micro` native/CUDA extension rebuild.

After the final test-only path diagnostic was removed, Debug was rerun and again passed 145/145.

## Throughput

### Native Fixed-Action Batch

Command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
zig build --cache-dir /tmp/tdmicro-current-cache-0716 \
  --global-cache-dir /tmp/tdmicro-current-global-0716 -Doptimize=ReleaseFast
cc -O3 -std=c11 -I include tools/batch_benchmark.c \
  zig-out/lib/libtd_micro.a -lm -lpthread -o /tmp/td_micro_batch_benchmark
/tmp/td_micro_batch_benchmark 64 16384
```

| Build | Run 1 SPS | Run 2 SPS | Mean SPS | Failures | Digest stable |
| --- | ---: | ---: | ---: | ---: | --- |
| Parent parity candidate | 95,583.053 | 95,884.045 | 95,733.549 | 0 | yes |
| Schema-7 early-force candidate | 101,557.306 | 100,807.283 | 101,182.295 | 0 | yes |

The fixed-action mean improved 5.69% on this machine. This is useful but secondary to the behavior
fix; no isolated subsystem speedup is claimed.

### PufferLib GPU Training Smoke

Command:

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

Result:

| Build | Aggregate SPS | Final displayed SPS | Start failures | Engine failures | Valid |
| --- | ---: | ---: | ---: | ---: | --- |
| Matched parent candidate mean | 76,306.409 | n/a | 0.000 | 0.000 | yes |
| Schema-7 early-force candidate | 76,302.238 | 72,527 | 0.000 | 0.000 | yes |

Configuration was 64 agents, 4 buffers, 4 threads, horizon 32, 1,048,576 total timesteps,
minibatch 2,048, hidden 64x1, and GPU training. The -0.006% aggregate difference is noise: the
full training path has no measurable throughput regression. Log:
`PufferLib/logs/cnc_micro/1784307384562.json`.

## Next Gate

Retrain on the schema-7 rules and require held-out Zig and visible Vanilla evaluations to record
enemy infantry production and combat orders. A policy win without encountering a nonzero defending
force must not count as completion of the Easy-AI curriculum.
