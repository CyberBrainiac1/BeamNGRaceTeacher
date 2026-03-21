#!/usr/bin/env python3
"""Repository-level smoke checks for BeamNGRaceCoach assets.

These checks are intentionally lightweight and environment-independent.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mods/unpacked/BeamNGRaceCoach"

REQUIRED_FILES = [
    MOD / "info.json",
    MOD / "settings/default_track.json",
    MOD / "scripts/modScript.lua",
    MOD / "lua/ge/extensions/raceCoach/init.lua",
    MOD / "lua/ge/extensions/raceCoach/nativePlanner.lua",
    MOD / "lua/ge/extensions/raceCoach/pathPlanner.lua",
    MOD / "lua/ge/extensions/raceCoach/sourcePlanner.lua",
    MOD / "lua/ge/extensions/raceCoach/speedPlanner.lua",
    MOD / "lua/ge/extensions/raceCoach/coach.lua",
    MOD / "lua/ge/extensions/raceCoach/mpccMath.lua",
    MOD / "lua/ge/extensions/raceCoach/viz.lua",
    ROOT / "native/BeamNGRaceCoachCore/CMakeLists.txt",
    ROOT / "native/BeamNGRaceCoachCore/main.cpp",
    ROOT / "tools/build_native.ps1",
]


def fail(msg: str) -> None:
    print(f"FAIL: {msg}")
    sys.exit(1)


for f in REQUIRED_FILES:
    if not f.exists():
        fail(f"Missing required file: {f}")

info = json.loads((MOD / "info.json").read_text())
for key in ("name", "version", "description"):
    if key not in info:
        fail(f"info.json missing key '{key}'")

cfg = json.loads((MOD / "settings/default_track.json").read_text())
if len(cfg.get("points", [])) < 10:
    fail("default_track.json should contain at least 10 points")

if not cfg.get("native", {}).get("exePath"):
    fail("default_track.json must include native.exePath")

for idx, pt in enumerate(cfg["points"]):
    for axis in ("x", "y", "z"):
        if axis not in pt:
            fail(f"Point {idx} missing axis '{axis}'")

coach = (MOD / "lua/ge/extensions/raceCoach/coach.lua").read_text()
viz = (MOD / "lua/ge/extensions/raceCoach/viz.lua").read_text()
mpcc_math = (MOD / "lua/ge/extensions/raceCoach/mpccMath.lua").read_text()
init = (MOD / "lua/ge/extensions/raceCoach/init.lua").read_text()
mod_script = (MOD / "scripts/modScript.lua").read_text()
native_planner = (MOD / "lua/ge/extensions/raceCoach/nativePlanner.lua").read_text()

if "Brake hard" not in coach or "Light brake" not in coach or "Accelerate" not in coach:
    fail("coach.lua missing simplified HUD coaching prompts")

if "contouring" not in coach or "lagError" not in coach:
    fail("coach.lua missing MPCC-style error outputs")

if "projectOnPath" not in mpcc_math or "getErrorInfo" not in mpcc_math:
    fail("mpccMath.lua missing MPCC reference projection helpers")

if "onModActivated" not in init or "onModDeactivated" not in init:
    fail("init.lua missing mod activation hooks for auto-start behavior")

if "plannerMode" not in init or "nativePlanner.buildPlan" not in init:
    fail("init.lua missing native planner integration")

if "extensions.load('raceCoach/init')" not in mod_script:
    fail("modScript.lua must auto-load raceCoach/init")

if "os.execute" not in native_planner or "beamng_racecoach_native.exe" not in native_planner:
    fail("nativePlanner.lua missing executable bridge logic")

if "drawChevronTrail" not in viz or "drawChevron" not in viz:
    fail("viz.lua missing chevron visual helpers")

if "drawText(" in viz or "drawTextAdvanced" in viz:
    fail("viz.lua should not render world-space text labels")

# extremely lightweight structural sanity checks
for lua_file in MOD.glob("lua/ge/extensions/raceCoach/*.lua"):
    text = lua_file.read_text()
    if text.count("function ") == 0:
        fail(f"{lua_file.name} has no function definitions")
    if re.search(r"\bTODO\b", text):
        fail(f"{lua_file.name} contains TODO markers")

print("PASS: smoke checks completed")
