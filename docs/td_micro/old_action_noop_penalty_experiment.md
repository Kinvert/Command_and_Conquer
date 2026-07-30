# ABI9 Invalid-Noop Penalty Experiment

Date: 2026-07-19

Status: complete; ABI9 historical regressions pass, the broad 1M screen is diagnosed, and the
matched 2M coefficient study rejects a nonzero invalid-action penalty

## Result

The historical ABI9 action transport now runs on the current simulator without changing commits or
tags. `PufferLib/config/cnc_micro.ini` selects it with `action_abi = 9`; setting `action_abi = 13`
selects the retained conditional actor-target reference. Both use observation version 5 and the
same current TD Micro simulation, map, Easy AI, rewards, terminals, and reset path.

ABI9 is the seven-head `MultiDiscrete` action:

```text
{12, 65, 6, 4, 64, 64, 64}
command, actor, product, target kind, x, y, target slot
```

Its 279-byte mask is intentionally independent by head. A cross-head tuple can therefore be
sampled even when the complete tuple is illegal. Such a tuple is rejected by `input.apply`, counted
as invalid, and treated as a canonical no-op: the decision is consumed and the Easy AI plus world
still advance the normal four simulation frames. There is no repair and no invalid-streak terminal.

## Penalty Contract

`reward_invalid_action` defaults to zero and accepts a finite value in `[-1, 0]`. The first isolated
sweep grid is exactly:

```text
0, -0.000025, -0.00005, -0.0001, -0.00025
```

The cumulative emitted invalid-action cost is capped at `-0.5` per episode. A terminal win, loss, or
draw replaces all shaping on its decision, so an invalid penalty computed on the terminal decision
is not emitted or included in `invalid_action_penalty`. Explicit `noop` is valid and unpenalized.

Puffer logs both:

- `invalid_actions`: rejected tuples from completed episodes only;
- `invalid_action_penalty`: actual capped cost emitted per completed episode.

This required correcting an older aggregation bug that mixed invalid actions from ongoing worlds
into the completed-episode denominator. On the fixed `-0.0001` smoke, the coherent result is 636
invalid actions over 1,285 decisions and `-0.0635005` emitted cost. The one-action difference from
`-0.0636` is the replaced terminal-step shaping.

## Exact Penalty-Zero Regression

Command from `PufferLib/`:

```bash
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 \
LD_LIBRARY_PATH=/usr/lib/wsl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib \
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --env.action-abi 9 \
  --env.reward-invalid-action 0 \
  --vec.total-agents 64 \
  --vec.num-buffers 1 \
  --vec.num-threads 4 \
  --train.total-timesteps 2097152 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 512 \
  --tag abi9-forward-port-final
```

Configuration: CUDA training, 64 agents, one buffer, four threads, horizon 32, minibatch 2,048,
hidden 64x1, and 2,097,152 timesteps. The final displayed bucket was 36,352 SPS. This is a valid
learning/determinism run, not a speedup claim: `start_failures=0` and engine `failures=0`.

Final metrics from `PufferLib/logs/cnc_micro/1784495166645.json`:

| Metric | Value |
| --- | ---: |
| `perf` | 0.468619 |
| `balanced_perf` | 0.421753 |
| Close win rate | 0.202128 |
| Medium win rate | 0.641379 |
| Corrected invalid actions / completed episode | 1,983.715 |
| Applied invalid penalty | 0 |

Checkpoint SHA-256 gates match the historical ABI9 run exactly:

| Timesteps | SHA-256 |
| ---: | --- |
| 2,048 | `138a8b4e997aa5a3d46f1037477c2119c759ed5995fc0c94f8315e4e6494fb14` |
| 1,050,624 | `71478a42716181cf724e691bca143209c23372614ac5476faeea34d0744e48e6` |
| 2,097,152 | `490064539416022a02179b47136a74219ed37a618fcfa6173cabc659510c7a37` |

The exact hashes prove that the forward-port, dynamic action metadata, generic CUDA sampler route,
and zero-valued penalty preserve the historical policy update sequence bit for bit.

## Historical Best-Code Audit

The strongest older ABI9 runs did not use a different simulator or observation contract:

- CNC5 `b9sj4ihr` and CNC6 `qj7bux1j` both record base commit
  `83dea42d017aab29d88f38d321ea44def8d68b45`.
- Tag `td-micro-abi9` at `fd74644` is the frozen pre-action-redesign reference.
- The current worktree is based at `09c666b` and forward-ports that ABI9 command decoder and mask
  onto the current simulator. The observation remains version 5.
- At the time of the CNC8 broad screen, the configured sweep ranges were unchanged relative to
  `fd74644` except for the explicit `action_abi` selector and the categorical invalid-penalty
  coefficient. The focused post-study sweep configuration is intentionally narrower; see below.

The CNC5 W&B archive retains its full configuration and base commit but no dirty-worktree patch, so
the commit alone is not a byte-complete old source snapshot. This is why the current regression uses
observable behavior plus the separately retained CNC6 checkpoint hashes rather than trusting the
commit label by itself.

The current `policy_abi9.zig` delegates observation packing to the current observation-v5 encoder,
but preserves ABI9's seven action heads, independent masks, decoder, and invalid-as-noop behavior.
The exact CNC6 checkpoint hashes above are the byte-level gate for that claim.

### Exact CNC5 Winner Reproduction

The complete historical `b9sj4ihr` configuration was rerun on the current ABI9 worktree with every
environment, vector, network, PPO, and reward value fixed. It used normal PufferLib CUDA training,
not `--slowly` and not CPU training.

```bash
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 --train.seed 42 --train.total-timesteps 5000000 \
  --vec.total-agents 64 --vec.num-buffers 2 --vec.num-threads 4 \
  --env.seed 1 --env.max-decisions 12000 --env.action-abi 9 \
  --env.reward-milestone 0.2 \
  --env.reward-player-infantry 0.03258661490856304 \
  --env.reward-enemy-unit-loss 0.002247313227290637 \
  --env.reward-enemy-building-loss 0.8294312037645342 \
  --env.reward-player-unit-loss 0 \
  --env.reward-refinery 0 --env.reward-first-delivery 0.4 \
  --env.reward-tiberium-income 0.01600434791519773 \
  --env.reward-invalid-action 0 \
  --policy.hidden-size 32 --policy.num-layers 4 \
  --train.learning-rate 0.0021215680597303508 \
  --train.gamma 0.9956981579826178 --train.gae-lambda 0.995 \
  --train.replay-ratio 3.0134766192909708 \
  --train.clip-coef 0.4914978911429064 \
  --train.vf-coef 0.9845955806717972 \
  --train.vf-clip-coef 2.35832528429639 \
  --train.max-grad-norm 0.25 --train.ent-coef 0.0014435690687336343 \
  --train.beta1 0.9726218968517497 --train.beta2 0.9133334328758781 \
  --train.eps 4.685399074244875e-08 \
  --train.minibatch-size 2048 --train.horizon 32 \
  --train.vtrace-rho-clip 1.1420133358877036 \
  --train.vtrace-c-clip 2.7571669441891027 \
  --train.prio-alpha 0.25389988761806925 \
  --train.prio-beta0 0.9457733193874489 \
  --checkpoint-interval 512 --tag b9-current-abi9-exact-reproduction
```

Historical and current final evaluation results match exactly across 528 completed episodes:

| Metric | Historical `b9sj4ihr` | Current ABI9 |
| --- | ---: | ---: |
| Actual training steps | 4,999,168 | 4,999,168 |
| Overall win rate | 0.420454532 | 0.420454532 |
| Balanced win rate | 0.402904242 | 0.402904242 |
| Close win rate | 0.217573240 | 0.217573240 |
| Medium win rate | 0.588235259 | 0.588235259 |
| Loss rate | 0.558712125 | 0.558712125 |
| Draw rate | 0.020833334 | 0.020833334 |
| Units built / kills / losses | 61.321968 / 21.301136 / 49.770832 | 61.321968 / 21.301136 / 49.770832 |
| Buildings destroyed / lost | 2.482955 / 4.875000 | 2.482955 / 4.875000 |
| Tiberium income | 1,159.564453 | 1,159.564453 |
| Start / engine failures | 0 / 0 | 0 / 0 |
| Final displayed SPS | 29,952 | 55,153 |

The SPS values are informative but not a controlled code-only A/B. W&B metadata shows that the old
run was one child of a sweep configured for two concurrent workers on the same GPU, while the
current reproduction ran alone. The current command is valid: 64 agents, two buffers, four threads,
horizon 32, minibatch 2,048, CUDA, and zero start or engine failures.

The current 4,999,168-step checkpoint SHA-256 is
`54cf1dcd8d94d9e5994bedbdc2916523496d31086ef73e2b7f199ef2270cf3fa`. Post-training evaluation
created later checkpoint filenames, but all contain that same frozen model hash. The historical
CNC5 binary was not retained, so this run cannot provide a cross-era model-byte comparison. The
exact CNC6 hashes provide that stronger gate; the CNC5 run independently proves unchanged final
policy quality and behavior. The old/current `invalid_actions` display differs because completed-
episode aggregation was corrected, not because episode outcomes changed.

## Sweep And Trace Gates

An official five-run CUDA sweep smoke varied only `env.reward_invalid_action`. All five children
detected seven action heads, completed 65,536 timesteps, reported `start_failures=0`, and ranged from
about 69K to 82K displayed SPS. This validates sweep plumbing only; 65,536 steps is not a learning
comparison.

Win trace version 3 records the selected action ABI and all nine reward coefficients. The replay
tool chooses the matching ABI9 or ABI13 observe/step path and retains readers for legacy v1/v2
layouts. A real ABI9 winning trace was replayed twice:

```text
actions=3036 reward=1 wins=1 losses=0 draws=0 failures=0 invalid=1568
trajectory_hash=bde325c624eac593
```

## Corrected `cnc8` Broad 1M Screen

The accepted broad screen used 100 CUDA trials of 1,048,576 timesteps and varied 29 PPO,
architecture, vectorization, reward, and invalid-action dimensions. It did not use `sweep_only`.
`train.total_timesteps` was the sole excluded sweep dimension.

```bash
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 \
LD_LIBRARY_PATH=/usr/lib/wsl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cu13/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/nccl/lib:$PWD/.venv/lib/python3.12/site-packages/nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib \
.venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --sweep.max-runs 100 \
  --sweep.gpus 1 \
  --train.gpus 1 \
  --train.total-timesteps 1048576 \
  --wandb \
  --wandb-project cnc8
```

The W&B project also contains invalid preliminary runs. The accepted subset begins at
`pious-aardvark-54` (`45nbsani`) and ends at `feasible-wave-153` (`fl8q0jj4`). Exactly 100 local
JSON records belong to this subset, and all 100 have zero `start_failures`.

| Result | Corrected ABI9 `cnc8` | ABI10 `cnc7` |
| --- | ---: | ---: |
| Trials | 100 | 100 |
| Best balanced performance | 0.175109 | 0.396091 |
| Mean balanced performance | 0.014854 | 0.027950 |
| Median balanced performance | 0 | 0 |
| Nonzero trials | 37 | 32 |

The corrected ABI9 screen is worse at the top and on mean quality than the prior ABI10 1M screen,
despite a slightly higher nonzero hit count. The repeated ABI13 matched-default result is also
higher at 0.383830 after 1M. The raw campaign result is real, but it is not an ABI9 code-regression
result: the exact 2M hashes and exact CNC5 reproduction above reject that explanation.

The best corrected run is `b61p3rrm`: balanced performance 0.175109, direct win performance
0.175000, 55,553 SPS, hidden 32x7, horizon 64, and invalid penalty `-0.00025`. Across all accepted
trials, final displayed SPS ranges from 34,787 to 126,015 with a 66,274.5 median; this is not a
matched throughput comparison because the sweep varies model and rollout shapes.

Penalty allocation was strongly imbalanced after Protein adapted:

| Invalid coefficient | Trials | Best | Mean | Nonzero |
| ---: | ---: | ---: | ---: | ---: |
| `-0.00025` | 56 | 0.175109 | 0.024034 | 29 |
| `-0.0001` | 18 | 0.052381 | 0.006603 | 6 |
| `-0.00005` | 15 | 0.010309 | 0.001375 | 2 |
| `-0.000025` | 9 | 0 | 0 | 0 |
| `0` | 2 | 0 | 0 | 0 |

The extra 29th dimension is not an adequate explanation. The failure came from where the adaptive
optimizer spent its trials:

| Structural choice | CNC7 ABI10, 100 trials | CNC8 ABI9, 100 trials |
| --- | ---: | ---: |
| Horizon 32 | 93 | 4 |
| One MinGRU layer | 47 | 2 |
| One buffer | 62 | 2 |
| Hidden 32 or 64 | 43 | 92 |
| Horizon 32 + one layer + one buffer + hidden 32/64 | 15 | 1 |

That one CNC8 sample in the complete historical ABI9 success shape was the default bootstrap. Its
`qj7bux1j` configuration is tuned for a 2M cosine schedule and scored zero when retrained with a 1M
schedule. Among the initial exploratory proposals, only one early run scored nonzero: 0.009259 at
horizon 64, three layers, and four buffers. Protein then exploited that weak signal. The final CNC8
population contained 92 horizon-64 trials, 98 multi-layer trials, and 61 eight-buffer trials. Its
best run, `b61p3rrm`, is therefore from a 32x7, horizon-64, eight-buffer, LR-0.01594 basin, not the
known successful ABI9 basin.

This differs sharply from CNC7, where duplicate default bootstraps each scored 0.101742 and gave
Protein a useful horizon-32/one-layer/one-buffer signal. It also agrees with the longer CNC6 ABI9
history: its first 100 broad 2M trials averaged 0.0071 with no result above 0.2; the raw winner did
not arrive until trials 301-400 and the robust winner until trials 601-700. A sparse terminal metric
can send a 100-trial adaptive screen down a bad branch even when the dimensional count is unchanged.

With `anneal_lr = 1`, changing the total budget from 2M to 1M changes every learning-rate value
after initialization; a 1M run is not a stopped prefix of the 2M run. The known 2M trace reports
0.265530 in its approximately 0.81M aggregate bucket before reaching 0.421753, but retraining with a
1M schedule follows a different optimizer trajectory.

Two sweep-plumbing faults were found before the accepted subset. An accidental
`sweep_only = env.reward_invalid_action` made the first attempt effectively fixed, and PufferLib's
`idx > 1` condition used defaults for both of its first two trials despite claiming only the first
was the bootstrap. The first setting was removed; the scheduler now uses sampled values beginning
at index 1. Tests preserve that bootstrap boundary and separately pin the current focused
25-dimensional search surface.

## Matched CNC9 2M Coefficient Study

The coefficient decision used a fixed factorial study, not an adaptive sweep. Every run used the
exact historical `qj7bux1j` environment, PPO, vector, network, and 2M cosine schedule. Only the
invalid-action coefficient and the top-level Puffer seed changed:

```bash
PufferLib/.venv/bin/python tools/run_abi9_penalty_study.py --project cnc9 --execute
PufferLib/.venv/bin/python tools/analyze_abi9_penalty_study.py --project cnc9
PufferLib/.venv/bin/python tools/evaluate_abi9_penalty_study.py
```

Shape: CUDA training, 64 agents, one buffer, four threads, horizon 32, minibatch 2,048, hidden
64x1, and 2,097,152 timesteps per run. All 15 runs completed with `start_failures=0` and engine
`failures=0`, for 31,457,280 valid transitions total. Final displayed SPS ranged from 25,178 to
55,751, with a median of 38,157. This is not a speedup comparison because learned behavior and
episode lengths differ by arm.

The study uncovered an important seed-contract detail. Top-level `--seed` controls the policy and
training trajectory used by this backend; changing only `--train.seed` produced byte-identical
checkpoints. The accepted matrix therefore holds `train.seed=42` fixed and uses top-level seeds
73, 74, and 75. Two setup runs that varied only `train.seed` are excluded by exact run tags and
configuration validation in the analyzer.

Puffer's normal train command freezes the final policy and runs a post-training evaluation window.
The first table is that built-in result:

| Invalid coefficient | Built-in eval, seeds 73 / 74 / 75 | Median | Worst | Mean | Mean invalid actions | Mean emitted cost | Median final SPS |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `0` | 0.421753 / 0.182921 / 0.000000 | **0.182921** | 0 | **0.201558** | 2,557.351 | 0 | 37,510 |
| `-0.000025` | 0.057759 / 0.000000 / 0.113750 | 0.057759 | 0 | 0.057170 | 1,610.074 | -0.040246 | 38,168 |
| `-0.00005` | 0.100904 / 0.000000 / 0.000000 | 0 | 0 | 0.033635 | 1,145.785 | -0.057285 | 29,675 |
| `-0.0001` | 0.077721 / 0.000000 / 0.145745 | 0.077721 | 0 | 0.074489 | 587.835 | -0.058773 | 43,804 |
| `-0.00025` | 0.234876 / 0.000000 / 0.000000 | 0 | 0 | 0.078292 | 207.063 | -0.051139 | 50,593 |

The clean evaluator removes two remaining confounders from that built-in window: each checkpoint
starts from fresh worlds, and all checkpoints use the same held-out policy-sampling seed 173. It
uses the native CUDA backend for policy inference with 64 agents, one buffer, four threads, and
horizon 32, but performs no optimizer updates. Each checkpoint ran to at least 256 completed
episodes. Across 15 checkpoints it evaluated 3,843 episodes and 21,037,056 transitions with zero
start or engine failures. Evaluation SPS ranged from 26,590 to 66,893, with a median of 41,414;
policy behavior differs, so this is not a speedup comparison.

| Invalid coefficient | Fresh paired eval, train seeds 73 / 74 / 75 | Median | Worst | Mean | Mean invalid actions | Mean units built | Median eval SPS |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `0` | 0.476479 / 0.228026 / 0.000000 | **0.228026** | 0 | **0.234835** | 2,303.972 | 57.126 | 43,266 |
| `-0.000025` | 0.069809 / 0.000000 / 0.168461 | 0.069809 | 0 | 0.079423 | 1,422.716 | 50.927 | 40,895 |
| `-0.00005` | 0.145039 / 0.000000 / 0.000000 | 0 | 0 | 0.048346 | 1,126.502 | 43.190 | 29,324 |
| `-0.0001` | 0.050727 / 0.000000 / 0.226417 | 0.050727 | 0 | 0.092381 | 565.525 | 53.087 | 44,941 |
| `-0.00025` | 0.268441 / 0.000000 / 0.003846 | 0.003846 | 0 | 0.090762 | 187.303 | 30.104 | 48,633 |

The largest penalty reduced invalid tuples by 91.9% relative to zero, but two of three seeds were
effectively collapsed and mean units built fell from 57.126 to 30.104. The policy learned to avoid
penalized activity, not a more robust command strategy. Every coefficient still had one zero-score
seed, so training robustness remains open, but the penalty coefficient is not the fix.

The clean seed-73 zero-penalty run (`i532cn9u`) exactly reproduced the historical final checkpoint:

```text
490064539416022a02179b47136a74219ed37a618fcfa6173cabc659510c7a37
```

An independent 256-episode rerun of that checkpoint exactly matched every non-timing result,
including 1,169,408 transitions and balanced performance 0.476478696. A newly recorded ABI9 win
also passed the replay tool's internal two-run comparison:

```text
actions=1381 reward=1 wins=1 losses=0 draws=0 failures=0 invalid=356
trajectory_hash=058f3df7f1cb883e
```

Decision: keep `reward_invalid_action = 0` and do not promote any nonzero coefficient. The default
sweep now fixes the known structural basin at 2M steps, horizon 32, one layer, one buffer, and ABI9;
it searches hidden size 32/64, learning rate 0.0008-0.0012, entropy 0.0005-0.0025, and the remaining
optimizer/reward dimensions. It contains neither `sweep_only` nor a penalty sweep.

The corrected search surface also passed a three-child official CUDA/W&B sweep smoke:

```bash
.venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --sweep.max-runs 3 --sweep.gpus 1 --sweep.workers-per-gpu 1 \
  --train.gpus 1 --train.total-timesteps 65536 \
  --wandb --wandb-project cnc9 --tag abi9-focused-sweep-smoke
```

All children used 64 agents, one buffer, four threads, horizon 32, minibatch 2,048, ABI9, penalty
zero, and normal GPU training. Runs `s65net5y`, `8t2tnpr6`, and `fmku4i3r` sampled distinct values
inside the focused surface, reported zero start/engine failures, and displayed 68,609, 87,680, and
82,133 SPS respectively. This validates sweep plumbing only; 65,536 steps is not a learning claim.

## Validation

- All 166 Zig tests pass in Debug, ReleaseSafe, and ReleaseFast.
- ABI9 contract and broad cross-head rejection have focused tests.
- Penalty-zero identity, explicit-noop exemption, cap, terminal replacement, and completed-episode
  accounting have focused tests.
- Current ABI13 and ABI9 C API actions produce the same canonical world digest for equivalent
  commands: `cdde069f216661b92e5e030650698b1a7a54641c5e9d1dc068a9b6aa9a2ece4f`.
- Puffer C binding, dynamic action metadata, official sweep parsing, CUDA training, clean paired
  checkpoint evaluation, and v3 winning replay pass.

## Next Experiment

Run a focused 2M sweep from the corrected configuration, retaining `qj7bux1j` and `u6ul1umm` as
controls. Select candidates by fixed-policy close/medium evaluation, repeated-seed stability, and
collapse resistance rather than the best rolling training bucket. ABI13 remains available as the
conditional-scoring reference. CNC5 `b9sj4ihr` remains the 5M historical control; it must not be
compared at a different cosine schedule and called a prefix.
