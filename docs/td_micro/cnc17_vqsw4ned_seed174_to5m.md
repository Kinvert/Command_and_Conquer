# CNC17 Invalid `vqsw4ned` Seed-174 Warm-Start Attempt

## Verdict

This run completed, but it was not a warm start. Native `train` accepted and
logged `--load-model-path` without loading it, so the run trained a fresh random
policy for 2,902,016 steps. It must not be used as continuation evidence.

- Untouched source robust perf: `0.266805`
- Fresh 2.9M-run robust perf: `0.130091`
- Training validity: valid, `start_failures=0`, `failures=0`
- Source checkpoint was not overwritten and its SHA-256 remained unchanged.

The bug was found when a subsequent `3e-6` control behaved like an untrained
policy. `PufferLib/pufferlib/pufferl.py::train` restored
`--load-training-state-path`, but had no corresponding `load_weights` call for
`--load-model-path`. CNC17 therefore says nothing about whether the source can
benefit from additional training or whether the requested learning rate is too
large.

## Inputs

- Source family: `vqsw4ned`, ABI9 MinGRU H64 L1
- Source training seed: `174`
- Source checkpoint:
  `PufferLib/checkpoints/cnc_micro/zuy67pgp/0000000002097152.bin`
- Source SHA-256:
  `63eb4dd6e4ee85307f8626c61710f08d1ce9a474ff6f9260be18dcc575b0ebcb`
- Source steps: `2,097,152`
- Requested added steps: `2,902,016`
- Actual fresh-policy exposure: `2,902,016`
- Intended cumulative target: `4,999,168` (not achieved by this run)
- Code commit: `f5c7cb8eac8f017a95fef021b398f2ed7733a9a0`
- W&B: [cnc17/divine-moon-1](https://wandb.ai/kinvert-k/cnc17/runs/nscvud8n)

Seed 174 was selected because it had the strongest locked held-out result among
the three promoted-family confirmations. Family promotion itself remains based
on the three-seed rule, not this individual seed.

## Training Command

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
env PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 \
  LD_LIBRARY_PATH=/usr/lib/wsl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project=cnc17 \
  --tag=vqsw4ned-s174-policy-warmstart-to-5m \
  --seed=174 \
  --load-model-path=/home/claude/cnc/.worktrees/td-micro-v1/PufferLib/checkpoints/cnc_micro/zuy67pgp/0000000002097152.bin \
  --save-training-state \
  --checkpoint-dir=checkpoints/cnc17_vqsw4ned_seed174_to5m \
  --log-dir=logs/cnc17_vqsw4ned_seed174_to5m \
  --checkpoint-interval=512 --eval-episodes=10000 --cudagraphs=10 \
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
  --train.total-timesteps=2902016 \
  --train.schedule-timesteps=2902016 \
  --train.learning-rate=0.001050809111017901 \
  --train.anneal-lr=1 --train.min-lr-ratio=0.0 \
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

This is the normal native CUDA training path: no `--slowly` and no CPU
training backend.

## Throughput

- Agents: `64`
- Buffers: `1`
- Threads: `4`
- Horizon: `32`
- Minibatch: `2,048`
- Replay ratio: `3.5029455311743467`
- Added timesteps: `2,902,016`
- GPU/train mode: native PufferLib CUDA, one GPU
- Final reported SPS: `43,226`
- `start_failures=0`, `failures=0`
- SPS claim validity: valid

## Locked Evaluation

Both policies use `cnc14-promotion-v1`: eval seed `19173`, 512 exact close
episodes, 512 exact medium episodes, four buffers, four threads, and zero
reward shaping during evaluation.

| Checkpoint | Close | Medium | Balanced | Robust |
|---|---:|---:|---:|---:|
| Source at 2M | `0.238281` (122/512) | `0.302734` (155/512) | `0.270508` | `0.266805` |
| Fresh 2.9M run | `0.082031` (42/512) | `0.283203` (145/512) | `0.182617` | `0.130091` |

The fresh-run result is valid on its own terms, with `start_failures=0`,
`failures=0`, and exact episode-row SHA-256
`fdaac319f57a89ff60afc2e6a575ee7974a35f53e414b42cfdc5bc3b682a5fc8`.
It is not a valid before/after continuation comparison.

## Outputs

- Training run ID: `nscvud8n`
- Training log:
  `PufferLib/logs/cnc17_vqsw4ned_seed174_to5m/cnc_micro/nscvud8n.json`
- Training-end policy:
  `PufferLib/checkpoints/cnc17_vqsw4ned_seed174_to5m/cnc_micro/nscvud8n/0000000002902016.bin`
- Training-end policy SHA-256:
  `94728f8d1fcf572cb366f688d447971f8edc1a9ba3de66b90955199727743a21`
- Exact future-continuation state for the unrelated fresh trajectory:
  `PufferLib/checkpoints/cnc17_vqsw4ned_seed174_to5m/cnc_micro/nscvud8n/0000000002902016.state`
- State SHA-256:
  `45440b0a76e4a4aeae1322923a6fb4a11c025ebd763f28df8cc41753eef0f64e`
- Fixed evaluation summary:
  `PufferLib/logs/cnc17_vqsw4ned_seed174_to5m/cnc_micro/nscvud8n_fixed_eval_seed19173.json`

The normal training loop also emitted policy files labelled `3147776` and
`4196352` while running its post-training evaluation. They have the same
SHA-256 as the `2902016` policy because no optimization occurs during that
phase. Use `2902016.state` as the actual end-of-training continuation point.

## Conclusion

Do not replace the promoted 2M checkpoint with this result. The native training
loader must be fixed and verified with a zero-learning-rate byte-identity gate
before rerunning any policy-only continuation study. A historical `.bin` still
cannot provide exact optimizer/RNG continuation, but it can support a genuine
policy-weight warm start once the loader is active.
