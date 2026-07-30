# TD Micro Infantry Movement And Egress Parity

Recorded: 2026-07-13

Status: partial M4. Automatic E1/E3 Barracks egress, occupied sub-cell selection, one unobstructed
move, and one static-terrain obstacle route are behavior-matched. This is not yet a dynamic
pathfinding, combat, unreachable-target, or general congestion claim.

## Vanilla Fixture

The canonical opening deploys the MCV, builds and places Power/Barracks, and trains E1/E3. At
decision 245 it commands player actor slot 3 (E1) from local cell `(7,9)` to `(10,9)`. The trace
runs through decision 275, after E1 has returned to guard.

```bash
tools/td_micro_oracle \
  --output /tmp/td_micro_e1_move.jsonl \
  --seed 1 --decisions 275 \
  --deploy-decision 1 \
  --power-decision 23 \
  --place-power-decision 77 --place-x 4 --place-y 7 \
  --barracks-decision 92 \
  --place-barracks-decision 146 --barracks-x 6 --barracks-y 7 \
  --e1-decision 161 --e3-decision 189 \
  --move-decision 245 --move-actor 3 --move-x 10 --move-y 9
```

Two fresh Vanilla processes produced byte-identical output:

```text
ruleset manifest  2cfdb59512771054eb4bf7a4b8b5111fc722b4a1ed5f415c7a172c47d75b9818
trace SHA-256     90e3e0432a9d31facc0a316a94250f7552600ce3ff55da69029979536a1b6ae2
```

`tools/record_td_micro_fixtures.sh` now repeats every canonical trace twice and installs a fixture
only after `cmp` proves the pair is byte-identical.

## Static Map Oracle

`CNC_TD_Micro_Get_Map` exports the 58x49 playable map separately from per-decision snapshots, so
existing action traces are not inflated by repeated terrain. Two fresh processes produced the
same 53,519-byte map fixture:

```text
map fixture SHA-256  b29261be5c42da9e31663fa5fd80dcbbe4b105b00428371b3fda895c85232531
generated Zig SHA-256 c165c0bccba2306f442ff7d9c1945a99c1a91e8e507b23d5b3a41013683e9ec7
```

`zig build generate-map` deterministically emits `generated/scenario1_map.zig`. The test reparses
the oracle JSON and compares all seven fields for every cell, rather than checking only dimensions
or a few samples.

## Obstacle Route

The first route commands E1 from `(7,9)` to `(18,9)`. Static terrain blocks `(15,9)`, directly on
the eastward line. Vanilla travels east to `(14,9)`, southeast to `(15,10)`, northeast to `(16,9)`,
then east to the target. It arrives at decision 349 and guards at 350.

```bash
tools/td_micro_oracle \
  --output /tmp/td_micro_e1_obstacle.jsonl \
  --seed 1 --decisions 350 \
  --deploy-decision 1 \
  --power-decision 23 \
  --place-power-decision 77 --place-x 4 --place-y 7 \
  --barracks-decision 92 \
  --place-barracks-decision 146 --barracks-x 6 --barracks-y 7 \
  --e1-decision 161 --e3-decision 189 \
  --move-decision 245 --move-actor 3 --move-x 18 --move-y 9
```

Two fresh runs were byte-identical at
`4d12f97dcb4ece1c366b2aad8d3b230b8d98a2a069723582bea4e305e6b5f9f1`.

## Ported Behavior

The source-backed movement constants are in the shared manifest: E1 maximum speed 8 and E3 maximum
speed 6. `movement.zig` reproduces the behavior exercised by these traces:

- player commands enter through the same owner-relative entity slot contract as Vanilla;
- the command waits for Vanilla's queued mission boundary;
- the five legal infantry stopping spots and Vanilla's nearest-free lookup order are preserved;
- moving infantry reserve their head spot, matching TD's occupation-bit behavior;
- `Desired_Facing256` and TD's exact 256-byte cosine table drive movement toward the head spot;
- the reachable static branch of TD's `Basic_Path`, `Find_Path`, and clockwise/counterclockwise
  `Follow_Edge` algorithm selects the same first-nine-command path buffer;
- nominal speed 8 therefore moves east by 7 leptons/frame, exactly as Vanilla does;
- reaching a segment within 16 leptons snaps to the exact head coordinate;
- the next cell segment starts on the following frame; and
- final arrival clears the destination and transitions `MISSION_MOVE` to `MISSION_GUARD`.

The explicit movement fixture compares cell, lepton coordinate, head coordinate, facing, mission,
queued mission, driving state, throttle, first path facing, and destination presence at all 31
decision boundaries. It now replays end to end from reset; there is no test-side state injection.

The E3 congestion test compares the same fields at all 16 boundaries from decision 243 through
258. E1 already occupies the preferred upper-left spot, so E3 reserves the center, follows the
slightly southeast lepton path, arrives exactly at `(1920,2432)`, and retains facing 128 when its
automatic egress mission returns to guard.

The obstacle test compares all 106 decision boundaries from command through guard. Its initial path
buffer is `E,E,E,E,E,E,E,SE,NE`, matching Vanilla's nine-cell lookahead. At the turn, the port also
matches Vanilla's center-offset stopping-spot calculation, including the lower-left sub-cell chosen
after the northeast segment. RNG-driven `Random_Animate` facing after entering guard is explicitly
outside this movement slice; all movement-facing values through arrival remain compared.

## Verification

The full suite passes in all required modes:

```bash
zig build test
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
```

The suite has 31 runner tests. The straight-movement
test was first observed red at decision 245 with Vanilla X `1870` versus Zig X `1856`. The E3 test
was separately observed red with Vanilla head X `1920` versus Zig `1856`, proving that it exercised
the occupied-slot branch before the source behavior was ported. The obstacle test was first red at
decision 272 because Zig had no nine-cell path buffer; after integration it matched through
decision 350 in all three build modes.

## Next Movement Gates

1. Extend the completed E1/E3 stationary combat slice to moving attack targets.
2. Add broader two-infantry congestion and unreachable-target fixtures.
3. Add dynamic building/infantry blockages to the path callback.
4. Only then treat movement as usable by the cloned Easy AI.
