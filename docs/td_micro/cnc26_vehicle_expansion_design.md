# CNC26 Vehicle Expansion Design (Weapons Factory / Humvee / Medium Tank)

Date: 2026-07-24

Status: design/scoping, written before implementation. This is the first `td-micro-cnc26`
worktree entry (branched from `td-micro-cnc25` at `e99542b`). CNC24 (`td-micro-v1`) and CNC25
(`td-micro-cnc25`) are untouched by this work.

## Goal

Per `td-micro/SPEC.md` section 17 ("Expansion After v1"), item 1: add the Weapons Factory
building and its two vehicles, Humvee and Medium Tank, as a new scoped ruleset expansion,
following the same TDD + Vanilla-oracle-parity discipline used for the Refinery/Harvester economy
(ABI7) and the CNC25 difficulty curriculum. This is a ruleset expansion first; a dedicated
curriculum stage that drills vehicle combat comes after the mechanic exists and has parity
evidence, mirroring how H0-H5 currently drill the existing infantry/economy roster.

## Ground truth from the real Vanilla-Conquer source

Pulled directly from `Vanilla-Conquer/tiberiandawn/{defines,udata,bdata}.cpp`, not guessed:

| Object | Internal name | Cost | Strength | Sight | Armor | Weapon | Move | Speed | ROT | Prereq |
| --- | --- | ---: | ---: | ---: | --- | --- | --- | --- | ---: | --- |
| Weapons Factory | `STRUCT_WEAP` / `"WEAP"` | 2000 | 200 | 3 | Aluminum | none | n/a | n/a | n/a | Refinery, build level 2 |
| Medium Tank | `UNIT_MTANK` / `"MTNK"` | 800 | 400 | 3 | Steel | `WEAPON_105MM` | Track | Medium | 5°/tick | none (build level 3) |
| Humvee (Jeep) | `UNIT_JEEP` / `"JEEP"` | 400 | 150 | 2 | Aluminum | `WEAPON_M60MG` | Wheel | Medium-fast | 10°/tick | none (build level 2) |

Weapons Factory: power drain 30 (no power generated), footprint `BSIZE_33` (3x3), factory type
producing `RTTI_UNITTYPE`. Both vehicles are turreted (`Is it equipped with a combat turret? =
true`), track-laying visual only for the tank, and the Medium Tank can squash infantry (Humvee
cannot). Neither is a transport. Both are `MISSION_HUNT` by default like the existing AI-controlled
roster.

Turret rotation is implemented in `Vanilla-Conquer/tiberiandawn/turret.cpp` (541 lines) /
`turret.h`/`facing.cpp`, confirmed by direct read:

- `TurretClass` holds `SecondaryFacing` (a `FacingClass`), independent of the body's
  `PrimaryFacing`. Both are 8-bit wraparound values (0-255 = one full rotation, not 0-31 or
  degrees).
- `FacingClass::Rotation_Adjust(rate)` (`facing.cpp:135`) is the exact formula to port:
  `diff = (signed char)(desired - current)` (wrapping subtraction gives the shortest rotation
  direction for free); if `abs(diff) < rate` snap to desired, else step `current +/- rate` in the
  sign of `diff`. `rate` is clamped to 127 (127 = instantaneous). This is pure 8-bit integer
  wraparound arithmetic — no floats, directly unit-testable in isolation.
- `TurretClass::AI()` (`turret.cpp:183`) calls `SecondaryFacing.Rotation_Adjust(Class->ROT + 1)`
  once per AI tick — i.e. the rate used is the unit's `ROT` stat **plus one** (Medium Tank ROT=5 ->
  rate 6; Humvee ROT=10 -> rate 11), not the raw stat value. Exact AI-tick cadence relative to
  td-micro's 4-frame decision interval still needs cross-checking against an oracle fixture, not
  assumed.
- When not tracking a target, the turret's desired facing reverts to the body's current facing
  (`SecondaryFacing.Set_Desired(PrimaryFacing.Current())`) — the turret "recenters" with the hull
  when idle, and independently tracks the target direction when attacking.

## Why this is more tractable than it first looked

The Zig fast core's `state.zig` already has a generic `Unit` struct (distinct from `Infantry` and
`Building`) used today for MCV and Harvester — both real stock TD vehicles. It already carries
track-based movement fields (`track_number`, `track_index`, `path`, `path_facing`, `speed`,
`movement_accum`) proven out by the existing Refinery/Harvester economy work. `rules.Armor` already
has `steel` and `aluminum` variants (used today by the existing infantry/building roster), and
`ObjectRule`/`ObjectType` are generated from `td-micro/rules/td_micro_v1.json` exactly like the
CNC25 difficulty handicap table was — the same `generate_rules.zig` pipeline applies.

What does **not** exist yet and is genuinely new work:

1. `Unit` has no combat fields. Infantry has `target: EntityRef`, `weapon_cooldown`, `ammo`,
   `firing`, `second_shot`; `Unit` has none of these. Both new vehicles are armed, so `Unit` needs
   these fields added (mirroring Infantry's existing shape, not inventing a new system).
2. `Unit` has a single `facing: u8` (body facing only). Both vehicles have an independently
   rotating turret, so a `turret_facing: u8` field plus rate-limited turret tracking (ported from
   `turret.cpp`) is new.
3. `QueueKind` only has `structure` and `infantry` (two production queues per owner). Weapons
   Factory needs a third, independent `unit` queue category, mirroring the existing two-queue
   pattern.
4. New `ObjectType` variants (`weapons_factory`, `medium_tank`, `humvee`) and their rule table rows
   in `td_micro_v1.json`, following the exact pattern of the CNC25 `difficulty_handicaps` array
   addition.
5. New Vanilla-Conquer oracle fixtures (Weapons Factory build + power drain, Medium Tank/Humvee
   production, movement including turret tracking, and combat with the 105mm/M60MG weapons)
   recorded and parity-checked exactly like the CNC25 difficulty fixtures were tonight.
6. Observation/action ABI: new entity kind slots, new action targets for building/producing at a
   second factory, updated action mask logic. Same shape of change as every prior ABI bump in this
   project (see `docs/td_micro/abi9`..`abi14` experiment docs), not a new category of change.

## Planned phase order (each phase: write failing tests first, then implement, then Vanilla parity
where applicable, then commit)

1. Ground-truth investigation (this doc) — done.
2. Read `turret.cpp`/`turret.h`/`facing.h` for the exact rotation-rate formula and lock-down
   behavior ("Must the turret be in a locked down position while moving?" is `false` for both, so
   turret can track a target independently of body movement).
3. Rules data: add `weapons_factory`, `medium_tank`, `humvee` to `td_micro_v1.json` and regenerate;
   unit test asserting the exact stats above (mirrors `rules_test.zig`'s existing pattern).
4. `Unit` struct: add combat fields (`target`, `weapon_cooldown`, `ammo`, `firing`) and
   `turret_facing`; extend `combat.zig` to let `Unit`-kind entities fight, reusing the existing
   armor-bias/weapon-resolution code paths already validated for infantry.
5. Weapons Factory building: placement, power drain, third (`unit`) production queue, prerequisite
   on Refinery — extending `production.zig` the same way the Barracks/Refinery queues already work.
6. Vehicle movement: track vs. wheel locomotion, turret-independent-of-body facing during
   move+attack — extending `movement.zig`.
7. Vanilla-Conquer oracle fixtures for build, movement (including turret tracking), and combat
   parity at both vehicles, recorded with `tools/record_td_micro_fixtures.sh` the same way as the
   CNC25 fixtures, with byte-identical double-record verification.
8. ABI/observation/action wiring, PufferLib binding updates, action mask updates.
9. New curriculum stage that specifically drills vehicle production/combat (naming and exact
   schedule id TBD once the mechanic itself is proven; likely analogous to how H0-H5 stages
   already work, not a new axis like CNC25's difficulty schedule).
10. Full deterministic suite (Debug/ReleaseSafe/ReleaseFast), C API smokes, a real CUDA smoke run,
    docs, and commit — same validation bar as the CNC25 difficulty work.

## Rule data status (task 8, done)

Added `weapons_factory` (id 9), `medium_tank` (id 10), `humvee` (id 11) to
`td-micro/rules/td_micro_v1.json` (schema bumped 10 -> 11) with a new TDD test
(`rules_test.zig`: "CNC26 vehicle expansion rule data matches real Vanilla stock stats") asserting
every field against the real Vanilla source. All fields are direct ground truth from
`udata.cpp`/`bdata.cpp`/`defines.h`'s `MPHType` enum (confirmed by exact match: Harvester's real
`MPH_MEDIUM_SLOW` speed constant, 12, equals its existing `max_speed: 12` JSON entry) **except
`weapons_factory`'s `construction_frames`/`ai_construction_frames: 58`**, which is inferred by
footprint analogy to the Refinery (identical `BSIZE_33` 3x3 footprint, also 58/58) rather than read
from a stat table — Vanilla's real construction-frame count is animation-driven, not present in any
stat table found so far. This must be verified against a real Vanilla oracle trace in task 12
(record a Weapons Factory build and check the actual frame count before `grand_opened` flips true);
if it differs, fix the JSON value there, not here.

Extending `combat.zig`'s three generic entity-lookup switches (`entityPosition`, `targetAlive`,
`entityCoord`) and the splash-damage-application switch in `takeDamage` to route
`medium_tank`/`humvee` through the existing `Unit`-backed paths (same as `mcv`/`harvester`) and
`weapons_factory` through the existing building paths was required for compilation (Zig's
exhaustive switches caught every unhandled case) and is generic entity plumbing, not combat
behavior — these three units still cannot fire yet; that is task 9.

## Weapon and turret status (task 9, in progress)

Weapon rules `105mm` and `m60mg` and the stock `rot`/`has_turret` object fields are in, schema
bumped 11 -> 12, all asserted against real source in `tests/vehicle_test.zig`. Findings:

- **`rot` and `has_turret` are independent.** MCV and Harvester both carry stock ROT 5 yet have no
  turret, so deriving one from the other would wrongly give them turrets.
- **Turret rate is `ROT + 1`.** From `TurretClass::AI`, not the raw stat: Medium Tank 6, Humvee 11.
- **Traveling non-homing projectiles are a real stock category.** The generator previously rejected
  any weapon with `projectile_speed != 0` and `turn_rate == 0`; `BULLET_APDS` (MPH_VERY_FAST, ROT 0)
  disproves that invariant, so the check was inverted to the one that actually holds (a
  non-traveling projectile cannot steer) rather than distorting the data to fit.
- **Warhead rows are shared, not duplicated.** `m60mg` carries WARHEAD_SA exactly like the M16, and
  `105mm` carries WARHEAD_AP exactly like the Dragon, so damage resolution reuses armor tables that
  were already validated against Vanilla.

`Unit` gained `target`, `turret_facing`, `weapon_cooldown`, and `firing`, appended after the
existing fields so the struct layout, and therefore every recorded snapshot, is undisturbed.
`combat.tickUnitTurrets` ports the turret half of `TurretClass::AI`: steer toward the target at
`ROT + 1`, and realign with the hull when there is no target.

Digest handling deserves a note. `digest.zig` hashes the new vehicle fields **only for units that
can carry a turret**. No turretless unit ever mutates them, so this keeps every digest recorded
before the vehicle expansion byte-identical while still putting the new state under determinism
checking wherever it actually exists. This is verified, not assumed: `digest_test.zig`'s hardcoded
`0fc9bb84...2117ed` opening digest still passes unchanged.

Firing is now implemented (task 9c):

- **`tickTravelingProjectile`** — `tickTow` and the new `tickApds` now share one routine
  parameterised by homing, instead of two copies that could drift. APDS flies its launch heading
  and never re-aims (`IsHoming` false, ROT 0). The existing E3 Dragon oracle fixtures still pass,
  which is real evidence the refactor preserved the validated TOW behaviour.
- **`canUnitFire`** — port of the turret arm of `TurretClass::Can_Fire`: neither vehicle carries a
  homing weapon, so both hold fire while the turret is still slewing, and the residual angle must
  be under 8 facing units.
- **`unitFireCoord`** — port of `TurretClass::Fire_Coord`: lift the centre coordinate north by
  0x30, then run out along the *turret* facing by the barrel length (Medium Tank 0xC0, Humvee
  0x30). Shells therefore leave the barrel tip, not the hull centre.

Needs oracle confirmation in task 12, flagged rather than assumed:

- Vehicle reload is set to the raw stock ROF. The infantry path adds `+3`, which is likely tied to
  infantry firing animation rather than `TechnoClass::Rearm_Delay`; the exact vehicle rearm timing
  must be read off a real trace.
- No firing scatter/inaccuracy is modelled for vehicles. Neither the 105mm nor the M60MG is an
  inaccurate weapon in stock TD, but this has not been confirmed against a trace.

## Weapons Factory and vehicle production status (task 10, done)

`QueueKind.unit` is a third, independent production queue (schema 12 -> 13), so vehicles build at
the Weapons Factory without blocking the Construction Yard or Barracks, matching stock TD's
separate factories. `start_build` routes by the product's category instead of assuming a structure;
this is purely additive, since a non-building product previously just failed `start`'s category
check. Infantry keep their own explicit `train` command.

Completed vehicles roll out via `weapons_factory_exits`, the stock `ExitWeap` list from
`bdata.cpp`, walked in order until an unoccupied in-bounds cell is found (preferred
`XYCELL(-1, 3)`).

The vehicle queue is hashed in the digest only once it holds something, for the same reason as the
turret fields: it cannot be non-empty without a Weapons Factory, so pre-expansion digests stay
byte-identical.

Needs oracle confirmation in task 12:

- Exit-cell *selection under contention*. The stock list order is ported exactly, but Vanilla's
  full notion of a blocked cell (terrain, reservations, other vehicles mid-move) is richer than the
  current unit/building occupancy check.
- The new vehicle's initial hull and turret facing after leaving the bay.

## Vehicle movement status (task 11, done)

This turned out to need far less new code than the plan assumed. `economy.zig` already contains a
complete, Vanilla-validated vehicle driving engine (`startMovement`, `advanceMovement`,
`smoothTurn`, track handling, path retries, scatter) built for the Harvester, which is itself a
real stock vehicle. It was only ever hardcoded in two places:
`rules.object(.harvester).?.max_speed`. Generalising those to `rules.object(unit.kind)` makes the
whole engine per-kind, and is a no-op for Harvesters, so the existing harvester oracle fixtures
still pass unchanged.

`assignMove` now accepts any drivable vehicle, and `tickCombatVehicles` gives combat vehicles their
own pass (move missions only, no harvest or docking). Keeping that pass separate leaves the
carefully ordered harvester sequence in `step.tickEasyAIFrameInto` exactly as it was validated.

Behavioural evidence, not just compilation: a Humvee (MPH_MEDIUM_FAST, 30) measurably reaches the
same destination in fewer frames than a Medium Tank (MPH_MEDIUM, 18), and a tank driving directly
away from an enemy keeps its turret on that enemy while the hull faces the other way.

Needs oracle confirmation in task 12:

- Track versus wheel locomotion is not yet distinguished. Both vehicles currently drive the
  Harvester's `SPEED_WHEEL`-derived track logic; stock TD gives the Medium Tank `SPEED_TRACK`.
  Whether that changes turn behaviour in the reduced ruleset must be read off a real trace rather
  than assumed either way.

## Vanilla oracle support status (task 12, in progress)

The C++ side can now drive the real engine: `Start_Structure`/`Place_Structure` accept
`STRUCT_WEAP`, a new `Build_Vehicle` orders `UNIT_MTANK`/`UNIT_JEEP` through `RTTI_UNITTYPE`,
`Move_Unit` accepts the combat vehicles, and the oracle exports `turret_facing`/`has_turret` from
Vanilla's `SecondaryFacing`. New oracle flags: `--weapons-factory-decision`,
`--place-weapons-factory-decision`, `--weapons-factory-x/y`, `--medium-tank-decision`,
`--humvee-decision`.

Getting there required fixing three separate gates, each found by the engine refusing rather than
by guessing:

1. **`Allows_Production`** — the restricted ruleset's may-build allowlist did not contain the new
   objects.
2. **`Allows_Object`** — a *separate* may-exist allowlist, which trips the content-violation guard
   and makes `CNC_TD_Micro_Get_Snapshot` return false. Unlike the production list this is not
   gated by side: once an object exists it is legal for either player to see or destroy.
3. **`Unit_Kind`/`Building_Kind`** — the oracle's type mappers returned `TD_MICRO_OBJECT_NONE` for
   the new types, which sets `AICommandOverflow` and fails the snapshot.

**Important scoping decision.** Vehicle and Weapons Factory production is gated to the human/policy
side (`Allows_Production` now takes `is_human`). Enabling them for the original AI measurably
destabilised it: the stock AI began ordering a Weapons Factory and the previously working
refinery-opening trace started failing at decision 130. The original AI has no validated vehicle
behaviour, and teaching it any would invalidate every recorded AI opening fixture. That is a
separate, deliberate piece of work, not a side effect of this one.

**Resolved: why the factory never finished.** Instrumenting `Abandon_Production` with `dladdr`
showed the caller was `BuildingClass::Detach_All` — the player's Construction Yard was being
*destroyed by the original AI* mid-build, which abandons its production. The recipe was simply too
slow: it was inherited from the harvesting fixture, which places the Refinery at decision 579. The
Refinery actually completes at decision 238, so the whole chain can run far earlier. The Weapons
Factory also builds noticeably slower than the equally priced Refinery, so it needs until roughly
decision 800 to complete. Placement is additionally subject to Vanilla's base-adjacency rule: cell
(2,9) works, (2,10) and (4,9) do not.

### Recorded fixtures

| Fixture | SHA-256 |
| --- | --- |
| `vanilla_seed1_weapons_factory.jsonl` | `49403833...710d0b2c` |
| `vanilla_seed1_medium_tank.jsonl` | `64699995...3c621be7` |
| `vanilla_seed1_humvee.jsonl` | `ff71f5bf...aba2c9a5` |

Each is double-recorded and byte-compared, as with every other fixture in this project.

The oracle emits `turret_facing` **only for turret-equipped entities**. That is deliberate: it
keeps all 40 pre-existing fixtures byte-identical in their simulation rows, which the project's
whole parity method depends on. This was verified rather than assumed — an initial unconditional
emission changed every historical fixture, and stripping just the new fields proved the simulation
itself was untouched.

### Vanilla ground truth, and what it already contradicts

- Humvee rolls out at cell offset `(-1, +3)` from the factory origin, which is exactly stock
  `ExitWeap`'s preferred cell and matches the Zig implementation.
- **Initial facing is wrong in the Zig side.** Vanilla gives a newly built Humvee hull 160 /
  turret 160, and the Medium Tank hull 159. `releaseCompletedUnit` currently hardcodes 128 for
  both hull and turret. This is a real, confirmed mismatch to fix, and is exactly the kind of thing
  the fixtures exist to catch.
- The Humvee completes at decision 960 versus the Medium Tank at 1060, consistent with 400 versus
  800 credits.
- Recorded strengths match stock exactly: Humvee 150, Medium Tank 400.

Still outstanding: a Zig-side parity test that replays these traces, and the remaining
"needs oracle confirmation" items (vehicle rearm timing, track versus wheel locomotion, exit-cell
contention).

## Explicit deferrals (documented per this project's "fail loudly, do not silently approximate"
rule, not silently skipped)

- Repair-facility interaction for these vehicles: deferred, not required for a first playable
  vehicle-combat curriculum stage.
- Infantry-squashing by the Medium Tank: real stock behavior, but deferred until basic move/build/
  combat parity is solid; will be called out explicitly if the curriculum stage ships without it.
- Any other stock unit type (APC, MLRS, other tanks): explicitly out of scope, per `SPEC.md`'s own
  "Expansion After v1" ordering (Weapons Factory/Humvee/Medium Tank is item 1 of that list).
