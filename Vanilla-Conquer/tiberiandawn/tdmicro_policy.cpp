#include "function.h"

#include "td_micro_api.h"
#include "td_micro_oracle.h"
#include "scenario1_tiberium.h"
#include "td_micro_v1.h"
#include "tdmicro.h"

#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <vector>

#ifndef _MSC_VER
#ifndef __cdecl
#define __cdecl
#endif
#ifndef __declspec
#define __declspec(x) __attribute__((visibility("default")))
#endif
#endif

extern "C" bool CNC_TD_Micro_Apply_Action(uint8_t owner, TdMicroAction const* action);
extern "C" bool CNC_TD_Micro_Apply_Group_Attack(uint8_t owner,
                                               uint8_t target_slot,
                                               uint8_t const* selectors,
                                               uint32_t selector_count,
                                               uint32_t* applied_count);

namespace {

enum ObservationOffset
{
    OBS_GLOBAL = 0,
    OBS_TIBERIUM = TD_MICRO_OBSERVATION_GLOBAL_SIZE,
    OBS_OWN = OBS_TIBERIUM + TD_MICRO_OBSERVATION_TIBERIUM_COUNT,
    OBS_ENEMY =
        OBS_OWN + TD_MICRO_OBSERVATION_ENTITY_SLOT_COUNT * TD_MICRO_OBSERVATION_ENTITY_SIZE,
};

static_assert(TD_MICRO_INITIAL_TIBERIUM_CELL_COUNT == TD_MICRO_OBSERVATION_TIBERIUM_COUNT,
              "generated map and observation ABI disagree");
static_assert(OBS_ENEMY
                      + TD_MICRO_OBSERVATION_ENTITY_SLOT_COUNT * TD_MICRO_OBSERVATION_ENTITY_SIZE
                  == TD_MICRO_OBSERVATION_SIZE,
              "entity record layout must sum to the exported observation size");

enum EntityField
{
    ENTITY_PRESENT = 0,
    ENTITY_TYPE = 1,
    ENTITY_ID_LOW = 2,
    ENTITY_ID_HIGH = 3,
    ENTITY_X = 4,
    ENTITY_Y = 5,
    ENTITY_HEALTH = 6,
    ENTITY_FACING = 7,
    ENTITY_MISSION = 8,
    ENTITY_TARGET_KIND = 9,
    ENTITY_TARGET_SLOT = 10,
    ENTITY_COOLDOWN = 11,
    ENTITY_FLAGS = 12,
    ENTITY_PROGRESS = 13,
    ENTITY_CATEGORY = 14,
    ENTITY_STATUS = 15,
};

static const uint16_t LEGACY_UNIT_COUNT = 2;
static const uint16_t ADDITIONAL_UNIT_ID_BASE =
    LEGACY_UNIT_COUNT + TD_MICRO_MAX_BUILDINGS + TD_MICRO_MAX_INFANTRY;

/* Derived from the head widths rather than written out, so widening a head (CNC26 took product
   from 6 to 9 for the Weapons Factory, Medium Tank and Humvee) shifts every later offset
   automatically instead of silently desynchronising from the trainer. */
enum MaskOffset
{
    MASK_COMMAND = 0,
    MASK_ACTOR = MASK_COMMAND + TD_MICRO_POLICY_COMMAND_COUNT,
    MASK_PRODUCT = MASK_ACTOR + TD_MICRO_POLICY_ACTOR_COUNT,
    MASK_TARGET_KIND = MASK_PRODUCT + TD_MICRO_POLICY_PRODUCT_COUNT,
    MASK_TARGET_X = MASK_TARGET_KIND + TD_MICRO_POLICY_TARGET_KIND_COUNT,
    MASK_TARGET_Y = MASK_TARGET_X + TD_MICRO_POLICY_COORDINATE_COUNT,
    MASK_TARGET_SLOT = MASK_TARGET_Y + TD_MICRO_POLICY_COORDINATE_COUNT,
};
static_assert(MASK_TARGET_SLOT + TD_MICRO_POLICY_TARGET_SLOT_COUNT == TD_MICRO_ABI9_ACTION_MASK_SIZE,
              "ABI9 mask offsets must sum to the exported mask size");

struct PolicyRuntime
{
    TdMicroPolicy* policy;
    /* Exactly one of policy / policy_abi14 is non-NULL, chosen by checkpoint size at load. */
    TdMicroPolicyAbi14* policy_abi14;
    bool use_abi14;
    FILE* telemetry;
    FILE* state_trace;
    FILE* action_trace;
    FILE* frame_trace;
    bool attempted_load;
    bool failed;
    bool waiting_logged;
    bool ready_logged;
    bool tiberium_field_ready;
    TDMicroPolicyOutcome outcome;
    int last_frame;
    uint64_t decisions;
    uint64_t accepted;
    uint64_t changed;
    uint32_t previous_tank_count;
    uint32_t current_tank_count;
    uint64_t medium_tanks_built;
    uint64_t tank_shots;
    uint8_t observation[TD_MICRO_OBSERVATION_SIZE];
    uint8_t mask[TD_MICRO_ACTION_MASK_SIZE];
};

PolicyRuntime Runtime = {};

uint8_t Clip_U8(int value)
{
    if (value <= 0) return 0;
    return static_cast<uint8_t>(value >= 255 ? 255 : value);
}

HouseClass* Logical_House(uint8_t owner)
{
    if (owner < MPlayerCount) return HouseClass::As_Pointer(MPlayerHouses[owner]);
    if (TDMicro.Enabled() && MPlayerCount == 1 && MPlayerGhosts == 1 && owner == 1) {
        return HouseClass::As_Pointer(HOUSE_MULTI1);
    }
    return NULL;
}

int Logical_Player_Count()
{
    if (TDMicro.Enabled() && MPlayerCount == 1 && MPlayerGhosts == 1) return TD_MICRO_PLAYER_COUNT;
    if (GameToPlay == GAME_SKIRMISH) return MPlayerCount + MPlayerGhosts;
    return MPlayerCount;
}

bool Policy_World_Ready()
{
    return Logical_Player_Count() == TD_MICRO_PLAYER_COUNT && Logical_House(0) != NULL && Logical_House(1) != NULL;
}

bool Ensure_Tiberium_Field()
{
    if (Runtime.tiberium_field_ready) return true;
    for (unsigned int index = 0; index < TD_MICRO_INITIAL_TIBERIUM_CELL_COUNT; ++index) {
        const uint16_t local_cell = TD_MICRO_INITIAL_TIBERIUM_CELLS[index];
        const CELL cell_number =
            XY_Cell(Map.MapCellX + local_cell % 64, Map.MapCellY + local_cell / 64);
        CellClass& cell = Map[cell_number];
        if (cell.Land_Type() != LAND_TIBERIUM) {
            if (cell.Overlay != OVERLAY_NONE) {
                std::fprintf(stderr,
                             "TD Micro policy: Tiberium fixture blocked index=%u cell=%d land=%d overlay=%d\n",
                             index,
                             cell_number,
                             cell.Land_Type(),
                             cell.Overlay);
                return false;
            }
            /* OverlayClass::Mark rejects several scenario-1 field cells because the executable's
               multiplayer loader exposes their underlying ground as non-buildable after omitting
               the overlay. Restore the pinned map cell directly, exactly as loading the scenario
               overlay table would have done. */
            cell.Overlay = static_cast<OverlayType>(TD_MICRO_INITIAL_TIBERIUM_OVERLAYS[index]);
        }
        cell.OverlayData = TD_MICRO_INITIAL_TIBERIUM_DATA[index];
        cell.Recalc_Attributes();
        cell.Redraw_Objects();
        if (cell.Land_Type() != LAND_TIBERIUM) return false;
    }
    Runtime.tiberium_field_ready = true;
    return true;
}

uint8_t Unit_Kind(UnitClass const* unit)
{
    switch (unit->Class->Type) {
    case UNIT_MCV:
        return TD_MICRO_OBJECT_MCV;
    case UNIT_HARVESTER:
        return TD_MICRO_OBJECT_HARVESTER;
    case UNIT_MTANK:
        return TD_MICRO_OBJECT_MEDIUM_TANK;
    case UNIT_JEEP:
        return TD_MICRO_OBJECT_HUMVEE;
    default:
        return TD_MICRO_OBJECT_NONE;
    }
}

uint8_t Building_Kind(BuildingClass const* building)
{
    switch (building->Class->Type) {
    case STRUCT_CONST:
        return TD_MICRO_OBJECT_CONSTRUCTION_YARD;
    case STRUCT_POWER:
        return TD_MICRO_OBJECT_POWER_PLANT;
    case STRUCT_BARRACKS:
        return TD_MICRO_OBJECT_BARRACKS;
    case STRUCT_REFINERY:
        return TD_MICRO_OBJECT_REFINERY;
    case STRUCT_WEAP:
        return TD_MICRO_OBJECT_WEAPONS_FACTORY;
    default:
        return TD_MICRO_OBJECT_NONE;
    }
}

uint8_t Infantry_Kind(InfantryClass const* infantry)
{
    switch (infantry->Class->Type) {
    case INFANTRY_E1:
        return TD_MICRO_OBJECT_E1;
    case INFANTRY_E3:
        return TD_MICRO_OBJECT_E3;
    default:
        return TD_MICRO_OBJECT_NONE;
    }
}

bool Is_Live(TechnoClass const* techno)
{
    return techno->IsActive && !techno->IsInLimbo && techno->Strength > 0;
}

FactoryClass* Factory_For(HouseClass* house, RTTIType product_type)
{
    FactoryClass* factory = house->Fetch_Factory(product_type == RTTI_BUILDINGTYPE ? RTTI_BUILDING : RTTI_INFANTRY);
    if (factory != NULL) return factory;
    for (int index = 0; index < Buildings.Count(); ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        if (building->House == house && Is_Live(building) && building->Class->ToBuild == product_type
            && building->Factory != NULL) {
            return building->Factory;
        }
    }
    return NULL;
}

bool Has_Operational_Factory(HouseClass* house, RTTIType product_type)
{
    for (int index = 0; index < Buildings.Count(); ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        if (building->House == house && Is_Live(building) && building->Class->ToBuild == product_type
            && building->Mission != MISSION_CONSTRUCTION && building->Mission != MISSION_DECONSTRUCTION) {
            return true;
        }
    }
    return false;
}

uint8_t Product_Kind(TechnoClass const* product)
{
    if (product == NULL) return TD_MICRO_OBJECT_NONE;
    if (product->What_Am_I() == RTTI_BUILDING) return Building_Kind(static_cast<BuildingClass const*>(product));
    if (product->What_Am_I() == RTTI_INFANTRY) return Infantry_Kind(static_cast<InfantryClass const*>(product));
    return TD_MICRO_OBJECT_NONE;
}

void Encode_Queue(uint8_t* output, HouseClass* house, RTTIType product_type)
{
    FactoryClass* factory = Factory_For(house, product_type);
    if (factory == NULL) return;
    TechnoClass* product = factory->Get_Object();
    output[0] = product != NULL;
    output[1] = factory->Has_Completed();
    output[2] = Product_Kind(product);
    output[3] = Clip_U8(factory->Completion() * 255 / 108);
    output[4] = Clip_U8(factory->TDMicro_Stage_Timer());
}

int Active_Count(uint8_t owner, TDMicroObjectCategory category)
{
    HouseClass* house = Logical_House(owner);
    if (house == NULL) return 0;
    int count = 0;
    if (category == TD_MICRO_CATEGORY_UNIT) {
        for (int index = 0; index < Units.Count(); ++index)
            if (Units.Ptr(index)->House == house && Is_Live(Units.Ptr(index))) ++count;
    } else if (category == TD_MICRO_CATEGORY_BUILDING) {
        for (int index = 0; index < Buildings.Count(); ++index)
            if (Buildings.Ptr(index)->House == house && Is_Live(Buildings.Ptr(index))) ++count;
    } else if (category == TD_MICRO_CATEGORY_INFANTRY) {
        for (int index = 0; index < Infantry.Count(); ++index)
            if (Infantry.Ptr(index)->House == house && Is_Live(Infantry.Ptr(index))) ++count;
    }
    return count;
}

void Encode_Globals(uint8_t* output, uint8_t owner)
{
    HouseClass* player = Logical_House(owner);
    HouseClass* enemy = Logical_House(owner == 0 ? 1 : 0);
    output[0] = TD_MICRO_OBSERVATION_VERSION;
    output[1] = Clip_U8(Map.MapCellWidth);
    output[2] = Clip_U8(Map.MapCellHeight);
    output[3] = Clip_U8(Frame / 32);
    output[4] = Clip_U8(player->Credits / 100);
    output[5] = Clip_U8(player->Power);
    output[6] = Clip_U8(player->Drain);
    output[7] = player->IsDefeated;
    output[8] = enemy->IsDefeated;
    output[9] = TDMicro.Had_Content_Violation();
    Encode_Queue(output + 10, player, RTTI_BUILDINGTYPE);
    Encode_Queue(output + 15, player, RTTI_INFANTRYTYPE);
    output[20] = Clip_U8(Active_Count(owner, TD_MICRO_CATEGORY_UNIT));
    output[21] = Clip_U8(Active_Count(owner, TD_MICRO_CATEGORY_BUILDING));
    output[22] = Clip_U8(Active_Count(owner, TD_MICRO_CATEGORY_INFANTRY));
    output[23] = Clip_U8(Active_Count(owner == 0 ? 1 : 0, TD_MICRO_CATEGORY_UNIT));
    output[24] = Clip_U8(Active_Count(owner == 0 ? 1 : 0, TD_MICRO_CATEGORY_BUILDING));
    output[25] = Clip_U8(Active_Count(owner == 0 ? 1 : 0, TD_MICRO_CATEGORY_INFANTRY));
    output[26] = Clip_U8(player->Tiberium / 25);
    output[27] = Clip_U8(player->Capacity / 25);
    output[28] = Clip_U8(player->HarvestedCredits / 25);
    output[29] = Clip_U8(enemy->Tiberium / 25);
    output[30] = Clip_U8(enemy->Capacity / 25);
    int tiberium_steps = 0;
    for (int y = 0; y < Map.MapCellHeight; ++y) {
        for (int x = 0; x < Map.MapCellWidth; ++x) {
            CellClass const& cell = Map[XY_Cell(Map.MapCellX + x, Map.MapCellY + y)];
            if (cell.Land_Type() == LAND_TIBERIUM) tiberium_steps += cell.OverlayData;
        }
    }
    output[31] = Clip_U8(tiberium_steps);
    output[32] = TD_MICRO_SCENARIO_ID;
    output[TD_MICRO_OBSERVATION_DIFFICULTY_OFFSET] =
        Clip_U8(TDMicro.Opponent_Difficulty());
}

void Encode_Tiberium(uint8_t* output)
{
    for (unsigned int index = 0; index < TD_MICRO_INITIAL_TIBERIUM_CELL_COUNT; ++index) {
        const uint16_t map_cell = TD_MICRO_INITIAL_TIBERIUM_CELLS[index];
        const int x = map_cell % 64;
        const int y = map_cell / 64;
        CellClass const& cell = Map[XY_Cell(Map.MapCellX + x, Map.MapCellY + y)];
        output[index] = cell.Land_Type() == LAND_TIBERIUM
            ? static_cast<uint8_t>(LAND_TIBERIUM | TD_MICRO_MAP_PASSABLE_BIT | TD_MICRO_MAP_VISIBLE_BIT)
            : static_cast<uint8_t>(TD_MICRO_MAP_PASSABLE_BIT | TD_MICRO_MAP_BUILDABLE_BIT
                                   | TD_MICRO_MAP_VISIBLE_BIT);
    }
}

uint8_t Health_Fraction(TechnoClass const* techno)
{
    const int maximum = techno->Class_Of().MaxStrength;
    if (maximum <= 0 || techno->Strength <= 0) return 0;
    return Clip_U8(techno->Strength * 255 / maximum);
}

void Encode_Entity_Base(uint8_t* output, TechnoClass const* techno, uint8_t kind, uint16_t id, uint8_t category)
{
    output[ENTITY_PRESENT] = 1;
    output[ENTITY_TYPE] = kind;
    output[ENTITY_ID_LOW] = static_cast<uint8_t>(id);
    output[ENTITY_ID_HIGH] = static_cast<uint8_t>(id >> 8);
    output[ENTITY_X] = Clip_U8(Coord_XCell(techno->Coord) - Map.MapCellX);
    output[ENTITY_Y] = Clip_U8(Coord_YCell(techno->Coord) - Map.MapCellY);
    output[ENTITY_HEALTH] = Health_Fraction(techno);
    output[ENTITY_FACING] = static_cast<uint8_t>(techno->PrimaryFacing.Current());
    output[ENTITY_MISSION] = static_cast<uint8_t>(static_cast<int>(techno->Mission) + 1);
    output[ENTITY_CATEGORY] = category;
    if (kind < TD_MICRO_OBSERVATION_ENTITY_TYPE_COUNT) {
        output[TD_MICRO_OBSERVATION_ENTITY_TYPE_ONE_HOT_OFFSET + kind] = 255;
    }
}

uint8_t Building_Progress(BuildingClass const* building, uint8_t owner)
{
    if (building->Mission != MISSION_CONSTRUCTION) return 255;
    BuildingTypeClass::AnimControlType const& animation = building->Class->Anims[BSTATE_CONSTRUCTION];
    const int rate = building->Fetch_Rate();
    const int stage = building->Fetch_Stage() - animation.Start;
    int remaining = (animation.Count - stage - 1) * rate + building->Fetch_Stage_Timer();
    if (building->Class->Type == STRUCT_CONST) remaining += owner == 0 ? 1 : -3;
    const int canonical_frames = building->Class->Type == STRUCT_CONST ? 64 : 60;
    if (remaining < 0) remaining = 0;
    if (remaining > canonical_frames) remaining = canonical_frames;
    return static_cast<uint8_t>(255 - remaining * 255 / canonical_frames);
}

uint8_t Entity_Slot(TechnoClass const* target)
{
    if (target == NULL) return 0;
    HouseClass* house = target->House;
    uint8_t slot = 0;
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        if (unit->House != house || !Is_Live(unit)) continue;
        if (unit == target) return slot;
        ++slot;
    }
    for (int index = 0; index < Buildings.Count(); ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        if (building->House != house || !Is_Live(building)) continue;
        if (building == target) return slot;
        ++slot;
    }
    for (int index = 0; index < Infantry.Count(); ++index) {
        InfantryClass* infantry = Infantry.Ptr(index);
        if (infantry->House != house || !Is_Live(infantry)) continue;
        if (infantry == target) return slot;
        ++slot;
    }
    return 0;
}

void Encode_Entities(uint8_t* output, uint8_t owner)
{
    HouseClass* house = Logical_House(owner);
    uint8_t slot = 0;
    uint16_t local_index = 0;
    for (int index = 0; index < Units.Count() && slot < TD_MICRO_OBSERVATION_ENTITY_SLOT_COUNT; ++index) {
        UnitClass* unit = Units.Ptr(index);
        if (unit->House != house || !Is_Live(unit)) continue;
        uint8_t* encoded = output + slot++ * TD_MICRO_OBSERVATION_ENTITY_SIZE;
        const uint16_t id = local_index < LEGACY_UNIT_COUNT
            ? local_index
            : static_cast<uint16_t>(ADDITIONAL_UNIT_ID_BASE + local_index - LEGACY_UNIT_COUNT);
        ++local_index;
        Encode_Entity_Base(encoded, unit, Unit_Kind(unit), id, 1);
        ObjectClass* target_object = As_Object(unit->TarCom);
        if (target_object != NULL && target_object->Is_Techno()) {
            TechnoClass* target = static_cast<TechnoClass*>(target_object);
            encoded[ENTITY_TARGET_KIND] = target->House == house ? TD_MICRO_TARGET_OWN_ENTITY
                                                                 : TD_MICRO_TARGET_VISIBLE_ENEMY;
            encoded[ENTITY_TARGET_SLOT] = Entity_Slot(target);
        }
        encoded[ENTITY_COOLDOWN] = unit->Class->Type == UNIT_HARVESTER
            ? Clip_U8(unit->TDMicro_Harvest_Timer())
            : Clip_U8(unit->Arm);
        encoded[ENTITY_FLAGS] = static_cast<uint8_t>((unit->IsDeploying ? 1 : 0)
                                                     | (unit->IsDriving ? 2 : 0)
                                                     | (unit->IsHarvesting ? 4 : 0)
                                                     | (unit->IsFiring ? 8 : 0));
        if (unit->Class->Type == UNIT_HARVESTER) {
            encoded[ENTITY_PROGRESS] =
                Clip_U8(static_cast<int>(unit->Tiberium) * 255 / UnitTypeClass::STEP_COUNT);
        } else if (unit->IsDeploying) {
            const int facing = static_cast<uint8_t>(unit->PrimaryFacing.Current());
            encoded[ENTITY_PROGRESS] = facing >= 146 ? static_cast<uint8_t>((facing - 146) / 5) : 0;
        } else if (unit->Class->Type == UNIT_MTANK || unit->Class->Type == UNIT_JEEP) {
            encoded[ENTITY_PROGRESS] = static_cast<uint8_t>(unit->SecondaryFacing.Current());
        }
        encoded[ENTITY_STATUS] = Clip_U8(unit->Status);
    }
    local_index = 0;
    for (int index = 0; index < Buildings.Count() && slot < TD_MICRO_OBSERVATION_ENTITY_SLOT_COUNT; ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        if (building->House != house || !Is_Live(building)) continue;
        uint8_t* encoded = output + slot++ * TD_MICRO_OBSERVATION_ENTITY_SIZE;
        Encode_Entity_Base(encoded,
                           building,
                           Building_Kind(building),
                           static_cast<uint16_t>(LEGACY_UNIT_COUNT + local_index++),
                           2);
        encoded[ENTITY_MISSION] = 1;
        const uint8_t progress = Building_Progress(building, owner);
        const bool operational = (building->Mission != MISSION_CONSTRUCTION
                                  && building->Mission != MISSION_DECONSTRUCTION)
            || progress == 255;
        encoded[ENTITY_FLAGS] = operational;
        encoded[ENTITY_PROGRESS] = operational ? 255 : progress;
    }
    local_index = 0;
    for (int index = 0; index < Infantry.Count() && slot < TD_MICRO_OBSERVATION_ENTITY_SLOT_COUNT; ++index) {
        InfantryClass* infantry = Infantry.Ptr(index);
        if (infantry->House != house || !Is_Live(infantry)) continue;
        uint8_t* encoded = output + slot++ * TD_MICRO_OBSERVATION_ENTITY_SIZE;
        Encode_Entity_Base(encoded,
                           infantry,
                           Infantry_Kind(infantry),
                           static_cast<uint16_t>(LEGACY_UNIT_COUNT + TD_MICRO_MAX_BUILDINGS + local_index++),
                           3);
        ObjectClass* target_object = As_Object(infantry->TarCom);
        if (target_object != NULL && target_object->Is_Techno()) {
            TechnoClass* target = static_cast<TechnoClass*>(target_object);
            encoded[ENTITY_TARGET_KIND] = target->House == house ? TD_MICRO_TARGET_OWN_ENTITY
                                                                 : TD_MICRO_TARGET_VISIBLE_ENEMY;
            encoded[ENTITY_TARGET_SLOT] = Entity_Slot(target);
        }
        encoded[ENTITY_COOLDOWN] = Clip_U8(infantry->Arm);
        encoded[ENTITY_FLAGS] = static_cast<uint8_t>((infantry->IsDriving ? 1 : 0)
                                                     | (infantry->IsFiring ? 2 : 0)
                                                     | (infantry->IsProne ? 4 : 0));
        encoded[ENTITY_PROGRESS] = infantry->Fear;
    }
}

void Encode_Observation(uint8_t owner, uint8_t* output)
{
    std::memset(output, 0, TD_MICRO_OBSERVATION_SIZE);
    Encode_Globals(output + OBS_GLOBAL, owner);
    Encode_Tiberium(output + OBS_TIBERIUM);
    Encode_Entities(output + OBS_OWN, owner);
    Encode_Entities(output + OBS_ENEMY, owner == 0 ? 1 : 0);
}

bool Can_Start_Structure(HouseClass* house, StructType type)
{
    /* Economy gate, mirroring policy_abi9.canStart: the barracks is withheld until a refinery
       exists so the opening is forced to power plant -> refinery -> barracks -> army. Must match
       the trainer exactly or the bridge offers actions the policy never saw. */
    if (type == STRUCT_BARRACKS) {
        bool has_refinery = false;
        for (int index = 0; index < Buildings.Count(); ++index) {
            BuildingClass* building = Buildings.Ptr(index);
            if (building->House == house && Is_Live(building) && building->Class->Type == STRUCT_REFINERY) {
                has_refinery = true;
                break;
            }
        }
        if (!has_refinery) return false;
    }
    FactoryClass* factory = Factory_For(house, RTTI_BUILDINGTYPE);
    return (factory == NULL || factory->Get_Object() == NULL) && Has_Operational_Factory(house, RTTI_BUILDINGTYPE)
        && house->Can_Build(type, house->ActLike);
}

bool Can_Train_Infantry(HouseClass* house, InfantryType type)
{
    FactoryClass* factory = Factory_For(house, RTTI_INFANTRYTYPE);
    return (factory == NULL || factory->Get_Object() == NULL) && Has_Operational_Factory(house, RTTI_INFANTRYTYPE)
        && house->Can_Build(type, house->ActLike);
}

/* Vehicles run on the Weapons Factory's own queue (RTTI_UNITTYPE), mirroring the .unit queue in
   policy_abi9.canStart. */
bool Can_Build_Vehicle(HouseClass* house, UnitType type)
{
    FactoryClass* factory = Factory_For(house, RTTI_UNITTYPE);
    return (factory == NULL || factory->Get_Object() == NULL) && Has_Operational_Factory(house, RTTI_UNITTYPE)
        && house->Can_Build(type, house->ActLike);
}

/* ABI13 action masks are a BITSET with per-command argument groups, not a byte-per-entry array
   with shared groups as ABI9 used. Every offset below comes from the generated header so this
   cannot silently drift again when the ABI changes; a size check alone does not catch that. */
static inline void Set_Mask_Bit(uint8_t* output, unsigned int bit_index)
{
    if (bit_index >= TD_MICRO_ACTION_MASK_BIT_COUNT) return;
    output[bit_index / 8] |= static_cast<uint8_t>(1u << (bit_index % 8));
}

static inline bool Mask_Group_Has_Any(uint8_t const* output, unsigned int base, unsigned int span)
{
    for (unsigned int i = 0; i < span; ++i) {
        const unsigned int bit = base + i;
        if (output[bit / 8] & (1u << (bit % 8))) return true;
    }
    return false;
}

void Encode_Action_Mask(uint8_t owner, uint8_t* output)
{
    std::memset(output, 0, TD_MICRO_ACTION_MASK_SIZE);
    HouseClass* house = Logical_House(owner);

    Set_Mask_Bit(output, TD_MICRO_MASK_PAD_BIT_OFFSET + TD_MICRO_POLICY_PAD_TOKEN);
    Set_Mask_Bit(output, TD_MICRO_MASK_COMMAND_BIT_OFFSET + TD_MICRO_COMMAND_NOOP);

    for (int x = 0; x < Map.MapCellWidth && x < TD_MICRO_POLICY_COORDINATE_COUNT; ++x)
        Set_Mask_Bit(output, TD_MICRO_MASK_MOVE_X_BIT_OFFSET + x);
    for (int y = 0; y < Map.MapCellHeight && y < TD_MICRO_POLICY_COORDINATE_COUNT; ++y)
        Set_Mask_Bit(output, TD_MICRO_MASK_MOVE_Y_BIT_OFFSET + y);

    /* One slot counter spans units, then buildings, then infantry, matching policy.zig. */
    uint16_t slot = 0;
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        if (unit->House != house || !Is_Live(unit)) continue;
        if (slot < TD_MICRO_POLICY_TARGET_SLOT_COUNT) {
            if (unit->Class->Type == UNIT_MCV && !unit->IsDeploying) {
                Set_Mask_Bit(output, TD_MICRO_MASK_DEPLOY_ACTOR_BIT_OFFSET + slot);
            } else if (unit->Class->Type == UNIT_MTANK || unit->Class->Type == UNIT_JEEP) {
                Set_Mask_Bit(output, TD_MICRO_MASK_MOVE_ACTOR_BIT_OFFSET + slot);
                Set_Mask_Bit(output, TD_MICRO_MASK_ATTACK_ACTOR_BIT_OFFSET + slot);
            } else if (unit->Class->Type == UNIT_HARVESTER) {
                /* Harvesters run the autonomous Vanilla harvest/return loop. Training withholds
                   policy actor commands because a move order replaces that mission and strands
                   the economy. */
            }
        }
        ++slot;
    }
    for (int index = 0; index < Buildings.Count(); ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        if (building->House != house || !Is_Live(building)) continue;
        const bool operational = building->Mission != MISSION_CONSTRUCTION
            && building->Mission != MISSION_DECONSTRUCTION;
        if (slot < TD_MICRO_POLICY_TARGET_SLOT_COUNT && building->Class->Type == STRUCT_REFINERY
            && operational) {
            Set_Mask_Bit(output, TD_MICRO_MASK_RETURN_TARGET_BIT_OFFSET + slot);
        }
        ++slot;
    }
    for (int index = 0; index < Infantry.Count(); ++index) {
        InfantryClass* infantry = Infantry.Ptr(index);
        if (infantry->House != house || !Is_Live(infantry)) continue;
        if (slot < TD_MICRO_POLICY_TARGET_SLOT_COUNT) {
            Set_Mask_Bit(output, TD_MICRO_MASK_MOVE_ACTOR_BIT_OFFSET + slot);
            const InfantryType type = infantry->Class->Type;
            if (type == INFANTRY_E1 || type == INFANTRY_E3) {
                Set_Mask_Bit(output, TD_MICRO_MASK_ATTACK_ACTOR_BIT_OFFSET + slot);
            }
        }
        ++slot;
    }

    if (Can_Start_Structure(house, STRUCT_POWER))
        Set_Mask_Bit(output, TD_MICRO_MASK_BUILD_PRODUCT_BIT_OFFSET + TD_MICRO_POLICY_PRODUCT_POWER_PLANT);
    if (Can_Start_Structure(house, STRUCT_BARRACKS))
        Set_Mask_Bit(output, TD_MICRO_MASK_BUILD_PRODUCT_BIT_OFFSET + TD_MICRO_POLICY_PRODUCT_BARRACKS);
    if (Can_Start_Structure(house, STRUCT_REFINERY))
        Set_Mask_Bit(output, TD_MICRO_MASK_BUILD_PRODUCT_BIT_OFFSET + TD_MICRO_POLICY_PRODUCT_REFINERY);
    if (Can_Start_Structure(house, STRUCT_WEAP))
        Set_Mask_Bit(
            output,
            TD_MICRO_MASK_BUILD_PRODUCT_BIT_OFFSET + TD_MICRO_POLICY_PRODUCT_WEAPONS_FACTORY);
    if (Can_Build_Vehicle(house, UNIT_MTANK))
        Set_Mask_Bit(
            output,
            TD_MICRO_MASK_BUILD_PRODUCT_BIT_OFFSET + TD_MICRO_POLICY_PRODUCT_MEDIUM_TANK);
    if (Can_Build_Vehicle(house, UNIT_JEEP))
        Set_Mask_Bit(output, TD_MICRO_MASK_BUILD_PRODUCT_BIT_OFFSET + TD_MICRO_POLICY_PRODUCT_HUMVEE);
    if (Can_Train_Infantry(house, INFANTRY_E1))
        Set_Mask_Bit(output, TD_MICRO_MASK_TRAIN_PRODUCT_BIT_OFFSET + TD_MICRO_POLICY_PRODUCT_E1);
    if (Can_Train_Infantry(house, INFANTRY_E3))
        Set_Mask_Bit(output, TD_MICRO_MASK_TRAIN_PRODUCT_BIT_OFFSET + TD_MICRO_POLICY_PRODUCT_E3);

    /* Placement: only when a completed structure is waiting, and only on legal origins.
       PLACE_Y is two dimensional, conditioned on x. */
    FactoryClass* structure_factory = Factory_For(house, RTTI_BUILDINGTYPE);
    if (structure_factory != NULL && structure_factory->Has_Completed()) {
        TechnoClass* pending = structure_factory->Get_Object();
        if (pending != NULL && pending->What_Am_I() == RTTI_BUILDING) {
            BuildingClass* building = static_cast<BuildingClass*>(pending);
            short const* occupy = building->Class->Occupy_List();
            for (int y = 0; y < Map.MapCellHeight && y < TD_MICRO_POLICY_COORDINATE_COUNT; ++y) {
                for (int x = 0; x < Map.MapCellWidth && x < TD_MICRO_POLICY_COORDINATE_COUNT; ++x) {
                    const CELL cell = XY_Cell(Map.MapCellX + x, Map.MapCellY + y);
                    /* Mirror policy.zig legalOriginRows: every footprint cell must be in bounds,
                       unoccupied and free of tiberium, and the origin must pass proximity. Checking
                       only the origin cell advertises placements Place_Object then refuses. */
                    bool footprint_clear = true;
                    for (short const* offset = occupy; offset != NULL && *offset != REFRESH_EOL; ++offset) {
                        const CELL part = static_cast<CELL>(cell + *offset);
                        if (part < 0 || part >= MAP_CELL_TOTAL) { footprint_clear = false; break; }
                        CellClass& part_cell = Map[part];
                        if (!part_cell.Is_Generally_Clear()) { footprint_clear = false; break; }
                        if (part_cell.Land_Type() == LAND_TIBERIUM) { footprint_clear = false; break; }
                    }
                    if (!footprint_clear) continue;
                    if (!building->Passes_Proximity_Check(cell)) continue;
                    Set_Mask_Bit(output, TD_MICRO_MASK_PLACE_X_BIT_OFFSET + x);
                    Set_Mask_Bit(output,
                                 TD_MICRO_MASK_PLACE_Y_BIT_OFFSET
                                     + static_cast<unsigned int>(x) * TD_MICRO_POLICY_TOKEN_COUNT + y);
                }
            }
        }
    }

    const uint8_t enemy_owner = owner == 0 ? 1 : 0;
    int enemy_count = Active_Count(enemy_owner, TD_MICRO_CATEGORY_UNIT)
        + Active_Count(enemy_owner, TD_MICRO_CATEGORY_BUILDING)
        + Active_Count(enemy_owner, TD_MICRO_CATEGORY_INFANTRY);
    if (enemy_count > TD_MICRO_POLICY_TARGET_SLOT_COUNT) enemy_count = TD_MICRO_POLICY_TARGET_SLOT_COUNT;
    for (int target = 0; target < enemy_count; ++target)
        Set_Mask_Bit(output, TD_MICRO_MASK_ATTACK_TARGET_BIT_OFFSET + target);

    /* Harvest cells: tiberium still present. HARVEST_Y is conditioned on x like PLACE_Y. */
    for (int y = 0; y < Map.MapCellHeight && y < TD_MICRO_POLICY_COORDINATE_COUNT; ++y) {
        for (int x = 0; x < Map.MapCellWidth && x < TD_MICRO_POLICY_COORDINATE_COUNT; ++x) {
            const CELL cell = XY_Cell(Map.MapCellX + x, Map.MapCellY + y);
            if (Map[cell].Land_Type() != LAND_TIBERIUM) continue;
            Set_Mask_Bit(output, TD_MICRO_MASK_HARVEST_X_BIT_OFFSET + x);
            Set_Mask_Bit(output,
                         TD_MICRO_MASK_HARVEST_Y_BIT_OFFSET
                             + static_cast<unsigned int>(x) * TD_MICRO_POLICY_TOKEN_COUNT + y);
        }
    }

    /* Command legality is derived last, from group occupancy, exactly as policy.zig does. */
    const unsigned int span = TD_MICRO_POLICY_TOKEN_COUNT;
    if (Mask_Group_Has_Any(output, TD_MICRO_MASK_DEPLOY_ACTOR_BIT_OFFSET, span))
        Set_Mask_Bit(output, TD_MICRO_MASK_COMMAND_BIT_OFFSET + TD_MICRO_COMMAND_DEPLOY);
    if (Mask_Group_Has_Any(output, TD_MICRO_MASK_BUILD_PRODUCT_BIT_OFFSET, span))
        Set_Mask_Bit(output, TD_MICRO_MASK_COMMAND_BIT_OFFSET + TD_MICRO_COMMAND_START_BUILD);
    if (Mask_Group_Has_Any(output, TD_MICRO_MASK_PLACE_X_BIT_OFFSET, span))
        Set_Mask_Bit(output, TD_MICRO_MASK_COMMAND_BIT_OFFSET + TD_MICRO_COMMAND_PLACE);
    if (Mask_Group_Has_Any(output, TD_MICRO_MASK_TRAIN_PRODUCT_BIT_OFFSET, span))
        Set_Mask_Bit(output, TD_MICRO_MASK_COMMAND_BIT_OFFSET + TD_MICRO_COMMAND_TRAIN);
    if (Mask_Group_Has_Any(output, TD_MICRO_MASK_MOVE_ACTOR_BIT_OFFSET, span))
        Set_Mask_Bit(output, TD_MICRO_MASK_COMMAND_BIT_OFFSET + TD_MICRO_COMMAND_MOVE);
    if (Mask_Group_Has_Any(output, TD_MICRO_MASK_ATTACK_ACTOR_BIT_OFFSET, span)
        && Mask_Group_Has_Any(output, TD_MICRO_MASK_ATTACK_TARGET_BIT_OFFSET, span))
        Set_Mask_Bit(output, TD_MICRO_MASK_COMMAND_BIT_OFFSET + TD_MICRO_COMMAND_ATTACK);
    if (Mask_Group_Has_Any(output, TD_MICRO_MASK_HARVEST_ACTOR_BIT_OFFSET, span)
        && Mask_Group_Has_Any(output, TD_MICRO_MASK_HARVEST_X_BIT_OFFSET, span))
        Set_Mask_Bit(output, TD_MICRO_MASK_COMMAND_BIT_OFFSET + TD_MICRO_COMMAND_HARVEST);
    if (Mask_Group_Has_Any(output, TD_MICRO_MASK_RETURN_ACTOR_BIT_OFFSET, span)
        && Mask_Group_Has_Any(output, TD_MICRO_MASK_RETURN_TARGET_BIT_OFFSET, span))
        Set_Mask_Bit(output, TD_MICRO_MASK_COMMAND_BIT_OFFSET + TD_MICRO_COMMAND_RETURN_CARGO);
}

/* ---- ABI14 mask -------------------------------------------------------------------------- */
/*
 * ABI14 is byte-per-entry, not the ABI13 bitset, and its first 279 bytes are the ABI9 mask copied
 * verbatim (policy_abi14.zig:actionMask). So the encoder below is the historical ABI9 encoder plus
 * a short tail, rather than a third independent implementation of the mask.
 */
static_assert(TD_MICRO_ABI14_SELECTOR_MASK_OFFSET == TD_MICRO_ABI9_ACTION_MASK_SIZE,
              "ABI14 selectors must begin exactly where the ABI9 base mask ends");
static_assert(TD_MICRO_ABI14_SELECTOR_MASK_OFFSET + TD_MICRO_ABI14_SELECTOR_COUNT * 2
                  == TD_MICRO_ABI14_ATTACK_TARGET_MASK_OFFSET,
              "ABI14 attack targets must follow 64 two-entry selector heads");
static_assert(TD_MICRO_ABI14_ATTACK_TARGET_MASK_OFFSET + TD_MICRO_ABI14_SELECTOR_COUNT
                  == TD_MICRO_ABI14_ACTION_MASK_SIZE,
              "ABI14 mask must end after 64 attack-target entries");
static_assert(MASK_TARGET_SLOT + 64 == TD_MICRO_ABI9_ACTION_MASK_SIZE,
              "ABI9 mask offsets must sum to the exported ABI9 mask size");

void Encode_Action_Mask_Abi9(uint8_t owner, uint8_t* output)
{
    std::memset(output, 0, TD_MICRO_ABI9_ACTION_MASK_SIZE);
    HouseClass* house = Logical_House(owner);
    output[MASK_COMMAND + TD_MICRO_COMMAND_NOOP] = 1;
    output[MASK_ACTOR + TD_MICRO_POLICY_ACTOR_NONE] = 1;
    output[MASK_PRODUCT + TD_MICRO_POLICY_PRODUCT_NONE] = 1;
    output[MASK_TARGET_KIND + TD_MICRO_TARGET_NONE] = 1;
    for (int x = 0; x < Map.MapCellWidth && x < 64; ++x) output[MASK_TARGET_X + x] = 1;
    for (int y = 0; y < Map.MapCellHeight && y < 64; ++y) output[MASK_TARGET_Y + y] = 1;

    uint8_t slot = 0;
    bool has_harvester = false;
    bool has_vehicle = false;
    bool has_refinery = false;
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        if (unit->House != house || !Is_Live(unit)) continue;
        if (slot < 64 && unit->Class->Type == UNIT_MCV && !unit->IsDeploying) {
            output[MASK_ACTOR + slot] = 1;
            output[MASK_COMMAND + TD_MICRO_COMMAND_DEPLOY] = 1;
        } else if (slot < 64
                   && (unit->Class->Type == UNIT_MTANK || unit->Class->Type == UNIT_JEEP)) {
            /* CNC26 combat vehicles are controllable exactly like infantry, matching
               policy_abi9.actionMask. Without an actor slot a purchased tank could never be moved
               or ordered to fire. */
            output[MASK_ACTOR + slot] = 1;
            has_vehicle = true;
        } else if (slot < 64 && unit->Class->Type == UNIT_HARVESTER) {
            /* The policy cannot control the harvester at all, mirroring policy_abi9.actionMask: no
               actor slot and no commands. TD assigns a new harvester its harvest mission and it
               mines the nearest tiberium unaided; exposing it let the policy issue move orders that
               pulled it off the field and destroyed the economy. */
        }
        ++slot;
    }
    for (int index = 0; index < Buildings.Count(); ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        if (building->House != house || !Is_Live(building)) continue;
        if (slot < 64 && building->Class->Type == STRUCT_REFINERY && building->Mission != MISSION_CONSTRUCTION
            && building->Mission != MISSION_DECONSTRUCTION) {
            output[MASK_TARGET_SLOT + slot] = 1;
            has_refinery = true;
        }
        ++slot;
    }
    bool has_infantry = false;
    for (int index = 0; index < Infantry.Count(); ++index) {
        InfantryClass* infantry = Infantry.Ptr(index);
        if (infantry->House != house || !Is_Live(infantry)) continue;
        if (slot < 64) output[MASK_ACTOR + slot] = 1;
        ++slot;
        has_infantry = true;
    }

    const uint8_t enemy_owner = owner == 0 ? 1 : 0;
    const int enemy_count = Active_Count(enemy_owner, TD_MICRO_CATEGORY_UNIT)
                            + Active_Count(enemy_owner, TD_MICRO_CATEGORY_BUILDING)
                            + Active_Count(enemy_owner, TD_MICRO_CATEGORY_INFANTRY);
    if (has_infantry || has_vehicle || has_harvester) {
        output[MASK_COMMAND + TD_MICRO_COMMAND_MOVE] = 1;
        output[MASK_TARGET_KIND + TD_MICRO_TARGET_CELL] = 1;
    }
    if (has_harvester) {
        output[MASK_COMMAND + TD_MICRO_COMMAND_HARVEST] = 1;
        output[MASK_TARGET_KIND + TD_MICRO_TARGET_CELL] = 1;
        if (has_refinery) {
            output[MASK_COMMAND + TD_MICRO_COMMAND_RETURN_CARGO] = 1;
            output[MASK_TARGET_KIND + TD_MICRO_TARGET_OWN_ENTITY] = 1;
        }
    }
    if ((has_infantry || has_vehicle) && enemy_count != 0) {
        output[MASK_COMMAND + TD_MICRO_COMMAND_ATTACK] = 1;
        output[MASK_TARGET_KIND + TD_MICRO_TARGET_VISIBLE_ENEMY] = 1;
    }

    if (Can_Start_Structure(house, STRUCT_POWER)) {
        output[MASK_COMMAND + TD_MICRO_COMMAND_START_BUILD] = 1;
        output[MASK_PRODUCT + TD_MICRO_POLICY_PRODUCT_POWER_PLANT] = 1;
    }
    if (Can_Start_Structure(house, STRUCT_BARRACKS)) {
        output[MASK_COMMAND + TD_MICRO_COMMAND_START_BUILD] = 1;
        output[MASK_PRODUCT + TD_MICRO_POLICY_PRODUCT_BARRACKS] = 1;
    }
    if (Can_Start_Structure(house, STRUCT_REFINERY)) {
        output[MASK_COMMAND + TD_MICRO_COMMAND_START_BUILD] = 1;
        output[MASK_PRODUCT + TD_MICRO_POLICY_PRODUCT_REFINERY] = 1;
    }
    if (Can_Train_Infantry(house, INFANTRY_E1)) {
        output[MASK_COMMAND + TD_MICRO_COMMAND_TRAIN] = 1;
        output[MASK_PRODUCT + TD_MICRO_POLICY_PRODUCT_E1] = 1;
    }
    if (Can_Train_Infantry(house, INFANTRY_E3)) {
        output[MASK_COMMAND + TD_MICRO_COMMAND_TRAIN] = 1;
        output[MASK_PRODUCT + TD_MICRO_POLICY_PRODUCT_E3] = 1;
    }
    if (Can_Start_Structure(house, STRUCT_WEAP)) {
        output[MASK_COMMAND + TD_MICRO_COMMAND_START_BUILD] = 1;
        output[MASK_PRODUCT + TD_MICRO_POLICY_PRODUCT_WEAPONS_FACTORY] = 1;
    }
    /* start_build, not train: production.buildQueueKind routes by category, sending vehicles to
       the Weapons Factory queue and keeping train for infantry. Offering them under train made
       every such action fail, and the trainer now offers start_build -- the masks must agree or
       the policy sees a different action space in Vanilla than it trained on. */
    if (Can_Build_Vehicle(house, UNIT_MTANK)) {
        output[MASK_COMMAND + TD_MICRO_COMMAND_START_BUILD] = 1;
        output[MASK_PRODUCT + TD_MICRO_POLICY_PRODUCT_MEDIUM_TANK] = 1;
    }
    if (Can_Build_Vehicle(house, UNIT_JEEP)) {
        output[MASK_COMMAND + TD_MICRO_COMMAND_START_BUILD] = 1;
        output[MASK_PRODUCT + TD_MICRO_POLICY_PRODUCT_HUMVEE] = 1;
    }

    FactoryClass* structure_factory = Factory_For(house, RTTI_BUILDINGTYPE);
    if (structure_factory != NULL && structure_factory->Has_Completed()) {
        const uint8_t product = Product_Kind(structure_factory->Get_Object());
        uint8_t policy_product = TD_MICRO_POLICY_PRODUCT_NONE;
        if (product == TD_MICRO_OBJECT_POWER_PLANT) policy_product = TD_MICRO_POLICY_PRODUCT_POWER_PLANT;
        if (product == TD_MICRO_OBJECT_BARRACKS) policy_product = TD_MICRO_POLICY_PRODUCT_BARRACKS;
        if (product == TD_MICRO_OBJECT_REFINERY) policy_product = TD_MICRO_POLICY_PRODUCT_REFINERY;
        if (policy_product != TD_MICRO_POLICY_PRODUCT_NONE) {
            output[MASK_COMMAND + TD_MICRO_COMMAND_PLACE] = 1;
            output[MASK_PRODUCT + policy_product] = 1;
            output[MASK_TARGET_KIND + TD_MICRO_TARGET_CELL] = 1;
        }
    }

    for (int target = 0; target < enemy_count && target < 64; ++target) output[MASK_TARGET_SLOT + target] = 1;
    /* Zig falls back to slot 0 only when the whole group is empty, which the refinery return slot
     * can already have populated. Testing enemy_count alone diverges in exactly that case. */
    bool has_target_slot = false;
    for (int target = 0; target < 64; ++target) has_target_slot = has_target_slot || output[MASK_TARGET_SLOT + target] != 0;
    if (!has_target_slot) output[MASK_TARGET_SLOT] = 1;
}

void Encode_Action_Mask_Abi14(uint8_t owner, uint8_t* output)
{
    Encode_Action_Mask_Abi9(owner, output);
    std::memset(output + TD_MICRO_ABI14_SELECTOR_MASK_OFFSET,
                0,
                TD_MICRO_ABI14_ACTION_MASK_SIZE - TD_MICRO_ABI14_SELECTOR_MASK_OFFSET);

    /* Deselecting is always legal, so entry 0 of every selector head is unconditionally set. */
    for (unsigned int index = 0; index < TD_MICRO_ABI14_SELECTOR_COUNT; ++index) {
        output[TD_MICRO_ABI14_SELECTOR_MASK_OFFSET + index * 2] = 1;
    }

    HouseClass* house = Logical_House(owner);
    /* One slot counter walked in the same units -> buildings -> infantry order as the ABI9 mask and
     * the entity observation, so selector N addresses observation entity N. */
    unsigned int slot = 0;
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        if (unit->House != house || !Is_Live(unit)) continue;
        ++slot;
    }
    for (int index = 0; index < Buildings.Count(); ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        if (building->House != house || !Is_Live(building)) continue;
        ++slot;
    }
    for (int index = 0; index < Infantry.Count(); ++index) {
        InfantryClass* infantry = Infantry.Ptr(index);
        if (infantry->House != house || !Is_Live(infantry)) continue;
        const InfantryType type = infantry->Class->Type;
        if (slot < TD_MICRO_ABI14_SELECTOR_COUNT && (type == INFANTRY_E1 || type == INFANTRY_E3)) {
            output[TD_MICRO_ABI14_SELECTOR_MASK_OFFSET + slot * 2 + 1] = 1;
        }
        ++slot;
    }

    const uint8_t enemy_owner = owner == 0 ? 1 : 0;
    int enemy_count = Active_Count(enemy_owner, TD_MICRO_CATEGORY_UNIT)
                      + Active_Count(enemy_owner, TD_MICRO_CATEGORY_BUILDING)
                      + Active_Count(enemy_owner, TD_MICRO_CATEGORY_INFANTRY);
    if (enemy_count > (int)TD_MICRO_ABI14_SELECTOR_COUNT) enemy_count = (int)TD_MICRO_ABI14_SELECTOR_COUNT;
    for (int target = 0; target < enemy_count; ++target) {
        output[TD_MICRO_ABI14_ATTACK_TARGET_MASK_OFFSET + target] = 1;
    }
}

uint64_t Fingerprint_State()
{
    uint64_t hash = 1469598103934665603ULL;
#define MIX_VALUE(value)                                                                                              \
    do {                                                                                                              \
        uint64_t mixed_value = static_cast<uint64_t>(value);                                                          \
        for (unsigned byte = 0; byte < sizeof(mixed_value); ++byte) {                                                 \
            hash ^= static_cast<uint8_t>(mixed_value >> (byte * 8));                                                  \
            hash *= 1099511628211ULL;                                                                                 \
        }                                                                                                             \
    } while (0)
    for (int owner = 0; owner < Logical_Player_Count(); ++owner) {
        HouseClass* house = Logical_House(static_cast<uint8_t>(owner));
        MIX_VALUE(house->Credits);
        MIX_VALUE(house->Tiberium);
        MIX_VALUE(house->Capacity);
        MIX_VALUE(house->HarvestedCredits);
        MIX_VALUE(house->Power);
        MIX_VALUE(house->Drain);
    }
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        MIX_VALUE(unit->Mission);
        MIX_VALUE(unit->MissionQueue);
        MIX_VALUE(unit->Status);
        MIX_VALUE(unit->IsDeploying);
        MIX_VALUE(unit->IsHarvesting);
        MIX_VALUE(unit->Tiberium);
        MIX_VALUE(unit->Coord);
    }
    for (int index = 0; index < Buildings.Count(); ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        MIX_VALUE(building->Class->Type);
        MIX_VALUE(building->Mission);
        MIX_VALUE(building->Coord);
    }
    for (int index = 0; index < Infantry.Count(); ++index) {
        InfantryClass* infantry = Infantry.Ptr(index);
        MIX_VALUE(infantry->Class->Type);
        MIX_VALUE(infantry->Mission);
        MIX_VALUE(infantry->MissionQueue);
        MIX_VALUE(infantry->TarCom);
        MIX_VALUE(infantry->NavCom);
    }
    for (int index = 0; index < Factories.Count(); ++index) {
        FactoryClass* factory = Factories.Ptr(index);
        MIX_VALUE(factory->Get_Object() != NULL);
        MIX_VALUE(factory->Completion());
    }
    for (int y = 0; y < Map.MapCellHeight; ++y) {
        for (int x = 0; x < Map.MapCellWidth; ++x) {
            CellClass const& cell = Map[XY_Cell(Map.MapCellX + x, Map.MapCellY + y)];
            MIX_VALUE(cell.Land_Type());
            MIX_VALUE(cell.OverlayData);
        }
    }
#undef MIX_VALUE
    return hash;
}

uint8_t Policy_Product_To_Object(uint8_t product)
{
    switch (product) {
    case TD_MICRO_POLICY_PRODUCT_POWER_PLANT:
        return TD_MICRO_OBJECT_POWER_PLANT;
    case TD_MICRO_POLICY_PRODUCT_BARRACKS:
        return TD_MICRO_OBJECT_BARRACKS;
    case TD_MICRO_POLICY_PRODUCT_REFINERY:
        return TD_MICRO_OBJECT_REFINERY;
    case TD_MICRO_POLICY_PRODUCT_E1:
        return TD_MICRO_OBJECT_E1;
    case TD_MICRO_POLICY_PRODUCT_E3:
        return TD_MICRO_OBJECT_E3;
    case TD_MICRO_POLICY_PRODUCT_WEAPONS_FACTORY:
        return TD_MICRO_OBJECT_WEAPONS_FACTORY;
    case TD_MICRO_POLICY_PRODUCT_MEDIUM_TANK:
        return TD_MICRO_OBJECT_MEDIUM_TANK;
    case TD_MICRO_POLICY_PRODUCT_HUMVEE:
        return TD_MICRO_OBJECT_HUMVEE;
    default:
        return TD_MICRO_OBJECT_NONE;
    }
}

bool Decode_Policy_Action(TdMicroPolicyAction const& source, HouseClass* house, TdMicroAction& output)
{
    std::memset(&output, 0, sizeof(output));
    output.command = source.command;
    switch (source.command) {
    case TD_MICRO_COMMAND_NOOP:
        return true;
    case TD_MICRO_COMMAND_DEPLOY:
        output.actor = source.arg0;
        return true;
    case TD_MICRO_COMMAND_START_BUILD:
    case TD_MICRO_COMMAND_TRAIN:
        output.product = Policy_Product_To_Object(source.arg0);
        return output.product != TD_MICRO_OBJECT_NONE;
    case TD_MICRO_COMMAND_PLACE: {
        FactoryClass* factory = Factory_For(house, RTTI_BUILDINGTYPE);
        output.product = factory != NULL && factory->Has_Completed()
            ? Product_Kind(factory->Get_Object())
            : TD_MICRO_OBJECT_NONE;
        output.target_kind = TD_MICRO_TARGET_CELL;
        output.target_x = source.arg0;
        output.target_y = source.arg1;
        return output.product != TD_MICRO_OBJECT_NONE;
    }
    case TD_MICRO_COMMAND_MOVE:
    case TD_MICRO_COMMAND_HARVEST:
        output.actor = source.arg0;
        output.target_kind = TD_MICRO_TARGET_CELL;
        output.target_x = source.arg1;
        output.target_y = source.arg2;
        return true;
    case TD_MICRO_COMMAND_ATTACK:
        output.actor = source.arg0;
        output.target_kind = TD_MICRO_TARGET_VISIBLE_ENEMY;
        output.target_slot = source.arg1;
        return true;
    case TD_MICRO_COMMAND_RETURN_CARGO:
        output.actor = source.arg0;
        output.target_kind = TD_MICRO_TARGET_OWN_ENTITY;
        output.target_slot = source.arg1;
        return true;
    default:
        return false;
    }
}

/*
 * ABI14 decode for everything except ATTACK, which the group path owns.
 *
 * ABI14's non-selector fields are ABI9's seven independent heads, not ABI13's packed arg0/arg1/arg2,
 * so this reads named fields rather than positional args. policy_abi14.apply delegates the same set
 * of commands to policy_abi9.decode.
 */
bool Decode_Policy_Action_Abi14(TdMicroPolicyActionAbi14 const& source, HouseClass* house, TdMicroAction& output)
{
    std::memset(&output, 0, sizeof(output));
    output.command = source.command;
    switch (source.command) {
    case TD_MICRO_COMMAND_NOOP:
        return true;
    case TD_MICRO_COMMAND_DEPLOY:
        output.actor = source.actor;
        return true;
    case TD_MICRO_COMMAND_START_BUILD:
    case TD_MICRO_COMMAND_TRAIN:
        output.product = Policy_Product_To_Object(source.product);
        return output.product != TD_MICRO_OBJECT_NONE;
    case TD_MICRO_COMMAND_PLACE: {
        FactoryClass* factory = Factory_For(house, RTTI_BUILDINGTYPE);
        output.product = factory != NULL && factory->Has_Completed() ? Product_Kind(factory->Get_Object())
                                                                    : TD_MICRO_OBJECT_NONE;
        output.target_kind = TD_MICRO_TARGET_CELL;
        output.target_x = source.target_x;
        output.target_y = source.target_y;
        return output.product != TD_MICRO_OBJECT_NONE;
    }
    case TD_MICRO_COMMAND_MOVE:
    case TD_MICRO_COMMAND_HARVEST:
        output.actor = source.actor;
        output.target_kind = TD_MICRO_TARGET_CELL;
        output.target_x = source.target_x;
        output.target_y = source.target_y;
        return true;
    case TD_MICRO_COMMAND_RETURN_CARGO:
        output.actor = source.actor;
        output.target_kind = TD_MICRO_TARGET_OWN_ENTITY;
        output.target_slot = source.target_slot;
        return true;
    default:
        return false;
    }
}

void Print_Hex(FILE* output, uint8_t const* bytes, size_t count)
{
    for (size_t index = 0; index < count; ++index) std::fprintf(output, "%02x", bytes[index]);
}

int Hex_Nibble(char value)
{
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    if (value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}

bool Rules_Hash_Matches()
{
    uint8_t actual[TD_MICRO_RULESET_HASH_SIZE];
    if (td_micro_ruleset_hash(actual, sizeof(actual)) != sizeof(actual)) return false;
    const char* expected = TD_MICRO_MANIFEST_SHA256;
    for (size_t index = 0; index < sizeof(actual); ++index) {
        const int high = Hex_Nibble(expected[index * 2]);
        const int low = Hex_Nibble(expected[index * 2 + 1]);
        if (high < 0 || low < 0 || actual[index] != static_cast<uint8_t>((high << 4) | low)) return false;
    }
    return true;
}

/*
 * Reads the whole checkpoint rather than a fixed expected size, so Load_Policy can pick the ABI
 * from the file itself. ABI13 and ABI14 share a trunk and differ only in decoder width, so their
 * sizes are distinct and an exact size match identifies the format unambiguously. Selecting the ABI
 * from the artifact removes the chance of a flag disagreeing with the file it points at.
 */
bool Read_Checkpoint(char const* path, std::vector<uint8_t>& bytes)
{
    if (path == NULL || path[0] == '\0') return false;
    FILE* file = std::fopen(path, "rb");
    if (file == NULL) return false;
    if (std::fseek(file, 0, SEEK_END) != 0) {
        std::fclose(file);
        return false;
    }
    const long size = std::ftell(file);
    if (size <= 0 || std::fseek(file, 0, SEEK_SET) != 0) {
        std::fclose(file);
        return false;
    }
    bytes.resize(static_cast<size_t>(size));
    const bool ok = std::fread(&bytes[0], 1, bytes.size(), file) == bytes.size();
    std::fclose(file);
    return ok;
}

void Mark_Policy_Failure(char const* reason)
{
    Runtime.failed = true;
    if (Runtime.telemetry != NULL) {
        std::fprintf(Runtime.telemetry, "failure reason=%s\n", reason);
        std::fflush(Runtime.telemetry);
    }
}

bool Load_Policy()
{
    Runtime.attempted_load = true;
    Runtime.telemetry = std::fopen("td_micro_policy.log", "w");
    Runtime.state_trace = std::fopen("td_micro_policy_state_live.bin", "wb");
    const char* action_trace_path = std::getenv("TD_MICRO_POLICY_ACTION_TRACE");
    if (action_trace_path != NULL && action_trace_path[0] != '\0') {
        Runtime.action_trace = std::fopen(action_trace_path, "wb");
        if (Runtime.action_trace == NULL) {
            Mark_Policy_Failure("action_trace_open");
            return false;
        }
    }
    const char* frame_trace_path = std::getenv("TD_MICRO_PARITY_FRAME_TRACE");
    if (frame_trace_path != NULL && frame_trace_path[0] != '\0') {
        Runtime.frame_trace = std::fopen(frame_trace_path, "w");
    }
    if (td_micro_abi_version() != TD_MICRO_ABI_VERSION
        || td_micro_observation_size() != TD_MICRO_OBSERVATION_SIZE
        || td_micro_action_mask_size() != TD_MICRO_ACTION_MASK_SIZE
        || td_micro_action_mask_size_abi14() != TD_MICRO_ABI14_ACTION_MASK_SIZE
        || td_micro_policy_checkpoint_size() != TD_MICRO_POLICY_CHECKPOINT_SIZE || !Rules_Hash_Matches()) {
        Mark_Policy_Failure("schema_mismatch");
        std::fprintf(stderr, "TD Micro policy: runtime schema mismatch\n");
        return false;
    }
    uint64_t policy_sampling_seed = 0;
    if (!TDMicro.Policy_Sampling_Seed(policy_sampling_seed)) {
        Mark_Policy_Failure("invalid_sampling_seed");
        std::fprintf(stderr, "TD Micro policy: invalid TD_MICRO_POLICY_SAMPLE_SEED\n");
        return false;
    }

    std::vector<uint8_t> checkpoint;
    if (!Read_Checkpoint(TDMicro.Policy_Path(), checkpoint)) {
        Mark_Policy_Failure("checkpoint_read");
        std::fprintf(stderr, "TD Micro policy: cannot read exact-size checkpoint %s\n", TDMicro.Policy_Path());
        return false;
    }
    const uint32_t checkpoint_size = static_cast<uint32_t>(checkpoint.size());
    /* ABI13 and ABI14 both shipped at hidden 64 and 128. Exact byte length selects the ABI and
       width, so deployment cannot silently instantiate the wrong matrix shape. */
    const uint32_t abi13_hidden = td_micro_policy_hidden_for_checkpoint_size(checkpoint_size);
    const uint32_t abi14_hidden = td_micro_policy_abi14_hidden_for_checkpoint_size(checkpoint_size);
    if ((abi13_hidden == 0 && abi14_hidden == 0) || (abi13_hidden != 0 && abi14_hidden != 0)) {
        Mark_Policy_Failure("checkpoint_size");
        std::fprintf(stderr,
                     "TD Micro policy: checkpoint is %u bytes and does not uniquely identify "
                     "ABI13/14 hidden 64/128\n",
                     checkpoint_size);
        return false;
    }
    Runtime.use_abi14 = abi14_hidden != 0;

    uint8_t checkpoint_hash[32];
    if (Runtime.use_abi14) {
        Runtime.policy_abi14 = td_micro_policy_create_abi14(&checkpoint[0], checkpoint_size);
        if (Runtime.policy_abi14 == NULL
            || !td_micro_policy_seed_sampling_abi14(Runtime.policy_abi14, policy_sampling_seed)) {
            Mark_Policy_Failure("checkpoint_rejected");
            std::fprintf(stderr, "TD Micro policy: ABI14 checkpoint rejected\n");
            return false;
        }
        td_micro_policy_checkpoint_sha256_abi14(Runtime.policy_abi14, checkpoint_hash, sizeof(checkpoint_hash));
    } else {
        Runtime.policy = td_micro_policy_create(&checkpoint[0], checkpoint_size);
        if (Runtime.policy == NULL || !td_micro_policy_seed_sampling(Runtime.policy, policy_sampling_seed)) {
            Mark_Policy_Failure("checkpoint_rejected");
            std::fprintf(stderr, "TD Micro policy: checkpoint rejected\n");
            return false;
        }
        td_micro_policy_checkpoint_sha256(Runtime.policy, checkpoint_hash, sizeof(checkpoint_hash));
    }
    FILE* outputs[2] = {stderr, Runtime.telemetry};
    for (int index = 0; index < 2; ++index) {
        if (outputs[index] == NULL) continue;
        std::fprintf(outputs[index], "TD Micro policy: loaded checkpoint=");
        Print_Hex(outputs[index], checkpoint_hash, sizeof(checkpoint_hash));
        std::fprintf(outputs[index], " abi=%u hidden=%u rules=%s obs=%u mask=%u sampling=categorical seed=%llu\n",
                     Runtime.use_abi14 ? 14u : (unsigned)TD_MICRO_ABI_VERSION,
                     Runtime.use_abi14 ? td_micro_policy_hidden_size_abi14(Runtime.policy_abi14)
                                       : td_micro_policy_hidden_size(Runtime.policy),
                     TD_MICRO_MANIFEST_SHA256,
                     TD_MICRO_OBSERVATION_SIZE,
                     Runtime.use_abi14 ? TD_MICRO_ABI14_ACTION_MASK_SIZE : TD_MICRO_ACTION_MASK_SIZE,
                     static_cast<unsigned long long>(policy_sampling_seed));
        std::fflush(outputs[index]);
    }
    return true;
}

void Log_Action(int frame, TdMicroPolicyAction const& action, bool accepted, bool changed)
{
    if (Runtime.telemetry == NULL) return;
    std::fprintf(Runtime.telemetry,
                 "frame=%d action=%u,%u,%u,%u accepted=%u changed=%u\n",
                 frame,
                 action.command,
                 action.arg0,
                 action.arg1,
                 action.arg2,
                 accepted,
                 changed);
    std::fflush(Runtime.telemetry);
}

void Log_Stage(char const* stage, int frame)
{
    if (Runtime.telemetry == NULL) return;
    std::fprintf(Runtime.telemetry, "stage=%s frame=%d\n", stage, frame);
    std::fflush(Runtime.telemetry);
}

char const* Outcome_Name(TDMicroPolicyOutcome outcome)
{
    switch (outcome) {
    case TD_MICRO_POLICY_WIN:
        return "win";
    case TD_MICRO_POLICY_LOSS:
        return "loss";
    case TD_MICRO_POLICY_DRAW:
        return "draw";
    case TD_MICRO_POLICY_TIMEOUT:
        return "timeout";
    default:
        return "running";
    }
}

void Update_Deployment_Metrics()
{
    HouseClass* player = Logical_House(0);
    if (player == NULL) return;
    uint32_t tanks = 0;
    UnitClass* showcase_tank = NULL;
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        if (unit->House != player || !Is_Live(unit) || unit->Class->Type != UNIT_MTANK) continue;
        if (showcase_tank == NULL) showcase_tank = unit;
        ++tanks;
    }
    if (tanks > Runtime.previous_tank_count) {
        Runtime.medium_tanks_built += tanks - Runtime.previous_tank_count;
    }
    Runtime.previous_tank_count = tanks;
    Runtime.current_tank_count = tanks;
    const char* showcase_camera = std::getenv("TD_MICRO_SHOWCASE_CAMERA");
    if (showcase_camera != NULL && std::strcmp(showcase_camera, "1") == 0) {
        /* Capture-only presentation aid: show the base during the opening, then follow the first
           live player tank so the unattended GIF records actual combat. */
        Map.Center_Map(showcase_tank != NULL ? showcase_tank->Center_Coord() : player->Center);
    }
}

void Finish_Policy(TDMicroPolicyOutcome outcome)
{
    if (outcome == TD_MICRO_POLICY_RUNNING || Runtime.outcome != TD_MICRO_POLICY_RUNNING) return;
    Update_Deployment_Metrics();
    Runtime.outcome = outcome;
    HouseClass* player = Logical_House(0);
    HouseClass* opponent = Logical_House(1);
    const unsigned harvested = player != NULL ? player->HarvestedCredits : 0;
    const bool full_perf = outcome == TD_MICRO_POLICY_WIN
        && harvested >= TD_MICRO_FULL_WIN_MIN_TIBERIUM_INCOME
        && Runtime.medium_tanks_built >= TD_MICRO_FULL_WIN_MIN_MEDIUM_TANKS
        && Runtime.tank_shots >= TD_MICRO_FULL_WIN_MIN_TANK_SHOTS;
    FILE* outputs[2] = {stderr, Runtime.telemetry};
    for (int index = 0; index < 2; ++index) {
        if (outputs[index] == NULL) continue;
        std::fprintf(outputs[index],
                     "terminal reason=%s frame=%d decisions=%llu accepted=%llu changed=%llu "
                     "player_defeated=%u opponent_defeated=%u failed=%u harvested=%u "
                     "tanks_built=%llu tanks_alive=%u tank_shots=%llu full_perf=%u\n",
                     Outcome_Name(outcome),
                     Frame,
                     static_cast<unsigned long long>(Runtime.decisions),
                     static_cast<unsigned long long>(Runtime.accepted),
                     static_cast<unsigned long long>(Runtime.changed),
                     player != NULL && player->IsDefeated,
                     opponent != NULL && opponent->IsDefeated,
                     Runtime.failed,
                     harvested,
                     static_cast<unsigned long long>(Runtime.medium_tanks_built),
                     Runtime.current_tank_count,
                     static_cast<unsigned long long>(Runtime.tank_shots),
                     full_perf);
        std::fflush(outputs[index]);
    }
}

} // namespace

void TDMicro_Policy_Record_Weapon_Fire(TechnoClass const* source)
{
    if (!TDMicro.Auto_Start_Skirmish() || source == NULL || source->What_Am_I() != RTTI_UNIT) return;
    UnitClass const* unit = static_cast<UnitClass const*>(source);
    HouseClass* player = Logical_House(0);
    if (player != NULL && unit->House == player && unit->Class->Type == UNIT_MTANK) {
        ++Runtime.tank_shots;
    }
}

void TDMicro_Policy_Reset()
{
    if (Runtime.policy != NULL) td_micro_policy_destroy(Runtime.policy);
    if (Runtime.telemetry != NULL) std::fclose(Runtime.telemetry);
    if (Runtime.state_trace != NULL) std::fclose(Runtime.state_trace);
    if (Runtime.action_trace != NULL) std::fclose(Runtime.action_trace);
    if (Runtime.frame_trace != NULL) std::fclose(Runtime.frame_trace);
    Runtime = PolicyRuntime();
    Runtime.last_frame = -1;
}

/*
 * One ABI14 decision.
 *
 * The shape difference from ABI13 is that ATTACK is a group command: the 64 binary selectors name
 * every unit that should be ordered onto the single chosen target, so one decision can move a whole
 * wave instead of one unit at a time.
 *
 * policy_abi14.apply no longer requires the unused base fields to hold sentinel values -- the
 * selectors supply the actors and target_slot the target -- so this must not require them either.
 * Enforcing them here rejected every attack the training simulator accepts, which is exactly the
 * bridge-vs-training divergence this file exists to avoid.
 */
void Policy_Tick_Abi14(HouseClass* player, bool first_decision)
{
    Encode_Observation(0, Runtime.observation);
    if (first_decision) Log_Stage("observation_encoded", Frame);
    Encode_Action_Mask_Abi14(0, Runtime.mask);
    if (first_decision) Log_Stage("mask_encoded", Frame);
    if (Runtime.state_trace != NULL) {
        std::fwrite(Runtime.observation, 1, sizeof(Runtime.observation), Runtime.state_trace);
        std::fwrite(Runtime.mask, 1, TD_MICRO_ABI14_ACTION_MASK_SIZE, Runtime.state_trace);
        std::fflush(Runtime.state_trace);
    }

    TdMicroPolicyActionAbi14 action;
    if (!td_micro_policy_act_sampled_abi14(Runtime.policy_abi14,
                                           Runtime.observation,
                                           sizeof(Runtime.observation),
                                           Runtime.mask,
                                           TD_MICRO_ABI14_ACTION_MASK_SIZE,
                                           &action)) {
        Mark_Policy_Failure("inference");
        std::fprintf(stderr, "TD Micro policy: ABI14 inference failed at frame %d\n", Frame);
        return;
    }
    if (first_decision) Log_Stage("inference_complete", Frame);

    unsigned int selected = 0;
    bool selectors_valid = true;
    for (unsigned int slot = 0; slot < TD_MICRO_ABI14_SELECTOR_COUNT; ++slot) {
        if (action.selectors[slot] > 1) selectors_valid = false;
        selected += action.selectors[slot] != 0 ? 1u : 0u;
    }

    if (Runtime.action_trace != NULL) {
        /* Same four-byte stride as the ABI13 trace, but ABI14 fields: a group attack is summarised
         * by its target and how many units were ordered onto it. */
        const uint8_t action_record[4] = {
            action.command,
            action.actor,
            action.target_slot,
            static_cast<uint8_t>(selected),
        };
        if (std::fwrite(action_record, 1, sizeof(action_record), Runtime.action_trace) != sizeof(action_record)
            || std::fflush(Runtime.action_trace) != 0) {
            Mark_Policy_Failure("action_trace_write");
            return;
        }
    }

    const uint64_t before = Fingerprint_State();
    bool accepted = false;
    uint32_t applied = 0;

    if (!selectors_valid) {
        accepted = false;
    } else if (action.command == TD_MICRO_COMMAND_ATTACK) {
        accepted = action.target_slot < TD_MICRO_ABI14_SELECTOR_COUNT
                   && CNC_TD_Micro_Apply_Group_Attack(0,
                                                      action.target_slot,
                                                      action.selectors,
                                                      TD_MICRO_ABI14_SELECTOR_COUNT,
                                                      &applied);
    } else {
        /* Selectors are attack-only; policy_abi14.apply ignores them here rather than rejecting,
           because PufferLib samples all 71 heads every step and build/move actions routinely carry
           them. Rejecting made the contract self-contradictory and left group attacks unusable. */
        TdMicroAction game_action;
        accepted = Decode_Policy_Action_Abi14(action, player, game_action)
                   && CNC_TD_Micro_Apply_Action(0, &game_action);
    }

    const bool changed = action.command != TD_MICRO_COMMAND_NOOP && before != Fingerprint_State();
    ++Runtime.decisions;
    if (accepted) ++Runtime.accepted;
    if (changed) ++Runtime.changed;
    if (first_decision) Log_Stage("action_applied", Frame);
    if (Runtime.telemetry != NULL) {
        std::fprintf(Runtime.telemetry,
                     "action frame=%d abi=14 command=%u actor=%u product=%u target_kind=%u target_x=%u "
                     "target_y=%u target_slot=%u selected=%u applied=%u accepted=%d changed=%d\n",
                     Frame,
                     action.command,
                     action.actor,
                     action.product,
                     action.target_kind,
                     action.target_x,
                     action.target_y,
                     action.target_slot,
                     selected,
                     applied,
                     accepted ? 1 : 0,
                     changed ? 1 : 0);
        std::fflush(Runtime.telemetry);
    }
}

void TDMicro_Policy_Tick()
{
    if (!TDMicro.Enabled() || std::strcmp(TDMicro.Player_Brain(), "PufferPolicy") != 0) return;
    if (!Runtime.attempted_load && !Load_Policy()) return;
    /* Exactly one handle is populated, depending on the ABI the checkpoint selected. */
    if (Runtime.failed || (Runtime.policy == NULL && Runtime.policy_abi14 == NULL)) return;
    if (Runtime.outcome != TD_MICRO_POLICY_RUNNING) return;
    if (!Policy_World_Ready()) {
        if (!Runtime.waiting_logged && Runtime.telemetry != NULL) {
            std::fprintf(Runtime.telemetry,
                         "waiting frame=%d humans=%d ghosts=%d logical_players=%d\n",
                         Frame,
                         MPlayerCount,
                         MPlayerGhosts,
                         Logical_Player_Count());
            std::fflush(Runtime.telemetry);
            Runtime.waiting_logged = true;
        }
        return;
    }
    if (!Runtime.ready_logged) {
        if (!Ensure_Tiberium_Field()) {
            Mark_Policy_Failure("tiberium_field_setup");
            return;
        }
        Log_Stage("world_ready", Frame);
        Runtime.ready_logged = true;
    }
    if (Runtime.frame_trace != NULL && Frame <= 32) {
        for (int index = 0; index < Units.Count(); ++index) {
            UnitClass* unit = Units.Ptr(index);
            if (unit->Class->Type != UNIT_MCV || !Is_Live(unit)) continue;
            std::fprintf(Runtime.frame_trace,
                         "frame=%d rng=%u index=%d house=%d human=%u difficulty=%d "
                         "mission=%d status=%d facing=%d deploying=%u\n",
                         Frame,
                         Scen.RandomNumber.Seed,
                         index,
                         unit->House->Class->House,
                         unit->House->IsHuman,
                         unit->House->Difficulty,
                         unit->Mission,
                         unit->Status,
                         unit->PrimaryFacing.Current(),
                         unit->IsDeploying);
        }
        std::fflush(Runtime.frame_trace);
    }
    HouseClass* player = Logical_House(0);
    HouseClass* opponent = Logical_House(1);
    if (player == NULL || opponent == NULL) {
        Mark_Policy_Failure("logical_house_missing");
        return;
    }
    Update_Deployment_Metrics();
    const TDMicroPolicyOutcome outcome =
        TDMicro_Classify_Policy_Outcome(Frame, player->IsDefeated, opponent->IsDefeated);
    if (outcome != TD_MICRO_POLICY_RUNNING) {
        Finish_Policy(outcome);
        if (outcome == TD_MICRO_POLICY_TIMEOUT) GameActive = false;
        return;
    }
    if (Frame < 0 || Frame % TD_MICRO_DECISION_FRAMES != 0 || Runtime.last_frame == Frame) return;
    Runtime.last_frame = Frame;

    const bool first_decision = Runtime.decisions == 0;
    if (Runtime.use_abi14) {
        Policy_Tick_Abi14(player, first_decision);
        return;
    }
    Encode_Observation(0, Runtime.observation);
    if (first_decision) Log_Stage("observation_encoded", Frame);
    Encode_Action_Mask(0, Runtime.mask);
    if (first_decision) Log_Stage("mask_encoded", Frame);
    if (Runtime.state_trace != NULL) {
        std::fwrite(Runtime.observation, 1, sizeof(Runtime.observation), Runtime.state_trace);
        std::fwrite(Runtime.mask, 1, sizeof(Runtime.mask), Runtime.state_trace);
        std::fflush(Runtime.state_trace);
    }
    TdMicroPolicyAction policy_action;
    if (!td_micro_policy_act_sampled(Runtime.policy,
                                     Runtime.observation,
                                     sizeof(Runtime.observation),
                                     Runtime.mask,
                                     sizeof(Runtime.mask),
                                     &policy_action)) {
        Mark_Policy_Failure("inference");
        std::fprintf(stderr, "TD Micro policy: inference failed at frame %d\n", Frame);
        return;
    }
    if (first_decision) Log_Stage("inference_complete", Frame);
    if (Runtime.action_trace != NULL) {
        const uint8_t action_record[4] = {
            policy_action.command,
            policy_action.arg0,
            policy_action.arg1,
            policy_action.arg2,
        };
        if (std::fwrite(action_record, 1, sizeof(action_record), Runtime.action_trace) != sizeof(action_record)
            || std::fflush(Runtime.action_trace) != 0) {
            Mark_Policy_Failure("action_trace_write");
            return;
        }
    }

    TdMicroAction game_action;
    const bool decoded = Decode_Policy_Action(policy_action, player, game_action);
    const uint64_t before = Fingerprint_State();
    const bool accepted = decoded && CNC_TD_Micro_Apply_Action(0, &game_action);
    const bool changed = policy_action.command != TD_MICRO_COMMAND_NOOP && before != Fingerprint_State();
    ++Runtime.decisions;
    if (accepted) ++Runtime.accepted;
    if (changed) ++Runtime.changed;
    if (first_decision) Log_Stage("action_applied", Frame);
    Log_Action(Frame, policy_action, accepted, changed);
}

void TDMicro_Policy_Record_Outcome(TDMicroPolicyOutcome outcome)
{
    if (!TDMicro.Auto_Start_Skirmish()) return;
    Finish_Policy(outcome);
}

bool TDMicro_Policy_Completed()
{
    return Runtime.failed || Runtime.outcome != TD_MICRO_POLICY_RUNNING;
}

extern "C" __declspec(dllexport) bool __cdecl CNC_TD_Micro_Get_Policy_State(uint8_t owner,
                                                                              uint8_t* observation,
                                                                              unsigned int observation_size,
                                                                              uint8_t* action_mask,
                                                                              unsigned int action_mask_size)
{
    if (!TDMicro.Enabled() || owner >= TD_MICRO_PLAYER_COUNT || observation == NULL || action_mask == NULL
        || observation_size != TD_MICRO_OBSERVATION_SIZE || action_mask_size != TD_MICRO_ACTION_MASK_SIZE
        || !Policy_World_Ready()) {
        return false;
    }
    Encode_Observation(owner, observation);
    Encode_Action_Mask(owner, action_mask);
    return true;
}
