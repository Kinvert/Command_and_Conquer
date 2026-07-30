#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root/PufferLib"

venv_nvidia=$PWD/.venv/lib/python3.12/site-packages/nvidia
extra_libs=/usr/lib/wsl/lib:$venv_nvidia/cu13/lib:$venv_nvidia/nccl/lib:$venv_nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
log=logs/cnc_micro/cnc22_random_credit_5mi_sweep_1000.console.log

export PYTHONUNBUFFERED=1
export OMP_NUM_THREADS=4
export LD_LIBRARY_PATH=$extra_libs

exec >"$log" 2>&1
exec .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb \
  --wandb-project cnc22 \
  --tag random-credit-5mi-10mi-schedule-sweep-1000 \
  --sweep.max-runs 1000 \
  --sweep.gpus 1 \
  --sweep.workers-per-gpu 3 \
  --train.gpus 1 \
  --train.total-timesteps 5242880 \
  --train.schedule-timesteps 10485760 \
  --vec.total-agents 64 \
  --vec.num-buffers 1 \
  --vec.num-threads 4 \
  --train.horizon 32 \
  --train.minibatch-size 2048
