local M = {}

local pathPlanner = require('ge/extensions/raceCoach/pathPlanner')

local function shallowCopy(tbl)
  local out = {}
  for k, v in pairs(tbl or {}) do
    out[k] = v
  end
  return out
end

local function copyPoints(points)
  local out = {}
  for i = 1, #(points or {}) do
    local p = points[i]
    out[i] = {
      x = p.x or (p.pos and p.pos.x) or 0,
      y = p.y or (p.pos and p.pos.y) or 0,
      z = p.z or (p.pos and p.pos.z) or 0,
      widthLeft = p.widthLeft or p.width or p.radius or 6,
      widthRight = p.widthRight or p.width or p.radius or 6
    }
  end
  return out
end

local function ensureSettingsDir()
  if FS and not FS:directoryExists('settings/BeamNGRaceCoach') then
    FS:directoryCreate('settings/BeamNGRaceCoach')
  end
end

local function defaultVirtualPath(cfg, key, fallback)
  local nativeCfg = cfg.native or {}
  local configured = nativeCfg[key]
  if configured and configured ~= '' then
    return configured
  end
  return fallback
end

local function resolveExecutableVirtualPath(cfg)
  local nativeCfg = cfg.native or {}
  local candidates = {
    nativeCfg.exePath,
    'mods/unpacked/BeamNGRaceCoach/bin/beamng_racecoach_native.exe',
    'settings/BeamNGRaceCoach/beamng_racecoach_native.exe'
  }

  for _, candidate in ipairs(candidates) do
    if candidate and candidate ~= '' and FS and FS:fileExists(candidate) then
      return candidate
    end
  end
end

local function quoteShell(path)
  return '"' .. tostring(path or '') .. '"'
end

local function toNativePath(virtualPath)
  if FS:fileExists(virtualPath) then
    return FS:getFileRealPath(virtualPath)
  end

  local userPath = FS:getUserPath() or ''
  local normalized = tostring(virtualPath or ''):gsub('^[/\\]+', ''):gsub('/', '\\')
  return userPath .. normalized
end

local function runNativeExecutable(exePath, requestPath, responsePath)
  if not os or not os.execute then
    return false, 'os.execute is unavailable in this BeamNG runtime'
  end

  local command = string.format('%s %s %s',
    quoteShell(exePath),
    quoteShell(requestPath),
    quoteShell(responsePath))

  local ok = os.execute(command)
  if ok == true or ok == 0 then
    return true
  end

  return false, tostring(ok)
end

local function buildRequest(source, cfg)
  return {
    sourceType = source.sourceType,
    label = source.label,
    detail = source.detail,
    closed = source.closed and true or false,
    points = copyPoints(source.points or {}),
    pathOptions = shallowCopy(source.pathOptions or {}),
    mpcc = shallowCopy(source.mpccConfig or cfg.mpcc or {}),
    vehicle = shallowCopy(source.vehicleConfig or cfg.vehicle or {})
  }
end

function M.buildPlan(source, cfg)
  local nativeCfg = cfg.native or {}
  if not nativeCfg.enabled then
    return nil, 'native planner disabled'
  end

  if not FS or not FS:getFileRealPath then
    return nil, 'BeamNG FS real-path helpers are unavailable'
  end

  ensureSettingsDir()

  local exeVirtual = resolveExecutableVirtualPath(cfg)
  if not exeVirtual then
    return nil, 'native executable not found'
  end

  local requestVirtual = defaultVirtualPath(cfg, 'requestPath', 'settings/BeamNGRaceCoach/native_request.json')
  local responseVirtual = defaultVirtualPath(cfg, 'responsePath', 'settings/BeamNGRaceCoach/native_response.json')

  local request = buildRequest(source, cfg)
  jsonWriteFile(requestVirtual, request, true)

  if FS:fileExists(responseVirtual) then
    FS:removeFile(responseVirtual)
  end

  local ok, err = runNativeExecutable(
    toNativePath(exeVirtual),
    toNativePath(requestVirtual),
    toNativePath(responseVirtual)
  )
  if not ok then
    return nil, 'native executable failed: ' .. tostring(err)
  end

  local response = jsonReadFile(responseVirtual)
  if not response then
    return nil, 'native executable did not produce a response'
  end

  if not response.ok then
    return nil, response.error or 'native executable returned an error'
  end

  local points = response.points or {}
  if #points < 4 then
    return nil, 'native executable returned too few points'
  end

  local improvedPath = pathPlanner.hydratePath(points, {
    closed = response.closed and true or false
  })

  if #improvedPath < 4 then
    return nil, 'native path hydration failed'
  end

  local speedProfile = response.speedProfile or {}
  local zones = response.zones or {}
  if #speedProfile ~= #improvedPath or #zones ~= #improvedPath then
    return nil, 'native response shape mismatch'
  end

  return {
    improved = improvedPath,
    speedProfile = speedProfile,
    zones = zones,
    plannerMode = 'native'
  }
end

return M
