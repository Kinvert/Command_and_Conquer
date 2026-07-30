# TD Micro 100M Combat-Metrics Run

Recorded: 2026-07-14

## Result

The first 100M-step run with the corrected 12,000-frame combat timeout and explicit production,
kill, loss, building-loss, and enemy-attack metrics completed and synced to W&B:

- project: `cnc1`
- run: `rare-fog-4`
- run id: `xhnetlv5`
- URL: <https://wandb.ai/kinvert-k/cnc1/runs/xhnetlv5>

This is useful policy and instrumentation evidence, but it is not a clean SPS baseline. Another game
was using the machine during training, and two episodes ended in an engine failure. The policy won
zero matches and never destroyed an opponent building.

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
| Logged timesteps | 99,999,744 |
| Uptime | 1,412.173 s |
| Aggregate SPS | 70,812.659 |
| Final dashboard SPS | 78,400 |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| GPU training | yes |
| Maximum `start_failures` | 0.000 |
| Engine failure episodes | 2 |
| Clean throughput claim | no |

The SPS values are retained only to make the record complete. Machine contention and the two engine
failures make comparison with uncontended baselines invalid.

Raw result:

```text
PufferLib/logs/cnc_micro/xhnetlv5.json
SHA-256 9dbbd248e978d9cbbdd9a61c33bc441dfc48bbcfb17587eec2597ac19f5ab2ed
```

## Full-Run Event Totals

The totals below reconstruct each event count from W&B history by weighting each per-episode metric
by that row's `env/n`. Floating-point roundoff was rounded to the nearest event.

| Outcome | Count |
| --- | ---: |
| Completed episodes | 267,607 |
| Wins | 0 |
| Losses | 261,709 |
| Draws | 5,896 |
| Engine failures | 2 |
| Building-limit losses | 292 |
| Infantry-limit losses | 0 |
| Invalid-streak losses | 250,845 |
| Rejected command tuples | 37,180,505 |

| Event | Player | Opponent |
| --- | ---: | ---: |
| E1 built | 4,406 | 234,263 |
| E3 built | 4,145 | 121,133 |
| Unit kill credits | 159 | 17,468 |
| Unit losses | 3,655 | 161 |
| Buildings lost | 13,811 | 0 |

Additional action metrics:

```text
enemy_attack_orders       109,933
accepted_train_actions      8,585
rejected_train_actions    399,654
```

The nonzero opponent production, attack, kill, player-unit-loss, and player-building-loss totals
prove that the extended timeout reaches real combat. Zero wins and zero opponent buildings lost
show that this run did not exercise a successful base attack.

## Final Checkpoint Replay

The final retained checkpoint was evaluated twice through the native C API:

```text
checkpoint steps     99,999,744
checkpoint SHA-256   93f631239260f99eda3d2aa4c72124015d6ef58bd4fa9e78599d0b5bdffceef5
trace SHA-256        0c08c1b01ebdd72bd33dbb3307878d04f59094cadb7cc05b962a2681f14edb25
terminal             legitimate loss at decision 2,467
reward sum           -0.90
commands             deploy=1, noop=2,466, all others=0
invalid actions      0
engine failures      0
opponent E1 / E3     9 / 1
opponent kill credits 1
player buildings lost 1
enemy attack orders   9
```

The policy deploys immediately and then no-ops until the Easy AI destroys its Construction Yard.
The matching trace hashes prove deterministic replay.

## Findings And Next Gate

1. A full player win must be proven reachable before another serious quality run. Add a Vanilla
   oracle fixture for a distant player attack, port exact attack/chase/path-to-target behavior, and
   run a scripted player trace through complete enemy elimination and `+1` terminal reward.
2. Remove the repeated `-0.01` pre-deployment penalty. It is not a global turn penalty, but it can
   contribute about `-20.9` before the deterministic all-noop loss and dwarfs all five `+0.1`
   milestones.
3. Do not add a large invalid-action penalty. Fix command-conditioned sampling first; if immediate
   feedback remains useful, use a small bounded curriculum channel rather than `-0.05` per reject.
4. The 37.2 million rejected tuples confirm that independent MultiDiscrete heads are a structural
   learning problem. Command-conditioned or autoregressive action heads are required.
5. Diagnose the two engine failures before the next clean run. They occurred in history windows at
   aggregate steps 10,129,408 and 59,621,376; the logger currently records only the aggregate
   failure count, not the `Failure` enum.
