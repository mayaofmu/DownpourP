--!strict
--[[
	Navigation Module

	Provides tactical pathfinding and positioning systems:
	- A* pathfinding with obstacle avoidance
	- Cover point evaluation and selection
	- Tactical positioning (flanking, high ground)
	- Grid-based spatial queries
]]

local Navigation = require(script.Navigation)
local NavigationGrid = require(script.NavigationGrid)
local PathfindingAdapter = require(script.PathfindingAdapter)
local SpatialGrid = require(script.SpatialGrid)

--// Type Exports
export type Navigation = Navigation.Navigation
export type NavigationGrid = NavigationGrid.NavigationGrid
export type PathResult = Navigation.PathResult
export type CoverPoint = Navigation.CoverPoint
export type TacticalPosition = Navigation.TacticalPosition
export type PathfindingAdapter = PathfindingAdapter.PathfindingAdapter
export type SpatialGrid = SpatialGrid.SpatialGrid

return {
	Navigation = Navigation,
	Grid = NavigationGrid,
	PathfindingAdapter = PathfindingAdapter,
	SpatialGrid = SpatialGrid,
}
