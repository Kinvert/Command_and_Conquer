# CNC6 Targeted Hyperparameter Gap Runs

Date: 2026-07-18

Status: complete, 22/22 distinct configurations plus 8 argv-audit replays finished

W&B project: [cnc6](https://wandb.ai/kinvert-k/cnc6)

Related analysis: [CNC6 ABI-9 sweep analysis](cnc6_abi9_2m_sweep_analysis.md)

## Verdict

The targeted campaign closed the important gaps around the two CNC6 winners. It found one new raw
fixed-seed high, but did not improve the robust two-spawn candidate.

- Exact replays of `8fcw2lp9` and `u6ul1umm` reproduced every final gameplay metric exactly.
- The robust candidate remains `8fcw2lp9` / replay `05t9n1ci`: balanced `0.397582`, minimum-spawn
  win rate `0.357664`.
- Increasing only `reward_milestone` from `0.180594779` to `0.2` produced `qj7bux1j`, a new raw
  balanced high of `0.421753`. It is medium-start specialized: close `0.202128`, medium `0.641379`.
- The raw gain over `u6ul1umm` is only `0.002912`, while its minimum-spawn score is much worse than
  the robust candidate. Do not promote it as the default policy without multi-seed validation.
- Reward/optimizer block crossings, coordinate-wise medians, search-boundary extensions, and every
  other isolated change regressed.
- All 22 accepted representatives completed 2,097,152 training steps with zero engine failures and
  zero start failures. The 22 distinct configurations account for 46,137,344 agent steps; eight
  successful audit replays add 16,777,216 more.

The next useful experiment is not more fixed-seed coordinate search. Evaluate the retained `8fc`
and milestone-`0.2` checkpoints across policy-sampling seeds, then repeat training across several
training seeds. Promote on median minimum-spawn performance, not this campaign's single best raw
point.

## Purpose

Test deliberately selected combinations that the 1,000-run adaptive sweep did not cover. These are
standalone CUDA training runs, not sweep suggestions. Every one of the 28 swept fields was set
explicitly on the command line, together with seeds, training budget, vector shape, and non-swept
optimizer schedule fields. No source or configuration code was changed during this campaign.

## Shared Run Contract

Unless a row below says otherwise, every run used:

- 2,097,152 training steps;
- 64 agents, one buffer, and 4 CPU environment threads;
- horizon 32 and minibatch 2,048;
- one 64-wide MinGRU layer with `Normalize255Encoder`;
- train seed 42, environment seed 1, and base seed 73;
- CUDA through `--train.gpus 1`;
- sampled no-update evaluation after training;
- W&B project `cnc6` with a blank group;
- checkpoints at initial, midpoint, and final epochs.

The exact 8fc control command was:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc6 --wandb-group '' \
  --tag cnc6-gap-anchor-8fc-explicit-full \
  --seed 73 --checkpoint-interval 512 --eval-episodes 10000 \
  --cudagraphs 10 --reset-state True \
  --env.seed 1 --env.max-decisions 12000 \
  --env.reward-milestone 0.18059477893139259 \
  --env.reward-player-infantry 0.0 \
  --env.reward-enemy-unit-loss 0.03176472410973994 \
  --env.reward-enemy-building-loss 0.23219496897879333 \
  --env.reward-player-unit-loss -0.005791169896719446 \
  --env.reward-refinery 0.042555945418244596 \
  --env.reward-first-delivery 0.0 \
  --env.reward-tiberium-income 0.007081631623240768 \
  --vec.total-agents 64 --vec.num-buffers 1 --vec.num-threads 4 \
  --policy.hidden-size 64 --policy.num-layers 1 --policy.expansion-factor 1 \
  --torch.network MinGRU --torch.encoder Normalize255Encoder \
  --torch.decoder DefaultDecoder \
  --train.gpus 1 --train.seed 42 --train.total-timesteps 2097152 \
  --train.learning-rate 0.0009701129526611177 \
  --train.anneal-lr 1 --train.min-lr-ratio 0.0 \
  --train.ent-coef 0.0013548995888609634 \
  --train.anneal-ent-coef 0 --train.min-ent-coef-ratio 0.1 \
  --train.gamma 0.975977019771838 \
  --train.gae-lambda 0.9297988511653911 \
  --train.vtrace-rho-clip 0.9780523042532735 \
  --train.vtrace-c-clip 0.1 --train.replay-ratio 4.0 \
  --train.clip-coef 1.0 --train.vf-clip-coef 3.579431156424427 \
  --train.vf-coef 4.241147435051642 \
  --train.max-grad-norm 0.6691746653678212 \
  --train.beta1 0.9963317652430518 --train.beta2 0.9989380402338324 \
  --train.eps 4.521619692179587e-07 \
  --train.prio-alpha 0.25053580595043257 --train.prio-beta0 1.0 \
  --train.minibatch-size 2048 --train.horizon 32 \
  --train.checkpoint-interval 512
```

Every local OAT command was this full command with the tag and listed field replacements. The exact
argv for every accepted run is also retained in its W&B metadata and local `wandb-metadata.json`;
no omitted field came from a random sweep suggestion.

## Gap Selection

The broad sweep's global held-out model was weak (`R2=0.055`), so it was used only as a veto. The
campaign used empirical high-performing blocks and controlled comparisons:

1. Replay both winners exactly to retain checkpoints and verify fixed-seed reproducibility.
2. Cross reward and optimizer blocks from the strongest robust parents.
3. Test the replay, value coefficient, and V-trace c-clip sweep boundaries together and alone.
4. Test a coordinate-wise consensus across the seven policies with minimum-spawn win rate at least
   `0.25`.
5. Change one high-evidence reward or optimizer coordinate at a time around exact 8fc.
6. Test three single-coordinate adjustments around the only improvement, milestone `0.2`.

Simple hidden-size swaps were rejected before training because the local ensemble ranked both well
below the selected cases. Horizon 32 and one layer were held fixed because all 48 original runs at
or above `0.2` used that shape.

## Deliberate Changes

The exact u6 and 8fc source configurations are in the parent
[sweep analysis](cnc6_abi9_2m_sweep_analysis.md#exact-reproduction-configurations).

| Tag suffix | Construction or replacement relative to exact 8fc |
| --- | --- |
| `anchor-8fc` | Exact `8fcw2lp9` replay. |
| `anchor-u6` | Exact `u6ul1umm` replay, including its 32-wide policy. |
| `8fc-boundary` | Replay `5`, value coefficient `5`, c clip `0.05`. |
| `robust-median64` | Coordinate median of the seven original minimum-spawn `>=0.25` runs. |
| `8fcopt-gta-reward` | Exact 8fc optimizer/shape block with exact `gtaoyvpn` reward block. |
| `gtaopt-8fc-reward` | Exact `gtaoyvpn` optimizer/shape block with exact 8fc rewards. |
| `74opt-8fc-reward` | Exact `74lrr38f` non-reward block, including two buffers, with 8fc rewards. |
| `8fc-replay5` | Replay ratio `5`. |
| `8fc-vfcoef5` | Value coefficient `5`. |
| `8fc-cclip005` | V-trace c clip `0.05`. |
| `8fc-milestone020` | Milestone reward `0.2`. |
| `8fc-milestone019` | Milestone reward `0.19`. |
| `8fc-maxgrad025` | Maximum gradient norm `0.25`. |
| `8fc-buildingreward0` | Enemy-building-loss reward `0`. |
| `8fc-refineryreward0` | Refinery reward `0`. |
| `8fc-prioalpha0` | Priority alpha `0`. |
| `8fc-ent002` | Entropy coefficient `0.002`. |
| `8fc-gamma098425` | Gamma `0.9842520579998716`. |
| `8fc-playerloss004` | Player-unit-loss reward `-0.004`. |
| `m020-building030` | Milestone `0.2`, then enemy-building-loss reward `0.3`. |
| `m020-lr00105` | Milestone `0.2`, then learning rate `0.00105`. |
| `m020-prioalpha050` | Milestone `0.2`, then priority alpha `0.5`. |

## Results

`Min` is the smaller close/medium win rate. `Perf` is the episode-weighted Puffer-side win rate.
All failure columns are zero, so every run is valid. SPS is the final displayed standalone CUDA
training value, not a controlled simulator speedup claim; policy behavior changes episode/reset
costs.

| Tag | Run | Balanced | Close | Medium | Min | Perf | n | SPS |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `anchor-8fc` | [`05t9n1ci`](https://wandb.ai/kinvert-k/cnc6/runs/05t9n1ci) | 0.397582 | 0.437500 | 0.357664 | **0.357664** | 0.400673 | 297 | 27,334 |
| `anchor-u6` | [`iyqizva6`](https://wandb.ai/kinvert-k/cnc6/runs/iyqizva6) | 0.418841 | 0.177305 | 0.660377 | 0.177305 | 0.511983 | 459 | 34,735 |
| `8fc-boundary` | [`ubw6ewbv`](https://wandb.ai/kinvert-k/cnc6/runs/ubw6ewbv) | 0.267140 | 0.235772 | 0.298507 | 0.235772 | 0.268482 | 257 | 38,116 |
| `robust-median64` | [`dvvqhg1f`](https://wandb.ai/kinvert-k/cnc6/runs/dvvqhg1f) | 0.005618 | 0.000000 | 0.011236 | 0.000000 | 0.005917 | 169 | 28,424 |
| `8fcopt-gta-reward` | [`f8sviz7o`](https://wandb.ai/kinvert-k/cnc6/runs/f8sviz7o) | 0.173135 | 0.118421 | 0.227848 | 0.118421 | 0.174194 | 155 | 40,165 |
| `gtaopt-8fc-reward` | [`670l1b7q`](https://wandb.ai/kinvert-k/cnc6/runs/670l1b7q) | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 228 | 34,919 |
| `74opt-8fc-reward` | [`djh0quy5`](https://wandb.ai/kinvert-k/cnc6/runs/djh0quy5) | 0.010526 | 0.000000 | 0.021053 | 0.000000 | 0.010471 | 191 | 66,097 |
| `8fc-replay5` | [`hktwofbd`](https://wandb.ai/kinvert-k/cnc6/runs/hktwofbd) | 0.036725 | 0.035714 | 0.037736 | 0.035714 | 0.036697 | 218 | 41,767 |
| `8fc-vfcoef5` | [`i4e3avus`](https://wandb.ai/kinvert-k/cnc6/runs/i4e3avus) | 0.131005 | 0.138298 | 0.123711 | 0.123711 | 0.130890 | 191 | 35,324 |
| `8fc-cclip005` | [`z10mlrdf`](https://wandb.ai/kinvert-k/cnc6/runs/z10mlrdf) | 0.251221 | 0.150442 | 0.352000 | 0.150442 | 0.256303 | 238 | 39,581 |
| `8fc-milestone020` | [`qj7bux1j`](https://wandb.ai/kinvert-k/cnc6/runs/qj7bux1j) | **0.421753** | 0.202128 | 0.641379 | 0.202128 | 0.468619 | 239 | 37,487 |
| `8fc-milestone019` | [`hy9tsixs`](https://wandb.ai/kinvert-k/cnc6/runs/hy9tsixs) | 0.010377 | 0.011494 | 0.009259 | 0.009259 | 0.010256 | 195 | 26,282 |
| `8fc-maxgrad025` | [`ktnjvsd6`](https://wandb.ai/kinvert-k/cnc6/runs/ktnjvsd6) | 0.006494 | 0.000000 | 0.012987 | 0.000000 | 0.006250 | 160 | 32,653 |
| `8fc-buildingreward0` | [`r2c4acvd`](https://wandb.ai/kinvert-k/cnc6/runs/r2c4acvd) | 0.118984 | 0.087591 | 0.150376 | 0.087591 | 0.118519 | 270 | 42,370 |
| `8fc-refineryreward0` | [`he9r0h6z`](https://wandb.ai/kinvert-k/cnc6/runs/he9r0h6z) | 0.200628 | 0.052632 | 0.348624 | 0.052632 | 0.210784 | 204 | 38,759 |
| `8fc-prioalpha0` | [`68u0zebw`](https://wandb.ai/kinvert-k/cnc6/runs/68u0zebw) | 0.218750 | 0.205357 | 0.232143 | 0.205357 | 0.218750 | 224 | 36,808 |
| `8fc-ent002` | [`kkpj7ke2`](https://wandb.ai/kinvert-k/cnc6/runs/kkpj7ke2) | 0.178672 | 0.144578 | 0.212766 | 0.144578 | 0.180791 | 177 | 37,868 |
| `8fc-gamma098425` | [`dbu7fyub`](https://wandb.ai/kinvert-k/cnc6/runs/dbu7fyub) | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 208 | 33,545 |
| `8fc-playerloss004` | [`dawisiij`](https://wandb.ai/kinvert-k/cnc6/runs/dawisiij) | 0.203093 | 0.200000 | 0.206186 | 0.200000 | 0.202899 | 207 | 30,935 |
| `m020-building030` | [`8ytmapn0`](https://wandb.ai/kinvert-k/cnc6/runs/8ytmapn0) | 0.133076 | 0.187500 | 0.078652 | 0.078652 | 0.135135 | 185 | 37,570 |
| `m020-lr00105` | [`h2e5p8vr`](https://wandb.ai/kinvert-k/cnc6/runs/h2e5p8vr) | 0.284569 | 0.347826 | 0.221311 | 0.221311 | 0.288462 | 260 | 30,833 |
| `m020-prioalpha050` | [`drwjbwax`](https://wandb.ai/kinvert-k/cnc6/runs/drwjbwax) | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 190 | 29,871 |

## Findings

### Argv Audit

The first executions of eight cases inherited `horizon=32` from the deterministic standalone
config instead of spelling it out in argv. They never received random sweep suggestions, and their
saved configs all recorded 32, but this did not satisfy the stricter explicit-field requirement.

Those eight cases were rerun with all 28 swept flags explicit. Every corrective replay matched its
earlier gameplay metrics exactly. The table above uses only the corrective run IDs. A final audit
checked all 22 accepted metadata files and found:

```text
accepted_runs=22 explicit_swept_flags=28 problems=[]
```

Run `fm9yrbzq` was an interrupted launcher attempt: training reached its checkpoint, but the PTY
closed before final evaluation and no local result JSON was produced. It is not included in any
result or conclusion.

### Determinism

The two exact controls matched their original sweep runs exactly on balanced, close, medium,
episode-weighted win rate, episode count, and gameplay counters. All eight argv-audit replays also
matched their first executions exactly. Displayed SPS differed because it is a wall-clock
measurement. This is strong evidence that the fixed-seed training path and current source state
reproduce, though it is not a substitute for simulator trace hashes.

### Co-adaptation

Optimizer and reward blocks are not modular. The three deliberate block crossings scored
`0.173135`, `0`, and `0.010526`. The coordinate median scored `0.005618`. Successful sweep points
must be treated as complete configurations, not bags of independently good coordinates.

### Boundaries

The combined boundary run scored `0.267140`. Isolated tests identified all three changes as
regressions: replay `5` scored `0.036725`, value coefficient `5` scored `0.131005`, and c clip
`0.05` scored `0.251221`. The original replay `4`, value coefficient `4.241147`, and c clip `0.1`
should remain.

### Reward Sensitivity

Milestone `0.2` is the only tested change that beat the parent on raw balanced score. Milestone
`0.19` collapsed to `0.010377`. This does not imply a smooth optimum at `0.2`: small reward changes
alter early gradients and sampled trajectories, after which training paths diverge. The fixed-seed
objective is highly discontinuous.

Removing building or refinery shaping also regressed. In this optimizer family those rewards are
part of the successful training trajectory even though other strong families use zero values.

### Follow-up Gate

Retain both checkpoints:

- robust reference: `05t9n1ci`, fully explicit exact 8fc replay;
- raw hypothesis: `qj7bux1j`, exact 8fc plus milestone reward `0.2`.

Before changing defaults, evaluate both over several policy-sampling seeds and retrain each over at
least three training seeds. A meaningful promotion must improve median balanced performance without
sacrificing minimum-spawn win rate. The current evidence keeps exact 8fc as the robust default and
labels milestone `0.2` as an unvalidated raw-score candidate.
