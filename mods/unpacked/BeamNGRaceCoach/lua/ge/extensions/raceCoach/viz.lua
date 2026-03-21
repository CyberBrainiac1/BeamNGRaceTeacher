local M = {}

local DRAW_AHEAD_DISTANCE = 135
local CHEVRON_SPACING = 4.4
local CHEVRON_START_OFFSET = 2.2
local CHEVRON_HEIGHT = 0.06

local ACTION_STYLES = {
  hard_brake = {
    color = ColorF(0.98, 0.18, 0.10, 0.94),
    widthScale = 1.18,
    tailScale = 1.30,
    tipScale = 1.55,
    spacing = 3.7
  },
  brake = {
    color = ColorF(1.00, 0.37, 0.12, 0.92),
    widthScale = 1.08,
    tailScale = 1.22,
    tipScale = 1.46,
    spacing = 3.9
  },
  light_brake = {
    color = ColorF(1.00, 0.67, 0.18, 0.88),
    widthScale = 1.00,
    tailScale = 1.16,
    tipScale = 1.38,
    spacing = 4.1
  },
  coast = {
    color = ColorF(1.00, 0.53, 0.16, 0.82),
    widthScale = 0.96,
    tailScale = 1.08,
    tipScale = 1.28,
    spacing = 4.3
  },
  accel = {
    color = ColorF(0.18, 0.92, 0.34, 0.88),
    widthScale = 1.00,
    tailScale = 1.12,
    tipScale = 1.34,
    spacing = 4.4
  },
  speed_up = {
    color = ColorF(0.38, 0.95, 0.45, 0.80),
    widthScale = 0.94,
    tailScale = 1.04,
    tipScale = 1.24,
    spacing = 4.6
  },
  hold = {
    color = ColorF(1.00, 0.50, 0.17, 0.62),
    widthScale = 0.88,
    tailScale = 1.00,
    tipScale = 1.20,
    spacing = 4.8
  }
}

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function segmentCount(path)
  if path.closed then
    return #path
  end
  return math.max(0, #path - 1)
end

local function nextIndex(path, i)
  if i < #path then
    return i + 1
  end
  if path.closed then
    return 1
  end
  return nil
end

local function normalizeSafe(v, fallback)
  if v:length() < 1e-3 then
    return vec3(fallback.x, fallback.y, fallback.z)
  end
  v:normalize()
  return v
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function offsetIndex(path, i, steps)
  local idx = i
  for _ = 1, steps do
    local ip1 = nextIndex(path, idx)
    if not ip1 then
      return idx
    end
    idx = ip1
  end
  return idx
end

local function samplePoint(p0, p1, t, segmentDir)
  local tangent = segmentDir
  if p0.tangent and p1.tangent then
    tangent = normalizeSafe(p0.tangent + (p1.tangent - p0.tangent) * t, segmentDir)
  end

  local normal = vec3(0, 1, 0)
  if p0.normal and p1.normal then
    normal = normalizeSafe(p0.normal + (p1.normal - p0.normal) * t, normal)
  elseif p0.normal then
    normal = vec3(p0.normal.x, p0.normal.y, p0.normal.z)
  end

  return {
    pos = p0.pos + (p1.pos - p0.pos) * t,
    tangent = tangent,
    normal = normal,
    widthLeft = lerp(p0.widthLeft or 4, p1.widthLeft or 4, t),
    widthRight = lerp(p0.widthRight or 4, p1.widthRight or 4, t)
  }
end

local function actionStyleForPoint(path, speedProfile, zones, i)
  local zone = zones[i]
  local vNow = (speedProfile[i] or 0) * 3.6
  local nearIdx = offsetIndex(path, i, 4)
  local farIdx = offsetIndex(path, i, 10)
  local vNear = (speedProfile[nearIdx] or speedProfile[i] or 0) * 3.6
  local vFar = (speedProfile[farIdx] or speedProfile[i] or 0) * 3.6

  local dropNear = math.max(0, vNow - vNear)
  local dropFar = math.max(0, vNow - vFar)
  local riseNear = math.max(0, vNear - vNow)

  if dropFar > 42 or (zone == 'brake' and dropNear > 20) then
    return ACTION_STYLES.hard_brake
  end
  if dropFar > 24 or (zone == 'brake' and dropNear > 12) then
    return ACTION_STYLES.brake
  end
  if dropFar > 12 or zone == 'turn_in' or (zone == 'brake' and dropNear > 6) then
    return ACTION_STYLES.light_brake
  end
  if zone == 'apex' or zone == 'corner' then
    return ACTION_STYLES.coast
  end
  if zone == 'accel' or riseNear > 9 then
    return ACTION_STYLES.accel
  end
  if zone == 'exit' or riseNear > 4 then
    return ACTION_STYLES.speed_up
  end
  return ACTION_STYLES.hold
end

local function drawFilledTriangle(a, b, c, color)
  if not debugDrawer or not debugDrawer.drawTriSolid then
    return
  end

  debugDrawer:drawTriSolid(a, b, c, color)
  debugDrawer:drawTriSolid(a, c, b, color)
end

local function drawChevron(sample, style)
  local laneWidth = math.min(sample.widthLeft or 4, sample.widthRight or 4)
  local halfWidth = clamp(laneWidth * 0.12, 0.45, 0.95) * (style.widthScale or 1.0)
  local tailLength = halfWidth * (style.tailScale or 1.0)
  local tipLength = halfWidth * (style.tipScale or 1.2)
  local center = sample.pos + vec3(0, 0, CHEVRON_HEIGHT)
  local baseCenter = center - sample.tangent * tailLength
  local tipCenter = center + sample.tangent * tipLength
  local gap = halfWidth * 0.30
  local tipInset = gap * 0.16

  local leftOuter = baseCenter - sample.normal * halfWidth
  local leftInner = baseCenter - sample.normal * gap
  local rightOuter = baseCenter + sample.normal * halfWidth
  local rightInner = baseCenter + sample.normal * gap
  local tipLeft = tipCenter - sample.normal * tipInset
  local tipRight = tipCenter + sample.normal * tipInset

  drawFilledTriangle(leftOuter, leftInner, tipLeft, style.color)
  drawFilledTriangle(rightInner, rightOuter, tipRight, style.color)
end

local function drawChevronTrail(path, speedProfile, zones, guidance)
  local startIndex = guidance and guidance.nearestIndex or 1
  local traveled = 0
  local nextMarker = CHEVRON_START_OFFSET
  local idx = startIndex
  local guard = 0

  while guard <= segmentCount(path) and traveled < DRAW_AHEAD_DISTANCE do
    local ip1 = nextIndex(path, idx)
    if not ip1 then
      break
    end

    local p0 = path[idx]
    local p1 = path[ip1]
    local segment = p1.pos - p0.pos
    local segLen = segment:length()

    if segLen > 1e-3 then
      local segDir = normalizeSafe(segment, p0.tangent or vec3(1, 0, 0))
      while nextMarker <= traveled + segLen and nextMarker <= DRAW_AHEAD_DISTANCE do
        local localDist = nextMarker - traveled
        local t = localDist / segLen
        local sample = samplePoint(p0, p1, t, segDir)
        local style = actionStyleForPoint(path, speedProfile, zones, idx)
        drawChevron(sample, style)
        nextMarker = nextMarker + (style.spacing or CHEVRON_SPACING)
      end
      traveled = traveled + segLen
    end

    idx = ip1
    guard = guard + 1
    if path.closed and idx == startIndex then
      break
    end
  end
end

function M.drawPathAndZones(path, speedProfile, zones, guidance)
  if not path or #path < 2 or not debugDrawer or not debugDrawer.drawTriSolid then
    return
  end

  drawChevronTrail(path, speedProfile, zones, guidance)
end

function M.drawGuidance(guidance)
end

return M
