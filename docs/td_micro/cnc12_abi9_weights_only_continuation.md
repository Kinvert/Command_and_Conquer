# CNC12 ABI9 Weights-Only Continuation

Date: 2026-07-20

Status: complete; weights-only continuation did not preserve the 1M policy

Source checkpoint: `PufferLib/checkpoints/cnc_micro/v9q3vd6v/0000000001048576.bin`

Source checkpoint SHA-256: `6f2a84749bbf0eb71548e092db3e3af9c2ee489e8a3190ce005adab4541620be`

## Purpose

Test whether the verified CNC10 1M leader can improve by continuing from its policy weights for one
additional million transitions at a fixed low learning rate. This isolates schedule behavior from a
fresh 2M cosine restart.

The experiment deliberately uses Puffer's existing `.bin` policy checkpoint format. That format
stores policy weights only. Puffer constructs a new optimizer and new training/RNG state, so this is
weights-only continuation with optimizer reinitialization, not a true optimizer-state resume.

## Matrix

The source environment, rewards, ABI9 action transport, vector shape, and PPO values were pinned to
candidate `5lk552uq` from `tools/cnc11_abi9_candidates.json`. Every run used:

- 64 agents, one buffer, four threads, horizon 32, minibatch 2,048;
- one GPU with the native PufferLib backend;
- source policy weights loaded through `--load-model-path`;
- one additional 1,048,576 transitions;
- `anneal_lr=0`; and
- fixed learning rates `0.00006`, `0.00012`, and `0.00024` across seeds 73, 74, and 75.

The runner is `tools/cnc12_abi9_continuation.py`. It validates the source path separately from the
output checkpoint path, requires exact steps, and rejects nonzero `start_failures` or `failures`.

## Training Results

All nine runs completed exactly 1,048,576 continuation transitions with zero start and engine
failures.

| LR | Seed | W&B run | Built-in balanced | Final SPS | Checkpoint SHA-256 |
| ---: | ---: | --- | ---: | ---: | --- |
| 0.00006 | 73 | `vz4upu66` | 0.000000 | 22,287 | `9858f0d568f86f7b85322d4f8b410767d8fc3ac5b91be60a4113aaae51ec2857` |
| 0.00006 | 74 | `1dnm2f4t` | 0.000000 | 17,145 | `497bd2f8b4dc52ad820c521b7c19362908ceb88e8c5ba59b8d50b427d2c4fdac` |
| 0.00006 | 75 | `savnr0og` | 0.000000 | 18,093 | `6d526f07670be38adb23b73b7dd9f34ead9bfcbfdd67a26176c2225ea8004c44` |
| 0.00012 | 73 | `t0ob0ctf` | 0.000000 | 15,944 | `4ce99e4d0a7695cc764d10fc33b4eb0073ed3b5ff249a8fccc6be4d5d6e1d918` |
| 0.00012 | 74 | `7nm8il2i` | 0.000000 | 10,390 | `974bc36002f12a496618b18389e7be7564d4a2d920fc5d9b9dde5fb6f1e8724b` |
| 0.00012 | 75 | `ebmz5b4n` | 0.018236 | 17,980 | `e5ae4cb729fab7f1b8b5d7acf39e0439424f7e50b60423eb1f83813f1dd9d980` |
| 0.00024 | 73 | `kfycstv6` | 0.000000 | 10,515 | `eb1180fa012b9ca42bc0633146e7141c7347da3947a6fadc4a273fa8b90b90e7` |
| 0.00024 | 74 | `cv3sk7r3` | 0.000000 | 10,068 | `1f26f24a4f12cb154641a0b9c90d3a0820010a99fe913c72ddeb64e739e1dea2` |
| 0.00024 | 75 | `edh7y64b` | 0.029812 | 18,494 | `4d48e408f6392320a238cc307d0e1e6bf0d16883701567e7c9de19e26d9ff8de` |

Training SPS ranged from 10,068 to 22,287, with median 17,145. These were three concurrent
workers on one GPU and are not a speed comparison.

## Common Evaluation

Each final checkpoint was evaluated with native CUDA inference, no optimizer updates, policy seed
173, and 512 fresh completed episodes.

| LR | Seed | Balanced | Close | Medium | Perf | Invalid actions | Units built | Unit kills | SPS |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0.00006 | 73 | 0.000000 | 0.000000 | 0.000000 | 2,348.150 | 14.822 | 4.361 | 43,363 |
| 0.00006 | 74 | 0.002273 | 0.004545 | 0.000000 | 2,434.023 | 16.889 | 4.998 | 40,450 |
| 0.00006 | 75 | 0.002222 | 0.004444 | 0.000000 | 2,631.094 | 19.539 | 6.619 | 39,804 |
| 0.00012 | 73 | 0.001852 | 0.000000 | 0.003704 | 2,627.682 | 22.492 | 6.645 | 36,770 |
| 0.00012 | 74 | 0.000000 | 0.000000 | 0.000000 | 2,645.740 | 23.314 | 5.592 | 35,696 |
| 0.00012 | 75 | 0.017375 | 0.000000 | 0.034749 | 3,236.812 | 29.773 | 9.877 | 36,880 |
| 0.00024 | 73 | 0.003912 | 0.003759 | 0.004065 | 3,060.760 | 26.650 | 9.068 | 36,240 |
| 0.00024 | 74 | 0.000000 | 0.000000 | 0.000000 | 2,390.451 | 27.236 | 4.982 | 30,989 |
| 0.00024 | 75 | 0.027437 | 0.015504 | 0.039370 | 3,474.760 | 38.201 | 13.816 | 33,245 |

The best rate was `0.00024`, with mean balanced performance `0.010450` and median `0.003912`.
Its worst seed was still zero. The source 1M checkpoint measured `0.298395` balanced performance
on the same common evaluation protocol. No continuation rate preserved the source quality.

The evaluation covered 4,608 completed episodes; all nine evaluations had zero start and engine
failures. The machine-readable report is
`PufferLib/logs/cnc_micro/cnc12_continuation_eval_seed173.json`.

## Conclusion

Fixed low learning rates alone do not solve the collapse. Because the continuation reinitialized
Muon optimizer state and training RNG state, it is not a faithful extension of the source
optimization trajectory. The result does not show that the 1M policy cannot improve; it shows that
policy-only `.bin` checkpoints are insufficient for a controlled continuation experiment.

No simulator, action, observation, reward, map, opponent, or default INI behavior changed.

## Next Task

Add an opt-in full training-state checkpoint format that preserves policy weights, optimizer state,
epoch/global step, and all relevant RNG state without changing the existing inference-compatible
`.bin` format. Train one verified 1M source run with that state, resume for one additional million
transitions at a fixed low LR, and compare exact replay plus common-seed evaluation before expanding
the matrix.

## Validation

```text
continuation contract tests: 4/4 passed
training runs: 9/9 exact steps, start_failures=0, failures=0
evaluation: 9 x 512 episodes, start_failures=0, failures=0
```
