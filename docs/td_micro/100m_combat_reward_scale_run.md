# TD Micro 100M Combat Reward Scale Run

Recorded: 2026-07-14

## Result

The environment completed a fresh 100M-timestep PufferLib GPU run after increasing combat shaping
from `+0.01` to `+0.1` per enemy unit and from `+0.05` to `+0.5` per enemy building:

- project: `cnc1`
- run: `cool-totem-8`
- run id: `cmv6t21t`
- URL: <https://wandb.ai/kinvert-k/cnc1/runs/cmv6t21t>

The run is valid under the `start_failures == 0` SPS rule. It completed without a pathfinding stall,
but the larger combat rewards did not produce a win. W&B reported zero wins in every retained
metric window, and none of the 97 retained greedy seed-1 checkpoints won or destroyed an enemy
building.

## Post-Run Timeout Audit

The run's 3,000-decision / 12,000-frame contract was later proven too short. With no policy or
simulation changes, extending replay to 7,500 decisions converted 94 of the 97 retained checkpoint
draws into losses. Extending the remaining three to 12,000 decisions converted all three into
losses; the latest terminal occurred at frame 41,876. The recorded W&B outcomes remain an accurate
description of the training contract, but they are not accurate skirmish outcomes.

The final checkpoint specifically changed from a draw at frame 12,000 to a legitimate loss at frame
26,552. See `docs/td_micro/learning_blockers_and_next_step.md` for the complete audit and replacement
contract.

## Command

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
env PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 \
  LD_LIBRARY_PATH="$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib:/usr/lib/wsl/lib" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
    --wandb \
    --wandb-project cnc1 \
    --tag reward-v3-combat-scale-100m \
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
| Uptime | 1,248.979 s |
| Aggregate SPS | 80,065 |
| Final dashboard SPS | 84,342 |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| Hidden layers | 64x1 |
| GPU training | yes |
| Maximum `start_failures` | 0.000 |
| Maximum rolling engine `failures` rate | 0.0013580 |
| Valid by SPS rule | yes |

The nonzero engine-failure samples make this a policy-quality run rather than a clean environment
speed comparison. The local result is:

```text
PufferLib/logs/cnc_micro/cmv6t21t.json
SHA-256 107efafc6c873e5598b0b8aa8bbb0d91578a81f59d8a4168e96a24973947a90a
```

The higher aggregate SPS than the preceding run is machine/runtime variation, not evidence that
larger reward constants made the simulator faster. Environment work and trainer hyperparameters
were unchanged.

## Policy Result

All 97 retained checkpoints were replayed from seed 1 through the native C inference API:

- 0 won.
- 9 issued attack commands.
- 2 killed at least one enemy unit.
- 0 destroyed an opponent building.
- every replay completed without an engine failure.

The strongest combat checkpoint was at 37,750,784 steps:

```text
checkpoint  PufferLib/checkpoints/cnc_micro/cmv6t21t/0000000037750784.bin
SHA-256     7815942cae365da021e0fb4c60f9306fa2aee750ec66674b1213bc847a2a4fdf
terminal    legitimate loss at 2,395 decisions
return      -0.04
production  E1=4, E3=2
combat      490 attacks, 4 enemy unit kills, 6 player unit losses
commands    noop=1,863 deploy=1 start=6 place=6 train=12 move=17 attack=490
invalid     507
failures    0
trace       33f8937041d266496c2febc06554228d2cfe3659c39897ac370da90654974fa6 (twice)
```

The matching complete state-trace hashes prove deterministic replay. The final checkpoint was also
deterministic but had collapsed to a partial economy opening:

```text
checkpoint  PufferLib/checkpoints/cnc_micro/cmv6t21t/0000000099999744.bin
SHA-256     d2c1f479e69b9fc9f2e301250793ce43d69ae3aa2697339aa07232cf85d076a8
terminal    timeout draw at 3,000 decisions
return      +0.20
milestones  Construction Yard, Power Plant
commands    noop=2,994 deploy=1 start=3 place=2; all others=0
invalid     0
failures    0
trace       b4ea07a0d00dac1247c8da980ea5f27cfdd160990215a505eadcecf23bd55664 (twice)
```

## Controlled Comparison

The preceding pathfinder-capped run used the same trainer and vector settings with the old combat
rewards. The checkpoint sweep gives the more useful comparison:

| Result | Old `+0.01/+0.05` | New `+0.1/+0.5` |
| --- | ---: | ---: |
| W&B rolling win rate ever nonzero | yes | no |
| Retained checkpoints | 97 | 97 |
| Retained seed-1 winners | 0 | 0 |
| Checkpoints issuing attacks | 10 | 9 |
| Best enemy unit kills | 8 | 4 |
| Checkpoints destroying an enemy building | 1 | 0 |
| Best terminal result | draw | draw |

The old run's strongest strategic checkpoint built both infantry types, attacked, killed a unit,
and destroyed one enemy building before drawing. The new run's strongest combat checkpoint killed
four units but lost without damaging a building. A single training seed is not enough to attribute
the difference entirely to reward scale, but there is no evidence that the 10x rewards improved the
policy.

## Finding

Increasing combat reward magnitude did not fix the learning bottleneck. The policy can enter combat,
but independent MultiDiscrete heads still produce incompatible command tuples and unstable policies.
The next serious training change should be command-conditioned action decoding plus automatic
checkpoint evaluation/selection. Repeating the same factorized policy for another 100M steps is not
supported by these results.
