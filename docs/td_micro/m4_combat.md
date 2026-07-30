# TD Micro E1/E3 Combat Parity

Recorded: 2026-07-13

Historical note: this file records the isolated M4 duel gate. The later closed-loop combat and
terminal result is authoritative in `docs/td_micro/m5_easy_ai.md`.

Status: M4 combat slice complete. Stationary E1-versus-E1 and E3-versus-E3 mirror duels match Vanilla
frame by frame through projectile flight, damage, both deaths, and object removal. This is not yet
a moving-target, building-damage, mixed-unit, or Easy-AI skirmish claim.

## Oracle Isolation

TD Micro disables unsupported simulation that was changing the shared scenario RNG despite being
outside the restricted ruleset:

- at the M4 milestone, transformable blossom terrain remained static because Tiberium economy was
  not yet implemented; ABI 7 supersedes that historical limitation; and
- only the two configured participant houses run `HouseClass::AI`.

These restrictions apply only when `td_micro_v1` is enabled. Normal Vanilla TD behavior remains
unchanged. They removed nine terrain RNG calls per frame and neutral-house startup calls from the
combat oracle, leaving a trace composed only of supported state transitions.

Oracle schema 6 exports scenario RNG, infantry fear/ammo/kill count and animation state, plus
projectile source/target identity, current and desired facing, speed accumulator, fuse timer,
arming delay, and proximity. It also exports Easy-AI state and timestamped high-level commands.
Those fields are compared rather than inferred from final health.

## Canonical Fixtures

The strict fixtures advance one TD frame per recorded decision:

```bash
tools/td_micro_oracle --output /tmp/e1.jsonl \
  --seed 1 --decisions 160 --advance-frames 1 \
  --fixture 1 --attack-decision 1 --attack-actor 1 --attack-target 1

tools/td_micro_oracle --output /tmp/e3.jsonl \
  --seed 1 --decisions 400 --advance-frames 1 \
  --fixture 2 --attack-decision 1 --attack-actor 1 --attack-target 1
```

`tools/record_td_micro_fixtures.sh` ran each fixture in two fresh Vanilla processes and required
byte equality before installation:

```text
E1 frame trace SHA-256  e7efa06ca6798dd984ddc08ccaf25159a40b427c940d1421a954a1bb3376fe18
E3 frame trace SHA-256  cd9ed95ae354e62b5e7d15710a4f14872dd57c287997e2da07f44f2595c887a7
```

The complete schema-6 fixture set, including reset, construction, production, egress, straight
movement, and obstacle routing, was also regenerated twice without a mismatch.

## Ported Behavior

The Zig combat path now includes the source LCG and rejection-sampled `Random_Pick`, guard mission
timers, target acquisition, infantry firing animation launch frames, cooldowns, and generated,
source-backed weapon/projectile/warhead constants from manifest schema 3.

E1 uses the M16 instant bullet path. E3 uses the TOW path with exact launch scatter, homing target
updates on odd frames, five-step facing rotation, 10-lepton speed accumulation, arming and
proximity fuse behavior, and the prior-coordinate detonation behavior in the Vanilla source.

Explosion handling preserves TD distance, 384-lepton scan range, SA/AP versus unarmored modifiers,
spread attenuation, prone damage reduction, fear transitions, death animations, target/source
detachment, and delayed object removal. A lethal hit also executes
`InfantryClass::Made_A_Kill` in source order: `Random_Pick(0, 5)` first, then the wrapping 16-bit
crew kill increment.

The canonical opening digest is now:

```text
837ccd9cad6e1d19c9a577330ec0b770aeeee5a110d915691cdf24c362a3736d
```

Two independently replayed worlds must match that digest before the pinned value is checked.

## Verification

All 59 tests pass in every required mode:

```bash
zig fmt --check src tests build.zig
zig build test
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
```

The E3 test was first red because the Zig port rejected E3. During TDD, the final first divergence
moved to frame 338, where Vanilla had advanced RNG from `2681161004` to `3730574325`. GDB tied
that transition to `InfantryClass::Made_A_Kill`; porting the draw and kill increment made all 401
snapshots match. E1 then passed after its older fixture was refreshed to include schema-6 state.

## Known Limits

- The duel starts in range; attack movement and target reacquisition after movement are untested.
- Damage to buildings, MCVs, mixed E1/E3 groups, and simultaneous splash victims is unported.
- The post-kill stoked/comment animation path after later kills is not implemented.
- The seed-1 production fixture explicitly preserves its observed E1 salute delay and immediate E3
  egress. General `Random_Animate` parity remains an Easy-AI prerequisite.
- No claim is made yet about full-skirmish RNG/hash parity or training SPS.

## Next Gates

1. Record a restricted Easy-AI GDI-versus-GDI action/state trace.
2. Port the minimum AI production, targeting, and attack-movement behavior needed by that trace.
3. Add terminal win/loss and full-episode replay hashes before PufferLib integration.
