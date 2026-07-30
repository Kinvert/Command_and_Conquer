#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
oracle=${TD_MICRO_ORACLE:-$root/tools/td_micro_oracle}
library=${TD_MICRO_LIBRARY:-$root/Vanilla-Conquer/build-remastertd/tiberiandawn/TiberianDawn.so}
shared_root=$(dirname "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)")
default_data=$root/td-data
if [[ ! -d $default_data ]]; then
    default_data=$shared_root/td-data
fi
data=${TD_MICRO_DATA:-$default_data/}
fixtures=$root/td-micro/tests/fixtures

record() {
    local name=$1
    shift
    local first second
    first=$(mktemp "/tmp/${name}.first.XXXXXX")
    second=$(mktemp "/tmp/${name}.second.XXXXXX")
    trap 'rm -f "$first" "$second"' RETURN

    "$oracle" --lib "$library" --data "$data" --output "$first" "$@"
    "$oracle" --lib "$library" --data "$data" --output "$second" "$@"
    cmp "$first" "$second"
    cp "$first" "$fixtures/$name"
    sha256sum "$fixtures/$name"
}

record_map() {
    local name=$1
    local first second first_trace second_trace
    first=$(mktemp "/tmp/${name}.first.XXXXXX")
    second=$(mktemp "/tmp/${name}.second.XXXXXX")
    first_trace=$(mktemp "/tmp/${name}.first-trace.XXXXXX")
    second_trace=$(mktemp "/tmp/${name}.second-trace.XXXXXX")
    trap 'rm -f "$first" "$second" "$first_trace" "$second_trace"' RETURN

    "$oracle" --lib "$library" --data "$data" \
        --output "$first_trace" --map-output "$first" --seed 1 --decisions 0
    "$oracle" --lib "$library" --data "$data" \
        --output "$second_trace" --map-output "$second" --seed 1 --decisions 0
    cmp "$first" "$second"
    cp "$first" "$fixtures/$name"
    sha256sum "$fixtures/$name"
}

opening=(
    --seed 1
    --deploy-decision 1
    --power-decision 23
    --place-power-decision 77 --place-x 4 --place-y 7
    --barracks-decision 92
    --place-barracks-decision 146 --barracks-x 6 --barracks-y 7
)

record_map vanilla_seed1_scenario1_map.json
record vanilla_seed1_idle64.jsonl --seed 1 --decisions 16
record vanilla_seed2_idle64.jsonl --seed 2 --decisions 16
record vanilla_seed1_ai_deploy_frame.jsonl --seed 1 --decisions 8 --advance-frames 1
record vanilla_seed1_ai_opening.jsonl --seed 1 --decisions 160
for difficulty in easy normal hard; do
    record "vanilla_seed1_difficulty_${difficulty}_ai_opening.jsonl" \
        --seed 1 --difficulty "$difficulty" --decisions 24
done
record vanilla_seed1_ai_infantry_hunt.jsonl --seed 1 --decisions 1600 --write-every 64
record vanilla_seed2_ai_early_force.jsonl --seed 2 --decisions 700 --write-every 4
record vanilla_seed1_ai_terminal.jsonl --seed 1 --decisions 3000
record vanilla_seed1_ai_economy.jsonl --seed 1 --decisions 1100 --write-every 4
record vanilla_seed1_mirror_deploy.jsonl --seed 1 --decisions 20 --deploy-decision 1
record vanilla_seed1_player_power.jsonl --seed 1 --decisions 80 --deploy-decision 1 --power-decision 23
record vanilla_seed1_player_power_place.jsonl --seed 1 --decisions 96 \
    --deploy-decision 1 --power-decision 23 \
    --place-power-decision 77 --place-x 4 --place-y 7
record vanilla_seed1_player_refinery_harvest.jsonl --seed 1 --decisions 1100 --write-every 4 \
    --deploy-decision 1 --power-decision 23 \
    --place-power-decision 77 --place-x 4 --place-y 7 \
    --refinery-decision 92 \
    --place-refinery-decision 579 --refinery-x 6 --refinery-y 7
record vanilla_seed1_player_barracks.jsonl --decisions 165 "${opening[@]}"
record vanilla_seed1_player_e1_e3.jsonl --decisions 258 "${opening[@]}" \
    --e1-decision 161 --e3-decision 189
record vanilla_seed1_player_e1_move.jsonl --decisions 275 "${opening[@]}" \
    --e1-decision 161 --e3-decision 189 \
    --move-decision 245 --move-actor 3 --move-x 10 --move-y 9
record vanilla_seed1_player_e1_obstacle.jsonl --decisions 350 "${opening[@]}" \
    --e1-decision 161 --e3-decision 189 \
    --move-decision 245 --move-actor 3 --move-x 18 --move-y 9
record vanilla_seed1_e1_duel_frame.jsonl --seed 1 --decisions 160 --advance-frames 1 \
    --fixture 1 --attack-decision 1 --attack-actor 1 --attack-target 1
record vanilla_seed1_e1_duel.jsonl --seed 1 --decisions 40 \
    --fixture 1 --attack-decision 1 --attack-actor 1 --attack-target 1
for difficulty in easy normal hard; do
    record "vanilla_seed1_difficulty_${difficulty}_e1_duel.jsonl" \
        --seed 1 --difficulty "$difficulty" --decisions 160 --advance-frames 1 --write-every 4 \
        --fixture 1 --attack-decision 1 --attack-actor 1 --attack-target 1
    record "vanilla_seed1_difficulty_${difficulty}_e1_move.jsonl" \
        --seed 1 --difficulty "$difficulty" --decisions 100 --advance-frames 1 --write-every 4 \
        --fixture 1 --action-owner 1 \
        --move-decision 1 --move-actor 1 --move-x 30 --move-y 20
done
record vanilla_seed1_e3_duel_frame.jsonl --seed 1 --decisions 400 --advance-frames 1 \
    --fixture 2 --attack-decision 1 --attack-actor 1 --attack-target 1
record vanilla_seed1_e3_duel.jsonl --seed 1 --decisions 100 \
    --fixture 2 --attack-decision 1 --attack-actor 1 --attack-target 1
record vanilla_seed1_e1_attack_mcv.jsonl --seed 1 --decisions 700 \
    --fixture 1 --attack-decision 1 --attack-actor 1 --attack-target 0
record vanilla_seed1_h0_finish_e1.jsonl --seed 1 --decisions 0 --fixture 3
record vanilla_seed1_h0_finish_e3.jsonl --seed 1 --decisions 0 --fixture 4
record vanilla_seed1_h0_finish_mixed.jsonl --seed 1 --decisions 0 --fixture 5
record vanilla_seed1_h1_assault_e1.jsonl --seed 1 --decisions 0 --fixture 6
record vanilla_seed1_h1_assault_e3.jsonl --seed 1 --decisions 0 --fixture 7
record vanilla_seed1_h1_assault_mixed.jsonl --seed 1 --decisions 0 --fixture 8
record vanilla_seed1_h2_mobilize.jsonl --seed 1 --decisions 0 --fixture 9
record vanilla_seed1_h3_economy.jsonl --seed 1 --decisions 0 --fixture 10
record vanilla_seed1_h4_opening.jsonl --seed 1 --decisions 0 --fixture 11
record vanilla_seed1_starting_force.jsonl --seed 1 --decisions 256 --write-every 1 --unit-count 6

# CNC26 vehicle expansion. The Weapons Factory needs a Refinery first, and the whole chain has to
# finish before the original AI overruns the base: an earlier attempt placed the Refinery at
# decision 579 and the Construction Yard was destroyed mid-build, which abandoned the factory
# production (BuildingClass::Detach_All -> Abandon_Production). The Weapons Factory also builds
# noticeably slower than the equally priced Refinery, hence the decision-800 placement.
vehicle_opening=(
    --seed 1 --write-every 20
    --deploy-decision 1
    --power-decision 23 --place-power-decision 77 --place-x 4 --place-y 7
    --refinery-decision 92 --place-refinery-decision 240 --refinery-x 6 --refinery-y 7
    --weapons-factory-decision 245
    --place-weapons-factory-decision 800 --weapons-factory-x 2 --weapons-factory-y 9
)
record vanilla_seed1_weapons_factory.jsonl --decisions 820 "${vehicle_opening[@]}"
record vanilla_seed1_medium_tank.jsonl --decisions 1120 "${vehicle_opening[@]}" \
    --medium-tank-decision 860
record vanilla_seed1_humvee.jsonl --decisions 1120 "${vehicle_opening[@]}" \
    --humvee-decision 860
