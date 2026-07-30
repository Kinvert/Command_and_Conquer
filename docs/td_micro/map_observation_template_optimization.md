# TD Micro Static Map Observation Optimization

Date: 2026-07-17
Status: committed; native implementation and determinism gates passed; PufferLib A/B pending
Parent commit: `f3b5a1cce7b6db0241601643f8d9e266051cba92`
Implementation commit: `0ee9239fb043de6ef6900290b2cb41414a46c6f6`

## Result

The fixed-action native batch improved from **74,075 to 116,070 SPS**, a **1.567x / 56.69%**
speedup in an alternating same-machine comparison. All four runs completed 320 episodes with zero
failures and the same final-state digest:

`38cca1613d27fcaa4500c25261cff6ea19d838ccd80d9c91fec4d045d718ce28`

The machine was also running the `cnc5` sweep, so these are contended absolute rates. The baseline
and candidate were alternated under the same contention and were individually stable. Do not mix
these rates with the earlier clean 101,182 SPS baseline or extrapolate a clean candidate rate.

## Change

`policy.observe` previously did all of the following on every decision:

1. Zero all 6,208 observation bytes.
2. Fill the 4,096-byte map region again.
3. Visit all 2,842 real map cells, look each cell up, test dynamic Tiberium, branch on terrain
   properties, and reconstruct its observation byte.

Terrain is immutable in TD Micro; only Tiberium presence and entity occupancy are dynamic. The new
path builds initial and depleted terrain templates at Zig compile time. Runtime observation packing
now:

1. Zeroes only the 64-byte globals and 2,048-byte entity regions.
2. Copies the 4,096-byte initial map template once.
3. Finds depleted Tiberium with one 64-bit mask per map row and updates only set bits.
4. Applies unit, building, and infantry occupancy exactly as before.

The observation ABI and version remain unchanged.

## Determinism Gates

- Added a full 4,096-cell reference test for pristine terrain, one depleted Tiberium cell, and all
  Tiberium depleted.
- Existing real-Vanilla executable fixtures still match exact SHA-256 hashes over every observation
  byte plus every action-mask byte at eight recorded states across both supported seeds.
- Debug: 146/146 tests passed.
- ReleaseFast: 146/146 tests passed.
- Native baseline and candidate final-state digests match exactly across repeated runs.
- Episode outcomes match exactly: 0 wins, 320 losses, 0 draws, 0 failures per run.

## Benchmark

Build command for the candidate:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache \
  zig build lib -Doptimize=ReleaseFast --summary all
cc -O3 -std=c11 -I include tools/batch_benchmark.c \
  zig-out/lib/libtd_micro.a -lm -lpthread \
  -o /tmp/td_micro_batch_benchmark_map_template
```

Matched command for each binary:

```bash
/tmp/td_micro_batch_benchmark 64 16384
/tmp/td_micro_batch_benchmark_map_template 64 16384
```

Configuration: 64 worlds, 16,384 iterations, 1,048,576 decisions, ReleaseFast, fixed actions.

| Build | Run 1 SPS | Run 2 SPS | Mean SPS | Failures | Digest |
| --- | ---: | ---: | ---: | ---: | --- |
| Pre-template baseline | 74,044.448 | 74,106.501 | 74,075.475 | 0 | `38cca161...ce28` |
| Static-template candidate | 115,091.737 | 117,048.440 | 116,070.088 | 0 | `38cca161...ce28` |

## Remaining Gate

The active `cnc5` sweep loads the existing PufferLib extension for newly spawned trials. Rebuilding
that extension mid-sweep would mix two environment implementations in one experiment, so no full
PufferLib SPS gain is claimed yet. After the sweep stops, rebuild `cnc_micro` and run an otherwise
identical GPU training A/B with `start_failures=0` and engine failures zero.

## Rejected Follow-Up: Incremental Map Cache

A second TDD candidate retained the observation buffer between decisions and restored only prior
occupancy cells plus changed Tiberium cells. It passed 148/148 Debug and ReleaseFast tests,
including persistent buffers, changed output pointers, auto-reset, occupancy movement, structure
footprints, depletion, and regrowth.

Matched native results did not justify the extra cache state or API surface:

| Build | Run 1 SPS | Run 2 SPS | Mean SPS | Difference |
| --- | ---: | ---: | ---: | ---: |
| Static-template candidate | 120,695.105 | 120,076.832 | 120,385.969 | baseline |
| Incremental-map cache | 120,746.007 | 120,753.714 | 120,749.861 | +0.30% |

Both builds had zero failures and digest `38cca161...ce28`. The cache bookkeeping replaced almost
all of the saved copy cost, so the candidate was removed. After removal, Debug and ReleaseFast
returned to 146/146 tests, and the rebuilt retained executable was byte-identical to the original
static-template candidate (SHA-256 `0fc08a99427581abc800ca22dca562b11fbb90cf720eb4af794f1766bbcc7f41`).
