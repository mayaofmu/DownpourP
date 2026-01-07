--!strict
--[[
	AI Module

	Provides utility AI and behavioral systems:
	- Consideration: Response curves for utility-based decisions
	- Memory: Three-tier cognitive memory (working/episodic/semantic)
	- Blackboard: Shared knowledge repository for coordination
	- Perception: Vision, hearing, and awareness systems
	- Personality: Trait-based behavioral variation
]]

local Consideration = require(script.Consideration)
local Memory = require(script.Memory)
local Blackboard = require(script.Blackboard)
local Perception = require(script.Perception)
local Personality = require(script.Personality)

--// Type Exports
export type Consideration = Consideration.Consideration
export type Memory = Memory.Memory
export type Blackboard = Blackboard.Blackboard
export type Perception = Perception.Perception
export type Personality = Personality.Personality

return {
	Consideration = Consideration,
	Memory = Memory,
	Blackboard = Blackboard,
	Perception = Perception,
	Personality = Personality,
}
