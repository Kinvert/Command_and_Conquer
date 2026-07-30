# TD Micro Infantry Prefix Loop Optimization

Date: 2026-07-17
Status: committed and verified natively; PufferLib A/B pending
Parent commit: `f3b5a1cce7b6db0241601643f8d9e266051cba92`
Implementation commit: `0ee9239fb043de6ef6900290b2cb41414a46c6f6`

## Result

Bounding four per-frame movement/combat loops to the populated infantry prefix improved the
static-map candidate from **113,094 to 132,038 SPS**, a **1.168x / 16.75%** speedup. Combined with
the compile-time static-map optimization, a direct original-versus-final A/B measured **74,551 to
136,579 SPS**, a **1.831x / 83.20%** gain.

Every measured run completed 320 episodes with zero failures and the same final-state digest:

`38cca1613d27fcaa4500c25261cff6ea19d838ccd80d9c91fec4d045d718ce28`

The `cnc5` sweep was active during all comparisons. Absolute rates are contended, but each result
uses alternating same-machine binaries under that contention.

## Change

`rules.max_infantry` reserves 128 slots, while `World.infantry_count` is the packed high-water mark
for populated slots. The Easy-AI frame path nevertheless visited all 128 slots in each of these
loops:

- movement's `moving_at_frame_start` snapshot;
- movement advancement;
- combat per-cell processing;
- combat's post-unit-mission infantry tick.

Those loops now visit `world.infantry[0..world.infantry_count]`. At low and moderate army sizes this
removes hundreds of empty-slot checks per game frame and more than two thousand per four-frame RL
decision. It does not skip a game frame, coarsen simulation, disable combat, or alter active-object
ordering.

## TDD And Determinism

- A pre-change invariant test ran both supported seeds for 3,000 Easy-AI frames and required every
  slot at or above `infantry_count` to remain inactive.
- The invariant test passed before changing loop bounds.
- Debug after the change: 147/147 tests passed.
- ReleaseFast after the change: 147/147 tests passed.
- Existing real-Vanilla observation/action-mask SHA-256 fixtures remained exact.
- Existing movement, combat, pathfinding, AI, economy, RNG, and frame-level differential traces
  remained exact.
- Repeated native baseline and candidate state digests and episode outcomes match exactly.

## Isolated Benchmark

Command for both binaries:

```bash
/tmp/td_micro_batch_benchmark_map_template_final 64 16384
/tmp/td_micro_batch_benchmark_infantry_prefix 64 16384
```

Configuration: 64 worlds, 16,384 iterations, 1,048,576 decisions, ReleaseFast, fixed actions.

| Build | Run 1 SPS | Run 2 SPS | Mean SPS | Difference |
| --- | ---: | ---: | ---: | ---: |
| Static-map baseline | 111,227.167 | 114,961.723 | 113,094.445 | baseline |
| Infantry-prefix candidate | 131,701.121 | 132,374.890 | 132,038.006 | +16.75% |

## Combined Benchmark

The preserved original binary predates both optimizations. The final binary includes the static map
template and bounded infantry loops.

| Build | Run 1 SPS | Run 2 SPS | Mean SPS | Difference |
| --- | ---: | ---: | ---: | ---: |
| Original pre-template | 72,811.943 | 76,289.869 | 74,550.906 | baseline |
| Final combined candidate | 136,820.878 | 136,337.847 | 136,579.363 | +83.20% |

Both original and final builds emitted 0 wins, 320 losses, 0 draws, 0 failures, and digest
`38cca161...ce28` on every run.

## Remaining Gate

The active `cnc5` sweep is still spawning trials from the existing PufferLib extension. Rebuilding
it now would mix environment implementations within one sweep. Once the sweep ends, rebuild
`cnc_micro` and run a matched GPU-training A/B with fixed agents, buffers, threads, horizon,
minibatch size, total timesteps, and policy shape; require `start_failures=0` and engine failures
zero before reporting a PufferLib SPS gain.
