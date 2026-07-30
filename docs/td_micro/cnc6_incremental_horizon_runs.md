# CNC6 Incremental Training-Horizon Runs

Date: 2026-07-18

## Purpose

Bracket the point where the best raw CNC6 2M candidate stops learning by raising
`train.total_timesteps` in small increments. Keep every seed, reward, vector, policy, and optimizer
setting fixed. Because `anneal_lr=1`, each budget is a fresh run with a slightly different
learning-rate schedule, not a continuation of the source checkpoint.

## Fixed Candidate

The source is [`qj7bux1j`](https://wandb.ai/kinvert-k/cnc6/runs/qj7bux1j), exact `8fc` with
`reward_milestone=0.2`. At 2,097,152 steps it scored:

| Steps | Run | Balanced | Close | Medium | Perf | n | SPS | Valid |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 2,097,152 | `qj7bux1j` | 0.421753 | 0.202128 | 0.641379 | 0.468619 | 239 | 37,487 | yes |
| 2,097,152 | [`k8tbk55t`](https://wandb.ai/kinvert-k/cnc6/runs/k8tbk55t) exact replay | 0.421753 | 0.202128 | 0.641379 | 0.468619 | 239 | 38,324 | yes |
| 2,097,152 | [`hq1eftis`](https://wandb.ai/kinvert-k/cnc6/runs/hq1eftis) post-cleanup gate | 0.421753 | 0.202128 | 0.641379 | 0.468619 | 239 | 33,289 | yes |
| 2,099,200 | [`g6oih672`](https://wandb.ai/kinvert-k/cnc6/runs/g6oih672) | 0.111520 | 0.098039 | 0.125000 | 0.112150 | 214 | 41,659 | yes |
| 2,101,248 | [`dneqp8in`](https://wandb.ai/kinvert-k/cnc6/runs/dneqp8in) | 0.267974 | 0.057377 | 0.478571 | 0.282443 | 262 | 38,458 | yes |
| 2,103,296 | [`dwj5edfa`](https://wandb.ai/kinvert-k/cnc6/runs/dwj5edfa) | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 241 | 28,460 | yes |
| 2,199,552 | [`uxyqwmit`](https://wandb.ai/kinvert-k/cnc6/runs/uxyqwmit) | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 291 | 24,366 | yes |

Validity requires CUDA training with `start_failures=0` and `failures=0`; all rows are valid. The
requested 2,100,000 and 2,200,000 budgets are rollout-aligned down to 2,099,200 and 2,199,552
agent steps respectively.

The 2026-07-18 `hq1eftis` gate ran from source commit
`2d9a4f1dab6ea9cd5342d2deb91c208fb204a1ba` after the dirty-worktree cleanup. Before training,
all 153 Zig tests passed in Debug, ReleaseSafe, and ReleaseFast, and `cnc_micro` rebuilt through
`PufferLib/build.sh`. The normal CUDA command completed with `start_failures=0` and engine
`failures=0`; its built-in sampled no-update evaluation reproduced every final outcome above.

The retained checkpoints are byte-identical across `hq1eftis`, `qj7bux1j`, and `k8tbk55t`:

| Agent steps | SHA-256 |
| ---: | --- |
| 2,048 | `138a8b4e997aa5a3d46f1037477c2119c759ed5995fc0c94f8315e4e6494fb14` |
| 1,050,624 | `71478a42716181cf724e691bca143209c23372614ac5476faeea34d0744e48e6` |
| 2,097,152 | `490064539416022a02179b47136a74219ed37a618fcfa6173cabc659510c7a37` |

The lower displayed SPS is not accompanied by any trajectory, metric, or checkpoint change. It is a
valid throughput sample but not evidence of a simulator regression without a controlled adjacent
benchmark on an otherwise idle host.

## Command

Set the complete source configuration in `PufferLib/config/cnc_micro.ini`, changing only
`train.total_timesteps`, then run:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc6 --tag <unique-incremental-tag>
```

The fixed shape is 64 agents, one buffer, four threads, horizon 32, minibatch 2,048, one 64-wide
MinGRU layer, CUDA GPU training, environment seed 1, and base seed 73. `train.seed=42` is recorded,
but the native CUDA backend initializes its policy and sampling RNG from the top-level base seed.

## Interpretation

The exact-budget replay reproduces every environment/result metric and every retained policy
checkpoint bit-for-bit. This training path is deterministic. The final 2,097,152-step policy in
both runs has SHA-256 `490064539416022a02179b47136a74219ed37a618fcfa6173cabc659510c7a37`.
The 2,048-step and 1,050,624-step checkpoint hashes also match between the two runs.

The 2.1M run matches the source at the first 2,048-step checkpoint, then diverges. The sole resolved
configuration difference is `total_timesteps`. With 64 agents and horizon 32, this changes
`total_epochs` from 1,024 to 1,025. In the active configuration:

- `anneal_lr=1`, so `total_epochs` is the denominator of the cosine learning-rate schedule;
- `anneal_ent_coef=0`, so entropy does not depend on the denominator;
- `prio_beta0=1`, so the nominal priority-beta anneal is constant at one.

At epoch 512, the 1,024-epoch schedule uses LR `0.000485056476331`; the 1,025-epoch schedule uses
`0.000485799817436`, only 0.153% higher. That small deterministic parameter difference eventually
changes a sampled action, which changes the trajectory and all subsequent PPO data. The 2.1M run
therefore reaches a different deterministic policy and falls to 0.111520 balanced performance.

The 2.2M run uses 1,074 epochs. At source epoch 1,023 its LR is `0.00000538751205`, versus
`0.00000000228277` in the 1,024-epoch source schedule, and it then performs 50 more updates. Its
complete collapse is consistent with the much larger late-training schedule change.

Any further incremental tests must use exact rollout-aligned budgets and advance one 2,048-step
epoch at a time: 2,105,344, 2,107,392, and so on. Each budget defines a distinct deterministic
optimization trajectory; this is not equivalent to continuing the successful checkpoint.

The first four adjacent aligned schedules score 0.421753, 0.111520, 0.267974, and 0.000000. The
local objective is therefore highly discontinuous with respect to the annealing denominator. Stop
treating a larger from-scratch `total_timesteps` value as a continuation experiment. Preserve the
1,024-epoch default until continuation includes optimizer/RNG state or training exposes an anneal
horizon independent of the stopping budget.
