--!strict
--[[
	Actor Module

	Provides parallel execution and multi-NPC management:
	- SharedBlackboard: Cross-actor shared state for coordination
	- ActorPool: Pool management for parallel actors
	- NPCScheduler: Tick-budgeted NPC update scheduling
]]

local SharedBlackboard = require(script.SharedBlackboard)
local ActorPool = require(script.ActorPool)
local NPCScheduler = require(script.NPCScheduler)

return {
	SharedBlackboard = SharedBlackboard,
	ActorPool = ActorPool,
	NPCScheduler = NPCScheduler,
}
