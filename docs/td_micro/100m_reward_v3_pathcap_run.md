# TD Micro Reward V3 Pathfinder-Capped 100M Run

Recorded: 2026-07-14

## Result

The corrected reward-v3 environment completed a full 100M-timestep PufferLib GPU run and synced it
to W&B:

- project: `cnc1`
- run: `confused-oath-7`
- run id: `p8jxidnw`
- URL: <https://wandb.ai/kinvert-k/cnc1/runs/p8jxidnw>

The run is valid under the `start_failures == 0` SPS rule. A rolling training window reported a
nonzero win rate, and retained greedy policies learned to build infantry, attack, kill units, and
destroy one enemy building. No retained checkpoint won the deterministic seed-1 replay, and the
final checkpoint collapsed to deploy-once followed by no-op.

## Command

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
env PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 \
  LD_LIBRARY_PATH="$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib:/usr/lib/wsl/lib" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
    --wandb \
    --wandb-project cnc1 \
    --tag reward-v3-pathcap-fix-100m \
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
| Uptime | 1,481.346 s |
| Aggregate SPS | 67,506 |
| Final dashboard SPS | 84,100 |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| Hidden layers | 64x1 |
| GPU training | yes |
| Maximum `start_failures` | 0.000 |
| Maximum rolling engine `failures` rate | 0.0007765 |
| Valid by SPS rule | yes |

The nonzero engine-failure samples make this a policy-quality run rather than a clean environment
speed comparison. The local result is:

```text
PufferLib/logs/cnc_micro/p8jxidnw.json
SHA-256 1d9cf3e0f10a0859faba201d06d8cce0021ffe27f16314c390951e442cc79d96
```

Five local metric samples were retained. The sample near 38.25M steps reported the run's only
nonzero rolling win rate, `0.0001939`. The same sample reported nonzero infantry production, unit
kills, and opponent-building losses. This establishes that stochastic training trajectories can
reach a win, but it does not establish a reliable greedy policy.

## Pathfinder Deadlock And Fix

The first attempt, W&B run `visionary-pond-6` (`hc6r9zx3`), stopped making progress immediately
after checkpoint 12,584,960. All four environment workers were consuming a core in:

```text
pathfinder.findRoute -> followEdge -> Context.passable/movementType
```

Vanilla TD limits edge following with an independent 400-iteration `cellcount`. The Zig port used
the mutable route length as its only bound. Route backtracking can shorten that length, allowing a
blocked infantry route to cycle forever. The fix adds Vanilla's independent 400-step edge-follow
budget and a minimized regression using the exact failing geometry:

```text
opponent barracks  (22,41)
source             (23,42)
destination        (1,13)
result             1,7,6,6,7,7,7,7,7
```

The failed run was terminated and is excluded from throughput and training-result claims. The
corrected run passed the old deadlock point and completed to 100M.

Verification after the fix:

- Zig tests passed in Debug, ReleaseSafe, and ReleaseFast; Debug reported `86/86`.
- C ABI smoke was stable across two runs with canonical digest
  `721b67018cbc2096602e52c74b6312443cb3b82fc8b2bb8b24e3721b0448eb52`.
- PufferLib C reward/log smoke passed with zero engine failures.
- The PufferLib `cnc_micro` extension rebuilt successfully.

## Retained Checkpoints

All 97 retained checkpoints were replayed from seed 1 through the native C inference API:

- 0 won.
- 10 issued attack commands.
- 1 destroyed an opponent building.
- every replay completed without an engine failure.

The strongest retained checkpoint was at 17,827,840 steps:

```text
checkpoint  PufferLib/checkpoints/cnc_micro/p8jxidnw/0000000017827840.bin
SHA-256     4ddca2503be5b185cdbb37273ec2b65e1ad1a29673132fa86195ae881614ae29
terminal    timeout draw at 3,000 decisions
return      +0.64
production  E1=3, E3=9
combat      2,463 attacks, 1 unit kill, 1 opponent building destroyed
commands    noop=300 deploy=1 start=6 place=6 train=57 move=167 attack=2,463
invalid     631
failures    0
trace       52c58b8aad1e22c37d1ec5cb37600459fe1f3415e1575fc77deb27f4a13e9344 (twice)
```

The matching complete state-trace hashes prove deterministic replay. The final checkpoint was also
deterministic but substantially worse:

```text
checkpoint  PufferLib/checkpoints/cnc_micro/p8jxidnw/0000000099999744.bin
SHA-256     ab820ee76f984d8fbd81500eece21f5ed2a968757a609a580eee53269088a3ca
terminal    legitimate loss at 2,467 decisions
return      -0.90
commands    noop=2,466 deploy=1; all others=0
invalid     0
failures    0
trace       0c08c1b01ebdd72bd33dbb3307878d04f59094cadb7cc05b962a2681f14edb25 (twice)
```

## Finding

The environment now demonstrably supports the entire win path under training: production, movement,
attack, kills, building destruction, and at least a rare stochastic win. Simply extending the same
PPO run did not produce a stable winning greedy policy. Policy quality peaked early and then
collapsed, while incompatible MultiDiscrete tuples still caused hundreds of invalid decisions in
the best replay. The next training change should address command-conditioned action decoding and
checkpoint selection rather than spend another 100M steps with the same action heads.
