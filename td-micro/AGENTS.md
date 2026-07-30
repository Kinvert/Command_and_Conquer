# TD Micro Engineering Rules
`SPEC.md` is authoritative. TD Micro is a deterministic, headless Zig simulator for the restricted
Tiberian Dawn ruleset, with Vanilla-Conquer as the behavioral oracle and deployment engine.

- ABI14 includes Power, Refinery, bundled Harvester, Tiberium depletion/delivery, Barracks, E1,
  and E3, with the compact 2,456-byte observation and sweepable ABI9 single-actor or ABI14 group
  actions. CNC25 selects ABI14 and observation version 6. H5 deterministically mixes MCV-only and
  symmetric 3-E1/3-E3 Unit Count 6 starts. Fixed force evaluation is 50/50; reverse training ramps
  force starts from 25% to 75% on a decision clock independent of H0-H5 profile progression.
- CNC25 independently ramps requested opponent difficulty from 90% Easy / 10% Normal to 10% Easy /
  90% Normal. Westwood's multiplayer handicap enum is inverted: requested Easy maps to internal
  `DIFF_HARD`, Normal to `DIFF_NORMAL`, and Hard to `DIFF_EASY`. Only H5 full matches enter the
  per-difficulty objective. Hard is parity-tested but not sampled in CNC25 training. Do not add
  other vehicles or far-spawn work without a new scoped goal.
- Model simulation as `step(World, Action) -> World`.
- Keep the hot path allocation-free, pointer-free, and free of I/O, rendering, audio, and callbacks.
- Keep exact placement masks row-bitset based. Never restore a per-decision 64x64 scalar placement
  scan for a completed structure queue.
- Use fixed-capacity state and stable integer handles. Capacity overflow is an explicit failure.
- Require repeatability: the same ruleset, seed, initial state, and ordered actions produce the same
  state hashes and terminal result.
- Use Vanilla as the behavioral oracle for supported mechanics. Determinism requires identical state
  evolution for a fixed ruleset, seed, initial state, and ordered actions; it does not require
  wall-clock pacing, render throttles, or exact stock AI event frames.
- Author rules in `rules/td_micro_v1.json`; generated Zig/C files must identify that exact manifest.
- Add a failing test before each supported behavior, then compare it with a focused Vanilla fixture.
- Hash explicit canonical fields, never raw struct memory.
- Benchmark ReleaseFast with an exact step definition. Do not report subsystem ticks as PufferLib SPS.
- Treat a sampled masked action rejected by `input.apply` as an ABI invariant failure in the
  ABI10-ABI14 exact-action paths. ABI13 must keep one complete semantic command in one Puffer
  transition; ABI14 must validate and apply its selected group in one transition. Neither path may
  use `--slowly`. `TASK-3B` is the only scoped exception: its isolated ABI9 experiment deliberately
  measures rejected tuples as four-frame no-ops.
- Unsupported objects, commands, and missions fail visibly; never silently fall back to approximate logic.
- Preserve the retained ABI-6 champion artifacts and ABI-8 through ABI-14 checkpoints. ABI13 and
  ABI14 are intentional action/checkpoint breaks; old checkpoints remain historical artifacts
  rather than being silently loaded. Observation version 6 keeps the 2,456-byte shape but assigns
  global byte 33 to requested difficulty, so CNC25 trains fresh instead of treating an older
  checkpoint as difficulty-aware.
- Consult the local architecture and profiling documents for implementation decisions.
