# TD Micro Puffer Log Schema

Current for runtime-selectable ABI9/ABI14, H0-H5, starting-force, and CNC25 difficulty curricula as
of 2026-07-23.

The native environment exports 28 fields. PufferLib adds `env/n`, leaving two reserved live-metric
slots under the 31-field project limit. Episode totals are aggregated by the C binding; rate fields
use their declared episode denominators instead of the mixed `env/n` denominator.

## Outcome Contract

| Field | Meaning |
| --- | --- |
| `perf` | H5 full-match wins divided by completed H5 episodes |
| `draw_rate` | H5 full-match draws divided by completed H5 episodes |
| `balanced_perf` | Equal-weight mean of `easy_balanced_perf` and `normal_balanced_perf` |
| `easy_balanced_perf` | Equal-weight mean of the four H5 spawn x starting-force cells at requested Easy |
| `normal_balanced_perf` | Equal-weight mean of the four H5 spawn x starting-force cells at requested Normal |
| `normal_episode_share` | Requested-Normal H5 episodes divided by all completed H5 episodes |
| `full_match_episode_share` | Completed H5 episodes divided by all completed episodes |
| `starting_force_episode_share` | Unit Count 6 episodes divided by completed H5 episodes |
| `episode_return` | Mean shaped and terminal return across the complete H0-H5 mixture |
| `episode_length` | Mean policy decisions across the complete H0-H5 mixture |

For a valid log window containing H5 completions, the unexported loss rate is
`1 - perf - draw_rate`. Both exported rates are zero when no H5 game completed in that window.
H0-H4 terminals never enter their numerator or denominator. A successful reset does not add a
denominator entry. Any nonzero `failures` or `start_failures` sample invalidates a training or
throughput claim.

The CNC25 sweep objective remains `balanced_perf`, now the equal-weight average of requested Easy
and requested Normal performance. Each difficulty first equal-weights its four spawn x
starting-force cells. Under reverse curriculum schedule 1, these counters include only H5
full-match episodes. Thus all terminal performance fields are H5-only. Shaped return, production,
combat, and economy fields remain mixed training diagnostics. The fixed evaluator also forces H5,
disables every curriculum clock, and evaluates one requested difficulty at a time.

The fixed evaluator additionally writes the starting-force variant, exact starting credits, four
credit bands, and W/L/D for all 16 spawn x force x credit-band cells to JSON/JSONL sidecars. Its
`credit_balanced_perf` and `credit_robust_perf` are offline promotion metrics, not live Puffer log
fields. See `deterministic_starting_force.md` and `deterministic_starting_credits.md`.

## Training Reporting Window

Puffer's training logger clears its completed-episode accumulator after each emitted point. The
generic default remains `log_interval=0.6` seconds, while `cnc_micro` uses `1.8` seconds. This
combines approximately three former windows without changing rollouts, PPO updates, environment
mix, or the metric values.

An adjacent one-million-transition CUDA A/B used 64 agents, one buffer, four threads, horizon 32,
minibatch 2,048, and MinGRU 64x1. The first four downsampled training bins represented these
estimated H5 completion counts (`env/n * full_match_episode_share`):

| Interval | Run | Estimated H5 games per point | Final checkpoint SHA-256 |
| ---: | --- | --- | --- |
| 0.6 s | `1784770211044` | 2.62, 3.58, 3.18, 3.86 | `98426969...98e2d47` |
| 1.8 s | `1784769912811` | 9.29, 10.81, 8.71, 9.04 | `98426969...98e2d47` |

Both runs had zero engine and start failures, identical final policy bytes, and identical final
environment metrics. The 1.8-second interval therefore improves the statistical resolution of the
live curve without changing training determinism. It does not increase games per second; it emits
fewer, better-supported points. The single adjacent pair showed no SPS regression, but is not a
throughput speedup claim.

## Exported Fields

Outcome and validity:

- `perf`
- `episode_return`
- `episode_length`
- `draw_rate`
- `invalid_actions`
- `failures`
- `start_failures`

Production, combat, and economy:

- `gunners_built`
- `rocket_soldiers_built`
- `unit_kills`
- `unit_losses`
- `buildings_lost`
- `buildings_destroyed`
- `enemy_attack_orders`
- `refineries_built`
- `tiberium_income`

Spawn-bucket accounting:

- `full_match_episode_share`
- `starting_force_episode_share`
- `close_win_rate`
- `close_mcv_win_rate`
- `close_force_win_rate`
- `medium_win_rate`
- `medium_mcv_win_rate`
- `medium_force_win_rate`
- `balanced_perf`
- `easy_balanced_perf`
- `normal_balanced_perf`
- `normal_episode_share`

The current full-match spawn balance covers close and medium starts; a future far bucket must be
added to both H5 accounting and the objective before it can affect promotion. `tiberium_income` is
the mean total Harvester-delivered credits per completed episode in the reporting window, not
current stored Tiberium. The reporting-window total is `tiberium_income * env/n`. `invalid_actions`
is the rejected tuple count from completed episodes only.

## Low-Level Metrics Not Exported

The Zig/C batch ABI retains counters that are useful for tests and replay diagnosis but are
intentionally omitted from the live Puffer/W&B surface:

- opponent E1/E3 production;
- opponent kills/losses and economy;
- accepted/rejected train actions;
- player Harvester spawn counts and capped invalid-action penalty;
- Construction Yard, Power Plant, Barracks, E1, E3, Refinery, Harvester, and first-delivery
  milestone counts;
- `infantry_limit_losses`; and
- the disabled legacy `invalid_streak_losses`.

Legacy counters remain available through the 248-byte `TdMicroBatchStats`. CNC25's additional
difficulty counters use the 376-byte `TdMicroBatchStatsV2` and `td_micro_batch_stats_v2`; removing a
counter from the Puffer dictionary does not remove its behavior or tests.

The batch ABI also retains loss counters for each spawn x starting-force cell. Live telemetry needs
only episodes and wins because detailed loss/draw splits can be derived offline.

## Retired Live Fields

- `units_built` was exactly
  `gunners_built + rocket_soldiers_built + harvesters_spawned`, so consumers now derive it offline.
- `power_plant_milestones` was a low-information prerequisite diagnostic. The native counter remains
  available, while Barracks, Refinery, production, and economy fields carry later progression.
- `close_loss_rate` and `medium_loss_rate` were redundant for optimization because the retained
  spawn-specific win rates fully define `balanced_perf`; overall H5 loss is derivable from retained
  `perf` and `draw_rate`.
- `building_limit_losses` diagnoses the artificial 16-building guardrail. The native counter and
  terminal rule remain tested, but historical training/evaluation samples stayed at zero.
- `barracks_milestones` was superseded by actual infantry production.
- `refinery_milestones` was redundant with `refineries_built`.
- `first_delivery_milestones` was redundant with `tiberium_income > 0`; retaining the income
  magnitude is more informative than a binary flag.
- `invalid_action_penalty` stayed zero because the active rules fix its coefficient at zero.
- `loss_rate` is derivable as `1 - perf - draw_rate` for every valid H5 reporting window.
- `harvesters_spawned` is represented by `refineries_built` under the current bundled-Harvester
  rules; `tiberium_income` measures whether those Harvesters actually delivered.

## ABI Verification

The standalone binding smoke enforces:

```text
CNC_MICRO_EXPORTED_LOG_COUNT == 28
CNC_MICRO_LOG_FLOAT_COUNT == 55
sizeof(Log) == 56 * sizeof(float)  // stable internal layout plus n
sizeof(TdMicroBatchStats) == 31 * sizeof(uint64_t)
sizeof(TdMicroBatchStatsV2) == 47 * sizeof(uint64_t)
```

Its final output is:

```text
episode_return=0.250 draw_rate=1
```

The ABI-9 binding smoke retains the same `episode_return=0.250 draw_rate=1` result with the
2,456-byte observation. The accepted GPU run `1784347201969` completed 1,048,576 steps with all
logged `env/failures` and `env/start_failures` samples equal to zero. Full command and results are in
`docs/td_micro/compact_observation_and_sweep_slots.md`.

CNC22 loaded its prior MCV-only extension before the starting-force source change. Its logs remain
valid for that historical domain, but they do not exercise starting forces and their
`balanced_perf` retains the prior two-spawn meaning. CNC22 has stopped; the rebuilt extension and
CNC23 preflight are documented in `cnc23_starting_force_preflight.md`.

CNC24 predates difficulty schema 10. Its logs retain the four-cell
spawn x starting-force `balanced_perf` meaning and do not contain per-difficulty fields. CNC25
training logs use the equal-difficulty definition above; compare projects only through their
documented historical schemas.
