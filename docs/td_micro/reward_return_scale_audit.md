# TD Micro Reward-Return Scale Audit

Date: 2026-07-17
Status: finding confirmed; no reward behavior changed

## What The Metrics Mean

- `perf` is the Puffer-side win rate: `1` for a win and `0` for a loss or draw.
- `balanced_perf` is the equal-weight mean of close- and medium-spawn win rates.
- Both are bounded to `[0, 1]`, and `balanced_perf` is the sweep objective.
- `episode_return` is the average completed-episode sum of every shaped reward plus the terminal
  reward. It is not the sweep score and is not currently bounded to `[-1, 1]`.

The Zig terminal path clears shaping earned on the terminal decision itself and emits exactly `+1`
for a win, `-1` for a loss, or `0` for a draw. It does not clear shaping earned on earlier
decisions. The C binding accumulates those emitted rewards until terminal and logs their sum.

## Aggregate Scale

The maximum positive shaping implied by the configured per-episode caps is:

| Channel | Promoted default maximum | Full-sweep maximum |
| --- | ---: | ---: |
| Five generic milestones | 1.000000 | 1.000000 |
| First ten player infantry | 0.303013 | 0.500000 |
| First ten enemy unit losses | 0.054266 | 2.000000 |
| First three enemy buildings | 2.190324 | 3.000000 |
| First Refinery | 0.000000 | 0.600000 |
| First delivery | 0.400000 | 0.400000 |
| First 5,000 harvested credits | 0.699285 | 1.000000 |
| **Positive shaping total** | **4.646888** | **8.500000** |
| Positive shaping plus win terminal | **5.646888** | **9.500000** |

Player-unit loss penalties can reduce return, but do not impose an upper bound. Consequently, a
loss can have positive `episode_return` after enough shaping. This means cumulative shaping can be
more valuable than the `-1` outcome even though the terminal decision itself is correct.

## Trainer Behavior

Both PufferLib training backends clamp each individual decision reward to `[-1, 1]` before advantage
calculation. They do not clamp the cumulative episode return. The environment logger sums the raw
pre-trainer values. Therefore:

1. An episode return above 1 is expected under the current reward definition.
2. If several reward events make one decision exceed 1, the logged return and optimized reward differ.
3. The win-rate sweep score remains bounded and correctly computed, but training can still favor a
   shaping-rich loss over a sparse win.

The discount makes this alignment problem stronger. Episodes commonly last thousands of decisions,
while the promoted `gamma=0.995` has an effective scale of roughly 200 decisions. Shaping arrives
immediately, whereas a terminal loss can be thousands of decisions later and heavily discounted.

## Empirical Confirmation

The full-hyperparameter `cnc5` run `wwqqx9fr` completed a final reporting window with:

- 534 episodes: 42 wins, 486 losses, and 6 draws;
- `episode_return=2.239339`;
- `balanced_perf=0.077217`;
- zero start and engine failures.

That run's reward vector permits at most `4.416349` positive shaping per episode. Even assigning the
maximum possible return to all 42 wins and 6 draws, the remaining aggregate return requires the 486
losing episodes to average at least `+1.937905`. Thus positive-return losses are observed in valid
training data, not merely possible from the coefficient bounds.

Source inspection independently confirms that the sweep target is `env/balanced_perf`, not
`env/episode_return`, so values above 1 do not directly escape into the sweep score.

## Recommendation

Do not treat `episode_return` as game score and do not merely clip its displayed value. Keep
`perf`/`balanced_perf` as the outcome score. Before spending the full 500M transitions on a broad
sweep, define an aggregate positive-shaping budget below the terminal magnitude, enforce it in
configuration validation, and add tests proving that a shaped loss remains worse than a draw and a
win. If a displayed signed outcome is useful, export `win - loss` separately rather than relabeling
or clipping shaped return.
