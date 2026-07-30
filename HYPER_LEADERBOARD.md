# TD Micro Hyperparameter Leaderboard

This file records reproducible training configurations that emitted at least one nonzero
`env/win_rate` window. An entry is a **candidate**, not automatically a certified winning policy.
Certification requires retained weights, evaluation over declared fixed policy seeds, and a
terminal trace proving that the opponent was legitimately defeated. Greedy action selection is a
useful separate test, but it is not required for a policy trained and deployed with categorical
sampling.

## Code Snapshots

The historical `cnc1` reward-sweep entries through `lqkwukxi` ran from a previously uncommitted
source state now frozen in:

```text
834ba2151a7b7f2cdd5a5386ecc5f59af93afa59
feat: extend td-micro skirmish training and reward sweeps
```

W&B may display the prior `74527db` HEAD because the source changes were uncommitted while the sweep
ran. Use `834ba2151a7b7f2cdd5a5386ecc5f59af93afa59` to reproduce the actual code, not the stale W&B
commit metadata. Only documentation changed between the sweep and this snapshot commit.

The ABI-6 balanced close/medium curriculum and current champion are frozen separately in:

```text
1625e88972d5a32a310b890862a86a10f21353b2
feat: add balanced spawn training curriculum
```

Those runs occurred while the changes were uncommitted on top of `41a219e`, so their W&B Git field
may also be stale. Use `1625e88` for the exact balanced source and config.

## Current Champion

| Rank | Retained run | Training evaluation | SPS | Source | Checkpoint SHA-256 |
| ---: | --- | --- | ---: | --- | --- |
| 1 | [`lwgwyjl7`](https://wandb.ai/kinvert-k/cnc2/runs/lwgwyjl7) | **505 wins / 0 losses / 0 draws**; 257/0/0 close and 248/0/0 medium | **97,772** | `1625e88` | `46695237efbb6d350971e1163a54c57877a897d487c2b9f7873f3b16dce275e7` |

`lwgwyjl7` is the first retained policy trained from scratch on the balanced ABI-6 curriculum that
passes the complete promotion chain: zero-failure PufferLib GPU training, perfect final close and
medium evaluation, byte-identical fixed-seed native replays for both profiles, and a real rendered
Vanilla win from the medium spawn. It supersedes `lqkwukxi` for the current curriculum. Full
evidence is in `docs/td_micro/lwgwyjl7_balanced_champion.md`.

## Historical Shared Hyperparameters

| Group | Hyperparameters |
| --- | --- |
| Workload | 1,048,576 timesteps per run; full 12,000-decision episodes |
| Vectorization | 64 agents; 4 buffers; 4 threads |
| Policy | `MinGRU`; hidden size 64; 1 layer; expansion factor 1 |
| Observation | byte transport; `Normalize255Encoder`; `DefaultDecoder` |
| Rollout | horizon 32; minibatch size 2,048; replay ratio 1.0 |
| PPO/V-trace | learning rate 0.015; gamma 0.995; GAE lambda 0.9; clip 0.2; V-trace rho/c 1.0/1.0 |
| Value/entropy | value coefficient 2.0; value clip 0.2; entropy coefficient 0.001 |
| Optimizer | max grad norm 1.5; beta1 0.95; beta2 0.999; epsilon 1e-12 |
| Priorities | alpha 0.8; beta0 0.2 |
| Seeds | Puffer seed 73; train seed 42; environment seed 1 |
| Compute | native CPU Zig env; Puffer CUDA trainer; 1 GPU; 10 cudagraphs |
| Sweep | Protein; metric `score = win_rate - loss_rate`; GP optimizer on CPU; only five reward fields varied |
| Retention | checkpoint interval 100,000,000; no candidate weights were retained |

W&B project: [`kinvert-k/cnc1`](https://wandb.ai/kinvert-k/cnc1), group
`reward-sweep-10`, tag `reward-sweep-10x1m`.

## Candidate Runs

`Best win` is the largest nonzero training-window `env/win_rate`. Early windows are aggregated across
workers and do not expose an exact integer win count. `Final W/L/D` is the final consolidated
reporting window and does expose integer-equivalent counts.

| Rank | Run | Milestone | Infantry | Enemy unit | Enemy building | Own loss | Best win | Final W/L/D | Code commit | Notes |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 1 | [`s5de39j5`](https://wandb.ai/kinvert-k/cnc1/runs/s5de39j5) | 0.111029 | 0.0237583 | 0.0214141 | 0.445982 | -0.00691817 | 37.50% | **1/11/40** | `834ba21` | Best final score, `-0.192308`; one countable final-window win; draw-heavy and slow at 33,199 SPS. |
| 2 | [`bzojokr5`](https://wandb.ai/kinvert-k/cnc1/runs/bzojokr5) | 0.0590374 | 0.0122953 | 0.0710608 | 0.0885419 | -0.00126279 | 6.38% | **6/83/5** | `834ba21` | Strongest countable win evidence: six final-window wins; final score `-0.819149`. |
| 3 | [`di2p2sj1`](https://wandb.ai/kinvert-k/cnc1/runs/di2p2sj1) | 0.0861404 | 0.0474949 | 0.0348740 | 0.218202 | -0.000643264 | 9.52% | 0/20/54 | `834ba21` | Early aggregated win signal only; final window had no wins and was draw-heavy. |
| 4 | [`r2mnrrwn`](https://wandb.ai/kinvert-k/cnc1/runs/r2mnrrwn) | 0.160334 | 0.00100175 | 0.127191 | 0.855853 | -0.00784224 | 11.11% | 0/160/0 | `834ba21` | Early aggregated win signal only; final policy window lost every episode. |
| 5 | [`hbvj2y5r`](https://wandb.ai/kinvert-k/cnc1/runs/hbvj2y5r) | 0.181962 | 0.0392564 | 0.166099 | 0.978264 | -0.00972268 | 7.14% | 0/109/1 | `834ba21` | Early aggregated win signal only; final window had no wins. |
| 6 | [`28a1mnns`](https://wandb.ai/kinvert-k/cnc1/runs/28a1mnns) | 0.100000 | 0.0100000 | 0.100000 | 0.500000 | -0.00100000 | 4.17% | 0/65/6 | `834ba21` | Default-reward bootstrap run; early aggregated win signal only. |
| 7 | [`64xujvdo`](https://wandb.ai/kinvert-k/cnc1/runs/64xujvdo) | 0.100000 | 0.0100000 | 0.100000 | 0.500000 | -0.00100000 | 4.17% | 0/65/6 | `834ba21` | Repeated default bootstrap; same final metrics as run 1. |
| 8 | [`v6up7dtd`](https://wandb.ai/kinvert-k/cnc1/runs/v6up7dtd) | 0.00680791 | 0.0129808 | 0.177588 | 0.748421 | -0.00349790 | 2.22% | 0/94/3 | `834ba21` | Early aggregated win signal only; final window had no wins. |

Runs `vllns5dm` and `z7m2gv91` never logged a nonzero win rate and are not leaderboard entries.

## Direct Reproduction

Substitute one row's five reward values into this fixed command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export EXTRA_LIBS="$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib:/usr/lib/wsl/lib"
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc1 --train.gpus 1 \
  --seed 73 --train.seed 42 --env.seed 1 --env.max-decisions 12000 \
  --vec.total-agents 64 --vec.num-buffers 4 --vec.num-threads 4 \
  --train.total-timesteps 1048576 --train.horizon 32 \
  --train.minibatch-size 2048 --train.learning-rate 0.015 \
  --train.gamma 0.995 --train.gae-lambda 0.9 --train.replay-ratio 1.0 \
  --policy.hidden-size 64 --policy.num-layers 1 \
  --env.reward-milestone MILESTONE \
  --env.reward-player-infantry INFANTRY \
  --env.reward-enemy-unit-loss ENEMY_UNIT \
  --env.reward-enemy-building-loss ENEMY_BUILDING \
  --env.reward-player-unit-loss OWN_LOSS
```

For certification, reduce the checkpoint interval and evaluate retained checkpoints on a declared
policy-seed set. Record whether actions are sampled or greedy. A training-window win alone must never
be promoted to a certified leaderboard result.

## Win Audit

The `bzojokr5` configuration has now passed a rollout-legitimacy audit. Two reruns reproduced its
final 94-episode window exactly at 6 wins, 83 losses, and 5 draws with zero engine/start failures.
The trace-enabled rerun emitted nine winning episodes across all windows; every action trace replayed
twice with terminal reward `+1`, one win, zero failures, substantial combat, and an identical
trajectory hash. Audit tooling is frozen in `92c836e1b5e5e5516c47b811ba2ed07a636c6cd3`; full evidence
is in `docs/td_micro/win_legitimacy_audit.md`.

The retained checkpoints did not win under greedy seed-1 inference. A later same-shape sampled audit
found only 18/256 wins for the short-schedule checkpoint, and longer training collapsed to 0/256.
This verifies that the logged wins were real stochastic training rollouts, but `bzojokr5` remains an
unstable candidate rather than a certified winning policy. Current sweeps optimize binary `perf`;
the table above preserves the historical `score`-based sweep results.

## Promoted Config Regression

Commit `9626b2ae` promoted the exact `bzojokr5` rewards and shared PPO settings into
`PufferLib/config/cnc_micro.ini`. An INI-only 1,048,576-step run (`1784140598595`) again finished
with **6 wins, 83 losses, and 5 draws**, 74,304 SPS, and zero failures.

Training the same configuration to 10M steps did not improve it. W&B run
[`hjk4ii86`](https://wandb.ai/kinvert-k/cnc1/runs/hjk4ii86) had wins only in its first downsample
region, then zero wins and zero production in every later region. Final evaluation was
**0 wins / 2,020 losses / 0 draws**. All 11 distinct training checkpoints lost under greedy seed-1
inference. See `docs/td_micro/promoted_bzo_10m_run.md`.

The follow-up root-cause audit evaluated each policy for 256 sampled episodes. The near-random 2K
checkpoint scored 1/256 wins, the short-schedule 1M checkpoint scored 18/256, the long-schedule
1.026M checkpoint scored 0/256, and the final 10M checkpoint scored 0/256. The longer budget also
changed cosine learning-rate annealing: at 1,048,576 steps the short run was at learning rate zero,
while the long run was still at about 0.01460. Independent action heads then let the policy collapse
onto `start_build + product_none`. See
`docs/td_micro/promoted_bzo_collapse_root_cause.md`.

## 100-Run Sweep Winner

The official 100 x 1M Protein sweep found a qualitatively stronger reward region. Of 100 completed
runs, 88 had zero engine/start failures and were valid. Top run
[`a1y38c6z`](https://wandb.ai/kinvert-k/cnc1/runs/a1y38c6z) produced **452 wins, 9 losses, and 1 draw**
over its final 462 episodes (97.84% wins).

Checkpointed run [`lqkwukxi`](https://wandb.ai/kinvert-k/cnc1/runs/lqkwukxi)
(`autumn-tree-125`) reproduced all final environment metrics exactly. Its final checkpoint has
SHA-256 `7c8734032f8a214c1108c8793f2013af2dc223acccdd87da13456fc65ec56a72`.
Fresh sampled evaluation seeds 74-76 then produced **768 wins, 2 losses, and 0 draws** over 770
episodes (99.74%), with zero failures. A winning action trace replayed twice with terminal `+1`, all
three enemy buildings destroyed, and trajectory hash `c6bfdff0a99314e7`.

This is a certified sampled-policy checkpoint for TD Micro. The native visible adapter now uses
seeded categorical sampling and has completed a real Vanilla win against the original Easy GDI AI:
frame 3,402, 851 decisions, `opponent_defeated=1`, and zero failures. Independent greedy argmax
remains a failing diagnostic path. Full sweep results are in
`docs/td_micro/reward_sweep_100x1m.md`; visible validation is in
`docs/td_micro/lqkwukxi_visible_vanilla_validation.md`.

## Balanced Spawn Baseline

Run [`2zuaj9oa`](https://wandb.ai/kinvert-k/cnc2/runs/2zuaj9oa) reused the exact `lqkwukxi` rewards
and shared training shape after adding deterministic close/medium starts. It is a curriculum
baseline, not a leaderboard candidate: the final 115-episode window was 0 wins, 115 losses, and 0
draws. Close finished 0/50 and medium 0/65. The valid GPU run reported 99,829 SPS, zero start or
engine failures, and 9.026 enemy attack orders per episode. See
`docs/td_micro/balanced_spawn_curriculum.md`.

Acceptance repeat [`bakj8jl2`](https://wandb.ai/kinvert-k/cnc2/runs/bakj8jl2) passed the complete
build/test/train/eval gate at 94,174 SPS with zero start or engine failures. Its post-training
evaluation also finished 0/115/0, but direct sampled evaluation found one medium win in six samples
from the 2,048-step checkpoint and zero wins in six from the final checkpoint. It remains a
diagnostic baseline, not a leaderboard candidate; final-checkpoint-only selection is rejected.

Default-only reproduction [`3mq4ot3x`](https://wandb.ai/kinvert-k/cnc2/runs/3mq4ot3x) first pinned
the complete authoritative `lqkwukxi` W&B config in `PufferLib/config/cnc_micro.ini`, including
prioritized replay and all inherited optimizer/clipping values. Its effective `env`, `vec`,
`policy`, `torch`, and `train` sections had zero differences from `lqkwukxi`; no model was loaded.
The valid 105,003 SPS run again finished 0/115/0, and both its 2,048-step and final checkpoint hashes
exactly matched `bakj8jl2`. The failed fresh training result is therefore not caused by omitted
hyperparameters or stale reward defaults at runtime.

The historical `lqkwukxi` champion itself remained compatible with ABI6. Fresh native evaluation
produced **250/6/0 close** and **256/0/0 medium**, or **506/6/0 overall (98.8281% wins)**, with zero
failures. It then won a real medium-spawn Vanilla match at frame 3,687. This established the
transfer baseline before `lwgwyjl7` superseded it. See
`docs/td_micro/lqkwukxi_balanced_abi6_eval.md`.

## Balanced Stability Sweep And Promotion

The 100-run `cnc2` stability sweep fixed the exact `lqkwukxi` rewards and varied six optimizer and
rollout controls. Of 100 completed 1M-step GPU trials, 99 were valid. Run
[`w1swzimb`](https://wandb.ai/kinvert-k/cnc2/runs/w1swzimb) (`cosmic-puddle-57`) finished with
**257/0/0 close** and **248/0/0 medium**, or **505/0/0 overall**, at 73,263 SPS and zero failures.

Its sampled values were learning rate `0.008668618381591891`, entropy coefficient
`0.0009582776518303332`, horizon 32, maximum gradient norm `0.6515999019540559`, priority alpha
`0.22100208042634323`, and priority beta0 `0.985908351638052`. Four trials exceeded 95% balanced
performance, showing a repeatable high-performing region rather than one isolated point.

Sweep workers did not retain checkpoints, so `w1swzimb` itself remains the discovery run. Normal
training run [`lwgwyjl7`](https://wandb.ai/kinvert-k/cnc2/runs/lwgwyjl7)
(`cool-surf-104`) then used the exact winning settings and retained checkpoint
`46695237efbb6d350971e1163a54c57877a897d487c2b9f7873f3b16dce275e7`.
It reproduced the sweep winner's final environment outcomes exactly: **257/0/0 close**,
**248/0/0 medium**, and **505/0/0 overall**. The valid one-GPU run reported 97,772 SPS with zero
start and engine failures.

Representative close and medium native samples both won and replayed byte-identically. The same
checkpoint then won a real medium-spawn Vanilla match at frame 4,168 with
`opponent_defeated=1` and zero failures. This is the promoted balanced champion, not merely a
training-window candidate. See `docs/td_micro/balanced_stability_sweep_100.md` and
`docs/td_micro/lwgwyjl7_balanced_champion.md`.
