# Deterministic Close/Medium Spawn Curriculum

Date: 2026-07-15

## Result

TD Micro now supports two authored scenario-1 spawn profiles in both Zig training and real Vanilla
TD inference. A 64-agent Puffer run starts exactly 32 close and 32 medium worlds. Selection is
deterministic: the same ruleset, seed, initial state, and ordered action stream produce the same
state sequence and terminal result.

This does not require wall-clock parity, render throttling, or forcing the Zig AI to emit every event
on the exact stock Vanilla frame. Vanilla is the behavioral oracle for supported mechanics;
deterministic state evolution is the hard requirement.

## Spawn Contract

| Seed | Bucket | Player waypoint/cell | Opponent waypoint/cell | Squared distance |
| ---: | --- | --- | --- | ---: |
| 1 | close | 0 / `(2,8)` | 1 / `(15,1)` | 218 |
| 2 | medium | 0 / `(2,8)` | 3 / `(37,23)` | 1,450 |

The generated C and Zig tables come from `td-micro/rules/td_micro_v1.json`. The new manifest hash is:

```text
ffc4646f31a9c8e64dcfbd1ffc91fa6163af4b5686478124b3bb21187107ca85
```

Puffer maps the configured base seed plus each global agent ordinal to alternating profile seeds.
The assigned profile remains fixed when that agent resets. This guarantees balanced initial worlds;
completed-episode shares can differ because one bucket may finish faster.

## Correctness Evidence

- Every profile is on-map, foot-passable, distinct, and resettable.
- Bases 1, 2, and 73 each produce exactly 32 close and 32 medium assignments over 64 ordinals.
- Two independent Zig worlds are compared after every state transition through terminal for each
  profile under the same deploy-then-noop action stream.
- Forced close/medium wins and losses verify all six profile terminal counters.
- Zig reset fields match recorded Vanilla reset fields for both profiles.
- Vanilla fixture pairs were recorded in fresh processes and were byte-identical.
- The Remastered/GlyphX and original human-play setup paths use the same generated coordinates.

Oracle trace hashes:

```text
close  a6071f860e2c923e8dc567f24835e5ac6fde363e9c5a041e8226a644d5630ab5
medium f66a34ecf3b880febdbfe0c0927206371f10e122af5daef62c9055f774373dd3
```

The first medium oracle attempt exposed a real bug: `USE_GLYPHX_START_LOCATIONS` bypassed the TD
Micro override, so seed 2 was labeled medium while still using the close opponent cell. Moving the
override above that compile-time branch fixed both shared-library and executable builds.

Both DISPLAY=:0 runs loaded the ABI-6 checkpoint and manifest successfully. Their startup telemetry
reported `seed=1 spawn=close` and `seed=2 spawn=medium`; each remained alive until the controlled
10-second timeout.

## Initial Puffer Run

W&B: [`2zuaj9oa` / `zany-bee-1`](https://wandb.ai/kinvert-k/cnc2/runs/2zuaj9oa)

The run kept the certified `lqkwukxi` reward vector and training shape unchanged:

```bash
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc2 --wandb-group balanced-spawn-v1 \
  --tag close-medium-v1 \
  --train.gpus 1 --env.seed 1 --env.max-decisions 12000 \
  --env.reward-milestone 0.2 \
  --env.reward-player-infantry 0.03030131620399178 \
  --env.reward-enemy-unit-loss 0.0054265722298487366 \
  --env.reward-enemy-building-loss 0.7301079315055825 \
  --env.reward-player-unit-loss 0.0 \
  --vec.total-agents 64 --vec.num-buffers 4 --vec.num-threads 4 \
  --train.total-timesteps 1048576 --train.horizon 32 \
  --train.minibatch-size 2048 --train.learning-rate 0.015 \
  --train.gamma 0.995 --train.gae-lambda 0.9 --train.replay-ratio 1.0 \
  --train.ent-coef 0.001 --policy.hidden-size 64 --policy.num-layers 1 \
  --checkpoint-interval 512
```

| Metric | Final value |
| --- | ---: |
| GPU mode | 1 GPU, RTX 5060 |
| SPS | **99,829** |
| Timesteps | 1,048,576 |
| Agents / buffers / threads | 64 / 4 / 4 |
| Puffer / train seed | 73 / 42 |
| Start failures / engine failures | **0 / 0** |
| Completed episodes | 115 |
| Overall win / loss / draw | 0 / 115 / 0 |
| Close episodes | 50 (43.4783%) |
| Close win / loss rate | 0% / 100% |
| Medium episodes | 65 (56.5217%) |
| Medium win / loss rate | 0% / 100% |
| Enemy attack orders per episode | 9.0261 |

This is a full PufferLib GPU-path baseline for the new workload, not a subsystem speedup claim. The
change intentionally alters episode workload by mixing spawn distances, so a native before/after
profiler ratio would not isolate implementation cost.

The policy won some early training windows but collapsed by the post-training evaluation. This run validates the
balanced curriculum, reporting, GPU throughput, and active opponent path. It does not certify a
generalized close/medium policy. The next training decision should use per-bucket checkpoint
evaluation rather than selecting only the final checkpoint or aggregate `perf`.

## Full Build/Test/Train/Eval Acceptance

W&B: [`bakj8jl2` / `distinctive-blaze-2`](https://wandb.ai/kinvert-k/cnc2/runs/bakj8jl2)

The uncommitted working tree based on `41a219e` passed the complete acceptance gate before this run:

- generated rules and map rebuilt without drift;
- all Zig tests passed in Debug, ReleaseSafe, and ReleaseFast;
- the ReleaseFast static ABI library rebuilt;
- both `TiberianDawn.so` and the windowed `VanillaTD` executable rebuilt;
- the `cnc_micro` PufferLib CUDA/native extension rebuilt;
- the C API, Puffer C binding, focused Vanilla TD Micro test, and oracle tools compiled with warnings
  treated as errors where supported;
- all 14 Vanilla CTest targets passed; and
- independent close and medium Vanilla oracle recordings matched byte-for-byte at the hashes above.

The training run used the same reward vector and training hyperparameters as the initial run. Only
the W&B group and tag changed:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
source .venv/bin/activate
export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc2 --wandb-group balanced-spawn-acceptance \
  --tag full-build-test-train-eval \
  --train.gpus 1 --env.seed 1 --env.max-decisions 12000 \
  --env.reward-milestone 0.2 \
  --env.reward-player-infantry 0.03030131620399178 \
  --env.reward-enemy-unit-loss 0.0054265722298487366 \
  --env.reward-enemy-building-loss 0.7301079315055825 \
  --env.reward-player-unit-loss 0.0 \
  --vec.total-agents 64 --vec.num-buffers 4 --vec.num-threads 4 \
  --train.total-timesteps 1048576 --train.horizon 32 \
  --train.minibatch-size 2048 --train.learning-rate 0.015 \
  --train.gamma 0.995 --train.gae-lambda 0.9 --train.replay-ratio 1.0 \
  --train.ent-coef 0.001 --policy.hidden-size 64 --policy.num-layers 1 \
  --checkpoint-interval 512
```

| Metric | Acceptance value |
| --- | ---: |
| SPS | **94,174** |
| Timesteps | 1,048,576 |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| Puffer / train seed | 73 / 42 |
| GPU mode | 1 GPU |
| Start failures / engine failures | **0 / 0** |
| Post-training episodes | 115 |
| Overall win / loss / draw | 0 / 115 / 0 |
| Close episodes and W/L | 50; 0/50 |
| Medium episodes and W/L | 65; 0/65 |
| Enemy attack orders per episode | 9.0261 |

The two final checkpoint files have the same SHA-256,
`251a42b190fc48929b5fdd4a2342ea6cc30dd374e0940e0832ef9fbb43172a8b`. Direct sampled evaluation
of that policy produced 0/3 close wins and 0/3 medium wins. The 2,048-step checkpoint,
`1c4d04197c0f94c2823b5762267740cb811b90ce23f7d696746d82c1d9cbdc34`, produced 0/3 close wins
and 1/3 medium wins. These six-sample checks are policy sanity checks, not statistical estimates.

Repeated sampled inference matched both the complete observation/mask trace and terminal log:

```text
early close,  seed 1 / sample 74  e1e2f64df98201902b5ebe8af461b2b3af39c621f14529b480db4170ace835b9  loss
early medium, seed 2 / sample 75  af895269f61d45dcc6efcd1e94225b84ea319d08fa861d8f70dcbc0ea5051e29  win
final close,  seed 1 / sample 74  7dfcf591f72ce5586197fb4bb248f4061605bfd6da1fc5d0e520ac5e4cf91e45  loss
final medium, seed 2 / sample 74  640aabba75636eb864cb493dc7ec0cde55c92bda7fe7759eafbdd0048a93b9a1  loss
```

This acceptance establishes a complete, deterministic build-to-evaluation path and a valid
94K-class workload measurement. It also reproduces policy collapse: the final checkpoint is worse
than an early checkpoint and must not be promoted. Checkpoint selection needs fixed sampled-seed,
per-profile evaluation during training before spending compute on a longer run.

The machine-readable Puffer run record is `PufferLib/logs/cnc_micro/bakj8jl2.json`.

## Authoritative W&B Default Reproduction

W&B: [`3mq4ot3x` / `trim-fire-3`](https://wandb.ai/kinvert-k/cnc2/runs/3mq4ot3x)

The complete `cnc1/lqkwukxi` config was fetched from the W&B API and compared against a plain
`load_config("cnc_micro")`. Before correction, the INI's five active reward values were the sweep
proposal means rather than the winning run's sampled values, and the top-level checkpoint interval
was 500 rather than 512. The inherited vector, policy, encoder, PPO, optimizer, V-trace, and
prioritized-replay values already matched. The INI now pins all of them explicitly.

The fresh run used no model checkpoint and no learning override; only W&B labels were supplied:

```bash
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc2 \
  --wandb-group lqkwukxi-defaults-balanced \
  --tag fresh-seed42-defaults-1m
```

The saved run records for `lqkwukxi` and `3mq4ot3x` have zero differences across every key in
`env`, `vec`, `policy`, `torch`, and `train`. Effective training values included 64 agents, 4
buffers, 4 threads, horizon 32, minibatch 2,048, hidden size 64 with one layer, learning rate 0.015,
replay ratio 1.0, `prio_alpha=0.8`, `prio_beta0=0.2`, and one GPU.

| Metric | Result |
| --- | ---: |
| Timesteps | 1,048,576 |
| SPS | **105,003** |
| Start failures / engine failures | **0 / 0** |
| Post-training win / loss / draw | **0 / 115 / 0** |
| Close episodes and W/L | 50; 0/50 |
| Medium episodes and W/L | 65; 0/65 |
| Enemy attack orders per episode | 9.0261 |

The 2,048-step checkpoint hash is
`1c4d04197c0f94c2823b5762267740cb811b90ce23f7d696746d82c1d9cbdc34`; the final hash is
`251a42b190fc48929b5fdd4a2342ea6cc30dd374e0940e0832ef9fbb43172a8b`. Both exactly match the
corresponding `bakj8jl2` checkpoints. This proves the corrected defaults reproduce the intended
experiment and rules out an omitted hyperparameter as the cause of failure. For train seed 42, the
mixed close/medium rollout distribution deterministically drives the same late policy collapse.

## Transfer Success Versus Fresh-Training Collapse

There is no checkpoint/evaluator contradiction. `lqkwukxi` was trained from random initialization
with all 64 environments using the close seed-1 reset. The ABI-6 runs start from random initialization
with 32 close and 32 medium environments. A frozen mature strategy can generalize to the medium
spawn even when PPO from random weights does not reliably rediscover that strategy under the mixed
rollout distribution.

The downsampled learning records show that the mixed learner initially succeeds and then collapses:

| Approximate step | lqkwukxi perf / entropy / units built | 3mq4ot3x perf / entropy / units built |
| ---: | ---: | ---: |
| 200K | 0.331 / 12.306 / 14.89 | **0.595 / 11.479 / 26.21** |
| 450K | 0.092 / 7.659 / 42.66 | **0.000 / 3.543 / 19.99** |
| 710-722K | 0.393 / 6.419 / 14.46 | **0.000 / 2.186 / 10.40** |
| final | **0.978 / 6.408 / 24.24** | 0.000 / 2.882 / 1.13 |

The first post-update checkpoint already differs after 2,048 steps (`59ee1e66...` close-only versus
`1c4d041...` balanced), because half of the first rollout observations and resulting advantages are
different. The balanced run's final building destruction rate is zero and production falls to 1.13
units per episode. This is consistent with premature entropy collapse under the high 0.015 learning
rate, long credit horizon, and seven independently sampled action heads; it is not evidence that the
winning weights cannot execute the new profile.

The remaining clean causal control is a current-ABI all-close fresh run versus an all-medium fresh
run, with every other setting and seed fixed. That A/B should precede a broad sweep if the goal is to
separate spawn-mixture gradient interference from any other code-snapshot effect.

## Existing Champion Transfer

The failed fresh training runs do not imply that the balanced environment is unsolved. The existing
`lqkwukxi` checkpoint was evaluated without updates on 256 fresh categorical samples per profile:

```text
close:  250 wins / 6 losses / 0 draws  (97.6562%)
medium: 256 wins / 0 losses / 0 draws  (100.0000%)
total:  506 wins / 6 losses / 0 draws  (98.8281%)
```

It also won a real seed-2 medium-spawn Vanilla match at frame 3,687 with zero failures. At that
stage, it was promoted unchanged and no warm-start sweep was justified on the current two-profile
curriculum. It remains the historical transfer baseline; full commands, loss audit, replay hashes,
and visible telemetry are in `docs/td_micro/lqkwukxi_balanced_abi6_eval.md`.

## Fresh Balanced Champion

The later stability sweep and retained reproduction resolved the fresh-training collapse without
changing the curriculum or reward vector. Run
[`lwgwyjl7` / `cool-surf-104`](https://wandb.ai/kinvert-k/cnc2/runs/lwgwyjl7) trained from scratch
on the 32-close/32-medium mixture and finished **257/0/0 close**, **248/0/0 medium**, and
**505/0/0 overall** at 97,772 SPS with zero start or engine failures.

Its retained checkpoint SHA-256 is
`46695237efbb6d350971e1163a54c57877a897d487c2b9f7873f3b16dce275e7`. Deterministic native
checks passed for both profiles, and the same checkpoint won a real medium-spawn Vanilla match.
Source/config is frozen at `1625e88`; the authoritative promotion record is
`docs/td_micro/lwgwyjl7_balanced_champion.md`.
