#include "../../src/cnc_micro_group_action_spec.h"

#include <cassert>
#include <cstdio>

using namespace cnc_micro_group_action;

int main()
{
    static_assert(kActionHeadCount == 71);
    static_assert(kLogitCount == 407);
    static_assert(kMaskSize == 471);
    static_assert(kAttackTargetMask == 407);
    assert(head_offset(kCommand) == 0);
    assert(head_offset(kTargetSlot) == 215);
    assert(head_offset(kBaseHeadCount) == 279);
    assert(head_offset(kActionHeadCount - 1) == 405);
    assert(head_size(kActionHeadCount - 1) == 2);

    for (int head = 0; head < kActionHeadCount; ++head) {
        const bool expected_attack =
            head == kCommand || head == kTargetSlot || head >= kBaseHeadCount;
        const bool expected_nonattack = head < kBaseHeadCount;
        assert(head_active(kAttack, head, true) == expected_attack);
        assert(head_active(0, head, false) == expected_nonattack);
    }
    assert(!head_active(kAttack, kTargetSlot, false));
    assert(selector_contributes(kAttack, true));
    assert(!selector_contributes(kAttack, false));
    assert(!selector_contributes(0, true));
    assert(forced_attack_value(kActor) == kActorNone);
    assert(forced_attack_value(kProduct) == kProductNone);
    assert(forced_attack_value(kTargetKind) == kVisibleEnemy);
    assert(forced_attack_value(kTargetX) == 0);
    assert(forced_attack_value(kTargetY) == 0);
    assert(forced_attack_value(kTargetSlot) == -1);

    std::puts("cnc_micro ABI14 group action spec ok");
    return 0;
}
