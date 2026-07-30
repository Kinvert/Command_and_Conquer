# CNC22 Random-Credit 5 Mi Sweep

Date: 2026-07-22

Status: stopped intentionally on 2026-07-23 after 621 complete 5,242,880-step runs.

Final note: CNC22 ran from the MCV-only binary loaded at process start. The later deterministic
starting-force working tree did not alter that process. CNC22 remains the random-credit, MCV-only
baseline and retains the two-spawn `balanced_perf` meaning documented below. Four selected
configurations were recreated on the new fixed-50 domain in
`cnc23_starting_force_preflight.md`.

## Purpose

CNC22 is the first broad learning campaign on deterministic randomized full-match credits. It
screens configurations for 5,242,880 transitions while preserving an immutable 10,485,760-step
cosine schedule. A reproduced finalist can therefore resume from full training state to 10 Mi
without restarting or stretching its learning-rate, entropy, or priority schedule.

This is a new domain, not a direct numerical continuation of CNC21. CNC21 used fixed `$10,000`
starts and annealed over its three-Mi endpoint.

## Fixed Contract

- W&B project: `cnc22`
- command: `tools/run_cnc22_random_credit_5mi_sweep.sh`
- maximum trials: 1,000
- native CUDA workers: three concurrent workers on one GPU
- stop: 5,242,880 transitions (`5 Mi`)
- immutable schedule: 10,485,760 transitions (`10 Mi`)
- vector: 64 agents, one buffer, four threads
- PPO horizon/minibatch: 32/2,048
- policy: native MinGRU, one layer, H64 or H128
- action/observation: ABI9 and observation v5
- curriculum: H0-H5 reverse schedule with at least 20% H5 anchors before pure H5
- live objective: H5-only close/medium `balanced_perf`
- reward-invalid-action: fixed at zero
- live environment fields: exactly 31 before Puffer adds `env/n`

The broad sweep uses one fixed training seed so hyperparameter comparisons are paired. Multi-seed
reproduction happens after screening, where it buys more evidence per GPU-hour.

## Expanded Ranges

CNC21's valid top 25 placed on old boundaries this often:

| Dimension | Old boundary | Top-25 boundary hits | CNC22 range |
| --- | ---: | ---: | --- |
| Hidden size | H64 maximum | 25 | H64, H128 |
| Curriculum stage | 512 minimum | 22 | 256, 512, 1,024, 2,048, 4,096, 8,192 |
| Replay ratio | 4 maximum | 21 | 0.25-8 |
| Max gradient norm | 2 maximum | 15 | 0.25-4 |
| Learning rate | 0.0012 maximum | 11 | 0.0006-0.0018 |
| V-trace rho | 5 maximum | 11 | 0.1-10 |
| V-trace c | 0.1 minimum | 23 | 0.02-5 |
| Value clip | 5 maximum | 8 | 0.01-8 |
| Beta2 | 0.9 minimum | 14 | 0.8-0.99999 |

Reward ranges, action ABI, one-layer recurrence, horizon, minibatch, vector topology, and invalid
penalty remain unchanged. This keeps the experiment interpretable and avoids reopening rejected
structural choices.

## Promotion Protocol

1. Reject any trial with nonzero `start_failures`, engine failures, NaN loss, or an incomplete
   budget unless Protein explicitly early-stopped it as unpromising.
2. Rank complete trials by H5-only `balanced_perf`, but inspect full curves and H5 game counts rather
   than trusting one endpoint window.
3. Reproduce roughly 8-12 distinct leading configurations at the 5 Mi stop with every hyperparameter
   explicit, `--save-training-state`, and the same `--train.schedule-timesteps 10485760`.
4. Use three training seeds for those reproductions. Rank families by median fixed-suite
   `credit_robust_perf`, then worst-seed score and minimum cell win rate.
5. Resume only the strongest stable families from their exact 5 Mi `.state` files to 10 Mi using
   `--load-training-state-path`; never substitute a weights-only warm start.
6. Evaluate 10 Mi endpoints on the same fixed credit-aware suite. Keep exact JSONL episode hashes,
   checkpoint hashes, commands, failures, and valid SPS.

Broad sweep workers intentionally do not save training states for every trial. Reproduction is
deterministic and avoids storing thousands of optimizer/environment snapshots. No CNC22 policy is
promoted from the noisy live objective alone.

## Validation Before Launch

- fixed evaluator tests include H128 MinGRU/MLP checkpoint layouts;
- native MinGRU H128 completed one rollout/update with 399,360 parameters, a 1,597,440-byte
  checkpoint, and zero start or engine failures;
- loaded sweep config contains no `sweep_only` and keeps total/schedule steps fixed;
- the shell launcher passes `bash -n`;
- the 31-field binding assertion remains part of the C gate.

A one-trial local Protein orchestration smoke used 64 agents, one buffer, four threads, horizon 32,
minibatch 2,048, native GPU training, 131,072 transitions, and a 262,144-step test schedule. It
completed validly at 62,265 final SPS with zero start/engine failures and exactly 31 environment
fields plus `env/n`. Evidence: `PufferLib/logs/cnc_micro/1784780071731.json`. This short smoke is an
integration result, not a learning or campaign-throughput claim.
