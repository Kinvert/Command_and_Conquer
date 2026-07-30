# Deterministic Full-Match Starting Force

Date: 2026-07-23

Status: implemented and validated in Zig, the Puffer C ABI, and the real Vanilla multiplayer
startup path. CNC22 used its previously loaded MCV-only binary and is not part of this changed
domain.

## Contract

H5/full-match episodes can start each GDI side with a reduced Unit Count 6 force:

```text
3 E1 Minigunners + 3 E3 Rocket Soldiers per side
```

The remaining starts use one MCV per side with no infantry. H0-H4 authored curriculum starts are
unchanged. Starting infantry are legal idle guards placed symmetrically in deterministic rings
around each MCV, facing the opposing start.

The fixed H5 evaluator keeps an exact 50/50 assignment, independent of spawn and starting credits:

```text
slot = (61 * (lane mod 100) + 47 * episode_ordinal + 17) mod 100
starting_force = UnitCount6 if slot < 50 else MCVOnly
```

This gives exactly 50 force starts per 100 episodes for every lane. Across one 100-lane block it
also gives 25 close-force, 25 close-MCV, 25 medium-force, and 25 medium-MCV starts. It consumes no
mutable gameplay RNG. Across the shared 100-lane by 100-episode period, the force axis splits both
the constrained-credit and random-credit populations exactly in half.

Reverse-curriculum training uses the same slot but ramps its threshold linearly from 25% to 75%
on an independent per-lane decision clock:

```text
H phase = min(5, curriculum_decisions / curriculum_stage_decisions)
ramp_decisions = starting_force_ramp_decisions
elapsed = min(curriculum_decisions, ramp_decisions)
force_percent = 25 + floor(50 * elapsed / ramp_decisions)
starting_force = UnitCount6 if slot < force_percent else MCVOnly
```

`curriculum_stage_decisions` controls only the H0-H5 profile schedule.
`starting_force_ramp_decisions` controls only the force threshold. CNC23 sweeps the latter over
2,048, 4,096, 8,192, and 12,288 decisions per lane. With the default 4,096-decision H phase, those
finish halfway through phase 0, at the end of phase 0, at the end of phase 1, and at the end of phase
2. The default is 8,192. No mutable performance-triggered state is used. A repeated
seed/lane/episode/progress/config tuple therefore selects the same start. The final training domain
retains a permanent 25% MCV-only share so rushing remains a legitimate conditional strategy.

The manifest is schema 9 with SHA-256:

```text
a776dac1f17d141e7f29d7cc596a172331b732aedf5976a4d0bee21af8c44b57
```

## Why This Roster

Stock TD Unit Count 6 at tech level 7 creates roughly four vehicles and two infantry. TD Micro does
not yet support the stock vehicle roster, so silently enabling tanks, Humvees, APCs, or MLRS units
would violate the reduced ruleset. The setting therefore keeps the stock six-units-per-side
meaning while substituting the complete currently supported combat roster, split evenly between
E1 and E3.

This is intended to prevent every episode from being solved by an undefended MCV rush. It does not
remove rushes: fixed evaluation remains 50% MCV-only, and the final training distribution remains
25% MCV-only. The policy must learn when a rush is appropriate and when an existing army must be
fought or defended against.

## Reward And Metric Semantics

- Starting units are not counted as units built.
- Their E1/E3 milestone bits are preseeded, so setup grants no production or milestone reward.
- Infantry trained later still earns the normal per-unit production reward.
- Later kills and losses involving those units are ordinary combat events.
- `perf` remains aggregate H5 win rate.
- `balanced_perf` is now the equal mean of four H5 rates:
  close/MCV, close/force, medium/MCV, and medium/force.
- Live telemetry exports those four rates plus `starting_force_episode_share`.
- The fixed evaluator additionally records all 16 spawn x force x credit-band cells and computes
  credit-balanced and harmonic-robust promotion scores from those cells.

The native binding exports 25 fields, with Puffer appending `env/n`; this remains below the
31-field project limit.

## Vanilla Path

TD Micro uses TD's existing `MPlayerUnitCount` startup value:

- the human skirmish screen retains the stock bases-on default of 6;
- policy auto-start accepts `TD_MICRO_STARTING_UNITS=0` or `6`;
- the Remastered multiplayer API accepts only 0 or 6 for TD Micro;
- non-TD-Micro Vanilla games retain the original stock unit creation path.

For TD Micro count 6, Vanilla suppresses unsupported stock vehicles and creates the same ordered
E1/E3 package as Zig after both MCVs exist. Vanilla's deliberate post-scenario gameplay RNG reset is
mirrored by preserving the pre-force RNG in Zig.

The autonomous opening was recorded twice through 256 decisions:

```bash
tools/td_micro_oracle \
  --output /tmp/vanilla_seed1_starting_force.jsonl \
  --seed 1 --decisions 256 --write-every 1 --unit-count 6
```

Both fresh processes produced the exact fixture SHA-256:

```text
1500d9b05f2e392397fd625e194deed4640fec6847c156778db18ceb4ccb5d9f
```

The reset record contains 2 MCVs and 12 infantry. Its two-line reset prefix remains
`723e276d8c88182d4f954aa1149cb9cd557efab57fbd3e48ca3bb07165980005`.
The Zig differential test advances the same no-op policy through all 256 decisions and compares
players, autonomous AI commands and state, queues, entities, projectiles, Tiberium, and RNG at every
decision boundary through frame 1,024. This crosses the original AI's first infantry-production
start and release, attack trigger, six emitted hunt commands, and live infantry movement.

The longer trace found and now guards two ordering details that the reset-only fixture could not:

- starting infantry predate the deployed factories in Vanilla's global object list, so their
  mission RNG runs before later Barracks factory RNG;
- the policy-controlled human house has not entered Westwood's internal `IsStarted` state, so the
  Easy AI applies its stock minimum infantry cap of 10 without counting the player's starting six.

Two fresh `--unit-count 0` startup traces also matched exactly at
`5a40c129131eb2d4e2a681a6a4ba9d9e447562eece062aaf96fc68cbab578fd7` and contained only the two
MCVs.

## Determinism And Compatibility

- All 198 Zig tests pass in Debug, ReleaseSafe, and ReleaseFast.
- The generated-rules check and real Vanilla oracle fixture pass.
- The standalone Puffer C ABI smoke passes with `episode_return=0.250 draw_rate=1`.
- Full-match snapshot version is 3, curriculum snapshot version is 6, and Puffer environment-state
  version is 4. The independent force-ramp duration is part of snapshot compatibility; older or
  differently configured environment-state files are intentionally rejected.
- Policy-only ABI9/ABI13 checkpoint tensor layouts are unchanged, but old policies were not trained
  on this starting-force domain and must not be treated as promoted policies for it.

The fixed-50 preflight and adjacent 25%-to-75% curriculum comparisons are recorded in
`cnc23_starting_force_preflight.md`. Existing CNC22 hyperparameters regressed on the changed
training distribution, so no ramp-trained policy is promoted from those checks; CNC23 must sweep
curriculum pace and learning hyperparameters on the new domain.
