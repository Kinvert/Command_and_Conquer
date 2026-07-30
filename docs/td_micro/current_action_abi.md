# TD Micro Current Action ABI

Date: 2026-07-19

Status: ABI9 is the current default training transport, with the completed coefficient study
retaining a zero invalid-action penalty. ABI13 remains compiled and runtime-selectable as the
conditional actor-target reference. Both run on the same current simulator; changing
`env.action_abi` does not change commits, tags, observations, rewards, maps, or opponent behavior.
Neither architecture is yet promoted as final.

## Runtime Selection

`PufferLib/config/cnc_micro.ini` selects `action_abi = 9` by default. Use 13 to select the retained
conditional path. ABI9 uses seven independent heads `{12, 65, 6, 4, 64, 64, 64}` and a 279-byte
mask. ABI13 uses four conditional heads `{12, 65, 65, 65}` and a 1,156-byte packed mask. The native
vector allocation and CUDA policy route are selected from that runtime metadata.

Penalty-zero ABI9 reproduces the historical 2M checkpoint hashes exactly. The rejected bounded
invalid-action coefficient study and its fresh paired evaluation are documented in
`old_action_noop_penalty_experiment.md`.

## ABI13 Reference Shapes

The observation remains observation version 5: a 2,456-element `ByteTensor` normalized by the
native `Normalize255Encoder`.

| Region | Bytes |
| --- | ---: |
| Globals | 64 |
| Authored Tiberium cells | 344 |
| 64 own-entity records | 1,024 |
| 64 enemy-entity records | 1,024 |
| **Total** | **2,456** |

One action is exactly four bytes with head sizes `{12, 65, 65, 65}`:

```text
RawAction = [command, arg0, arg1, arg2]
PAD = 64
```

| Command | Canonical sequence |
| --- | --- |
| noop | `noop, PAD, PAD, PAD` |
| deploy | `deploy, actor, PAD, PAD` |
| start_build | `start_build, product, PAD, PAD` |
| place | `place, x, y, PAD` |
| train | `train, product, PAD, PAD` |
| move | `move, actor, x, y` |
| attack | `attack, actor, enemy_slot, PAD` |
| harvest | `harvest, actor, x, y` |
| return_cargo | `return_cargo, actor, refinery_slot, PAD` |

`guard`, `stop`, and `hunt` keep stable command ids but are masked and rejected by this ruleset.
Placement derives its product from the completed structure queue. This removes product/queue
aliases and gives every inactive argument one canonical value.

## Exact Prefix Masks

Zig remains the legality authority. It exports 9,242 logical mask bits packed into 1,156 bytes:

- command legality;
- command-specific actor or product legality;
- exact `place y | x` rows for legal structure footprints;
- exact live-Tiberium `harvest y | x` rows;
- attack actor and visible-enemy slots;
- return-cargo Harvester and Refinery slots; and
- one shared PAD bit.

The sampler reads a branch mask only after its required prefix has been selected. Masked tokens are
excluded from normalization, sampling, entropy, and gradient calculations rather than represented
by a merely large negative logit. Randomized masked-sequence tests require every generated action
to decode and be accepted by `input.apply`.

## Native Policy Path

The ABI13 decoder retains ABI11's 2,352 base policy components:

```text
command: 12 logits
arg0:    12 command rows * 65 values
arg1:    12 command rows * 65 values
arg2:    12 command rows * 65 values
```

It then adds 1,024 rank-4 actor-query components and 1,536 rank-4 target-key components. Move,
attack, harvest, and return-cargo target branches use:

```text
base(target) + 2 * tanh((0.5 / 2) * dot(query(actor), key(target)))
```

The interaction starts as an exact zero residual, is bounded to `[-2, 2]`, and restores an explicit
selected-actor contribution without recreating ABI10's dense prefix table. The sampler still
selects all four tokens sequentially and applies the exact mask for each selected prefix. The CUDA
rollout kernel stores one four-byte action and one summed log-probability for one PPO/environment
transition, with no host synchronization.

The custom PPO kernel replays the same stored path. A PAD-only head has probability one, entropy
zero, log-probability zero, and gradient zero. Zig CPU inference uses the same layout for Vanilla
deployment.

| Item, hidden 64x1 | ABI10 | ABI11 | ABI13 |
| --- | ---: | ---: | ---: |
| Decoder outputs including value | 15,028 | 2,353 | 4,913 |
| Parameters | 1,131,264 | 320,064 | 483,904 |
| Raw checkpoint size | 4,525,056 bytes | 1,280,256 bytes | 1,935,616 bytes |

Checkpoint schemas remain shape-separated: ABI9 checkpoints load only on the ABI9 route, and ABI13
checkpoints load only on the ABI13 route. Cross-loading cannot silently succeed because the decoder
parameter counts differ.

## ABI13 Validation Results

No command used `--slowly` or CPU training.

- Zig tests: 166/166 in Debug, ReleaseSafe, and ReleaseFast.
- Host/device action-spec test: pass, including C ABI constant checks.
- C ABI smoke: ABI 13, 2,456-byte observation, 1,156-byte mask, zero failures.
- Scripted economy: Refinery 1, Harvester 1, income 675, first delivery 1, invalid 0, failures 0.
- Puffer binding and C inference checkpoint transfer: pass.
- Explicit CPU/CUDA score, probability, entropy, log-probability, and gradient parity: pass.
- Every retained ABI13 CUDA run: `invalid_actions=0`, `start_failures=0`, `failures=0`.
- Two 1M CUDA repeats have exact final checkpoint SHA-256
  `c281af96694ce3436a87f59939955efe072bda35008c7098ad44e42ac10c9450`.
- Native world digest remains
  `38cca1613d27fcaa4500c25261cff6ea19d838ccd80d9c91fec4d045d718ce28`.
- Completed-building placement masks retain the exact row-bitset implementation documented in
  `abi10_placement_mask_hotspot.md`.

Commands, effective configurations, artifact hashes, and W&B links are in
`abi13_actor_target_experiment.md`.

## Performance And Learning Tradeoff

The final ABI13 262,144-step run used 64 agents, one buffer, four threads, horizon 32, minibatch
2,048, hidden 64x1, and one GPU. It finished at 30,052 displayed SPS with all failure counters zero.
This is not a speedup claim. An adjacent native ABI11/ABI13 check was noise-level and retained the
same world digest; that native workload does not execute the policy decoder.

Under exact `qj7bux1j` settings, ABI13 reaches 0.384 reproducibly at 1M but only 0.092 at 2M. ABI11
reaches 0.175 and 0.161; ABI9 reaches 0.422 at 2M despite 44.943% rejected tuples. In the ABI13
30-run screen, the 28 non-bootstrap trials have median 0, mean 0.024, and maximum 0.203. The current
exact-action path therefore remains a valid experiment, not the promoted learning architecture.

The controlled ABI9 restoration is implemented and penalty zero is bit-identical to the historical
run. A matched 15-run 2M study plus 3,843-episode fresh paired evaluation rejected every nonzero
invalid-action coefficient. CNC11 then reproduced the three leading CNC10 1M outcomes exactly and
tested those configurations plus the historical 2M control over three fresh 2M seeds. The CNC10
families collapsed to near-zero medians; the control reached median 0.233987 but still had one zero
seed. No candidate is promoted. The next gate is fixed-low-rate continuation from the verified 1M
`5lk552uq` checkpoint, not another fresh 2M cosine restart. CNC12 tested weights-only continuation
at three fixed rates across three seeds and fell from the source 0.298395 common-evaluation
performance to a best 0.027437, with a zero seed at every rate. The existing policy-only checkpoint
format does not preserve optimizer or RNG state. The next gate is an opt-in full training-state
checkpoint/resume format. Preserve ABI13 as the reference for any later hybrid that combines ABI9's
learning behavior with conditional actor-target scores. See `cnc11_abi9_promotion_tournament.md`
and `cnc12_abi9_weights_only_continuation.md`.

## Historical Context

ABI 9 used `MultiDiscrete([12, 65, 6, 4, 64, 64, 64])`. Its masks could mark values legal per
head but could not represent legal combinations. Reproducible run `qj7bux1j` rejected 1,986.594 of
4,420.213 mean episode decisions, or 44.943%. The full diagnosis and source-backed design study are
in `action_space_architecture_study.md`.
