# TD Micro Compact Observation And Sweep Slots

Date: 2026-07-17

Status: accepted for throughput and determinism; compact-ABI hyperparameters still require retuning

## Summary

Two independent throughput changes are retained:

1. ABI 9 replaces the repeated 4,096-byte map observation with 344 dynamic Tiberium bytes and a
   scenario id. Observation size falls from 6,208 to 2,456 bytes.
2. PufferLib sweeps can run multiple logical worker slots on each physical GPU. Three workers on
   GPU 0 improved aggregate machine throughput by 36.45% in the official fixed-workload smoke.

The compact observation preserves fixed-action simulation outcomes and world digests exactly. It
does change the policy input tensor, so old checkpoints are rejected by size and new policies must
be trained from scratch.

## ABI 9 Observation

| Region | ABI 8 bytes | ABI 9 bytes | ABI 9 meaning |
| --- | ---: | ---: | --- |
| Globals | 64 | 64 | Existing public state plus scenario id at byte 32 |
| Map/resource | 4,096 | 344 | One byte for each initially authored Tiberium cell |
| Own entities | 1,024 | 1,024 | Unchanged 64 x 16-byte records |
| Enemy entities | 1,024 | 1,024 | Unchanged 64 x 16-byte records |
| Total | 6,208 | 2,456 | 60.44% fewer transported elements |

The Tiberium positions are generated in deterministic row-major order from the immutable Vanilla
scenario-1 map fixture. Zig and Vanilla both use that generated order. A live resource cell keeps
the legacy packed value `45`; a depleted cell keeps the legacy clear/buildable value `56`. Static
terrain and occupancy are omitted because terrain is fixed for this scenario and occupancy is
already represented by entity records.

At hidden size 64, the input matrix falls from 397,312 to 157,184 weights. The complete policy falls
from 427,520 to 187,392 weights, and an exact FP32 checkpoint falls from 1,710,080 to 749,568 bytes.

Generated artifact hashes:

```text
scenario1_map.zig       a40a56ceb69468929eb74ecc4ba6d374b2470a0caceecd28e4140e78aa4243cd
scenario1_tiberium.h    12b896c735c238453bbb843c366a54234db84f78d6d210a9f432b95f00fdb62a
```

Regenerating both outputs twice produced the same bytes.

## TDD And Determinism Gates

Tests were introduced against the compact symbols and layout before the implementation. The final
suite passes 153/153 tests in Debug and ReleaseFast. It covers:

- ABI/version/size constants and exact old-checkpoint rejection;
- canonical Tiberium ordering, depletion, and reappearance;
- unchanged own/enemy entity record bytes;
- observation purity through an unchanged pre/post world digest;
- projection of the immutable real-Vanilla ABI-4 executable fixture into ABI 9; and
- shared Zig/Vanilla generated-cell order and packed-value semantics for the compact representation.

The legacy ABI-4 encoder remains test-only code so the immutable executable fixture does not need to
be rewritten. The compact projection test is therefore anchored transitively to real executable
bytes without replacing historical evidence. The legacy encoder is not exposed through the current
C API or Puffer environment.

The C API smoke passed with ABI 9 and reported:

```text
abi=9 obs=2456 mask=279 worlds=2 decisions=2
digest=cdde069f...ece4f
```

The economy C smoke completed 900 decisions with one Refinery, one Harvester, 675 harvested credits,
one first-delivery milestone, zero invalid actions, and zero failures. The Puffer binding smoke
reported `episode_return=0.250 draw_rate=1`. The Vanilla human target, Remastered shared library,
and headless TD smoke all built or ran successfully.

## Native Fixed-Action A/B

Both binaries were pinned to CPU 0 and alternated A-B-A-B. Each run used 64 worlds and 32,768
iterations, for 2,097,152 decisions:

```bash
taskset -c 0 /tmp/td_micro_batch_benchmark_obs_v4 64 32768
taskset -c 0 /tmp/td_micro_batch_benchmark_obs_v5 64 32768
```

Comparison artifact SHA-256 values:

```text
ABI-8 static library      a70d9b1551cc1005b8ab0d48d5de407fae5ba0d6d1a61186518069ec5a3d1c5a
ABI-9 static library      d6a7abce2549304edd91c11f0c483ce6912a3c09398a69c14aa973eb10ab6f92
ABI-8 Puffer extension    2b11bbe0edf00f17b3b4e791cf5a8b4b279f00d0e750e3aef61f14042d0df52d
ABI-9 Puffer extension    33204a1642a02cf628380ab57750ab4996b3322ad4ecffa089e457d94ac16a26
```

| Build | Run 1 SPS | Run 2 SPS | Mean SPS | Change |
| --- | ---: | ---: | ---: | ---: |
| ABI 8 / 6,208 bytes | 204,626.111 | 203,837.624 | 204,231.868 | baseline |
| ABI 9 / 2,456 bytes | 215,350.487 | 214,626.056 | 214,988.272 | +5.27% |

Every run completed 672 episodes, all losses, with zero failures and the exact digest:

```text
5b1054c53678200eb794ae9c2d351b0adc17cad4315539051b8175146a53a879
```

This is the simulator apples-to-apples speed claim because the action stream and outcomes are fixed.
An earlier independent A-B-A-B measured 205,803.524 versus 216,212.416 SPS, or +5.06%, so the gain
reproduced across both adjacent series.

## PufferLib CUDA Result

The accepted ABI-9 single run used:

```bash
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 --vec.num-buffers 4 --vec.num-threads 4 \
  --train.total-timesteps 1048576 --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

| Result | Value |
| --- | ---: |
| Reported SPS | 91,575 |
| Aggregate `agent_steps / uptime` | 97,856.622 SPS |
| Uptime | 10.7154 s |
| Balanced performance | 0.155449 |
| Start failures | 0.000 |
| Engine failures | 0.000 |

Log: `PufferLib/logs/cnc_micro/1784347201969.json`.

The adjacent ABI-8 pair averaged 90,435 aggregate SPS, so this one ABI-9 run was 8.21% faster. That
comparison is behavior-dependent; the fixed-action native result is the authoritative subsystem
speedup. The old ABI reached 0.296 balanced performance at 1M under these defaults, so the compact
ABI is not learning-equivalent under hyperparameters tuned for the old fan-in and must be retuned.

## Rejected Numeric Encoding

The first compact prototype encoded Tiberium as `255` present and `0` depleted. It reached roughly
98K aggregate SPS, but its 5M policy collapsed to zero balanced performance and near-zero entropy.
The larger normalized resource activations also changed the effective initialization scale after
the input fan-in reduction. This encoding was rejected.

Preserving the old packed values (`45` and `56`) restored nonzero wins and policy entropy at 1M. A
5M run is not used as the acceptance gate because the current independent-head action ABI has an
already documented long-schedule collapse under both ABI 8 and ABI 9. The old-ABI 5M control also
collapsed to 0.00575 balanced performance. That action/optimizer issue is tracked separately in
`docs/td_micro/promoted_bzo_collapse_root_cause.md`.

## Concurrent Sweep Workers

`sweep.workers_per_gpu` is a generic scheduler setting with a default of one. Logical worker slots
are now separate from physical GPU ids, so several trainers can safely share one GPU without
colliding in the scheduler's active-work table. For multiple GPUs, physical GPU groups are repeated
in deterministic order. Only DDP rank zero reports a trial result. The scheduler-only key is
removed before constructing the sweep optimizer, and the parent drains every active slot in the
final partial/full batch before returning.

The acceptance run launched three fixed 1,048,576-step trials on GPU 0 with the same per-trial CUDA
configuration as the single run:

```bash
.venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --sweep.max-runs 3 --sweep.gpus 1 --sweep.workers-per-gpu 3 \
  --train.gpus 1 --train.total-timesteps 1048576 \
  --vec.total-agents 64 --vec.num-buffers 4 --vec.num-threads 4 \
  --train.horizon 32 --train.minibatch-size 2048 \
  --policy.hidden-size 64 --policy.num-layers 1
```

All sweepable paths were excluded for this scheduler acceptance, so all three trials used an exact
fixed configuration.

| Slot | Log | Reported SPS | Aggregate SPS | Uptime |
| ---: | --- | ---: | ---: | ---: |
| 0 | `1784347351121.json` | 45,681 | 44,602.842 | 23.5092 s |
| 1 | `1784347351167.json` | 42,498 | 44,655.812 | 23.4813 s |
| 2 | `1784347351156.json` | 43,400 | 44,265.592 | 23.6883 s |
| Combined | | 131,579 | 133,524.246 | |

Compared with the adjacent single-run aggregate of 97,856.622 SPS, three workers improve aggregate
machine throughput by **36.45%**. Summed reported SPS improves by 43.68%. All three runs had zero
start and engine failures and the exact final gameplay metric fingerprint
`bb1d6884e18c8d67`. Each produced balanced performance `0.15544871985912323`.

This is a sweep-throughput gain, not a claim that one policy trains faster. Three workers are the
measured setting for the current 64x1 model on this 8-core/16-thread host and 8 GB GPU; larger models
can require fewer workers due to VRAM and CPU limits.

Code review after that throughput run found that the parent could return after collecting only the
first result from its final batch. The three child logs remain valid as a machine-throughput
measurement, but that launch was not sufficient scheduler-result acceptance. A red unit test pinned
the final sequence `(active, completed) = (3,0), (2,1), (1,2)` and the loop was changed to drain all
three before exit. The post-fix CUDA integration used three fixed 262,144-step trials and returned
exit 0 only after all three TUI results were printed:

```text
1784348846999.json  final SPS 43,937  agent_steps 262,144  failures 0/0
1784348846984.json  final SPS 45,560  agent_steps 262,144  failures 0/0
1784348847002.json  final SPS 48,517  agent_steps 262,144  failures 0/0
```

The scheduler unit suite now passes 6/6 tests, including final-batch drain, failed-run slot
replacement, and rank-zero-only DDP reporting. The sandbox-only CUDA-unavailable attempt is invalid
and is not a throughput result.

## Next Gate

Retune learning rate and related optimizer settings for ABI 9 before promoting a policy. After that,
profile a representative trained-policy action trace and target repeated reward/metric scans or
remaining route/target lookups. Do not spend another 5M run on the current independent-head action
ABI until its long-schedule collapse is resolved.
