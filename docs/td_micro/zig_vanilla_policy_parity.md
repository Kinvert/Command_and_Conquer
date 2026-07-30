# Zig/Vanilla Policy-State Parity

Date: 2026-07-16

Status: complete for the declared TD Micro v1 traces

## Scope

This gate compares the policy-visible observation and action mask produced by the pure Zig
simulator with the real `VanillaTD` executable. It covers:

- close setup seed 1 and medium setup seed 2;
- initial state and early MCV deployment;
- original Easy-AI construction and infantry production through frame 4,400;
- player Refinery, Harvester, first delivery, and AI E1 production;
- E1 movement, combat, MCV destruction, and terminal handling; and
- deterministic map, economy, movement, projectile, RNG, command, and entity fixtures.

This is not a claim that every possible policy trajectory or complete stock Tiberian Dawn behavior
is equivalent. Broad held-out outcome comparison is `TASK-2` in `docs/td_micro/TODO.md`.

## Fixes

- Tiberium presence is represented separately from the remaining overlay-step count. A present
  zero-step overlay is no longer exposed as clear terrain.
- Vanilla startup and Zig reset now use the same deterministic setup RNG and executable-loop
  ordering.
- Logical player/opponent houses are mapped consistently in policy and oracle exports.
- Easy-AI Harvester, infantry, message, and target-selection RNG calls follow Vanilla ordering.
- Released infantry preserve Vanilla guard-area mission, animation, tether, scatter, and arrival
  behavior.
- Movement tests true building occupancy cells instead of treating every building bounding box as
  completely occupied.
- A Harvester in the docking/limbo phase is excluded from AI target selection.
- A real-executable fixture and first-difference comparator now guard the packed policy record.

## Exact Executable Evidence

Two fresh `VanillaTD` processes were recorded for each seed. Each repeat was byte-identical, and
all eight 6,487-byte observation-plus-mask records matched the Zig-generated records exactly:

| Seed | Decision | Record SHA-256 |
| ---: | ---: | --- |
| 1 | 0 | `4bc1ded9129d5c5af41f665d51a6087da6e505f86b8b6ef067c753e60d24becb` |
| 1 | 1 | `d9e9278202a2f46315ddc7878d2783abef70890fe445372c18a13e32073c2f92` |
| 1 | 2 | `f850111cff5909d5d72977a51e0a864caf27ed53d5121407f13cdd762bc450ab` |
| 1 | 3 | `dfeb8e8b77cde988accf7cba76ab8c0d6ea2e33b6eda6d91c9a860c6650e8794` |
| 2 | 0 | `f689c967d59d6de4024a78a00cd4fb71567c191a6b9f81b67c70539fbe77d183` |
| 2 | 1 | `0a2569df63a598bf8dd67da5aee82779f9f386ed1a2485ac91c4fdd715d318cf` |
| 2 | 2 | `00c1099d513cf2c4998ba1712bd25644284aaeea72a8e6b2dfe5c2b225f1e551` |
| 2 | 3 | `5c219009e8ad84d4db86cb7a7328e6507084513395f4ef494ac0ca570977092f` |

The standalone comparator also reports:

```text
equal records=4 bytes=25948
```

Representative regenerated oracle fixture hashes:

| Fixture | SHA-256 |
| --- | --- |
| Scenario map | `4bb31ef19fd7e091d3d12812b82f39df2aa8530d17af1dbc52d86e0f07078383` |
| Easy-AI economy | `f12ea080c1671f94113578e4dfe370024f204d50ae21fd9d49ed43cfcf4a6c57` |
| Player Refinery/Harvester | `27c91e5e457fdf9634e56a334a89faefe6c31f82a603baa9d25023dfebc08892` |
| E1 attack against MCV | `f0cd63750f93c6d60c03f7593459513a5390fbaf505953738434226ab3bef572` |
| Terminal trace | `bc266105ade5aca6faafbaf608d032ef87ed817e2a145e10867bb589f7ff1c06` |

`tools/record_td_micro_fixtures.sh` generates every fixture twice in fresh processes and requires
the pair to pass `cmp` before replacing the checked-in fixture.

## Verification

- Zig Debug tests: 120/120 passed.
- Zig `ReleaseSafe` tests: passed.
- Zig `ReleaseFast` tests: passed.
- C ABI smoke: repeated digest
  `9c3e2f73dfeddd3c64e6415ea90937d526d9cf2bb0609179fcfd5cb0155f94a0`.
- Economy C API smoke: first delivery completed, zero invalid calls, zero failures.
- Standalone Puffer binding smoke: completed with `episode_return=0.250`.
- PufferLib CUDA/native extension: rebuilt successfully.
- VanillaTD: built successfully.
- Vanilla CTest suite: 14/14 passed.
- Full fixture recorder: every fresh-process repeat matched.

## Native Throughput

The native benchmark uses 64 worlds and 16,384 iterations, or 1,048,576 total decisions:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
zig build -Doptimize=ReleaseFast
cc -O3 -std=c11 -I include tools/batch_benchmark.c \
  zig-out/lib/libtd_micro.a -lm -lpthread -o /tmp/td_micro_batch_benchmark
/tmp/td_micro_batch_benchmark 64 16384
```

| Version | Run 1 SPS | Run 2 SPS | Mean SPS | Failures | Valid |
| --- | ---: | ---: | ---: | ---: | --- |
| Baseline `627c5d57` | 81,649 | 82,361 | 82,005 | 0 | yes |
| Parity-fixed source | 82,797 | 81,512 | 82,154 | 0 | yes |

The measured change is `+0.18%`, which is noise-level and indicates no material native throughput
regression. Each version repeated one stable world digest; different versions have different
digests because the parity corrections intentionally change simulation state.

## PufferLib Throughput

Both versions used the same normal PufferLib CUDA training workload:

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

| Version | Elapsed | Aggregate SPS | Start failures | Engine failures | Valid |
| --- | ---: | ---: | ---: | ---: | --- |
| Baseline `627c5d57` | 23.742 s | 44,166 | 0 | 0 | yes |
| Parity-fixed source | 20.698 s | 50,660 | 0 | 0 | yes |

Logs:

- baseline: `PufferLib/logs/cnc_micro/1784240023382.json`
- parity-fixed: `PufferLib/logs/cnc_micro/1784240412728.json`

The current run was 14.7% faster, but this is one run per version and policy behavior changes the
amount of simulated work. It establishes no regression; it is not a claimed simulator speedup.

## Next Gate

`TASK-2` ran 100 close and 100 medium matched fresh-process episodes. It found that the declared
fixtures were too narrow: all broad policy trajectories diverged by decision 76, native win rate
was 89%, and real Vanilla win rate was 42%.

`TASK-2A` has since fixed the decision-6 MCV-facing and decision-76
enemy-construction-progress classes. The broad exact prefix now reaches at least decision 179, but
terminal agreement is only 83/200 and the Zig/Vanilla win-rate gap remains 45.5 percentage points.
Continue policy-path parity work before changing spawn geometry. See
`docs/td_micro/abi8_parity_corrections.md`.
