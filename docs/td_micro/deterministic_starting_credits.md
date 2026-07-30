# Deterministic Full-Match Starting Credits

Date: 2026-07-22

Status: implemented and validated for Zig/PufferLib training and credit-stratified promotion
outcomes. Schema 9 subsequently added an independent starting-force axis; visible Vanilla credit
selection and per-band economy telemetry remain follow-up work.

## Contract

Every scheduled `full_match` reset now gives both GDI players the same deterministic starting
credit amount:

| Branch | Weight | Values |
| --- | ---: | --- |
| Constrained | 35% | exactly `$2,300` |
| Random | 65% | `$2,400` through `$10,000`, inclusive, in `$100` increments |

The random branch contains 77 possible values. It is sampled from a stable 64-bit mixed value based
on setup seed, batch lane, and episode ordinal. The constrained branch uses this exact permutation:

```text
slot = (37 * (lane mod 100) + 53 * episode_ordinal) mod 100
constrained = slot < 35
```

This gives exactly 35 constrained assignments in every 100-lane block for any fixed episode
ordinal. No mutable runtime RNG is consumed by credit selection.

The distribution was introduced in `td-micro/rules/td_micro_v1.json` schema 8 and generated into
both Zig and C rule files. Its manifest SHA-256 changed from
`bcb23e390785cb3b500f763752ae354a45972ec864356352ea5614d59f2df389` to
`619ccb703dd91f4fd7b110db79ec8e77f21b63bf9245ed4e4218ba05eb5549de`.
Schema 9 retains this exact credit sampler and adds the independent starting-force contract
documented in `deterministic_starting_force.md`.

## Scope And Compatibility

- The distribution applies to normal full-match training and H5 full-match anchors inside the
  reverse curriculum.
- Both sides receive exactly the same amount. Difficulty is not introduced through asymmetric
  money.
- H0-H4 authored curriculum states are unchanged.
- `World.reset` and `curriculum.reset` remain fixed at `$10,000`, preserving Vanilla oracle fixture
  behavior and direct simulation tests.
- Existing observation version 5 already encodes player credits in hundreds at global byte 4.
  `$100` increments are therefore lossless and require no observation ABI change.
- Action ABI 9, rewards, spawn assignment, content, and policy checkpoint layout are unchanged.
  Existing policy-only checkpoints remain loadable, although the reset distribution is a real
  training-domain change.
- Full-match batch snapshots persist episode ordinals and selected starting credits. Schema 9 later
  advances snapshot versions to 3 for full match, 5 for curriculum, and 3 for the Puffer wrapper.
  Old environment-state snapshots are intentionally incompatible; policy-only checkpoints are
  unaffected.
- The current Puffer binding exports 25 user fields, with `env/n` appended separately.

The visible Vanilla TD Micro launcher still starts at `$10,000`. Do not claim a random-credit
Vanilla parity result until the launcher can select and report the same lane/episode assignment.

## TDD And Determinism

The implementation was driven from a failing test gate. The current Zig suite passes all 198 tests,
including:

- exact 35/65 assignment over 100 lanes;
- close/medium balance within one assignment;
- bounds, `$100` divisibility, all 77 random values reachable, and integer wraparound safety;
- equal player/opponent credits and exact observation byte 4;
- direct fixed-reset and H0-H4 compatibility;
- episode-to-episode resampling; and
- full-match snapshot/restore followed by an identical terminal reset.

The ReleaseFast gate also exposed and fixed uninitialized padding in the batch snapshot header.
Headers are now zero-initialized before field assignment, making serialized bytes deterministic in
both Debug and optimized builds.

ReleaseFast C checks also pass for the public batch API, refinery/harvester economy path, and Puffer
binding. Three identical C smoke replays produced this exact digest each time:

```text
d816a8cb01bce2164892437f87e2897a65b80dbb5733d7d02654283f85c4c77a
```

All pre-existing Vanilla oracle tests pass. Their fixture hashes remain accepted as prior-manifest
fixed-reset evidence rather than being regenerated.

## Native Performance

The adjacent benchmark used pristine commit `1ecdd987d13a5e5dd6b9f5de494033e23d656639` as the old
build and the current working tree as the new build:

```bash
taskset -c 0 /tmp/td_micro_batch_benchmark_{before,after} 64 16384
```

| Build | SPS runs | Mean SPS | Episodes | Failures | Digest |
| --- | --- | ---: | ---: | ---: | --- |
| Fixed `$10,000` | 169,352.776; 169,380.311; 170,066.095 | 169,599.727 | 320 | 0 | `38cca161...ce28` |
| Random credits | 164,947.261; 164,764.424; 164,766.804 | 164,826.163 | 273 | 0 | `a5b06a63...99e3` |

The measured difference is `-2.8%`, but this is a changed-workload result, not sampler overhead:
different credits change accepted builds, army sizes, terminal timing, and episode count. Both
builds are deterministic and failure-free.

## PufferLib CUDA Validation

Command:

```bash
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 1 \
  --vec.num-threads 4 \
  --train.total-timesteps 262144 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

Two exact-seed repeats produced:

- GPU training mode, MinGRU H64x1, ABI 9;
- 262,144 transitions each;
- final displayed SPS: `60,570` and `59,702` (mean `60,136`);
- `start_failures=0.000`;
- engine `failures=0.000`;
- exact initial checkpoint SHA-256 in both runs:
  `249cb9ef50ad5699e68010b6848bb11009b9e39796c8ae274d0876c1381fd928`;
- exact final checkpoint SHA-256 in both runs:
  `93f70dac71a6b6ee1929d33c01d5623f8793fbbdc14cd946af766e289b8ab553`;
- exact final environment-metric fingerprint in both runs:
  `18b06e00686aca107015e3ad53019983db4cc744f4300c55b40baf443c94c53e`;
- valid runs;
- logs: `PufferLib/logs/cnc_micro/1784765651967.json` and
  `PufferLib/logs/cnc_micro/1784766094656.json`.

Dashboard loss buckets are emitted on wall-clock polling boundaries and differed between runs. This
does not indicate training divergence: final weights and every final environment metric are exact.

### Exact stop/resume gate

The existing native CUDA training-state gate was rerun after the optimized snapshot-padding fix.
It used 64 agents, one buffer, four threads, horizon/minibatch 32/2,048, replay ratio 1, a split at
131,072 transitions, and a final step at 262,144. Uninterrupted and resumed execution matched
exactly for all six gates:

- independently produced split state;
- final serialized training state;
- final policy weights;
- post-split action/reward/terminal trace;
- final environment metrics; and
- training compatibility fingerprint.

Evidence:

| Artifact | SHA-256 |
| --- | --- |
| Final weights | `87700076c5e19a610eef3643f2e99053a80beebb467d5ffacdf131d892128647` |
| Final state | `58d3a3f3deb780401b9b23ecf8eab7cb3a82df17b624b3a3da8c3867bb97d448` |
| Post-split trace | `e44f7b6c1881aaeec12e3496d0506b03c56bd0dcbf2751b1b532aad67cb8d9fe` |
| Compatibility fingerprint | `7a333e55dd360a31a6f50a10752f80e21cc880ac39edad1cbf5387b2ded595db` |

The gate completed 157 episodes with `start_failures=0`, engine `failures=0`, and all corruption and
configuration-mismatch rejection checks passing. Machine-readable evidence is in
`PufferLib/logs/cnc_micro/starting_credit_state_gate/report.json`.

## Credit-Aware Fixed Evaluation

`tools/cnc_micro_fixed_eval.py` now reads each lane's actual initial credit byte from a temporary
native vector configured identically to the inference runtime. It does not duplicate the Zig credit
sampler in Python. Every episode JSONL row records exact starting credits and one of four versioned
evaluation bands:

| Band | Credits |
| --- | ---: |
| `constrained` | exactly `$2,300` |
| `low` | `$2,400-$4,900` |
| `mid` | `$5,000-$7,400` |
| `rich` | `$7,500-$10,000` |

The summary reports W/L/D for each band, the four spawn x starting-force cells, and all 16
spawn x force x credit-band cells. Two promotion scores are derived from the JSONL sidecar:

- `credit_balanced_perf`: arithmetic mean of the 16 cell win rates, so natural sampler frequency
  cannot let the 35% constrained atom or one force variant dominate the score;
- `credit_robust_perf`: epsilon-shifted harmonic mean of the same 16 rates, so a policy that
  fails one regime is ranked conservatively.

The evaluator rejects a suite with any empty cell. None of these detailed fields enter the live
Puffer log.

An exact 256-game native-CUDA repeat used checkpoint
`1784769912811/0000000001048576.bin` (SHA-256 `98426969...98e2d47`), 128 episodes per spawn,
four buffers, four threads, MinGRU H64x1, policy sampling seed 173, and a 12,000-decision timeout.
Both runs completed 603 native episodes with zero start or engine failures and matched exactly:

```text
suite_sha256    b04c9173996ebbac594565e76e78d9082f852f652acc9ae3a038d5d9392fa160
episodes_sha256 e437acfc59e41fe6bff32554cc6d5642954933809fe32e31a7ce9194076b7c56
```

All eight cells were nonempty. The old fixed-credit checkpoint scored zero wins under the new
domain, so it is validation evidence rather than a retained policy. Evaluator throughput was
174,255 and 176,661 executed transitions/s; this is inference throughput, not training SPS.

Per-band first-delivery rate, harvested credits, unit production, and no-delivery wins still need a
per-episode native telemetry path. Current Puffer aggregate logs cannot assign those values back to
individual lanes. Add that offline without increasing the 31-field live schema.

Also, `$2,300` does not structurally require harvesting: Power Plant + Barracks still leaves enough
for 17 E1. It creates a meaningful spending choice but does not complete `TASK-4`'s stronger
harvesting-required invariant.
