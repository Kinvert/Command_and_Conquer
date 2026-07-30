#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root/PufferLib"

max_runs=${1:-1000}
if [[ ! $max_runs =~ ^[1-9][0-9]*$ ]]; then
  echo "usage: $0 [positive-max-runs]" >&2
  exit 2
fi

venv_nvidia=$PWD/.venv/lib/python3.12/site-packages/nvidia
extra_libs=/usr/lib/wsl/lib:$venv_nvidia/cu13/lib:$venv_nvidia/nccl/lib:$venv_nvidia/cudnn/lib:/usr/local/cuda-12.8/targets/x86_64-linux/lib
log=logs/cnc_micro/cnc23_defended_curriculum_5mi_sweep_"$max_runs".console.log

export PYTHONUNBUFFERED=1
export OMP_NUM_THREADS=4
export LD_LIBRARY_PATH=$extra_libs

exec >"$log" 2>&1
exec .venv/bin/python -m pufferlib.pufferl sweep cnc_micro \
  --wandb \
  --wandb-project cnc23 \
  --tag defended-curriculum-independent-clocks-5mi-10mi-schedule-"$max_runs" \
  --sweep.max-runs "$max_runs" \
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
