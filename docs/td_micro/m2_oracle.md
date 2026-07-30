# TD Micro Vanilla Oracle And Initial Zig Parity

Recorded: 2026-07-13

Historical note: this file records the M2 oracle gate. Closed-loop Easy-AI parity now extends
through a legitimate terminal; see `docs/td_micro/m5_easy_ai.md`.

2026-07-15 update: manifest schema 5 adds deterministic close and medium scenario-1 spawn profiles.

Historical status: partial M2/M3/M4/M5. Reset, the restricted build/economy opening, E1/E3 egress, explicit
movement, static-obstacle routing, stationary combat, and the recorded Easy-AI opening through an
operational Barracks are pinned. Autonomous Easy-AI decisions, full-episode parity, action masks,
terminal state, and PufferLib integration remain open.

## Authoritative Ruleset

`td-micro/rules/td_micro_v1.json` is the authored manifest. Its current SHA-256 is:

```text
ffc4646f31a9c8e64dcfbd1ffc91fa6163af4b5686478124b3bb21187107ca85
```

The generator emits matching Zig and C headers. The corrected effective Vanilla strengths are 800
for the Construction Yard, 400 for the Power Plant, and 800 for the Barracks. Vanilla's building
type constructor doubles the raw strengths in `bdata.cpp`; copying those raw values directly was an
earlier manifest error caught by the deploy fixture. Manifest schema 3 introduced the controller
difference exposed by the Easy-AI trace: a policy/human Construction Yard uses 64 construction
frames while the original Easy-AI path uses 60; Power and Barracks use 60. It also source-backs the
M16 and Dragon damage, reload, range, projectile, launch, speed, arming, turn, unarmored modifier,
and spread values consumed by the Zig combat path. Current schema 5 additionally declares the two
authored spawn profiles.

## Oracle Build

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache zig build generate-rules
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache zig build generate-map

cd /home/claude/cnc/.worktrees/td-micro-v1/Vanilla-Conquer
cmake --build build-remastertd --target TiberianDawn

cd /home/claude/cnc/.worktrees/td-micro-v1
g++ -std=c++17 -O2 -Wall -Wextra \
  -Itd-micro/generated -Itd-micro/include \
  tools/td_micro_oracle.cpp -ldl -o tools/td_micro_oracle
```

The harness creates a PID-specific startup directory and `CONQUER.INI`, points `DataPath` at the
local ignored TD data, and gives every run an isolated user directory. This is required because TD
must mount its core MIX archives before loading `SCM01EA.INI`.

## Deterministic Traces

Each command below was run twice in a fresh process. Each pair was byte-identical.

| Fixture | Command suffix | Final frame | SHA-256 |
| --- | --- | ---: | --- |
| `vanilla_seed1_scenario1_map.json` | `--seed 1 --decisions 0 --map-output ...` | reset | `b29261be5c42da9e31663fa5fd80dcbbe4b105b00428371b3fda895c85232531` |
| `vanilla_seed1_idle64.jsonl` | `--seed 1 --decisions 16` | 64 | `a6071f860e2c923e8dc567f24835e5ac6fde363e9c5a041e8226a644d5630ab5` |
| `vanilla_seed2_idle64.jsonl` | `--seed 2 --decisions 16` | 64 | `f66a34ecf3b880febdbfe0c0927206371f10e122af5daef62c9055f774373dd3` |
| `vanilla_seed1_ai_deploy_frame.jsonl` | exact Easy-AI deploy command | 8 | `e6341df49b0c05f7dbc0c8a1c5d281595ff8d3e13359c08d73bb3b88f3a76b5a` |
| `vanilla_seed1_ai_opening.jsonl` | recorded Easy-AI opening | 640 | `71c7fd7039fc6e750a179cd59a2386c6434739057658d073a694452d3c2a97f1` |
| `vanilla_seed1_mirror_deploy.jsonl` | `--seed 1 --decisions 20 --deploy-decision 1` | 80 | `e3cdc5908a0c0d01a0b262cee21a96d497e571e11c9a9f0143eec8641d9a8c71` |
| `vanilla_seed1_player_power.jsonl` | through completed Power queue | 320 | `049aebba723873675dcc1ef640322a6291c81e8c9ca2d36e3f2eb3c8952aa05a` |
| `vanilla_seed1_player_power_place.jsonl` | through operational Power | 384 | `36f314a85dbfc7e32969a6fcf992c7c9c458cae3d064f5306e160d4fb1678c34` |
| `vanilla_seed1_player_barracks.jsonl` | through operational Barracks | 660 | `5a141929eca8672297959106cb176d1ebe126cfab9bf228911b67aebff2e8b17` |
| `vanilla_seed1_player_e1_e3.jsonl` | E1/E3 egress through guard | 1032 | `6576de0c064261650bdcd63a6d8acfccd2c61d7e9bffc73354813cd25f569a00` |
| `vanilla_seed1_player_e1_move.jsonl` | E1 straight move through guard | 1100 | `80e027dbaf68292ed4b1ff1424c4c5ca1eb5ae9329cb5e2ad0155bbc01ca8931` |
| `vanilla_seed1_player_e1_obstacle.jsonl` | E1 route around blocked terrain | 1400 | `ff61c48aeb9613f3a1a7a0d1fef1b133b953d437cd427a9b655d76141a0b7c96` |

Full-opening invocation:

```bash
tools/td_micro_oracle \
  --output /tmp/td_micro_e1_e3.jsonl \
  --seed 1 --decisions 258 \
  --deploy-decision 1 \
  --power-decision 23 \
  --place-power-decision 77 --place-x 4 --place-y 7 \
  --barracks-decision 92 \
  --place-barracks-decision 146 --barracks-x 6 --barracks-y 7 \
  --e1-decision 161 --e3-decision 189
```

## Pinned Vanilla Behavior

Seed 1 resets to a 58x49 playable map at global cell origin `(3,11)`, 10,000 credits per side,
post-load RNG state `2137312273`, player MCV local cell `(2,8)`, and opponent MCV local cell
`(15,1)`. The opponent is an original Easy GDI AI.

Seed 2 uses the same map, resources, RNG reset, and player MCV, with the opponent MCV at local cell
`(37,23)`. Spawn-profile selection does not consume simulation RNG or impose a separate AI timer.

MCV deployment takes 24 policy-path frames. At four-frame decision boundaries the facing sequence is 246,
226, 206, 186, and 166 before the MCV becomes a Construction Yard. The yard is placed one local
cell northwest of the MCV. It immediately contributes 30 power. The policy path remains in
construction for 64 frames and contributes its 15 drain at frame 88; the Easy-AI path uses its
separate 60-frame rule and is operational by the frame-84 decision boundary.

The original AI starts a Power Plant as its yard becomes operational. Oracle queue discovery now
handles both production models used by TD: the human house-level factory and the original AI's
factory attached to its producer building. At frame 92, after the player issues `start_build` at
decision 23, the player queue is Power Plant, stage 2, rate 2, and balance 296. The fixture follows
all 108 installments through completion.

The player places Power at local cell `(4,7)`. It becomes operational at frame 364. Barracks starts
at decision 92, completes at frame 580, is placed at local cell `(6,7)` at decision 146, and becomes
operational at frame 640. The shared action ABI proves `noop`, owner-relative-slot `deploy`,
`start_build(power|barracks)`, `place(power|barracks)`, and `train(E1|E3)` on this trace.

E1 starts at decision 161, completes at frame 748, and automatically exits the Barracks on the next
decision. It travels from the Barracks exit at local cell `(7,8)` to the upper-left infantry spot in
`(7,9)`. E3 starts at decision 189 and completes at frame 968. Because E1 reserves that upper-left
spot, Vanilla selects the center spot for E3. Zig matches the full E3 egress at every decision from
243 through 258, including lepton coordinates, head reservation, non-cardinal movement, arrival,
mission transition, and retained south-facing idle state. E1 has 50 health and E3 has 25.

Unsupported commands return false rather than silently mutating state.

The separate map-oracle ABI exports all 58x49 playable cells in row-major order. Each cell records
land type, foot cost, ground buildability, static terrain blockage, final static foot passability,
overlay type, and overlay data. `generate-map` compiles that twice-recorded fixture into immutable
Zig data, and the map parity test compares every generated field back to the JSON source.

## Tests

The full Zig suite passes in Debug, ReleaseSafe, and ReleaseFast. The ReleaseFast C ABI is also built
and exercised by the Puffer binding smoke test:

```bash
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache zig build test
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache zig build test -Doptimize=ReleaseSafe
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache zig build test -Doptimize=ReleaseFast
```

Covered parity fields include reset geometry/resources/MCVs, deploy lifecycle and visible MCV
state, Construction Yard transition, player resources, every production installment, completed
structure placement/construction, E1/E3 queue state, automatic egress with an occupied sub-cell,
the complete static map fixture, an end-to-end explicit E1 move, and one source-style obstacle
route. Actor slots are owner-relative in both Vanilla and Zig; a failed test exposed and corrected
the earlier global-index interpretation.

The Vanilla settings and TD Micro allowlist tests also pass:

```text
settings  passed
tdmicro   passed
```

## Limits Before M2 Can Close

- Seeds 1 and 2 have explicit reset fixtures. Undeclared profile seeds fail as unsupported in Zig.
- Zig pins Vanilla's post-load RNG value but does not yet consume RNG in Vanilla's per-frame order.
- Original-AI actions are timestamped by per-frame read-only observation and retained inside the
  compact four-frame trace. Recorded-command Zig replay matches the opening through frame 640.
- Zig accepts the recorded placements but does not yet reproduce footprint, terrain, adjacency, or
  occupancy rejection. Action masks are absent.
- Infantry sub-cell reservations, egress, directional movement, static obstacle routing, and
  stationary E1/E3 combat exist. Dynamic pathfinding breadth, mixed combat, and terminal state are
  still absent.
- Zig has a canonical internal digest, but full cross-engine RNG/digest parity is not yet claimed.
- Autonomous original-AI behavior in Zig is not yet claimed; the green gate replays Vanilla's
  recorded commands. See `docs/td_micro/m5_easy_ai.md`.

The next gameplay parity slice is the autonomous Easy-AI opening. It must emit the same command
schedule without consuming a recorded command stream, then extend through infantry production,
hunting, combat, and terminal state.
