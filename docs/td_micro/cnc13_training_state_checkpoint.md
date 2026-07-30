# CNC13 Native Training-State Checkpoint

Date: 2026-07-21

Status: accepted for single-GPU native TD Micro continuation

## Scope

TD Micro now has an opt-in, version-4 native training-state file beside the existing policy-only
`.bin` checkpoint. The `.bin` format is unchanged and remains the inference and historical
evaluation format. Full-state continuation is enabled with `--save-training-state` and resumed
with `--load-training-state-path`.

This change does not alter the simulator, action ABI, observations, rewards, maps, opponent, or
canonical seed. Seed 73 remains active; migration to seed 42 is `TASK-3G` and must be a separate
commit.

## Serialized State

The native state contains:

- FP32 master policy weights and the active BF16 policy representation;
- Muon momentum, learning-rate buffers, and accumulated native loss counters;
- epoch, global step, immutable schedule horizon, and source optimizer settings;
- rollout RNG offsets and every per-buffer CUDA Philox state;
- every per-buffer MinGRU recurrent state;
- host and GPU observations, actions, rewards, terminals, and action masks;
- complete TD Micro worlds, reset seeds, episode steps and returns, invalid-action state,
  milestones, death tracking, statistics, metrics, and optional action traces; and
- a compatibility fingerprint and payload checksum.

The compatibility fingerprint covers trajectory-relevant environment, vector, policy, optimizer,
schedule, seed, native-backend binary, and trainer-source configuration. It deliberately excludes
the temporary stopping rung and output paths. A 2M stop can therefore be resumed toward a declared
50M schedule without changing the learning-rate denominator. Full-state mode requires an explicit
`train.schedule_timesteps`; ordinary state-disabled runs retain the historical
`schedule_timesteps=0 -> total_timesteps` behavior.

State checkpoints are written only at optimizer boundaries. The reporting accumulators are flushed
before each state save so uninterrupted and restarted processes serialize the same boundary.
Self-play pools and non-native backends are rejected because their complete state is not yet part
of this format.

## Exact CUDA Gate

Command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1
env PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 \
  LD_LIBRARY_PATH=/usr/lib/wsl/lib:/home/claude/cnc/.worktrees/td-micro-v1/PufferLib/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:/home/claude/cnc/.worktrees/td-micro-v1/PufferLib/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:/home/claude/cnc/.worktrees/td-micro-v1/PufferLib/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib \
  PufferLib/.venv/bin/python tools/cnc_micro_training_state_gate.py
```

Shape: native CUDA MinGRU, 64 agents, one buffer, four threads, horizon 32, minibatch 2,048,
replay ratio 1, split at 131,072 transitions, and finish at 262,144 transitions under one immutable
262,144-transition schedule.

The gate runs three fresh processes: uninterrupted, stopped prefix, and resumed suffix. It passed
all exact comparisons:

| Evidence | Uninterrupted | Resumed | Result |
| --- | --- | --- | --- |
| Final state SHA-256 | `a5b2c43378d8d3ce8cfe767db4130f9a0e783f5438a2bc1624bbed76bf7a4bea` | same | exact |
| Final weights SHA-256 | `70153d75f3fcae7e22169fb2a85d522fdf561953559af4a6a421ebab95bcad91` | same | exact |
| Post-split action/reward/terminal digest | `0785aa1cec7d820bbb8abda0d36e43a5714d564085b94f2d1fce5a9d12d3c0dd` | same | exact |
| Compatibility fingerprint | `396c92df8807e1196c53556ecd376469ae50933914500e4ce1d5c9ec67fadd1d` | same | exact |
| Post-split environment metrics | 61 completed episodes | identical values | exact |

The independently produced split-state SHA-256 was
`8e95529b494939cdac150e65050e7246425c46445d2e2556d7e3e395ed3ffbee` in both the uninterrupted
and stopped-prefix processes. `start_failures=0` and `failures=0` throughout.

The same gate rejects a truncated file, damaged header, arbitrary payload corruption, changed
seed, changed schedule, and changed reward configuration. Payload corruption is detected by the
stored checksum; trajectory changes are rejected by the compatibility fingerprint.

### Rejected Callback Refactor

A follow-up cleanup replaced the CNC-named environment snapshot calls in generic vector code with
preprocessor callback aliases. Although the generated path was intended to be semantically
identical, the rebuilt native binary produced a different, internally repeatable training
trajectory: final policy SHA-256 `8a41a83b73ce68509225642d72f470ea2b7ca3870d193d559b509117924a31a9`
instead of `70153d75...bcad91`. Reverting that cleanup and rebuilding restored every original hash,
including the final policy, state, trace, fingerprint, and episode metrics. The cleanup was
rejected. This confirms that continuation compatibility must pin the exact native backend binary,
not merely a claimed source-level behavior contract.

Raw machine-readable evidence is generated at
`PufferLib/logs/cnc_micro/training_state_gate/report.json`.

## Normal CLI Gate

`tools/cnc_micro_training_state_cli_gate.py` repeats uninterrupted, split, and fresh-process resume
through the normal `python -m pufferlib.pufferl train cnc_micro` path. Its CUDA check passed exact
split-state, final-state, and final-weight comparisons. The final state SHA-256 was
`63e331e9f983ae8a7bf4a11729365e3d5d36ece80e98b12856c8cefa107dffc5`; final policy SHA-256 was
`1e14b32ec6fea87afc26ab435c20e6fb3b96c442156cde2cf2bb6972fe911d1f`.

The state and compatibility hashes changed when native training gained the missing
`--load-model-path` warm-start call because the exact-state fingerprint pins the trainer source.
The policy SHA and post-split action/reward/terminal digest stayed identical, proving the fix did
not alter the established fresh-training or exact-state-resume trajectory.

## Compatibility And Throughput Checks

- Two repeated fixed evaluations of the pre-change promoted `.bin` produced the identical ordered
  episode digest `d2b223d6c776c8033eedba73dafeb82810260e47c03ed121c23e8edb8275718c`.
- A normal state-disabled CUDA smoke used 64 agents, one buffer, four threads, horizon 32,
  minibatch 2,048, and 262,144 transitions. Its five SPS buckets were 75,696, 65,250, 60,006.5,
  47,972.5, and 45,248; median 60,006.5 SPS, with zero start and engine failures.
- This smoke establishes that the normal path remains valid. It is not an adjacent performance A/B
  and no speedup is claimed.

The exact continuation gate is now accepted. It enables multi-fidelity experiments to stop and
resume one optimization trajectory; it does not by itself make that trajectory learn robustly.
