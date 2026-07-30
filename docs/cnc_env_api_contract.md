# CNC Env API Contract (v1)

This is the short, stable contract for experiments and future engine work.

## Step model

- One `c_step` corresponds to one policy decision.
- The step does:
  - apply command action(s) (cheap),
  - advance fixed in-engine time (or explicit wait action),
  - compute reward / terminal,
  - emit observation and metadata.
- Time waits should not silently absorb hundreds of frames unless explicitly requested.

## Action ABI

Current v1 action space is a flat discrete set in `PufferLib/ocean/cnc_build/binding.c`:

- `0` no-op
- `1` wait_1
- `2` wait_8
- `3` wait_64
- `4` deploy_mcv
- `5` build_power
- `6` build_refinery
- `7` build_barracks
- `8` train_minigunner
- `9` train_rocket
- `10` start_power
- `11` complete_power
- `12` place_power
- `13` start_refinery
- `14` complete_refinery
- `15` place_refinery
- `16` start_barracks
- `17` complete_barracks
- `18` place_barracks
- `19` start_minigunner
- `20` complete_minigunner
- `21` start_rocket
- `22` complete_rocket

Skirmish extension keeps this shape until a masked multi-head schema is introduced.

## Observation ABI (current)

`CNC_OBS_SIZE` remains fixed at 12 in the current fast path.

```
0: mcv_deployed
1: power_present
2: refinery_present
3: barracks_present
4: e1_trained
5: e3_trained
6: harvested_credits / 700
7: episode_progress
8: credits / 12000
9: power_balance / 200
10: last_action_invalid
11: start_command_ok
```

Additional fields may be added only with migration notes in this document.

## Rewards

Current reward fields in this contract:

- `+0.25` successful MCV deploy gate
- `+1.0` successful power plant placement
- `+1.5` successful refinery placement
- `+1.5` successful barracks placement
- `+1.0` successful E1 train
- `+1.0` successful E3 train
- `+2.0` first harvest crossing 700 credits
- `+2.0` terminal economy success
- `-0.01` step cost
- `-0.05` invalid action

## Termination

- Terminal on timeout.
- Terminal success when build chain succeeds and harvested credits objective is met.
- Losing terminal should remain explicit in reward and logs.

## Determinism contract

- For supported fields, replaying a fixed command script must produce identical traces and hashes.
- A new subsystem is accepted only when checkpoint fields match or unsupported fields are explicitly documented.
- Unsupported behavior must fail loudly rather than silently approximate.

## Versioning

- Bump version when any field order/semantics changes.
- Any code touching this contract must update this file and link to the corresponding test/trace update in docs.
