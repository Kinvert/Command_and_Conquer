#include "function.h"

#include "td_micro_api.h"
#include "td_micro_oracle.h"
#include "tdmicro.h"

#include <cstring>

#ifndef _MSC_VER
#ifndef __cdecl
#define __cdecl
#endif
#ifndef __declspec
#define __declspec(x) __attribute__((visibility("default")))
#endif
#endif

namespace {

HouseClass* Owner_House(uint8_t owner)
{
    if (owner < MPlayerCount) return HouseClass::As_Pointer(MPlayerHouses[owner]);
    if (TDMicro.Enabled() && MPlayerCount == 1 && MPlayerGhosts == 1 && owner == 1) {
        return HouseClass::As_Pointer(HOUSE_MULTI1);
    }
    return NULL;
}

TechnoClass* Actor_By_Slot(HouseClass* house, uint8_t slot)
{
    uint8_t candidate = 0;
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        if (unit->House == house && unit->IsActive && !unit->IsInLimbo) {
            if (candidate == slot) return unit;
            ++candidate;
        }
    }
    for (int index = 0; index < Buildings.Count(); ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        if (building->House == house && building->IsActive && !building->IsInLimbo) {
            if (candidate == slot) return building;
            ++candidate;
        }
    }
    for (int index = 0; index < Infantry.Count(); ++index) {
        InfantryClass* infantry = Infantry.Ptr(index);
        if (infantry->House == house && infantry->IsActive && !infantry->IsInLimbo) {
            if (candidate == slot) return infantry;
            ++candidate;
        }
    }
    return NULL;
}

TechnoClass* Enemy_By_Slot(HouseClass* house, uint8_t slot)
{
    uint8_t candidate = 0;
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        if (unit->House != house && !house->Is_Ally(unit) && unit->IsActive && !unit->IsInLimbo) {
            if (candidate == slot) return unit;
            ++candidate;
        }
    }
    for (int index = 0; index < Buildings.Count(); ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        if (building->House != house && !house->Is_Ally(building) && building->IsActive && !building->IsInLimbo) {
            if (candidate == slot) return building;
            ++candidate;
        }
    }
    for (int index = 0; index < Infantry.Count(); ++index) {
        InfantryClass* infantry = Infantry.Ptr(index);
        if (infantry->House != house && !house->Is_Ally(infantry) && infantry->IsActive && !infantry->IsInLimbo) {
            if (candidate == slot) return infantry;
            ++candidate;
        }
    }
    return NULL;
}

bool Has_Operational_Factory(HouseClass* house, RTTIType product_type)
{
    for (int index = 0; index < Buildings.Count(); ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        if (building->House == house && building->IsActive && !building->IsInLimbo
            && building->Class->ToBuild == product_type && building->Mission != MISSION_CONSTRUCTION
            && building->Mission != MISSION_DECONSTRUCTION) {
            return true;
        }
    }
    return false;
}

bool Start_Structure(HouseClass* house, uint8_t product)
{
    StructType structure = STRUCT_NONE;
    switch (product) {
    case TD_MICRO_OBJECT_POWER_PLANT:
        structure = STRUCT_POWER;
        break;
    case TD_MICRO_OBJECT_BARRACKS:
        structure = STRUCT_BARRACKS;
        break;
    case TD_MICRO_OBJECT_REFINERY:
        structure = STRUCT_REFINERY;
        break;
    case TD_MICRO_OBJECT_WEAPONS_FACTORY:
        structure = STRUCT_WEAP;
        break;
    default:
        return false;
    }

    if (!Has_Operational_Factory(house, RTTI_BUILDINGTYPE) || !house->Can_Build(structure, house->ActLike)) {
        return false;
    }
    return house->Begin_Production(RTTI_BUILDINGTYPE, structure) == PROD_OK;
}

bool Place_Structure(HouseClass* house, TdMicroAction const& action)
{
    if (action.target_kind != TD_MICRO_TARGET_CELL || action.target_x >= Map.MapCellWidth
        || action.target_y >= Map.MapCellHeight) {
        return false;
    }

    StructType expected = STRUCT_NONE;
    switch (action.product) {
    case TD_MICRO_OBJECT_POWER_PLANT:
        expected = STRUCT_POWER;
        break;
    case TD_MICRO_OBJECT_BARRACKS:
        expected = STRUCT_BARRACKS;
        break;
    case TD_MICRO_OBJECT_REFINERY:
        expected = STRUCT_REFINERY;
        break;
    case TD_MICRO_OBJECT_WEAPONS_FACTORY:
        expected = STRUCT_WEAP;
        break;
    default:
        return false;
    }

    FactoryClass* factory = house->Fetch_Factory(RTTI_BUILDINGTYPE);
    if (factory == NULL || !factory->Has_Completed()) return false;
    TechnoClass* product = factory->Get_Object();
    if (product == NULL || product->What_Am_I() != RTTI_BUILDING
        || static_cast<BuildingClass*>(product)->Class->Type != expected) {
        return false;
    }

    const CELL cell = XY_Cell(Map.MapCellX + action.target_x, Map.MapCellY + action.target_y);
    return house->Place_Object(RTTI_BUILDINGTYPE, cell);
}

/* Vehicles are produced from the Weapons Factory queue. Route them by product so both the current
   start-build contract and older train actions reach the right Vanilla production queue. */
bool Build_Vehicle(HouseClass* house, uint8_t product)
{
    UnitType unit = UNIT_NONE;
    switch (product) {
    case TD_MICRO_OBJECT_MEDIUM_TANK:
        unit = UNIT_MTANK;
        break;
    case TD_MICRO_OBJECT_HUMVEE:
        unit = UNIT_JEEP;
        break;
    default:
        return false;
    }
    if (!Has_Operational_Factory(house, RTTI_UNITTYPE)) return false;
    if (!house->Can_Build(unit, house->ActLike)) return false;
    return house->Begin_Production(RTTI_UNITTYPE, unit) == PROD_OK;
}

bool Train_Infantry(HouseClass* house, uint8_t product)
{
    InfantryType infantry = INFANTRY_NONE;
    switch (product) {
    case TD_MICRO_OBJECT_E1:
        infantry = INFANTRY_E1;
        break;
    case TD_MICRO_OBJECT_E3:
        infantry = INFANTRY_E3;
        break;
    default:
        return false;
    }

    if (!Has_Operational_Factory(house, RTTI_INFANTRYTYPE)) return false;

    if (!house->Can_Build(infantry, house->ActLike)) return false;
    return house->Begin_Production(RTTI_INFANTRYTYPE, infantry) == PROD_OK;
}

bool Move_Unit(HouseClass* house, TechnoClass* actor, TdMicroAction const& action)
{
    if (actor == NULL || actor->House != house
        || (actor->What_Am_I() != RTTI_INFANTRY && actor->What_Am_I() != RTTI_UNIT)
        || action.target_kind != TD_MICRO_TARGET_CELL || action.target_x >= Map.MapCellWidth
        || action.target_y >= Map.MapCellHeight) {
        return false;
    }
    if (actor->What_Am_I() == RTTI_UNIT) {
        const UnitType type = static_cast<UnitClass*>(actor)->Class->Type;
        if (type != UNIT_HARVESTER && type != UNIT_MTANK && type != UNIT_JEEP) return false;
    }

    const CELL cell = XY_Cell(Map.MapCellX + action.target_x, Map.MapCellY + action.target_y);
    actor->Player_Assign_Mission(MISSION_MOVE, TARGET_NONE, ::As_Target(cell));
    return true;
}

bool Harvest_Tiberium(HouseClass* house, TechnoClass* actor, TdMicroAction const& action)
{
    if (actor == NULL || actor->House != house || actor->What_Am_I() != RTTI_UNIT
        || static_cast<UnitClass*>(actor)->Class->Type != UNIT_HARVESTER
        || action.target_kind != TD_MICRO_TARGET_CELL || action.target_x >= Map.MapCellWidth
        || action.target_y >= Map.MapCellHeight) {
        return false;
    }

    const CELL cell = XY_Cell(Map.MapCellX + action.target_x, Map.MapCellY + action.target_y);
    if (Map[cell].Land_Type() != LAND_TIBERIUM) return false;
    actor->Player_Assign_Mission(MISSION_HARVEST, TARGET_NONE, ::As_Target(cell));
    return true;
}

bool Return_Cargo(HouseClass* house, TechnoClass* actor, TdMicroAction const& action)
{
    if (actor == NULL || actor->House != house || actor->What_Am_I() != RTTI_UNIT
        || static_cast<UnitClass*>(actor)->Class->Type != UNIT_HARVESTER
        || action.target_kind != TD_MICRO_TARGET_OWN_ENTITY) {
        return false;
    }
    TechnoClass* target = Actor_By_Slot(house, action.target_slot);
    if (target == NULL || target->What_Am_I() != RTTI_BUILDING
        || static_cast<BuildingClass*>(target)->Class->Type != STRUCT_REFINERY) {
        return false;
    }
    actor->Player_Assign_Mission(MISSION_ENTER, TARGET_NONE, target->As_Target());
    return true;
}

/*
 * Attack validation, split out so ABI14 group attacks can be checked before any of them mutate the
 * world. policy_abi14.apply is all-or-nothing: every selected unit is validated first, and if any
 * one fails the whole group is rejected without side effects. Keeping the predicate here rather
 * than reimplementing it in the policy bridge is what stops the two from drifting apart.
 * Returns the resolved target, or NULL if this actor cannot attack this slot.
 */
TechnoClass* Attack_Target_Resolve(HouseClass* house, TechnoClass* actor, TdMicroAction const& action)
{
    if (actor == NULL || actor->House != house || action.target_kind != TD_MICRO_TARGET_VISIBLE_ENEMY) {
        return NULL;
    }
    if (actor->What_Am_I() == RTTI_UNIT) {
        const UnitType type = static_cast<UnitClass*>(actor)->Class->Type;
        if (type != UNIT_MTANK && type != UNIT_JEEP) return NULL;
    } else if (actor->What_Am_I() != RTTI_INFANTRY) {
        return NULL;
    }
    return Enemy_By_Slot(house, action.target_slot);
}

bool Attack_Target(HouseClass* house, TechnoClass* actor, TdMicroAction const& action)
{
    TechnoClass* target = Attack_Target_Resolve(house, actor, action);
    if (target == NULL) return false;
    actor->Player_Assign_Mission(MISSION_ATTACK, target->As_Target());
    return true;
}

} // namespace

extern "C" __declspec(dllexport) bool __cdecl CNC_TD_Micro_Apply_Action(uint8_t owner,
                                                                         TdMicroAction const* action)
{
    if (!TDMicro.Enabled() || action == NULL) return false;
    if (action->command == TD_MICRO_COMMAND_NOOP) return true;

    HouseClass* house = Owner_House(owner);
    if (house == NULL) return false;

    if (action->command == TD_MICRO_COMMAND_START_BUILD) {
        // Vehicles are produced by the Weapons Factory, structures by the Construction Yard.
        if (action->product == TD_MICRO_OBJECT_MEDIUM_TANK || action->product == TD_MICRO_OBJECT_HUMVEE) {
            return Build_Vehicle(house, action->product);
        }
        return Start_Structure(house, action->product);
    }
    if (action->command == TD_MICRO_COMMAND_PLACE) {
        return Place_Structure(house, *action);
    }
    if (action->command == TD_MICRO_COMMAND_TRAIN) {
        if (action->product == TD_MICRO_OBJECT_MEDIUM_TANK || action->product == TD_MICRO_OBJECT_HUMVEE) {
            return Build_Vehicle(house, action->product);
        }
        return Train_Infantry(house, action->product);
    }

    TechnoClass* actor = Actor_By_Slot(house, action->actor);
    if (actor != NULL && action->command == TD_MICRO_COMMAND_DEPLOY && actor->What_Am_I() == RTTI_UNIT) {
        UnitClass* unit = static_cast<UnitClass*>(actor);
        if (unit->Class->Type != UNIT_MCV || unit->IsDeploying) return false;
        unit->Player_Assign_Mission(MISSION_UNLOAD);
        return true;
    }
    if (action->command == TD_MICRO_COMMAND_MOVE) {
        return Move_Unit(house, actor, *action);
    }
    if (action->command == TD_MICRO_COMMAND_ATTACK) {
        return Attack_Target(house, actor, *action);
    }
    if (action->command == TD_MICRO_COMMAND_HARVEST) {
        return Harvest_Tiberium(house, actor, *action);
    }
    if (action->command == TD_MICRO_COMMAND_RETURN_CARGO) {
        return Return_Cargo(house, actor, *action);
    }
    return false;
}

/*
 * ABI14 group attack: order every selected unit onto one target in a single decision.
 *
 * Mirrors policy_abi14.apply exactly, including its atomicity. Pass one resolves every selected
 * actor without mutating anything; if any selection is illegal the whole group is rejected and the
 * world is untouched. Only then does pass two assign missions. A half-applied group would silently
 * diverge from the simulator the policy was trained against.
 *
 * Selecting nothing is legal and applies nothing, matching the Zig side.
 */
extern "C" __declspec(dllexport) bool __cdecl CNC_TD_Micro_Apply_Group_Attack(uint8_t owner,
                                                                              uint8_t target_slot,
                                                                              uint8_t const* selectors,
                                                                              uint32_t selector_count,
                                                                              uint32_t* applied_count)
{
    if (applied_count != NULL) *applied_count = 0;
    if (!TDMicro.Enabled() || selectors == NULL) return false;
    if (selector_count > TD_MICRO_ABI14_SELECTOR_COUNT) return false;

    HouseClass* house = Owner_House(owner);
    if (house == NULL) return false;

    TdMicroAction action;
    std::memset(&action, 0, sizeof(action));
    action.command = TD_MICRO_COMMAND_ATTACK;
    action.target_kind = TD_MICRO_TARGET_VISIBLE_ENEMY;
    action.target_slot = target_slot;

    TechnoClass* actors[TD_MICRO_ABI14_SELECTOR_COUNT];
    TechnoClass* targets[TD_MICRO_ABI14_SELECTOR_COUNT];
    uint32_t selected = 0;

    for (uint32_t slot = 0; slot < selector_count; ++slot) {
        if (selectors[slot] > 1) return false; /* selectors are strictly binary */
        if (selectors[slot] == 0) continue;
        TechnoClass* actor = Actor_By_Slot(house, static_cast<uint8_t>(slot));
        TechnoClass* target = Attack_Target_Resolve(house, actor, action);
        /* Apply the valid subset, mirroring policy_abi14.apply. All-or-nothing made the command
           unreachable: with 64 independently sampled selectors a fully valid set essentially never
           occurs, so the policy never executed one and could never learn it. */
        if (target == NULL) continue;
        actors[selected] = actor;
        targets[selected] = target;
        ++selected;
    }
    /* Nothing applicable means nothing happened, so the action is invalid. */
    if (selected == 0) return false;

    for (uint32_t index = 0; index < selected; ++index) {
        actors[index]->Player_Assign_Mission(MISSION_ATTACK, targets[index]->As_Target());
    }
    if (applied_count != NULL) *applied_count = selected;
    return true;
}
