# TD Micro Opponent No-Units Root Cause

Date: 2026-07-15

## Finding

The original TD opponent AI is active and its production code is running. It builds and places its
Construction Yard, Power Plant, and Barracks. In the earlier close-spawn replay, it produced no
meaningful force: its first infantry completed only after the player had already started destroying
the base. The later ABI-8 medium-spawn replay survived just long enough to produce one E3, but too
late to field an army.

This was caused by stock TD timing, not by Easy/Normal/Hard selecting different build strategies.
TD Micro schema 7 fixes the micro-map mismatch by pinning `AttackDelay=1` in both Vanilla and Zig.
The original AI now fields infantry before the retained policy can execute the old undefended-base
rush.

## Exact Gate

`HouseClass` initializes the computer attack countdown in `tiberiandawn/house.cpp` as:

```cpp
Attack = Rule.AttackDelay * Random_Pick(TICKS_PER_MINUTE / 2, TICKS_PER_MINUTE * 2);
```

The previous schema-6 rules inherited `AttackDelay=5`. With `TICKS_PER_MINUTE=900`, the opening
countdown was a deterministic seeded value in the range `2,250..9,000` TD frames. That is 2.5 to 10
simulated minutes at TD's 15 Hz simulation rate.

For the schema-6 seed-1 oracle:

```text
initial Attack countdown:       3,115 frames
first infantry queue selected:  frame 3,162
first completed infantry:       frame 3,272
first recorded nonzero cap:     frame 3,164
```

Until that gate, `Control.MaxInfantry` is zero. `HouseClass::AI_Infantry()` is called, but its
`CurInfantry >= Control.MaxInfantry` guard correctly prevents production. The canonical idle-player
Vanilla trace then produces five E1 and five E3 and destroys the player's MCV at frame 8,358. That
proves the original AI's infantry production and attack path work when the base survives.

The retained checkpoint reaches the enemy first:

```text
first enemy building destroyed: frame 2,860
enemy base eliminated:          frame 3,396
terminal win:                   frame 3,402
stock first infantry selection: frame 3,162
```

The close-spawn opponent can therefore release a single late defender, but it cannot field a useful
force before the rush reaches and dismantles its base. The medium-spawn case below is even clearer:
its first infantry appears only 63 frames before terminal.

## Difficulty Mapping Bug

Westwood's `DiffType` is a handicap applied to a house, not a user-facing opponent-strength label.
For a computer house, `DIFF_EASY` grants the strongest production/combat bonuses and `DIFF_HARD`
applies the weakest values. The normal skirmish menu therefore inverts the player's requested
difficulty for the computer:

| Requested opponent | Computer house handicap |
| --- | --- |
| Easy | `DIFF_HARD` |
| Normal | `DIFF_NORMAL` |
| Hard | `DIFF_EASY` |

The first TD Micro difficulty implementation passed the label straight through. Consequently, the
run displayed as Easy was actually the strongest computer handicap, and the run displayed as Hard
was the weakest. TD Micro now performs the same inversion as the stock skirmish menu. The historical
seed-1 oracle remains pinned to internal `DIFF_EASY`, so its behavior and fixtures remain unchanged.

This mapping fix does not make units appear sooner. Difficulty changes cost, build-speed, movement,
firepower, armor, rate-of-fire, and related handicap values; it does not change the initial
`AttackDelay` countdown.

## Historical Implication

The checkpoint's Vanilla win is mechanically legitimate, but the schema-6 micro matchup permitted
a zero-army timing exploit. It should not be promoted as evidence that the policy can beat an enemy
army or that the Easy/Normal/Hard curriculum is complete.

## Implemented Contract

Schema 7 pins `AttackDelay=1` in the versioned TD Micro rules rather than adding another runtime INI
toggle. Vanilla applies the generated constant in `TDMicroSettings::Apply_Rules`; Zig derives its
seeded countdown from the same manifest. The underlying Westwood AI phases and production choices
remain intact.

The implementation also follows stock ordering: when the attack countdown expires, the AI raises
its infantry cap as soon as it has a base center, and it may select infantry production before its
Barracks is placed. The production queue itself remains suspended until the Barracks exists. This
ordering matters for exact seeded RNG and frame parity.

The new seed-2 real-Vanilla oracle records:

```text
initial Attack countdown:       1,396 frames
first E3 train command:         frame 1,430
first completed infantry:       frame 1,648
maximum infantry by frame 2,800: 7
```

The rules-manifest SHA-256 is
`bcb23e390785cb3b500f763752ae354a45972ec864356352ea5614d59f2df389`. Existing checkpoints target
the old rules contract and must be retrained before policy-quality claims. Full implementation,
parity, determinism, and throughput evidence is in `docs/td_micro/attack_delay_early_force.md`.

## ABI-8 Medium-Spawn Confirmation

The 2026-07-16 visible run used retained checkpoint `lqn5ogu8`, setup seed 2, policy sampling seed
74, and the original Hard-menu GDI AI. Its packed Vanilla policy-state trace contains 1,935 records
through the terminal at frame 7,739.

The trace establishes:

```text
initial Attack countdown:       6,980 frames
first enemy Barracks visible:   frame 1,060
enemy E1 ever live:             0
first and only enemy E3:        frame 7,676
last enemy E3 observation:      frame 7,712
terminal policy win:            frame 7,739
```

The opponent also built Power Plants, Refineries, Harvesters, and replacement Barracks throughout
the match. Its house AI and construction economy were therefore active. Infantry production was
held at `Control.MaxInfantry=0` by the stock opening countdown for nearly the entire episode; the
single late E3 confirms that the production/release path was not disabled.

For seed 2, the schema-7 `AttackDelay=1` contract reduces the opening gate to 1,396 frames. The AI
then queues its first E3 at frame 1,430 and releases it at frame 1,648, early enough to build a
defending force before the current policy reaches the base.

Future policy promotion gates should record, for each setup profile:

1. initial countdown and the frame where `MaxInfantry` becomes nonzero;
2. first E1/E3 queue and release frames;
3. maximum simultaneously live enemy infantry;
4. first HUNT or ATTACK order; and
5. terminal result and whether the policy encountered a nonzero enemy force.

A visible win should not count as an AI-combat demonstration unless the trace records enemy
infantry production and at least one enemy combat order.
