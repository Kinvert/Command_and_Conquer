# CNC21 H0-H5 3 Mi Sweep

Date: 2026-07-21

Status: corrected sweep complete; 5M follow-up justified, but not yet run on randomized credits

## Campaign Contract

- W&B project: `cnc21`
- Trained commit: `ad3a2f1` (`Measure curriculum performance on H5 only`)
- 3 Mi configuration commit: `8709cf9`
- Curriculum implementation commit: `5b5539f`
- Maximum runs: 1,000
- Concurrent workers: three on one CUDA GPU
- Budget per run: 3,145,728 transitions
- Shape: 64 agents, one buffer, four env threads, horizon 32, minibatch 2,048
- Action/model baseline: ABI9, one-layer MinGRU, hidden size swept over 32/64
- Sweep objective: H5-only `balanced_perf`
- W&B group: none

Continue follow-up sweeps, confirmations, and exact continuations in `cnc21`. Do not increment the
project name unless the environment/task definition materially changes and the user explicitly
approves a new project.

## Curriculum Pace

Protein samples `env/curriculum_stage_decisions` from:

```text
512, 1024, 2048, 4096, 8192
```

Each run gives every lane 49,152 decisions. Pure H5 starts after five stage lengths, leaving these
minimum pure-H5 tails:

| Stage decisions | Pure-H5 decisions per lane |
| ---: | ---: |
| 512 | 46,592 |
| 1,024 | 44,032 |
| 2,048 | 38,912 |
| 4,096 | 28,672 |
| 8,192 | 8,192 |

Thus every sampled pace reaches the hardest full-match profile before the endpoint. H0-H4 wins do
not enter `perf` or `balanced_perf`; the sweep cannot improve its objective by solving only partial
starts. Every phase has at least a 20% H5 start share, and `full_match_episode_share` exposes the
realized completed-episode share.

## Launch

Persistent tmux session:

```text
cnc21_h0_h5_3mi
```

Reproducible launcher:

```bash
tools/run_cnc21_h0_h5_3mi_sweep.sh
```

Corrected-launch console log:

```text
PufferLib/logs/cnc_micro/cnc21_h0_h5_3mi_h5_metrics_sweep_1000.console.log
```

The stopped pre-fix log is retained at
`PufferLib/logs/cnc_micro/cnc21_h0_h5_3mi_sweep_1000.console.log`.

Stopped pre-fix initial W&B runs:

- `f7er8nuq` (`azure-darkness-1`)
- `hrngg0v2` (`azure-jazz-1`)
- `taftxby5` (`exalted-serenity-1`)

Startup verification found all three CUDA workers active and syncing to
`https://wandb.ai/kinvert-k/cnc21`. Protein's printed min/max samples included curriculum rates 512
and 8,192, confirming the curriculum advance rate is part of the search space. No robust-policy
claim is made until completed candidates pass fixed H5 evaluation and multi-seed reproduction.

## Completed Trend Check

The corrected campaign completed all 1,000 requested trials. Of those, 994 had zero engine and
start failures. The two strongest endpoint candidates showed sustained increases across the
downsampled H5-only training curve rather than a single favorable terminal bucket:

| Run | H5 `balanced_perf` training curve | Final evaluation | Evaluation games |
| --- | --- | ---: | ---: |
| `elcuybox` | 0.005, 0.080, 0.344, 0.473 | 0.508 | 472 |
| `pcplaks8` | 0.007, 0.110, 0.324, 0.431 | 0.506 | 425 |

Several additional stage-512 candidates followed the same rising shape and finished between 0.40
and 0.48. This is enough evidence to justify a controlled 5M experiment. It does not prove that 5M
will improve the endpoint: changing the requested endpoint also changes Puffer's cosine schedule.
Furthermore, CNC21 used the prior fixed-10K-credit reset distribution. A 5M run under deterministic
randomized credits is a new-domain validation, not a direct continuation of this result.

The first three trials completed the full budget with zero start and engine failures:

| Run | Stage decisions | SPS | H5 `balanced_perf` |
| --- | ---: | ---: | ---: |
| `f7er8nuq` | 4,096 | 36,848 | 0.084763 |
| `hrngg0v2` | 4,096 | 45,661 | 0.000000 |
| `taftxby5` | 1,024 | 42,572 | 0.003448 |

This is startup validity evidence only. Three trials are far too few to compare curriculum rates or
identify a stable candidate.

The initial launch was stopped after 13 completed trials when generic `perf`, `loss_rate`, and
`draw_rate` were found to include H0-H4 terminals. Its optimization target, `balanced_perf`, was
already H5-only, but those generic fields were misleading. The corrected launch remains in project
`cnc21`; pre-correction generic terminal metrics are not comparable with corrected runs.

## H5 Metric Validation

- The C regression mixes two easy wins with three H5 outcomes and reports H5-only win/loss/draw
  rates of one third plus `full_match_episode_share=0.6`.
- All 181 Zig tests pass, including the exact phase mixtures with at least 20% H5 starts.
- The Puffer extension rebuild and six fixed-evaluator tests pass; the native log remains 31 fields.
- A 262,144-transition CUDA smoke completed at 76,800 final SPS with 64 agents, one buffer, four
  threads, horizon 32, minibatch 2,048, and `start_failures=0`. It displayed the replacement
  `full_match_episode_share` field and H5-only terminal rates.
- The C API digest repeated exactly on two runs:
  `cdde069f216661b92e5e030650698b1a7a54641c5e9d1dc068a9b6aa9a2ece4f`.

The corrected sweep started in the same `cnc21` project with tag
`h0-h5-3mi-h5-metrics-sweep-1000`. Its first three runs completed with zero engine and start
failures:

| Run | Stage decisions | SPS | H5 `perf` | H5 `balanced_perf` |
| --- | ---: | ---: | ---: | ---: |
| `aofipz5b` | 1,024 | 39,764 | 0.000000 | 0.000000 |
| `l4gtjlnh` | 4,096 | 37,781 | 0.089005 | 0.084763 |
| `q2qmhokz` | 2,048 | 41,112 | 0.000000 | 0.000000 |

All three endpoint windows were in the pure-H5 tail and reported
`full_match_episode_share=1.0`. Earlier windows expose the changing H5 share while keeping H0-H4
terminals out of all performance rates.

## Promotion Procedure

1. Rank completed valid candidates by H5-only `balanced_perf`; reject any run with nonzero engine
   or start failures.
2. Evaluate the strongest endpoints with the fixed schedule-0 H5 evaluator.
3. Reproduce the leading configurations across at least three training seeds.
4. Promote by median fixed-suite `robust_perf`, with worst-seed and close/medium results reported.
5. Continue the retained lineage from exact training state rather than restarting its LR schedule.
