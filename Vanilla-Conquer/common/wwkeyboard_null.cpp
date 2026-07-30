//
// Copyright 2020 Electronic Arts Inc.
//
// TiberianDawn.DLL and RedAlert.dll and corresponding source code is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version.

#include "wwkeyboard.h"

class WWKeyboardClassNull : public WWKeyboardClass
{
public:
    virtual ~WWKeyboardClassNull() {}

    virtual KeyASCIIType To_ASCII(unsigned short)
    {
        return KA_NONE;
    }

private:
    virtual void Fill_Buffer_From_System(void)
    {
    }
};

WWKeyboardClass* CreateWWKeyboardClass(void)
{
    return new WWKeyboardClassNull;
}
