#include "function.h"
#include "td_micro_api.h"
#include "td_micro_v1.h"
#include "tdmicro.h"

#include <cstdlib>
#include <cstring>

RulesClass Rule;

void TDMicro_Reset_AI_Trace()
{
}

void TDMicro_Policy_Reset()
{
}

static int Expect(bool condition)
{
    return condition ? 0 : 1;
}

static void Set_Sampling_Seed_Environment(char const* value)
{
#ifdef _WIN32
    _putenv_s("TD_MICRO_POLICY_SAMPLE_SEED", value == NULL ? "" : value);
#else
    if (value == NULL) {
        unsetenv("TD_MICRO_POLICY_SAMPLE_SEED");
    } else {
        setenv("TD_MICRO_POLICY_SAMPLE_SEED", value, 1);
    }
#endif
}

int main()
{
    Set_Sampling_Seed_Environment(NULL);
    int failures = 0;
    INIClass ini;
    TDMicroSettings settings;
    failures += Expect(!settings.Enabled());
    failures += Expect(settings.Allows_Crew_Survivors());
    failures += Expect(TD_MICRO_PLAYER_COUNT == 2);
    failures += Expect(TD_MICRO_MAX_MAP_WIDTH == 64);
    failures += Expect(TD_MICRO_MAX_MAP_HEIGHT == 64);
    failures += Expect(TD_MICRO_MAX_UNITS == 16);
    failures += Expect(TD_MICRO_MAX_BUILDINGS == 64);
    failures += Expect(TD_MICRO_MAX_INFANTRY == 128);
    failures += Expect(TD_MICRO_MAX_PROJECTILES == 256);
    failures += Expect(TD_MICRO_TRAINING_TIMEOUT_FRAMES == 48000);
    failures += Expect(TD_MICRO_TRAINING_MAX_DECISIONS == 12000);
    failures += Expect(TD_MICRO_TRAINING_MAX_DECISIONS * TD_MICRO_DECISION_FRAMES
                       == TD_MICRO_TRAINING_TIMEOUT_FRAMES);
    failures += Expect(TDMicro_Classify_Policy_Outcome(47999, false, false) == TD_MICRO_POLICY_RUNNING);
    failures += Expect(TDMicro_Classify_Policy_Outcome(48000, false, false) == TD_MICRO_POLICY_TIMEOUT);
    failures += Expect(TDMicro_Classify_Policy_Outcome(100, true, false) == TD_MICRO_POLICY_LOSS);
    failures += Expect(TDMicro_Classify_Policy_Outcome(100, false, true) == TD_MICRO_POLICY_WIN);
    failures += Expect(TDMicro_Classify_Policy_Outcome(100, true, true) == TD_MICRO_POLICY_DRAW);
    failures += Expect(TDMicro_Classify_Policy_Outcome(48000, true, false) == TD_MICRO_POLICY_LOSS);
    failures += Expect(TD_MICRO_SPAWN_PROFILE_COUNT == 2);
    failures += Expect(TD_MICRO_SPAWN_PROFILES[0].bucket == TD_MICRO_SPAWN_CLOSE);
    failures += Expect(TD_MICRO_SPAWN_PROFILES[1].bucket == TD_MICRO_SPAWN_MEDIUM);

    ini.Put_String("TDMicro", "Ruleset", TD_MICRO_RULESET_ID);
    ini.Put_String("TDMicro", "PlayerBrain", "PufferPolicy");
    ini.Put_String("TDMicro", "OpponentBrain", "OriginalAI");
    ini.Put_String("TDMicro", "PolicyPath", "/tmp/policy.bin");
    ini.Put_Int("TDMicro", "Seed", 2);
    ini.Put_Int("TDMicro", "OpponentDifficulty", DIFF_NORMAL);
    settings.Load(ini);

    failures += Expect(settings.Enabled());
    failures += Expect(settings.Auto_Start_Skirmish());
    failures += Expect(settings.Is_Skirmish_Opponent_House(HOUSE_MULTI1, GAME_SKIRMISH, 1));
    failures += Expect(!settings.Is_Skirmish_Opponent_House(HOUSE_MULTI2, GAME_SKIRMISH, 1));
    failures += Expect(!settings.Is_Skirmish_Opponent_House(HOUSE_MULTI1, GAME_SKIRMISH, 0));
    failures += Expect(!settings.Is_Skirmish_Opponent_House(HOUSE_MULTI1, GAME_NORMAL, 1));
    failures += Expect(!settings.Allows_Crew_Survivors());
    failures += Expect(std::strcmp(settings.Player_Brain(), "PufferPolicy") == 0);
    failures += Expect(std::strcmp(settings.Opponent_Brain(), "OriginalAI") == 0);
    failures += Expect(settings.Opponent_Difficulty() == DIFF_NORMAL);
    failures += Expect(settings.Opponent_Handicap() == DIFF_NORMAL);
    failures += Expect(settings.Setup_Seed() == 2);
    failures += Expect(settings.Spawn_Bucket() == TD_MICRO_SPAWN_MEDIUM);
    int start_x = -1;
    int start_y = -1;
    failures += Expect(settings.Start_Coordinate(true, start_x, start_y));
    failures += Expect(start_x == 2 && start_y == 8);
    failures += Expect(settings.Start_Coordinate(false, start_x, start_y));
    failures += Expect(start_x == 37 && start_y == 23);
    failures += Expect(settings.Reset_RNG_State() == 2093743367u);
    failures += Expect(std::strcmp(settings.Policy_Path(), "/tmp/policy.bin") == 0);
    uint64_t sampling_seed = 0;
    failures += Expect(settings.Policy_Sampling_Seed(sampling_seed));
    failures += Expect(sampling_seed == 74);
    failures += Expect(settings.Allows_Object(TD_MICRO_CATEGORY_UNIT, UNIT_MCV));
    failures += Expect(settings.Allows_Object(TD_MICRO_CATEGORY_UNIT, UNIT_HARVESTER));
    failures += Expect(settings.Allows_Object(TD_MICRO_CATEGORY_BUILDING, STRUCT_CONST));
    failures += Expect(settings.Allows_Object(TD_MICRO_CATEGORY_BUILDING, STRUCT_POWER));
    failures += Expect(settings.Allows_Object(TD_MICRO_CATEGORY_BUILDING, STRUCT_BARRACKS));
    failures += Expect(settings.Allows_Object(TD_MICRO_CATEGORY_BUILDING, STRUCT_REFINERY));
    failures += Expect(settings.Allows_Object(TD_MICRO_CATEGORY_INFANTRY, INFANTRY_E1));
    failures += Expect(settings.Allows_Object(TD_MICRO_CATEGORY_INFANTRY, INFANTRY_E3));
    failures += Expect(!settings.Allows_Object(TD_MICRO_CATEGORY_UNIT, UNIT_MTANK));
    failures += Expect(!settings.Allows_Object(TD_MICRO_CATEGORY_BUILDING, STRUCT_WEAP));
    failures += Expect(!settings.Allows_Object(TD_MICRO_CATEGORY_INFANTRY, INFANTRY_E2));

    failures += Expect(!settings.Allows_Production(TD_MICRO_CATEGORY_UNIT, UNIT_MCV));
    failures += Expect(settings.Allows_Production(TD_MICRO_CATEGORY_BUILDING, STRUCT_POWER));
    failures += Expect(settings.Allows_Production(TD_MICRO_CATEGORY_BUILDING, STRUCT_BARRACKS));
    failures += Expect(settings.Allows_Production(TD_MICRO_CATEGORY_BUILDING, STRUCT_REFINERY));
    failures += Expect(settings.Allows_Production(TD_MICRO_CATEGORY_INFANTRY, INFANTRY_E1));
    failures += Expect(settings.Allows_Production(TD_MICRO_CATEGORY_INFANTRY, INFANTRY_E3));

    Rule.AttackInterval = 99;
    Rule.WarRatio = 99;
    Rule.Diff[DIFF_EASY].GroundspeedBias = 99;
    Rule.Diff[DIFF_NORMAL].BuildDelay = 99;
    settings.Apply_Rules();
    failures += Expect(Rule.AttackInterval == fixed(3));
    failures += Expect(Rule.WarRatio == fixed(".1"));
    failures += Expect(Rule.Diff[DIFF_EASY].FirepowerBias == fixed(11, 10));
    failures += Expect(Rule.Diff[DIFF_EASY].GroundspeedBias == fixed(11, 10));
    failures += Expect(Rule.Diff[DIFF_EASY].ROFBias == fixed(4, 5));
    failures += Expect(Rule.Diff[DIFF_EASY].CostBias == fixed(4, 5));
    failures += Expect(Rule.Diff[DIFF_EASY].BuildSpeedBias == fixed(3, 5));
    failures += Expect(Rule.Diff[DIFF_EASY].RepairDelay == fixed(1, 1000));
    failures += Expect(Rule.Diff[DIFF_EASY].BuildDelay == fixed(1, 500));
    failures += Expect(!Rule.Diff[DIFF_EASY].IsBuildSlowdown);
    failures += Expect(Rule.Diff[DIFF_EASY].IsWallDestroyer);
    failures += Expect(Rule.Diff[DIFF_EASY].IsContentScan);
    failures += Expect(Rule.Diff[DIFF_NORMAL].BuildDelay == fixed(3, 100));
    failures += Expect(Rule.Diff[DIFF_HARD].FirepowerBias == fixed(9, 10));
    failures += Expect(Rule.Diff[DIFF_HARD].GroundspeedBias == fixed(9, 10));
    failures += Expect(Rule.Diff[DIFF_HARD].ArmorBias == fixed(21, 20));
    failures += Expect(Rule.Diff[DIFF_HARD].ROFBias == fixed(21, 20));
    failures += Expect(Rule.Diff[DIFF_HARD].RepairDelay == fixed(1, 20));
    failures += Expect(Rule.Diff[DIFF_HARD].BuildDelay == fixed(1, 10));
    failures += Expect(Rule.Diff[DIFF_HARD].IsBuildSlowdown);

    INIClass easy;
    easy.Put_String("TDMicro", "Ruleset", TD_MICRO_RULESET_ID);
    easy.Put_Int("TDMicro", "OpponentDifficulty", DIFF_EASY);
    TDMicroSettings easy_settings;
    easy_settings.Load(easy);
    failures += Expect(easy_settings.Opponent_Difficulty() == DIFF_EASY);
    failures += Expect(easy_settings.Opponent_Handicap() == DIFF_HARD);

    INIClass hard;
    hard.Put_String("TDMicro", "Ruleset", TD_MICRO_RULESET_ID);
    hard.Put_Int("TDMicro", "OpponentDifficulty", DIFF_HARD);
    TDMicroSettings hard_settings;
    hard_settings.Load(hard);
    failures += Expect(hard_settings.Opponent_Difficulty() == DIFF_HARD);
    failures += Expect(hard_settings.Opponent_Handicap() == DIFF_EASY);

    INIClass unknown;
    unknown.Put_String("TDMicro", "Ruleset", "not_td_micro");
    settings.Load(unknown);
    failures += Expect(!settings.Enabled());
    failures += Expect(!settings.Auto_Start_Skirmish());
    failures += Expect(settings.Opponent_Difficulty() == DIFF_EASY);
    failures += Expect(settings.Opponent_Handicap() == DIFF_HARD);
    failures += Expect(settings.Setup_Seed() == 1);
    failures += Expect(settings.Spawn_Bucket() == -1);
    failures += Expect(settings.Reset_RNG_State() == 0);
    failures += Expect(!settings.Start_Coordinate(true, start_x, start_y));
    failures += Expect(!settings.Is_Skirmish_Opponent_House(HOUSE_MULTI1, GAME_SKIRMISH, 1));
    failures += Expect(settings.Allows_Crew_Survivors());

    Set_Sampling_Seed_Environment("18446744073709551615");
    TDMicroSettings overridden_sampling;
    overridden_sampling.Load(easy);
    failures += Expect(overridden_sampling.Policy_Sampling_Seed(sampling_seed));
    failures += Expect(sampling_seed == UINT64_MAX);

    Set_Sampling_Seed_Environment("74junk");
    TDMicroSettings invalid_sampling;
    invalid_sampling.Load(easy);
    failures += Expect(!invalid_sampling.Policy_Sampling_Seed(sampling_seed));

    Set_Sampling_Seed_Environment("18446744073709551616");
    TDMicroSettings overflow_sampling;
    overflow_sampling.Load(easy);
    failures += Expect(!overflow_sampling.Policy_Sampling_Seed(sampling_seed));
    Set_Sampling_Seed_Environment(NULL);

    Rule.AttackInterval = 77;
    settings.Apply_Rules();
    failures += Expect(Rule.AttackInterval == fixed(77));

    TDMicroSettings oracle;
    failures += Expect(!oracle.Configure_Oracle("not_td_micro", 1));
    failures += Expect(!oracle.Enabled());
    failures += Expect(oracle.Configure_Oracle(TD_MICRO_RULESET_ID, 1));
    failures += Expect(Rule.Diff[DIFF_EASY].FirepowerBias == fixed(1));
    failures += Expect(Rule.Diff[DIFF_NORMAL].GroundspeedBias == fixed(1));
    failures += Expect(Rule.Diff[DIFF_HARD].CostBias == fixed(1));
    failures += Expect(oracle.Enabled());
    failures += Expect(!oracle.Auto_Start_Skirmish());
    failures += Expect(std::strcmp(oracle.Opponent_Brain(), "OriginalAI") == 0);
    failures += Expect(oracle.Opponent_Difficulty() == DIFF_EASY);
    failures += Expect(oracle.Opponent_Handicap() == DIFF_HARD);
    failures += Expect(std::strcmp(oracle.Player_Brain(), "Human") == 0);
    failures += Expect(oracle.Has_Oracle_Seed());
    failures += Expect(oracle.Oracle_Seed() == 1);
    failures += Expect(oracle.Reset_RNG_State() == 3488684595u);

    TDMicroSettings medium_oracle;
    failures += Expect(medium_oracle.Configure_Oracle_Difficulty(TD_MICRO_RULESET_ID, 2, DIFF_NORMAL));
    failures += Expect(medium_oracle.Setup_Seed() == 2);
    failures += Expect(medium_oracle.Spawn_Bucket() == TD_MICRO_SPAWN_MEDIUM);
    failures += Expect(medium_oracle.Reset_RNG_State() == 2093743367u);
    failures += Expect(medium_oracle.Opponent_Difficulty() == DIFF_NORMAL);
    failures += Expect(medium_oracle.Opponent_Handicap() == DIFF_NORMAL);
    failures += Expect(!medium_oracle.Configure_Oracle(TD_MICRO_RULESET_ID, 0));
    failures += Expect(!medium_oracle.Configure_Oracle(TD_MICRO_RULESET_ID, TD_MICRO_SPAWN_PROFILE_COUNT + 1));
    failures += Expect(!medium_oracle.Configure_Oracle_Difficulty(TD_MICRO_RULESET_ID, 1, -1));
    failures += Expect(!medium_oracle.Configure_Oracle_Difficulty(TD_MICRO_RULESET_ID, 1, DIFF_COUNT));
    TDMicroSettings hard_oracle;
    failures += Expect(hard_oracle.Configure_Oracle_Difficulty(TD_MICRO_RULESET_ID, 1, DIFF_HARD));
    failures += Expect(hard_oracle.Opponent_Handicap() == DIFF_EASY);
    return failures;
}
