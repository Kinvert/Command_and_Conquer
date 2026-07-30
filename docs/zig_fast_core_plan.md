# Scoped Zig Fast Core Plan For 10k+ SPS

## Goal

The current Vanilla-Conquer wrapper is now useful enough for early PufferLib experiments, but it is unlikely to reach `10,000+` aggregate SPS while it still depends on global C++ game state, `dlmopen`, broad UI buffers, and TD frame advancement.

The `10,000+ SPS` path is a scoped deterministic Zig fast core for the build/economy subset, using Vanilla-Conquer traces as the oracle.

This is not a full Tiberian Dawn rewrite. It is a narrow, measurable simulator core that starts with the parts required by the first RL tasks.

The long-term product target remains real RTS play: a learned GDI/player-side policy should first beat an original-AI GDI opponent in a mirror skirmish, then ladder through easy, normal, and hard AI. Later, human play should choose the computer-side brain through config/INI, either the original AI or a trained PufferLib policy running inference. The fast core exists to accelerate verified mechanics; it must not erase the original-AI reference path.

## Why Zig

Zig is a good fit here because the target architecture needs:

- explicit state ownership
- fixed-size structs and arrays
- no hidden allocation in hot paths
- cheap snapshot/clone
- C ABI export for PufferLib
- deterministic integer logic
- easy standalone benchmarks

The language is not the speedup by itself. The speedup comes from the data model: no renderer, no audio, no UI, no globals, no broad state dumps, no dynamic-loader namespace isolation.

## Scope

### Phase A: Build/Economy Core

Implement only:

- fixed map grid
- player credits
- power produced/drained
- MCV/deployed construction yard state
- buildable prerequisites
- power plant
- refinery
- building placement footprint checks
- simple tiberium/resource accounting placeholder
- production/build queues
- deterministic command input log
- compact observation export
- action masks
- snapshot/restore

Out of scope for Phase A:

- combat
- shroud/fog
- pathfinding
- harvesters moving on the map
- AI opponents
- triggers beyond those needed to initialize the fixed task
- renderer/audio/video
- arbitrary campaign missions

### Phase B: Harvest Loop

Add:

- refinery storage
- harvester entity
- tiberium cell depletion
- simple deterministic harvest travel model
- resource return timing

Still avoid full pathfinding until the build/economy loop is validated.

### Phase C: Combat Slice

Add only if needed:

- fixed unit slots
- hitpoints
- target selection
- weapon cooldowns
- deterministic projectile/damage rules

## API Shape

Target C ABI for PufferLib:

```c
typedef struct CncFastEnv CncFastEnv;

CncFastEnv* cnc_fast_create(uint64_t seed);
void cnc_fast_destroy(CncFastEnv* env);
void cnc_fast_reset(CncFastEnv* env, uint64_t seed);
void cnc_fast_snapshot(CncFastEnv* env, void* dst, size_t len);
void cnc_fast_restore(CncFastEnv* env, const void* src, size_t len);
void cnc_fast_step(CncFastEnv* env, const CncFastAction* action, CncFastStepResult* out);
void cnc_fast_observe(const CncFastEnv* env, float* obs);
void cnc_fast_action_mask(const CncFastEnv* env, uint8_t* mask);
uint64_t cnc_fast_hash(const CncFastEnv* env);
```

Core equation:

```text
CnCFastState + CnCFastInput -> CnCFastState
```

All nondeterminism enters through seed plus input. No clock or OS RNG is allowed on the sim path.

## State Layout

Use fixed-size arrays first:

```text
State
  tick: u32
  rng_seed: u64
  players[2]
  map_cells[W * H]
  buildings[MAX_BUILDINGS]
  units[MAX_UNITS]
  build_queues[PLAYERS][QUEUE_TYPES]
```

Use stable integer ids:

```text
BuildingId = u16
UnitId = u16
Cell = u16
```

No pointers in serialized state. No heap allocation in `step`.

## Parity Oracle

Vanilla-Conquer remains the reference.

The first oracle harness is now:

```bash
cd /home/claude/cnc
g++ -std=c++17 -O2 -Wall -Wextra tools/td_parity_trace.cpp -ldl -o tools/td_parity_trace
tools/td_parity_trace --replays 3 --settle-frames 64
```

Current expected result:

```text
determinism replays=3 ok=1 trace_hash=0xe7dc5ff7b7c9fb44
```

Details are in `docs/td_determinism_parity.md`.

For each supported behavior, create a scripted trace:

```text
seed/setup -> commands -> Vanilla-Conquer compact state stream
seed/setup -> commands -> Zig fast core compact state stream
compare allowed fields
```

Initial parity fields:

- credits
- power produced
- power drained
- buildable bits
- build queue ready/progress bits
- placement legal/illegal
- building placed/not placed
- terminal success/failure
- reward path for the current curriculum

Parity should be field-level, not full raw TD state. The fast core is scoped; unsupported fields must be explicit.

## Unsupported Behavior Policy

Unsupported mechanics must fail loudly:

- unsupported building type
- unsupported unit type
- unsupported trigger
- unsupported weapon
- unsupported sidebar command
- unsupported map feature
- unsupported AI order

Do not silently approximate unsupported full-game behavior while claiming TD parity.

## Benchmarks

Benchmarks must separate:

- raw core steps/sec
- PufferLib env SPS
- reset/snapshot cost
- observation packing cost
- action mask cost
- parity trace cost

Target ladder:

| Milestone | Target |
| --- | ---: |
| Zig core build/economy microbench | 100k+ raw steps/sec single thread |
| PufferLib single-process vector env | 10k+ aggregate env SPS on Phase A |
| Parity trace suite | 100% pass for supported fields |
| Snapshot restore | cheaper than full scenario setup by at least 10x |

The only headline number that matters for training is PufferLib env SPS.

## Relationship To Current Wrapper

The current wrapper stays useful for:

- discovering the task surface
- generating parity traces
- validating rewards/actions
- early policy experiments
- checking whether a fast-core simplification is acceptable

The wrapper should not be forced to become the final high-SPS architecture. `dlmopen` and global TD state are prototype tools.

## Current Zig Prototype

The first scoped Zig core lives in:

```text
zig-fast-core/
```

It implements the current build/economy parity slice only:

- construction-yard setup state
- power plant construction and placement
- refinery construction and placement
- compact FNV state hashing compatible with `tools/td_parity_trace.cpp`
- `State`/`Input`/`step`/`observe`/`mask`/`hash`
- snapshot/restore by value
- raw core benchmark CLI

Verified commands:

```bash
cd /home/claude/cnc/zig-fast-core
ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache zig build test --cache-dir .zig-cache
ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache zig build run --cache-dir .zig-cache -Doptimize=ReleaseFast -- parity
ZIG_GLOBAL_CACHE_DIR=/tmp/zig-global-cache zig build run --cache-dir .zig-cache -Doptimize=ReleaseFast -- bench 100000000
```

Verified results:

```text
parity ok=1 trace_hash=0xe7dc5ff7b7c9fb44
bench iterations=100000000 seconds=0.119958 raw_sps=833623219
```

This is not yet a PufferLib env and should not be presented as training SPS.

## Immediate Next Steps

1. Add invalid-placement and prerequisite Vanilla-Conquer traces before widening the action space.
2. Add reset/snapshot restore parity against Vanilla-Conquer setup.
3. Add a trace-replay benchmark that measures full scripted episodes, not only raw frame steps.
4. Add a C ABI and PufferLib env only after the next trace set passes.
5. Keep Vanilla-Conquer trace export as the oracle while replacing one subsystem at a time.
