#include "../../src/cnc_micro_action_spec.h"
#include "../../../td-micro/include/td_micro_api.h"

#include <cassert>
#include <cstdio>

using namespace cnc_micro_action;

int main()
{
    static_assert(kMaskBitCount == 9242);
    static_assert(kMaskSize == 1156);
    static_assert(kActorTargetRank == 4);
    static_assert(kActorTargetBound == 2.0f);
    static_assert(kActorQueryGroupCount == 4);
    static_assert(kTargetKeyBranchCount == 6);
    static_assert(kActorQueryLogits == 2352);
    static_assert(kTargetKeyLogits == 3376);
    static_assert(kZeroInitLogitBegin == kActorQueryLogits);
    static_assert(kZeroInitLogitEnd == kTargetKeyLogits);
    static_assert(kZeroInitLogitEnd - kZeroInitLogitBegin ==
        kActorQueryGroupCount * kEntitySlotCount * kActorTargetRank);
    static_assert(kLogitCount == 4912);
    static_assert(kDecoderOutputSize == 4913);
    static_assert(kReturnTargetMask + kTokenCount == kMaskBitCount);
    static_assert(TD_MICRO_ABI_VERSION == 13);
    static_assert(TD_MICRO_ACTION_HEAD_COUNT == kActionHeadCount);
    static_assert(TD_MICRO_POLICY_COMMAND_COUNT == kCommandCount);
    static_assert(TD_MICRO_POLICY_TOKEN_COUNT == kTokenCount);
    static_assert(TD_MICRO_POLICY_PAD_TOKEN == kPad);
    static_assert(TD_MICRO_ACTION_MASK_BIT_COUNT == kMaskBitCount);
    static_assert(TD_MICRO_ACTION_MASK_SIZE == kMaskSize);
    static_assert(TD_MICRO_POLICY_DECODER_SIZE == kDecoderOutputSize);
    static_assert(sizeof(TdMicroPolicyAction) == kActionHeadCount);

    for (int bit = 0; bit < 8; ++bit) {
        assert(packed_mask_bit(1 << bit, bit));
        assert(!packed_mask_bit(0, bit));
    }

    assert(argument_mask_offset(kNoop, 0, kPad, kPad) == kPadMask);
    assert(argument_mask_offset(kDeploy, 0, kPad, kPad) == kDeployActorMask);
    assert(argument_mask_offset(kPlace, 1, 17, kPad) == kPlaceYMask + 17 * kTokenCount);
    assert(argument_mask_offset(kHarvest, 2, 3, 29) == kHarvestYMask + 29 * kTokenCount);
    assert(argument_mask_offset(kPlace, 1, kPad, kPad) == -1);
    assert(argument_mask_offset(kHarvest, 2, 0, kPad) == -1);

    for (int command = 0; command < kCommandCount; ++command) {
        for (int arg0 = 0; arg0 < kTokenCount; ++arg0) {
            for (int arg1 = 0; arg1 < kTokenCount; ++arg1) {
                for (int stage = 0; stage < 3; ++stage) {
                    const LogitComponents components =
                        argument_logit_components(command, stage, arg0, arg1);
                    assert(components.count == 1);
                    for (int component = 0; component < components.count; ++component) {
                        assert(components.base[component] >= kCommandCount);
                        assert(components.base[component] + kTokenCount <= kLogitCount);
                    }
                    const int expected = kArg0CommandLogits
                        + (stage * kCommandCount + command) * kTokenCount;
                    assert(components.base[0] == expected);
                }
            }
        }
    }

    const LogitSpec attack_one = argument_logit_spec(kAttack, 1, 7, kPad);
    assert(attack_one.interaction.enabled());
    assert(attack_one.interaction.actor == 7);
    assert(attack_one.interaction.query_base ==
        kActorQueryLogits + kAttackQueryGroup * kEntitySlotCount * kActorTargetRank);
    assert(attack_one.interaction.key_base ==
        kTargetKeyLogits + kAttackTargetKeyBranch * kEntitySlotCount * kActorTargetRank);

    const LogitSpec move_x = argument_logit_spec(kMove, 1, 9, kPad);
    const LogitSpec move_y = argument_logit_spec(kMove, 2, 9, 31);
    assert(move_x.interaction.enabled());
    assert(move_y.interaction.enabled());
    assert(move_x.interaction.query_base == move_y.interaction.query_base);
    assert(move_x.interaction.key_base != move_y.interaction.key_base);

    const LogitSpec no_actor = argument_logit_spec(kAttack, 1, kPad, kPad);
    const LogitSpec build = argument_logit_spec(kStartBuild, 0, kPad, kPad);
    assert(!no_actor.interaction.enabled());
    assert(!build.interaction.enabled());

    std::puts("cnc_micro ABI13 bounded actor-target action spec ok");
    return 0;
}
