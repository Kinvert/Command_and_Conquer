# `lqkwukxi` Balanced ABI6 Evaluation

Date: 2026-07-15

Historical status: this was the first checkpoint proven to transfer across both ABI-6 spawn
profiles. It was superseded on 2026-07-16 by the from-scratch balanced champion `lwgwyjl7`, which
retains a perfect 505/0/0 final balanced evaluation and a real Vanilla win. See
`docs/td_micro/lwgwyjl7_balanced_champion.md`.

## Verdict

The existing `cnc1` champion already solves the current ABI6 close/medium curriculum. It does not
need to be replaced or fine-tuned before the curriculum becomes harder.

Checkpoint:

```text
PufferLib/checkpoints/cnc_micro/lqkwukxi/0000000001048576.bin
SHA-256 7c8734032f8a214c1108c8793f2013af2dc223acccdd87da13456fc65ec56a72
```

Across 512 fresh sampled episodes in the current Zig environment, it won 506 and lost 6, for a
balanced aggregate win rate of **98.8281%**. All failures and artificial limit terminals were zero.

## Native Evaluation

Each profile used 256 independent fresh processes and categorical policy seeds 1000 through 1255.
Environment seed 1 selects the original close spawn; environment seed 2 selects the medium spawn.
No optimizer, Puffer trainer, or weight update participated in this evaluation.

Representative command shape:

```bash
seq 1000 1255 | xargs -P16 -I{} sh -c \
  '/tmp/td_micro_policy_c_api_smoke \
    PufferLib/checkpoints/cnc_micro/lqkwukxi/0000000001048576.bin \
    --seed PROFILE_SEED --sample-seed "$1" > "/tmp/lqk-eval/$1.log"' _ {}
```

| Profile | Episodes | Win/loss/draw | Win rate | Mean decisions | Mean invalid actions | Failures |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Close, seed 1 | 256 | 250 / 6 / 0 | **97.6562%** | 1,222.68 | 391.74 | 0 |
| Medium, seed 2 | 256 | 256 / 0 / 0 | **100.0000%** | 1,143.41 | 290.94 | 0 |
| Balanced total | 512 | 506 / 6 / 0 | **98.8281%** | 1,183.05 | 341.34 | 0 |

| Profile | E1 built | E3 built | Unit kills | Unit losses | Enemy buildings lost | Enemy attack orders |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Close mean | 24.02 | 0.67 | 3.20 | 3.11 | 2.97 | 0.53 |
| Medium mean | 24.14 | 0.55 | 3.21 | 1.27 | 3.00 | 0.14 |

The six close losses used sampling seeds `1047`, `1057`, `1146`, `1152`, `1188`, and `1226`.
They were legitimate long matches: each destroyed one or two opponent buildings, then lost to an
active opponent after 4,817 to 7,559 decisions. None was an engine failure, building-limit loss,
infantry-limit loss, invalid-streak terminal, draw, or timeout.

## Determinism

A representative close loss and medium win were each repeated in independent processes. Both the
complete observation/action-mask trace and the human-readable terminal log matched byte-for-byte:

```text
close loss,  environment 1 / sample 1047
d0e31d26619b8af5839eb9fb2b3972d4d0f63054f11223c55898157ec246b006

medium win, environment 2 / sample 1000
f27a894ff8ace668f911f4321013d428c792d157b03aeaa2c891563ef3dec8fe
```

## Real Vanilla Medium Transfer

The normal `VanillaTD` executable was run from an isolated `/tmp` user directory so the human-play
INI remained untouched. The configuration selected seed 2, the checkpoint above, categorical
sampling seed 74, the original GDI AI, and unlimited simulation speed. The process reported:

```text
TD Micro: auto-starting scenario=1 seed=2 spawn=medium GDI policy vs Hard GDI AI
TD Micro policy: loaded checkpoint=7c8734032f8a214c1108c8793f2013af2dc223acccdd87da13456fc65ec56a72
terminal reason=win frame=3687 decisions=922 accepted=862 changed=85
player_defeated=0 opponent_defeated=1 failed=0
```

The state trace contained 922 observations and masks and had SHA-256:

```text
80f72a621845b3f45ef58f04fae220cbb246c0630eec4675449eb6bb0414a1e7
```

The outer 60-second wrapper later returned `124` because Vanilla remained at its menu after the
completed match. The policy terminal had already been emitted and is the evaluation result.

## Decision

Do not run a warm-start sweep on this two-profile curriculum. It would optimize an already-passing
policy and create catastrophic-forgetting risk without a demonstrated learning gap. Keep the exact
checkpoint immutable and promote it as the ABI6 balanced baseline.

The next curriculum should force interaction with the opponent's army. The medium visible win ends
at frame 3,687, still before the canonical stock-AI first-infantry command at frame 3,935. Add a
farther valid spawn profile or initial combat units, then evaluate this checkpoint before deciding
whether warm-start training or a targeted sweep is necessary.
