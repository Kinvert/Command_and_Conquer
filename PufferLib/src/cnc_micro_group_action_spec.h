#ifndef PUFFERLIB_CNC_MICRO_GROUP_ACTION_SPEC_H
#define PUFFERLIB_CNC_MICRO_GROUP_ACTION_SPEC_H

#include <math.h>

#if defined(__CUDACC__)
#define CNC_MICRO_GROUP_HD __host__ __device__ __forceinline__
#else
#define CNC_MICRO_GROUP_HD inline
#endif

namespace cnc_micro_group_action {

constexpr int kCommand = 0;
constexpr int kActor = 1;
constexpr int kProduct = 2;
constexpr int kTargetKind = 3;
constexpr int kTargetX = 4;
constexpr int kTargetY = 5;
constexpr int kTargetSlot = 6;
constexpr int kBaseHeadCount = 7;
constexpr int kSelectorCount = 64;
constexpr int kActionHeadCount = kBaseHeadCount + kSelectorCount;

constexpr int kCommandCount = 12;
constexpr int kActorCount = 65;
// CNC26 widened this from 6 to 9 for the Weapons Factory, Medium Tank and Humvee.
// Every later offset derives from it, so the mask geometry follows automatically.
constexpr int kProductCount = 9;
constexpr int kTargetKindCount = 4;
constexpr int kCoordinateCount = 64;
constexpr int kTargetSlotCount = 64;
constexpr int kSelectorValueCount = 2;

constexpr int kCommandOffset = 0;
constexpr int kActorOffset = kCommandOffset + kCommandCount;
constexpr int kProductOffset = kActorOffset + kActorCount;
constexpr int kTargetKindOffset = kProductOffset + kProductCount;
constexpr int kTargetXOffset = kTargetKindOffset + kTargetKindCount;
constexpr int kTargetYOffset = kTargetXOffset + kCoordinateCount;
constexpr int kTargetSlotOffset = kTargetYOffset + kCoordinateCount;
constexpr int kSelectorOffset = kTargetSlotOffset + kTargetSlotCount;
constexpr int kLogitCount = kSelectorOffset + kSelectorCount * kSelectorValueCount;
constexpr int kDecoderOutputSize = kLogitCount + 1;
constexpr int kAttackTargetMask = kLogitCount;
constexpr int kMaskSize = kAttackTargetMask + kTargetSlotCount;

constexpr int kAttack = 6;
constexpr int kActorNone = 64;
constexpr int kProductNone = 0;
constexpr int kVisibleEnemy = 3;
constexpr float kMaxAbsPpoLogRatio = 10.0f;

struct PpoHeadTerms {
    float bounded_logratio;
    float ratio;
    float policy_loss;
    float d_new_logprob;
    float old_approx_kl;
    float approx_kl;
    float clip_fraction;
};

CNC_MICRO_GROUP_HD float bounded_ppo_logratio(float logratio) {
    return logratio > kMaxAbsPpoLogRatio ? kMaxAbsPpoLogRatio
        : (logratio < -kMaxAbsPpoLogRatio ? -kMaxAbsPpoLogRatio : logratio);
}

CNC_MICRO_GROUP_HD PpoHeadTerms ppo_head_terms(
        float new_logprob, float old_logprob,
        float weighted_advantage, float clip_coefficient) {
    const float logratio = bounded_ppo_logratio(new_logprob - old_logprob);
    const float ratio = expf(logratio);
    const float clipped_ratio =
        fmaxf(1.0f - clip_coefficient, fminf(1.0f + clip_coefficient, ratio));
    const float loss_unclipped = weighted_advantage * ratio;
    const float loss_clipped = weighted_advantage * clipped_ratio;
    const float policy_loss = fmaxf(loss_unclipped, loss_clipped);
    float d_ratio = weighted_advantage;
    if (loss_clipped > loss_unclipped &&
            (ratio <= 1.0f - clip_coefficient ||
             ratio >= 1.0f + clip_coefficient)) {
        d_ratio = 0.0f;
    }
    return {
        .bounded_logratio = logratio,
        .ratio = ratio,
        .policy_loss = policy_loss,
        .d_new_logprob = d_ratio * ratio,
        .old_approx_kl = -logratio,
        .approx_kl = (ratio - 1.0f) - logratio,
        .clip_fraction = fabsf(ratio - 1.0f) > clip_coefficient ? 1.0f : 0.0f,
    };
}

CNC_MICRO_GROUP_HD float centered_subaction_policy_loss(
        float summed_policy_loss, int active_heads, float weighted_advantage) {
    return summed_policy_loss - float(active_heads - 1) * weighted_advantage;
}

CNC_MICRO_GROUP_HD int head_size(int head) {
    switch (head) {
    case kCommand: return kCommandCount;
    case kActor: return kActorCount;
    case kProduct: return kProductCount;
    case kTargetKind: return kTargetKindCount;
    case kTargetX:
    case kTargetY:
    case kTargetSlot:
        return kCoordinateCount;
    default:
        return head >= kBaseHeadCount && head < kActionHeadCount
            ? kSelectorValueCount : 0;
    }
}

CNC_MICRO_GROUP_HD int head_offset(int head) {
    switch (head) {
    case kCommand: return kCommandOffset;
    case kActor: return kActorOffset;
    case kProduct: return kProductOffset;
    case kTargetKind: return kTargetKindOffset;
    case kTargetX: return kTargetXOffset;
    case kTargetY: return kTargetYOffset;
    case kTargetSlot: return kTargetSlotOffset;
    default:
        return head >= kBaseHeadCount && head < kActionHeadCount
            ? kSelectorOffset + (head - kBaseHeadCount) * kSelectorValueCount
            : -1;
    }
}

CNC_MICRO_GROUP_HD bool head_active(int command, int head, bool has_selection) {
    if (head == kCommand) return true;
    if (command == kAttack) {
        return (head == kTargetSlot && has_selection) ||
            (head >= kBaseHeadCount && head < kActionHeadCount);
    }
    return head > kCommand && head < kBaseHeadCount;
}

CNC_MICRO_GROUP_HD bool selector_contributes(int command, bool option_one_allowed) {
    return command == kAttack && option_one_allowed;
}

CNC_MICRO_GROUP_HD int forced_attack_value(int head) {
    switch (head) {
    case kActor: return kActorNone;
    case kProduct: return kProductNone;
    case kTargetKind: return kVisibleEnemy;
    case kTargetX:
    case kTargetY:
        return 0;
    default:
        return -1;
    }
}

} // namespace cnc_micro_group_action

#undef CNC_MICRO_GROUP_HD

#endif
