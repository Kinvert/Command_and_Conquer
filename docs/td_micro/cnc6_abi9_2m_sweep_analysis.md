# CNC6 ABI-9 Sweep Analysis

Date: 2026-07-18

Campaign: [W&B `cnc6`](https://wandb.ai/kinvert-k/cnc6)

Source and launch record: [CNC6 ABI-9 two-million-step sweep](cnc6_abi9_2m_sweep.md)

## Verdict

CNC6 completed successfully and found several real winning policies. It did not produce a retained
checkpoint, and its nominal winner is not the policy that should be promoted first.

- Raw objective winner: `u6ul1umm`, balanced win rate `0.418841`.
- Best two-spawn candidate: `8fcw2lp9`, balanced win rate `0.397582`, with at least `0.357664` on
  either spawn bucket.
- Existing retained CNC5 baseline: `b9sj4ihr`, balanced win rate `0.402904`, but only `0.217573` on
  its weaker spawn.
- CNC6 therefore did not establish a statistically decisive new raw-score record. It did find a
  much more balanced two-spawn policy in only 2M training steps.
- The learned behavior is still mostly E1 mass production and attack. It is not yet a meaningful
  combined-arms or economy strategy.
- The largest visible learning blocker is the factorized action ABI: roughly 44% to 62% of sampled
  decisions are invalid even with action masks.

The next step is not another 1,000-run broad sweep. Reproduce `u6ul1umm` and `8fcw2lp9` as retained
checkpoints, evaluate them on more sampling seeds, and promote the robust candidate only if that
result repeats.

## Campaign Validity

All 1,000 W&B runs finished. Local logs contain 1,000 matching runs and 999 unique configurations;
the two default bootstrap runs intentionally duplicated one configuration.

| Property | Result |
| --- | ---: |
| Runs completed | 1,000 / 1,000 |
| Training steps per run | 2,097,152 |
| Total training steps | 2,097,152,000 |
| Runs pruned or stopped early | 0 |
| Runs with start failures | 0 |
| Unique configurations | 999 |
| Search dimensions | 28 |
| CUDA trainers | 3 concurrent workers on GPU 0 |

Every trial used 64 agents, 4 environment threads, a 2,048 minibatch, CUDA training, train seed 42,
and environment seed 1. Horizon, buffers, network shape, optimizer values, and rewards were swept.

After training, PufferLib ran rollouts without optimizer updates for up to half as many rollout
epochs. Final scores came from 90 to 512 completed evaluation episodes per run, with a median of
215. The configured `eval_episodes=10000` was never reached because the fixed evaluation epoch
budget ended first.

The policy is sampled during this evaluation. PufferLib's CUDA backend calls `sample_logits`, and
the visible Vanilla integration also uses sampled policy actions. These are not greedy argmax
scores.

## Objective Definition

The sweep maximized:

```text
balanced_perf = 0.5 * (close_win_rate + medium_win_rate)
```

Only Puffer-side wins count. Losses, draws, and engine failures contribute no wins. This metric is
bounded to `[0, 1]` and gives equal weight to close and medium starts even when their episode counts
differ.

`env/perf` is the unbalanced win fraction over all completed episodes. `env/episode_return` is the
shaped training return and can exceed 1. It is not the game score. See the
[reward and return audit](reward_return_scale_audit.md).

## Score Distribution

The campaign found a useful upper tail, but most of the 28-dimensional search space did not learn
much in 2M steps.

| Statistic | Final balanced win rate |
| --- | ---: |
| Maximum | 0.418841 |
| 99th percentile | 0.312965 |
| 95th percentile | 0.189586 |
| 90th percentile | 0.136015 |
| Median | 0.009573 |
| Mean | 0.043271 |
| Zero | 382 runs |

Counts above useful thresholds:

| Threshold | Runs |
| --- | ---: |
| `balanced_perf >= 0.1` | 154 |
| `balanced_perf >= 0.2` | 48 |
| `balanced_perf >= 0.3` | 15 |
| Both spawn win rates `>= 0.2` | 14 |
| Both spawn win rates `>= 0.25` | 7 |
| Both spawn win rates `>= 0.3` | 3 |

Nine runs above `0.2` had a close/medium gap of at least `0.4`. A balanced average alone therefore
does not prevent severe specialization.

## Candidate Ranking

`Min spawn` is the smaller of close and medium win rate. It is the most useful promotion column for
the current two-start curriculum.

| Run | Balanced | Close | Medium | Min spawn | Eval episodes |
| --- | ---: | ---: | ---: | ---: | ---: |
| [`u6ul1umm`](https://wandb.ai/kinvert-k/cnc6/runs/u6ul1umm) | **0.418841** | 0.177305 | 0.660377 | 0.177305 | 459 |
| [`xi4dllew`](https://wandb.ai/kinvert-k/cnc6/runs/xi4dllew) | 0.402078 | 0.238938 | 0.565217 | 0.238938 | 251 |
| [`oo4ronlt`](https://wandb.ai/kinvert-k/cnc6/runs/oo4ronlt) | 0.401635 | 0.020000 | 0.783270 | 0.020000 | 413 |
| [`8fcw2lp9`](https://wandb.ai/kinvert-k/cnc6/runs/8fcw2lp9) | 0.397582 | **0.437500** | 0.357664 | **0.357664** | 297 |
| [`gtaoyvpn`](https://wandb.ai/kinvert-k/cnc6/runs/gtaoyvpn) | 0.379108 | 0.314465 | 0.443750 | 0.314465 | 319 |
| [`74lrr38f`](https://wandb.ai/kinvert-k/cnc6/runs/74lrr38f) | 0.334450 | 0.305263 | 0.363636 | 0.305263 | 183 |
| [`pkczdmfq`](https://wandb.ai/kinvert-k/cnc6/runs/pkczdmfq) | 0.312950 | 0.294964 | 0.330935 | 0.294964 | 278 |
| [`xi2kmpg3`](https://wandb.ai/kinvert-k/cnc6/runs/xi2kmpg3) | 0.303731 | 0.295775 | 0.311688 | 0.295775 | 148 |

### Raw Winner: `u6ul1umm`

W&B name: `pretty-field-317`.

It won 25/141 close episodes and 210/318 medium episodes, with 2 draws. Its overall win fraction is
235/459, or `0.511983`, but the equal-spawn objective correctly reduces that to `0.418841`.

Its logged balanced curve was:

```text
0.019583, 0.224306, 0.361993, 0.377062, 0.418841
```

This is a clean rising trace, but the policy is highly specialized to the medium start. It is useful
as the raw-score reproduction target, not as the default visible-inference candidate.

### Robust Candidate: `8fcw2lp9`

W&B name: `polished-pine-656`.

It won 70/160 close episodes and 49/137 medium episodes with no draws. Its close/medium gap is only
`0.079836`, compared with `0.483072` for the raw winner.

Its logged balanced curve was:

```text
0.000000, 0.283046, 0.320696, 0.327885, 0.397582
```

This is the first candidate to reproduce for human-visible evaluation because it is the best policy
under the conservative minimum-spawn metric.

## Statistical Uncertainty

Using independent Beta(1,1) priors for each spawn's win probability gives these finite-evaluation
intervals. Counts were reconstructed from the logged episode rates and rounded to exact episodes.

| Candidate | Balanced estimate | Bayesian 95% interval |
| --- | ---: | ---: |
| CNC6 `u6ul1umm` | 0.418841 | 0.381 to 0.463 |
| CNC6 `8fcw2lp9` | 0.397582 | 0.345 to 0.455 |
| Retained CNC5 `b9sj4ihr` | 0.402904 | 0.366 to 0.443 |

Under this simple model, the posterior chance that `u6ul1umm` has a higher balanced win rate than
`b9sj4ihr` is about 72%. That is promising, not decisive. The chance that `8fcw2lp9` is higher on raw
balanced score is about 44%.

On minimum-spawn win rate, `8fcw2lp9` is above the retained baseline with about 99.8% posterior
probability and above `u6ul1umm` with about 99.96%. This is a post-hoc robustness comparison, so it
still needs a retained reproduction.

These intervals account only for finite evaluation episodes. They do not account for:

- selection of the best result from 1,000 trials;
- the common training seed and common deterministic world sequence;
- variation across fresh training seeds;
- policy-sampling seed sensitivity;
- simulator-to-Vanilla transfer mismatch.

The best-of-1,000 point estimates are therefore optimistic.

## CNC5 Comparison

The retained CNC5 reproduction `b9sj4ihr` used 4,999,168 actual training steps with a 32x4 MinGRU.
It evaluated at:

| Metric | CNC5 `b9sj4ihr` | CNC6 `u6ul1umm` | CNC6 `8fcw2lp9` |
| --- | ---: | ---: | ---: |
| Training steps | 4,999,168 | 2,097,152 | 2,097,152 |
| Balanced win rate | 0.402904 | 0.418841 | 0.397582 |
| Close win rate | 0.217573 | 0.177305 | 0.437500 |
| Medium win rate | 0.588235 | 0.660377 | 0.357664 |
| Minimum spawn | 0.217573 | 0.177305 | 0.357664 |
| Eval episodes | 528 | 459 | 297 |

CNC6 did not clearly beat CNC5 on raw score. Its material gain is finding a substantially more
balanced candidate using less than half the training budget.

The current Zig/Vanilla inference code is fixed at 32x4, matching the retained CNC5 model.
`u6ul1umm` is 32x1 and `8fcw2lp9` is 64x1. Neither can be shown in Vanilla until its exact training
run is reproduced with a retained checkpoint and the inference architecture is configured for that
shape.

## Learning Dynamics

Across the five retained log points, population balanced performance evolved as follows:

| Curve statistic | Point 1 | Point 2 | Point 3 | Point 4 | Final |
| --- | ---: | ---: | ---: | ---: | ---: |
| Median | 0.0000 | 0.0052 | 0.0084 | 0.0066 | 0.0096 |
| 90th percentile | 0.0171 | 0.0696 | 0.1059 | 0.1170 | 0.1360 |
| 99th percentile | 0.0530 | 0.1783 | 0.2803 | 0.3014 | 0.3130 |
| Best at point | 0.1091 | 0.3519 | 0.3620 | 0.4003 | 0.4188 |

There were 102 runs whose best logged score exceeded their final score by at least `0.05`, and 26
whose drop was at least `0.10`. Some policies still degrade after an initially useful phase. Because
the final point is a sampled no-update evaluation while earlier points include training rollouts,
this is a warning signal rather than a precise collapse estimate.

Protein's completion-order blocks improved over the night. The first 100 trials averaged `0.0071`
with no result above `0.2`; the final 100 averaged `0.0760` with seven above `0.2`. The raw winner was
already found in the 301-400 block, while the robust winner arrived in the 601-700 block. More broad
search was still improving hit rate but had stopped improving the absolute maximum.

## What The Policies Learned

The strongest correlate of balanced score is buildings destroyed (`Spearman rho=0.884`). Unit kills
(`0.615`), units built (`0.597`), and gunners built (`0.557`) also track success. Unit losses are
positively correlated (`0.612`) because active policies fight more; this is not evidence that losing
units is beneficial.

| Per-episode behavior | All runs mean | Top decile mean |
| --- | ---: | ---: |
| Buildings destroyed | 0.641 | 1.891 |
| Buildings lost | 6.557 | 5.362 |
| Units built | 35.550 | 56.355 |
| E1 built | 24.804 | 46.223 |
| E3 built | 9.910 | 9.466 |
| Unit kills | 13.773 | 20.376 |
| Tiberium income | 632 | 1,090 |
| Refineries built | 0.836 | 0.666 |
| Opponent attack orders | 23.534 | 22.844 |
| Invalid-action fraction | 60.0% | 54.8% |

The enemy is issuing attack orders, so high scores are not explained by a completely inert opponent.
The top policies build more troops, fight, and destroy buildings.

They are not learning combined arms. `u6ul1umm` makes 92.7% E1 among its infantry, and `8fcw2lp9`
makes 91.8% E1. Across the top decile, E1 production nearly doubles while E3 production is flat.
This is expected in the current ruleset: E1 costs 100 and has 50 strength; E3 costs 300 and has 25
strength, while the curriculum contains no combat vehicles that make rocket infantry strategically
necessary.

## Economy Is Not Structurally Required

The simulator starts each side with 10,000 credits. A power plant and barracks cost 300 each, leaving
9,400 credits, enough for 94 E1 without harvesting. The top decile averages only 56 total units.

This explains the mixed economy result:

- Better policies harvest more credits on average.
- Better policies build fewer refineries than the population average.
- The raw winner assigns zero reward to refinery construction and still reaches `0.418841`.
- Tiberium income reward has a weak positive global association, while refinery and first-delivery
  rewards have weak negative associations.

Harvesting is currently optional acceleration, not a prerequisite to victory. If the next curriculum
is intended to teach economy, initial credits must be low enough that the policy cannot fund its
winning army without a refinery, but high enough to construct the power/refinery chain. That change
needs Vanilla parity and deterministic trace tests before training.

## Action-Space Blocker

The ABI has seven independently sampled heads:

```text
command, actor, product, target_kind, target_x, target_y, target_slot
```

The mask marks legal values in each head independently. It cannot express that an actor, product,
target kind, and target are legal only for the selected command. Sampling valid values from each
head can therefore produce an invalid joint command.

Measured invalid-action fractions:

| Population | Invalid decisions / episode decisions |
| --- | ---: |
| All-run median | 61.96% |
| Top-decile mean | 54.77% |
| `u6ul1umm` | 48.09% |
| `8fcw2lp9` | 43.58% |
| Retained `b9sj4ihr` | 60.74% |

This is a sample-efficiency problem, not mainly a simulator-throughput problem. Time still advances
on rejected commands, but most decisions do not express the policy's intended game action. Adding a
large invalid-action penalty risks making noop the safest policy and does not repair the action
representation.

The durable fix is a conditionally valid policy action representation. Two viable designs are:

1. A fixed-size catalog of concrete legal high-level commands, exposed as one masked categorical
   action and translated back into the existing seven-field Vanilla command.
2. An autoregressive decoder that samples command first, then applies command-specific masks to
   actor, product, and target heads.

The seven-field simulator and Vanilla integration can remain the downstream command ABI. Only the
policy-facing selection mechanism needs to change. This should be measured with the same retained
candidate hyperparameters before another large sweep.

## Hyperparameter Findings

The 48 runs at or above `0.2` all used horizon 32 and one MinGRU layer. Their architecture counts
were:

| Dimension | Successful-run count |
| --- | --- |
| Hidden size | 32: 31, 64: 17 |
| Buffers | 1: 39, 2: 7, 4: 2 |
| Horizon | 32: 48 |
| Layers | 1: 48 |

The successful optimizer basin was much narrower than the configured search range:

| Hyperparameter | 10th percentile | Median | 90th percentile |
| --- | ---: | ---: | ---: |
| Learning rate | 0.000871 | 0.000958 | 0.001115 |
| Entropy coefficient | 0.000624 | 0.001149 | 0.002091 |
| Gamma | 0.97143 | 0.98472 | 0.99197 |
| GAE lambda | 0.91821 | 0.96252 | 0.98647 |
| Replay ratio | 3.229 | 4.000 | 4.000 |
| Clip coefficient | 0.742 | 0.904 | 1.000 |
| Value coefficient | 2.812 | 4.199 | 5.000 |
| Value clip | 1.609 | 3.371 | 4.547 |
| Max gradient norm | 0.250 | 0.453 | 0.982 |
| V-trace rho clip | 1.085 | 2.219 | 3.305 |
| V-trace c clip | 0.100 | 0.116 | 0.825 |
| Priority beta 0 | 0.766 | 0.963 | 1.000 |

Several useful configurations reached search boundaries: replay ratio 4, clip coefficient 1, value
coefficient 5, Adam epsilon `1e-4`, and V-trace c clip `0.1`. A focused follow-up should confirm those
boundaries instead of blindly extending all of them.

These are associations from an adaptive sweep, not isolated causal effects. Protein sampled only 10
initial Sobol points, then concentrated heavily around horizon 32, one layer, hidden size 32/64, and
one buffer. A held-out ExtraTrees model explained only 5.5% of score variance; a classifier for
`balanced_perf >= 0.2` reached AUC 0.668. The data is useful for defining a focused basin, but weak for
claims that one individual hyperparameter causes success.

The existing 32x4 CNC5 checkpoint is also a counterexample to a blanket conclusion that deeper
models cannot work. The current result only says one layer dominated this 2M-step adaptive search.

## Reward Findings

Top-decile runs had a smaller mean shaping budget than the full population, `1.952` versus `2.202`.
The shaping-budget correlation with balanced score was weakly negative (`rho=-0.103`). Both leading
candidates set `reward_player_infantry` to zero.

The raw winner also set enemy-building and refinery rewards to zero. It learned to destroy buildings
from the terminal objective plus smaller milestone, unit-loss, first-delivery, and income signals.
This argues for simpler shaping, not larger reward totals.

No reward conclusion should be promoted independently of its optimizer configuration. The search
jointly changed 28 dimensions, and the predictive model fit was weak.

## Reliability And Determinism

- `start_failures` was zero for all 1,000 trials.
- The duplicate bootstrap configuration produced exactly the same final gameplay metrics and
  balanced score in both runs. This is a useful deterministic launch check.
- Four low-scoring trials recorded engine failures. Three ended with nonzero failure rates and one
  had only a transient training failure. No top candidate recorded a failure.
- The largest rate was 2 failures in 104 episodes (`0.01923`).

The current metric combines `capacity_overflow` and `unsupported_content`, so the sweep cannot tell
which invariant failed. Add failure-subtype counters before another billion-step campaign. The one
duplicate configuration is not a substitute for deterministic trace/hash replay of promoted
candidates.

## Throughput

The exact campaign command and source hashes are in the [launch record](cnc6_abi9_2m_sweep.md).
Reporting shape:

- 64 agents per trial;
- 4 CPU environment threads;
- 1 to 8 buffers, swept;
- horizon 32 to 128, swept;
- 2,097,152 training steps per run;
- minibatch 2,048;
- normal PufferLib CUDA training with `--train.gpus 1`;
- three concurrent sweep workers on one physical GPU;
- `start_failures=0` for every run, so the campaign is valid.

The campaign consumed 2,097,152,000 requested training steps in 8h 46m 11s, or about 66,427 training
SPS across the whole machine. That denominator includes no-update evaluation, W&B, process launch,
and sweep scheduling, so it is a campaign-capacity number rather than raw simulator SPS.

Final per-trial displayed SPS had median 35,214, 90th percentile 55,564, and maximum 93,952. Those
runs shared a GPU and used different networks, buffers, behavior, episode lengths, and reset rates.
The maximum is not a valid speedup claim. CNC6 was not a controlled before/after performance test.

## Exact Reproduction Configurations

Shared fixed settings for both candidates: 64 agents, 4 threads, minibatch 2,048, 2,097,152 training
steps, CUDA, train seed 42, environment seed 1.

| Setting | `u6ul1umm` | `8fcw2lp9` |
| --- | ---: | ---: |
| Hidden size | 32 | 64 |
| Layers | 1 | 1 |
| Horizon | 32 | 32 |
| Buffers | 1 | 1 |
| Learning rate | 0.001040889542 | 0.000970112953 |
| Entropy coefficient | 0.001433147497 | 0.001354899589 |
| Gamma | 0.9908287658 | 0.9759770198 |
| GAE lambda | 0.9631829387 | 0.9297988512 |
| Replay ratio | 4.0 | 4.0 |
| Clip coefficient | 0.8528788649 | 1.0 |
| Value coefficient | 1.737762846 | 4.241147435 |
| Value clip | 1.719952994 | 3.579431156 |
| Max gradient norm | 0.9979773096 | 0.6691746654 |
| Beta 1 | 0.9948981381 | 0.9963317652 |
| Beta 2 | 0.9984108742 | 0.9989380402 |
| Adam epsilon | 4.10658785e-7 | 4.52161969e-7 |
| V-trace rho clip | 2.551767536 | 0.9780523043 |
| V-trace c clip | 0.1 | 0.1 |
| Priority alpha | 0.0 | 0.2505358060 |
| Priority beta 0 | 0.9739204246 | 1.0 |
| Milestone reward | 0.1787722003 | 0.1805947789 |
| Infantry-built reward | 0.0 | 0.0 |
| Enemy-unit-loss reward | 0.0136776653 | 0.0317647241 |
| Enemy-building-loss reward | 0.0 | 0.2321949690 |
| Player-unit-loss reward | -0.0081535734 | -0.0057911699 |
| Refinery reward | 0.0 | 0.0425559454 |
| First-delivery reward | 0.0509815315 | 0.0 |
| Tiberium-income reward | 0.0063852081 | 0.0070816316 |

## Recommended Sequence

1. Preserve the exact sweep source state and run the full test suite before changing simulator or
   policy semantics.
2. Reproduce `u6ul1umm` and `8fcw2lp9` independently at exactly 2,097,152 steps with checkpoints
   enabled. The fixed-seed run should first match the sweep result closely.
3. Evaluate each retained checkpoint over substantially more episodes and several policy-sampling
   seeds. Report close, medium, balanced, minimum-spawn, failures, and confidence intervals.
4. Repeat training with several training seeds. Promote based on median robust performance, not the
   best replica.
5. Configure the Zig/Vanilla inference shape for the winning checkpoint and run a sampled visible
   evaluation. Verify state/action trace parity before judging strategy from the rendered match.
6. Redesign the policy-facing action selection so masks represent joint command validity. TDD must
   cover legal-command enumeration, deterministic translation to the existing ABI, replay hashes,
   training smoke, invalid-action rate, SPS, and Vanilla parity.
7. Run a focused sweep around the successful basin. Keep horizon 32 and one layer as the primary
   arm, compare hidden 32/64, and search optimizer/reward ranges narrowly. Retain checkpoints and
   periodic evaluations so policy degradation is observable.
8. Only then make harvesting structurally necessary and add curriculum complexity such as a farther
   spawn and combat vehicles. Each change needs simulator/Vanilla deterministic parity before
   spending another large sweep budget.

## Reproducing This Analysis

The local analyzer reads the complete JSON log set and does not require W&B access:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1
PufferLib/.venv/bin/python tools/analyze_cnc6_sweep.py \
  PufferLib/logs/cnc_micro --top 25
```

It reports campaign distributions, reconstructed spawn counts, posterior intervals, robust
rankings, duplicate configurations, completion-order blocks, successful hyperparameter quantiles,
behavior correlations, failures, and a held-out predictive-model sanity check.
