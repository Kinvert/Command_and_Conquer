#include "tdmicro.h"

#include "function.h"

#include <cstdio>

bool TDMicroSettings::Validate_Active_Objects()
{
    if (!IsEnabled)
        return true;

    TDMicroObjectCategory category = TD_MICRO_CATEGORY_OTHER;
    int type = -1;
    for (int index = 0; index < Units.Count(); index++) {
        type = Units.Ptr(index)->Class->Type;
        if (!Allows_Object(TD_MICRO_CATEGORY_UNIT, type)) {
            category = TD_MICRO_CATEGORY_UNIT;
            goto violation;
        }
    }
    for (int index = 0; index < Buildings.Count(); index++) {
        type = Buildings.Ptr(index)->Class->Type;
        if (!Allows_Object(TD_MICRO_CATEGORY_BUILDING, type)) {
            category = TD_MICRO_CATEGORY_BUILDING;
            goto violation;
        }
    }
    for (int index = 0; index < Infantry.Count(); index++) {
        type = Infantry.Ptr(index)->Class->Type;
        if (!Allows_Object(TD_MICRO_CATEGORY_INFANTRY, type)) {
            category = TD_MICRO_CATEGORY_INFANTRY;
            goto violation;
        }
    }
    if (Aircraft.Count() != 0) {
        type = Aircraft.Ptr(0)->Class->Type;
        goto violation;
    }
    return true;

violation:
    if (!HasContentViolation) {
        std::fprintf(stderr, "TD Micro unsupported object: category=%d type=%d\n", category, type);
    }
    HasContentViolation = true;
    return false;
}

bool TDMicroSettings::Had_Content_Violation() const
{
    return HasContentViolation;
}
