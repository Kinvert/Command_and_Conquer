# TD Micro 100M W&B Training Run

Recorded: 2026-07-14

## Result

The first 100M-step TD Micro run completed successfully and synced to W&B:

- project: `cnc1`
- run: `mild-universe-1`
- run id: `bjd42h26`
- URL: <https://wandb.ai/kinvert-k/cnc1/runs/bjd42h26>

The run is valid throughput evidence but did not produce a winning final policy. The final checkpoint
converged to an all-noop timeout draw. Earlier retained checkpoints are materially better.

## Command

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
env PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb \
  --wandb-project cnc1 \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 4 \
  --vec.num-threads 4 \
  --train.total-timesteps 100000000 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 512 \
  --eval-episodes 1
```

## Throughput And Validity

| Field | Result |
| --- | ---: |
| Configured timesteps | 100,000,000 |
| Logged timesteps | 99,999,744 |
| Difference from requested total | 256, due rollout quantum |
| Uptime | 906.037 s (15m 6s) |
| Aggregate SPS | 110,371 |
| Final partial-interval SPS | 96,820 |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| GPU training | yes |
| Maximum `start_failures` | 0.000 |
| Maximum engine `failures` | 0.000 |
| Valid throughput claim | yes |

The final partial interval is not representative because it contains only the tail of the last
rollout. Aggregate SPS is logged steps divided by total uptime. Live full intervals were generally
about 104K-117K SPS.

Machine-readable result:

```text
PufferLib/logs/cnc_micro/bjd42h26.json
SHA-256 d66bb25c903e3ff331999312701ab759c95c39fe5f2c428c8e5260ffef9aa112
```

## Checkpoint Sweep

The run retained 97 checkpoints at approximately 1.05M-step intervals. Every checkpoint was replayed
from seed 1 through terminal with the deterministic native C API. No replay had an engine failure and
none won. Seven checkpoints reached at least three milestones; four reached Construction Yard, Power
Plant, Barracks, and E1. None reached E3.

Raw deterministic summaries:

```text
docs/td_micro/benchmarks/cnc_micro_wandb_100m_checkpoint_eval.tsv
SHA-256 269a038d5a806d64565a6eeacf181b9a28018418609230300b50314a4bbbe728
```

### Best Transfer Candidate

```text
steps       10,487,808
checkpoint  PufferLib/checkpoints/cnc_micro/bjd42h26/0000000010487808.bin
SHA-256     d866b4f5978da7a6fdae28f69988ba8cf039fb9d3edd58777f468b89623cb760
terminal    timeout draw at 1,800 decisions
return      +0.40
milestones  4/5: Construction Yard, Power Plant, Barracks, E1
invalid     214
failures    0
commands    noop=1288 deploy=1 start=4 place=4 train=41 move=0 attack=462 guard=0 stop=0
```

Its first meaningful accepted sequence was:

| Decision | Action |
| ---: | --- |
| 0 | Deploy MCV |
| 1,143 | Start Power Plant |
| 1,197 | Place Power Plant |
| 1,198 | Start Barracks |
| 1,252 | Place Barracks |
| 1,309 | Train E1 |
| 1,337 | First attack command |

The 41 train-head selections do not mean 41 infantry were built; many assembled tuples were invalid.
The one accepted E1 production is proven by the milestone transition. This distinction motivates the
new production counters required below.

### Action-Heavy Candidate

```text
steps       24,119,296
checkpoint  PufferLib/checkpoints/cnc_micro/bjd42h26/0000000024119296.bin
SHA-256     02fd91ffaab06666778020ba164bf9003c7a87c25af983988d13cf41ba8354e5
terminal    timeout draw at 1,800 decisions
return      +0.34
milestones  4/5
invalid     371
failures    0
commands    noop=1420 deploy=7 start=3 place=3 train=334 move=0 attack=33 guard=0 stop=0
```

The earlier inference that `+0.34` implied 60 infantry deaths was wrong. Exact event counters added
after this run show zero unit losses and zero enemy attack orders. The missing `0.06` is six
pre-deployment penalties before the MCV deploy command was accepted. Under the corrected 3,000-step
combat contract this checkpoint terminates at decision 1,880 from an invalid-action streak, still
before enemy engagement.

### Final Checkpoint

```text
steps       99,999,744
SHA-256     a0767e8d6ab1d7c38200ef94d1ffe4be8db1d85fe0ce884ea1466158b75bcfe4
terminal    timeout draw at 1,800 decisions
return      -17.99
milestones  0/5
invalid     0
commands    noop=1800; all others=0
```

The final checkpoint is rejected for deployment. Training quality is highly non-monotonic, so future
runs must select checkpoints by deterministic task metrics rather than final timestep.

## Required Metrics Before The Next Run

Before another training run, add tested per-episode and W&B metrics for:

- player E1 built;
- player E3 built;
- opponent E1 and E3 built;
- player unit kills;
- player unit losses;
- player and opponent buildings lost;
- explicit enemy attack orders;
- accepted and rejected train commands; and
- each milestone completion rate.

Birth and death counters must come from simulation events, not net active-unit counts, so a build and
death within one four-frame decision cannot cancel each other. Counter changes must leave canonical
world digests and deterministic parity unchanged.

These metrics and the corrected 12,000-frame combat timeout are now implemented and verified in
`docs/td_micro/combat_metrics_and_timeout_fix.md`.

## Conclusion

More timesteps alone did not solve the policy. The run reached useful E1-and-attack behavior around
10.5M steps, then repeatedly moved among invalid-streak, timeout, and all-noop local optima. The next
training work should add the requested observability, correct the oversized repeated pre-deployment
penalty, and improve action validity before spending another 100M steps.
