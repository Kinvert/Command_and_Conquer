# TD Micro Upstream Baseline

Recorded: 2026-07-13

TD Micro starts from the root repository's pristine source-import commit:

```text
fde281808225aa6c9d452f9b7d1d180bf249bb95
```

The imported Vanilla-Conquer snapshot was revision:

```text
7f351daed0c19d7c4764dc4ebae1a70c7809ac1f
```

Before TD Micro modifications, only `Vanilla-Conquer/` was refreshed from the upstream `vanilla`
branch to:

```text
commit 75526cbd4cbb6cca789f94b6f6abe00100ce7777
tree   4f749865ea0f5f6450c50d207572476b5911ff6f
```

The complete upstream delta from the imported revision is:

```text
M .github/workflows/linux.yml
M .github/workflows/mingw.yml
M .github/workflows/windows.yml
M common/sockets.h
M common/wsproto.h
```

The two commits before `75526cbd` only change CI packaging. `75526cbd` changes socket portability
headers to restore `fd_set` declarations on some platforms. No Tiberian Dawn gameplay source changed.

The extracted `Vanilla-Conquer/` directory was compared recursively against `git archive` output for
the pinned revision. `diff -qr` produced no differences before any TD Micro code was added.

Official source references remain pinned separately:

```text
CnC_Tiberian_Dawn          e0d372dc582c053a699114942b984dad0457f9b3
CnC_Remastered_Collection f1f0d42bc2dcd06d5d1df943c6150ab34bf307ae
```

The official original source is the historical algorithm/data reference. Pinned pristine
Vanilla-Conquer is the executable oracle and final graphical deployment target.

## Pristine Build Verification

Configuration:

```bash
cmake -S . -B build-td -G Ninja \
  -DBUILD_VANILLATD=ON \
  -DBUILD_VANILLARA=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_TOOLS=ON \
  -DOPENAL=ON \
  -DSDL2=ON
cmake --build build-td --target VanillaTD -j 10
```

Toolchain and output:

```text
GCC/G++ 13.3.0
SDL2 enabled
OpenAL enabled
binary SHA-256 e454959a63442bc675e842d901b636b6736c4028a57b41cef3dc89a0ba3bd1bd
```

`./build-td/vanillatd -h` exited successfully and printed the original C&C command-line options.

The data smoke used the existing `/home/claude/cnc/td-data` through an ignored runtime INI and an
isolated `/tmp/td-micro-vanilla-user` user path:

```bash
timeout 15s env SDL_VIDEODRIVER=dummy ALSOFT_DRIVERS=null ./build-td/vanillatd -XQ
```

It reached the 15-second timeout (`124`) without a startup/data failure. The GUI smoke used:

```bash
timeout 12s env SDL_VIDEODRIVER=x11 ALSOFT_DRIVERS=null DISPLAY=:0 \
  ./build-td/vanillatd -XQ
```

It also remained alive until timeout (`124`). No source compatibility patch was applied for either
smoke. The ignored runtime INI, English string symlink, and build directory are not part of the
source baseline.

The user visually confirmed that the pristine GUI rendered correctly. The old experimental
title/menu palette patches are therefore not part of TD Micro.

## Linux Remastered-Style Oracle Build

The executable oracle uses Vanilla's Remastered shared-library API, built on Linux from a separate
configured tree:

```bash
cmake -S . -B build-remastertd -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DBUILD_REMASTERTD=ON \
  -DBUILD_REMASTERRA=OFF \
  -DBUILD_VANILLATD=OFF \
  -DBUILD_VANILLARA=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_TOOLS=OFF \
  -DOPENAL=OFF \
  -DSDL2=OFF \
  -DNETWORKING=OFF
cmake --build build-remastertd --target TiberianDawn
```

Upstream's Remastered target assumed Windows. The local portability layer selects a null keyboard
backend for `commonr`, omits the Windows-only DLL editor source, supplies non-MSVC export/calling
convention definitions, guards Win32 startup APIs, and supports `VANILLA_CONQUER_ARGV0` so a
headless harness can choose the adjacent runtime INI. These changes are build/startup plumbing;
they do not replace TD simulation behavior.

The resulting oracle library is:

```text
Vanilla-Conquer/build-remastertd/tiberiandawn/TiberianDawn.so
```
