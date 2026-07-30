#!/usr/bin/env bash
# ABI14 training with hol84xr2's exact swept hyperparameters.
#
# hol84xr2 is the best ABI14 run in cnc24 (balanced_perf 0.5876). action_scheme=1 selects ABI14;
# hidden_size 128 is load-bearing -- every hidden-64 ABI14 run scored at or below 0.0625.
# total_timesteps 5,242,880 with schedule_timesteps 10,485,760 reproduces the run exactly.
set -euo pipefail
cd "$(dirname "$0")"

export VENV_NVIDIA=$PWD/.venv/lib/python3.12/site-packages/nvidia
export EXTRA_LIBS=/usr/lib/wsl/lib:$VENV_NVIDIA/cu13/lib:$VENV_NVIDIA/nccl/lib:$VENV_NVIDIA/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib

PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4 LD_LIBRARY_PATH=$EXTRA_LIBS \
.venv/bin/python -m pufferlib.pufferl train cnc_micro \
  --env.action-scheme 1 \
  --env.seed 1 \
  --env.max-decisions 12000 \
  --env.curriculum-schedule-id 1 \
  --env.curriculum-stage-decisions 256 \
  --env.starting-force-ramp-decisions 8192 \
  --env.reward-milestone 0.2 \
  --env.reward-player-infantry 0.05 \
  --env.reward-enemy-unit-loss 0.08412947097881353 \
  --env.reward-enemy-building-loss 0.22094468739154355 \
  --env.reward-player-unit-loss -0.006191462576083561 \
  --env.reward-refinery 0.0 \
  --env.reward-first-delivery 0.0 \
  --env.reward-tiberium-income 0.01766468267825115 \
  --env.reward-invalid-action 0.0 \
  --policy.hidden-size 128 \
  --policy.num-layers 1 \
  --policy.expansion-factor 1 \
  --vec.total-agents 64 \
  --vec.num-buffers 1 \
  --vec.num-threads 4 \
  --train.gpus 1 \
  --train.seed 42 \
  --train.total-timesteps 5242880 \
  --train.schedule-timesteps 10485760 \
  --train.horizon 32 \
  --train.minibatch-size 2048 \
  --train.learning-rate 0.0007008334730736885 \
  --train.anneal-lr 1 \
  --train.gamma 0.9977484657997334 \
  --train.gae-lambda 0.9904238708405093 \
  --train.replay-ratio 8 \
  --train.clip-coef 0.01 \
  --train.vf-coef 1.088756768730596 \
  --train.vf-clip-coef 0.8639545679377619 \
  --train.max-grad-norm 1.7547443393247057 \
  --train.ent-coef 0.0012593618309841104 \
  --train.beta1 0.988278853495442 \
  --train.beta2 0.99999 \
  --train.eps 1.578933818857656e-07 \
  --train.prio-alpha 0.4606329832762312 \
  --train.prio-beta0 0.1599983509821492 \
  --train.vtrace-c-clip 2.735915115243374 \
  --train.vtrace-rho-clip 7.324034212094765 \
  --checkpoint-interval 512 \
  --eval-episodes 1000 \
  --wandb --wandb-project cnc25 --wandb-group '' \
  "$@"
