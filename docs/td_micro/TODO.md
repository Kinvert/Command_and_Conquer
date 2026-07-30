# TD Micro Work Queue

Last updated: 2026-07-23

This is the authoritative near-term task list for TD Micro. Every task is enclosed by visible
`TASK START` and `TASK END` markers. Content between those markers is one distinct engineering
task, test gate, and commit boundary. Do not mix implementation from adjacent tasks into the same
commit. Documentation and evidence for a task should be committed with that task after its
acceptance gate passes.

Current reference point:

- source/config checkpoint commit: `f3b5a1cce7b6db0241601643f8d9e266051cba92`
- retained ABI-8 checkpoint: `lqn5ogu8/0000000001048576.bin`
- broad native close/medium evaluation: `178/22/0`, or `89%` wins
- matched real Vanilla close/medium evaluation: `84/116/0`, or `42%` wins
- declared Zig/Vanilla policy-state parity traces: exact and deterministic as of 2026-07-16; see
  `docs/td_micro/zig_vanilla_policy_parity.md`
- `TASK-2A` candidate broad rerun: Zig `175/25/0`, Vanilla `84/116/0`, terminal agreement
  `83/200`; first divergence is decision 179 or later
- the decision-6 MCV-facing and decision-76 construction-progress classes are fixed, but broad
  outcome parity remains open; see `docs/td_micro/abi8_parity_corrections.md`
- schema-7 early-force candidate: `AttackDelay=1`; real Vanilla seed 2 trains its first E3 at frame
  1,430, releases it at frame 1,648, and fields seven infantry by frame 2,800; all acceptance tests
  pass; see `docs/td_micro/attack_delay_early_force.md`
- `TASK-3` exact conditional action protocol: ABI10 established the grammar, ABI11 compacted it,
  and experimental ABI13 added bounded actor-target scoring. ABI13 reaches 0.384 reproducibly at
  1M but only 0.092 at 2M; its sampled 30-run median is zero. It is preserved at `9789107` but not
  promoted; see `docs/td_micro/abi13_actor_target_experiment.md`
- `TASK-3J` experimental group action: ABI14 preserves ABI9 and adds 64 command-gated binary
  infantry selectors. Native implementation, CUDA parity, fixed evaluation, determinism, and
  adjacent SPS validation pass; learning comparison and visible Vanilla transfer remain open.
- `TASK-3K` deterministic difficulty curriculum: requested Easy/Normal/Hard are explicit,
  stock-handicap mechanics and oracle fixtures are implemented, and CNC25 ramps H5 selection from
  90/10 Easy/Normal to 10/90 without changing rewards or supported content. Final build, training
  smoke, adjacent SPS evidence, and commit are pending.

## Execution Order

1. `TASK-1`: complete - Zig/Vanilla policy-state parity is exact on the declared traces.
2. `TASK-2`: complete - broad real-Vanilla evaluation found a material transfer gap.
3. `TASK-2A`: in progress - early mismatch classes are fixed; close the remaining policy-path and
   outcome gap.
4. `TASK-2B`: complete - the original AI fields an early infantry force under schema 7.
5. `TASK-3`: complete - one exact conditional command is emitted per transition.
6. `TASK-3A`: in progress - ABI13 adds compact actor-target interaction, but does not recover ABI9
   2M robustness and is not promoted.
7. `TASK-3B`: complete - ABI9 is runtime-selectable, historical hashes reproduce exactly, and a
   matched 15-run 2M study rejects nonzero invalid-action penalties.
8. `TASK-3C`: complete - the CNC10 1M leaders reproduce, but fresh 2M cosine schedules collapse;
   the historical 2M control remains seed-fragile.
9. `TASK-3D`: complete - weights-only fixed-LR continuation does not preserve the 1M policy.
10. `TASK-3E`: complete - native full-state continuation is exact across uninterrupted and
    fresh-process split/resume CUDA runs.
11. `TASK-3F`: complete - promote the ABI9 baseline and run the native MLP/MinGRU ablation.
12. `TASK-3H`: replicate the successful late-LR continuation across the promoted family.
13. `TASK-3I`: run the matched full-match control, then sweep curriculum pace.
14. `TASK-3J`: compare ABI9 single-actor and ABI14 group-action learning, then add visible Vanilla
    transfer only if ABI14 earns promotion.
15. `TASK-3K`: validate and launch the isolated CNC25 requested Easy-to-Normal curriculum.
16. `TASK-3G`: migrate the canonical development seed from 73 to 42 in an isolated commit.
17. `TASK-6A`: author and validate a fixed-credit long spawn.
18. `TASK-4`: make harvesting structurally necessary in a dedicated curriculum profile.
19. `TASK-5`: add deterministic starting-credit diversity.
20. `TASK-6`: combine distance and credit curricula.
21. `TASK-7`: train, evaluate, benchmark, and promote the next policy.

`TASK-3` is implemented through ABI13. It removes the 44.943% ABI9 rejection problem without
changing rewards, decision timing, or the native CUDA backend, and it has explicit CPU/CUDA
gradient parity. Its remaining issue is learning robustness: exact actions have not matched ABI9's
2M performance. `TASK-3B` reopens the old action path as a controlled experiment rather than
assuming rejection-free sampling is automatically better.

---

> **TASK START: TASK-1**

## TASK-1: Close Zig/Vanilla Policy-State Parity

Status: complete and verified on 2026-07-16

Commit boundary: parity fixes, differential tests, and parity documentation only. Do not change the
action protocol, rewards, starting credits, spawn distribution, or training hyperparameters.

### Outcome

The same ruleset, setup seed, ordered actions, and frame count must expose the same policy
observation and action mask in Zig and the real Vanilla executable for every declared parity trace.

### Work

- Represent Tiberium presence separately from its harvestable overlay-step count.
- Fix the decision-0 mismatch at map cell `(40,48)`, where Zig reports clear/buildable terrain and
  Vanilla reports present Tiberium.
- Locate and resolve the decision-1 enemy-MCV facing mismatch, currently Zig `246` versus Vanilla
  `236`.
- Add executable-path fixtures for initial state and early frame advancement, not only
  shared-library oracle fixtures.
- Add a comparator that reports the first field, byte offset, decision, and simulation frame that
  differs.

### Acceptance

- Exact observation and mask equality at decision 0 for close seed 1 and medium seed 2.
- No unexplained policy-visible mismatch in the declared early-frame and scripted economy/combat
  traces.
- Repeated Zig traces are byte-identical.
- Repeated Vanilla traces are byte-identical.
- All Zig, C ABI, Puffer binding, Vanilla, and fixture tests pass.
- Record native and Puffer SPS before and after; any material regression must be explained.

Evidence: `docs/td_micro/zig_vanilla_policy_parity.md`

> **TASK END: TASK-1**

---

> **TASK START: TASK-2**

## TASK-2: Build Broad Real-Vanilla Evaluation

Status: complete and verified on 2026-07-16

Commit boundary: evaluation infrastructure only. Do not retrain, alter game rules, or change the
policy action ABI.

### Outcome

Measure real-engine policy quality over enough held-out stochastic trajectories to replace the
current one-sampling-seed anecdote with a credible Vanilla win rate.

### Work

- Replace the hard-coded policy sampling seed `74` with an evaluation-only override.
- Prefer a headless runner argument or narrowly scoped environment variable over another normal
  gameplay INI setting.
- Launch each Vanilla episode in a fresh process so legacy global state cannot leak between matches.
- Run identical tuples of checkpoint, rules hash, setup seed, and policy sampling seed in Zig and
  Vanilla.
- Emit machine-readable episode records containing profile, sampling seed, result, frames,
  decisions, accepted/changed/failed actions, checkpoint hash, rules hash, and first divergence.
- Produce per-profile and balanced aggregate reports.

### Acceptance

- At least 100 close and 100 medium held-out Vanilla episodes.
- Zero startup, schema, controller, and engine failures.
- Matching Zig evaluations exist for every Vanilla tuple.
- Report close, medium, overall, and equal-profile-balanced W/L/D.
- Report terminal agreement and first-divergence statistics between Zig and Vanilla.
- The command, checkpoint hash, source commit, and raw result path are documented.

Evidence: `docs/td_micro/abi8_broad_vanilla_evaluation.md`

> **TASK END: TASK-2**

---

> **TASK START: TASK-2A**

## TASK-2A: Close Broad Policy-Path Parity

Status: in progress; the first correction pass is verified but acceptance is not met

Commit boundary: Zig/Vanilla parity fixes and differential fixtures only. Do not change rewards,
starts, credits, action ABI, policy weights, or training hyperparameters.

### Outcome

Make the fast Zig environment match real Vanilla along sampled policy trajectories closely enough
that native evaluation predicts real-engine outcomes.

### Work

- [x] Reproduce close sample seed 1012 at decision 6, where own MCV facing was Zig 166 and Vanilla
  171.
- [x] Reproduce sample seed 1000 at decision 76, where enemy building construction progress was Zig
  22 and Vanilla 13.
- [x] Record sampled actions with both traces so the first state mismatch is distinguished from an
  action-application mismatch.
- [x] Port Vanilla timing, rotation, construction, production, movement, mission, and infantry
  egress behavior into Zig without changing Vanilla.
- [x] Add focused differential fixtures and regressions for the corrected mismatch classes.
- [x] Rerun the exact `TASK-2` 200-tuple evaluation after the first correction pass.
- [ ] Resolve the remaining decision-179+ player-infantry facing, mission, position, flags, and map
  occupancy mismatch families.
- [ ] Rerun the same 200 tuples until outcome agreement meets the acceptance gate.

### Acceptance

- The two declared reproductions are exact through their previous first-divergence points.
- No systematic early policy-visible mismatch remains unexplained.
- Repeated fixed-seed traces are byte-identical in each engine.
- Broad terminal agreement is at least 95%, and balanced Zig/Vanilla win rates differ by at most 5
  percentage points.
- All tests, deterministic hashes, native throughput, and valid Puffer SPS are recorded.

Current result: the two declared early classes are fixed and exact prefixes are much longer, but
terminal agreement is `83/200` and the balanced win-rate gap is 45.5 percentage points. Acceptance
is not met.

Evidence: `docs/td_micro/abi8_parity_corrections.md`

> **TASK END: TASK-2A**

---

> **TASK START: TASK-2B**

## TASK-2B: Field An Early Original-AI Force

Status: complete and verified on 2026-07-16; candidate is not committed

Commit boundary: one versioned AI-timing rule plus the Zig/Vanilla parity corrections exposed by
the resulting early force. Do not change rewards, actions, starts, credits, policy weights, or
training hyperparameters.

### Outcome

Prevent the current micro-map policy from winning against an undefended base solely because stock
TD's opening attack countdown outlasts the match.

### Acceptance

- Both setup seeds field original-AI infantry before frame 2,500.
- Real Vanilla seed 2 records an infantry train by frame 1,430, a completed infantry by frame 1,648,
  and at least four simultaneously live infantry.
- Zig matches the declared Vanilla economy, movement, combat, and RNG fixtures exercised by the
  early force.
- Repeated deterministic hashes match.
- Debug, ReleaseFast, Vanilla, CTest, native benchmark, and valid Puffer GPU gates pass.

Result: schema 7 pins `AttackDelay=1`; seed 2 fields seven infantry by frame 2,800. Native
fixed-action throughput is 101,182 SPS mean (+5.69% versus the matched parent candidate), and the
matched Puffer GPU smoke is 76,302 SPS with zero start/engine failures and no measurable regression.

Evidence: `docs/td_micro/attack_delay_early_force.md`

> **TASK END: TASK-2B**

---

> **TASK START: TASK-6A**

## TASK-6A: Author A Fixed-Credit Long Spawn

Status: blocked by `TASK-2A`

Commit boundary: long-spawn geometry and deterministic assignment only. Keep the current credits,
rules, rewards, action ABI, and close/medium starts unchanged.

### Outcome

Add one pathable long-distance profile without confounding the geometry change with economy or
reward changes.

### Acceptance

- The long start is pathable, resettable, and selected deterministically.
- Close and medium starts remain unchanged.
- Zig and Vanilla initial observation/mask parity is exact for all three profiles.
- Repeated fixed-seed traces are byte-identical in both engines.
- Tests, replay hashes, native throughput, and valid Puffer SPS are recorded.

> **TASK END: TASK-6A**

---

> **TASK START: TASK-3**

## TASK-3: Replace Independent Action Heads

Status: complete and verified on 2026-07-18

Commit boundary: this must be its own ABI-changing commit. Do not begin it as part of parity,
evaluation, harvesting, spawn, or reward work.

### Outcome

Replace independently sampled action tuples with a conditional legal-command protocol so the policy
does not generate thousands of invalid tuples per episode as the ruleset expands.

### Required Gate Before Starting

- `TASK-1` and `TASK-2` are complete.
- The exact command grammar and tensor/checkpoint compatibility impact are reviewed.
- Existing checkpoints are archived with their ABI and rules hashes.

### Acceptance

- One semantic command remains one Puffer transition and four TD frames.
- Every enabled prefix has a legal completion and randomized masked sequences are accepted.
- Native CUDA sampling and PPO replay the same stored conditional path without host synchronization.
- Inactive PAD heads contribute zero log-probability, entropy, and gradient.
- Three seeded CUDA runs report zero invalid actions, start failures, and engine failures.
- Initial and final checkpoint hashes match exactly across repeated runs.
- Debug, ReleaseSafe, ReleaseFast, C ABI, economy, Puffer binding, and native-CUDA gates pass.
- Reward and simulator configuration are unchanged.

Evidence: `docs/td_micro/current_action_abi.md`

> **TASK END: TASK-3**

---

> **TASK START: TASK-3A**

## TASK-3A: Replace The Dense ABI10 Decoder

Status: ABI11 and ABI13 candidates implemented and validated on 2026-07-19; acceptance remains open

### Outcome

Keep ABI10's exact command grammar and masks, but replace its 15,027-output prefix-row decoder with
a compact shared conditional decoder that restores training robustness and exceeds 50K valid CUDA
SPS. ABI11 completes the size reduction. ABI13 adds bounded rank-4 actor-target preference, but
does not restore ABI9-level 2M learning.

### Current Result

- [x] Reduce policy logits from 15,027 to 2,352 without changing environment semantics.
- [x] Reduce hidden-64x1 parameters from 1,131,264 to 320,064.
- [x] Keep randomized action acceptance and all start/engine/invalid failure counters at zero.
- [x] Preserve exact native world and repeated CUDA checkpoint hashes.
- [x] Improve matched 1M/2M balanced performance over ABI10: 0.175/0.161 versus 0.102/0.000.
- [x] Add explicit numerical CPU/CUDA score, probability, entropy, log-probability, and gradient
  parity tests, including finite differences and bounded saturation.
- [x] Add bounded rank-4 actor-target preference without a large dense prefix table.
- [x] Reproduce the ABI13 1M result and checkpoint hash exactly: 0.383830 in both repeats.
- [x] Run a 30-trial ABI13 screen: sampled median 0, mean 0.024241, maximum 0.203216.
- [ ] Recover or exceed ABI9's 0.422 matched 2M performance.
- [ ] Demonstrate at least 50K valid SPS while learning a nonzero policy under a matched gate.

### Acceptance

- Environment actions, observations, rewards, terminals, simulation, and exact masks are unchanged.
- CPU and CUDA sampling, log-probability, entropy, PPO ratio, and gradients match a reference.
- Random masked actions remain valid; invalid/start/engine failures remain zero.
- Fixed semantic traces and world hashes remain exact across implementations and repeats.
- Adjacent old/new benchmarks use identical agents, buffers, threads, horizon, minibatch, GPU, and
  total timesteps.
- Matched 1M/2M runs include the ABI9 `qj7bux1j` settings and both leading CNC7 configurations.
- Acceptance uses median/hit rate and collapse resistance, not only the best trial.

Evidence: `docs/td_micro/abi9_vs_abi10_learning_assessment.md`,
`docs/td_micro/abi11_compact_decoder_experiment.md`,
`docs/td_micro/abi13_actor_target_experiment.md`

> **TASK END: TASK-3A**

---

> **TASK START: TASK-3B**

## TASK-3B: Reassess Old Independent Actions With Invalid No-Ops

Status: complete and verified on 2026-07-19; retain ABI9 with zero invalid-action penalty

Commit boundary: use an isolated branch/worktree. Keep ABI13 intact and selectable; do not mix the
experiment with simulator, observation, map, opponent, or unrelated reward changes. Preserve the
ABI13 implementation reference at commit `9789107`.

### Outcome

Determine whether the old ABI9 seven-head action distribution trains more robustly than ABI11/13
when rejected tuples remain four-frame no-ops and receive either no penalty or a tiny bounded cost.

### Known Behavior

ABI9 already implemented invalid-as-noop. `input.apply` returned false, the invalid counter
incremented, and the simulator still advanced four frames with the Easy AI. The experiment adds no
action repair and no invalid-streak terminal.

Historical mean: 1,986.594 invalid actions per 4,420.213-decision episode. Therefore:

| Per-invalid reward | Approximate episode contribution |
| ---: | ---: |
| `-0.05` | `-99.33` - prohibited |
| `-0.001` | `-1.99` - too large for the first grid |
| `-0.00025` | `-0.497` |
| `-0.0001` | `-0.199` |
| `-0.00005` | `-0.099` |
| `-0.000025` | `-0.050` |

### Work

- Rebuild the exact ABI9 source/config reference and reproduce its penalty-zero checkpoint hash or
  documented learning curve before changing reward behavior.
- Add one experiment-only `reward_invalid_action` coefficient with default `0`.
- Compare only `{0, -0.000025, -0.00005, -0.0001, -0.00025}` in the fixed factorial study; cap
  cumulative invalid cost at `-0.5` and log both raw invalid count and applied cost.
- Keep invalid actions as canonical no-ops that still consume one decision and four simulation
  frames.
- Run exact 2M repeats with every non-penalty hyperparameter, reward, vector, and schedule value
  fixed. A 1M cosine schedule is not a prefix of the 2M control and is not used for coefficient
  selection.
- Evaluate retained checkpoints on a fixed close/medium episode set. Do not select on the final
  rolling training bucket alone.
- The old transport has been forward-ported onto the current simulator ahead of coefficient
  selection. Preserve ABI13 as the conditional-scoring reference and rerun all parity gates before
  any promotion.

### Acceptance

- TDD covers penalty-zero identity, invalid-noop frame advancement, reward accumulation/cap, terminal
  reward replacement, and deterministic replay.
- Penalty zero reproduces the historical effective-action/world trace.
- Start failures and engine failures remain zero; invalid tuples are measured, not hidden.
- Commands report agents, buffers, threads, horizon, total timesteps, minibatch, GPU mode, and all
  failure counters.
- At least three exact seeds or repeats support any robustness claim.
- Promotion requires stronger fixed-policy 2M evaluation than ABI11 and ABI13, not merely a lucky
  1M training window.

Evidence target: `docs/td_micro/old_action_noop_penalty_experiment.md`

Implementation checkpoint:

- ABI9 and ABI13 are selected by `env.action_abi` on the same current simulator build.
- The penalty-zero 2M run reproduces all historical checkpoint hashes exactly and has zero start or
  engine failures.
- The exact CNC5 `b9sj4ihr` 5M configuration reproduces its historical 0.402904242 balanced result
  and final close/medium, outcome, combat, and economy metrics on the current ABI9 path.
- Raw completed-episode invalid count and actual capped cost are logged within the 31-field limit.
- Debug, ReleaseSafe, ReleaseFast, C binding, CUDA, official sweep-smoke, and two-pass winning-trace
  replay gates pass.
- The broad CNC8 screen sampled the proven horizon-32/one-layer/one-buffer ABI9 basin only once;
  its weak result is adaptive-search lock-in, not a forward-port regression.
- The matched 15-run study used three top-level training seeds for each of five coefficients. On a
  fresh common 256-episode evaluation set, penalty zero won on median (0.228026) and mean
  (0.234835) balanced performance; every arm still had one zero-score seed. Nonzero penalties
  reduced invalid actions but did not improve robustness.
- The clean evaluator covered 3,843 episodes and 21,037,056 transitions with zero start/engine
  failures. An independent seed-73 repeat matched every non-timing result exactly.
- The seed-73 penalty-zero final checkpoint exactly matches historical SHA-256
  `490064539416022a02179b47136a74219ed37a618fcfa6173cabc659510c7a37`.
- The next search is focused at 2M in the successful CNC6 structural basin. The default config fixes
  ABI9, penalty zero, horizon 32, one layer, and one buffer; there is no `sweep_only`.

> **TASK END: TASK-3B**

---

> **TASK START: TASK-3C**

## TASK-3C: Test ABI9 Candidates For Multi-Seed 2M Robustness

Status: complete and verified on 2026-07-19; no CNC10 candidate promoted

Commit boundary: experiment manifest, orchestration, tests, and evidence only. Do not change the
simulator, actions, observations, rewards, maps, opponent, or default training configuration.

### Outcome

Reproduce the three leading CNC10 1M configurations, then train those configurations and the
historical `qj7bux1j` control from scratch for 2M transitions on top-level seeds 73, 74, and 75.
Rank final checkpoints using a fresh common 512-episode evaluation per checkpoint.

### Acceptance

- Every nested candidate value is pinned and validated from a versioned manifest.
- Normal PufferLib GPU training is used; no sweep, `--cpu`, or `--slowly` path is allowed.
- The three 1M source outcomes reproduce before promotion training starts.
- All 12 tournament runs reach exactly 2,097,152 transitions with zero start and engine failures.
- Every checkpoint receives the same policy seed and at least 512 completed fresh episodes.
- Report full commands, shapes, W&B ids, checkpoint hashes, SPS, and balanced close/medium results.
- Promotion requires a nonzero worst seed, not one favorable final bucket.

### Result

- All three 1M outcomes reproduced exactly to nine decimal places.
- The final evaluator covered 6,144 episodes and 30,576,640 transitions with zero failures.
- Fresh 2M median balanced performance was 0 for `5lk552uq` and `xlidr1ce`, and 0.001845 for
  `mnglsikv`.
- `qj7bux1j` ranked first at median 0.233987, but its three seeds scored 0.452784, 0.233987, and 0;
  it does not meet the nonzero-worst-seed promotion gate.
- Seed-73 `qj7bux1j` exactly reproduced historical checkpoint SHA-256
  `490064539416022a02179b47136a74219ed37a618fcfa6173cabc659510c7a37`.
- Doubling `total_timesteps` changes Puffer's cosine schedule at every intermediate update; the
  useful 1M runs are not prefixes of these fresh 2M runs.

Evidence: `docs/td_micro/cnc11_abi9_promotion_tournament.md`

> **TASK END: TASK-3C**

---

> **TASK START: TASK-3D**

## TASK-3D: Continue A Verified 1M Policy Without Schedule Reset

Status: complete and verified on 2026-07-20; weights-only continuation rejected

Commit boundary: checkpoint-resume semantics, focused continuation matrix, tests, and evidence
only. Keep ABI9, rewards, observations, maps, opponent, vector shape, and environment defaults
fixed.

### Outcome

Preserve the useful verified 1M `5lk552uq` weights and test whether fixed low-rate continuation
avoids the collapse caused by restarting with a new 2M cosine schedule.

### Acceptance

- [x] Prove that the existing policy-only checkpoint intentionally reinitializes optimizer and RNG
  state; do not call it a true resume.
- [x] Compare fixed LR `{0.00006, 0.00012, 0.00024}` across seeds 73, 74, and 75.
- [x] Evaluate every final checkpoint on the same 512-episode common seed set used by `TASK-3C`.
- [x] Record full commands, hashes, training/evaluation SPS, and all validity fields.
- [ ] Promotion requires zero failures, a nonzero worst seed, and a stronger median than the
  retained `qj7bux1j` control. This was not met.

### Result

All nine runs reached exactly 1,048,576 continuation transitions with zero failures. The best
common-evaluation balanced performance was 0.027437, versus the source checkpoint's 0.298395; every
rate had a zero seed. The result is documented in `docs/td_micro/cnc12_abi9_weights_only_continuation.md`.

> **TASK END: TASK-3D**

---

> **TASK START: TASK-3E**

## TASK-3E: Add Full Training-State Checkpoint And Resume

Status: complete and verified on 2026-07-21

Commit boundary: opt-in checkpoint/resume format, focused serialization tests, deterministic replay,
and one continuation gate only. Do not change the simulator, action ABI, observations, rewards,
maps, opponent, or default INI behavior.

### Outcome

Make continuation a real extension of the source optimization trajectory by preserving policy
weights, optimizer state, epoch/global step, scheduler state, and all relevant CPU/CUDA/Puffer RNG
state. Keep the existing policy-only `.bin` format unchanged for inference and old checkpoints.

### Acceptance

- [x] Full-state files are versioned and opt-in; existing `.bin` inference loading remains unchanged.
- [x] Native state round-trips policy weights, Muon momentum, learning-rate device state, epoch/global
  step, rollout RNG offsets, and CUDA Philox states.
- [x] Add serialization for the opaque `StaticVec`/TD Micro environment state.
- [x] Resume verifies architecture, ABI, rewards, trajectory configuration, schedule, seed,
  trainer source, native backend, and state payload integrity.
- [x] A meaningful CUDA gate crosses completed episodes and compares an uninterrupted run with a
  stopped prefix plus fresh-process resume at the same final step.
- [x] Final policy, optimizer/RNG/environment state, post-split action/reward/terminal trace, and
  post-split environment metrics match exactly.
- [x] Record hashes, optimizer/RNG semantics, normal-path SPS, and all failure counters.

### Result

The version-4 native format and immutable `train.schedule_timesteps` contract passed the direct
CUDA gate at 262,144 transitions, split at 131,072. Final state, final policy, post-split actions,
rewards, terminals, compatibility fingerprint, and all environment metrics were exact across the
uninterrupted and resumed processes. The comparison covered 61 completed post-split episodes with
`start_failures=0` and `failures=0`. The normal PufferLib CLI split/resume gate also produced exact
split state, final state, and final policy hashes. Truncation, header corruption, payload
corruption, and seed/schedule/reward incompatibilities are rejected.

Evidence: `docs/td_micro/cnc13_training_state_checkpoint.md`

> **TASK END: TASK-3E**

---

> **TASK START: TASK-3F**

## TASK-3F: Promote ABI9 Baseline And Compare Native MLP

Status: complete and verified on 2026-07-20

Commit boundary: fixed evaluation, promotion manifests, native architecture selection, focused
smokes, and architecture evidence only. Keep environment rules, rewards, observations, action ABI,
training hyperparameters, and the MinGRU implementation unchanged.

### Outcome

Promote a reproducible three-seed ABI9 baseline on an untouched suite, then determine whether a
matched native feedforward policy reduces the observed training-seed instability.

### Acceptance

- [x] Lock finalists, checkpoint hashes, selection rule, evaluation seed, and episode count before
  promotion evaluation.
- [x] Score 512 close and 512 medium games for every retained checkpoint with zero failures.
- [x] Promote only a candidate with nonzero wins in both profiles for all three training seeds.
- [x] Implement a real native CUDA `Linear + GELU` MLP; do not mislabel zero MinGRU layers as MLP.
- [x] Verify MLP and unchanged MinGRU rollout, backward/update, parameter count, checkpoint layout,
  evaluator loading, and failure counters.
- [x] Train three matched 2M MLP seeds with only `torch.network` changed.
- [x] Compare both architectures on a new locked 512-close/512-medium suite.

### Result

`vqsw4ned` is promoted with untouched-suite median robust 0.2445. On the architecture suite,
MinGRU retains the higher median robust score, 0.2487 versus MLP's 0.0614, and the higher worst
score, 0.0827 versus 0.0087. The initial CNC15 pass was invalidated due to a biased-GELU backward
bug and replaced in full by CNC16 v2. All 15,360 retained promotion and corrected-architecture
evaluation games were valid and failure-free.

Evidence: `docs/td_micro/cnc14_promotion_and_cnc16_architecture.md`

> **TASK END: TASK-3F**

---

> **TASK START: TASK-3H**

## TASK-3H: Replicate Late-LR Policy Continuation

Status: in progress; seed-174 improvement verified, family replication pending

Commit boundary: continuation runs, fixed evaluation, manifests, and evidence only. Do not change
the environment, rewards, observations, action ABI, model architecture, or source checkpoints.

### Outcome

Determine whether the seed-174 gain from one additional million steps at fixed LR `1e-5` is a
reliable promoted-family continuation recipe rather than a single-checkpoint result.

### Work

- [x] Fix and test native `train --load-model-path`; zero LR must preserve source weights exactly.
- [x] Verify seed 174 on the locked 19173 suite and fresh 29173 suite.
- [x] Replay seed 174 from the clean fix commit and require exact policy and full-state hashes.
- [ ] Apply the same +1M fixed-`1e-5` recipe to the seed-173 and seed-175 `vqsw4ned` checkpoints.
- [ ] Evaluate all three continued policies on both full suites without selecting another LR.
- [ ] Compare family median, worst seed/profile, mean, and eligibility against the source family.

### Acceptance

- All six continuation evaluations complete with zero start failures and runtime failures.
- Every continued training run has a reproducible policy hash and a complete `.state` checkpoint.
- Promotion requires a better family median robust score without making the worst seed/profile
  materially worse.
- Record commands, source and output hashes, SPS shape, exact episode rows, and selection rule.

Evidence: `docs/td_micro/cnc18_cnc20_late_lr_warmstart.md`

> **TASK END: TASK-3H**

---

> **TASK START: TASK-3I**

## TASK-3I: Sweep Curriculum Pace Against Hardest-Scenario Performance

Status: implementation and validation complete; matched learning experiments remain

Commit boundary: curriculum profiles/sampler, fixed hardest-profile evaluation, schedule manifests,
and paired curriculum ablations only. Do not change rewards, action ABI, model architecture, enemy
rules, or PufferLib core.

### Outcome

Use partial starts only as training aids while always measuring and maximizing held-out full-match
win rate. Sweep how quickly training advances through the curriculum without allowing easy-state
wins to become the objective.

### Work

- [x] Add deterministic Vanilla-parity recipes for H0-H4; H0/H1 each include E1, E3, and mixed
  force packages, while H5 retains the stock reset.
- [x] Keep pure H0 internal to tests and reject it through the public C/Puffer schedule API.
- [x] Add decision-paced schedule 1 with exact mixtures: `3/77/0/0/0/20`,
  `0/20/60/0/0/20`, `0/0/20/60/0/20`, `0/0/0/20/60/20`, `0/0/0/0/20/80`, then pure H5.
- [x] Sweep the one curriculum pace parameter over `512, 1024, 2048, 4096, 8192` decisions per
  lane per phase.
- [x] Snapshot schedule id, phase length, per-lane decision counter, episode ordinal, and active
  profile for exact continuation.
- [x] Restrict `perf`, terminal rates, and close/medium counters to H5; export the H5 episode share
  and keep Protein's configured `balanced_perf` objective full-match-only.
- [x] Force the fresh fixed evaluator to schedule 0/stage 0 so promotion `robust_perf` is H5-only.
- [x] Finish adjacent native/Puffer validation with zero failures and record the evidence.
- [ ] Compare schedule 0 against schedule 1 under matched hyperparameters and training seeds.
- [ ] Sweep schedule-1 phase length, reproduce the strongest result across at least three seeds,
  and promote only through the fixed H5 evaluator.

### Acceptance

- Protein ranks curriculum trials by H5-only `balanced_perf`; H0-H4 terminals never enter any
  performance rate, while shaped returns remain mixed diagnostics.
- Fixed promotion evaluates only schedule-0 H5 matches and reports fresh-suite `robust_perf`.
- Exact continuation preserves curriculum stage length, decision counters, episode ordinals, and
  active profiles.
- Schedule 0/1 and phase-length comparisons hold simulator, rewards, model, budget, and seed suites
  constant.
- All tests, hashes, valid native/Puffer throughput, and `start_failures=0` evidence are recorded.

Evidence: `docs/td_micro/stable_training_curriculum_plan.md`

> **TASK END: TASK-3I**

---

> **TASK START: TASK-3J**

## TASK-3J: Evaluate Sweepable Group Actions

Status: native implementation complete; learning and visible Vanilla transfer pending

Commit boundary: ABI14 action/mask contract, CNC-specific native CUDA dispatch, fixed evaluation,
determinism tests, and adjacent benchmarks. Preserve ABI9 and do not change observations, rewards,
curriculum, enemy rules, or generic Puffer environments.

### Outcome

Let one policy decision issue one shared attack order to any subset of the 64 observed owned-unit
slots. Keep ABI9 as scheme 0 and expose ABI14 as scheme 1 so matched training and Protein sweeps can
decide whether group selection improves learning enough to justify its added policy complexity.

### Work

- [x] Add ABI14 with seven ABI9 heads followed by 64 separate binary selector heads.
- [x] Activate selectors only for attack, force ineligible/inactive heads to zero contribution, and
  condition target credit on a nonempty selected set.
- [x] Validate the entire selected set before applying orders, then issue orders in slot order
  before advancing simulation.
- [x] Add explicit native CUDA dispatch, CPU/CUDA gradient parity, and ABI-aware fixed evaluation.
- [x] Expose `env.action_scheme = 0|1` and sweep that public integer while retaining a non-swept
  technical ABI override.
- [x] Record frozen shape, checkpoint size, deterministic hashes, fixed-workload native SPS, and
  behavior-dependent end-to-end GPU SPS.
- [ ] Run paired multi-seed ABI9/ABI14 learning screens under unchanged rewards, curriculum,
  hyperparameters, and budgets.
- [ ] Implement and parity-test visible Vanilla ABI14 inference only if the learning screen earns
  promotion.

### Acceptance

- Scheme 0 remains ABI9-compatible and scheme 1 exposes exactly 71 heads, 407 logits, 471 mask
  bytes, and 71 raw action bytes.
- Inactive variables have exactly zero log-probability contribution, entropy contribution, and
  gradient; CPU and CUDA calculations match.
- Repeated group traces and matched fixed-workload ABI9/ABI14 traces have stable hashes.
- Every Puffer run has zero start/runtime failures and reports the full benchmark shape.
- Promotion requires better fixed-suite balanced performance across multiple matched seeds, not
  one sweep endpoint or a changed-workload SPS comparison.
- Visible Vanilla action/decision parity is required before an ABI14 checkpoint is shown as a
  transferable policy.

Evidence: `docs/td_micro/abi14_group_action_experiment.md`

> **TASK END: TASK-3J**

---

> **TASK START: TASK-3K**

## TASK-3K: Deterministic Easy-to-Normal Difficulty Curriculum

Status: implementation complete; final smoke, adjacent benchmark, documentation, and commit pending

Commit boundary: stock difficulty rules, deterministic selection/snapshots, Vanilla fixtures,
observation version 6, per-difficulty H5 metrics, fixed evaluator support, CNC25 configuration, and
their verification evidence. Preserve CNC24 in its running worktree. Do not change rewards,
supported units/buildings, maps, credits, action semantics, decision timing, or policy family.

### Outcome

Train selected ABI14 policies against a deterministic mix that begins at 90% requested Easy /
10% requested Normal and ends at 10% Easy / 90% Normal. Keep requested Hard available for parity
tests but outside CNC25 training. Rank trials on an equal-difficulty, equal-cell H5 objective rather
than allowing the changing episode mix or H0-H4 curriculum to inflate performance.

### Work

- [x] Generate Westwood's three handicap rows from the authoritative rules manifest and keep the
  requested skirmish label distinct from the inverted internal `DiffType`.
- [x] Apply reachable firepower, ground-speed, armor, ROF, cost, and MCV rotation effects in Zig and
  Vanilla.
- [x] Add deterministic fixed Easy, Easy-to-Normal, fixed Normal, and fixed Hard schedules with a
  separate per-lane decision clock.
- [x] Preserve schedule identity, ramp length, per-lane progress, and active requested difficulty
  in exact continuation snapshots.
- [x] Add byte-identical Easy/Normal/Hard Vanilla fixtures for combat, movement, and autonomous AI
  opening/deployment, then compare them from Zig tests.
- [x] Bump observations to version 6 and expose requested difficulty in global byte 33 without
  changing the 2,456-byte shape.
- [x] Export Easy and Normal four-cell balanced rates plus realized Normal H5 share; keep total
  Puffer fields including `env/n` at 29.
- [x] Preserve the 248-byte legacy stats ABI and add an explicit 376-byte v2 stats API.
- [x] Make the fixed evaluator pin requested Easy or Normal and reject mismatched observation
  difficulty.
- [ ] Pass the complete Zig, C API, Python, Vanilla, native CUDA build, and tiny GPU training gates
  with zero failures.
- [ ] Record adjacent CNC24/CNC25 throughput under one fixed command shape. Treat measurements made
  while CNC24 is active as contention-bound validation, not a speedup claim.

### Acceptance

- Requested Easy maps to internal `DIFF_HARD`, requested Normal to `DIFF_NORMAL`, and requested
  Hard to `DIFF_EASY`; generated C/Zig values share one manifest hash.
- Identical lane, episode, seed, and decision progress select identical difficulties without
  consuming gameplay RNG.
- The autonomous opening fixture matches commands, AI state, credits, deployment/queue state, and
  RNG through frame 96 at all three requested difficulties.
- Only H5 episodes enter difficulty denominators. `balanced_perf` equals
  `0.5 * (easy_balanced_perf + normal_balanced_perf)`, with each component equal-weighting its four
  spawn x force cells.
- Fixed Easy and fixed Normal evaluation artifacts are run separately for promotion.
- Every valid Puffer smoke/benchmark has `start_failures=0`, no runtime failures, and the full
  command shape recorded.

Evidence: `docs/td_micro/cnc25_difficulty_curriculum.md`

> **TASK END: TASK-3K**

---

> **TASK START: TASK-3G**

## TASK-3G: Canonicalize Fixed Training Seed 42

Status: planned; no seed change has been made

Commit boundary: this seed migration, its focused tests, new seed-42 hashes, and migration evidence
only. Start from a clean commit boundary and commit it separately. Do not include policy, optimizer,
simulator, observation, action ABI, reward, curriculum, map, or hyperparameter changes.

### Outcome

Replace the inherited top-level native training seed `73` with the project-standard fixed seed
`42` without weakening deterministic replay or invalidating historical evidence. Keep environment
seed `1` so the existing deterministic close/medium lane assignment remains unchanged. The
top-level seed controls native CUDA policy initialization, action sampling, and replay sampling;
the nested `train.seed` field does not control the native CUDA trajectory.

### Work

- Change only `[base].seed` in `PufferLib/config/cnc_micro.ini` from `73` to `42`; keep
  `[env].seed=1` and all other defaults byte-for-byte unchanged.
- Preserve historical seed-73 scripts, manifests, checkpoints, and expected hashes as immutable
  evidence. Add seed-42 records separately rather than rewriting or relabeling old results.
- Audit current launchers and active experiment scripts for implicit or explicit `--seed`
  overrides. Historical studies retain their declared seeds; new development commands explicitly
  use or inherit `42`.
- Run two fresh, identical native CUDA training jobs with the same source, configuration, vector
  shape, and fixed budget. Compare policy checkpoints, action traces, environment state, metrics,
  failure counters, and every non-timing log field.
- Repeat the fixed held-out evaluator from the same seed-42 checkpoint and require identical
  ordered episode rows and action digest.
- Verify that existing policy-only checkpoints still load for inference. A seed-73 full training
  state must not silently resume as a seed-42 lineage; reject it through the continuation
  compatibility contract once `TASK-3E` is accepted.
- Record the old and new config hashes, source commit, commands, checkpoint hashes, evaluator
  digest, and validity counters. Do not describe the seed migration as a learning or SPS gain.

### Acceptance

- The seed migration diff contains no material change beyond the canonical seed, focused tests,
  hash manifest, and documentation.
- Two matched seed-42 training runs produce identical final checkpoint SHA-256 hashes and exact
  non-timing outputs, with `start_failures=0` and engine failures `=0`.
- Two fixed-suite evaluations produce byte-identical ordered episode evidence and action digests.
- All historical seed-73 deterministic fixtures still pass and their recorded hashes are
  unchanged.
- Normal PufferLib CUDA training remains the tested path; no `--cpu` or `--slowly` substitute.
- `git diff --check`, native/CUDA build tests, Zig tests, binding tests, and deterministic replay
  tests pass before the dedicated commit is created.

> **TASK END: TASK-3G**

---

> **TASK START: TASK-4**

## TASK-4: Make Harvesting Structurally Necessary

Status: planned after `TASK-6A`

Commit boundary: one versioned economy-curriculum rules change plus its Zig/Vanilla implementation,
tests, traces, and benchmark. Do not include the action-protocol redesign.

### Outcome

Create at least one training profile in which a policy cannot win through a starting-cash infantry
rush and must complete a Tiberium delivery before it can field a viable attacking army.

### Important Constraint

Starting credits alone are not yet proven to enforce this. At `2300` credits, a player can choose:

```text
Power Plant 300 + Barracks 300 + up to 17 E1 for 1700
```

Therefore, do not hard-code `2300` and claim harvesting is mandatory. First establish the complete
budget and combat constraints for every legal no-harvest opening.

### Work

1. Build a deterministic budget/opening audit for all supported construction and infantry choices.
2. Measure whether low-credit close, medium, and candidate long spawns still permit a no-Refinery
   rush to win.
3. Add a harvesting-bootstrap curriculum state with no starting attackers and insufficient liquid
   credits for infantry, but with a source-faithful Refinery/Harvester path available. A practical
   first profile may start after the economy buildings are established so the first delivery is the
   only route to Barracks and infantry.
4. Add a full-MCV economy profile after the bootstrap profile works. Combine constrained resources
   with a sufficiently distant or defended opponent so foregoing the Refinery is not viable.
5. If cash and geometry cannot guarantee the invariant, use an explicit curriculum-only unlock
   such as disabling Barracks until the first delivery. Mirror it in Zig and Vanilla, identify it as
   a TD Micro curriculum restriction, and do not claim it is a stock TD prerequisite.
6. Keep terminal rewards `+1` for a legitimate win and `-1` for a legitimate loss. Any
   first-delivery shaping reward must be one-time, bounded, and secondary to terminal outcome.

### Acceptance

- A scripted Zig/Vanilla parity trace covers economy start, harvesting, return, unloading, Barracks,
  and E1/E3 production.
- A test establishes the selected profile's no-delivery invariant structurally. Merely observing
  zero no-delivery wins in one training run is insufficient.
- Every legitimate win in evaluation records at least one completed delivery.
- The original AI can execute the same economy contract without engine failure.
- The final evaluation starts from the declared full-match reset, even if temporary bootstrap
  states are used during curriculum training.
- Deterministic replay hashes, full tests, native throughput, and valid Puffer SPS are recorded.

> **TASK END: TASK-4**

---

> **TASK START: TASK-5**

## TASK-5: Add Deterministic Starting-Credit Diversity

Status: in progress. The Zig/Puffer full-match distribution, snapshot contract, and
credit-stratified promotion outcomes were implemented on 2026-07-22. Vanilla parity and per-band
economy telemetry remain. See `docs/td_micro/deterministic_starting_credits.md`.

Commit boundary: starting-credit selection, deterministic assignment, fixtures, and reporting only.
Do not add or move spawn points, add content, or change the action protocol in this commit.

### Outcome

Make starting money another policy-visible condition instead of training every episode from one
fixed rich opening. Preserve exact replay and keep the distribution explicit enough that each
economy regime remains understandable.

### Work

- Use the versioned 35% atom at `$2,300` plus a 65% uniform branch from `$2,400` through `$10,000`
  in `$100` increments.
- Keep rich-credit starts in the random branch so the already learned rush remains a legitimate
  conditional strategy.
- Treat `$2,300` as a constrained spending profile, not proof that harvesting is mandatory; that
  stronger invariant remains `TASK-4`.
- Select the bucket deterministically from setup seed plus episode index. Do not draw unrecorded
  runtime randomness.
- Initially give both GDI sides the same selected credit bucket. Any asymmetric-money curriculum
  must be a later, explicitly named task.
- [x] Export exact starting credits and a derived evaluation band in fixed evaluation records.
- Add Vanilla parity fixtures covering the constrained atom and representative low, medium, and
  rich values from the random branch.
- [x] Report W/L/D per credit band and per close/medium x credit-band cell without adding live log
  fields.
- [ ] Add offline per-episode telemetry for first-delivery rate, harvested credits, unit production,
  and no-delivery wins per credit band.

### Acceptance

- Zig and Vanilla resolve the same seed and episode index to the same named bucket and exact credits.
- Initial observation and action-mask parity passes for every credit bucket on the existing close
  and medium starts.
- Repeated fixed-seed traces are byte-identical in both engines.
- Training and evaluation logs contain nonzero samples for every configured bucket.
- Bucket weights are explicit, versioned, and verified by a deterministic assignment test.
- Tests, replay hashes, native throughput, and valid Puffer SPS are recorded.

> **TASK END: TASK-5**

---

> **TASK START: TASK-5A**

## TASK-5A: Mix Symmetric Starting Defenders

Status: implementation, deterministic parity, rebuild, and CNC23 preflight complete; broad sweep
running, promotion remains

Commit boundary: starting-force assignment, reduced Unit Count 6 setup, cell metrics, fixtures, and
fixed evaluation only. Do not add vehicles, change rewards, or alter the action/observation ABI.

### Outcome

Prevent undefended MCV rushing from being the universal full-match strategy while retaining rushable
games. Fixed evaluation is exactly half MCV-only and half 3 E1 plus 3 E3 per side. Reverse
curriculum training ramps armed H5 starts from 25% to 75%.

### Work

- [x] Add an exact deterministic 50/50 assignment independent of credits and close/medium spawn.
- [x] Give both sides identical legal idle forces without consuming persistent gameplay RNG.
- [x] Exclude starting infantry from production counts and setup rewards.
- [x] Route real Vanilla `MPlayerUnitCount=6` through the same supported roster.
- [x] Add Vanilla 256-decision parity, snapshot continuation, four-cell terminal stats, and ABI tests.
- [x] Equal-weight close/MCV, close/force, medium/MCV, and medium/force in live `balanced_perf`.
- [x] Extend fixed evaluation to all 16 spawn x force x credit-band cells.
- [x] Add a deterministic 25%-to-75% force-start ramp.
- [x] Decouple its per-lane decision clock from `curriculum_stage_decisions`; sweep completion from
  midway through H0 through the end of H2 at the default H pace.
- [x] Rebuild the Puffer extension after CNC22 and run adjacent training and exact-evaluation checks.
- [x] Expand the sweepable curriculum clock through 16384 decisions per lane.
- [x] Pass a complete 5 Mi CUDA/W&B gate and launch the 1,000-run CNC23 campaign.
- [ ] Train a new campaign and require nonzero wins in every spawn x force cell.

### Acceptance

- All 198 Zig tests pass in Debug, ReleaseSafe, and ReleaseFast.
- Two real Vanilla Unit Count 6 traces are byte-identical and match Zig through 256 decisions and
  1,024 frames, including AI production, release, attack orders, and movement.
- Fixed-evaluation assignment is exactly 50/50 overall and within each lane over 100 episodes.
- Reverse training reaches deterministic 25%, 50%, and 75% thresholds at the start, midpoint, and
  endpoint of every configured force ramp without consuming gameplay RNG or changing H-profile
  selection.
- Puffer exports no more than 31 fields and reports four distinct cell win rates.
- A promoted policy wins both defended and MCV-only starts rather than exploiting either subset.

Evidence: `docs/td_micro/deterministic_starting_force.md`,
`docs/td_micro/cnc23_starting_force_preflight.md`, and
`docs/td_micro/cnc23_force_ramp_decoupling.md`, and
`docs/td_micro/cnc23_defended_curriculum_5mi_sweep.md`

> **TASK END: TASK-5A**

---

> **TASK START: TASK-6**

## TASK-6: Add A Long Spawn And Distance Curriculum

Status: planned after `TASK-5` and `TASK-6A`

Commit boundary: deterministic distance-profile assignment, curriculum weights, fixtures, and
reporting only. Use the long geometry already validated by `TASK-6A`; do not change spawn cells,
starting-credit values, content, or the action protocol in this commit.

### Outcome

Combine the validated close, medium, and long distances with the credit buckets from `TASK-5` so
one policy must condition its strategy on geometry, available money, and economy state.

### Work

- Use the `TASK-6A` long spawn, where an immediate infantry rush is not universally sufficient.
- Preserve the existing close and medium starts. The goal is not to ban rushing; it is to make
  rushing one conditional strategy instead of the universal solution.
- Select close, medium, or long deterministically from setup seed plus episode index.
- First test the long spawn with the same credit bucket as close and medium to isolate geometry.
- Then form an explicit curriculum over distance and the credit buckets from `TASK-5`.
- Start with close/medium-heavy sampling, introduce long episodes at a controlled weight, and move
  toward the declared final mixture only after the policy can complete each stage.
- Hold out selected distance/credit combinations for evaluation rather than training on the entire
  cross-product.
- Keep all curriculum stages and sampling weights explicit and versioned.
- Report W/L/D and economy metrics separately for each distance and credit bucket.
- Use an equal-bucket balanced promotion metric so shorter close episodes cannot dominate by
  completing more often.

### Acceptance

- The `TASK-6A` long spawn remains valid, pathable, resettable, and unchanged.
- Zig and Vanilla resolve the same seed and episode index to the same spawn cells and profile name.
- Exact initial observation/mask parity passes for close, medium, and long profiles.
- The configured agent/episode assignment produces the intended deterministic distance distribution.
- Fixed-seed replay is byte-identical in each engine.
- Held-out evaluation contains nonzero samples for every declared distance/credit bucket.
- The policy records wins outside the close-rich rush bucket.
- No single strategy appears successful solely because one short profile is overrepresented.
- Tests, replay hashes, native throughput, and valid Puffer SPS are recorded.

> **TASK END: TASK-6**

---

> **TASK START: TASK-7**

## TASK-7: Train, Evaluate, Benchmark, And Promote

Status: blocked by `TASK-4`, `TASK-5A`, and `TASK-6`

### Outcome

Train the next policy through normal PufferLib CUDA training, verify it in Zig and real Vanilla, and
promote it only if it solves the declared curriculum rather than exploiting one start bucket.

### Acceptance

- Use `--train.gpus 1`; do not substitute CPU training for the throughput report.
- `start_failures=0` and engine failures `=0`.
- Report command, agents, buffers, threads, horizon, total timesteps, minibatch size, checkpoint
  hash, source commit, and SPS.
- Target at least 50,000 valid aggregate training SPS, while reporting a valid lower result rather
  than hiding it if the expanded workload misses the target.
- Run fixed held-out native evaluation for every start bucket.
- Run broad headless Vanilla evaluation through the `TASK-2` harness.
- Require wins in the economy-required and long-spawn buckets, not only aggregate wins.
- Require deterministic replay evidence and no unexplained policy-visible parity mismatch.
- Add the promoted checkpoint and exact result to the leaderboard/status documentation.

> **TASK END: TASK-7**
