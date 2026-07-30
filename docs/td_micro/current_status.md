# TD Micro Current Status And Priorities

Date: 2026-07-23

Status: current working-state summary. CNC24 remains running in its isolated worktree. The
`td-micro-cnc25` worktree adds a deterministic requested Easy-to-Normal opponent curriculum on top
of selected ABI14 group actions; its final validation is in progress and no CNC25 sweep has
launched.

## Current Position

TD Micro is a pure-Zig, state-fed training environment for the restricted Tiberian Dawn skirmish.
The active simulator has GDI versus an original-style GDI AI and includes MCV deployment, power
plant, barracks, refinery/harvester, E1/E3 infantry, close/medium starts, and `AttackDelay=1`.
ABI9 remains the historical training baseline. CNC24 compares it with ABI14, which preserves ABI9
commands and adds 64 binary infantry selectors for group attacks. CNC25 selects ABI14 rather than
mixing action schemes inside its new difficulty experiment.

The current working tree adds validated deterministic H0-H5 reverse-curriculum resets. H0/H1 cover
finishing and assault combat packages, H2 starts from production-ready mobilization, H3 from an
operational economy, H4 from a deployed Construction Yard, and H5 is the unchanged full two-MCV
match. `curriculum_stage_decisions` controls decisions per lane in each H transition phase, while
`starting_force_ramp_decisions` independently controls defended-start progression. H5 remains
present in every phase, close/medium metrics count only H5, and the fixed evaluator forcibly
disables both clocks.

The next full-match domain uses two symmetric openings: MCV-only or reduced Unit Count 6,
represented by 3 E1 plus 3 E3 per side. Fixed evaluation is exactly 50/50. Reverse-curriculum
training linearly ramps armed H5 starts from 25% to 75% on an independent per-lane decision clock.
The CNC23 force-ramp range finishes between midway through H0 and the end of H2 at the default H
pace. This is designed to stop undefended MCV rushes from dominating while retaining rushable
games. The real Vanilla parity evidence for both starting-force recipes remains unchanged.

Four fixed-50 preflight controls and two adjacent ramp runs completed with zero failures. The best
fixed control scored 0.39608 on the exact suite; direct reuse of its CNC22 hyperparameters scored
0.26495 with the 1024-stage ramp and 0.16054 with the 4096-stage ramp. This is a negative
hyperparameter-transfer result, so no ramp policy is promoted. See
`deterministic_starting_force.md`, `cnc23_starting_force_preflight.md`, and
`cnc23_force_ramp_decoupling.md`.

The prior CNC23 process is no longer running; 108 complete 5,242,880-transition local records are
available. CNC24 launched from commit `8ef8143` with three workers in tmux session
`cnc24-sweep`. Its 12-trial mixed ABI9/ABI14 preflight completed cleanly with finite optimizer
metrics and zero start failures; see `cnc24_action_scheme_5mi_sweep.md`.

CNC25 is isolated from that active process and does not alter its binaries or configuration. It
ramps requested difficulty from 90% Easy / 10% Normal to 10% Easy / 90% Normal on a decision clock
independent of H0-H5 and starting-force progression. Hard is available only as a fixed parity-test
mode. Observation version 6 keeps the 2,456-byte shape and writes requested difficulty to global
byte 33. The live objective equal-weights requested Easy and Normal, and each side first
equal-weights the four H5 spawn x starting-force cells. See
`cnc25_difficulty_curriculum.md`.

CNC13 stopped intentionally after 980 completed 2,097,152-transition sweep runs. Its final trainer
buckets were used only to select candidate configurations because those buckets can include
episodes that straddle changing training policies and do not constitute independent checkpoint
evaluation.

The new fixed evaluator loads a frozen checkpoint into a fresh native CUDA runtime, resets worlds
and recurrent state, uses an exact held-out seed suite, scores only the first completed episode per
lane, and reports close and medium starts separately. Its repeated-check determinism digest is:

```text
c5f9cc440969ffbbfc08c588a3f314cbceb0a8067ee293360009a1966021c862
```

## CNC14 Stable Confirmation

Five CNC13 configurations were recreated from exact manifests and trained from scratch at seeds
173, 174, and 175. All 15 runs reached exactly 2,097,152 transitions with zero start or engine
failures. Each resulting checkpoint was then evaluated on exactly 128 fresh close episodes and 128
fresh medium episodes.

The score is the epsilon-shifted harmonic mean of close and medium terminal win rates documented in
`stable_training_curriculum_plan.md`.

| Configuration | Seed 173 | Seed 174 | Seed 175 | Median | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| `vqsw4ned` | 0.2441 | 0.3085 | 0.1129 | **0.2441** | Best stable candidate |
| `o5e9lorj` | 0.2833 | 0.2070 | 0.0267 | 0.2070 | Two good seeds, one near-collapse |
| `4pkdtoqj` | 0.0171 | 0.1208 | 0.0566 | 0.0566 | Weak repeated control |
| `x8biqwx1` | 0.0179 | 0.2367 | 0.0000 | 0.0179 | Failed one seed and profile |
| `hmc7f77r` | 0.0321 | 0.0000 | 0.0132 | 0.0132 | CNC13 result did not reproduce |

`vqsw4ned` is now the promoted ABI9 MinGRU baseline. The untouched `cnc14-promotion-v1` suite used
evaluation seed 19173 and scored 512 close plus 512 medium games for each of nine predeclared
checkpoints. All 9,216 games were valid and failure-free. `vqsw4ned` won the declared median-first
stability rank with median robust 0.2445 and worst robust 0.0932, ahead of `o5e9lorj` at 0.1820 and
0.0233 and the retained control at 0.0472 and 0.0289.

The corrected `cnc16-architecture-v2` experiment added a real native CUDA `Linear + GELU` MLP path
and compared it with MinGRU using the promoted configuration, the same three training seeds, and a
fresh 512-close/512-medium suite at seed 39173. MinGRU won median robust 0.2487 versus 0.0614 and
worst robust 0.0827 versus 0.0087. The initial CNC15 pass was rejected because GELU backward used
the pre-bias activation; its checkpoints are not evidence. See
`cnc14_promotion_and_cnc16_architecture.md`.

Candidate training SPS is not a code-speed benchmark because policy behavior changes simulator
workload and the CNC13 sweep trained several policies concurrently. Use `perf_baseline_log.md` and
the matched commands in `cnc13_abi9_2m_sweep_analysis.md` for throughput evidence. Do not claim a
new speedup from CNC14.

## Known Problems

1. **Training-seed instability.** The promoted MinGRU baseline spans robust scores from 0.0827 to
   0.2565 on the corrected architecture suite. The tested MLP is substantially worse, so removing
   recurrence does not solve the problem.
2. **Zig-to-Vanilla transfer parity.** The last broad matched evaluation produced 89% Zig wins,
   42% Vanilla wins, and only 83/200 matching terminal outcomes. Remaining systematic divergence
   begins around decision 179 in infantry facing, missions, position, flags, and map occupancy.
3. **Flat observation encoding.** Observation version 6 transports a compact 2,456-byte state, but
   the policy divides every field by 255 and projects the flat vector. This loses the semantics of
   booleans, ids, coordinates, health, map resources, and repeated entity records. Compacted entity
   slots also shift and can omit controllable infantry.
4. **ABI9 tuple rejection.** Seven independently sampled heads produce approximately 44.9% invalid
   tuples, which become four-frame no-ops. Nonzero invalid-action penalties were rejected by the
   matched ABI9 study. Exact conditional ABIs removed rejection but learned worse, so another
   decoder should wait for meaningful entity and spatial embeddings.
5. **Economy is avoidable.** Random credits and starting defenders make unconditional rushing less
   reliable, but harvesting is still not structurally necessary.
6. **Promotion evaluation is not automatic inside Protein.** Protein now sees H5-only `perf`,
   terminal rates, and `balanced_perf` during curriculum training, while the stronger fresh-suite
   `robust_perf` gate is still a separate evaluator command.

Exact single-GPU native continuation is accepted. Version-4 state files preserve the TD Micro
worlds, episode counters, reward and metric state, host/GPU vector buffers, policy, Muon momentum,
learning-rate and loss buffers, CUDA sampling states and offsets, MinGRU state, epoch, and global
step. An immutable schedule is separate from the temporary stopping rung. At 262,144 transitions,
an uninterrupted process and a fresh process resumed at 131,072 produced exact final state,
weights, post-split action/reward/terminal trace, and environment metrics across 61 completed
post-split episodes, with zero failures. See `cnc13_training_state_checkpoint.md`.

The decision-179 Zig/Vanilla issue is cross-engine parity failure, not same-engine nondeterminism.
Both engines repeat their own traces exactly. The earliest retained example is policy decision 179,
game frame 716: the first player infantry is encoded as `MOVE` in Zig and `ATTACK` in Vanilla. The
dominant first-mismatch fields across 200 runs are infantry mission and facing, followed by movement
flags, position/occupancy, and health. The strongest current hypothesis is an off-by-one or ordering
difference in Barracks egress, animation/radio-tether release, active movement interruption, and
queued ATTACK commencement. Dynamic infantry-list ordering and subcell reservation/scatter behavior
are secondary likely causes. Shared RNG divergence is probably an amplifier after the first branch,
not the initial cause.

## Low-Hanging Work

1. CNC25 build/test/train smoke and fixed-evaluator plumbing check are done; see
   `docs/perf_baseline_log.md`. CNC24's tmux session was stopped during this validation pass, so
   the next promotion sweep launch has the GPU to itself; decide whether to resume CNC24 first.
2. Run the real fixed Easy and fixed Normal promotion suites (with a trained checkpoint, full
   12,000-decision cap) before interpreting a mixed CNC25 training metric or launching the sweep.
3. Perform the canonical seed-73 to seed-42 migration as its own clean, deterministic commit.
4. Keep the selected action scheme and MinGRU fixed while replacing the flat observation projection with typed global,
   entity, and spatial encoders plus stable entity identity and masked pooling.
5. Continue the focused decision-179 Zig/Vanilla parity investigation independently of learner
   changes.

## Priority Order

1. Validate and commit CNC25 as a separate deterministic difficulty experiment while CNC24
   remains historical and untouched.
2. Train CNC25 only after its launcher, fixed Easy/Normal evaluator, failure counters, and adjacent
   performance gate pass.
3. Promote a result only when fixed Easy and fixed Normal suites reproduce across seeds and all
   spawn-by-force/credit cells.
4. Migrate the canonical development seed to 42 in its own deterministic commit.
5. Close the remaining Zig/Vanilla policy-path and outcome parity gap.
6. Replace the flat encoder with typed globals, stable entity identity, entity embeddings, spatial
   resource features, and masked pooling while keeping ABI9 and rewards fixed.
7. Automate fixed-suite robust evaluation in future candidate selection.
8. Revisit an exact conditional action decoder only after actor and target representations exist;
   preserve one explicit no-op and calibrate entropy separately from ABI9.
9. Then make harvesting structurally necessary and add long starts and later
   curriculum stages.

Do not stop or mutate CNC24, add another action ABI, or optimize isolated one-percent simulator
paths while CNC25 validation is in progress.

## Evidence And Detailed Plans

- `docs/td_micro/cnc13_abi9_2m_sweep_analysis.md`
- `docs/td_micro/stable_training_curriculum_plan.md`
- `docs/td_micro/cnc13_training_state_checkpoint.md`
- `docs/td_micro/cnc14_promotion_and_cnc16_architecture.md`
- `docs/td_micro/cnc23_defended_curriculum_5mi_sweep.md`
- `docs/td_micro/cnc24_action_scheme_5mi_sweep.md`
- `docs/td_micro/cnc25_difficulty_curriculum.md`
- `docs/td_micro/abi14_group_action_experiment.md`
- `docs/td_micro/abi8_parity_corrections.md`
- `docs/td_micro/TODO.md`
- `tools/cnc13_stable_candidates.json`
- `tools/cnc13_stable_confirmation.py`
- `tools/cnc_micro_fixed_eval.py`
- `tools/cnc16_architecture_ablation.py`
- `PufferLib/logs/cnc_micro/cnc13_confirmation_eval/`
- `PufferLib/logs/cnc_micro/cnc14_promotion_v1/`
- `PufferLib/logs/cnc_micro/cnc16_architecture_v2/`
