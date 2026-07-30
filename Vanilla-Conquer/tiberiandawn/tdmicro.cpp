#include "tdmicro.h"

#include "function.h"
#include "td_micro_api.h"
#include "td_micro_v1.h"

#include <cstdio>
#include <cerrno>
#include <cstdlib>
#include <cstring>

TDMicroSettings TDMicro;

namespace {

const uint64_t DEFAULT_POLICY_SAMPLING_SEED = 74;

bool Read_Policy_Sampling_Seed(uint64_t& output)
{
    output = DEFAULT_POLICY_SAMPLING_SEED;
    const char* value = std::getenv("TD_MICRO_POLICY_SAMPLE_SEED");
    if (value == NULL || value[0] == '\0') return true;

    for (const char* cursor = value; *cursor != '\0'; ++cursor) {
        if (*cursor < '0' || *cursor > '9') return false;
    }
    errno = 0;
    char* end = NULL;
    const unsigned long long parsed = std::strtoull(value, &end, 10);
    if (errno == ERANGE || end == value || *end != '\0') return false;
    output = static_cast<uint64_t>(parsed);
    return true;
}

bool Read_Starting_Unit_Count(int& output)
{
    output = 0;
    const char* value = std::getenv("TD_MICRO_STARTING_UNITS");
    if (value == NULL || value[0] == '\0') return true;
    if (std::strcmp(value, "0") == 0) return true;
    if (std::strcmp(value, "6") == 0) {
        output = TD_MICRO_STARTING_FORCE_UNIT_COUNT;
        return true;
    }
    return false;
}

} // namespace

TDMicroPolicyOutcome TDMicro_Classify_Policy_Outcome(int frame, bool player_defeated, bool opponent_defeated)
{
    if (player_defeated && opponent_defeated) return TD_MICRO_POLICY_DRAW;
    if (player_defeated) return TD_MICRO_POLICY_LOSS;
    if (opponent_defeated) return TD_MICRO_POLICY_WIN;
    if (frame >= static_cast<int>(TD_MICRO_TRAINING_TIMEOUT_FRAMES)) return TD_MICRO_POLICY_TIMEOUT;
    return TD_MICRO_POLICY_RUNNING;
}

TDMicroSettings::TDMicroSettings()
    : IsEnabled(false)
    , DifficultyActive(false)
    , HasContentViolation(false)
    , HasOracleSeed(false)
    , OracleSeed(0)
    , ScenarioSeed(1)
    , OpponentDifficulty(DIFF_EASY)
    , PolicySamplingSeed(DEFAULT_POLICY_SAMPLING_SEED)
    , HasValidPolicySamplingSeed(true)
    , StartingUnitCount(0)
    , HasValidStartingUnitCount(true)
{
    std::strcpy(PlayerBrain, "Human");
    OpponentBrain[0] = '\0';
    PolicyPath[0] = '\0';
}

void TDMicroSettings::Load(INIClass const& ini)
{
    TDMicro_Reset_AI_Trace();
    TDMicro_Policy_Reset();
    char ruleset[64];
    ini.Get_String("TDMicro", "Ruleset", "", ruleset, sizeof(ruleset));
    ini.Get_String("TDMicro", "PlayerBrain", "Human", PlayerBrain, sizeof(PlayerBrain));
    ini.Get_String("TDMicro", "OpponentBrain", "OriginalAI", OpponentBrain, sizeof(OpponentBrain));
    ini.Get_String("TDMicro", "PolicyPath", "", PolicyPath, sizeof(PolicyPath));
    ScenarioSeed = static_cast<unsigned int>(ini.Get_Int("TDMicro", "Seed", 1));
    if (ScenarioSeed == 0 || ScenarioSeed > TD_MICRO_SPAWN_PROFILE_COUNT) ScenarioSeed = 1;
    OpponentDifficulty = ini.Get_Int("TDMicro", "OpponentDifficulty", DIFF_EASY);
    if (OpponentDifficulty < DIFF_EASY || OpponentDifficulty > DIFF_HARD) OpponentDifficulty = DIFF_EASY;
    DifficultyActive = true;
    HasValidPolicySamplingSeed = Read_Policy_Sampling_Seed(PolicySamplingSeed);
    HasValidStartingUnitCount = Read_Starting_Unit_Count(StartingUnitCount);

    IsEnabled = std::strcmp(ruleset, TD_MICRO_RULESET_ID) == 0;
    HasContentViolation = false;
    HasOracleSeed = false;
    OracleSeed = 0;
    if (IsEnabled && std::strcmp(OpponentBrain, "OriginalAI") != 0
        && std::strcmp(OpponentBrain, "PufferPolicy") != 0) {
        IsEnabled = false;
    }
    if (IsEnabled && std::strcmp(PlayerBrain, "Human") != 0
        && std::strcmp(PlayerBrain, "PufferPolicy") != 0) {
        IsEnabled = false;
    }
    if (IsEnabled && !HasValidStartingUnitCount) IsEnabled = false;
    if (ruleset[0] != '\0') {
        std::fprintf(stderr,
                     "TD Micro: ruleset=%s enabled=%s player=%s opponent=%s\n",
                     ruleset,
                     IsEnabled ? "yes" : "no",
                     PlayerBrain,
                     OpponentBrain);
    }
}

bool TDMicroSettings::Configure_Oracle(char const* ruleset, unsigned int seed)
{
    return Configure_Oracle_Impl(ruleset, seed, DIFF_EASY, false);
}

bool TDMicroSettings::Configure_Oracle_Difficulty(
    char const* ruleset,
    unsigned int seed,
    int opponent_difficulty)
{
    return Configure_Oracle_Impl(ruleset, seed, opponent_difficulty, true);
}

bool TDMicroSettings::Configure_Oracle_Impl(
    char const* ruleset,
    unsigned int seed,
    int opponent_difficulty,
    bool difficulty_active)
{
    TDMicro_Reset_AI_Trace();
    TDMicro_Policy_Reset();
    IsEnabled = ruleset != NULL && std::strcmp(ruleset, TD_MICRO_RULESET_ID) == 0 && seed > 0
        && seed <= TD_MICRO_SPAWN_PROFILE_COUNT;
    HasContentViolation = false;
    HasOracleSeed = IsEnabled;
    OracleSeed = IsEnabled ? seed : 0;
    const bool valid_difficulty = opponent_difficulty >= DIFF_EASY && opponent_difficulty <= DIFF_HARD;
    IsEnabled = IsEnabled && valid_difficulty;
    DifficultyActive = difficulty_active;
    OpponentDifficulty = valid_difficulty ? opponent_difficulty : DIFF_EASY;
    PolicySamplingSeed = DEFAULT_POLICY_SAMPLING_SEED;
    HasValidPolicySamplingSeed = true;
    StartingUnitCount = 0;
    HasValidStartingUnitCount = true;
    std::strcpy(PlayerBrain, "Human");
    std::strcpy(OpponentBrain, "OriginalAI");
    PolicyPath[0] = '\0';
    Apply_Rules();
    return IsEnabled;
}

void TDMicroSettings::Apply_Rules() const
{
    if (!IsEnabled) return;

    // TD Micro is a versioned simulation contract; user RULES.INI overrides must not alter it.
    RulesClass pinned_rules;
    pinned_rules.AttackDelay = TD_MICRO_ATTACK_DELAY;
    for (int index = 0; index < DIFF_COUNT; ++index) {
        if (!DifficultyActive) {
            pinned_rules.Diff[index] = DifficultyClass();
            continue;
        }
        const TdMicroDifficultyHandicap& source = TD_MICRO_DIFFICULTY_HANDICAPS[index];
        DifficultyClass& target = pinned_rules.Diff[index];
        target.FirepowerBias = fixed(source.firepower_bias.numerator, source.firepower_bias.denominator);
        target.GroundspeedBias = fixed(source.groundspeed_bias.numerator, source.groundspeed_bias.denominator);
        target.AirspeedBias = fixed(source.airspeed_bias.numerator, source.airspeed_bias.denominator);
        target.ArmorBias = fixed(source.armor_bias.numerator, source.armor_bias.denominator);
        target.ROFBias = fixed(source.rof_bias.numerator, source.rof_bias.denominator);
        target.CostBias = fixed(source.cost_bias.numerator, source.cost_bias.denominator);
        target.BuildSpeedBias = fixed(source.build_speed_bias.numerator, source.build_speed_bias.denominator);
        target.RepairDelay = fixed(source.repair_delay.numerator, source.repair_delay.denominator);
        target.BuildDelay = fixed(source.build_delay.numerator, source.build_delay.denominator);
        target.IsBuildSlowdown = source.build_slowdown;
        target.IsWallDestroyer = source.wall_destroyer;
        target.IsContentScan = source.content_scan;
    }
    Rule = pinned_rules;
}

bool TDMicroSettings::Enabled() const
{
    return IsEnabled;
}

bool TDMicroSettings::Auto_Start_Skirmish() const
{
    return IsEnabled && std::strcmp(PlayerBrain, "PufferPolicy") == 0;
}

bool TDMicroSettings::Allows_Object(TDMicroObjectCategory category, int type) const
{
    if (!IsEnabled)
        return true;

    switch (category) {
    case TD_MICRO_CATEGORY_UNIT:
        // CNC26 combat vehicles. Unlike Allows_Production this is not gated to the human side:
        // once an object exists it is legal for either player to see or destroy it.
        return type == UNIT_MCV || type == UNIT_HARVESTER || type == UNIT_MTANK || type == UNIT_JEEP;
    case TD_MICRO_CATEGORY_BUILDING:
        return type == STRUCT_CONST || type == STRUCT_POWER || type == STRUCT_BARRACKS
            || type == STRUCT_REFINERY || type == STRUCT_WEAP;
    case TD_MICRO_CATEGORY_INFANTRY:
        return type == INFANTRY_E1 || type == INFANTRY_E3;
    default:
        return false;
    }
}

bool TDMicroSettings::Allows_Production(TDMicroObjectCategory category, int type, bool is_human) const
{
    if (!IsEnabled)
        return true;

    switch (category) {
    case TD_MICRO_CATEGORY_BUILDING:
        // The Weapons Factory is CNC26 and policy-side only, for the same reason as the vehicles
        // below: the original AI has no validated behaviour for it, and letting it order one
        // changes every recorded AI opening trace.
        if (type == STRUCT_WEAP) return is_human;
        return type == STRUCT_POWER || type == STRUCT_BARRACKS || type == STRUCT_REFINERY;
    case TD_MICRO_CATEGORY_INFANTRY:
        return type == INFANTRY_E1 || type == INFANTRY_E3;
    case TD_MICRO_CATEGORY_UNIT:
        // The MCV and Harvester arrive with the opening or the Refinery rather than being
        // ordered, so only the CNC26 combat vehicles are buildable here. Deliberately restricted
        // to the human/policy side: the original AI has no validated vehicle behaviour, and
        // letting it order tanks changes every recorded AI opening trace.
        return is_human && (type == UNIT_MTANK || type == UNIT_JEEP);
    default:
        return false;
    }
}

bool TDMicroSettings::Allows_Crew_Survivors() const
{
    return !IsEnabled;
}

bool TDMicroSettings::Is_Skirmish_Opponent_House(int house, int game_type, int ghost_count) const
{
    return IsEnabled && game_type == GAME_SKIRMISH && ghost_count == 1 && house == HOUSE_MULTI1;
}

char const* TDMicroSettings::Player_Brain() const
{
    return PlayerBrain;
}

char const* TDMicroSettings::Opponent_Brain() const
{
    return OpponentBrain;
}

int TDMicroSettings::Opponent_Difficulty() const
{
    return OpponentDifficulty;
}

int TDMicroSettings::Opponent_Handicap() const
{
    // The skirmish menu inverts the player's requested difficulty for the computer house.
    if (OpponentDifficulty == DIFF_EASY) return DIFF_HARD;
    if (OpponentDifficulty == DIFF_HARD) return DIFF_EASY;
    return DIFF_NORMAL;
}

unsigned int TDMicroSettings::Setup_Seed() const
{
    return HasOracleSeed ? OracleSeed : ScenarioSeed;
}

int TDMicroSettings::Spawn_Bucket() const
{
    const unsigned int seed = Setup_Seed();
    if (!IsEnabled || seed == 0 || seed > TD_MICRO_SPAWN_PROFILE_COUNT) return -1;
    return TD_MICRO_SPAWN_PROFILES[seed - 1].bucket;
}

bool TDMicroSettings::Start_Coordinate(bool player, int& x, int& y) const
{
    const unsigned int seed = Setup_Seed();
    if (!IsEnabled || seed == 0 || seed > TD_MICRO_SPAWN_PROFILE_COUNT) return false;
    const TdMicroSpawnProfile& profile = TD_MICRO_SPAWN_PROFILES[seed - 1];
    x = player ? profile.player_x : profile.opponent_x;
    y = player ? profile.player_y : profile.opponent_y;
    return true;
}

unsigned int TDMicroSettings::Reset_RNG_State() const
{
    static const unsigned int reset_rng_states[TD_MICRO_SPAWN_PROFILE_COUNT] = {
        3488684595u,
        2093743367u,
    };
    const unsigned int seed = Setup_Seed();
    if (!IsEnabled || seed == 0 || seed > TD_MICRO_SPAWN_PROFILE_COUNT) return 0;
    return reset_rng_states[seed - 1];
}

char const* TDMicroSettings::Policy_Path() const
{
    return PolicyPath;
}

bool TDMicroSettings::Policy_Sampling_Seed(uint64_t& seed) const
{
    seed = PolicySamplingSeed;
    return HasValidPolicySamplingSeed;
}

int TDMicroSettings::Starting_Unit_Count() const
{
    return StartingUnitCount;
}

bool TDMicroSettings::Has_Oracle_Seed() const
{
    return HasOracleSeed;
}

unsigned int TDMicroSettings::Oracle_Seed() const
{
    return OracleSeed;
}
