local M = {}

local function shallowCopy(tbl)
  local out = {}
  for k, v in pairs(tbl or {}) do
    out[k] = v
  end
  return out
end

local function countPairs(tbl)
  local count = 0
  for _ in pairs(tbl or {}) do
    count = count + 1
  end
  return count
end

local function parseBoolField(obj, key)
  local value = obj[key]
  if value ~= nil then
    return value and true or false
  end

  if obj.getField then
    local raw = obj:getField(key, 0)
    if raw ~= nil and raw ~= '' then
      return raw == '1' or raw == 'true'
    end
  end

  return false
end

local function pointFromPos(pos, halfWidth)
  return {
    x = pos.x,
    y = pos.y,
    z = pos.z,
    widthLeft = halfWidth,
    widthRight = halfWidth
  }
end

local function makeSignature(prefix, a, b, c)
  return string.format('%s:%s:%s:%s', prefix, tostring(a or ''), tostring(b or ''), tostring(c or ''))
end

local function makeEdgeKey(aId, bId)
  local a = tostring(aId)
  local b = tostring(bId)
  if a < b then
    return a .. '>' .. b
  end
  return b .. '>' .. a
end

local function roadContainsPoint(road, pos)
  local roadPos = road:getNodePosition(0)
  local probe = vec3(pos.x, pos.y, roadPos.z)
  local idx = road:containsPoint(probe)
  return idx ~= -1, idx
end

local function controlPointDistanceSq(road, pos)
  local nodeCount = road:getNodeCount() or 0
  if nodeCount < 2 then
    return math.huge
  end

  local best = math.huge
  local prev = vec3(road:getNodePosition(0))
  for i = 1, nodeCount - 1 do
    local curr = vec3(road:getNodePosition(i))
    best = math.min(best, pos:squaredDistanceToLineSegment(prev, curr))
    prev = curr
  end

  if parseBoolField(road, 'looped') and nodeCount > 2 then
    best = math.min(best, pos:squaredDistanceToLineSegment(prev, vec3(road:getNodePosition(0))))
  end

  return best
end

local function buildPointsFromRoadObject(road)
  local points = {}
  local nodeCount = road:getNodeCount() or 0
  for i = 0, nodeCount - 1 do
    local pos = road:getNodePosition(i)
    local halfWidth = math.max(2.5, (road:getNodeWidth(i) or 8) * 0.5)
    points[#points + 1] = pointFromPos(pos, halfWidth)
  end
  return points
end

local function findLoopedTrackRoad(vehicleState, autoCfg)
  local searchRadius = autoCfg.trackSearchRadius or 18
  local maxDistSq = searchRadius * searchRadius
  local minDrivability = autoCfg.trackMinDrivability or 0.75
  local best

  for _, roadName in ipairs(scenetree.findClassObjects('DecalRoad') or {}) do
    local road = scenetree.findObject(roadName)
    if road and (road.drivability or 0) >= minDrivability and (road:getNodeCount() or 0) >= 4 and parseBoolField(road, 'looped') then
      local inside = roadContainsPoint(road, vehicleState.pos)
      local distSq = inside and 0 or controlPointDistanceSq(road, vehicleState.pos)
      if distSq <= maxDistSq then
        local score = distSq - (road.drivability or 0) * 25
        if inside then
          score = score - 100
        end

        if not best or score < best.score then
          best = {
            road = road,
            roadName = roadName,
            score = score
          }
        end
      end
    end
  end

  if not best then
    return nil
  end

  return {
    sourceType = 'track',
    label = 'Track loop',
    detail = best.roadName,
    signature = makeSignature('track', best.roadName, best.road:getNodeCount(), best.road.drivability),
    closed = true,
    trackLike = true,
    points = buildPointsFromRoadObject(best.road)
  }
end

local function routeNodeHalfWidth(routeEntry, mapNodes, laneWidthCap)
  if routeEntry.wp and mapNodes and mapNodes[routeEntry.wp] and mapNodes[routeEntry.wp].radius then
    return math.min(mapNodes[routeEntry.wp].radius, laneWidthCap)
  end
  return laneWidthCap
end

local function buildDestinationRoute(vehicleState, autoCfg)
  if not core_groundMarkers or not core_groundMarkers.currentlyHasTarget or not core_groundMarkers.currentlyHasTarget() then
    return nil
  end

  local planner = core_groundMarkers.routePlanner
  if not planner then
    return nil
  end

  if vehicleState.vehicle then
    planner:trackVehicle(vehicleState.vehicle)
  else
    planner:trackPosition(vehicleState.pos)
  end

  if not planner.path or #planner.path < 2 then
    return nil
  end

  local laneWidthCap = autoCfg.routeHalfWidth or 2.4
  local mapData = map.getMap()
  local mapNodes = mapData and mapData.nodes or nil
  local points = {}

  for i = 1, #planner.path do
    local entry = planner.path[i]
    local halfWidth = routeNodeHalfWidth(entry, mapNodes, laneWidthCap)
    points[#points + 1] = pointFromPos(entry.pos, halfWidth)
  end

  local target = planner.path[#planner.path].pos
  return {
    sourceType = 'destination',
    label = 'Destination route',
    detail = 'Navigation target',
    signature = makeSignature('destination', math.floor(target.x), math.floor(target.y), math.floor(target.z)),
    closed = false,
    trackLike = false,
    points = points
  }
end

local function legalDirectionScore(edge, fromNode)
  if not edge.oneWay then
    return 0
  end
  return edge.inNode == fromNode and 0 or -5
end

local function chooseNextLoopNode(prevId, currId, startId, visited, mapNodes)
  local currNode = mapNodes[currId]
  local prevNode = mapNodes[prevId]
  if not currNode or not prevNode then
    return nil
  end

  local inDir = currNode.pos - prevNode.pos
  if inDir:length() < 1e-3 then
    inDir = vec3(1, 0, 0)
  else
    inDir:normalize()
  end

  local bestNeighbor
  local bestScore = -math.huge

  for neighborId, edge in pairs(currNode.links or {}) do
    if neighborId ~= prevId then
      local nextNode = mapNodes[neighborId]
      if nextNode then
        local outDir = nextNode.pos - currNode.pos
        local segLen = outDir:length()
        if segLen > 1.0 then
          outDir:normalize()

          local score = inDir:dot(outDir) * 4.0
          score = score + (edge.drivability or 1) * 2.5
          score = score + math.min(currNode.radius or 6, nextNode.radius or 6) * 0.08
          score = score + legalDirectionScore(edge, currId)

          local nextDegree = countPairs(nextNode.links)
          if nextDegree > 2 then
            score = score - (nextDegree - 2) * 0.75
          end

          if visited[currId .. '>' .. neighborId] then
            score = score - 100
          end

          if neighborId == startId then
            score = score + 10
          end

          if score > bestScore then
            bestScore = score
            bestNeighbor = neighborId
          end
        end
      end
    end
  end

  return bestNeighbor
end

local function measureLoop(pathIds, mapNodes)
  local totalLength = 0
  local drivabilitySum = 0
  local highDegreeCount = 0
  local edgeCount = 0

  for i = 1, #pathIds do
    local aId = pathIds[i]
    local bId = pathIds[(i % #pathIds) + 1]
    local a = mapNodes[aId]
    local b = mapNodes[bId]
    local edge = a and a.links and a.links[bId]
    if a and b and edge then
      totalLength = totalLength + (b.pos - a.pos):length()
      drivabilitySum = drivabilitySum + (edge.drivability or 1)
      edgeCount = edgeCount + 1
    end

    local degree = countPairs(a and a.links or nil)
    if degree > 2 then
      highDegreeCount = highDegreeCount + 1
    end
  end

  return {
    length = totalLength,
    avgDrivability = edgeCount > 0 and (drivabilitySum / edgeCount) or 0,
    highDegreeRatio = #pathIds > 0 and (highDegreeCount / #pathIds) or 1
  }
end

local function walkGraphLoop(startA, startB, mapNodes, autoCfg)
  local maxSteps = autoCfg.graphLoopMaxSteps or 400
  local minNodes = autoCfg.graphLoopMinNodes or 8
  local maxLength = autoCfg.graphLoopMaxLength or 15000

  local pathIds = { startA, startB }
  local visited = { [startA .. '>' .. startB] = true }
  local totalLength = (mapNodes[startB].pos - mapNodes[startA].pos):length()

  while #pathIds < maxSteps and totalLength < maxLength do
    local prevId = pathIds[#pathIds - 1]
    local currId = pathIds[#pathIds]
    local nextId = chooseNextLoopNode(prevId, currId, startA, visited, mapNodes)

    if not nextId then
      return nil
    end

    if nextId == startA then
      if #pathIds >= minNodes then
        return pathIds
      end
      return nil
    end

    visited[currId .. '>' .. nextId] = true
    totalLength = totalLength + (mapNodes[nextId].pos - mapNodes[currId].pos):length()
    pathIds[#pathIds + 1] = nextId
  end

  return nil
end

local function buildPointsFromNodeIds(nodeIds, mapNodes)
  local points = {}
  for i = 1, #nodeIds do
    local node = mapNodes[nodeIds[i]]
    if node then
      points[#points + 1] = pointFromPos(node.pos, math.max(2.5, node.radius or 6))
    end
  end
  return points
end

local function collectNearbyStartEdges(vehicleState, autoCfg, mapNodes)
  local searchRadius = autoCfg.graphLoopSearchRadius or 60
  local maxDistSq = searchRadius * searchRadius
  local minDrivability = autoCfg.trackMinDrivability or 0.75
  local maxCandidates = autoCfg.graphLoopMaxCandidates or 24
  local candidates = {}
  local seen = {}

  local dir = vec3(vehicleState.dir.x, vehicleState.dir.y, vehicleState.dir.z)
  if dir:length() < 1e-3 then
    dir = nil
  else
    dir:normalize()
  end

  for nodeId, node in pairs(mapNodes or {}) do
    if node and node.pos then
      for neighborId, edge in pairs(node.links or {}) do
        local other = mapNodes[neighborId]
        if other and other.pos then
          local key = makeEdgeKey(nodeId, neighborId)
          if not seen[key] and (edge.drivability or 0) >= minDrivability then
            seen[key] = true

            local distSq = vehicleState.pos:squaredDistanceToLineSegment(node.pos, other.pos)
            if distSq <= maxDistSq then
              local align = 0
              if dir then
                local edgeDir = other.pos - node.pos
                if edgeDir:length() >= 1e-3 then
                  edgeDir:normalize()
                  align = math.abs(dir:dot(edgeDir))
                end
              end

              candidates[#candidates + 1] = {
                a = nodeId,
                b = neighborId,
                distSq = distSq,
                align = align,
                drivability = edge.drivability or 0
              }
            end
          end
        end
      end
    end
  end

  table.sort(candidates, function(a, b)
    local aScore = a.distSq - a.align * 110 - a.drivability * 30
    local bScore = b.distSq - b.align * 110 - b.drivability * 30
    return aScore < bScore
  end)

  while #candidates > maxCandidates do
    table.remove(candidates)
  end

  return candidates
end

local function findGraphLoop(vehicleState, autoCfg)
  local mapData = map.getMap()
  if not mapData or not mapData.nodes then
    return nil
  end

  local mapNodes = mapData.nodes
  local startEdges = collectNearbyStartEdges(vehicleState, autoCfg, mapNodes)

  if #startEdges == 0 then
    local n1, n2 = map.findClosestRoad(vehicleState.pos, autoCfg.graphLoopSearchRadius or 60)
    if n1 and n2 and mapNodes[n1] and mapNodes[n2] then
      startEdges[1] = {
        a = n1,
        b = n2,
        distSq = 0,
        align = 0,
        drivability = ((mapNodes[n1].links or {})[n2] or {}).drivability or 0
      }
    end
  end

  if #startEdges == 0 then
    return nil
  end

  local best
  local minLength = autoCfg.graphLoopMinLength or 250
  local minDrivability = autoCfg.trackMinDrivability or 0.75
  local softMaxIntersectionRatio = autoCfg.graphLoopMaxIntersectionRatio or 0.45
  local hardMaxIntersectionRatio = autoCfg.graphLoopHardMaxIntersectionRatio or 0.75
  local preferredLength = autoCfg.graphLoopPreferredLength or 5000

  for _, startEdge in ipairs(startEdges) do
    local candidates = {
      walkGraphLoop(startEdge.a, startEdge.b, mapNodes, autoCfg),
      walkGraphLoop(startEdge.b, startEdge.a, mapNodes, autoCfg)
    }

    for _, nodeIds in ipairs(candidates) do
      if nodeIds and #nodeIds >= (autoCfg.graphLoopMinNodes or 8) then
        local metrics = measureLoop(nodeIds, mapNodes)
        if metrics.length >= minLength
          and metrics.avgDrivability >= (minDrivability * 0.9)
          and metrics.highDegreeRatio <= hardMaxIntersectionRatio then
          local lengthBonus = math.min(metrics.length, preferredLength) * 0.01
          local softIntersectionPenalty = math.max(0, metrics.highDegreeRatio - softMaxIntersectionRatio) * 220
          local score = metrics.avgDrivability * 120
            + lengthBonus
            + startEdge.align * 12
            - metrics.highDegreeRatio * 55
            - softIntersectionPenalty
            - math.sqrt(startEdge.distSq) * 0.35

          if not best or score > best.score then
            best = {
              nodeIds = nodeIds,
              score = score,
              metrics = metrics
            }
          end
        end
      end
    end
  end

  if not best then
    return nil
  end

  return {
    sourceType = 'track',
    label = 'Track loop',
    detail = 'Road graph loop',
    signature = makeSignature('graphLoop', best.nodeIds[1], best.nodeIds[2], #best.nodeIds),
    closed = true,
    trackLike = true,
    points = buildPointsFromNodeIds(best.nodeIds, mapNodes)
  }
end

local function defaultFallback(cfg)
  if not ((cfg.auto or {}).allowSampleFallback) then
    return nil
  end

  if cfg.points and #cfg.points >= 4 then
    return {
      sourceType = 'fallback',
      label = cfg.trackName or 'Fallback track',
      detail = 'Sample settings file',
      signature = makeSignature('fallback', cfg.trackName or 'sample', #cfg.points, 'json'),
      closed = true,
      trackLike = true,
      points = cfg.points
    }
  end
  return nil
end

local function buildMpccConfig(source, cfg)
  local autoCfg = cfg.auto or {}
  local mpccCfg = shallowCopy(cfg.mpcc or {})

  if source.sourceType == 'destination' then
    mpccCfg.maxTrackUsage = autoCfg.routeMaxTrackUsage or 0.35
    mpccCfg.preferredScale = autoCfg.routePreferredScale or 0.55
    mpccCfg.lookaheadPts = math.min(mpccCfg.lookaheadPts or 10, autoCfg.routeLookaheadPts or 8)
  else
    mpccCfg.maxTrackUsage = autoCfg.trackMaxTrackUsage or 0.92
    mpccCfg.preferredScale = autoCfg.trackPreferredScale or 1.0
  end

  return mpccCfg
end

local function buildPathOptions(source, cfg)
  local autoCfg = cfg.auto or {}
  return {
    closed = source.closed,
    resampleSpacing = autoCfg.resampleSpacing or (source.closed and 6 or 8)
  }
end

function M.resolveSource(vehicleState, cfg)
  local autoCfg = cfg.auto or {}

  local source = findLoopedTrackRoad(vehicleState, autoCfg)
    or buildDestinationRoute(vehicleState, autoCfg)
    or findGraphLoop(vehicleState, autoCfg)
    or defaultFallback(cfg)

  if not source then
    return nil
  end

  source.mpccConfig = buildMpccConfig(source, cfg)
  source.pathOptions = buildPathOptions(source, cfg)
  source.vehicleConfig = shallowCopy(cfg.vehicle or {})

  return source
end

return M
