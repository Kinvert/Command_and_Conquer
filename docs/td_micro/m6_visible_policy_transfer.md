# M6 Visible Policy Transfer

Recorded: 2026-07-14

Status: **complete**. A checkpoint trained through PufferLib's normal GPU path in the reduced Zig
simulator controlled the normally human/player GDI side in a visible, restricted Vanilla TD
GDI-vs-GDI skirmish against the original Easy AI. It ran from match start through the declared
7,200-frame timeout without human commands, controller fallback, schema mismatch, or engine failure.

Winning was not required for M6. The selected policy is strategically poor: it deployed and built
two Power Plants, then no-op'd until timeout. The user visually confirmed that behavior. Native Zig
evaluation produces the same repeated-Power policy pattern, so this is policy quality rather than a
checkpoint-transfer mismatch.

## GPU Training Run

The aligned run used `max_decisions=1800`, which is exactly 7,200 TD frames at four frames per policy
decision.

```bash
cd /home/claude/cnc/.worktrees/td-micro-v1/PufferLib
export VENV_NVIDIA="$PWD/.venv/lib/python3.12/site-packages/nvidia"
export EXTRA_LIBS="/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib"
PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH="$EXTRA_LIBS" \
  .venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --train.gpus 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 4 \
  --vec.num-threads 4 \
  --train.total-timesteps 1048576 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --policy.hidden-size 64 \
  --policy.num-layers 1 \
  --checkpoint-interval 512 \
  --eval-episodes 1
```

| Field | Result |
| --- | --- |
| Training mode | PufferLib GPU, `--train.gpus 1` |
| Agents / buffers / threads | 64 / 4 / 4 |
| Horizon / minibatch | 32 / 2,048 |
| Total timesteps | 1,048,576 |
| Final dashboard SPS | 102,519 |
| Dashboard uptime | 10.279 s |
| `start_failures` | 0.000 |
| Engine `failures` | 0.000 |
| Valid SPS claim | yes |

Selected checkpoint:

```text
PufferLib/checkpoints/cnc_micro/1784062135168/0000000001048576.bin
SHA-256 e67950993827b5f72951943e71b5c62cef15787bbfd52a220830f40bc61c7765
```

## Deterministic Native Evaluation

The selected checkpoint was evaluated twice from seed 1 through the public C API. The complete state
traces were byte-identical:

```text
trace run 1 SHA-256 691691dd5919565db3d2fdaadf1066c0be2292c9dc3ee101a9486524e016f8bb
trace run 2 SHA-256 691691dd5919565db3d2fdaadf1066c0be2292c9dc3ee101a9486524e016f8bb
```

Both runs terminated after 902 decisions with a building-limit loss. Each had reward sum `-0.80`,
two positive milestone rewards, zero invalid actions, and zero engine failures. Command counts were:

```text
noop=869 deploy=1 start_build=16 place=16 train=0 move=0 attack=0 guard=0 stop=0
```

The poor policy therefore predates visible transfer. It is not introduced by Vanilla rendering or
the native inference adapter.

## Visible Vanilla Run

The visible run used normal Vanilla rendering and assets with these effective settings:

```ini
[Video]
Windowed=yes
FrameLimit=0

[TDMicro]
Ruleset=td_micro_v1
PlayerBrain=PufferPolicy
OpponentBrain=OriginalAI
PolicyPath=/home/claude/cnc/.worktrees/td-micro-v1/PufferLib/checkpoints/cnc_micro/1784062135168/0000000001048576.bin
```

`FrameLimit=0` was used only to finish the evidence run quickly. The local human-play user INI was
restored to `FrameLimit=60` afterward.

Telemetry proves the exact checkpoint and ruleset loaded before inference:

```text
TD Micro policy: loaded checkpoint=e67950993827b5f72951943e71b5c62cef15787bbfd52a220830f40bc61c7765 rules=2cfdb59512771054eb4bf7a4b8b5111fc722b4a1ed5f415c7a172c47d75b9818 obs=6208 mask=275
```

Accepted commands that changed real Vanilla state:

| TD frame | Command | Result |
| ---: | --- | --- |
| 88 | Start Power Plant | accepted, state changed |
| 304 | Place Power Plant | accepted, state changed |
| 308 | Start second Power Plant | accepted, state changed |
| 524 | Place second Power Plant | accepted, state changed |

The final lifecycle record is:

```text
terminal reason=timeout frame=7200 decisions=1800 accepted=1800 changed=4 player_defeated=0 opponent_defeated=0 failed=0
```

The transient service then exited on its own with `Result=success`, `ExecMainStatus=0`,
`ActiveState=inactive`, and `SubState=dead`. No `vanillatd` process remained.

The adapter may resolve a completed structure to the first legal Vanilla placement cell. This proves
checkpoint loading, live observation/mask encoding, inference, and real command application; it does
not claim that the model learned exact map-cell placement. No human command was issued after match
start.

## Artifact Hashes

| Artifact | SHA-256 or revision |
| --- | --- |
| Root source-import commit | `fde281808225aa6c9d452f9b7d1d180bf249bb95` |
| Pinned Vanilla upstream commit | `75526cbd4cbb6cca789f94b6f6abe00100ce7777` |
| M6 source bundle | `5f29ef90e3213af46940b875ed3c9b7d095b316ac90627dda3e0d81895b5d8e4` |
| Ruleset manifest | `2cfdb59512771054eb4bf7a4b8b5111fc722b4a1ed5f415c7a172c47d75b9818` |
| Generated Zig rules | `b1834b414cfdf4b83e5cfacc438c2abd6d4b37868375f726809e6b670bea08fd` |
| Generated C rules | `6f5c512e9b1b28038ab4e945e419095dcd898d920a71b49b57b67d0249f0a830` |
| Zig static library | `c14e2e1be7e6949913a6577163971a60218723d0045a0d305f64a57afb01435f` |
| Selected checkpoint | `e67950993827b5f72951943e71b5c62cef15787bbfd52a220830f40bc61c7765` |
| Puffer JSON result | `17178f647dce9c406fbcb4eac602b51a24fc858dc2df8501e0fa2b97e9d1505b` |
| Native deterministic trace | `691691dd5919565db3d2fdaadf1066c0be2292c9dc3ee101a9486524e016f8bb` |
| Visible telemetry/result | `a9ad873ca1c32b5347ec3e161ac290aa1a50ee1c31e9e30d0c261876a4a3538e` |
| Visible state trace | `69ac9cd5f1d18e423223c3a4d52b3fdb28bc4101e4d367a358db3a38446f6fa1` |
| Visible initial state | `688de03a635be56f987c5753c7403f0a6172fe4f377035639fd9c036506e6f2c` |
| Executed Vanilla binary | `5bc8e29829de5de4450b5a6ee0622dedfb910973ea24d9f303b01b82fe603501` |

The deterministic source bundle was created with sorted paths, zero timestamps, numeric owner/group
zero, and the `.zig-cache` test scratch directory excluded. It contains `td-micro` source, tests,
fixtures, rules, generators, and spec; Vanilla root/common/TD/test source; and the PufferLib
`cnc_micro` binding, config, and build entry point.

Raw records:

- `PufferLib/logs/cnc_micro/1784062135168.json`
- `docs/td_micro/benchmarks/td_micro_visible_e6795099.log`
- `Vanilla-Conquer/td_micro_policy_state_live.bin`

## Verification

```text
Zig tests: 73/73 in Debug, ReleaseSafe, and ReleaseFast
C API: abi=4 obs=6208 mask=275 digest=a2ed292eae3a17e9fb925a60c775b1b7c9d0e1473ca53616c4365e206d663ad2
Puffer C reward regression: episode_return=0.100 draw_rate=1
Vanilla CTest: 14/14 passed
VanillaTD build: passed
Visible service: success, exit status 0
```

## M6 Acceptance Audit

| Requirement | Result |
| --- | --- |
| Train a checkpoint through PufferLib GPU in Zig | pass |
| Complete timeout-or-terminal episode in Zig | pass |
| Load the same checkpoint in real Vanilla | pass |
| Visible restricted skirmish against original Easy GDI AI | pass |
| At least one legal model command changes Vanilla state | pass, four changes |
| No human command after match start | pass |
| No crash, fallback, unsupported content, or engine failure | pass |
| Exact source, ruleset, trace, model, and result hashes | pass |

The next work is policy quality: correct the reward-scale problem, learn Barracks/E1/E3 production,
and stop repeated-building behavior without weakening deterministic parity or the completed transfer
gate.
