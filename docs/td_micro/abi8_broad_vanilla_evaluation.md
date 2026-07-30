# ABI-8 Broad Vanilla Evaluation

Date: 2026-07-16

Status: `TASK-2` complete; transfer mismatch found

## Scope

The retained ABI-8 `lqn5ogu8` checkpoint was evaluated on 100 close and 100 medium policy-sampling
seeds. Every tuple used the same checkpoint, rules hash, setup profile, and categorical sampling
seed in the native Zig simulator and a fresh standalone `VanillaTD` process.

This is an outcome-transfer test, not a training run. It changes no rules, rewards, starts, action
ABI, or policy weights.

## Provenance

| Item | Value |
| --- | --- |
| Checkpoint | `PufferLib/checkpoints/cnc_micro/lqn5ogu8/0000000001048576.bin` |
| Checkpoint SHA-256 | `d1d283876cb05113eefe9436add60d52677a1905c9ab00b25ea770ef52664a05` |
| Rules SHA-256 | `1dc2ff0a28076c0cf2e1fb3c85ac35ea0704c794cee1f89703a56b950c90b6ae` |
| Base source commit | `0f40722992653e02ed915b92d9a503d9e7bf4c6a` |
| Evaluation patch SHA-256 | `2b96a0cfe4d3d1f0cf769d2e0e4a0d807c156d06bcd85faadbdc3f0608f026ed` |
| Runner SHA-256 | `4a9579006b2afdb74be35305e4bbaadfa1d3e2740095289b6aa99931fecc9310` |
| Native evaluator SHA-256 | `39a752cedb96bcc2022120826d0b7044f81daed8247758f3aa8292973ef0ad50` |
| VanillaTD SHA-256 | `a922cabe5f35e128bad363a1dd20170c3209ed85c10fbaba0a37c69a479aadae` |

The source was intentionally recorded as the parity commit plus a tracked evaluation-only patch;
the raw records retain both identifiers. The patch adds the sampling-seed override and failure
telemetry used by the runner.

## Command

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1
python3 tools/td_micro_transfer_eval.py \
  --checkpoint PufferLib/checkpoints/cnc_micro/lqn5ogu8/0000000001048576.bin \
  --native-evaluator /tmp/td_micro_policy_c_api_smoke \
  --output docs/td_micro/results/abi8_transfer_100x2 \
  --work-root /tmp/td-micro-transfer-abi8-100x2-work \
  --samples-per-profile 100 \
  --sample-seed-start 1000 \
  --jobs 10 \
  --timeout-seconds 180
```

Close uses setup seed 1, medium uses setup seed 2, and both use policy-sampling seeds `1000..1099`.
Successful large traces were discarded after comparison; compact raw episode records were retained.

## Results

| Profile | Engine | W/L/D | Win rate | Terminal agreement | Exact traces |
| --- | --- | ---: | ---: | ---: | ---: |
| Close | Zig | 78/22/0 | 78% | 39/100 | 0/100 |
| Close | Vanilla | 25/75/0 | 25% | 39/100 | 0/100 |
| Medium | Zig | 100/0/0 | 100% | 59/100 | 0/100 |
| Medium | Vanilla | 59/41/0 | 59% | 59/100 | 0/100 |
| Overall | Zig | 178/22/0 | 89% | 98/200 | 0/200 |
| Overall | Vanilla | 84/116/0 | 42% | 98/200 | 0/200 |

Because both profiles have 100 episodes, the equal-profile-balanced Vanilla win rate is also 42%.
All 200 tuples were valid. Startup, schema, controller, native-engine, and Vanilla-engine failures
were all zero.

The earlier retained smoke and this broad run independently evaluated close/1000 and medium/1000.
For both tuples, native result and full trace hash, Vanilla result and full trace hash, and first
divergence were identical across runs. This verifies fresh-process repeatability for the retained
cross-run samples.

## First Divergence

Every matched trajectory diverged before terminal:

| First divergent policy state | Count | Zig byte | Vanilla byte |
| --- | ---: | ---: | ---: |
| Decision 6, frame 24, own entity 0 facing | 27 | 166 | 171 |
| Decision 6, frame 24, own entity 0 facing | 6 | 186 | 191 |
| Decision 76, frame 304, enemy entity 1 construction progress | 167 | 22 | 13 |

The decision-6 cases expose a five-unit MCV-facing discrepancy after an early sampled command. The
remaining cases expose different original-AI building construction progress. Once either byte
differs, policy logits and subsequent sampled actions can differ, so later outcome disagreement is
not attributable to sampling noise.

## Conclusion

The broad gate rejects the previous assumption that native policy quality transfers closely to the
real game. Native evaluation overstates win rate by 47 percentage points on this matched set, and
terminal outcomes agree on only 49% of tuples.

Do not add a far spawn, retrain, or promote this simulator state yet. First reproduce and close the
two early policy-visible discrepancies, then rerun this exact 200-tuple gate. The real Vanilla
engine remains the behavioral reference.

Raw evidence:

- `docs/td_micro/results/abi8_transfer_100x2/episodes.jsonl`
  (`e607d16a2d120e6545f711aa679ee0bc33ae6a46187a0a5ebaba39e36c082fdd`)
- `docs/td_micro/results/abi8_transfer_100x2/summary.json`
  (`fc91216a7d1dcbd975ad1323ca25af1bf89a020a349c30c8861ecebd979515cb`)

## Follow-Up

The first `TASK-2A` correction pass removed both universal early mismatch classes and pushed first
divergence from decision 6/76 to decision 179 or later. It did not close outcome parity: the matched
rerun reached only 83/200 terminal agreements. See `docs/td_micro/abi8_parity_corrections.md` for
the implementation, tests, hashes, throughput A/B, and raw 200-episode result.
