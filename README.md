# BeamNGRaceCoach (MPCC-Style Racing Assist for BeamNG.drive / BeamNG.tech)

This repository contains a practical V1 BeamNG mod that acts as a **live racing coach**, not a full autonomous controller.

It focuses on:
- fast-path estimation and MPCC-style path shaping
- optional native C++ planning core with Lua fallback
- target speed planning from curvature demand
- braking / turn-in / apex / exit / acceleration zone labeling
- in-game visual overlays for line + zones + target speed
- live coaching prompts (Brake now, Slow down, Off racing line, etc.)
- automatic source selection:
  - use the current looped track under the car when one is detected
  - otherwise use the active BeamNG destination route

## MPCC references used

Primary concept reference:
- https://github.com/alexliniger/MPCC

Secondary concept reference:
- https://github.com/nirajbasnet/Nonlinear_MPCC_for_autonomous_racing

V1 does not port the full solver stack from these projects. Instead, it uses the MPCC core concepts in a lightweight BeamNG implementation designed for real-time coaching and future extension.

## Folder structure

```text
native/BeamNGRaceCoachCore/
  CMakeLists.txt
  main.cpp
mods/unpacked/BeamNGRaceCoach/
  bin/beamng_racecoach_native.exe
  info.json
  scripts/modScript.lua
  settings/default_track.json
  lua/ge/extensions/raceCoach/
    init.lua
    nativePlanner.lua
    pathPlanner.lua
    speedPlanner.lua
    coach.lua
    viz.lua
```

## How it works

### 1) Baseline path and geometry
`pathPlanner.buildBaselinePath()` ingests either:
- a detected looped track
- the active destination route
- or the fallback JSON sample path

It then computes:
- path tangent and local normal
- accumulated arc progress
- signed curvature

This is the center reference that later gets improved.

### 2) MPCC-style path improvement (core logic)
The planner can run in two modes:
- native C++ via `native/BeamNGRaceCoachCore/main.cpp`
- pure Lua fallback via `pathPlanner.improvePathMPCCStyle()`

Both perform iterative optimization over lateral offsets along the track normal.

Objective terms are inspired by MPCC contouring/lag framing:
- **contouring-like penalty**: keep offsets bounded and consistent
- **lag-like penalty**: penalize abrupt longitudinal progress distortion via neighbor differences
- **curvature proxy penalty**: reduce high second-difference (line roughness / sharpness)
- **corner preference term**: encourages outside-in-outside behavior, with explicit entry/apex/exit preference

The corner preference is built from local + lookahead curvature and acts as a practical approximation of racing-line bias for stronger exits.

### 3) Target speed profile
`speedPlanner.buildSpeedAndZones()` computes a curvature-limited speed envelope:

- lateral limit: `v <= sqrt(mu * g / |kappa|)`
- forward pass: accel-limited speed growth
- backward pass: brake-limited feasibility

The result is a lap speed profile that respects cornering demand and longitudinal capability.

### 4) Zone classification
Each path index is classified into zones:
- `straight`
- `brake`
- `turn_in`
- `apex`
- `exit`
- `accel`
- fallback `corner`

Classification uses curvature magnitude and local speed-gradient signals.

### 5) Live coaching
`coach.update()` compares player state against the improved path and target speed.

Examples of generated prompts:
- Critical: **Brake now**, **Slow down now**, **Too fast for corner**
- Important: **Turn in now**, **Off racing line**, **Missed braking zone**
- Coaching: **Accelerate**, **Good exit**, **Exit speed low**, **Good speed**

Spam control:
- single prioritized message at a time
- cooldown/hysteresis behavior
- critical messages can pre-empt cooldown

### 6) Visual guidance
`viz.lua` draws:
- racing line segments color-coded by zone
- track-surface style zone ribbons (semi-filled cross-hatched overlays) so braking/turn-in/apex/exit areas are readable at speed
- periodic target-speed labels (km/h)
- top-level current coaching summary text

Recommended zone colors are already encoded:
- green: straight/accel emphasis
- yellow/orange: setup and turn-in/apex
- red: braking

## Install and run in BeamNG

1. Copy this folder into your BeamNG user mods path as an unpacked mod:
   - `mods/unpacked/BeamNGRaceCoach/...`
2. Launch BeamNG.drive or BeamNG.tech.
3. Enable the mod in BeamNG's mod manager if it is not already enabled.
4. Start driving on a map.
5. The mod auto-loads `raceCoach/init` when the mod is activated and automatically chooses a source:
   - detected looped track near the vehicle
   - otherwise the current destination route from BeamNG navigation
   - otherwise the fallback sample path in `settings/BeamNGRaceCoach/default_track.json`
6. If `mods/unpacked/BeamNGRaceCoach/bin/beamng_racecoach_native.exe` exists, the mod uses the native C++ planner.
7. If the native executable is missing or fails, the mod falls back to the Lua planner automatically.
8. The mod builds the MPCC-style path + speed plan and starts drawing guidance + coaching.

## Build the native planner

From this repo root, run:

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_native.ps1
```

That builds `native/BeamNGRaceCoachCore`, then copies `beamng_racecoach_native.exe` into:
- `mods/unpacked/BeamNGRaceCoach/bin/`
- your active BeamNG user profile mod folder when present

## Customizing for a real track

Edit `mods/unpacked/BeamNGRaceCoach/settings/default_track.json`:
- Replace `points` with your track loop points in driving order.
- Supply per-point `widthLeft` / `widthRight` where possible.
- Tune `mpcc` weights and `vehicle` dynamics.

## Practical limitations of V1

- The native side currently ports the lightweight planner, not the full upstream nonlinear MPC/QP solver stack.
- Zone detection is heuristic and should be tuned per track and tire model.

## Next planned improvements

- Use in-game road graph / AI line data as baseline generation source.
- Add adaptive per-corner apex prediction and better turn-in timing logic.
- Replace heuristic optimizer with a tighter QP stage approximating the MPCC objective and constraints.
- Add richer UI app panel with next-corner cards and confidence metrics.

## Local smoke checks

From this repo root, run:

```bash
python tools/smoke_check.py
```

This validates file layout, JSON sanity, and key Lua feature hooks before in-game testing.
