local M = {}

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function wrapAngle(angle)
  while angle > math.pi do
    angle = angle - 2.0 * math.pi
  end
  while angle < -math.pi do
    angle = angle + 2.0 * math.pi
  end
  return angle
end

local function vecLengthSquared(v)
  return v.x * v.x + v.y * v.y + v.z * v.z
end

local function normalizeSafe(v, fallback)
  if vecLengthSquared(v) < 1e-6 then
    return vec3(fallback.x, fallback.y, fallback.z)
  end
  v:normalize()
  return v
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

local function segmentArcBounds(path, i, ip1, segLen)
  local s0 = path[i].s or 0
  local s1
  if ip1 == 1 and path.closed then
    s1 = path.totalLength or (s0 + segLen)
  else
    s1 = path[ip1].s or (s0 + segLen)
  end
  return s0, s1
end

function M.advanceS(path, s, distance)
  if not path then
    return 0
  end

  local totalLength = path.totalLength or 0
  local out = (s or 0) + (distance or 0)

  if path.closed and totalLength > 1e-3 then
    out = out % totalLength
    if out < 0 then
      out = out + totalLength
    end
    return out
  end

  return clamp(out, 0, totalLength)
end

function M.referenceAtS(path, s)
  if not path or #path < 2 then
    return nil
  end

  local totalLength = path.totalLength or 0
  if path.closed and totalLength > 1e-3 then
    s = M.advanceS(path, s, 0)
  else
    s = clamp(s or 0, 0, totalLength)
  end

  for i = 1, segmentCount(path) do
    local ip1 = nextIndex(path, i)
    if ip1 then
      local p0 = path[i]
      local p1 = path[ip1]
      local segment = p1.pos - p0.pos
      local segLen = segment:length()
      if segLen > 1e-4 then
        local s0, s1 = segmentArcBounds(path, i, ip1, segLen)
        if s >= s0 and s <= s1 then
          local t = clamp((s - s0) / math.max(s1 - s0, 1e-4), 0.0, 1.0)
          local sample = {
            pos = p0.pos + segment * t,
            tangent = normalizeSafe(segment, p0.tangent or vec3(1, 0, 0)),
            normal = p0.normal and vec3(p0.normal.x, p0.normal.y, p0.normal.z) or vec3(0, 1, 0),
            thetaRef = 0,
            dThetaRef = lerp(p0.curvature or 0, p1.curvature or 0, t),
            s = s,
            curvature = lerp(p0.curvature or 0, p1.curvature or 0, t),
            widthLeft = lerp(p0.widthLeft or 4, p1.widthLeft or 4, t),
            widthRight = lerp(p0.widthRight or 4, p1.widthRight or 4, t),
            segmentIndex = i,
            nextIndex = ip1,
            t = t
          }

          if p0.tangent and p1.tangent then
            sample.tangent = normalizeSafe(p0.tangent + (p1.tangent - p0.tangent) * t, sample.tangent)
          end
          if p0.normal and p1.normal then
            sample.normal = normalizeSafe(p0.normal + (p1.normal - p0.normal) * t, sample.normal)
          end

          sample.thetaRef = math.atan2(sample.tangent.y, sample.tangent.x)
          return sample
        end
      end
    end
  end

  local last = path[#path]
  return {
    pos = vec3(last.pos.x, last.pos.y, last.pos.z),
    tangent = last.tangent and vec3(last.tangent.x, last.tangent.y, last.tangent.z) or vec3(1, 0, 0),
    normal = last.normal and vec3(last.normal.x, last.normal.y, last.normal.z) or vec3(0, 1, 0),
    thetaRef = last.tangent and math.atan2(last.tangent.y, last.tangent.x) or 0,
    dThetaRef = last.curvature or 0,
    s = last.s or 0,
    curvature = last.curvature or 0,
    widthLeft = last.widthLeft or 4,
    widthRight = last.widthRight or 4,
    segmentIndex = math.max(1, #path - 1),
    nextIndex = #path,
    t = 1.0
  }
end

function M.projectOnPath(path, pos)
  if not path or #path < 2 or not pos then
    return nil
  end

  local best
  local bestDistSq = math.huge

  for i = 1, segmentCount(path) do
    local ip1 = nextIndex(path, i)
    if ip1 then
      local p0 = path[i]
      local p1 = path[ip1]
      local segment = p1.pos - p0.pos
      local segLenSq = vecLengthSquared(segment)
      if segLenSq > 1e-6 then
        local rel = pos - p0.pos
        local t = clamp((rel.x * segment.x + rel.y * segment.y + rel.z * segment.z) / segLenSq, 0.0, 1.0)
        local projPos = p0.pos + segment * t
        local dx = pos.x - projPos.x
        local dy = pos.y - projPos.y
        local dz = pos.z - projPos.z
        local distSq = dx * dx + dy * dy + dz * dz
        if distSq < bestDistSq then
          local segLen = math.sqrt(segLenSq)
          local s0, s1 = segmentArcBounds(path, i, ip1, segLen)
          local tangent = normalizeSafe(segment, p0.tangent or vec3(1, 0, 0))
          local normal = p0.normal and vec3(p0.normal.x, p0.normal.y, p0.normal.z) or vec3(0, 1, 0)
          if p0.tangent and p1.tangent then
            tangent = normalizeSafe(p0.tangent + (p1.tangent - p0.tangent) * t, tangent)
          end
          if p0.normal and p1.normal then
            normal = normalizeSafe(p0.normal + (p1.normal - p0.normal) * t, normal)
          end

          best = {
            pos = projPos,
            tangent = tangent,
            normal = normal,
            thetaRef = math.atan2(tangent.y, tangent.x),
            dThetaRef = lerp(p0.curvature or 0, p1.curvature or 0, t),
            s = lerp(s0, s1, t),
            curvature = lerp(p0.curvature or 0, p1.curvature or 0, t),
            widthLeft = lerp(p0.widthLeft or 4, p1.widthLeft or 4, t),
            widthRight = lerp(p0.widthRight or 4, p1.widthRight or 4, t),
            segmentIndex = i,
            nextIndex = ip1,
            t = t,
            distanceSq = distSq,
            distance = math.sqrt(distSq),
            nearestIndex = t < 0.5 and i or ip1
          }
          bestDistSq = distSq
        end
      end
    end
  end

  return best
end

function M.sampleArrayAtS(path, values, s)
  if not path or not values or #values == 0 then
    return nil
  end

  local ref = M.referenceAtS(path, s)
  if not ref then
    return values[1]
  end

  local i = ref.segmentIndex or 1
  local ip1 = ref.nextIndex or i
  local t = ref.t or 0
  local v0 = values[i] or values[#values]
  local v1 = values[ip1] or v0
  if type(v0) ~= 'number' or type(v1) ~= 'number' then
    return t < 0.5 and v0 or v1
  end
  return lerp(v0, v1, t)
end

function M.getErrorInfo(projection, x, y)
  if not projection then
    return nil
  end

  local thetaRef = projection.thetaRef or 0
  local sinTheta = math.sin(thetaRef)
  local cosTheta = math.cos(thetaRef)
  local xRef = projection.pos.x
  local yRef = projection.pos.y
  local dxRef = projection.tangent and projection.tangent.x or cosTheta
  local dyRef = projection.tangent and projection.tangent.y or sinTheta
  local dThetaRef = projection.dThetaRef or 0

  local eC = -sinTheta * (xRef - x) + cosTheta * (yRef - y)
  local eL = cosTheta * (xRef - x) + sinTheta * (yRef - y)

  local dContouring = -dThetaRef * cosTheta * (xRef - x)
    - dThetaRef * sinTheta * (yRef - y)
    - dxRef * sinTheta
    + dyRef * cosTheta
  local dLag = -dThetaRef * sinTheta * (xRef - x)
    + dThetaRef * cosTheta * (yRef - y)
    + dxRef * cosTheta
    + dyRef * sinTheta

  return {
    contouring = eC,
    lag = eL,
    dContouring = dContouring,
    dLag = dLag
  }
end

function M.headingError(dir, thetaRef)
  if not dir then
    return 0
  end

  return wrapAngle(math.atan2(dir.y, dir.x) - (thetaRef or 0))
end

return M
