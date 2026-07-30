#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    /* This utility decodes the retained ABI-4/8 full-map trace format. */
    OBSERVATION_SIZE = 6208,
    ACTION_MASK_SIZE = 279,
    RECORD_SIZE = OBSERVATION_SIZE + ACTION_MASK_SIZE,
    MAP_OFFSET = 64,
    OWN_OFFSET = MAP_OFFSET + 64 * 64,
    ENEMY_OFFSET = OWN_OFFSET + 64 * 16,
};

static const char* entity_fields[16] = {
    "present", "type", "id_low", "id_high", "x", "y", "health", "facing",
    "mission", "target_kind", "target_slot", "cooldown", "flags", "progress",
    "category", "status",
};

static const char* global_fields[32] = {
    "observation_version", "map_width", "map_height", "frame_div_32",
    "player_credits_div_100", "player_power", "player_drain", "player_defeated",
    "enemy_defeated", "failure", "structure_queue_active", "structure_queue_complete",
    "structure_queue_product", "structure_queue_progress", "structure_queue_timer",
    "infantry_queue_active", "infantry_queue_complete", "infantry_queue_product",
    "infantry_queue_progress", "infantry_queue_timer", "own_units", "own_buildings",
    "own_infantry", "enemy_units", "enemy_buildings", "enemy_infantry",
    "player_tiberium_div_25", "player_capacity_div_25", "player_harvested_div_25",
    "enemy_tiberium_div_25", "enemy_capacity_div_25", "map_tiberium_steps",
};

static void describe_offset(size_t offset, char* output, size_t capacity)
{
    if (offset < MAP_OFFSET) {
        if (offset < 32) {
            snprintf(output, capacity, "global.%s", global_fields[offset]);
        } else {
            snprintf(output, capacity, "global.reserved[%zu]", offset);
        }
        return;
    }
    if (offset < OWN_OFFSET) {
        const size_t cell = offset - MAP_OFFSET;
        snprintf(output, capacity, "map[%zu,%zu]", cell % 64, cell / 64);
        return;
    }
    if (offset < ENEMY_OFFSET) {
        const size_t entity = offset - OWN_OFFSET;
        snprintf(output, capacity, "own_entity[%zu].%s", entity / 16, entity_fields[entity % 16]);
        return;
    }
    if (offset < OBSERVATION_SIZE) {
        const size_t entity = offset - ENEMY_OFFSET;
        snprintf(output, capacity, "enemy_entity[%zu].%s", entity / 16, entity_fields[entity % 16]);
        return;
    }

    const size_t mask = offset - OBSERVATION_SIZE;
    static const size_t starts[] = {0, 12, 77, 83, 87, 151, 215, ACTION_MASK_SIZE};
    static const char* names[] = {
        "command", "actor", "product", "target_kind", "target_x", "target_y", "target_slot",
    };
    for (size_t head = 0; head < 7; ++head) {
        if (mask >= starts[head] && mask < starts[head + 1]) {
            snprintf(output, capacity, "mask.%s[%zu]", names[head], mask - starts[head]);
            return;
        }
    }
    snprintf(output, capacity, "unknown[%zu]", offset);
}

static int parse_decision_frames(const char* value)
{
    char* end = NULL;
    errno = 0;
    const long parsed = strtol(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || parsed <= 0 || parsed > 1000000) return -1;
    return (int)parsed;
}

int main(int argc, char** argv)
{
    if (argc != 3 && argc != 4) {
        fprintf(stderr, "usage: %s LEFT_TRACE RIGHT_TRACE [DECISION_FRAMES]\n", argv[0]);
        return 2;
    }
    const int decision_frames = argc == 4 ? parse_decision_frames(argv[3]) : 4;
    if (decision_frames <= 0) {
        fprintf(stderr, "invalid decision frame count: %s\n", argv[3]);
        return 2;
    }

    FILE* left = fopen(argv[1], "rb");
    FILE* right = fopen(argv[2], "rb");
    if (left == NULL || right == NULL) {
        fprintf(stderr, "failed to open traces: %s\n", strerror(errno));
        if (left != NULL) fclose(left);
        if (right != NULL) fclose(right);
        return 2;
    }

    uint8_t left_record[RECORD_SIZE];
    uint8_t right_record[RECORD_SIZE];
    size_t decision = 0;
    for (;;) {
        const size_t left_size = fread(left_record, 1, sizeof(left_record), left);
        const size_t right_size = fread(right_record, 1, sizeof(right_record), right);
        const size_t common = left_size < right_size ? left_size : right_size;
        for (size_t offset = 0; offset < common; ++offset) {
            if (left_record[offset] == right_record[offset]) continue;
            char field[128];
            describe_offset(offset, field, sizeof(field));
            printf("mismatch decision=%zu simulation_frame=%zu byte_offset=%zu field=%s left=%u right=%u\n",
                   decision,
                   decision * (size_t)decision_frames,
                   offset,
                   field,
                   left_record[offset],
                   right_record[offset]);
            fclose(left);
            fclose(right);
            return 1;
        }
        if (left_size != right_size) {
            printf("length_mismatch decision=%zu simulation_frame=%zu record_offset=%zu left_bytes=%zu right_bytes=%zu\n",
                   decision,
                   decision * (size_t)decision_frames,
                   common,
                   left_size,
                   right_size);
            fclose(left);
            fclose(right);
            return 1;
        }
        if (left_size == 0) break;
        if (left_size != RECORD_SIZE) {
            printf("truncated_record decision=%zu simulation_frame=%zu bytes=%zu\n",
                   decision,
                   decision * (size_t)decision_frames,
                   left_size);
            fclose(left);
            fclose(right);
            return 1;
        }
        ++decision;
    }

    printf("equal records=%zu bytes=%zu\n", decision, decision * (size_t)RECORD_SIZE);
    fclose(left);
    fclose(right);
    return 0;
}
