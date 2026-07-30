# ABI11 Compact Decoder Experiment

Date: 2026-07-19

Status: retain as an intermediate candidate. ABI11 is deterministic, valid, substantially smaller,
and learns better than the ABI10 dense decoder under the matched configuration. It does not yet
recover ABI9 sample efficiency or prove the 50K useful-training target.

## Decision

ABI11 keeps the ABI10 environment contract unchanged and replaces only the policy decoder layout.
This is a successful correction relative to ABI10, but not the final action architecture:

- exact action legality remains intact;
- simulator behavior and world hashes remain exact;
- policy parameters fall from 1,131,264 to 320,064;
- matched 1M balanced performance rises from 0.101742 to 0.174665;
- matched 2M balanced performance rises from 0.000000 to 0.161406; and
- ABI9 still leads at 0.421753 after 2M, despite rejecting 44.943% of its actions.

The next decoder should restore actor-target conditioning with shared entity features or a low-rank
pointer score. Returning to ABI9's independent heads is not acceptable.

## Scope

These remained byte-for-byte or semantically unchanged:

- 2,456-byte observation version 5;
- four-byte action `[command, arg0, arg1, arg2]`;
- 9,242 logical exact-prefix mask bits packed into 1,156 bytes;
- command ids, argument ids, canonical PAD, and one semantic command per transition;
- rewards, terminals, simulation, four-frame decision interval, maps, and opponent AI; and
- normal PufferLib native CUDA training with `--train.gpus 1`.

The intentional checkpoint ABI change is 10 to 11.

## Decoder Layout

ABI10 emitted a separate state-dependent dense row for several selected-prefix values. ABI11 shares
state-dependent scores by command and lets the existing exact prefix masks narrow their legal
support after each sampled token.

| Component | ABI10 logits | ABI11 logits |
| --- | ---: | ---: |
| Command | 12 | 12 |
| Argument 0 | 780 | 780 |
| Argument 1 | 1,560 | 780 |
| Argument 2 | 12,675 | 780 |
| **Policy total** | **15,027** | **2,352** |
| Value | 1 | 1 |

ABI11's three argument blocks each contain `12 * 65` command-conditioned logits. The mask may still
depend on the complete selected prefix. For example, placement `y` legality remains exact for the
chosen `x`; only the unmasked score is shared across `x` values.

| Model property, hidden 64x1 | ABI10 | ABI11 | Change |
| --- | ---: | ---: | ---: |
| Decoder outputs including value | 15,028 | 2,353 | -84.3% |
| Parameters | 1,131,264 | 320,064 | -71.7% |
| Raw checkpoint bytes | 4,525,056 | 1,280,256 | -71.7% |

This first compact layout deliberately gives up an explicit actor-conditioned target score. Exact
actor-target legality is preserved by the mask, but target preference is only state- and
command-conditioned. That is the most likely remaining expressiveness limitation.

## TDD And Correctness Gates

The ABI/layout assertions were changed first. Before implementation, Debug Zig had exactly three
expected failures and the C++ host/device action-spec test failed its ABI and policy-size assertions.
After implementation:

- Zig Debug: 161/161 pass;
- Zig ReleaseSafe: 161/161 pass;
- Zig ReleaseFast: 161/161 pass;
- C++ host/device action spec: `cnc_micro ABI11 compact action spec ok`;
- scripted economy: Refinery 1, Harvester 1, income 675, first delivery 1, invalid 0, failures 0;
- randomized masked-sequence acceptance: pass;
- CPU policy loading and sampling through the C API: pass; and
- all CUDA runs below: `invalid_actions=0`, `start_failures=0`, `failures=0`.

The unchanged native environment benchmark produced:

```text
ABI10 mean: 170,023.403 SPS
ABI11 runs: 170,315.523 and 168,203.570 SPS
ABI11 mean: 169,259.547 SPS (-0.45%, noise-level)
world digest, every run: 38cca1613d27fcaa4500c25261cff6ea19d838ccd80d9c91fec4d045d718ce28
```

Command:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/td-micro
cc -O3 -std=c11 -I include tools/batch_benchmark.c \
  zig-out/lib/libtd_micro.a -lm -lpthread -o /tmp/td_micro_batch_benchmark_abi11
taskset -c 0 /tmp/td_micro_batch_benchmark_abi11 64 16384
```

Two exact 262,144-step ABI11 CUDA repeats produced the same final checkpoint:

```text
268abd8306a02776e42c6399f67305a6667dfb871e75e546de64bf1f0b438ad8
```

The C API state smoke also retained its established digest:

```text
abi=11 obs=2456 mask=1156 worlds=2 decisions=2
digest=cdde069f216661b92e5e030650698b1a7a54641c5e9d1dc068a9b6aa9a2ece4f
```

Current built-artifact hashes for this uncommitted candidate are:

```text
Puffer extension 487392347e56ca03e7063cd50f353071fb9219988164b91e9ee067bd3996e777
Zig static lib   67b1a296a44e30620d9675b490108a65eb5faabfafa019713d85edb5024401de
```

## Adjacent Throughput

The before and both after runs used the same command and same idle machine shape:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 1 \
  --vec.num-threads 4 \
  --train.total-timesteps 262144 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 100000000
```

| Run | Decoder | GPU | Final SPS | Start/engine/invalid failures | Valid |
| --- | --- | ---: | ---: | --- | --- |
| `1784448988548` | ABI10 dense | 1 | 34,071 | 0 / 0 / 0 | yes |
| `1784450089967` | ABI11 compact | 1 | 28,234 | 0 / 0 / 0 | yes |
| `1784450159276` | ABI11 compact | 1 | 32,829 | 0 / 0 / 0 | yes |

Configuration for every row: 64 agents, one buffer, four threads, horizon 32, 262,144 total
timesteps, minibatch 2,048, hidden 64x1, and normal GPU/native training. The final partial reporting
bucket is noisy, and different learned policies create different environment workloads. This
adjacent test therefore does **not** establish a full-loop SPS win.

The longer matched-default comparison was 30,984 SPS for historical ABI10 run `ieuq9hu7` and
32,604 SPS for ABI11 run `eh4g0roi`, about +5.2%. It is directionally useful but was not captured as
an adjacent binary A/B, so it is not a definitive speedup claim.

## Matched Learning

The controlled runs use the complete `qj7bux1j` environment, reward, network, PPO, vector, and seed
configuration. Only action implementation and requested total timesteps differ.

| Run | Decoder | Steps | Balanced perf | Entropy | Final SPS | Failures | Valid |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| `qj7bux1j` | ABI9 independent | 805,795 | 0.251082 | 12.668 | n/a | high invalid | no for exact-action semantics |
| `qj7bux1j` | ABI9 independent | 2,097,152 | 0.421753 | 13.118 | 37,487 | 44.943% rejected | no for exact-action semantics |
| `klp6t1x1` | ABI10 dense | 1,048,576 | 0.101742 | 1.229 | n/a | 0 / 0 / 0 | yes |
| `ieuq9hu7` | ABI10 dense | 2,097,152 | 0.000000 | 0.272 | 30,984 | 0 / 0 / 0 | yes |
| `ak4m495m` | ABI11 compact | 1,048,576 | **0.174665** | 3.155 | 28,531 | 0 / 0 / 0 | yes |
| `eh4g0roi` | ABI11 compact | 2,097,152 | **0.161406** | 0.419 | 32,604 | 0 / 0 / 0 | yes |

ABI11's 1M curve is `0.020833, 0.074306, 0.065972, 0.169643, 0.174665`. Its 2M curve is
`0.006250, 0.053030, 0.050725, 0.116667, 0.161406`. It does not reproduce ABI10's deterministic
collapse to zero, but it remains much weaker than ABI9.

Commands for the ABI11 rows:

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc8 --tag abi11-compact-qj-1m \
  --train.gpus 1 --vec.total-agents 64 --vec.num-buffers 1 --vec.num-threads 4 \
  --train.total-timesteps 1048576 --train.horizon 32 --train.minibatch-size 2048 \
  --policy.hidden-size 64 --policy.num-layers 1 --checkpoint-interval 100000000

# The 2M run changes the tag and total timesteps only.
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --wandb --wandb-project cnc8 --tag abi11-compact-qj-2m \
  --train.gpus 1 --vec.total-agents 64 --vec.num-buffers 1 --vec.num-threads 4 \
  --train.total-timesteps 2097152 --train.horizon 32 --train.minibatch-size 2048 \
  --policy.hidden-size 64 --policy.num-layers 1 --checkpoint-interval 100000000
```

W&B evidence:

- [`cnc8/ak4m495m`](https://wandb.ai/kinvert-k/cnc8/runs/ak4m495m)
- [`cnc8/eh4g0roi`](https://wandb.ai/kinvert-k/cnc8/runs/eh4g0roi)

## High-Throughput Transfer Checks

Two 1M transfers using CNC7 winner-style optimizer settings reached 57,670 and 60,552 valid SPS,
respectively, but both had zero balanced performance. They demonstrate that the compact decoder can
exceed 50K when the learned environment workload remains cheap; they do not meet the useful-training
target. Exact effective configurations and complete metrics are retained in:

- `PufferLib/logs/cnc_micro/bg6ij2bm.json`
- `PufferLib/logs/cnc_micro/ilfr6q4y.json`
- [`cnc8/bg6ij2bm`](https://wandb.ai/kinvert-k/cnc8/runs/bg6ij2bm)
- [`cnc8/ilfr6q4y`](https://wandb.ai/kinvert-k/cnc8/runs/ilfr6q4y)

Both used 64 agents, two buffers, four threads, horizon 32, minibatch 2,048, hidden 64x1, one GPU,
1,048,576 total timesteps, and had zero invalid actions, start failures, and engine failures.

## Next Gate

Post-gate result: implemented as bounded ABI13 and preserved at commit `9789107`. It passes the
CPU/CUDA numerical and determinism gates and reaches 0.383830 reproducibly at 1M, but reaches only
0.092308 at matched 2M. Its 28 sampled screen trials have median 0 and maximum 0.203216. ABI13 is
therefore not promoted; see `abi13_actor_target_experiment.md` and `TODO.md` `TASK-3B`.

Do not launch a large generic sweep merely because the model is smaller. First add one compact
actor-target interaction mechanism and compare it directly against ABI11:

1. gather the selected actor and candidate target entity features;
2. score targets with a shared dot product or low-rank bilinear term;
3. preserve the existing transport, exact masks, PAD behavior, and one-transition command;
4. add CPU/CUDA probability and gradient parity tests before implementation; and
5. repeat the adjacent SPS, exact-hash, and matched 1M/2M learning gates in this document.
