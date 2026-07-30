#include "settings.h"

int main()
{
    SettingsClass defaults;
    return defaults.Video.Windowed && !defaults.Mouse.RawInput ? 0 : 1;
}
