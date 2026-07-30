# `lqkwukxi` Visible Vanilla Validation

Date: 2026-07-15

## Result

Checkpoint `lqkwukxi/0000000001048576.bin` now completes a real Vanilla TD auto-skirmish against the
original GDI AI. This run assigned the computer house internal `DIFF_EASY`, which is TD's strongest
computer handicap despite the enum name. The corrected headless render-path replay ended with:

```text
terminal reason=win frame=3402 decisions=851 accepted=793 changed=79
player_defeated=0 opponent_defeated=1 failed=0
```

Checkpoint SHA-256:

```text
7c8734032f8a214c1108c8793f2013af2dc223acccdd87da13456fc65ec56a72
```

The policy uses seeded categorical sampling in visible Vanilla. The runtime log pins
`sampling=categorical seed=74`; the old independent-head greedy decoder remains available only for
diagnostics.

## Opponent Infantry Timing

The winning visible trajectory contained no enemy infantry, but the original AI was active. Its
internal object counts changed as follows:

```text
frame 0:    1 MCV, 0 buildings
frame 12:   0 MCV, 1 building
frame 292:  2 buildings
frame 508:  3 buildings
frame 2860: 2 buildings
frame 2968: 1 building
frame 3396: 0 buildings
frame 3402: terminal win
```

The canonical seed-1 Vanilla oracle does not create its first infantry until frame 3,936. The
computer's initial `Attack` timer keeps `Control.MaxInfantry` at zero until frame 3,935. This policy
began destroying the base at frame 2,860 and won 534 frames before that first-infantry point. The
absent enemy infantry is therefore expected stock-AI opening timing, not evidence that the AI house
was still disabled.

This is a legitimate engine win, but it is not evidence that the policy beat a fighting Hard army.
The tiny map lets it destroy the production base before the stock AI's army-opening timer expires.
The full root cause and proposed curriculum correction are in
`docs/td_micro/opponent_no_units_root_cause.md`.

## Bugs Found By The First Display Run

### Original AI house was skipped

The TD Micro guard at the start of `HouseClass::AI` treated only entries below `MPlayerCount` as
participants. Auto-skirmish has one local player (`MPlayerCount=1`) and one AI ghost
(`MPlayerGhosts=1`). The opponent is `HOUSE_MULTI1`, outside the loop, so its entire house tick
returned early.

Consequences in the first visible run:

- the original opponent house AI did not execute;
- it never built a normal base or attack force;
- `Check_Pertinent_Structures` did not execute for that house;
- after its MCV died, internal counts were zero while `IsDefeated` remained false.

The fix explicitly recognizes the single supported skirmish ghost as the second TD Micro
participant. A regression test covers `HOUSE_MULTI1`, rejects other houses and modes, and requires
exactly one ghost.

### Early-win option was not enabled

TD Micro's Zig terminal rule follows Vanilla's pertinent-structure condition: a side loses when it
has no live non-wall building or MCV. The auto-start path had not enabled `Special.IsEarlyWin`.
Auto-start and restricted manual setup now enable it explicitly.

### Visible inference used greedy heads

The trained policy is stochastic. Independent argmax selected an illegal placement loop and was not
the policy evaluated by PufferLib. The Zig C ABI now exposes a separate seeded categorical action
function, and the Vanilla controller uses that path.

### `FrameLimit` is not simulation speed

`Video.FrameLimit` only limits rendering. TD simulation cadence comes from `Options.GameSpeed`:

- `GameSpeed=4`: original 15 simulation frames per second;
- `GameSpeed=1`: 60 simulation frames per second, the visible 4x setting;
- `GameSpeed=0`: unlimited, used only for automated replay.

Visible inference was restored to `GameSpeed=1` and `FrameLimit=60` after validation.

## Validation

Vanilla test suite:

```text
ctest --test-dir build-td --output-on-failure
14/14 passed
```

The canonical 1,600-decision Vanilla opponent trace was regenerated in two fresh processes after
the difficulty mapping correction. Both outputs and the retained fixture were byte-identical:

```text
SHA-256 13325e5cb1b79f27951e55237e7eacd40ffe2e775c0ccedcd929db1a030b185b
first infantry command: frame 3,935
```

The unlimited replay used the normal Vanilla executable with dummy SDL rendering, the original AI,
scenario 1, environment seed 1, and the exact retained checkpoint. Before the fix, the opponent had
zero structures because its house tick was skipped. After the fix it had three live buildings by
frame 1,396 and reached Vanilla's normal `opponent_defeated=1` terminal at frame 3,402.

This validates one fixed sampled trajectory in Vanilla. Broad Zig-to-Vanilla outcome-rate parity
still requires a multi-seed replay harness; it should not be inferred from this single visible-path
win.
