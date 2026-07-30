#ifndef PUFFERLIB_CNC_MICRO_ACTION_SPEC_H
#define PUFFERLIB_CNC_MICRO_ACTION_SPEC_H

#include <math.h>

#if defined(__CUDACC__)
#define CNC_MICRO_HD __host__ __device__ __forceinline__
#else
#define CNC_MICRO_HD inline
#endif

namespace cnc_micro_action {

constexpr int kCommandCount = 12;
constexpr int kTokenCount = 65;
constexpr int kCoordinateCount = 64;
constexpr int kEntitySlotCount = 64;
constexpr int kPad = 64;
constexpr int kActionHeadCount = 4;
constexpr int kActorTargetRank = 4;
constexpr float kActorTargetScale = 0.5f;
constexpr float kActorTargetBound = 2.0f;

constexpr int kMoveQueryGroup = 0;
constexpr int kAttackQueryGroup = 1;
constexpr int kHarvestQueryGroup = 2;
constexpr int kReturnQueryGroup = 3;
constexpr int kActorQueryGroupCount = 4;

constexpr int kMoveXKeyBranch = 0;
constexpr int kMoveYKeyBranch = 1;
constexpr int kAttackTargetKeyBranch = 2;
constexpr int kHarvestXKeyBranch = 3;
constexpr int kHarvestYKeyBranch = 4;
constexpr int kReturnTargetKeyBranch = 5;
constexpr int kTargetKeyBranchCount = 6;

constexpr int kNoop = 0;
constexpr int kDeploy = 1;
constexpr int kStartBuild = 2;
constexpr int kPlace = 3;
constexpr int kTrain = 4;
constexpr int kMove = 5;
constexpr int kAttack = 6;
constexpr int kGuard = 7;
constexpr int kStop = 8;
constexpr int kHunt = 9;
constexpr int kHarvest = 10;
constexpr int kReturnCargo = 11;

constexpr int kCommandMask = 0;
constexpr int kPadMask = 12;
constexpr int kDeployActorMask = 77;
constexpr int kBuildProductMask = 142;
constexpr int kPlaceXMask = 207;
constexpr int kPlaceYMask = 272;
constexpr int kTrainProductMask = 4432;
constexpr int kMoveActorMask = 4497;
constexpr int kMoveXMask = 4562;
constexpr int kMoveYMask = 4627;
constexpr int kAttackActorMask = 4692;
constexpr int kAttackTargetMask = 4757;
constexpr int kHarvestActorMask = 4822;
constexpr int kHarvestXMask = 4887;
constexpr int kHarvestYMask = 4952;
constexpr int kReturnActorMask = 9112;
constexpr int kReturnTargetMask = 9177;
constexpr int kMaskBitCount = 9242;
constexpr int kMaskSize = (kMaskBitCount + 7) / 8;

// Each argument stage shares one state-dependent row per command. Exact
// prefix legality remains in the selected mask row rather than a dense logit
// row for every possible prior token.
constexpr int kCommandLogits = 0;
constexpr int kArg0CommandLogits = 12;
constexpr int kArg1CommandLogits = kArg0CommandLogits + kCommandCount * kTokenCount;
constexpr int kArg2CommandLogits = kArg1CommandLogits + kCommandCount * kTokenCount;
constexpr int kBaseLogitCount = kArg2CommandLogits + kCommandCount * kTokenCount;
constexpr int kActorQueryLogits = kBaseLogitCount;
constexpr int kTargetKeyLogits = kActorQueryLogits
    + kActorQueryGroupCount * kEntitySlotCount * kActorTargetRank;
// The actor-query branch is a residual interaction. Starting it at zero
// preserves the compact base policy while random target keys provide a
// nonzero first gradient into the query rows.
constexpr int kZeroInitLogitBegin = kActorQueryLogits;
constexpr int kZeroInitLogitEnd = kTargetKeyLogits;
constexpr int kLogitCount = kTargetKeyLogits
    + kTargetKeyBranchCount * kEntitySlotCount * kActorTargetRank;
constexpr int kDecoderOutputSize = kLogitCount + 1;

struct LogitComponents {
    int count;
    int base[3];
};

struct ActorTargetInteraction {
    int query_base;
    int key_base;
    int actor;

    CNC_MICRO_HD bool enabled() const {
        return query_base >= 0 && key_base >= 0 &&
            actor >= 0 && actor < kEntitySlotCount;
    }
};

struct LogitSpec {
    LogitComponents additive;
    ActorTargetInteraction interaction;
};

CNC_MICRO_HD bool packed_mask_bit(int packed_byte, int bit_index) {
    return (packed_byte & (1 << (bit_index % 8))) != 0;
}

CNC_MICRO_HD int argument_mask_offset(int command, int stage, int arg0, int arg1) {
    if (command < 0 || command >= kCommandCount || stage < 0 || stage >= 3) return -1;
    if (stage == 0) {
        switch (command) {
        case kNoop: return kPadMask;
        case kDeploy: return kDeployActorMask;
        case kStartBuild: return kBuildProductMask;
        case kPlace: return kPlaceXMask;
        case kTrain: return kTrainProductMask;
        case kMove: return kMoveActorMask;
        case kAttack: return kAttackActorMask;
        case kHarvest: return kHarvestActorMask;
        case kReturnCargo: return kReturnActorMask;
        default: return kPadMask;
        }
    }
    if (stage == 1) {
        switch (command) {
        case kPlace:
            return arg0 >= 0 && arg0 < kCoordinateCount
                ? kPlaceYMask + arg0 * kTokenCount : -1;
        case kMove: return kMoveXMask;
        case kAttack: return kAttackTargetMask;
        case kHarvest: return kHarvestXMask;
        case kReturnCargo: return kReturnTargetMask;
        default: return kPadMask;
        }
    }
    switch (command) {
    case kMove: return kMoveYMask;
    case kHarvest:
        return arg1 >= 0 && arg1 < kCoordinateCount
            ? kHarvestYMask + arg1 * kTokenCount : -1;
    default: return kPadMask;
    }
}

CNC_MICRO_HD LogitComponents argument_logit_components(
        int command, int stage, int, int) {
    LogitComponents result = {0, {-1, -1, -1}};
    if (command < 0 || command >= kCommandCount || stage < 0 || stage >= 3) return result;
    constexpr int stage_stride = kCommandCount * kTokenCount;
    result.count = 1;
    result.base[0] = kArg0CommandLogits + stage * stage_stride + command * kTokenCount;
    return result;
}

CNC_MICRO_HD int actor_query_group(int command) {
    switch (command) {
    case kMove: return kMoveQueryGroup;
    case kAttack: return kAttackQueryGroup;
    case kHarvest: return kHarvestQueryGroup;
    case kReturnCargo: return kReturnQueryGroup;
    default: return -1;
    }
}

CNC_MICRO_HD int target_key_branch(int command, int stage) {
    if (stage == 1) {
        switch (command) {
        case kMove: return kMoveXKeyBranch;
        case kAttack: return kAttackTargetKeyBranch;
        case kHarvest: return kHarvestXKeyBranch;
        case kReturnCargo: return kReturnTargetKeyBranch;
        default: return -1;
        }
    }
    if (stage == 2) {
        switch (command) {
        case kMove: return kMoveYKeyBranch;
        case kHarvest: return kHarvestYKeyBranch;
        default: return -1;
        }
    }
    return -1;
}

CNC_MICRO_HD LogitSpec argument_logit_spec(
        int command, int stage, int arg0, int arg1) {
    LogitSpec result = {
        argument_logit_components(command, stage, arg0, arg1),
        {-1, -1, -1},
    };
    const int query_group = actor_query_group(command);
    const int key_branch = target_key_branch(command, stage);
    if (query_group < 0 || key_branch < 0 ||
            arg0 < 0 || arg0 >= kEntitySlotCount) {
        return result;
    }
    result.interaction = {
        kActorQueryLogits + query_group * kEntitySlotCount * kActorTargetRank,
        kTargetKeyLogits + key_branch * kEntitySlotCount * kActorTargetRank,
        arg0,
    };
    return result;
}

CNC_MICRO_HD LogitSpec command_logit_spec() {
    return {{1, {kCommandLogits, -1, -1}}, {-1, -1, -1}};
}

template <typename Reader>
CNC_MICRO_HD float actor_target_dot(
        ActorTargetInteraction interaction, int token, const Reader& read) {
    if (!interaction.enabled() || token < 0 || token >= kEntitySlotCount) return 0.0f;
    const int query = interaction.query_base + interaction.actor * kActorTargetRank;
    const int key = interaction.key_base + token * kActorTargetRank;
    float dot = 0.0f;
    for (int rank = 0; rank < kActorTargetRank; ++rank) {
        dot += read(query + rank) * read(key + rank);
    }
    return dot;
}

template <typename Reader>
CNC_MICRO_HD float actor_target_gradient_scale(
        ActorTargetInteraction interaction, int token, const Reader& read) {
    const float bounded = tanhf(
        (kActorTargetScale / kActorTargetBound) *
        actor_target_dot(interaction, token, read));
    return kActorTargetScale * (1.0f - bounded * bounded);
}

template <typename Reader>
CNC_MICRO_HD float score_logit(LogitSpec spec, int token, const Reader& read) {
    float result = 0.0f;
    for (int component = 0; component < spec.additive.count; ++component) {
        result += read(spec.additive.base[component] + token);
    }
    if (spec.interaction.enabled() && token >= 0 && token < kEntitySlotCount) {
        result += kActorTargetBound * tanhf(
            (kActorTargetScale / kActorTargetBound) *
            actor_target_dot(spec.interaction, token, read));
    }
    return result;
}

template <typename Reader>
CNC_MICRO_HD float actor_query_gradient_factor(
        ActorTargetInteraction interaction, int token, int rank,
        float gradient_scale, const Reader& read) {
    if (!interaction.enabled() || token < 0 || token >= kEntitySlotCount ||
            rank < 0 || rank >= kActorTargetRank) return 0.0f;
    return gradient_scale * read(
        interaction.key_base + token * kActorTargetRank + rank);
}

template <typename Reader>
CNC_MICRO_HD float target_key_gradient_factor(
        ActorTargetInteraction interaction, int rank,
        float gradient_scale, const Reader& read) {
    if (!interaction.enabled() || rank < 0 || rank >= kActorTargetRank) return 0.0f;
    return gradient_scale * read(
        interaction.query_base + interaction.actor * kActorTargetRank + rank);
}

CNC_MICRO_HD float categorical_logit_gradient(
        int token, int selected, float probability, float logprob,
        float entropy, float d_new_logprob, float d_entropy) {
    float gradient = (token == selected ? d_new_logprob : 0.0f) -
        probability * d_new_logprob;
    gradient += d_entropy * probability * (-entropy - logprob);
    return gradient;
}

} // namespace cnc_micro_action

#undef CNC_MICRO_HD

#endif
