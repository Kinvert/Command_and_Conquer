# TD Micro Policy-Death Terminals

Recorded: 2026-07-13

Current contract updated: 2026-07-16

TD Micro separates policy-caused task deaths from simulator failures. Policy deaths emit terminal
reward `-1.0`, increment `losses` plus one named counter, and auto-reset the world. They do not
increment `failures` and therefore do not invalidate an SPS run.

| Condition | Limit | Counter |
| --- | ---: | --- |
| Active player buildings | 16 | `building_limit_losses` |
| Active player infantry | 64 | `infantry_limit_losses` |

The terminal fires after a limit is exceeded. A real TD win or loss on the same decision takes
precedence over the policy-death classification.

The former 128-consecutive-invalid terminal is disabled. ABI 5 retains the exported limit and
`invalid_streak_losses` field for compatibility, but the limit is `0` and the counter remains zero.
Rejected tuples are diagnostic no-ops that advance four game frames. This avoids turning independent
head incompatibilities into artificial `-1` losses or teaching the policy that no-op is safer than
exploration. The building and infantry limits remain training-task rules, not claims about stock TD.

Hard fixed-array exhaustion, unsupported content, unsupported seeds, startup failure, and parity
failure remain engine failures. They must increment `failures` or fail a test and make a throughput
claim invalid rather than being relabeled as a policy loss.

ABI 7 keeps the physical 128-entry infantry pool while making its lifetime semantics safe for long
matches. After each RL decision, completed death-animation entries are compacted in stable active
order, infantry/projectile references are remapped, and the external death ledger is compacted with
the entities. Destroyed Harvester slots above the two reserved MCV slots are reclaimed after
unit-loss accounting. Simultaneous live/dying capacity exhaustion still remains an engine failure.

The Puffer log surface no longer exports `infantry_limit_losses` because ABI 7 uses all 31 available
environment fields for higher-value economy and outcome metrics. The counter remains in
`TdMicroBatchStats` and its behavior is unchanged.

TDD coverage is in `td-micro/tests/batch_test.zig`. Building and infantry tests assert terminal
`-1.0`, the exact named counter, clean reset state, and zero engine failures. A separate regression
submits 129 consecutive invalid tuples and asserts no terminal, zero reward, advancing game time,
and exact diagnostic counts. Additional regressions verify infantry compaction/reference remapping
and destroyed-Harvester slot reuse.
