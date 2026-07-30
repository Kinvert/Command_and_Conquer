# TD Micro Combat Metrics And Timeout Fix

Date: 2026-07-14

Status: implemented and verified in the Zig batch API, PufferLib GPU path, and Vanilla timeout
contract. A completed 100M-step W&B run exposed production, combat, loss, building-loss, and
enemy-attack metrics through the normal logger.

> **Metric-schema update (2026-07-15):** The underlying batch counters described here remain, but
> the constrained Puffer/W&B surface was reduced to 26 player-focused fields. See
> `docs/td_micro/puffer_log_schema.md` for current names and semantics.

> **Post-run correction (2026-07-14):** The 12,000-frame extension documented here was necessary
> but insufficient. Replaying all 97 retained checkpoints from run `cmv6t21t` converted 94 draws to
> losses by 30,000 frames and all 97 by 48,000 frames. ABI 5 now implements the measured
> 48,000-frame replacement contract. The implementation and GPU verification are in
> `docs/td_micro/abi5_timeout_placement_obsnorm_1m.md`.

## Root Cause

The prior `7,200`-frame (`1,800`-decision) episode ended before the original Easy TD AI reached the
player. This made a nominal skirmish behave like an economy sandbox at terminal time.

The recorded Vanilla seed-1 oracle is unambiguous:

- at frame `6,620`, original-AI infantry are already on mission 13 (`HUNT`) and moving toward the
  player;
- at frame `7,200`, those infantry are still traveling and the player is undamaged;
- at frame `8,284`, the player MCV has only `93/600` health;
- at frame `8,358`, the original AI destroys the MCV and the player is defeated.

The old timeout cut the episode off 1,158 frames before the deterministic loss. The fix preserves
the original AI behavior and extends the episode contract to `12,000` frames / `3,000` policy
decisions. It does not make the AI attack earlier or replace its decision logic.

## Logged Metrics

Metrics are exact event totals accumulated per world and folded into global totals only when an
episode terminates. They are stored outside canonical `World`, so they do not alter observations,
simulation behavior, policy checkpoint ABI 4, or world digests.

| Puffer/W&B key | Definition |
| --- | --- |
| `gunners_built` | Player E1 releases completed during the episode |
| `rocket_soldiers_built` | Player E3 releases completed during the episode |
| `opponent_gunners_built` | Opponent E1 releases completed during the episode |
| `opponent_rocket_soldiers_built` | Opponent E3 releases completed during the episode |
| `unit_kills` | Kill credits added to player-owned E1/E3 units |
| `opponent_unit_kills` | Kill credits added to opponent-owned E1/E3 units |
| `unit_losses` | Player E1, E3, or MCV deaths |
| `opponent_unit_losses` | Opponent E1, E3, or MCV deaths |
| `buildings_lost` | Player Construction Yard, Power Plant, or Barracks deaths |
| `opponent_buildings_lost` | Opponent Construction Yard, Power Plant, or Barracks deaths |
| `enemy_attack_orders` | Original-Easy-AI clone `HUNT`/`ATTACK` transitions emitted by its command stream |
| `accepted_train_actions` | Player train commands accepted by simulation rules |
| `rejected_train_actions` | Player train commands rejected by simulation rules |

The logger also exports one-shot completion counts for Construction Yard, Power Plant, Barracks, E1,
and E3 milestones. Births and deaths are event-ledger based, so a unit produced and killed within the
same four-frame policy decision cannot disappear through net-count cancellation.

## Deterministic Enemy-Attack Proof

The final all-noop checkpoint from W&B run `bjd42h26` is intentionally poor, but it isolates the
opponent path. Under the corrected timeout it deterministically loses before timeout:

```text
checkpoint  a0767e8d6ab1d7c38200ef94d1ffe4be8db1d85fe0ce884ea1466158b75bcfe4
terminal    loss at decision 2090
failures    0
opponent E1 built       5
opponent E3 built       5
enemy attack orders     4
opponent unit kills     1
player unit losses      1
```

The lost unit is the undeployed player MCV. Two complete observation/action-mask traces were
byte-identical:

```text
14db5afd9149bb54ea4a2a24ad8d742ad30414fe6dfe05557df41265ab6b9093
```

The canonical two-world C smoke digest remains unchanged from the pre-instrumentation baseline:

```text
a2ed292eae3a17e9fb925a60c775b1b7c9d0e1473ca53616c4365e206d663ad2
```

## GPU Smoke

Command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 4 \
  --vec.num-threads 4 \
  --train.total-timesteps 262144 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 100000000 \
  --eval-episodes 1
```

Result:

| Field | Value |
| --- | ---: |
| GPU mode | 1 GPU |
| Agents / buffers / threads | 64 / 4 / 4 |
| Timesteps / horizon / minibatch | 262,144 / 32 / 2,048 |
| Hidden network | 64 x 1 |
| Max episode decisions | 3,000 |
| Aggregate SPS | 100,513 |
| Final dashboard SPS | 98,313 |
| `start_failures` | 0.000 |
| Engine `failures` | 0.000 |
| Valid throughput smoke | yes |

At the final log point, 53 completed episodes averaged:

```text
enemy_attack_orders       4.924528
opponent_unit_kills       0.716981
buildings_lost            0.716981
opponent_gunners_built    4.377358
opponent_rocket_soldiers  5.622642
```

Raw Puffer result: `PufferLib/logs/cnc_micro/1784070157072.json`.

## Corrected Checkpoint Interpretation

The prior claim that the 24,119,296-step checkpoint lost 60 infantry was wrong. Its `+0.34` return
was `+0.40` from four milestones minus six `-0.01` pre-deploy steps. Exact counters show zero unit
losses and zero enemy attack orders before its old timeout.

Under the new contract that checkpoint terminates at decision `1,880` from an invalid-action streak,
still before engagement. The 10,487,808-step builder checkpoint reaches Construction Yard, Power,
Barracks, and one E1, but terminates at decision `2,367` from an invalid-action streak. Existing
checkpoints were trained against the premature timeout and should not be used as evidence of a policy
that both builds and fights.

The historical next run described here used `max_decisions=3000`; subsequent evidence invalidated
that value as a sufficient terminal bound. A run is not evidence of an active opponent unless
`enemy_attack_orders > 0`; combat engagement additionally requires nonzero kill/loss metrics.

The completed diagnostic run is recorded in `docs/td_micro/100m_combat_metrics_run.md`. Across
267,607 episodes it logged 109,933 enemy attack orders, 17,468 opponent kill credits, 3,655 player
unit losses, and 13,811 player building losses. It produced zero wins and zero opponent building
losses. The subsequent reward-v3 work completed the attack/chase and reachable-win simulation gate;
see `docs/td_micro/policy_win_path_and_reward_v3.md`.

## Verification

```text
Zig tests: 79/79 Debug, ReleaseSafe, ReleaseFast
C API: ABI 4; canonical digest unchanged
Puffer C reward/log smoke: passed
Puffer GPU smoke: passed; start_failures=0; failures=0
Vanilla CTest: 14/14 passed
VanillaTD rebuild: passed
```
