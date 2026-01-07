--!strict
--// SpatialGrid.lua
--// High-performance spatial hashing for O(1) proximity queries.
--//
--// Divides 2D/3D space into cells and tracks entities by cell.
--// Enables fast "find all entities within radius" queries.
--//
--// Time Complexity:
--//   - Insert/Update/Remove: O(1)
--//   - Query radius: O(k) where k = entities in nearby cells
--//
--// Usage:
--//   local grid = SpatialGrid.new(20) -- 20 stud cells
--//   grid:insert("npc1", Vector3.new(10, 0, 10))
--//   local nearby = grid:query(playerPos, 50) -- Find all within 50 studs

local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

--// ============================================================================
--// TYPE DEFINITIONS
--// ============================================================================

export type SpatialGrid = typeof(SpatialGrid.new())

export type GridEntry = {
	id: string,
	position: Vector3,
	data: any?,
}

--// ============================================================================
--// CONSTANTS
--// ============================================================================

local DEFAULT_CELL_SIZE = 20 -- studs
local FLOOR = math.floor

--// ============================================================================
--// CONSTRUCTOR
--// ============================================================================

--// Creates a new SpatialGrid with the specified cell size.
--// Smaller cells = more precise queries but more cells to check.
--// Larger cells = fewer cells but more entities per cell.
--// Recommended: cell size = typical query radius / 2
function SpatialGrid.new(cellSize: number?): SpatialGrid
	local self = setmetatable({}, SpatialGrid)

	self._cellSize = cellSize or DEFAULT_CELL_SIZE
	self._invCellSize = 1 / self._cellSize
	self._cells = {} :: { [string]: { GridEntry } }
	self._entityCells = {} :: { [string]: string } -- entity id -> cell key
	self._entityData = {} :: { [string]: GridEntry } -- entity id -> entry
	self._entityCount = 0

	return self
end

--// ============================================================================
--// CELL HELPERS
--// ============================================================================

--// Converts world position to cell key (string).
--// Using string key for Lua table efficiency.
function SpatialGrid:_getCellKey(x: number, z: number): string
	local cx = FLOOR(x * self._invCellSize)
	local cz = FLOOR(z * self._invCellSize)
	return cx .. "," .. cz
end

--// Converts world position to cell coordinates.
function SpatialGrid:_getCellCoords(x: number, z: number): (number, number)
	return FLOOR(x * self._invCellSize), FLOOR(z * self._invCellSize)
end

--// ============================================================================
--// ENTITY MANAGEMENT
--// ============================================================================

--// Inserts an entity into the grid.
--// If entity already exists, updates its position.
function SpatialGrid:insert(id: string, position: Vector3, data: any?)
	local cellKey = self:_getCellKey(position.X, position.Z)

	-- Remove from old cell if exists
	local oldCellKey = self._entityCells[id]
	if oldCellKey then
		if oldCellKey == cellKey then
			-- Same cell, just update position
			local entry = self._entityData[id]
			if entry then
				entry.position = position
				entry.data = data
			end
			return
		end
		-- Different cell, remove from old
		self:_removeFromCell(id, oldCellKey)
	else
		self._entityCount += 1
	end

	-- Add to new cell
	local cell = self._cells[cellKey]
	if not cell then
		cell = {}
		self._cells[cellKey] = cell
	end

	local entry: GridEntry = {
		id = id,
		position = position,
		data = data,
	}

	table.insert(cell, entry)
	self._entityCells[id] = cellKey
	self._entityData[id] = entry
end

--// Updates an entity's position (alias for insert).
function SpatialGrid:update(id: string, position: Vector3, data: any?)
	self:insert(id, position, data)
end

--// Removes an entity from the grid.
function SpatialGrid:remove(id: string): boolean
	local cellKey = self._entityCells[id]
	if not cellKey then
		return false
	end

	self:_removeFromCell(id, cellKey)
	self._entityCells[id] = nil
	self._entityData[id] = nil
	self._entityCount -= 1
	return true
end

--// Internal: removes entity from a specific cell.
function SpatialGrid:_removeFromCell(id: string, cellKey: string)
	local cell = self._cells[cellKey]
	if not cell then
		return
	end

	for i = #cell, 1, -1 do
		if cell[i].id == id then
			-- Swap with last for O(1) removal
			local lastIdx = #cell
			if i ~= lastIdx then
				cell[i] = cell[lastIdx]
			end
			cell[lastIdx] = nil
			break
		end
	end

	-- Clean up empty cells
	if #cell == 0 then
		self._cells[cellKey] = nil
	end
end

--// Clears all entities from the grid.
function SpatialGrid:clear()
	table.clear(self._cells)
	table.clear(self._entityCells)
	table.clear(self._entityData)
	self._entityCount = 0
end

--// ============================================================================
--// QUERIES
--// ============================================================================

--// Finds all entities within radius of a position.
--// Returns array of GridEntry.
function SpatialGrid:query(position: Vector3, radius: number): { GridEntry }
	local results = {}
	self:queryTo(position, radius, results)
	return results
end

--// Optimized version that fills an existing table.
function SpatialGrid:queryTo(position: Vector3, radius: number, results: { GridEntry })
	local radiusSq = radius * radius
	local px, pz = position.X, position.Z

	-- Calculate cell range to check
	local cellRange = math.ceil(radius * self._invCellSize)
	local centerCx, centerCz = self:_getCellCoords(px, pz)

	-- Check all cells in range
	for dx = -cellRange, cellRange do
		for dz = -cellRange, cellRange do
			local cx = centerCx + dx
			local cz = centerCz + dz
			local cellKey = cx .. "," .. cz
			local cell = self._cells[cellKey]

			if cell then
				for _, entry in cell do
					local ex, ez = entry.position.X, entry.position.Z
					local distX, distZ = ex - px, ez - pz
					local distSq = distX * distX + distZ * distZ

					if distSq <= radiusSq then
						table.insert(results, entry)
					end
				end
			end
		end
	end
end

--// Finds the nearest entity to a position within max radius.
--// Returns (entry, distanceSq) or (nil, math.huge).
function SpatialGrid:queryNearest(position: Vector3, maxRadius: number): (GridEntry?, number)
	local nearestEntry: GridEntry? = nil
	local nearestDistSq = maxRadius * maxRadius
	local px, pz = position.X, position.Z

	-- Start with just the center cell, expand if needed
	local cellRange = math.ceil(maxRadius * self._invCellSize)
	local centerCx, centerCz = self:_getCellCoords(px, pz)

	-- Check cells in expanding rings for early exit
	for ring = 0, cellRange do
		for dx = -ring, ring do
			for dz = -ring, ring do
				-- Only check perimeter of ring (optimization)
				if ring > 0 and math.abs(dx) < ring and math.abs(dz) < ring then
					continue
				end

				local cx = centerCx + dx
				local cz = centerCz + dz
				local cellKey = cx .. "," .. cz
				local cell = self._cells[cellKey]

				if cell then
					for _, entry in cell do
						local ex, ez = entry.position.X, entry.position.Z
						local distX, distZ = ex - px, ez - pz
						local distSq = distX * distX + distZ * distZ

						if distSq < nearestDistSq then
							nearestDistSq = distSq
							nearestEntry = entry
						end
					end
				end
			end
		end

		-- If we found something in inner rings and checked enough cells, we can stop
		if nearestEntry and ring > 0 then
			-- Check if nearest could possibly be in outer rings
			local minPossibleDist = (ring - 1) * self._cellSize
			if nearestDistSq < minPossibleDist * minPossibleDist then
				break
			end
		end
	end

	return nearestEntry, nearestDistSq
end

--// Counts entities within radius (without allocating results array).
function SpatialGrid:queryCount(position: Vector3, radius: number): number
	local count = 0
	local radiusSq = radius * radius
	local px, pz = position.X, position.Z

	local cellRange = math.ceil(radius * self._invCellSize)
	local centerCx, centerCz = self:_getCellCoords(px, pz)

	for dx = -cellRange, cellRange do
		for dz = -cellRange, cellRange do
			local cx = centerCx + dx
			local cz = centerCz + dz
			local cellKey = cx .. "," .. cz
			local cell = self._cells[cellKey]

			if cell then
				for _, entry in cell do
					local ex, ez = entry.position.X, entry.position.Z
					local distX, distZ = ex - px, ez - pz
					local distSq = distX * distX + distZ * distZ

					if distSq <= radiusSq then
						count += 1
					end
				end
			end
		end
	end

	return count
end

--// Checks if any entity exists within radius.
function SpatialGrid:hasAny(position: Vector3, radius: number): boolean
	local radiusSq = radius * radius
	local px, pz = position.X, position.Z

	local cellRange = math.ceil(radius * self._invCellSize)
	local centerCx, centerCz = self:_getCellCoords(px, pz)

	for dx = -cellRange, cellRange do
		for dz = -cellRange, cellRange do
			local cx = centerCx + dx
			local cz = centerCz + dz
			local cellKey = cx .. "," .. cz
			local cell = self._cells[cellKey]

			if cell then
				for _, entry in cell do
					local ex, ez = entry.position.X, entry.position.Z
					local distX, distZ = ex - px, ez - pz
					local distSq = distX * distX + distZ * distZ

					if distSq <= radiusSq then
						return true
					end
				end
			end
		end
	end

	return false
end

--// Iterates over all entities in the grid.
--// Callback receives (id, position, data).
function SpatialGrid:forEach(callback: (string, Vector3, any?) -> ())
	for _, entry in self._entityData do
		callback(entry.id, entry.position, entry.data)
	end
end

--// ============================================================================
--// STATISTICS
--// ============================================================================

--// Gets the number of entities in the grid.
function SpatialGrid:getCount(): number
	return self._entityCount
end

--// Gets the number of non-empty cells.
function SpatialGrid:getCellCount(): number
	local count = 0
	for _ in self._cells do
		count += 1
	end
	return count
end

--// Gets the cell size.
function SpatialGrid:getCellSize(): number
	return self._cellSize
end

--// Gets grid statistics for debugging.
function SpatialGrid:getStats(): { entities: number, cells: number, avgPerCell: number, cellSize: number }
	local cellCount = self:getCellCount()
	return {
		entities = self._entityCount,
		cells = cellCount,
		avgPerCell = if cellCount > 0 then self._entityCount / cellCount else 0,
		cellSize = self._cellSize,
	}
end

--// ============================================================================
--// DEBUG
--// ============================================================================

function SpatialGrid:__tostring(): string
	local stats = self:getStats()
	return string.format(
		"SpatialGrid{entities=%d, cells=%d, avgPerCell=%.1f, cellSize=%d}",
		stats.entities,
		stats.cells,
		stats.avgPerCell,
		stats.cellSize
	)
end

return SpatialGrid
