# ABI9 Versus ABI10 Learning Assessment

Date: 2026-07-19

Status: corrected post-sweep assessment; ABI11 and ABI13 follow-ups completed

## Conclusion

The concern about CNC7 is valid. ABI10 fixes the action-validity defect, but the current dense
conditional decoder is materially less sample-efficient and less robust than ABI9 under the same
training configuration. The best CNC7 trial proves that ABI10 can learn; it does not prove that the
current implementation is a healthy replacement.

Do not return to ABI9's independent action heads: its strongest reproducible policy had 44.943% of
decisions rejected. Preserve ABI10's command grammar, exact masks, canonical PAD values, and
one-command-per-transition semantics, but replace the 15,027-output decoder with a compact shared
conditional decoder before spending heavily on another broad sweep.

## Matched Comparison

Run `qj7bux1j` is the strongest controlled baseline. The current ABI10 defaults reproduce its
environment, rewards, vector shape, network, PPO settings, and seeds exactly. A structured config
comparison found no differences in `env`, `policy`, `torch`, `train`, or `vec`, excluding only the
intended total-timestep and checkpoint-interval differences.

| Run | Action implementation | Steps | Balanced perf | Entropy | Invalid actions |
| --- | --- | ---: | ---: | ---: | ---: |
| `qj7bux1j` | ABI9 independent heads | 805,795 | 0.251082 | 12.668 | high |
| `qj7bux1j` | ABI9 independent heads | 1,328,947 | 0.451667 | 12.517 | high |
| `qj7bux1j` | ABI9 independent heads | 2,097,152 | 0.421753 | 13.118 | 1,986.594/episode |
| `klp6t1x1` | ABI10 conditional decoder | 928,817 | 0.125000 | 1.348 | 0 |
| `klp6t1x1` | ABI10 conditional decoder | 1,048,576 | 0.101742 | 1.229 | 0 |
| `9fgpabc5` | ABI10 exact duplicate | 1,048,576 | 0.101742 | 1.252 | 0 |
| `ieuq9hu7` | ABI10 2M repeat | 2,097,152 | 0.000000 | 0.272 | 0 |
| `1784438085172` | ABI10 2M repeat | 2,097,152 | 0.000000 | 0.272 | 0 |

The ABI9 run was already at 0.251 balanced performance before 0.81M steps. ABI10 reaches only
0.102 at 1M with those exact settings, then both deterministic 2M repeats collapse to zero. This is
a real action-implementation regression, not a reward, map, observation, seed, or PPO-setting
confound.

Raw entropy values are not directly comparable across ABIs because ABI9 sums seven independent
categoricals while ABI10 sums only active conditional branches. The trend within ABI10 is still
decisive: its default falls from roughly 3.1 to 1.2 by 1M and to 0.27 by 2M while performance
vanishes.

## Sweep Population

Focusing only on CNC7's best trial hid the robustness problem.

| Sweep | Trials x steps | Maximum | Mean | Median | Nonzero trials |
| --- | ---: | ---: | ---: | ---: | ---: |
| CNC4, earlier action ABI | 100 x 1M | 0.295712 | 0.088007 | 0.063461 | 80/100 |
| CNC7, ABI10 | 100 x 1M | 0.396091 | 0.027947 | 0.000000 | 32/100 |

CNC7 produced the higher single maximum, but only 4/100 trials reached 0.2 and only 2/100 reached
0.3. Its typical run is much worse. CNC4 searched only three reward dimensions around established
optimizer settings, while CNC7 searched 28 dimensions, so this table is not a pure ABI A/B. The
matched `qj7bux1j` comparison above removes that ambiguity and reaches the same conclusion.

Historical CNC1 near-perfect 1M results are not a valid comparator because the old opponent timing
often left its base effectively undefended. CNC6 used ten times as many trials and twice the budget.

## What The Winners Show

The two good CNC7 policies avoid the default's monotonic entropy collapse:

| Run | Balanced perf | Entropy curve | Important differences from the matched default |
| --- | ---: | --- | --- |
| `6y3jrp5w` | 0.396091 | 3.656, 1.555, 1.212, 2.203, 2.486 | 2.09x LR, 2.67x entropy coefficient, `vf_coef=0.1`, 2 buffers |
| `0gor2tys` | 0.331015 | 7.088, 5.313, 4.727, 4.474, 4.249 | 1.37x LR, 2.12x entropy coefficient, `vf_coef=0.1`, 2 buffers, hidden 32 |

`6y3jrp5w` learned late: its balanced curve was `0, 0, 0, 0.231019, 0.396091`. These runs show
that the grammar is learnable and that old entropy/value-loss settings no longer transfer. They do
not resolve the low hit rate, sparse gradient sharing, or decoder throughput cost.

## Structural Diagnosis

ABI10's first correctness implementation projects each state into 15,027 policy components. Later
arguments select prefix-specific dense rows, so many rows receive gradients only when their exact
command and prefix are sampled. This is substantially larger and more sparsely trained than ABI9's
279-logit projection.

Exact legality does not require every prefix to own a separate dense state projection. For example,
placement can use shared command-conditioned y scores and then apply the exact `y | x` mask. Actor
and target dependencies can use low-rank prefix embeddings or entity-pointer scores instead of a
full row per prefix. That preserves the semantic action contract while improving parameter sharing,
sample efficiency, and the measured 30.9K-SPS training path.

## Next Controlled Experiment

1. Reproduce `6y3jrp5w` and `0gor2tys` at 2M before treating either as a promoted policy. Record
   whether entropy and balanced performance survive past their late 1M rise.
2. Implement a compact command-conditioned decoder while leaving the four-byte environment action,
   exact prefix masks, simulation, observations, rewards, and terminal rules unchanged.
3. Require CPU/CUDA probability, sampling, log-probability, entropy, and gradient parity tests;
   randomized legal-action acceptance; deterministic semantic traces; and exact world hashes.
4. Benchmark the old and compact decoders adjacently with fixed hardware and identical PufferLib
   settings. Report SPS, all failure counters, and checkpoint/world hashes.
5. Run the matched `qj7bux1j` configuration and the two CNC7 winner configurations at 1M and 2M.
   Judge the candidate by population hit rate and collapse resistance, not only best-of-N score.

Do not launch another large broad sweep on the current 15,027-output decoder before these gates.

## ABI11 Follow-Up

The first controlled compact candidate completed these gates on 2026-07-19. ABI11 keeps the exact
ABI10 environment action and mask contract but reduces policy outputs from 15,027 to 2,352 and
hidden-64x1 parameters from 1,131,264 to 320,064.

| Run | Decoder | Steps | Balanced perf | Entropy | Invalid/start/engine failures |
| --- | --- | ---: | ---: | ---: | --- |
| `klp6t1x1` | ABI10 dense | 1,048,576 | 0.101742 | 1.229 | 0 / 0 / 0 |
| `ak4m495m` | ABI11 compact | 1,048,576 | 0.174665 | 3.155 | 0 / 0 / 0 |
| `ieuq9hu7` | ABI10 dense | 2,097,152 | 0.000000 | 0.272 | 0 / 0 / 0 |
| `eh4g0roi` | ABI11 compact | 2,097,152 | 0.161406 | 0.419 | 0 / 0 / 0 |
| `qj7bux1j` | ABI9 independent | 2,097,152 | 0.421753 | 13.118 | 44.943% rejected |

ABI11 is a real improvement over ABI10 and does not repeat its zero-performance 2M collapse. It
still falls well short of ABI9, so merely sharing logits by command is not enough. Exact masks
retain legal actor-target support, but ABI11 has no explicit selected-actor contribution to target
preferences. The next experiment should add a compact actor-target interaction before a broad
sweep.

Full commands, curves, SPS validity, deterministic hashes, and W&B links are in
`abi11_compact_decoder_experiment.md`.

## ABI13 Follow-Up

ABI13 added the requested bounded rank-4 actor-target interaction and explicit CPU/CUDA numerical
gradient tests. Exact 1M repeats improved to 0.383830, but the matched 2M run reached only 0.092308.
The subsequent 30-run screen had sampled median 0, mean 0.024241, and maximum 0.203216. This does
not justify retiring ABI9. The next controlled gate is the isolated invalid-as-noop penalty study
in `TODO.md` `TASK-3B`; full evidence is in `abi13_actor_target_experiment.md`.

## Evidence

- `PufferLib/logs/cnc_micro/qj7bux1j.json`
- `PufferLib/logs/cnc_micro/klp6t1x1.json`
- `PufferLib/logs/cnc_micro/9fgpabc5.json`
- `PufferLib/logs/cnc_micro/ieuq9hu7.json`
- `PufferLib/logs/cnc_micro/1784438085172.json`
- `PufferLib/logs/cnc_micro/6y3jrp5w.json`
- `PufferLib/logs/cnc_micro/0gor2tys.json`
- `cnc7_abi10_1m_sweep.md`
- `current_action_abi.md`
- `abi11_compact_decoder_experiment.md`
- `abi13_actor_target_experiment.md`
