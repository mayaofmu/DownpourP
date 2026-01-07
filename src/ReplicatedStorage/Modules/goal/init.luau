--!strict
--// Goal - Universal GOAP (Goal-Oriented Action Planning) System
--// A flexible AI planning library for Roblox with parallel execution support.

local Goal = {}

--// ============================================================================
--// CORE MODULE IMPORTS
--// ============================================================================

local StateModule = require(script.State)
local GoalModule = require(script.Goal)
local ActionModule = require(script.Action)
local ActionSequenceModule = require(script.ActionSequence)
local PlannerModule = require(script.Planner)
local UtilitiesModule = require(script.Utilities)
local LoggerModule = require(script.Logger)

--// ============================================================================
--// SUBFOLDER MODULE IMPORTS
--// ============================================================================

--// AI (Utility AI systems)
local AIModule = require(script.AI)

--// Navigation (Pathfinding and tactical positioning)
local NavigationModule = require(script.Navigation)

--// HTN (Hierarchical Task Network)
local HTNModule = require(script.HTN)

--// Actor (Parallel execution - lazy-loaded)
local ActorModule: typeof(require(script.Actor))? = nil

local function loadActorModules()
	if not ActorModule then
		ActorModule = require(script.Actor)
	end
end

--// ============================================================================
--// TYPE EXPORTS
--// ============================================================================

--// Core Types
export type State = StateModule.State
export type GoalType = GoalModule.Goal
export type Action = ActionModule.Action
export type ActionSequence = ActionSequenceModule.ActionSequence
export type Planner = PlannerModule.Planner
export type PlanResult = PlannerModule.PlanResult
export type ProfilingData = PlannerModule.ProfilingData
export type PriorityQueue = UtilitiesModule.PriorityQueue
export type LogLevel = LoggerModule.LogLevel
export type ScopedLogger = LoggerModule.ScopedLogger

--// AI Types
export type Consideration = AIModule.Consideration
export type Memory = AIModule.Memory
export type Blackboard = AIModule.Blackboard
export type Perception = AIModule.Perception
export type Personality = AIModule.Personality

--// Navigation Types
export type Navigation = NavigationModule.Navigation
export type NavigationGrid = NavigationModule.NavigationGrid
export type PathResult = NavigationModule.PathResult
export type CoverPoint = NavigationModule.CoverPoint
export type TacticalPosition = NavigationModule.TacticalPosition
export type PathfindingAdapter = NavigationModule.PathfindingAdapter
export type SpatialGrid = NavigationModule.SpatialGrid

--// HTN Types
export type Task = HTNModule.Task
export type TaskType = HTNModule.TaskType
export type Method = HTNModule.Method
export type HTNDomain = HTNModule.HTNDomain
export type HTNPlanner = HTNModule.HTNPlanner
export type HTNPlanResult = HTNModule.HTNPlanResult

--// ============================================================================
--// CORE MODULE EXPORTS
--// ============================================================================

Goal.State = StateModule
Goal.Goal = GoalModule
Goal.Action = ActionModule
Goal.ActionSequence = ActionSequenceModule
Goal.Planner = PlannerModule
Goal.Utilities = UtilitiesModule
Goal.Logger = LoggerModule

--// ============================================================================
--// AI MODULE EXPORTS (Utility AI)
--// ============================================================================

Goal.AI = AIModule
Goal.Consideration = AIModule.Consideration
Goal.Memory = AIModule.Memory
Goal.Blackboard = AIModule.Blackboard
Goal.Perception = AIModule.Perception
Goal.Personality = AIModule.Personality

--// ============================================================================
--// NAVIGATION MODULE EXPORTS
--// ============================================================================

Goal.Navigation = NavigationModule.Navigation
Goal.NavigationGrid = NavigationModule.Grid
Goal.PathfindingAdapter = NavigationModule.PathfindingAdapter
Goal.SpatialGrid = NavigationModule.SpatialGrid

--// ============================================================================
--// HTN MODULE EXPORTS
--// ============================================================================

Goal.HTN = HTNModule
Goal.Task = HTNModule.Task
Goal.Method = HTNModule.Method
Goal.HTNDomain = HTNModule.Domain
Goal.HTNPlanner = HTNModule.Planner

--// ============================================================================
--// ACTOR MODULE EXPORTS (lazy-loaded via __index)
--// ============================================================================

setmetatable(Goal, {
	__index = function(_self, key)
		if key == "Actor" then
			loadActorModules()
			return ActorModule
		elseif key == "SharedBlackboard" then
			loadActorModules()
			return ActorModule and ActorModule.SharedBlackboard
		elseif key == "ActorPool" then
			loadActorModules()
			return ActorModule and ActorModule.ActorPool
		elseif key == "NPCScheduler" then
			loadActorModules()
			return ActorModule and ActorModule.NPCScheduler
		end
		return nil
	end,
})

--// ============================================================================
--// VERSION
--// ============================================================================

Goal.VERSION = "1.5.0"

--// ============================================================================
--// FACTORY FUNCTIONS
--// ============================================================================

export type SetupConfig = {
	initialState: { [string]: any }?,
	actions: { { [string]: any } }?,
	plannerConfig: PlannerModule.PlannerConfig?,
}

--// Creates a planner and state in one call.
function Goal.createSetup(config: SetupConfig?): (Planner, State)
	local cfg = config or {}
	local planner = PlannerModule.new(cfg.plannerConfig)
	local state = StateModule.new(cfg.initialState)

	if cfg.actions then
		for _, actionConfig in cfg.actions do
			planner:registerAction(ActionModule.new(actionConfig))
		end
	end

	return planner, state
end

export type SequenceOptions = {
	failureStrategy: ("abort" | "skip" | "retry")?,
	maxRetries: number?,
	onStepComplete: ((number, boolean) -> ())?,
	onSequenceComplete: ((boolean) -> ())?,
	onInterrupt: (() -> ())?,
	interruptible: boolean?,
}

--// Creates an action sequence with a clean API.
function Goal.createActionSequence(name: string, actions: { any }, options: SequenceOptions?): ActionSequence
	assert(type(name) == "string" and #name > 0, "[Goal] name must be a non-empty string")
	assert(type(actions) == "table", "[Goal] actions must be a table")

	local opts = options or {}
	return ActionSequenceModule.new({
		name = name,
		actions = actions,
		failureStrategy = opts.failureStrategy,
		maxRetries = opts.maxRetries,
		onStepComplete = opts.onStepComplete,
		onSequenceComplete = opts.onSequenceComplete,
		onInterrupt = opts.onInterrupt,
		interruptible = opts.interruptible,
	})
end

export type PerformancePlannerConfig = {
	maxIterations: number?,
	maxPlanLength: number?,
	priorityThreshold: number?,
	maxEvaluationsPerTick: number?,
	cacheTTL: number?,
	enableProfiling: boolean?,
}

--// Creates a planner optimized for many NPCs.
function Goal.createPerformancePlanner(config: PerformancePlannerConfig?): Planner
	local cfg = config or {}
	return PlannerModule.new({
		maxIterations = cfg.maxIterations or 500,
		maxPlanLength = cfg.maxPlanLength or 10,
		performanceMode = true,
		priorityThreshold = cfg.priorityThreshold or 0,
		maxEvaluationsPerTick = cfg.maxEvaluationsPerTick or 10,
		cacheTTL = cfg.cacheTTL or 0.5,
		enableProfiling = cfg.enableProfiling or false,
	})
end

--// ============================================================================
--// FORMATTING UTILITIES
--// ============================================================================

--// Formats a plan for debug output.
function Goal.formatPlan(plan: PlanResult): string
	if not plan.success then
		return string.format("Plan FAILED (iterations: %d)", plan.iterations)
	end

	local lines = {
		string.format("Plan SUCCESS (cost: %.2f, iterations: %d)", plan.totalCost, plan.iterations),
		"Actions:",
	}

	for i, action in plan.actions do
		table.insert(lines, string.format("  %d. %s", i, action:getName()))
	end

	if #plan.actions == 0 then
		table.insert(lines, "  (goal already satisfied)")
	end

	return table.concat(lines, "\n")
end

--// Formats profiling data for debug output.
function Goal.formatProfiling(data: ProfilingData): string
	return table.concat({
		"=== Profiling ===",
		string.format("Plans: %d", data.planCount),
		string.format("Total: %.4fs", data.totalPlanTime),
		string.format("Avg: %.4fs", data.averagePlanTime),
		string.format("Last: %.4fs", data.lastPlanTime),
		string.format("Evals: %d", data.totalEvaluations),
	}, "\n")
end

--// Formats a state for debug output.
function Goal.formatState(state: State): string
	local lines = { "State:" }
	local data = state:getData()
	local keys = {}

	for key in data do
		table.insert(keys, key)
	end
	table.sort(keys)

	for _, key in keys do
		table.insert(lines, string.format("  %s = %s", key, tostring(data[key])))
	end

	if #keys == 0 then
		table.insert(lines, "  (empty)")
	end

	return table.concat(lines, "\n")
end

--// Formats an action for debug output.
function Goal.formatAction(action: Action): string
	local lines = {
		string.format("Action: %s (cost: %s)", action:getName(), tostring(action.baseCost)),
		"  Preconditions:",
	}

	local hasPrec = false
	for key, value in action:getPreconditions():pairs() do
		table.insert(lines, string.format("    %s = %s", key, tostring(value)))
		hasPrec = true
	end
	if not hasPrec then
		table.insert(lines, "    (none)")
	end

	table.insert(lines, "  Effects:")
	local hasEffects = false
	for key, value in action:getEffects():pairs() do
		table.insert(lines, string.format("    %s = %s", key, tostring(value)))
		hasEffects = true
	end
	if not hasEffects then
		table.insert(lines, "    (none)")
	end

	return table.concat(lines, "\n")
end

--// ============================================================================
--// DEBUG SUMMARY
--// ============================================================================

--// Returns module status summary.
function Goal.debugSummary(): string
	local coreModules = { "State", "Goal", "Action", "ActionSequence", "Planner", "Utilities", "Logger" }
	local aiModules = { "Consideration", "Memory", "Blackboard", "Perception", "Personality" }
	local navModules = { "Navigation", "NavigationGrid", "PathfindingAdapter", "SpatialGrid" }
	local htnModules = { "Task", "Method", "HTNDomain", "HTNPlanner" }
	local actorModules = { "SharedBlackboard", "ActorPool", "NPCScheduler" }

	local lines = { string.format("Goal v%s", Goal.VERSION), "", "Core:" }
	for _, name in coreModules do
		table.insert(lines, string.format("  %s: OK", name))
	end

	table.insert(lines, "")
	table.insert(lines, "AI (src/AI/):")
	for _, name in aiModules do
		table.insert(lines, string.format("  %s: OK", name))
	end

	table.insert(lines, "")
	table.insert(lines, "Navigation (src/Navigation/):")
	for _, name in navModules do
		table.insert(lines, string.format("  %s: OK", name))
	end

	table.insert(lines, "")
	table.insert(lines, "HTN (src/HTN/):")
	for _, name in htnModules do
		table.insert(lines, string.format("  %s: OK", name))
	end

	table.insert(lines, "")
	table.insert(lines, "Actor (src/Actor/ - lazy):")
	for _, name in actorModules do
		table.insert(lines, string.format("  %s: %s", name, if ActorModule then "OK" else "NOT_LOADED"))
	end

	return table.concat(lines, "\n")
end

return Goal
