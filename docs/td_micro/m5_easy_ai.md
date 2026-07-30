# TD Micro Closed-Loop Easy-AI Parity

Recorded: 2026-07-13

Status: the canonical seed-1 no-player match now has exact closed-loop Zig/Vanilla parity through a
legitimate player defeat. This completes the first M5 trace, not the entire M5 gate: scripted-player
terminal traces and randomized seed/action coverage remain open.

## Canonical Result

The original Vanilla Easy GDI AI autonomously deploys its MCV, builds Power and Barracks, produces
five E1 and five E3 infantry, enters `MISSION_HUNT`, and destroys the idle player's MCV.

| Field | Result |
| --- | --- |
| Ruleset | `td_micro_v1` |
| Setup seed | `1` |
| Decision interval | 4 TD frames |
| Recorded decisions | 2,090 |
| Terminal frame | 8,358 |
| Outcome | player defeat |
| Final supported entities | 13 opponent objects |
| Startup/content violations | 0 |

Vanilla's terminal call has unusual but source-faithful frame semantics. The pre-terminal state is
already frame 8,358. One more `Logic.AI()` call fires the killing bullet, removes the last player
object, marks the player defeated, and returns on `PlayerLoses` before `Frame++`. Zig explicitly
matches this same-frame terminal transition.

## Differential Contract

The long test starts from `World.reset(1)` and lets the Zig Easy AI choose and execute its own
commands. No recorded opponent commands are replayed. At every four-frame oracle boundary it
compares:

- exact frame and shared scenario RNG state;
- both players' credits, power, drain, and defeat flags;
- Easy-AI state, timers, selected products, base center/radius, and maxima;
- structure and infantry production queues;
- every active unit, building, and infantry object's owner, type, position, health, mission,
  cooldown, movement, animation, prone/fear, ammo, kills, and target validity;
- every active projectile's pool ID, type, coordinates, fuse, strength, current/desired facing,
  speed accumulator, timer, arming, proximity, source, and target; and
- emitted Easy-AI commands with their exact TD frame.

The terminal fixture is generated in two fresh Vanilla processes and must be byte-identical before
installation:

```text
td-micro/tests/fixtures/vanilla_seed1_ai_terminal.jsonl
SHA-256 4d3e3228139de9af7125cfb540aa677dbe3b324b20111e9ee17182613148a3d2
```

The preceding sparse infantry/hunt trace is also deterministic:

```text
td-micro/tests/fixtures/vanilla_seed1_ai_infantry_hunt.jsonl
SHA-256 13325e5cb1b79f27951e55237e7eacd40ffe2e775c0ccedcd929db1a030b185b
```

## Source-Faithful Fixes

The first-divergence workflow found and pinned several ordering details that final-state-only tests
would miss:

1. `InfantryClass::Take_Damage` clears `IsFiring`; infantry AI re-arms the existing fire animation
   without restarting its stage.
2. Vanilla object AI consumes combat RNG before `HouseClass::Expert_AI` consumes its delay draw.
3. E3 TOW fire against an MCV is accurate and consumes no launch-scatter RNG; infantry targets use
   the inaccurate branch.
4. Projectile pool slot order is not simulation order. Zig keeps a dense creation-order list so an
   older TOW advances before a newer instant bullet that reused a lower pool slot.
5. TOW splash can set infantry fear after its AI pass; the next frame decrements fear and begins
   `DO_LIE_DOWN` exactly as Vanilla does.
6. Destroying the last object consumes kill-credit RNG before invisible-impact scatter RNG, then
   terminates without advancing the frame or Easy-AI timers.

TD Micro disables random crew survivors from destroyed vehicles and buildings because C1/C7 are
outside the declared E1/E3 content set. This is one ruleset restriction, is covered by the Vanilla
settings test, and is inactive when TD Micro is disabled.

## Determinism Artifacts

```text
rules/td_micro_v1.json          2cfdb59512771054eb4bf7a4b8b5111fc722b4a1ed5f415c7a172c47d75b9818
generated/td_micro_v1.zig       b1834b414cfdf4b83e5cfacc438c2abd6d4b37868375f726809e6b670bea08fd
generated/td_micro_v1.h         6f5c512e9b1b28038ab4e945e419095dcd898d920a71b49b57b67d0249f0a830
canonical Zig opening digest     837ccd9cad6e1d19c9a577330ec0b770aeeee5a110d915691cdf24c362a3736d
```

`tools/record_td_micro_fixtures.sh` records every fixture twice and compares the bytes. The complete
fixture corpus passed that gate after the terminal fixture was added.

## Verification

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache zig build test --summary all
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache zig build test -Doptimize=ReleaseSafe --summary all
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache zig build test -Doptimize=ReleaseFast --summary all
```

All three modes pass 59 of 59 tests. The fixture recorder's independent two-process byte comparisons
also pass.

## Remaining M5 Work

- Add at least one closed-loop scripted-player trace through timeout or terminal.
- Expand from seed 1 to deterministic seed/action sweeps once reset generation supports more seeds.
- Exercise simultaneous player/opponent production and combat, including player victory.
- Replace the current per-trajectory exceptions discovered by broader traces only when the Vanilla
  oracle proves the required behavior.

No PufferLib SPS claim follows from this milestone. Compact observations/actions, batched stepping,
GPU-path training, checkpoint inference, and visible Vanilla policy control are the next vertical
slice.
