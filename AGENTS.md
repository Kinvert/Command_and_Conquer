# Repository Guidelines

## Project Purpose

This repository is a local C&C RL research workspace. The serious path is a headless, state-fed Tiberian Dawn environment for PufferLib, not a human UI port, launcher, or graphics/audio project.

Long-term target:

- Train a PufferLib policy to control the human/player side in real Tiberian Dawn matches.
- Start as GDI against a built-in original-AI GDI opponent in a GDI-vs-GDI mirror skirmish.
- Curriculum should progress from simple build/economy slices to easy AI, then normal AI, then hard AI.
- Final human-play integration should let an INI/config choose the opponent brain: original TD AI or a trained PufferLib policy running inference.
- Do not remove the original AI path; the learned policy is an alternate controller, not a hard replacement.

Primary target:

- deterministic Zig simulator and Vanilla differential oracle: `td-micro/`
- native PufferLib env: `PufferLib/ocean/cnc_micro`
- current reduced ruleset: MCV, Power Plant, Refinery/bundled Harvester, Tiberium economy,
  Barracks, E1, and E3
- Vanilla target: visible Easy GDI-vs-GDI mirror skirmish with the original AI on the opponent side
- policy target: the trained checkpoint controls the side normally controlled by the human/player
- normal training path: PufferLib CUDA/native command with `--train.gpus 1`

`PufferLib/ocean/cnc_build` is the historical TD shared-library environment. Keep it for reference and regression work, but do not treat it as the current implementation or benchmark path.

## Project Layout

- `td-micro/`: current Zig simulation, deterministic parity tests, policy ABI, batch API, and C API.
- `td-micro/SPEC.md`: current reduced-game and Vanilla deployment specification.
- `td-micro/include/td_micro_api.h`: ABI 13 public batch and policy API.
- `Vanilla-Conquer/`: Vanilla TD oracle and visible deployment target.
- `PufferLib/ocean/cnc_micro/`: current native PufferLib environment.
- `PufferLib/ocean/cnc_build/`: historical TD shared-library environment, not the active path.
- `tools/td_micro_oracle.cpp`: Vanilla differential fixture/oracle tool.
- `tools/record_td_micro_fixtures.sh`: deterministic Vanilla fixture recorder.
- `td-data/`: local extracted game data. Do not commit commercial or user-supplied game data.
- `docs/perf_baseline_log.md`: append-only throughput ledger.
- `docs/td_micro/`: parity, oracle, ABI, and benchmark evidence for the current path.

## Build Commands

Deterministic Zig test matrix:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
```

Human-play VanillaTD build, used for oracle and visible checkpoint-control checks:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/Vanilla-Conquer
cmake -S . -B build-td -G Ninja \
  -DBUILD_VANILLATD=ON \
  -DBUILD_VANILLARA=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_TOOLS=ON \
  -DOPENAL=ON \
  -DSDL2=ON
cmake --build build-td --target VanillaTD
```

PufferLib `cnc_micro` native/CUDA backend:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
source .venv/bin/activate
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
CC=clang CXX=g++ CCACHE_DIR=/tmp/ccache CUDA_HOME=/usr/local/cuda-12.8 \
  LIBRARY_PATH=$EXTRA_LIBS LD_LIBRARY_PATH=$EXTRA_LIBS ./build.sh cnc_micro
```

Current clean PufferLib GPU benchmark shape:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 1 \
  --vec.num-threads 4 \
  --train.total-timesteps 131072 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

Do not switch to `--cpu` for throughput work. The established path is PufferLib's normal GPU training command with the native CPU env.

## Current Performance Baseline

- All **198/198** deterministic tests pass in Debug, ReleaseSafe, and ReleaseFast.
- Policy ABI is **13**, with observation version **5**, a **2,456-byte ByteTensor**, and a packed
  **9,242-bit / 1,156-byte** exact prefix mask. Native training and Zig inference both normalize
  observations by `1/255`.
- One action is `{12, 65, 65, 65}`: command plus three conditionally sampled arguments. One complete
  semantic command remains one Puffer transition and advances four TD frames. Do not split prefix
  selection into environment steps and do not use `--slowly`.
- Native CUDA samples the conditional path in one kernel and PPO replays that same stored prefix.
  Inactive PAD heads contribute zero log-probability, entropy, and gradient. Sampled masked actions
  rejected by the simulator are invariant failures, not expected no-ops.
- The authored scenario-1 curriculum has deterministic close seed 1 and medium seed 2 profiles.
  A 64-agent vector starts exactly 32 worlds in each profile; each agent retains its profile across
  resets. This is deterministic state evolution, not a wall-clock or stock-AI event-timing contract.
- H5/full-match fixed evaluation independently assigns exactly 50% MCV-only starts and 50%
  symmetric reduced Unit Count 6 starts (3 E1 + 3 E3 per side). Reverse training ramps force starts
  from 25% to 75% over the existing curriculum clock. Live `balanced_perf` equal-weights all four
  spawn-by-force cells; authored H0-H4 starts are unchanged.
- Training and visible transfer share a **48,000 TD-frame / 12,000-decision** timeout contract.
- Soft-death terminals give **-1** for a 17th active building or a 65th active infantry. The former
  invalid-action-streak terminal is disabled; malformed externally submitted tuples remain
  diagnostic no-ops, while the native sampler must never emit one.
- Current reward defaults are authoritative in `PufferLib/config/cnc_micro.ini`. The ABI10/ABI11/ABI13
  action work did not alter them: milestone `0.2`, player infantry `0.0`, enemy unit loss
  `0.03176472410973994`,
  enemy building loss `0.23219496897879333`, player unit loss `-0.005791169896719446`, Refinery
  `0.042555945418244596`, first delivery `0.0`, and Tiberium income `0.007081631623240768`.
- The physical **64-building hard capacity** remains an engine failure. It must invalidate a throughput run rather than masquerade as a gameplay terminal.
- Early balanced-spawn ABI 6 runs reached **94K-105K SPS** but collapsed to all losses. They remain
  useful workload and regression baselines. SPS changes materially as trained policies create
  different unit/pathfinding/combat workloads; use fixed action/state traces before attributing a
  gap to one environment change.
- W&B run `cnc2/3mq4ot3x` used only the corrected INI defaults. Its effective `env`, `vec`, `policy`,
  `torch`, and `train` sections have zero differences from `cnc1/lqkwukxi`; it reproduced the same
  failed final checkpoint hash as the prior balanced runs. Missing hidden PPO defaults are therefore
  ruled out for this deterministic seed.
- The focused 100-run `cnc2` stability sweep found `w1swzimb`, then normal run `lwgwyjl7`
  reproduced its exact final environment outcomes and retained the model. Source/config is frozen
  at `1625e88`; checkpoint SHA-256 is
  `46695237efbb6d350971e1163a54c57877a897d487c2b9f7873f3b16dce275e7`.
  The valid one-GPU run reached **97,772 SPS**, zero failures, and **505/0/0** final evaluation:
  257/0/0 close and 248/0/0 medium.
- `lwgwyjl7` is the current champion. Representative close and medium native samples replayed
  byte-identically through wins, and the exact checkpoint won a real medium-spawn Vanilla match at
  frame 4,168 with zero failures. `lqkwukxi` remains the historical transfer baseline.
- ABI10 removed the independent-head legality blocker. ABI11 preserves the exact grammar and mask
  while reducing policy outputs from 15,027 to 2,352 and hidden-64x1 parameters from 1,131,264 to
  320,064. Two 262,144-step CUDA repeats produced the exact checkpoint hash, and every run reports
  zero invalid actions, start failures, and engine failures. Matched balanced performance improves
  from ABI10's 0.102/0.000 at 1M/2M to 0.175/0.161, but still trails ABI9's 0.422 at 2M. See
  `docs/td_micro/abi11_compact_decoder_experiment.md`.
- ABI13 adds a bounded rank-4 actor-target residual and explicit CPU/CUDA gradient parity. It
  reaches 0.383830 reproducibly at 1M but only 0.092308 at matched 2M; its 28 sampled screen trials
  have median 0 and maximum 0.203216. Commit `9789107` is preserved but not promoted. The next
  experiment restores ABI9's seven heads in isolation and compares invalid-as-noop with zero and
  tiny penalties. See `docs/td_micro/abi13_actor_target_experiment.md` and `TASK-3B` in `TODO.md`.
- Final fixed-action native runs measured 171,090 and 168,957 SPS with exact pre-change world digest
  `38cca161...ce28`. The immediately captured ABI9 native baseline was about 195,671 SPS. Exact
  row-bitset placement masks removed a completed-queue collapse from about 1K SPS to 162K-164K SPS;
  see `docs/td_micro/abi10_placement_mask_hotspot.md`.
- Current spawn, parity, DISPLAY, and training evidence is in
  `docs/td_micro/balanced_spawn_curriculum.md` and
  `docs/td_micro/balanced_stability_sweep_100.md`. The authoritative champion record is
  `docs/td_micro/lwgwyjl7_balanced_champion.md`.

The benchmark includes the complete `cnc_micro` PufferLib path: action application, four deterministic simulation frames, observation and mask packing, reward, terminal handling, reset, vector synchronization, and GPU training.

## Valid SPS Reporting Rules

Every SPS report must include:

- command used
- agents, buffers, threads, horizon, total timesteps, minibatch size
- GPU/train mode
- `start_failures`
- whether the run is valid
- relevant native profiler before/after numbers for env changes

Rules:

- Any PufferLib run with `start_failures > 0` is invalid for SPS claims.
- Any `cnc_micro` run with engine `failures > 0` is invalid for SPS claims.
- Intentional soft-death counters (`building_limit_losses` and `infantry_limit_losses`) are gameplay
  outcomes and are not engine failures. The invalid-action-streak terminal is disabled.
- Historical `cnc_build` runs with `dlmopen` start failures remain invalid and must not be compared as current throughput.

## Current Completion Gate

The historical ABI 4 M6 transfer gate is complete. Checkpoint `e6795099...c7765`, trained through
PufferLib GPU at 102,519 SPS,
controlled the normally human/player side in rendered Vanilla TD against the restricted original
Easy AI. It reached the exact 7,200-frame timeout, changed real simulation state four times, logged
zero failures, and exited cleanly without human commands. Exact evidence is in
`docs/td_micro/m6_visible_policy_transfer.md`.

The ABI-6 balanced quality gate is also complete. Source `1625e88` and retained checkpoint
`46695237...275e7` passed valid GPU training, perfect final close/medium evaluation, deterministic
native replay checks, and a visible Vanilla win. The active gate is now:

1. Preserve the completed exact conditional action protocol and add compact actor-target
   interaction that recovers ABI9-level learning while reaching at least 50K valid native-CUDA SPS.
2. Keep deterministic Zig/Vanilla parity, normalized Puffer/inference observations, and zero engine
   failures green.
3. Add a farther or pre-armed deterministic profile that forces sustained interaction with the
   original AI army.
4. Train and select by fixed-seed, per-profile outcomes, then repeat visible Vanilla transfer with
   that exact checkpoint.
5. Preserve M8 as the broad held-out Vanilla win-rate gate; the current two-profile result does not
   close it.

## Coding And Editing Rules

- Prefer existing local patterns over new framework code.
- Keep upstream source snapshots and local research patches distinct.
- Do not push to PufferLib upstream, EA/C&C upstream, or public remotes unless explicitly asked.
- Do not commit `td-data/`, game ISOs, user saves, downloaded commercial data, checkpoints, caches, or generated binaries.
- Do not report a speedup without the command and validity checks above.
- Do not start CUDA simulator work until profiling identifies a batchable kernel and CPU reference behavior is pinned.
- Add compact comments only where needed to explain non-obvious headless/API behavior.

## Git Notes

This repo is used as a local safety net. Local commits are useful, but remote pushing is not part of the normal workflow.

Before committing:

```bash
git status --short
git diff --stat
```

Never revert user changes or unrelated worktree changes just to make a clean diff.
