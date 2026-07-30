/* Proves the ABI14 header declarations match the real Zig exports, and that a synthetic
 * checkpoint of the declared size is accepted and produces a mask-legal action. */
#include "td_micro_api.h"
#include "td_micro_oracle.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
    const uint32_t size = td_micro_policy_checkpoint_size_abi14();
    printf("abi14 checkpoint_size = %u (weights %u)\n", size, td_micro_policy_weight_count_abi14());
    /* Derived, not pinned: the ABI14 decoder width tracks the action space, and CNC26's nine-wide
       product head moved it. Cross-check it against the documented formula instead. */
    const uint32_t hidden = td_micro_policy_abi14_hidden_for_checkpoint_size(size);
    if (hidden == 0) { printf("FAIL: checkpoint size %u is not a valid ABI14 size\n", size); return 1; }
    printf("implied hidden size = %u\n", hidden);

    /* Small deterministic weights; behaviour is not under test, the ABI is. */
    unsigned char* bytes = malloc(size);
    float* w = (float*)bytes;
    unsigned int s = 12345u;
    for (uint32_t i = 0; i < size / 4; ++i) { s = s * 1103515245u + 12345u; w[i] = ((float)((s >> 16) & 0x7fff) / 32767.0f - 0.5f) * 0.1f; }

    TdMicroPolicyAbi14* p = td_micro_policy_create_abi14(bytes, size);
    if (p == NULL) { printf("FAIL: create rejected an exact-size checkpoint\n"); return 1; }
    if (!td_micro_policy_seed_sampling_abi14(p, 74)) { printf("FAIL: seed\n"); return 1; }
    if (!td_micro_policy_reset_abi14(p)) { printf("FAIL: reset\n"); return 1; }

    unsigned char hash[32];
    td_micro_policy_checkpoint_sha256_abi14(p, hash, sizeof(hash));
    printf("checkpoint sha256 = "); for (int i = 0; i < 8; ++i) printf("%02x", hash[i]); printf("...\n");

    /* Feed it the Zig-side observation and mask for a real reset world. */
    TdMicroBatch* batch = td_micro_batch_create(1, TD_MICRO_TRAINING_MAX_DECISIONS);
    uint64_t seeds[1] = {2};
    td_micro_reset_batch(batch, seeds, 1);
    unsigned char* obs = calloc(1, TD_MICRO_OBSERVATION_SIZE);
    unsigned char* mask = calloc(1, TD_MICRO_ABI14_ACTION_MASK_SIZE);
    if (!td_micro_observe_batch_abi14(batch, obs, mask, 1)) { printf("FAIL: observe\n"); return 1; }

    TdMicroPolicyActionAbi14 action;
    memset(&action, 0, sizeof(action));
    if (!td_micro_policy_act_sampled_abi14(p, obs, TD_MICRO_OBSERVATION_SIZE, mask,
                                           TD_MICRO_ABI14_ACTION_MASK_SIZE, &action)) {
        printf("FAIL: act_sampled rejected\n"); return 1;
    }
    if (!mask[action.command]) { printf("FAIL: sampled a masked-out command %u\n", action.command); return 1; }

    unsigned selected = 0;
    for (unsigned i = 0; i < TD_MICRO_ABI14_SELECTOR_COUNT; ++i) {
        if (action.selectors[i] > 1) { printf("FAIL: selector %u not binary\n", i); return 1; }
        selected += action.selectors[i];
    }
    printf("action: command=%u actor=%u target_slot=%u selectors_on=%u\n",
           action.command, action.actor, action.target_slot, selected);
    if (action.command != TD_MICRO_COMMAND_ATTACK && selected != 0) {
        printf("FAIL: non-attack command carried %u selectors\n", selected); return 1;
    }
    td_micro_policy_destroy_abi14(p);
    printf("PASS: abi14 C ABI links and behaves\n");
    return 0;
}
