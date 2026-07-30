# Human-Play Smoke Test

## Result

Tiberian Dawn now builds to a playable Linux executable through Vanilla-Conquer:

- Source: `Vanilla-Conquer`
- Commit inspected: `7f351da`
- Build directory: `Vanilla-Conquer/build-td`
- Executable: `Vanilla-Conquer/build-td/vanillatd`
- Binary type: Linux x86-64 ELF
- Size: about 15 MB

The official EA `CnC_Remastered_Collection` tree was not built in this WSL/Linux environment because it only provides Visual Studio project files for Win32 DLL builds. Vanilla-Conquer is the practical human-play bridge because it is a portable source port of the first-generation C&C engine and builds native Linux executables.

## Commands run

Dependencies installed:

```sh
sudo apt-get update
sudo apt-get install -y cmake pkg-config libsdl2-dev libopenal-dev
```

Configure:

```sh
cd /home/claude/cnc/Vanilla-Conquer
cmake -S . -B build-td -G Ninja \
  -DBUILD_VANILLATD=ON \
  -DBUILD_VANILLARA=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_TOOLS=ON \
  -DOPENAL=ON \
  -DSDL2=ON
```

Build:

```sh
cmake --build build-td --target VanillaTD
```

Sanity check:

```sh
./build-td/vanillatd -h
```

This printed the Command & Conquer command-line help successfully.

## Verified human-play launch

Human play is now verified past the main menu, difficulty selection, side selection, mission intro video, and into the first mission. The game data was extracted from the freeware Tiberian Dawn Gold GDI/Nod ISO files into:

```text
/home/claude/cnc/td-data
```

The extracted root contains the required mix files, including:

```text
CONQUER.MIX
GENERAL.MIX
SOUNDS.MIX
CCLOCAL.MIX
MOVIES.MIX
SCORES.MIX
UPDATE.MIX
UPDATEC.MIX
TEMPICNH.MIX
DESEICNH.MIX
WINTICNH.MIX
```

`CCLOCAL.MIX` was present under `INSTALL/CCLOCAL.MIX` and was copied to the data root because VanillaTD looks for it through the normal game data search path.

The current working path uses C&C95 high-resolution mode, not the earlier DOS fallback. `INSTALL/SETUP.Z` must be unpacked because the CD root does not contain the installed-game archives that hold high-res UI and sidebar icon data.

The installed-game archives were extracted from `SETUP.Z` into `/tmp/td-install` with `tools/extract_setupz.c`, then copied into `td-data`:

```sh
cd /home/claude/cnc
curl -L https://raw.githubusercontent.com/madler/zlib/master/contrib/blast/blast.c -o /tmp/blast.c
curl -L https://raw.githubusercontent.com/madler/zlib/master/contrib/blast/blast.h -o /tmp/blast.h
gcc -O2 -I/tmp tools/extract_setupz.c /tmp/blast.c -o /tmp/extract_setupz
/tmp/extract_setupz td-data/SETUP.PKG td-data/INSTALL/SETUP.Z /tmp/td-install

for f in UPDATE.MIX UPDATEC.MIX WINTICNH.MIX TEMPICNH.MIX DESEICNH.MIX TRANSIT.MIX SPEECH.MIX; do
  install -m 664 /tmp/td-install/$f /home/claude/cnc/td-data/$f
done
```

This fixed the blank build sidebar. Before extraction, deployment added buildable entries in the game logic, but every sidebar cameo pointer was null. After extraction and high-res mode, `TEMPICNH.MIX` provides `nukeicnh.tem`, `pyleicnh.tem`, `handicnh.tem`, and wall icons, while `UPDATEC.MIX` provides `hstrip.shp`, `hclock.shp`, `hside1.shp`, `hside2.shp`, `hrepair.shp`, `hsell.shp`, and `hmap.shp`.

The ISO-localized `CONQUER.ENG` text inside `CCLOCAL.MIX` was German. A loose English `CONQUER.ENG` was generated from the English strings in `tiberiandawn/conquer.h` and placed in both:

```text
/home/claude/cnc/td-data/CONQUER.ENG
/home/claude/cnc/Vanilla-Conquer/CONQUER.ENG
```

The working-directory copy is required for this launch path because `RawFileClass("CONQUER.ENG")` checks the process working directory before the data path.

The binary-side config file is:

```text
/home/claude/cnc/Vanilla-Conquer/build-td/CONQUER.INI
```

with:

```ini
[Paths]
DataPath=/home/claude/cnc/td-data
UserPath=/home/claude/.config/vanilla-conquer/vanillatd

[Intro]
PlayIntro=no

[Options]
ScrollRate=6

[Video]
Windowed=yes
WindowWidth=960
WindowHeight=600
Width=0
Height=0
Boxing=yes
BoxingAspectRatio=16:10
FrameLimit=60
InterpolationMode=1
HardwareCursor=no
DOSMode=no
Scaler=nearest
Driver=software
PixelFormat=default

[Mouse]
RawInput=no
Sensitivity=100
ControllerEnabled=no
ControllerPointerSpeed=10
MouseWheelScrolling=yes
```

The same `[Video]` block was also written to `/home/claude/.config/vanilla-conquer/vanillatd/conquer.ini` so a saved user config does not push the game back into fullscreen.

`ScrollRate=6` is set in both the build-side INI and the active user INI. VanillaTD defaults to `ScrollRate=4`; in WSLg that made edge scrolling too fast for manual testing.

`DOSMode=no` is now the correct setting. Earlier, `DOSMode=yes` was used as a workaround because the CD root alone was missing installed high-res assets. Once `INSTALL/SETUP.Z` was unpacked, high-res mode became visibly better and the build sidebar icons appeared.

The source was also patched in two narrow places to apply the loaded title/menu palette explicitly when the menu is redrawn:

```text
Vanilla-Conquer/tiberiandawn/init.cpp
Vanilla-Conquer/tiberiandawn/menus.cpp
```

The relevant diagnosis:

```text
gdb backtrace: Main_Game -> Select_Game -> Main_Menu -> Frame_Limiter
640x400 path: TitlePicture = "HTITLE.PCX", Palette remained all zero
320x200 DOS path: TitlePicture = "TITLE.CPS", Palette became nonzero
```

A headless data-path smoke test stayed alive until timeout, which means it did not hit the previous missing-CD/data failure:

```sh
cd /home/claude/cnc/Vanilla-Conquer
SDL_VIDEODRIVER=dummy ALSOFT_DRIVERS=null timeout 15s ./build-td/vanillatd
```

The WSLg launch path that stayed alive until timeout was:

```sh
cd /home/claude/cnc/Vanilla-Conquer
SDL_VIDEODRIVER=x11 \
ALSOFT_DRIVERS=pulse \
PULSE_SERVER=/mnt/wslg/PulseServer \
DISPLAY=:0 \
timeout -s TERM 8s ./build-td/vanillatd
```

For actual play, the game was launched as a transient user systemd service so it survives after the launch command returns. The INI controls windowed mode; the service command only supplies WSLg display/audio environment:

```sh
systemd-run --user \
  --unit=vanillatd \
  --collect \
  --working-directory=/home/claude/cnc/Vanilla-Conquer \
  --setenv=SDL_VIDEODRIVER=x11 \
  --setenv=ALSOFT_DRIVERS=pulse \
  --setenv=PULSE_SERVER=/mnt/wslg/PulseServer \
  --setenv=DISPLAY=:0 \
  /home/claude/cnc/Vanilla-Conquer/build-td/vanillatd
```

For actual play with the current audio instability, use quiet mode:

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

`-XQ` enables the original quiet-mode flag. It is currently the safer human-play path because normal audio mode can still crash in the OpenAL sound mixer after campaign/video playback.

Verification after launch:

```text
Active: active (running)
Window: "Vanilla Conquer", 960x600 through WSLg/X11
Menu: visible after splash with DOSMode=no
New Game -> Normal: reaches side selection
Side selection: fallback GDI/Nod screen works when CHOOSE.WSA is unavailable
Mission intro: VQA playback reached in normal audio mode
First mission: entered successfully
Construction yard: MCV deploys, build sidebar shows power plant and wall icons
Production: power plant can be started from the sidebar
```

Stop it with:

```sh
systemctl --user stop vanillatd
```

Check status with:

```sh
systemctl --user status vanillatd --no-pager
```

## Source patches

The current local source tree has several narrow human-play compatibility patches:

- `tiberiandawn/init.cpp` and `tiberiandawn/menus.cpp`: apply the loaded title/menu palette explicitly, fixing black menu rendering after the splash screen.
- `common/wsa.cpp`: validate animation file opens and headers before constructing a WSA handle; guard null handles in `Close_Animation()` and `Animate_Frame()`.
- `common/xordelta.cpp`: reject invalid delta buffers with non-positive width, preventing the choose-side animation from busy-looping forever.
- `tiberiandawn/intro.cpp`: detect missing/invalid `CHOOSE.WSA`, draw a simple GDI/Nod fallback selection screen, and skip broken choose-side AUD samples.
- `common/soundio_common.cpp`: add invalid-handle guards for audio sample tracker access.
- `tiberiandawn/building.cpp`: allow a construction yard deployed from an MCV to run `Grand_Opening()` during reveal. Without this, the normal-game CY path skipped grand opening during `MISSION_CONSTRUCTION`, then skipped it again when construction completed, leaving the build sidebar empty.
- `tiberiandawn/bdata.cpp`: keep a fallback from high-res `*ICNH.SHP` cameo lookup to classic `*ICON.SHP` lookup if installed icon archives are absent or incomplete.
- `tiberiandawn/sidebar.cpp`: initialize draw-loop production state defensively before resolving the visible buildable slot.

## Current Known Issues

Normal audio mode remains unstable. The observed crash is in `common/soundio_common.cpp` under `Sound_Callback() -> Maintenance_Callback() -> Sample_Copy() -> Simple_Copy()`, usually after campaign/video audio has run for a while. Quiet mode with `-XQ` avoids the known crash path for human-play smoke testing.

WSLg mouse movement was inverted in mission gameplay when `RawInput=yes`. Setting `RawInput=no` in both the user config and build-side `CONQUER.INI` fixed the direction issue while preserving menu input.

## Data source

Vanilla-Conquer's README says Tiberian Dawn works with the final freeware Command & Conquer Gold CD release data. Remastered Collection, Ultimate Collection, and First Decade data are not the recommended data source for Vanilla-Conquer.

The ISO files currently used are:

```text
/home/claude/cnc/isos/CnC_GDI95.iso
/home/claude/cnc/isos/CnC_NOD95.iso
```

They were extracted with:

```sh
7z x /home/claude/cnc/isos/CnC_GDI95.iso -o/home/claude/cnc/td-data -y
7z x /home/claude/cnc/isos/CnC_NOD95.iso -o/home/claude/cnc/td-data -y
```

## Why this is the right first step

Human play gives us a working source/build/data loop before RL-specific work:

- validates game data loading
- validates render/input/audio paths
- gives a visual reference for later headless behavior
- confirms the gameplay code is usable before adding PufferLib
- creates a known-good baseline for scripted input and deterministic replay

After human play works, the next step is a non-interactive harness that starts a tiny TD scenario, advances frames, extracts structured state, and injects scripted commands.
