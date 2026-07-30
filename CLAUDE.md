# CLAUDE.md

This file provides guidance to coding agents working in this local C&C RL workspace.

## Project Identity

This is a headless RTS reinforcement-learning simulator project. The goal is to make Tiberian Dawn trainable through PufferLib at meaningfully higher SPS.

The long-term product goal is a real RTS opponent, not a sandbox benchmark. First train a learned player-side GDI policy against an original-AI GDI opponent in a GDI-vs-GDI mirror skirmish. The difficulty ladder should be easy AI, then normal AI, then hard AI. Later, human play should expose an INI/config choice for the opponent controller:

```text
original_td_ai
puffer_policy
```

The original AI remains available as a selectable backend. The PufferLib policy is an alternate brain for inference, not a destructive replacement of the stock AI path.

It is not primarily:

- a human-play polish project
- a graphics/audio/video playback project
- a UI automation project
- a generic C&C remaster fork
- a CUDA rewrite project

The current implementation is the deterministic Zig simulator in `td-micro/`, integrated through the native PufferLib environment at `PufferLib/ocean/cnc_micro`. The historical `PufferLib/ocean/cnc_build` TD shared-library environment remains available for reference and regressions, but it is not the current implementation or benchmark path.

## Current Truth

The current `td-micro` path has these verified properties:

- All **104/104** deterministic tests pass in Debug, ReleaseSafe, and ReleaseFast.
- The public policy contract is ABI **6**, with a **6,208-byte observation**, **275-byte action
  mask**, and observation version **3**.
- Scenario 1 has deterministic close seed 1 and medium seed 2 profiles. A 64-agent vector starts
  exactly 32 worlds in each profile and preserves each assignment across resets.
- Training and visible deployment share a **48,000 TD-frame / 12,000-decision** timeout contract.
- Soft-death terminals give **-1** for a 17th active building or a 65th active infantry. Rejected
  command tuples are diagnostic no-ops; the invalid-action-streak terminal is disabled.
- Current shaping uses the exact `lqkwukxi` reward vector: `+0.2` milestones,
  `+0.03030131620399178` bounded infantry production, `+0.0054265722298487366` enemy unit loss,
  `+0.7301079315055825` enemy building loss, and `0.0` player unit loss.
- The **64-building hard capacity** is still an engine limit; exceeding it is an engine failure and invalidates the run.
- The current reduced ruleset is MCV, Power Plant, Barracks, E1, and E3.
- Source/config snapshot `1625e88` is the current reproducible baseline.
- W&B run `cnc2/lwgwyjl7` trained from scratch through the normal one-GPU PufferLib path at
  **97,772 SPS**, with zero start and engine failures. Its final evaluation was **505/0/0**:
  257/0/0 close and 248/0/0 medium.
- The retained champion checkpoint is
  `46695237efbb6d350971e1163a54c57877a897d487c2b9f7873f3b16dce275e7`.
  Representative close and medium native traces replay byte-identically through wins.
- The exact checkpoint won a rendered medium-spawn Vanilla match at frame 4,168 with
  `opponent_defeated=1` and zero failures.

Use `td-micro/SPEC.md`, `docs/td_micro/`, and `docs/perf_baseline_log.md` as the current sources of truth. Treat older `cnc_build`, `dlmopen`, and TD step-loop profiles as historical evidence only.

## Operating Principles

1. Measure first, then optimize.
2. Use PufferLib's normal GPU training command for throughput checks.
3. Treat `start_failures > 0` or engine `failures > 0` as invalid for SPS claims.
4. Keep gameplay soft-death terminals distinct from engine-capacity failures.
5. Keep the sim path headless: no renderer, no audio, no movie work on the training path.
6. Preserve the ABI 6 observation/action contract between Zig training and visible Vanilla inference.
7. Prefer compact semantic state exports over UI or framebuffer observations.
8. Require Vanilla differential and replay/hash checks for simulator changes.
9. Do not start a CUDA simulator port until profiling proves a specific batchable kernel.

## Target Architecture

The north star is:

```text
CnCWorld + CnCInput -> CnCWorld
```

The training path uses explicit batched Zig worlds. The visible deployment path now bridges the trained policy back into Vanilla-Conquer with:

- live Vanilla state packed into the same 6,208-byte observation used during training
- the same 275-byte action mask and seven-head action semantics
- a native loader for the actual trained checkpoint and its recurrent state
- deterministic decision timing and telemetry proving accepted actions change game state
- continued Vanilla differential parity for the reduced RTS subset
- opponent-controller plumbing that can select original TD AI or a trained PufferLib policy through config/INI for human play

CUDA is a later tool for selected batchable kernels such as observation packing, shroud/influence maps, or pathfinding. It is not the first fix.

## Main Commands

Deterministic parity suite:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
zig build test -Doptimize=Debug
zig build test -Doptimize=ReleaseSafe
zig build test -Doptimize=ReleaseFast
```

Clean PufferLib GPU run:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS .venv/bin/python -m pufferlib.pufferl train cnc_micro \
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

If running inside the Codex sandbox, GPU devices may be hidden. Do not interpret `torch.cuda.is_available() == false` inside the sandbox as proof that WSL GPU training is broken.

## Current Completion Gate

M6 integration and the current ABI-6 two-profile quality gate are complete. The retained
`lwgwyjl7` checkpoint trained end to end, won every final close/medium evaluation episode, passed
fixed-seed deterministic native replay, and won in rendered Vanilla. See
`docs/td_micro/lwgwyjl7_balanced_champion.md`.

The active gate is to replace the seven independent action heads with a conditional legal-command
protocol, add a harder deterministic profile that forces sustained interaction with the original AI
army, and repeat the train/evaluate/Vanilla-transfer chain. M8's broad held-out Vanilla win-rate
requirement remains open.

## What Not To Do

- Do not use `--cpu` as the primary training path when measuring current PufferLib throughput.
- Do not cite any run with nonzero start failures or engine failures as valid throughput.
- Do not optimize human-play rendering/audio/video for RL SPS.
- Do not rewrite large parts of TD without a replay/hash/parity check.
- Do not silently approximate unsupported TD behavior in a fast core. Fail loudly and document unsupported cases.
- Do not present historical `cnc_build` results as the current `cnc_micro` implementation.
- Do not treat the current reduced game as the final goal; it exists to establish end-to-end training and deployment against the built-in computer.
- Do not delete or bypass the original TD AI path when adding PufferLib inference for human play. Make the controller selectable.
- Do not commit game data, ISOs, checkpoints, caches, or generated binaries.
