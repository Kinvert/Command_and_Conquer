# Build-order shaping: measured negative result

Date: 2026-07-25
Config: ABI14, `hol84xr2` hyperparameters, 5,242,880 timesteps, hidden 128, `failures = 0` throughout.

## Question

On constrained 2300-credit starts, is opening with a barracks before a refinery a mistake worth
penalising? The intended opening is power plant -> refinery.

## Answer

No. The premise does not survive contact with the baseline, and every penalty tested collapsed the
policy regardless of magnitude.

## Results

| run | violation / constrained / sequence | balanced_perf | gunners_built | build_order_violations |
| --- | --- | ---: | ---: | ---: |
| baseline (shaping absent) | — | **0.588** | 31.348 | 0.974 |
| A | -0.2 / -0.75 / — repeating | 0.053 | 1.942 | 0.050 |
| B | 0.0 / -0.75 / — repeating | 0.051 | 0.960 | 0.047 |
| C | -0.05 / -0.2 / +0.1 once | 0.041 | 5.355 | 0.134 |
| D | -0.05 / -0.2 / 0.0 once | 0.052 | 8.262 | 0.260 |
| control | 0 / 0 / 0 | **0.588** | 31.348 | 0.974 |

The control reproduces the baseline to four decimals (`perf` 0.622, `episode_return` 2.382,
`invalid_actions` 918.346), which establishes that the environment, the rebuilt `_C.so`, and the
per-head PPO path from `8ef8143` are all intact. The collapse is caused by the shaping alone.

## The premise was wrong

From the control run:

```
constrained_win_rate    0.704
build_order_violations  0.974 per episode
```

The agent queues a barracks before a refinery in roughly 97% of episodes **and wins 70.4% of
constrained 2300-credit games** — its second-strongest bucket, above the 0.588 average and far above
medium's 0.406. There is no 2300-credit failure mode to correct. The observed poor play in rendered
Vanilla has a different cause (see `vanilla_policy_bridge_mask_bug.md` and the ABI14 attack
findings), not the opening build order.

## Why magnitude did not matter

Run D applies at most -0.2, once per episode, on ~0.26 episodes — roughly -0.02 of reward against a
baseline `episode_return` of +2.382. That cannot collapse a policy by magnitude. It does so anyway
because **PPO normalises advantages**: the absolute reward scale does not bound the gradient. What
distinguishes the penalty is that it is immediate and perfectly attributable to a single action,
while the +1 win is delayed, noisy, and hard to credit. The policy therefore learns
"barracks -> reliably negative" much more cleanly than "barracks -> may help me win later", and the
cheapest way to satisfy that is to stop building barracks at all. Infantry production falls from
31.3 to between 1.0 and 8.3 per episode, and with nothing to fight with the win rate follows.

Run B rules out scope as an explanation: zeroing the penalty on the 65% of non-constrained games did
not recover anything. A single shared policy cannot segregate build behaviour by credit bucket, so a
penalty applied in any bucket suppresses barracks in all of them.

## Current state

All three terms remain implemented, tested and sweepable, but **default to 0.0**. Sweep ranges
include zero so the search can also switch them off. Defaults were verified to reproduce
`balanced_perf` 0.588 exactly.

## If this is revisited

Penalising the action teaches avoidance of the action. To constrain an opening without that side
effect, make the wrong opening **unavailable** rather than expensive: withhold the barracks entry
from `BUILD_PRODUCT` in the action mask until a refinery exists. That produces no gradient teaching
"barracks are bad" because the choice is never presented and never punished. The mask path is
already verified byte-identical between Zig and Vanilla, so this costs no parity risk.

Note that doing so would still be solving a problem the data does not show exists.

---

# Addendum: ABI14 group-attack reachability

## Fixed

`policy_abi14.apply` required `actor`, `product`, `target_x` and `target_y` to hold exact sentinel
values while the action mask constrained none of them. The seven base heads are sampled
independently, so a trained policy had to land one combination in roughly 6.4 million by chance. It
never did: 0 of 140 sampled attacks were structurally valid, and 0 of 226 applied through the
Vanilla bridge. Those four fields carry no meaning for a group attack -- the selectors supply the
actors and `target_slot` supplies the target -- so they are no longer validated. On a full-match
batch with the trained checkpoint this cut rejections from 709 to 380 per 3,000 decisions.

## Not fixed, and more important

Training is **bit-identical** with and without that change: same `balanced_perf` 0.588, same
`invalid_actions` 918.346, md5-identical metric blocks across two runs 29 minutes apart. Across 5M
steps not one attack changed outcome. Two mechanisms explain it, and the second is the real barrier:

1. An attack with **no selectors set** is now accepted, but it is a no-op. It changes no world state,
   and `reward_invalid_action` defaults to 0, so it changes no reward either.
2. An attack **with** selectors must have *every* selected slot pass `combat.canApply`, or the whole
   group is rejected. PufferLib samples all 64 selector heads independently during training, so
   roughly half the slots are selected and nearly all point at entities that are not attack-capable
   infantry. The group is therefore rejected essentially always.

The all-or-nothing rule makes the command unreachable under exploration: the probability that a
random selector set is entirely valid falls off exponentially in the number of selections. A policy
cannot learn to use a primitive it can never once execute.

## Recommendation

Apply the valid subset and ignore invalid selections, rather than rejecting the whole group. That
makes the command reachable immediately -- any single valid selection succeeds -- and lets gradient
reach the selector heads so the policy can learn *which* units to commit.

This is a semantic change to the trained environment and must be mirrored in
`CNC_TD_Micro_Apply_Group_Attack`, which currently implements all-or-nothing to match Zig. Both
sides must change together or the Vanilla bridge diverges from training.

Note this is a hypothesis supported by the bit-identical result and the structure of `apply`, not yet
by a direct count of accepted group attacks under the training curriculum. That count is the cheapest
next measurement.
