local M = {}

local RESULT_PATH = 'settings/BeamNGRaceCoach/test_results.json'

local state = {
  phase = 'track_wait',
  phaseTime = 0,
  trackReloaded = false,
  destinationSet = false,
  results = {
    startedAt = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    success = false,
    steps = {}
  }
}

local function countPairs(tbl)
  local count = 0
  for _ in pairs(tbl or {}) do
    count = count + 1
  end
  return count
end

local function writeResults()
  jsonWriteFile(RESULT_PATH, state.results, true)
end

local function getCoachExtension()
  return _G['raceCoach_init'] or _G['raceCoach/init']
end

local function getCoachSnapshot()
  local ext = getCoachExtension()
  if ext and ext.getDebugState then
    return ext.getDebugState()
  end
end

local function recordStep(name, pass, details)
  state.results.steps[#state.results.steps + 1] = {
    name = name,
    pass = pass and true or false,
    details = details or {}
  }
  writeResults()
end

local function finish(success, message)
  state.results.success = success and true or false
  state.results.finishedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
  state.results.message = message
  writeResults()

  if success then
    log('I', 'BeamNGRaceCoachTest', message)
  else
    log('E', 'BeamNGRaceCoachTest', message)
  end

  quit()
end

local function fail(message, details)
  if details then
    recordStep(state.phase, false, details)
  end
  finish(false, message)
end

local function switchPhase(name)
  state.phase = name
  state.phaseTime = 0
end

local function ensureCoachLoaded()
  if not extensions.isExtensionLoaded('raceCoach/init') then
    extensions.load('raceCoach/init')
  end

  local ext = getCoachExtension()
  return ext ~= nil
end

local function chooseDestinationPos()
  local veh = getPlayerVehicle(0)
  local mapData = map.getMap()
  if not veh or not mapData or not mapData.nodes then
    return nil
  end

  local origin = veh:getPosition()
  local minDistSq = 300 * 300
  local maxDistSq = 2500 * 2500
  local bestNode
  local bestDistSq = -1

  for _, node in pairs(mapData.nodes) do
    if node and node.pos and countPairs(node.links) > 0 then
      local distSq = node.pos:squaredDistance(origin)
      if distSq >= minDistSq and distSq <= maxDistSq then
        local goodEdge = false
        for _, edge in pairs(node.links) do
          if (edge.drivability or 0) >= 0.5 then
            goodEdge = true
            break
          end
        end

        if goodEdge and distSq > bestDistSq then
          bestNode = node
          bestDistSq = distSq
        end
      end
    end
  end

  return bestNode and bestNode.pos or nil
end

local function timeoutForPhase()
  if state.phase == 'track_wait' then
    return 90
  end
  if state.phase == 'west_load' then
    return 90
  end
  if state.phase == 'destination_wait' then
    return 60
  end
  return 30
end

local function onTrackPhase()
  local level = getCurrentLevelIdentifier()
  local veh = getPlayerVehicle(0)

  if level ~= 'hirochi_raceway' or not veh then
    return
  end

  if not ensureCoachLoaded() then
    return
  end

  local coachExt = getCoachExtension()
  if coachExt and coachExt.reloadPlan and not state.trackReloaded then
    coachExt.reloadPlan()
    state.trackReloaded = true
  end

  local snap = getCoachSnapshot()
  if snap and snap.loaded and snap.sourceType == 'track' and snap.closed and snap.pathPointCount >= 10 and snap.message then
    recordStep('track_wait', true, snap)
    freeroam_freeroam.startFreeroamByName('west_coast_usa', 'spawn_highway')
    switchPhase('west_load')
  end
end

local function onWestLoadPhase()
  local level = getCurrentLevelIdentifier()
  local veh = getPlayerVehicle(0)

  if level ~= 'west_coast_usa' or not veh then
    return
  end

  if not ensureCoachLoaded() then
    return
  end

  if not state.destinationSet then
    local target = chooseDestinationPos()
    if not target then
      fail('Failed to find a valid destination node on west_coast_usa')
      return
    end

    core_groundMarkers.setPath(target, {clearPathOnReachingTarget = false})
    local coachExt = getCoachExtension()
    if coachExt and coachExt.reloadPlan then
      coachExt.reloadPlan()
    end

    state.results.destination = {
      x = target.x,
      y = target.y,
      z = target.z
    }
    state.destinationSet = true
    writeResults()
    switchPhase('destination_wait')
  end
end

local function onDestinationPhase()
  if getCurrentLevelIdentifier() ~= 'west_coast_usa' then
    return
  end

  local snap = getCoachSnapshot()
  if snap and snap.loaded and snap.sourceType == 'destination' and not snap.closed and snap.pathPointCount >= 4 and snap.message and core_groundMarkers.currentlyHasTarget() then
    recordStep('destination_wait', true, snap)
    finish(true, 'BeamNGRaceCoach automated tests passed')
  end
end

function M.onInit()
  setExtensionUnloadMode(M, 'manual')
end

function M.onExtensionLoaded()
  state.phase = 'track_wait'
  state.phaseTime = 0
  state.trackReloaded = false
  state.destinationSet = false
  writeResults()
  log('I', 'BeamNGRaceCoachTest', 'Harness loaded')
end

function M.onUpdate(dtReal, dtSim, dtRaw)
  state.phaseTime = state.phaseTime + dtReal
  if state.phaseTime > timeoutForPhase() then
    fail('Timed out during ' .. state.phase, {
      phase = state.phase,
      phaseTime = state.phaseTime,
      snapshot = getCoachSnapshot()
    })
    return
  end

  if state.phase == 'track_wait' then
    onTrackPhase()
  elseif state.phase == 'west_load' then
    onWestLoadPhase()
  elseif state.phase == 'destination_wait' then
    onDestinationPhase()
  end
end

return M
