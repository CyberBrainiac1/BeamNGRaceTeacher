local M = {}

local mpccMath = require('ge/extensions/raceCoach/mpccMath')

local runtime = {
  cooldown = 0,
  lastMessage = '',
  path = nil,
  speed = nil,
  zones = nil,
  source = nil
}

local HUD_CATEGORY = 'raceCoach.coaching'

local MESSAGES = {
  BRAKE_HARD = { text = 'Brake hard', priority = 100, critical = true, ttl = 0.45, icon = 'warning' },
  BRAKE = { text = 'Brake', priority = 95, critical = true, ttl = 0.45, icon = 'warning' },
  LIGHT_BRAKE = { text = 'Light brake', priority = 90, critical = true, ttl = 0.50, icon = 'warning' },
  SLOW_DOWN = { text = 'Slow down', priority = 84, critical = true, ttl = 0.55, icon = 'warning' },
  TURN_IN = { text = 'Turn in', priority = 62, ttl = 0.75, icon = 'info' },
  BACK_TO_LINE = { text = 'Back to line', priority = 58, ttl = 0.80, icon = 'warning' },
  DESTINATION = { text = 'Destination ahead', priority = 50, ttl = 0.85, icon = 'info' },
  ACCEL = { text = 'Accelerate', priority = 40, ttl = 0.80, icon = 'info' },
  SPEED_UP = { text = 'Speed up', priority = 34, ttl = 0.80, icon = 'info' }
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

local function showHud(message)
  if not guihooks then
    return
  end

  if guihooks.message then
    guihooks.message(message.text, message.ttl or 0.8, HUD_CATEGORY, message.icon or 'info')
  end

  if guihooks.trigger then
    guihooks.trigger('ScenarioRealtimeDisplay', {
      msg = message.text,
      big = false
    })
  end
end

function M.clearHud()
  if guihooks then
    if guihooks.message then
      guihooks.message('', 0, HUD_CATEGORY)
    end
    if guihooks.trigger then
      guihooks.trigger('ScenarioRealtimeDisplay', { msg = '' })
    end
  end

  runtime.cooldown = 0
  runtime.lastMessage = ''
end

function M.reset(path, speedProfile, zones, source)
  runtime.path = path
  runtime.speed = speedProfile
  runtime.zones = zones
  runtime.source = source or nil
  runtime.cooldown = 0
  runtime.lastMessage = ''
  runtime.lastS = nil
  M.clearHud()
end

function M.update(dt, vehicleState, path, speedProfile, zones)
  runtime.cooldown = math.max(0, runtime.cooldown - dt)

  local closed = path.closed and true or false
  local projection = mpccMath.projectOnPath(path, vehicleState.pos)
  if not projection then
    return {
      nearestIndex = 1,
      nearestDist = 0,
      targetSpeedNow = 0,
      targetSpeedSoon = 0,
      zone = zones[1],
      message = 'Ready',
      critical = false
    }
  end

  local idx = projection.nearestIndex or 1
  local errors = mpccMath.getErrorInfo(projection, vehicleState.pos.x, vehicleState.pos.y)
  local headingError = mpccMath.headingError(vehicleState.dir, projection.thetaRef)
  runtime.lastS = projection.s

  local previewDistance = math.max(18, math.min(60, vehicleState.speedMps * 0.9))
  local targetNow = (mpccMath.sampleArrayAtS(path, speedProfile, projection.s) or speedProfile[idx] or 0) * 3.6
  local targetSoon = (mpccMath.sampleArrayAtS(path, speedProfile, mpccMath.advanceS(path, projection.s, previewDistance)) or speedProfile[idx] or 0) * 3.6
  local speed = vehicleState.speedKph
  local remainingDistance = math.max(0, (path.totalLength or path[#path].s or 0) - (projection.s or path[idx].s or 0))
  local zone = mpccMath.sampleArrayAtS(path, zones, projection.s) or zones[idx]
  local overshootSoon = speed - targetSoon

  local candidates = {}
  if overshootSoon > 22 then
    table.insert(candidates, MESSAGES.BRAKE_HARD)
  elseif overshootSoon > 13 then
    table.insert(candidates, MESSAGES.BRAKE)
  elseif overshootSoon > 7 then
    table.insert(candidates, MESSAGES.LIGHT_BRAKE)
  elseif overshootSoon > 3 then
    table.insert(candidates, MESSAGES.SLOW_DOWN)
  end

  if math.abs(errors.contouring) > 1.4 or math.abs(errors.lag) > 2.8 then
    table.insert(candidates, MESSAGES.BACK_TO_LINE)
  end

  local prevIdx
  if idx > 1 then
    prevIdx = idx - 1
  elseif closed and #zones > 1 then
    prevIdx = #zones
  end

  if prevIdx and zone == 'turn_in' and (zones[prevIdx] == 'brake' or zones[prevIdx] == 'turn_in')
    and math.abs(headingError) < 0.35 then
    table.insert(candidates, MESSAGES.TURN_IN)
  end

  if (zone == 'accel' or zone == 'exit') and speed < targetNow - 5 then
    table.insert(candidates, MESSAGES.ACCEL)
  elseif zone == 'straight' and speed < targetSoon - 10 then
    table.insert(candidates, MESSAGES.SPEED_UP)
  end

  if not closed and remainingDistance < 40 then
    table.insert(candidates, MESSAGES.DESTINATION)
  end

  local message = bestMessage(candidates)

  if not message then
    if runtime.lastMessage ~= '' then
      M.clearHud()
    end
  elseif runtime.cooldown <= 0 or message.text ~= runtime.lastMessage then
    showHud(message)
    runtime.lastMessage = message.text
    runtime.cooldown = message.ttl or (message.critical and 0.5 or 0.8)
  end

  return {
    nearestIndex = idx,
    nearestDist = projection.distance or 0,
    targetSpeedNow = targetNow,
    targetSpeedSoon = targetSoon,
    zone = zone,
    message = message and message.text or 'Ready',
    critical = message and message.critical and true or false,
    remainingDistance = closed and nil or remainingDistance,
    contouringError = errors.contouring,
    lagError = errors.lag,
    headingError = headingError,
    progressS = projection.s,
    thetaRef = projection.thetaRef,
    sourceLabel = runtime.source and runtime.source.label or 'Guidance',
    sourceDetail = runtime.source and runtime.source.detail or nil
  }
end

return M
