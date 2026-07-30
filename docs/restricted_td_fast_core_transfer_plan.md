# Restricted TD Fast-Core Training And Vanilla Deployment

> Planning background. The narrower, authoritative implementation contract is now
> [`td-micro/SPEC.md`](../td-micro/SPEC.md). In particular, TD Micro v1 starts without a refinery,
> harvester, Weapons Factory, vehicles, or defenses.

The first delivery gate is end to end, not maximum throughput: train on the restricted fixed-map
task, load the same checkpoint in pristine Vanilla-Conquer, and win one complete easy-mode skirmish
without manual commands. Determinism breadth, 50,000 SPS hardening, and held-out win-rate claims come
after that proof works.

## Verdict

The proposed idea is good:

1. Define a smaller but strategically meaningful Tiberian Dawn ruleset.
2. Implement that exact ruleset in a compact Zig simulator for high-SPS training;
3. apply the same restrictions in Vanilla-Conquer; and
4. run the trained policy as the controller inside the real Vanilla-Conquer game and renderer.

This is a credible project if the result is described accurately: **a policy trained in a
high-speed compatible simulator and deployed in the real open-source TD engine under the same
restricted ruleset**. It should not be described as training in the original engine.

The better version is not one-way transfer. Use three connected lanes:

```text
Vanilla TD oracle <-> Zig fast core <-> PufferLib training
       |                                      |
       +-------- exact-engine adaptation -----+
```

Most samples come from Zig. Vanilla continuously supplies traces, differential checks, evaluation,
and a smaller amount of final adaptation data. This makes 50K+ training SPS plausible without
betting the public demo on zero-shot simulator transfer.

## Alternatives Considered

| Approach | Advantage | Main problem |
| --- | --- | --- |
| Keep optimizing and deglobalize Vanilla | Lowest behavior gap | Large legacy-engine refactor; weak evidence it reaches 50K SPS |
| Train only in a simplified Zig clone | Highest likely throughput | Policy can exploit clone differences and fail in Vanilla |
| Hybrid fast core plus Vanilla adaptation | High throughput and a real-engine result | Requires a disciplined shared contract and parity corpus |

The hybrid is the best balance. Vanilla remains the authority and deployment engine, but it is not
forced to generate every training sample.

## Why This Is Defensible

- EA published the TD gameplay DLL source, so Vanilla can remain the behavior oracle and the real
  graphical deployment target. The EA release is GPLv3 with additional terms, which must be
  respected for any public derivative distribution.
- OpenAI Five is a direct precedent for an impressive real-game agent with an explicitly restricted
  ruleset. It initially used a fixed hero subset and disabled mechanics, then played through the
  actual Dota 2 game. Restricted scope did not make the demonstration fake; hiding the restrictions
  would have.
- AlphaStar's full StarCraft II evaluation shows why the real-engine match suite still matters.
  Simulator-only win rates are not enough for the final claim.
- PufferLib's native design favors fixed contiguous state, no per-step allocation, and many native
  environments writing directly to rollout buffers. A pure Zig core with a C ABI fits this much
  better than multiple `dlmopen` TD object graphs.
- RL agents routinely exploit simulator mistakes. Exact replay checks and Vanilla evaluation are
  product requirements, not optional polish.

Sources:

- [EA C&C Remastered source release](https://github.com/electronicarts/CnC_Remastered_Collection)
- [PufferLib native environment documentation](https://puffer.ai/docs.html)
- [OpenAI Five restricted real-game setup](https://openai.com/index/openai-five/)
- [OpenAI Five paper](https://arxiv.org/abs/1912.06680)
- [AlphaStar full-game evaluation](https://www.nature.com/articles/s41586-019-1724-z)
- [OpenAI on agents exploiting environment mechanics](https://openai.com/index/emergent-tool-use/)
- [Dynamics randomization and the simulator transfer gap](https://arxiv.org/abs/1710.06537)

## Recommended First Ruleset: TD Micro v1

Use a GDI-vs-GDI mirror match so both sides share observations, actions, rules, and policy weights.

Include enough TD to preserve the RTS identity:

- construction yard and MCV deployment;
- power plant, refinery, barracks, weapons factory, and guard tower;
- harvester and real tiberium collection;
- E1 minigunner, E3 rocket soldier, Humvee, and medium tank;
- building placement, production queues, power, credits, fog/shroud, movement, pathfinding, combat,
  destruction, and terminal base elimination;
- two or more fixed TD maps, followed by randomized starting locations and a larger map pool;
- original TD unit costs, timings, footprints, weapons, armor, movement rates, and RNG behavior for
  every supported mechanic.

Initially exclude:

- aircraft, engineers, repair facilities, walls, advanced tech, superweapons, crates, civilians,
  campaign triggers, and mission scripting;
- every unsupported unit and building, in both Vanilla and Zig;
- graphics, audio, UI, and wall-clock pacing from the Zig core.

This is much more convincing than an economy-only task while remaining small enough to specify and
port. Expand the allowlist only after the current subset passes parity and transfer gates.

## One Shared Rules Manifest

Do not maintain two handwritten lists. Add one versioned manifest that generates or configures:

- Zig comptime unit/building/weapon tables;
- Vanilla build and production allowlists;
- observation type ids and action masks;
- replay schema id and policy compatibility id.

The local TD source already centralizes legality in `HouseClass::Can_Build`, including `IsBuildable`,
ownership, prerequisite, and build-level checks. A restricted-rules allowlist should be checked before
the existing computer-player early return so the original AI cannot produce excluded objects.

Unsupported content must fail loudly in Zig. It must never silently approximate a unit, weapon,
mission, or map feature and then count that episode as parity-valid.

## Shared Policy Contract

Zig and Vanilla must expose the same versioned contract:

```text
reset(seed, map, ruleset) -> observation, action_mask
step(action, decision_ticks) -> observation, action_mask, reward, terminal
state_digest() -> canonical supported-state hash
```

Use the same:

- compact entity-slot ordering;
- fog-filtered observations;
- multi-head command grammar;
- action masks;
- decision interval;
- terminal and reward definitions; and
- recurrent-state reset semantics.

The policy should consume structured state, not pixels. During the public demo, Vanilla renders the
real match while the policy reads only the information allowed by this shared contract.

## Fast-Core Architecture

Implement the simulator as one coherent Zig-owned state machine, not Zig leaf calls into C++:

```text
step(State, Input) -> State
```

Use:

- fixed-capacity, pointer-free state;
- structure-of-arrays storage for units, buildings, projectiles, and map occupancy;
- integer/fixed-point TD-compatible math;
- deterministic iteration and RNG;
- no allocation, I/O, callbacks, rendering, or tracing on the hot step path;
- snapshot reset by copying a compact initialized state;
- one batched C ABI call that steps many environments and writes directly into Puffer buffers;
- ReleaseFast benchmarks plus scalar/batch hash equivalence tests.

Zig is the recommended language because the existing prototype and tests already use it. C could reach
the same speed; language choice is not the multiplier. State ownership, bounded data, batching, and
removal of the original object/UI runtime are the multiplier. Hot paths must remain allocation-free,
the world must be a serializable value, rendering must stay an adapter, and canonical per-tick hashes
are the determinism gate.

## Transfer And Correctness Gates

### 1. Unit and property tests

Test every supported rule in isolation: costs, prerequisites, placement, movement, collision,
pathfinding, cooldowns, target legality, damage, harvesting, death, and terminal outcomes.

### 2. Differential replay

Record `(setup, seed, ordered actions)` once. Run it through Vanilla and Zig. At every decision tick,
compare canonical supported fields and find the first divergent field automatically.

Do not require raw memory hashes to match across engines. Hash the same canonical schema in both.

### 3. Scenario corpus

Maintain traces for:

- focused mechanics;
- scripted build/economy openings;
- pathfinding around obstacles and congestion;
- squad combat and focus fire;
- harvesting under attack;
- complete restricted skirmishes; and
- adversarial random/fuzz action streams.

### 4. Policy transfer gate

For each checkpoint, run the same policy seeds in both engines and report:

- action disagreement after observation parity;
- first state divergence;
- terminal agreement;
- Zig and Vanilla win rate against identical opponents; and
- unsupported-state count.

### 5. Exact-engine adaptation

Do not rely only on zero-shot transfer. A practical schedule is:

```text
90-99% Zig rollouts + 1-10% Vanilla rollouts/evaluations
```

Use Vanilla data to fine-tune the policy, train an auxiliary behavior-consistency loss, or update the
fast core when the mismatch is a simulator defect. Randomize maps, spawns, opponent policies, and
decision latency for robustness; do not randomize away known TD rules instead of implementing them.

## Performance Gates

Define one RL step precisely, for example one command followed by 8 or 16 TD simulation ticks. Never
compare this with a one-tick microbenchmark.

Initial targets:

| Gate | Target |
| --- | ---: |
| Raw Zig restricted-skirmish decisions | at least 100K SPS aggregate |
| Fixed-hyper PufferLib GPU training | at least 50K SPS |
| Start failures | exactly 0 |
| Per-tick canonical parity corpus | 100% for supported behavior |
| Vanilla policy deployment | real-time with the original renderer |
| Unsupported mechanics reached in certified matches | exactly 0 |

The existing scoped economy core's roughly 73K PufferLib SPS proves the integration can cross 50K for
a small state machine. It does not prove the combat skirmish core will. Movement, pathfinding, combat,
and observation packing each need an explicit budget and benchmark.

## Milestone Order

1. Freeze `TD Micro v1`: roster, maps, timing, action/observation schema, and canonical digest schema.
2. Implement the same restrictions in Vanilla and verify a human can play a complete restricted match.
3. Build the replay corpus and field-level Vanilla trace exporter before adding more fast-core logic.
4. Extend Zig from the existing economy core through real harvesting.
5. Add movement, occupancy, and pathfinding as one owned subsystem.
6. Add targeting, weapons, projectiles, damage, and death as one owned subsystem.
7. Run scripted full matches, then random-action differential matches, until parity is green.
8. Add a simple scripted/original-AI-compatible opponent and train in PufferLib at fixed reported SPS.
9. Run continuous Vanilla evaluations and exact-engine adaptation.
10. Ship a human-visible Vanilla match where config selects `OriginalAI` or `PufferPolicy`.

## Public Claim And Demo

The strongest honest demo is:

> A PufferLib policy trained at high throughput in a behavior-checked Zig implementation of TD Micro,
> then deployed as a controller in the real open-source Tiberian Dawn engine, using the original game
> assets, graphics, map, unit rules, and match loop.

Show the ruleset, parity corpus, transfer win rates, and both SPS numbers. That is more technically
interesting than implying the training simulator and Vanilla are the same binary, and much more
credible than presenting an approximate clone without transfer measurements.
