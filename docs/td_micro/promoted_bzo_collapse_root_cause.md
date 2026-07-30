# Promoted BZO Policy Collapse Root Cause

Date: 2026-07-15

Status: investigated. This is a policy-learning failure, not an engine-start, terminal-logging, or
environment-determinism failure.

## Verdict

The 1M and 10M results are compatible because the 1M result was a stochastic, high-entropy policy
with a measurable chance of sampling a winning action sequence. It was never a greedy winning
policy. The 10M command started a new run from random initialization, and changing
`total_timesteps` also changed every learning-rate update because cosine annealing uses the total
budget as its denominator. Continued PPO updates at nearly the full `0.015` learning rate erased
production behavior and converged to a deploy-only local optimum.

Three issues combine:

1. The seven action heads are sampled independently, but action legality is conditional across
   heads. Puffer can sample `start_build + product_none` even though both selected head values are
   individually unmasked.
2. The immediate Construction Yard milestone is easy to learn, while win/loss credit arrives
   thousands of decisions later. The final policy receives exactly the deployment reward followed
   by the terminal loss.
3. The reward sweep selected a configuration at a fixed 1M-step cosine schedule. Extending the
   budget to 10M kept the optimizer near full learning rate at the old stopping point, so it was not
   an apples-to-apples continuation.

The environment remains deterministic for fixed semantic actions. Existing winning traces still
replay to identical hashes, and both training runs reported zero start and engine failures.

## Controlled Checkpoint Evaluation

Five checkpoints were evaluated through PufferLib's native CUDA sampler with the same 64-agent,
four-buffer, horizon-32 environment shape. Each row is 256 completed stochastic episodes from
environment seed 1. This uses sampled actions, not Zig's greedy checkpoint adapter.

| Checkpoint | Win/loss/draw | Win rate | Mean return | Mean decisions | Invalid actions | Units built | Unit kills | Buildings destroyed |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Near-random 2K, long run | 1/248/7 | 0.39% | -0.1892 | 5,514.5 | 2,836.9 | 28.74 | 13.38 | 0.26 |
| Promoted 1M, short schedule | **18/230/8** | **7.03%** | 0.3167 | 5,236.9 | 2,922.3 | 38.10 | 17.99 | 6.82 |
| 1.026M, long schedule | 0/248/8 | 0% | -0.7232 | 5,246.2 | 4,694.7 | 2.83 | 2.30 | 0.05 |
| 2.050M, long schedule | 0/256/0 | 0% | -0.9410 | 4,257.1 | 4,749.9 | 0 | 0 | 0 |
| 9.998M, long schedule | 0/256/0 | 0% | -0.9410 | 2,467.0 | 1,100.3 | 0 | 0 | 0 |

Checkpoint paths:

```text
PufferLib/checkpoints/cnc_micro/hjk4ii86/0000000000002048.bin
PufferLib/checkpoints/cnc_micro/1784140598595/0000000001048576.bin
PufferLib/checkpoints/cnc_micro/hjk4ii86/0000000001026048.bin
PufferLib/checkpoints/cnc_micro/hjk4ii86/0000000002050048.bin
PufferLib/checkpoints/cnc_micro/hjk4ii86/0000000009998336.bin
```

The 1M checkpoint's 95% Wilson win-rate interval is 4.49% to 10.84%. The near-random checkpoint's
interval is 0.07% to 2.18%. A one-sided Fisher exact comparison gives `p=2.89e-5`. Training did put
substantially more probability on winning traces, but the action distribution remained exploratory;
all retained 1M checkpoints still lost greedily.

## Learning-Rate Schedule Change

`anneal_lr=1` and `min_lr_ratio=0` come from `PufferLib/config/default.ini`. The native trainer uses:

```text
lr(t) = 0.5 * 0.015 * (1 + cos(pi * t / total_timesteps))
```

Therefore changing only `--train.total-timesteps` changes the effective optimizer configuration:

| Aggregate steps | 1,048,576-step budget | 10,000,000-step budget |
| ---: | ---: | ---: |
| 520,192 | about 0.00759 | about 0.01490 |
| 755,712 | about 0.0027 | about 0.01479 |
| 1,048,576 | **0** | **0.01460** |

The short run had effectively frozen its useful high-entropy distribution by 1M. At approximately
the same step in the long run, learning rate was still 97% of its initial value. The controlled
checkpoint comparison above isolates the effect: 18/256 wins for the short schedule versus 0/256
wins for the long schedule at 1.026M.

### Five-Million-Step Confirmation

The 2026-07-17 `cnc5` bootstrap trials provide the same controlled comparison against the schema-7
early-force task. W&B/local run `qs7g6tml` and runs `v0jlk8xq` plus `tdxbdc15` have identical env,
vector, policy, encoder, optimizer, reward, and seed configuration. Their only configuration
difference is `train.total_timesteps`.

| Run | Requested schedule | Final balanced win rate | Highest downsampled balanced rate | Failures |
| --- | ---: | ---: | ---: | ---: |
| `qs7g6tml` | 1,048,576 | **0.295712** | 0.382937 | 0 |
| `v0jlk8xq` | 5,000,000 | 0.005747 | 0.092534 | 0 |
| `tdxbdc15` | 5,000,000 | 0.005747 | 0.105165 | 0 |

With the promoted base learning rate `0.008668618381591891`, cosine annealing produces:

| Aggregate steps | 1,048,576 schedule | 5,000,000 schedule |
| ---: | ---: | ---: |
| 524,288 | 0.004334 | 0.008436 |
| 786,432 | 0.001269 | 0.008150 |
| 1,048,576 | **0** | **0.007761** |

Thus the 5M policy is still updating at 89.54% of the initial learning rate where the successful
1M schedule has frozen. The duplicate 5M final metrics and zero failures confirm schedule-dependent
policy degradation, not simulator nondeterminism.

The later reward-scale audit adds a second pressure: valid `cnc5` episodes empirically include
positive-return losses because cumulative immediate shaping can exceed the delayed `-1` terminal.
See `docs/td_micro/reward_return_scale_audit.md`.

The full W&B event history for `hjk4ii86` contains 267 records. Its only nonzero win records were:

| Steps | Wins / outcomes | Entropy |
| ---: | ---: | ---: |
| 163,840 | 1/1 | 11.14 |
| 196,608 | 2/5 | 9.39 |
| 227,328 | 1/5 | 10.16 |

Unit production, Power Plant milestones, and Barracks milestones become permanently zero in logged
windows from 1,810,432 steps onward. Final entropy is 0.561, compared with 7.67 for the short 1M
checkpoint.

## Invalid Joint Actions

The current action ABI is:

```text
command=9, actor=65, product=5, target_kind=4, x=64, y=64, target_slot=64
```

[`policy.zig`](../../td-micro/src/policy.zig) always unmasks `noop`, `actor_none`, `product_none`,
and `target_kind_none`, then independently unmasks values that are useful for other commands.
[`pufferlib.cu`](../../PufferLib/src/pufferlib.cu) samples one categorical distribution per head and
sums their log probabilities. It has no representation for a conditional tuple mask.

After MCV deployment, for example, `start_build` and `power_plant` are unmasked, but so are `noop`
and `product_none`. The Cartesian sampler can therefore emit all four command/product pairs. The
environment accepts `start_build + power_plant` but rejects `start_build + product_none`.

Checkpoint traces show the failure directly:

- 1.026M long-schedule checkpoint: deploys, starts a Power Plant, then greedily repeats an illegal
  placement coordinate.
- 2.050M long-schedule checkpoint: deploys, then greedily repeats `start_build + product_none`.
- 9.998M checkpoint: deploys, then alternates no-op with `start_build + product_none` and never
  produces anything.

The independent heads also include irrelevant coordinates and target slots in every PPO joint
log-probability and entropy calculation. Those choices add policy-gradient variance even when the
selected command ignores them. The nominal unmasked Cartesian ABI has 3,067,084,800 tuples; dynamic
head masks reduce that number, but cannot remove cross-head-invalid combinations.

## Reward And Credit Assignment

The collapsed final return is diagnostic:

```text
-1 terminal loss + 0.059037386 Construction Yard milestone = -0.940962614
observed final mean return                              = -0.940962970
```

So the final policy learned one reliable immediate reward and nothing after it. There is no turn
penalty and no invalid-action penalty. `consecutive_invalid_action_limit` is disabled, so rejected
tuples are punished only indirectly when the Easy AI eventually wins.

With `gamma=0.995`, `GAE lambda=0.9`, and horizon 32:

```text
gamma * lambda                         = 0.8955
GAE trace half-life                    = 6.28 decisions
direct GAE weight after 32 decisions   = 0.02925
gamma discount after 2,467 decisions  = 4.26e-6
```

The critic can bootstrap information farther than one rollout, so terminal credit is not
mathematically impossible. It is nevertheless a difficult propagation problem compared with the
immediate `+0.059` deployment reward, especially while almost half of sampled decisions are invalid
joint tuples.

## Corrective Gate

Do not spend another long run on the current action ABI. The next ordered work is:

1. Implement the fixed-depth conditional token protocol already specified in
   `docs/td_micro/learning_blockers_and_next_step.md`. Acceptance requires zero invalid sampled
   actions and identical semantic-action replay hashes.
2. Add automatic sampled and greedy checkpoint evaluation. Retain the best evaluated checkpoint;
   do not use final training-window `perf` as the policy-quality result.
3. Make learning-rate decay independent of an arbitrarily extended run budget, or resume the 1M
   checkpoint with an explicitly small continuation rate. Never describe a changed cosine budget
   as only "more of the same training."
4. After the action gate, run short multi-seed tests for learning rate, entropy, horizon, gamma, and
   GAE lambda. Long-horizon credit should be tuned only after every sampled command is executable.
5. Keep the near-random checkpoint evaluation as a baseline. A candidate must beat both baseline
   stochastic wins and its own greedy/fixed-seed evaluation.

This investigation changes no simulator or training behavior. It explains why the observed runs
diverged and defines the correctness gate before further training.
