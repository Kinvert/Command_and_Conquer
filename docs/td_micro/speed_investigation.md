# Where td-micro's time actually goes, and what a faster rewrite would need to sacrifice

Date: 2026-07-24

Context: exploring a possible non-deterministic rewrite aimed at 10-100x, where human play borrows
the original Vanilla renderer so it still *looks* like C&C. This document is the measurement pass
that should precede that decision, per this project's own first operating principle.

Everything below is measured on this machine against the current `td-micro-cnc26` tree, not
estimated.

## 1. Measured footprint

```
World (one env)      : 32,256 bytes
  projectiles        : 11,264  (35%)   256 slots x 44 B
  infantry           :  9,216  (29%)   128 slots x 72 B
  building_fires     :  4,608  (14%)   384 slots x 12 B
  tiberium_steps     :  4,096  (13%)   64x64 u8
  units              :  1,088          16 slots x 68 B
  buildings          :    768          64 slots x 12 B
  tiberium_present   :    512          64x64 bitset
observation          :  2,456 bytes = 64 globals + 344 tiberium + 2,048 entity records
abi14 action mask    :    471 bytes
```

The scenario map is **not** per-world: it is a compile-time `const` array of 2,842 `Cell` structs
(8 B each, ~22 KB) shared by every world.

## 2. The cache hypothesis is wrong

Holding total work constant (~1,048,576 decisions) and varying only how many worlds share the
batch, single-threaded `batch_benchmark`, ReleaseFast:

| worlds | batch footprint | SPS |
| ---: | ---: | ---: |
| 1 | 31 KB | 138,646 |
| 4 | 126 KB | 137,522 |
| 16 | 504 KB | 136,373 |
| 64 | 2,016 KB | 128,397 |
| 256 | 8,064 KB | 125,075 |

A **256x increase in memory footprint costs only ~10% throughput.** There is no cliff at L1, L2 or
L3. The simulator is **compute-bound, not memory-bound**.

This directly refutes the intuition that shrinking the map, packing tiles into fewer bytes, or
slimming the `World` will speed anything up *on CPU*. It would not. Those changes matter only for
a GPU port (see section 5).

Budget: ~138,646 SPS single-threaded at ~3.5 GHz is **~25,000 cycles per decision**, and a decision
advances 4 TD frames, so **~6,300 cycles per simulated frame**. That is a great deal of work for a
frame in which typically a handful of entities are doing anything.

## 3. Where the cycles actually go: iterating dead slots

There are **69 loops in the per-frame path that iterate a full capacity array** rather than the
active count. Per frame that is on the order of 128 infantry + 256 projectiles + 384 fire effects +
64 buildings + 16 units = ~848 slot visits, times 4 frames = ~3,400 slot visits per decision,
almost all of them on empty slots.

Ablation, 64 worlds, identical episode count (462) and zero failures in every case:

| configuration | SPS | vs baseline |
| --- | ---: | ---: |
| baseline (inf 128, proj 256, bld 64) | 128,397 | — |
| inf 32, proj 64 | 158,994 | **+24%** |
| inf 16, proj 32, bld 16 | 210,214 | **+64%** |

**~1.64x is available with no algorithmic change and no gameplay change**, purely by not walking
empty slots. Note this experiment shrank capacities to prove the cost; the real fix is dense active
lists / free lists, which gets the same win while *keeping* the current limits.

This is the single highest-value optimisation found, it is entirely compatible with determinism,
and it needs no rewrite.

## 4. Answering the specific proposals

### "Make the map smaller"
No direct throughput win: the map is shared `const`, and section 2 shows footprint barely matters.
It *is* valuable for a different reason — a smaller map means shorter episodes, so more episodes
per wall-clock hour, which improves learning throughput. That is a curriculum decision, not a
performance one, and should be argued on those terms.

### "Represent each tile with fewer bytes"
Currently 8 B/cell: `land_type u8`, `foot_cost u8`, three bools, `overlay i16`, `overlay_data u8`.
Almost all of it is derivable or redundant:
- `foot_cost` is a function of `land_type` -> lookup table, drop the field.
- The three bools are 3 bits.
- `land_type` needs ~3 bits for the reduced ruleset.
- `overlay`/`overlay_data` are tiberium/walls, already duplicated in `tiberium_steps`.

Realistic packing: **2 bits/cell** (passable, buildable) as two parallel bitsets = ~711 B total for
the whole map, versus ~22 KB today. Bitsets additionally let occupancy and passability be tested 64
cells at a time. Again: near-zero CPU win, but a real enabler for GPU.

### "Remove terrain normally, handle it only in render mode"
Partly right, and worth doing. Terrain cannot leave the simulation entirely — `foot_cost`,
passability and buildability change gameplay. But everything *visual* can go: tile art indices,
overlay graphics, land type beyond the passable/buildable bits. Keep 2 bits/cell in the sim; let
the renderer read the original map file for everything else. Same argument applies to
`building_fires`: 4,608 B and 14% of the `World` for a damage-over-time effect that could be one
timer per building (64 B), with the flames themselves being purely a render concern.

### "Keep it all on the GPU, minimise transfers"
This is the genuinely interesting direction, and it is where the struct-shrinking work pays off.

The prize is not the sim kernel; it is **never copying observations to the host**. Today the loop
is: env writes 2,456 B/agent on CPU -> copy to GPU -> policy forward -> copy actions back. If the
env kernel writes observations directly into the CUDA tensor the policy reads, per-step transfers
go to zero and only episode statistics ever come back.

What that requires:
- **SoA, not AoS.** A 72-byte `Infantry` struct is the worst case for coalesced access. Split into
  parallel arrays (`x[]`, `y[]`, `health[]`, ...) so a warp reads contiguous lanes.
- **One thread per world**, not per entity, for the branchy mission/pathfinding logic. Entity-level
  parallelism inside one world is too divergent; world-level gives you thousands of independent
  lanes.
- **Shrink the World hard.** 32 KB/world x 10,000 worlds = 320 MB, which fits, but 32 KB per thread
  lives in global memory and every access pays latency. This is where 2-bit tiles, sparse tiberium,
  removed fire effects and dense entity arrays genuinely matter — for occupancy and bandwidth, not
  cache.
- **Bounded, uniform work per step.** Variable-length pathfinding is the enemy of a GPU step.
  Precomputed flow fields per target, or a coarse navigation grid with local refinement, convert
  per-unit A* into a table lookup.

Divergence remains the real risk: worlds in different game phases take different branches and
serialise within a warp. Sorting worlds by phase, or stepping in phase-synchronised waves, is the
standard mitigation and is worth prototyping before committing.

### Other shortcuts worth evaluating
1. **Hitscan weapons need no projectile slot.** Bullets already resolve near-instantly
   (`timer = 4`, placed at the target). Resolving them immediately would remove most churn through
   the 11 KB projectile array — the single largest block in the `World`.
2. **`explode()` is O(projectiles x all entities)** — it scans all 128 infantry, 64 buildings and
   16 units per detonation. A coarse spatial grid makes it O(nearby).
3. **Sparse tiberium.** 4,096 B of `tiberium_steps` for a map where only ~344 cells ever hold
   tiberium (the observation already knows this — it encodes exactly 344 bytes). A sparse list is
   ~10x smaller.
4. **Decision interval.** `decision_frames = 4`. Raising it to 8 or 16 linearly reduces simulated
   frames per RL step. This trades control granularity for throughput and is a pure knob, no
   rewrite required — worth measuring before anything more drastic.
5. **Event-driven fast-forward.** If nothing is moving, firing, producing or harvesting, the next
   several frames are predetermined; jump to the next scheduled event instead of ticking each
   frame. Early game is largely idle waiting on build timers.
6. **Episode length.** The 12,000-decision (48,000-frame) timeout dominates wall-clock for
   non-terminating episodes.

## 5. What determinism actually costs, revisited

Nothing in the measured data above is caused by determinism. The 1.64x from dense entity lists, the
`explode()` scan, the projectile array, the fire effects, the decision interval — every one is
available while staying bit-exact against Vanilla. Determinism's real cost in this project is
*developer time* spent on parity plumbing, not runtime.

The honest trade is therefore not "deterministic vs fast". It is:

- **Keep reproducibility** (same seed -> same episode) regardless. It is nearly free and it is what
  makes regression tests and debugging possible. Dropping it is close to pure downside.
- **Relaxing bit-exact Vanilla parity** saves implementation effort and frees the design (SoA,
  GPU layouts, hitscan resolution, flow fields). That is a real and defensible saving.
- But it costs the transfer evidence. Today, a policy winning a rendered Vanilla match *proves*
  the sim matches the game. Without parity that same render is a demo, not evidence.

## 6. Recommended order

1. Dense active entity lists. Measured 1.64x, no gameplay or determinism change. Do this first.
2. Hitscan resolution + `explode()` spatial grid + fire-effect removal. Shrinks the hottest arrays.
3. Measure `decision_frames` 8 and 16. Free knob.
4. Only then decide on GPU residency, and treat struct packing / 2-bit tiles as part of *that*
   work, since they buy nothing on CPU.

A final strategic note: none of this addresses sample efficiency. `current_status.md` already flags
that the policy divides every observation byte by 255 and projects a flat vector, discarding the
structure of ids, coordinates and entity records. A better encoder could plausibly beat a 10x
simulator speedup in time-to-good-policy, and it is far less work than a rewrite.
