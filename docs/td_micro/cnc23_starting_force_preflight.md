# CNC23 Starting-Force Curriculum Preflight

Date: 2026-07-23

Status: implementation and validation complete; no ramp-trained policy promoted.

## Decision

CNC23 training uses a deterministic H5 starting-force curriculum:

- 25% reduced Unit Count 6 starts at curriculum progress zero;
- a linear ramp to 75% on an independent per-lane decision clock;
- 25% MCV-only starts remain after the ramp;
- H0-H4 authored starts do not change;
- standalone H5 evaluation remains an exact 50/50 MCV/force suite; and
- `balanced_perf` remains the equal mean of close/MCV, close/force, medium/MCV, and medium/force
  win rates.

The ramp is based on deterministic decision progress, not live win rate. Outcome-triggered
advancement would make reset state depend on noisy aggregate training history and would weaken
reproducibility. The two sweepable clocks are:

```text
curriculum_stage_decisions:
  256, 512, 1024, 2048, 4096, 8192, 16384
starting_force_ramp_decisions:
  2048, 4096, 8192, 12288
```

The first controls only H0-H5 profile progression; the second controls only the 25%-75% defended
start threshold. At the default 4,096-decision H phase, the force choices finish midway through H0,
at the H0 boundary, at the H1 boundary, or at the H2 boundary.

## Fixed-50 Controls

Four fresh 5,242,880-step native-CUDA controls tested representative CNC22 configurations against
the new starting-force implementation before the ramp changed training. All used 64 agents, one
buffer, four environment threads, horizon 32, minibatch 2048, one 64-wide MinGRU layer, train seed
42, environment seed 1, ABI9, and a fixed 10,485,760-step optimizer schedule. Every run had
`failures=0` and `start_failures=0`.

| W&B run | Source configuration | Stage | `balanced_perf` | `perf` | Tiberium income |
|---|---|---:|---:|---:|---:|
| `balmy-lion-1` / `vttfb9bn` | current default control | 4096 | 0.18097 | 0.20217 | 491.68 |
| `helpful-puddle-2` / `c7mykt6c` | CNC22 `proud-bird-262` | 256 | 0.28499 | 0.28944 | 281.26 |
| `elated-planet-3` / `pttvt8hc` | CNC22 `dandy-wildflower-333` | 1024 | **0.39552** | 0.40678 | 217.58 |
| `warm-durian-4` / `yfx9t4nj` | CNC22 `likely-valley-463` | 256 | 0.03147 | 0.03160 | 282.11 |

The exact 256-game fixed suite for `pttvt8hc` confirmed:

```text
balanced_perf        0.39608
credit_balanced_perf 0.38333
robust_perf          0.36396
credit_robust_perf   0.30255
close win rate       0.50781
medium win rate      0.28906
MCV-only win rate    0.34375
Unit Count 6 rate    0.45312
```

The result is valid and its episode ledger SHA-256 is
`217f1770818b88e14c6ecba6e33466bd52752ce920ea34e52e07f6e060c6126a`.

## Adjacent Ramp Checks

Before the clocks were separated, the strongest control configuration was rerun from scratch with
the original five-phase ramp. The first check retained `stage_decisions=1024`; the second changed
that value to 4096. Both completed on native CUDA with zero failures and zero start failures.

| W&B run | Stage | Final training force share | W&B `balanced_perf` | Exact 50/50 `balanced_perf` |
|---|---:|---:|---:|---:|
| `vibrant-wind-5` / `sczi283r` | 1024 | 0.74265 | 0.29511 | 0.26495 |
| `silver-snowflake-6` / `x4dk7q4c` | 4096 | 0.75240 | 0.12105 | 0.16054 |

Exact fixed-suite detail:

| Run | Credit-balanced | Robust | Credit-robust | Close | Medium | MCV-only | Unit Count 6 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `sczi283r` | 0.23099 | 0.22753 | 0.03362 | 0.35156 | 0.17188 | 0.28125 | 0.24219 |
| `x4dk7q4c` | 0.14766 | 0.10417 | 0.03074 | 0.25781 | 0.06250 | 0.15625 | 0.16406 |

The old best hyperparameters therefore do not transfer robustly to the ramped domain. More
importantly, these checks were confounded: changing `curriculum_stage_decisions` changed both the
H-profile schedule and force-ramp duration. They motivate the independent clock now used for CNC23;
they do not rank the new force-ramp choices.

## Verification

- 198 Zig tests pass in Debug, ReleaseSafe, and ReleaseFast.
- Generated-rules validation passes.
- The native Puffer CUDA extension rebuild passes.
- The standalone C binding smoke reports `episode_return=0.250 draw_rate=1`.
- All 10 fixed-evaluator unit tests pass.
- The 131,072-step native-CUDA smoke used 64 agents, one buffer, four threads, horizon 32,
  minibatch 2048, and one H64 MinGRU layer. It completed at 58,139 final displayed SPS with
  `failures=0` and `start_failures=0`; this is a smoke result, not a throughput comparison.
- Fixed evaluation remained exactly 128 MCV-only and 128 Unit Count 6 episodes.
- A fresh Unit Count 6 Vanilla trace through 256 decisions matched the checked-in fixture at
  `1500d9b05f2e392397fd625e194deed4640fec6847c156778db18ceb4ccb5d9f`.
- Two fresh MCV-only 256-decision traces matched each other at
  `c93ecff6c94f518c93c1f7d70c114e0fa0655f811d4b7665da5ce65236ff6af8`; the reset-only trace
  retained `5a40c129131eb2d4e2a681a6a4ba9d9e447562eece062aaf96fc68cbab578fd7`.

## CNC23 Gate

The environment is ready for a CNC23 sweep, but no existing CNC22 configuration should be treated
as promoted on the new domain. The sweep must:

1. maximize final H5-only `balanced_perf`;
2. include the full curriculum-stage range through 16384 and the independent force-ramp range
   2048 through 12288;
3. keep ABI9, vector structure, training budget, and optimizer schedule fixed;
4. sweep optimizer and reward parameters together with curriculum pace; and
5. promote candidates only through the exact fixed H5 suite, with credit-balanced and robust scores
   inspected alongside `balanced_perf`.
