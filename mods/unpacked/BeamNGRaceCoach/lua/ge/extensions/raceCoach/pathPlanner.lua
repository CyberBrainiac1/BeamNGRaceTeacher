local M = {}

local function vec3FromPoint(p)
  if p.pos then
    return vec3(p.pos.x, p.pos.y, p.pos.z)
  end
  return vec3(p.x or 0, p.y or 0, p.z or 0)
end

local function scalarLerp(a, b, t)
  return a + (b - a) * t
end

local function prepareControlPoints(points, closed)
  local control = {}
  for i = 1, #points do
    local p = points[i]
    control[i] = {
      pos = vec3FromPoint(p),
      widthLeft = p.widthLeft or p.width or p.radius or 6,
      widthRight = p.widthRight or p.width or p.radius or 6
    }
  end

  if closed and #control > 2 then
    local first = control[1]
    local last = control[#control]
    if first.pos:squaredDistance(last.pos) < 0.25 then
      table.remove(control, #control)
    end
  end

  return control
end

local function buildSegments(points, closed)
  local segments = {}
  local totalLength = 0

  for i = 1, #points - 1 do
    local len = (points[i + 1].pos - points[i].pos):length()
    if len > 1e-3 then
      segments[#segments + 1] = {
        a = i,
        b = i + 1,
        start = totalLength,
        len = len
      }
      totalLength = totalLength + len
    end
  end

  if closed and #points > 2 then
    local len = (points[1].pos - points[#points].pos):length()
    if len > 1e-3 then
      segments[#segments + 1] = {
        a = #points,
        b = 1,
        start = totalLength,
        len = len
      }
      totalLength = totalLength + len
    end
  end

  return segments, totalLength
end

local function sampleControlPoints(control, segments, totalLength, spacing, closed)
  if spacing <= 0 or totalLength <= spacing * 0.5 or #segments == 0 then
    return control, totalLength
  end

  local out = {}
  local segIdx = 1

  local function addSample(targetDist)
    while segIdx < #segments and targetDist > segments[segIdx].start + segments[segIdx].len do
      segIdx = segIdx + 1
    end

    local seg = segments[segIdx]
    if not seg then
      seg = segments[#segments]
    end

    local a = control[seg.a]
    local b = control[seg.b]
    local localDist = math.max(0, math.min(seg.len, targetDist - seg.start))
    local t = seg.len > 1e-3 and (localDist / seg.len) or 0

    out[#out + 1] = {
      pos = a.pos + (b.pos - a.pos) * t,
      widthLeft = scalarLerp(a.widthLeft, b.widthLeft, t),
      widthRight = scalarLerp(a.widthRight, b.widthRight, t)
    }
  end

  local dist = 0
  while dist < totalLength do
    addSample(dist)
    dist = dist + spacing
  end

  if not closed then
    local last = out[#out]
    if not last or last.pos:squaredDistance(control[#control].pos) > 0.25 then
      out[#out + 1] = {
        pos = vec3(control[#control].pos.x, control[#control].pos.y, control[#control].pos.z),
        widthLeft = control[#control].widthLeft,
        widthRight = control[#control].widthRight
      }
    end
  end

  return out, totalLength
end

local function prevIndex(path, i)
  if i > 1 then
    return i - 1
  end
  if path.closed and #path > 2 then
    return #path
  end
  return nil
end

local function nextIndex(path, i)
  if i < #path then
    return i + 1
  end
  if path.closed and #path > 2 then
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

local function computeGeometry(path)
  if #path == 0 then
    path.totalLength = 0
    return
  end

  path[1].s = 0
  local s = 0
  for i = 2, #path do
    s = s + (path[i].pos - path[i - 1].pos):length()
    path[i].s = s
  end

  path.totalLength = s
  if path.closed and #path > 2 then
    path.totalLength = path.totalLength + (path[1].pos - path[#path].pos):length()
  end

  for i = 1, #path do
    local prevIdx = prevIndex(path, i)
    local nextIdx = nextIndex(path, i)
    local curr = path[i]

    local t
    if prevIdx and nextIdx then
      t = path[nextIdx].pos - path[prevIdx].pos
    elseif nextIdx then
      t = path[nextIdx].pos - curr.pos
    elseif prevIdx then
      t = curr.pos - path[prevIdx].pos
    else
      t = vec3(1, 0, 0)
    end

    t = normalizeSafe(t, vec3(1, 0, 0))

    local up = vec3(0, 0, 1)
    local n = up:cross(t)
    n = normalizeSafe(n, vec3(0, 1, 0))

    curr.tangent = t
    curr.normal = n
  end

  for i = 1, #path do
    local prevIdx = prevIndex(path, i)
    local nextIdx = nextIndex(path, i)
    local curr = path[i]

    if not prevIdx or not nextIdx then
      curr.curvature = 0
    else
      local a = curr.pos - path[prevIdx].pos
      local b = path[nextIdx].pos - curr.pos
      local lenA = a:length()
      local lenB = b:length()
      if lenA < 1e-3 or lenB < 1e-3 then
        curr.curvature = 0
      else
        a:normalize()
        b:normalize()
        local ds = math.max((lenA + lenB) * 0.5, 1e-3)
        local curvature = (b - a):length() / ds
        local cross = a:cross(b)
        curr.curvature = curvature * (cross.z >= 0 and 1 or -1)
      end
    end
  end
end

local function copyPath(path)
  local out = {
    closed = path.closed and true or false,
    totalLength = path.totalLength or 0
  }

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

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function buildOffsetPath(referencePath, offsets)
  local path = copyPath(referencePath)
  for i = 1, #path do
    local offset = offsets[i] or 0
    path[i].lateralOffset = offset
    path[i].pos = path[i].pos + path[i].normal * offset
  end
  computeGeometry(path)
  return path
end

local function segmentSpacing(path, i)
  local prevIdx = prevIndex(path, i)
  local nextIdx = nextIndex(path, i)

  if prevIdx and nextIdx then
    local prevDs = (path[i].pos - path[prevIdx].pos):length()
    local nextDs = (path[nextIdx].pos - path[i].pos):length()
    return math.max((prevDs + nextDs) * 0.5, 0.5)
  end
  if nextIdx then
    return math.max((path[nextIdx].pos - path[i].pos):length(), 0.5)
  end
  if prevIdx then
    return math.max((path[i].pos - path[prevIdx].pos):length(), 0.5)
  end
  return 1.0
end

local function endpointBlend(i, n, rampCount)
  if rampCount <= 0 or n <= 2 then
    return 1.0
  end

  local fromStart = clamp((i - 1) / rampCount, 0.0, 1.0)
  local fromEnd = clamp((n - i) / rampCount, 0.0, 1.0)
  return math.min(fromStart, fromEnd)
end

local function seedOffsets(path, maxTrackUsage)
  local offsets = {}
  for i = 1, #path do
    local widthLim = math.min(path[i].widthLeft, path[i].widthRight) * maxTrackUsage
    offsets[i] = clamp(path[i].preferredOffset or 0, -widthLim, widthLim)
  end
  return offsets
end

function M.hydratePath(points, options)
  options = options or {}
  local closed = options.closed and true or false
  local path = {
    closed = closed,
    totalLength = 0
  }

  for i = 1, #points do
    local p = points[i]
    path[i] = {
      pos = vec3FromPoint(p),
      widthLeft = p.widthLeft or p.width or p.radius or 6,
      widthRight = p.widthRight or p.width or p.radius or 6,
      lateralOffset = p.lateralOffset or 0,
      preferredOffset = p.preferredOffset or 0,
      s = 0,
      curvature = 0
    }
  end

  if #path > 1 then
    computeGeometry(path)
  end

  return path
end

function M.buildBaselinePath(points, options)
  options = options or {}
  local closed = options.closed and true or false
  local control = prepareControlPoints(points, closed)

  if #control < 2 then
    return { closed = closed, totalLength = 0 }
  end

  local segments, totalLength = buildSegments(control, closed)
  control, totalLength = sampleControlPoints(control, segments, totalLength, options.resampleSpacing or 0, closed)

  local path = {
    closed = closed,
    totalLength = totalLength or 0
  }

  for i = 1, #control do
    path[i] = {
      x = control[i].pos.x,
      y = control[i].pos.y,
      z = control[i].pos.z,
      widthLeft = control[i].widthLeft,
      widthRight = control[i].widthRight
    }
  end

  return M.hydratePath(path, { closed = closed })
end

local function buildCornerPreference(path, lookaheadPts, maxTrackUsage, preferredScale)
  local n = #path
  for i = 1, n do
    local k0 = path[i].curvature
    local kAbs = math.abs(k0)

    local futureMax = 0
    local futureSign = 0
    for j = 1, lookaheadPts do
      local idx = i + j
      if idx > n then
        if path.closed then
          idx = ((idx - 1) % n) + 1
        else
          break
        end
      end

      local kj = path[idx].curvature
      if math.abs(kj) > futureMax then
        futureMax = math.abs(kj)
        futureSign = kj >= 0 and 1 or -1
      end
    end

    local turnSign = kAbs > 1e-4 and (k0 >= 0 and 1 or -1) or futureSign
    local severity = math.min(math.max(futureMax * 10.0, 0), 1)
    local maxOffset = math.min(path[i].widthLeft, path[i].widthRight) * maxTrackUsage

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

    path[i].preferredOffset = pref * preferredScale
  end
end

local function solveLocalMpccOffset(referencePath, workingPath, offsets, config, i)
  local closed = referencePath.closed and true or false
  local n = #referencePath

  if not closed and (i == 1 or i == n) then
    return 0
  end

  local im1 = i > 1 and i - 1 or n
  local ip1 = i < n and i + 1 or 1

  local om = offsets[im1] or 0
  local oi = offsets[i] or 0
  local op = offsets[ip1] or 0

  local ds = segmentSpacing(workingPath, i)
  local curvature = workingPath[i].curvature or 0
  local widthLim = math.min(referencePath[i].widthLeft, referencePath[i].widthRight) * config.maxTrackUsage
  local pref = referencePath[i].preferredOffset or 0
  local blend = config.closed and 1.0 or endpointBlend(i, n, config.endpointRampCount)

  local qContour = (config.wContouring or 1.0) * blend
  local qLag = config.wLag or 0.6
  local qProgress = (config.wProgress or 0.45) * blend
  local qSmooth = config.wSmooth or 0.55
  local qCurvature = config.wCurvature or 0.9
  local qPreferred = (config.wPreferred or 1.2) * blend

  local qRef = qContour + qPreferred
  local curvatureSq = curvature * curvature
  local numerator = 2.0 * qRef * pref
    + (2.0 * qSmooth + 4.0 * qCurvature) * (om + op)
    + qProgress * ds * curvature
  local denominator = 2.0 * qRef
    + 2.0 * qLag * curvatureSq
    + 4.0 * qSmooth
    + 8.0 * qCurvature

  local target = denominator > 1e-6 and (numerator / denominator) or oi
  target = clamp(target, -widthLim, widthLim)

  return lerp(oi, target, config.alpha or 0.2)
end

function M.improvePathMPCCStyle(baselinePath, config)
  local referencePath = copyPath(baselinePath)
  computeGeometry(referencePath)

  local closed = referencePath.closed and true or false
  local solverCfg = {
    closed = closed,
    iterations = config.iterations or 24,
    alpha = config.alpha or 0.18,
    wContouring = config.wContouring or 0.85,
    wLag = config.wLag or 0.75,
    wProgress = config.wProgress or 0.55,
    wSmooth = config.wSmooth or 0.60,
    wCurvature = config.wCurvature or 1.0,
    wPreferred = config.wPreferred or 1.35,
    lookaheadPts = config.lookaheadPts or 10,
    maxTrackUsage = config.maxTrackUsage or (closed and 0.92 or 0.4),
    preferredScale = config.preferredScale or 1.0,
    endpointRampCount = config.endpointRampCount or 8
  }

  buildCornerPreference(referencePath, solverCfg.lookaheadPts, solverCfg.maxTrackUsage, solverCfg.preferredScale)

  local offsets = seedOffsets(referencePath, solverCfg.maxTrackUsage)
  local workingPath = buildOffsetPath(referencePath, offsets)

  -- This shapes the reference racing line.
  -- The repo-derived MPCC contouring / lag / progress tracking math lives in mpccMath.lua and is used by the live coach.
  -- Discrete Frenet MPCC approximation:
  -- J = q_c * e_c^2 + q_l * e_l^2 - q_p * theta_dot + q_s * d_offset^2 + q_k * dd_offset^2
  -- with e_c taken against the geometric racing-line prior and e_l linearized as kappa * e_y.
  for _ = 1, solverCfg.iterations do
    workingPath = buildOffsetPath(referencePath, offsets)
    for i = 1, #referencePath do
      offsets[i] = solveLocalMpccOffset(referencePath, workingPath, offsets, solverCfg, i)
    end
  end

  return buildOffsetPath(referencePath, offsets)
end

return M
