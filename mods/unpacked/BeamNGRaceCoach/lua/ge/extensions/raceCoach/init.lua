local M = {}

local pathPlanner = require('ge/extensions/raceCoach/pathPlanner')
local sourcePlanner = require('ge/extensions/raceCoach/sourcePlanner')
local speedPlanner = require('ge/extensions/raceCoach/speedPlanner')
local nativePlanner = require('ge/extensions/raceCoach/nativePlanner')
local coach = require('ge/extensions/raceCoach/coach')
local viz = require('ge/extensions/raceCoach/viz')

local MOD_NAME = 'BeamNGRaceCoach'

local state = {
  loaded = false,
  enabled = true,
  path = nil,
  speedProfile = nil,
  zones = nil,
  lastGuidance = nil,
  nearestIndex = 1,
  source = nil,
  sourceSignature = nil,
  plannerMode = 'lua',
  lastPlanRefresh = 0,
  planRefreshSeconds = 1.5
}

local function resetState()
  state.loaded = false
  state.path = nil
  state.speedProfile = nil
  state.zones = nil
  state.lastGuidance = nil
  state.nearestIndex = 1
  state.source = nil
  state.sourceSignature = nil
  state.plannerMode = 'lua'
  state.lastPlanRefresh = 0
end

local function matchesMod(modData)
  if not modData then
    return false
  end

  if modData.modname == MOD_NAME then
    return true
  end

  if modData.modData and modData.modData.name == MOD_NAME then
    return true
  end

  return false
end

local function loadConfig()
  local cfgPath = 'settings/BeamNGRaceCoach/default_track.json'
  local cfg = jsonReadFile(cfgPath)
  if not cfg then
    cfgPath = 'mods/unpacked/BeamNGRaceCoach/settings/default_track.json'
    cfg = jsonReadFile(cfgPath)
  end

  if not cfg then
    log('E', 'BeamNGRaceCoach', 'Missing configuration at ' .. cfgPath)
    return nil
  end

  return cfg
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

local function buildLuaPlan(source, cfg)
  local baseline = pathPlanner.buildBaselinePath(source.points or {}, source.pathOptions or {})
  if #baseline < 4 then
    log('E', 'BeamNGRaceCoach', 'Baseline path is too short for coaching')
    return nil
  end

  local improvedPath = pathPlanner.improvePathMPCCStyle(baseline, source.mpccConfig or cfg.mpcc or {})
  local speedProfile, zones = speedPlanner.buildSpeedAndZones(improvedPath, source.vehicleConfig or cfg.vehicle or {})

  return {
    cfg = cfg,
    source = source,
    baseline = baseline,
    improved = improvedPath,
    speedProfile = speedProfile,
    zones = zones,
    plannerMode = 'lua'
  }
end

local function planIfNeeded(simTime, vehicleState)
  if state.path and simTime - state.lastPlanRefresh < state.planRefreshSeconds then
    return
  end

  local cfg = loadConfig()
  if not cfg then
    state.loaded = false
    state.path = nil
    state.speedProfile = nil
    state.zones = nil
    state.source = nil
    state.sourceSignature = nil
    state.lastGuidance = nil
    coach.clearHud()
    return
  end

  local source = sourcePlanner.resolveSource(vehicleState, cfg)
  if not source then
    log('W', 'BeamNGRaceCoach', 'No track loop or destination route found')
    state.loaded = false
    state.path = nil
    state.speedProfile = nil
    state.zones = nil
    state.source = nil
    state.sourceSignature = nil
    state.lastGuidance = nil
    coach.clearHud()
    return
  end

  if state.loaded and state.path and state.sourceSignature == source.signature then
    state.lastPlanRefresh = simTime
    return
  end

  local model
  local nativeModel, nativeErr = nativePlanner.buildPlan(source, cfg)
  if nativeModel then
    model = {
      cfg = cfg,
      source = source,
      baseline = nil,
      improved = nativeModel.improved,
      speedProfile = nativeModel.speedProfile,
      zones = nativeModel.zones,
      plannerMode = nativeModel.plannerMode or 'native'
    }
  else
    if (cfg.native or {}).enabled then
      log('W', 'BeamNGRaceCoach', 'Native planner fallback: ' .. tostring(nativeErr))
    end
    model = buildLuaPlan(source, cfg)
  end

  if not model then
    state.loaded = false
    state.path = nil
    state.speedProfile = nil
    state.zones = nil
    state.source = nil
    state.sourceSignature = nil
    state.lastGuidance = nil
    coach.clearHud()
    return
  end

  state.path = model.improved
  state.speedProfile = model.speedProfile
  state.zones = model.zones
  state.source = model.source
  state.sourceSignature = model.source and model.source.signature or nil
  state.plannerMode = model.plannerMode or 'lua'
  state.lastPlanRefresh = simTime
  state.loaded = true
  coach.reset(model.improved, model.speedProfile, model.zones, model.source)

  log('I', 'BeamNGRaceCoach',
    string.format('Plan generated: %s (%s, %d points, %s planner)',
      model.source.label or 'Guidance',
      model.source.detail or model.source.sourceType or 'unknown',
      #state.path,
      state.plannerMode))
end

local function updateCoach(dtReal, simTime)
  if not state.enabled then
    coach.clearHud()
    return
  end

  local vehicleState = pullVehicleState()
  if not vehicleState then
    coach.clearHud()
    return
  end

  planIfNeeded(simTime, vehicleState)
  if not state.loaded then
    return
  end

  local guidance = coach.update(dtReal, vehicleState, state.path, state.speedProfile, state.zones)
  state.lastGuidance = guidance
  state.nearestIndex = guidance.nearestIndex or state.nearestIndex

  viz.drawPathAndZones(state.path, state.speedProfile, state.zones, guidance)
  viz.drawGuidance(guidance)
end

function M.onInit()
  setExtensionUnloadMode(M, 'manual')
end

function M.onExtensionLoaded()
  state.enabled = true
  resetState()
  coach.clearHud()
  log('I', 'BeamNGRaceCoach', 'Extension loaded')
end

function M.onExtensionUnloaded()
  resetState()
  coach.clearHud()
end

function M.onModActivated(modData)
  if not matchesMod(modData) then
    return
  end

  state.enabled = true
  M.reloadPlan()
  log('I', 'BeamNGRaceCoach', 'Mod activated, auto guidance enabled')
end

function M.onModDeactivated(modData)
  if not matchesMod(modData) then
    return
  end

  state.enabled = false
  resetState()
  coach.clearHud()
  log('I', 'BeamNGRaceCoach', 'Mod deactivated, guidance cleared')
end

function M.onUpdate(dtReal, dtSim, dtRaw)
  local simTime = Engine and Engine.Sim and Engine.Sim.getSimulationTime() or 0
  updateCoach(dtReal, simTime)
end

function M.setEnabled(enabled)
  state.enabled = enabled and true or false
  if not state.enabled then
    coach.clearHud()
  end
end

function M.reloadPlan()
  state.lastPlanRefresh = -math.huge
  state.loaded = false
  state.sourceSignature = nil
end

function M.getDebugState()
  return {
    loaded = state.loaded,
    enabled = state.enabled,
    level = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or nil,
    sourceType = state.source and state.source.sourceType or nil,
    sourceLabel = state.source and state.source.label or nil,
    sourceDetail = state.source and state.source.detail or nil,
    sourceSignature = state.sourceSignature,
    plannerMode = state.plannerMode,
    closed = state.path and state.path.closed or nil,
    pathPointCount = state.path and #state.path or 0,
    speedPointCount = state.speedProfile and #state.speedProfile or 0,
    zoneCount = state.zones and #state.zones or 0,
    totalLength = state.path and state.path.totalLength or 0,
    nearestIndex = state.nearestIndex,
    message = state.lastGuidance and state.lastGuidance.message or nil,
    zone = state.lastGuidance and state.lastGuidance.zone or nil,
    remainingDistance = state.lastGuidance and state.lastGuidance.remainingDistance or nil,
    contouringError = state.lastGuidance and state.lastGuidance.contouringError or nil,
    lagError = state.lastGuidance and state.lastGuidance.lagError or nil,
    headingError = state.lastGuidance and state.lastGuidance.headingError or nil,
    progressS = state.lastGuidance and state.lastGuidance.progressS or nil
  }
end

return M
