# `lwgwyjl7` Balanced-Spawn Champion

Date: 2026-07-16

Status: promoted retained checkpoint

## Verdict

W&B run [`lwgwyjl7` / `cool-surf-104`](https://wandb.ai/kinvert-k/cnc2/runs/lwgwyjl7)
is the current TD Micro champion. It reproduced the winning `w1swzimb` sweep configuration through
normal PufferLib training, retained the resulting checkpoint, finished its balanced close/medium
evaluation at **505 wins, 0 losses, and 0 draws**, passed deterministic native replay checks on both
spawn profiles, and won a real rendered Vanilla TD match from the medium spawn.

This promotion is scoped to the current ABI-6 `td_micro_v1` ruleset: GDI versus original-AI GDI,
MCV, Power Plant, Barracks, E1, E3, no Tiberium economy, and deterministic close/medium scenario-1
starts. It is not evidence for broader units, maps, or difficulties.

## Immutable Identity

| Item | Value |
| --- | --- |
| Exact source/config snapshot | `1625e88972d5a32a310b890862a86a10f21353b2` |
| Source commit | `feat: add balanced spawn training curriculum` |
| W&B project/run | `cnc2/lwgwyjl7` |
| W&B name/tag | `cool-surf-104` / `w1swzimb-retained-reproduction` |
| Retained checkpoint | `PufferLib/checkpoints/cnc_micro/lwgwyjl7/0000000001048576.bin` |
| Checkpoint bytes | 1,709,056 |
| Checkpoint SHA-256 | `46695237efbb6d350971e1163a54c57877a897d487c2b9f7873f3b16dce275e7` |
| Rules manifest SHA-256 | `ffc4646f31a9c8e64dcfbd1ffc91fa6163af4b5686478124b3bb21187107ca85` |
| Policy ABI | 6 |
| Observation / mask | 6,208 bytes / 275 bytes |

Training occurred while the balanced-spawn source/config changes were uncommitted on top of
`41a219e`. Commit `1625e88` freezes that exact executable state before these documentation changes.
W&B may therefore display the older HEAD; use `1625e88`, not the W&B Git field, to reproduce the
code. Checkpoints and run logs remain ignored local artifacts by design.

## Training

The normal retained-checkpoint run used the INI defaults committed in `1625e88`; no model was
loaded. The launcher command was:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc2 --wandb-group '' \
  --tag w1swzimb-retained-reproduction
```

Effective configuration:

| Group | Value |
| --- | --- |
| Timesteps | 1,048,576 |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| Trainer | PufferLib CUDA, `train.gpus=1` |
| Policy | `MinGRU`, hidden 64, one layer |
| Encoder / decoder | `Normalize255Encoder` / `DefaultDecoder` |
| Seeds | Puffer 73, train 42, environment base 1 |
| Learning rate | `0.008668618381591891` |
| Entropy coefficient | `0.0009582776518303332` |
| Maximum gradient norm | `0.6515999019540559` |
| Priority alpha / beta0 | `0.22100208042634323` / `0.985908351638052` |
| Gamma / GAE / replay | `0.995` / `0.9` / `1.0` |

The reward vector remained the prior `lqkwukxi` champion vector: milestone `0.2`, player infantry
`0.03030131620399178`, enemy unit loss `0.0054265722298487366`, enemy building loss
`0.7301079315055825`, and player unit loss `0.0`.

## What Changed

The successful run did not change the simulator, observations, rewards, model, vectorization, or
training budget relative to the failed authoritative balanced reproduction `3mq4ot3x`. It changed
only the stability controls found by `w1swzimb`:

| Control | Failed balanced default | `lwgwyjl7` |
| --- | ---: | ---: |
| Learning rate | `0.015` | `0.008668618381591891` |
| Entropy coefficient | `0.001` | `0.0009582776518303332` |
| Maximum gradient norm | `1.5` | `0.6515999019540559` |
| Priority alpha | `0.8` | `0.22100208042634323` |
| Priority beta0 | `0.2` | `0.985908351638052` |
| Horizon | `32` | `32` |

The failed run finished 0/115/0; the retained reproduction finished 505/0/0. This is a policy
optimization result, not an environment implementation speedup.

## Training Result

| Metric | Final value |
| --- | ---: |
| SPS | **97,772** |
| Uptime | 11.5869 seconds |
| Start failures / engine failures | **0 / 0** |
| Completed evaluation episodes | 505 |
| Overall win / loss / draw | **505 / 0 / 0** |
| Close episodes and result | **257; 257 / 0 / 0** |
| Medium episodes and result | **248; 248 / 0 / 0** |
| Balanced performance | **1.0000** |
| Mean episode decisions | 1,043.19 |
| Mean units / E1 / E3 built | 28.57 / 27.16 / 1.41 |
| Mean unit kills / losses | 3.08 / 0.145 |
| Mean buildings destroyed / lost | 3.0 / 0.0 |
| Mean invalid actions | 600.26 |

The run is valid for SPS reporting because both startup and engine failures are zero. SPS is
behavior-dependent and is not presented as a simulator speedup. Machine-readable results are in
`PufferLib/logs/cnc_micro/lwgwyjl7.json`; the captured TUI is
`docs/td_micro/benchmarks/cnc2_w1swzimb_retained_reproduction.log`.

## Deterministic Native Checks

The final checkpoint was run twice in fresh native processes for one declared sample on each spawn.
Both complete observation/mask traces and terminal logs were byte-identical within each pair.

| Profile | Env/sample seed | Result | Decisions | E1/E3 | Kills/losses | Buildings destroyed | Trace SHA-256 |
| --- | --- | --- | ---: | --- | --- | ---: | --- |
| Close | 1 / 74 | win | 1,072 | 30 / 1 | 3 / 0 | 3 | `001fde9e266fc2f590e9855f457302a9d638fc662ae67304966990d15d0c9e39` |
| Medium | 2 / 74 | win | 1,076 | 32 / 0 | 3 / 0 | 3 | `fdeded5028ce43b174f87c76364ff8a4e0f37d7086de521d05ff7b8e7af9bfaa` |

The corresponding terminal-log hashes are
`6371e372bfd41977397d7d5ea9247912a248bb90e06bf38f4a0a2d463b551dcb` for close and
`533e75ff7c9acf6eca7378e4a86be5909284a0e9a545e8ad991ea8f54884a0f0` for medium.
This proves fixed-seed inference repeatability; it does not claim bit-identical PPO training.

## Real Vanilla Transfer

The same checkpoint controlled the normally human/player side in a fresh isolated, windowed
`DISPLAY=:0` Vanilla runtime. The match used medium spawn seed 2, categorical sample seed 74, the
original GDI AI, unlimited simulation speed, and a 120 FPS render cap. Vanilla reported:

```text
TD Micro: auto-starting scenario=1 seed=2 spawn=medium GDI policy vs Hard GDI AI
TD Micro policy: loaded checkpoint=46695237efbb6d350971e1163a54c57877a897d487c2b9f7873f3b16dce275e7
terminal reason=win frame=4168 decisions=1043 accepted=536 changed=78
player_defeated=0 opponent_defeated=1 failed=0
```

The runtime policy log SHA-256 is
`3d78edc6f7df8a0f773cf43f32c0f5332e1c85ded086874e802ec079473fd688`; the live packed-state
trace SHA-256 is
`e198ab4a4102671e50d2540dafcf09a9c9de21ab8623f47a78ecbf33896d86ac`.
The UI used the wrong-language local data archive, but policy loading, control, simulation, and
terminal detection were unaffected.

## Verification Matrix

Before source commit `1625e88`:

- all 104 Zig tests passed in Debug, ReleaseSafe, and ReleaseFast;
- generated rules and map outputs matched their checked-in files;
- `zig fmt --check` passed;
- the Vanilla executable and shared library built;
- all 14 Vanilla CTest targets passed;
- every current Vanilla oracle fixture was recorded twice in fresh processes and matched;
- the C binding test passed with warnings treated as errors;
- the Puffer native/CUDA extension built; and
- focused self-contained Puffer Python tests passed 4/4.

The complete Puffer test suite could not collect because unrelated optional packages and legacy
imports are absent (`jax`, `heavyball`, `pandas`, `pyximport`, and old Puffer modules). This does not
affect the focused `cnc_micro` build, training, checkpoint, or transfer evidence above.

## Promotion And Next Gate

`lwgwyjl7` supersedes `lqkwukxi` as the retained current-curriculum champion. The next work should
not broaden reward search on the same solved two-profile task. The important remaining issues are:

1. replace the seven independent action heads with a conditional legal-command protocol;
2. add a farther or pre-armed curriculum profile that forces sustained combat with the opponent AI;
3. rerun deterministic parity, retained-checkpoint evaluation, and visible Vanilla transfer; and
4. eventually satisfy M8's broad held-out Vanilla win-rate gate.
