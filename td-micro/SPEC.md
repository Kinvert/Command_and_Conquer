# TD Micro v1 Specification

Status: implemented through M6 plus compact observations, the Refinery/Harvester economy, ABI14
group actions, and a deterministic Easy-to-Normal difficulty curriculum; M7/M8 remain open

This document is the authority for a new restricted Tiberian Dawn training environment. The project
lives in `/home/claude/cnc/td-micro` and uses the existing repository for local version control. It
does not replace `zig-fast-core`, `cnc_build`, or Vanilla-Conquer until its own gates pass.

## 1. Product Statement

Train a PufferLib policy at high throughput in a small, deterministic Zig implementation of a
faithful Tiberian Dawn rules subset, then run that policy as a controller in the real
Vanilla-Conquer engine with the original graphics, assets, map, and match loop.

The first opponent is the original built-in GDI AI operating under the same restricted rules. The
Zig training environment contains a behavior-matched port of only the AI branches reachable by the
restricted game.

The public claim must remain precise:

> The policy was trained in a behavior-checked Zig implementation of TD Micro and deployed in the
> real open-source Tiberian Dawn engine under the same TD Micro ruleset.

It must not be described as training every sample in the original engine.

## 2. Goals

- Prove the complete loop first: train in Zig, load the policy in Vanilla, and run one restricted
  easy-mode skirmish without crashes or manual intervention.
- Preserve the supported TD mechanics exactly enough for policy transfer to Vanilla.
- Reach at least 50,000 valid aggregate PufferLib training SPS.
- Run the final trained policy in a visible, human-playable Vanilla match.
- Beat the restricted original easy GDI AI in held-out Vanilla matches.
- Keep the original Vanilla AI selectable; the policy is an alternate controller.
- Make every supported run deterministic and replayable from a seed plus ordered actions.
- Detect the first cross-engine divergence automatically.

### 2.1 First End-To-End Success

The first project success is intentionally modest:

1. Train a policy through PufferLib in the TD Micro Zig environment on one fixed map and a small
   seed set.
2. Load that exact checkpoint through the Vanilla controller adapter.
3. Let it play `td_micro_v1` GDI-versus-GDI against the original easy GDI AI.
4. Run to the declared timeout or a legitimate Vanilla terminal without human commands after match
   start, crashes, schema errors, or controller fallback.
5. Record evidence that model outputs crossed the adapter and at least one legal non-noop command
   changed real Vanilla simulation state.

This proves the observation, action, simulation, training, model export, inference, and real-game
integration path. It is not yet a generalization or policy-quality claim. M6 achieved this gate on
2026-07-14; exact evidence is in `docs/td_micro/m6_visible_policy_transfer.md`. Broader trace
coverage, throughput hardening, held-out evaluation, winning, normal difficulty, hard difficulty,
and a larger ruleset come afterward.

## 3. Non-Goals For v1

- Full Tiberian Dawn compatibility.
- Campaign missions or scripted campaign triggers.
- NOD, vehicles other than the initial MCV and bundled Harvester, aircraft, or naval units.
- Weapons Factories, vehicle production, defenses, walls, repair, selling, or superweapons.
- Pixel observations or mouse/keyboard imitation.
- Rendering or audio in the Zig simulator.
- CUDA simulation before a CPU batch profile identifies a suitable kernel.
- Rewriting isolated Vanilla leaf functions for small percentage gains.

## 4. Repository And Branch Strategy

Use the existing `/home/claude/cnc` Git repository. Do not add submodules or a remote requirement.

Recommended local branch:

```text
td-micro-v1
```

Create this branch from the pristine source-import commit `fde281808225aa6c9d452f9b7d1d180bf249bb95`,
not from the current performance-experiment HEAD. That import contains Vanilla-Conquer revision
`7f351daed0c19d7c4764dc4ebae1a70c7809ac1f`. As the first source-bootstrap change, refresh only the
Vanilla-Conquer snapshot to pinned upstream `vanilla` revision
`75526cbd4cbb6cca789f94b6f6abe00100ce7777`, the upstream head fetched on 2026-07-13. Review and record
the full old-to-new diff before accepting it. Preserve the existing `master` history as an archive,
but do not copy its C++/Zig performance patches into the new branch.

The current dirty experimental changes may be discarded before switching branches. Preserve this
specification outside that cleanup, then add it as the first TD Micro documentation commit.

### 4.1 Pristine Engine Baseline

"Pristine Vanilla" means an exact, reproducible upstream source revision, not the current directory
with experimental features disabled:

1. Start with the pinned fresh Vanilla-Conquer revision above and verify it exactly matches upstream.
2. Build `VanillaTD` without TD Micro, headless, profiling, or Zig modifications.
3. Run a human-play skirmish smoke test with the known-good local game data.
4. Record the executable hash, source revision, toolchain, data fingerprint, and smoke-test result.
5. If it fails, add the smallest separately reviewed portability/data compatibility patch and repeat
   the smoke test. Do not restore an old patch wholesale.

No simulation, balance, AI, timing, or performance modification is allowed in this baseline. TD
Micro restrictions and controller hooks are a distinct patch layer on top of it. With the ruleset
disabled, a regression test must continue to match the pristine baseline.

### 4.2 Source Authority

Use the three local source snapshots for different purposes:

| Source | Pinned revision | Role |
| --- | --- | --- |
| Official original Tiberian Dawn | `e0d372dc582c053a699114942b984dad0457f9b3` | Original Westwood/EA algorithms, data definitions, and historical intent |
| Vanilla-Conquer | `75526cbd4cbb6cca789f94b6f6abe00100ce7777` | Buildable Linux behavioral oracle and final graphical deployment |
| Official Remastered Collection | `f1f0d42bc2dcd06d5d1df943c6150ab34bf307ae` | Secondary reference for the exported state/command API |

The official original TD source is not the executable oracle because its own README says the source
drop does not fully compile, omits core engine libraries, and requires DirectX 5 plus Watcom/TASM/MASM
era dependencies. We did not reject a working official build; no complete supported build target was
provided. Restoring that toolchain would be a separate preservation project and would not solve
Linux state export, deterministic tracing, or batched PufferLib integration.

When original TD and Vanilla behavior differ, document the difference. Because the trained policy
deploys inside Vanilla, the v1 Zig simulator matches the pinned pristine Vanilla behavior, while the
official source is used to catch and explain unintended modernization. An original C&C Gold binary
may be used for manual black-box smoke comparisons, but it is not suitable as the primary parity
oracle because it cannot directly export canonical internal state and RNG traces.

Planned layout:

```text
td-micro/
  SPEC.md
  AGENTS.md
  build.zig
  build.zig.zon
  rules/
    td_micro_v1.json
  generated/
    td_micro_v1.h
    td_micro_v1.zig
  src/
    state.zig
    rules.zig
    input.zig
    step.zig
    production.zig
    movement.zig
    combat.zig
    ai.zig
    observe.zig
    digest.zig
    replay.zig
    batch.zig
    c_api.zig
  tests/
    rules_test.zig
    production_test.zig
    movement_test.zig
    combat_test.zig
    ai_test.zig
    replay_test.zig
    fixtures/
PufferLib/ocean/cnc_micro/
tools/td_micro_oracle.cpp
docs/td_micro/
```

`zig-fast-core` remains a prototype and source of tested ABI ideas. TD Micro starts with a clean
state model and must not inherit its debug-completion macros or approximate harvesting behavior.

Commit at green subsystem boundaries. A useful sequence is specification, Vanilla restriction,
trace oracle, Zig production, movement, combat, AI, Puffer binding, and Vanilla policy inference.

## 5. TD Micro v1 Ruleset

Ruleset identifier:

```text
td_micro_v1
```

### 5.1 Match Configuration

| Setting | v1 value |
| --- | --- |
| Players | 2 |
| Houses | GDI versus GDI |
| Player side | Human or Puffer policy |
| Opponent | Original requested Easy/Normal GDI AI or its Zig behavior-matched port |
| Initial objects | 50% one MCV per side; 50% one MCV plus 3 E1 and 3 E3 per side |
| Initial credits | Deterministic 35% at 2,300; otherwise 2,400-10,000 in 100-credit increments |
| Bases | Enabled |
| Tiberium economy | Enabled: Refinery, bundled Harvester, depletion, docking, and income |
| Crates/goodies | Disabled |
| Superweapons | Disabled |
| Visceroids | Disabled |
| Victory | Normal TD structure-destruction victory |
| First map | Existing multiplayer scenario 1 |
| Spawn profiles | Close seed 1 and medium seed 2 |
| First parity seed set | `{1, 2}` |
| Playable coordinates | Map-local, at most 64x64 for v1 |
| Decision interval | 4 TD frames |
| Training timeout | 48,000 TD frames / 12,000 decisions |

ABI 7 added the first economy expansion without adding general vehicle production. ABI 8 changed
only reward configuration. ABI 9 changes observation version 4 to 5 and reduces the policy tensor
from 6,208 to 2,456 bytes by replacing the repeated full map with canonical dynamic Tiberium state.
ABI 10 retains that observation and replaces seven independent action heads with one four-token
conditional grammar sampled inside a single native CUDA/PPO transition.
ABI 11 retains the exact ABI10 environment action and mask grammar while replacing the dense
15,027-logit prefix decoder with 2,352 command-conditioned logits. It is a policy checkpoint break,
not a simulation, observation, reward, or action-transport change.
ABI 13 adds a bounded rank-4 selected-actor/candidate-target residual to the ABI11 decoder. It keeps
the same environment contract and exact masks but expands the policy projection to 4,912 logits.
ABI13 is a preserved experiment, not a promoted policy architecture: matched 2M learning remains
below the historical ABI9 seven-head baseline. ABI12 was an unretained unbounded prototype.
ABI 14 preserves the ABI9 heads and adds 64 command-gated binary infantry selectors so one attack
decision can command a group. Action scheme 0 selects ABI9 and scheme 1 selects ABI14; CNC25 pins
scheme 1. Observation version 6 retains the 2,456-byte tensor and records requested opponent
difficulty in global byte 33. Because older checkpoints saw that byte only as zero, CNC25 trains
fresh.
A Refinery costs 2,000 credits, includes one 1,400-credit Harvester, adds 1,000 storage, and uses the source-faithful
600-credit Refinery-only production time. Harvesters search the authored scenario Tiberium, follow
vehicle tracks, remove overlay steps, dock through the Refinery backup/unload/exit sequence, and
store 25 credits per unloaded step for the player or 33 for the multiplayer Easy AI. A full load is
28 steps. Tiberium extraction is limited to one step group every 15 TD frames.

The timeout is a temporary upper bound, not a draw strategy. A post-training audit of all 97
retained checkpoints from run `cmv6t21t` found that the prior 12,000-frame limit created false
draws: 94 resolved as losses by 30,000 frames and all 97 resolved by 48,000 frames. ABI 5 introduced
the 48,000-frame contract in Zig, C, Vanilla, and Puffer config, and ABI 6 retains it. See
`docs/td_micro/learning_blockers_and_next_step.md`.

Under `td_micro_v1`, only the two participating houses receive `HouseClass::AI` updates. Vanilla
keeps its original AI implementation. The Zig port must be deterministic
for a fixed ruleset, seed, initial state, and ordered action stream. Vanilla is the behavioral oracle
for supported mechanics, but wall-clock pacing, render throttling, and exact historical AI event
frames are not independent requirements.

The authored manifest declares two valid scenario-1 starts. Seed 1 is the close pairing from player
waypoint 0 `(2,8)` to opponent waypoint 1 `(15,1)`. Seed 2 is the medium pairing from player
waypoint 0 `(2,8)` to opponent waypoint 3 `(37,23)`. Puffer vector initialization alternates these
profile seeds by global agent ordinal. A 64-agent run therefore starts exactly 32 close and 32
medium worlds. Each agent retains its assigned profile across episode resets. Completed-episode
shares need not remain 50/50 because episode lengths differ.

Schema 9 adds an independent deterministic full-match starting-force assignment. Fixed H5
evaluation retains the two-MCV opening in exactly half of episodes and gives each side a reduced
Unit Count 6 package of three E1 plus three E3 in the other half. Reverse training linearly ramps
the force-start threshold from 25% to 75% on an independent per-lane decision clock. H0-H4 authored
starts are unchanged. `curriculum_stage_decisions` controls only H-profile progression;
`starting_force_ramp_decisions` controls only the force threshold. The affine lane/episode
permutation consumes no gameplay RNG. Initial infantry do not count as production or milestone
rewards. Live `balanced_perf` equal-weights close/MCV, close/force, medium/MCV, and medium/force win
rates.

Schema 10 adds requested opponent difficulty without changing supported content, rewards, action
semantics, maps, or decision timing. Its independent decision clock ramps episode selection from
90% requested Easy / 10% requested Normal to 10% Easy / 90% Normal. Hard is representable and
parity-tested but is not sampled by CNC25. Only H5 full matches enter difficulty performance
counters. `easy_balanced_perf` and `normal_balanced_perf` each equal-weight the four spawn x
starting-force cells; the CNC25 sweep objective is their equal-weight mean.

The dedicated Vanilla setup accepts only `MPlayerUnitCount=0` or `6`. Count 0 creates one MCV per
side; count 6 substitutes the supported symmetric E1/E3 package for TD's unsupported stock vehicle
mix. Policy auto-start selects it with `TD_MICRO_STARTING_UNITS=0|6`, while the human skirmish
screen retains the normal bases-on default of 6.

The current multiplayer API does not apply `CNC_Set_Difficulty`; that function only handles normal
campaign games. TD Micro setup explicitly applies the requested multiplayer difficulty after player
initialization and exports both the requested value and assigned internal value in oracle state.
Westwood's skirmish mapping is inverted: requested Easy assigns internal `DIFF_HARD`, requested
Normal assigns `DIFF_NORMAL`, and requested Hard assigns `DIFF_EASY`.

The Remastered-style build uses a 128x128 internal `MEGAMAPS` grid. TD Micro v1 uses coordinates
relative to the selected map's playable origin and requires its playable width and height to be at
most 64. M1 must verify scenario 1 satisfies this before it becomes a fixture. If it does not, select
a qualifying existing multiplayer map and update this table; do not truncate the map.

### 5.2 Allowed Content

Initial-only unit:

- MCV, which may only deploy into a Construction Yard.

Buildings:

- Construction Yard.
- Power Plant.
- Barracks.
- Refinery.

Economy unit:

- Harvester, created only as the bundled unit from an operational Refinery.

Trainable infantry:

- E1 Minigunner.
- E3 Rocket Soldier.

All costs, build times, power values, prerequisites, footprints, health, armor, speed, weapon range,
damage, warhead effects, reload time, facing, mission transitions, and death behavior come from the
same TD source revision used by Vanilla. The shared manifest records the values and their source
symbols; it does not invent balance values.

TD Micro disables random crew survivors from destroyed vehicles and buildings. Vanilla may spawn
C1/C7 civilians or other infantry from those paths, which would violate the declared E1/E3-only
content set and introduce unrelated survivor behavior. Destruction damage, removal, kill credit,
and defeat behavior otherwise remain source-faithful. This restriction is inactive outside TD Micro.

Every other object type is unsupported. It must be rejected by Vanilla's ruleset layer and produce
an explicit `unsupported_content` failure if reached in Zig or an oracle trace.

### 5.3 One Restriction Layer

Vanilla exposes one ruleset selection, not a collection of optimization environment variables:

```ini
[TDMicro]
Ruleset=td_micro_v1
OpponentBrain=OriginalAI
PolicyPath=
```

`OpponentBrain` may later be `PufferPolicy`. `Ruleset` is the only switch that changes gameplay
content.

The restriction layer must apply to:

- human sidebar entries;
- `HouseClass::Can_Build` before the computer-player early return;
- AI build and production candidate selection;
- construction and infantry production requests;
- scenario and multiplayer starting-object creation;
- transformable terrain and nonparticipant-house simulation;
- debug/API command validation;
- captures or scripted spawns if any become reachable; and
- a per-tick active-object validation scan in parity/debug builds.

The original AI logic remains unchanged except that disallowed candidates do not exist. If the AI
cannot complete a match under this allowlist, fix the general candidate filtering path or revise the
declared ruleset. Do not add hidden special-case strategy to make the AI look competent.

## 6. Shared Rules Manifest

`td-micro/rules/td_micro_v1.json` is the single authored ruleset description. A generator produces:

- `generated/td_micro_v1.h` for Vanilla and oracle code;
- `generated/td_micro_v1.zig` for the simulator;
- stable type ids used by observations, actions, and replay records; and
- a canonical ruleset hash embedded in traces, policies, and binaries.

Generated files are committed so changes are reviewable. CI/tests regenerate them and fail on a
diff. Vanilla and Zig refuse to load a replay or policy with a different ruleset hash.

The manifest contains only supported values and references to their original TD definitions. An
extraction test checks the generated values against the compiled Vanilla source tables.

## 7. Simulation Model

The canonical model is:

```text
step(State, Input) -> State
```

All nondeterminism enters through the initial seed and ordered input stream. No wall clock, OS RNG,
I/O, allocator, tracing, rendering, or callbacks are allowed on the hot step path.

The initial target is x86_64 ReleaseFast equivalence with the current Vanilla build. Cross-architecture
equivalence is a later gate.

### 7.1 State Ownership

Zig owns the complete supported simulation state:

```text
World
  frame
  setup_seed
  spawn_bucket
  starting_force
  rng_state
  players[2]
  map[64 * 64]
  tiberium_steps[64 * 64]
  units[MAX_UNITS]
  buildings[MAX_BUILDINGS]
  infantry[MAX_INFANTRY]
  projectiles[MAX_PROJECTILES]
  production_queues[2]
  original_ai_state[1]
  terminal_state
```

Use fixed-capacity, pointer-free arrays and stable integer handles. The hot representation is
structure-of-arrays where it benefits full-system loops. No entity or component allocation occurs
after reset.

Initial capacity targets:

| State | Capacity |
| --- | ---: |
| Units | 16 total |
| Buildings | 64 total |
| Infantry | 128 total |
| Projectiles | 256 total |
| Production queues | 2 per player: structures and infantry |

Capacity overflow is a terminal implementation error in tests and an invalid environment in
training. It must never silently drop an entity.

The batch environment reclaims completed infantry death-animation entries at decision boundaries,
preserving active order and remapping infantry/projectile references. Destroyed Harvester slots
above the two reserved MCV slots are also reclaimed after loss metrics are recorded. This prevents
legal long matches from exhausting append-only lifetime slots while preserving the canonical MCV
ids used by the Vanilla adapter.

### 7.2 Ordering And RNG

Preserve TD's update and RNG-call order for supported behavior. Do not replace the original mutable
RNG stream with a keyed RNG while exact parity is required.

Every collection with behaviorally visible iteration has a specified stable order. Spawned entities
receive a canonical id based on owner, category, and spawn ordinal. Digests serialize by canonical id,
not by pointer, heap slot, or hash-map order.

### 7.3 Batch API

The performance API steps many worlds per call:

```c
void td_micro_reset_batch(TdMicroBatch* batch, const uint64_t* seeds, uint32_t count);
void td_micro_step_batch(
    TdMicroBatch* batch,
    const TdMicroAction* actions,
    uint8_t* observations,
    uint8_t* action_masks,
    float* rewards,
    uint8_t* terminals,
    uint32_t count);
```

PufferLib must not call Zig once per entity or marshal through Vanilla structures. Worlds,
observations, masks, rewards, and terminals are contiguous across environments.

## 8. Player Action Contract

One policy controls one RTS player. Units are not separate agents.

One action may issue one command, after which the simulator advances four TD frames. ABI 13 stores
the complete action as four categorical bytes: `command`, `arg0`, `arg1`, and `arg2`. The command
domain has 12 values; each argument domain has 65 values, where `64` is canonical `PAD`.

| Command | Four-token grammar |
| --- | --- |
| noop | `noop, PAD, PAD, PAD` |
| deploy | `deploy, actor, PAD, PAD` |
| start_build | `start_build, product, PAD, PAD` |
| place | `place, x, y, PAD` |
| train | `train, product, PAD, PAD` |
| move | `move, actor, x, y` |
| attack | `attack, actor, enemy_slot, PAD` |
| harvest | `harvest, actor, x, y` |
| return_cargo | `return_cargo, actor, refinery_slot, PAD` |

`guard`, `stop`, and `hunt` retain stable command ids but are not enabled in this ruleset. Placement
derives the product from the completed structure queue, so impossible queue/product combinations
cannot be sampled.

Command semantics are state-level TD commands, not UI clicks. Vanilla and Zig translate this exact
contract into their native mission, production, placement, and targeting operations.

Zig exports exact prefix masks as a 9,242-bit packed table. CUDA samples command, then each argument
conditioned on the selected prefix, inside one fused sampler call with no host synchronization.
Placement and harvest use conditional `y|x` rows; actor/target branches use command- and
actor-conditioned logits. PPO reconstructs the same stored prefix, sums only active conditional
log-probabilities and entropies, and gives canonical PAD heads zero gradient. Every completed masked
sequence must be accepted by `input.apply`; rejection is an ABI invariant failure. Malformed
externally submitted tuples remain deterministic no-ops with an `invalid_action` diagnostic.

## 9. Observation Contract

TD Micro v1 uses AI-style structured simulation state. The policy receives all active supported
objects for both participants and a fully visible supported map, but never raw C++ pointers,
renderer state, or the original AI controller's private timers, build choices, or RNG bookkeeping.
This is an intentionally fully observable first task, not a fog-of-war claim.

Observation groups:

- global frame fraction, credits, power produced/drained, defeat flags, and production state;
- player/opponent stored Tiberium, capacity, cumulative harvested credits, and total map Tiberium;
- scenario id and one packed byte for each of the 344 authored Tiberium cells in canonical row-major
  order;
- fixed own-building and own-infantry slots;
- fixed enemy building and infantry slots;
- per-entity type, canonical id, position, health, facing, mission, target, cooldown, and selection mask;
- Harvester cargo fraction, mission status, movement, harvesting, and harvest-timer state;
- current legal-action context.

Slot ordering is deterministic by category, canonical id, and owner. Missing slots are zero with an
explicit presence bit. Numeric encoding and normalization are versioned with the ruleset hash.

ABI 9 removes static terrain and occupancy from the per-decision tensor. Static terrain is fixed by
the scenario id, and dynamic occupancy is reconstructible from entity records and known footprints.
Each Tiberium byte preserves the corresponding ABI-8 packed value: `45` while present and `56` after
depletion. This keeps the prior input scale while reducing repeated transport and dense policy
weights. The 64-byte globals and both 1,024-byte entity regions are otherwise unchanged.

Uniform byte-to-`[0,1]` scaling remains a transfer-parity contract, not the intended final learning
representation. A later encoder should apply field-aware scaling, preserve booleans as `0/1`, and
represent categorical fields explicitly. Training and visible inference must use the same decoder
and remain byte-parity testable.

The original AI's private controller state belongs to the opponent controller and is not leaked into
the player's observation. Public simulation consequences such as enemy objects, health, missions,
and production-independent world state are observable.

## 10. Reward And Terminal Contract

The certified task reward is:

```text
+1.0 win
-1.0 loss
 0.0 timeout/draw
```

Final evaluation uses terminal reward only. Curriculum shaping may expose separate, named channels
for deploy, valid construction, production, damage, and invalid actions, but every channel must be
logged independently and annealed to zero before the transfer claim.

The current end-to-end curriculum applies these bounded shaping rewards:

| Event | Reward | Frequency |
| --- | ---: | --- |
| Deploy MCV / own first Construction Yard | `+0.2` | once per episode |
| Own first Power Plant | `+0.2` | once per episode |
| Own first Barracks | `+0.2` | once per episode |
| Own first E1 | `+0.2` | once per episode |
| Own first E3 | `+0.2` | once per episode |
| Own first Refinery and receive bundled Harvester | `+0.4` | once per episode |
| Own first Harvester | `0.0` | metric only; bundled with Refinery |
| Complete first Tiberium delivery | `+0.2` | once per episode |
| Player releases an E1 or E3 | `+0.03030131620399178` | first 10 per episode |
| Opponent loses an E1, E3, or MCV | `+0.0054265722298487366` | first 10 per episode |
| Opponent loses a supported building | `+0.7301079315055825` | first 3 per episode |
| Player earns harvested Tiberium | `+0.01` per 100 credits | first 5,000 credits per episode |
| Player-owned E1, E3, MCV, or Harvester dies | `0.0` | once per dead object slot |

The eight shaping coefficients are startup configuration in
`PufferLib/config/cnc_micro.ini`; the values above are the exact sampled values from W&B run
`cnc1/lqkwukxi` plus the economy defaults `reward_refinery=0.4`,
`reward_first_delivery=0.2`, and `reward_tiberium_income=0.01`. The ABI-8 economy sweep varies only
those three economy coefficients while keeping policy and optimizer settings fixed. Per-episode
caps and terminal rewards are fixed. Economy income shaping is computed from cumulative delivered
credits and does not alter simulation state or its canonical digest.

Completing all milestones does not terminate the episode. MCV deployment is not an infantry death
and receives no casualty penalty. On a terminal decision, the terminal result replaces that
decision's shaping reward, so the emitted terminal reward remains exactly `+1.0`, `-1.0`, or `0.0`.
There is no turn, no-op, pre-deployment, or invalid-action reward penalty. ABI 13's native sampler
must emit only executable masked sequences. Malformed tuples submitted through the public C ABI
remain diagnostic no-ops and still advance four TD frames; they are an integration failure, not a
training mechanism.

Terminal outcome comes from the same supported TD defeat rule in both engines. A side with no active
objects loses immediately. Under `DestroyStructures`, a side with infantry but no supported
non-wall building or MCV enters TD's 15-frame early-win countdown, then its survivors are destroyed
and the side loses. Startup failure, unsupported content, capacity overflow, and parity failure are
invalid runs, not draws or losses.

The training task also has explicit anti-degenerate death terminals:

| Condition | Terminal reward | Named counter |
| --- | ---: | --- |
| More than 16 active player-owned buildings | `-1.0` | `building_limit_losses` |
| More than 64 active player-owned infantry | `-1.0` | `infantry_limit_losses` |

The invalid-action-streak terminal is disabled. Its legacy counter remains in low-level batch stats,
but ABI 6 no longer exports it as a Puffer log metric. These soft task limits are distinct from the
simulator's fixed storage capacities: capacity overflow remains an invalid engine run and must never
be reported as a policy loss.

### 10.1 Training Curriculum

The curriculum changes reset states and reward shaping, not the ruleset or simulation mechanics:

1. Deploy the MCV and complete a legal Power Plant/Barracks opening.
2. Build a Refinery, receive the bundled Harvester, harvest/deplete Tiberium, and complete delivery.
3. Train E1/E3 and win short combat fixtures from prebuilt mirrored states.
4. Play full matches against scripted command traces and then the cloned easy AI.
5. Remove all shaping and train/evaluate full matches with terminal reward only.

Every stage retains the same observation and action schema. A policy promoted to the next stage must
continue to pass the previous stage's evaluation fixtures.

H5 additionally mixes two symmetric openings: MCV-only and reduced Unit Count 6. Reverse training
ramps their mixture from 25% to 75% force starts on an independent decision clock; fixed evaluation
remains 50/50. Both remain full matches and enter terminal performance metrics. Promotion must
report all spawn x starting-force cells; credit-aware promotion further expands this to all 16
spawn x force x credit-band cells.

### 10.2 Current Certified Baseline

Source/config snapshot `1625e88` and retained checkpoint
`46695237efbb6d350971e1163a54c57877a897d487c2b9f7873f3b16dce275e7` are the current ABI-6
baseline. PufferLib run `cnc2/lwgwyjl7` trained from scratch on the balanced close/medium reset
mixture and finished 505/0/0 in its final evaluation, with zero start or engine failures. Fixed-seed
native traces replayed identically for one close and one medium win, and the same checkpoint won a
real medium-spawn Vanilla match.

This completes the current two-profile M6 quality path but does not close M8. Broad held-out Vanilla
evaluation, stronger opponent interaction, and the declared 90% held-out win-rate gate remain open.
The authoritative evidence is `docs/td_micro/lwgwyjl7_balanced_champion.md`.

ABI 7 changed the action decoder and observation semantics, so the ABI-6 checkpoint is preserved as
the champion artifact rather than silently loaded into the economy environment. The economy slice
has a valid training smoke and transfer-compatible Vanilla adapter, but no economy policy has yet
been promoted over the retained champion. ABI 8 changes reward configuration only; ABI-7 policy
weights remain tensor-compatible because observation/action dimensions are unchanged. ABI 9 is an
intentional observation tensor break: older checkpoints fail exact-size validation and policies
must be retrained with the 2,456-byte input. ABI 10 is a second intentional checkpoint break: it
retains the observation but changes action transport and the conditional decoder, so all ABI-9
checkpoints remain historical artifacts.
ABI 11 is a third intentional checkpoint break. It retains ABI10's environment action transport
and exact masks but changes the policy projection layout; ABI10 checkpoints remain historical
artifacts and must fail exact-size validation rather than load silently.
ABI 13 is a fourth intentional checkpoint break. It retains ABI11 transport and masks but adds
bounded actor-query and target-key rows. ABI11/ABI12 checkpoints must fail exact-size validation.
The implementation is retained for research and transfer testing; it is not evidence that ABI13
should replace the stronger historical ABI9 training baseline.

## 11. Original AI Clone

The goal is not a newly designed Zig opponent. It is a restricted port of the original built-in GDI
AI behavior reachable in TD Micro v1.

The AI work is split from simulation parity:

1. **Recorded-command mode:** Vanilla runs the original AI and records its authoritative commands.
   Zig replays commands from both sides. This validates simulation without requiring a Zig AI.
2. **AI decision mode:** Given equivalent canonical state, Vanilla and Zig independently produce the
   next AI command list. Commands and AI state digests are compared before either simulation advances.
3. **Closed-loop mode:** Both engines run their own restricted AI and the same player input stream.
   Per-tick state and command digests must remain equal through terminal.

Reachable AI state includes build-choice timers, quantities, money/power checks, team/mission state,
difficulty values, enemy selection, and every RNG draw used by those branches. Any hidden state that
changes an emitted command must be added to the canonical AI digest.

The first AI gate was requested Easy. CNC25 adds deterministic requested Easy/Normal selection as
schema 10. Requested Hard remains a fixed parity-test mode and is not sampled in CNC25 training.
Difficulty is explicit versioned state, never untracked runtime variation.

## 12. Oracle Trace And Determinism

Vanilla is the behavioral oracle. The oracle tool records a versioned binary trace and can emit a
human-readable JSON diff.

```text
TraceHeader
  schema_version
  ruleset_hash
  vanilla_commit
  zig_commit
  map_id
  seed
  decision_frames

TickRecord
  frame
  player_action
  original_ai_commands
  canonical_state_digest
  canonical_ai_digest
  rng_digest
  optional canonical fields for diagnostics
```

Canonical supported state includes:

- frame and RNG state/call count;
- credits, power, ownership, production queues, and build progress;
- all supported map occupancy and shroud state;
- every supported entity's canonical id, type, owner, position, health, facing, mission, target,
  weapon cooldown, and lifecycle state;
- projectile state; and
- terminal outcome.

Do not compare raw C++ and Zig memory. Both engines serialize the same explicit schema and hash those
bytes. A mismatch report names the first frame, entity/field, expected value, and actual value.

Required trace corpus:

- MCV deploy success and failure cases;
- power and barracks production/placement legality;
- Refinery production/placement, bundled Harvester creation, vehicle movement, Tiberium search and
  depletion, docking/unloading, and both player/AI income rates;
- E1 and E3 production and spawn placement;
- straight movement, turns, obstacle routing, congestion, and unreachable targets;
- E1 versus E1, E3 versus E1, E1 versus E3, and mixed squads;
- target acquisition, explicit attack, guard, stop, projectile impact, death, and building destruction;
- original AI opening with no player commands;
- scripted pressure against the original AI;
- full closed-loop matches; and
- randomized valid and invalid action fuzz traces.

The first end-to-end milestone needs only the reset/opening traces, focused production/movement/combat
fixtures, and one complete fixed-map closed-loop trace. The full corpus above is required before the
certified throughput and held-out transfer claims, not before the first visible easy-mode policy run.

Determinism gates:

- repeated Vanilla runs produce identical canonical digest streams;
- repeated Zig runs produce identical canonical digest streams;
- Debug, ReleaseSafe, and ReleaseFast Zig runs match;
- scalar and batch Zig paths match; and
- Vanilla and Zig match for every certified trace.

## 13. Test-Driven Development Rules

For each subsystem:

1. Add or extract a focused Vanilla fixture.
2. Write a failing Zig unit/property test.
3. Implement only the supported behavior.
4. Run the focused test and full Zig suite.
5. Run the matching differential trace and locate the first divergence.
6. Run the fixed workload benchmark.
7. Document command, hashes, SPS, and conclusion before committing.

No subsystem is accepted because a human smoke test looked correct. Human play is required for the
Vanilla restriction and final integration gates, but canonical traces are the correctness gate.

## 14. PufferLib Integration

Create a new native environment:

```text
PufferLib/ocean/cnc_micro
```

Do not overload `cnc_build` with another backend/mode matrix. `cnc_micro` links the Zig C ABI and
owns contiguous batches directly. It does not use `dlopen`, `dlmopen`, an 8 MB scratch buffer, or a
Vanilla instance during normal training.

The serious benchmark command uses PufferLib's native GPU training path with:

- at least one hidden layer;
- fixed agents, buffers, threads, horizon, minibatch, and policy shape across A/B runs;
- `--train.gpus 1`;
- `start_failures=0`; and
- at least three repeated measurements after warmup.

One RL step includes action validation/application, four TD frames, original-AI step, observation,
mask, reward, terminal, reset when needed, vector synchronization, and policy training overhead.

Performance gates:

| Gate | Required result |
| --- | ---: |
| Raw full Zig decision step | at least 100,000 aggregate SPS |
| PufferLib GPU training | at least 50,000 aggregate SPS |
| Start failures | 0 |
| Unsupported-content/capacity failures | 0 |
| Certified trace parity | 100% |

Raw subsystem or one-frame microbenchmarks are diagnostics, not headline training SPS.

## 15. Vanilla Policy Deployment

Vanilla gains a controller adapter that runs the same observation encoder, action masks, decision
interval, and action translator used by `cnc_micro`.

Supported controller choices:

```ini
PlayerBrain=Human
PlayerBrain=PufferPolicy
OpponentBrain=OriginalAI
OpponentBrain=PufferPolicy
```

For the first automated visible transfer run, `PlayerBrain=PufferPolicy` controls the normally
human GDI slot while `OpponentBrain=OriginalAI` leaves the restricted Easy GDI opponent unchanged.
For the later human-versus-policy demonstration, these roles are reversed. Neither setting removes
or overwrites the original AI implementation.

The original AI path remains available. The policy adapter loads a versioned model only when its
ruleset, observation, action, and model schema hashes match the running game.

The visible deployment must use normal Vanilla rendering and assets. Inference may run through the
PufferNet C path or another measured native runtime, but it must not alter simulation time or expose
hidden state to the policy.

## 16. Milestones And Acceptance Gates

### M0: Repository Baseline

- Preserve the current `master` history, then discard its uncommitted experimental source changes.
- Create local branch `td-micro-v1` from clean import commit `fde2818`.
- Refresh only Vanilla-Conquer to pinned upstream revision `75526cbd` and review the complete delta.
- Add this specification and supporting strategy documentation as the first branch checkpoint.
- Verify the three pinned source revisions and record their tree hashes.
- Build and human-smoke pristine Vanilla before adding TD Micro behavior.
- Add `td-micro/AGENTS.md` derived from this spec.

### M1: Restricted Vanilla Match

- One ruleset selection enables TD Micro v1.
- Scenario 1 is verified to fit the declared map-local 64x64 limit, or the spec names a qualifying
  existing multiplayer map before fixtures are recorded.
- Both declared spawn profiles reset to the selected MCV-only or symmetric Unit Count 6 recipe and
  the declared deterministic starting-credit sample.
- The opponent house reports the internal handicap corresponding to requested difficulty after
  multiplayer initialization.
- Human can play GDI against restricted original easy GDI AI.
- Both sides can deploy, build power/refinery/barracks, harvest Tiberium, train E1/E3, fight, and terminate.
- The parity/debug active-object scan reports no disallowed object in a complete match.
- Ruleset disabled behaves exactly like the pinned pristine Vanilla baseline.

### M2: Oracle And Contract

- Shared generated manifest exists.
- Vanilla exports canonical state, AI command, AI state, and RNG digests.
- Repeated traces for every declared spawn seed match exactly.
- Field-level first-divergence report works.

### M3: Zig Production Slice

- Reset, MCV deploy, credits, power, Refinery/Harvester economy, barracks, placement, E1/E3
  production, and action masks match.
- Recorded-command traces through production match.
- Snapshot reset and batch/scalar determinism pass.

### M4: Zig Movement And Combat

- Occupancy, pathfinding, movement, targeting, weapons, projectiles, damage, death, and victory match.
- Scripted complete matches using recorded commands match through terminal.

### M5: Restricted Original AI Port

- Supported AI decisions and internal state match at declared fixture checkpoints. Exact wall-clock
  pacing and every historical stock timer frame are not independent requirements.
- Closed-loop no-player and scripted-player matches match through terminal.

### M6: First End-To-End Policy Run

- A PufferLib GPU run trains a checkpoint in Zig on the fixed first map and declared seed set.
- The checkpoint runs a complete timeout-or-terminal TD Micro episode against the cloned easy AI in Zig.
- The same checkpoint loads through the real Vanilla controller adapter without schema mismatch.
- It runs one visible Vanilla skirmish against the restricted original easy GDI AI to the declared
  timeout or a legitimate terminal without crashes, controller fallback, or unsupported content.
- Adapter telemetry proves at least one legal model command changed Vanilla simulation state.
- No human command is issued after the match starts.
- Exact source, ruleset, trace, model, and result hashes are recorded.

This is the first vertical-slice proof. It has no minimum SPS, win, or broad win-rate requirement.

### M7: Determinism And Throughput Hardening

- At least 100 randomized closed-loop traces pass without unsupported behavior.
- The complete certified trace corpus passes across required Zig build modes and scalar/batch paths.
- `cnc_micro` exceeds 50,000 valid PufferLib GPU SPS under a recorded fixed configuration.
- Curriculum reaches full terminal-reward matches.
- Checkpoint beats the Zig easy AI on held-out seeds.

### M8: Certified Real Vanilla Transfer

- The same checkpoint loads in Vanilla without schema mismatch.
- It wins at least 60% of 200 held-out matches against restricted original easy GDI AI.
- No unsupported behavior, startup failure, or ruleset violation occurs.
- A human-visible match demonstrates the original renderer and selectable opponent controller.

## 17. Expansion After v1

The first expansion, Refinery/Harvester/Tiberium economy, is implemented in ABI 7. Recommended next
order after its parity and policy-transfer evidence is retained:

1. Weapons Factory, Humvee, and Medium Tank.
2. Guard Tower and repair/sell.
3. Additional maps and broader deterministic spawn sets.
4. Complete Normal promotion, then add Hard to a later declared curriculum.
5. NOD and asymmetric matchups.

Each expansion bumps the ruleset/schema version and repeats parity, throughput, training, and real
Vanilla transfer gates. TD Micro v1 remains available as a permanent regression environment.

## 18. Failure Conditions

Stop and fix the architecture if any of these occur:

- Zig calls back into Vanilla per frame, entity, path probe, or AI decision during training.
- The ruleset is represented by scattered environment switches instead of one manifest/id.
- Unsupported behavior silently falls back or approximates.
- AI parity and simulation parity are tested only together, making divergence attribution ambiguous.
- A speed claim changes decision frames, agents, policy shape, or other benchmark semantics.
- A Puffer run has `start_failures > 0`.
- Final evaluation occurs only in Zig.
- The public demo cannot state exactly which TD mechanics are supported and excluded.
