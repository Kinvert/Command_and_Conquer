# `cnc_micro` Reward Sweep Readiness

Date: 2026-07-15

Status: ready for the ABI-8 PufferLib GPU economy reward sweep.

ABI-8 update: 2026-07-16. Observation version 4 and policy dimensions are unchanged. The reward
configuration now separates Refinery completion and first delivery from the generic milestone
coefficient.

Execution update: 83 valid one-million-step trials completed before the sweep stopped. The winner,
its retained reproduction, native evaluation, real Vanilla transfer, and next gates are recorded in
`docs/td_micro/cnc3_abi8_policy_status.md`.

## Sweep Contract

| INI key | Default | Sweep min | Sweep max |
| --- | ---: | ---: | ---: |
| `reward_refinery` | 0.4 | 0.0 | 0.6 |
| `reward_first_delivery` | 0.2 | 0.0 | 0.4 |
| `reward_tiberium_income` | 0.01 | 0.0 | 0.02 |

The values live in `PufferLib/config/cnc_micro.ini`. The current `sweep_only` limits Protein's
search space to the final three economy fields; policy, optimizer, vectorization, combat rewards,
and rollout settings stay constant. The original sweep metric was `score`, which is win rate minus
loss rate, rather than shaped episode return. As of `92c836e`, current sweeps optimize binary
`perf`; historical runs retain their original `score` values.

The raw C API defaults preserve ABI-7 behavior: `reward_refinery=0.2` replaces the two old
`0.1` Refinery/Harvester milestone rewards, and `reward_first_delivery=0.1` replaces the old first
delivery milestone reward. The Puffer INI uses `0.4` and `0.2` because its retained
`reward_milestone=0.2` training baseline previously produced those aggregate values.

Positive coefficients must be finite and in `[0, 1]`; the loss coefficient must be finite and in
`[-1, 0]`. Invalid startup configuration is rejected before any environment buffer starts. Terminal
rewards (`+1` win, `-1` loss, `0` draw) and reward-count caps remain fixed and are not sweep inputs.

The binding reads configuration once in `my_vec_init`, validates one eight-float
`TdMicroRewardConfig`, and passes it through the C ABI into every Zig batch. There is no INI
parsing, allocation, or validation in the step loop. The original `td_micro_batch_create` API still
constructs the exact default reward contract.

Protein's small Gaussian-process optimizer is explicitly CPU-backed for this config because CUDA
tensors cannot safely cross the WSL multiprocessing spawn boundary. Training remains on CUDA with
`--train.gpus 1`.

## Determinism And Tests

`zig build test` passes. The focused reward tests establish:

- all eight default values are exact;
- each coefficient independently reaches its intended reward path;
- a default and `reward_milestone=0.25` batch produce rewards `0.1` and `0.25` while their canonical
  simulation digests remain equal;
- negative positive-reward values, positive loss penalties, values outside `[-1, 1]`, and NaN are
  rejected.

The default C API smoke retains the ABI-7 economy baseline world digest under ABI 8:

```text
7b12c606e590f9f35de2a353b38af28953a10217f5f7853995ad691d1622eb92
```

The Puffer C binding smoke rejects an invalid config and reports the configured milestone path:

```text
episode_return=0.250 draw_rate=1
```

The sweep parser regression also passes. It prevents scalar `match_enemy_*` metadata inherited from
`default.ini` from being treated as malformed hyperparameters. Resolved ABI-8 `cnc_micro` sweep
dimensions are exactly:

```text
env/reward_refinery
env/reward_first_delivery
env/reward_tiberium_income
```

## Historical GPU Train Smoke

This pre-ABI-8 smoke established the fixed CUDA/vector training shape. It did not exercise the
three-field economy reward sweep and is retained only as a throughput reference.

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export EXTRA_LIBS="$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib:/usr/lib/wsl/lib"
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --env.max-decisions 128 \
  --vec.total-agents 64 \
  --vec.num-buffers 4 \
  --vec.num-threads 4 \
  --train.total-timesteps 65536 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

Result: 65,536 steps, final displayed 76,107 SPS, `start_failures=0`, engine `failures=0`, valid.
Log: `PufferLib/logs/cnc_micro/1784133540214.json`.

## Historical GPU Sweep Smoke

This pre-ABI-8 sweep varied the older five-field reward contract. It is not evidence for the current
three-field economy sweep and is retained only to document the launcher behavior: PufferLib reaches
a genuinely sampled trial after its two default bootstrap trials.

```bash
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --sweep.max-runs 3 \
  --sweep.gpus 1 \
  --train.gpus 1 \
  --env.max-decisions 128 \
  --vec.total-agents 64 \
  --vec.num-buffers 4 \
  --vec.num-threads 4 \
  --train.total-timesteps 65536 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

| Trial | Historical reward tuple: milestone / infantry / unit / building / loss | SPS | Start failures | Engine failures |
| --- | --- | ---: | ---: | ---: |
| Bootstrap 1 | `0.1 / 0.01 / 0.1 / 0.5 / -0.001` | 90,477 | 0 | 0 |
| Bootstrap 2 | `0.1 / 0.01 / 0.1 / 0.5 / -0.001` | 89,020 | 0 | 0 |
| Sampled | `0.065890 / 0.033211 / 0.134527 / 0.509115 / -0.007253` | 90,393 | 0 | 0 |

Logs: `1784133810992.json`, `1784133814233.json`, and `1784133817339.json` under
`PufferLib/logs/cnc_micro/`.

All three trials are valid. The 128-decision timeout is smoke-only, so these short-run SPS numbers
are launcher validation rather than the full 12,000-decision training baseline.
