# CNC35 Harvester regression repair

Authoritative as of 2026-07-28. CNC34 is invalid and stopped. CNC35 is the first sweep using the
repair described here.

## Failure

CNC34's first three completed trials all reported `full_perf=0`. This was not only a sparse-window
display problem:

- two trials had zero raw wins and one had raw `perf=0.00126`;
- mean delivered Tiberium was `0`, `0.0315`, and `0.1799` credits per episode;
- the same policies still built roughly `1.05-1.23` Refineries per episode;
- failures and start failures were zero.

CNC33's median final policy delivered 10,444 credits per episode. The discontinuity was therefore
between refinery construction and Harvester delivery.

## Cause

CNC34 changed the active policy action path from ABI14 to ABI13. ABI14 deliberately excludes
Harvesters from every selector because they run the simulator's automatic harvest/return loop.
ABI13 still exposed a Harvester actor for `move`, `harvest`, and `return_cargo`.

A sampled `move` command changes the Harvester mission to `mission_move` and clears its harvesting
state. It does not automatically resume `mission_harvest`. CNC34 also deliberately set
`reward_first_delivery=0` and `reward_tiberium_income=0`, so the policy had no dense signal from
which to relearn manual coordinate selection and return sequencing. Activating ABI13 therefore
reactivated a known economy-killing action-mask defect.

`full_perf` requires a win, at least 1,000 harvested credits, at least one Medium Tank built, and at
least one tank shot. The income collapse made a full win unreachable even when a raw rush win
occurred.

## Repair

- Keep the Harvester in the ABI13 observation and stable entity-slot ordering.
- Do not place it in the ABI13 move, harvest, or return actor masks.
- Leave the simulator's validated automatic harvest/return behavior in control.
- Add ABI13 regression tests asserting that a Harvester enables none of those commands.
- Preserve the direct low-level Harvester command implementation for simulator/oracle tests; only
  the learned policy surface is restricted.

Longer fuzz trajectories made possible by the repair also reached two normal shared-array stalls.
Completed infantry now waits when the infantry array is full, matching completed vehicle behavior,
and a Refinery that cannot spawn its bundled Harvester refunds the Harvester component without
marking an engine failure.

Validation:

- 313 Zig tests pass, including the 12,000-decision masked-policy fuzz trajectories.
- The C ABI/binding test passes.
- All three focused sweep-config checks pass.
- The native CUDA extension rebuilt successfully.

## CNC35

Durable controller:

```bash
tmux new-session -d -s cnc35 -c /home/claude/cnc/.worktrees/merge-test/PufferLib \
  "bash -lc 'exec env PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=... \
  .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb --wandb-project cnc35 \
  --sweep.gpus 1 --sweep.max-runs 1000 --sweep.workers-per-gpu 1 \
  > logs/cnc35-tmux.log 2>&1'"
```

The sweep varies only:

- `train.total_timesteps`: 5,242,880 to 10,485,760;
- `env.reward_refinery`: 0.3 to 0.6.

First live acceptance snapshot:

| Run | Agent steps | Tiberium income | Raw perf | Full perf | Failures | Start failures |
|---|---:|---:|---:|---:|---:|---:|
| `sgthem51` | 1,935,360 | 2,950.0 | 0.3333 | 0.0000 | 0 | 0 |
| `e7lt64wv` | 2,150,400 | 11,316.7 | 0.0000 | 0.0000 | 0 | 0 |
| `7yvk6cj7` | 1,859,584 | 3,537.5 | 0.2500 | 0.2500 | 0 | 0 |

The required acceptance condition was nonzero delivered income with clean starts. All three trials
pass it, and one already has a full win. CNC34's mechanical zero is repaired.

## Throughput correction

The first CNC35 controller incorrectly used three simultaneous sweep workers. On this eight-core
host the three native environments saturated the CPU while the GPU remained underused:

- completed runtimes were 861.9, 967.7, and 1,081.1 seconds;
- final SPS was 8.3K, 7.0K, and 4.8K;
- the native environment evaluation dominated the timing.

This initially looked like an ABI13 simulator regression. A matched single-worker check disproved
that attribution:

```text
train cnc_micro --train.total-timesteps 1048576
agents=64 buffers=1 threads=4 horizon=32 minibatch=2048 GPU
SPS=27.7K runtime=41s start_failures=0 failures=0 valid=yes
```

The unchanged single-worker sweep then reported 28.8K SPS at 1.20M steps, with
`start_failures=0`, mean delivered income 9,022, and a live `full_perf=0.111`. Its first complete
5,242,880-step trial finished at 17.8K SPS in 334 seconds with `start_failures=0`, `failures=0`,
mean delivered income 5,720, and `full_perf=0.0463`. The host was also running a separate
CPU-heavy dogfight evaluation; later live CNC35 points fell to roughly 12K SPS while that process
used about three cores. CNC35 was relaunched with `--sweep.workers-per-gpu 1`. One worker removes
the self-inflicted three-way oversubscription; remaining variation is external host contention and
the requested 5-10 Mi trial length.
