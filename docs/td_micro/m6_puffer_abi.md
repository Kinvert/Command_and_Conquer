# TD Micro PufferLib ABI And GPU Training Gate

Recorded: 2026-07-14

Historical note: this document records the ABI-2/ABI-4 M6 gate. The live economy environment is
ABI 7; see `docs/td_micro/refinery_harvester_economy.md`. The retained ABI-6 champion remains
documented separately and was not modified by the economy expansion.

Status: the native Zig-to-PufferLib vertical slice and first visible checkpoint transfer are valid.
The reduced Zig simulator steps the full supported Easy-AI match, packs state observations and action
masks, applies one player command, advances four TD frames, emits reward/terminal state, and resets
contiguous worlds. Repeated GPU training runs exceed the 50,000 SPS performance gate with zero
startup or engine failures. An ABI4 checkpoint from the aligned 1,800-decision training contract also
completed an unattended rendered Vanilla TD match; see `docs/td_micro/m6_visible_policy_transfer.md`.

## Correctness Baseline

The shared 64-building ruleset was regenerated through the Vanilla oracle after the first sustained
Puffer run exposed the old 32-slot hard capacity. Every fixture was recorded twice in fresh Vanilla
processes and compared byte-for-byte before installation.

```text
ruleset manifest SHA-256    2cfdb59512771054eb4bf7a4b8b5111fc722b4a1ed5f415c7a172c47d75b9818
generated Zig SHA-256       b1834b414cfdf4b83e5cfacc438c2abd6d4b37868375f726809e6b670bea08fd
generated C SHA-256         6f5c512e9b1b28038ab4e945e419095dcd898d920a71b49b57b67d0249f0a830
opening digest              837ccd9cad6e1d19c9a577330ec0b770aeeee5a110d915691cdf24c362a3736d
terminal fixture SHA-256    4d3e3228139de9af7125cfb540aa677dbe3b324b20111e9ee17182613148a3d2
terminal frame              8358
terminal outcome            player defeat
```

All 73 tests pass in Debug, ReleaseSafe, and ReleaseFast. This includes exact scalar/batch digest
parity, deterministic masked-action fuzzing, the complete closed-loop Easy-AI trace, a physical
64-slot capacity test, task-level soft-death terminal tests, and focused reward-shaping tests.

## ABI History And Current Contract

The three-repeat benchmark below was captured with ABI v2. The current working tree is ABI v4: v3
changed entity IDs to owner-local canonical IDs for Vanilla transfer, and v4 added named
infantry-limit and invalid-streak loss counters. Observation size, action heads, action mask, and
checkpoint tensor shape did not change. The later M6-aligned run validates the current ABI4 path.

The static library is `td-micro/zig-out/lib/libtd_micro.a`; its public header is
`td-micro/include/td_micro_api.h`. One C call advances a contiguous batch of worlds without Vanilla,
`dlopen`, per-entity callbacks, or hot-path allocation.

Action heads:

```text
command       9
actor        65
product       5
target_kind   4
target_x     64
target_y     64
target_slot  64
mask bytes  275
```

The 6,208-byte observation is:

```text
64 bytes      globals and player production state
4096 bytes    packed 64x64 map
1024 bytes    64 own entity slots x 16 bytes
1024 bytes    64 enemy entity slots x 16 bytes
```

Each map byte contains land type, passability, buildability, visibility, and two-bit occupancy.
The observation is intentionally AI-style and fully observable for supported simulation entities.
It excludes the opponent controller's private timers, selected build products, credits, power, and
RNG bookkeeping.

Independent MultiDiscrete masks cannot encode every cross-head dependency. An incompatible assembled
tuple is therefore a deterministic no-op and increments `invalid_actions`; this is not an engine
failure.

Native C smoke result:

```text
abi=4 obs=6208 mask=275 worlds=2 decisions=2
digest=a2ed292eae3a17e9fb925a60c775b1b7c9d0e1473ca53616c4365e206d663ad2
```

## Death And Failure Semantics

The following section records the contract used for the M6 run. The current reward-v3 contract
disables the rejected-command terminal while retaining its ABI field; see
`docs/td_micro/policy_win_path_and_reward_v3.md`.

TD Micro v1 has a soft task limit of 16 active player buildings. Placing a 17th building emits a
terminal, gives `-1.0`, increments both `losses` and `building_limit_losses`, and resets the world.
This discourages a degenerate structure-spam policy.

Two additional anti-degenerate terminals use the same `-1.0` policy-loss path:

- a 65th active player infantry increments `infantry_limit_losses`;
- 128 consecutive rejected command tuples increments `invalid_streak_losses`.

Any accepted command, including no-op, clears the invalid-command streak. All three conditions reset
normally and leave engine `failures` unchanged.

The current training curriculum awards `+0.1` once for each of Construction Yard, Power Plant,
Barracks, E1, and E3. It does not terminate when those milestones are complete. Each player-owned E1
or E3 death costs `-0.001` exactly once; opponent deaths and MCV deployment do not incur that
penalty. A terminal decision emits the exact terminal result and replaces shaping on that decision.
The batch wrapper keeps the per-episode death ledger outside canonical world state, so reward
bookkeeping cannot alter simulation digests or Vanilla parity.

The simulator separately reserves 64 physical building slots. Exhausting fixed storage,
unsupported content, or startup failure increments `failures` and invalidates a benchmark. These
conditions are never relabeled as policy losses. Unsupported behavior and implementation defects
remain structured and loud.

## GPU Benchmark

These results remain the valid ABI-v2 performance baseline, not a post-ABI-v4 claim.

All three repetitions used this command from `PufferLib/`:

```bash
export VENV_NVIDIA="$PWD/.venv/lib/python3.12/site-packages/nvidia"
export EXTRA_LIBS="/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib"
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 4 \
  --vec.num-threads 4 \
  --train.total-timesteps 1048576 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 100000000 \
  --eval-episodes 1
```

| Run | SPS | Training uptime | `start_failures` | Engine `failures` | Valid |
| --- | ---: | ---: | ---: | ---: | --- |
| 1 | 100,289 | 10.787 s | 0.000 | 0.000 | yes |
| 2 | 104,543 | 10.619 s | 0.000 | 0.000 | yes |
| 3 | 101,501 | 10.626 s | 0.000 | 0.000 | yes |
| Mean | 102,111 | 10.677 s | 0.000 | 0.000 | yes |

Raw dashboard logs:

- `docs/td_micro/benchmarks/cnc_micro_gpu_1m_repeat1.log`
- `docs/td_micro/benchmarks/cnc_micro_gpu_1m_repeat2.log`
- `docs/td_micro/benchmarks/cnc_micro_gpu_1m_repeat3.log`

Every captured interval reports zero startup and engine failures. Some intervals report intentional
building-limit losses, demonstrating that the new death terminal is active and separately
accounted. The minimum repeated result is 2.0x the 50,000 SPS gate.

## Current ABI4 M6-Aligned Run

The current reward and timeout contract was trained once more with `max_decisions=1800`, ABI4,
reward-v2 shaping, and checkpoint retention every 512 epochs. All other benchmark-shape settings
remained 64 agents, four buffers, four threads, horizon 32, minibatch 2,048, and hidden 64x1 on GPU.

| Timesteps | SPS | Uptime | `start_failures` | Engine `failures` | Valid |
| ---: | ---: | ---: | ---: | ---: | --- |
| 1,048,576 | 102,519 | 10.279 s | 0.000 | 0.000 | yes |

Result log:

```text
PufferLib/logs/cnc_micro/1784062135168.json
SHA-256 17178f647dce9c406fbcb4eac602b51a24fc858dc2df8501e0fa2b97e9d1505b
```

Selected checkpoint:

```text
PufferLib/checkpoints/cnc_micro/1784062135168/0000000001048576.bin
SHA-256 e67950993827b5f72951943e71b5c62cef15787bbfd52a220830f40bc61c7765
```

The exact checkpoint was replayed twice through the native C API. Both state traces had SHA-256
`691691dd5919565db3d2fdaadf1066c0be2292c9dc3ee101a9486524e016f8bb`, terminated at decision 902
with the same building-limit loss, and reported zero engine failures.

## Rejected Preliminary Run

Before the capacity correction, a 262,144-step run displayed about 72.1K SPS but hit
`capacity_overflow`. It is invalid and is not a performance baseline. Limiting action choices or
looking only at the final interval would have hidden the defect; the batch failure counter is the
reason the run was rejected.

## Next Gate

The reduced-simulator throughput target and M6 visible transfer gate are complete. The next gate is
policy quality: resolve the reward-scale issue, learn Barracks/E1/E3 production, and avoid repeated
structure spam before attempting held-out win-rate claims.
