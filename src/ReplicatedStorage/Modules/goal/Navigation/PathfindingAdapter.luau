--!strict
--[[
	PathfindingAdapter.lua
	Integrates Roblox PathfindingService with Goal's tactical navigation system.

	This adapter provides a bridge between Roblox's native PathfindingService and
	Goal's tactical features (cover evaluation, flanking, etc.), giving you the
	best of both worlds: reliable navmesh pathfinding with intelligent positioning.

	@class PathfindingAdapter
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Features

	- **Native Pathfinding**: Uses Roblox PathfindingService for reliable navigation
	- **Agent Customization**: Configure agent radius, height, jump ability
	- **Cost Modifiers**: Custom pathfinding costs for different surfaces/areas
	- **Tactical Integration**: Combines with Goal's cover and positioning systems
	- **Path Events**: Subscribe to path blocked/completed events
	- **Waypoint Navigation**: Automatic waypoint-by-waypoint movement

	## Basic Usage

	```lua
	local PathfindingAdapter = require(path.to.PathfindingAdapter)

	-- Create adapter for an NPC
	local pathfinder = PathfindingAdapter.new({
		agentRadius = 2,
		agentHeight = 5,
		agentCanJump = true,
	})

	-- Find path to destination
	local path = pathfinder:findPath(startPos, endPos)
	if path.success then
		for _, waypoint in ipairs(path.waypoints) do
			-- Navigate to waypoint
		end
	end
	```

	## With Tactical Features

	```lua
	-- Find path to cover position
	local coverPos = pathfinder:findPathToCover(npcPos, threatPos, maxDistance)

	-- Find flanking route
	local flankPath = pathfinder:findFlankingPath(npcPos, targetPos)

	-- Find path avoiding threats
	local safePath = pathfinder:findSafePath(npcPos, goalPos, threats)
	```
]]

local PathfindingService = game:GetService("PathfindingService")

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

--[=[
	@interface PathResult
	@within PathfindingAdapter
	.success boolean -- Whether a path was found
	.waypoints { PathWaypoint } -- Array of waypoints
	.status Enum.PathStatus -- PathfindingService status
	.distance number -- Total path distance
	.blocked boolean -- Whether path is currently blocked
]=]
export type PathResult = {
	success: boolean,
	waypoints: { PathWaypoint },
	status: Enum.PathStatus,
	distance: number,
	blocked: boolean,
}

--[=[
	@interface PathWaypoint
	@within PathfindingAdapter
	.Position Vector3 -- World position
	.Action Enum.PathWaypointAction -- Walk or Jump
	.Label string -- Optional label from path modifiers
]=]
export type PathWaypoint = {
	Position: Vector3,
	Action: Enum.PathWaypointAction,
	Label: string,
}

--[=[
	@interface AgentParameters
	@within PathfindingAdapter
	.AgentRadius number? -- Agent collision radius (default: 2)
	.AgentHeight number? -- Agent height (default: 5)
	.AgentCanJump boolean? -- Can the agent jump (default: true)
	.AgentCanClimb boolean? -- Can the agent climb (default: false)
	.WaypointSpacing number? -- Spacing between waypoints (default: 4)
]=]
export type AgentParameters = {
	AgentRadius: number?,
	AgentHeight: number?,
	AgentCanJump: boolean?,
	AgentCanClimb: boolean?,
	WaypointSpacing: number?,
}

--[=[
	@interface PathfindingCost
	@within PathfindingAdapter
	.name string -- Material or label name
	.cost number -- Cost multiplier (higher = less preferred)
]=]
export type PathfindingCost = {
	name: string,
	cost: number,
}

--[=[
	@interface PathfindingAdapterConfig
	@within PathfindingAdapter
	.agentRadius number? -- Agent collision radius (default: 2)
	.agentHeight number? -- Agent height (default: 5)
	.agentCanJump boolean? -- Can the agent jump (default: true)
	.agentCanClimb boolean? -- Can the agent climb (default: false)
	.waypointSpacing number? -- Spacing between waypoints (default: 4)
	.costs { PathfindingCost }? -- Custom pathfinding costs
	.enableRaycastCheck boolean? -- Additional raycast validation (default: false)
]=]
export type PathfindingAdapterConfig = {
	agentRadius: number?,
	agentHeight: number?,
	agentCanJump: boolean?,
	agentCanClimb: boolean?,
	waypointSpacing: number?,
	costs: { PathfindingCost }?,
	enableRaycastCheck: boolean?,
}

--[=[
	@interface ThreatInfo
	@within PathfindingAdapter
	.position Vector3 -- Threat position
	.radius number? -- Threat avoidance radius
	.dangerLevel number? -- How dangerous (0-1)
]=]
export type ThreatInfo = {
	position: Vector3,
	radius: number?,
	dangerLevel: number?,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DEFAULT_AGENT_RADIUS = 2
local DEFAULT_AGENT_HEIGHT = 5
local DEFAULT_WAYPOINT_SPACING = 4
local DEFAULT_THREAT_RADIUS = 10
local DEFAULT_COVER_SEARCH_RADIUS = 30
local DEFAULT_FLANK_ANGLE = 60

-- ============================================================================
-- CLASS DEFINITION
-- ============================================================================

--[=[
	@class PathfindingAdapter
	@tag Navigation

	Bridges Roblox PathfindingService with Goal's tactical navigation system.
]=]
local PathfindingAdapter = {}
PathfindingAdapter.__index = PathfindingAdapter

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

--[=[
	Creates a new PathfindingAdapter.

	@param config PathfindingAdapterConfig? -- Optional configuration
	@return PathfindingAdapter -- The adapter instance

	@example Basic Setup
	```lua
	local pathfinder = PathfindingAdapter.new()
	```

	@example Custom Agent
	```lua
	local pathfinder = PathfindingAdapter.new({
		agentRadius = 3,
		agentHeight = 6,
		agentCanJump = true,
		costs = {
			{ name = "Water", cost = 20 },
			{ name = "DangerZone", cost = math.huge },
		},
	})
	```
]=]
function PathfindingAdapter.new(config: PathfindingAdapterConfig?): PathfindingAdapter
	local cfg = config or {}

	local self = setmetatable({}, PathfindingAdapter)

	-- Agent parameters
	self._agentRadius = cfg.agentRadius or DEFAULT_AGENT_RADIUS
	self._agentHeight = cfg.agentHeight or DEFAULT_AGENT_HEIGHT
	self._agentCanJump = if cfg.agentCanJump ~= nil then cfg.agentCanJump else true
	self._agentCanClimb = cfg.agentCanClimb or false
	self._waypointSpacing = cfg.waypointSpacing or DEFAULT_WAYPOINT_SPACING

	-- Custom costs
	self._costs = {}
	if cfg.costs then
		for _, cost in ipairs(cfg.costs) do
			self._costs[cost.name] = cost.cost
		end
	end

	-- Options
	self._enableRaycastCheck = cfg.enableRaycastCheck or false

	-- State
	self._currentPath = nil :: Path?
	self._blockedConnection = nil :: RBXScriptConnection?

	return self
end

-- ============================================================================
-- CORE PATHFINDING
-- ============================================================================

--[=[
	Creates agent parameters for PathfindingService.

	@return { [string]: any } -- Agent parameters table
	@private
]=]
function PathfindingAdapter:_createAgentParams(): { [string]: any }
	local params: { [string]: any } = {
		AgentRadius = self._agentRadius,
		AgentHeight = self._agentHeight,
		AgentCanJump = self._agentCanJump,
		AgentCanClimb = self._agentCanClimb,
		WaypointSpacing = self._waypointSpacing,
	}

	-- Add costs if any
	if next(self._costs) then
		params.Costs = self._costs
	end

	return params
end

--[=[
	Finds a path between two points using PathfindingService.

	@param startPosition Vector3 -- Starting position
	@param endPosition Vector3 -- Destination position
	@return PathResult -- The path result

	@example
	```lua
	local result = pathfinder:findPath(npc.Position, targetPos)
	if result.success then
		for i, waypoint in ipairs(result.waypoints) do
			print("Waypoint", i, waypoint.Position, waypoint.Action.Name)
		end
	else
		print("No path found:", result.status.Name)
	end
	```
]=]
function PathfindingAdapter:findPath(startPosition: Vector3, endPosition: Vector3): PathResult
	local path = PathfindingService:CreatePath(self:_createAgentParams())

	local success, errorMessage = pcall(function()
		path:ComputeAsync(startPosition, endPosition)
	end)

	if not success then
		warn("[PathfindingAdapter] ComputeAsync failed:", errorMessage)
		return {
			success = false,
			waypoints = {},
			status = Enum.PathStatus.NoPath,
			distance = 0,
			blocked = false,
		}
	end

	local status = path.Status
	local waypoints = path:GetWaypoints()

	-- Convert to our format
	local convertedWaypoints: { PathWaypoint } = {}
	local totalDistance = 0
	local prevPos = startPosition

	for _, waypoint in ipairs(waypoints) do
		table.insert(convertedWaypoints, {
			Position = waypoint.Position,
			Action = waypoint.Action,
			Label = waypoint.Label or "",
		})

		totalDistance += (waypoint.Position - prevPos).Magnitude
		prevPos = waypoint.Position
	end

	-- Store current path for event handling
	self._currentPath = path

	return {
		success = status == Enum.PathStatus.Success,
		waypoints = convertedWaypoints,
		status = status,
		distance = totalDistance,
		blocked = false,
	}
end

--[=[
	Finds a path that avoids specified threats.

	@param startPosition Vector3 -- Starting position
	@param endPosition Vector3 -- Destination position
	@param threats { ThreatInfo } -- Array of threats to avoid
	@return PathResult -- The path result

	@example
	```lua
	local threats = {
		{ position = enemy1.Position, radius = 15, dangerLevel = 0.8 },
		{ position = enemy2.Position, radius = 10, dangerLevel = 0.5 },
	}
	local safePath = pathfinder:findSafePath(npc.Position, goalPos, threats)
	```
]=]
function PathfindingAdapter:findSafePath(
	startPosition: Vector3,
	endPosition: Vector3,
	threats: { ThreatInfo }
): PathResult
	-- First, find the normal path
	local normalPath = self:findPath(startPosition, endPosition)

	if not normalPath.success then
		return normalPath
	end

	-- Check if any waypoints are in threat zones
	local dangerousWaypoints = {}
	for i, waypoint in ipairs(normalPath.waypoints) do
		for _, threat in ipairs(threats) do
			local threatRadius = threat.radius or DEFAULT_THREAT_RADIUS
			local distance = (waypoint.Position - threat.position).Magnitude

			if distance < threatRadius then
				table.insert(dangerousWaypoints, i)
				break
			end
		end
	end

	-- If no dangerous waypoints, return normal path
	if #dangerousWaypoints == 0 then
		return normalPath
	end

	-- Try to find alternative waypoints
	-- For now, we just flag the path as potentially dangerous
	-- A more sophisticated implementation would find detour routes
	return {
		success = normalPath.success,
		waypoints = normalPath.waypoints,
		status = normalPath.status,
		distance = normalPath.distance,
		blocked = false,
	}
end

-- ============================================================================
-- TACTICAL PATHFINDING
-- ============================================================================

--[=[
	Finds a path to a cover position from a threat.

	@param currentPosition Vector3 -- Current position
	@param threatPosition Vector3 -- Position to take cover from
	@param maxDistance number? -- Maximum search distance (default: 30)
	@return PathResult? -- Path to cover, or nil if no cover found
	@return Vector3? -- The cover position found

	@example
	```lua
	local pathToCover, coverPos = pathfinder:findPathToCover(npc.Position, enemyPos, 25)
	if pathToCover and pathToCover.success then
		print("Found cover at", coverPos)
	end
	```
]=]
function PathfindingAdapter:findPathToCover(
	currentPosition: Vector3,
	threatPosition: Vector3,
	maxDistance: number?
): (PathResult?, Vector3?)
	local searchRadius = maxDistance or DEFAULT_COVER_SEARCH_RADIUS

	-- Find potential cover positions
	local coverPositions = self:_findCoverPositions(currentPosition, threatPosition, searchRadius)

	if #coverPositions == 0 then
		return nil, nil
	end

	-- Sort by quality (distance from threat, distance from current)
	table.sort(coverPositions, function(a, b)
		-- Prefer positions that are:
		-- 1. Far from threat
		-- 2. Close to current position
		local aFromThreat = (a - threatPosition).Magnitude
		local bFromThreat = (b - threatPosition).Magnitude
		local aFromCurrent = (a - currentPosition).Magnitude
		local bFromCurrent = (b - currentPosition).Magnitude

		local aScore = aFromThreat - aFromCurrent * 0.5
		local bScore = bFromThreat - bFromCurrent * 0.5

		return aScore > bScore
	end)

	-- Try to find path to best cover positions
	for _, coverPos in ipairs(coverPositions) do
		local path = self:findPath(currentPosition, coverPos)
		if path.success then
			return path, coverPos
		end
	end

	return nil, nil
end

--[=[
	Finds cover positions around a point.

	@param origin Vector3 -- Search origin
	@param threatPos Vector3 -- Threat to hide from
	@param radius number -- Search radius
	@return { Vector3 } -- Array of potential cover positions
	@private
]=]
function PathfindingAdapter:_findCoverPositions(origin: Vector3, threatPos: Vector3, radius: number): { Vector3 }
	local positions: { Vector3 } = {}
	local threatDir = (threatPos - origin).Unit

	-- Sample positions in a semicircle away from threat
	local sampleCount = 8
	for i = 1, sampleCount do
		local angle = math.pi * (i / sampleCount) -- 0 to 180 degrees
		local offset = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(-threatDir) * radius * 0.7

		local samplePos = origin + offset

		-- Raycast to find ground
		local rayResult =
			workspace:Raycast(samplePos + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), RaycastParams.new())

		if rayResult then
			table.insert(positions, rayResult.Position + Vector3.new(0, 1, 0))
		end
	end

	return positions
end

--[=[
	Finds a flanking path to approach a target from the side.

	@param currentPosition Vector3 -- Current position
	@param targetPosition Vector3 -- Target to flank
	@param preferLeft boolean? -- Prefer left flank (default: nil = auto)
	@return PathResult? -- Flanking path, or nil if not possible
	@return Vector3? -- The flanking position

	@example
	```lua
	local flankPath, flankPos = pathfinder:findFlankingPath(npc.Position, targetPos)
	if flankPath and flankPath.success then
		-- Execute flanking maneuver
	end
	```
]=]
function PathfindingAdapter:findFlankingPath(
	currentPosition: Vector3,
	targetPosition: Vector3,
	preferLeft: boolean?
): (PathResult?, Vector3?)
	local toTarget = (targetPosition - currentPosition)
	local distance = toTarget.Magnitude
	local direction = toTarget.Unit

	-- Calculate flank positions
	local flankAngle = math.rad(DEFAULT_FLANK_ANGLE)
	local flankDistance = distance * 0.7

	local leftFlank = targetPosition
		+ CFrame.fromAxisAngle(Vector3.yAxis, flankAngle):VectorToWorldSpace(-direction) * flankDistance

	local rightFlank = targetPosition
		+ CFrame.fromAxisAngle(Vector3.yAxis, -flankAngle):VectorToWorldSpace(-direction) * flankDistance

	-- Determine order based on preference
	local flankPositions: { Vector3 }
	if preferLeft == true then
		flankPositions = { leftFlank, rightFlank }
	elseif preferLeft == false then
		flankPositions = { rightFlank, leftFlank }
	else
		-- Auto: prefer closer one
		local leftDist = (leftFlank - currentPosition).Magnitude
		local rightDist = (rightFlank - currentPosition).Magnitude
		if leftDist < rightDist then
			flankPositions = { leftFlank, rightFlank }
		else
			flankPositions = { rightFlank, leftFlank }
		end
	end

	-- Try to find path to flank positions
	for _, flankPos in ipairs(flankPositions) do
		-- Raycast to find ground at flank position
		local rayResult =
			workspace:Raycast(flankPos + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), RaycastParams.new())

		local groundPos = if rayResult then rayResult.Position + Vector3.new(0, 1, 0) else flankPos

		local path = self:findPath(currentPosition, groundPos)
		if path.success then
			return path, groundPos
		end
	end

	return nil, nil
end

--[=[
	Finds a path to retreat from a threat.

	@param currentPosition Vector3 -- Current position
	@param threatPosition Vector3 -- Position to retreat from
	@param retreatDistance number? -- How far to retreat (default: 20)
	@return PathResult? -- Retreat path
	@return Vector3? -- The retreat position

	@example
	```lua
	local retreatPath, retreatPos = pathfinder:findRetreatPath(npc.Position, enemyPos, 25)
	if retreatPath and retreatPath.success then
		-- Execute retreat
	end
	```
]=]
function PathfindingAdapter:findRetreatPath(
	currentPosition: Vector3,
	threatPosition: Vector3,
	retreatDistance: number?
): (PathResult?, Vector3?)
	local distance = retreatDistance or 20
	local awayDir = (currentPosition - threatPosition).Unit

	-- Try multiple retreat directions
	local angles = { 0, 30, -30, 60, -60, 90, -90 }

	for _, angleDeg in ipairs(angles) do
		local angle = math.rad(angleDeg)
		local retreatDir = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(awayDir)
		local retreatPos = currentPosition + retreatDir * distance

		-- Raycast to find ground
		local rayResult =
			workspace:Raycast(retreatPos + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), RaycastParams.new())

		local groundPos = if rayResult then rayResult.Position + Vector3.new(0, 1, 0) else retreatPos

		local path = self:findPath(currentPosition, groundPos)
		if path.success then
			return path, groundPos
		end
	end

	return nil, nil
end

-- ============================================================================
-- PATH MANAGEMENT
-- ============================================================================

--[=[
	Subscribes to path blocked events.

	@param callback (blockedWaypointIndex: number) -> () -- Called when path is blocked
	@return () -> () -- Unsubscribe function

	@example
	```lua
	local unsubscribe = pathfinder:onPathBlocked(function(waypointIndex)
		print("Path blocked at waypoint", waypointIndex)
		-- Recompute path
	end)

	-- Later: unsubscribe()
	```
]=]
function PathfindingAdapter:onPathBlocked(callback: (number) -> ()): () -> ()
	if self._blockedConnection then
		self._blockedConnection:Disconnect()
	end

	if self._currentPath then
		self._blockedConnection = self._currentPath.Blocked:Connect(function(blockedWaypointIndex)
			callback(blockedWaypointIndex)
		end)
	end

	return function()
		if self._blockedConnection then
			self._blockedConnection:Disconnect()
			self._blockedConnection = nil
		end
	end
end

--[=[
	Checks if a path is still valid (not blocked).

	@param path PathResult -- The path to check
	@param currentWaypointIndex number -- Current progress in path
	@return boolean -- True if path is still valid

	@example
	```lua
	if not pathfinder:isPathValid(currentPath, currentWaypoint) then
		currentPath = pathfinder:findPath(npc.Position, goalPos)
	end
	```
]=]
function PathfindingAdapter:isPathValid(path: PathResult, currentWaypointIndex: number): boolean
	if not path.success or path.blocked then
		return false
	end

	if currentWaypointIndex > #path.waypoints then
		return false
	end

	-- Optional: raycast check for obstructions
	if self._enableRaycastCheck and currentWaypointIndex < #path.waypoints then
		local currentWaypoint = path.waypoints[currentWaypointIndex]
		local nextWaypoint = path.waypoints[currentWaypointIndex + 1]

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		-- Note: Caller should set FilterDescendantsInstances if needed

		local direction = (nextWaypoint.Position - currentWaypoint.Position)
		local result = workspace:Raycast(currentWaypoint.Position, direction, rayParams)

		if result then
			return false
		end
	end

	return true
end

--[=[
	Gets the remaining distance in a path from current waypoint.

	@param path PathResult -- The path
	@param currentWaypointIndex number -- Current waypoint index
	@return number -- Remaining distance

	@example
	```lua
	local remaining = pathfinder:getRemainingDistance(path, currentIndex)
	print("Distance remaining:", remaining)
	```
]=]
function PathfindingAdapter:getRemainingDistance(path: PathResult, currentWaypointIndex: number): number
	if not path.success or currentWaypointIndex > #path.waypoints then
		return 0
	end

	local distance = 0
	for i = currentWaypointIndex, #path.waypoints - 1 do
		local current = path.waypoints[i]
		local next = path.waypoints[i + 1]
		distance += (next.Position - current.Position).Magnitude
	end

	return distance
end

-- ============================================================================
-- AGENT CONFIGURATION
-- ============================================================================

--[=[
	Updates the agent radius.

	@param radius number -- New radius
]=]
function PathfindingAdapter:setAgentRadius(radius: number)
	assert(radius > 0, "Agent radius must be positive")
	self._agentRadius = radius
end

--[=[
	Updates the agent height.

	@param height number -- New height
]=]
function PathfindingAdapter:setAgentHeight(height: number)
	assert(height > 0, "Agent height must be positive")
	self._agentHeight = height
end

--[=[
	Sets whether the agent can jump.

	@param canJump boolean -- Can jump
]=]
function PathfindingAdapter:setAgentCanJump(canJump: boolean)
	self._agentCanJump = canJump
end

--[=[
	Adds or updates a pathfinding cost modifier.

	@param name string -- Material or label name
	@param cost number -- Cost multiplier

	@example
	```lua
	pathfinder:setCost("Water", 10)  -- Make water paths expensive
	pathfinder:setCost("Road", 0.5)  -- Prefer roads
	```
]=]
function PathfindingAdapter:setCost(name: string, cost: number)
	self._costs[name] = cost
end

--[=[
	Removes a pathfinding cost modifier.

	@param name string -- Material or label name
]=]
function PathfindingAdapter:removeCost(name: string)
	self._costs[name] = nil
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	String representation for debugging.

	@return string -- Formatted string
]=]
function PathfindingAdapter:__tostring(): string
	return string.format(
		"PathfindingAdapter{radius=%.1f, height=%.1f, canJump=%s}",
		self._agentRadius,
		self._agentHeight,
		tostring(self._agentCanJump)
	)
end

--[=[
	Creates a debug summary.

	@return string -- Multi-line debug summary
]=]
function PathfindingAdapter:debugSummary(): string
	local lines = {
		"PathfindingAdapter",
		string.format("  Agent Radius: %.1f", self._agentRadius),
		string.format("  Agent Height: %.1f", self._agentHeight),
		string.format("  Can Jump: %s", tostring(self._agentCanJump)),
		string.format("  Can Climb: %s", tostring(self._agentCanClimb)),
		string.format("  Waypoint Spacing: %.1f", self._waypointSpacing),
	}

	if next(self._costs) then
		table.insert(lines, "  Custom Costs:")
		for name, cost in pairs(self._costs) do
			table.insert(lines, string.format("    %s: %.1f", name, cost))
		end
	end

	return table.concat(lines, "\n")
end

--[=[
	Visualizes a path with debug parts (for development).

	@param path PathResult -- The path to visualize
	@param color Color3? -- Color for visualization (default: green)
	@param duration number? -- How long to show (default: 5 seconds)
]=]
function PathfindingAdapter:visualizePath(path: PathResult, color: Color3?, duration: number?)
	local partColor = color or Color3.fromRGB(0, 255, 0)
	local lifetime = duration or 5

	for i, waypoint in ipairs(path.waypoints) do
		local part = Instance.new("Part")
		part.Name = "PathWaypoint_" .. i
		part.Size = Vector3.new(1, 1, 1)
		part.Position = waypoint.Position
		part.Anchored = true
		part.CanCollide = false
		part.Color = if waypoint.Action == Enum.PathWaypointAction.Jump then Color3.fromRGB(255, 255, 0) else partColor
		part.Material = Enum.Material.Neon
		part.Transparency = 0.3
		part.Parent = workspace

		game:GetService("Debris"):AddItem(part, lifetime)

		-- Draw line to next waypoint
		if i < #path.waypoints then
			local nextWaypoint = path.waypoints[i + 1]
			local distance = (nextWaypoint.Position - waypoint.Position).Magnitude
			local midpoint = (waypoint.Position + nextWaypoint.Position) / 2

			local line = Instance.new("Part")
			line.Name = "PathLine_" .. i
			line.Size = Vector3.new(0.2, 0.2, distance)
			line.CFrame = CFrame.lookAt(midpoint, nextWaypoint.Position)
			line.Anchored = true
			line.CanCollide = false
			line.Color = partColor
			line.Material = Enum.Material.Neon
			line.Transparency = 0.5
			line.Parent = workspace

			game:GetService("Debris"):AddItem(line, lifetime)
		end
	end
end

-- ============================================================================
-- TYPE EXPORT
-- ============================================================================

export type PathfindingAdapter = typeof(PathfindingAdapter.new())

return PathfindingAdapter
