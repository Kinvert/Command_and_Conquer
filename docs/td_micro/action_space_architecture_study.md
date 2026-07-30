# TD Micro Action-Space Architecture Study

Date: 2026-07-18

Status: original research completed, implementation decision under reassessment. The recommended
one-transition conditional design was implemented as ABI10, compacted as ABI11, and given bounded
actor-target scoring as ABI13. Measured results are in `current_action_abi.md`,
`abi11_compact_decoder_experiment.md`, and `abi13_actor_target_experiment.md`.

Implementation note: ABI10's 15,027-output prefix-row decoder proved exact legality but regressed
matched learning. ABI11 replaces it with 2,352 command-conditioned logits and improves matched
1M/2M performance while preserving all masks and hashes. It still lacks explicit actor-target
preference and remains below ABI9 sample efficiency. ABI13 adds a bounded low-rank interaction and
reaches 0.384 reproducibly at 1M, but falls to 0.092 at 2M and has a zero-median 30-run sampled
screen. Exact legality alone has therefore not justified retiring the stronger ABI9 training path.

Post-ABI13 decision: preserve the exact-action implementations, but run a controlled restoration
of ABI9's seven heads. ABI9 already treated rejected tuples as four-frame no-ops. Compare no penalty
against tiny invalid-action costs before attempting another decoder redesign. Do not use `-0.05`:
at the historical invalid count it contributes roughly `-99` per episode.

## Original Decision (Under Reassessment)

The original recommendation was to retire ABI9 because its seven independently sampled heads do
not represent the conditional structure of a C&C command. In the best reproducible CNC6 run,
44.943% of policy decisions were rejected after sampling. ABI10-ABI13 proved that this diagnosis was
real, but also proved that eliminating rejections can reduce learning enough to lose overall. The
following migration remains the design record, not the current promotion decision.

The recommended migration is:

1. Keep the existing semantic `Action` type as the game-facing contract.
2. Introduce ABI 10 as a **one-step, command-gated tagged union with targeted autoregression**:
   command first, actor/product next, then the target for branches where the choices belong
   together.
3. Implement that small dependency graph in PufferLib's native CUDA sampler and PPO evaluator.
   Inactive heads must be canonical zero/PAD and contribute no log-probability or entropy.
4. Have Zig export exact prefix masks. Condition attack, move, harvest, and return targets on the
   selected actor for policy expressiveness; condition placement y on x for exact legality.
5. Continue using PufferLib's normal native CUDA backend with `--train.gpus 1`. **Do not use
   `--slowly` or a Python custom decoder.**
6. Keep a pure Zig conditional-grammar oracle and deterministic traces as the reference for the
   native implementation.
7. Add dependencies beyond this explicit graph, or entity pointer encoders, only when expanded TD
   rules or measured learning failures require them.

This keeps one policy step equal to one semantic game decision, eliminates irrelevant-head policy
gradient noise, represents correlated actor-target choices, and preserves exact game-rule masking.
A four-token environment-mediated grammar is documented below as a low-risk reference/prototype,
but it should not be the production ABI: four policy transitions alter discounting, GAE,
recurrent-state timing, and semantic throughput.

## Scope And Requirements

The action interface must eventually cover full player-side control in a real Tiberian Dawn
skirmish, not only the current economy curriculum. It must support changing numbers of units,
buildings, enemies, and legal products while remaining usable by both the fast Zig simulator and
Vanilla Tiberian Dawn inference.

Hard requirements:

- Normal PufferLib native CUDA PPO training, not `--slowly`.
- One player-level semantic command per policy step and game decision.
- Exact game-rule masking so every sampled completed command is executable.
- No rejection sampling, repair aliases, or invalid-action penalties as the primary mechanism.
- Deterministic semantic traces and world hashes.
- A fixed transport shape suitable for native vectorization.
- Honest throughput accounting that distinguishes policy tokens from completed game commands.
- A path from the current reduced game to more commands, units, buildings, and maps.

Useful terminology in this document:

- **Semantic command:** one complete C&C action such as `move(actor, x, y)`.
- **Branch head:** an argument distribution used only by one command or command family.
- **Tagged union:** a command tag plus only the arguments belonging to that command.
- **Token step:** one environment interaction used to select part of a command in the reference
  four-token alternative, not in the recommended production ABI.

## Current ABI 9 Diagnosis

The current action is a `MultiDiscrete([12, 65, 6, 4, 64, 64, 64])` tuple:

| Head | Size | Meaning |
| --- | ---: | --- |
| `command` | 12 | Command ID |
| `actor` | 65 | Owned slot 0-63 or none |
| `product` | 6 | Build/train product or none |
| `target_kind` | 4 | None, cell, own entity, enemy entity |
| `target_x` | 64 | Map x |
| `target_y` | 64 | Map y |
| `target_slot` | 64 | Entity slot |

This is only 279 logits, but it denotes 4,907,335,680 tuples. The action mask in
[`policy.zig`](../../td-micro/src/policy.zig) marks values that are useful for *some* command. It
cannot say that E1 is legal for `train` but illegal for `start_build`, or that a particular actor is a
valid harvester but not a valid attacker.

PufferLib's [`DefaultDecoder`](../../PufferLib/pufferlib/models.py) emits one linear projection and
splits it into seven categorical distributions. Both
[`sample_logits`](../../PufferLib/pufferlib/torch_pufferl.py) and the normal native CUDA sampler in
[`pufferlib.cu`](../../PufferLib/src/pufferlib.cu) sample those distributions independently and sum
their log probabilities.

The represented policy is therefore:

```text
pi(a | s) = product_h pi(a_h | s)
```

The game requires a conditional policy:

```text
pi(a | s)
  = pi(command | s)
  * pi(actor_or_product | command, s)
  * pi(target | command, actor_or_product, s)
```

Examples of ABI 9 aliases and invalid combinations:

- `start_build + E1`
- `train + Power Plant`
- `attack + harvester + cell`
- `return_cargo + infantry + enemy slot`
- `noop` plus arbitrary values in six irrelevant heads

The last case is legal but still harmful: irrelevant heads add entropy and policy-gradient terms to
the same semantic no-op. Thousands of raw tuples can mean the same game action.

Measured on CNC6 policy `qj7bux1j`
([current ABI audit](current_action_abi.md#measured-impact)):

| Metric | Value |
| --- | ---: |
| Mean decisions per episode | 4,420.213 |
| Mean rejected actions per episode | 1,986.594 |
| Rejected decision share | **44.943%** |
| Balanced win rate | 0.421753 |

The policy can learn despite this representation, but a hyperparameter sweep cannot make an
independent product distribution express cross-head legality. The action architecture is now a
larger robustness problem than PPO tuning.

## What Other Game Environments Do

### SC2LE And PySC2: Function Plus Typed Arguments

The original StarCraft II Learning Environment describes the full game as a large, dynamic action
problem involving selection and control of hundreds of units. Its baseline full-game agents made
little progress, which is useful evidence that merely exposing the game is not enough
([SC2LE paper](https://arxiv.org/abs/1708.04782)).

PySC2 deliberately avoids a flat action ID. It exposes each action as a C-style `FunctionCall`: a
function identifier plus only the argument types required by that function. Each observation also
reports which functions are currently available. For example, `Train_Marine_quick` needs only a
queue flag, while `Move_screen` needs a queue flag and a screen point. The official documentation
explicitly says that flattening the interface would produce millions or billions of mostly invalid,
highly correlated actions
([PySC2 action documentation](https://github.com/google-deepmind/pysc2/blob/master/docs/environment.md#actions)).

Lesson for TD Micro: the semantic API should be a tagged command with typed arguments. A single
global `target_kind` is redundant because the command already determines the target type.

### AlphaStar: Autoregressive Arguments And Entity Pointers

AlphaStar samples action arguments autoregressively from a recurrent state and observation
encoders. Its heads cover action type, delay, queued, selected units, target unit, and target point
([AlphaStar paper](https://www.nature.com/articles/s41586-019-1724-z),
[open manuscript](https://storage.googleapis.com/deepmind-media/research/alphastar/AlphaStar_unformatted.pdf)).

The released architecture makes the dependency concrete. The function head is sampled first,
creates argument masks, embeds the selected function into the shared vector stream, and then later
heads select units and targets. Unit selection uses pointer logits over observed entities. The
selected units are embedded before target-unit selection
([official AlphaStar architecture](https://github.com/google-deepmind/alphastar/blob/main/alphastar/architectures/standard/standard.py),
[official action heads](https://github.com/google-deepmind/alphastar/blob/main/alphastar/architectures/standard/heads.py)).

Lesson for TD Micro: later choices must observe earlier choices, and dynamic actors/targets should
eventually be scored as entities rather than treated as unrelated fixed labels.

### StarCraft Commander: Condition On What Actually Matters

StarCraft Commander (SCC) is especially relevant because its authors ablated the dependency
structure instead of assuming that every argument needed a full AlphaStar-style chain. They found
that every other head critically needed to condition on the selected action/command. Target-unit
and target-position heads also benefited from the selected units, but unrelated heads did not need
to condition on one another. SCC therefore used command-conditioned branch structures while using
substantially less training compute than AlphaStar
([SCC paper](https://proceedings.mlr.press/v139/wang21v.html),
[SCC architecture supplement, section A.4](https://proceedings.mlr.press/v139/wang21v/wang21v-supp.pdf)).

Lesson for TD Micro: command gating is not merely a compromise made for implementation
convenience. It is an empirically supported dependency pattern for full-game StarCraft II. We
should condition every active argument branch on the command, then add actor-to-target
conditioning only where TD legality or learning results show that it is needed.

SCC and AlphaStar also use imitation to initialize the structured policy before reinforcement
learning ([SCC paper](https://proceedings.mlr.press/v139/wang21v.html),
[AlphaStar manuscript](https://storage.googleapis.com/deepmind-media/research/alphastar/AlphaStar_unformatted.pdf)).
TD Micro already has original-AI command instrumentation, so ABI 10 should make each
translated AI command directly supervisable: command loss plus only the losses for its active
prefix. That is a strong later use of the new contract, although it is not required to validate the
decoder itself.

### OpenAI Five: Primary Action Plus Active Parameters

OpenAI Five used one primary action plus delay, target-unit, and spatial-offset parameters. The
primary action determined which parameter outputs were read; ignored parameters were removed from
the optimization because their gradients would be noise. The target-unit keys were also gated by a
per-action mask based on the sampled primary action
([OpenAI Five paper, Appendix F and Figure 18](https://cdn.openai.com/dota-2.pdf)).

Some parameter combinations still became no-ops. That was survivable at OpenAI Five's scale, but
it is not a good target for TD Micro when the measured rejection rate is already nearly 45%.

Lesson for TD Micro: command-gated branches are a proven middle ground between fully independent
heads and a giant flat action space. Inactive arguments must contribute neither entropy nor
log-probability.

### Gym-microRTS: Composition, Full Masks, UAS, And GridNet

Gym-microRTS is the closest published analogue to this project: a fast full-game RTS with resource
harvesting, production, combat, PPO, and scripted opponents. Its raw single-unit action combines a
source unit, action type, and action-specific parameters. On the studied map, flattening that tuple
would require about 50 million actions. Action composition reduces the model output to 301 logits
([Gym-microRTS paper](https://arxiv.org/abs/2105.13807),
[conference PDF](https://ieee-cog.org/2021/assets/papers/paper_174.pdf)).

The paper compares two ways to control a variable number of units:

- **Unit Action Simulation (UAS):** sample a source unit, query its conditional mask, issue its
  action in a simulated state, and repeat until all units have commands.
- **GridNet:** output action components for every map cell at once and discard outputs for empty or
  uncontrolled cells.

Most importantly, its ablation found that masking only action types had little effect, while full
masks over action types *and parameters* considerably improved performance. The authors describe
action composition and invalid-action masking as the two essential additions that made full-game
learning start working.

Lesson for TD Micro: the current ABI resembles action composition with only partial masks. The
published ablation predicts exactly the failure we observe. UAS is conceptually useful, but TD
Micro currently issues one player command per decision rather than simultaneous orders to every
unit. GridNet would waste work across a 64x64 map.

### SMAC: One Small Masked Policy Per Combat Unit

The StarCraft Multi-Agent Challenge gives each combat unit its own agent. Each unit chooses from
no-op, stop, four movement directions, and attack or heal by entity ID. A per-step mask guarantees
valid actions. The maximum per-agent action set in the original scenarios ranges from 7 to 70
([SMAC/JMLR description](https://jmlr.csail.mit.edu/papers/volume21/20-081/20-081.pdf)).

This makes combat micro tractable, but SMAC intentionally removes economy, production, and
full-game macro strategy. It changes the problem from one player-level policy to a dynamic team of
unit policies.

Lesson for TD Micro: a shared per-unit policy is a credible future tactical sub-controller. It is not
a replacement for the current whole-player action interface because MCV deployment, production,
placement, harvesting, and army-level coordination still need a commander.

### CivRealm: Category, Entity Pointer, Then Action

CivRealm is a Civilization-inspired environment with unit, city, government, technology, and
diplomacy actions. Its fixed tensor action space contains nine subspaces, but the selected actor
category determines which entity-ID and action-type fields are meaningful. Its baseline network
serializes selection as actor category, entity pointer, then exact action
([CivRealm paper](https://arxiv.org/abs/2401.10568),
[official tensor-agent documentation](https://bigai-ai.github.io/civrealm/advanced_materials/tensor_agent.html)).

The paper emphasizes that technology and game progress continually change the available action
space. Its canonical RL agents perform reasonably on mini-games but struggle in the full game.

Lesson for TD Micro: Civilization research independently converged on hierarchical category and
entity selection. The fixed transport may contain many fields, but the policy must not sample all
of them as unrelated simultaneous decisions.

### ELF Mini-RTS: Fast Simulation And Hierarchical Commands

ELF's Mini-RTS is another close strategic precedent. It includes fog of war, gathering,
construction, and combat, and the paper reports roughly 40,000 frames per second per core. The
engine exposes a command hierarchy so a learned policy can act at a strategic level while built-in
tactics execute lower-level behavior. It trained a full-game agent against built-in AIs on one
machine
([ELF paper](https://papers.neurips.cc/paper/6859-elf-an-extensive-lightweight-and-flexible-research-platform-for-real-time-strategy-games.pdf)).

Lesson for TD Micro: our fast Zig simulator plus real-game inference plan has strong precedent.
Macro commands can help a curriculum, but they should supplement rather than permanently replace
the primitive semantic commands needed for faithful Vanilla control.

### Hierarchical StarCraft: Learned Macro Actions

Pang et al. reduced StarCraft II's action space with macro-actions extracted from expert
trajectories and a two-level curriculum. Their first setting deliberately used a 64x64 map and a
restricted unit set against the easiest built-in AI before transferring to harder full-game tasks
([full-length StarCraft paper](https://arxiv.org/abs/1809.09095)). LastOrder separately learned to
select macro actions while the existing bot supplied their lower-level execution
([LastOrder macro-action paper](https://arxiv.org/abs/1812.00336)).

Lesson for TD Micro: the current reduced-unit easy-AI curriculum has direct precedent, and optional
macro/options can later improve long-horizon exploration. They are not a substitute for repairing
the primitive action ABI: both StarCraft systems delegate behavior below the selected macro, while
this project ultimately needs the learned policy's commands to execute faithfully in Vanilla TD.

## Supporting Action-Space Research

### Invalid-Action Masking Beats Penalties

Huang and Ontanon show that sampling from a correctly masked and renormalized categorical policy
produces a valid policy gradient. Their experiments also show that, as the invalid space grows,
masking scales while invalid-action penalties fail to find even the first reward
([invalid-action masking paper](https://arxiv.org/abs/2006.14171)).

This directly rejects a larger invalid-action penalty as the solution to ABI 9. A penalty asks PPO
to rediscover deterministic game rules through sparse experience. It also risks making no-op the
safest policy.

### Action Branching Reduces Outputs But Assumes Independence

Branching Dueling Q-Networks use a shared torso followed by one branch per action dimension. This
changes output growth from combinatorial to linear by allowing independence between dimensions
([Action Branching Architectures](https://arxiv.org/abs/1711.08946)).

ABI 9 already receives this output-count benefit. The missing capability is conditional legality.
Shared hidden features can correlate logits statistically, but independent sampling still cannot
make `product` depend on the sampled `command`.

### Pointer Networks Handle Variable Entity Sets

Pointer Networks use attention to select an element of a variable-length input sequence, so the
output dictionary changes with the input
([Pointer Networks](https://arxiv.org/abs/1506.03134)). AlphaStar and CivRealm use this idea for
entity selection.

TD Micro's fixed 64 slots are acceptable as a transport limit, but a future field-aware encoder
should score actor and target records with shared entity weights. That is an encoder/decoder quality
improvement, not a prerequisite for ABI 10 legality.

### Parameterized Actions And Temporal Options

Parameterized-action research formalizes a discrete action type with action-specific parameters
([Deep RL in Parameterized Action Space](https://arxiv.org/abs/1511.04143)). Later work explicitly
conditions the parameter policy on the discrete action output
([Hierarchical Approaches for Parameterized Action Space](https://arxiv.org/abs/1810.09656)). This
matches `command -> arguments` more closely than independent `MultiDiscrete` heads.

The options framework treats a high-level action as a closed-loop policy that runs for a variable
duration
([Between MDPs and Semi-MDPs](https://www.ece.uvic.ca/~bctill/papers/learning/Sutton_etal_1999.pdf)).
Options are relevant to later commands such as `harvest_until_full` or `attack_move`, but introducing
them now would mix action-interface repair with hierarchical RL.

## Candidate Architecture Comparison

| Design | Exact legality | Native CUDA now | One game decision per policy step | Scales to full TD | Verdict |
| --- | --- | --- | --- | --- | --- |
| ABI 9 independent heads | No | Yes | Yes | Poor | Retire |
| Flat Cartesian action ID | With a huge mask | Yes | Yes | No | Reject |
| Dynamic list of complete legal actions | Yes | Not with current dense decoder | Yes | Poor for spatial moves | Limited use |
| Independent action branches | Only if dependencies do not cross branches | Yes | Yes | Incomplete | Not enough |
| Native command-gated dependency graph | Yes | Requires native CUDA work | **Yes** | Best fit | **Production recommendation** |
| Fixed four-token conditional grammar | Yes | **Yes** | No; four policy steps | Good | Reference/prototype only |
| Full linear autoregressive decoder | Yes | Requires more native CUDA work | Yes | Best expressiveness | Add only as needed |
| UAS repeated per-unit selection | Yes | Requires protocol changes | Multiple calls | Good for simultaneous unit orders | Later only |
| GridNet per map cell | Yes with full masks | Requires new model | Yes | Wasteful at 64x64 | Reject |
| SMAC-style one agent per unit | Yes | Requires MARL/vector redesign | Many agent actions | Tactical only | Future sub-policy |
| Macro/options-only policy | Yes | Yes | Variable duration | Loses primitive control | Auxiliary only |
| Continuous coordinates/action embedding | Approximate | Requires new model | Yes | Poor rule fit | Reject for now |

## Detailed Tradeoffs

### Flat Complete Actions

A single masked `Discrete(K)` is attractive because standard PPO handles it perfectly. It works
well for a small build-only curriculum. It fails as a full interface because movement alone can
contain up to `64 actors * 4096 cells = 262,144` complete actions before attack, harvesting,
production, or placement are added.

A dynamic legal-action list reduces `K`, but a dense decoder does not know what a changing list
slot means unless candidate descriptors are part of the observation and the model scores them.
That becomes a custom pointer/attention policy and still has a potentially enormous movement list.
Candidate pruning to "interesting" destinations could be useful in a curriculum, but it silently
changes what the final agent is allowed to do.

### Repair, Rejection, And No-op Conversion

These are not acceptable primary designs:

- **Invalid penalty:** empirically scales poorly and encourages conservative no-op behavior.
- **Convert invalid to no-op:** gives no-op many aliases and trains on a policy distribution that is
  much less informative than its raw entropy suggests.
- **Deterministic repair:** many raw actions map to one semantic action. PPO's stored raw-action
  probability is not the probability of the executed semantic action unless all alias probabilities
  are aggregated.
- **Resample until legal:** changes the normalized joint distribution. Correct PPO would need the
  probability mass of the complete valid set, defeating the apparent simplicity.

### Grid Or Per-Entity Simultaneous Outputs

GridNet is well matched to microRTS maps where every unit occupies one cell and every owned unit
must receive an action at each frame. On TD Micro's 64x64 map it would produce thousands of
mostly discarded cell outputs. It also changes the current human-like limit of one semantic command
per decision.

A transformer that emits one action per observed owned entity avoids empty cells and has been
demonstrated in microRTS
([Transformers as Policies for Variable Action Environments](https://arxiv.org/abs/2301.03679)).
It is a stronger future design if simultaneous unit orders become a requirement. It is a model and
multi-action protocol change, not the shortest fix for the current policy.

### Multi-Agent Unit Control

SMAC-style control could eventually split the system into:

- one commander for economy, production, placement, and squad objectives;
- one shared unit policy for movement, target selection, and combat micro.

That may improve tactical generalization, but it creates dynamic agent lifetimes, many actions per
game decision, and a new credit-assignment problem. We should first establish a reliable
player-level policy and measure whether unit micro is actually the learning bottleneck.

### Stock TD AI Already Issues Multi-Unit Orders

The one-actor player ABI is more restrictive than both the human interface and the original TD AI.
Stock `HouseClass::AI_Attack` loops over every owned aircraft, vehicle, and infantry object during
one strategy invocation and can queue `MISSION_HUNT` for many of them on the same game frame.
`TeamClass::Coordinate_Attack` is even more explicit: it loops the linked list of team members and
assigns every initiated member `MISSION_ATTACK` with the same team target during one team-AI tick.
`Coordinate_Move` similarly assigns movement across the team.

`MissionClass::Assign_Mission` only writes `MissionQueue`; each object subsequently commences and
executes its mission through normal object AI. Thus the orders share an issue frame even though
pathfinding, mission timers, facing, movement, and weapon cooldowns can make their visible actions
diverge.

The current Zig Easy-AI port preserves the house-level behavior: `aiAttack` scans all supported
opponent infantry and queues `mission_hunt` for every selected member during one house phase. It
does not yet reproduce the complete stock `TeamClass` subsystem.

This means a player group command is not a superhuman convenience. It restores an affordance already
available to the original AI and to a human through box selection. With four game frames per policy
decision, ordering ten units through the current one-actor ABI consumes forty game frames before
the last unit receives its order.

### Implemented Experimental ABI14: 64 Binary Buttons

ABI14 is **not** one categorical choice over `2^64` subsets and is **not** an
eight-byte action exposed to the policy. It has 64 separate integer action heads of size two:

```text
select_00 = 0 or 1
select_01 = 0 or 1
...
select_63 = 0 or 1
```

They accompany one shared semantic command and its shared target. An attack transition is
conceptually:

```text
command = attack
target = enemy_03
selected = [0, 1, 1, 1, 0, ..., 1]
```

Every eligible owned entity whose selector is `1` receives that same attack order before any game
frame advances. One transition still cannot order a harvester to one cell, send an E1 somewhere
else, and start E3 production. Those remain separate decisions. The policy action tensor will
physically contain the heads in contiguous memory for batching, but each selector remains a
separately sampled binary action. Packing them into a machine word inside the simulator would be an
optional implementation detail, not the policy contract.

This is a compact approximation of the action grammar used by AlphaStar: choose an action type,
choose any subset of owned units, then choose a target
([open AlphaStar manuscript](https://storage.googleapis.com/deepmind-media/research/alphastar/AlphaStar_unformatted.pdf)).
AlphaStar uses a recurrent pointer network for the selected set. The fixed 64-slot TD Micro
observation makes separate binary selectors a much smaller experiment while the current armies
remain around six to ten controllable combat units.

#### Conditional Probability Contract

Appending 64 ordinary independent heads to ABI9 is not sufficient. It would make PPO optimize
meaningless selector coin flips during `noop`, build, place, and train commands. It would also let
empty, dead, building, harvester, or otherwise ineligible slots contribute entropy and likelihood.

The native sampler and PPO scorer must instead implement:

```text
P(command | state)
* P(active selectors | command, state)
* P(target | command, selected set, state)
```

The implemented contract:

- activate the 64 selectors only for group-capable commands, initially `attack`;
- force empty and ineligible entity slots to `0`;
- give every forced or inactive selector exactly zero log-probability, entropy, and gradient;
- retain one 0/1 head for each eligible entity rather than replacing the set with a categorical
  actor;
- apply selected actors in ascending observation-slot order before advancing the four-frame
  decision interval; and
- treats an all-zero attack selection as one canonical no-effect action without a reward penalty.

The target head should eventually observe a pooled representation of the sampled selected set.
SCC found that all argument heads need to condition on the action type and that target-unit and
target-position heads also benefit from the selected units
([SCC architecture supplement, section A.4](https://proceedings.mlr.press/v139/wang21v/wang21v-supp.pdf)).
The first controlled experiment may leave target logits command-conditioned but not
set-conditioned if that is required to isolate the group selector. A later ABI can average the
existing bounded per-actor query vectors and score targets against that group query.

The PPO joint log-probability is the sum across active selectors. This is manageable with the
current six-to-ten-unit armies, but at dozens of eligible units small per-head policy changes can
compound into a clipped joint PPO ratio. Empty and ineligible slots must therefore never count, and
the scaling must be re-evaluated before expanding to full-size armies.

#### Runtime And Protein Selection

This is an action ABI, not a loose semantic toggle, because it changes action heads, masks, policy
weights, checkpoints, and Vanilla inference. Preserve ABI9 and ABI13 and add the group selector as a
new ABI rather than replacing either implementation.

The current runtime is already close to supporting this experiment:

- `binding.c` reads `env.action_abi` before exposing the action shape;
- the native backend creates the environment before constructing the policy;
- sweep trials run in separate spawned processes, so every trial can have one static ABI; and
- Protein accepts categorical INI parameters.

A two-scheme sweep uses the public `action_scheme` selector:

```ini
[env]
action_scheme = 0

[sweep.env.action_scheme]
distribution = categorical
values = 0, 1
scale = auto
```

Scheme `0` resolves to ABI9 and scheme `1` resolves to ABI14. The lower-level `env.action_abi`
setting defaults to `0`, meaning derive the ABI from the scheme; explicit `9`, `13`, or `14`
remains available only as a compatibility override and is excluded from sweeps. The native backend
stores and dispatches the ABI explicitly. Native fixed evaluation is ABI-aware. Visible Vanilla
inference still assumes ABI13, so an ABI14 checkpoint cannot be promoted for visible-game transfer
until that adapter is implemented. Checkpoints from different action ABIs are intentionally
incompatible.

Protein can optimize a binary categorical choice, but it cannot make an under-sampled architecture
comparison fair. Action ABI interacts with entropy coefficient, learning rate, network size, and
horizon. Run paired fixed-hyperparameter screens with multiple seeds first, then expose `9` versus
`14` to a joint sweep with enough trials for both schemes. Compare full-match balanced performance,
curve stability, and final fixed-suite evaluation rather than one noisy endpoint.

#### Promotion Gates

Implementation status:

1. Complete: focused mask, decode, empty-set, sparse-set, and atomic-rejection tests.
2. Complete: inactive selectors and an empty-set target have zero log-probability contribution,
   entropy contribution, and gradient.
3. Complete: native CPU/CUDA log-probability, entropy, and gradient parity, including finite
   differences.
4. Complete: the repeated 128-decision Zig group trace has digest
   `294be02cc1bd0b3672df4c42f7f03dc7a7f07d8178d1da9801384e9492eab425`.
5. Complete: selected slots are validated atomically and ordered ascending before simulation
   advancement.
6. Pending: visible Vanilla action and decision parity for ABI14.
7. Complete: adjacent fixed-workload and end-to-end ABI9/ABI14 measurements.
8. Pending: matched multi-seed learning screens with unchanged observations, rewards, curriculum,
   and training hyperparameters.

The simulator-side operation is only a bounded 64-slot scan. The material engineering work is the
command-gated CUDA sampler/PPO loss, checkpoint-aware evaluation, and Vanilla transfer path. This is
still a reasonable experiment: it directly removes the current one-unit command bottleneck without
granting heterogeneous simultaneous commands or redesigning the rest of the game.

The fixed no-op native A/B held simulation behavior constant and measured ABI9 at `116,725.560`
SPS versus ABI14 at `114,385.752` SPS, a `2.0%` mask/plumbing cost. Both runs completed 939
episodes with exact digest
`8814cd2df3976c88bda246c141394402158d81c80b2ba6e75ccc444bf170ecf6`.
The short end-to-end GPU runs measured `35,734` SPS for ABI9 and `20,514` SPS for ABI14, but random
ABI14 policies issued multi-unit attacks, produced much shorter episodes, and reset more often.
That `42.6%` difference is behavior-dependent and is not the intrinsic cost of the ABI. Normalized
Puffer timers attribute about 69% of the added step time to environment execution, 20% to GPU
rollout/action sampling, 4% to PPO training, and 7% to other overhead. See
`docs/td_micro/abi14_group_action_experiment.md` for commands and the full validation record.

## Four-Token Reference Grammar

The simplest way to exercise exact conditional masks without changing PufferLib's native sampler
is one categorical action head of size 65. Values `0..63` carry command IDs, products, slots, or
coordinates according to the current grammar stage. Value 64 is the canonical `PAD` token.

This is a useful executable specification and possibly a short experimental baseline. It is **not
the recommended production ABI**, because it turns one semantic game decision into four PPO
transitions. The table is retained because the same grammar defines the mask oracle and provides a
clear test reference for the one-step native decoder.

Every command has exactly four tokens:

| Semantic command | Token 0 | Token 1 | Token 2 | Token 3 |
| --- | --- | --- | --- | --- |
| No-op | `noop` | `PAD` | `PAD` | `PAD` |
| Deploy | `deploy` | actor slot | `PAD` | `PAD` |
| Start build | `start_build` | product | `PAD` | `PAD` |
| Place | `place` | x | y | `PAD` |
| Train | `train` | product | `PAD` | `PAD` |
| Move | `move` | actor slot | x | y |
| Attack | `attack` | actor slot | enemy slot | `PAD` |
| Harvest | `harvest` | harvester slot | x | y |
| Return cargo | `return_cargo` | harvester slot | refinery slot | `PAD` |

`guard`, `stop`, and `hunt` retain stable semantic command IDs but remain masked until their game
implementations and tests exist.

The command implies the argument types, so the grammar removes `target_kind`. For `place`, the
queued product is derived from state rather than sampled. The decoder still asserts that a completed
queue exists before exposing the command.

### Conditional Masks

The Zig environment owns the grammar and emits an exact mask at each stage:

1. **Command:** only commands with at least one legal completion.
2. **Primary argument:** only actors/products legal for the sampled command, or only `PAD`.
3. **Secondary argument:** only legal target slots/x coordinates given the prefix, or only `PAD`.
4. **Final argument:** only legal y coordinates given command, actor/product, and x, or only `PAD`.

Examples:

- `attack` exposes only armed player infantry as token 1.
- After an attacker is selected, token 2 exposes only visible enemy slots it may target.
- `harvest` exposes only active harvesters, then only x/y pairs containing live Tiberium.
- `place` exposes only x/y pairs passing the exact placement rules.
- `noop` has three singleton `PAD` masks, producing zero irrelevant entropy.

Required invariant: every unmasked prefix has at least one legal completion.

### Reference Environment State Machine

If this reference is run as an actual PufferLib environment, each vectorized environment stores a
small pending-action state:

```text
stage:  0..3
token0: command or unset
token1: primary argument or unset
token2: secondary argument or unset
```

The protocol operates as follows:

1. Read one masked token from the normal native CUDA action buffer.
2. Record it in the pending prefix and update the next mask.
3. Do not mutate the world, run the opponent, advance timers, emit shaping, or test terminals on
   stages 0-2.
4. At stage 3, decode the complete semantic `Action`.
5. Assert that `input.apply` accepts it, advance the normal decision frames once, collect reward and
   terminal state, clear the prefix, and return to stage 0.

The policy observation must include the stage and selected prefix tokens. These can use reserved
global observation bytes, so the 2,456-byte observation need not grow materially.

This creates a valid augmented MDP. The policy distribution over one completed command is:

```text
pi(a | s)
  = pi(t0 | s)
  * pi(t1 | s, t0)
  * pi(t2 | s, t0, t1)
  * pi(t3 | s, t0, t1, t2)
```

PufferLib already stores the per-step mask used for sampling and PPO evaluation, so sampling and
training use the same normalized conditional distribution. That makes the reference internally
valid, but it does not make four transitions equivalent to one composite PPO action.

### Discounting And Rollout Accounting

There is no exact fixed-`gamma` conversion from the current one-command transition to four token
transitions. Setting

```text
gamma_token  = gamma_command^(1/4)
lambda_token = lambda_command^(1/4)
```

matches the aggregate discount between command-boundary value estimates, but the final command
reward is delayed across the prefix transitions. It also changes GAE attribution. Exact
command-time semantics would require transition-specific factors: `gamma=1` and `lambda=1` on
prefix transitions, then the configured command-level values on completion, or a trainer that
groups all four log-probabilities into one PPO transition. PufferLib's normal native path currently
uses fixed values, so the fourth-root setting is only an approximation.

The recurrent state also advances four times while the world is frozen. Stage and prefix bytes make
that augmented process observable, but they change the policy's memory timescale. These are not
implementation details that can be ignored when comparing learning curves.

Any experiment with this reference should use a horizon and minibatch that are multiples of four.
Four million token steps contain approximately one million completed commands. Report all three
throughput measures:

- Puffer token SPS;
- completed semantic commands per second;
- simulated C&C frames per second.

Do not claim a speedup from token SPS alone. Prefix steps are intentionally cheaper because they do
not advance the game.

### Reference Uses And Costs

Benefits:

- Exact legal actions using the existing action-mask mechanism.
- One 65-way head instead of seven independent heads totaling 279 logits.
- No custom Python policy and no `--slowly`.
- No PufferLib CUDA changes for the first implementation.
- Canonical no-op and padding representation.
- The same grammar can drive Zig and Vanilla inference.
- A direct TDD oracle for the production native decoder.

Costs:

- Four encoder/policy evaluations and four rollout records per completed command.
- Effective game-decision horizon is one quarter of the token horizon.
- Vanilla inference initially performs four small policy calls per game decision.
- Reported Puffer SPS is no longer the same as semantic command SPS.
- Fixed-discount PPO and recurrent-state timing no longer match ABI 9 command time.

The reference remains useful for exhaustive grammar tests and a short learning sanity check. It
should not become the long-lived training ABI unless adjacent evidence shows that its altered time
semantics and semantic throughput are acceptable.

## Recommended ABI 10: Native Conditional Tagged Union

ABI 10 should preserve the existing rule that one PufferLib step applies one complete semantic
command and advances the game once. The decoder samples `command` first, activates only that
command's branch, and samples the branch's arguments in its declared dependency order. All sampled
log-probabilities belong to one rollout transition. This is the PySC2/AlphaStar/OpenAI Five/SCC
structure reduced to the dependencies TD Micro actually needs.

### Semantic Branches

The fixed transport can remain an `Action` record, but only the fields named by the selected branch
are policy outputs:

| Command | Active policy arguments | Canonical decoder behavior |
| --- | --- | --- |
| `noop` | none | Zero every argument |
| `deploy` | owned actor | Fill `actor` |
| `start_build` | structure product | Fill `product` |
| `place` | x -> legal y | Derive product from the completed queue; fill cell |
| `train` | infantry product | Fill `product` |
| `move` | movable actor -> x -> y | Derive cell target kind |
| `attack` | armed actor -> visible enemy | Derive visible-enemy target kind |
| `harvest` | harvester -> x -> live y | Derive cell target kind |
| `return_cargo` | harvester -> owned refinery | Derive own-entity target kind |

`guard`, `stop`, and `hunt` keep their command IDs but remain command-masked until their semantics
and tests exist. `target_kind` is never sampled; it is a deterministic consequence of the command.
The queued structure product for `place` is also state, not a decision, so sampling it would add an
unnecessary alias.

The rollout transport can be a fixed four-value prefix record:

```text
[command, argument_0_or_PAD, argument_1_or_PAD, argument_2_or_PAD]
```

All values are sampled inside one native policy callback and stored as one PPO action. The semantic
decoder fills derived fields such as `target_kind`, queued product, or Tiberium x/y. This fixed
record is not the four environment transitions described in the reference design.

### Minimal Dependency Graph

Legality and useful policy expressiveness are different requirements. A source audit shows that,
after selecting the command, most current actor-target combinations are executable:

- [`movement.apply`](../../td-micro/src/movement.zig) accepts every in-bounds x/y for every valid
  movable actor. Reachability affects execution, not command validity.
- [`combat.apply`](../../td-micro/src/combat.zig) accepts every valid armed infantry actor paired
  with every visible live enemy slot.
- [`economy.assignHarvest`](../../td-micro/src/economy.zig) accepts every active harvester paired
  with every live Tiberium cell.
- [`economy.assignReturn`](../../td-micro/src/economy.zig) accepts every active harvester paired
  with every operational owned refinery.

Independent arguments could therefore make rejection zero, but they would still impose
`pi(actor, target | command, state) = pi(actor | command, state) * pi(target | command, state)`.
That cannot express "this infantry attacks that nearby target" or "this harvester uses that field."
SCC's selected-unit ablation is direct evidence not to keep that restriction.

Use this dependency graph:

```text
command
|-- noop
|-- deploy -> actor
|-- start_build -> product
|-- place -> x -> y
|-- train -> product
|-- move -> actor -> x -> y
|-- attack -> actor -> enemy
|-- harvest -> actor -> x -> y
`-- return_cargo -> actor -> refinery
```

Placement and harvest y are conditioned on x for legality. Move, attack, harvest, and return
targets are conditioned on the actor for expressiveness even where the current legality mask is
actor independent. Unrelated branch heads do not condition on one another.

Sequential coordinates do not reduce control: `pi(x, y) = pi(x) * pi(y | x)` can represent any
distribution over the full 64x64 grid while evaluating two 64-way heads instead of one 4,096-way
head.

The target head should consume a compact embedding of the selected entity record, not only its slot
number. A small concat-plus-FC block matches SCC's successful design and lets the target distribution
use unit type, position, health, and mission state. Fixed slots remain the transport; shared entity
encoding can be introduced without changing action semantics.

### Initial Native Head Budget

Using current fixed domain sizes, the categorical widths across the graph are:

| Head | Width |
| --- | ---: |
| command | 12 |
| deploy actor | 65 |
| start-build product | 6 |
| place x, y | 64 + 64 |
| train product | 6 |
| move actor, x, y | 65 + 64 + 64 |
| attack actor, target | 65 + 64 |
| harvest actor, x, y | 65 + 64 + 64 |
| return actor, refinery | 65 + 64 |
| **Total across all branch heads** | **861** |

Only one branch is evaluated for a sampled command. The widest active paths are move and harvest at
`12 + 65 + 64 + 64 = 205` categorical values. This is far smaller than a 4,096-way flat cell head
while retaining every legal cell.

Exact placement and live-Tiberium masks can each be exported as 64 conditional y rows. Each is
4,096 bytes as byte masks or 512 bytes as 64-bit row bitsets. The latter is a reasonable native
transport optimization after a byte-mask reference passes parity. Do not prune legal cells or
change game control merely to make the tensor smaller.

### Categorical Index Precision

Using x/y instead of a 344-way Tiberium index also avoids a current native correctness trap. The
default CUDA build defines `precision_t` as BF16 in
[`kernels.cu`](../../PufferLib/src/kernels.cu), and rollout actions are `PrecisionTensor` values in
[`pufferlib.cu`](../../PufferLib/src/pufferlib.cu). BF16 represents every integer only through 256;
above that, adjacent odd indices are not distinct. A sampled Tiberium index such as 301 could be
rounded before reaching the environment or PPO replay.

Every proposed ABI 10 categorical value is at most 64, so it round-trips exactly through the current
buffers. Add an exhaustive action-value round-trip test. If a later entity or candidate head needs
more than 256 values, convert discrete rollout actions to an integer tensor rather than relying on
floating-point storage.

### Native Sampling And PPO Contract

The local PufferLib CUDA path needs a small conditional-head descriptor mapping each command to its
active path and each head to the prefix values it consumes. Sampling is:

```text
prefix = [masked_sample(command_logits(state), command_mask(state))]
logprob = logprob(prefix[0])
active_head_entropy = entropy(command)

for head in active_path[prefix[0]]:
    logits = head(state_embedding, embeddings(prefix))
    mask = zig_mask_for(head, prefix)
    prefix.append(masked_sample(logits, mask))
    logprob += logprob(prefix[-1])
    active_head_entropy += entropy(head | prefix)

set every inactive field to canonical zero/PAD
```

PPO evaluation must replay the stored prefix through exactly the same path and sum the conditional
log-probabilities. PPO ratios therefore use the exact probability of the executed composite action.
For entropy regularization, initially sum the exact categorical entropy of each active head at its
recorded prefix. This is a practical per-active-head regularizer, not the exact gradient of joint
entropy through the sampled discrete parents; document that distinction rather than hiding it.
Inactive heads receive no policy loss, entropy loss, or gradient.

Zig remains the sole game-rule authority: it exports every prefix mask alongside the observation;
CUDA performs masked categorical sampling, conditional head evaluation, and probability
accounting. Every unmasked prefix must have at least one legal completion.

The observation torso and value head run once. Argument heads then run in the selected branch's
short native sequence, inside the same environment/PPO transition. Sampling needs staged native
execution; evaluation is easier because the rollout already contains every prefix. Profile kernel
launches and conditional-head compute adjacent to ABI 9. This still uses normal PufferLib CUDA
training with `--train.gpus 1`; it does not use `--slowly`.

There must be no host synchronization between heads. For the small current domains, the preferred
rollout implementation is one fused/predicated CUDA kernel per batch that computes and samples only
the selected path while retaining the persistent RNG state. A fixed sequence captured in the
existing rollout CUDA graph is the fallback. Training can batch replay by stored branch because all
prefixes are already known. The adjacent profile decides between those native implementations.

### Local PufferLib Implementation Boundary

This is not an INI change or an environment-only mask change. The current native path makes four
independence assumptions that ABI 10 must replace:

- [`decoder_forward`](../../PufferLib/src/models.cu) is one linear projection over all logits.
- [`sample_logits`](../../PufferLib/src/pufferlib.cu) loops through every declared action head and
  samples each one independently.
- [`ppo_loss_compute`](../../PufferLib/src/pufferlib.cu) scores every head and writes gradients for
  every logit.
- Rollout action and mask buffers assume one flat list of independent head widths.
- The decoder receives only the recurrent hidden tensor, not the selected 16-byte entity record
  needed by actor-conditioned target heads.

PufferLib's native `Decoder` already uses function pointers, which is a useful extension boundary,
but `build_policy` currently installs only the default decoder and the sampler/loss live outside that
abstraction. A decoder hook alone is therefore insufficient.

The clean local change is a native action-distribution interface selected by static environment
metadata, with access to the hidden state and current observation and with operations for staged
rollout sampling and stored-prefix PPO evaluation/backward. It can gather and encode the selected
entity record directly during rollout and replay rather than forcing all slot identity through a
single shared recurrent bottleneck.
The fixed rollout action stores the sampled prefix values, while a fixed mask buffer stores command
masks and conditional prefix tables. The implementation needs:

1. conditional decoder weights, activations, checkpoint metadata, forward, and backward;
2. one-transition staged CUDA sampling using the persistent per-agent RNG;
3. active-path log-probability, entropy, PPO ratio, and gradient logic;
4. fixed-shape prefix-mask storage and rollout transposition;
5. CPU-reference, CUDA, checkpoint, determinism, and throughput tests.

That is meaningful PufferLib-core work, but it is bounded and directly addresses the measured
failure. It remains the standard compiled native/CUDA backend and local repository code. It does
require local PufferLib source changes, but it does not require a Python policy, `--slowly`, an
upstream contribution, or a push to PufferLib's remotes.

### Future Full Autoregressive Decoder

The recommended graph is already autoregressive where TD needs it. "Full" AlphaStar-style decoding
would additionally force every later head to consume every earlier selection in one linear chain.
SCC found that unnecessary for unrelated heads. Entity pointer heads should replace fixed
actor/target classifiers when the entity cap or unit diversity makes shared entity scoring
valuable.

The hard part is obtaining conditional masks without CPU/GPU round trips. Options include compact
prefix mask tables exported by Zig, a native callback/staged sampler, or duplicated legality logic
in CUDA. The last option risks simulator/learner drift and should be avoided unless profiling proves
it necessary. SCC's ablation says not to pay for a full dependency chain before the task needs one.

## Expected Impact And Remaining Unknowns

ABI 10 provides three structural changes:

- rejected policy actions fall from 44.943% to zero unless there is an invariant bug;
- inactive arguments and no-op aliases disappear from policy log-probability and entropy;
- one policy transition remains one semantic command, preserving command-time rewards and discount.

It does **not** guarantee a higher win rate or higher SPS. The first implementation is more expressive and
the microRTS masking ablation makes improved learning a strong hypothesis, but TD Micro still has
long-horizon exploration, reward, observation-encoder, and opponent-curriculum problems. Staged
CUDA heads and larger conditional-mask buffers may also cost throughput. Those are adjacent A/B
measurements, not claims to make in advance.

ABI 9 checkpoints cannot be loaded as ABI 10 policies without an explicit migration experiment.
Keep them for historical evaluation and behavior-cloning data; expect the new action decoder to be
trained from a controlled initialization.

## TDD, Determinism, And Benchmark Gates

### Grammar Unit Tests

- Every command round-trips through semantic action -> tagged branch -> semantic action.
- Every enabled command has a legal completion through its active prefix path.
- Every completed masked branch action is accepted by `input.apply`.
- Every inactive argument is exactly `PAD`.
- `target_kind` is derived from command and never sampled.
- The placement x mask and every conditional y row match `placement.isLegal` exactly.
- The harvest x mask and every conditional y row contain exactly live Tiberium cells.
- Actor and target masks use the same stable entity-slot ordering as the observation.
- The four-token reference enumerates the same semantic action set as the branch masks.
- Every stored categorical value round-trips through the configured rollout precision exactly.

### Native Sampler And Loss Tests

- Fixed logits, masks, and recorded actions produce the same active-head log-probability and entropy
  in a small CPU reference and the CUDA evaluator, within the established numeric tolerance.
- Sampling never selects a masked command or branch value.
- Inactive heads are canonical and contribute exactly zero log-probability, entropy, and gradient.
- Re-evaluating a stored rollout action uses the stored command's branch map.
- Changing the selected actor can change move/attack/harvest/return target logits without changing
  the observation torso output.
- Selecting placement x chooses the matching conditional y mask.
- An unchanged policy produces PPO ratio 1 for every command shape.
- Every composite command remains one rollout transition and one environment step.
- Reset and rollout boundaries require no pending prefix state in production ABI 10.

### Replay Parity

- Encode existing semantic fixture traces through ABI 10 and decode them back.
- Compare every command's world hash with the direct semantic-action reference.
- Compare final result, reward events, unit/building counts, economy, and RNG state.
- Run the same branch trace through Zig and Vanilla inference adapters and compare emitted semantic
  actions before comparing game-state parity.
- Repeat identical seeded CUDA sampling runs and require identical action/reward/hash traces on the
  same build and hardware.

### Random And Training Gates

- Fuzz masked branch selection across representative random worlds.
- Require zero rejected actions. A rejection is an invariant failure, not a reward metric.
- Build and run the normal native CUDA command with `--train.gpus 1` and without `--slowly`.
- Require `start_failures=0` and engine failures zero.
- Run adjacent ABI 9/ABI 10 benchmarks with unchanged PufferLib hyperparameters on the same idle
  machine.
- Report semantic-command SPS, simulated-frame SPS, agents, buffers, threads, horizon, minibatch,
  total steps, GPU mode, `start_failures`, and validity. In production ABI 10, one Puffer step is
  one semantic command again.
- Compare learning over several deterministic seeds using median and worst-case win rates, not one
  peak checkpoint.
- Do not spend a large sweep budget until short runs show zero invalid actions and no regression in
  deterministic replay, throughput, or basic learning.

## Recommended Work Order

1. Freeze ABI 9 checkpoints and traces as historical artifacts.
2. Implement the pure Zig tagged-union encoder, decoder, branch masks, and four-token reference
   oracle under exhaustive/property tests.
3. Add a small CPU reference for conditional sampling, log-probability, and entropy.
4. Implement the native conditional decoder/action-distribution interface, graph metadata,
   sampler, and PPO evaluator in the local PufferLib checkout, with CUDA-vs-reference tests before
   touching the environment binding.
5. Export the ABI 10 prefix masks from `cnc_micro`; retain one semantic command per environment
   step and increment the policy ABI.
6. Pass random masked-action, semantic replay, world-hash, reward, and Vanilla-adapter parity gates.
7. Build and run the normal native CUDA smoke test, then adjacent ABI 9/ABI 10 throughput benchmarks
   with all training hyperparameters held fixed.
8. Train several short deterministic seeds and compare invalid rate, median win rate, collapse rate,
   and wall-clock learning before spending another large sweep budget.
9. Profile staged native head execution, kernel launches, and conditional-mask transport. Optimize
   byte masks to bitsets or fuse kernels only where the adjacent profile shows a material cost.
10. Add dependencies beyond the declared graph and richer entity-pointer encoders incrementally as
    expanded game rules require them; do not redesign the semantic command contract.

## Bottom Line

The current representation is convoluted because it mixes a clean function-call command with a
Cartesian transport and asks PPO to discover which fields belong together. SC2LE, AlphaStar, SCC,
OpenAI Five, microRTS, SMAC, CivRealm, and parameterized-action research converge on the same core
lessons:

- select the command/category first;
- condition later arguments on that choice;
- use entity pointers or stable entity slots for dynamic actors and targets;
- mask parameters, not only command types;
- do not train game rules through invalid-action penalties;
- use hierarchy only where intentionally giving control to a lower-level policy or script.

For this repository, the serious production design is a one-step native CUDA conditional tagged
union: command gating plus actor-conditioned targets and conditional spatial coordinates. It
directly fixes ABI 9's 44.943% rejection problem without changing game-time discounting, rollout
accounting, or the established `--train.gpus 1` path. The four-token grammar is valuable as an
executable legality oracle and optional prototype, not as the default training ABI. Additional
AlphaStar-style dependencies should be added only when TD's expanded rules or measured learning
failures require them.
