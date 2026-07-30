# CNC13 ABI9 2M Sweep Analysis

Date: 2026-07-20

Status: campaign stopped intentionally at 980/1,000 completed runs. This is candidate-generation
evidence, not a promotion result.

## Decision

Do not choose the arithmetic endpoint leader and do not promote any CNC13 policy directly.

Retain this confirmation slate:

1. `hmc7f77r`: strongest high-performing candidate with a stable late curve.
2. `x8biqwx1`: smooth late curve and useful close/medium balance.
3. `vqsw4ned`: nearly identical close and medium win rates with a stable plateau.
4. `o5e9lorj`: highest robust endpoint and a rising curve, but its large final gain requires
   confirmation rather than promotion.
5. `4pkdtoqj`: exact repeated historical/default control, despite strong medium-spawn skew.

Recreate these configurations under multiple training seeds only after the fresh common-suite
evaluator is integrated. Rank confirmations by terminal wins across both profiles, not by one final
training/evaluation bucket.

## Campaign Shape

The original Protein process ended without a traceback after 817 completed local results. A second
Protein instance was started for the intended final 183. It was stopped after 163 completed results
because Protein does not know the campaign's `max_runs` and does not reserve final trials for an
exploit phase.

The final population is therefore:

```text
817 proposals from Protein state A
163 proposals from Protein state B
980 completed 2,097,152-transition runs
979 unique configurations
2,055,208,960 total training transitions
```

This population is useful for candidate screening and distribution analysis. It is not one
uninterrupted 980-step adaptive optimizer trajectory.

Tail command before the intentional stop:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
.venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc13 --wandb-group '' \
  --tag abi9-2m-sweep-1000 \
  --sweep.max-runs 183 --sweep.gpus 1 --sweep.workers-per-gpu 3 \
  --train.gpus 1 --train.total-timesteps 2097152 \
  --vec.total-agents 64 --vec.num-buffers 1 --vec.num-threads 4 \
  --train.horizon 32 --train.minibatch-size 2048
```

There was no `sweep_only`, `--cpu`, or `--slowly` path.

## Population Results

| Statistic | Result |
| --- | ---: |
| Completed/full-budget runs | 980/980 |
| Nonzero arithmetic balanced result | 860 |
| Arithmetic balanced `>= 0.2` | 154 |
| Arithmetic balanced `>= 0.3` | 33 |
| Both profile win rates `>= 0.2` | 82 |
| Both profile win rates `>= 0.3` | 10 |
| Median arithmetic balanced result | 0.0759 |
| P90 arithmetic balanced result | 0.2348 |
| Maximum arithmetic balanced result | 0.4455 |
| Median completed episodes in final bucket | 218 |
| Final-bucket episode range | 117-409 |
| Median aggregate SPS | 33,157 |
| Median displayed final SPS | 32,389 |
| Start failures | 0 |

One run, `kq5pen41`, logged a transient nonzero engine-failure bucket and is invalid for promotion.
Its final balanced result was zero. All other runs had zero observed engine failures. SPS is valid as
a campaign workload description, not a code-speed claim: three policies trained concurrently and
learned behavior changes simulator workload.

The five logged arithmetic-balanced buckets show that endpoint instability is common:

```text
129 runs dropped at least 0.05 from their logged peak to the final bucket
 31 runs dropped at least 0.10 from their logged peak to the final bucket
```

## Why Arithmetic Performance Is Wrong

Current `balanced_perf` is the arithmetic mean of close and medium win rates. It rewards severe
specialization:

| Run | Close | Medium | Arithmetic | Robust |
| --- | ---: | ---: | ---: | ---: |
| `iqttpc1r` | 0.0769 | 0.8142 | **0.4455** | 0.1473 |
| `4pkdtoqj` | 0.2021 | 0.6414 | 0.4218 | 0.3100 |
| `o5e9lorj` | 0.3525 | 0.4710 | 0.4117 | **0.4033** |
| `hmc7f77r` | 0.4777 | 0.3060 | 0.3918 | 0.3735 |

The proposed `robust_perf` is the epsilon-shifted harmonic mean documented in
`stable_training_curriculum_plan.md`. It strongly penalizes a failed profile while remaining smooth
enough for Protein.

## Stability Screen

The five buckets below are robust close/medium aggregates reconstructed from each run's logged
profile rates. They are not clean common-suite checkpoint evaluations, so they are used only to
reject obvious spikes and collapses.

| Run | Robust buckets | Final | Last-3 mean | Last-3 minimum | Interpretation |
| --- | --- | ---: | ---: | ---: | --- |
| `hmc7f77r` | 0.000, 0.085, 0.270, 0.361, 0.373 | 0.373 | 0.335 | 0.270 | Stable high performer |
| `x8biqwx1` | 0.000, 0.125, 0.302, 0.317, 0.319 | 0.319 | 0.313 | 0.302 | Smooth plateau |
| `vqsw4ned` | 0.000, 0.120, 0.320, 0.294, 0.307 | 0.307 | 0.307 | 0.294 | Stable and profile-balanced |
| `o5e9lorj` | 0.033, 0.094, 0.214, 0.289, 0.403 | **0.403** | 0.302 | 0.214 | Rising, but final gain is large |
| `pm00cpye` | 0.000, 0.047, 0.270, 0.274, 0.346 | 0.346 | 0.297 | 0.270 | Secondary reserve candidate |
| `4pkdtoqj` | 0.000, 0.202, 0.298, 0.360, 0.310 | 0.310 | 0.323 | 0.298 | Reproducible skewed control |

`o5e9lorj` is not dismissed as a one-bucket accident because all five buckets rise. It is also not
called the winner because the final robust increase over its prior maximum is `+0.114`. In contrast,
`hmc7f77r` gains only `+0.012` over its prior maximum while ending higher on both-profile robustness
than the stable alternatives.

Approximate beta-posterior 95% intervals from the final aggregate episode counts overlap heavily:

| Run | Robust median | Approximate 95% interval |
| --- | ---: | ---: |
| `o5e9lorj` | 0.403 | 0.344-0.462 |
| `hmc7f77r` | 0.374 | 0.312-0.435 |
| `pm00cpye` | 0.346 | 0.287-0.408 |
| `x8biqwx1` | 0.319 | 0.260-0.380 |
| `vqsw4ned` | 0.307 | 0.249-0.371 |

These intervals cover only episode-sampling uncertainty. They do not cover training-seed variance,
which prior CNC11 results show is much larger.

## Reproducibility Evidence

The only exact duplicate configuration in this campaign is represented by `4pkdtoqj` and
`xx8nonox`. Both end at exactly:

```text
balanced = 0.421753466129303
close    = 0.202127665281296
medium   = 0.641379296779633
episodes = 239
```

This is useful deterministic evidence for the retained ABI9/default control. Sweep trials do not
save final checkpoints, so this does not provide a checkpoint hash. The duplicate is not a robust
winner because it remains strongly specialized toward medium starts.

## Evaluation Limitation

CNC13 final buckets are not independent fresh-checkpoint evaluations. Puffer's training loop clears
completed logs and then continues the same in-progress worlds under the frozen final policy. Up to
64 first completions can straddle the train/eval boundary. With median final sample count 218, that
is an upper bound of 29% of the bucket. Episode counts also vary by policy because evaluation has an
epoch cap.

The existing CNC11 tournament evaluator starts a fresh runtime and is the correct base to harden,
but it is not connected to sweep scoring and still needs exact tuple scheduling and matched current
MinGRU horizon-reset semantics. This work must remain CNC-specific; generic PufferLib MinGRU and
other environments are not changed.

Therefore, neither arithmetic rank, robust rank, nor late-curve rank is a promotion result. Together
they define a small, defensible confirmation slate.

## Hyperparameter Interpretation

A held-out ExtraTrees model has only `R^2 = 0.170` for final arithmetic performance; its classifier
for results `>= 0.2` reaches AUC `0.708`. This is useful for narrowing ranges but not for causal
claims. CNC13 jointly varies optimizer/model settings and eight reward coefficients, and Protein's
samples are adaptive.

The successful population generally concentrates on hidden size 64, relatively high entropy,
replay near 3.4-4.0, low prioritized-replay alpha, and high Tiberium-income shaping. These are priors
for confirmation, not proven effects. Reward, optimizer, curriculum, encoder, and action claims must
be isolated in later paired ablations.

## Next Gate

1. Harden the fresh evaluator and score an exact common suite with `robust_perf` while staying at 31
   environment fields before Puffer appends `N`.
2. Recreate the four candidate configurations and the repeated control from clean manifests.
3. Train at least three seeds per configuration under the same fixed 2M protocol.
4. Evaluate exactly 512 games per required profile and seed on an untouched promotion suite.
5. Rank by median training-seed `robust_perf`, then worst-seed minimum-profile win rate.
6. Promote no configuration with a zero profile or a zero training seed.

This confirmation gate directly tests whether the apparent learning is stable rather than an
accident of one training seed, one profile, or one final bucket.

## Evidence

- Local logs: `PufferLib/logs/cnc_micro/*.json`, project `cnc13`, tag
  `abi9-2m-sweep-1000`
- Console tail: `PufferLib/logs/cnc_micro/cnc13_abi9_2m_sweep_tail_183.console.log`
- Planning and metric definition: `docs/td_micro/stable_training_curriculum_plan.md`
