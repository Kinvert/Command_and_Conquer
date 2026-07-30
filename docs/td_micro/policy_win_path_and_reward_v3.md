# TD Micro Policy Win Path And Reward V3

Date: 2026-07-14

## Goal

The environment does not need a scripted full-game winner. It needs a normal PufferLib action path
that can win when the policy chooses the right actions. Focused oracle traces are development tests
for individual commands; PPO remains responsible for discovering and sequencing those commands.

## Reachable Win Proof

The Vanilla oracle fixture `vanilla_seed1_e1_attack_mcv.jsonl` starts with one MCV and one E1 per
side, disables both house controllers, and submits one ordinary player command:

```text
command=attack actor=1 target_kind=visible_enemy target_slot=0
```

Vanilla's E1 chases the distant opponent MCV, pathfinds into weapon range, destroys it, and reaches
the `DestroyStructures` terminal at frame 2,649. The opponent still has infantry when its MCV dies;
TD starts a 15-frame early-win countdown, blows up the survivor, and marks that house defeated.

The Zig port now implements the required mechanics:

- `MISSION_ATTACK` approaches a live target and refreshes navigation;
- guard missions discard live targets that leave weapon range;
- moving infantry do not dive prone under TD's defender-advantage rule;
- explicit queued attack targets survive the local command-commencement delay;
- no-structure early win uses the same 15-frame delayed defeat path;
- attack movement, combat, MCV destruction, terminal frame, and outcome match the focused oracle.

Vanilla consumes one extra idle-animation RNG draw during the irreversible shutdown window. The
test keeps RNG and command-visible state parity strict before early win begins, then checks the exact
terminal frame and outcome. Zig's own canonical digest includes the pending-defeat timer, so repeated
Zig runs remain fully deterministic.

The Puffer-facing regression uses `policy.RawAction`, generated head masks, `Batch.step`, and the
normal auto-reset path. It verifies that attack, actor 1, visible enemy, and target slot 0 are masked
legal and that this action eventually emits terminal reward `+1.0`. This proves the win path is open
through the same API used for training, without a scripted policy controller.

## Reward V3

Terminal reward remains authoritative:

| Event | Reward | Bound |
| --- | ---: | ---: |
| Win / loss / timeout | `+1.0` / `-1.0` / `0.0` | terminal decision |
| First CY, Power, Barracks, E1, E3 | `+0.1` each | once each |
| Player E1/E3 released | `+0.01` | first 10 |
| Opponent E1/E3/MCV lost | `+0.1` | first 10 |
| Opponent supported building lost | `+0.5` | first 3 |
| Player E1/E3/MCV lost | `-0.001` | once per object |

There is no turn, no-op, pre-deployment, or invalid-action penalty. A terminal result replaces all
shaping on that decision, preserving exact `+1/-1/0` terminal rewards. Bounds prevent indefinite
unit production or combat farming from dominating the actual match result.

The old 128-invalid-tuple death is also disabled. The 100M diagnostic produced 37,180,505 rejected
tuples and 250,845 invalid-streak losses, so that rule classified independent-head incompatibility as
defeat in most losing episodes. Invalid tuples now remain logged no-ops that advance four TD frames.

## TDD Status

```text
Debug:      85/85 tests passed
ReleaseSafe: 85/85 tests passed
ReleaseFast: 85/85 tests passed
Vanilla CTest: 14/14 passed
Puffer C reward/log smoke: passed
```

Focused tests cover Vanilla attack/chase parity, early-win timing, ordinary masked policy victory,
bounded production reward, enemy unit/building reward, player casualty penalty, invalid-tuple
behavior, and stable canonical digest state.

Determinism gates:

| Gate | Hash / result |
| --- | --- |
| Full Zig attack-win canonical trace | `7f120a77dfb06b804d30cfb48f04745a3fb565731e886408de8a2bb4ddfab1ba` |
| C ABI smoke, run 1 | `721b67018cbc2096602e52c74b6312443cb3b82fc8b2bb8b24e3721b0448eb52` |
| C ABI smoke, run 2 | same |

The earlier C ABI smoke digest was
`a2ed292eae3a17e9fb925a60c775b1b7c9d0e1473ca53616c4365e206d663ad2`.
The new digest intentionally differs because canonical `World` now includes the source-faithful
pending-defeat flag and countdown. ABI 4, observation size 6,208, action mask size 275, and the
policy checkpoint shape are unchanged.

## GPU Diagnostics

Both runs used the normal PufferLib CUDA trainer and the same performance-sensitive settings:

```bash
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 4 \
  --vec.num-threads 4 \
  --train.total-timesteps 1048576 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 100000000 \
  --eval-episodes 1
```

| Field | 1M run | 262K preservation run |
| --- | ---: | ---: |
| Run id | `1784078879276` | `1784078963094` |
| Timesteps | 1,048,576 | 262,144 |
| Final dashboard SPS | 101,509 | 73,969 |
| `start_failures` | 0.000 | 0.000 |
| Engine `failures` | 0.000 | 0.000 |
| Valid | yes | yes |

The shorter run changed only total timesteps. Its lower SPS is a short-run/machine-load observation,
not an environment regression claim. The 1M run is the throughput result for this contract.

The 1M rolling metric near 244K steps showed the policy population building both infantry types,
receiving player kill credits, and destroying opponent buildings. By one million steps the policy
had collapsed to a simpler opening. Its final checkpoint is deterministic but poor:

```text
checkpoint c9eec05ed50f81ce70979b8caafc78b7df96fbd718cfa790712470f2e03d924e
episode    deploy once, then 2,466 no-ops, legitimate loss at decision 2,467
trace      0c08c1b01ebdd72bd33dbb3307878d04f59094cadb7cc05b962a2681f14edb25 (twice)
```

The preserved 262K checkpoint demonstrates the economy chain but not combat:

```text
checkpoint 0339f75e42265cf7ebba1c8d5501a7476400ae73d44c89d3a85e98caffc7ea7b
episode    CY -> Power -> Barracks -> E1; timeout draw; return 0.41
commands   attack=0; invalid=2,157; most invalids are move with actor=none
trace      87dd259225e679247f651edb41c53d35c5d56797e58d110c9939ead82fd801a5 (twice)
```

The simulator win path is open, but independent MultiDiscrete heads remain the next policy-learning
bottleneck. Each head can select a masked value that is individually legal yet incompatible with
the selected command. A command-conditioned/autoregressive decoder or canonicalization layer should
be evaluated before another 100M run; adding another large invalid penalty would recreate the old
noop attractor.

Raw logs:

- `PufferLib/logs/cnc_micro/1784078879276.json`
- `PufferLib/logs/cnc_micro/1784078963094.json`

The later controlled 100M run with `+0.1` unit and `+0.5` building rewards is recorded in
`docs/td_micro/100m_combat_reward_scale_run.md`. It produced no wins and did not improve the retained
checkpoint result over the preceding lower-reward run.
