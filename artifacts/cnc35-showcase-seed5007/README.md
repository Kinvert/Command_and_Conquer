# CNC35 Vanilla showcase win

This is a deterministic visible Vanilla Tiberian Dawn replay of the retained CNC35 ABI13
checkpoint. It is a showcase match, not a 30% win-rate claim.

## Result

```text
terminal reason=win frame=10261 decisions=2566 accepted=1901 changed=24
player_defeated=0 opponent_defeated=1 failed=0 harvested=9800
tanks_built=4 tanks_alive=4 tank_shots=84 full_perf=1
```

The GIF is a 12x time-compressed recording of the complete 181-second visible replay. Its final
frame holds Vanilla's real `EINSATZZIEL ERREICHT` mission-accomplished screen.

## Replay identity

- Checkpoint: `41i0jsrh/0000000005654528.bin`
- Checkpoint SHA-256: `03ce2ce4fdef3dcfa8cc0bfaf5bcf1e5e290117bcd56ae5c87a0dfa9a4d6a867`
- Rules SHA-256: `f9cf1827cb80c3fe29ebddffa11453a4d9bcf42929005fb45573a3bb612b367b`
- Policy: ABI13, hidden size 128, categorical sampling seed 5007
- Scenario/environment seed: 1, close spawn
- Starting force: MCV only
- Player starting credits: 10,000
- Opponent starting credits: 2,300
- Requested opponent difficulty: Hard (`2`), which maps to TD's strongest computer setting
- Capture cadence: `GameSpeed=1`, `FrameLimit=60`

The credit asymmetry is deliberate because the requested deliverable is one full-looking win. The
capture-only camera follows the player base until the first Medium Tank exists, then follows the
first live player tank. It does not modify actions, combat, reward, or terminal state.

## Exact launch environment

```bash
SDL_VIDEODRIVER=x11 \
SDL_AUDIODRIVER=dummy \
ALSOFT_DRIVERS=null \
VANILLA_CONQUER_ARGV0=/tmp/cnc-vanilla-showcase-advantage/work/seed-5007/startup/vanillatd \
TD_MICRO_POLICY_SAMPLE_SEED=5007 \
TD_MICRO_STARTING_CREDITS=10000 \
TD_MICRO_STARTING_UNITS=0 \
TD_MICRO_OPPONENT_STARTING_CREDITS=2300 \
TD_MICRO_SHOWCASE_CAMERA=1 \
/tmp/cnc-vanilla-showcase-advantage/work/seed-5007/startup/vanillatd -XQ
```

## Artifact hashes

```text
c8f437a476775f1ccecf2a83425259d55392449335be9c982905616180d1cc45  cnc35-showcase-win.gif
a83c2a112c97382d4eba0c3b6be2f3f93e239d3b3df50047a6e7669948550ee8  replay-capture.mp4
64cd5fe50adcfe24a6185a608996873115589e8612cd43dd752fa678460c3b73  td_micro_policy.log
```
