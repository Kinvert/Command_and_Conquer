# Promoted BZO Hyperparameters: 1M And 10M Runs

Date: 2026-07-15

Code/config commit: `9626b2ae` (`config: promote verified td micro rewards`)

## Configuration

`PufferLib/config/cnc_micro.ini` now contains the exact `bzojokr5` reward vector and its fixed
training shape: seed 73, train seed 42, environment seed 1, 64 agents, 4 buffers, 4 threads, horizon
32, minibatch 2,048, hidden size 64, one layer, learning rate 0.015, gamma 0.995, GAE lambda 0.9,
replay ratio 1.0, and entropy coefficient 0.001. Future reward sweeps are centered on these values.

## INI-Only 1M Regression

The trainer was launched without any CLI hyperparameter overrides:

```bash
.venv/bin/python -m pufferlib.pufferl train cnc_micro
```

Local run `1784140598595` reproduced the prior candidate exactly:

| Steps | Final episodes | Win/loss/draw | Perf | SPS | Start/engine failures |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1,048,576 | 94 | **6/83/5** | 0.063830 | 74,304 | 0/0 |

Final combat and production metrics also matched the earlier runs exactly: 38.6915 infantry built,
18.4255 unit kills, 37.2340 unit losses, 7.9894 buildings lost, and 6.4681 buildings destroyed.

## 10M Extension

Only the CLI timestep budget changed:

```bash
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc1 --wandb-group promoted-bzo-long \
  --tag bzo-10m --train.total-timesteps 10000000
```

W&B run: [`hjk4ii86`](https://wandb.ai/kinvert-k/cnc1/runs/hjk4ii86)

This was not an equivalent optimizer schedule extended in time. `anneal_lr=1` computes cosine decay
against `total_timesteps`, so the 1M run reached learning rate zero at its endpoint while this run
still used about `0.01460` at the same aggregate step. The controlled root-cause audit is in
`docs/td_micro/promoted_bzo_collapse_root_cause.md`.

The longer run did **not** produce a better policy:

| Phase | Win/loss/draw | Units built | Unit kills | Buildings destroyed |
| --- | ---: | ---: | ---: | ---: |
| First downsample region | Nonzero wins; mean `perf=0.02319` | 7.591 | 4.722 | 0.227 |
| Remaining four training regions | `perf=0` throughout | 0 | 0 | 0 |
| Final post-training evaluation | **0/2020/0** | 0 | 0 | 0 |

The final training window was also 100% losses. It deployed the MCV but did not complete a power
plant, barracks, or infantry production. `start_failures` and engine `failures` remained zero, so
this is policy collapse rather than an invalid environment run.

The W&B history API timed out during the exact all-window count query. The synced local JSON retains
five downsample regions and the full 2,020-episode final evaluation, which are sufficient to establish
that wins disappeared rather than increased.

## Checkpoint Audit

Eleven distinct training checkpoints were retained from 2,048 through 9,998,336 steps. Native
greedy seed-1 inference lost for every checkpoint:

- 2,048 steps: only no-op.
- 1,026,048 steps: deploy, begin construction, then invalid placement forever.
- 2,050,048 steps and later: deploy, then alternate no-op/build-start behavior; no training or attack.
- Final checkpoint SHA-256: `82591010e47188e045bc7b06496d394e0f00c578f3f7a801aefc035e81b91ddc`.

Four eval-loop checkpoint files after the training budget have that same final hash.

## Conclusion

The promoted reward vector reliably creates occasional stochastic rollout wins around 1M steps,
but a fresh run with a ten-times-longer cosine schedule collapses production and yields no final
wins. A same-shape 256-episode audit measured 18 wins for the short-schedule 1M checkpoint, zero for
the long-schedule 1.026M checkpoint, and zero for the final 10M checkpoint. More timesteps are not
the next lever. Fix conditional action sampling, decouple learning-rate decay from the requested
budget, retain and evaluate checkpoints automatically, and select on fixed-policy outcomes rather
than a sampled training window.
