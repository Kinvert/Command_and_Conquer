# CNC Failure Modes and Recovery
This file is the operational playbook for known failures in this workspace.

## Invalid throughput claims

- Symptom: higher SPS despite poor behavior.
- Check: `start_failures` in Puffer log.
- Rule: any row with `start_failures > 0` is invalid for throughput claims.
- Action: rerun with lower in-process env count or isolate root cause first.

## `dlmopen` / TLS exhaustion

- Symptom: logs mention `dlmopen` failure, `start_failures` rises (often >0.0 at 12+ envs).
- Cause: static TLS pressure from per-env shared-library namespaces.
- Action:
  - keep envs at a clean valid point (typically 10 total agents in current setup),
  - capture and compare both native and Puffer profiles at that valid point,
  - do not quote higher 12+ env numbers until this is resolved.

## Skirmish startup and data availability

- Symptom: immediate startup fail, missing textures/sfx, or instant exit.
- Cause: missing or incorrect `td-data` layout.
- Action:
  - confirm `td-data/` points to extracted original game assets,
  - confirm game binary was built for the selected target (`build-remastertd`).

## Determinism regressions

- Symptom: parity hash drift for the same scripted replay.
- Cause: unsupported behavior path changed, incorrect replay timing, or nondeterministic state read.
- Action:
  - run `tools/td_parity_trace`,
  - diff checkpoint hashes,
  - block merge until hash deltas are resolved and documented.

## Headful/render artifacts

- Symptom: mouse/controls feel inverted or UI-only behavior regresses during training smoke.
- Cause: run defaults using headful-only settings in a headless loop.
- Action:
  - ensure `CNC_LEGACY_RENDER=0` for Puffer training,
  - keep headful smoke/legacy settings explicit in manual-run scripts only.

## Environment variable conflicts

- Symptom: command seems ignored or behavior changes unexpectedly.
- Cause: stale environment inheritance across shells/devices.
- Action:
  - print the effective env block before launch,
  - isolate runs with explicit exports in the same command block.

## Vanilla policy source/header ABI drift

- Symptom: the policy adapter can compile and decode the current four-field ABI13 action, but its
  action-mask encoder still follows the older unpacked ABI9 offsets.
- Cause: a stale policy object previously hid source/header drift during incremental builds. The
  action record and decoder were updated so a clean `TiberianDawn` shared-library build succeeds,
  but this does not establish visible-policy parity.
- Scope: TD Micro Zig training, the C/Puffer binding, and Vanilla curriculum oracle are covered by
  their normal gates. ABI13 headful inference remains unpromoted.
- Action: do not claim ABI13 visible inference until the Vanilla encoder emits the exact packed
  ABI13 mask and a native-versus-Vanilla mask/action trace test passes.
