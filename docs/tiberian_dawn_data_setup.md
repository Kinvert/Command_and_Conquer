# Tiberian Dawn Data Setup

## Working Data Root

The active Vanilla-Conquer data root is:

```text
/home/claude/cnc/td-data
```

The game now works in C&C95 high-resolution mode with:

```ini
[Video]
Windowed=yes
WindowWidth=960
WindowHeight=600
DOSMode=no
HardwareCursor=no

[Paths]
DataPath=/home/claude/cnc/td-data
UserPath=/home/claude/.config/vanilla-conquer/vanillatd
```

The active user config is:

```text
/home/claude/.config/vanilla-conquer/vanillatd/conquer.ini
```

## Required Installed Archives

Extracting only the CD root is not enough. The CD root contains core game archives such as `CONQUER.MIX`, `GENERAL.MIX`, `MOVIES.MIX`, and `SCORES.MIX`, but the Windows install also unpacks additional archives from:

```text
/home/claude/cnc/td-data/INSTALL/SETUP.Z
```

The missing installed archives caused the build sidebar to be blank. The construction-yard logic added buildable entries, but the sidebar cameo pointers were null because icon archives were absent.

These installed files must be present in `td-data`:

```text
UPDATE.MIX
UPDATEC.MIX
WINTICNH.MIX
TEMPICNH.MIX
DESEICNH.MIX
TRANSIT.MIX
SPEECH.MIX
```

Useful verification:

```sh
/home/claude/cnc/Vanilla-Conquer/build-td/vanillamix -l /home/claude/cnc/td-data/TEMPICNH.MIX | rg -i 'nukeicnh|pyleicnh|handicnh|sbagicnh|cyclicnh|brikicnh'
/home/claude/cnc/Vanilla-Conquer/build-td/vanillamix -l /home/claude/cnc/td-data/UPDATEC.MIX | rg -i 'hstrip|hclock|hside|hrepair|hsell|hmap'
```

## Extraction Command

The archive is an old InstallShield Z payload using PKWARE DCL compression. `7z` recognizes it but cannot extract it, and `unshield` does not support this pre-CAB format.

The local helper `tools/extract_setupz.c` splits the archive using `SETUP.PKG` and uses zlib's `contrib/blast` DCL decompressor:

```sh
cd /home/claude/cnc
curl -L https://raw.githubusercontent.com/madler/zlib/master/contrib/blast/blast.c -o /tmp/blast.c
curl -L https://raw.githubusercontent.com/madler/zlib/master/contrib/blast/blast.h -o /tmp/blast.h
gcc -O2 -I/tmp tools/extract_setupz.c /tmp/blast.c -o /tmp/extract_setupz
/tmp/extract_setupz td-data/SETUP.PKG td-data/INSTALL/SETUP.Z /tmp/td-install
```

Copy the installed archives:

```sh
for f in UPDATE.MIX UPDATEC.MIX WINTICNH.MIX TEMPICNH.MIX DESEICNH.MIX TRANSIT.MIX SPEECH.MIX; do
  install -m 664 /tmp/td-install/$f /home/claude/cnc/td-data/$f
done
```

## Why The Sidebar Was Blank

Before extracting `SETUP.Z`, MCV deployment did this correctly:

```text
Construction yard deployed
Power plant and walls added to sidebar column 0
```

But drawing failed because the visible entries had null cameo data:

```text
shape=(nil)
```

After extracting the installed archives and switching to `DOSMode=no`, the same sidebar slots had valid shape pointers. The power plant icon comes from `nukeicnh.tem` in `TEMPICNH.MIX`.

## Launch

Use quiet mode for now because normal audio remains unstable:

```sh
systemd-run --user \
  --unit=vanillatd \
  --collect \
  --working-directory=/home/claude/cnc/Vanilla-Conquer \
  --setenv=SDL_VIDEODRIVER=x11 \
  --setenv=ALSOFT_DRIVERS=pulse \
  --setenv=PULSE_SERVER=/mnt/wslg/PulseServer \
  --setenv=DISPLAY=:0 \
  /home/claude/cnc/Vanilla-Conquer/build-td/vanillatd -XQ
```
