# Tiberian Dawn PufferLib Environment Spec

## Purpose

This document defines the local design contract for making Tiberian Dawn a serious PufferLib RL environment.

The long-term goal is high-SPS, state-fed RTS training that produces a real C&C player. The learned policy should first control one GDI side in a GDI-vs-GDI mirror skirmish against the original Tiberian Dawn computer AI. Training should progress from scoped curriculum tasks to easy AI, then normal AI, then hard AI. GDI-vs-Nod can come later once the mirror path is stable.

The current public-quality milestone is not "all of C&C." It is a narrow, real-engine Tiberian Dawn economy task with semantic observations and actions:

```text
deploy MCV -> build power plant -> build refinery -> build barracks -> train E1 -> train E3 -> collect harvested Tiberium
```

The current implementation is `PufferLib/ocean/cnc_build/binding.c`.

Current skirmish oracle status is documented in `CNC_GDI_GDI_SKIRMISH_ORACLE.md`. In short, `CNC_MODE=skirmish_gdi_gdi` starts a TD-backed GDI-vs-GDI multiplayer match with Puffer on one side and the original TD AI on the other. Reward is only from the Puffer side. This is not two-perspective training yet.

The current oracle also has a local TD export, `CNC_Get_Raw_Command_State`, that snapshots each side's owned objects with mission, mission queue, target, nav target, archive target, cell/coord, health, and object identity. This is enough raw command/state data to begin building an original-AI-to-action translator, but the translator itself is still future work.

The scoped `10,000+ SPS` rewrite plan is in `docs/zig_fast_core_plan.md`.

## Long-Term Product Target

The final useful product is a playable RTS opponent:

1. PufferLib trains a policy that controls the player side in real TD matches.
2. The reference opponent is the original TD computer AI, starting with a GDI-vs-GDI mirror setup and graduating through easy, normal, and hard.
3. Once the policy can beat the built-in AI, the learned policy can be run in inference mode as the computer opponent for a human player.
4. Human play must keep both opponent brains selectable through INI/config:

```ini
OpponentBrain=OriginalAI
; or
OpponentBrain=PufferPolicy
PufferPolicyPath=/path/to/checkpoint_or_export
```

Do not delete or permanently bypass the original AI. The PufferLib policy is an alternate controller backend. The original AI remains a benchmark, fallback, and selectable game mode.

## Goals

- Train through PufferLib's native env path with `--train.gpus 1`.
- Use headless Tiberian Dawn logic, not human UI automation.
- Feed agents compact structured state, not screenshots.
- Use semantic RTS actions with masks, not mouse pixels.
- Support one learned player-side GDI policy against an original-AI GDI opponent as the main first skirmish training target.
- Preserve a config/INI choice between original AI and PufferLib policy when a human plays against the computer side.
- Make env steps faster by reducing TD frame waits, state-copy overhead, reset cost, and global-state isolation overhead.
- Preserve correctness with replay/hash/parity gates before large rewrites.
- Keep Vanilla-Conquer as the reference implementation for behavior.

## Non-Goals

- Pixel-perfect rendering.
- Audio fidelity.
- Movie/cinematic playback.
- Human-play UX polish.
- Full campaign/skirmish support as the first milestone. Skirmish against the built-in AI is the long-term target, not the first unchecked jump.
- Full simulator CUDA rewrite as the first optimization.
- Silent approximation of unsupported TD mechanics.

## Current Substrate

Headless/API library:

```text
/home/claude/cnc/Vanilla-Conquer/build-remastertd/tiberiandawn/TiberianDawn.so
```

Useful exported functions:

- `CNC_Init`
- `CNC_Start_Instance`
- `CNC_Start_Instance_Variation`
- `CNC_Start_Custom_Instance`
- `CNC_Advance_Instance`
- `CNC_Get_Game_State`
- `CNC_Get_Raw_Command_State`
- `CNC_Handle_Sidebar_Request`
- `CNC_Handle_Debug_Request`

Current PufferLib env:

```text
PufferLib/ocean/cnc_build/binding.c
PufferLib/config/cnc_build.ini
```

Current first-task observation size:

```c
#define CNC_OBS_SIZE 12
```

Current broad scratch buffer:

```c
#define CNC_BUFFER_SIZE (8 * 1024 * 1024)
```

The current task force-completes production with `DEBUG_REQUEST_END_PRODUCTION`. This is acceptable for curriculum bring-up, but final task variants should either make it an explicit curriculum flag or remove it.

## Step Semantics

The project must use precise step names. Do not collapse all of these into "step."

### TD Frame

A TD frame is one call to:

```c
CNC_Advance_Instance(player_id)
```

This advances game logic through the existing TD frame path, including `Logic.AI()` and `Queue_AI()`.

### Command Action

A command action is a semantic input issued to TD:

- start construction
- hold construction
- cancel construction
- start placement
- place building
- spawn/setup/debug command for curriculum
- no-op

Command actions should be cheap. They should not hide hundreds of TD frames unless the action explicitly says it advances time.

### RL Decision Step

An RL decision step is one PufferLib `c_step` call:

```text
read action -> issue command(s) -> advance fixed small time -> compute reward/terminal -> pack observation
```

The target design is fixed-cost or near-fixed-cost per decision step. Slow actions should not stall an entire PufferLib vector because they secretly advance hundreds of frames.

### Time-Advance Action

If the policy needs to wait, that should be explicit:

```text
advance 0 frames
advance 1 frame
advance 4 frames
advance 16 frames
```

or a fixed env-level frame advance after every command. This decision must be documented and benchmarked.

## Opponent Controller Semantics

Training modes should make the controller ownership explicit:

| Mode | Player Side | Computer Side | Purpose |
| --- | --- | --- | --- |
| Curriculum sandbox | PufferLib policy | none or scripted pressure | Learn isolated mechanics and validate fast-core parity. |
| Built-in AI ladder | PufferLib policy | original TD AI | Main route to a real GDI-vs-GDI skirmish agent first; asymmetric GDI-vs-Nod can follow later. |
| Policy opponent | human or evaluation policy | PufferLib policy | Human-play inference and later learned-opponent evaluation. |
| Original game | human | original TD AI | Fallback, parity reference, and normal C&C behavior. |

The original TD AI must remain selectable. When adding human-play inference, route the computer side through a config/INI switch rather than replacing the stock AI globally.

The eventual difficulty ladder is:

```text
scoped curriculum -> easy original AI -> normal original AI -> hard original AI -> learned policy opponent
```

## Current Action ABI

Current `cnc_build` action space:

```text
0: noop
1: wait_1
2: wait_8
3: wait_64
4: deploy_mcv
5: build_power
6: build_refinery
7: build_barracks
8: train_minigunner
9: train_rocket
10: start_power
11: complete_power
12: place_power
13: start_refinery
14: complete_refinery
15: place_refinery
16: start_barracks
17: complete_barracks
18: place_barracks
19: start_minigunner
20: complete_minigunner
21: start_rocket
22: complete_rocket
```

Current reward:

```text
+0.25 successful MCV deploy gate
+1.0 successful power plant placement
+1.5 successful refinery placement
+1.5 successful barracks placement
+1.0 successful E1 minigunner training
+1.0 successful E3 rocket soldier training
+2.0 first harvest crossing 700 harvested credits
+2.0 terminal economy success
-0.01 step cost
-0.05 invalid action
terminal success after refinery + barracks + E1 + E3 + >=700 harvested credits
terminal failure on timeout
```

Required next action ABI direction:

- keep a no-op/wait action
- split construction start from placement when practical
- add action masks for legal build/place choices
- make invalid actions measurable but not dominant
- keep command action cost bounded
- move from this flat curriculum action set to the full masked RTS command grammar before real skirmish training

Future action lanes should be multi-discrete or masked semantic actions:

```text
command_type
buildable_id
target_cell_or_slot
time_advance
```

## Observation ABI

The first env can use a compact flat vector for PufferLib, but each field must have a stable meaning.

Current `cnc_build` fields:

```text
0: MCV deployed
1: power plant built
2: refinery built
3: barracks built
4: E1 minigunner trained
5: E3 rocket soldier trained
6: harvested credits / 700
7: episode progress
8: credits / 12000
9: power balance / 200
10: last action invalid
11: start OK
```

Required next observation work:

- replace broad 8 MB state reads for small fields with compact TD exports
- add action mask fields or PufferLib mask buffer support
- expose build queue and placement validity directly
- expose enemy/computer-side state needed for skirmish learning: visible units, visible buildings, threat, attacks, damage, and win/loss state
- avoid per-step allocations
- avoid broad `memset` of huge buffers for tiny observations

Future observation shape:

- fixed scalar header
- fixed map/resource planes at chosen resolution
- fixed own-unit/building slots
- fixed enemy/neutral visible slots
- legal action masks

The policy should never need raw mouse position, rendered pixels, or internal object pointers for the serious training path.

## Reset Semantics

Current reset starts or restarts a scenario through TD APIs and setup debug commands. Profiling measured reset at about 28.79 ms.

Target reset:

1. Boot scenario.
2. Apply curriculum setup.
3. Snapshot the mutable state after setup.
4. Restore from that snapshot on episode reset.
5. Verify restore by replay/hash checks.

Reset is part of env SPS. Do not exclude it from performance claims unless reporting a separate microbenchmark.

## Determinism Contract

Near-term Vanilla-Conquer wrapper:

- record semantic commands issued by the env
- record TD frame counts advanced per decision
- compute compact state hashes after scripted traces
- repeat a trace and require matching final observations/rewards

Long-term deglobalized or rewritten core:

```text
CnCWorld + CnCInput -> CnCWorld
```

Rules:

- no wall clock on the sim path
- no OS RNG on the sim path
- no renderer/audio/movie dependency on the training path
- no raw pointers in serialized state
- deterministic input stream is the only nondeterminism channel
- state snapshots must be restorable and hashable

## Validity Gates

### Native Profiler Gate

Run:

```bash
cd /home/claude/cnc
g++ -std=c++17 -O2 -Wall -Wextra tools/td_step_profile.cpp -ldl -o tools/td_step_profile
tools/td_step_profile --noop-steps 2000 --build-episodes 5 --isolated-envs 12
```

Report:

- no-op SPS
- build-curriculum SPS
- average frame advance time
- observation extraction time
- reset time
- action component timings
- isolated env capacity

### Determinism Parity Gate

Run:

```bash
cd /home/claude/cnc
g++ -std=c++17 -O2 -Wall -Wextra tools/td_parity_trace.cpp -ldl -o tools/td_parity_trace
tools/td_parity_trace --replays 3 --settle-frames 64
```

Required current result:

```text
determinism replays=3 ok=1 trace_hash=0xe7dc5ff7b7c9fb44
```

The parity method and checkpoint hashes are documented in `docs/td_determinism_parity.md`.

### PufferLib Gate

Run:

```bash
cd /home/claude/cnc/PufferLib
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=10 LD_LIBRARY_PATH=$EXTRA_LIBS .venv/bin/python -m pufferlib.pufferl train cnc_build \
  --train.gpus 1 \
  --vec.total-agents 10 \
  --vec.num-buffers 1 \
  --vec.num-threads 10 \
  --train.total-timesteps 1280 \
  --train.horizon 64 \
  --train.minibatch-size 640 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

Valid PufferLib benchmark requirements:

- `start_failures=0.000`
- command includes `--train.gpus 1`
- command includes agents/threads/horizon/minibatch details
- result includes SPS and whether the run is valid
- if a run uses 12+ envs, prove there are no `dlmopen` TLS failures before citing SPS

### Replay/Parity Gate

For any change that affects TD behavior:

- run a scripted economy trace before and after
- compare final observation fields
- compare reward/terminal path
- compare compact state hash once available
- document unsupported differences

For any fast-core or C/Zig rewrite:

- unsupported TD feature must fail loudly
- parity tests must name the Vanilla-Conquer reference scenario
- do not claim full TD support unless triggers, production, pathing, combat, shroud, and edge cases are covered

## Performance Targets

Current measured baseline:

| Config | Result |
| --- | ---: |
| Native no-op profiler | about 5,062 SPS |
| Native build-curriculum profiler | about 26.3 SPS |
| TD-backed PufferLib 10 agents / 10 threads | about 147 SPS |
| Scoped Zig fast-core economy PufferLib 10 agents / 1 thread | about 72,979 SPS |
| PufferLib 12 agents / 12 threads | invalid if `start_failures > 0` |

Phase targets:

| Phase | Target |
| --- | --- |
| Prototype fix | 100-300+ aggregate SPS on current narrow curriculum |
| Snapshot + compact exports | 500+ aggregate SPS if frame waits are controlled |
| Deglobalized in-process envs | 500-2,000+ aggregate SPS for constrained build/econ tasks |
| Verified scoped C/Zig fast core | 10k+ aggregate SPS may be plausible across many CPU threads |

These are targets, not claims. Every claim needs command output and validity checks.

## Optimization Roadmap

### Phase 0: Remove Prototype Pathologies

- keep the current fastest valid settle-frame setting documented and measured
- split command actions from time advancement
- compact sidebar/player/build state exports
- add action masks
- reprofile native and PufferLib SPS

### Phase 1: Deterministic Trace Gate

- scripted command trace
- final observation comparison
- compact state hash
- reset repeatability check

### Phase 2: Snapshot Reset

- snapshot after scenario setup
- restore on reset
- verify replay/hash stability
- measure reset-time reduction

### Phase 3: Deglobalize TD

- replace `dlmopen` scaling with explicit per-env state
- add `CnCInstance`-style handle
- isolate `Map`, `Logic`, `PlayerPtr`, `Factories`, houses, object pools, and frame globals
- support 32+ envs without TLS failures

### Phase 4: Data-Oriented Hot Loops

- run `perf record -g`
- optimize only proven hot paths
- add parity tests for each subsystem touched

### Phase 5: Scoped Fast Core

- implement a deterministic RTS subset in C/Zig only if Vanilla-Conquer remains too slow
- validate against Vanilla-Conquer traces
- keep unsupported mechanics explicit

### Phase 6: Selective CUDA

- only after state is batchable
- keep CPU reference implementations
- require end-to-end PufferLib SPS improvement

## Documentation Requirements

After any profiling or env-performance change, update or supersede:

- `docs/td_step_loop_profile.md`
- `TIBERIAN_DAWN_RL_STATUS.md` if the user-facing status changed
- `PUFFERLIB_TRAINING_PATH.md` if the training path changed

Do not leave stale SPS numbers without noting the date, command, and validity.
