# CNC18-CNC20 Late-LR Warm-Start Study

## Result

Yes: the promoted-family seed-174 policy improves when it is genuinely loaded
and fine-tuned at a learning rate appropriate for the end of its original
schedule.

- Best result: add 1,048,576 steps at fixed LR `1e-5`.
- Source cumulative steps: `2,097,152`.
- Best-policy cumulative steps: `3,145,728`.
- Combined two-suite robust perf: `0.257776 -> 0.281902` (`+9.4%` relative).
- A cosine `1e-5 -> 0` extension remains better than source at 4,999,168
  cumulative steps, but is weaker than the +1M checkpoint.
- Fixed `1e-5` through 5M overtrains and loses the gain.

The best checkpoint is a single-seed research leader, not a replacement for
the three-training-seed promoted family. Replicate this recipe across training
seeds before changing the canonical promotion record.

## Warm-Start Bug

The initial CNC17 attempt was invalid. Native `train` accepted
`--load-model-path` in its config but never called `backend.load_weights`, so it
trained a fresh random policy. The tiny-LR control exposed the problem because
it behaved exactly like an untrained policy.

Commit `4b60671` fixes native training warm starts and adds a regression test.
Exact `.state` resume remains a separate path, and specifying both checkpoint
types is rejected as ambiguous.

Verification:

- Unit test failed before the fix and passes afterward.
- A one-epoch zero-LR warm start saved policy SHA-256
  `63eb4dd6e4ee85307f8626c61710f08d1ce9a474ff6f9260be18dcc575b0ebcb`,
  exactly matching the source.
- The native CUDA split/resume gate remains exact. Its accepted policy and
  trace hashes are unchanged.
- The normal CLI split/resume gate remains exact.
- The winning +1M run was replayed from clean commit `4b60671`; both policy and
  complete `.state` hashes matched the original run exactly.

## Source

- Candidate family: `vqsw4ned`, ABI9 MinGRU H64 L1
- Training seed: `174`
- Checkpoint:
  `PufferLib/checkpoints/cnc_micro/zuy67pgp/0000000002097152.bin`
- SHA-256:
  `63eb4dd6e4ee85307f8626c61710f08d1ce9a474ff6f9260be18dcc575b0ebcb`
- Original base LR: `0.001050809111017901`
- Original schedule: cosine to zero over 2,097,152 steps

The winning fine-tuning LR, `1e-5`, is about 0.95% of the original peak LR.
Restarting the original peak LR is not a meaningful late-stage continuation.

## Study Shape

Every training run held these fixed:

- Native PufferLib CUDA backend, one GPU; no `--slowly` and no CPU trainer
- 64 agents, one buffer, four threads
- Horizon 32, minibatch 2,048
- Replay ratio `3.5029455311743467`
- Top-level seed 174, train seed 42, environment seed 1
- ABI9, identical rewards, observations, actions, and environment rules
- `start_failures=0`, `failures=0`

The four +1M trials changed only fixed learning rate: `3e-6`, `1e-5`, `3e-5`,
and `1e-4`.

## Winning Command

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
env PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 \
  LD_LIBRARY_PATH=/usr/lib/wsl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project=cnc18 \
  --tag=vqsw4ned-s174-warmstart-1m-lr1e-5-fixed-loaderfix \
  --seed=174 \
  --load-model-path=$PWD/checkpoints/cnc_micro/zuy67pgp/0000000002097152.bin \
  --save-training-state \
  --checkpoint-dir=checkpoints/cnc18_fixed_lr1e-5 \
  --log-dir=logs/cnc18_fixed_lr1e-5 \
  --checkpoint-interval=512 --eval-episodes=64 --cudagraphs=10 \
  --vec.total-agents=64 --vec.num-buffers=1 --vec.num-threads=4 \
  --env.seed=1 --env.max-decisions=12000 --env.action-abi=9 \
  --env.reward-milestone=0.2 \
  --env.reward-player-infantry=0.023557773160741098 \
  --env.reward-enemy-unit-loss=0.011135930523537963 \
  --env.reward-enemy-building-loss=0.0 \
  --env.reward-player-unit-loss=-0.0037895242163774644 \
  --env.reward-refinery=0.0 --env.reward-first-delivery=0.0 \
  --env.reward-tiberium-income=0.017023407771955025 \
  --env.reward-invalid-action=0.0 \
  --policy.hidden-size=64 --policy.num-layers=1 \
  --policy.expansion-factor=1 \
  --torch.network=MinGRU --torch.encoder=Normalize255Encoder \
  --torch.decoder=DefaultDecoder \
  --train.gpus=1 --train.seed=42 \
  --train.total-timesteps=1048576 \
  --train.schedule-timesteps=1048576 \
  --train.learning-rate=0.00001 --train.anneal-lr=0 \
  --train.min-lr-ratio=0.0 \
  --train.gamma=0.9683312187368112 \
  --train.gae-lambda=0.2990261235331877 \
  --train.replay-ratio=3.5029455311743467 \
  --train.clip-coef=1.0 --train.vf-coef=5.0 \
  --train.vf-clip-coef=4.5591941978708 \
  --train.max-grad-norm=0.37930584235159936 \
  --train.ent-coef=0.0017508734135523291 \
  --train.anneal-ent-coef=0 --train.min-ent-coef-ratio=0.1 \
  --train.beta1=0.9928911247307971 \
  --train.beta2=0.9984803215030886 --train.eps=0.0001 \
  --train.minibatch-size=2048 --train.horizon=32 \
  --train.vtrace-rho-clip=4.176526376541711 \
  --train.vtrace-c-clip=0.2585496798908753 \
  --train.prio-alpha=0.032941403802958846 \
  --train.prio-beta0=0.9909711001472885 \
  --train.checkpoint-interval=512
```

## Learning-Rate Screen

The deterministic screen used eval seed 19173 and 128 exact episodes per
profile for every policy. These results selected candidates but did not decide
promotion.

| Policy | Close | Medium | Balanced | Robust |
| --- | ---: | ---: | ---: | ---: |
| Source | `0.210938` | `0.312500` | `0.261719` | `0.252228` |
| +1M, fixed `3e-6` | `0.296875` | `0.351562` | `0.324219` | `0.321982` |
| +1M, fixed `1e-5` | `0.328125` | `0.281250` | `0.304688` | `0.302942` |
| +1M, fixed `3e-5` | `0.242188` | `0.328125` | `0.285156` | `0.278901` |
| +1M, fixed `1e-4` | `0.226562` | `0.328125` | `0.277344` | `0.268369` |

The full suite rejected the apparent `3e-6` lead. This is another concrete
example of why a small dashboard or screen result is not promotion evidence.

## Full Evaluation

Each row below contains 512 exact close and 512 exact medium episodes. Seed
19173 is the locked promotion suite. Seed 29173 was not used to choose the
learning rate and acts as a fresh confirmation.

| Policy / suite | Close | Medium | Balanced | Robust |
| --- | ---: | ---: | ---: | ---: |
| Source / 19173 | `0.238281` | `0.302734` | `0.270508` | `0.266805` |
| +1M fixed `1e-5` / 19173 | `0.257812` | `0.304688` | `0.281250` | `0.279364` |
| Source / 29173 | `0.230469` | `0.269531` | `0.250000` | `0.248533` |
| +1M fixed `1e-5` / 29173 | `0.269531` | `0.300781` | `0.285156` | `0.284329` |

Combined over both suites:

| Policy | Close | Medium | Balanced | Robust |
| --- | ---: | ---: | ---: | ---: |
| Source | `0.234375` | `0.286133` | `0.260254` | `0.257776` |
| +1M fixed `1e-5` | `0.263672` | `0.302734` | `0.283203` | `0.281902` |

The candidate gains 30 close wins and 17 medium wins across the 2,048 exact
episodes. Both profile rates improve, so the robust-score gain is not produced
by trading one spawn profile against the other.

## Five-Million-Step Follow-Up

Two corrected runs loaded the same source and added 2,902,016 steps, reaching
4,999,168 cumulative policy steps.

- CNC19: fixed LR `1e-5`; final screen robust `0.246244`. It overtrained.
- CNC20: cosine LR `1e-5 -> 0`; final screen robust `0.280969`.

CNC20 full evaluation:

| Policy / suite | Close | Medium | Balanced | Robust |
| --- | ---: | ---: | ---: | ---: |
| Source / 19173 | `0.238281` | `0.302734` | `0.270508` | `0.266805` |
| 5M cosine / 19173 | `0.250000` | `0.298828` | `0.274414` | `0.272318` |
| Source / 29173 | `0.230469` | `0.269531` | `0.250000` | `0.248533` |
| 5M cosine / 29173 | `0.253906` | `0.298828` | `0.276367` | `0.274605` |

The 5M cosine policy has combined robust perf `0.273466`, a 6.1% relative
gain over source, but it does not beat the +1M fixed-LR policy's `0.281902`.

## Throughput

All claims are valid native CUDA runs with `start_failures=0` and `failures=0`.

| Run | Added steps | Agents / buffers / threads | Horizon / minibatch | SPS |
| --- | ---: | --- | --- | ---: |
| CNC18 +1M fixed `1e-5` | `1,048,576` | `64 / 1 / 4` | `32 / 2,048` | `43,540` |
| CNC19 to 5M fixed `1e-5` | `2,902,016` | `64 / 1 / 4` | `32 / 2,048` | `43,155` |
| CNC20 to 5M cosine `1e-5 -> 0` | `2,902,016` | `64 / 1 / 4` | `32 / 2,048` | `44,194` |

CNC19 and CNC20 use the winning command above with
`train.total_timesteps=train.schedule_timesteps=2902016`; CNC19 keeps
`train.anneal_lr=0`, while CNC20 sets `train.anneal_lr=1`. Their exact complete
configs are stored in the run JSON files listed below.

## Artifacts

Best +1M policy:

- W&B: [cnc18/clear-bee-3](https://wandb.ai/kinvert-k/cnc18/runs/2yr8pk7z)
- Policy:
  `PufferLib/checkpoints/cnc18_fixed_lr1e-5/cnc_micro/2yr8pk7z/0000000001048576.bin`
- Policy SHA-256:
  `0a39da80dbac5575cb398fd3590150e7531324352b2019eefe489cffa52ea5b0`
- Full state:
  `PufferLib/checkpoints/cnc18_fixed_lr1e-5/cnc_micro/2yr8pk7z/0000000001048576.state`
- State SHA-256:
  `4956d7c1d8058c9a7de1e9cf1a06b1926a3ad4e12cdabff9cee53461edb0178c`
- Exact replay copies have the same hashes under
  `PufferLib/checkpoints/cnc18_replay_lr1e-5/`.
- Run config and metrics:
  `PufferLib/logs/cnc18_fixed_lr1e-5/cnc_micro/2yr8pk7z.json`
- Full evaluations:
  `PufferLib/logs/cnc18_lr_study/lr1e-5_s174_seed19173_ep512.json` and
  `PufferLib/logs/cnc18_lr_study/lr1e-5_s174_seed29173_ep512.json`

Five-million-step cosine policy:

- W&B: [cnc20/stellar-sky-1](https://wandb.ai/kinvert-k/cnc20/runs/qeg2yoxy)
- Policy:
  `PufferLib/checkpoints/cnc20_lr1e-5_cosine_to5m/cnc_micro/qeg2yoxy/0000000002902016.bin`
- Policy SHA-256:
  `a11ad10b07e87460d54ad72e955eacf691cefde475ad308c6c3ec1e86c51ff5d`
- Full state SHA-256:
  `04b377e19a9304f70c751c19809f07464b49286fee1983160f294e4da67a5add`
- Run config and metrics:
  `PufferLib/logs/cnc20_lr1e-5_cosine_to5m/cnc_micro/qeg2yoxy.json`

## Next Gate

Run the +1M fixed-`1e-5` recipe from the seed-173 and seed-175 `vqsw4ned`
checkpoints, then evaluate all three training seeds on both full suites. Promote
the continuation recipe only if the family median and worst-profile gates beat
the current promoted family. Do not select another LR using these same two
evaluation seeds.
