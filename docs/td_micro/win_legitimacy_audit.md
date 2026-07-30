# TD Micro Win Legitimacy Audit

Date: 2026-07-15

## Verdict

The recorded `bzojokr5` wins are legitimate **stochastic training-rollout wins in TD Micro**. They
are not fabricated by Puffer aggregation, a startup failure, timeout handling, or reward shaping.
The exact training configuration reproduced its final 6/83/5 window twice, and a trace-enabled
third run produced nine winning episodes that all replayed twice with identical trajectory hashes.

This does **not** establish a winning trained policy. Every retained checkpoint lost under greedy
seed-1 inference. The leaderboard entry therefore remains a hyperparameter candidate, not a
certified policy checkpoint.

## Exact Reproduction

All three runs used 64 agents, 4 buffers, 4 threads, horizon 32, minibatch 2,048, one 64-unit hidden
layer, 1,048,576 training timesteps, CUDA training, environment seed 1, and the exact `bzojokr5`
reward vector.

| Run | Purpose | Final episodes | Win/loss/draw | Unit kills | Unit losses | Buildings lost | Buildings destroyed | Failures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `bzojokr5` | Original sweep | 94 | 6/83/5 | 18.4255 | 37.2340 | 7.9894 | 6.4681 | 0 |
| `68ra4q3e` | Checkpointed rerun | 94 | 6/83/5 | 18.4255 | 37.2340 | 7.9894 | 6.4681 | 0 |
| `1784139435355` | Trace-enabled rerun | 94 | 6/83/5 | 18.4255 | 37.2340 | 7.9894 | 6.4681 | 0 |

`start_failures` was zero in all runs. The original and both reruns agree exactly on the final
episode counts and combat metrics. The trace-enabled run reported 57,190 SPS, but tracing is an
audit mode and that number is not a throughput baseline.

## Terminal And Logger Audit

`td-micro/src/batch.zig` clears the step reward at terminal and emits `+1` only when the opponent is
defeated and the player is not. Player defeat emits `-1`; mutual defeat and timeout are draws;
engine failures increment `failures` and cannot increment wins.

`PufferLib/ocean/cnc_micro/cnc_micro.h` reads monotonic Zig batch counters and adds the exact win
delta to `perf`. PufferLib's vector logger sums those fields and divides by `env/n`; it cannot create
a positive numerator. Commit `92c836e1b5e5e5516c47b811ba2ed07a636c6cd3` also removed the old
successful-reset denominator entry, so `perf` is now exactly wins divided by completed outcomes.

TD Micro's early-win rule mirrors the enabled Vanilla TD `DestroyStructures` option. Vanilla's
`HouseClass::Check_Pertinent_Structures` calls `Flag_To_Die` when a side has no live non-wall
building or MCV. TD Micro uses the same pertinent-structure condition and a 15-frame destruction
delay. Oracle tests cover this rule and the Vanilla-matched terminal tick.

## Replayed Winning Rollouts

Set `CNC_MICRO_WIN_TRACE_PREFIX` to enable the opt-in recorder. Normal runs allocate no trace buffer
and write no files. Each trace stores the seed, reward configuration, ruleset hash, and every sampled
seven-head action. `td-micro/tools/win_trace_replay.c` rejects a trace unless native replay ends with
exactly one win, terminal reward `+1`, and zero failures, then replays it again and requires an
identical result and trajectory hash.

The exact `bzojokr5` rerun emitted nine wins across all reporting windows:

| Actions | E1/E3 built | Unit kills/losses | Buildings lost/destroyed | Attack heads | Trajectory hash |
| ---: | ---: | ---: | ---: | ---: | --- |
| 5,742 | 20/17 | 55/23 | 0/14 | 2,735 | `2d64a1e15fc0e554` |
| 6,003 | 11/21 | 47/0 | 0/6 | 3,357 | `db10d77c21a828ef` |
| 3,186 | 22/16 | 46/11 | 0/16 | 1,269 | `81479ecd34a847fa` |
| 4,585 | 16/19 | 44/25 | 0/15 | 1,664 | `3a96435b06ce4111` |
| 9,882 | 14/22 | 63/28 | 6/3 | 4,791 | `1a388307c6395ca4` |
| 2,593 | 13/21 | 40/21 | 0/14 | 1,002 | `0a80be723566f8de` |
| 9,146 | 31/15 | 51/17 | 0/17 | 5,317 | `9c9cbf84e20ca3d6` |
| 3,648 | 23/18 | 45/22 | 3/16 | 1,944 | `13e1b100219b28ff` |
| 9,317 | 19/18 | 54/18 | 0/18 | 5,490 | `e90303adeab073fb` |

Every trace contains one deploy action, accepted infantry training, movement, and explicit attack
heads. The combat and destruction counts rule out a timeout, empty-opponent initialization, or a
milestone reward being mistaken for victory.

Trace files are transient diagnostics and are not committed. Rebuild and replay with:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1
clang -std=c11 -O2 -Wall -Wextra -Werror -Itd-micro/include \
  td-micro/tools/win_trace_replay.c td-micro/zig-out/lib/libtd_micro.a \
  -ldl -lpthread -lm -o /tmp/td_micro_win_trace_replay
/tmp/td_micro_win_trace_replay /tmp/cnc-win-bzo-audit-20260715-*.bin
```

## Checkpoint Result

The checkpointed rerun retained nine distinct training snapshots through 1,048,576 steps. Four
later eval-loop files have the same SHA-256 as the final training weights. Native greedy seed-1
evaluation lost for every snapshot. The final checkpoint SHA-256 is:

```text
ddd2c78e954d5d5bd41262301bdb8e74e2e9c051d6eb0af0a05ffb99e9801940
```

The final greedy policy deployed, started construction, then repeatedly selected invalid placement;
it never trained infantry or attacked. The rollout wins arose from stochastic action sampling during
training, not from a stable greedy strategy.

## Remaining Boundary

The full winning traces have been replayed against the deterministic Zig environment, not injected
into a live Vanilla TD match. Individual combat, AI, defeat, and timing behavior has Vanilla oracle
coverage, but full-match Zig-to-Vanilla trace parity remains a separate gate before claiming the
policy wins in the original executable.
