# TD Micro Occupancy And AI Base Optimization

Date: 2026-07-17
Status: committed and verified natively and through PufferLib CUDA training
Implementation commit: `eef90b7c4ff6fba10d4519a3e421341e47b933c4`
Source-equivalent baseline commit: `0ee9239fb043de6ef6900290b2cb41414a46c6f6`

## Result

Four isolated optimizations raised the matched native batch workload from **116,260 to 130,137
SPS**, a **1.119x / 11.94%** combined speedup. The comparison used two alternating runs per build,
3,145,728 decisions per run, and the same machine under the same active-sweep contention.

After the `cnc5` sweep ended, a matched four-run PufferLib GPU A/B measured **57,470 to 62,774
aggregate SPS**, a **1.092x / 9.23%** end-to-end training speedup.

Every combined run completed 992 losses with zero wins, draws, or failures and produced the same
final-state digest:

`c523dde6a952aa791cf860d89a3f2dd6617a5efad8ba230d36527f979e7d8cba`

## Changes

1. Pathfinder occupancy scans stop at `building_count` and `infantry_count` instead of visiting all
   64 building and 128 infantry slots for every queried route cell.
2. Easy-AI base-center scans stop at `building_count`.
3. Placement occupancy and proximity scans stop at the same proven populated prefixes.
4. Easy-AI base geometry is recalculated only after an opponent building is added or destroyed.
   Projectile damage, building fire, and owner blowup all invalidate the cache.

No game frame is skipped, no simulation rule is approximated, and unit-slot scans remain full
because vehicle slots are sparse and reused rather than prefix-packed.

## TDD And Determinism

- A pre-change characterization test proved that no active building appears at or above
  `building_count` during 3,000 frames for both supported seeds.
- A pre-change geometry test pinned base-center behavior after building addition, unchanged frames,
  and owner blowup.
- Focused tests pin cache invalidation from projectile destruction and building-fire destruction.
- Debug: 151/151 tests passed.
- ReleaseFast: 151/151 tests passed.
- Recorded Vanilla observations, action masks, AI commands, frame traces, RNG, economy, movement,
  pathfinding, and combat fixtures remained exact.
- All native A/B outcomes and state digests matched exactly.

## Isolated Results

All short runs used 64 worlds, 16,384 iterations, 1,048,576 decisions, ReleaseFast, and fixed
actions. Long placement/cache runs used 65,536 iterations and 4,194,304 decisions.

| Candidate | Baseline mean SPS | Candidate mean SPS | Difference | Samples |
| --- | ---: | ---: | ---: | ---: |
| Pathfinder populated prefixes | 139,975.976 | 144,885.974 | +3.51% | 4 alternating short runs/build |
| Easy-AI recalc populated prefix | 140,963.768 | 148,614.216 | +5.43% | 4 alternating short runs/build |
| Placement populated prefixes | 143,001.551 | 145,281.521 | +1.59% | 2 alternating long runs/build |
| Dirty Easy-AI base cache | 144,091.838 | 151,299.842 | +5.00% | 2 alternating long runs/build |

The isolated percentages are measured against each candidate's immediate predecessor and must not
be added. Scheduler contention moved absolute rates between candidate windows.

## Combined Benchmark

Commands for the preserved source-equivalent baseline and final implementation binaries:

```bash
/tmp/td_micro_batch_benchmark_infantry_prefix 64 49152
/tmp/td_micro_batch_benchmark_base_dirty 64 49152
```

| Build | Run 1 SPS | Run 2 SPS | Mean SPS | Difference |
| --- | ---: | ---: | ---: | ---: |
| Committed baseline | 112,134.367 | 120,386.356 | 116,260.362 | baseline |
| Final implementation | 130,529.777 | 129,744.479 | 130,137.128 | +11.94% |

An earlier 4,194,304-decision pair was discarded because the baseline process exceeded the tool
yield and briefly overlapped the candidate. It is not included above.

## Verification Commands

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache zig build test --summary all
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache zig build test -Doptimize=ReleaseFast --summary all
ZIG_GLOBAL_CACHE_DIR=/tmp/td-micro-zig-global-cache zig build lib -Doptimize=ReleaseFast --summary all
cc -O3 -std=c11 -I include tools/batch_benchmark.c zig-out/lib/libtd_micro.a \
  -lm -lpthread -o /tmp/td_micro_batch_benchmark_base_dirty
```

## PufferLib GPU A/B

The sweep was stopped after 90 trials. Two baseline runs used the existing pre-change Puffer
extension; the extension was then rebuilt from implementation commit `eef90b7`, and two candidate
runs used the identical command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
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

Configuration: PufferLib native CPU environments with CUDA training, 64 agents, 4 buffers, 4
threads, horizon 32, minibatch 2,048, 1,048,576 timesteps, and a 64x1 policy.

| Extension | Run 1 SPS | Run 2 SPS | Mean SPS | Difference |
| --- | ---: | ---: | ---: | ---: |
| Pre-change baseline | 60,386.687 | 54,553.983 | 57,470.335 | baseline |
| `eef90b7` candidate | 65,244.359 | 60,304.482 | 62,774.421 | +9.23% |

Validity evidence:

- Baseline extension SHA-256: `5e30aecc5b469152fd083ccc9027358ac88fc226bffe42556ae6122a235ba1bf`.
- Candidate extension SHA-256: `2b11bbe0edf00f17b3b4e791cf5a8b4b279f00d0e750e3aef61f14042d0df52d`.
- INI SHA-256 remained `cf29814d176cf4df2852c13111b6c60c14dcce06fa6456bdace4bd026193edf0`.
- Resolved `vec`, `env`, `policy`, `torch`, and `train` configurations match across all four logs.
- `start_failures` and engine `failures` are zero in every sampled window.
- All 32 final environment metrics match exactly across all four runs, including performance,
  episode length, units, kills, losses, buildings, refinery, Harvester, and Tiberium metrics.
- The rebuilt Puffer C binding compiled with warnings as errors and emitted
  `episode_return=0.250 draw_rate=1`.

Logs:

- baseline: `PufferLib/logs/cnc_micro/1784336114167.json`,
  `PufferLib/logs/cnc_micro/1784336203202.json`;
- candidate: `PufferLib/logs/cnc_micro/1784336380942.json`,
  `PufferLib/logs/cnc_micro/1784336563743.json`.

The optimized extension is now the installed local PufferLib build. The host exhibited timing noise,
but each same-order candidate beat its corresponding baseline, and the two-run mean agrees with the
independent +11.94% native fixed-action result.
