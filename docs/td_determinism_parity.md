# Tiberian Dawn Determinism And Parity Harness

## Goal Text

Build the C&C deterministic parity track: export compact Vanilla-Conquer state hashes for fixed command traces, verify repeated replay hashes, then replace one subsystem at a time in a Zig fast core and require per-checkpoint parity before using it in PufferLib.

## Determinism Definition

For this project, a run is deterministic when the same initial setup, semantic commands, and exact TD frame counts produce the same compact state hash at every checkpoint.

We are not comparing pixels, audio, UI animation, or full raw engine memory. The oracle is a field-level digest of the gameplay state needed by the current RL task. If a future subsystem changes one of these fields, that trace must still match before the replacement is accepted.

## Current Harness

Source:

```text
tools/td_parity_trace.cpp
```

Build:

```bash
cd /home/claude/cnc
g++ -std=c++17 -O2 -Wall -Wextra tools/td_parity_trace.cpp -ldl -o tools/td_parity_trace
```

Run the current oracle trace:

```bash
cd /home/claude/cnc
tools/td_parity_trace --replays 3 --settle-frames 64
```

The default uses an isolated `dlmopen` namespace per replay. That is intentional: Vanilla-Conquer has process-global state, and the parity oracle needs a clean reference run.

## Current Verified Result

Command:

```bash
tools/td_parity_trace --replays 3 --settle-frames 64
```

Result:

```text
determinism replays=3 ok=1 trace_hash=0xe7dc5ff7b7c9fb44
```

The trace has 12 checkpoints:

| Phase | Frame | State hash |
| --- | ---: | --- |
| `setup` | 64 | `0xabb260d2a8f44822` |
| `power.started` | 66 | `0xd335df709e99089f` |
| `power.completed` | 68 | `0xf321a8f7e527622d` |
| `power.placement_mode` | 69 | `0x62f1ee85cae5a123` |
| `power.placed` | 73 | `0x0e6005f53b44554e` |
| `power.settled` | 137 | `0xbb5c8a4ba1ce7054` |
| `refinery.started` | 139 | `0x5ef183f35b402365` |
| `refinery.completed` | 141 | `0xef421b6b84681f24` |
| `refinery.placement_mode` | 142 | `0x31e2f49567d350aa` |
| `refinery.placed` | 146 | `0x2b105f13a3e8cd93` |
| `refinery.settled` | 210 | `0x53ea93e5a5912255` |
| `final` | 210 | `0x4a7abf69c5c86504` |

Placement cells in this trace:

| Structure | Cell |
| --- | --- |
| Power plant | `20,8` |
| Refinery | `17,4` |

Final compact state:

```text
credits=11998
power=138/55
entries=16
power_present=1
power_completed=0
refinery_present=1
refinery_completed=0
```

## Compact State Fields

The state digest currently includes:

- checkpoint index, phase id, TD frame number
- last command, last buildable id, last placement cell
- credits, credits counter, tiberium, max tiberium
- power produced, power drained, mission timer
- sidebar entry counts
- power plant sidebar digest
- refinery sidebar digest

Each structure digest includes:

- present
- completed
- constructing
- on hold
- busy
- cost
- build time
- power provided
- placement list length
- progress, quantized to thousandths

The hash is stable FNV-1a over explicit little-endian integer writes. That makes the trace easy to port to Zig and compare without depending on C/C++ struct padding.

## Negative Control

The shared-library path is intentionally available as a control:

```bash
tools/td_parity_trace --replays 3 --settle-frames 64 --shared
```

Current result:

```text
determinism replays=3 ok=0 trace_hash=0xe7dc5ff7b7c9fb44
```

Replay 0 matches the isolated oracle, but replay 1 changes to:

```text
trace_hash=0x38b52b275e8db777
final_state_hash=0xdaa4a411b97f7764
final_power=137/55
```

That is useful evidence. It means process-global Vanilla-Conquer state can leak across non-isolated loads. Serious training should not depend on this path for correctness, and the fast core should use explicit per-env state instead of loader namespaces.

## Replacement Workflow

Use this process for each fast-core replacement:

1. Add or select a Vanilla-Conquer trace that covers the behavior being replaced.
2. Record semantic commands and exact frame counts.
3. Export compact state hashes from Vanilla-Conquer.
4. Implement the smallest matching subsystem in the fast core.
5. Replay the same commands against the fast core.
6. Compare every checkpoint field and hash.
7. Only then route that subsystem into the PufferLib env.

A replacement is not accepted because the episode reward still works. It is accepted when the supported fields match at every checkpoint, or when a documented unsupported field is intentionally excluded from the parity contract.

## Next Trace Targets

The current trace covers construction yard setup, power plant construction/placement, and refinery construction/placement.

Next useful traces:

- invalid placement rejection
- build prerequisites before and after power plant
- low-power state after refinery
- reset/snapshot restore parity
- harvester/refinery resource timing
