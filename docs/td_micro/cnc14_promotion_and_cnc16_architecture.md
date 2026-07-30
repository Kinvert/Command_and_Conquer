# CNC14 Promotion And CNC16 Native Architecture Ablation

Date: 2026-07-20

## Decision

- Promote `vqsw4ned` as the current ABI9 MinGRU training baseline.
- Keep the native MLP implementation as a tested architecture control.
- Do not replace MinGRU with MLP. Corrected MLP lost both median and worst-seed comparisons.
- Do not claim an architecture throughput speedup from these runs. Their training SPS observations
  were not collected as an adjacent A/B benchmark.

## CNC14 Untouched Promotion Suite

The confirmation-stage evaluator seed `9173` was not reused. The locked promotion suite
`cnc14-promotion-v1` used evaluation seed `19173`, exactly 512 close games and 512 medium games per
checkpoint, and the nine checkpoints declared before evaluation began. All 9,216 scored games were
valid. Every native result reported `start_failures=0` and `failures=0`.

Selection order was declared before the seed bank was opened:

1. all three training seeds must win at least one game in both profiles;
2. median robust score across training seeds;
3. worst-seed minimum-profile win rate;
4. worst robust score, then mean robust score.

`robust` is the epsilon-shifted harmonic mean of close and medium terminal win rates.

| Configuration | Seed | Close | Medium | Robust |
| --- | ---: | ---: | ---: | ---: |
| `vqsw4ned` | 173 | 0.283203 | 0.214844 | 0.244513 |
| `vqsw4ned` | 174 | 0.238281 | 0.302734 | 0.266805 |
| `vqsw4ned` | 175 | 0.082031 | 0.107422 | 0.093188 |
| `o5e9lorj` | 173 | 0.154297 | 0.375000 | 0.220310 |
| `o5e9lorj` | 174 | 0.171875 | 0.193359 | 0.182018 |
| `o5e9lorj` | 175 | 0.025391 | 0.021484 | 0.023323 |
| `4pkdtoqj` | 173 | 0.041016 | 0.021484 | 0.028938 |
| `4pkdtoqj` | 174 | 0.179688 | 0.074219 | 0.106648 |
| `4pkdtoqj` | 175 | 0.039062 | 0.058594 | 0.047207 |

| Rank | Configuration | Median robust | Worst robust | Worst seed/profile |
| ---: | --- | ---: | ---: | ---: |
| 1 | `vqsw4ned` | **0.244513** | **0.093188** | **0.082031** |
| 2 | `o5e9lorj` | 0.182018 | 0.023323 | 0.021484 |
| 3 | `4pkdtoqj` | 0.047207 | 0.028938 | 0.021484 |

The locked manifest, exact episode rows, action hashes, and summaries are under:

```text
PufferLib/logs/cnc_micro/cnc14_promotion_v1/
```

## Native MLP Implementation Gate

The native CUDA backend previously ignored `[torch].network` and always constructed MinGRU.
Setting `network=MLP` was therefore not a valid experiment. The native selector now supports:

- `MinGRU`: unchanged fused recurrent layer and checkpoint layout;
- `MLP`: one or more `Linear(hidden, hidden) + GELU` feedforward blocks with native rollout,
  backward, parameter-gradient, checkpoint, and fixed-evaluator support.

The architecture smoke performs one real rollout and optimizer update, writes a temporary policy
checkpoint, and verifies its exact layout.

| Network | H/L | Parameters | Checkpoint bytes | Start failures | Failures |
| --- | --- | ---: | ---: | ---: | ---: |
| MinGRU | 64/1 | 187,392 | 749,568 | 0 | 0 |
| MLP | 64/1 | 179,264 | 717,056 | 0 | 0 |

This is a real nonlinear MLP control. A zero-layer MinGRU would only leave two bias-free linear
maps and was rejected as an invalid MLP comparison.

Two independent corrected-MLP native evaluations of the same 32-game suite produced the exact
same episode/action digest:

```text
d77501e32b2635c641b776479ee68f45065d906970734f78c9e3331066aa77ca
```

### Rejected CNC15 Attempt

The first CNC15 MLP pass was invalidated before commit. Forward added the learned bias before GELU,
but backward evaluated the GELU derivative at the pre-bias activation. The final biases were
material, with mean absolute values from 0.0453 to 0.0509 and maxima from 0.1888 to 0.2354, so the
error could not be dismissed. None of the CNC15 MLP scores or checkpoints are promotion evidence.

The correction stores the exact biased GELU argument for backward. A focused source regression,
native rebuild, and rollout/update/checkpoint smoke passed before any replacement training began.
CNC16 uses new tags, run ids, checkpoint hashes, W&B project, suite id, and untouched eval seed.

## CNC16 Matched Architecture Suite

The locked `cnc16-architecture-v2` protocol held the promoted `vqsw4ned` environment, rewards,
optimizer, vector shape, hidden size, one network layer, training budget, and seeds constant. The
only changed field was `torch.network`.

- Training seeds: 173, 174, 175.
- Training budget: 2,097,152 transitions per seed.
- MinGRU checkpoints: reused from CNC14 without retraining.
- MLP project/runs: `cnc16`, runs `2vhko2vc`, `01q7oyrh`, and `6ntrrhe0`.
- Fresh comparison seed: `39173`.
- Evaluation: 512 close plus 512 medium games per checkpoint, 6,144 games total.
- Validity: all six evaluations had zero start and engine failures.

| Network | Seed | Close | Medium | Robust |
| --- | ---: | ---: | ---: | ---: |
| MinGRU | 173 | 0.257812 | 0.240234 | 0.248725 |
| MinGRU | 174 | 0.203125 | 0.345703 | 0.256545 |
| MinGRU | 175 | 0.058594 | 0.132812 | 0.082675 |
| MLP | 173 | 0.039062 | 0.121094 | 0.061402 |
| MLP | 174 | 0.177734 | 0.132812 | 0.152221 |
| MLP | 175 | 0.033203 | 0.001953 | 0.008725 |

| Network | Median robust | Mean robust | Worst robust | Worst seed/profile |
| --- | ---: | ---: | ---: | ---: |
| MinGRU | **0.248725** | **0.195982** | **0.082675** | **0.058594** |
| MLP | 0.061402 | 0.074116 | 0.008725 | 0.001953 |

The corrected MLP is substantially worse in typical, mean, and worst-seed performance. Removing
recurrence does not solve the instability and gives up useful policy capacity under the current
flat observation encoder. With three seeds, this is a rejection of this specific H64/L1 MLP as the
baseline, not a precise estimate of every feedforward architecture.

The locked manifest and raw results are under:

```text
PufferLib/logs/cnc_micro/cnc16_architecture_v2/
```

Checkpoint hashes are pinned in that manifest. The three MLP checkpoint hashes are:

```text
2vhko2vc  0e0b710ee13af0854e47ca3d5909748098b26fb082dfabd0547627e4e4977d8c
01q7oyrh  5477e667260a852312e87cbd98509d708d9da999b99bf3bf174f176bd1bde2b2
6ntrrhe0  e6bfa06494a5276985075ab1ff68db9e721be55e3919ca5102c03922cc565c9c
```

## Commands

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib

.venv/bin/python ../tools/test_cnc13_stable_confirmation.py
.venv/bin/python ../tools/test_cnc_micro_fixed_eval.py
.venv/bin/python ../tools/test_cnc16_architecture_ablation.py

.venv/bin/python ../tools/cnc13_stable_confirmation.py --project cnc14 promote --execute --workers 1

.venv/bin/python ../tools/cnc_micro_native_arch_smoke.py --network MinGRU
.venv/bin/python ../tools/cnc_micro_native_arch_smoke.py --network MLP

.venv/bin/python ../tools/cnc_micro_fixed_eval.py \
  checkpoints/cnc_micro/2vhko2vc/0000000002097152.bin \
  --puffer-root="$PWD" --output=/tmp/cnc16-mlp-det-a.json \
  --episodes-per-profile=16 --eval-seed=49173 --num-buffers=4 --num-threads=4

.venv/bin/python ../tools/cnc16_architecture_ablation.py run --execute
.venv/bin/python ../tools/cnc16_architecture_ablation.py evaluate --execute
.venv/bin/python ../tools/cnc16_architecture_ablation.py report
```

The build uses the repository's documented `./build.sh cnc_micro` CUDA/native command. None of
these runs used `--slowly`, `--cpu`, or sweep-only configuration.

## Next Decision

Keep MinGRU and ABI9 fixed for the next representation experiment. The highest-leverage next model
change is a typed observation encoder with stable entity identity and masked entity/spatial pooling,
not another action ABI or another broad hyperparameter sweep. Exact full-state continuation and
Zig/Vanilla policy-path parity remain independent acceptance gates.
