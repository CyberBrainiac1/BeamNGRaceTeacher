local M = {}

local function vec3FromPoint(p)
  return vec3(p.x or 0, p.y or 0, p.z or 0)
end

local function copyPath(path)
  local out = {}
  for i = 1, #path do
    local p = path[i]
    out[i] = {
      pos = vec3(p.pos.x, p.pos.y, p.pos.z),
      widthLeft = p.widthLeft,
      widthRight = p.widthRight,
      s = p.s,
      curvature = p.curvature,
      tangent = p.tangent and vec3(p.tangent.x, p.tangent.y, p.tangent.z) or nil,
      normal = p.normal and vec3(p.normal.x, p.normal.y, p.normal.z) or nil,
      preferredOffset = p.preferredOffset or 0,
      lateralOffset = p.lateralOffset or 0
    }
  end
  return out
end

local function computeGeometry(path)
  local s = 0
  for i = 1, #path do
    local prev = path[(i - 2 + #path) % #path + 1]
    local next = path[i % #path + 1]
    local curr = path[i]

    local t = (next.pos - prev.pos)
    if t:length() < 1e-3 then
      t = vec3(1, 0, 0)
    else
      t:normalize()
    end

    local up = vec3(0, 0, 1)
    local n = up:cross(t)
    if n:length() < 1e-3 then
      n = vec3(0, 1, 0)
    else
      n:normalize()
    end

    curr.tangent = t
    curr.normal = n

    local d = (curr.pos - prev.pos):length()
    s = s + d
    curr.s = s
  end

  for i = 1, #path do
    local prev = path[(i - 2 + #path) % #path + 1]
    local curr = path[i]
    local next = path[i % #path + 1]

    local a = curr.pos - prev.pos
    local b = next.pos - curr.pos
    local ds = math.max((a:length() + b:length()) * 0.5, 1e-3)

    local da = curr.tangent - prev.tangent
    curr.curvature = da:length() / ds

    local cross = a:cross(b)
    local sign = cross.z >= 0 and 1 or -1
    curr.curvature = curr.curvature * sign
  end
end

function M.buildBaselinePath(points)
  local path = {}
  for i = 1, #points do
    local p = points[i]
    path[i] = {
      pos = vec3FromPoint(p),
      widthLeft = p.widthLeft or 6,
      widthRight = p.widthRight or 6,
      lateralOffset = 0,
      preferredOffset = 0,
      s = 0,
      curvature = 0
    }
  end

  if #path > 2 then
    computeGeometry(path)
  end

  return path
end

local function buildCornerPreference(path, lookaheadPts)
  local n = #path
  for i = 1, n do
    local k0 = path[i].curvature
    local kAbs = math.abs(k0)

    local futureMax = 0
    local futureSign = 0
    for j = 1, lookaheadPts do
      local idx = ((i + j - 1) % n) + 1
      local kj = path[idx].curvature
      if math.abs(kj) > futureMax then
        futureMax = math.abs(kj)
        futureSign = kj >= 0 and 1 or -1
      end
    end

    local turnSign = kAbs > 1e-4 and (k0 >= 0 and 1 or -1) or futureSign
    local severity = math.min(math.max(futureMax * 10.0, 0), 1)

    local maxOffset = math.min(path[i].widthLeft, path[i].widthRight) * 0.9

    -- MPCC-inspired line shape target:
    -- entry: outside lane (opposite curvature sign)
    -- apex: inside lane (same sign)
    -- exit: drift outward again for speed
    local trend = futureMax - kAbs
    local phase
    if trend > 0.002 then
      phase = 'entry'
    elseif trend < -0.002 then
      phase = 'exit'
    else
      phase = 'apex'
    end

    local pref = 0
    if phase == 'entry' then
      pref = -turnSign * maxOffset * 0.8 * severity
    elseif phase == 'apex' then
      pref = turnSign * maxOffset * 0.6 * severity
    else
      pref = -turnSign * maxOffset * 0.5 * severity
    end

    path[i].preferredOffset = pref
  end
end

function M.improvePathMPCCStyle(baselinePath, config)
  local path = copyPath(baselinePath)
  computeGeometry(path)

  local iterations = config.iterations or 20
  local alpha = config.alpha or 0.12
  local wContouring = config.wContouring or 1.0
  local wLag = config.wLag or 0.6
  local wCurvature = config.wCurvature or 0.9
  local wPreferred = config.wPreferred or 1.4
  local lookaheadPts = config.lookaheadPts or 10

  buildCornerPreference(path, lookaheadPts)

  local n = #path
  local offsets = {}
  for i = 1, n do
    offsets[i] = 0
  end

  for _ = 1, iterations do
    local grad = {}

    for i = 1, n do
      local im1 = ((i - 2 + n) % n) + 1
      local ip1 = (i % n) + 1

      local widthLim = math.min(path[i].widthLeft, path[i].widthRight) * 0.95
      local oi = offsets[i]
      local om = offsets[im1]
      local op = offsets[ip1]

      local contourTerm = 2.0 * oi
      local lagTerm = 2.0 * (2.0 * oi - om - op)

      local curvProxy = (op - 2 * oi + om)
      local curvTerm = -4.0 * curvProxy

      local prefTerm = 2.0 * (oi - path[i].preferredOffset)

      local g = wContouring * contourTerm + wLag * lagTerm + wCurvature * curvTerm + wPreferred * prefTerm
      grad[i] = g

      offsets[i] = math.max(-widthLim, math.min(widthLim, oi - alpha * g))
    end
  end

  for i = 1, n do
    path[i].lateralOffset = offsets[i]
    path[i].pos = path[i].pos + path[i].normal * offsets[i]
  end

  computeGeometry(path)
  return path
end

return M
