# TD Micro Restricted Vanilla Human Smoke

Recorded: 2026-07-13

## First Attempt: Invalid

The first launch used `build-td/CONQUER.INI` to discover `DataPath` and `UserPath`, after which
Vanilla reopened `/tmp/td-micro-vanilla-user/conquer.ini`. That effective user file contained only
`PlayIntro=no`, so the `TDMicro` section and `RawInput=no` setting were absent.

Observed consequences:

- skirmish setup showed the normal unit count of 6;
- the match started with extra infantry and tanks;
- the normal building/sidebar catalog remained available; and
- SDL raw relative mouse input made the tactical-view cursor move in the opposite direction.

This run is not TD Micro evidence. It established that an adjacent path-discovery INI is not
necessarily the gameplay settings file.

## Corrected Attempt: Passed

The runtime now uses one isolated effective user INI under `build-td/user/conquer.ini`. The
executable printed the effective configuration before opening the window:

```text
TD Micro: ruleset=td_micro_v1 enabled=yes opponent=OriginalAI
```

The user then confirmed in a real windowed skirmish that:

- mouse movement was correct;
- the opening used the restricted MCV setup rather than random infantry/tanks;
- the only structure progression was Power Plant followed by Barracks; and
- the only trainable infantry were the E1 gunner and E3 rocket soldier.

The stock difficulty slider still appeared at Normal during this run even though match setup
overrode the original-AI house to `DIFF_EASY`. The slider initialization was subsequently changed
to display Easy whenever `td_micro_v1` is active. A second GUI smoke confirmed that the skirmish
screen now defaults to Easy. Both the displayed setting and the computer house assignment therefore
use Easy in TD Micro.

## Automated Guards

- `test_tdmicro` checks config parsing, full supported-object allowlisting, production allowlisting,
  and disabled behavior for an unknown ruleset.
- `HouseClass::Can_Build` applies the production allowlist before the original AI's unconditional
  computer-player return.
- The current rebuilt executable scans active units, buildings, infantry, and aircraft every TD
  frame and prints the first unsupported type. This guard was added after the successful content
  smoke; a complete guarded match is still required before the full M1 gate can pass.
