# TD Micro Reward Shaping V2

Recorded: 2026-07-14

> Historical run record. The active contract is reward v3 in
> `docs/td_micro/policy_win_path_and_reward_v3.md`; it removes the repeated pre-deploy penalty and
> invalid-streak terminal and adds bounded production/combat shaping.

## Contract

The current curriculum reward is:

| Event | Reward |
| --- | ---: |
| First Construction Yard, Power Plant, Barracks, E1, or E3 | `+0.1` each |
| Each player-owned E1/E3 death | `-0.001` once |
| Win / loss / timeout-draw | `+1.0` / `-1.0` / `0.0` |

Completing all five milestones does not terminate the episode. MCV deployment is not treated as a
casualty. A terminal result replaces shaping on that terminal decision; shaping earned or lost on
prior decisions remains in the episode return.

The batch wrapper tracks penalized infantry slots outside `World`. This catches an infantry unit
produced and killed within one four-frame decision, prevents duplicate penalties for death
animations, and leaves canonical simulation state unchanged.

## TDD And Determinism

The focused tests cover the exact `0.1` milestone value, one owned E1 death penalized once, no repeat
on the next decision, no opponent-death penalty, and no MCV-deployment casualty penalty.

```text
Debug       73/73 passed
ReleaseSafe 73/73 passed
ReleaseFast 73/73 passed
C binding reward test: episode_return=0.100 draw_rate=1
C ABI smoke digest: a2ed292eae3a17e9fb925a60c775b1b7c9d0e1473ca53616c4365e206d663ad2
```

The ABI smoke digest is unchanged from the prior baseline. Two independent rollouts of the selected
3,147,776-step checkpoint produced byte-identical command telemetry and episode summaries.

## GPU Training Run

Command, run from `PufferLib/`:

```bash
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 4 \
  --vec.num-threads 4 \
  --train.total-timesteps 10485760 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 512 \
  --eval-episodes 1
```

Results:

| Field | Result |
| --- | ---: |
| Aggregate timesteps | 10,485,760 |
| Final dashboard SPS | 110,100 |
| Dashboard uptime | 1m 49s |
| Approximate aggregate SPS including checkpoint saves | 96,200 |
| `start_failures` | 0.000 |
| Engine `failures` | 0.000 |
| Throughput validity | valid |

Raw log: `docs/td_micro/benchmarks/cnc_micro_gpu_reward_v2_10m.log`.
Checkpoint directory: `PufferLib/checkpoints/cnc_micro/1784060776866/`.

PufferLib's checkpoint interval is measured in epochs, not timesteps. At 64 agents and horizon 32,
one epoch is 2,048 aggregate steps, so interval 512 retains a checkpoint about every 1,048,576
steps. The config default now uses 512.

## Deterministic Checkpoint Evaluation

All unique retained checkpoints were rolled out from seed 1 through terminal with the native Zig C
API. `Positive` counts decisions with positive shaping reward, and every checkpoint emitted zero
engine failures.

| Steps | SHA-256 | Positive | Decisions | Result |
| ---: | --- | ---: | ---: | --- |
| 2,048 | `2b2f4591572424230f8d9d8e1dfd17f9bcf7f50bc36b8bb9fcaa1df4cc98734a` | 0 | 2,090 | legitimate loss; all no-op |
| 1,050,624 | `5eceeac7c0ab70fede69027829352e720d659eedf99db5e0b2bd4e0ba5479048` | 2 | 1,086 | invalid-streak loss |
| 2,099,200 | `9cadbef4f9ff2a39a528243b3b60cfac976ad086f659cc4f7b7bbbb22e4934de` | 2 | 3,137 | building-limit loss |
| 3,147,776 | `5e5f656896b405c779cfdb6173c5f156261aba4f8ac35d48092a45f00e81c451` | 2 | 4,077 | legitimate loss; exact-repeat gate passed |
| 4,196,352 | `249910a629b64e3a021b273d85de60a763830e67b95b8fb404990d6e4a6923a5` | 0 | 128 | invalid-streak loss |
| 5,244,928 | `d35fb34490fe22530a0936e8195641ffb823910a7b8b6ecf707f9135f9cc8d71` | 1 | 2,611 | legitimate loss |
| 6,293,504 | `5124e5c3c75b31197902a79c6c66174a21e33a5155ee73a2836f9ac534db82bb` | 1 | 1,195 | invalid-streak loss |
| 7,342,080 | `a1a913718ac08ef526739d284ccc97343f114db6aeecbb6242810a9b79dd5e87` | 2 | 3,474 | legitimate loss |
| 8,390,656 | `d9b1f7f1e61c97ffeda686445f40bd73cd6794a89cadfaf2968261a4aa492a28` | 0 | 2,090 | legitimate loss; all no-op |
| 9,439,232 | `c71796ebc5ca20a8d06214532c54fdd5a8e55ac79321a58bef251a35b885d5b9` | 0 | 1,463 | invalid-streak loss |
| 10,485,760 | `9239078f7ab47697563078f83cdeab1492340d97d87c196260959df6d859938c` | 1 | 2,156 | legitimate loss |

The final 10,487,808-step save duplicates the 10,485,760-step hash. No retained checkpoint issued a
train-infantry command, so none reached E1 or E3. This run is valid throughput evidence but rejected
as a transfer-policy improvement. The older 1,048,576-step checkpoint remains better: it reached
Construction Yard, Power Plant, Barracks, and E1 in native evaluation and visibly placed Power and
Barracks in Vanilla. Re-evaluated under reward v2, that older checkpoint deterministically terminates
after 523 decisions with four positive shaping decisions, return `-0.61`, zero engine failures, and
SHA-256 `c5197d742617cbfdb3e230f65b237ca6b3c8f1c79cc9b70e238a320a1b756786`.

## Instrumentation Finding

The Puffer binding previously reported `episode_return` as `wins - losses`, hiding shaping from the
dashboard. Training still received the correct reward tensor. The binding now accumulates actual
per-agent rewards until terminal, with a C regression proving a shaped draw reports `0.100`.

The existing pre-deploy penalty remains `-0.01` per decision. It dominates this reward scale: an
all-noop 2,090-decision loss returns `-21.89`, while all five positive milestones total only `+0.5`.
Removing it or changing it to a one-time bounded penalty is the next reward-design decision before
another long training run.

## M6-Aligned Follow-Up

A fresh 1,048,576-step ABI4 GPU run used the final 1,800-decision timeout contract and reached
102,519 SPS with zero startup or engine failures. Its selected checkpoint is
`e67950993827b5f72951943e71b5c62cef15787bbfd52a220830f40bc61c7765`. It deterministically builds
repeated Power Plants in native evaluation and produced the same behavior while controlling visible
Vanilla TD through the full 7,200-frame timeout. This completed the transfer gate but did not solve
the reward-scale or policy-quality issue. Full evidence is in
`docs/td_micro/m6_visible_policy_transfer.md`.
