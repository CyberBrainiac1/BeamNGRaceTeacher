local M = {}

local COLORS = {
  straight = ColorF(0.2, 0.8, 0.2, 0.9),
  accel = ColorF(0.15, 0.95, 0.15, 0.9),
  brake = ColorF(0.95, 0.2, 0.2, 0.95),
  turn_in = ColorF(0.95, 0.85, 0.2, 0.9),
  apex = ColorF(0.95, 0.45, 0.15, 0.9),
  exit = ColorF(0.3, 0.7, 0.95, 0.9),
  corner = ColorF(0.85, 0.65, 0.2, 0.85)
}

local SURFACE_ALPHA = {
  straight = 0.05,
  accel = 0.08,
  brake = 0.26,
  turn_in = 0.20,
  apex = 0.16,
  exit = 0.12,
  corner = 0.10
}

local function zoneColor(zone)
  return COLORS[zone] or ColorF(0.8, 0.8, 0.8, 0.8)
end

local function zoneSurfaceColor(zone)
  local lineCol = zoneColor(zone)
  return ColorF(lineCol.r, lineCol.g, lineCol.b, SURFACE_ALPHA[zone] or 0.08)
end

local function drawTrackRibbon(path, zones)
  if not debugDrawer or not debugDrawer.drawLine then
    return
  end
  for i = 1, #path do
    local ip1 = (i % #path) + 1
    local p0 = path[i]
    local p1 = path[ip1]

    local n0 = p0.normal or vec3(0, 1, 0)
    local n1 = p1.normal or n0
    local hw0 = math.min(p0.widthLeft or 6, p0.widthRight or 6) * 0.85
    local hw1 = math.min(p1.widthLeft or 6, p1.widthRight or 6) * 0.85

    local l0 = p0.pos - n0 * hw0 + vec3(0, 0, 0.05)
    local r0 = p0.pos + n0 * hw0 + vec3(0, 0, 0.05)
    local l1 = p1.pos - n1 * hw1 + vec3(0, 0, 0.05)
    local r1 = p1.pos + n1 * hw1 + vec3(0, 0, 0.05)

    local col = zoneSurfaceColor(zones[i])
    -- Dense cross-hatching gives a practical semi-filled zone style
    debugDrawer:drawLine(l0, r0, col)
    debugDrawer:drawLine(l1, r1, col)
    if i % 2 == 0 then
      debugDrawer:drawLine(l0, l1, col)
      debugDrawer:drawLine(r0, r1, col)
    end
  end
end

function M.drawPathAndZones(path, speedProfile, zones)
  if not path or #path < 2 or not debugDrawer or not debugDrawer.drawLine then
    return
  end

  drawTrackRibbon(path, zones)

  for i = 1, #path do
    local ip1 = (i % #path) + 1
    local a = path[i].pos + vec3(0, 0, 0.15)
    local b = path[ip1].pos + vec3(0, 0, 0.15)
    local color = zoneColor(zones[i])

    debugDrawer:drawLine(a, b, color)

    if i % 20 == 0 then
      local label = string.format('%d', math.floor(speedProfile[i] * 3.6 + 0.5))
      if debugDrawer.drawText then
        debugDrawer:drawText(a + vec3(0, 0, 0.4), String(label), color)
      end
    end
  end
end

function M.drawGuidance(guidance)
  if not guidance or not debugDrawer then
    return
  end

  local col = guidance.critical and ColorF(1, 0.25, 0.2, 0.9) or ColorF(0.2, 0.85, 1, 0.85)
  local text = string.format('%s | target %.0f km/h | zone %s', guidance.message, guidance.targetSpeedSoon, guidance.zone)
  if debugDrawer.drawTextAdvanced then
    debugDrawer:drawTextAdvanced(vec3(0, 0, 3), String(text), col, true, false, ColorI(0, 0, 0, 180))
  elseif debugDrawer.drawText then
    debugDrawer:drawText(vec3(0, 0, 3), String(text), col)
  end
end

return M
