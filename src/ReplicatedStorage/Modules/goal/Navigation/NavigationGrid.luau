--!strict
--[[
	NavigationGrid - Spatial grid representation for pathfinding

	Provides a discrete grid overlay on the game world for A* pathfinding.
	Handles walkability checks, height sampling, and neighbor traversal.

	@class NavigationGrid
]]

local NavigationGrid = {}
NavigationGrid.__index = NavigationGrid

-- ============================================================================
-- TYPES
-- ============================================================================

export type GridCell = {
	x: number,
	y: number,
	z: number,
	worldPosition: Vector3,
	walkable: boolean,
	cost: number,
	height: number,
}

export type GridConfig = {
	cellSize: number?,
	heightTolerance: number?,
	maxSlope: number?,
	obstructionCheck: ((Vector3, Vector3) -> boolean)?,
	heightSampler: ((Vector3) -> number)?,
	walkableCheck: ((Vector3) -> boolean)?,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DEFAULT_CELL_SIZE = 4
local DEFAULT_HEIGHT_TOLERANCE = 4
local DEFAULT_MAX_SLOPE = 45

-- Neighbor offsets for 8-directional movement
local NEIGHBOR_OFFSETS = {
	{ x = 1, z = 0, cost = 1.0 }, -- East
	{ x = -1, z = 0, cost = 1.0 }, -- West
	{ x = 0, z = 1, cost = 1.0 }, -- North
	{ x = 0, z = -1, cost = 1.0 }, -- South
	{ x = 1, z = 1, cost = 1.414 }, -- NE (diagonal)
	{ x = -1, z = 1, cost = 1.414 }, -- NW
	{ x = 1, z = -1, cost = 1.414 }, -- SE
	{ x = -1, z = -1, cost = 1.414 }, -- SW
}

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

--[=[
	Creates a new NavigationGrid.

	@param config GridConfig? -- Optional configuration
	@return NavigationGrid
]=]
function NavigationGrid.new(config: GridConfig?): NavigationGrid
	local cfg = config or {}

	local self = setmetatable({}, NavigationGrid)

	-- Configuration
	self._cellSize = cfg.cellSize or DEFAULT_CELL_SIZE
	self._heightTolerance = cfg.heightTolerance or DEFAULT_HEIGHT_TOLERANCE
	self._maxSlope = cfg.maxSlope or DEFAULT_MAX_SLOPE

	-- Custom functions
	self._obstructionCheck = cfg.obstructionCheck
	self._heightSampler = cfg.heightSampler
	self._walkableCheck = cfg.walkableCheck

	-- Cached cells
	self._cellCache = {} :: { [string]: GridCell }
	self._cacheHits = 0
	self._cacheMisses = 0

	return self
end

-- ============================================================================
-- CELL OPERATIONS
-- ============================================================================

--[=[
	Converts a world position to grid coordinates.

	@param position Vector3 -- World position
	@return number, number, number -- Grid x, y, z coordinates
]=]
function NavigationGrid:worldToGrid(position: Vector3): (number, number, number)
	local x = math.floor(position.X / self._cellSize)
	local y = math.floor(position.Y / self._cellSize)
	local z = math.floor(position.Z / self._cellSize)
	return x, y, z
end

--[=[
	Converts grid coordinates to world position (center of cell).

	@param x number -- Grid X
	@param y number -- Grid Y
	@param z number -- Grid Z
	@return Vector3 -- World position at center of cell
]=]
function NavigationGrid:gridToWorld(x: number, y: number, z: number): Vector3
	local halfCell = self._cellSize / 2
	return Vector3.new(x * self._cellSize + halfCell, y * self._cellSize + halfCell, z * self._cellSize + halfCell)
end

--[=[
	Gets the cache key for a grid position.

	@param x number
	@param y number
	@param z number
	@return string
]=]
function NavigationGrid:_getCacheKey(x: number, y: number, z: number): string
	return `{x},{y},{z}`
end

--[=[
	Gets or creates a cell at the given grid coordinates.

	@param x number -- Grid X
	@param y number -- Grid Y
	@param z number -- Grid Z
	@return GridCell
]=]
function NavigationGrid:getCell(x: number, y: number, z: number): GridCell
	local key = self:_getCacheKey(x, y, z)

	if self._cellCache[key] then
		self._cacheHits += 1
		return self._cellCache[key]
	end

	self._cacheMisses += 1

	local worldPos = self:gridToWorld(x, y, z)
	local height = self:_sampleHeight(worldPos)
	local walkable = self:_checkWalkable(worldPos)

	local cell: GridCell = {
		x = x,
		y = y,
		z = z,
		worldPosition = Vector3.new(worldPos.X, height, worldPos.Z),
		walkable = walkable,
		cost = 1.0,
		height = height,
	}

	self._cellCache[key] = cell
	return cell
end

--[=[
	Gets a cell at a world position.

	@param position Vector3 -- World position
	@return GridCell
]=]
function NavigationGrid:getCellAtPosition(position: Vector3): GridCell
	local x, y, z = self:worldToGrid(position)
	return self:getCell(x, y, z)
end

--[=[
	Samples the height at a world position.

	@param position Vector3 -- Position to sample
	@return number -- Height at position
]=]
function NavigationGrid:_sampleHeight(position: Vector3): number
	if self._heightSampler then
		return self._heightSampler(position)
	end

	-- Default: raycast down to find ground
	local rayOrigin = Vector3.new(position.X, position.Y + 100, position.Z)
	local rayDirection = Vector3.new(0, -200, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {}

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	if result then
		return result.Position.Y
	end

	return position.Y
end

--[=[
	Checks if a position is walkable.

	@param position Vector3 -- Position to check
	@return boolean -- True if walkable
]=]
function NavigationGrid:_checkWalkable(position: Vector3): boolean
	if self._walkableCheck then
		return self._walkableCheck(position)
	end

	-- Default: check if there's ground and no obstruction
	local groundPos = Vector3.new(position.X, self:_sampleHeight(position), position.Z)

	-- Check for obstructions at character height
	local checkHeight = 5
	local rayOrigin = groundPos + Vector3.new(0, 0.5, 0)
	local rayDirection = Vector3.new(0, checkHeight, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {}

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	-- If we hit something close, position is not walkable
	if result and (result.Position - rayOrigin).Magnitude < 2 then
		return false
	end

	return true
end

--[=[
	Checks if there's a clear line between two positions.

	@param from Vector3 -- Start position
	@param to Vector3 -- End position
	@return boolean -- True if clear path exists
]=]
function NavigationGrid:hasLineOfSight(from: Vector3, to: Vector3): boolean
	if self._obstructionCheck then
		return not self._obstructionCheck(from, to)
	end

	-- Default raycast check
	local direction = to - from
	local distance = direction.Magnitude

	if distance < 0.1 then
		return true
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {}

	local result = workspace:Raycast(from + Vector3.new(0, 1, 0), direction.Unit * distance, raycastParams)

	return result == nil
end

--[=[
	Gets walkable neighbors of a cell.

	@param cell GridCell -- The cell to get neighbors for
	@return { { cell: GridCell, cost: number } } -- Array of neighbor cells with movement costs
]=]
function NavigationGrid:getNeighbors(cell: GridCell): { { cell: GridCell, cost: number } }
	local neighbors = {}

	for _, offset in NEIGHBOR_OFFSETS do
		local nx = cell.x + offset.x
		local nz = cell.z + offset.z
		local neighborCell = self:getCell(nx, cell.y, nz)

		if neighborCell.walkable then
			-- Check height difference
			local heightDiff = math.abs(neighborCell.height - cell.height)

			if heightDiff <= self._heightTolerance then
				-- Calculate slope
				local horizontalDist = self._cellSize * offset.cost
				local slope = math.deg(math.atan2(heightDiff, horizontalDist))

				if slope <= self._maxSlope then
					-- Add height cost modifier
					local heightCost = heightDiff / self._heightTolerance * 0.5
					local totalCost = offset.cost + heightCost + (neighborCell.cost - 1)

					table.insert(neighbors, {
						cell = neighborCell,
						cost = totalCost,
					})
				end
			end
		end
	end

	return neighbors
end

--[=[
	Sets a custom cost for a cell (e.g., for dangerous areas).

	@param x number -- Grid X
	@param y number -- Grid Y
	@param z number -- Grid Z
	@param cost number -- Movement cost multiplier (1.0 = normal)
]=]
function NavigationGrid:setCellCost(x: number, y: number, z: number, cost: number): ()
	local cell = self:getCell(x, y, z)
	cell.cost = math.max(0.1, cost)
end

--[=[
	Sets a cell as blocked or unblocked.

	@param x number -- Grid X
	@param y number -- Grid Y
	@param z number -- Grid Z
	@param walkable boolean -- Whether the cell is walkable
]=]
function NavigationGrid:setCellWalkable(x: number, y: number, z: number, walkable: boolean): ()
	local cell = self:getCell(x, y, z)
	cell.walkable = walkable
end

--[=[
	Marks cells around a position as blocked.

	@param position Vector3 -- Center position
	@param radius number -- Radius in studs
]=]
function NavigationGrid:blockArea(position: Vector3, radius: number): ()
	local cellRadius = math.ceil(radius / self._cellSize)
	local cx, cy, cz = self:worldToGrid(position)

	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local dist = math.sqrt(dx * dx + dz * dz) * self._cellSize
			if dist <= radius then
				self:setCellWalkable(cx + dx, cy, cz + dz, false)
			end
		end
	end
end

--[=[
	Clears blocked cells around a position.

	@param position Vector3 -- Center position
	@param radius number -- Radius in studs
]=]
function NavigationGrid:unblockArea(position: Vector3, radius: number): ()
	local cellRadius = math.ceil(radius / self._cellSize)
	local cx, cy, cz = self:worldToGrid(position)

	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local dist = math.sqrt(dx * dx + dz * dz) * self._cellSize
			if dist <= radius then
				self:setCellWalkable(cx + dx, cy, cz + dz, true)
			end
		end
	end
end

-- ============================================================================
-- DISTANCE CALCULATIONS
-- ============================================================================

--[=[
	Calculates Manhattan distance between two cells.

	@param cellA GridCell
	@param cellB GridCell
	@return number
]=]
function NavigationGrid:manhattanDistance(cellA: GridCell, cellB: GridCell): number
	return math.abs(cellA.x - cellB.x) + math.abs(cellA.z - cellB.z)
end

--[=[
	Calculates Euclidean distance between two cells.

	@param cellA GridCell
	@param cellB GridCell
	@return number
]=]
function NavigationGrid:euclideanDistance(cellA: GridCell, cellB: GridCell): number
	local dx = cellA.x - cellB.x
	local dz = cellA.z - cellB.z
	return math.sqrt(dx * dx + dz * dz)
end

--[=[
	Calculates octile distance (diagonal heuristic) between two cells.
	Better for 8-directional movement.

	@param cellA GridCell
	@param cellB GridCell
	@return number
]=]
function NavigationGrid:octileDistance(cellA: GridCell, cellB: GridCell): number
	local dx = math.abs(cellA.x - cellB.x)
	local dz = math.abs(cellA.z - cellB.z)
	local diagonal = math.min(dx, dz)
	local straight = dx + dz - 2 * diagonal
	return diagonal * 1.414 + straight
end

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

--[=[
	Clears the cell cache.
]=]
function NavigationGrid:clearCache(): ()
	self._cellCache = {}
	self._cacheHits = 0
	self._cacheMisses = 0
end

--[=[
	Gets cache statistics.

	@return { hits: number, misses: number, size: number, hitRate: number }
]=]
function NavigationGrid:getCacheStats(): { hits: number, misses: number, size: number, hitRate: number }
	local size = 0
	for _ in self._cellCache do
		size += 1
	end

	local total = self._cacheHits + self._cacheMisses
	local hitRate = total > 0 and (self._cacheHits / total) or 0

	return {
		hits = self._cacheHits,
		misses = self._cacheMisses,
		size = size,
		hitRate = hitRate,
	}
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

--[=[
	Sets the obstruction check function.

	@param fn (Vector3, Vector3) -> boolean -- Returns true if path is obstructed
]=]
function NavigationGrid:setObstructionCheck(fn: (Vector3, Vector3) -> boolean): ()
	self._obstructionCheck = fn
end

--[=[
	Sets the height sampling function.

	@param fn (Vector3) -> number -- Returns height at position
]=]
function NavigationGrid:setHeightSampler(fn: (Vector3) -> number): ()
	self._heightSampler = fn
end

--[=[
	Sets the walkability check function.

	@param fn (Vector3) -> boolean -- Returns true if position is walkable
]=]
function NavigationGrid:setWalkableCheck(fn: (Vector3) -> boolean): ()
	self._walkableCheck = fn
end

--[=[
	Gets the cell size.

	@return number
]=]
function NavigationGrid:getCellSize(): number
	return self._cellSize
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	String representation for debugging.
]=]
function NavigationGrid:__tostring(): string
	local stats = self:getCacheStats()
	return `NavigationGrid(cellSize={self._cellSize}, cached={stats.size}, hitRate={string.format(
		"%.1f%%",
		stats.hitRate * 100
	)})`
end

--[=[
	Gets a debug summary.

	@return string
]=]
function NavigationGrid:debugSummary(): string
	local stats = self:getCacheStats()
	local lines = {
		"NavigationGrid Debug Summary",
		`  Cell Size: {self._cellSize} studs`,
		`  Height Tolerance: {self._heightTolerance} studs`,
		`  Max Slope: {self._maxSlope}°`,
		`  Cache Size: {stats.size} cells`,
		`  Cache Hits: {stats.hits}`,
		`  Cache Misses: {stats.misses}`,
		`  Hit Rate: {string.format("%.1f%%", stats.hitRate * 100)}`,
	}
	return table.concat(lines, "\n")
end

-- ============================================================================
-- TYPE EXPORT
-- ============================================================================

export type NavigationGrid = typeof(NavigationGrid.new())

return NavigationGrid
