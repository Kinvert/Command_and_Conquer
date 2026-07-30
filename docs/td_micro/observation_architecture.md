# TD Micro Observation Architecture

Date: 2026-07-14

ABI-7 economy update: 2026-07-16

ABI-9 compact-observation update: 2026-07-17

Status: observation version 5 is implemented. Transport is 2,456 bytes; static terrain and dynamic
occupancy are no longer resent on every decision.

## Conclusion

The current `2,456`-byte observation does not justify a separately trained autoencoder. ABI 9
removed the repeated static-map payload while preserving public dynamic state. The native policy
immediately maps the bytes into a 64-value learned hidden representation. The remaining problem is
semantic: one flat linear layer still receives packed resource bytes, booleans, categorical ids,
coordinates, and continuous values as if they had the same meaning.

PufferLib already contains the appropriate precedent. `nmmo3` transports a compact `ByteTensor`,
then a custom CUDA encoder expands categorical map values into multihot channels, applies
convolutions, embeds player fields, and projects the result into the policy hidden state. TD Micro
should follow that pattern with a C&C-specific structured encoder trained end to end with PPO.

## How PufferLib Environments Handle Observations

The local PufferLib environments use four broad patterns:

1. Small physics/game state vectors use a short `FloatTensor` and the default linear encoder.
2. Small boards use compact byte or float cells, often with the default encoder.
3. Image observations use `NatureEncoder` or `ImpalaEncoder`, which apply a CNN and emit a learned
   hidden vector.
4. Structured complex state can use a custom encoder. `nmmo3` declares a 1,707-byte observation in
   `PufferLib/ocean/nmmo3/binding.c`, while `PufferLib/src/ocean.cu` converts its categorical map to
   multihot planes, applies a CNN, embeds non-map fields, and projects everything to hidden size.

`PufferLib/pufferlib/models.py::MinimalEntityEncoder` is a smaller example: it applies one shared
MLP to every entity/point and max-pools the set. There is no autoencoder implementation or common
autoencoder workflow in the local PufferLib tree.

## Current 2,456-Byte Layout

Defined in `td-micro/src/policy.zig`:

| Region | Bytes | Share | Meaning |
| --- | ---: | ---: | --- |
| Globals | 64 | 2.6% | Economy, queues, frame, defeat/failure state, counts, scenario id |
| Dynamic Tiberium | 344 | 14.0% | One packed byte per authored resource cell |
| Player entities | 1,024 | 41.7% | 64 slots x 16 bytes |
| Opponent entities | 1,024 | 41.7% | 64 slots x 16 bytes |
| Total | 2,456 | 100% | Compact `ByteTensor` |

### Map Id Status

`td-micro/src/map.zig` declares `scenario_id = 1`, identifying the generated map fixture supported
by TD Micro. ABI 9 writes that id to global byte 32. The encoder can therefore associate the dynamic
state with the immutable generated terrain instead of receiving all 4,096 cells every decision.

A map id is useful only when the encoder has a table of known maps. For the present single-map task,
it also acts as an explicit schema/parity check. With a finite map set, the id can select the
corresponding constant terrain. An id cannot represent a procedurally generated or previously
unseen map; that map's terrain must still be supplied.

### Globals

Bytes 0-32 currently carry data:

- observation version, map width, and map height;
- frame divided by 32 and clipped to a byte;
- credits divided by 100, power, and drain;
- player defeat, opponent defeat, and engine failure;
- structure and infantry queues: active, complete, product, progress, and timer;
- own and opponent counts for units, buildings, and infantry;
- player stored Tiberium, storage capacity, and cumulative harvested credits;
- opponent stored Tiberium and storage capacity; and
- total remaining map Tiberium steps, clipped to a byte; and
- scenario id.

Bytes 33-63 are currently zero. Several populated values are also derivable elsewhere: dimensions
are constant, and entity counts can be derived from complete entity presence data.

### Dynamic Tiberium

ABI 9 lists the 344 cells that contain Tiberium in the immutable scenario fixture, in row-major
order. Each output byte keeps the legacy packed-map numeric value:

```text
45: Tiberium present, passable, visible
56: depleted clear land, passable, buildable, visible
```

The byte exposes Tiberium presence, not the exact remaining overlay level. Static terrain,
passability, and visibility are fixed by the generated scenario. Dynamic occupancy and
occupancy-induced buildability are reconstructed from entity records plus known footprints when a
spatial encoder needs them.

### Entity Records

Each side receives 64 compacted slots. A 16-byte slot contains:

```text
presence, type, canonical-id low/high, x, y, health fraction, facing,
mission, target kind, target slot, cooldown, flags, progress, category, status
```

Flags, progress, cooldown, and status are type-dependent. Buildings use progress for construction
state; infantry use it for fear; MCVs use it for deployment progress. Harvesters use progress for
cargo fraction, cooldown for the harvest timer, flags for movement/harvesting, and status for the
harvest/docking mission state.

There is a correctness limit in this layout. Units, then buildings, then infantry are compacted into
only 64 slots per owner. The player may legally have roughly 16 buildings plus 64 infantry before
the soft terminal, so later infantry can be absent from the detailed entity block and unavailable
through the 64-slot actor head. Map occupancy can still reveal their positions, but not their full
type, health, mission, or controllable identity. A new schema must make observation and action
capacity agree with the declared gameplay limits.

## What The Built-In AI Sees

The built-in opponent does not consume this observation tensor. The cloned Easy AI in
`td-micro/src/ai.zig` receives a mutable pointer to the complete `World`, including full object
arrays, both owners' public simulation state, map data, exact coordinates/health/missions, RNG, and
its private controller timers and planned production. Individual routines mostly read their own
economy and production state, but there is no enforced observation boundary. Hunt target selection
in `td-micro/src/combat.zig` scans the complete enemy unit, building, and infantry arrays without a
fog/discovery test.

This matches the important behavior of the original engine more closely than a human screen does.
Vanilla TD's `TechnoClass::Evaluate_Object` scans live engine objects and explicitly treats
human-owned objects as visible to computer targeting. Its discovery rejection is also conditional
on `GAME_NORMAL`, so non-campaign/skirmish-style modes do not impose that check.

The Puffer policy therefore does not currently have an unfair information advantage over the game
AI. It receives a public, fully observable projection and does not receive the opponent AI's private
timers, build choices, or RNG state. In fact, the current 64-slot truncation can give Puffer less
usable object detail than the built-in AI. A future symmetric policy-vs-policy mode should run the
same encoder from each owner's perspective, but the original AI path will still operate directly on
engine state.

### Measured Raw-State Comparison

There is no finite "AI observation tensor" in either implementation. The AI calls simulator methods
and scans engine-owned object arrays. In TD Micro, that interface is a direct `*World` pointer.

| Representation | Notes |
| --- | --- |
| Current Puffer observation | 2,456 exact bytes, including 344 dynamic Tiberium bytes |
| TD Micro `World` | Raw mutable state with 16 units, 64 buildings, 128 infantry, 256 projectiles, exact Tiberium levels, paths, animation state, RNG, and private Easy-AI state |
| Static map | Compile-time terrain known separately by simulator and Easy AI |

ABI 7 enlarged `World` with Harvester movement/docking state and a 4,096-byte Tiberium-level array.
That private representation is intentionally much larger than the public policy observation.
Vanilla's C++ AI similarly sees an object graph rather than a fixed tensor, so its memory footprint
is not a meaningful observation-space target.

The correct parity target is the same **public gameplay facts**, not a raw memory copy. ABI 9 reaches
the lower end of the prior 2.4-3.2 KB estimate, but the existing 64-entity slot limit still does not
represent every legal infantry slot at the declared soft cap. A capacity-correct successor should
exclude projectile internals, animation bookkeeping, RNG, and the opponent controller's private
plan while making every controllable entity addressable.

## Current Learned Latent

The current native CUDA policy already has an encoder bottleneck:

```text
2,456 byte values
  -> GPU cast and uniform 1/255 scale
  -> learned 2,456 x 64 linear projection
  -> 64-value MinGRU state
  -> action logits and value
```

This is a learned 64-dimensional latent trained directly for PPO return. It is not an autoencoder
because there is no decoder or reconstruction loss. The issue is that the encoder has no structural
knowledge and the uniform scale gives poor semantics to booleans, enums, packed flags, and map bits.

Here, "encoder" means the neural-network front end that converts an environment observation into a
small hidden representation. It is distinct from `policy.observe`, which serializes `World` into
bytes. The current neural encoder is just one dense matrix: every one of the 2,456 byte values is
divided by 255 and multiplied by a learned `2456 x 64` matrix. It has no concept of map adjacency,
entity slots, categories, or field boundaries.

### Current Numeric Precision

The environment buffer is already a `ByteTensor`: each observation element occupies one byte as an
unsigned integer. During native GPU rollout, PufferLib's scaled-cast kernel converts each byte to
`value / 255` in `precision_t`. The normal build uses two-byte BF16 for rollout tensors, weights, and
activations, with FP32 accumulation where required; `--float` changes `precision_t` to four-byte
FP32. The resulting BF16 vector is then multiplied by the learned `2456 x 64` encoder matrix.

An eight-bit floating-point type would still occupy one byte, so it cannot reduce the environment
buffer below the current `uint8` representation. It would also approximate integer ids and packed
flags less faithfully, and the current PufferLib encoder path has no FP8 implementation. Sub-byte
bit or nibble packing can reduce transport storage, but values must be unpacked before neural
arithmetic and the policy still receives the same number of semantic features. The current map byte
already packs several bit fields, which is one reason the flat `/255` interpretation is poor.

Therefore numeric precision is not the observation-learning lever. Reduce redundant elements,
separate categorical fields, or use a structured encoder; do not replace exact bytes with FP8.

## Local PufferLib Observation-Size Survey

PufferLib has no 200-value observation limit. Among the current buildable native `vecenv.h`
bindings in this checkout, the largest observations are:

| Environment | Elements | Transport | Encoder treatment |
| --- | ---: | --- | --- |
| `cnc_micro` | 2,456 | bytes | Current flat dense projection |
| `nmmo3` | 1,707 | bytes | Custom multihot, CNN, embeddings, and projection |
| `nethack` (default) | 1,659 | bytes | 21x79 character grid; flat by default |
| `craftax_classic` | 1,345 | float32 | 7x9 local symbolic grid plus inventory |
| `drive` | 973 | float32 | Ego, nearby-agent, and road-segment records |

Thus TD Micro remains the largest working native observation in this local tree, about 1.4 times
NMMO3. It is no longer an extreme outlier, but still lacks NMMO3's structured encoder.
PufferLib also provides CNN encoders for image-shaped observations and does not impose a general
maximum observation dimension.

The stale `ocean/tactical` source allocates 58,564 bytes (`121 x 121 x 4`), but it is not a valid
counterexample: its observation writer is empty and its obsolete binding no longer builds with the
current trainer API.

## Implemented Transport Reduction

ABI 9 implements the largest fixed-map reduction without removing current dynamic meaning:

1. Treat the sole current map as immutable and export its scenario id.
2. Export Tiberium presence as 344 canonical dynamic bytes.
3. Keep existing own/enemy entity records unchanged.
4. Omit redundant occupancy and static terrain from per-step transport.

This removes the full 4,096-byte map block and reduces the total observation by 60.44%. A later
structured encoder can cache static terrain and rasterize entity positions and footprints into
dynamic channels on the GPU. Globals and records may shrink further only after field-level parity
tests prove the removed values redundant.

This optimization is only lossless while the map can be recovered from the map id. Supporting
procedurally generated or previously unseen maps requires transmitting their static terrain, either
at reset or in the normal observation.

### Partial-Map Alternatives

A local crop alone is not a good RTS observation. It can hide an enemy base, distant Tiberium,
reinforcements, or the terrain connecting an actor to its target, making the policy partially
observable for reasons unrelated to fog of war. Use one of these designs instead:

1. **Fixed-map task (recommended first):** send dynamic entities plus a compact Tiberium plane, with
   no map id needed. Keep exact static terrain in the encoder and rasterize current entities and
   structure footprints there.
2. **Finite map set:** load the static map once at reset and cache its spatial embedding for the
   episode. Per-step observations contain only dynamic state.
3. **Unseen-map generalization:** combine a coarse global map (for example 16x16) with high-resolution
   local terrain features around each entity or action focus. The global branch preserves strategic
   context; local branches preserve collision, placement, and combat detail.

For the fixed-map curriculum, normalized entity coordinates plus the cached terrain embedding are
strictly preferable to choosing one arbitrary visible window. If terrain reasoning remains hard,
add derived public features the built-in AI can also compute, such as connected-region id, local
passability, or path distance to candidate targets. Those features reduce the learning burden
without leaking opponent-private state.

## Recommended C&C Encoder

Follow the native `nmmo3` pattern rather than adding a standalone autoencoder:

- **Map branch:** select immutable terrain by scenario id, overlay dynamic Tiberium and rasterized
  entity occupancy into separate channels, then use a small CNN or spatial pooling network.
- **Entity branch:** shared per-entity MLP with explicit presence, type/category embeddings,
  normalized coordinates/health/cooldown/progress, boolean flags, and owner context; aggregate with
  masked pooling or lightweight attention.
- **Global branch:** field-aware normalization for economy/time/progress, explicit booleans, and
  embeddings or one-hot values for queues/products/failures.
- **Fusion:** concatenate branch outputs and project to the MinGRU hidden size.
- **Action follow-up:** reuse entity and spatial embeddings to score actor, target, and placement
  choices conditionally instead of treating every action head independently.

Keep `ByteTensor` transport. The custom CUDA encoder should consume raw categorical bytes and apply
field-specific transforms on the GPU; a global `/255` cast should no longer define the semantics.
Visible Zig inference must implement the exact same schema-aware encoder.

## Why Not A Separate Autoencoder First

A reconstruction autoencoder optimizes byte reconstruction, not winning C&C. Even after ABI 9,
repeated entity slots could dominate reconstruction loss while rare but decisive state such as one
target, low building health, or a completed queue receives little representation capacity.
It also introduces pretraining data distribution, decoder, checkpoint-transfer, and latent-staleness
problems without addressing the entity-slot/action-capacity mismatch.

If representation pretraining is needed later, original-AI trajectories are better used for behavior
cloning, next-state prediction, or auxiliary semantic targets on the same structured encoder. Start
with end-to-end PPO so the latent is optimized for control.

## ABI 9 Acceptance Status

- Fixed-action traces preserve simulation/reward/terminal outcomes and exact world digests.
- Zig projects the immutable executable-validated legacy fixture into compact state; Zig and Vanilla
  share the generated cell order and packed-value contract; CUDA uses the declared 2,456-byte shape.
- Old checkpoints fail exact-size validation.
- GPU training passes with the standard 64-agent shape and zero start/engine failures.
- Native fixed-action throughput improves 5.27%; the accepted 1M CUDA run improves 8.21% over the
  adjacent old-ABI mean, with the behavior-dependent caveat documented separately.
- Learning remains nonzero, but old hyperparameters do not transfer exactly and must be retuned.
- Full object/action capacity remains a future ABI requirement; ABI 9 intentionally leaves the
  existing 64-slot entity/action limit unchanged.

Detailed commands, hashes, and rejected variants are in
`docs/td_micro/compact_observation_and_sweep_slots.md`.
