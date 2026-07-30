# CNC25 Difficulty Curriculum

Date: 2026-07-23

Status: implemented and validated in the isolated `td-micro-cnc25` worktree. The deterministic
parity suite (Debug/ReleaseSafe/ReleaseFast), C API smokes, Vanilla oracle fixture recording, the
CNC25 fixed-evaluator plumbing smoke (Easy and Normal), and a canonical CUDA training run all pass;
see `docs/perf_baseline_log.md` for the SPS entries. The `tools/run_cnc25_difficulty_5mi_sweep.sh`
promotion sweep itself has not been launched. CNC24 remains a separate historical action-scheme
experiment; its tmux session was stopped to free the GPU for this validation pass and it is not
otherwise modified by this work.

## Experiment Contract

CNC25 adds one independent curriculum dimension to the existing TD Micro domain:

- selected action path: ABI14 group actions (`env.action_scheme=1`);
- opponent schedule: 90% requested Easy / 10% requested Normal at the start;
- terminal schedule: 10% requested Easy / 90% requested Normal;
- Hard: representable and parity-tested, but not sampled by CNC25 training;
- unchanged: H0-H5 curriculum, starting-force curriculum, maps, credits, units, rewards, decision
  interval, terminal rules, policy family, and Puffer CUDA backend.

The purpose is to learn a policy that retains Easy performance while progressively facing the
stock Normal opponent. It is not evidence for unrestricted Normal or Hard Tiberian Dawn.

## Westwood Difficulty Mapping

Tiberian Dawn stores the multiplayer computer handicap in the inverse order from the requested
skirmish label. TD Micro names the public selection separately from the internal `DiffType`:

| Requested | Internal handicap | Firepower | Ground speed | Armor damage | ROF | Cost |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Easy | `DIFF_HARD` (2) | 0.9 | 0.9 | 1.05 | 1.05 | 1.0 |
| Normal | `DIFF_NORMAL` (1) | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 |
| Hard | `DIFF_EASY` (0) | 1.1 | 1.1 | 1.0 | 0.8 | 0.8 |

The values are generated from `td-micro/rules/td_micro_v1.json` and applied to both the Vanilla
oracle and Zig simulator. CNC24 and earlier TD Micro runs assigned an Easy label but neutralized
the stock multipliers to 1.0. Those runs remain valid for their historical domain; they are not
stock-Easy difficulty evidence.

The supported Zig mechanics apply the reachable stock effects to:

- infantry and Harvester ground speed;
- MCV deployment rotation;
- weapon damage and reload delay;
- incoming armor-biased damage; and
- original-AI purchase cost.

Repair, wall destruction, aircraft, and unsupported production branches remain outside the current
rules subset.

## Deterministic Schedule

Each lane has a separate `difficulty_decisions` clock. For ramp length `R`:

```text
normal_percent(d) = 10 + floor(80 * min(d, R) / R)
```

Episode selection uses a deterministic lane/episode permutation and consumes no gameplay RNG.
Difficulty advances on every training decision, independently of H0-H5 progression and the
starting-force ramp. Fixed schedules require a zero ramp:

| ID | Schedule |
| ---: | --- |
| 0 | fixed Easy |
| 1 | Easy-to-Normal CNC25 ramp |
| 2 | fixed Normal |
| 3 | fixed Hard |

Exact continuation snapshots preserve the schedule ID, ramp length, and each lane's difficulty
clock. Incompatible settings reject the snapshot instead of resuming under a different domain.

## Observation And Metrics

Observation version 6 remains 2,456 bytes. Global byte 33 contains the requested opponent
difficulty:

```text
0 = Easy
1 = Normal
2 = Hard
```

Older checkpoints have the same input tensor size but were trained with byte 33 always zero.
CNC25 must train fresh; a checkpoint is not certified for Normal merely because its tensor loads.

Only completed H5 full matches enter performance metrics. For each difficulty, the environment
retains four cells:

```text
close / MCV-only
close / Unit Count 6
medium / MCV-only
medium / Unit Count 6
```

The live objective is:

```text
easy_balanced_perf   = mean(Easy four-cell win rates)
normal_balanced_perf = mean(Normal four-cell win rates)
balanced_perf        = 0.5 * (easy_balanced_perf + normal_balanced_perf)
```

`normal_episode_share` verifies the realized H5 mix. `perf` remains pooled H5 wins divided by
pooled H5 episodes and is therefore schedule-weighted; it is not the CNC25 sweep objective.
Curriculum H0-H4 episodes never enter these denominators.

The binding exports 28 fields. Puffer appends `env/n`, for 29 total fields under the project limit
of 31.

## Fixed Promotion Evaluation

Promotion runs the same frozen checkpoint twice on fresh suites:

```bash
cd /home/claude/cnc/PufferLib
source .venv/bin/activate
python ../tools/cnc_micro_fixed_eval.py CHECKPOINT --action-scheme 1 --difficulty easy \
  --output logs/cnc_micro/cnc25-easy.json
python ../tools/cnc_micro_fixed_eval.py CHECKPOINT --action-scheme 1 --difficulty normal \
  --output logs/cnc_micro/cnc25-normal.json
```

The evaluator pins H5, disables every curriculum clock, validates observation byte 33, and names
the difficulty in its artifact. CNC25 promotion equal-weights the Easy and Normal fixed-suite
scores offline. A mixed live training window is not a substitute for these two evaluations.

Legacy binary win-trace version 3 does not encode episode difficulty or curriculum progress. The
Puffer binding therefore disables that trace path for schedule 1 and directs CNC25 evaluation to
the fixed artifacts.

## Parity Evidence

The Vanilla oracle records each fixture twice and requires byte-identical output. The current
rules manifest is:

```text
d0f18637c1eed32963ef1ff5162e3b3e7f6914364a0ade59e67901f0e8ed595b
```

Recorded fixture coverage:

| Fixture class | Easy SHA-256 | Normal SHA-256 | Hard SHA-256 |
| --- | --- | --- | --- |
| autonomous opening | `c66a9ca...ea21930` | `516aefd1...e650da3` | `4b51d4c3...e650da3` |
| E1 duel | `f983323c...07242` | `b3f8ae29...9bfea` | `8d335f6c...a1846` |
| opponent E1 move | `38ab5059...8f2d` | `d433d8b6...2836` | `ab012a53...63636` |

The autonomous trace compares reset state, every four-frame command list, RNG, AI state, MCV
facing/deployment, construction-yard state, queue stage, credits, and purchase cost through frame
96. Easy starts its first Power Plant at frame 88; Normal and Hard start at frame 84. Hard pays 240
credits, while Easy and Normal pay 300.

Combat parity caught and fixed one real ordering bug: Vanilla halves prone-infantry damage before
applying the target armor bias. The three duel traces now match exact health, projectile, timing,
and RNG state through frame 160.

Policy-visible opponent movement state matches through frame 100 at all three difficulties.
The direct movement probe's post-reset shared RNG diverges on Normal at frame 40 while cell,
subcell coordinates, facing, mission, movement flags, path, speed, and destination remain exact.
This is a retained per-cell/idle-ordering gap, so CNC25 does not claim complete frame-level
closed-loop RNG parity from that probe. The autonomous opening does retain exact RNG through its
declared frame-96 boundary.

## Compatibility

- `td_micro_batch_create_with_configs` retains the legacy neutral-difficulty behavior.
- `td_micro_batch_create_with_configs_v2` enables the explicit schedule.
- `CNC_TD_Micro_Configure` likewise retains historical neutral oracle behavior, while
  `CNC_TD_Micro_Configure_Difficulty` explicitly enables stock requested difficulty.
- `TdMicroBatchStats` remains the 248-byte legacy ABI.
- `TdMicroBatchStatsV2` and `td_micro_batch_stats_v2` expose the 376-byte CNC25 counters.
- Batch snapshot versions are 4 for full match and 7 for reverse curriculum.
- Puffer state version is 5.

The legacy stats call has a canary test proving it cannot overwrite a caller's old buffer.

## Launch

Build, tests, fixed evaluator smoke, and a canonical SPS check now pass and are recorded in
`docs/perf_baseline_log.md`. The promotion sweep itself has not been launched:

```bash
cd /home/claude/cnc
tools/run_cnc25_difficulty_5mi_sweep.sh 1000
```

The launcher targets W&B project `cnc25`, uses the normal Puffer CUDA path with three workers, and
does not use `sweep_only`. CNC24 is no longer running (its tmux session was stopped), so launching
CNC25 no longer needs to share the GPU with it, but the launch itself is a separate, explicit step
this validation pass does not take.
