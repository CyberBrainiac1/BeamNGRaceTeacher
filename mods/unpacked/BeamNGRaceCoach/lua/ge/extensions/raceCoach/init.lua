local M = {}

local pathPlanner = require('ge/extensions/raceCoach/pathPlanner')
local speedPlanner = require('ge/extensions/raceCoach/speedPlanner')
local coach = require('ge/extensions/raceCoach/coach')
local viz = require('ge/extensions/raceCoach/viz')

local state = {
  loaded = false,
  enabled = true,
  path = nil,
  speedProfile = nil,
  zones = nil,
  nearestIndex = 1,
  lastPlanRefresh = 0,
  planRefreshSeconds = 5.0
}

local function loadTrackModel()
  local cfgPath = 'settings/BeamNGRaceCoach/default_track.json'
  local cfg = jsonReadFile(cfgPath)
  if not cfg then
    cfgPath = 'mods/unpacked/BeamNGRaceCoach/settings/default_track.json'
    cfg = jsonReadFile(cfgPath)
  end
  if not cfg then
    log('E', 'BeamNGRaceCoach', 'Missing track model at ' .. cfgPath)
    return nil
  end

  local baseline = pathPlanner.buildBaselinePath(cfg.points or {})
  if #baseline < 10 then
    log('E', 'BeamNGRaceCoach', 'Baseline path is too short for coaching')
    return nil
  end

  local improvedPath = pathPlanner.improvePathMPCCStyle(baseline, cfg.mpcc or {})
  local speedProfile, zones = speedPlanner.buildSpeedAndZones(improvedPath, cfg.vehicle or {})

  return {
    cfg = cfg,
    baseline = baseline,
    improved = improvedPath,
    speedProfile = speedProfile,
    zones = zones
  }
end

local function pullVehicleState()
  local vehicle = be:getPlayerVehicle(0)
  if not vehicle then
    return nil
  end

  local vel = vehicle:getVelocity()
  local speedMps = vel:length()
  local pos = vehicle:getPosition()
  local dir = vehicle:getDirectionVector()

  return {
    vehicle = vehicle,
    speedMps = speedMps,
    speedKph = speedMps * 3.6,
    pos = pos,
    dir = dir
  }
end

local function planIfNeeded(simTime)
  if state.path and simTime - state.lastPlanRefresh < state.planRefreshSeconds then
    return
  end

  local model = loadTrackModel()
  if not model then
    return
  end

  state.path = model.improved
  state.speedProfile = model.speedProfile
  state.zones = model.zones
  state.lastPlanRefresh = simTime
  state.loaded = true
  coach.reset(model.improved, model.speedProfile, model.zones)

  log('I', 'BeamNGRaceCoach', string.format('Plan generated: %d path points', #state.path))
end

local function updateCoach(dtReal, simTime)
  if not state.enabled then
    return
  end

  planIfNeeded(simTime)
  if not state.loaded then
    return
  end

  local vehicleState = pullVehicleState()
  if not vehicleState then
    return
  end

  local guidance = coach.update(dtReal, vehicleState, state.path, state.speedProfile, state.zones)
  state.nearestIndex = guidance.nearestIndex or state.nearestIndex

  viz.drawPathAndZones(state.path, state.speedProfile, state.zones)
  viz.drawGuidance(guidance)
end

function M.onExtensionLoaded()
  state.loaded = false
  log('I', 'BeamNGRaceCoach', 'Extension loaded')
end

function M.onUpdate(dtReal, dtSim, dtRaw)
  local simTime = Engine and Engine.Sim and Engine.Sim.getSimulationTime() or 0
  updateCoach(dtReal, simTime)
end

function M.setEnabled(enabled)
  state.enabled = enabled and true or false
end

return M
