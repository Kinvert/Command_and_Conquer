# Handoff — getting a Vanilla win with a Medium Tank

Authoritative as of 2026-07-28. Supersedes `HANDOFF_cnc30_vehicle_win.md`, which is kept only for
its CNC30 detail. Read this before touching anything.

## The deliverable (user's words)

> "the goal is getting medium tank and humvee... We want a winning gif of winning a refinery +
> medium tank + humvee. That gets us the full 'rock paper scissors' of the game."

> "It needs to win IN VANILLA, it must build the war factory or whatever and build at least one
> tank."

Explicitly **not** a rush: *"showing lame rush games is gay... I already have gifs of rushes."* A
refinery-win GIF is already delivered. What is open: a **Vanilla** win, in a played-out game, that
builds a Weapons Factory and at least one Medium Tank that fires.

### Standing constraints — do not violate

- **Never put AI attribution in commit messages.** No `Co-Authored-By`, no "Generated with". The
  user was blunt about this; there is a memory file recording it.
- **Do not exceed the user's $100 credit limit.** Past the normal Pro limit into the credits is
  fine; past the credits is not.
- **Keep determinism with Vanilla.** *"Don't fuck up the progress made in the td-micro."*
- Prefer commands that do not need approval when working autonomously.
- The user works late and leaves sweeps running overnight. If you launch one, it **must** survive
  you going idle — see "Launching a sweep so it survives".

## Where everything is

```
/home/claude/cnc/.worktrees/merge-test          branch: td-micro-merge-test
├── td-micro/          deterministic Zig simulator (the training core)
├── PufferLib/         native env `cnc_micro` + sweep driver (modified; not stock upstream)
└── Vanilla-Conquer/   C++ bridge for visible deployment
```

The repo root `/home/claude/cnc` has its own `CLAUDE.md`; the worktree has a **different** one
describing the td-micro path. The worktree copy is the relevant one.

Base HEAD: `ff5c510 Write the current handoff and mark the CNC30 one superseded`

## CNC32 — stopped, diagnosed, and replaced

The CNC32 sweep is no longer running. Log `PufferLib/logs/cnc32_night3.log`. W&B:
https://wandb.ai/kinvert-k/cnc32

**Filter by creation time.** cnc32 holds runs from two builds. Runs created **before
`2026-07-27T08:46:23Z`** used the latched armour rewards (since reverted, see below) and must be
excluded. `glamorous-sun-14` onward is the current build.

Best result so far, roughly **double CNC30's 0.066**:

| full_perf | perf | factories | tanks | kills | failures | steps | run |
|---:|---:|---:|---:|---:|---:|---:|---|
| **0.1237** | 0.309 | 0.67 | 0.87 | 1.11 | 0.0000 | 5.51 Mi | `worldly-smoke-325` |
| 0.1111 | 0.478 | 0.61 | 1.34 | 1.15 | 0.0000 | 5.00 Mi | `fiery-snow-367` |
| 0.0934 | 0.278 | 1.00 | 1.62 | 1.69 | 0.0276 | 5.00 Mi | `treasured-sound-122` |

Population: max 0.1237, median 0.0205, 52 trials > 0.05, 2 > 0.10. It did not approach the 0.30
target.

### Two findings that matter

**Longer training barely helps, and the optimiser knows it.** `total_timesteps` was swept 5–10 Mi,
but Protein kept choosing short runs: median 5.01 Mi, max only 7.69 Mi. Shorter half mean full_perf
0.0213, longer half 0.0272. Protein is cost-aware, so it is buying more trials rather than longer
ones. If you want a genuine long-training answer, pin `total_timesteps` at 10 Mi rather than
sweeping it.

**The champion barely pays for armour at all.** `worldly-smoke-325` used
`reward_weapons_factory = 0.089`, `reward_vehicle = 0.0`, `reward_tank_kill = 0.082`,
`reward_milestone = 0.0`, `reward_player_unit_loss = 0.0`. The tech path instead comes from
`reward_refinery = 0.494`, `reward_enemy_building_loss = 1.0` and
`reward_build_order_sequence = 0.374`. This independently confirms the user's instinct that paying
much for factories teaches bad play — the optimiser drove that reward to near zero on its own.

Champion training hypers: `learning_rate 0.001669`, `gamma 0.80`, `gae_lambda 0.9905`,
`ent_coef 0.001021`, `vf_coef 4.225`, `vf_clip_coef 7.52`, `clip_coef 0.9031`,
`max_grad_norm 1.0568`, `replay_ratio 6.186`, `prio_alpha 0.0725`, `vtrace_rho_clip 0.5706`,
`vtrace_c_clip 5`, `minibatch_size 2048`, `total_timesteps 5781504`.

### What CNC32 says about reachability

The tank is not combinatorially unfindable. The current action surface has 12 commands and legality
masks expose the short prerequisite chain. Across completed CNC32 runs, 916/963 trials had nonzero
`full_perf`; the median policy built about 1.04 tanks and fired about 8.25 tank shots per episode.
The hard part is assigning credit across the long temporal chain and converting a reached tank
state into a win.

### Current replacement experiment

CNC33 was stopped after 36 finished trials. The evidence and repairs are recorded in
`docs/td_micro/cnc33_combat_diagnosis_and_repairs.md`.

The first replacement, CNC34, is invalid and stopped. Switching from ABI14 to ABI13 activated
ABI13's old Harvester move/harvest/return masks. Random policy move orders replaced the autonomous
harvest mission, collapsing mean delivered income from CNC33's 10,444-credit median to effectively
zero. The diagnosis, repair, and CNC35 acceptance snapshot are recorded in
`docs/td_micro/cnc35_harvester_repair.md`.

CNC35 is running in durable tmux session `cnc35`, log `PufferLib/logs/cnc35-tmux.log`, W&B:
https://wandb.ai/kinvert-k/cnc35. It uses explicit ABI13 actor-conditioned targeting, categorical
entity-type features, complete tank combat observations, E3-versus-tank counter drills, and
matchup telemetry. Harvesters remain observable but are no longer policy-selectable, leaving
harvest/return to the simulator. The reward surface is `reward_enemy_building_loss=1.0`,
`reward_refinery=0.4`, one-time first-tank/first-shot rewards of `0.1`, and
`reward_qualified_loss=-1.0`; incidental production, unit-kill, income-drip, and build-order
rewards remain zero.

CNC35 honors the requested 5-10 Mi transition range and varies only:

- `train.total_timesteps`: integer uniform `[5,242,880, 10,485,760]`
- `reward_refinery`: uniform `[0.3, 0.6]`, default `0.4`

The first live acceptance snapshot at roughly 1.9-2.15 Mi steps showed mean delivered income of
2,950, 3,537.5, and 11,316.7 credits, with zero failures/start failures. One run already had
`full_perf=0.25`, proving the CNC34 mechanical zero is gone. New logs expose the E1-to-infantry,
E3-to-vehicle, tank-to-E3, and tank-loss-to-E3 rates alongside the existing tank build/use and
terminal metrics.

**CNC35 must use one sweep worker.** Three simultaneous workers each ran at only 4.8-8.3K SPS and
took 14-18 minutes because their native env steps saturated the eight CPU cores. An unchanged
single-worker 1,048,576-step validation ran at 27.7K SPS in 41 seconds; the relaunched sweep's first
live point was 28.8K SPS. Its first complete 5,242,880-step run averaged 17.8K SPS and 334 seconds
under concurrent host load, with zero failures and start failures. A separate dogfight evaluation
was observed using roughly three additional CPU cores, and a later CNC35 live point fell to 12K
SPS while it ran. One worker removes CNC35's self-inflicted oversubscription; remaining slowdown
comes from other work sharing this CPU and from trials legitimately ranging from 5-10 Mi.

Do not edit the ini while a sweep runs — trials read it at spawn.

## Launching a sweep so it survives

```bash
cd /home/claude/cnc/.worktrees/merge-test/PufferLib
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
setsid nohup env PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cncNN \
  --sweep.gpus 1 --sweep.max-runs 1000 --sweep.workers-per-gpu 1 \
  > logs/cncNN.log 2>&1 < /dev/null &
```

Three things that each killed a sweep on this box:

1. **`setsid` is required.** `nohup ... &` leaves the process in the shell's process group, so an
   interrupted turn signals it and it dies. Verify with `ps -o pid,ppid,sid` — the parent must show
   `PPID 1` and its own SID.
2. **`--sweep.gpus 1` is required.** Otherwise `pufferl.sweep` counts GPUs via
   `len(os.listdir('/proc/driver/nvidia/gpus'))`, which does not exist on WSL, and dies instantly.
3. **Never use a `categorical` sweep space.** Protein feeds continuous values back through
   `normalize()`, and `Categorical.normalize` resolves by tuple membership, so the first modelled
   suggestion raises `ValueError: np.float64(...) is not in categorical values` and takes the
   parent with it — **after the first batch completes**, which looks exactly like "the sweep is
   stuck at N runs". `total_timesteps` is now `int_uniform`, snapped to the epoch grid in
   `pufferl.sweep` before `validate_config` (that snap also clamps to the configured range;
   without the clamp a 741k suggestion became a 0.71 Mi trial against a 5 Mi floor).
4. **Use one CNC sweep worker on this eight-core host.** Three workers oversubscribe the
   single-threaded native batch work and reduce aggregate SPS. Do not infer GPU parallelism from
   low VRAM use; CNC is CPU-bound during environment evaluation.

**Always confirm a sweep gets past its first batch** (trials > workers) before walking away.

### Building

```bash
cd td-micro && zig build -Doptimize=ReleaseFast        # produces zig-out/lib/libtd_micro.a
cd ../PufferLib
export PATH="$PWD/.venv/bin:$PATH"      # build.sh calls bare `python`
export CUDA_HOME=/usr/local/cuda-12.8   # else ccache tries ./bin/nvcc and fails
./build.sh cnc_micro
```

**Never rebuild the `.so` while a sweep runs.** Running workers keep their loaded copy but new
trials load the new binary, silently mixing two simulators into one search. This happened once
already and cost a sweep.

## The reward design

`full_perf = full_wins / full_match_episodes`, where a full win needs **all** of: win, harvested
income ≥ 1000, ≥ 1 medium tank, and ≥ 1 tank shot. Humvees are opt-in (`full_win_min_humvees = 0`).
Log metrics must stay under 31 keys (currently 30).

The active armour rewards are one-time events, not active-count deltas. This closes the rebuild
farming channel without making the whole outcome depend on one terminal conjunction. Keep the
older dense fields in the ABI for trace/config compatibility, but they are zero in the focused
sweep.

Two changes from that work were kept because they hold regardless of density:

- `vehicle_gain` counts **medium tanks only**. A humvee costs 400 against the tank's 800, so
  counting both let the cheap unit collect a bounty meant to pay for reaching armour — against a
  criterion that specifically requires a tank.
- `reward_tank_kill` pays **per kill** credited to a player medium tank. A large bounty for
  *building* a tank rewards rushing one out to be deleted by rocket infantry; a kill costs a real
  engagement and cannot be manufactured the way an active-count delta can.

## Open problems

1. **Qualified-loss conversion.** A high qualification rate with low conversion means the softer
   terminal is teaching decorative tank use rather than winning; use the new conversion metric as
   the veto, even if return improves.
2. **Residual engine failures.** Median ~0.004, some trials to 0.036. Four hypotheses are already
   **disproved by measurement — do not re-propose them**:
   - unit array `max_units = 16` — was a real cause, fixed in `224c41d` (`failures 0.0103 → 0.000`)
   - projectile pool — census showed `proj=0` at the failing step
   - buildings/infantry — `bld=8`, `inf=18` against caps of 64 and 128
   - scripted play reproducing it — 12.8M env steps, build-heavy and attack-heavy, **zero** failures

   Live lead: the probe's `initWithConfigs` does not match `binding.c`'s `cnc_micro_init`; likely
   the starting-credit randomisation (2300–10000). `batch.FailureCensus` records which capacity
   overflowed at the failing step — use it rather than guessing.
   `td-micro/tests/failure_census_probe.zig` exists untracked as a scratch probe; it adds ~13M env
   steps per test run, so gate or delete it before committing.

## Capacity facts

| constant | value | meaning |
|---|---:|---|
| `max_units` | 16 | simulator storage for the *vehicle* array (MCV, harvester, tank, humvee) |
| `max_buildings` | 64 | building storage |
| `max_infantry` | 128 | infantry storage |
| `max_projectiles` | 256 | projectile pool |
| `entity_slot_count` | 64 | the **policy's** addressable slots, spanning units + buildings + infantry together |

`max_units = 16` is legacy — sized when the ruleset was MCV + harvester only, and CNC26 dropped
combat vehicles into the same array. Harvesters occupy a slot despite not being commandable
(controllability is a mask decision; storage is not). `addUnit` only reuses a slot once its `kind`
is cleared, so **destroyed units keep occupying one** — use `world.freeUnitSlots()`, never a count
of live units. **Raising any capacity edits the rules manifest, changes `TD_MICRO_MANIFEST_SHA256`
and invalidates every Vanilla fixture.**

## Verification gates

```bash
cd td-micro
zig build test -Doptimize=Debug        # 311/311
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
python3 tools/abi_field_order_check.py           # field ORDER, not just size
cc -Iinclude tools/abi_size_check.c -o /tmp/abisize && /tmp/abisize
```

`zig build test` prints a `failed command:` line to stderr even on success — **check the exit code**,
not the text. Other false-pass patterns that have burned prior sessions:

- `cmd | head && echo PASS` prints PASS even when `cmd` failed — check for the artifact
- the CMake target is `VanillaTD`, not `vanillatd`; the wrong case "succeeds" while building nothing
- `cmp -s a b` on two missing files reports "differ", which reads as a pass
- a stale binary will run happily after `cc` fails — delete it first
- `pgrep -f`/`pkill -f` match your own shell; use `[p]attern` or explicit PIDs

## Lessons that keep paying off

**Every hypothesis reasoned-into this project has been wrong; every real bug came from differential
measurement.** Budget for measurement, not analysis. Specifically:

- Confirm a new metric is **non-zero** before sweeping on it. `tank_shots` was declared, summed and
  never assigned — it read 0.000 for an entire sweep while looking like a real measurement.
- Do not conclude from n=1. The reward-latch collapse only became credible at three seeds; and the
  "armour costs wins" reading from CNC30 evaporated under a proper correlation.
- Beware ratio artifacts. `conversion = full_perf/perf` correlates negatively with `perf` by
  construction; that is not a strategy trade-off.
- Size asserts do not catch field-order drift. `Stats` vs `TdMicroBatchStatsV2` once disagreed on
  order at identical 424 bytes. `abi_field_order_check.py` exists for this.
- Exceeding the `vec_log` dict capacity corrupted the heap silently under `-DNDEBUG`. Capacity is
  now `PUFFER_LOG_DICT_CAPACITY 128` with an unconditional abort.
- Commit before merging or sweeping; a merge once silently reverted uncommitted working-tree fixes.

## Next steps toward the deliverable

1. Reproduce `worldly-smoke-325` as a real retained checkpoint (a sweep trial is not one).
2. Hunt Vanilla seeds for a match that checkpoint wins **in Vanilla** while building a Weapons
   Factory and ≥1 Medium Tank that fires.
3. Capture the GIF. **WSLg:** `x11grab` on the X root captures nothing (12-byte frames) — use
   `td-micro/tools/wingrab.c`, which does `XGetImage` on the window drawable. An earlier `xwd`-based
   check was a false positive; `xwd` was not installed.

Deferred: Vanilla oracle fixtures for Weapons Factory/Humvee/Medium Tank parity (task 12);
`starting_credits_constrained_percent` 35 → 50 (blocked by manifest-hash invalidation).
Build-order violation shaping stays **off by default** — any nonzero value collapsed
`balanced_perf` 0.588 → ~0.05 by teaching barracks avoidance instead of build reordering. The user
on being told it would learn worse: *"yeah I said it would learn worse. duh."*
