# Zig-to-Vanilla transfer gap: the simulator's AI is weaker on novel trajectories

Date: 2026-07-25
Checkpoint: `qjnoq207/0000000007342080.bin` (ABI14, hidden 128, balanced_perf 0.588)

## The result

Same checkpoint, same world seed (1), same four policy sampling seeds:

| | Zig simulator | Vanilla |
| --- | ---: | ---: |
| seeds 74, 75, 76, 77 | **4 wins / 0 losses** | **0 wins / 4 losses** |

A systematic flip, not variance. Zig reports `close_win_rate` 0.768 for this checkpoint; Vanilla has
never produced a single win for it.

## Where the traces part

Streaming both sides through the same policy and diffing decision by decision, the observation and
mask are **byte-identical for six decisions**, then differ by exactly one byte:

```
obs[1445]   zig=16  vanilla=20     mask: 0 bytes differ
```

Offset 1445 decodes as entity slot 64 (first opponent entity), field 13 = `progress`: the AI's
building construction progress, off by about one frame. Both encoders compensate for TD's easy AI
counting down 58 frames against a 60-frame animation timeline, and they compensate differently:

- Zig adjusts non-construction-yard buildings, `+3` for easy AI and `+1` for human
- Vanilla adjusts only `STRUCT_CONST`, `+1` for the player and `-3` for the AI

This is a real defect and worth fixing, but it explains only why the two runs become *different
games*. It does not explain a uniform 4/4 to 0/4 flip; diverging trajectories should give
different-but-comparable outcomes.

## What actually explains it

Enemy strength along the same seed, from the observation globals:

| decision | Zig own u/b/i | Zig enemy u/b/i | Vanilla own u/b/i | Vanilla enemy u/b/i |
| ---: | --- | --- | --- | --- |
| 200 | 0/3/7 | 0/3/6 | 0/3/7 | 0/2/6 |
| 400 | 0/5/16 | 0/3/6 | 0/4/16 | 1/3/6 |
| 900 | 0/5/15 | **0/1/0** | 0/5/**9** | **1/4/3** |

Three differences, all in the same direction:

1. **Vanilla's AI fields a unit** from about decision 400 (a harvester, so income). Zig's AI produces
   **zero units** for the entire game.
2. **Vanilla's AI reaches 4 buildings; Zig's reaches 3.** Zig's AI never completes its refinery, so it
   never gains an economy.
3. **Vanilla's AI kills.** Player infantry falls 17 to 9. In Zig it goes 16 to 15.

The policy is not failing to transfer. It was trained against a materially weaker opponent than the
one it meets in the real engine, so its 0.588 balanced_perf is an overestimate of its true strength.

## Why the oracle fixtures did not catch this

`src/ai.zig` can build power plants, refineries, barracks and infantry, and the AI oracle fixtures are
long (`vanilla_seed1_ai_terminal.jsonl` is 26 MB, reaching frame ~7886). They pass.

They validate AI behaviour **along recorded trajectories**. A trained policy explores novel states,
and the AI diverges there. Fidelity on the recorded paths does not imply fidelity on the paths an
agent actually drives the game into.

## Options

1. **Fix the `progress` encoder mismatch.** Small and well understood; removes a known defect but will
   not close the win-rate gap on its own.
2. **Raise Zig's AI to match Vanilla on novel trajectories.** Addresses the real cause, but full-game
   AI parity is a large project and the current fixtures cannot certify it.
3. **Randomise opponent strength during training (domain randomisation).** Rather than chase exact
   parity, train across a band of AI build speed and aggression so the policy generalises to a
   stronger opponent than any single simulated one. This is the cheapest route to a policy that
   survives in Vanilla, and it degrades gracefully when parity is imperfect.

Option 3 is recommended, with option 1 done alongside since it is nearly free. Both are Tier 3
changes: they alter the RL problem, so `balanced_perf` is not comparable across the boundary. The
metric that matters is the **Vanilla win rate**, which is currently 0 of 4.

---

## Root cause: the full chain

Traced end to end, the gap is one timing defect amplified by a credit knife-edge.

1. Zig models AI construction with `ai_construction_frames` (58 for most, 60 for the construction
   yard); Vanilla's real construction runs 60 and 64. Both observation encoders paper over the
   difference with ad-hoc fudges: Zig adds `+3` for easy AI and `+1` for human on non-CONST
   buildings, Vanilla adds `+1` for the player and `-3` for the AI on `STRUCT_CONST` only.
2. The fudges do not cancel exactly, producing the one-byte `progress` divergence at decision 6.
3. That byte reflects a real ~1-frame offset in AI construction timing, so the AI's decision ticks
   fall on different frames in the two simulators.
4. Different tick timing means a different sequence of RNG draws.
5. `HouseClass::AI_Building` gives both the refinery (`BQuantity < 2 ? URGENCY_HIGH`) and the
   barracks (`current > 0 ? URGENCY_LOW : URGENCY_HIGH`) the same URGENCY_HIGH when neither exists,
   then breaks the tie with `Random_Pick(0, num_bestindexes - 1)`. `src/ai.zig` models this
   faithfully with its own coin flip. The two land differently.
6. At 2300 starting credits the flip is decisive. Refinery-first costs `300 + 2000 = 2300`, exactly
   affordable. Barracks-first leaves 1700 and the 2000-credit refinery becomes permanently
   unreachable, so the AI never gets a harvester and never earns income again.
7. Measured: at a raw 10,000-credit reset Zig's AI builds construction yard, power plant, refinery
   (frame 209), barracks (frame 263) and ends with 4 buildings and a harvester -- matching Vanilla.
   In the constrained game it stalls at 3 buildings and 0 units.

This is why the oracle fixtures pass: they were recorded at default credits, where the tie-break is
harmless because both structures are affordable either way. The defect only bites in constrained
games, which is exactly the configuration the GIF target uses.

## Recommended fix, in order

1. **Model construction timing as Vanilla does** and delete both encoder fudges, removing the
   divergence at its source instead of compensating downstream. This is the determinism fix.
2. **Re-diff the streams** to confirm the first divergence moves later or disappears, then find the
   next one. Fixing one divergence usually exposes another.
3. **Record oracle fixtures at constrained credits**, not just default. The current fixtures cannot
   catch this class of defect because they never enter the state where it matters.
4. **Re-measure the Vanilla win rate.** It is the only metric that certifies transfer; `balanced_perf`
   cannot, because it is computed against the simulator being corrected.

Domain randomisation is not a substitute for any of the above. It would make the policy robust to a
band of incorrect opponents rather than correct for the one real opponent, and would leave the
underlying timing defect in place.
