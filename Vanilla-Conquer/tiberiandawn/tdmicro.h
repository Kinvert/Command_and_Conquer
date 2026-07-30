#ifndef TD_TDMICRO_H
#define TD_TDMICRO_H

#include <stdint.h>

class INIClass;
class TechnoClass;

enum TDMicroObjectCategory
{
    TD_MICRO_CATEGORY_UNIT,
    TD_MICRO_CATEGORY_BUILDING,
    TD_MICRO_CATEGORY_INFANTRY,
    TD_MICRO_CATEGORY_OTHER,
};

enum TDMicroPolicyOutcome
{
    TD_MICRO_POLICY_RUNNING,
    TD_MICRO_POLICY_WIN,
    TD_MICRO_POLICY_LOSS,
    TD_MICRO_POLICY_DRAW,
    TD_MICRO_POLICY_TIMEOUT,
};

class TDMicroSettings
{
public:
    TDMicroSettings();

    void Load(INIClass const& ini);
    bool Configure_Oracle(char const* ruleset, unsigned int seed);
    bool Configure_Oracle_Difficulty(char const* ruleset, unsigned int seed, int opponent_difficulty);
    void Apply_Rules() const;
    bool Enabled() const;
    bool Auto_Start_Skirmish() const;
    bool Allows_Object(TDMicroObjectCategory category, int type) const;
    bool Allows_Production(TDMicroObjectCategory category, int type, bool is_human) const;
    bool Allows_Crew_Survivors() const;
    bool Is_Skirmish_Opponent_House(int house, int game_type, int ghost_count) const;
    bool Validate_Active_Objects();
    bool Had_Content_Violation() const;
    char const* Player_Brain() const;
    char const* Opponent_Brain() const;
    int Opponent_Difficulty() const;
    int Opponent_Handicap() const;
    unsigned int Setup_Seed() const;
    int Spawn_Bucket() const;
    bool Start_Coordinate(bool player, int& x, int& y) const;
    unsigned int Reset_RNG_State() const;
    char const* Policy_Path() const;
    bool Policy_Sampling_Seed(uint64_t& seed) const;
    int Starting_Unit_Count() const;
    bool Has_Oracle_Seed() const;
    unsigned int Oracle_Seed() const;

private:
    bool Configure_Oracle_Impl(
        char const* ruleset,
        unsigned int seed,
        int opponent_difficulty,
        bool difficulty_active);

    bool IsEnabled;
    bool DifficultyActive;
    bool HasContentViolation;
    bool HasOracleSeed;
    unsigned int OracleSeed;
    unsigned int ScenarioSeed;
    int OpponentDifficulty;
    uint64_t PolicySamplingSeed;
    bool HasValidPolicySamplingSeed;
    int StartingUnitCount;
    bool HasValidStartingUnitCount;
    char PlayerBrain[32];
    char OpponentBrain[32];
    char PolicyPath[512];
};

extern TDMicroSettings TDMicro;

void TDMicro_Reset_AI_Trace();
void TDMicro_Observe_AI_Commands();
bool TDMicro_Add_Starting_Force();
void TDMicro_Policy_Reset();
void TDMicro_Policy_Tick();
void TDMicro_Policy_Record_Weapon_Fire(TechnoClass const* source);
TDMicroPolicyOutcome TDMicro_Classify_Policy_Outcome(int frame, bool player_defeated, bool opponent_defeated);
void TDMicro_Policy_Record_Outcome(TDMicroPolicyOutcome outcome);
bool TDMicro_Policy_Completed();

#endif
