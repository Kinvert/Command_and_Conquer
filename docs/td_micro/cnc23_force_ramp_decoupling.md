# CNC23 Force-Ramp Clock Decoupling

Date: 2026-07-23

Status: implemented and validated; no learning result or speedup claim.

## Problem

The first defended-start implementation used:

```text
starting_force_ramp_decisions = 5 * curriculum_stage_decisions
```

Changing `curriculum_stage_decisions` therefore changed both the H0-H5 reset mixture and the
25%-75% defended-start ramp. The two adjacent CNC23 preflight runs could not identify which schedule
caused their learning difference.

## Contract

The clocks are now independent:

```text
H phase = min(5, curriculum_decisions / curriculum_stage_decisions)

elapsed = min(curriculum_decisions, starting_force_ramp_decisions)
force_percent = 25 + floor(50 * elapsed / starting_force_ramp_decisions)
```

- `curriculum_stage_decisions` affects only H-profile selection.
- `starting_force_ramp_decisions` affects only H5 MCV/force assignment.
- Both use deterministic per-lane policy-decision progress.
- H0-H4 authored states remain unchanged.
- Full-match evaluation ignores both clocks and remains exactly 50/50.
- The final training mix remains 75% Unit Count 6 and 25% MCV-only.

The CNC23 force-ramp sweep is:

| Ramp decisions per lane | Endpoint with default 4,096-decision H phases |
|---:|---|
| 2,048 | Midway through phase 0 |
| 4,096 | End of phase 0 |
| 8,192 | End of phase 1 |
| 12,288 | End of phase 2 |

The default is 8,192. The H-profile sweep remains
`256, 512, 1024, 2048, 4096, 8192, 16384`.

## Compatibility

The setting is carried through the Zig batch, public C API, native Puffer binding, INI loader, and
fixed evaluator. Curriculum snapshots include both clock durations and reject restoration into a
batch with a different force-ramp duration.

- TD Micro full-match snapshot: version 3, unchanged
- TD Micro curriculum snapshot: version 6
- Puffer environment state: version 4
- Policy checkpoint layout and action/observation ABI: unchanged

## Verification

The schedule test pins 25%, 50%, and 75% assignment at each ramp's start, midpoint, and endpoint.
It also proves that changing the H-stage duration by 10x changes H-profile selection. The
starting-force sampler does not receive the H-stage duration at all; it accepts only force-ramp
progress and its own duration.

Completed gates:

- full Zig suite passes in Debug, ReleaseSafe, and ReleaseFast;
- native Puffer CUDA extension rebuild passes;
- C binding smoke reports `episode_return=0.250 draw_rate=1`;
- all 10 fixed-evaluator tests pass;
- Puffer sweep parsing exposes both independent categorical parameters; and
- the existing Vanilla Unit Count 6 oracle fixture remains covered by the full Zig suite.

Two serial native runs used:

```bash
/tmp/td_micro_batch_benchmark_ramp 64 16384 1 4096 8192
```

Both completed 1,048,576 decisions with 305 episodes, 274 losses, 31 draws, zero failures, and:

```text
313a1df45e516e2fd36507459febd81a8fada2cdeab922f9162965049052e6b9
```

Their measured subsystem rates were 163,087 and 164,732 SPS. This is a repeatability check, not the
full PufferLib benchmark.

The valid native-CUDA smoke command used 64 agents, one buffer, four threads, horizon 32,
minibatch 2,048, one 64-wide MinGRU layer, and 131,072 total transitions. It finished at 56.7K
displayed SPS with `failures=0` and `start_failures=0`. A final rerun after the last internal API
tightening finished at 58.2K with the same validity fields. No throughput improvement is claimed; the
change removes an experimental confound.

## CNC23 Use

Protein should sweep both clocks while keeping ABI9, rewards, model family, vector shape, and
training budget in the declared CNC23 basin. Selection remains H5-only `balanced_perf`; promotion
still requires the fixed 50/50 evaluator and inspection of all spawn x force x credit cells.
