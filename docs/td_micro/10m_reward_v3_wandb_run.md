# TD Micro Reward V3 10M W&B Run

Recorded: 2026-07-14

## Result

The reward-v3 reachable-win environment completed a 10M-step PufferLib GPU training run and synced
it to W&B:

- project: `cnc1`
- run: `generous-cherry-5`
- run id: `6eegusyb`
- URL: <https://wandb.ai/kinvert-k/cnc1/runs/6eegusyb>

The run is valid under the `start_failures == 0` SPS rule and proved that training can visit the
economy, infantry, combat, and enemy-building-loss state space. It did not learn a win. Policy
quality was non-monotonic, and the final checkpoint collapsed to no-op plus rejected deploy tuples.

## Command

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
env PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb \
  --wandb-project cnc1 \
  --tag reward-v3-reachable-win-10m \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 4 \
  --vec.num-threads 4 \
  --train.total-timesteps 10000000 \
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
| Logged timesteps | 9,998,336 |
| Uptime | 140.294 s |
| Aggregate SPS | 71,267 |
| Final dashboard SPS | 77,423 |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| Hidden layers | 64x1 |
| GPU training | yes |
| Maximum `start_failures` | 0.000 |
| Maximum rolling engine `failures` rate | 0.0008547 |
| Valid by SPS rule | yes |

The rare nonzero engine-failure sample means this is a policy-quality run, not a clean environment
performance comparison. The raw local result is:

```text
PufferLib/logs/cnc_micro/6eegusyb.json
SHA-256 98ca081cd2e51e98d13589d5cc734784bf9fb347efe866c08b3df1e59d36bfae
```

No logged evaluation window had a nonzero win rate. Intermediate windows did report both infantry
types, player kill credits, and opponent building losses, confirming that the population visited
useful combat states even though greedy retained policies did not preserve a winning sequence.

## Retained Checkpoints

All 11 retained checkpoints were replayed from seed 1 through the native C inference API. None won
and none issued an attack command. The strongest retained seed-1 policy was:

```text
steps       7,342,080
checkpoint  PufferLib/checkpoints/cnc_micro/6eegusyb/0000000007342080.bin
SHA-256     9ade5cf21e537d45d39870ee6d9bacd53702a9215215086b32a0ce1e58fb1cea
terminal    timeout draw at 3,000 decisions
return      +0.41
milestones  Construction Yard, Power Plant, Barracks, E3
commands    noop=722 deploy=1 start=646 place=763 train=1 move=867 attack=0
invalid     2,249
failures    0
trace       a906210510b1858e97a9b22d6358c1f3dfce1110781136f533e304e0ba30541a (twice)
```

The matching trace hashes prove deterministic replay. The final checkpoint was deterministic but
substantially worse:

```text
steps       9,998,336
checkpoint  PufferLib/checkpoints/cnc_micro/6eegusyb/0000000009998336.bin
SHA-256     79fbf0b1533bb54b1703176a0e410c791215328b65a55ad401851f7600b31039
terminal    legitimate loss at 2,090 decisions
return      -1.00
commands    noop=1,146 deploy=944; all others=0
invalid     944
failures    0
trace       14db5afd9149bb54ea4a2a24ad8d742ad30414fe6dfe05557df41265ab6b9093 (twice)
```

## Finding

Longer training with the current independent MultiDiscrete heads is not the next useful experiment.
The heads choose values that are individually mask-legal but incompatible as a command tuple; the
best checkpoint spent 2,249 decisions on such tuples and never attacked. The next gate is a
command-conditioned/autoregressive decoder or an equivalent canonical action encoding, followed by
the same deterministic checkpoint sweep and W&B benchmark.
