#include <stddef.h>
#include "td_micro_api.h"
/* Pins the C structs against their Zig counterparts so the two cannot silently diverge.
 * TdMicroBatchStats is the frozen 248-byte legacy prefix; V2 carries the difficulty split plus the
 * constrained/build-order/attack counters appended after it. */
_Static_assert(sizeof(TdMicroBatchStats) == 248, "legacy TdMicroBatchStats prefix moved");
_Static_assert(sizeof(TdMicroBatchStatsV2) == 424, "TdMicroBatchStatsV2 drifted from Zig batch.Stats");
_Static_assert(sizeof(TdMicroRewardConfig) == 96, "TdMicroRewardConfig drifted from Zig RewardConfig");
_Static_assert(sizeof(TdMicroBatchMetrics) == 344, "TdMicroBatchMetrics drifted from Zig Metrics");
_Static_assert(offsetof(TdMicroRewardConfig, reward_qualified_loss)
                   == sizeof(TdMicroRewardConfig) - sizeof(float),
               "reward_qualified_loss must be last, matching batch.RewardConfig");
/* Field offsets, not just sizes. economy_wins was third from the end in C and last in Zig: the
   sizes matched exactly, the size assert passed, and the field silently read a different counter.
   Anything appended to batch.Stats must be appended here too, in the same order. */
_Static_assert(offsetof(TdMicroBatchStatsV2, full_wins)
                   == sizeof(TdMicroBatchStatsV2) - sizeof(uint64_t),
               "full_wins must be the last field, matching batch.Stats");
_Static_assert(offsetof(TdMicroBatchStatsV2, constrained_episodes)
                   < offsetof(TdMicroBatchStatsV2, attacks_attempted),
               "constrained counters precede the attack counters in batch.Stats");
_Static_assert(offsetof(TdMicroBatchStatsV2, easy_close_mcv_episodes) == sizeof(TdMicroBatchStats),
               "the difficulty split must begin exactly at the legacy prefix boundary");

int main(void) { return 0; }
