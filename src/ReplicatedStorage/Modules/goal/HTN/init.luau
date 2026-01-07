--!strict
--[[
	HTN (Hierarchical Task Network) Module

	Provides hierarchical task planning capabilities alongside GOAP.
	HTN excels at structured, procedural behaviors while GOAP handles
	emergent, goal-driven decision-making.
]]

local Task = require(script.Task)
local Method = require(script.Method)
local HTNDomain = require(script.HTNDomain)
local HTNPlanner = require(script.HTNPlanner)

--// Type Exports
export type Task = Task.Task
export type TaskType = Task.TaskType
export type Method = Method.Method
export type HTNDomain = HTNDomain.HTNDomain
export type HTNPlanner = HTNPlanner.HTNPlanner
export type HTNPlanResult = HTNPlanner.HTNPlanResult

return {
	Task = Task,
	Method = Method,
	Domain = HTNDomain,
	Planner = HTNPlanner,
}
