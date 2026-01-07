--!strict
--[[
	Navigation - Tactical pathfinding and positioning system

	Provides smart navigation for NPCs including:
	- A* pathfinding with obstacle avoidance
	- Cover point evaluation and selection
	- Tactical positioning (flanking, high ground, chokepoints)
	- Flee path calculation

	Integrates with Perception, Memory, and Blackboard systems.

	@class Navigation
]]

local NavigationGrid = require(script.Parent.NavigationGrid)
local Utilities = require(script.Parent.Parent.Utilities)

local Navigation = {}
Navigation.__index = Navigation

-- ============================================================================
-- TYPES
-- ============================================================================

export type PathResult = {
	waypoints: { Vector3 },
	totalDistance: number,
	estimatedTime: number,
	pathFound: boolean,
	iterations: number,
}

export type CoverPoint = {
	position: Vector3,
	quality: number,
	exposedDirections: { Vector3 },
	height: number,
	retreatRoutes: number,
}

export type TacticalPosition = {
	position: Vector3,
	type: "flank" | "highGround" | "chokepoint" | "ambush",
	advantage: number,
	approachPath: { Vector3 }?,
	description: string,
}

export type NavigationConfig = {
	-- Grid settings
	gridSize: number?,
	heightTolerance: number?,
	maxSlope: number?,

	-- Pathfinding settings
	maxIterations: number?,
	maxPathLength: number?,
	replanThreshold: number?,
	moveSpeed: number?,

	-- Cover settings
	minCoverHeight: number?,
	maxCoverDistance: number?,
	preferredCoverDistance: number?,

	-- Tactical settings
	flankAngle: number?,
	highGroundMinHeight: number?,
	chokeWidth: number?,

	-- Custom functions
	obstructionCheck: ((Vector3, Vector3) -> boolean)?,
	heightSampler: ((Vector3) -> number)?,
	walkableCheck: ((Vector3) -> boolean)?,
}

export type AvoidanceZone = {
	position: Vector3,
	radius: number,
	cost: number,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DEFAULT_MAX_ITERATIONS = 500
local DEFAULT_MAX_PATH_LENGTH = 100
local DEFAULT_REPLAN_THRESHOLD = 5
local DEFAULT_MOVE_SPEED = 16
local DEFAULT_MIN_COVER_HEIGHT = 3
local DEFAULT_MAX_COVER_DISTANCE = 50
local DEFAULT_PREFERRED_COVER_DISTANCE = 15
local DEFAULT_FLANK_ANGLE = 60
local DEFAULT_HIGH_GROUND_MIN_HEIGHT = 3
local DEFAULT_CHOKE_WIDTH = 8

-- LOG_PREFIX reserved for future error messages

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

--[=[
	Creates a new Navigation system.

	@param config NavigationConfig? -- Optional configuration
	@return Navigation

	@example
	```lua
	local nav = Navigation.new({
		gridSize = 4,
		maxIterations = 1000,
		moveSpeed = 16,
	})
	```
]=]
function Navigation.new(config: NavigationConfig?): Navigation
	local cfg = config or {}

	local self = setmetatable({}, Navigation)

	-- Create navigation grid
	self._grid = NavigationGrid.new({
		cellSize = cfg.gridSize,
		heightTolerance = cfg.heightTolerance,
		maxSlope = cfg.maxSlope,
		obstructionCheck = cfg.obstructionCheck,
		heightSampler = cfg.heightSampler,
		walkableCheck = cfg.walkableCheck,
	})

	-- Pathfinding settings
	self._maxIterations = cfg.maxIterations or DEFAULT_MAX_ITERATIONS
	self._maxPathLength = cfg.maxPathLength or DEFAULT_MAX_PATH_LENGTH
	self._replanThreshold = cfg.replanThreshold or DEFAULT_REPLAN_THRESHOLD
	self._moveSpeed = cfg.moveSpeed or DEFAULT_MOVE_SPEED

	-- Cover settings
	self._minCoverHeight = cfg.minCoverHeight or DEFAULT_MIN_COVER_HEIGHT
	self._maxCoverDistance = cfg.maxCoverDistance or DEFAULT_MAX_COVER_DISTANCE
	self._preferredCoverDistance = cfg.preferredCoverDistance or DEFAULT_PREFERRED_COVER_DISTANCE

	-- Tactical settings
	self._flankAngle = cfg.flankAngle or DEFAULT_FLANK_ANGLE
	self._highGroundMinHeight = cfg.highGroundMinHeight or DEFAULT_HIGH_GROUND_MIN_HEIGHT
	self._chokeWidth = cfg.chokeWidth or DEFAULT_CHOKE_WIDTH

	-- Current path state
	self._currentPath = nil :: PathResult?
	self._currentWaypointIndex = 1
	self._pathStartTime = 0

	-- Avoidance zones (threats, danger areas)
	self._avoidanceZones = {} :: { AvoidanceZone }

	-- Integration references
	self._blackboard = nil
	self._perception = nil
	self._memory = nil
	self._ownerId = nil :: string?

	-- Statistics
	self._totalPathsComputed = 0
	self._totalPathsFailed = 0
	self._lastPathTime = 0

	-- Path caching
	self._pathCache = {} :: { [string]: PathResult }
	self._pathCacheTimestamps = {} :: { [string]: number }
	self._pathCacheTTL = 1.0 -- Cache paths for 1 second
	self._pathCacheMaxSize = 50 -- Max cached paths
	self._pathCacheCount = 0
	self._pathCacheHits = 0
	self._pathCacheMisses = 0

	return self
end

--// ============================================================================
--// PATH CACHING
--// ============================================================================

--[=[
	Generates a cache key for a path query.
]=]
function Navigation:_getPathCacheKey(start: Vector3, goal: Vector3): string
	-- Round to cell size for cache coherence
	local cellSize = self._grid:getCellSize()
	local sx = math.floor(start.X / cellSize)
	local sz = math.floor(start.Z / cellSize)
	local gx = math.floor(goal.X / cellSize)
	local gz = math.floor(goal.Z / cellSize)
	return `{sx},{sz}->{gx},{gz}`
end

--[=[
	Gets a cached path if valid.
]=]
function Navigation:_getCachedPath(key: string): PathResult?
	local cached = self._pathCache[key]
	if not cached then
		return nil
	end

	local timestamp = self._pathCacheTimestamps[key]
	if not timestamp or (os.clock() - timestamp) > self._pathCacheTTL then
		-- Cache expired
		self._pathCache[key] = nil
		self._pathCacheTimestamps[key] = nil
		return nil
	end

	self._pathCacheHits += 1
	return cached
end

--[=[
	Caches a path result.
]=]
function Navigation:_cachePath(key: string, result: PathResult)
	-- Simple cache size tracking - clear when full
	self._pathCacheCount = (self._pathCacheCount or 0) + 1
	if self._pathCacheCount > self._pathCacheMaxSize then
		table.clear(self._pathCache)
		table.clear(self._pathCacheTimestamps)
		self._pathCacheCount = 1
	end

	self._pathCache[key] = result
	self._pathCacheTimestamps[key] = os.clock()
	self._pathCacheMisses += 1
end

--[=[
	Clears the path cache.
]=]
function Navigation:clearPathCache()
	table.clear(self._pathCache)
	table.clear(self._pathCacheTimestamps)
	self._pathCacheCount = 0
end

--[=[
	Sets the path cache TTL.

	@param ttl number -- Time to live in seconds
]=]
function Navigation:setPathCacheTTL(ttl: number)
	self._pathCacheTTL = math.max(0, ttl)
end

-- ============================================================================
-- A* PATHFINDING
-- ============================================================================

--[=[
	Finds a path from start to goal using A* algorithm.

	@param start Vector3 -- Starting position
	@param goal Vector3 -- Goal position
	@param options { avoidThreats: boolean?, useCache: boolean? }? -- Optional pathfinding options
	@return PathResult

	@example
	```lua
	local path = nav:findPath(myPosition, targetPosition)
	if path.pathFound then
		for _, waypoint in path.waypoints do
			-- Move to waypoint
		end
	end
	```
]=]
function Navigation:findPath(
	start: Vector3,
	goal: Vector3,
	options: { avoidThreats: boolean?, useCache: boolean? }?
): PathResult
	local startTime = os.clock()
	local opts = options or {}
	local useCache = opts.useCache ~= false -- Default to true

	-- Check path cache first (only for non-threat-avoidance paths)
	if useCache and not opts.avoidThreats then
		local cacheKey = self:_getPathCacheKey(start, goal)
		local cachedPath = self:_getCachedPath(cacheKey)
		if cachedPath then
			return cachedPath
		end
	end

	local startCell = self._grid:getCellAtPosition(start)
	local goalCell = self._grid:getCellAtPosition(goal)

	-- Check if goal is walkable
	if not goalCell.walkable then
		self._totalPathsFailed += 1
		return {
			waypoints = {},
			totalDistance = 0,
			estimatedTime = 0,
			pathFound = false,
			iterations = 0,
		}
	end

	-- A* algorithm
	local openSet = Utilities.PriorityQueue.new()
	local cameFrom = {} :: { [string]: typeof(startCell) }
	local gScore = {} :: { [string]: number }
	local fScore = {} :: { [string]: number }

	local startKey = self:_cellKey(startCell)
	gScore[startKey] = 0
	fScore[startKey] = self._grid:octileDistance(startCell, goalCell)

	openSet:push(startCell, fScore[startKey])

	local closedSet = {} :: { [string]: boolean }
	local iterations = 0

	while not openSet:isEmpty() and iterations < self._maxIterations do
		iterations += 1

		local current = openSet:pop()
		local currentKey = self:_cellKey(current)

		-- Check if we reached the goal
		if current.x == goalCell.x and current.z == goalCell.z then
			local path = self:_reconstructPath(cameFrom, current, start, goal)
			self._totalPathsComputed += 1
			self._lastPathTime = os.clock() - startTime
			-- Cache successful path
			if useCache and not opts.avoidThreats then
				local cacheKey = self:_getPathCacheKey(start, goal)
				self:_cachePath(cacheKey, path)
			end
			return path
		end

		closedSet[currentKey] = true

		-- Process neighbors
		local neighbors = self._grid:getNeighbors(current)

		for _, neighborData in neighbors do
			local neighbor = neighborData.cell
			local neighborKey = self:_cellKey(neighbor)

			if closedSet[neighborKey] then
				continue
			end

			-- Calculate cost with avoidance zones
			local moveCost = neighborData.cost

			if opts.avoidThreats then
				moveCost = moveCost + self:_getAvoidanceCost(neighbor.worldPosition)
			end

			local tentativeGScore = (gScore[currentKey] or math.huge) + moveCost

			if tentativeGScore < (gScore[neighborKey] or math.huge) then
				cameFrom[neighborKey] = current
				gScore[neighborKey] = tentativeGScore
				fScore[neighborKey] = tentativeGScore + self._grid:octileDistance(neighbor, goalCell)

				-- Add to open set (priority queue handles duplicates by priority)
				openSet:push(neighbor, fScore[neighborKey])
			end
		end
	end

	-- No path found
	self._totalPathsFailed += 1
	self._lastPathTime = os.clock() - startTime

	return {
		waypoints = {},
		totalDistance = 0,
		estimatedTime = 0,
		pathFound = false,
		iterations = iterations,
	}
end

--[=[
	Gets cell key for hash tables.
]=]
function Navigation:_cellKey(cell: NavigationGrid.GridCell): string
	return `{cell.x},{cell.z}`
end

--[=[
	Reconstructs path from A* result.
]=]
function Navigation:_reconstructPath(
	cameFrom: { [string]: NavigationGrid.GridCell },
	current: NavigationGrid.GridCell,
	start: Vector3,
	goal: Vector3
): PathResult
	local waypoints = { goal }
	local totalDistance = 0

	local key = self:_cellKey(current)
	while cameFrom[key] do
		local prev = cameFrom[key]
		table.insert(waypoints, 1, current.worldPosition)
		totalDistance += (current.worldPosition - prev.worldPosition).Magnitude
		current = prev
		key = self:_cellKey(current)
	end

	-- Add start position
	if #waypoints > 0 then
		totalDistance += (waypoints[1] - start).Magnitude
	end
	table.insert(waypoints, 1, start)

	-- Smooth path by removing unnecessary waypoints
	waypoints = self:_smoothPath(waypoints)

	local estimatedTime = totalDistance / self._moveSpeed

	return {
		waypoints = waypoints,
		totalDistance = totalDistance,
		estimatedTime = estimatedTime,
		pathFound = true,
		iterations = 0,
	}
end

--[=[
	Smooths a path by removing redundant waypoints.
]=]
function Navigation:_smoothPath(waypoints: { Vector3 }): { Vector3 }
	if #waypoints <= 2 then
		return waypoints
	end

	local smoothed = { waypoints[1] }
	local current = 1

	while current < #waypoints do
		local farthest = current + 1

		-- Find the farthest visible waypoint
		for i = current + 2, #waypoints do
			if self._grid:hasLineOfSight(waypoints[current], waypoints[i]) then
				farthest = i
			else
				break
			end
		end

		table.insert(smoothed, waypoints[farthest])
		current = farthest
	end

	return smoothed
end

--[=[
	Calculates avoidance cost for a position.
]=]
function Navigation:_getAvoidanceCost(position: Vector3): number
	local totalCost = 0

	for _, zone in self._avoidanceZones do
		local distance = (position - zone.position).Magnitude
		if distance < zone.radius then
			local factor = 1 - (distance / zone.radius)
			totalCost += zone.cost * factor
		end
	end

	return totalCost
end

-- ============================================================================
-- PATH FOLLOWING
-- ============================================================================

--[=[
	Sets the current path to follow.

	@param path PathResult -- The path to follow
]=]
function Navigation:setPath(path: PathResult): ()
	self._currentPath = path
	self._currentWaypointIndex = 1
	self._pathStartTime = os.clock()
end

--[=[
	Gets the next waypoint in the current path.

	@return Vector3? -- Next waypoint, or nil if no path or path complete
]=]
function Navigation:getNextWaypoint(): Vector3?
	if not self._currentPath or not self._currentPath.pathFound then
		return nil
	end

	if self._currentWaypointIndex > #self._currentPath.waypoints then
		return nil
	end

	return self._currentPath.waypoints[self._currentWaypointIndex]
end

--[=[
	Advances to the next waypoint.

	@param currentPosition Vector3 -- Current NPC position
	@param acceptanceRadius number? -- Distance to consider waypoint reached (default: 2)
	@return boolean -- True if path is complete
]=]
function Navigation:advanceWaypoint(currentPosition: Vector3, acceptanceRadius: number?): boolean
	local radius = acceptanceRadius or 2

	local nextWaypoint = self:getNextWaypoint()
	if not nextWaypoint then
		return true
	end

	local distance = (currentPosition - nextWaypoint).Magnitude
	if distance <= radius then
		self._currentWaypointIndex += 1
	end

	return self._currentWaypointIndex > #self._currentPath.waypoints
end

--[=[
	Gets the current path.

	@return PathResult?
]=]
function Navigation:getCurrentPath(): PathResult?
	return self._currentPath
end

--[=[
	Cancels the current path.
]=]
function Navigation:cancelPath(): ()
	self._currentPath = nil
	self._currentWaypointIndex = 1
end

--[=[
	Checks if we need to replan based on obstacle changes.

	@param currentPosition Vector3 -- Current position
	@return boolean -- True if replanning is recommended
]=]
function Navigation:shouldReplan(currentPosition: Vector3): boolean
	if not self._currentPath or not self._currentPath.pathFound then
		return false
	end

	local nextWaypoint = self:getNextWaypoint()
	if not nextWaypoint then
		return false
	end

	-- Check if path to next waypoint is blocked
	if not self._grid:hasLineOfSight(currentPosition, nextWaypoint) then
		return true
	end

	return false
end

-- ============================================================================
-- COVER SYSTEM
-- ============================================================================

--[=[
	Finds the best cover position from threats.

	@param position Vector3 -- Current position
	@param threats { Vector3 } -- Array of threat positions
	@param searchRadius number? -- Search radius (default: maxCoverDistance)
	@return CoverPoint? -- Best cover point, or nil if none found

	@example
	```lua
	local threats = { enemy1.Position, enemy2.Position }
	local cover = nav:findBestCover(myPosition, threats)
	if cover then
		-- Move to cover.position
	end
	```
]=]
function Navigation:findBestCover(position: Vector3, threats: { Vector3 }, searchRadius: number?): CoverPoint?
	local radius = searchRadius or self._maxCoverDistance
	local coverPoints = self:scanCoverPoints(position, radius, threats)

	if #coverPoints == 0 then
		return nil
	end

	-- Sort by quality (highest first)
	table.sort(coverPoints, function(a, b)
		return a.quality > b.quality
	end)

	return coverPoints[1]
end

--[=[
	Finds cover from a single threat.

	@param position Vector3 -- Current position
	@param threatPosition Vector3 -- Threat position
	@param searchRadius number? -- Search radius
	@return CoverPoint?
]=]
function Navigation:findCover(position: Vector3, threatPosition: Vector3, searchRadius: number?): CoverPoint?
	return self:findBestCover(position, { threatPosition }, searchRadius)
end

--[=[
	Scans for all cover points in an area.

	@param center Vector3 -- Center of search area
	@param radius number -- Search radius
	@param threats { Vector3 }? -- Optional threat positions for scoring
	@return { CoverPoint }

	@example
	```lua
	local allCover = nav:scanCoverPoints(myPosition, 30, { enemyPosition })
	for _, cover in allCover do
		print("Cover at", cover.position, "quality:", cover.quality)
	end
	```
]=]
function Navigation:scanCoverPoints(center: Vector3, radius: number, threats: { Vector3 }?): { CoverPoint }
	local coverPoints: { CoverPoint } = {}
	local threatList = threats or {}

	local cellRadius = math.ceil(radius / self._grid:getCellSize())
	local cx, _, cz = self._grid:worldToGrid(center)

	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local dist = math.sqrt(dx * dx + dz * dz) * self._grid:getCellSize()
			if dist <= radius then
				local cell = self._grid:getCell(cx + dx, 0, cz + dz)

				if cell.walkable then
					local coverHeight = self:_measureCoverHeight(cell.worldPosition, threatList)

					if coverHeight >= self._minCoverHeight then
						local quality = self:evaluateCoverQuality(cell.worldPosition, threatList)
						local exposedDirs = self:_getExposedDirections(cell.worldPosition, threatList)
						local retreatRoutes = self:_countRetreatRoutes(cell.worldPosition, threatList)

						table.insert(coverPoints, {
							position = cell.worldPosition,
							quality = quality,
							exposedDirections = exposedDirs,
							height = coverHeight,
							retreatRoutes = retreatRoutes,
						})
					end
				end
			end
		end
	end

	return coverPoints
end

--[=[
	Evaluates the quality of a cover position.

	@param coverPos Vector3 -- Cover position to evaluate
	@param threats { Vector3 } -- Threat positions
	@return number -- Quality score (0-1, higher is better)

	@example
	```lua
	local quality = nav:evaluateCoverQuality(potentialCover, threats)
	if quality > 0.7 then
		print("Good cover!")
	end
	```
]=]
function Navigation:evaluateCoverQuality(coverPos: Vector3, threats: { Vector3 }): number
	if #threats == 0 then
		return 0.5
	end

	-- Factor 1: Protection from threats (0-1)
	local protection = self:_calculateProtection(coverPos, threats)

	-- Factor 2: Distance score (prefer preferred distance)
	local avgDistance = 0
	for _, threat in threats do
		avgDistance += (coverPos - threat).Magnitude
	end
	avgDistance /= #threats

	local distanceScore
	if avgDistance < self._preferredCoverDistance then
		distanceScore = avgDistance / self._preferredCoverDistance
	else
		distanceScore = math.max(0, 1 - (avgDistance - self._preferredCoverDistance) / self._maxCoverDistance)
	end

	-- Factor 3: Retreat options
	local retreatRoutes = self:_countRetreatRoutes(coverPos, threats)
	local retreatScore = math.min(retreatRoutes / 3, 1)

	-- Weighted combination
	local quality = protection * 0.5 + distanceScore * 0.3 + retreatScore * 0.2

	return math.clamp(quality, 0, 1)
end

--[=[
	Measures cover height at a position relative to threats.
]=]
function Navigation:_measureCoverHeight(position: Vector3, threats: { Vector3 }): number
	if #threats == 0 then
		return self:_measureCoverHeightGeneral(position)
	end

	local minHeight = math.huge

	for _, threat in threats do
		local direction = (threat - position).Unit

		-- Raycast to find cover
		local rayOrigin = position + Vector3.new(0, 0.5, 0)
		local rayDirection = direction * 3

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {}

		local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

		if result then
			-- Found cover, measure height
			local coverPart = result.Instance
			if coverPart:IsA("BasePart") then
				local height = coverPart.Size.Y
				minHeight = math.min(minHeight, height)
			end
		else
			minHeight = 0
			break
		end
	end

	return minHeight == math.huge and 0 or minHeight
end

--[=[
	Measures general cover height (not threat-specific).
]=]
function Navigation:_measureCoverHeightGeneral(position: Vector3): number
	local maxHeight = 0

	-- Check 8 directions
	for angle = 0, 315, 45 do
		local rad = math.rad(angle)
		local direction = Vector3.new(math.cos(rad), 0, math.sin(rad))

		local rayOrigin = position + Vector3.new(0, 0.5, 0)
		local rayDirection = direction * 3

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {}

		local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

		if result then
			local coverPart = result.Instance
			if coverPart:IsA("BasePart") then
				maxHeight = math.max(maxHeight, coverPart.Size.Y)
			end
		end
	end

	return maxHeight
end

--[=[
	Calculates protection percentage from threats.
]=]
function Navigation:_calculateProtection(coverPos: Vector3, threats: { Vector3 }): number
	if #threats == 0 then
		return 0.5
	end

	local blocked = 0

	for _, threat in threats do
		if not self._grid:hasLineOfSight(coverPos + Vector3.new(0, 1.5, 0), threat + Vector3.new(0, 1.5, 0)) then
			blocked += 1
		end
	end

	return blocked / #threats
end

--[=[
	Gets directions exposed to threats.
]=]
function Navigation:_getExposedDirections(coverPos: Vector3, threats: { Vector3 }): { Vector3 }
	local exposed = {}

	for _, threat in threats do
		local eyeLevel = coverPos + Vector3.new(0, 1.5, 0)
		local threatEye = threat + Vector3.new(0, 1.5, 0)

		if self._grid:hasLineOfSight(eyeLevel, threatEye) then
			table.insert(exposed, (threat - coverPos).Unit)
		end
	end

	return exposed
end

--[=[
	Counts available retreat routes away from threats.
]=]
function Navigation:_countRetreatRoutes(coverPos: Vector3, threats: { Vector3 }): number
	local count = 0
	local threatCenter = Vector3.zero

	if #threats > 0 then
		for _, threat in threats do
			threatCenter += threat
		end
		threatCenter /= #threats
	end

	-- Check 8 directions
	for angle = 0, 315, 45 do
		local rad = math.rad(angle)
		local direction = Vector3.new(math.cos(rad), 0, math.sin(rad))
		local checkPos = coverPos + direction * 10

		-- Is this direction away from threats?
		local isAwayFromThreats = true
		if #threats > 0 then
			local dotProduct = direction:Dot((threatCenter - coverPos).Unit)
			isAwayFromThreats = dotProduct < 0.3
		end

		if isAwayFromThreats then
			local cell = self._grid:getCellAtPosition(checkPos)
			if cell.walkable and self._grid:hasLineOfSight(coverPos, checkPos) then
				count += 1
			end
		end
	end

	return count
end

-- ============================================================================
-- TACTICAL POSITIONS
-- ============================================================================

--[=[
	Finds a flanking route to approach a target from the side or rear.

	@param myPos Vector3 -- Current position
	@param targetPos Vector3 -- Target position
	@param targetFacing Vector3? -- Direction target is facing (optional)
	@return PathResult? -- Path to flanking position

	@example
	```lua
	local flankPath = nav:findFlankingRoute(myPosition, enemyPosition, enemyFacing)
	if flankPath and flankPath.pathFound then
		nav:setPath(flankPath)
	end
	```
]=]
function Navigation:findFlankingRoute(myPos: Vector3, targetPos: Vector3, targetFacing: Vector3?): PathResult?
	local facing = targetFacing or (myPos - targetPos).Unit
	local flankPositions = self:getFlankPositions(targetPos, 15, facing)

	if #flankPositions == 0 then
		return nil
	end

	-- Sort by advantage
	table.sort(flankPositions, function(a, b)
		return a.advantage > b.advantage
	end)

	-- Find path to best flanking position
	for _, flankPos in flankPositions do
		local path = self:findPath(myPos, flankPos.position, { avoidThreats = true })
		if path.pathFound then
			return path
		end
	end

	return nil
end

--[=[
	Gets potential flanking positions around a target.

	@param targetPos Vector3 -- Target position
	@param radius number -- Distance from target
	@param targetFacing Vector3? -- Direction target is facing
	@return { TacticalPosition }

	@example
	```lua
	local flanks = nav:getFlankPositions(enemyPosition, 20, enemyFacing)
	for _, pos in flanks do
		print(pos.type, pos.advantage)
	end
	```
]=]
function Navigation:getFlankPositions(targetPos: Vector3, radius: number, targetFacing: Vector3?): { TacticalPosition }
	local positions: { TacticalPosition } = {}
	local facing = targetFacing or Vector3.new(0, 0, 1)

	-- Generate positions in a circle
	for angle = 0, 350, 30 do
		local rad = math.rad(angle)
		local direction = Vector3.new(math.cos(rad), 0, math.sin(rad))
		local candidatePos = targetPos + direction * radius

		local cell = self._grid:getCellAtPosition(candidatePos)
		if cell.walkable then
			-- Calculate angle from target's facing
			local toCandidate = (candidatePos - targetPos).Unit
			local facingDot = facing:Dot(toCandidate)

			-- facingDot: 1 = directly in front, -1 = directly behind, 0 = side
			local isFlank = math.abs(facingDot) < 0.5
			local isRear = facingDot < -0.5

			if isFlank or isRear then
				local advantage
				local description

				if isRear then
					advantage = 0.9
					description = "Rear approach"
				else
					advantage = 0.7 - math.abs(facingDot) * 0.3
					description = "Flank approach"
				end

				-- Check if position has cover
				if self:_measureCoverHeightGeneral(candidatePos) >= self._minCoverHeight then
					advantage += 0.1
				end

				table.insert(positions, {
					position = cell.worldPosition,
					type = "flank",
					advantage = advantage,
					approachPath = nil,
					description = description,
				})
			end
		end
	end

	return positions
end

--[=[
	Finds high ground positions in an area.

	@param center Vector3 -- Center of search area
	@param radius number -- Search radius
	@return TacticalPosition? -- Best high ground position

	@example
	```lua
	local highGround = nav:findHighGround(myPosition, 30)
	if highGround then
		print("High ground advantage:", highGround.advantage)
	end
	```
]=]
function Navigation:findHighGround(center: Vector3, radius: number): TacticalPosition?
	local positions = self:scanHighGroundPositions(center, radius)

	if #positions == 0 then
		return nil
	end

	table.sort(positions, function(a, b)
		return a.advantage > b.advantage
	end)

	return positions[1]
end

--[=[
	Scans for all high ground positions in an area.

	@param center Vector3 -- Center of search
	@param radius number -- Search radius
	@return { TacticalPosition }
]=]
function Navigation:scanHighGroundPositions(center: Vector3, radius: number): { TacticalPosition }
	local positions: { TacticalPosition } = {}
	local baseHeight = center.Y

	local cellRadius = math.ceil(radius / self._grid:getCellSize())
	local cx, _, cz = self._grid:worldToGrid(center)

	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local dist = math.sqrt(dx * dx + dz * dz) * self._grid:getCellSize()
			if dist <= radius then
				local cell = self._grid:getCell(cx + dx, 0, cz + dz)

				if cell.walkable then
					local heightAdvantage = cell.height - baseHeight

					if heightAdvantage >= self._highGroundMinHeight then
						local advantage = math.clamp(heightAdvantage / 10, 0, 1)

						-- Bonus for visibility
						local visibilityBonus = self:_calculateVisibility(cell.worldPosition, radius) * 0.2
						advantage = math.min(advantage + visibilityBonus, 1)

						table.insert(positions, {
							position = cell.worldPosition,
							type = "highGround",
							advantage = advantage,
							approachPath = nil,
							description = `{string.format("%.1f", heightAdvantage)} studs elevation`,
						})
					end
				end
			end
		end
	end

	return positions
end

--[=[
	Evaluates height advantage over a target.

	@param position Vector3 -- Your position
	@param targetPos Vector3 -- Target position
	@return number -- Height advantage (0-1)
]=]
function Navigation:evaluateHeightAdvantage(position: Vector3, targetPos: Vector3): number
	local heightDiff = position.Y - targetPos.Y

	if heightDiff <= 0 then
		return 0
	end

	return math.clamp(heightDiff / 10, 0, 1)
end

--[=[
	Calculates visibility from a position.
]=]
function Navigation:_calculateVisibility(position: Vector3, radius: number): number
	local visibleCount = 0
	local totalChecks = 0

	for angle = 0, 350, 30 do
		for dist = 10, radius, 10 do
			local rad = math.rad(angle)
			local direction = Vector3.new(math.cos(rad), 0, math.sin(rad))
			local checkPos = position + direction * dist

			totalChecks += 1
			if self._grid:hasLineOfSight(position + Vector3.new(0, 1.5, 0), checkPos + Vector3.new(0, 1.5, 0)) then
				visibleCount += 1
			end
		end
	end

	return totalChecks > 0 and (visibleCount / totalChecks) or 0
end

--[=[
	Finds chokepoints in an area (narrow passages).

	@param center Vector3 -- Center of search
	@param radius number -- Search radius
	@return { TacticalPosition }

	@example
	```lua
	local chokepoints = nav:findChokepoints(areaCenter, 50)
	for _, choke in chokepoints do
		if choke.advantage > 0.7 then
			print("Strong chokepoint found!")
		end
	end
	```
]=]
function Navigation:findChokepoints(center: Vector3, radius: number): { TacticalPosition }
	local positions: { TacticalPosition } = {}

	local cellRadius = math.ceil(radius / self._grid:getCellSize())
	local cx, _, cz = self._grid:worldToGrid(center)

	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local dist = math.sqrt(dx * dx + dz * dz) * self._grid:getCellSize()
			if dist <= radius then
				local cell = self._grid:getCell(cx + dx, 0, cz + dz)

				if cell.walkable then
					local width = self:_measurePassageWidth(cell.worldPosition)

					if width > 0 and width <= self._chokeWidth then
						local advantage = 1 - (width / self._chokeWidth)

						table.insert(positions, {
							position = cell.worldPosition,
							type = "chokepoint",
							advantage = advantage,
							approachPath = nil,
							description = `{string.format("%.1f", width)} stud passage`,
						})
					end
				end
			end
		end
	end

	return positions
end

--[=[
	Checks if a position is a chokepoint.

	@param position Vector3 -- Position to check
	@return boolean
]=]
function Navigation:isChokepoint(position: Vector3): boolean
	local width = self:_measurePassageWidth(position)
	return width > 0 and width <= self._chokeWidth
end

--[=[
	Measures the width of a passage at a position.
]=]
function Navigation:_measurePassageWidth(position: Vector3): number
	local minWidth = math.huge

	-- Check perpendicular directions
	for angle = 0, 150, 30 do
		local rad = math.rad(angle)
		local direction = Vector3.new(math.cos(rad), 0, math.sin(rad))

		local width = self:_measureWidthInDirection(position, direction)
		minWidth = math.min(minWidth, width)
	end

	return minWidth == math.huge and 0 or minWidth
end

--[=[
	Measures width in a specific direction.
]=]
function Navigation:_measureWidthInDirection(position: Vector3, direction: Vector3): number
	local maxDist = 20
	local leftDist = 0
	local rightDist = 0

	-- Check left
	for dist = 1, maxDist do
		local checkPos = position - direction * dist
		local cell = self._grid:getCellAtPosition(checkPos)
		if not cell.walkable then
			leftDist = dist
			break
		end
	end

	-- Check right
	for dist = 1, maxDist do
		local checkPos = position + direction * dist
		local cell = self._grid:getCellAtPosition(checkPos)
		if not cell.walkable then
			rightDist = dist
			break
		end
	end

	if leftDist == 0 or rightDist == 0 then
		return 0 -- Not a chokepoint (open on one side)
	end

	return (leftDist + rightDist) * self._grid:getCellSize()
end

-- ============================================================================
-- FLEE SYSTEM
-- ============================================================================

--[=[
	Finds an escape path away from threats.

	@param position Vector3 -- Current position
	@param threats { Vector3 } -- Threat positions to flee from
	@param minDistance number? -- Minimum escape distance (default: 30)
	@return PathResult

	@example
	```lua
	local escapePath = nav:findFleePath(myPosition, { enemy1.Position, enemy2.Position }, 40)
	if escapePath.pathFound then
		nav:setPath(escapePath)
	end
	```
]=]
function Navigation:findFleePath(position: Vector3, threats: { Vector3 }, minDistance: number?): PathResult
	local distance = minDistance or 30

	local escapeDirection = self:findSafestDirection(position, threats)
	local goalPos = position + escapeDirection * distance

	-- Find a walkable position near the goal
	local goalCell = self._grid:getCellAtPosition(goalPos)
	if not goalCell.walkable then
		-- Search for nearby walkable cell
		goalPos = self:_findNearestWalkable(goalPos, 20)
	end

	-- Add threats as avoidance zones temporarily
	local oldZones = self._avoidanceZones
	self._avoidanceZones = {}

	for _, threat in threats do
		table.insert(self._avoidanceZones, {
			position = threat,
			radius = 15,
			cost = 10,
		})
	end

	local path = self:findPath(position, goalPos, { avoidThreats = true })

	self._avoidanceZones = oldZones

	return path
end

--[=[
	Finds the safest direction to flee from threats.

	@param position Vector3 -- Current position
	@param threats { Vector3 } -- Threat positions
	@return Vector3 -- Unit direction vector pointing away from threats

	@example
	```lua
	local escapeDir = nav:findSafestDirection(myPosition, threatPositions)
	local targetPos = myPosition + escapeDir * 20
	```
]=]
function Navigation:findSafestDirection(position: Vector3, threats: { Vector3 }): Vector3
	if #threats == 0 then
		return Vector3.new(1, 0, 0)
	end

	-- Calculate threat centroid
	local centroid = Vector3.zero
	for _, threat in threats do
		centroid += threat
	end
	centroid /= #threats

	-- Direction away from centroid
	local awayDirection = (position - centroid)
	if awayDirection.Magnitude < 0.1 then
		return Vector3.new(1, 0, 0)
	end

	awayDirection = Vector3.new(awayDirection.X, 0, awayDirection.Z).Unit

	-- Find best direction that's walkable
	local bestDirection = awayDirection
	local bestScore = -math.huge

	for angle = -90, 90, 15 do
		local rad = math.rad(angle)
		local rotatedDir = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), rad):VectorToWorldSpace(awayDirection)

		local checkPos = position + rotatedDir * 15
		local cell = self._grid:getCellAtPosition(checkPos)

		if cell.walkable then
			local score = 0

			-- Distance from threats
			for _, threat in threats do
				score += (checkPos - threat).Magnitude
			end

			-- Bonus for clear line of sight (can run faster)
			if self._grid:hasLineOfSight(position, checkPos) then
				score += 10
			end

			if score > bestScore then
				bestScore = score
				bestDirection = rotatedDir
			end
		end
	end

	return bestDirection
end

--[=[
	Evaluates how safe a position is from threats.

	@param position Vector3 -- Position to evaluate
	@param threats { Vector3 } -- Threat positions
	@return number -- Safety score (0-1, higher is safer)

	@example
	```lua
	local safety = nav:evaluateSafety(potentialPosition, threats)
	if safety < 0.3 then
		print("Danger zone!")
	end
	```
]=]
function Navigation:evaluateSafety(position: Vector3, threats: { Vector3 }): number
	if #threats == 0 then
		return 1
	end

	local minDistance = math.huge
	local totalDistance = 0

	for _, threat in threats do
		local dist = (position - threat).Magnitude
		minDistance = math.min(minDistance, dist)
		totalDistance += dist
	end

	local avgDistance = totalDistance / #threats

	-- Score based on distances
	local minDistScore = math.clamp(minDistance / 30, 0, 1)
	local avgDistScore = math.clamp(avgDistance / 50, 0, 1)

	-- Bonus if position has cover
	local coverBonus = 0
	local protection = self:_calculateProtection(position, threats)
	coverBonus = protection * 0.3

	return math.clamp(minDistScore * 0.5 + avgDistScore * 0.3 + coverBonus, 0, 1)
end

--[=[
	Finds nearest walkable position.
]=]
function Navigation:_findNearestWalkable(position: Vector3, searchRadius: number): Vector3
	local cellRadius = math.ceil(searchRadius / self._grid:getCellSize())
	local cx, _, cz = self._grid:worldToGrid(position)

	local closest = position
	local closestDist = math.huge

	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local cell = self._grid:getCell(cx + dx, 0, cz + dz)
			if cell.walkable then
				local dist = (cell.worldPosition - position).Magnitude
				if dist < closestDist then
					closestDist = dist
					closest = cell.worldPosition
				end
			end
		end
	end

	return closest
end

-- ============================================================================
-- AVOIDANCE ZONES
-- ============================================================================

--[=[
	Adds an avoidance zone (area to avoid during pathfinding).

	@param position Vector3 -- Center of zone
	@param radius number -- Zone radius
	@param cost number? -- Additional pathfinding cost (default: 5)
]=]
function Navigation:addAvoidanceZone(position: Vector3, radius: number, cost: number?): ()
	table.insert(self._avoidanceZones, {
		position = position,
		radius = radius,
		cost = cost or 5,
	})
end

--[=[
	Removes avoidance zones near a position.

	@param position Vector3 -- Position to clear around
	@param radius number -- Clear radius
]=]
function Navigation:removeAvoidanceZone(position: Vector3, radius: number): ()
	local newZones = {}

	for _, zone in self._avoidanceZones do
		if (zone.position - position).Magnitude > radius then
			table.insert(newZones, zone)
		end
	end

	self._avoidanceZones = newZones
end

--[=[
	Clears all avoidance zones.
]=]
function Navigation:clearAvoidanceZones(): ()
	self._avoidanceZones = {}
end

-- ============================================================================
-- INTEGRATION HELPERS
-- ============================================================================

--[=[
	Sets the Blackboard for squad coordination.

	@param blackboard Blackboard -- Shared blackboard instance
	@param ownerId string? -- This NPC's identifier
]=]
function Navigation:setBlackboard(blackboard: any, ownerId: string?): ()
	self._blackboard = blackboard
	self._ownerId = ownerId
end

--[=[
	Shares current position on the blackboard.

	@param npcId string? -- NPC identifier (uses stored ownerId if nil)
]=]
function Navigation:sharePosition(npcId: string?): ()
	if not self._blackboard then
		return
	end

	local id = npcId or self._ownerId
	if not id then
		return
	end

	local path = self._currentPath
	if path and path.pathFound then
		local destination = path.waypoints[#path.waypoints]
		self._blackboard:post("npc_destination_" .. id, {
			position = destination,
			eta = path.estimatedTime,
		}, id, 5)
	end
end

--[=[
	Sets the Perception system for threat awareness.

	@param perception Perception -- Perception instance
]=]
function Navigation:setPerception(perception: any): ()
	self._perception = perception
end

--[=[
	Updates avoidance zones based on perceived threats.
]=]
function Navigation:updateThreatsFromPerception(): ()
	if not self._perception then
		return
	end

	-- Clear old threat zones
	self:clearAvoidanceZones()

	-- Add zones for alerted threats
	local alertTargets = self._perception:getTargetsInState("alert")
	for _, target in alertTargets do
		if target.lastKnownPosition then
			self:addAvoidanceZone(target.lastKnownPosition, 10, 8)
		end
	end

	local combatTargets = self._perception:getTargetsInState("combat")
	for _, target in combatTargets do
		if target.lastKnownPosition then
			self:addAvoidanceZone(target.lastKnownPosition, 15, 15)
		end
	end
end

--[=[
	Sets the Memory system for path learning.

	@param memory Memory -- Memory instance
]=]
function Navigation:setMemory(memory: any): ()
	self._memory = memory
end

--[=[
	Stores a successful path in memory.

	@param pathId string -- Unique identifier for this route
	@param path PathResult -- The path to remember
]=]
function Navigation:learnPath(pathId: string, path: PathResult): ()
	if not self._memory then
		return
	end

	if path.pathFound then
		self._memory:recordFact("path_" .. pathId, {
			waypoints = path.waypoints,
			distance = path.totalDistance,
			estimatedTime = path.estimatedTime,
		}, 0.8)
	end
end

--[=[
	Recalls a previously learned path.

	@param pathId string -- Path identifier
	@return PathResult? -- Remembered path or nil
]=]
function Navigation:recallPath(pathId: string): PathResult?
	if not self._memory then
		return nil
	end

	local pathData, confidence = self._memory:getFact("path_" .. pathId)

	if pathData and confidence > 0.5 then
		return {
			waypoints = pathData.waypoints,
			totalDistance = pathData.distance,
			estimatedTime = pathData.estimatedTime,
			pathFound = true,
			iterations = 0,
		}
	end

	return nil
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

--[=[
	Gets the navigation grid.

	@return NavigationGrid
]=]
function Navigation:getGrid(): typeof(NavigationGrid.new())
	return self._grid
end

--[=[
	Sets the movement speed (affects time estimates).

	@param speed number -- Movement speed in studs/second
]=]
function Navigation:setMoveSpeed(speed: number): ()
	self._moveSpeed = math.max(1, speed)
end

--[=[
	Gets the movement speed.

	@return number
]=]
function Navigation:getMoveSpeed(): number
	return self._moveSpeed
end

-- ============================================================================
-- STATISTICS
-- ============================================================================

--[=[
	Gets navigation statistics.

	@return { pathsComputed: number, pathsFailed: number, successRate: number, lastPathTime: number, cacheHits: number, cacheMisses: number, cacheHitRate: number }
]=]
function Navigation:getStats(): {
	pathsComputed: number,
	pathsFailed: number,
	successRate: number,
	lastPathTime: number,
	cacheHits: number,
	cacheMisses: number,
	cacheHitRate: number,
}
	local total = self._totalPathsComputed + self._totalPathsFailed
	local successRate = total > 0 and (self._totalPathsComputed / total) or 1
	local cacheTotal = self._pathCacheHits + self._pathCacheMisses
	local cacheHitRate = cacheTotal > 0 and (self._pathCacheHits / cacheTotal) or 0

	return {
		pathsComputed = self._totalPathsComputed,
		pathsFailed = self._totalPathsFailed,
		successRate = successRate,
		lastPathTime = self._lastPathTime,
		cacheHits = self._pathCacheHits,
		cacheMisses = self._pathCacheMisses,
		cacheHitRate = cacheHitRate,
	}
end

--[=[
	Resets statistics.
]=]
function Navigation:resetStats(): ()
	self._totalPathsComputed = 0
	self._totalPathsFailed = 0
	self._lastPathTime = 0
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	String representation for debugging.
]=]
function Navigation:__tostring(): string
	local stats = self:getStats()
	return `Navigation(paths={stats.pathsComputed}, failed={stats.pathsFailed}, successRate={string.format(
		"%.1f%%",
		stats.successRate * 100
	)})`
end

-- ============================================================================
-- MEMORY MANAGEMENT
-- ============================================================================

--[=[
	Destroys the navigation system and releases all resources.

	IMPORTANT: Call this when the NPC is despawned to prevent memory leaks.
	This clears all caches, integration references, and current path state.
	After calling destroy(), the navigation system should not be used.

	@example
	```lua
	-- When NPC is despawned
	navigation:destroy()
	```
]=]
function Navigation:destroy()
	-- Clear path cache
	self:clearPathCache()

	-- Clear current path state
	self._currentPath = nil
	self._currentWaypointIndex = 1

	-- Clear avoidance zones
	table.clear(self._avoidanceZones)

	-- Clear integration references (prevents holding references to other systems)
	self._blackboard = nil
	self._perception = nil
	self._memory = nil
	self._ownerId = nil

	-- Clear the grid reference (the grid may be shared, so just nil the reference)
	self._grid = nil
end

--[=[
	Gets memory statistics for monitoring.

	@return { pathCacheSize: number, avoidanceZones: number, hasCurrentPath: boolean }
]=]
function Navigation:getMemoryStats(): {
	pathCacheSize: number,
	avoidanceZones: number,
	hasCurrentPath: boolean,
}
	return {
		pathCacheSize = self._pathCacheCount,
		avoidanceZones = #self._avoidanceZones,
		hasCurrentPath = self._currentPath ~= nil,
	}
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	Gets a debug summary.

	@return string
]=]
function Navigation:debugSummary(): string
	local stats = self:getStats()
	local gridStats = self._grid:getCacheStats()

	local lines = {
		"Navigation Debug Summary",
		"",
		"=== Pathfinding ===",
		`  Max Iterations: {self._maxIterations}`,
		`  Max Path Length: {self._maxPathLength}`,
		`  Move Speed: {self._moveSpeed} studs/s`,
		`  Paths Computed: {stats.pathsComputed}`,
		`  Paths Failed: {stats.pathsFailed}`,
		`  Success Rate: {string.format("%.1f%%", stats.successRate * 100)}`,
		`  Last Path Time: {string.format("%.4f", stats.lastPathTime)}s`,
		"",
		"=== Cover Settings ===",
		`  Min Cover Height: {self._minCoverHeight} studs`,
		`  Max Cover Distance: {self._maxCoverDistance} studs`,
		`  Preferred Distance: {self._preferredCoverDistance} studs`,
		"",
		"=== Tactical Settings ===",
		`  Flank Angle: {self._flankAngle}°`,
		`  High Ground Min: {self._highGroundMinHeight} studs`,
		`  Choke Width: {self._chokeWidth} studs`,
		"",
		"=== Grid ===",
		`  Cell Size: {self._grid:getCellSize()} studs`,
		`  Cached Cells: {gridStats.size}`,
		`  Cache Hit Rate: {string.format("%.1f%%", gridStats.hitRate * 100)}`,
		"",
		"=== Avoidance Zones ===",
		`  Active Zones: {#self._avoidanceZones}`,
		"",
		"=== Integrations ===",
		`  Blackboard: {self._blackboard and "Connected" or "Not set"}`,
		`  Perception: {self._perception and "Connected" or "Not set"}`,
		`  Memory: {self._memory and "Connected" or "Not set"}`,
	}

	return table.concat(lines, "\n")
end

-- ============================================================================
-- TYPE EXPORT
-- ============================================================================

export type Navigation = typeof(Navigation.new())

return Navigation
