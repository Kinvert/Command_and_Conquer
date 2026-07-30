# CNC33 combat diagnosis and repairs

Authoritative as of 2026-07-28. CNC33 was stopped before any simulator, observation, action, or
reward changes below were made.

## Result

CNC33 did not improve with more suggestions. At the 36-finished-trial snapshot:

- median `full_perf`: 0.0150
- mean `full_perf`: 0.0169
- maximum `full_perf`: 0.0520
- chronological first-half versus second-half mean at the earlier 31-trial check: 0.0178 versus
  0.0172
- correlation of `train.total_timesteps` with `full_perf`: -0.03

This is below CNC32's 0.1237 maximum and nowhere near the 0.30 target. The mostly-zero training
curve is partly a sampling presentation problem: full wins are rare and each training log window
contains few completed full matches. It is not only presentation, however; the final evaluation
population is poor.

## What the policy learned

The policy reaches the requested economy and armour state. Median final-evaluation behavior was:

| Metric | Median |
|---|---:|
| Refineries built | 2.78 |
| Harvested credits | 10,444 |
| Medium Tanks built | 0.94 |
| Tank shots | 8.52 |
| Tank kills | 1.40 |
| Raw full-match win rate | 0.094 |
| Qualified-loss conversion | 0.160 |
| Unit kills / losses | 4.96 / 19.26 |
| Buildings destroyed / lost | 0.56 / 3.95 |
| Full-match loss rate | 0.717 |

Tank discovery is not the bottleneck. The policy builds a tank, fires it, and loses the subsequent
fight. CNC33 rewarded the existence and first use of armour but supplied no clean way to learn
which actors should engage which targets.

## Reward evidence

These are univariate correlations over 36 Protein suggestions, not causal estimates. Protein's
parameters can be correlated, so the table is evidence for direction and not a proof.

| Swept input | Refineries | Tank build rate | Tank use rate | Qualification | `full_perf` |
|---|---:|---:|---:|---:|---:|
| `reward_refinery` | +0.320 | +0.285 | +0.288 | +0.040 | +0.132 |
| `reward_first_tank` | +0.148 | -0.222 | -0.249 | -0.128 | -0.186 |
| `reward_first_tank_shot` | +0.054 | +0.116 | +0.148 | -0.028 | +0.103 |
| softer `reward_qualified_loss` | +0.104 | -0.169 | -0.159 | +0.037 | -0.145 |

The refinery reward is the only swept signal that consistently moved its intended behavior and
downstream armour behavior in the useful direction. The softer qualified loss did not increase
qualification, and the first-tank reward did not increase tank reach. CNC32's best policy used
`reward_refinery ~= 0.494` and `reward_enemy_building_loss = 1.0`; CNC33 capped refinery at 0.1 and
fixed enemy-building loss at 0.25.

## Observation defects

Friendly and enemy entities do expose a slot-aligned object type, position, health, mission, and
category. That does not mean the policy has been given usable matchup knowledge:

1. Object types are ordinal bytes (`E1=5`, `E3=6`, `Medium Tank=10`) divided by 255 and fed into
   one flat linear encoder. There is no categorical type representation.
2. The 2,456-byte observation, map/economy state, and as many as 128 entity records are compressed
   into a 64-value hidden state. There is no slot-wise entity encoder.
3. Armour, weapon, range, damage, and armour-versus-warhead modifiers are not observed. They must
   be inferred from outcomes.
4. Infantry observations include target, weapon cooldown, and firing state. Vehicle observations
   incorrectly put `harvest_timer` in the cooldown field and omit vehicle target, weapon cooldown,
   turret facing, and firing state.

The repair bumps the observation version, preserves the legacy-v4 layout, appends a 255-valued
one-hot object-type vector to every current entity record, and exposes the missing vehicle combat
state.

## Action defect

ABI14 represents one group attack as 64 independently parameterized binary friendly selectors and
one enemy target. Every selected actor receives the same target. Although all logits share a hidden
state, the target logits are not conditioned on the sampled group and the selector logits are not
conditioned on the sampled target. It is an awkward representation for:

- E1 attacking infantry while E3 attacks vehicles;
- a tank focusing or avoiding enemy E3;
- separate simultaneous target assignments;
- retreating or repositioning a group.

The repository already has a tested ABI13 action path with a learned actor-query/target-key
interaction. It samples one actor, then scores targets conditional on that actor. The repair
extends ABI13 to Weapons Factories, Medium Tanks, and Humvees and makes it the explicit training ABI.
This trades one-command group selection for a directly learnable actor-to-target assignment.

## Missing evidence

Prior W&B logs cannot say whether an E1 attacked infantry, whether an E3 attacked a vehicle, or
whether a tank focused the E3s killing it. They contain aggregate attacks and aggregate deaths only.

The repair adds episode counters and exported rates for:

- E1 attack orders targeting infantry;
- E3 attack orders targeting vehicles;
- Medium Tank attack orders targeting E3;
- player Medium Tank deaths caused by E3.

These are diagnostics, not rewards. They make type-aware combat falsifiable without adding another
behavioral objective.

## Curriculum defect

The existing H0/H1 fixtures contain pure E1, pure E3, and mixed infantry assaults. The H2 armour
fixture teaches vehicle production, not vehicle combat. No scheduled fixture specifically presents
an E3-versus-tank or tank-versus-E3 decision.

The repair adds both counter-matchup assault profiles to the reverse curriculum:

- player E3 versus opponent Medium Tanks;
- player Medium Tanks versus opponent E3.

They retain the normal short terminal objective. No per-shot or per-matchup reward is introduced.

## Reward reset

The next baseline uses the evidence-backed objective before another sweep:

- restore a meaningful one-time refinery reward at `0.4`;
- restore enemy-building destruction to `1.0` as the dense signal aligned with winning the match;
- keep first-tank and first-shot rewards small and one-time at `0.1` each;
- restore every loss, including a qualified loss, to `-1.0`;
- keep production spam, infantry-count, income-drip, unit-kill, vehicle-count, and tank-kill
  rewards at zero.

The intent is not to reintroduce a large collection of signals. It is to retain two finite,
goal-aligned waypoints while moving matchup learning into the observation, action, and curriculum
contracts where it belongs. This makes the refinery reward larger than either individual tank
event despite the earlier intuition that it should be smaller: CNC33 measured refinery reward as
the only waypoint that improved refinery, tank-build, and tank-use behavior together. The next
sweep therefore varies only refinery reward over `[0.3, 0.6]` plus the requested 5-10M total
timesteps; it does not resweep the reward terms that failed to improve conversion.

## Implemented repair

- Observation v7 uses 28-byte entity records with explicit one-hot object type and vehicle
  target, weapon cooldown, turret facing, and firing state.
- ABI13 now supports Weapons Factory, Medium Tank, and Humvee production, vehicle movement, and
  vehicle attacks. Its target logits are conditioned on the selected actor.
- H1 sampling includes deterministic player-E3-versus-enemy-tank and
  player-tank-versus-enemy-E3 profiles.
- Completed-episode metrics and Puffer logs expose the four matchup rates listed above.
- The training config uses ABI13 explicitly, a 128-value hidden state, and the reward baseline
  specified in this note.
- CNC33 remains stopped; no replacement sweep was launched while implementing or validating these
  changes.

## Validation gates

Before a new sweep:

1. Observation tests must prove one-hot E1/E3/tank identity and vehicle target/cooldown/turret/fire
   state.
2. ABI13 tests must prove Weapons Factory and vehicle production are legal and actor-conditioned
   target logits can select different targets for different actor slots.
3. Telemetry tests must prove every numerator and denominator increments only on the intended
   applied action or lethal hit.
4. Curriculum tests must prove both counter-matchup profiles reset deterministically and expose
   legal attacks.
5. Debug, ReleaseSafe, and ReleaseFast Zig suites, the C ABI/order checks, the Puffer binding test,
   and the sweep-config test must pass.
6. A short native GPU preflight must report `start_failures=0` before any new W&B project is
   launched.

## Validation result

All 311 Zig tests pass in Debug, ReleaseSafe, and ReleaseFast. The ABI field-order and size checks,
C API smoke, Puffer binding test, sweep-config tests, and native-extension rebuild also pass.

The native CUDA preflight used:

```bash
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 --vec.num-buffers 1 --vec.num-threads 4 \
  --train.total-timesteps 262144 --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 128 --policy.num-layers 1 \
  --env.action-scheme 0 --env.action-abi 13 \
  --checkpoint-interval 100000000 --eval-episodes 1
```

It completed at 32,284 displayed SPS with `start_failures=0`, `failures=0`, and
`invalid_actions=0`. The run is valid as a startup/integration gate, not as a learning or speedup
claim. Its final log also contained the new matchup fields, proving the telemetry reaches Puffer:
`e1_infantry_target_rate=0.601`, `e3_vehicle_target_rate=0.037`,
`tank_e3_target_rate=0.000`, and `tank_e3_loss_share=0.000`.
