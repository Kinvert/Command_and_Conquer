> **SUPERSEDED by `docs/HANDOFF.md`** (2026-07-27). Read that first. This file is kept only
> for its CNC30 detail; its "what is running" and "open problem" sections are stale.

# Handoff — CNC30: winning Vanilla games with a Medium Tank

Written 2026-07-26. Read this before touching anything; it records what is running, what is
uncommitted, and which hypotheses have already been disproved by measurement.

## The goal (user's words, verbatim)

> "the goal is getting medium tank and humvee... We want a winning gif of winning a refinery +
> medium tank + humvee. That gets us the full 'rock paper scissors' of the game."

> "It needs to win IN VANILLA, it must build the war factory or whatever and build at least one
> tank."

Explicitly **not** a rush: *"showing lame rush games is gay... I already have gifs of rushes."*
A refinery-win GIF has already been delivered. The open deliverable is a **Vanilla** win that
builds a Weapons Factory and at least one Medium Tank, in a played-out (non-rush) game.

### Standing constraints — do not violate

- **Never put AI attribution in commit messages.** No `Co-Authored-By: Claude`, no "Generated
  with". The user was blunt about this. There is a memory file recording it.
- **Do not exceed the user's $100 credit limit.** Going past the normal Pro limit into the $100 of
  credits is fine; past the credits is not.
- **Keep determinism with Vanilla.** *"Don't fuck up the progress made in the td-micro."*
- Prefer commands that do not require approval while working autonomously.
- Sweeps are aimed at **cnc30** now (the loop prompt still says cnc27; it has advanced
  cnc27 → cnc28 → cnc29 → cnc30). The next one is cnc31.

## Where everything lives

Primary worktree — **this is where all current work is**:

```
/home/claude/cnc/.worktrees/merge-test          branch: td-micro-merge-test
├── td-micro/          deterministic Zig simulator (the training core)
├── PufferLib/         native env `cnc_micro` + training/sweep driver
└── Vanilla-Conquer/   C++ bridge for visible deployment (tdmicro_policy.cpp, tdmicro_action.cpp)
```

Note the repo root `/home/claude/cnc` has its own `CLAUDE.md`, and the worktree has a **different**
`CLAUDE.md` describing the td-micro path. The worktree copy is the relevant one.

HEAD: `224c41d Stop a full unit array from voiding the episode`

## CNC32 OVERNIGHT SWEEP -- READ THIS FIRST

Launched 2026-07-27 08:46 UTC. W&B project **cnc32**, `--sweep.max-runs 1000`,
`--sweep.workers-per-gpu 3`, log `PufferLib/logs/cnc32_overnight.log`.

**`train.total_timesteps` is swept, 5 Mi to 10 Mi** (11 categorical values, every one a multiple of
the 2048 epoch size -- `validate_config` rejects anything else, which is why it is categorical and
not `int_uniform`). `train.schedule_timesteps` stays excluded at 10 Mi so the LR anneal shape is
identical across trials and only the stopping point moves.

**Filter by creation time before analysing.** cnc32 holds runs from two different builds:

- runs created **before 2026-07-27T08:46:23Z** (names ending -1 through -13) ran the *latched*
  armour rewards, which were measured to collapse training and have since been reverted.
- runs created **at or after** that timestamp (`glamorous-sun-14` onward) are the current build.

Mixing them corrupts the analysis exactly the way CNC30's degenerate trials skewed the reward
correlations. Filter on `r.created_at >= "2026-07-27T08:46:23Z"`.

Expect the optimiser to drift toward 10 Mi, since longer training should score better on
`full_perf`; that costs about twice the compute per trial, so trial count will be lower than
CNC30's ~29/hour.

## What was running earlier

The **cnc30 sweep**, launched from `PufferLib/`:

```bash
cd /home/claude/cnc/.worktrees/merge-test/PufferLib
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
nohup env PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc30 \
  --sweep.gpus 1 --sweep.max-runs 400 --sweep.workers-per-gpu 3 \
  > logs/cnc30_sweep.log 2>&1 &
```

- W&B: https://wandb.ai/kinvert-k/cnc30
- Log: `PufferLib/logs/cnc30_sweep.log` (rich TUI; strip NULs with `tr -d '\000'` before grepping)
- ~29 trials started as of writing; best `full_perf` seen **0.054**, best `perf` **0.203**.
- 3 worker processes at ~485% CPU each, plus the parent.

**`--sweep.gpus 1` is required.** Without it, `pufferl.sweep` autodetects GPUs via
`len(os.listdir('/proc/driver/nvidia/gpus'))`, which does not exist on WSL, and dies with
`FileNotFoundError`.

### Do not rebuild the `.so` while the sweep runs

`./build.sh cnc_micro` rewrites `pufferlib/_C.cpython-312-x86_64-linux-gnu.so`. Running workers
keep the copy they loaded, but **newly spawned trials load the new binary**, so the search would
silently mix two different simulators. Keep any simulator investigation in Zig-only tests
(`zig build test`) until you are ready to stop the sweep.

Build (when the sweep is *not* running) needs both of these or it fails:

```bash
cd /home/claude/cnc/.worktrees/merge-test/PufferLib
export PATH="$PWD/.venv/bin:$PATH"    # build.sh calls bare `python`
export CUDA_HOME=/usr/local/cuda-12.8 # else ccache tries ./bin/nvcc and fails
./build.sh cnc_micro
```

`zig build -Doptimize=ReleaseFast` in `td-micro/` first — it produces
`td-micro/zig-out/lib/libtd_micro.a`, which `build.sh` links.

## The `full_perf` objective (user-designed)

> "we need to change this so our sweep maximizes: 1) Win 2) income threshold 3) build at least one
> tank... Only when it hits all our thresholds is it getting the +1 for full_perf... +0.5 for other
> wins, but + 1.0 when it hits all the criteria."

> "I'd like to track that a tank fired at least once to get the +1 full_perf."

`full_perf = full_wins / full_match_episodes`, where a full win requires **all** of: win, harvested
income ≥ `economy_win_credits` (1000), ≥ `full_win_min_tanks` (1), and ≥ `full_win_min_tank_shots`
(1). Humvees are opt-in (`full_win_min_humvees = 0`) — *"maybe skip humvee for now."*
Config: `PufferLib/config/cnc_micro.ini`, `[sweep] metric = full_perf`.

Log metrics must stay **under 31** keys (currently 19). Exceeding the `vec_log` dict capacity
previously caused heap corruption — see "Bugs already found" below.

## Uncommitted work in the tree

```
 M td-micro/src/batch.zig            FailureCensus struct + capture at the `failed` site
 M td-micro/tests/all_tests.zig      registers the probe below
?? td-micro/tests/failure_census_probe.zig   TEMPORARY diagnostic
```

`FailureCensus` is worth keeping — `state.Failure` only says `capacity_overflow` without naming
*which* array, and the world resets before anything can be inspected. It is captured at the point
`failed` is computed (batch.zig ~line 1057), **not** at the `stats.failures` increment further
down, because the world resets in between and a census read there describes a fresh world.

`tests/failure_census_probe.zig` is a scratch probe, not a parity test. It runs 200k batch steps ×
64 worlds and prints a census on any failure. **Delete it or gate it before committing** — it adds
~13M env steps to every `zig build test` run.

## The open problem

Some cnc30 trials report `failures ≈ 0.011–0.021` at the 5M-step mark (most frames report `0.000`).
Engine failures void episodes, and `CLAUDE.md` says nonzero failures invalidate a run — so
`full_perf` is being measured on a slightly contaminated population.

### Already disproved by measurement — do not re-propose these

1. **Unit array (`max_units = 16`)** — was a real cause, now **fixed** in `224c41d`. Verified
   `failures 0.0103 → 0.000` over a clean 3M-step run.
2. **Projectile pool (`max_projectiles = 256`)** — the census showed `proj=0` at the failing step.
3. **Buildings / infantry** — `bld=8`, `inf=18` at the failing step, against caps of 64 and 128.
4. **Random or greedy scripted play reproducing it** — the probe ran 12.8M env steps (~1,000
   episodes) with both build-heavy (85% production commands) and attack-heavy (50/35) action
   distributions and produced **zero** failures.

### The live lead

The probe's `initWithConfigs` is **not** configured the way the real env is. I was mid-diff of
`PufferLib/ocean/cnc_micro/binding.c` (`cnc_micro_init`, around line 141) against the probe when
this handoff was written. The most likely gap is **starting-credit randomization** — the env
randomizes starting income in 100-credit increments between 2300 and 10000, and 10,000-credit
starts build far more than the probe's defaults. Make the probe match `binding.c` exactly, then
re-run; if it reproduces, the census prints the offending array directly.

If it still will not reproduce, the honest next step is a **separate worktree** with its own `.so`,
running a full 5Mi training with the census printed to stderr — do not do this in this worktree
while the sweep is live.

## Bugs already found and fixed (context for how this code fails)

The recurring lesson, validated many times this session: **every hypothesis reasoned-into was
wrong; every real bug came from differential measurement.** Budget for measurement, not analysis.

- **Weapons Factory was unplaceable** — `placement.footprint()` had no `weapons_factory` case, hit
  `else => null`, so `isLegal` was false on every cell of every map. `weapons_factories_built` was
  0.000 across 116 trials. I blamed reward price, then exploration depth; both wrong.
- **Mask/apply mismatch** — a recurring defect class. The mask advertised actions the apply path
  rejected (ABI13 bitset, ABI14 group attacks, vehicles). `MaskOffset` in `tdmicro_policy.cpp` is
  now derived from head widths with `static_assert`.
- **Struct field-order drift** — `Stats` vs `TdMicroBatchStatsV2` disagreed on field *order* while
  both were 424 bytes, so the size assert passed. Symptom the user caught: *"How can wins that
  require special cases happen more than any kind of win?"* Now guarded by
  `td-micro/tools/abi_field_order_check.py` (compares field *sequences*) and offset asserts in
  `tools/abi_size_check.c` (build with `cc -Iinclude`).
- **`vec_log` dict overflow** — 39 keys into a capacity-32 dict; `-DNDEBUG` removed the assert, so
  it silently corrupted the heap. Capacity is now `PUFFER_LOG_DICT_CAPACITY 128` and the bounds
  check is an unconditional `fprintf` + `abort`.
- **Silent flat-zero metrics** — `tank_shots` was declared and summed but never assigned; it would
  have made the cnc30 objective a flat-zero landscape. Now assigned in `batch.zig` from
  `world.metrics_tank_shots`. **Always confirm a new metric is nonzero before sweeping on it.**
- **Unit slots vs live units** — `addUnit` only reuses a slot once its `kind` is cleared, so
  destroyed units keep occupying one. A guard counting *live* units passed at 14 of 16 and walked
  straight into the overflow it existed to prevent. Use `world.freeUnitSlots()`.
- **Uncommitted work lost in a merge** — the barracks gate and harvester lock existed only as
  working-tree edits and a merge silently reverted them. **Commit before merging or sweeping.**

### Capacity facts worth knowing

| constant | value | meaning |
|---|---:|---|
| `max_units` | 16 | simulator storage for the *vehicle* array (MCV, harvester, tank, humvee) |
| `max_buildings` | 64 | building storage |
| `max_infantry` | 128 | infantry storage |
| `max_projectiles` | 256 | projectile pool |
| `entity_slot_count` / `selector_count` | 64 | the **policy's** addressable slots, spanning units + buildings + infantry *together* |

`max_units = 16` is legacy: it was sized when the ruleset was MCV + harvester only, and CNC26
dropped combat vehicles into the same array without resizing it. Harvesters occupy a slot even
though the policy cannot command them (controllability is a mask decision; storage is not).
**Raising any capacity edits the rules manifest, changes `TD_MICRO_MANIFEST_SHA256`, and
invalidates every Vanilla fixture.** That is why the fix was deferral + masking, not a bigger array.

## Verification gates before any claim

```bash
cd /home/claude/cnc/.worktrees/merge-test/td-micro
zig build test -Doptimize=Debug        # 301/301 (302 with the probe registered)
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
python3 tools/abi_field_order_check.py
cc -Iinclude tools/abi_size_check.c -o /tmp/abisize && /tmp/abisize
```

**Beware false-pass shell patterns.** These have burned me repeatedly this session:
- `cmd | head && echo PASS` prints PASS even when `cmd` failed — check for the *artifact*, not the
  exit status of a pipeline.
- `cmake --build --target vanillatd` reported 0 errors while building nothing; the target is
  `VanillaTD` (case-sensitive).
- `cmp -s a b` on two files that both do not exist reports "differ", which reads as a pass.
- `pgrep -f`/`pkill -f` match your own shell. Use the `[p]attern` bracket trick or explicit PIDs.
  I killed my own shell five times (exit 144) before adopting this.

## Remaining path to the deliverable

1. Close out the failure rate (above), so `full_perf` is measured on clean episodes.
2. Let cnc30 run; pick the best `full_perf` config off the W&B leaderboard.
3. Reproduce that config as a real checkpoint (a sweep trial is not a retained checkpoint).
4. Hunt Vanilla seeds for a match the checkpoint wins **in Vanilla** while building a Weapons
   Factory and ≥1 Medium Tank that fires.
5. Capture the GIF. **WSLg note:** `x11grab` on the X root captures nothing (12-byte frames) —
   WSLg composites. Use `td-micro/tools/wingrab.c`, which does `XGetImage` on the window drawable.
   An earlier `xwd`-based check was a false positive; `xwd` was not even installed.

### Deferred / known-open

- Task 12: Vanilla-Conquer oracle fixtures for Weapons Factory / Humvee / Medium Tank parity.
- `starting_credits_constrained_percent` 35 → 50, blocked by the manifest-hash / fixture
  invalidation problem described above.
- Build-order shaping (`reward_build_order_violation`) is **off by default**: any nonzero value
  collapsed `balanced_perf` from 0.588 to ~0.05 by teaching barracks *avoidance* rather than
  build reordering. The user's reaction: *"yeah I said it would learn worse. duh."* It stays
  sweepable, with ranges that include 0.
