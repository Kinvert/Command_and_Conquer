## puffer [train | eval | sweep] [env_name] [optional args] -- See https://puffer.ai for full details
# This is the same as python -m pufferlib.pufferl [train | eval | sweep] [env_name] [optional args]

import warnings
warnings.filterwarnings('error', category=RuntimeWarning)

import os
import sys
import glob
import json
import hashlib
import ast
import time
import argparse
import configparser
from collections import defaultdict
import multiprocessing as mp
from copy import deepcopy

import numpy as np

import torch
import pufferlib
try:
    from pufferlib import _C
except ImportError:
    raise ImportError('Failed to import PufferLib C++ backend. If you have non-default PyTorch, try installing with --no-build-isolation')

from pufferlib import selfplay

import rich
import rich.traceback
from rich.table import Table
from rich_argparse import RichHelpFormatter
rich.traceback.install(show_locals=False)

import signal # Aggressively exit on ctrl+c
signal.signal(signal.SIGINT, lambda sig, frame: os._exit(0))

def unroll_nested_dict(d):
    if not isinstance(d, dict):
        return d

    for k, v in d.items():
        if isinstance(v, dict):
            for k2, v2 in unroll_nested_dict(v):
                yield f"{k}/{k2}", v2
        else:
            yield k, v

def abbreviate(num, b2, c2):
    prefixes = ['', 'K', 'M', 'B', 'T']
    for i, prefix in enumerate(prefixes):
        if num < 1e3: break
        num /= 1e3

    return f'{b2}{num:.1f}{c2}{prefix}'

def duration(seconds, b2, c2):
    if seconds < 0: return f"{b2}0{c2}s"
    if seconds < 1: return f"{b2}{seconds*1000:.0f}{c2}ms"
    seconds = int(seconds)
    d = f'{b2}{seconds // 86400}{c2}d '
    h = f'{b2}{(seconds // 3600) % 24}{c2}h '
    m = f'{b2}{(seconds // 60) % 60}{c2}m '
    s = f'{b2}{seconds % 60}{c2}s'
    return d + h + m + s

def fmt_perf(name, color, delta_ref, elapsed, b2, c2):
    percent = 0 if delta_ref == 0 else int(100*elapsed/delta_ref - 1e-5)
    return f'{color}{name}', duration(elapsed, b2, c2), f'{b2}{percent:2d}{c2}%'

def print_dashboard(args, model_size, flat_logs, clear=False, idx=[0],
        c1='[cyan]', c2='[white]', b1='[bright_cyan]', b2='[bright_white]'):
    g = lambda k, d=0: flat_logs.get(k, d)
    console = rich.console.Console()
    dashboard = Table(box=rich.box.ROUNDED, expand=True,
        show_header=False, border_style='bright_cyan')
    table = Table(box=None, expand=True, show_header=False)
    dashboard.add_row(table)

    table.add_column(justify="left", width=30)
    table.add_column(justify="center", width=12)
    table.add_column(justify="center", width=18)
    table.add_column(justify="right", width=12)

    table.add_row(
        f'{b1}PufferLib {b2}4.0 {idx[0]*" "}:blowfish:',
        f'{c1}GPU: {b2}{g("util/gpu_percent"):.0f}{c2}%',
        f'{c1}VRAM: {b2}{g("util/vram_used_gb"):.1f}{c2}/{b2}{g("util/vram_total_gb"):.0f}{c2}G',
        f'{c1}RAM: {b2}{g("util/cpu_mem_gb"):.1f}{c2}G',
    )
    idx[0] = (idx[0] - 1) % 10

    s = Table(box=None, expand=True)
    remaining = f'{b2}A hair past a freckle{c2}'
    agent_steps = g('agent_steps')
    if g('SPS') != 0:
        remaining = duration((args['train']['total_timesteps']*args['train'].get('gpus', 1) - agent_steps)/g('SPS'), b2, c2)

    s.add_column(f"{c1}Summary", justify='left', vertical='top', width=10)
    s.add_column(f"{c1}Value", justify='right', vertical='top', width=14)
    s.add_row(f'{c2}Env', f'{b2}{args["env_name"]}')
    s.add_row(f'{c2}Params', abbreviate(model_size, b2, c2))
    s.add_row(f'{c2}Steps', abbreviate(agent_steps, b2, c2))
    s.add_row(f'{c2}SPS', abbreviate(g('SPS'), b2, c2))
    s.add_row(f'{c2}Epoch', f'{b2}{g("epoch")}')
    s.add_row(f'{c2}Uptime', duration(g('uptime'), b2, c2))
    s.add_row(f'{c2}Remaining', remaining)

    rollout = g('perf/rollout')
    train = g('perf/train')
    delta = rollout + train
    p = Table(box=None, expand=True, show_header=False)
    p.add_column(f"{c1}Performance", justify="left", width=10)
    p.add_column(f"{c1}Time", justify="right", width=8)
    p.add_column(f"{c1}%", justify="right", width=4)
    p.add_row(*fmt_perf('Evaluate', b1, delta, rollout, b2, c2))
    p.add_row(*fmt_perf('  GPU', b2, delta, g('perf/eval_gpu'), b2, c2))
    p.add_row(*fmt_perf('  Env', b2, delta, g('perf/eval_env'), b2, c2))
    p.add_row(*fmt_perf('Train', b1, delta, train, b2, c2))
    p.add_row(*fmt_perf('  Misc', b2, delta, g('perf/train_misc'), b2, c2))
    p.add_row(*fmt_perf('  Forward', b2, delta, g('perf/train_forward'), b2, c2))

    l = Table(box=None, expand=True)
    l.add_column(f'{c1}Losses', justify="left", width=16)
    l.add_column(f'{c1}Value', justify="right", width=8)
    for k, v in flat_logs.items():
        if k.startswith('loss/'):
            l.add_row(f'{b2}{k[5:]}', f'{b2}{v:.3f}')

    monitor = Table(box=None, expand=True, pad_edge=False)
    monitor.add_row(s, p, l)
    dashboard.add_row(monitor)

    table = Table(box=None, expand=True, pad_edge=False)
    dashboard.add_row(table)
    left = Table(box=None, expand=True)
    right = Table(box=None, expand=True)
    table.add_row(left, right)
    left.add_column(f"{c1}User Stats", justify="left", width=20)
    left.add_column(f"{c1}Value", justify="right", width=10)
    right.add_column(f"{c1}User Stats", justify="left", width=20)
    right.add_column(f"{c1}Value", justify="right", width=10)

    i = 0
    for k, v in flat_logs.items():
        if k.startswith('env/') and k != 'env/n':
            u = left if i % 2 == 0 else right
            u.add_row(f'{b2}{k[4:]}', f'{b2}{v:.3f}')
            i += 1
            if i == 30:
                break

    if clear:
        console.clear()

    with console.capture() as capture:
        console.print(dashboard)

    print('\033[0;0H' + capture.get())

def _resolve_schedule_timesteps(args):
    configured = int(args['train'].get('schedule_timesteps', 0))
    if configured < 0:
        raise ValueError('train.schedule_timesteps must be nonnegative')
    return configured or int(args['train']['total_timesteps'])


def _sha256_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def _training_state_fingerprint(args, backend_path, trainer_path=__file__):
    train = dict(args['train'])
    train.pop('total_timesteps', None)
    train['schedule_timesteps'] = _resolve_schedule_timesteps(args)
    trajectory = {
        'version': 1,
        'env_name': args['env_name'],
        'base': {
            key: args.get(key)
            for key in ('seed', 'reset_state', 'cudagraphs', 'rank', 'world_size')
        },
        'vec': args['vec'],
        'env': args['env'],
        'policy': args['policy'],
        'torch': args['torch'],
        'train': train,
        'selfplay': args.get('selfplay', {}),
        'backend_sha256': _sha256_file(backend_path),
        'trainer_sha256': _sha256_file(trainer_path),
    }
    encoded = json.dumps(
        trajectory,
        sort_keys=True,
        separators=(',', ':'),
        allow_nan=False,
    ).encode('utf-8')
    return hashlib.sha256(encoded).hexdigest()


def _prepare_training_state_contract(args, backend):
    state_requested = bool(args.get('save_training_state') or args.get('load_training_state_path'))
    if state_requested and int(args.get('selfplay', {}).get('enabled', 0)) != 0:
        raise ValueError('Full training-state continuation does not yet support selfplay pools')
    args['train']['schedule_timesteps'] = _resolve_schedule_timesteps(args)
    if not state_requested:
        return
    backend_path = getattr(backend, '__file__', None)
    if not backend_path:
        if args.get('save_training_state') or args.get('load_training_state_path'):
            raise ValueError('Full training-state continuation requires the native backend')
        return
    args['training_state_fingerprint'] = _training_state_fingerprint(args, backend_path)


def _load_training_start(args, backend, pufferl):
    state_path = args.get('load_training_state_path')
    model_path = args.get('load_model_path')
    if state_path and model_path:
        raise ValueError(
            '--load-training-state-path and --load-model-path are mutually exclusive'
        )
    if state_path:
        backend.load_training_state(pufferl, state_path)
        print(f'Resumed native training state: {state_path} at step {pufferl.global_step}')
        if args['train'].get('anneal_lr', 0) == 0 and hasattr(backend, 'set_learning_rate'):
            backend.set_learning_rate(pufferl, args['train']['learning_rate'])
        return 'state'
    if model_path:
        backend.load_weights(pufferl, model_path)
        print(f'Warm-started policy weights: {model_path}')
        return 'weights'
    return None


def validate_config(args):
    minibatch_size = args['train']['minibatch_size']
    horizon = args['train']['horizon']
    total_agents = args['vec']['total_agents']
    epoch_steps = horizon * total_agents
    total_timesteps = int(args['train']['total_timesteps'])
    configured_schedule = int(args['train'].get('schedule_timesteps', 0))
    schedule_timesteps = _resolve_schedule_timesteps(args)
    if args['log_interval'] <= 0:
        raise ValueError('log_interval must be positive')
    assert (minibatch_size % horizon) == 0, \
        f'minibatch_size {minibatch_size} must be divisible by horizon {horizon}'
    assert minibatch_size <= horizon * total_agents, \
        f'minibatch_size {minibatch_size} > total_agents {total_agents} * horizon {horizon}'
    if total_timesteps <= 0:
        raise ValueError('train.total_timesteps must be positive')
    state_requested = bool(args.get('save_training_state') or args.get('load_training_state_path'))
    if state_requested and configured_schedule == 0:
        raise ValueError(
            'Full training-state continuation requires explicit train.schedule_timesteps'
        )
    if configured_schedule != 0 and total_timesteps % epoch_steps != 0:
        raise ValueError(
            f'train.total_timesteps must be positive and divisible by epoch size {epoch_steps}'
        )
    if configured_schedule != 0 \
            and (schedule_timesteps < total_timesteps or schedule_timesteps % epoch_steps != 0):
        raise ValueError(
            'train.schedule_timesteps must cover train.total_timesteps and be divisible '
            f'by epoch size {epoch_steps}'
        )

def _sweep_result_slot(args):
    return int(args.get('sweep_slot_id', args['gpu_id']))

def _sweep_report_result(result_queue, args, scores, costs, timesteps):
    if result_queue is None or int(args.get('rank', 0)) != 0:
        return
    result_queue.put((_sweep_result_slot(args), scores, costs, timesteps))

def _sweep_worker_layout(sweep_gpus, experiment_gpus, workers_per_gpu):
    sweep_gpus = int(sweep_gpus)
    experiment_gpus = int(experiment_gpus)
    workers_per_gpu = int(workers_per_gpu)
    if sweep_gpus <= 0 or experiment_gpus <= 0 or workers_per_gpu <= 0:
        raise ValueError('sweep GPU counts and workers_per_gpu must be positive')
    if sweep_gpus % experiment_gpus != 0:
        raise ValueError(
            f'sweep GPUs {sweep_gpus} must be divisible by experiment GPUs {experiment_gpus}')

    groups = [
        tuple(range(start, start + experiment_gpus))
        for start in range(0, sweep_gpus, experiment_gpus)
    ]
    return groups * workers_per_gpu

def _sweep_optimizer_config(sweep_config):
    optimizer_config = deepcopy(sweep_config)
    method = optimizer_config.pop('method')
    optimizer_config.pop('workers_per_gpu', None)
    return method, optimizer_config

def _sweep_should_collect(active_count, completed, max_runs, worker_capacity):
    return active_count > 0 and (
        active_count >= worker_capacity or completed + active_count >= max_runs)

def _sweep_should_suggest(experiment_index):
    return experiment_index > 0

def _resolve_backend(args):
    compiled_env = getattr(_C, 'env_name', None)
    assert compiled_env is None or compiled_env == args['env_name'], \
        f'build.sh was run for {compiled_env}, not {args["env_name"]}'
    if args.get('slowly'):
        from pufferlib.torch_pufferl import PuffeRL
        return PuffeRL
    return _C

def _train_worker(args):
    backend = _resolve_backend(args)
    _prepare_training_state_contract(args, backend)
    pufferl = backend.create_pufferl(args)
    args.pop('nccl_id', None)
    while pufferl.global_step < args['train']['total_timesteps']:
        backend.rollouts(pufferl)
        backend.train(pufferl)

    backend.close(pufferl)

def _train(env_name, args, sweep_obj=None, result_queue=None, verbose=False):
    '''Single-GPU training worker. Process target for both DDP ranks and sweep trials.'''
    backend = _resolve_backend(args)
    _prepare_training_state_contract(args, backend)
    rank = args['rank']
    run_id = str(int(1000*time.time()))
    if args['wandb']:
        import wandb
        run_id = wandb.util.generate_id()
        wandb.init(id=run_id, config=args,
            project=args['wandb_project'], group=args['wandb_group'],
            tags=[args['tag']] if args['tag'] is not None else [],
            settings=wandb.Settings(console="off"),
        )

    target_key = f'env/{args["sweep"]["metric"]}'
    total_timesteps = args['train']['total_timesteps']
    all_logs = []

    # When sweeping, optionally score each trial by winrate vs a fixed enemy
    # checkpoint (match mode) instead of the training-time self-play metric.
    match_mode = (sweep_obj is not None
        and bool(args.get('sweep', {}).get('match_enemy_model_path')))

    checkpoint_dir = os.path.join(args['checkpoint_dir'], args['env_name'], run_id)
    os.makedirs(checkpoint_dir, exist_ok=True)

    log_dir = os.path.join(args['log_dir'], args['env_name'])
    os.makedirs(log_dir, exist_ok=True)

    try:
        pufferl = backend.create_pufferl(args)
    except RuntimeError as e:
        print(f'WARNING: {e}, skipping')
        _sweep_report_result(result_queue, args, [], [], [])
        return

    _load_training_start(args, backend, pufferl)

    args.pop('nccl_id', None)
    model_size = pufferl.num_params()
    # A loaded state owns its accumulated environment/loss counters. Reading a
    # dashboard log here would clear them before the first resumed rollout.
    if verbose and not args.get('load_training_state_path'):
        flat_logs = dict(unroll_nested_dict(backend.log(pufferl)))
        print_dashboard(args, model_size, flat_logs, clear=True)

    # Selfplay-pool curriculum (no-op unless selfplay.enabled). Disabled
    # under match-mode sweeps since match() owns its own perm/frozen bank.
    pool_state = None
    try:
        pool_state = selfplay.setup(pufferl, backend, args, run_id)
    except RuntimeError as e:
        print(f'WARNING: {e}, skipping')
        backend.close(pufferl)
        _sweep_report_result(result_queue, args, [], [], [])
        return

    model_path = ''
    flat_logs = {}
    total_epochs = int(total_timesteps // (args['vec']['total_agents'] * args['train']['horizon']))
    train_epochs = max(0, total_epochs - int(pufferl.epoch))
    eval_epochs = train_epochs // 2
    for epoch in range(train_epochs + eval_epochs):
        backend.rollouts(pufferl)

        if epoch < train_epochs:
            backend.train(pufferl)

        # In match-sweep mode we need the final checkpoint to feed into match().
        is_final = epoch == train_epochs - 1
        should_save = (sweep_obj is None
            and (epoch % args['checkpoint_interval'] == 0 or is_final)
        ) or (match_mode and is_final)
        state_checkpoint = (should_save and args.get('save_training_state', False)
            and epoch < train_epochs)
        checkpoint_logs = None
        if state_checkpoint:
            # Make reporting accumulators part of a deterministic optimizer
            # boundary. Both an uninterrupted run and a stopped prefix clear
            # them before serializing the state from which training resumes.
            checkpoint_logs = backend.log(pufferl)
        if should_save:
            model_path = os.path.join(checkpoint_dir, f'{pufferl.global_step:016d}.bin')
            backend.save_weights(pufferl, model_path)
            if state_checkpoint:
                backend.save_training_state(pufferl, model_path[:-4] + '.state')

        # Rate limit training telemetry, but always log eval to maintain determinism.
        if checkpoint_logs is None \
                and time.time() < pufferl.last_log_time + args['log_interval'] \
                and epoch < train_epochs - 1:
            continue

        logs = checkpoint_logs
        if logs is None:
            logs = backend.eval_log(pufferl) if epoch >= train_epochs else backend.log(pufferl)
        flat_logs = {**flat_logs, **dict(unroll_nested_dict(logs))}

        if epoch < train_epochs:
            selfplay.step(pufferl, backend, pool_state, flat_logs, epoch)

        if verbose:
            print_dashboard(args, model_size, flat_logs)

        if target_key not in flat_logs:
            continue

        if args['wandb']:
            wandb.log(flat_logs, step=flat_logs['agent_steps'])

        if epoch < train_epochs:
            all_logs.append(flat_logs)

            if (sweep_obj is not None
                    and pufferl.global_step > min(0.20*total_timesteps, 100_000_000) and
                    sweep_obj.early_stop(logs, target_key)):
                break
        elif flat_logs['env/n'] > args['eval_episodes']:
            break


    print_dashboard(args, model_size, flat_logs)
    # Match-mode trials may have early-stopped before the in-loop save fired;
    # ensure we always have a checkpoint to feed match().
    if match_mode and not model_path:
        model_path = os.path.join(checkpoint_dir, f'{pufferl.global_step:016d}.bin')
        backend.save_weights(pufferl, model_path)
    backend.close(pufferl)

    if target_key not in flat_logs:
        _sweep_report_result(result_queue, args, None, None, None)
        return

    # Match-mode scoring: primary = trained policy (model_path); frozen bank =
    # fixed enemy. Score is slot 0's average winrate. Creates its own pufferl
    # so must run after the training instance is closed. Single observation per
    # trial (mid-training curve doesn't predict final match score).
    match_score = None
    if match_mode:
        sweep_cfg = args['sweep']
        match_args = deepcopy(args)
        match_args['enemy_hidden_size'] = int(sweep_cfg['match_enemy_hidden_size'])
        match_args['enemy_num_layers'] = int(sweep_cfg['match_enemy_num_layers'])
        match_logs = match(env_name,
            policy_a_path=model_path,
            policy_b_path=sweep_cfg['match_enemy_model_path'],
            num_games=int(sweep_cfg['match_num_games']),
            args=match_args, verbose=verbose)
        match_score = float(match_logs['env/slot_0_score'])
        if args['wandb']:
            wandb.log({'env/match_score': match_score}, step=flat_logs['agent_steps'])

    # This version has the training perf logs and eval env logs
    all_logs.append(flat_logs)

    # Downsample results
    n = args['sweep']['downsample']
    metrics = {k: [[]] for k in all_logs[0]}
    logged_timesteps = all_logs[-1]['agent_steps']
    next_bin = logged_timesteps / (n - 1) if n > 1 else np.inf
    for log in all_logs:
        for k, v in log.items():
            metrics[k][-1].append(v)

        if log['agent_steps'] < next_bin:
            continue

        next_bin += logged_timesteps / (n - 1)
        for k in metrics:
            metrics[k][-1] = np.mean(metrics[k][-1])
            metrics[k].append([])

    for k in metrics:
        metrics[k][-1] = all_logs[-1][k]

    # Match-mode: single observation at final-training cost. Protein's curve
    # fit collapses to one point — we only trust the match winrate, not any
    # training-time proxy. Replicate the scalar across all downsample bins so
    # the JSON log shape matches every other metric (cache_data.py rejects
    # length-mismatched metrics as "bad data").
    if match_mode:
        metrics['env/match_score'] = [match_score] * len(metrics['agent_steps'])

    # Save own log: config + downsampled results
    log_dir = os.path.join(args['log_dir'], args['env_name'])
    os.makedirs(log_dir, exist_ok=True)
    with open(os.path.join(log_dir, run_id + '.json'), 'w') as f:
        json.dump({**args, 'metrics': metrics}, f)

    if args['wandb']:
        if sweep_obj is None and model_path: # Don't spam uploads during sweeps
            artifact = wandb.Artifact(run_id, type='model')
            artifact.add_file(model_path)
            wandb.run.log_artifact(artifact)

        wandb.run.finish()

    if match_mode:
        # One observation: final hypers -> match winrate, at total training cost.
        _sweep_report_result(result_queue, args, [match_score],
            [metrics['uptime'][-1]], [metrics['agent_steps'][-1]])
    else:
        _sweep_report_result(result_queue, args,
            metrics[target_key], metrics['uptime'], metrics['agent_steps'])

def train(env_name, args=None, gpus=None, **kwargs):
    args = args or load_config(env_name)
    validate_config(args)

    subprocess = gpus is not None
    gpus = list(gpus or range(args['train']['gpus']))
    args['train']['total_timesteps'] //= len(gpus)
    args['world_size'] = len(gpus)
    args['nccl_id'] = _C.get_nccl_id() if len(gpus) > 1 else b''

    if not subprocess:
        gpus = gpus[-1:] + gpus[:-1]  # Main process gets rank 0

    ctx = mp.get_context('spawn')
    for rank, gpu_id in reversed(list(enumerate(gpus))):
        worker_args = deepcopy(args)
        worker_args['rank'] = rank
        worker_args['gpu_id'] = gpu_id
        if rank == 0 and not subprocess:
            _train(env_name, worker_args, verbose=True)
        else:
            # Protein's GP models live on cuda:0 on non-WSL setups; spawn-pickling
            # them works fine via CUDA IPC. On WSL, sweep.py forces device='cpu'
            # at construction so there's nothing to move.
            ctx.Process(target=_train, args=(env_name, worker_args),
                kwargs=kwargs).start()

def sweep(env_name, args=None, pareto=False):
    '''Train entry point. Handles single-GPU, multi-GPU DDP, and sweeps.'''
    args = args or load_config(env_name)
    exp_gpus = args['train']['gpus']
    sweep_gpus = args['sweep']['gpus'] or len(os.listdir('/proc/driver/nvidia/gpus'))
    worker_layout = _sweep_worker_layout(
        sweep_gpus, exp_gpus, args['sweep'].get('workers_per_gpu', 1))
    args['vec']['num_threads'] //= (sweep_gpus // exp_gpus)
    args['no_model_upload'] = True

    method, sweep_config = _sweep_optimizer_config(args['sweep'])
    import pufferlib.sweep
    try:
        sweep_cls = getattr(pufferlib.sweep, method)
    except:
        raise ValueError(f'Invalid sweep method {method}. See pufferlib.sweep')

    sweep_obj = sweep_cls(sweep_config)
    num_experiments = args['sweep']['max_runs']
    ts_default = args['train']['total_timesteps']
    ts_config = sweep_config.get('train', {}).get('total_timesteps', {'min': ts_default, 'max': ts_default})
    
    all_timesteps = np.geomspace(ts_config['min'], ts_config['max'], len(worker_layout))
    result_queue = mp.get_context('spawn').Queue()

    active = {}
    completed = 0
    while completed < num_experiments:
        if _sweep_should_collect(
                len(active), completed, num_experiments, len(worker_layout)):
            slot_id, scores, costs, timesteps = result_queue.get()
            done_args = active.pop(slot_id)

            if not scores:
                sweep_obj.observe(done_args, 0, 0, is_failure=True)
                continue

            completed += 1
            for s, c, t in zip(scores, costs, timesteps):
                done_args['train']['total_timesteps'] = t
                sweep_obj.observe(done_args, s, c, is_failure=False)
            continue

        idx = completed + len(active)
        slot_id = next(i for i in range(len(worker_layout)) if i not in active)
        timestep_total = all_timesteps[slot_id] if pareto else None
        if _sweep_should_suggest(idx):  # First experiment uses defaults
            sweep_obj.suggest(args, fixed_total_timesteps=timestep_total)
            # validate_config requires total_timesteps to be a whole number of epochs, and a swept
            # value is continuous. Snap it here rather than letting the trial be skipped. Not a
            # categorical space: Protein feeds continuous values back through normalize(), and
            # Categorical.normalize demands exact tuple membership, which killed the sweep after
            # its first batch with "np.float64(...) is not in categorical values".
            epoch_steps = args['train']['horizon'] * args['vec']['total_agents']
            requested = int(args['train']['total_timesteps'])
            # Clamp to the configured search range first: the optimiser can propose well outside
            # it, and an unclamped snap produced a 0.71 Mi trial from a 5 Mi floor.
            span = (args.get('sweep', {}).get('train', {}) or {}).get('total_timesteps', {})
            if isinstance(span, dict) and 'min' in span:
                requested = max(int(span['min']), min(int(span['max']), requested))
            snapped = max(epoch_steps, (requested // epoch_steps) * epoch_steps)
            schedule = int(args['train'].get('schedule_timesteps') or 0)
            if schedule:
                snapped = min(snapped, (schedule // epoch_steps) * epoch_steps)
            args['train']['total_timesteps'] = snapped

        try:
            validate_config(args)
        except (AssertionError, ValueError) as e:
            print(f'WARNING: {e}, skipping')
            sweep_obj.observe(args, 0, 0, is_failure=True)
            continue

        exp_args = deepcopy(args)
        exp_args['sweep_slot_id'] = slot_id
        active[slot_id] = exp_args
        train(env_name, exp_args, worker_layout[slot_id],
            sweep_obj=sweep_obj, result_queue=result_queue)

def eval(env_name, args=None, load_path=None):
    '''Evaluate a trained policy. Supports both native and --slowly torch backends.'''
    args = args or load_config(env_name)
    args['reset_state'] = False
    args['train']['horizon'] = 1

    backend = _resolve_backend(args)
    pufferl = backend.create_pufferl(args)

    # Resolve load path
    load_path = load_path or args.get('load_model_path')
    if load_path == 'latest':
        checkpoint_dir = args['checkpoint_dir']
        pattern = os.path.join(checkpoint_dir, args['env_name'], '**', '*.bin')
        candidates = glob.glob(pattern, recursive=True)
        if not candidates:
            raise FileNotFoundError(f'No .bin checkpoints found in {checkpoint_dir}/{args["env_name"]}/')
        load_path = max(candidates, key=os.path.getctime)

    if load_path is not None:
        backend.load_weights(pufferl, load_path)
        print(f'Loaded weights from {load_path}')

    while True:
        backend.render(pufferl, 0)
        backend.rollouts(pufferl)

    backend.close(pufferl)

def match(env_name, policy_a_path, policy_b_path, num_games=4096, args=None, verbose=True):
    '''Head-to-head match between two trained policies in a 2-agent selfplay env.
    Policy A plays slot 0 (e.g. white in chess), policy B plays slot 1 (black).
    Both checkpoints must come from the same env / arch.
    '''
    args = args or load_config(env_name)
    args['reset_state'] = False
    args['train']['horizon'] = 1
    args.setdefault('nccl_id', b'')  # match is always single-GPU
    # Sweep suggestions can give odd agents_per_buffer (e.g. num_buffers=5,
    # total_agents=4096 -> 819). Pin to a stable eval config that guarantees
    # clean slot-0/slot-1 split; ignores trial's vec tuning (eval, not train).
    args['vec']['num_buffers'] = 2
    args['vec']['total_agents'] = 8192
    backend = _resolve_backend(args)
    if backend is not _C:
        raise RuntimeError('match() requires the native CUDA backend')

    def _resolve_latest(path):
        if path != 'latest':
            return path
        pattern = os.path.join(args['checkpoint_dir'], args['env_name'], '**', '*.bin')
        candidates = glob.glob(pattern, recursive=True)
        if not candidates:
            raise FileNotFoundError(f'No .bin checkpoints found in {args["checkpoint_dir"]}/{args["env_name"]}/')
        return max(candidates, key=os.path.getctime)
    policy_a_path = _resolve_latest(policy_a_path)
    policy_b_path = _resolve_latest(policy_b_path)

    total_agents = int(args['vec']['total_agents'])
    num_buffers = int(args['vec']['num_buffers'])
    agents_per_buffer = total_agents // num_buffers
    half = agents_per_buffer // 2
    if 2 * half != agents_per_buffer:
        raise RuntimeError(f'agents_per_buffer ({agents_per_buffer}) must be even for 2-agent selfplay')

    # Primary holds policy A (owns first half of each buffer); one frozen bank
    # holds policy B (owns second half). Bank is created inside create_pufferl
    # before cudagraph capture so the graph bakes in its pointers; weight loads
    # later only update data.
    args['vec']['num_frozen_banks'] = 1
    args['vec']['frozen_bank_pct'] = 0.5
    # CLI flags take precedence; fall back to [sweep].match_enemy_* so the same
    # config drives sweep-time and CLI-time matches. 0 / None means "use primary".
    sweep_cfg = args.get('sweep', {})
    enemy_hidden = args.get('enemy_hidden_size') or sweep_cfg.get('match_enemy_hidden_size')
    enemy_layers = args.get('enemy_num_layers')  or sweep_cfg.get('match_enemy_num_layers')
    if enemy_hidden:
        args['vec']['frozen_bank_hidden_size'] = int(enemy_hidden)
    if enemy_layers:
        args['vec']['frozen_bank_num_layers'] = int(enemy_layers)

    pufferl = backend.create_pufferl(args)

    # Per-buffer perm: each env's slot 0 lands in primary's slice [0, half),
    # slot 1 lands in frozen bank's slice [half, agents_per_buffer). The env
    # side randomizes slot<->color per env, so A and B each play both colors.
    perm = np.empty(total_agents, dtype=np.int32)
    envs_per_buffer = half
    for b in range(num_buffers):
        off = b * agents_per_buffer
        for i in range(envs_per_buffer):
            perm[off + 2*i]     = off + i
            perm[off + 2*i + 1] = off + half + i
    backend.set_agent_perm(pufferl, perm)

    backend.load_weights(pufferl, policy_a_path)
    backend.load_frozen_bank(pufferl, 0, policy_b_path)

    logs = {}
    while True:
        backend.rollouts(pufferl)
        logs = dict(unroll_nested_dict(backend.eval_log(pufferl)))
        n = int(logs.get('env/n', 0))
        if verbose:
            a = logs.get('env/slot_0_score', 0.0)
            b = logs.get('env/slot_1_score', 0.0)
            draws = logs.get('env/draw_rate', 0.0)
            print(f'\rgames={n}/{num_games}  A={a:.3f}  B={b:.3f}  draw={draws:.3f}', end='')
        if n >= num_games:
            break

    if verbose:
        print()

    backend.close(pufferl)
    return logs

def load_config(env_name):
    parser = argparse.ArgumentParser(formatter_class=RichHelpFormatter, add_help=False)
    parser.add_argument('--load-model-path', type=str, default=None,
        help='Path to a pretrained checkpoint')
    parser.add_argument('--load-training-state-path', type=str, default=None,
        help='Resume native policy, optimizer, counters, and RNG state')
    parser.add_argument('--save-training-state', action='store_true',
        help='Save native continuation state alongside policy checkpoints')
    parser.add_argument('--load-enemy-model-path', type=str, default=None,
        help='Path to opponent checkpoint for `puffer match` (slot 1 / black in chess)')
    parser.add_argument('--num-games', type=int, default=4096,
        help='Number of games to play in `puffer match`')
    parser.add_argument('--enemy-hidden-size', type=int, default=None,
        help='hidden_size of the enemy checkpoint (defaults to primary)')
    parser.add_argument('--enemy-num-layers', type=int, default=None,
        help='num_layers of the enemy checkpoint (defaults to primary)')
    parser.add_argument('--load-id', type=str,
        default=None, help='Kickstart/eval from from a finished Wandbrun')
    parser.add_argument('--render-mode', type=str, default='auto',
        choices=['auto', 'human', 'ansi', 'rgb_array', 'raylib', 'None'])
    parser.add_argument('--wandb', action='store_true', help='Use wandb for logging')
    parser.add_argument('--wandb-project', type=str, default='puffer4')
    parser.add_argument('--wandb-group', type=str, default='debug')
    parser.add_argument('--tag', type=str, default=None, help='Tag for experiment')
    parser.add_argument('--slowly', action='store_true', help='Use PyTorch training backend')
    parser.add_argument('--save-frames', type=int, default=0)
    parser.add_argument('--gif-path', type=str, default='eval.gif')
    parser.add_argument('--fps', type=float, default=15)
    parser.description = f':blowfish: PufferLib [bright_cyan]{pufferlib.__version__}[/]' \
        ' demo options. Shows valid args for your env and policy'

    repo_dir = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    puffer_config_dir = os.path.join(repo_dir, 'config/**/*.ini')
    puffer_default_config = os.path.join(repo_dir, 'config/default.ini')
    #CC: Remove the default. Just raise an error on "puffer train" etc with no env (think we already do)
    if env_name == 'default':
        p = configparser.ConfigParser()
        p.read(puffer_default_config)
    else:
        for path in glob.glob(puffer_config_dir, recursive=True):
            p = configparser.ConfigParser()
            p.read([puffer_default_config, path])
            if env_name in p['base']['env_name'].split(): break
        else:
            raise ValueError('No config for env_name {}'.format(env_name))

    for section in p.sections():
        for key in p[section]:
            try:
                value = ast.literal_eval(p[section][key])
            except:
                value = p[section][key]

            #TODO: Can clean up with default sections in 3.13+
            fmt = f'--{key}' if section == 'base' else f'--{section}.{key}'
            dtype = type(value)
            parser.add_argument(
                fmt.replace('_', '-'), default=value,
                type=lambda v, t=dtype: v if v == 'auto' else t(v),
            )

    parser.add_argument('-h', '--help', default=argparse.SUPPRESS,
        action='help', help='Show this help message and exit')

    # Unpack to nested dict
    parsed = vars(parser.parse_args())
    args = defaultdict(dict)
    for key, value in parsed.items():
        nxt = args
        for subkey in key.split('.'):
            prev = nxt
            nxt = nxt.setdefault(subkey, {})

        prev[subkey] = value

    args['env_name'] = env_name
    for section in p.sections():
        args.setdefault(section, {})
    return dict(args)

def main():
    err = 'Usage: puffer [train, eval, sweep, paretosweep, match] [env_name] [optional args]. --help for more info'
    if len(sys.argv) < 3:
        raise ValueError(err)

    mode = sys.argv.pop(1)
    env_name = sys.argv.pop(1)
    args = load_config(env_name)

    if 'train' in mode:
        train(env_name=env_name, args=args)
    elif 'eval' in mode:
        eval(env_name=env_name, args=args)
    elif 'sweep' in mode:
        sweep(env_name=env_name, args=args, pareto='pareto' in mode)
    elif 'match' in mode:
        a_path = args.get('load_model_path')
        b_path = args.get('load_enemy_model_path')
        if not a_path or not b_path:
            raise ValueError('puffer match requires --load-model-path and --load-enemy-model-path')
        match(env_name=env_name, policy_a_path=a_path, policy_b_path=b_path,
            num_games=args.get('num_games', 4096), args=args)
    else:
        raise ValueError(err)

if __name__ == '__main__':
    main()
