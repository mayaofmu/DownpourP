--!strict
--[[
	HTNPlanner.lua
	Hierarchical Task Network planner with depth-first decomposition.

	The HTN planner decomposes high-level compound tasks into sequences of
	primitive actions. It uses depth-first search with optional backtracking
	to find valid decompositions.

	┌─────────────────────────────────────────────────────────────────────────┐
	│                       HTN PLANNING ALGORITHM                            │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│    Input: Root Task "ClearRoom", World State { hasAmmo: false }         │
	│                                                                         │
	│    Step 1: Push root task onto stack                                    │
	│    ┌─────────────────────────────────────────────────────────────────┐  │
	│    │ Stack: [ ClearRoom ]                 Plan: [ ]                  │  │
	│    └─────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	│    Step 2: Pop ClearRoom (compound), select method, push subtasks       │
	│    ┌─────────────────────────────────────────────────────────────────┐  │
	│    │ Stack: [ ScanArea, EngageEnemy ]     Plan: [ ]                  │  │
	│    └─────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	│    Step 3: Pop ScanArea (primitive), add action to plan                 │
	│    ┌─────────────────────────────────────────────────────────────────┐  │
	│    │ Stack: [ EngageEnemy ]               Plan: [ Look ]             │  │
	│    └─────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	│    Step 4: Pop EngageEnemy (compound), select method based on state     │
	│            hasAmmo=false → select "ReloadFirst" method                  │
	│    ┌─────────────────────────────────────────────────────────────────┐  │
	│    │ Stack: [ Reload, Shoot ]             Plan: [ Look ]             │  │
	│    └─────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	│    Step 5: Pop Reload (primitive), add action, update simulated state   │
	│    ┌─────────────────────────────────────────────────────────────────┐  │
	│    │ Stack: [ Shoot ]                     Plan: [ Look, Reload ]     │  │
	│    │ Simulated State: { hasAmmo: true }                              │  │
	│    └─────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	│    Step 6: Pop Shoot (primitive), add action                            │
	│    ┌─────────────────────────────────────────────────────────────────┐  │
	│    │ Stack: [ ]                           Plan: [ Look, Reload, Shoot]│ │
	│    └─────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	│    Result: SUCCESS - Plan contains 3 actions                            │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          API QUICK REFERENCE                            │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│  CONSTRUCTOR                                                            │
	│    HTNPlanner.new(config)           Create planner with domain          │
	│                                                                         │
	│  PLANNING                                                               │
	│    :plan(rootTask, startState)      Generate plan from root task        │
	│    :planWithAgent(root, state, agent, context)  Plan with agent context │
	│                                                                         │
	│  EXECUTION                                                              │
	│    :executePlan(plan, agent?, ctx?) Execute plan actions sequentially   │
	│    :executeStep(plan, step, agent?) Execute single plan step            │
	│                                                                         │
	│  CONFIGURATION                                                          │
	│    :setMaxDepth(depth)              Set max decomposition depth         │
	│    :setMaxIterations(iters)         Set max planning iterations         │
	│    :setBacktracking(enabled)        Enable/disable backtracking         │
	│    :setGOAPFallback(enabled, planner?) Enable GOAP fallback             │
	│                                                                         │
	│  DOMAIN                                                                 │
	│    :getDomain()                     Get associated domain               │
	│    :setDomain(domain)               Change domain                       │
	│                                                                         │
	│  DEBUGGING                                                              │
	│    :debugSummary()                  Get planner configuration           │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class HTNPlanner
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Basic Usage

	```lua
	local domain = HTNDomain.new({ name = "Combat" })
	-- ... register tasks ...

	local planner = HTNPlanner.new({
		domain = domain,
		maxDepth = 20,
		enableBacktracking = true,
	})

	local worldState = State.new({ hasAmmo = false, targetVisible = true })
	local plan = planner:plan("EngageEnemy", worldState)

	if plan.success then
		for i, action in plan.actions do
			print(i, action:getName())
		end
	end
	```

	## With GOAP Fallback

	```lua
	local planner = HTNPlanner.new({
		domain = domain,
		enableGOAPFallback = true,
		goapPlanner = myGOAPPlanner,
	})
	```
]]

local Action = require(script.Parent.Parent.Action)
local State = require(script.Parent.Parent.State)
local Task = require(script.Parent.Task)
local HTNDomain = require(script.Parent.HTNDomain)

--// ============================================================================
--// TYPE DEFINITIONS
--// ============================================================================

--// Forward declaration for GOAP Planner
export type GOAPPlannerLike = {
	plan: (self: GOAPPlannerLike, startState: State.State, goal: any, agent: any?, context: any?) -> any,
}

--// Configuration for creating an HTN planner
export type HTNPlannerConfig = {
	domain: HTNDomain.HTNDomain,
	maxDepth: number?,
	maxIterations: number?,
	enableBacktracking: boolean?,
	enableGOAPFallback: boolean?,
	goapPlanner: GOAPPlannerLike?,
	enableProfiling: boolean?,
}

--// Result of HTN planning
export type HTNPlanResult = {
	actions: { Action.Action },
	success: boolean,
	iterations: number,
	decompositionDepth: number,
	totalCost: number,
	failureReason: string?,
	failedTask: string?,
}

--// Internal decomposition frame for backtracking
type DecompositionFrame = {
	task: Task.Task,
	methodIndex: number,
	validMethods: { Task.MethodLike },
	state: State.State,
	planIndex: number,
}

--// ============================================================================
--// CONSTANTS
--// ============================================================================

local LOG_PREFIX = "[Goal.HTNPlanner]"
local DEFAULT_MAX_DEPTH = 20
local DEFAULT_MAX_ITERATIONS = 1000

--// ============================================================================
--// CLASS DEFINITION
--// ============================================================================

local HTNPlanner = {}
HTNPlanner.__index = HTNPlanner

--// ============================================================================
--// CONSTRUCTOR
--// ============================================================================

--[[
	Creates a new HTN planner.

	@param config HTNPlannerConfig -- Configuration with domain and options
	@return HTNPlanner -- New planner
]]
function HTNPlanner.new(config: HTNPlannerConfig): HTNPlanner
	assert(config.domain, LOG_PREFIX .. " HTNPlanner requires a domain")

	local self = setmetatable({}, HTNPlanner)

	self._domain = config.domain
	self._maxDepth = config.maxDepth or DEFAULT_MAX_DEPTH
	self._maxIterations = config.maxIterations or DEFAULT_MAX_ITERATIONS
	self._enableBacktracking = if config.enableBacktracking ~= nil then config.enableBacktracking else true
	self._enableGOAPFallback = config.enableGOAPFallback or false
	self._goapPlanner = config.goapPlanner
	self._enableProfiling = config.enableProfiling or false

	return self
end

--// ============================================================================
--// PLANNING
--// ============================================================================

--[[
	Plans from a root task to produce a sequence of actions.

	@param rootTask string | Task -- Root task name or Task object
	@param startState State -- Initial world state
	@param agent any? -- Optional agent context
	@param context any? -- Optional execution context
	@return HTNPlanResult -- Planning result
]]
function HTNPlanner:plan(
	rootTask: string | Task.Task,
	startState: State.State,
	agent: any?,
	_context: any?
): HTNPlanResult
	local startTime = if self._enableProfiling then os.clock() else 0

	-- Resolve root task
	local task: Task.Task?
	if type(rootTask) == "string" then
		task = self._domain:getTask(rootTask)
		if not task then
			return {
				actions = {},
				success = false,
				iterations = 0,
				decompositionDepth = 0,
				totalCost = 0,
				failureReason = "unknown_task",
				failedTask = rootTask,
			}
		end
	else
		task = rootTask
	end

	-- Initialize planning state
	local actions: { Action.Action } = {}
	local totalCost = 0
	local iterations = 0
	local maxDepthReached = 0

	-- Task stack for depth-first decomposition
	-- Each entry: { task: Task, depth: number }
	local taskStack: { { task: Task.Task, depth: number } } = {}
	table.insert(taskStack, { task = task, depth = 1 })

	-- Decomposition stack for backtracking
	local decompositionStack: { DecompositionFrame } = {}

	-- Simulated world state (tracks effects as we plan)
	local simulatedState = startState:clone()

	while #taskStack > 0 do
		iterations += 1

		-- Check iteration limit
		if iterations > self._maxIterations then
			return {
				actions = {},
				success = false,
				iterations = iterations,
				decompositionDepth = maxDepthReached,
				totalCost = 0,
				failureReason = "max_iterations",
			}
		end

		-- Pop next task
		local current = table.remove(taskStack)
		if not current then
			break
		end

		local currentTask = current.task
		local currentDepth = current.depth
		maxDepthReached = math.max(maxDepthReached, currentDepth)

		-- Check depth limit
		if currentDepth > self._maxDepth then
			if self._enableBacktracking and #decompositionStack > 0 then
				-- Try backtracking
				local backtrackResult = self:_backtrack(decompositionStack, actions, taskStack)
				if backtrackResult then
					simulatedState = backtrackResult.state
					totalCost = backtrackResult.cost
					continue
				end
			end

			return {
				actions = {},
				success = false,
				iterations = iterations,
				decompositionDepth = maxDepthReached,
				totalCost = 0,
				failureReason = "max_depth",
				failedTask = currentTask:getName(),
			}
		end

		if currentTask:isPrimitive() then
			-- Primitive task: add action to plan
			local action = currentTask:getAction()
			if not action then
				return {
					actions = {},
					success = false,
					iterations = iterations,
					decompositionDepth = maxDepthReached,
					totalCost = 0,
					failureReason = "no_action",
					failedTask = currentTask:getName(),
				}
			end

			-- Check preconditions against simulated state
			if not action:checkPreconditions(simulatedState) then
				if self._enableBacktracking and #decompositionStack > 0 then
					local backtrackResult = self:_backtrack(decompositionStack, actions, taskStack)
					if backtrackResult then
						simulatedState = backtrackResult.state
						totalCost = backtrackResult.cost
						continue
					end
				end

				return {
					actions = {},
					success = false,
					iterations = iterations,
					decompositionDepth = maxDepthReached,
					totalCost = 0,
					failureReason = "precondition_failed",
					failedTask = currentTask:getName(),
				}
			end

			-- Check custom validation
			if not action:isValid(simulatedState, agent) then
				if self._enableBacktracking and #decompositionStack > 0 then
					local backtrackResult = self:_backtrack(decompositionStack, actions, taskStack)
					if backtrackResult then
						simulatedState = backtrackResult.state
						totalCost = backtrackResult.cost
						continue
					end
				end

				return {
					actions = {},
					success = false,
					iterations = iterations,
					decompositionDepth = maxDepthReached,
					totalCost = 0,
					failureReason = "validation_failed",
					failedTask = currentTask:getName(),
				}
			end

			-- Add action to plan
			table.insert(actions, action)
			totalCost += action:getCost(simulatedState, agent)

			-- Apply effects to simulated state
			simulatedState = action:applyEffects(simulatedState)
		else
			-- Compound task: decompose via methods
			local methods = currentTask:getMethods()

			-- Get valid methods
			local validMethods: { Task.MethodLike } = {}
			for _, method in ipairs(methods) do
				if method:checkPreconditions(simulatedState) and method:isValid(simulatedState, agent) then
					table.insert(validMethods, method)
				end
			end

			if #validMethods == 0 then
				-- No valid methods - try GOAP fallback or backtrack
				-- NOTE: GOAP fallback for compound tasks would require defining
				-- a goal state for the compound task. This is a future enhancement.

				if self._enableBacktracking and #decompositionStack > 0 then
					local backtrackResult = self:_backtrack(decompositionStack, actions, taskStack)
					if backtrackResult then
						simulatedState = backtrackResult.state
						totalCost = backtrackResult.cost
						continue
					end
				end

				return {
					actions = {},
					success = false,
					iterations = iterations,
					decompositionDepth = maxDepthReached,
					totalCost = 0,
					failureReason = "no_valid_method",
					failedTask = currentTask:getName(),
				}
			end

			-- Sort by cost (lowest first)
			table.sort(validMethods, function(a, b)
				return a:getCost() < b:getCost()
			end)

			-- Select first (lowest cost) method
			local selectedMethod = validMethods[1]

			-- Save decomposition frame for backtracking
			if self._enableBacktracking and #validMethods > 1 then
				table.insert(decompositionStack, {
					task = currentTask,
					methodIndex = 1,
					validMethods = validMethods,
					state = simulatedState:clone(),
					planIndex = #actions,
				})
			end

			-- Push subtasks in REVERSE order (so first subtask is processed first)
			local subtasks = selectedMethod:getSubtasks()
			for i = #subtasks, 1, -1 do
				local subtaskName = subtasks[i]
				local subtask = self._domain:getTask(subtaskName)
				if not subtask then
					return {
						actions = {},
						success = false,
						iterations = iterations,
						decompositionDepth = maxDepthReached,
						totalCost = 0,
						failureReason = "unknown_subtask",
						failedTask = subtaskName,
					}
				end
				table.insert(taskStack, { task = subtask, depth = currentDepth + 1 })
			end
		end
	end

	-- Success!
	if self._enableProfiling then
		local elapsed = os.clock() - startTime
		print(
			string.format(
				"%s Plan completed in %.4fs, %d iterations, depth %d",
				LOG_PREFIX,
				elapsed,
				iterations,
				maxDepthReached
			)
		)
	end

	return {
		actions = actions,
		success = true,
		iterations = iterations,
		decompositionDepth = maxDepthReached,
		totalCost = totalCost,
	}
end

--[[
	Attempts to backtrack and try an alternate method.

	@param decompositionStack { DecompositionFrame } -- Stack of decomposition frames
	@param actions { Action } -- Current action plan (will be trimmed)
	@param taskStack { { task, depth } } -- Task stack (will be cleared and rebuilt)
	@return { state: State, cost: number }? -- New state/cost if backtrack succeeded
]]
function HTNPlanner:_backtrack(
	decompositionStack: { DecompositionFrame },
	actions: { Action.Action },
	taskStack: { { task: Task.Task, depth: number } }
): { state: State.State, cost: number }?
	while #decompositionStack > 0 do
		local frame = decompositionStack[#decompositionStack]

		-- Try next method
		frame.methodIndex += 1

		if frame.methodIndex <= #frame.validMethods then
			-- Found alternate method - restore state and rebuild
			local method = frame.validMethods[frame.methodIndex]

			-- Trim actions back to where we were
			while #actions > frame.planIndex do
				table.remove(actions)
			end

			-- Clear task stack
			for i = #taskStack, 1, -1 do
				table.remove(taskStack, i)
			end

			-- Push subtasks for new method
			local subtasks = method:getSubtasks()
			for i = #subtasks, 1, -1 do
				local subtaskName = subtasks[i]
				local subtask = self._domain:getTask(subtaskName)
				if subtask then
					table.insert(taskStack, { task = subtask, depth = 1 })
				end
			end

			-- Recalculate cost
			local newCost = 0
			for _, action in ipairs(actions) do
				newCost += action:getCost()
			end

			return { state = frame.state:clone(), cost = newCost }
		else
			-- No more methods at this level, pop and continue backtracking
			table.remove(decompositionStack)
		end
	end

	return nil
end

--// ============================================================================
--// EXECUTION
--// ============================================================================

--[[
	Executes a plan's actions sequentially.

	@param plan HTNPlanResult -- Plan to execute
	@param agent any? -- Optional agent context
	@param context any? -- Optional execution context
	@return (boolean, number) -- (success, completedCount)
]]
function HTNPlanner:executePlan(plan: HTNPlanResult, agent: any?, context: any?): (boolean, number)
	if not plan.success then
		return false, 0
	end

	local completed = 0

	for _, action in ipairs(plan.actions) do
		local success = action:execute(agent, context)
		if not success then
			return false, completed
		end
		completed += 1
	end

	return true, completed
end

--[[
	Executes a single step of a plan.

	@param plan HTNPlanResult -- Plan containing actions
	@param step number -- Step index (1-based)
	@param agent any? -- Optional agent context
	@param context any? -- Optional execution context
	@return boolean -- True if step executed successfully
]]
function HTNPlanner:executeStep(plan: HTNPlanResult, step: number, agent: any?, context: any?): boolean
	if not plan.success then
		return false
	end

	if step < 1 or step > #plan.actions then
		return false
	end

	local action = plan.actions[step]
	return action:execute(agent, context)
end

--// ============================================================================
--// CONFIGURATION
--// ============================================================================

--[[
	Sets the maximum decomposition depth.

	@param depth number -- Max depth (default: 20)
]]
function HTNPlanner:setMaxDepth(depth: number): ()
	self._maxDepth = depth
end

--[[
	Gets the maximum decomposition depth.

	@return number -- Max depth
]]
function HTNPlanner:getMaxDepth(): number
	return self._maxDepth
end

--[[
	Sets the maximum planning iterations.

	@param iterations number -- Max iterations (default: 1000)
]]
function HTNPlanner:setMaxIterations(iterations: number): ()
	self._maxIterations = iterations
end

--[[
	Gets the maximum planning iterations.

	@return number -- Max iterations
]]
function HTNPlanner:getMaxIterations(): number
	return self._maxIterations
end

--[[
	Enables or disables backtracking.

	@param enabled boolean -- Whether to enable backtracking
]]
function HTNPlanner:setBacktracking(enabled: boolean): ()
	self._enableBacktracking = enabled
end

--[[
	Checks if backtracking is enabled.

	@return boolean -- True if backtracking enabled
]]
function HTNPlanner:isBacktrackingEnabled(): boolean
	return self._enableBacktracking
end

--[[
	Enables or disables GOAP fallback.

	@param enabled boolean -- Whether to enable GOAP fallback
	@param goapPlanner GOAPPlannerLike? -- GOAP planner to use (required if enabled)
]]
function HTNPlanner:setGOAPFallback(enabled: boolean, goapPlanner: GOAPPlannerLike?): ()
	self._enableGOAPFallback = enabled
	if goapPlanner then
		self._goapPlanner = goapPlanner
	end
end

--[[
	Checks if GOAP fallback is enabled.

	@return boolean -- True if GOAP fallback enabled
]]
function HTNPlanner:isGOAPFallbackEnabled(): boolean
	return self._enableGOAPFallback
end

--[[
	Enables or disables profiling output.

	@param enabled boolean -- Whether to enable profiling
]]
function HTNPlanner:setProfiling(enabled: boolean): ()
	self._enableProfiling = enabled
end

--// ============================================================================
--// DOMAIN
--// ============================================================================

--[[
	Gets the associated domain.

	@return HTNDomain -- The domain
]]
function HTNPlanner:getDomain(): HTNDomain.HTNDomain
	return self._domain
end

--[[
	Sets a new domain.

	@param domain HTNDomain -- New domain to use
]]
function HTNPlanner:setDomain(domain: HTNDomain.HTNDomain): ()
	self._domain = domain
end

--// ============================================================================
--// DEBUGGING
--// ============================================================================

--[[
	Gets a human-readable summary of planner configuration.

	@return string -- Debug summary
]]
function HTNPlanner:debugSummary(): string
	local lines: { string } = {}

	table.insert(lines, "HTNPlanner Configuration:")
	table.insert(lines, string.format("  Domain: %s", self._domain:getName()))
	table.insert(lines, string.format("  Max Depth: %d", self._maxDepth))
	table.insert(lines, string.format("  Max Iterations: %d", self._maxIterations))
	table.insert(lines, string.format("  Backtracking: %s", tostring(self._enableBacktracking)))
	table.insert(lines, string.format("  GOAP Fallback: %s", tostring(self._enableGOAPFallback)))
	table.insert(lines, string.format("  Profiling: %s", tostring(self._enableProfiling)))

	return table.concat(lines, "\n")
end

--[[
	Formats a plan result for debugging.

	@param plan HTNPlanResult -- Plan to format
	@return string -- Formatted plan
]]
function HTNPlanner.formatPlan(plan: HTNPlanResult): string
	local lines: { string } = {}

	if plan.success then
		table.insert(lines, "HTN Plan: SUCCESS")
		table.insert(lines, string.format("  Actions: %d", #plan.actions))
		table.insert(lines, string.format("  Total Cost: %.2f", plan.totalCost))
		table.insert(lines, string.format("  Iterations: %d", plan.iterations))
		table.insert(lines, string.format("  Max Depth: %d", plan.decompositionDepth))
		table.insert(lines, "\n  Action Sequence:")
		for i, action in ipairs(plan.actions) do
			table.insert(lines, string.format("    %d. %s", i, action:getName()))
		end
	else
		table.insert(lines, "HTN Plan: FAILED")
		table.insert(lines, string.format("  Reason: %s", plan.failureReason or "unknown"))
		if plan.failedTask then
			table.insert(lines, string.format("  Failed Task: %s", plan.failedTask))
		end
		table.insert(lines, string.format("  Iterations: %d", plan.iterations))
	end

	return table.concat(lines, "\n")
end

--// ============================================================================
--// TYPE EXPORT
--// ============================================================================

export type HTNPlanner = typeof(HTNPlanner.new({
	domain = HTNDomain.new({ name = "" }),
}))

return HTNPlanner
