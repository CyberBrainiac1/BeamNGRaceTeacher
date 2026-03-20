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
  local vmax = vehicleCfg.vmax or 83.0 -- ~299 kph

  local n = #path
  local v = {}
  local ds = {}

  for i = 1, n do
    local im1 = ((i - 2 + n) % n) + 1
    ds[i] = math.max((path[i].pos - path[im1].pos):length(), 0.5)

    local k = math.max(math.abs(path[i].curvature), 1e-4)
    local vLat = math.sqrt((mu * g) / k)
    v[i] = math.min(vLat, vmax)
  end

  for i = 2, n do
    v[i] = math.min(v[i], math.sqrt(v[i - 1] * v[i - 1] + 2 * maxAccel * ds[i]))
  end

  for i = n - 1, 1, -1 do
    v[i] = math.min(v[i], math.sqrt(v[i + 1] * v[i + 1] + 2 * maxBrake * ds[i + 1]))
  end

  local zones = {}
  for i = 1, n do
    local ip1 = (i % n) + 1
    local dv = v[ip1] - v[i]
    zones[i] = classifyZone(math.abs(path[i].curvature), dv)
  end

  return v, zones
end

return M
