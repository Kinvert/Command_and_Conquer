# CNC11 ABI9 Promotion Tournament

Date: 2026-07-19

Status: complete; no 1M CNC10 candidate is promoted to fresh 2M training

Source commit: `75357e8` (`Restore ABI9 and focus TD Micro sweeps`)

## Question

CNC10 found several useful ABI9 policies at 1M transitions. This experiment asks whether those
configurations are reproducible and robust when trained from scratch for 2M transitions, while
holding the environment, action ABI, rewards, optimizer configuration, and vector shape fixed.

The comparison includes:

- CNC10 leader `5lk552uq`;
- CNC10 runner-up `xlidr1ce`;
- CNC10 close/medium-balanced candidate `mnglsikv`; and
- historical 2M ABI9 control `qj7bux1j`.

The exact candidate configurations are versioned in `tools/cnc11_abi9_candidates.json`. The driver
rejects configuration drift and incomplete or nonzero-failure runs before accepting an artifact.
This is a fixed tournament, not a Puffer sweep.

## Fixed Protocol

Every training run used normal PufferLib CUDA training with:

- 64 agents, one buffer, four vector threads;
- horizon 32 and minibatch size 2,048;
- hidden size 64 and one MinGRU layer;
- ABI9 and `reward_invalid_action = 0`;
- one GPU, no `--cpu`, and no `--slowly`; and
- exact candidate-specific environment, reward, and PPO values from the manifest.

The 2M tournament changes only the top-level Puffer seed across `{73, 74, 75}`. Candidate configs
continue to pin every nested `env`, `vec`, `policy`, `torch`, and `train` value. Runs execute three
at a time on one GPU to maximize experiment throughput, so their per-run SPS is workload-dependent
and is not a code-speed comparison.

The fresh evaluator loads each final checkpoint in a new native CUDA runtime, performs no optimizer
updates, uses common policy seed 173, and collects 512 completed episodes per checkpoint. Selection
uses equal-profile balanced performance, not the shorter close profile's raw episode count.

## Commands

From `/home/claude/cnc/.worktrees/td-micro-v1/PufferLib` after activating `.venv`:

```bash
.venv/bin/python ../tools/cnc11_abi9_tournament.py \
  --puffer-root . --project cnc11 run \
  --phase reproduce --workers 3 --execute

.venv/bin/python ../tools/cnc11_abi9_tournament.py \
  --puffer-root . --project cnc11 evaluate \
  --phase pre --episodes 512

.venv/bin/python ../tools/cnc11_abi9_tournament.py \
  --puffer-root . --project cnc11 run \
  --phase tournament --workers 3 --execute

.venv/bin/python ../tools/cnc11_abi9_tournament.py \
  --puffer-root . --project cnc11 evaluate \
  --phase final --episodes 512
```

The driver supplies the established WSL CUDA library path, `OMP_NUM_THREADS=4`, and every pinned
training argument. Omitting `--execute` prints the full commands without starting runs. Completed
zero-failure runs and evaluations are resumable.

## 1M Reproduction Gate

All three CNC10 outcomes reproduced exactly to nine decimal places. The historical source
checkpoints are not retained locally, so this establishes exact reported-result reproduction rather
than source-checkpoint hash identity.

| Candidate | CNC11 run | Balanced | Close | Medium | Episodes | Final SPS | Checkpoint SHA-256 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `5lk552uq` | `v9q3vd6v` | 0.262711883 | 0.101694912 | 0.423728824 | 118 | 24,107 | `6f2a84749bbf0eb71548e092db3e3af9c2ee489e8a3190ce005adab4541620be` |
| `xlidr1ce` | `he4ji3ug` | 0.179054052 | 0.108108111 | 0.250000000 | 81 | 23,192 | `8fbaf3b587335b3e6000f40bc4b7dd340efb3929461e4f08c03c57dfd1b2c43f` |
| `mnglsikv` | `87b9v78y` | 0.173360661 | 0.196721315 | 0.150000006 | 121 | 22,096 | `08bb7f667ac85a41fd55f59a08ce8c1534a586fdb324c4d8de3b9e52d70bba2f` |

The adjacent 1M run SPS range was 22,096 to 24,107, with median 23,192. Every start and engine
failure counter was zero.

## Common Evaluation Before Promotion

The 1M reproductions are real policies rather than favorable final training buckets. On 512 fresh
episodes each, the CNC10 leader improves to 0.298 balanced performance. The historical 2M control
remains substantially stronger.

| Candidate | Steps | Balanced | Close | Medium | Perf | Invalid actions | Units built | Unit kills | SPS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `5lk552uq` | 1,048,576 | 0.298395 | 0.157676 | 0.439114 | 0.306641 | 2,619.789 | 67.463 | 20.627 | 40,940 |
| `xlidr1ce` | 1,048,576 | 0.223199 | 0.188462 | 0.257937 | 0.222656 | 3,874.158 | 68.656 | 27.893 | 40,387 |
| `mnglsikv` | 1,048,576 | 0.166840 | 0.149254 | 0.184426 | 0.166016 | 2,959.109 | 52.516 | 17.135 | 42,436 |
| `qj7bux1j` | 2,097,152 | 0.452784 | 0.236715 | 0.668852 | 0.494141 | 1,795.754 | 73.762 | 22.074 | 44,715 |

This gate covered 2,048 completed episodes and 10,397,696 transitions with zero start or engine
failures.

## Fresh 2M Training Results

| Candidate | Seed | W&B run | Balanced | Close | Medium | Episodes | Final SPS | Checkpoint SHA-256 |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `5lk552uq` | 73 | `5alike7o` | 0.000000 | 0.000000 | 0.000000 | 305 | 13,970 | `50b605a80834fed54dadc6f57b357be8eb4570273dce1f0e95cdaa15b5d38d62` |
| `5lk552uq` | 74 | `y1qf97y2` | 0.000000 | 0.000000 | 0.000000 | 345 | 33,365 | `577ebbe2f893ab62ea7fa56ac0e53bf61c41dd944f0b90fe75aa3d8682dc1182` |
| `5lk552uq` | 75 | `qk7padta` | 0.040777 | 0.061947 | 0.019608 | 215 | 30,919 | `b6897613310c64a6b1f65f3f2fcef9103a492d8b8dc65ba476f89120419c1b5a` |
| `xlidr1ce` | 73 | `rkgfwr6j` | 0.027778 | 0.055556 | 0.000000 | 210 | 26,801 | `0077a1c9cec7f168d96807e69255f0613b601cae2a198a81a5e6541dc771bcee` |
| `xlidr1ce` | 74 | `hplpr9nq` | 0.000000 | 0.000000 | 0.000000 | 179 | 25,314 | `8b274a567bbab04bebfdec44753fa775252ba11c04663cb50c6cf51a37073340` |
| `xlidr1ce` | 75 | `q5vsjroi` | 0.000000 | 0.000000 | 0.000000 | 382 | 40,269 | `d6ad5ba8012d4c5bd52d39b6fefdb7ccfeadf36dafea0e71d5b0d00e73a606d1` |
| `mnglsikv` | 73 | `v4muxudk` | 0.010638 | 0.021277 | 0.000000 | 182 | 19,418 | `9bb953a2575932d7d12a8d0e008c319ee8f0ce5bb2f72a4764f2c4859d28bc21` |
| `mnglsikv` | 74 | `0rwoorsg` | 0.000000 | 0.000000 | 0.000000 | 123 | 26,655 | `e40b9be6c3af3aa2951072b3d161c9755e9018dea86cf8f7f03dad53c669c216` |
| `mnglsikv` | 75 | `4cz7i4s2` | 0.000000 | 0.000000 | 0.000000 | 251 | 26,664 | `80a77abf7f7e7bf7438ec28ecd66f243d058e2cec44e090d9eaca285eacbf788` |
| `qj7bux1j` | 73 | `91trh5h9` | 0.421753 | 0.202128 | 0.641379 | 239 | 17,979 | `490064539416022a02179b47136a74219ed37a618fcfa6173cabc659510c7a37` |
| `qj7bux1j` | 74 | `p3pqle5y` | 0.182921 | 0.205128 | 0.160714 | 229 | 29,616 | `21d112714826b87938de5fbac78ad70813358b5ef03fadc97b68025cbf82555d` |
| `qj7bux1j` | 75 | `4oliwjc5` | 0.000000 | 0.000000 | 0.000000 | 188 | 22,547 | `21cce2317b8c7cf5d34991de055287993b31b1b6c83b11a0143a8bf4e4be6263` |

The tournament consumed 25,165,824 valid training transitions. Final displayed SPS ranged from
13,970 to 40,269 with median 26,659.5. These concurrently measured, behavior-dependent values do
not establish a simulator speed change.

## Fresh 2M Evaluation

| Candidate | Seed | Balanced | Close | Medium | Perf | Invalid actions | Units built | Unit kills | SPS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `5lk552uq` | 73 | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 1,610.520 | 64.680 | 5.938 | 29,152 |
| `5lk552uq` | 74 | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 1,789.826 | 0.027 | 0.043 | 93,474 |
| `5lk552uq` | 75 | 0.039194 | 0.047619 | 0.030769 | 0.039063 | 3,861.623 | 33.020 | 14.748 | 48,722 |
| `xlidr1ce` | 73 | 0.013050 | 0.021898 | 0.004202 | 0.013672 | 1,812.748 | 20.916 | 10.229 | 47,536 |
| `xlidr1ce` | 74 | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 4,517.875 | 22.830 | 18.480 | 52,866 |
| `xlidr1ce` | 75 | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 2,169.797 | 0.000 | 0.000 | 111,549 |
| `mnglsikv` | 73 | 0.012010 | 0.016667 | 0.007353 | 0.011719 | 1,900.852 | 74.516 | 21.982 | 41,188 |
| `mnglsikv` | 74 | 0.001845 | 0.000000 | 0.003690 | 0.001953 | 4,673.939 | 26.213 | 36.541 | 48,851 |
| `mnglsikv` | 75 | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 1,460.477 | 32.580 | 3.820 | 42,982 |
| `qj7bux1j` | 73 | 0.452784 | 0.236715 | 0.668852 | 0.494141 | 1,795.754 | 73.762 | 22.074 | 44,493 |
| `qj7bux1j` | 74 | 0.233987 | 0.226337 | 0.241636 | 0.234375 | 1,783.951 | 51.158 | 20.678 | 48,567 |
| `qj7bux1j` | 75 | 0.000000 | 0.000000 | 0.000000 | 0.000000 | 3,652.100 | 47.717 | 13.900 | 33,308 |

Robustness ranking by median, then worst seed, then mean balanced performance:

| Candidate | Median | Worst | Mean | Seed 73 / 74 / 75 |
| --- | ---: | ---: | ---: | --- |
| `qj7bux1j` | 0.233987 | 0.000000 | 0.228923 | 0.452784 / 0.233987 / 0.000000 |
| `mnglsikv` | 0.001845 | 0.000000 | 0.004618 | 0.012010 / 0.001845 / 0.000000 |
| `5lk552uq` | 0.000000 | 0.000000 | 0.013065 | 0.000000 / 0.000000 / 0.039194 |
| `xlidr1ce` | 0.000000 | 0.000000 | 0.004350 | 0.013050 / 0.000000 / 0.000000 |

The final gate covered 6,144 completed episodes and 30,576,640 transitions. Evaluator SPS ranged
from 29,152 to 111,549 with median 48,052. Every run had `start_failures = 0` and `failures = 0`.

## Determinism And Interpretation

The seed-73 `qj7bux1j` restart exactly reproduces the historical 2M checkpoint SHA-256
`490064539416022a02179b47136a74219ed37a618fcfa6173cabc659510c7a37`. Its 512-episode evaluation
also exactly matches the retained control checkpoint on every non-timing metric. The tournament
changes no simulator code, so there is no new world-state determinism surface. The three CNC10 1M
runs reproduce every expected final outcome metric exactly; historical checkpoint files are absent,
so stronger hash identity cannot be claimed for those three.

The main result is schedule sensitivity. Puffer computes `total_epochs` from
`total_timesteps / (agents * horizon)` and applies cosine learning-rate annealing using
`epoch / total_epochs`. Therefore, changing a configuration from 1M to 2M changes every
intermediate learning rate. A fresh 2M run is not a continuation or prefix extension of its 1M
counterpart. All three useful 1M configurations collapse under that changed schedule.

## Decision

Do not run another broad action or reward sweep yet. Retain ABI9, zero invalid-action penalty, and
the existing environment. The next isolated experiment should start from the verified 1M
`5lk552uq` checkpoint and continue training with a fixed low learning rate rather than restarting a
2M cosine schedule. Compare a small grid such as `{0.05, 0.10, 0.20} * 0.0012` across at least
three continuation seeds, preserving the 1M weights and optimizer-loading semantics explicitly.

Promotion still requires a nonzero worst seed and a materially stronger common-seed median than
the current `qj7bux1j` control. Do not alter action ABI, observations, rewards, maps, or opponent
timing in that experiment.

## Validation

```text
python contract tests: 5/5 passed
1M reproduction runs: 3/3 exact expected metrics, zero failures
2M tournament runs: 12/12 complete, zero failures
pre-promotion evaluation: 2,048 episodes, zero failures
final evaluation: 6,144 episodes, zero failures
```

Raw generated logs and checkpoints remain under ignored `PufferLib/logs/` and
`PufferLib/checkpoints/`. Versioned inputs and orchestration are in `tools/`.
