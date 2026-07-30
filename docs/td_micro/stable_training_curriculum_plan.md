# TD Micro Stable Training And Curriculum Plan

Date: 2026-07-23

Status: H0-H5 reverse-curriculum implementation validated. Schedule 0 remains the unchanged
full-match control; schedule 1 walks backward from finishing combat to H5 while retaining
full-match anchors. The next H5 domain independently mixes MCV-only and symmetric reduced Unit
Count 6 starts. Matched learning and multi-seed robustness results are still pending.

## Decision Summary

TD Micro is ready for better experimental discipline, but it is not yet ready for a single 50M-step
"final" run. Four foundations should be fixed first:

1. Sweep on a robust terminal-win metric computed from an exact common evaluation suite.
2. Use the accepted exact full-training-state continuation so a 2M checkpoint can become the
   prefix of a declared 50M schedule instead of starting a different cosine schedule from scratch.
3. Keep one curriculum-wide observation/action contract and change legal content through a
   versioned curriculum manifest and masks.
4. Replace the flat observation encoder before attempting another action decoder. The next action
   decoder should point into actual entity and spatial embeddings, not add more opaque slot logits.

The fixed evaluator's recommended promotion scalar is an epsilon-shifted harmonic mean over H5
spawn x starting-force cells, named `robust_perf`. Protein optimizes H5-only `balanced_perf`, the
arithmetic mean of those cells; it is a candidate-generation metric, not sufficient promotion
evidence. Credit-aware promotion expands the score to all 16 spawn x force x credit-band cells.

The proposed curriculum is:

```text
E1/E3 roster, AttackDelay 5
  -> E1/E3 roster, transition to AttackDelay 1
  -> forced refinery/harvester discovery with temporary shaping
  -> low-credit economy under AttackDelay 1 while shaping decays
  -> unshaped low-credit refinery + E1/E3 matches
  -> distance/credit diversity
  -> one new production family at a time
  -> full easy, normal, and hard restricted TD
```

This rules progression is only one curriculum axis. The second axis is the episode's **start-state
horizon**: begin with valid states close to a win, then move the reset point backward through
assault, production, economy, deployment, and finally the full MCV opening. TD Micro can exploit
this reverse curriculum because it owns the complete simulator state and has exact snapshot/restore.

Here, "two units" means the two enabled infantry types, E1 and E3. It does not mean that only two
individual infantry start on the map.

## Current Evidence

The original CNC13 sweep process stopped without a traceback after 817 completed trials. The final
183 trials were restarted with the same project, tag, 2M budget, sweep ranges, ABI, and runtime
binary, but Protein began with a new optimizer state. The resulting 1,000-run population is valid
for candidate and distribution analysis, but it is two consecutive adaptive searches rather than
one uninterrupted Protein trajectory. The final CNC13 report must state that distinction.

### Historical sweep metric through CNC22

The binding used by the historical CNC22 process computes:

```text
balanced_perf = 0.5 * (close_win_rate + medium_win_rate)
```

This is the expected win rate under a uniform close/medium deployment distribution. It is a useful
reported statistic, but it permits severe specialization. The interim CNC13 raw leader illustrates
the problem:

| Candidate | Close | Medium | Arithmetic balanced | Minimum profile |
| --- | ---: | ---: | ---: | ---: |
| `iqttpc1r` | 0.0769 | 0.8142 | **0.4455** | 0.0769 |
| `4pkdtoqj` | 0.2021 | 0.6414 | 0.4218 | 0.2021 |
| `hmc7f77r` | 0.4777 | 0.3060 | 0.3918 | 0.3060 |
| `pm00cpye` | 0.3250 | 0.3697 | 0.3474 | **0.3250** |
| `9xosu4au` | 0.3417 | 0.3223 | 0.3320 | 0.3223 |

The arithmetic objective ranks a policy that almost never wins close games above policies that win
roughly one third of both profiles. That is not the desired generalization pressure.

### Evaluation sample count

The trainer currently permits final evaluation for at most half as many epochs as training. It also
stops if `eval_episodes` is reached, but a 2M run normally exhausts the epoch cap first. Episode count
therefore depends on policy behavior: a slow or passive policy can be scored from fewer completed
matches than an aggressive policy. Candidates do not necessarily see the same exact policy-sampling
seed sequence either.

More importantly, the training loop does not reset worlds at the train/eval boundary. The final
training log clears completed log records, then evaluation advances the same in-progress episodes.
The first games credited to "final evaluation" can therefore contain decisions made by earlier
training policies before being completed by the frozen final policy. Different candidates also
arrive at the boundary in different world states and at different points in their episode-seed
streams. `static_vec_eval_log` accumulates those completions without repairing the boundary.

In an interim 839-run CNC13 audit, final episode counts ranged from 117 to 409 with median 218. With
64 live worlds, up to 64 first completions can straddle the boundary: 29.4% of the median sample and
54.7% of the shortest sample. This is an upper bound, but it is too large to dismiss.

This should be replaced by an exact episode-count evaluator before treating small score differences
as real. The evaluator must start fresh worlds and fresh policy state from a versioned held-out seed
list after loading the final checkpoint.

There is already a useful starting point in `tools/cnc11_abi9_tournament.py`: it loads each
checkpoint into a new native runtime and gathers a common episode budget. It avoids the
training-world boundary defect. It still uses an implicit aggregate reset stream, accepts vector
overshoot, emits no ordered per-episode evidence, and is not connected to Protein. Harden and
generalize this evaluator rather than duplicating it.

### Observation

Observation version 5 transports 2,456 bytes:

| Region | Shape |
| --- | ---: |
| Globals | 64 bytes |
| Authored Tiberium cells | 344 bytes |
| Own entities | 64 x 16 bytes |
| Opponent entities | 64 x 16 bytes |

Transport is already compact. The neural encoder is the weak part:

```text
2,456 heterogeneous bytes
  -> divide every field by 255
  -> one dense 2,456 x hidden-size projection
  -> MinGRU
```

This treats object types, mission ids, bit flags, booleans, coordinates, health, and production
progress as the same kind of scalar. It also ignores the repeated structure of entity records.
Concrete scale problems include:

- a presence boolean becomes `1/255 = 0.0039`, while full health becomes `1.0`;
- map coordinates in `[0, 63]` occupy only the bottom quarter of the normalized range;
- small object/mission ids are treated as ordered near-zero magnitudes; and
- Tiberium presence is represented by `45/255` versus depleted `56/255`, even though this is a
  binary resource fact rather than a continuous magnitude.

There is a second correctness problem. Active units, buildings, then infantry are compacted into 64
slots. Adding a building can shift every infantry slot, dead infantry are compacted, and the
generated simulator arrays currently permit 16 units, 64 buildings, and 128 infantry across the
world. A policy can therefore lose detail and control access to legal infantry before the declared
soft terminal. The encoded `entity_id` also uses the compacted active-object index rather than the
stable simulator-array index, so it does not repair the identity shift.

### Action

ABI9 samples seven independent heads:

```text
command, actor, product, target_kind, target_x, target_y, target_slot
```

Its masks prove only that each head value is useful somewhere. They do not prove that the assembled
tuple is legal. The reproducible ABI9 control rejects about 44.9% of decisions as four-frame no-ops.

ABI10/11/13 proved that exact conditional sampling can run in the native CUDA trainer with zero
invalid actions. They did not improve learning. ABI13 reaches 0.384 reproducibly at 1M but falls to
0.092 at 2M, while the matched ABI9 control reaches 0.422. Therefore:

- legality is necessary for a long-term interface, but was not the only learning blocker;
- invalid-action penalties are not a repair and were already rejected experimentally;
- another slot-logit decoder should not be built before the observation supplies meaningful entity
  and spatial embeddings.

Raw entropy is also not comparable across these ABIs. ABI9 sums seven always-sampled categorical
entropies, while exact decoders sum only active conditional branches. Reusing one `ent_coef` does
not impose equal exploration pressure. Future decoder comparisons must report command entropy,
active-argument entropy, and entropy normalized by legal branch capacity offline. Either calibrate
or sweep entropy regularization separately for each decoder, or test one predeclared normalized
entropy bonus as its own ablation. The terminal-win evaluator remains the selection criterion.

ABI9's rejected tuples also act as an accidental wait prior: about 44.9% of decisions advance four
frames without applying a semantic command. An exact decoder initialized nearly uniformly can
therefore issue commands much more frequently even when every optimizer hyperparameter is copied.
The structured decoder should retain one learnable canonical no-op and predeclare its initial
command bias. Compare an unbiased initialization with a bias calibrated to ABI9's measured initial
semantic-command rate. Track semantic commands per game frame; do not recreate waiting through
invalid tuples.

### Continuation

Fresh 1M, 2M, and 3M runs using nominally identical hyperparameters are not prefixes of one another.
PufferLib derives the cosine schedule from requested `total_timesteps`, so changing the endpoint
changes every intermediate learning rate. Weights-only continuation also loses optimizer, RNG,
counter, and environment state and has already failed.

Exact single-GPU native split-run equivalence passed on 2026-07-21. A 262,144-transition CUDA run
split at 131,072 produced exact final state, policy, post-split action/reward/terminal trace, and
environment metrics across 61 completed post-split episodes. Full-state experiments must declare
the immutable final schedule through `train.schedule_timesteps`; changing only the stopping rung
does not alter that schedule. See `cnc13_training_state_checkpoint.md`.

### Recurrent state

Current training has `reset_state=True`, which zeros native MinGRU rollout state at every horizon.
The CNC11 external evaluator sets `reset_state=False`; native rollout code does not mask recurrent
state on individual environment terminals, so state can carry across horizons and into a later
episode. Those are different policy semantics.

Do not change generic PufferLib MinGRU behavior or defaults as part of TD work. First make the
historical baseline internally consistent: evaluation and visible inference use the same declared
fixed-horizon resets as training. Then test PufferLib's existing MLP as a separate baseline because
the state-fed simulator is intended to expose a complete Markov state.

Only if recurrence demonstrates a reproducible need should TD test carry-through-episode state with
lane-local terminal reset. That path must be CNC-specific and opt-in. Prefer a TD policy/backend
adapter; if a minimal generic hook is unavoidable, preserve every existing Puffer default and add
non-CNC regression tests. Persistent recurrent state must then be included in full-state
checkpoints. Do not redesign PufferLib core recurrence for this project.

### Current sweep interpretation

CNC13 jointly varies optimizer/model settings and eight reward coefficients. Protein proposals are
adaptive rather than independent samples, and the last 183 proposals come from a restarted
optimizer. The campaign can find candidate configurations and reveal gross failure regions, but it
cannot establish that one reward term, optimizer setting, or interaction caused an improvement.
Future reward, architecture, curriculum, and annealing claims need paired campaigns that hold every
other family fixed.

## Sweep Objective

### Primary objective

Let each required evaluation profile have win rate `p_i` and deployment weight `w_i`, with weights
summing to one. Use:

```text
epsilon = 0.01
robust_perf = max(0, 1 / sum_i(w_i / (p_i + epsilon)) - epsilon)
```

This shifted harmonic mean has useful properties:

- it remains in `[0, 1]`;
- if every profile has the same win rate `p`, the score is exactly `p`;
- it strongly penalizes one weak profile without the high variance and large flat regions of a hard
  minimum;
- one perfect profile cannot hide a zero profile; and
- it generalizes directly from close/medium to larger curriculum profile sets.

The score is namespaced by an immutable evaluation-suite id containing the profile set and weights.
`robust_perf` is comparable across trials in that suite, not across arbitrary suite versions. For
example, a close/medium score is not numerically compared with a later close/medium/far x credit
bucket score. Start a new W&B campaign when the required profile manifest changes and retain the
old suite as an explicit anchor evaluation.

For the four interim CNC13 examples above, approximate `robust_perf` values are:

| Candidate | `balanced_perf` | Proposed `robust_perf` |
| --- | ---: | ---: |
| `iqttpc1r` | **0.4455** | 0.152 |
| `4pkdtoqj` | 0.4218 | 0.310 |
| `hmc7f77r` | 0.3918 | **0.373** |
| `pm00cpye` | 0.3474 | 0.346 |
| `9xosu4au` | 0.3320 | 0.332 |

This ranking matches the desired preference for competence on both starts while preserving a smooth
signal for Protein.

Do not use any of these as the sweep objective:

- shaped `episode_return`;
- units built, kills, income, or milestone counts;
- peak training win rate; or
- raw arithmetic mean without a profile-imbalance term.

Those remain diagnostics. The objective is held-out terminal win probability.

If nearly every C0 sweep trial has zero held-out wins, do not replace the objective with shaped
return merely to give Protein a gradient. That means the curriculum entry task, budget, or policy
initialization is still too hard. Simplify C0, increase the fixed budget, or test behavior cloning
until terminal wins become measurable.

### Draws and failures

- A legitimate timeout draw contributes zero wins, just like it does to current `perf`.
- A loss contributes zero wins to `robust_perf`; terminal reward remains `-1`.
- Any start or engine failure invalidates the run for promotion.
- Failure rate must not be folded into the score in a way that lets Protein trade correctness for
  wins.

### Fixed evaluation suite

Every candidate in one experiment must use the same ordered tuples of:

```text
(curriculum profile, setup seed, policy-sampling seed)
```

Use three disjoint, versioned seed banks:

| Bank | Used for | Visibility |
| --- | --- | --- |
| Train | Environment resets that generate PPO experience | May be sampled repeatedly by training |
| Sweep validation | The common suite whose scalar is returned to Protein | Fixed for the entire campaign |
| Promotion audit | Reproduction, ablations, and release claims | Never returned to Protein or used to choose sweep trials |

The promotion bank is necessary because a 1,000-trial optimizer can indirectly overfit even a
nominally held-out sweep suite. Do not replace or edit that bank after seeing a candidate's result.
Create a new versioned experiment instead. Real-Vanilla transfer scenarios are an additional audit,
not a substitute for the untouched Zig promotion bank.

Recommended budgets:

| Use | Games per required profile | Training seeds |
| --- | ---: | ---: |
| Broad sweep scoring | 128 | 1 |
| Candidate confirmation | 512 | 3 |
| Major architecture/reward ablation | 1,000 | at least 5 |
| Real Vanilla transfer gate | Existing SPEC gate, at least 200 total | promoted models only |

Evaluation must continue until the exact game count is complete, independent of episode duration or
training budget. The evaluator should reset recurrent state and worlds at the evaluation boundary
and use the run's declared recurrent-reset contract exactly. Training and held-out seed banks must
be disjoint and versioned.

The suite also declares policy action selection. The primary mode must exactly match intended
deployment in visible Vanilla, including sampling versus argmax and any temperature. For stochastic
deployment, the policy-sampling seed is part of each tuple. A deterministic argmax result may be
reported as a diagnostic, but it is not silently mixed with sampled-policy results.

Implement this as a dedicated post-training evaluator, not another tail of the training vector:

1. Save final weights to a temporary local checkpoint even for sweep trials.
2. Construct a fresh evaluation vector with the candidate's exact model shape.
3. Reset worlds, recurrent state, environment seeds, and policy-sampling RNG from the suite id.
4. For the retained MinGRU baseline, reproduce its current fixed-horizon reset points exactly; do
   not carry state into a different horizon or episode.
5. Record per-episode results and retain exactly the first `N` declared tuples per profile; parallel
   completion overshoot is not part of the score.
6. Compute `robust_perf`, write the JSONL evidence, report one final scalar to Protein, and remove the
   temporary checkpoint unless the run is promoted.

Assign suite tuple ids to vector lanes explicitly. On terminal, a lane records that tuple id and is
assigned its next declared tuple; it does not obtain seeds from an implicit incrementing reset
stream. Final JSONL order is tuple-id order, not wall-clock completion order. This makes the result
independent of which parallel episode finishes first and gives exact reruns a meaningful file hash.

Protein can receive the final scalar replicated across its expected curve bins, as the existing
match-sweep mode does. For fixed-budget searches, a trustworthy endpoint is more valuable than
fitting a contaminated training/evaluation curve.

### Promotion statistic

Protein should maximize `robust_perf` during a sweep. Promotion is stricter:

1. Recreate each finalist from a clean source/config manifest under at least three training seeds.
2. Evaluate all finalists on the same untouched promotion-audit suite.
3. Rank by median training-seed `robust_perf`, then worst-seed minimum-profile win rate.
4. Require every training seed to have nonzero wins in every required profile.
5. Use a stratified bootstrap over training seeds and profile episodes to report a 95% interval.
6. Promote only if the paired interval versus the retained baseline supports the claimed gain.

For major claims, report the interquartile mean and performance profile in addition to the median.
The recommendation follows the uncertainty-aware evaluation practices in
[Agarwal et al.](https://arxiv.org/abs/2108.13264), adapted to TD's profile and seed hierarchy.

## Observation Strategy

### Decision

Do not train a reconstruction autoencoder and do not compress the 2,456 bytes further yet. Keep
`ByteTensor` transport and build a field-aware encoder trained end to end with PPO.

The observation work should happen in two isolated steps.

### Step O1: capacity and identity correctness

Define a generated observation schema whose entity capacity covers every state legal under the
selected rules manifest. Do not guess a fixed 64-slot limit independently of the gameplay caps.

Required properties:

- every controllable owned entity is addressable by the action decoder;
- every targetable opponent entity is represented;
- object identity remains stable across births, deaths, and unrelated construction;
- presence holes are masked rather than compacting all later identities;
- category/type ids are append-only within a schema; and
- observation and action code use the same slot/id mapping.

Identity needs to be stable for an object's entire lifetime, not consume an unbounded new row for
every object ever produced. Internal infantry indices cannot serve this purpose because TD Micro
intentionally compacts that array after deaths. Assign each created object a policy-facing slot from
a deterministic world-level free list; carry that slot with the object through internal compaction,
and release it only at death. Expose a generation id so reuse is unambiguous. A reused row is absent
or changes generation before representing the new object; unrelated births and deaths never
renumber still-live objects.

One global table sized from the generated simultaneous world capacity is preferable to two guessed
64-row tables. Include owner in each record and derive owned/opponent actor masks from it. The
temporary independent-head baseline must expand its actor/target vocabulary to the same generated
capacity; preserving the literal 65-value ABI9 pointer would preserve the truncation bug.

Pin this with tests that fill every generated capacity, kill an early infantry object while later
objects remain live, compact internal infantry, create a replacement object, and round-trip every
live policy slot through observation, legality mask, decoded command, save/load, and world digest.
Any silent drop, alias, or remap of a still-live object is a failure.

This will require an observation ABI bump and new checkpoints. It should be done once before the
curriculum becomes a long-lived experimental platform.

### Step O2: structured encoder on exact public state

Use four components:

1. **Global branch:** field-specific normalization for credits, power, time, counts, and progress;
   explicit booleans; embeddings for queue product and failure/status enums.
2. **Entity branch:** one shared MLP over each entity record, with embeddings for type/category/
   mission/status and normalized numeric fields. Preserve per-entity embeddings for action pointers
   and masked-pool them for the recurrent torso.
3. **Resource/spatial branch:** use the fixed scenario id to select immutable terrain, then encode
   live Tiberium at its known coordinates. Start with a small coordinate-aware resource set encoder;
   add a raster/CNN only if a matched ablation improves control.
4. **Fusion:** concatenate global, pooled own, pooled opponent, and spatial summaries and project to
   the MinGRU hidden size.

After O1 is frozen, every arm of the first encoder comparison should consume the same corrected
observation bytes and simulator behavior. The flat arm must be retrained on that schema; the old
observation-v5 checkpoint remains a historical external baseline, not a checkpoint-compatible arm:

| Encoder | Purpose |
| --- | --- |
| `Normalize255Encoder` | Retrained flat ABI9 baseline on the corrected schema |
| Field-aware globals + flat records | Isolate numeric/categorical semantics |
| Shared entity encoder + pooling | Test object-set inductive bias |
| Shared entities + spatial/resource branch | Test map reasoning |

Match hidden size and approximate parameter count where possible. Compare learning curves at fixed
steps, not just final scores. The custom native CUDA path needs a scalar CPU reference, explicit
forward/backward parity, deterministic checkpoint hashes, and the same implementation in visible
Zig/Vanilla inference. Keep it selected by the `cnc_micro` model/backend contract; do not change
generic `Normalize255Encoder`, `DefaultDecoder`, MinGRU, or other Puffer environments.

### Information boundary

Keep the current state-fed boundary: public exact gameplay state comparable to what the original AI
can inspect, but no opponent-controller RNG, private build plan, or private timers. Do not introduce
an arbitrary local crop. A crop would hide strategy-relevant bases, resources, and paths and turn a
fully observable control problem into an unrelated memory problem.

## Action Strategy

### Immediate baseline

Keep ABI9 available and unchanged while metric, fixed evaluation, full-state continuation, and the
structured encoder are established. It is the strongest measured learning baseline despite its
invalid tuples. Keep ABI13 as the exact-action control.

### Proposed production action

The next action model should emit one complete semantic command in one Puffer transition:

```text
command
  -> optional product
  -> optional owned-entity pointer
  -> optional entity-target pointer or spatial-target pointer
```

Command branches:

| Command family | Active outputs |
| --- | --- |
| No-op | command only |
| Deploy | owned MCV pointer |
| Start build / train | product id |
| Place | legal construction-cell pointer |
| Move | movable actor pointer -> map-cell pointer |
| Attack | armed actor pointer -> opponent-entity pointer |
| Harvest | Harvester pointer -> live-Tiberium-cell pointer |
| Return cargo | Harvester pointer -> owned-Refinery pointer |

Key requirements:

- Zig remains the legality authority and exports exact conditional masks.
- Only the selected branch contributes log-probability, entropy, PPO ratio, and gradient.
- `target_kind`, queued placement product, and other state-derived fields are not sampled.
- No-op has one canonical representation.
- Actor queries come from the selected entity embedding.
- Entity target keys come from actual target embeddings.
- Spatial target keys come from actual map/resource embeddings.
- Spatial scoring uses a low-rank query/key form instead of materializing
  `actors x 4,096 cells` as independent dense logits.
- The downstream semantic command remains compatible with the Vanilla controller adapter.

This is the AlphaStar/SCC pattern reduced to TD's needs: structured state, command-conditioned
arguments, entity pointers, and only necessary dependencies. See the
[AlphaStar paper](https://www.nature.com/articles/s41586-019-1724-z),
[SCC](https://arxiv.org/abs/2012.13169), and the
[SC2 learning-environment specification](https://arxiv.org/abs/1708.04782).

The important difference from ABI13 is that actor/target scores consume the encoded objects and
cells they refer to. ABI13's bounded interaction is still generated from opaque global torso output
rows and does not provide a shared entity representation.

### Curriculum compatibility

The command, product, and object vocabularies must be supersets for all stages covered by a
checkpoint. A stage disables unsupported content through masks; it does not resize heads or reorder
ids. New content is appended only with a declared model/action schema change.

Optional behavior cloning from original-AI state/command records should be tested after the
structured decoder works. It is a warm-start ablation, not a substitute for terminal RL.

### Deferred temporal and group control

Do not add a delay head or hidden macro-actions to the first structured decoder. Once canonical
no-op and valid-command rates are measured, a bounded wait argument can be tested only with correct
variable-duration reward accumulation and `gamma^frames` discounting. Report semantic game-frame
throughput as well as Puffer transitions so longer waits cannot create a fake SPS gain.

Likewise, one-actor commands are sufficient for the first E1/E3 vertical slice but may become an
action-rate bottleneck as armies grow. The faithful extension is persistent control groups or an
autoregressive selected-unit set, followed by one target command, matching RTS selection semantics.
Do not introduce type-wide scripted attack macros that the visible Vanilla controller cannot
represent. Group control is a later isolated action-schema experiment.

## Curriculum Design

### Representation

Do not add a growing set of unrelated INI switches. Define versioned profiles in one generated
curriculum manifest. A run selects one `curriculum_schedule_id`; the schedule names profile ids and
mixture weights.

A profile contains at least:

```text
ruleset id
enabled roster and products
opponent difficulty and AttackDelay
starting-credit bucket
spawn-distance bucket
start-state template id
authored force/economy/placement parameter buckets
temporary curriculum masks
reward/shaping profile id
```

Profile selection must be deterministic from the episode seed. Include the public profile id in the
observation whenever profiles with different rules are mixed.

A world's selected profile is immutable until terminal/reset. Global curriculum weights may evolve
with restored training steps, but AttackDelay, credits, enabled content, masks, and shaping scale do
not change inside a live match. Newly reset worlds sample from the current deterministic mixture.
Checkpoint state therefore includes each world's active profile plus curriculum sampler counters.

### Start-state horizon and reverse curriculum

The curriculum has two independent dimensions:

1. **Rules complexity:** enabled units/buildings, economy restrictions, opponent pressure, distance,
   and difficulty. This is the existing C0-C7 progression.
2. **Start-state horizon:** how much of the match remains for the policy to solve. This ranges from
   issuing the final useful combat commands to playing the entire match from an undeployed MCV.

Do not materialize the full Cartesian product. Each curriculum stage declares a small authored set
of compatible start templates. The active distribution moves along a narrow frontier, retaining a
few solved states and a full-match anchor.

The implemented E1/E3 plus Refinery/Harvester start-state bank is:

| Start id | Episode begins with | Skill exposed | Initial success gate |
| --- | --- | --- | --- |
| H0: finish | Player Construction Yard plus 16 idle E1, 16 idle E3, or an 8/8 mix near the enemy Construction Yard; no defenders or future enemy production | Issue useful attacks and finish a legal win | Bootstrap only; never a promotion score |
| H1: assault | The same three 16-infantry packages at approach distance against two E1 plus two E3 defenders; future enemy production disabled | Move, fight defenders, select targets, and finish | Tactical bridge only |
| H2: mobilize | Operational Construction Yard, Power Plant, Refinery, Barracks, free Harvester, no infantry, and 1,200 credits | Produce an army and launch it | Production-to-combat bridge |
| H3: economy | Operational Construction Yard, Power Plant, Refinery, free Harvester, no Barracks or infantry, and 300 credits | Harvest, build production, and convert income into combat | Economy-to-production bridge |
| H4: opening | Deployed operational Construction Yard and normal 10,000 credits | Execute the restricted build/economy opening | Opening bridge |
| H5: full match | Stock deterministic two-MCV reset against the original Easy AI | Solve the real restricted match end to end | Only training profile counted by the sweep objective |

These thresholds are provisional experiment gates, not reward values. They must be evaluated on
fixed held-out profile seeds and at least three training seeds before promotion.

H0 directly covers near-endgame states such as many Minigunners or many Rocket Soldiers near the
enemy base. Future expansions should vary more than raw unit count:

- force composition: E1-heavy, E3-heavy, and mixed;
- force-value tier: overwhelming, favorable, and approximately even;
- approach geometry: near, medium approach, and at least one obstacle/flank placement;
- remaining enemy assets: MCV, Construction Yard, or a small legal base;
- defenders: none, E1-heavy, E3-heavy, and mixed where supported; and
- health/cargo/credit buckets only after full-health states work.

Use authored force-value packages rather than independently sampling every count. E1 and E3 have
different cost and combat roles, so equal unit counts do not imply equal difficulty. Keep training
and held-out combinations distinct; for example, train on several compositions and positions while
reserving at least one composition/position pairing for generalization evaluation.

Near-win states must still require the policy to act. At reset:

- policy infantry start in GUARD with no target, no pending attack, and no live projectile that can
  complete the win automatically;
- no scripted opponent or projectile damage can complete the win for the policy;
- a no-op policy must lose or time out rather than inherit a scripted victory; and
- every terminal win must be caused by legal commands available through the normal policy ABI.

### Start-state construction contract

Represent each start state as a versioned, declarative setup recipe. A recipe begins from a normal
ruleset reset, then applies deterministic setup operations such as assigning credits, adding legal
operational buildings, adding units in free cells, setting Harvester cargo, or advancing an authored
action prefix. Hash the recipe and generated state.

Use two construction paths:

1. **Authored state builder:** appropriate for controlled combat packages and economy substates.
   It must update house scans, power/drain, occupancy, ownership, AI bookkeeping, production queues,
   and terminal bookkeeping through validated helpers rather than raw external memory writes.
2. **Scripted pre-roll:** appropriate when hidden Vanilla timing matters. Start a full match, apply a
   fixed legal action trace for a declared number of frames, then capture the resulting state. Cache
   the generated snapshot so training reset remains fast.

The existing whole-batch snapshot format remains the exact continuation mechanism, but opaque batch
snapshots should not be the curriculum's source of truth. Add a world/profile reset API that can
construct one selected profile per environment regardless of vector width. The batch snapshot then
serializes the selected profile, episode ordinal, sampler state, world, metrics, and milestones.

Pre-existing achievements are baseline state, not newly earned rewards. A profile that starts with
a Power Plant, Refinery, Harvester, or infantry must initialize milestone and metric baselines so the
first policy step cannot collect rewards for setup work. Recurrent policy state resets at the start
of every partial episode. Put a public rules/profile id in the observation only when legal actions,
temporary masks, or hidden rules differ; ordinary unit positions and credits should be learned from
the state observation itself.

Every recipe must pass these gates before training:

- two resets from the same setup seed produce identical complete world hashes;
- snapshot and restore produce an exact continuation hash;
- all objects are legal, collision-free, observable, and below fixed capacities;
- Zig and Vanilla agree on the declared state and scripted continuation checkpoints;
- a scripted policy can solve the intended subtask;
- a no-op policy cannot receive a free terminal win;
- terminal outcomes and reward baselines are correct; and
- adjacent native and Puffer benchmarks show valid throughput with zero failures.

### Horizon sampling schedule

Schedule ids currently exposed through `curriculum_schedule_id` are:

```text
0  full matches only
1  deterministic H0-H5 reverse curriculum with H5 anchors
```

Schedule 1 uses one sweepable duration, `curriculum_stage_decisions`, measured independently for
each lane in policy decisions. It is not measured in completed episodes: short H0/H1 games cannot
accelerate the schedule or expose a lane to more easy games. Five transition phases precede pure
H5 play:

| Phase | Exact episode-start mixture |
| --- | --- |
| 0 | 3% H0, 77% H1, 20% H5 |
| 1 | 20% H1, 60% H2, 20% H5 |
| 2 | 20% H2, 60% H3, 20% H5 |
| 3 | 20% H3, 60% H4, 20% H5 |
| 4 | 20% H4, 80% H5 |
| 5+ | 100% H5 |

The phase is `min(5, lane_decisions / curriculum_stage_decisions)`. The default phase length is
4,096 decisions per lane; Protein sweeps the single categorical value
`256, 512, 1024, 2048, 4096, 8192, 16384`. This keeps curriculum pace identifiable instead of
adding separate thresholds for every transition. In a 2,097,152-transition, 64-agent run, the
default gives 32,768 decisions per lane: pure H5 begins at decision 20,480 and occupies the final
12,288 decisions.

An independent `starting_force_ramp_decisions` clock controls H5 starting-force difficulty.
Reverse training starts with 25% reduced Unit Count 6 games and linearly reaches 75% after that many
per-lane decisions. Protein sweeps 2,048, 4,096, 8,192, and 12,288; at the default H phase length
these complete midway through H0 through the end of H2. Fixed evaluation remains exactly 50%
MCV-only and 50% Unit Count 6. The policy therefore sees occasional defended H5 anchors from the
beginning, progressively faces them more often, and retains a permanent MCV-only domain where a
conditional rush remains valid.

Within a phase, profile selection is a deterministic permutation of lane and episode ordinal. It
has the exact percentages over 100 lanes and, unlike a contiguous slot assignment, places H5
anchors inside the actual 64-lane training batch. H0 appears only in phase 0 and only at 3% of
episode starts. H0/H1 rotate deterministically through E1, E3, and mixed packages.

The pure-H0 sampler remains internal test machinery and public C/Puffer validation rejects it. The
batch snapshot stores schedule id, H-stage duration, force-ramp duration, per-lane decision count,
episode ordinal, and active profile. Exact resume therefore cannot replay an earlier stage or
choose a different reset. Loading only model weights into a new process remains a new run, not exact
continuation.

### Curriculum verification

The red/green suite checks:

- exact phase mixtures and H5 presence in the real 64-lane shape;
- progression by decisions rather than episode count;
- deterministic E1, E3, and mixed package selection;
- no inherited H0 win or setup milestone reward;
- legitimate scripted terminal H0 wins through normal policy actions;
- exact snapshot/restore of schedule state; and
- rejection of invalid/public test-only schedules.

Vanilla oracle fixtures cover all three H0 packages, all three H1 packages, and H2-H4. Zig tests
compare the complete declared authored state: RNG, credits, power/drain, Tiberium/capacity/income,
object identity and count, ownership, position/coordinates, health, facing, missions, status, and
cargo. Each fixture recording is required to repeat byte-for-byte. H5 continues to use the existing
stock-reset parity path.

Validation on 2026-07-21 produced:

- `zig build test`: 181/181 tests passed;
- fresh-cache ReleaseFast build: passed;
- standalone C/Puffer binding smoke: `episode_return=0.250 draw_rate=1`;
- fixed-evaluator tests: 6/6 passed;
- focused sweep-config tests: 2/2 passed;
- unchanged full-match C digest on both runs:
  `cdde069f216661b92e5e030650698b1a7a54641c5e9d1dc068a9b6aa9a2ece4f`;
- native A/B/A/B repeats with 64 worlds and 4,096 iterations: full match averaged 165,754 SPS,
  schedule 1 averaged 156,268 SPS, all failures were zero, and each mode repeated its exact digest;
- forced-transition CUDA smoke: 262,144 timesteps, 64 agents, one buffer, four threads, horizon 32,
  minibatch 2,048, hidden 64x1, GPU, stage/timeout 512, 83,634 final SPS,
  `start_failures=0`, failures zero; and
- production-shaped CUDA run: 2,097,152 timesteps with the same vector/model shape, stage 4,096,
  timeout 12,000, 36,632 final SPS, `start_failures=0`, failures zero. The endpoint H5-only
  `balanced_perf` was 0.0253. This is an end-to-end validation run, not a robust-policy claim.

The production run exposed a telemetry contamination problem: early H1-heavy windows reported
mixed `perf` around 0.85 while H5-only `balanced_perf` remained zero. The H5 metric correction now
excludes every H0-H4 terminal from live `perf` and `draw_rate` plus internal loss accounting, and exports
`full_match_episode_share` so the anchor workload is auditable. Historical pre-correction `perf`
must not be compared with the corrected field; historical `balanced_perf` remains H5-only.

```bash
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --env.curriculum-schedule-id 1 --env.curriculum-stage-decisions 4096 \
  --env.max-decisions 12000 --train.gpus 1 \
  --vec.total-agents 64 --vec.num-buffers 1 --vec.num-threads 4 \
  --train.total-timesteps 2097152 --train.horizon 32 \
  --train.minibatch-size 2048 --policy.hidden-size 64 --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

### Hardest-scenario sweep objective

Curriculum episodes choose the training distribution; they do not define success. Close/medium
spawn counters record only H5 episodes. Therefore Protein's configured `balanced_perf` objective,
plus `perf` and `draw_rate`, are H5-only even while schedule 1 trains on H0-H4. H5 loss rate is
derived as `1 - perf - draw_rate`.
`full_match_episode_share` reports the H5 fraction. Episode return, production, combat, and economy
logs remain mixed diagnostics and can be inflated by easier starts; they must not select a
curriculum winner.

Promotion remains stricter than the live sweep objective. `tools/cnc_micro_fixed_eval.py` forcibly
sets schedule 0, H-stage length 0, and force-ramp length 0, then evaluates the frozen policy on the
declared fresh H5 suite and reports `robust_perf`. This prevents the default schedule-1 INI from
silently evaluating easy starts. `full_match_episode_share` replaces `close_episode_share`, keeping
the native log under the 31-field limit before Puffer appends `env/n`.

The first controlled experiment compares schedule 0 against schedule 1 at matched simulator,
reward, model, optimizer, budget, and training seeds. Schedule-1 H-profile pace and starting-force
pace are swept independently through `curriculum_stage_decisions` and
`starting_force_ramp_decisions`. Candidates are ranked by H5-only `balanced_perf`, reproduced
across training seeds, and promoted only by fixed-suite H5 `robust_perf`. H0-H4 outcomes never
substitute for end-to-end wins.

### Proposed stages

| Stage | Match content | Opponent | Economy | Training aid | Exit target |
| --- | --- | --- | --- | --- | --- |
| C0: build/combat bootstrap | MCV, Power Plant, Barracks, E1/E3 | Easy, AttackDelay 5 | Fixed credits; Refinery masked | At most one PP; small build/combat potential | Reliable wins on both current starts |
| C1: pressure | Same roster | Blend Delay 5 -> Delay 1 | Same | Reduce build potential | Retain Delay-5 skill and win under Delay 1 |
| C2: economy discovery | Add Refinery/Harvester | Delay 5 | Low credits | Barracks/infantry masked until first delivery; economy potential | Deploy, harvest, then field E1/E3 reliably |
| C3: economy pressure | Same | Blend Delay 5 -> Delay 1 | Low credits | Remove first-delivery mask; anneal potential toward zero | Win with free build order under pressure |
| C4: terminal-only micro | Refinery/Harvester + E1/E3 | Delay 1 | Low credits | No curriculum-only masks; shaping zero | Robust terminal wins on close/medium |
| C5: generalization | Same | Delay 1 | Deterministic credit buckets | Add far start after parity gate | Robust score across distance/credit cells |
| C6: vehicles | Add Weapons Factory, then Humvee, then Medium Tank | Easy | Full restricted economy | One production family per substage | Combined-arms wins |
| C7: game progression | Expanded restricted TD | Easy -> Normal -> Hard | Increasingly stock-like | No reward hints | Held-out Zig and real-Vanilla wins |

C2 intentionally makes harvesting unavoidable for the discovery lesson. This is cleaner than
paying a large repeatable refinery reward. C3 removes the artificial sequencing mask, and C4
removes shaping, so the final policy is free to choose a better build order or a legitimate rush.

Before C2, scripted feasibility tests must establish:

- the intended power/refinery/Harvester/first-delivery/Barracks path succeeds;
- one Power Plant is sufficient for the enabled slice;
- a no-harvest policy cannot fund the designated combat-force threshold;
- both Zig and Vanilla agree on the profile; and
- the opponent can still defeat a passive player.

### Stage mixtures and forgetting

Do not replace one stage distribution with another in one step. Use a deterministic transition
window, initially:

```text
first 10% of a new phase: linearly move from 80/20 previous/new to 20/80
steady phase:              80% current / 20% retained anchor profiles
```

The retained 20% should cover prior pressure/economy skills, not every historical profile equally.
Held-out profiles are never sampled for updates.

Uniform deterministic mixing is the first baseline. Once the profile bank is large enough, compare
it with Prioritized Level Replay, which prioritizes levels with estimated learning potential
([Jiang et al.](https://arxiv.org/abs/2010.03934)). Do not make adaptive level selection part of the
first curriculum implementation because it would confound the stage design.

### Temporary shaping

Prefer environment constraints and prerequisites over reward hints. Existing build prerequisites
already enforce much of the order. For the remaining discovery aid, use a bounded state potential
rather than independent event payments:

```text
F(s, s') = shaping_scale * (gamma * Phi(s') - Phi(s))
```

An initial C2 potential can combine normalized indicators for:

- deployed Construction Yard;
- sufficient power without redundant Power Plants;
- operational Refinery and live Harvester;
- first Tiberium delivery;
- operational Barracks; and
- a small target combat-force value.

Keep `Phi` bounded and versioned. C3 anneals `shaping_scale` to zero; C4 holds it at zero. Do not
sweep separate milestone coefficients once this path is active. Potential-based shaping is the
standard policy-invariant form under its assumptions; see
[Ng, Harada, and Russell](https://ai.stanford.edu/~ang/papers/shaping-icml99.pdf).
Changing the shaping scale over training makes the learning reward nonstationary, so the invariance
argument does not by itself validate the annealed curriculum. That is why C4 includes a substantial
zero-shaping phase and why shaping-on/off/annealed must be an explicit ablation.

Terminal reward remains:

```text
win  +1
loss -1
draw  0
```

`perf`, `balanced_perf`, and `robust_perf` remain terminal statistics in `[0, 1]`. Shaped episode
return is a diagnostic and is never called performance or used for sweep selection.

## Annealing And Continuation

### Absolute schedules

Every schedule must be a function of restored global training steps, not the requested endpoint of
the current command. A run stopped at 2M and resumed to 50M must exactly match an uninterrupted 50M
run through the split point.

Required state includes:

- model weights;
- optimizer moments;
- rollout/replay contents needed by the algorithm;
- trainer and CUDA RNG state;
- global step/epoch and schedule position;
- recurrent and environment state; and
- curriculum sampler/profile counters.

The current full-state work is accepted only when an uninterrupted run and one or more split/resume
runs produce exact checkpoint and environment-state hashes at the same final step.

### Schedule ablations

Do not jointly sweep schedule shape with rewards, encoder, and action ABI. After exact continuation:

1. fixed learning rate;
2. global cosine with a nonzero floor;
3. fixed entropy coefficient;
4. global entropy decay; and
5. shaping-scale decay over C2/C3.

Compare at fixed 1M, 2M, 5M, and 10M checkpoints using the common evaluator. Extending a run must
not retroactively alter its earlier schedule.

## Experimental Program

### Phase 0: make measurements trustworthy

1. Finish the current CNC13 population and document it as the final ABI9/current-metric baseline.
2. Finish the already in-progress exact full-state checkpoint/resume work and return to a clean
   commit boundary.
3. Harden the fresh-runtime evaluator into fixed common-seed promotion evaluation, exactly match the
   declared recurrent reset semantics, and retain evaluator-side `robust_perf`; the live Puffer log
   stays under the 31-field limit and uses H5-only `balanced_perf` for candidate generation.
4. Require a clean source commit, exact config manifest, binary hash, and zero failure counters for
   every new campaign.

No observation, action, reward, or curriculum claim should be mixed into Phase 0.

### Campaign protocol

Use a fixed-budget broad sweep followed by exact multi-fidelity continuation. Do not take a good
2M configuration and launch a fresh 50M process with a newly stretched schedule.

An initial protocol is:

1. Sweep 256-1,000 configurations to 2M under the actual long-horizon absolute schedules.
2. Reproduce the top 16 robust configurations at 2M with three training seeds.
3. Continue the top eight exact training states to 5M.
4. Continue the top three to 10M under at least three seeds.
5. Continue the retained champion lineage through curriculum gates toward 50M.

At every rung, endpoint `robust_perf` is the sweep/promotion performance statistic. Earlier
checkpoints are diagnostics and curriculum-retention gates; they are not added to shaped return.
Reject a candidate that fails a predeclared prior-stage retention gate or has a statistically
supported collapse. Otherwise rank the latest endpoint, not a noisy peak selected after inspection.

Disable ordinary score-based early stopping for the broad fixed-budget comparison. If compute later
requires pruning, use only predeclared rungs with the fresh common evaluator and retain enough
candidates to measure false-pruning risk. Never let a contaminated training-log peak decide which
trial receives more steps.

Within one campaign, freeze simulator, reward profile, curriculum distribution, observation/action
schema, encoder, seed suites, and training budget. Sweep optimizer/model hyperparameters only. Test
reward shaping, curriculum, encoder, decoder, and schedule families in separate paired ablations.

### Phase 1: direct-learning baseline

Run the current ABI9/observation-v5 environment with the new evaluator. Re-rank retained CNC13
candidates under `robust_perf`, reproduce the top robust candidates across three seeds, and retain
one baseline checkpoint family.

### Phase 2: observation ablation

With actions, rewards, profiles, and optimizer settings fixed:

1. current flat normalization;
2. field-aware encoding;
3. shared entity encoding;
4. shared entity plus resource/spatial encoding.

Use paired train/eval seeds and parameter-matched models. Promote the simplest encoder with a
reproducible robust gain. This phase must also close entity identity and capacity correctness.

### Phase 3: action ablation

With the promoted structured encoder fixed:

1. ABI9 independent heads;
2. ABI13 exact slot-logit control;
3. structured command/entity/spatial pointer decoder; and
4. pointer decoder with calibrated canonical-noop initialization; and
5. pointer decoder with original-AI behavior-cloning warm start.

Measure terminal learning, accepted semantic-command rate, noop rate, entropy by active branch,
normalized legal-capacity entropy, gradient health, and SPS. Zero invalid actions is a correctness
gate, not the optimization metric. A decoder does not lose an ablation merely because its raw
entropy number is on a different scale.

### Phase 4: curriculum and shaping ablation

Compare:

1. direct C4 terminal-only training;
2. hard stage replacement;
3. mixed replay curriculum;
4. mixed curriculum with temporary potential shaping; and
5. the same run with shaping removed from the beginning.

The key outcomes are final C4 robust performance, area under the C4 held-out learning curve, and
retention on earlier stages. Milestone completion alone cannot win an ablation.

### Phase 5: annealing ablation

Use the winning observation/action/curriculum stack and compare the absolute schedule variants.
This is where learning-rate, entropy, and shaping annealing become real experiments rather than
confounded sweep dimensions.

## Provisional 50M Path

A 50M budget should be one exact resumable training lineage with gates, not one fresh command whose
cosine is stretched over 50M. A provisional allocation is:

| Global steps | Rules distribution | Start-state frontier | Purpose |
| --- | --- | --- | --- |
| 0-2M | C0 | H0 finish -> H2 mobilize, with H5 anchor | Learn terminal combat, then connect production to combat |
| 2-5M | C1 + C0 anchor | H1 assault -> H5 full match | Retain finishing skill and survive early pressure |
| 5-10M | C2 + prior anchors | H3 economy -> H4 opening | Learn forced harvesting and convert income into an army |
| 10-20M | C3 + prior anchors | H3/H4 -> H5 | Remove sequencing aid and solve longer horizons under pressure |
| 20-35M | C4 + retention anchors | Primarily H5, with H1/H3 anchors | Optimize unshaped terminal wins without tactical/economy forgetting |
| 35-50M | C4/C5 final mixture | At least 80% H5 | Improve full-match robustness and generalization |

These are ceilings, not automatic transitions. At every boundary:

- run the fixed held-out suite;
- advance only after the stage's predeclared robust gate;
- otherwise continue the current stage or revise one isolated blocker;
- retain checkpoints at 1M, 2M, 5M, 10M, 20M, 35M, and 50M; and
- never select the final checkpoint from training return.

The first serious 50M run should remain E1/E3 + Refinery/Harvester against Easy AI. Vehicles and
Normal/Hard belong to later lineages after that vertical slice is robust in Zig and transfers to
Vanilla.

## Logging Within The 31-Field Limit

The next environment binding emits 25 fields before PufferLib appends `N`, reserving six export
slots under the project limit. Existing counters remain restricted to H5. Live `balanced_perf`
equal-weights close/MCV, close/force, medium/MCV, and medium/force, while fixed-suite
`robust_perf` remains evaluator-side.

Keep only high-value aggregate concepts in the Puffer user log:

```text
perf, balanced_perf
episode_return, draw_rate, episode_length
invalid_actions, failures, start_failures
gunners_built, rocket_soldiers_built
unit_kills, unit_losses
buildings_destroyed, buildings_lost
refineries_built, tiberium_income
enemy_attack_orders
starting_force_episode_share
close_mcv_win_rate, close_force_win_rate
medium_mcv_win_rate, medium_force_win_rate
```

Do not add every stage x spawn x credit cell to the Puffer dictionary. Write exact per-episode
evaluation records to a JSONL sidecar and derive detailed tables offline. Any future live metric
must replace a retired field under a versioned log schema; it must never be appended on top. Do not
exceed 31 environment fields before `N`.

## Reproducibility Contract

Every promoted experiment records:

- clean git commit and tracked-diff status;
- rules, curriculum, observation, action, model, and reward schema ids/hashes;
- compiled Zig library and Puffer extension hashes;
- exact command and effective config;
- train seed and fixed evaluation-suite id;
- checkpoint and full-training-state hashes;
- zero `start_failures` and zero engine failures;
- valid SPS reporting shape; and
- Zig/Vanilla parity status for every active profile.

One exact duplicate configuration is included in every large sweep as a determinism sentinel.
Structural changes use TDD, CPU/CUDA reference tests, fixed-action world hashes, and adjacent
performance measurements before learning claims.

## Experimental Platform Ready Gate

The platform is ready for curriculum and annealing claims when all of these hold:

1. Re-evaluating one checkpoint with one suite id produces the same ordered episode JSONL and file
   hash, including stochastic-policy actions driven by the declared sampling seeds.
2. [Complete] An uninterrupted training run and split/resumed variants produce exact model,
   optimizer, trainer, curriculum, and environment-state hashes at the same global step.
3. The generated observation schema proves that every legal live object fits and remains
   addressable; overflow is a test failure, never silent truncation.
4. Recurrent-state tests prove exact matching train/eval/visible-inference reset semantics and no
   cross-episode hidden-state leakage. Any later lane-local terminal-reset mode is CNC-specific and
   opt-in.
5. Exact-action decoder tests prove that every emitted command is legal and that inactive branches
   contribute no log-probability, entropy, PPO ratio, or gradient.
6. A retained ABI9 baseline reproduces under at least three training seeds and an untouched
   promotion suite with zero engine/start failures.
7. Zig and visible Vanilla agree on the scripted profile traces and promoted-policy terminal result
   for every curriculum profile currently in scope.

This gate does not require a strong policy. It requires that a measured difference can be assigned
to the experiment rather than evaluation state, truncation, continuation, or interface drift.

## Immediate Next Work

1. Finish native, C/Puffer, CUDA, determinism, and Vanilla-oracle validation for schedule 1.
2. Run matched schedule-0/schedule-1 controls, then sweep the independent H-profile and force-ramp
   clocks and promote with fixed H5 evaluation.
3. Migrate the canonical development seed from 73 to 42 in its own deterministic commit.
4. Correct entity capacity/identity, then run the structured-encoder ablation.
5. Build the structured pointer decoder only after entity embeddings are available.

This order makes later annealing, curriculum, action, and observation experiments interpretable. It
also preserves ABI9 as a measured baseline instead of repeatedly replacing several foundations at
once.

## Primary References

- [Deep RL at the Edge of the Statistical Precipice](https://arxiv.org/abs/2108.13264)
- [Grandmaster Level in StarCraft II Using Multi-Agent Reinforcement Learning](https://www.nature.com/articles/s41586-019-1724-z)
- [SCC: An Efficient Deep Reinforcement Learning Agent Mastering StarCraft II](https://arxiv.org/abs/2012.13169)
- [StarCraft II: A New Challenge for Reinforcement Learning](https://arxiv.org/abs/1708.04782)
- [Prioritized Level Replay](https://arxiv.org/abs/2010.03934)
- [Reverse Curriculum Generation for Reinforcement Learning](https://arxiv.org/abs/1707.05300)
- [Policy Invariance Under Reward Transformations](https://ai.stanford.edu/~ang/papers/shaping-icml99.pdf)
- [Curriculum Learning](https://icml.cc/Conferences/2009/papers/119.pdf)
