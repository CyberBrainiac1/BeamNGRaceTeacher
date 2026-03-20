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
    MOD / "lua/ge/extensions/raceCoach/init.lua",
    MOD / "lua/ge/extensions/raceCoach/pathPlanner.lua",
    MOD / "lua/ge/extensions/raceCoach/speedPlanner.lua",
    MOD / "lua/ge/extensions/raceCoach/coach.lua",
    MOD / "lua/ge/extensions/raceCoach/viz.lua",
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

for idx, pt in enumerate(cfg["points"]):
    for axis in ("x", "y", "z"):
        if axis not in pt:
            fail(f"Point {idx} missing axis '{axis}'")

coach = (MOD / "lua/ge/extensions/raceCoach/coach.lua").read_text()
viz = (MOD / "lua/ge/extensions/raceCoach/viz.lua").read_text()

if "BRAKE_NOW" not in coach or "TOO_FAST" not in coach:
    fail("coach.lua missing critical guidance message definitions")

if "drawTrackRibbon" not in viz:
    fail("viz.lua missing zone-ribbon visual helper")

# extremely lightweight structural sanity checks
for lua_file in MOD.glob("lua/ge/extensions/raceCoach/*.lua"):
    text = lua_file.read_text()
    if text.count("function ") == 0:
        fail(f"{lua_file.name} has no function definitions")
    if re.search(r"\bTODO\b", text):
        fail(f"{lua_file.name} contains TODO markers")

print("PASS: smoke checks completed")
