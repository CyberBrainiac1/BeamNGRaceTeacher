local M = {}

local function classifyZone(curvAbs, dv)
  if curvAbs < 0.01 then
    if dv > 0.5 then
      return 'accel'
    end
    return 'straight'
  end

  if dv < -1.2 then
    return 'brake'
  end

  if curvAbs > 0.065 then
    return 'apex'
  end

  if dv < -0.3 then
    return 'turn_in'
  end

  if dv > 0.2 then
    return 'exit'
  end

  return 'corner'
end

function M.buildSpeedAndZones(path, vehicleCfg)
  local mu = vehicleCfg.mu or 1.12
  local g = 9.81
  local maxAccel = vehicleCfg.maxAccel or 4.5
  local maxBrake = vehicleCfg.maxBrake or 8.5
  local vmax = vehicleCfg.vmax or 83.0

  local n = #path
  local closed = path.closed and true or false
  local v = {}
  local ds = {}

  if n == 0 then
    return v, {}
  end

  for i = 1, n do
    local prevIdx
    if i > 1 then
      prevIdx = i - 1
    elseif closed and n > 1 then
      prevIdx = n
    else
      prevIdx = math.min(2, n)
    end

    ds[i] = math.max((path[i].pos - path[prevIdx].pos):length(), 0.5)

    local k = math.max(math.abs(path[i].curvature), 1e-4)
    local vLat = math.sqrt((mu * g) / k)
    v[i] = math.min(vLat, vmax)
  end

  local smoothingPasses = closed and 2 or 1
  for _ = 1, smoothingPasses do
    for i = 2, n do
      v[i] = math.min(v[i], math.sqrt(v[i - 1] * v[i - 1] + 2 * maxAccel * ds[i]))
    end

    for i = n - 1, 1, -1 do
      v[i] = math.min(v[i], math.sqrt(v[i + 1] * v[i + 1] + 2 * maxBrake * ds[i + 1]))
    end
  end

  local zones = {}
  for i = 1, n do
    local ip1
    if i < n then
      ip1 = i + 1
    elseif closed then
      ip1 = 1
    else
      ip1 = i
    end

    local dv = v[ip1] - v[i]
    zones[i] = classifyZone(math.abs(path[i].curvature), dv)
  end

  if not closed and n > 0 then
    zones[n] = 'exit'
  end

  return v, zones
end

return M
