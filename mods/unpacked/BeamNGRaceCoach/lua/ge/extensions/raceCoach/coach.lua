local M = {}

local runtime = {
  cooldown = 0,
  lastMessage = '',
  path = nil,
  speed = nil,
  zones = nil
}

local MESSAGES = {
  BRAKE_NOW = { text = 'Brake now', priority = 100, critical = true },
  SLOW_DOWN = { text = 'Slow down now', priority = 95, critical = true },
  TOO_FAST = { text = 'Too fast for corner', priority = 90, critical = true },
  TURN_IN = { text = 'Turn in now', priority = 65 },
  OFF_LINE = { text = 'Off racing line', priority = 60 },
  MISSED_BRAKE = { text = 'Missed braking zone', priority = 58 },
  ACCEL = { text = 'Accelerate', priority = 40 },
  GOOD_EXIT = { text = 'Good exit', priority = 30 },
  EARLY_THROTTLE = { text = 'Early throttle', priority = 24 },
  EXIT_LOW = { text = 'Exit speed low', priority = 20 },
  GOOD_SPEED = { text = 'Good speed', priority = 15 }
}

local function nearestPathIndex(path, pos)
  local bestIdx = 1
  local bestDist = math.huge
  for i = 1, #path do
    local d = (path[i].pos - pos):length()
    if d < bestDist then
      bestDist = d
      bestIdx = i
    end
  end
  return bestIdx, bestDist
end

local function bestMessage(candidates)
  local winner = nil
  for _, c in ipairs(candidates) do
    if not winner or c.priority > winner.priority then
      winner = c
    end
  end
  return winner
end

function M.reset(path, speedProfile, zones)
  runtime.path = path
  runtime.speed = speedProfile
  runtime.zones = zones
  runtime.cooldown = 0
  runtime.lastMessage = ''
end

function M.update(dt, vehicleState, path, speedProfile, zones)
  runtime.cooldown = math.max(0, runtime.cooldown - dt)

  local idx, dist = nearestPathIndex(path, vehicleState.pos)
  local look = math.min(idx + 12, #path)
  local targetNow = speedProfile[idx] * 3.6
  local targetSoon = speedProfile[look] * 3.6
  local speed = vehicleState.speedKph

  local candidates = {}
  if speed > targetSoon + 16 then
    table.insert(candidates, MESSAGES.BRAKE_NOW)
  elseif speed > targetSoon + 10 then
    table.insert(candidates, MESSAGES.SLOW_DOWN)
  elseif speed > targetSoon + 6 then
    table.insert(candidates, MESSAGES.TOO_FAST)
  end

  if dist > 3.0 then
    table.insert(candidates, MESSAGES.OFF_LINE)
  end

  local zone = zones[idx]
  if zone == 'brake' and speed > targetNow + 6 then
    table.insert(candidates, MESSAGES.MISSED_BRAKE)
  end
  local prevIdx = ((idx - 2 + #zones) % #zones) + 1
  if zone == 'turn_in' and zones[prevIdx] == 'brake' then
    table.insert(candidates, MESSAGES.TURN_IN)
  end
  if zone == 'accel' and speed < targetNow - 3 then
    table.insert(candidates, MESSAGES.ACCEL)
  end
  if zone == 'exit' and speed > targetNow - 2 then
    table.insert(candidates, MESSAGES.GOOD_EXIT)
  elseif zone == 'exit' and speed < targetNow - 8 then
    table.insert(candidates, MESSAGES.EXIT_LOW)
  end

  if #candidates == 0 then
    table.insert(candidates, MESSAGES.GOOD_SPEED)
  end

  local message = bestMessage(candidates)

  if runtime.cooldown <= 0 or message.text ~= runtime.lastMessage or message.critical then
    if guihooks and guihooks.trigger then
      guihooks.trigger('ScenarioRealtimeDisplay', {
        msg = message.text,
        context = string.format('Target %.0f km/h', targetSoon),
        category = message.critical and 'critical' or 'coaching'
      })
    end
    runtime.lastMessage = message.text
    runtime.cooldown = message.critical and 0.15 or 0.8
  end

  return {
    nearestIndex = idx,
    nearestDist = dist,
    targetSpeedNow = targetNow,
    targetSpeedSoon = targetSoon,
    zone = zone,
    message = message.text,
    critical = message.critical and true or false
  }
end

return M
