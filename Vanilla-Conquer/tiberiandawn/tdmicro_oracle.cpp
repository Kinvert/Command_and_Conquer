#include "function.h"

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

int Logical_Player_Count()
{
    if (TDMicro.Enabled() && MPlayerCount == 1 && MPlayerGhosts == 1) return TD_MICRO_PLAYER_COUNT;
    return MPlayerCount;
}

HouseClass* Logical_House(uint8_t owner)
{
    if (owner < MPlayerCount) return HouseClass::As_Pointer(MPlayerHouses[owner]);
    if (TDMicro.Enabled() && MPlayerCount == 1 && MPlayerGhosts == 1 && owner == 1) {
        return HouseClass::As_Pointer(HOUSE_MULTI1);
    }
    return NULL;
}

uint8_t Logical_Owner(HouseClass const* house)
{
    for (int index = 0; index < Logical_Player_Count(); ++index) {
        if (Logical_House(static_cast<uint8_t>(index)) == house) {
            return static_cast<uint8_t>(index);
        }
    }
    return UINT8_MAX;
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

uint8_t Techno_Kind(TechnoClass const* techno)
{
    switch (techno->What_Am_I()) {
    case RTTI_UNIT:
        return Unit_Kind(static_cast<UnitClass const*>(techno));
    case RTTI_BUILDING:
        return Building_Kind(static_cast<BuildingClass const*>(techno));
    case RTTI_INFANTRY:
        return Infantry_Kind(static_cast<InfantryClass const*>(techno));
    default:
        return TD_MICRO_OBJECT_NONE;
    }
}

uint16_t Techno_Id(TechnoClass* techno)
{
    switch (techno->What_Am_I()) {
    case RTTI_UNIT:
        return static_cast<uint16_t>(Units.ID(static_cast<UnitClass*>(techno)));
    case RTTI_BUILDING:
        return static_cast<uint16_t>(Buildings.ID(static_cast<BuildingClass*>(techno)));
    case RTTI_INFANTRY:
        return static_cast<uint16_t>(Infantry.ID(static_cast<InfantryClass*>(techno)));
    default:
        return 0;
    }
}

struct AIObservedState
{
    bool initialized;
    UnitClass* mcv;
    bool mcv_unloading;
    TechnoClass* products[2];
    BuildingClass* buildings[TD_MICRO_MAX_BUILDINGS];
    uint16_t building_count;
    InfantryClass* infantry[TD_MICRO_MAX_INFANTRY];
    int8_t infantry_missions[TD_MICRO_MAX_INFANTRY];
    uint16_t infantry_count;
};

TdMicroOracleAICommand AICommands[TD_MICRO_ORACLE_MAX_AI_COMMANDS];
uint16_t AICommandCount = 0;
bool AICommandOverflow = false;
AIObservedState AIObserved = {};

uint8_t Structure_Kind(StructType type)
{
    switch (type) {
    case STRUCT_NONE:
        return TD_MICRO_OBJECT_NONE;
    case STRUCT_CONST:
        return TD_MICRO_OBJECT_CONSTRUCTION_YARD;
    case STRUCT_POWER:
        return TD_MICRO_OBJECT_POWER_PLANT;
    case STRUCT_BARRACKS:
        return TD_MICRO_OBJECT_BARRACKS;
    case STRUCT_REFINERY:
        return TD_MICRO_OBJECT_REFINERY;
    default:
        return UINT8_MAX;
    }
}

uint8_t Infantry_Type_Kind(InfantryType type)
{
    switch (type) {
    case INFANTRY_NONE:
        return TD_MICRO_OBJECT_NONE;
    case INFANTRY_E1:
        return TD_MICRO_OBJECT_E1;
    case INFANTRY_E3:
        return TD_MICRO_OBJECT_E3;
    default:
        return UINT8_MAX;
    }
}

TdMicroOracleAICommand* Begin_AI_Command(HouseClass* house, TechnoClass* actor, uint8_t command)
{
    if (!TDMicro.Enabled() || house == NULL || house->IsHuman || Logical_Owner(house) != 1) return NULL;
    if (AICommandCount >= TD_MICRO_ORACLE_MAX_AI_COMMANDS) {
        AICommandOverflow = true;
        return NULL;
    }

    TdMicroOracleAICommand& output = AICommands[AICommandCount];
    std::memset(&output, 0, sizeof(output));
    output.frame = static_cast<uint32_t>(Frame);
    output.sequence = AICommandCount;
    output.owner = 1;
    output.command = command;
    output.target_owner = UINT8_MAX;
    output.target_entity_kind = TD_MICRO_OBJECT_NONE;
    if (actor != NULL) {
        output.actor_kind = Techno_Kind(actor);
        output.actor_id = Techno_Id(actor);
    }
    ++AICommandCount;
    return &output;
}

bool Fill_Entity(TdMicroOracleEntity& output, TechnoClass const* techno, uint16_t id, uint8_t kind)
{
    uint8_t owner = Logical_Owner(techno->House);
    if (kind == TD_MICRO_OBJECT_NONE || owner == UINT8_MAX) {
        return false;
    }

    std::memset(&output, 0, sizeof(output));
    output.id = id;
    output.kind = kind;
    output.owner = owner;
    output.active = techno->IsActive;
    output.in_limbo = techno->IsInLimbo;
    output.cell_x = static_cast<int16_t>(Coord_XCell(techno->Coord) - Map.MapCellX);
    output.cell_y = static_cast<int16_t>(Coord_YCell(techno->Coord) - Map.MapCellY);
    output.coord_x = Coord_X(techno->Coord) - Cell_To_Lepton(Map.MapCellX);
    output.coord_y = Coord_Y(techno->Coord) - Cell_To_Lepton(Map.MapCellY);
    output.health = techno->Strength;
    output.max_health = techno->Class_Of().MaxStrength;
    output.facing = static_cast<int16_t>(techno->PrimaryFacing.Current());
    output.mission = static_cast<int8_t>(techno->Mission);
    output.queued_mission = static_cast<int8_t>(techno->MissionQueue);
    output.status = techno->Status;
    output.weapon_cooldown = techno->Arm;
    output.target = static_cast<uint64_t>(techno->TarCom);

    if (techno->What_Am_I() == RTTI_UNIT) {
        UnitClass const* turreted = static_cast<UnitClass const*>(techno);
        if (turreted->Class->IsTurretEquipped) {
            output.has_turret = 1;
            output.turret_facing = static_cast<int16_t>(turreted->SecondaryFacing.Current());
        }
    }

    if (techno->What_Am_I() == RTTI_UNIT || techno->What_Am_I() == RTTI_INFANTRY) {
        FootClass const* foot = static_cast<FootClass const*>(techno);
        output.moving = foot->IsDriving;
        output.firing = foot->IsFiring;
        output.deploying = foot->IsDeploying;
        output.speed = foot->Speed;
        output.path_facing = static_cast<int8_t>(foot->Path[0]);
        output.new_destination = foot->IsNewNavCom;
        if (foot->Head_To_Coord() != 0) {
            output.head_coord_x = Coord_X(foot->Head_To_Coord()) - Cell_To_Lepton(Map.MapCellX);
            output.head_coord_y = Coord_Y(foot->Head_To_Coord()) - Cell_To_Lepton(Map.MapCellY);
        }
        output.destination = static_cast<uint64_t>(foot->NavCom);
    }
    if (techno->What_Am_I() == RTTI_UNIT) {
        UnitClass const* unit = static_cast<UnitClass const*>(techno);
        output.cargo_steps = unit->Tiberium;
        output.harvesting = unit->IsHarvesting;
    }
    if (techno->What_Am_I() == RTTI_INFANTRY) {
        InfantryClass const* infantry = static_cast<InfantryClass const*>(techno);
        output.animation = static_cast<int8_t>(infantry->Doing);
        output.animation_stage = static_cast<uint16_t>(infantry->Fetch_Stage());
        output.animation_timer = static_cast<uint8_t>(infantry->Fetch_Stage_Timer());
        output.animation_rate = static_cast<uint8_t>(infantry->Fetch_Rate());
        output.prone = infantry->IsProne;
        output.fear = infantry->Fear;
        output.ammo = static_cast<int16_t>(infantry->Ammo);
        output.kills = infantry->Kills;
        output.second_shot = infantry->IsSecondShot;
    }
    return true;
}

bool Fill_Queue(TdMicroOracleQueue& output, HouseClass* house, uint8_t owner, uint8_t category)
{
    std::memset(&output, 0, sizeof(output));
    output.owner = owner;
    output.category = category;

    RTTIType factory_type = category == 0 ? RTTI_BUILDING : RTTI_INFANTRY;
    FactoryClass* factory = house->Fetch_Factory(factory_type);
    if (factory == NULL) {
        const RTTIType building_factory_type = category == 0 ? RTTI_BUILDINGTYPE : RTTI_INFANTRYTYPE;
        for (int index = 0; index < Buildings.Count(); ++index) {
            BuildingClass* building = Buildings.Ptr(index);
            if (building->House == house && building->IsActive && !building->IsInLimbo
                && building->Class->ToBuild == building_factory_type && building->Factory != NULL) {
                factory = building->Factory;
                break;
            }
        }
    }
    if (factory == NULL) {
        return true;
    }

    TechnoClass* product = factory->Get_Object();
    output.active = product != NULL;
    output.completed = factory->Has_Completed();
    output.product = product != NULL ? Techno_Kind(product) : TD_MICRO_OBJECT_NONE;
    output.suspended = factory->TDMicro_Is_Suspended();
    output.stage = static_cast<uint16_t>(factory->Completion());
    output.stage_timer = static_cast<uint8_t>(factory->TDMicro_Stage_Timer());
    output.rate = static_cast<uint8_t>(factory->TDMicro_Rate());
    output.balance = factory->TDMicro_Balance();
    return product == NULL || output.product != TD_MICRO_OBJECT_NONE;
}

TechnoClass* AI_Factory_Product(HouseClass* house, uint8_t category)
{
    RTTIType factory_type = category == 0 ? RTTI_BUILDING : RTTI_INFANTRY;
    FactoryClass* factory = house->Fetch_Factory(factory_type);
    if (factory == NULL) {
        const RTTIType building_factory_type = category == 0 ? RTTI_BUILDINGTYPE : RTTI_INFANTRYTYPE;
        for (int index = 0; index < Buildings.Count(); ++index) {
            BuildingClass* building = Buildings.Ptr(index);
            if (building->House == house && building->IsActive && !building->IsInLimbo
                && building->Class->ToBuild == building_factory_type && building->Factory != NULL) {
                factory = building->Factory;
                break;
            }
        }
    }
    return factory != NULL ? factory->Get_Object() : NULL;
}

bool Was_Observed(BuildingClass* building)
{
    for (uint16_t index = 0; index < AIObserved.building_count; ++index) {
        if (AIObserved.buildings[index] == building) return true;
    }
    return false;
}

int8_t Prior_Infantry_Mission(InfantryClass* infantry)
{
    for (uint16_t index = 0; index < AIObserved.infantry_count; ++index) {
        if (AIObserved.infantry[index] == infantry) return AIObserved.infantry_missions[index];
    }
    return MISSION_NONE;
}

void Observe_AI_Commands()
{
    if (!TDMicro.Enabled() || Logical_Player_Count() != TD_MICRO_PLAYER_COUNT) return;
    HouseClass* house = Logical_House(1);
    if (house == NULL || house->IsHuman) return;

    UnitClass* mcv = NULL;
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        if (unit->House == house && Unit_Kind(unit) == TD_MICRO_OBJECT_MCV && unit->IsActive && !unit->IsInLimbo) {
            mcv = unit;
            break;
        }
    }

    TechnoClass* products[2] = {AI_Factory_Product(house, 0), AI_Factory_Product(house, 1)};
    BuildingClass* buildings[TD_MICRO_MAX_BUILDINGS] = {};
    uint16_t building_count = 0;
    for (int index = 0; index < Buildings.Count(); ++index) {
        BuildingClass* building = Buildings.Ptr(index);
        const uint8_t kind = Building_Kind(building);
        if (building->House == house && building->IsActive && !building->IsInLimbo
            && (kind == TD_MICRO_OBJECT_POWER_PLANT || kind == TD_MICRO_OBJECT_BARRACKS
                || kind == TD_MICRO_OBJECT_REFINERY)) {
            if (building_count >= TD_MICRO_MAX_BUILDINGS) {
                AICommandOverflow = true;
                return;
            }
            buildings[building_count++] = building;
        }
    }

    InfantryClass* infantry[TD_MICRO_MAX_INFANTRY] = {};
    int8_t infantry_missions[TD_MICRO_MAX_INFANTRY] = {};
    uint16_t infantry_count = 0;
    for (int index = 0; index < Infantry.Count(); ++index) {
        InfantryClass* object = Infantry.Ptr(index);
        if (object->House == house && object->IsActive && !object->IsInLimbo) {
            if (infantry_count >= TD_MICRO_MAX_INFANTRY) {
                AICommandOverflow = true;
                return;
            }
            infantry[infantry_count] = object;
            infantry_missions[infantry_count] = static_cast<int8_t>(object->Mission);
            ++infantry_count;
        }
    }

    if (AIObserved.initialized) {
        const bool mcv_unloading = mcv != NULL && mcv->Mission == MISSION_UNLOAD;
        if (mcv_unloading && (AIObserved.mcv != mcv || !AIObserved.mcv_unloading)) {
            Begin_AI_Command(house, mcv, TD_MICRO_AI_COMMAND_DEPLOY);
        }
        for (uint16_t index = 0; index < building_count; ++index) {
            BuildingClass* building = buildings[index];
            if (!Was_Observed(building)) {
                TdMicroOracleAICommand* command = Begin_AI_Command(house, NULL, TD_MICRO_AI_COMMAND_PLACE);
                if (command != NULL) {
                    command->product = Building_Kind(building);
                    command->target_kind = TD_MICRO_TARGET_CELL;
                    command->target_x = static_cast<int16_t>(Coord_XCell(building->Coord) - Map.MapCellX);
                    command->target_y = static_cast<int16_t>(Coord_YCell(building->Coord) - Map.MapCellY);
                }
            }
        }
        for (uint8_t category = 0; category < 2; ++category) {
            if (products[category] != NULL && products[category] != AIObserved.products[category]) {
                const uint8_t product = Techno_Kind(products[category]);
                if (product == TD_MICRO_OBJECT_NONE) {
                    AICommandOverflow = true;
                    continue;
                }
                TdMicroOracleAICommand* command = Begin_AI_Command(
                    house,
                    NULL,
                    category == 0 ? TD_MICRO_AI_COMMAND_START_BUILD : TD_MICRO_AI_COMMAND_TRAIN);
                if (command != NULL) command->product = product;
            }
        }
        for (uint16_t index = 0; index < infantry_count; ++index) {
            if (infantry_missions[index] == MISSION_HUNT && Prior_Infantry_Mission(infantry[index]) != MISSION_HUNT) {
                Begin_AI_Command(house, infantry[index], TD_MICRO_AI_COMMAND_HUNT);
            }
        }
    }

    AIObserved.initialized = true;
    AIObserved.mcv = mcv;
    AIObserved.mcv_unloading = mcv != NULL && mcv->Mission == MISSION_UNLOAD;
    AIObserved.products[0] = products[0];
    AIObserved.products[1] = products[1];
    AIObserved.building_count = building_count;
    std::memcpy(AIObserved.buildings, buildings, sizeof(buildings));
    AIObserved.infantry_count = infantry_count;
    std::memcpy(AIObserved.infantry, infantry, sizeof(infantry));
    std::memcpy(AIObserved.infantry_missions, infantry_missions, sizeof(infantry_missions));
}

bool Fill_AI_State(TdMicroOracleAIState& output, HouseClass* house, uint8_t owner)
{
    std::memset(&output, 0, sizeof(output));
    output.owner = owner;
    output.enemy = UINT8_MAX;
    if (house == NULL) return false;

    output.active = !house->IsHuman;
    output.state = static_cast<int8_t>(house->State);
    output.started = house->IsStarted;
    output.alerted = house->IsAlerted;
    output.base_building = house->IsBaseBuilding;
    output.tiberium_short = house->IsTiberiumShort;
    output.difficulty = static_cast<uint8_t>(house->Difficulty);
    if (house->Enemy != HOUSE_NONE) output.enemy = Logical_Owner(HouseClass::As_Pointer(house->Enemy));
    output.build_structure = Structure_Kind(house->BuildStructure);
    output.build_infantry = Infantry_Type_Kind(house->BuildInfantry);
    output.unsupported_choice = output.build_structure == UINT8_MAX || output.build_infantry == UINT8_MAX
        || (house->BuildUnit != UNIT_NONE && house->BuildUnit != UNIT_HARVESTER)
        || house->BuildAircraft != AIRCRAFT_NONE;
    output.ai_timer = static_cast<int>(house->AITimer);
    output.attack_timer = house->TDMicro_Attack_Timer();
    output.has_center = house->Center != 0;
    if (output.has_center) {
        output.center_x = Coord_X(house->Center) - Cell_To_Lepton(Map.MapCellX);
        output.center_y = Coord_Y(house->Center) - Cell_To_Lepton(Map.MapCellY);
    }
    output.radius = house->Radius;
    output.current_units = house->CurUnits;
    output.current_buildings = house->CurBuildings;
    output.current_infantry = house->CurInfantry;
    output.max_units = house->MaxUnit;
    output.max_buildings = house->MaxBuilding;
    output.max_infantry = house->MaxInfantry;
    output.construction_yards = static_cast<uint16_t>(house->TDMicro_Building_Quantity(STRUCT_CONST));
    output.power_plants = static_cast<uint16_t>(house->TDMicro_Building_Quantity(STRUCT_POWER));
    output.barracks = static_cast<uint16_t>(house->TDMicro_Building_Quantity(STRUCT_BARRACKS));
    output.refineries = static_cast<uint16_t>(house->TDMicro_Building_Quantity(STRUCT_REFINERY));
    output.harvesters = static_cast<uint16_t>(house->TDMicro_Unit_Quantity(UNIT_HARVESTER));
    output.e1 = static_cast<uint16_t>(house->TDMicro_Infantry_Quantity(INFANTRY_E1));
    output.e3 = static_cast<uint16_t>(house->TDMicro_Infantry_Quantity(INFANTRY_E3));
    output.building_scan = house->BScan;
    output.active_building_scan = house->ActiveBScan;
    output.infantry_scan = house->IScan;
    output.active_infantry_scan = house->ActiveIScan;
    return !output.unsupported_choice;
}

bool Copy_AI_Commands(TdMicroOracleSnapshot& output)
{
    if (AICommandOverflow) return false;
    output.ai_command_count = AICommandCount;
    std::memcpy(output.ai_commands, AICommands, sizeof(AICommands[0]) * AICommandCount);
    AICommandCount = 0;
    return true;
}

int Abs_Offset(int value)
{
    return value < 0 ? -value : value;
}

bool Add_Curriculum_Infantry(HouseClass* house,
                             InfantryType type,
                             int count,
                             CELL center,
                             CELL facing_target,
                             int min_radius,
                             int max_radius)
{
    int added = 0;
    const int center_x = Cell_X(center);
    const int center_y = Cell_Y(center);
    for (int radius = min_radius; radius <= max_radius && added < count; ++radius) {
        for (int y_offset = -radius; y_offset <= radius && added < count; ++y_offset) {
            for (int x_offset = -radius; x_offset <= radius && added < count; ++x_offset) {
                if (Abs_Offset(x_offset) != radius && Abs_Offset(y_offset) != radius) continue;
                const int x = center_x + x_offset;
                const int y = center_y + y_offset;
                if (x < Map.MapCellX || y < Map.MapCellY || x >= Map.MapCellX + Map.MapCellWidth
                    || y >= Map.MapCellY + Map.MapCellHeight) {
                    continue;
                }
                const CELL cell = XY_Cell(x, y);
                if (!Map.In_Radar(cell) || !Ground[Map[cell].Land_Type()].Cost[SPEED_FOOT]
                    || !Map[cell].Is_Clear_To_Move(false, false)) {
                    continue;
                }
                InfantryClass* infantry = new InfantryClass(type, house->Class->House);
                if (infantry == NULL
                    || !infantry->Unlimbo(
                        Cell_Coord(cell),
                        Direction8(Cell_Coord(cell), Cell_Coord(facing_target)))) {
                    delete infantry;
                    return false;
                }
                infantry->Assign_Mission(MISSION_GUARD);
                infantry->Commence();
                ++added;
            }
        }
    }
    return added == count;
}

bool Setup_Starting_Force()
{
    if (Units.Count() != TD_MICRO_PLAYER_COUNT || Infantry.Count() != 0 || Buildings.Count() != 0) {
        return false;
    }

    CELL starts[TD_MICRO_PLAYER_COUNT] = {};
    bool found[TD_MICRO_PLAYER_COUNT] = {};
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        const uint8_t owner = Logical_Owner(unit->House);
        if (owner >= TD_MICRO_PLAYER_COUNT || Unit_Kind(unit) != TD_MICRO_OBJECT_MCV || found[owner]) {
            return false;
        }
        starts[owner] = Coord_Cell(unit->Coord);
        found[owner] = true;
    }
    if (!found[0] || !found[1]) return false;

    HouseClass* player = Logical_House(0);
    HouseClass* opponent = Logical_House(1);
    const unsigned int gameplay_rng_state = Scen.RandomNumber.Seed;
    const bool added = player != NULL && opponent != NULL
        && Add_Curriculum_Infantry(
            player,
            INFANTRY_E1,
            TD_MICRO_STARTING_FORCE_E1_COUNT,
            starts[0],
            starts[1],
            3,
            6)
        && Add_Curriculum_Infantry(
            player,
            INFANTRY_E3,
            TD_MICRO_STARTING_FORCE_E3_COUNT,
            starts[0],
            starts[1],
            3,
            6)
        && Add_Curriculum_Infantry(
            opponent,
            INFANTRY_E1,
            TD_MICRO_STARTING_FORCE_E1_COUNT,
            starts[1],
            starts[0],
            3,
            6)
        && Add_Curriculum_Infantry(
            opponent,
            INFANTRY_E3,
            TD_MICRO_STARTING_FORCE_E3_COUNT,
            starts[1],
            starts[0],
            3,
            6);
    Scen.RandomNumber.Seed = gameplay_rng_state;
    return added;
}

bool Add_Curriculum_Building(HouseClass* house, StructType type, COORDINATE coordinate)
{
    BuildingClass* building = new BuildingClass(type, house->Class->House);
    if (building == NULL || !building->Unlimbo(coordinate)) {
        delete building;
        return false;
    }
    house->Adjust_Power(building->Class->Power);
    building->Grand_Opening();
    building->Assign_Mission(MISSION_GUARD);
    building->Commence();
    return true;
}

bool Add_Curriculum_Building_At_First_Legal_Cell(HouseClass* house, StructType type)
{
    BuildingTypeClass const& object = BuildingTypeClass::As_Reference(type);
    short const* footprint = object.Occupy_List(true);
    for (int y = 0; y < Map.MapCellHeight; ++y) {
        for (int x = 0; x < Map.MapCellWidth; ++x) {
            const CELL cell = XY_Cell(Map.MapCellX + x, Map.MapCellY + y);
            if (!object.Legal_Placement(cell)
                || !Map.Passes_Proximity_Check(&object, house->Class->House, footprint, cell)) {
                continue;
            }
            return Add_Curriculum_Building(house, type, Cell_Coord(cell));
        }
    }
    return false;
}

bool Setup_Combat_Curriculum_Fixture(uint8_t fixture)
{
    if (Units.Count() != TD_MICRO_PLAYER_COUNT || Buildings.Count() != 0) return false;
    COORDINATE mcv_coords[TD_MICRO_PLAYER_COUNT] = {};
    bool found[TD_MICRO_PLAYER_COUNT] = {};
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        const uint8_t owner = Logical_Owner(unit->House);
        if (owner >= TD_MICRO_PLAYER_COUNT || Unit_Kind(unit) != TD_MICRO_OBJECT_MCV || found[owner]) {
            return false;
        }
        mcv_coords[owner] = unit->Coord;
        found[owner] = true;
    }
    if (!found[0] || !found[1]) return false;
    for (int index = Units.Count() - 1; index >= 0; --index) delete Units.Ptr(index);

    for (int owner = 0; owner < TD_MICRO_PLAYER_COUNT; ++owner) {
        HouseClass* house = Logical_House(static_cast<uint8_t>(owner));
        if (house == NULL) return false;
        house->IsHuman = owner == 0;
        house->Credits = 0;
        house->InitialCredits = 0;
        house->Tiberium = 0;
        house->MaxInfantry = 0;
        house->BuildStructure = STRUCT_NONE;
        house->BuildUnit = UNIT_NONE;
        house->BuildInfantry = INFANTRY_NONE;
        house->BuildAircraft = AIRCRAFT_NONE;

        if (!Add_Curriculum_Building(
                house,
                STRUCT_CONST,
                Adjacent_Cell(mcv_coords[owner], FACING_NW))) return false;
    }

    HouseClass* player = Logical_House(0);
    HouseClass* opponent = Logical_House(1);
    const CELL player_start = Coord_Cell(mcv_coords[0]);
    const CELL opponent_start = Coord_Cell(mcv_coords[1]);
    const bool assault = fixture >= 6;
    const int e1_count = fixture == 3 || fixture == 6 ? 16 : fixture == 5 || fixture == 8 ? 8 : 0;
    const int e3_count = fixture == 4 || fixture == 7 ? 16 : fixture == 5 || fixture == 8 ? 8 : 0;
    const int min_radius = assault ? 11 : 3;
    const int max_radius = assault ? 22 : 10;
    return player != NULL && opponent != NULL
        && Add_Curriculum_Infantry(
            player, INFANTRY_E1, e1_count, opponent_start, opponent_start, min_radius, max_radius)
        && Add_Curriculum_Infantry(
            player, INFANTRY_E3, e3_count, opponent_start, opponent_start, min_radius, max_radius)
        && (!assault
            || (Add_Curriculum_Infantry(
                    opponent, INFANTRY_E1, 2, opponent_start, player_start, 3, 7)
                && Add_Curriculum_Infantry(
                    opponent, INFANTRY_E3, 2, opponent_start, player_start, 3, 7)));
}

bool Setup_Base_Curriculum_Fixture(uint8_t fixture)
{
    if (fixture < 9 || fixture > 11 || Units.Count() != TD_MICRO_PLAYER_COUNT
        || Buildings.Count() != 0) return false;
    UnitClass* player_mcv = NULL;
    COORDINATE player_start = 0;
    for (int index = 0; index < Units.Count(); ++index) {
        UnitClass* unit = Units.Ptr(index);
        if (Logical_Owner(unit->House) != 0 || Unit_Kind(unit) != TD_MICRO_OBJECT_MCV) continue;
        if (player_mcv != NULL) return false;
        player_mcv = unit;
        player_start = unit->Coord;
    }
    if (player_mcv == NULL) return false;
    delete player_mcv;

    HouseClass* player = Logical_House(0);
    if (player == NULL
        || !Add_Curriculum_Building(
            player, STRUCT_CONST, Adjacent_Cell(player_start, FACING_NW))) return false;
    if (fixture == 11) return true;
    if (!Add_Curriculum_Building_At_First_Legal_Cell(player, STRUCT_POWER)
        || !Add_Curriculum_Building_At_First_Legal_Cell(player, STRUCT_REFINERY)
        || (fixture == 9
            && !Add_Curriculum_Building_At_First_Legal_Cell(player, STRUCT_BARRACKS))) {
        return false;
    }
    player->Credits = fixture == 9 ? 1200 : 300;
    player->InitialCredits = player->Credits;
    return true;
}

} // namespace

void TDMicro_Reset_AI_Trace()
{
    AICommandCount = 0;
    AICommandOverflow = false;
    std::memset(AICommands, 0, sizeof(AICommands));
    std::memset(&AIObserved, 0, sizeof(AIObserved));
}

void TDMicro_Observe_AI_Commands()
{
    Observe_AI_Commands();
}

bool TDMicro_Add_Starting_Force()
{
    return TDMicro.Enabled() && MPlayerUnitCount == TD_MICRO_STARTING_FORCE_UNIT_COUNT
        && Setup_Starting_Force() && TDMicro.Validate_Active_Objects();
}

extern "C" __declspec(dllexport) bool __cdecl CNC_TD_Micro_Setup_Fixture(uint8_t fixture)
{
    if (!TDMicro.Enabled() || fixture < 1 || fixture > 12 || Frame != 0
        || Logical_Player_Count() != TD_MICRO_PLAYER_COUNT || Infantry.Count() != 0) {
        return false;
    }

    if (fixture == 12) {
        return Setup_Starting_Force() && TDMicro.Validate_Active_Objects();
    }
    if (fixture >= 3 && fixture <= 8) {
        return Setup_Combat_Curriculum_Fixture(fixture) && TDMicro.Validate_Active_Objects();
    }
    if (fixture >= 9) {
        return Setup_Base_Curriculum_Fixture(fixture) && TDMicro.Validate_Active_Objects();
    }

    static const uint8_t x[TD_MICRO_PLAYER_COUNT] = {20, 21};
    const InfantryType type = fixture == 1 ? INFANTRY_E1 : INFANTRY_E3;
    for (int owner = 0; owner < TD_MICRO_PLAYER_COUNT; ++owner) {
        HouseClass* house = Logical_House(static_cast<uint8_t>(owner));
        if (house == NULL) return false;
        house->IsHuman = true;
        const CELL cell = XY_Cell(Map.MapCellX + x[owner], Map.MapCellY + 20);
        COORDINATE coord = Map[cell].Closest_Free_Spot(Cell_Coord(cell));
        InfantryClass* infantry = new InfantryClass(type, house->Class->House);
        if (coord == 0 || infantry == NULL || !infantry->Unlimbo(coord, owner == 0 ? DIR_E : DIR_W)) {
            delete infantry;
            return false;
        }
        infantry->Assign_Mission(MISSION_GUARD);
        infantry->Commence();
    }
    return TDMicro.Validate_Active_Objects();
}

extern "C" __declspec(dllexport) bool __cdecl CNC_TD_Micro_Get_Snapshot(TdMicroOracleSnapshot* output,
                                                                         unsigned int output_size)
{
    const int player_count = Logical_Player_Count();
    if (!TDMicro.Enabled() || output == NULL || output_size < sizeof(*output)
        || player_count != TD_MICRO_PLAYER_COUNT) {
        return false;
    }

    TDMicro_Observe_AI_Commands();
    std::memset(output, 0, sizeof(*output));
    output->schema_version = TD_MICRO_ORACLE_SCHEMA_VERSION;
    output->frame = static_cast<uint32_t>(Frame);
    output->setup_seed = TDMicro.Oracle_Seed();
    output->rng_state = Scen.RandomNumber.Seed;
    output->map_x = static_cast<int16_t>(Map.MapCellX);
    output->map_y = static_cast<int16_t>(Map.MapCellY);
    output->map_width = static_cast<uint16_t>(Map.MapCellWidth);
    output->map_height = static_cast<uint16_t>(Map.MapCellHeight);
    output->player_count = static_cast<uint8_t>(player_count);
    output->content_violation = TDMicro.Had_Content_Violation();

    for (int index = 0; index < player_count; ++index) {
        HouseClass* house = Logical_House(static_cast<uint8_t>(index));
        if (house == NULL) {
            return false;
        }
        TdMicroOraclePlayer& player = output->players[index];
        player.credits = house->Credits;
        player.power = house->Power;
        player.drain = house->Drain;
        player.tiberium = house->Tiberium;
        player.capacity = house->Capacity;
        player.harvested_credits = house->HarvestedCredits;
        player.logical_id = static_cast<uint8_t>(index);
        player.house = static_cast<uint8_t>(house->Class->House);
        player.act_like = static_cast<uint8_t>(house->ActLike);
        player.is_human = house->IsHuman;
        player.difficulty = static_cast<uint8_t>(house->Difficulty);
        player.defeated = house->IsDefeated;

        if (!Fill_Queue(output->queues[index * 2], house, static_cast<uint8_t>(index), 0)
            || !Fill_Queue(output->queues[index * 2 + 1], house, static_cast<uint8_t>(index), 1)) {
            return false;
        }
    }
    if (!Fill_AI_State(output->ai, HouseClass::As_Pointer(MPlayerHouses[1]), 1)) return false;

    uint16_t count = 0;
    for (int index = 0; index < Units.Count(); ++index) {
        if (count >= TD_MICRO_ORACLE_MAX_ENTITIES
            || !Fill_Entity(output->entities[count], Units.Ptr(index), static_cast<uint16_t>(Units.ID(Units.Ptr(index))),
                            Unit_Kind(Units.Ptr(index)))) {
            return false;
        }
        ++count;
    }
    for (int index = 0; index < Buildings.Count(); ++index) {
        if (count >= TD_MICRO_ORACLE_MAX_ENTITIES
            || !Fill_Entity(output->entities[count], Buildings.Ptr(index),
                            static_cast<uint16_t>(Buildings.ID(Buildings.Ptr(index))),
                            Building_Kind(Buildings.Ptr(index)))) {
            return false;
        }
        ++count;
    }
    for (int index = 0; index < Infantry.Count(); ++index) {
        if (count >= TD_MICRO_ORACLE_MAX_ENTITIES
            || !Fill_Entity(output->entities[count], Infantry.Ptr(index),
                            static_cast<uint16_t>(Infantry.ID(Infantry.Ptr(index))),
                            Infantry_Kind(Infantry.Ptr(index)))) {
            return false;
        }
        ++count;
    }
    output->entity_count = count;

    uint16_t projectile_count = 0;
    for (int index = 0; index < Bullets.Count(); ++index) {
        if (projectile_count >= TD_MICRO_MAX_PROJECTILES) return false;
        BulletClass* bullet = Bullets.Ptr(index);
        TdMicroOracleProjectile& projectile = output->projectiles[projectile_count++];
        projectile.id = static_cast<uint16_t>(Bullets.ID(Bullets.Ptr(index)));
        projectile.type = static_cast<uint8_t>(bullet->Class->Type);
        projectile.active = bullet->IsActive;
        projectile.in_limbo = bullet->IsInLimbo;
        projectile.coord_x = Coord_X(bullet->Coord) - Cell_To_Lepton(Map.MapCellX);
        projectile.coord_y = Coord_Y(bullet->Coord) - Cell_To_Lepton(Map.MapCellY);
        projectile.fuse_x = Coord_X(bullet->Fuse_Target()) - Cell_To_Lepton(Map.MapCellX);
        projectile.fuse_y = Coord_Y(bullet->Fuse_Target()) - Cell_To_Lepton(Map.MapCellY);
        projectile.strength = bullet->Strength;
        projectile.facing = static_cast<int16_t>(bullet->PrimaryFacing.Current());
        projectile.desired_facing = static_cast<uint8_t>(bullet->TDMicro_Desired_Facing());
        projectile.speed = static_cast<uint8_t>(bullet->Get_Speed());
        projectile.speed_accum = static_cast<uint16_t>(bullet->TDMicro_Speed_Accum());
        projectile.timer = bullet->Timer;
        projectile.arming = bullet->TDMicro_Arming();
        projectile.proximity = bullet->TDMicro_Proximity();
        projectile.target = static_cast<uint64_t>(bullet->TDMicro_Target());
        projectile.source_owner = UINT8_MAX;
        projectile.source_kind = TD_MICRO_OBJECT_NONE;
        projectile.target_owner = UINT8_MAX;
        projectile.target_kind = TD_MICRO_OBJECT_NONE;
        if (bullet->Payback != NULL) {
            projectile.source_owner = Logical_Owner(bullet->Payback->House);
            projectile.source_kind = Techno_Kind(bullet->Payback);
            projectile.source_id = Techno_Id(bullet->Payback);
        }
        ObjectClass* target = As_Object(bullet->TDMicro_Target());
        if (target != NULL && target->Is_Techno()) {
            TechnoClass* target_techno = static_cast<TechnoClass*>(target);
            projectile.target_owner = Logical_Owner(target_techno->House);
            projectile.target_kind = Techno_Kind(target_techno);
            projectile.target_id = Techno_Id(target_techno);
        }
    }
    output->projectile_count = projectile_count;

    for (int y = 0; y < Map.MapCellHeight; ++y) {
        for (int x = 0; x < Map.MapCellWidth; ++x) {
            CellClass const& cell = Map[XY_Cell(Map.MapCellX + x, Map.MapCellY + y)];
            const int index = y * TD_MICRO_MAX_MAP_WIDTH + x;
            if (cell.Land_Type() == LAND_TIBERIUM) {
                output->tiberium_steps[index] = cell.OverlayData;
                output->tiberium_present[index / 64] |= UINT64_C(1) << (index % 64);
            }
        }
    }
    return Copy_AI_Commands(*output) && Aircraft.Count() == 0 && !TDMicro.Had_Content_Violation();
}

extern "C" __declspec(dllexport) bool __cdecl CNC_TD_Micro_Get_Map(TdMicroOracleMap* output,
                                                                    unsigned int output_size)
{
    if (!TDMicro.Enabled() || output == NULL || output_size < sizeof(*output)
        || Map.MapCellWidth > TD_MICRO_MAX_MAP_WIDTH || Map.MapCellHeight > TD_MICRO_MAX_MAP_HEIGHT) {
        return false;
    }

    std::memset(output, 0, sizeof(*output));
    output->schema_version = TD_MICRO_ORACLE_MAP_SCHEMA_VERSION;
    output->map_x = static_cast<int16_t>(Map.MapCellX);
    output->map_y = static_cast<int16_t>(Map.MapCellY);
    output->map_width = static_cast<uint16_t>(Map.MapCellWidth);
    output->map_height = static_cast<uint16_t>(Map.MapCellHeight);

    for (int y = 0; y < Map.MapCellHeight; ++y) {
        for (int x = 0; x < Map.MapCellWidth; ++x) {
            CellClass const& cell = Map[XY_Cell(Map.MapCellX + x, Map.MapCellY + y)];
            TdMicroOracleMapCell& exported = output->cells[y * Map.MapCellWidth + x];
            const LandType land = cell.Land_Type();
            exported.land_type = static_cast<uint8_t>(land);
            exported.foot_cost = static_cast<uint8_t>(Ground[land].Cost[SPEED_FOOT]);
            exported.ground_buildable = Ground[land].Build;
            exported.overlay = static_cast<int16_t>(cell.Overlay);
            exported.overlay_data = cell.OverlayData;

            for (ObjectClass const* object = cell.Cell_Occupier(); object != NULL; object = object->Next) {
                if (object->What_Am_I() == RTTI_TERRAIN) {
                    exported.static_blocked = true;
                    break;
                }
            }

            bool wall_blocked = false;
            if (cell.Overlay != OVERLAY_NONE) {
                OverlayTypeClass const& overlay = OverlayTypeClass::As_Reference(cell.Overlay);
                wall_blocked = overlay.IsWall && (cell.OverlayData / 16) != overlay.DamageLevels;
            }
            exported.foot_passable = exported.foot_cost != 0 && !exported.static_blocked && !wall_blocked;
        }
    }
    return true;
}
