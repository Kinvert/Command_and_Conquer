/* Mask parity probe.
 *
 * Dumps the Zig-side ABI13 action mask for a freshly reset world so it can be diffed against the
 * mask the Vanilla bridge writes (td_micro_policy_state_live.bin, first record). The Zig side is
 * the source of truth; any disagreement is a bridge defect.
 *
 * usage: mask_parity_probe <seed> <out.bin>
 */
#include "td_micro_api.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv)
{
    const unsigned long seed = argc > 1 ? strtoul(argv[1], NULL, 10) : 2u;
    const char* out_path = argc > 2 ? argv[2] : "/tmp/zig_mask.bin";

    TdMicroBatch* batch = td_micro_batch_create(1, TD_MICRO_TRAINING_MAX_DECISIONS);
    if (batch == NULL) {
        fprintf(stderr, "batch_create failed\n");
        return 1;
    }

    unsigned long long seeds[1] = {(unsigned long long)seed};
    if (!td_micro_reset_batch(batch, seeds, 1)) {
        fprintf(stderr, "reset_batch failed\n");
        return 1;
    }

    unsigned char* obs = (unsigned char*)calloc(1, TD_MICRO_OBSERVATION_SIZE);
    unsigned char* mask = (unsigned char*)calloc(1, TD_MICRO_ACTION_MASK_SIZE);
    if (!td_micro_observe_batch(batch, obs, mask, 1)) {
        fprintf(stderr, "observe_batch failed\n");
        return 1;
    }

    FILE* f = fopen(out_path, "wb");
    if (f == NULL) {
        fprintf(stderr, "cannot open %s\n", out_path);
        return 1;
    }
    fwrite(obs, 1, TD_MICRO_OBSERVATION_SIZE, f);
    fwrite(mask, 1, TD_MICRO_ACTION_MASK_SIZE, f);
    fclose(f);

    /* Report group occupancy so a human can eyeball the structural difference immediately. */
    struct {
        const char* name;
        unsigned int bit_offset;
        unsigned int span;
    } groups[] = {
        {"COMMAND", TD_MICRO_MASK_COMMAND_BIT_OFFSET, 12},
        {"PAD", TD_MICRO_MASK_PAD_BIT_OFFSET, 65},
        {"DEPLOY_ACTOR", TD_MICRO_MASK_DEPLOY_ACTOR_BIT_OFFSET, 65},
        {"BUILD_PRODUCT", TD_MICRO_MASK_BUILD_PRODUCT_BIT_OFFSET, 65},
        {"PLACE_X", TD_MICRO_MASK_PLACE_X_BIT_OFFSET, 65},
        {"TRAIN_PRODUCT", TD_MICRO_MASK_TRAIN_PRODUCT_BIT_OFFSET, 65},
        {"MOVE_ACTOR", TD_MICRO_MASK_MOVE_ACTOR_BIT_OFFSET, 65},
        {"MOVE_X", TD_MICRO_MASK_MOVE_X_BIT_OFFSET, 65},
        {"MOVE_Y", TD_MICRO_MASK_MOVE_Y_BIT_OFFSET, 65},
        {"ATTACK_ACTOR", TD_MICRO_MASK_ATTACK_ACTOR_BIT_OFFSET, 65},
        {"ATTACK_TARGET", TD_MICRO_MASK_ATTACK_TARGET_BIT_OFFSET, 65},
        {"HARVEST_ACTOR", TD_MICRO_MASK_HARVEST_ACTOR_BIT_OFFSET, 65},
        {"HARVEST_X", TD_MICRO_MASK_HARVEST_X_BIT_OFFSET, 65},
        {"RETURN_ACTOR", TD_MICRO_MASK_RETURN_ACTOR_BIT_OFFSET, 65},
        {"RETURN_TARGET", TD_MICRO_MASK_RETURN_TARGET_BIT_OFFSET, 65},
    };
    printf("zig mask (seed %lu), %u bytes / %u bits\n",
           seed,
           (unsigned)TD_MICRO_ACTION_MASK_SIZE,
           (unsigned)TD_MICRO_ACTION_MASK_BIT_COUNT);
    for (unsigned g = 0; g < sizeof(groups) / sizeof(groups[0]); ++g) {
        unsigned set = 0;
        for (unsigned i = 0; i < groups[g].span; ++i) {
            const unsigned bit = groups[g].bit_offset + i;
            if (mask[bit / 8] & (1u << (bit % 8))) ++set;
        }
        printf("  %-14s bit=%-5u set=%u\n", groups[g].name, groups[g].bit_offset, set);
    }

    unsigned total = 0;
    for (unsigned i = 0; i < TD_MICRO_ACTION_MASK_SIZE; ++i) {
        for (unsigned b = 0; b < 8; ++b)
            if (mask[i] & (1u << b)) ++total;
    }
    printf("  total bits set = %u\n", total);

    /* ABI14 reference: same world, 471-byte byte-per-entry mask.
       Layout: [0,279) ABI9 base, [279,407) 64 selector heads x 2, [407,471) attack targets. */
    unsigned char* mask14 = (unsigned char*)calloc(1, TD_MICRO_ABI14_ACTION_MASK_SIZE);
    unsigned char* obs14 = (unsigned char*)calloc(1, TD_MICRO_OBSERVATION_SIZE);
    if (td_micro_observe_batch_abi14(batch, obs14, mask14, 1)) {
        char path14[512];
        snprintf(path14, sizeof(path14), "%s.abi14", out_path);
        FILE* g = fopen(path14, "wb");
        if (g != NULL) {
            fwrite(mask14, 1, TD_MICRO_ABI14_ACTION_MASK_SIZE, g);
            fclose(g);
        }
        unsigned base_set = 0, sel_on = 0, targets = 0;
        for (unsigned i = 0; i < 279; ++i) base_set += mask14[i] != 0;
        for (unsigned i = 0; i < 64; ++i) sel_on += mask14[279 + i * 2 + 1] != 0;
        for (unsigned i = 407; i < TD_MICRO_ABI14_ACTION_MASK_SIZE; ++i) targets += mask14[i] != 0;
        printf("\nabi14 mask (%u bytes) -> %s\n", (unsigned)TD_MICRO_ABI14_ACTION_MASK_SIZE, path14);
        printf("  base[0,279)      set=%u\n", base_set);
        printf("  selectors ON     =%u of 64\n", sel_on);
        printf("  attack targets   =%u\n", targets);
    }
    free(mask14);
    free(obs14);

    td_micro_batch_destroy(batch);
    free(obs);
    free(mask);
    return 0;
}
