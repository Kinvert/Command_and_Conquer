# ABI13 Bounded Actor-Target Experiment

Date: 2026-07-19

Implementation commit: `9789107`

Status: technically valid, preserved, and **not promoted**. ABI13 restores an explicit selected-
actor/candidate-target interaction to ABI11 without changing the environment contract. It improves
the matched 1M result, but the matched 2M result and 30-run screen do not beat the historical ABI9
training baseline reliably. Further generic ABI13 sweeps are not the next priority.

## Decision

Keep this commit as a tested research result, not as proof that the exact conditional action path is
the final architecture.

- ABI13 exact repeats reach `0.383830` balanced performance at 1M steps.
- The same matched configuration reaches only `0.092308` at 2M steps.
- Excluding two deterministic bootstrap repeats, the 30-run screen has median `0`, mean `0.024241`,
  and best `0.203216`.
- Historical ABI9 reaches `0.421753` at 2M despite rejecting `44.943%` of sampled tuples.
- Every ABI13 run used below has zero invalid actions, start failures, and engine failures.

The next controlled experiment returns to ABI9's seven-head transport in an isolated branch. It
will retain invalid tuples as four-frame no-ops and test a very small invalid-action cost. ABI13
must not be deleted; it is the correct CPU/CUDA reference if a later hybrid restores conditional
actor-target scoring to the old transport.

## Scope

These remain unchanged from ABI11:

- observation version 5: 2,456 bytes;
- action transport: `[command, arg0, arg1, arg2]` with head sizes `{12, 65, 65, 65}`;
- exact prefix mask: 9,242 bits packed into 1,156 bytes;
- rewards, terminals, simulation, maps, opponent AI, and four-frame decision interval; and
- normal PufferLib native CUDA training with `--train.gpus 1`.

Only the policy projection, native sampler/PPO scorer, checkpoint dimensions, and matching Zig CPU
inference changed. ABI12 was an unbounded development prototype. ABI13 is the retained bounded
form.

## Scorer

ABI11 supplies one state-dependent base score per command and token. ABI13 adds rank-4 residuals to
the branches where a previously selected actor should affect a target:

```text
score(actor, target) = base(target)
                     + 2 * tanh((0.5 / 2) * dot(query(actor), key(target)))
```

The residual is bounded to `[-2, 2]` and has derivative `0.5` at zero. Query groups are move,
attack, harvest, and return-cargo. Target-key branches are move-x, move-y, attack-target,
harvest-x, harvest-y, and return-target.

| Projection region | Logits |
| --- | ---: |
| ABI11 base command/argument scores | 2,352 |
| 4 query groups x 64 actors x rank 4 | 1,024 |
| 6 key branches x 64 targets x rank 4 | 1,536 |
| **ABI13 policy total** | **4,912** |
| Value | 1 |

For hidden 64x1, the full model grows from 320,064 to 483,904 parameters. Exact FP32 checkpoint
size grows from 1,280,256 to 1,935,616 bytes.

Query output rows initialize to exactly zero while key rows retain normal random initialization.
The initial policy is therefore exactly the ABI11 base scorer, but the first backward pass has a
nonzero gradient into query rows. Initializing both sides to zero would permanently block the
bilinear gradient; randomly initializing both sides caused the first ABI12 screen to fail.

This is a compact state-conditioned slot interaction, not yet a gathered per-entity feature
pointer. A future hybrid may gather the 16-byte actor and target records directly.

## TDD And Correctness

The ABI/layout, actor-target selection, bounded-score, and CUDA-gradient tests were written to fail
before their implementations were added. Final gates:

- Zig: 161/161 tests pass in Debug, ReleaseSafe, and ReleaseFast;
- host action specification: `cnc_micro ABI13 bounded actor-target action spec ok`;
- explicit CUDA reference: score, log-sum-exp, log-probability, entropy, base gradients, query
  gradients, and key gradients match CPU and finite differences;
- bounded saturation test: pass;
- C API smoke: ABI 13, observation 2,456, mask 1,156, zero failures;
- scripted economy: Refinery 1, Harvester 1, income 675, first delivery 1, invalid 0, failures 0;
- Zig CPU checkpoint loading and sampled inference: pass; and
- all retained CUDA runs: invalid actions 0, start failures 0, engine failures 0.

Canonical state and world hashes remain unchanged:

```text
C API digest: cdde069f216661b92e5e030650698b1a7a54641c5e9d1dc068a9b6aa9a2ece4f
world digest: 38cca1613d27fcaa4500c25261cff6ea19d838ccd80d9c91fec4d045d718ce28
```

Two exact 1M repeats have the same initial and final checkpoint hashes:

```text
initial: 5f0ebb06f71ef9096014665e07839ba4f303172b18938cc97971faa401626803
final:   c281af96694ce3436a87f59939955efe072bda35008c7098ad44e42ac10c9450
```

The retained final build artifacts are:

```text
Zig static library: f2ffb25d67ec35655ff6736ad3716ca30e29ee7c02499e18c939610c8f070b20
Puffer extension:   e440c2530b71b95a467ec6df988fb3315b602e42a2e939f7738785dc89f440e8
```

## Matched Learning

The matched rows use the complete historical `qj7bux1j` optimizer, environment, reward, vector,
network, and seed settings. A 2M run starts from scratch with its annealing schedule stretched over
2M steps; it is not a continuation of the 1M checkpoint.

| ABI | Decoder | Steps | Balanced perf | Invalid actions | Valid |
| --- | --- | ---: | ---: | ---: | --- |
| 9 | seven independent heads | 2,097,152 | **0.421753** | 44.943% rejected | historical semantic baseline |
| 10 | dense exact-prefix | 1,048,576 | 0.101742 | 0 | yes |
| 10 | dense exact-prefix | 2,097,152 | 0.000000 | 0 | yes |
| 11 | compact exact-prefix | 1,048,576 | 0.174665 | 0 | yes |
| 11 | compact exact-prefix | 2,097,152 | 0.161406 | 0 | yes |
| 12 | unbounded actor-target, zero-query | 1,048,576 | 0.291040 | 0 | yes |
| 12 | unbounded actor-target, zero-query | 2,097,152 | 0.012376 | 0 | yes |
| 13 | bound 0.5, zero-query | 1,048,576 | 0.048640 | 0 | yes |
| 13 | bound 2, zero-query | 1,048,576 | **0.383830** | 0 | yes |
| 13 | bound 2, zero-query | 2,097,152 | **0.092308** | 0 | yes |

The bound-2 1M result repeats exactly in W&B runs [`6xw8cid8`](https://wandb.ai/kinvert-k/cnc9/runs/6xw8cid8)
and [`fwnd05jt`](https://wandb.ai/kinvert-k/cnc9/runs/fwnd05jt), including the final checkpoint hash.
The matched 2M run is [`s3ubbtw6`](https://wandb.ai/kinvert-k/cnc9/runs/s3ubbtw6).

## Thirty-Run Screen

Command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
.venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc9 --wandb-group '' \
  --tag abi13-bound2-1m-screen-30 \
  --sweep.max-runs 30 --sweep.gpus 1 --sweep.workers-per-gpu 3 \
  --train.gpus 1 --train.total-timesteps 1048576 \
  --vec.total-agents 64 --vec.num-threads 4 \
  --train.minibatch-size 2048
```

All 30 trials completed with `start_failures=0`, `failures=0`, and `invalid_actions=0`.

| Population | Runs | Mean | Median | P90 | Max | Nonzero | `>=0.1` | `>=0.2` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| All, including two bootstrap repeats | 30 | 0.048213 | 0 | 0.150847 | 0.383830 | 14 | 5 | 3 |
| Sampled configurations only | 28 | 0.024241 | 0 | 0.105217 | 0.203216 | 12 | 3 | 1 |

The two bootstrap runs, `prcy7lom` and `4vdhj0ih`, reproduce `0.383830` exactly. Best sampled run
`mndesnj6` reaches `0.203216`, but its final bucket is a spike after weaker intermediate buckets.
`vqxvxsxk` rises more steadily to `0.150847`. Neither justifies a promotion or another broad sweep.

## Throughput

Final valid PufferLib command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 --vec.num-buffers 1 --vec.num-threads 4 \
  --train.total-timesteps 262144 --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

Result: 30,052 final displayed SPS, `start_failures=0`, `failures=0`, `invalid_actions=0`, valid.
Log: `PufferLib/logs/cnc_micro/1784488591758.json`. This is not a speedup claim. The larger decoder
adds policy work, while learned behavior changes environment work.

An adjacent native B/A/B check used 64 worlds, 16,384 iterations, CPU 0, and ReleaseFast. ABI11
reported 156,030 and 154,258 SPS; ABI13 reported 156,473 SPS. Every run had zero failures and the
same world digest. The simulator benchmark does not execute policy scoring, so this only confirms
no simulator regression.

## Old-Action Follow-Up

ABI9 already handled rejected tuples exactly as four-frame no-ops: `input.apply` returned false,
the invalid counter incremented, and `advanceWithEasyAI` still ran. The proposed behavior therefore
restores an existing, measured path and adds only an optional reward cost.

The historical mean is 1,986.594 invalid actions per 4,420.213-decision episode. An uncapped `-0.05`
cost would contribute about `-99.33` per episode and destroy the `-1/+1` terminal scale. Even
`-0.001` contributes about `-1.99`.

Use this first grid, with the complete cumulative invalid cost logged:

```text
0, -0.000025, -0.00005, -0.0001, -0.00025
```

At the historical invalid count those correspond to approximately `0`, `-0.050`, `-0.099`,
`-0.199`, and `-0.497` per episode. Add a diagnostic cumulative cap of `-0.5`; do not add an
invalid-streak death terminal. Reproduce penalty `0` first, then compare exact repeats at 1M and 2M
with every non-penalty hyperparameter fixed. Selection must use fixed-policy evaluation and median
or repeat hit rate, not the final rolling training bucket alone.
