# TD Micro Learning Blockers And Next Step

Date: 2026-07-14

Status: timeout, placement, and observation-scale stabilization implemented and verified;
field-aware observation representation and the conditional action protocol remain open.

## Implementation Outcome

The approved work landed as ABI 5 / observation version 3:

- the training cap is now `48,000` TD frames / `12,000` policy decisions;
- player and Easy-AI placement share one Vanilla-derived footprint, terrain, occupancy, and
  friendly-building proximity predicate;
- map occupancy uses the same `Occupy_List(true)`-style foundations and bib cells;
- Puffer transports the compact byte observation and performs the `1/255` conversion in its native
  GPU rollout cast; Zig checkpoint inference applies the same scale;
- destroying the final Construction Yard or Barracks now abandons and refunds its production queue,
  matching Vanilla's producer-destruction path instead of producing an engine failure.

The corrected byte-transport 1M-step CUDA smoke completed at `57,636` aggregate SPS with
`start_failures=0` and engine `failures=0`. Its final checkpoint is byte-identical to the rejected
CPU-float A/B run at `59,254` SPS. Full evidence is in
`docs/td_micro/abi5_timeout_placement_obsnorm_1m.md`.

The action protocol was not changed. In concrete terms, Puffer currently rolls seven independent
choices. It can select an `x` that is legal for one placement and a `y` that is legal for another,
while the combined `(x,y)` cell is illegal. The final smoke checkpoint made `5,883` invalid choices
in `6,094` deterministic replay decisions. That is the deferred item 3.

## Decision

At audit time, the experiment had three correctness and representation blockers that a sweep could
not repair:

1. the `12,000`-frame timeout records false draws before the original Easy AI finishes attacking;
2. seven independently sampled MultiDiscrete heads cannot express the environment's conditional
   action legality;
3. the native network consumes byte observations on their raw `0..255` scale, saturating its
   recurrent gates.

The timeout, placement apply path, and observation scaling are now fixed. Do not run a broad sweep
while the conditional action issue still makes most policy decisions invalid. Run short multi-seed
ablations only after that gate passes and episodes resolve primarily to real wins or losses.

## Timeout Audit

At audit time, the timeout was `12,000` TD frames in `td-micro/src/batch.zig`, with four frames
advanced per policy decision. `PufferLib/config/cnc_micro.ini` therefore used `3,000` decisions.

That limit is too short. The original Vanilla seed-1 no-op oracle lost at frame `8,358`, but player
commands alter the shared deterministic RNG stream and can delay the Easy AI's attack schedule. A
single no-op oracle is therefore not a sufficient timeout bound for trained policies.

The final checkpoint from run `cmv6t21t` demonstrates the problem:

| Replay limit | Result | Enemy attack orders | Player losses |
| --- | --- | ---: | ---: |
| 3,000 decisions / 12,000 frames | draw | 0 | 0 |
| 6,000 decisions / 24,000 frames | draw | 7 | 0 |
| 12,000 decisions / 48,000 frames | loss at decision 6,638 / frame 26,552 | nonzero | 3 buildings |

The same checkpoint and policy weights were used in all three runs. Only the diagnostic episode cap
changed.

The audit was then extended to all 97 retained checkpoints from the same 100M-step run:

| Replay limit | Wins | Losses | Draws | Failures |
| --- | ---: | ---: | ---: | ---: |
| 7,500 decisions / 30,000 frames | 0 | 94 | 3 | 0 |
| 12,000 decisions / 48,000 frames | 0 | 97 | 0 | 0 |

The three trajectories still drawing at 30,000 frames became losses at:

| Checkpoint step | Terminal decision | Terminal frame |
| ---: | ---: | ---: |
| 12,584,960 | 10,469 | 41,876 |
| 18,876,416 | 8,209 | 32,836 |
| 79,693,824 | 10,003 | 40,012 |

For the current seed and retained policy corpus, `48,000` frames / `12,000` decisions is the first
tested cap that resolves every episode. It now replaces `12,000` frames as the temporary training
contract, with C, Zig, Vanilla, and Puffer config assertions at the new boundary.

The long-term draw rule should be an explicit, tested stalemate condition based on lack of meaningful
state progress, not merely a clock that expires before the AI's next wave. Until that rule exists,
the empirically validated 48,000-frame cap is the safer contract.

Longer episodes increase the terminal-credit horizon, so this timeout fix does not remove milestone
or combat shaping. It removes a false objective where passive policies receive a draw while active
policies fight and receive a loss.

## Action Representation Blocker

Current ABI-9 details and measured CNC6 evidence are authoritative in
`docs/td_micro/current_action_abi.md`. The protocol analysis below remains the implementation
proposal.

The Puffer action ABI currently contains seven heads with sizes:

```text
command=12, actor=65, product=6, target_kind=4, target_x=64, target_y=64, target_slot=64
```

PufferLib samples each head independently and sums their log probabilities. The Zig action mask can
mark legal values within each head, but it cannot say that legality depends on the command sampled
from another head. Examples include:

- `attack` requires a live player infantry actor and a live visible-enemy target slot;
- `move` requires player infantry and a cell target;
- `start_build`, `place`, and `train` each require a product from a different legal subset.

The environment therefore rejects combinations assembled entirely from individually unmasked head
values. The reproducible ABI-9 policy `qj7bux1j` averages `1,986.594` invalid actions over
`4,420.213` decisions, or `44.943%`. Hyperparameter tuning cannot make an independently factorized
sampler represent these cross-head constraints reliably.

A flat catalog is not compatible with the normal native Puffer path. The unmasked ABI-9 Cartesian
space contains 4,907,335,680 tuples, while a legal flat catalog with movement would still make
rollout masks and logits unreasonably large.

One candidate is a fixed four-token `Discrete(64)` grammar. This proposal is not approved or
implemented. Each token would be sampled by the existing single categorical CUDA path, and its mask
would be conditioned on the already selected prefix:

| Semantic action | Token 0 | Token 1 | Token 2 | Token 3 |
| --- | --- | --- | --- | --- |
| no-op | command | pad | pad | pad |
| deploy | command | actor | pad | pad |
| start build | command | product | pad | pad |
| train | command | product | pad | pad |
| place | command | product | x | y |
| move | command | actor | x | y |
| attack | command | actor | enemy slot | pad |
| harvest | command | harvester actor | x | y |
| return cargo | command | harvester actor | refinery slot | pad |

`target_kind` becomes command-implied and every irrelevant field receives one canonical value. The
world, frame, RNG, and Easy AI remain frozen through tokens 0-2; token 3 constructs one existing
semantic `Action`, applies it once, and advances four TD frames. A failed final apply is then an
environment contract failure rather than an ordinary policy choice.

Use one 64-way Puffer action head and store the protocol stage/prefix in the unused global
observation bytes. Keep protocol state outside canonical `World`, preserve the direct semantic batch
API for fixtures/oracles, and mirror the four-token inference adapter in Vanilla. Fixed depth avoids
giving short commands different discount lengths. To preserve approximately 32 semantic game
decisions per rollout, the first training comparison should use horizon 128. Equivalent per-token
discounts for the current settings are:

```text
gamma  = 0.995^(1/4) = 0.998747649
lambda = 0.90^(1/4)  = 0.974003746
```

After this change, dashboard SPS counts protocol tokens, not game decisions. Every benchmark must
also report semantic-command SPS (`token SPS / 4`) and TD-frame SPS so the protocol cannot create an
illusory throughput gain.

Required tests:

- every unmasked prefix has at least one legal completion;
- tokens 0-2 do not mutate world state, frame, or RNG;
- every completed masked sequence applies successfully;
- semantic actions round-trip through grammar encode/decode;
- sampled training actions produce `invalid_actions == 0`;
- Zig and Vanilla receive identical semantic actions from identical token traces;
- fixed-seed simulation digests remain deterministic after equivalent semantic action traces.

This is intentionally an action, observation, and checkpoint ABI change. Old policy checkpoints
remain evaluation artifacts, not initialization candidates for the corrected policy.

## Observation Scale Blocker

Before ABI 5, the environment exported a `6,208`-element `ByteTensor`. The native GPU rollout cast
those bytes to the training precision, but the default encoder directly matrix-multiplied them
without dividing by 255. The visible Zig inference path likewise multiplied raw byte values by
encoder weights.

Measured reset-observation RMS is `35.6836`. Replaying trained checkpoints through an activation
audit found severe saturation:

| Checkpoint | Mean absolute encoder activation | Recurrent gates with `abs(x) > 10` | Highway values with `abs(x) > 10` |
| --- | ---: | ---: | ---: |
| prior best, run `p8jxidnw` | 328.7 | 63 / 64 | 64 / 64 |
| combat best, run `cmv6t21t` | 399.2 | 63 / 64 | 64 / 64 |
| final, run `cmv6t21t` | not required | 64 / 64 | 64 / 64 |

At those magnitudes, sigmoid gates are effectively binary and gradients through them are nearly
zero. Normalize bytes by `1/255` before the first matrix multiply in both the native Puffer encoder
and Zig inference. Add cross-backend checkpoint tests so GPU training and visible inference use
identical scaling. The first acceptance gate is a large reduction from the current `63/64` saturated
recurrent gates on the reset observation.

The first ABI 5 implementation performed this correction in the CPU environment by advertising a
`FloatTensor`, allocating a second observation buffer, and converting all 6,208 bytes per agent on
every step. That was the wrong boundary: at 64 agents it expanded each observation transfer from
397,312 bytes to 1,589,248 bytes.

The current ABI 5 implementation advertises the original `ByteTensor`. Puffer copies compact bytes
and fuses byte-to-rollout-precision conversion with `1/255` scaling in its CUDA cast. Zig inference
applies the same scale before its first matrix multiply; the PyTorch fallback uses
`Normalize255Encoder`. The fixed-hyperparameter CPU-float and GPU-byte runs produced the exact same
final checkpoint SHA-256, proving semantic equivalence. Their 59,254 versus 57,636 aggregate SPS
also proves that observation conversion was not the source of the large historical throughput gap.

Uniform `/255` is not the final representation. Presence and other booleans become `0.0039`, enum
fields remain ordinal, coordinate/count ranges top out near `0.25`, and each map byte packs several
semantic channels behind one dense input weight. The serious follow-up is a new observation ABI
that keeps compact host bytes but unpacks separate map channels and applies field-aware continuous,
boolean, and categorical encoding on the GPU. Do not run a broad quality sweep while treating the
current flat byte vector as settled architecture.

## Placement Correctness

Before ABI 5, player placement checked only queue state and map bounds before calling
`World.addBuilding`. One final policy placed structures at `(42,15)` and `(42,30)`, far from its
Construction Yard.

ABI 5 now checks:

- full structure footprint inside map bounds;
- buildable terrain for every footprint cell;
- no footprint overlap with active objects;
- Vanilla-compatible adjacency/build-radius rules for the player;
- the recorded Vanilla legal `(4,7)` and illegal distant `(14,32)` placements.

The player and Easy AI call the same predicate, and observation occupancy uses the same footprints.
Exact per-cell placement masking remains tied to the deferred action protocol: separate `x` and `y`
heads cannot represent an exact set of legal coordinate pairs.

## Ordered Work

1. **Done:** raise the temporary timeout to `48,000` frames / `12,000` decisions.
2. **Done:** enforce Vanilla-derived placement legality from one shared predicate. Exact coordinate
   masks remain coupled to item 3.
3. **Deferred:** replace the seven independent heads with a conditional action protocol after the
   protocol and its SPS accounting are reviewed.
4. **Done as stabilization:** apply identical `1/255` scaling in Puffer training and Zig inference.
   **Open:** replace the mixed flat-byte semantics with a field-aware GPU-decoded observation ABI.
5. **Done as a smoke:** run 1M CUDA steps with `start_failures=0`, engine failures `=0`, enemy
   attacks, combat, and real terminals. Invalid sampled actions are not zero because item 3 remains.
6. Add automatic fixed-seed checkpoint evaluation and selection. Report milestones, legal action
   rate, combat damage, terminal outcome, and determinism hashes.
7. Only then run a small multi-seed Puffer sweep. Tune learning rate, entropy, gamma, GAE, horizon,
   and network size while holding the environment/action contract constant.

The sweep metric at the time of this analysis was `score = wins - losses`. Under the false timeout,
a passive draw scored better than an exploratory loss. As of `92c836e`, wins are nonzero and current
sweeps optimize binary `perf`; final policy selection still requires fixed-seed inference rather
than a stochastic training window.

Behavior cloning original Easy-AI state/command records into the same semantic catalog is a useful
follow-up initialization strategy. It should complement, not replace, the corrected online PPO
path.
