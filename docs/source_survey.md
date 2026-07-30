# C&C Source Survey for RL
## Local repositories

The following repositories were cloned into this workspace:

- `CnC_Remastered_Collection`: official EA Remastered source for `TiberianDawn.dll`, `RedAlert.dll`, and the map editor.
- `CnC_Tiberian_Dawn`: official EA original Tiberian Dawn source drop.
- `CnC_Red_Alert`: official EA original Red Alert source drop.
- `PufferLib`: local copy used to inspect the native vector environment interface.

Line references below point at these local clones.

## Official build status

### Remastered Collection

`CnC_Remastered_Collection/README.md` says the repo includes source for `TiberianDawn.dll`, `RedAlert.dll`, and the map editor. It lists Windows 8.1 SDK and MFC for Visual Studio C++ as dependencies and marks compiling as Win32 only. It also says Visual Studio 2017 is recommended because later Visual Studio versions report a Windows SDK packing issue.

This is the only official EA tree with a realistic first path to a controllable simulator harness.

### Original Tiberian Dawn

`CnC_Tiberian_Dawn/README.md` says:

- DirectX 5 SDK is required.
- The code does not fully compile.
- It does not contain core engine libraries.
- Those core libraries are in the Red Alert repository.
- Restoring the original build environment requires Watcom C/C++ 10.6, TASM 4.0, and MASM 6.11d.

This is valuable for historical reference, but it is not the best first substrate for a PufferLib environment.

### Original Red Alert

`CnC_Red_Alert/README.md` says:

- DirectX 5 SDK and DirectX Media 5.1 SDK are required.
- The code does not fully compile.
- Restoring the original build environment requires Watcom C/C++ 10.6 and TASM 4.0.

It is more complete than the original TD drop in some shared-engine areas, but its restoration cost is high.

## Remastered TD control surfaces

### Exported C API

`CnC_Remastered_Collection/TIBERIANDAWN/DLLInterface.cpp:127-138` declares the main exported functions needed for an RL harness:

- `CNC_Start_Instance`
- `CNC_Start_Instance_Variation`
- `CNC_Start_Custom_Instance`
- `CNC_Advance_Instance`
- `CNC_Get_Game_State`
- `CNC_Handle_Input`
- `CNC_Handle_Unit_Request`

This is a strong sign that the Remastered tree is a better starting point than the original drops. It already had to expose game state and commands to an external Remastered host.

### Frame advance

`CNC_Advance_Instance` starts at `TIBERIANDAWN/DLLInterface.cpp:1443`. Important behavior:

- Sets `InMainLoop`.
- Sets player context from `player_id`.
- Calls `Reallocate_Big_Shape_Buffer`.
- Runs map input plumbing with no external input at `DLLInterface.cpp:1489-1492`.
- Sorts the ground layer at `DLLInterface.cpp:1518`.
- Runs object/team/map/factory logic via `Logic.AI()` at `DLLInterface.cpp:1527-1530`.
- Executes queued events through `Queue_AI()` or `Glyphx_Queue_AI()` at `DLLInterface.cpp:1543-1550`.
- Returns false on win/loss game-over paths around `DLLInterface.cpp:1575-1608`.

This is the first function to benchmark.

### Game logic

`LogicClass::AI` starts at `TIBERIANDAWN/LOGIC.CPP:165`.

It processes:

- crate regeneration
- team AI
- object AI for all sentient objects
- scan bits for units, infantry, aircraft, and buildings
- map logic
- factory processing

This is the core simulation tick. For a headless port, the objective is to keep this logic while stripping render, audio, UI, and host callbacks out of the step path.

### State export

`GameStateRequestEnum` in `TIBERIANDAWN/DLLInterface.h:63-72` includes:

- static map
- dynamic map
- layers
- sidebar
- placement
- shroud
- occupier
- player info

Useful structs:

- `CNCObjectStruct` at `TIBERIANDAWN/DLLInterface.h:205-281`
- `CNCObjectListStruct` at `TIBERIANDAWN/DLLInterface.h:283-285`
- `CNCSidebarStruct` at `TIBERIANDAWN/DLLInterface.h:358-376`
- `CNCDynamicMapStruct` at `TIBERIANDAWN/DLLInterface.h:535-542`
- `CNCPlayerInfoStruct` starts at `TIBERIANDAWN/DLLInterface.h:771`

Relevant implementations:

- `CNC_Get_Game_State` starts at `TIBERIANDAWN/DLLInterface.cpp:2774`.
- `Get_Shroud_State` starts at `TIBERIANDAWN/DLLInterface.cpp:5492`.
- `Get_Occupier_State` starts at `TIBERIANDAWN/DLLInterface.cpp:5586`.
- `Get_Player_Info_State` starts at `TIBERIANDAWN/DLLInterface.cpp:5671`.

The object/layer state path appears tied to render/draw interception in parts of `DLLInterface.cpp`. That is acceptable for an early harness, but a fast native env should pack observations from the game heaps directly.

### Input and event model

UI-style input enums live in `TIBERIANDAWN/DLLInterface.h:413-464`:

- mouse move/click/area
- sell/select/command at position
- special keys
- unit scatter/select-next/select-prev/guard/stop

Semantic command events are more RL-relevant:

- `EventType` in `TIBERIANDAWN/EVENT.H:51-88` includes mission, idle, scatter, destruct, deploy, place, produce, suspend, abandon, primary, repair, sell, and special events.
- `Queue_Mission` creates mission events and appends to `OutList` in `TIBERIANDAWN/QUEUE.CPP:236-244`.
- `Queue_AI_Normal` moves `OutList` to `DoList` and executes it in `TIBERIANDAWN/QUEUE.CPP:371-407`.
- `EventClass::Execute` dispatches event behavior in `TIBERIANDAWN/EVENT.CPP:400`.

The RL action API should target this event layer rather than raw mouse clicks, with optional wrappers that reuse existing legality checks.

### Reset and snapshot

TD save/load is useful as a correctness oracle:

- Save writes map, heaps, logic, map layers, score, base AI, and misc values in `TIBERIANDAWN/SAVELOAD.CPP:220-290`.
- Load clears the scenario before reading state in `TIBERIANDAWN/SAVELOAD.CPP:406-418`.

The benchmark harness should measure this, but a production PufferLib env needs memory snapshots or direct reset.

## Red Alert notes

`CnC_Remastered_Collection/REDALERT` has parallel machinery:

- `REDALERT/DLLInterface.cpp` exposes the same broad `CNC_*` API.
- `REDALERT/LOGIC.CPP:195` has `LogicClass::AI`.
- `REDALERT/CONQUER.CPP:2150` has the old main loop.
- `REDALERT/QUEUE.CPP:352` processes queued events.
- `REDALERT/EVENT.H:53` defines event types.
- `REDALERT/SAVELOAD.CPP:128` writes a broader state set, including RA-specific heaps like vessels.

Red Alert is attractive for a later benchmark because it is more famous and mechanically richer. It is not the right first target because the wider rules surface makes observation/action design harder before the core env exists.

## Global-state problem

The engine uses global queues and global game context. For example, TD declares:

- `OutList` and `DoList` in `TIBERIANDAWN/GLOBALS.CPP:419-420`

The DLL step function also relies on global `PlayerPtr`, `Frame`, `Map`, `Logic`, `GameToPlay`, and many scenario globals. That makes many envs in one process unsafe until the state is isolated.

This is the central engineering challenge for PufferLib:

- Process-per-env can work for a baseline.
- Threaded in-process vector envs require deglobalization.
- A partial context object may be enough if all globals used by the step path are captured and swapped per env.
- A clean long-term version turns the game into explicit `GameState*` plus read-only rules/assets.

## Immediate open questions

- Can `TiberianDawn.dll` be built and loaded without the closed Remastered host?
- Which callbacks are mandatory for `CNC_Start_Custom_Instance` and `CNC_Advance_Instance`?
- Can render/draw interception be fully disabled while still getting object/layer state?
- Does frame advance remain deterministic across repeated runs with the same seed and scripted actions?
- What is the minimum asset set required to load a tiny custom map?
- How much of state export cost comes from variable-length buffers and per-step allocation?
