# CNC5 Five-Million-Step Sweep: Partial Snapshot

Date: 2026-07-17 13:18 PDT
Status: stopped after 11/100 trials because the sweep was unintentionally reward-only
W&B project: [`cnc5`](https://wandb.ai/kinvert-k/cnc5)

## Configuration

The stopped sweep used the schema-7 early-force environment, 100 maximum runs, CUDA training, and
5,000,000 requested timesteps per trial. PufferLib batch alignment produces 4,999,168 actual agent
steps. The sweep varies only `reward_refinery`, `reward_first_delivery`, and
`reward_tiberium_income`; optimizer and policy hyperparameters remain fixed.

## Validity And Throughput

- Completed trials: 11/100.
- Engine-failure trials: 0.
- Start-failure trials: 0.
- Aggregate SPS range: 49,894 to 70,008.
- Mean aggregate SPS: 61,559.
- Median aggregate SPS: 61,964.

The `cnc5-sweep` tmux session was terminated at the user's request. The restrictive `sweep_only`
setting was then removed from `PufferLib/config/cnc_micro.ini` so future sweeps can use the existing
policy, optimizer, rollout, and reward parameter ranges.

## Early Learning Result

This is currently much weaker than the one-million-step `cnc4` sweep:

| Result | Final balanced win rate |
| --- | ---: |
| `cnc4` winner `qs7g6tml` | 0.295712 |
| Best completed `cnc5` trial, `swr4xoyd` | 0.037394 |
| `cnc5` completed-trial mean | 0.005801 |
| `cnc5` completed-trial median | 0.000000 |

`swr4xoyd` is winning on both spawn bands, but only at 4.61% close and 2.87% medium. It averages
13.47 E1, 0.94 E3, 11.45 kills, 11.90 losses, 0.23 buildings destroyed, and 1,419 harvested
credits. This is real mixed combat and economy behavior, but not yet an effective strategy.

The exact `cnc4` winner reward vector was sampled twice in `cnc5`. Both trials ended with identical
final behavior and a 0.005747 balanced win rate despite transient peaks of 0.087430 and 0.100280.
That repeat is evidence of deterministic policy degradation after the useful early phase, rather
than an engine-start or simulator failure.

## Interpretation

Five million timesteps is not simply the successful one-million-step training run plus four million
extra steps. `anneal_lr = 1`, and PufferLib computes its cosine learning-rate schedule from
`total_timesteps`. Raising the trial budget therefore changes the learning rate throughout the first
million steps as well as extending training. The early data indicates schedule instability or policy
collapse is the immediate issue.

Some trials learn isolated subskills without combining them. `owegs11f` builds a large mixed force
and destroys 1.39 buildings per episode but loses almost all matches; `1wers8q3` reliably harvests
about 4,112 credits but fields almost no army and records no wins.

This stopped 11% sample is not a final sweep conclusion and should not be used to choose a candidate.
Its reward-only search space could not test the optimizer and schedule explanation. Removing
`sweep_only` exposes 29 configured dimensions, including the inherited `train/total_timesteps`
dimension. The replacement sweep should pin that one dimension at five million timesteps and search
the other 28 policy, rollout, optimizer, and reward dimensions.
