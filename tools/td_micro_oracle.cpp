#include "td_micro_oracle.h"
#include "td_micro_api.h"

#include <dlfcn.h>

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

#include <unistd.h>

namespace {

constexpr int kMaxPlayers = 6;
constexpr int kMaxHouses = 32;
constexpr int kMaxExportCells = 128 * 128;
constexpr uint64_t kPlayerId = 1001;
constexpr uint64_t kOpponentId = 1002;

#pragma pack(push, 1)
struct CNCMultiplayerOptionsStruct {
    int MPlayerCount;
    int MPlayerBases;
    int MPlayerCredits;
    int MPlayerTiberium;
    int MPlayerGoodies;
    int MPlayerGhosts;
    int MPlayerSolo;
    int MPlayerUnitCount;
    bool IsMCVDeploy;
    bool SpawnVisceroids;
    bool EnableSuperweapons;
    bool MPlayerShadowRegrow;
    bool MPlayerAftermathUnits;
    bool CaptureTheFlag;
    bool DestroyStructures;
    bool ModernBalance;
};

struct CNCSpiedInfoStruct {
    int Power;
    int Drain;
    int Money;
};

struct CNCPlayerInfoStruct {
    char Name[64];
    unsigned char House;
    int ColorIndex;
    uint64_t GlyphxPlayerID;
    int Team;
    int StartLocationIndex;
    unsigned char HomeCellX;
    unsigned char HomeCellY;
    bool IsAI;
    unsigned int AllyFlags;
    bool IsDefeated;
    unsigned int SpiedPowerFlags;
    unsigned int SpiedMoneyFlags;
    CNCSpiedInfoStruct SpiedInfo[kMaxHouses];
    int SelectedID;
    int SelectedType;
    unsigned char ActionWithSelected[kMaxExportCells];
    unsigned int ActionWithSelectedCount;
    unsigned int ScreenShake;
    bool IsRadarJammed;
};
#pragma pack(pop)

static_assert(sizeof(CNCPlayerInfoStruct) == 16886, "CNCPlayerInfoStruct ABI mismatch");

using EventCallback = void (*)(const void*);
using InitFn = void (*)(const char*, EventCallback);
using ConfigureFn = bool (*)(const char*, unsigned int);
using ConfigureDifficultyFn = bool (*)(const char*, unsigned int, int);
using SetMultiplayerFn = bool (*)(int, CNCMultiplayerOptionsStruct&, int, CNCPlayerInfoStruct*, int);
using StartFn = bool (*)(int, int, int, int, const char*, const char*, const char*, int, const char*);
using AdvanceFn = bool (*)(uint64_t);
using SnapshotFn = bool (*)(TdMicroOracleSnapshot*, unsigned int);
using MapFn = bool (*)(TdMicroOracleMap*, unsigned int);
using FixtureFn = bool (*)(uint8_t);
using ActionFn = bool (*)(uint8_t, const TdMicroAction*);
using PolicyStateFn = bool (*)(uint8_t, uint8_t*, unsigned int, uint8_t*, unsigned int);

struct Api {
    void* library = nullptr;
    InitFn init = nullptr;
    ConfigureFn configure = nullptr;
    ConfigureDifficultyFn configure_difficulty = nullptr;
    SetMultiplayerFn set_multiplayer = nullptr;
    StartFn start = nullptr;
    AdvanceFn advance = nullptr;
    SnapshotFn snapshot = nullptr;
    MapFn map = nullptr;
    FixtureFn fixture = nullptr;
    ActionFn action = nullptr;
    PolicyStateFn policy_state = nullptr;
};

struct Options {
    std::string library = "Vanilla-Conquer/build-remastertd/tiberiandawn/TiberianDawn.so";
    std::string data = "td-data/";
    std::string output = "/tmp/td_micro_oracle.jsonl";
    std::string map_output;
    std::string policy_state_output;
    unsigned int seed = 1;
    int difficulty = -1;
    int action_owner = 0;
    int decisions = 16;
    int deploy_decision = -1;
    int power_decision = -1;
    int place_power_decision = -1;
    int place_x = 4;
    int place_y = 7;
    int barracks_decision = -1;
    int place_barracks_decision = -1;
    int barracks_x = 1;
    int barracks_y = 9;
    int weapons_factory_decision = -1;
    int place_weapons_factory_decision = -1;
    int weapons_factory_x = 6;
    int weapons_factory_y = 11;
    int medium_tank_decision = -1;
    int humvee_decision = -1;
    int refinery_decision = -1;
    int place_refinery_decision = -1;
    int refinery_x = 6;
    int refinery_y = 7;
    int e1_decision = -1;
    int e3_decision = -1;
    int move_decision = -1;
    int move_actor = 3;
    int move_x = 10;
    int move_y = 9;
    int fixture = 0;
    int attack_decision = -1;
    int attack_actor = 1;
    int attack_target = 1;
    int harvest_decision = -1;
    int harvest_actor = 0;
    int harvest_x = 0;
    int harvest_y = 0;
    int return_decision = -1;
    int return_actor = 0;
    int return_target = 3;
    int advance_frames = TD_MICRO_DECISION_FRAMES;
    int write_every = 1;
    int unit_count = 0;
};

void Event_Callback(const void* raw_event)
{
    constexpr int kDebugPrintEvent = 3;
    const auto* bytes = static_cast<const unsigned char*>(raw_event);
    if (*reinterpret_cast<const int*>(bytes) == kDebugPrintEvent) {
        const char* message = *reinterpret_cast<const char* const*>(bytes + 12);
        if (message != nullptr) std::cerr << "TD: " << message << '\n';
    }
}

template <typename T> T Symbol(void* library, const char* name)
{
    dlerror();
    void* value = dlsym(library, name);
    const char* error = dlerror();
    if (value == nullptr || error != nullptr) {
        std::cerr << "missing symbol " << name << ": " << (error ? error : "null") << '\n';
        std::exit(2);
    }
    return reinterpret_cast<T>(value);
}

Api Load_Api(const std::string& path)
{
    Api api;
    api.library = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (api.library == nullptr) {
        std::cerr << "dlopen failed: " << dlerror() << '\n';
        std::exit(2);
    }
    api.init = Symbol<InitFn>(api.library, "CNC_Init");
    api.configure = Symbol<ConfigureFn>(api.library, "CNC_TD_Micro_Configure");
    api.configure_difficulty =
        Symbol<ConfigureDifficultyFn>(api.library, "CNC_TD_Micro_Configure_Difficulty");
    api.set_multiplayer = Symbol<SetMultiplayerFn>(api.library, "CNC_Set_Multiplayer_Data");
    api.start = Symbol<StartFn>(api.library, "CNC_Start_Instance_Variation");
    api.advance = Symbol<AdvanceFn>(api.library, "CNC_Advance_Instance");
    api.snapshot = Symbol<SnapshotFn>(api.library, "CNC_TD_Micro_Get_Snapshot");
    api.map = Symbol<MapFn>(api.library, "CNC_TD_Micro_Get_Map");
    api.fixture = Symbol<FixtureFn>(api.library, "CNC_TD_Micro_Setup_Fixture");
    api.action = Symbol<ActionFn>(api.library, "CNC_TD_Micro_Apply_Action");
    api.policy_state = Symbol<PolicyStateFn>(api.library, "CNC_TD_Micro_Get_Policy_State");
    return api;
}

std::string Prepare_Startup_Config(const Options& options)
{
    const std::filesystem::path runtime =
        std::filesystem::temp_directory_path() / ("td_micro_oracle_" + std::to_string(getpid()));
    const std::filesystem::path user = runtime / "user";
    std::filesystem::create_directories(user);

    std::ofstream config(runtime / "CONQUER.INI", std::ios::trunc);
    if (!config) {
        std::cerr << "failed to create TD startup config in " << runtime << '\n';
        std::exit(2);
    }
    config << "[Paths]\nDataPath=" << options.data << "\nUserPath=" << user.string()
           << "\n\n[Intro]\nPlayIntro=no\n\n[Options]\nGameFrameLimit=0\n\n[Video]\nWindowed=yes\n";
    config.close();
    return (runtime / "td_micro_oracle").string();
}

void Set_Player(CNCPlayerInfoStruct& player,
                const char* name,
                uint64_t id,
                int color,
                bool is_ai,
                int team,
                int start)
{
    std::memset(&player, 0, sizeof(player));
    std::snprintf(player.Name, sizeof(player.Name), "%s", name);
    player.House = 0;
    player.ColorIndex = color;
    player.GlyphxPlayerID = id;
    player.Team = team;
    player.StartLocationIndex = start;
    player.IsAI = is_ai;
}

bool Validate_Reset(
    const TdMicroOracleSnapshot& snapshot,
    unsigned int seed,
    int unit_count,
    int requested_difficulty)
{
    if (snapshot.schema_version != TD_MICRO_ORACLE_SCHEMA_VERSION || snapshot.setup_seed != seed
        || snapshot.player_count != TD_MICRO_PLAYER_COUNT || snapshot.map_width > TD_MICRO_MAX_MAP_WIDTH
        || snapshot.map_height > TD_MICRO_MAX_MAP_HEIGHT || snapshot.content_violation != 0
        || snapshot.players[0].credits != TD_MICRO_INITIAL_CREDITS
        || snapshot.players[1].credits != TD_MICRO_INITIAL_CREDITS || snapshot.players[0].is_human != 1
        || snapshot.players[1].is_human != 0
        || snapshot.players[1].difficulty != 2 - requested_difficulty) {
        return false;
    }

    int live_mcvs = 0;
    int live_e1 = 0;
    int live_e3 = 0;
    for (uint16_t index = 0; index < snapshot.entity_count; ++index) {
        const TdMicroOracleEntity& entity = snapshot.entities[index];
        if (!entity.active || entity.in_limbo) continue;
        if (entity.kind == TD_MICRO_OBJECT_MCV) ++live_mcvs;
        if (entity.kind == TD_MICRO_OBJECT_E1) ++live_e1;
        if (entity.kind == TD_MICRO_OBJECT_E3) ++live_e3;
    }
    const int expected_e1 =
        unit_count == TD_MICRO_STARTING_FORCE_UNIT_COUNT ? 2 * TD_MICRO_STARTING_FORCE_E1_COUNT : 0;
    const int expected_e3 =
        unit_count == TD_MICRO_STARTING_FORCE_UNIT_COUNT ? 2 * TD_MICRO_STARTING_FORCE_E3_COUNT : 0;
    return snapshot.entity_count == 2 + 2 * unit_count && live_mcvs == 2
        && live_e1 == expected_e1 && live_e3 == expected_e3;
}

void Write_Snapshot(std::ostream& output,
                    int decision,
                    const TdMicroAction& action,
                    const TdMicroOracleSnapshot& snapshot)
{
    output << "{\"decision\":" << decision << ",\"action\":" << static_cast<int>(action.command)
           << ",\"actor\":" << static_cast<int>(action.actor)
           << ",\"product\":" << static_cast<int>(action.product)
           << ",\"target_kind\":" << static_cast<int>(action.target_kind)
           << ",\"target_x\":" << static_cast<int>(action.target_x)
           << ",\"target_y\":" << static_cast<int>(action.target_y)
           << ",\"target_slot\":" << static_cast<int>(action.target_slot)
           << ",\"frame\":" << snapshot.frame
           << ",\"setup_seed\":" << snapshot.setup_seed << ",\"rng_state\":" << snapshot.rng_state
           << ",\"map\":[" << snapshot.map_x << ',' << snapshot.map_y << ',' << snapshot.map_width << ','
           << snapshot.map_height << "],\"content_violation\":" << static_cast<int>(snapshot.content_violation)
           << ",\"players\":[";
    for (int index = 0; index < TD_MICRO_PLAYER_COUNT; ++index) {
        if (index != 0) output << ',';
        const TdMicroOraclePlayer& player = snapshot.players[index];
        output << "{\"id\":" << static_cast<int>(player.logical_id) << ",\"house\":"
               << static_cast<int>(player.house) << ",\"act_like\":" << static_cast<int>(player.act_like)
               << ",\"human\":" << static_cast<int>(player.is_human) << ",\"difficulty\":"
               << static_cast<int>(player.difficulty) << ",\"credits\":" << player.credits << ",\"power\":"
               << player.power << ",\"drain\":" << player.drain << ",\"tiberium\":" << player.tiberium
               << ",\"capacity\":" << player.capacity << ",\"harvested\":" << player.harvested_credits
               << ",\"defeated\":"
               << static_cast<int>(player.defeated) << '}';
    }
    const TdMicroOracleAIState& ai = snapshot.ai;
    output << "],\"ai\":{\"active\":" << static_cast<int>(ai.active) << ",\"owner\":"
           << static_cast<int>(ai.owner) << ",\"state\":" << static_cast<int>(ai.state) << ",\"started\":"
           << static_cast<int>(ai.started) << ",\"alerted\":" << static_cast<int>(ai.alerted)
           << ",\"base_building\":" << static_cast<int>(ai.base_building) << ",\"tiberium_short\":"
           << static_cast<int>(ai.tiberium_short) << ",\"difficulty\":" << static_cast<int>(ai.difficulty)
           << ",\"enemy\":" << static_cast<int>(ai.enemy) << ",\"ai_timer\":" << ai.ai_timer
           << ",\"attack_timer\":" << ai.attack_timer << ",\"build_structure\":"
           << static_cast<int>(ai.build_structure) << ",\"build_infantry\":"
           << static_cast<int>(ai.build_infantry) << ",\"unsupported_choice\":"
           << static_cast<int>(ai.unsupported_choice) << ",\"has_center\":" << static_cast<int>(ai.has_center)
           << ",\"center\":[" << ai.center_x << ',' << ai.center_y << "],\"radius\":" << ai.radius
           << ",\"current\":[" << ai.current_units << ',' << ai.current_buildings << ',' << ai.current_infantry
           << "],\"maximum\":[" << ai.max_units << ',' << ai.max_buildings << ',' << ai.max_infantry
           << "],\"quantities\":[" << ai.construction_yards << ',' << ai.power_plants << ',' << ai.barracks << ','
           << ai.refineries << ',' << ai.harvesters << ',' << ai.e1 << ',' << ai.e3 << "],\"scans\":["
           << ai.building_scan << ',' << ai.active_building_scan << ','
           << ai.infantry_scan << ',' << ai.active_infantry_scan << "]},\"ai_commands\":[";
    for (uint16_t index = 0; index < snapshot.ai_command_count; ++index) {
        if (index != 0) output << ',';
        const TdMicroOracleAICommand& command = snapshot.ai_commands[index];
        output << "{\"frame\":" << command.frame << ",\"sequence\":" << command.sequence << ",\"owner\":"
               << static_cast<int>(command.owner) << ",\"command\":" << static_cast<int>(command.command)
               << ",\"actor_kind\":" << static_cast<int>(command.actor_kind) << ",\"actor_id\":" << command.actor_id
               << ",\"product\":" << static_cast<int>(command.product) << ",\"target_kind\":"
               << static_cast<int>(command.target_kind) << ",\"target\":[" << command.target_x << ','
               << command.target_y << "],\"target_owner\":" << static_cast<int>(command.target_owner)
               << ",\"target_entity_kind\":" << static_cast<int>(command.target_entity_kind)
               << ",\"target_id\":" << command.target_id << '}';
    }
    output << "],\"queues\":[";
    for (int index = 0; index < TD_MICRO_ORACLE_QUEUE_COUNT; ++index) {
        if (index != 0) output << ',';
        const TdMicroOracleQueue& queue = snapshot.queues[index];
        output << "{\"owner\":" << static_cast<int>(queue.owner) << ",\"category\":"
               << static_cast<int>(queue.category) << ",\"active\":" << static_cast<int>(queue.active)
               << ",\"completed\":" << static_cast<int>(queue.completed) << ",\"product\":"
               << static_cast<int>(queue.product) << ",\"suspended\":" << static_cast<int>(queue.suspended)
               << ",\"stage\":" << queue.stage << ",\"timer\":" << static_cast<int>(queue.stage_timer)
               << ",\"rate\":" << static_cast<int>(queue.rate) << ",\"balance\":" << queue.balance << '}';
    }
    output << "],\"entities\":[";
    for (uint16_t index = 0; index < snapshot.entity_count; ++index) {
        if (index != 0) output << ',';
        const TdMicroOracleEntity& entity = snapshot.entities[index];
        output << "{\"id\":" << entity.id << ",\"kind\":" << static_cast<int>(entity.kind)
               << ",\"owner\":" << static_cast<int>(entity.owner) << ",\"active\":"
               << static_cast<int>(entity.active) << ",\"limbo\":" << static_cast<int>(entity.in_limbo)
               << ",\"cell\":[" << entity.cell_x << ',' << entity.cell_y << "],\"coord\":[" << entity.coord_x
               << ',' << entity.coord_y << "],\"head_coord\":[" << entity.head_coord_x << ','
               << entity.head_coord_y << "],\"health\":" << entity.health << ",\"max_health\":"
               << entity.max_health << ",\"facing\":" << entity.facing;
        // Emitted only for turret-equipped objects. Turret facing is meaningless for everything
        // else, and gating it here keeps every trace recorded before the CNC26 vehicle expansion
        // byte-identical, which is what the whole Vanilla parity method depends on.
        if (entity.has_turret) {
            output << ",\"turret_facing\":" << entity.turret_facing;
        }
        output << ",\"mission\":"
               << static_cast<int>(entity.mission) << ",\"queued_mission\":"
               << static_cast<int>(entity.queued_mission) << ",\"status\":" << static_cast<int>(entity.status)
               << ",\"cooldown\":" << static_cast<int>(entity.weapon_cooldown) << ",\"moving\":"
               << static_cast<int>(entity.moving) << ",\"firing\":" << static_cast<int>(entity.firing)
               << ",\"deploying\":" << static_cast<int>(entity.deploying) << ",\"target\":" << entity.target
               << ",\"speed\":" << static_cast<int>(entity.speed) << ",\"path_facing\":"
               << static_cast<int>(entity.path_facing) << ",\"new_destination\":"
               << static_cast<int>(entity.new_destination) << ",\"animation\":"
               << static_cast<int>(entity.animation) << ",\"animation_stage\":" << entity.animation_stage
               << ",\"animation_timer\":" << static_cast<int>(entity.animation_timer)
               << ",\"animation_rate\":" << static_cast<int>(entity.animation_rate) << ",\"prone\":"
               << static_cast<int>(entity.prone) << ",\"fear\":" << static_cast<int>(entity.fear)
               << ",\"ammo\":" << entity.ammo << ",\"kills\":" << entity.kills << ",\"second_shot\":"
               << static_cast<int>(entity.second_shot) << ",\"cargo\":" << static_cast<int>(entity.cargo_steps)
               << ",\"harvesting\":" << static_cast<int>(entity.harvesting)
               << ",\"destination\":" << entity.destination << '}';
    }
    output << "],\"projectiles\":[";
    for (uint16_t index = 0; index < snapshot.projectile_count; ++index) {
        if (index != 0) output << ',';
        const TdMicroOracleProjectile& projectile = snapshot.projectiles[index];
        output << "{\"id\":" << projectile.id << ",\"type\":" << static_cast<int>(projectile.type)
               << ",\"active\":" << static_cast<int>(projectile.active) << ",\"limbo\":"
               << static_cast<int>(projectile.in_limbo) << ",\"coord\":[" << projectile.coord_x << ','
               << projectile.coord_y << "],\"fuse\":[" << projectile.fuse_x << ',' << projectile.fuse_y
               << "],\"strength\":" << projectile.strength << ",\"facing\":" << projectile.facing
               << ",\"desired_facing\":" << static_cast<int>(projectile.desired_facing) << ",\"speed\":"
               << static_cast<int>(projectile.speed) << ",\"speed_accum\":" << projectile.speed_accum
               << ",\"timer\":" << static_cast<int>(projectile.timer) << ",\"arming\":"
               << static_cast<int>(projectile.arming) << ",\"proximity\":" << projectile.proximity
               << ",\"source_owner\":"
               << static_cast<int>(projectile.source_owner) << ",\"source_kind\":"
               << static_cast<int>(projectile.source_kind) << ",\"source_id\":" << projectile.source_id
               << ",\"target_owner\":" << static_cast<int>(projectile.target_owner) << ",\"target_kind\":"
               << static_cast<int>(projectile.target_kind) << ",\"target_id\":" << projectile.target_id
               << ",\"target\":" << projectile.target << '}';
    }
    output << "],\"tiberium\":[";
    bool first_tiberium = true;
    for (int y = 0; y < snapshot.map_height; ++y) {
        for (int x = 0; x < snapshot.map_width; ++x) {
            const int index = y * TD_MICRO_MAX_MAP_WIDTH + x;
            if ((snapshot.tiberium_present[index / 64] & (UINT64_C(1) << (index % 64))) == 0) continue;
            const uint8_t steps = snapshot.tiberium_steps[index];
            if (!first_tiberium) output << ',';
            first_tiberium = false;
            output << '[' << index << ',' << static_cast<int>(steps) << ']';
        }
    }
    output << "]}\n";
}

void Write_Map(std::ostream& output, const TdMicroOracleMap& map)
{
    output << "{\"map_schema\":" << map.schema_version << ",\"map\":[" << map.map_x << ',' << map.map_y
           << ',' << map.map_width << ',' << map.map_height << "],\"cell_fields\":[\"land\",\"foot_cost\","
           << "\"ground_buildable\",\"static_blocked\",\"foot_passable\",\"overlay\",\"overlay_data\"],"
           << "\"cells\":[";
    const unsigned int count = map.map_width * map.map_height;
    for (unsigned int index = 0; index < count; ++index) {
        if (index != 0) output << ',';
        const TdMicroOracleMapCell& cell = map.cells[index];
        output << '[' << static_cast<int>(cell.land_type) << ',' << static_cast<int>(cell.foot_cost) << ','
               << static_cast<int>(cell.ground_buildable) << ',' << static_cast<int>(cell.static_blocked) << ','
               << static_cast<int>(cell.foot_passable) << ',' << cell.overlay << ','
               << static_cast<int>(cell.overlay_data) << ']';
    }
    output << "]}\n";
}

bool Write_Policy_State(Api const& api, std::ostream& output)
{
    uint8_t observation[TD_MICRO_OBSERVATION_SIZE];
    uint8_t action_mask[TD_MICRO_ACTION_MASK_SIZE];
    if (!api.policy_state(0, observation, sizeof(observation), action_mask, sizeof(action_mask))) return false;
    output.write(reinterpret_cast<const char*>(observation), sizeof(observation));
    output.write(reinterpret_cast<const char*>(action_mask), sizeof(action_mask));
    return static_cast<bool>(output);
}

Options Parse_Options(int argc, char** argv)
{
    Options options;
    for (int index = 1; index < argc; ++index) {
        std::string argument = argv[index];
        auto value = [&](const char* name) -> const char* {
            if (++index >= argc) {
                std::cerr << "missing value for " << name << '\n';
                std::exit(2);
            }
            return argv[index];
        };
        if (argument == "--lib") {
            options.library = value("--lib");
        } else if (argument == "--data") {
            options.data = value("--data");
        } else if (argument == "--output") {
            options.output = value("--output");
        } else if (argument == "--map-output") {
            options.map_output = value("--map-output");
        } else if (argument == "--policy-state-output") {
            options.policy_state_output = value("--policy-state-output");
        } else if (argument == "--seed") {
            options.seed = static_cast<unsigned int>(std::strtoul(value("--seed"), nullptr, 10));
        } else if (argument == "--difficulty") {
            const std::string requested = value("--difficulty");
            if (requested == "easy") {
                options.difficulty = 0;
            } else if (requested == "normal") {
                options.difficulty = 1;
            } else if (requested == "hard") {
                options.difficulty = 2;
            } else {
                std::cerr << "--difficulty must be easy, normal, or hard\n";
                std::exit(2);
            }
        } else if (argument == "--action-owner") {
            options.action_owner = std::atoi(value("--action-owner"));
        } else if (argument == "--decisions") {
            options.decisions = std::atoi(value("--decisions"));
        } else if (argument == "--deploy-decision") {
            options.deploy_decision = std::atoi(value("--deploy-decision"));
        } else if (argument == "--power-decision") {
            options.power_decision = std::atoi(value("--power-decision"));
        } else if (argument == "--place-power-decision") {
            options.place_power_decision = std::atoi(value("--place-power-decision"));
        } else if (argument == "--place-x") {
            options.place_x = std::atoi(value("--place-x"));
        } else if (argument == "--place-y") {
            options.place_y = std::atoi(value("--place-y"));
        } else if (argument == "--barracks-decision") {
            options.barracks_decision = std::atoi(value("--barracks-decision"));
        } else if (argument == "--place-barracks-decision") {
            options.place_barracks_decision = std::atoi(value("--place-barracks-decision"));
        } else if (argument == "--barracks-x") {
            options.barracks_x = std::atoi(value("--barracks-x"));
        } else if (argument == "--barracks-y") {
            options.barracks_y = std::atoi(value("--barracks-y"));
        } else if (argument == "--weapons-factory-decision") {
            options.weapons_factory_decision = std::atoi(value("--weapons-factory-decision"));
        } else if (argument == "--place-weapons-factory-decision") {
            options.place_weapons_factory_decision = std::atoi(value("--place-weapons-factory-decision"));
        } else if (argument == "--weapons-factory-x") {
            options.weapons_factory_x = std::atoi(value("--weapons-factory-x"));
        } else if (argument == "--weapons-factory-y") {
            options.weapons_factory_y = std::atoi(value("--weapons-factory-y"));
        } else if (argument == "--medium-tank-decision") {
            options.medium_tank_decision = std::atoi(value("--medium-tank-decision"));
        } else if (argument == "--humvee-decision") {
            options.humvee_decision = std::atoi(value("--humvee-decision"));
        } else if (argument == "--refinery-decision") {
            options.refinery_decision = std::atoi(value("--refinery-decision"));
        } else if (argument == "--place-refinery-decision") {
            options.place_refinery_decision = std::atoi(value("--place-refinery-decision"));
        } else if (argument == "--refinery-x") {
            options.refinery_x = std::atoi(value("--refinery-x"));
        } else if (argument == "--refinery-y") {
            options.refinery_y = std::atoi(value("--refinery-y"));
        } else if (argument == "--e1-decision") {
            options.e1_decision = std::atoi(value("--e1-decision"));
        } else if (argument == "--e3-decision") {
            options.e3_decision = std::atoi(value("--e3-decision"));
        } else if (argument == "--move-decision") {
            options.move_decision = std::atoi(value("--move-decision"));
        } else if (argument == "--move-actor") {
            options.move_actor = std::atoi(value("--move-actor"));
        } else if (argument == "--move-x") {
            options.move_x = std::atoi(value("--move-x"));
        } else if (argument == "--move-y") {
            options.move_y = std::atoi(value("--move-y"));
        } else if (argument == "--fixture") {
            options.fixture = std::atoi(value("--fixture"));
        } else if (argument == "--attack-decision") {
            options.attack_decision = std::atoi(value("--attack-decision"));
        } else if (argument == "--attack-actor") {
            options.attack_actor = std::atoi(value("--attack-actor"));
        } else if (argument == "--attack-target") {
            options.attack_target = std::atoi(value("--attack-target"));
        } else if (argument == "--harvest-decision") {
            options.harvest_decision = std::atoi(value("--harvest-decision"));
        } else if (argument == "--harvest-actor") {
            options.harvest_actor = std::atoi(value("--harvest-actor"));
        } else if (argument == "--harvest-x") {
            options.harvest_x = std::atoi(value("--harvest-x"));
        } else if (argument == "--harvest-y") {
            options.harvest_y = std::atoi(value("--harvest-y"));
        } else if (argument == "--return-decision") {
            options.return_decision = std::atoi(value("--return-decision"));
        } else if (argument == "--return-actor") {
            options.return_actor = std::atoi(value("--return-actor"));
        } else if (argument == "--return-target") {
            options.return_target = std::atoi(value("--return-target"));
        } else if (argument == "--advance-frames") {
            options.advance_frames = std::atoi(value("--advance-frames"));
        } else if (argument == "--write-every") {
            options.write_every = std::atoi(value("--write-every"));
        } else if (argument == "--unit-count") {
            options.unit_count = std::atoi(value("--unit-count"));
        } else {
            std::cerr << "unknown argument: " << argument << '\n';
            std::exit(2);
        }
    }
    if (options.advance_frames <= 0 || options.advance_frames > TD_MICRO_DECISION_FRAMES) {
        std::cerr << "--advance-frames must be between 1 and " << TD_MICRO_DECISION_FRAMES << '\n';
        std::exit(2);
    }
    if (options.write_every <= 0) {
        std::cerr << "--write-every must be positive\n";
        std::exit(2);
    }
    if (options.unit_count != 0 && options.unit_count != TD_MICRO_STARTING_FORCE_UNIT_COUNT) {
        std::cerr << "--unit-count must be 0 or " << TD_MICRO_STARTING_FORCE_UNIT_COUNT << '\n';
        std::exit(2);
    }
    if (options.action_owner < 0 || options.action_owner >= TD_MICRO_PLAYER_COUNT) {
        std::cerr << "--action-owner must be 0 or 1\n";
        std::exit(2);
    }
    return options;
}

} // namespace

int main(int argc, char** argv)
{
    Options options = Parse_Options(argc, argv);
    Api api = Load_Api(options.library);
    const std::string startup_path = Prepare_Startup_Config(options);
    setenv("VANILLA_CONQUER_ARGV0", startup_path.c_str(), 1);
    api.init("-XQ", Event_Callback);
    const int requested_difficulty = options.difficulty < 0 ? 0 : options.difficulty;
    const bool configured = options.difficulty < 0
        ? api.configure(TD_MICRO_RULESET_ID, options.seed)
        : api.configure_difficulty(TD_MICRO_RULESET_ID, options.seed, requested_difficulty);
    if (!configured) {
        std::cerr << "TD Micro configuration rejected\n";
        return 1;
    }

    CNCMultiplayerOptionsStruct multiplayer{};
    multiplayer.MPlayerCount = 2;
    multiplayer.MPlayerBases = 1;
    multiplayer.MPlayerCredits = TD_MICRO_INITIAL_CREDITS;
    multiplayer.MPlayerTiberium = 0;
    multiplayer.MPlayerGhosts = 1;
    multiplayer.MPlayerSolo = 1;
    multiplayer.MPlayerUnitCount = options.unit_count;
    multiplayer.IsMCVDeploy = true;
    multiplayer.DestroyStructures = true;

    CNCPlayerInfoStruct players[kMaxPlayers]{};
    Set_Player(players[0], "TDMicro", kPlayerId, 0, false, 0, 0);
    Set_Player(players[1], "OriginalAI", kOpponentId, 1, true, 1, 1);
    if (!api.set_multiplayer(1, multiplayer, 2, players, kMaxPlayers)) {
        std::cerr << "CNC_Set_Multiplayer_Data rejected TD Micro scenario 1\n";
        return 1;
    }
    if (!api.start(1, 0, 0, 98, "GDI", "GAME_GLYPHX_MULTIPLAYER", options.data.c_str(), -1, nullptr)) {
        std::cerr << "CNC_Start_Instance_Variation failed TD Micro scenario 1\n";
        return 1;
    }
    if (options.fixture != 0 && !api.fixture(static_cast<uint8_t>(options.fixture))) {
        std::cerr << "CNC_TD_Micro_Setup_Fixture rejected fixture " << options.fixture << '\n';
        return 1;
    }

    if (!options.map_output.empty()) {
        TdMicroOracleMap map{};
        if (!api.map(&map, sizeof(map))) {
            std::cerr << "CNC_TD_Micro_Get_Map failed\n";
            return 1;
        }
        std::ofstream map_file(options.map_output, std::ios::trunc);
        if (!map_file) {
            std::cerr << "failed to open map trace: " << options.map_output << '\n';
            return 1;
        }
        Write_Map(map_file, map);
    }

    std::ofstream policy_state;
    if (!options.policy_state_output.empty()) {
        policy_state.open(options.policy_state_output, std::ios::binary | std::ios::trunc);
        if (!policy_state || !Write_Policy_State(api, policy_state)) {
            std::cerr << "failed to write policy state: " << options.policy_state_output << '\n';
            return 2;
        }
    }

    std::ofstream trace(options.output, std::ios::trunc);
    if (!trace) {
        std::cerr << "failed to open trace: " << options.output << '\n';
        return 1;
    }
    if (options.difficulty < 0 && options.action_owner == 0) {
        trace << "{\"trace_schema\":5,\"ruleset\":\"" << TD_MICRO_RULESET_ID
              << "\",\"manifest\":\"" << TD_MICRO_MANIFEST_SHA256 << "\",\"seed\":"
              << options.seed << ",\"decision_frames\":" << options.advance_frames
              << ",\"write_every\":" << options.write_every << "}\n";
    } else {
        trace << "{\"trace_schema\":6,\"ruleset\":\"" << TD_MICRO_RULESET_ID
              << "\",\"manifest\":\"" << TD_MICRO_MANIFEST_SHA256 << "\",\"seed\":"
              << options.seed << ",\"decision_frames\":" << options.advance_frames
              << ",\"write_every\":" << options.write_every
              << ",\"difficulty_requested\":" << requested_difficulty
              << ",\"difficulty_internal\":" << 2 - requested_difficulty
              << ",\"action_owner\":" << options.action_owner << "}\n";
    }

    TdMicroOracleSnapshot snapshot{};
    if (!api.snapshot(&snapshot, sizeof(snapshot))) {
        std::cerr << "CNC_TD_Micro_Get_Snapshot failed at reset\n";
        return 1;
    }
    Write_Snapshot(trace, 0, TdMicroAction{}, snapshot);
    trace.flush();
    if (options.fixture == 0
        && !Validate_Reset(snapshot, options.seed, options.unit_count, requested_difficulty)) {
        std::cerr << "reset snapshot failed TD Micro invariants; inspect " << options.output << '\n';
        return 1;
    }

    bool alive = true;
    int completed_decisions = 0;
    for (int decision = 1; decision <= options.decisions && alive; ++decision) {
        TdMicroAction action{};
        if (decision == options.deploy_decision) {
            action.command = TD_MICRO_COMMAND_DEPLOY;
            action.actor = 0;
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected deploy at decision " << decision << '\n';
                return 1;
            }
        } else if (decision == options.power_decision) {
            action.command = TD_MICRO_COMMAND_START_BUILD;
            action.product = TD_MICRO_OBJECT_POWER_PLANT;
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected power production at decision " << decision << '\n';
                return 1;
            }
        } else if (decision == options.place_power_decision) {
            action.command = TD_MICRO_COMMAND_PLACE;
            action.product = TD_MICRO_OBJECT_POWER_PLANT;
            action.target_kind = TD_MICRO_TARGET_CELL;
            action.target_x = static_cast<uint8_t>(options.place_x);
            action.target_y = static_cast<uint8_t>(options.place_y);
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected power placement at decision " << decision << " cell "
                          << options.place_x << ',' << options.place_y << '\n';
                return 1;
            }
        } else if (decision == options.barracks_decision) {
            action.command = TD_MICRO_COMMAND_START_BUILD;
            action.product = TD_MICRO_OBJECT_BARRACKS;
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected Barracks production at decision " << decision << '\n';
                return 1;
            }
        } else if (decision == options.place_barracks_decision) {
            action.command = TD_MICRO_COMMAND_PLACE;
            action.product = TD_MICRO_OBJECT_BARRACKS;
            action.target_kind = TD_MICRO_TARGET_CELL;
            action.target_x = static_cast<uint8_t>(options.barracks_x);
            action.target_y = static_cast<uint8_t>(options.barracks_y);
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected Barracks placement at decision " << decision << " cell "
                          << options.barracks_x << ',' << options.barracks_y << '\n';
                return 1;
            }
        } else if (decision == options.refinery_decision) {
            action.command = TD_MICRO_COMMAND_START_BUILD;
            action.product = TD_MICRO_OBJECT_REFINERY;
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected Refinery production at decision " << decision << '\n';
                return 1;
            }
        } else if (decision == options.place_refinery_decision) {
            action.command = TD_MICRO_COMMAND_PLACE;
            action.product = TD_MICRO_OBJECT_REFINERY;
            action.target_kind = TD_MICRO_TARGET_CELL;
            action.target_x = static_cast<uint8_t>(options.refinery_x);
            action.target_y = static_cast<uint8_t>(options.refinery_y);
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected Refinery placement at decision " << decision << " cell "
                          << options.refinery_x << ',' << options.refinery_y << '\n';
                return 1;
            }
        } else if (decision == options.weapons_factory_decision) {
            action.command = TD_MICRO_COMMAND_START_BUILD;
            action.product = TD_MICRO_OBJECT_WEAPONS_FACTORY;
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected Weapons Factory production at decision " << decision << '\n';
                return 1;
            }
        } else if (decision == options.place_weapons_factory_decision) {
            action.command = TD_MICRO_COMMAND_PLACE;
            action.product = TD_MICRO_OBJECT_WEAPONS_FACTORY;
            action.target_kind = TD_MICRO_TARGET_CELL;
            action.target_x = static_cast<uint8_t>(options.weapons_factory_x);
            action.target_y = static_cast<uint8_t>(options.weapons_factory_y);
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected Weapons Factory placement at decision " << decision << " cell "
                          << options.weapons_factory_x << ',' << options.weapons_factory_y << '\n';
                return 1;
            }
        } else if (decision == options.medium_tank_decision) {
            action.command = TD_MICRO_COMMAND_START_BUILD;
            action.product = TD_MICRO_OBJECT_MEDIUM_TANK;
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected Medium Tank production at decision " << decision << '\n';
                return 1;
            }
        } else if (decision == options.humvee_decision) {
            action.command = TD_MICRO_COMMAND_START_BUILD;
            action.product = TD_MICRO_OBJECT_HUMVEE;
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected Humvee production at decision " << decision << '\n';
                return 1;
            }
        } else if (decision == options.e1_decision) {
            action.command = TD_MICRO_COMMAND_TRAIN;
            action.product = TD_MICRO_OBJECT_E1;
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected E1 train/release at decision " << decision << '\n';
                return 1;
            }
        } else if (decision == options.e3_decision) {
            action.command = TD_MICRO_COMMAND_TRAIN;
            action.product = TD_MICRO_OBJECT_E3;
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected E3 train/release at decision " << decision << '\n';
                return 1;
            }
        } else if (decision == options.move_decision) {
            action.command = TD_MICRO_COMMAND_MOVE;
            action.actor = static_cast<uint8_t>(options.move_actor);
            action.target_kind = TD_MICRO_TARGET_CELL;
            action.target_x = static_cast<uint8_t>(options.move_x);
            action.target_y = static_cast<uint8_t>(options.move_y);
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected move at decision " << decision << " actor "
                          << options.move_actor << " cell " << options.move_x << ',' << options.move_y << '\n';
                return 1;
            }
        } else if (decision == options.attack_decision) {
            action.command = TD_MICRO_COMMAND_ATTACK;
            action.actor = static_cast<uint8_t>(options.attack_actor);
            action.target_kind = TD_MICRO_TARGET_VISIBLE_ENEMY;
            action.target_slot = static_cast<uint8_t>(options.attack_target);
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected attack at decision " << decision << " actor "
                          << options.attack_actor << " target " << options.attack_target << '\n';
                return 1;
            }
        } else if (decision == options.harvest_decision) {
            action.command = TD_MICRO_COMMAND_HARVEST;
            action.actor = static_cast<uint8_t>(options.harvest_actor);
            action.target_kind = TD_MICRO_TARGET_CELL;
            action.target_x = static_cast<uint8_t>(options.harvest_x);
            action.target_y = static_cast<uint8_t>(options.harvest_y);
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected harvest at decision " << decision << " actor "
                          << options.harvest_actor << " cell " << options.harvest_x << ',' << options.harvest_y
                          << '\n';
                return 1;
            }
        } else if (decision == options.return_decision) {
            action.command = TD_MICRO_COMMAND_RETURN_CARGO;
            action.actor = static_cast<uint8_t>(options.return_actor);
            action.target_kind = TD_MICRO_TARGET_OWN_ENTITY;
            action.target_slot = static_cast<uint8_t>(options.return_target);
            if (!api.action(options.action_owner, &action)) {
                std::cerr << "Vanilla rejected return cargo at decision " << decision << " actor "
                          << options.return_actor << " target " << options.return_target << '\n';
                return 1;
            }
        }
        TdMicroOracleAICommand ai_commands[TD_MICRO_ORACLE_MAX_AI_COMMANDS] = {};
        uint16_t ai_command_count = 0;
        for (int frame = 0; frame < options.advance_frames; ++frame) {
            alive = api.advance(kPlayerId);
            TdMicroOracleSnapshot frame_snapshot{};
            if (!api.snapshot(&frame_snapshot, sizeof(frame_snapshot))) {
                std::cerr << "snapshot failed at decision " << decision << " frame " << frame + 1 << '\n';
                return 1;
            }
            for (uint16_t index = 0; index < frame_snapshot.ai_command_count; ++index) {
                if (ai_command_count >= TD_MICRO_ORACLE_MAX_AI_COMMANDS) {
                    std::cerr << "AI command aggregation overflow at decision " << decision << '\n';
                    return 1;
                }
                ai_commands[ai_command_count] = frame_snapshot.ai_commands[index];
                ai_commands[ai_command_count].sequence = ai_command_count;
                ++ai_command_count;
            }
            snapshot = frame_snapshot;
            if (!alive) break;
        }
        snapshot.ai_command_count = ai_command_count;
        std::memcpy(snapshot.ai_commands, ai_commands, sizeof(ai_commands[0]) * ai_command_count);
        if (policy_state.is_open() && !Write_Policy_State(api, policy_state)) {
            std::cerr << "failed to write policy state at decision " << decision << '\n';
            return 2;
        }
        if (ai_command_count != 0 || decision % options.write_every == 0 || decision == options.decisions || !alive) {
            Write_Snapshot(trace, decision, action, snapshot);
        }
        completed_decisions = decision;
    }
    trace.close();
    std::cout << "trace=" << options.output << " decisions=" << completed_decisions << " frame=" << snapshot.frame
              << " map=" << snapshot.map_width << 'x' << snapshot.map_height << " entities=" << snapshot.entity_count
              << " alive=" << (alive ? 1 : 0) << '\n';
    return 0;
}
