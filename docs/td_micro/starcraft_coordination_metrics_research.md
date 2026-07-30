# StarCraft Coordination And Attack-Wave Metrics

Date: 2026-07-23

## Question

How should TD Micro distinguish ineffective one-unit attacks from coordinated assaults without
building a brittle, expensive "wave" detector?

## Bottom Line

StarCraft research generally does **not** assign a hand-designed wave identifier during training.
It uses:

1. win rate as the primary task metric;
2. cheap per-step coordination diagnostics such as focus fire and target entropy; and
3. replay or trajectory analysis when researchers need actual combat episodes, squads, or attack
   sequences.

TD Micro should follow the same split:

- Add a few cheap, full-match-only coordination summaries to training logs.
- Save a compact combat trace only for fixed evaluation/promotion runs.
- Derive attacks and waves offline from that trace.
- Do not add these metrics to reward until they have been validated against visible games and win
  rate.

This is simpler and more informative than four literal `firing` percentage bins.

## What The Literature Does

### SMAC: win rate remains the benchmark

The original [StarCraft Multi-Agent Challenge](https://arxiv.org/abs/1902.04043) gives each allied
unit an independent policy, uses the built-in StarCraft II AI as the opponent, and evaluates the
percentage of test episodes in which all enemies are defeated. Its evaluation pauses training every
10,000 steps and runs 32 greedy test episodes.

SMAC explicitly describes focus fire as important, but also shows that a simple heuristic that sends
the whole team against the closest enemy is not enough. Formations, kiting, positioning, and terrain
still matter. Therefore:

- coordinated fire is a useful diagnostic;
- it is not a replacement objective for winning; and
- a high focus-fire score alone must not promote a policy.

SMAC does not define attack waves or synchronized assault episodes.

### Behavior diagnostics: focus fire, entropy, and action transitions

A recent SMAC study,
[Sparse Communication for Policy Shaping in Multi-Agent Reinforcement Learning](https://www.mdpi.com/1424-8220/26/11/3413),
uses win rate as its primary task metric and defines separate behavior-level metrics:

**Focus fire**

```text
mean over attack steps of:
    maximum number of allied agents attacking the same enemy
```

Higher values mean more attackers are concentrated on one target.

**Target entropy**

```text
p_j = attackers assigned to enemy j / all current attackers
entropy = -sum(p_j * log(p_j)) / log(number_of_enemies)
```

Lower values mean more concentrated target selection. This must be interpreted with the number of
attackers: one lone attacker has low entropy but is not a coordinated assault.

**Attack-to-move ratio**

```text
number of agent transitions from attack at t-1 to move at t
-----------------------------------------------------------
number of agent attack actions at t-1
```

This was designed to characterize StarCraft II attack-move micro and is less directly useful for
the present TD Micro question.

The important pattern is that these are evaluation diagnostics, not replacements for win rate.

### Replay analysis: detect combat episodes after the fact

[A Dataset for StarCraft AI and an Example of Armies Clustering](https://ojs.aaai.org/index.php/AIIDE/article/download/12546/12397)
extracts attacks from professional Brood War replays. Its original attack tracker:

- starts around a unit death with at least two military units nearby;
- expands a spatial hull to include participating units;
- refreshes an inactivity timeout as combat continues; and
- records participants, position, attack type, losses, attacker, defender, and outcome.

The later paper
[Automatic Learning of Combat Models for RTS Games](https://ojs.aaai.org/index.php/AIIDE/article/view/12793)
notes that waiting for a death starts the event too late. It instead begins combat when a military
unit is:

- **aggressive**: has an attack order; or
- **exposed**: an aggressive enemy is in attack range.

It then expands participation through nearby/in-range units. This is a reasonable basis for an
offline TD combat-event detector. It still detects an engagement, not a strategic "wave."

### Squad abstraction

[Improving Monte Carlo Tree Search Policies in StarCraft via Probabilistic Models Learned from Replay Data](https://ojs.aaai.org/index.php/AIIDE/article/download/12852/12699/16368)
groups units of the same type in the same map region into squads. A squad has size, average health,
region, current action, target region, and expected completion time. Low-level orders are reduced to
`Move`, `Attack`, or `Idle`, with the most common unit action used as the squad action.

That abstraction is useful later when TD Micro has larger mixed armies. It is unnecessary for the
current E1/E3 scale.

### Preserve traces instead of guessing every useful scalar

[STARDATA](https://ojs.aaai.org/index.php/AIIDE/article/view/12929) stores full game state every three
frames plus player actions across 65,646 StarCraft replays. The
[StarCraft II Learning Environment](https://arxiv.org/abs/1708.04782) likewise emphasizes a game
interface and expert replay data for action and outcome prediction.

The practical lesson is to preserve enough state/action history for offline analysis. A scalar-only
logging design cannot answer future questions that were not anticipated when the run started.

## Mapping To TD Micro

TD Micro differs from SMAC:

- one centralized policy issues one actor/target command per decision;
- old orders persist while later units receive commands;
- each decision advances four game frames;
- E1 and E3 reload periods differ substantially; and
- the state already exposes each infantry unit's mission, target, movement, firing, and cooldown.

Consequently, the policy's latest action is not the army's current joint action. Coordination should
be computed from the persistent per-unit mission and target state.

Literal `firing` bins are also misleading. An E3 can remain correctly committed to a target while
spending much longer on cooldown than an E1. A policy's measured coordination would change merely
because its unit mix changed.

## Recommended Online Metrics

Compute these only on **full refinery matches** and only on **combat samples**. A combat sample is a
decision at which at least one player infantry unit has a live enemy target and an attack/hunt
mission, queued attack mission, or pending attack.

1. `combat_army_participation`

   Mean fraction of living, combat-capable player infantry currently committed to a live enemy.
   One-at-a-time feeding should be low; a broad assault should be high.

2. `focus_fire`

   Mean, over combat samples, of the largest number of committed player infantry sharing one live
   enemy target. This closely follows the published SMAC behavior metric.

3. `target_entropy`

   Mean normalized entropy of committed units across their live enemy targets. Lower is more
   concentrated. Interpret only alongside participation and focus fire.

4. `combat_samples`

   Denominator/context for the three means. It distinguishes "no combat occurred" from a real zero.

The native binding currently exports 25 metrics and PufferLib appends `env/n`, leaving five slots
under the hard limit of 31. These four would leave one slot free.

Do not log four firing bins. They consume all available capacity while losing army size, target
choice, and combat context.

## Recommended Offline Trace

For promoted checkpoints and fixed-seed evaluations, record one compact row per decision:

```text
frame
alive_combat_units
committed_units
moving_units
firing_units
distinct_live_targets
max_attackers_on_one_target
player_damage_delta
enemy_damage_delta
player_losses_delta
enemy_losses_delta
```

An offline analyzer can then:

1. start an engagement on aggression, exposure, or damage;
2. associate nearby units using a fixed spatial radius or connected component;
3. keep the engagement alive while aggression, exposure, or damage continues;
4. close it after a documented inactivity timeout;
5. report participants, commitment spread, duration, damage, losses, and outcome; and
6. optionally merge nearby engagements into a higher-level assault wave.

This makes the contentious timeout and grouping choices analysis parameters rather than simulator
semantics or permanent W&B fields.

## Validation Gate

Before using any coordination metric:

1. Create deterministic fixtures for one-unit feeding, a coordinated group attack, and split-target
   attacks.
2. Verify the expected ordering:

   ```text
   coordinated participation > one-at-a-time participation
   coordinated focus_fire > one-at-a-time focus_fire
   split-target entropy > same-target entropy
   ```

3. Verify that changing E1/E3 cooldown state without changing orders does not change participation
   or target concentration.
4. Repeat traces and require identical hashes and metrics.
5. Benchmark adjacent before/after runs and reject a material SPS regression.
6. Check candidate policies visually and correlate metrics with full-match balanced win rate.

## Recommendation

Implement the four online summaries only after the current CNC23 sweep is no longer sensitive to
schema changes. Add the offline trace first if immediate analysis is needed, because it does not
consume permanent training-log slots and lets us test several definitions on the same games.

The first research question should be:

> At equal army size and scenario mix, do higher participation and focus-fire values predict better
> full-match balanced win rate?

If the answer is no, do not reward or optimize these metrics. They are diagnostics, not the task.
