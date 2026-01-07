--!strict
--// Planner.lua
--// Core GOAP planner using A* search to find optimal action sequences.
--//
--// The Planner is the brain of the GOAP system. Given a current world state
--// and a goal to achieve, it searches through possible action combinations
--// to find the optimal (lowest cost) sequence of actions.
--//
--// Algorithm: A* Search
--//   f(n) = g(n) + h(n)
--//   - g(n): Path cost from start
--//   - h(n): Heuristic estimate to goal (unsatisfied conditions * weight)
--//   - Time Complexity: O(b^d) where b = branching factor, d = depth
--//   - Space Complexity: O(b^d) for visited set and open set
--//
--// Features:
--//   - A* search finds optimal (lowest cost) action sequences
--//   - O(1) state hashing via cached State:getHash()
--//   - Performance mode with caching for many NPCs
--//   - Batch evaluation for processing multiple agents
--//   - Priority-based goal selection
--//   - Interrupt handling for urgent goals
--//   - Built-in profiling statistics

local Action = require(script.Parent.Action)
local Goal = require(script.Parent.Goal)
local State = require(script.Parent.State)
local Utilities = require(script.Parent.Utilities)

--// ============================================================================
--// TYPE DEFINITIONS
--// ============================================================================

--// Configuration options for Planner.new()
export type PlannerConfig = {
	maxIterations: number?, --// Maximum A* iterations (default: 1000)
	maxPlanLength: number?, --// Maximum actions in plan (default: 20)
	heuristicWeight: number?, --// A* heuristic weight (default: 1.0)
	performanceMode: boolean?, --// Enable caching optimizations
	priorityThreshold: number?, --// Ignore goals below this priority
	maxEvaluationsPerTick: number?, --// Max evaluations per update
	cacheTTL: number?, --// Priority cache TTL in seconds
	enableProfiling: boolean?, --// Track timing statistics
	cloneState: boolean?, --// Clone state before planning (thread-safe)
}

--// Result returned from plan() and planBestGoal()
export type PlanResult = {
	actions: { Action.Action }, --// Sequence of actions to execute
	totalCost: number, --// Sum of all action costs
	success: boolean, --// Whether planning succeeded
	iterations: number, --// A* iterations used
}

--// Profiling statistics from getProfilingData()
export type ProfilingData = {
	totalPlanTime: number, --// Total time spent planning
	planCount: number, --// Number of plans generated
	averagePlanTime: number, --// Average time per plan
	lastPlanTime: number, --// Time for most recent plan
	totalEvaluations: number, --// Total goal evaluations
}

--// Entry for batchEvaluate()
export type AgentEntry = {
	agent: any, --// The agent object
	state: State.State, --// The agent's world state
	goals: { Goal.Goal }, --// The agent's available goals
}

--// Result from batchEvaluate()
export type BatchResult = {
	agent: any, --// The agent object
	plan: PlanResult?, --// The generated plan (nil if skipped)
	goal: Goal.Goal?, --// The selected goal (nil if no plan)
	skipped: boolean, --// Whether evaluation was skipped
}

--// Internal node structure for A* search
type SearchNode = {
	state: State.State,
	action: Action.Action?,
	parent: SearchNode?,
	gCost: number,
	hCost: number,
	fCost: number,
	depth: number,
}

--// ============================================================================
--// CONSTANTS
--// ============================================================================

local DEFAULT_MAX_ITERATIONS: number = 1000
local DEFAULT_MAX_PLAN_LENGTH: number = 20
local DEFAULT_HEURISTIC_WEIGHT: number = 1.0 --// 1.0 = admissible, >1.0 = weighted A*
local DEFAULT_CACHE_TTL: number = 1.0
local DEFAULT_PRIORITY_THRESHOLD: number = 0
local DEFAULT_NODE_POOL_SIZE: number = 256
local LOG_PREFIX = "[Goal.Planner]"

--// Roblox task API for Actor support
local task_desynchronize = task.desynchronize
local task_synchronize = task.synchronize

--// ============================================================================
--// NODE POOL (Object Recycling for A* Search)
--// ============================================================================

--// Node pool for reducing GC pressure during A* search.
--// Reuses SearchNode objects instead of creating new ones each iteration.
local NodePool = {}
NodePool.__index = NodePool

function NodePool.new(initialSize: number?): typeof(NodePool.new())
	local self = setmetatable({}, NodePool)
	local size = initialSize or DEFAULT_NODE_POOL_SIZE
	self._pool = table.create(size) :: { SearchNode }
	self._poolSize = 0
	self._totalCreated = 0
	self._totalReused = 0
	return self
end

--// Acquires a node from the pool or creates a new one.
function NodePool:acquire(): SearchNode
	if self._poolSize > 0 then
		local node = self._pool[self._poolSize]
		self._pool[self._poolSize] = nil
		self._poolSize -= 1
		self._totalReused += 1
		return node
	end

	--// Create new node
	self._totalCreated += 1
	return {
		state = nil :: any,
		action = nil :: any,
		parent = nil :: any,
		gCost = 0,
		hCost = 0,
		fCost = 0,
		depth = 0,
	}
end

--// Returns a node to the pool for reuse.
function NodePool:release(node: SearchNode)
	-- Clear references to prevent memory leaks
	node.state = nil :: any
	node.action = nil
	node.parent = nil

	local poolSize = self._poolSize + 1
	self._poolSize = poolSize
	self._pool[poolSize] = node
end

--// Releases multiple nodes at once (batch release - inlined for performance).
function NodePool:releaseAll(nodes: { SearchNode })
	local pool = self._pool
	local poolSize = self._poolSize
	local nodeCount = #nodes

	for i = 1, nodeCount do
		local node = nodes[i]
		-- Clear references inline
		node.state = nil :: any
		node.action = nil
		node.parent = nil
		poolSize += 1
		pool[poolSize] = node
	end

	self._poolSize = poolSize
end

--// Clears the pool (for memory cleanup).
function NodePool:clear()
	table.clear(self._pool)
	self._poolSize = 0
end

--// Gets pool statistics.
function NodePool:getStats(): { poolSize: number, totalCreated: number, totalReused: number, reuseRate: number }
	local total = self._totalCreated + self._totalReused
	return {
		poolSize = self._poolSize,
		totalCreated = self._totalCreated,
		totalReused = self._totalReused,
		reuseRate = if total > 0 then self._totalReused / total else 0,
	}
end

--// ============================================================================
--// CLASS DEFINITION
--// ============================================================================

local Planner = {}
Planner.__index = Planner

--// ============================================================================
--// CONSTRUCTOR
--// ============================================================================

--// Creates a new Planner with optional configuration.
function Planner.new(config: PlannerConfig?): Planner
	local self = setmetatable({}, Planner)

	local cfg = config or {}

	-- Validate numeric config values
	if cfg.maxIterations ~= nil then
		assert(
			type(cfg.maxIterations) == "number" and cfg.maxIterations > 0,
			`{LOG_PREFIX} maxIterations must be a positive number`
		)
	end
	if cfg.maxPlanLength ~= nil then
		assert(
			type(cfg.maxPlanLength) == "number" and cfg.maxPlanLength > 0,
			`{LOG_PREFIX} maxPlanLength must be a positive number`
		)
	end
	if cfg.heuristicWeight ~= nil then
		assert(
			type(cfg.heuristicWeight) == "number" and cfg.heuristicWeight > 0,
			`{LOG_PREFIX} heuristicWeight must be a positive number`
		)
	end

	-- Search configuration
	self.maxIterations = cfg.maxIterations or DEFAULT_MAX_ITERATIONS
	self.maxPlanLength = cfg.maxPlanLength or DEFAULT_MAX_PLAN_LENGTH
	self.heuristicWeight = cfg.heuristicWeight or DEFAULT_HEURISTIC_WEIGHT

	-- Performance settings
	self.performanceMode = cfg.performanceMode or false
	self.priorityThreshold = cfg.priorityThreshold or DEFAULT_PRIORITY_THRESHOLD
	self.maxEvaluationsPerTick = cfg.maxEvaluationsPerTick or math.huge
	self.cacheTTL = cfg.cacheTTL or DEFAULT_CACHE_TTL
	self.enableProfiling = cfg.enableProfiling or false

	-- Action registry
	self._actions = {} :: { Action.Action }
	self._actionGroups = {} :: { [string]: { Action.Action } }

	-- Caching (performance mode)
	self._priorityCache = {} :: { [string]: number }
	self._planCache = {} :: { [string]: PlanResult }
	self._cacheTimestamps = {} :: { [string]: number }

	-- Goal sorting cache (avoids re-sorting goals every frame)
	self._sortedGoalsCache = nil :: { Goal.Goal }?
	self._goalsCacheKey = nil :: string?

	-- Plan result cache (avoids re-planning when state unchanged)
	self._lastStateHash = nil :: string?
	self._lastPlanResult = nil :: PlanResult?
	self._lastPlanGoal = nil :: Goal.Goal?

	-- Profiling data
	self._profilingData = {
		totalPlanTime = 0,
		planCount = 0,
		averagePlanTime = 0,
		lastPlanTime = 0,
		totalEvaluations = 0,
	}

	-- Node pool for A* search (reduces GC pressure)
	self._nodePool = NodePool.new()

	-- Thread-safe planning options
	self.cloneState = cfg.cloneState or false

	-- Actor detection (lazy)
	self._inActor = nil :: boolean?

	-- Execution stats
	self._executionStats = {
		plansExecuted = 0,
		actionsExecuted = 0,
		executionsFailed = 0,
	}

	return self
end

--// ============================================================================
--// ACTION REGISTRATION
--// ============================================================================

--// Registers an action with the planner.
--// Actions must be registered before they can be used in planning.
function Planner:registerAction(action: Action.Action)
	assert(action ~= nil, `{LOG_PREFIX} action cannot be nil`)

	table.insert(self._actions, action)

	-- Add to group index if action has a group
	local group = action:getGroup()
	if group then
		if not self._actionGroups[group] then
			self._actionGroups[group] = {}
		end
		table.insert(self._actionGroups[group], action)
	end
end

--// Registers multiple actions with the planner.
function Planner:registerActions(actions: { Action.Action })
	for _, action in ipairs(actions) do
		self:registerAction(action)
	end
end

--// Unregisters an action from the planner.
--// Returns true if action was found and removed.
function Planner:unregisterAction(action: Action.Action): boolean
	-- Remove from main list
	local found = false
	for i, registeredAction in ipairs(self._actions) do
		if registeredAction == action then
			table.remove(self._actions, i)
			found = true
			break
		end
	end

	-- Remove from group index
	local group = action:getGroup()
	if group and self._actionGroups[group] then
		for i, groupAction in ipairs(self._actionGroups[group]) do
			if groupAction == action then
				table.remove(self._actionGroups[group], i)
				break
			end
		end
	end

	return found
end

--// Clears all registered actions.
function Planner:clearActions()
	table.clear(self._actions)
	table.clear(self._actionGroups)
end

--// Gets all registered actions.
function Planner:getActions(): { Action.Action }
	return self._actions
end

--// Gets the number of registered actions.
function Planner:getActionCount(): number
	return #self._actions
end

--// Gets actions by group name.
function Planner:getActionsByGroup(group: string): { Action.Action }
	return self._actionGroups[group] or {}
end

--// Gets actions by tag.
function Planner:getActionsByTag(tag: string): { Action.Action }
	local result = {}
	for _, action in ipairs(self._actions) do
		if action:hasTag(tag) then
			table.insert(result, action)
		end
	end
	return result
end

--// ============================================================================
--// A* SEARCH INTERNALS
--// ============================================================================

--// Calculates the heuristic cost from current state to goal.
--// Uses unsatisfied condition count * heuristic weight.
--// Admissible when weight = 1.0 (never overestimates).
function Planner:_calculateHeuristic(currentState: State.State, goalState: State.State): number
	return currentState:countUnsatisfied(goalState) * self.heuristicWeight
end

--// Returns a unique hash for a state (for visited set tracking).
--// Delegates to State:getHash() which uses O(1) cached hashing.
function Planner:_hashState(state: State.State): string
	return state:getHash()
end

--// Gets valid actions that can be performed from the current state.
--// Checks preconditions, validation functions, cooldowns, and resources.
function Planner:_getValidActions(currentState: State.State, agent: any?, context: any?): { Action.Action }
	local validActions = {}
	local actions = self._actions
	local actionCount = #actions

	for i = 1, actionCount do
		local action = actions[i]
		-- Use canExecute if available (comprehensive check)
		if action.canExecute then
			if action:canExecute(currentState, agent, context) then
				validActions[#validActions + 1] = action
			end
		else
			-- Fall back to basic checks
			if action:checkPreconditions(currentState) and action:isValid(currentState, agent) then
				validActions[#validActions + 1] = action
			end
		end
	end

	return validActions
end

--// Reconstructs the plan from a goal node.
--// Walks backwards through parent nodes to build the action sequence.
function Planner:_reconstructPlan(goalNode: SearchNode): { Action.Action }
	local actions = {}
	local current: SearchNode? = goalNode

	while current do
		if current.action then
			table.insert(actions, 1, current.action)
		end
		current = current.parent
	end

	return actions
end

--// Calculates the depth (plan length) of a node.
function Planner:_getNodeDepth(node: SearchNode): number
	local depth = 0
	local current: SearchNode? = node

	while current and current.parent do
		depth += 1
		current = current.parent
	end

	return depth
end

--// Records profiling data after a plan.
function Planner:_recordProfiling(startTime: number?)
	if not self.enableProfiling or not startTime then
		return
	end

	local elapsed = os.clock() - startTime
	self._profilingData.lastPlanTime = elapsed
	self._profilingData.totalPlanTime += elapsed
	self._profilingData.planCount += 1
	self._profilingData.averagePlanTime = self._profilingData.totalPlanTime / self._profilingData.planCount
end

--// ============================================================================
--// CORE PLANNING (A* SEARCH)
--// ============================================================================

--// Plans a sequence of actions to achieve a goal using A* search.
--// Returns optimal (lowest cost) action sequence from start to goal.
function Planner:plan(startState: State.State, goal: Goal.Goal, agent: any?, context: any?): PlanResult
	local startTime: number? = nil
	if self.enableProfiling then
		startTime = os.clock()
	end

	local goalState = goal:getDesiredState()

	-- Early exit: goal already satisfied
	if startState:satisfies(goalState) then
		local result: PlanResult = {
			actions = {},
			totalCost = 0,
			success = true,
			iterations = 0,
		}
		self:_recordProfiling(startTime)
		return result
	end

	-- Initialize A* data structures with pre-allocated capacity
	local openSet = Utilities.PriorityQueue.new(self.maxIterations)
	local visited: { [string]: boolean } = {}
	local iterations = 0
	local nodePool = self._nodePool
	local allNodes: { SearchNode } = table.create(self.maxIterations) -- Track nodes for pool release
	local nodeCount = 0

	-- Create start node from pool
	local startHeuristic = self:_calculateHeuristic(startState, goalState)
	local startNode = nodePool:acquire()
	startNode.state = startState
	startNode.action = nil
	startNode.parent = nil
	startNode.gCost = 0
	startNode.hCost = startHeuristic
	startNode.fCost = startHeuristic
	startNode.depth = 0

	nodeCount += 1
	allNodes[nodeCount] = startNode
	openSet:push(startNode, startNode.fCost)
	visited[self:_hashState(startState)] = true

	-- Cache local references for hot loop
	local maxIterations = self.maxIterations
	local maxPlanLength = self.maxPlanLength
	local heuristicWeight = self.heuristicWeight
	local actions = self._actions
	local actionCount = #actions

	-- A* main loop
	while not openSet:isEmpty() and iterations < maxIterations do
		iterations += 1

		local currentNode: SearchNode = openSet:pop()
		local currentState = currentNode.state

		-- Goal check: is current state satisfactory?
		if currentState:satisfies(goalState) then
			local resultActions = self:_reconstructPlan(currentNode)
			local result: PlanResult = {
				actions = resultActions,
				totalCost = currentNode.gCost,
				success = true,
				iterations = iterations,
			}
			-- Release nodes back to pool
			nodePool:releaseAll(allNodes)
			self:_recordProfiling(startTime)
			return result
		end

		-- Check plan length limit using depth
		local depth = currentNode.depth
		if depth >= maxPlanLength then
			continue -- Skip this node, too deep
		end

		-- Expand node: inline action validation to avoid table allocation
		for i = 1, actionCount do
			local action = actions[i]

			-- Quick precondition check (most common rejection path)
			if not action:checkPreconditions(currentState) then
				continue
			end

			-- Full validation
			if action.canExecute then
				if not action:canExecute(currentState, agent, context) then
					continue
				end
			elseif not action:isValid(currentState, agent) then
				continue
			end

			-- Apply action to get successor state
			local newState = action:applyEffects(currentState)
			local stateHash = newState:getHash()

			-- Only process unvisited states
			if not visited[stateHash] then
				visited[stateHash] = true

				-- Calculate costs (inline for performance)
				local gCost = currentNode.gCost + action:getCost(currentState, agent)
				local hCost = newState:countUnsatisfied(goalState) * heuristicWeight
				local fCost = gCost + hCost

				-- Create successor node from pool
				local newNode = nodePool:acquire()
				newNode.state = newState
				newNode.action = action
				newNode.parent = currentNode
				newNode.gCost = gCost
				newNode.hCost = hCost
				newNode.fCost = fCost
				newNode.depth = depth + 1

				nodeCount += 1
				allNodes[nodeCount] = newNode
				openSet:push(newNode, fCost)
			end
		end
	end

	-- No plan found - release nodes back to pool
	nodePool:releaseAll(allNodes)

	local result: PlanResult = {
		actions = {},
		totalCost = 0,
		success = false,
		iterations = iterations,
	}
	self:_recordProfiling(startTime)
	return result
end

--// ============================================================================
--// PERFORMANCE OPTIMIZATIONS
--// ============================================================================

--// Gets cached priority for a goal, or calculates and caches it.
function Planner:_getCachedPriority(goal: Goal.Goal, worldState: State.State): number
	local cacheKey = goal:getName()
	local now = os.clock()

	--// Check cache validity
	local cached = self._priorityCache[cacheKey]
	local timestamp = self._cacheTimestamps[cacheKey]

	if cached ~= nil and timestamp ~= nil and (now - timestamp) < self.cacheTTL then
		return cached
	end

	--// Enforce cache limits before adding new entry
	self:_enforceCacheLimits()

	--// Calculate and cache
	local priority = goal:calculateRelevance(worldState)
	self._priorityCache[cacheKey] = priority
	self._cacheTimestamps[cacheKey] = now

	return priority
end

--// Invalidates all caches.
--// Call this when significant world state changes occur.
function Planner:invalidateCache()
	table.clear(self._priorityCache)
	table.clear(self._cacheTimestamps)
	table.clear(self._planCache)
	self._sortedGoalsCache = nil
	self._goalsCacheKey = nil
	self._lastStateHash = nil
	self._lastPlanResult = nil
	self._lastPlanGoal = nil
end

--// Invalidates cache for a specific goal.
function Planner:invalidateCacheFor(goalName: string)
	self._priorityCache[goalName] = nil
	self._cacheTimestamps[goalName] = nil
	self._planCache[goalName] = nil
end

--// ============================================================================
--// MULTI-GOAL PLANNING
--// ============================================================================

--// Plans for the highest priority valid goal.
--// Uses caching and early-out optimizations in performance mode.
function Planner:planBestGoal(
	startState: State.State,
	goals: { Goal.Goal },
	agent: any?,
	context: any?
): (PlanResult, Goal.Goal?)
	-- Performance mode: check if state unchanged since last plan
	if self.performanceMode then
		local stateHash = startState:getHash()
		if stateHash == self._lastStateHash and self._lastPlanResult then
			-- State unchanged, return cached result
			return self._lastPlanResult, self._lastPlanGoal
		end
		self._lastStateHash = stateHash
	end

	local evaluations = 0
	local maxPriority = -math.huge
	local bestGoal: Goal.Goal? = nil
	local bestPlan: PlanResult? = nil

	-- Get sorted goals (use cache if available and valid)
	local sortedGoals: { Goal.Goal }

	if self.performanceMode then
		-- Build cache key from goal names
		local cacheKey = ""
		for i, g in goals do
			if i > 1 then
				cacheKey ..= ","
			end
			cacheKey ..= g:getName()
		end

		-- Check if cache is valid
		if self._goalsCacheKey == cacheKey and self._sortedGoalsCache then
			sortedGoals = self._sortedGoalsCache
		else
			-- Sort and cache
			sortedGoals = table.clone(goals)
			table.sort(sortedGoals, function(a, b)
				local priorityA = self:_getCachedPriority(a, startState)
				local priorityB = self:_getCachedPriority(b, startState)
				return priorityA > priorityB
			end)
			self._sortedGoalsCache = sortedGoals
			self._goalsCacheKey = cacheKey
		end
	else
		-- Non-performance mode: always sort fresh
		sortedGoals = table.clone(goals)
		table.sort(sortedGoals, function(a, b)
			local priorityA = a:calculateRelevance(startState)
			local priorityB = b:calculateRelevance(startState)
			return priorityA > priorityB
		end)
	end

	for _, goal in ipairs(sortedGoals) do
		-- Respect evaluation limit
		if evaluations >= self.maxEvaluationsPerTick then
			break
		end

		-- Get priority (cached or calculated)
		local priority: number
		if self.performanceMode then
			priority = self:_getCachedPriority(goal, startState)
		else
			priority = goal:calculateRelevance(startState)
		end

		-- Skip goals below threshold
		if priority < self.priorityThreshold then
			continue
		end

		-- Early-out: if we have a successful plan and current goal has lower priority, stop
		if self.performanceMode and bestPlan and bestPlan.success and priority < maxPriority then
			break
		end

		-- Check if goal is valid and not already achieved
		if goal:isValid(startState) and not goal:validate(startState) then
			evaluations += 1
			self._profilingData.totalEvaluations += 1

			local plan = self:plan(startState, goal, agent, context)

			if plan.success and priority > maxPriority then
				maxPriority = priority
				bestGoal = goal
				bestPlan = plan
			end
		end
	end

	if bestPlan then
		-- Cache result for performance mode
		if self.performanceMode then
			self._lastPlanResult = bestPlan
			self._lastPlanGoal = bestGoal
		end
		return bestPlan, bestGoal
	end

	--// No plan found
	local noPlan: PlanResult = {
		actions = {},
		totalCost = 0,
		success = false,
		iterations = 0,
	}

	-- Cache even failed plans
	if self.performanceMode then
		self._lastPlanResult = noPlan
		self._lastPlanGoal = nil
	end

	return noPlan, nil
end

--// Batch evaluates goals for multiple agents efficiently.
--// Respects per-tick evaluation limit across all agents.
function Planner:batchEvaluate(agents: { AgentEntry }, context: any?): { BatchResult }
	local results: { BatchResult } = {}
	local totalEvaluations = 0

	for _, entry in ipairs(agents) do
		local agent = entry.agent
		local state = entry.state
		local goals = entry.goals

		-- Respect per-tick evaluation limit across all agents
		if totalEvaluations >= self.maxEvaluationsPerTick then
			table.insert(results, {
				agent = agent,
				plan = nil,
				goal = nil,
				skipped = true,
			})
			continue
		end

		-- Only replan if state is dirty or no current plan
		local shouldReplan = true
		if self.performanceMode and state.isDirty then
			shouldReplan = state:isDirty()
		end

		if shouldReplan then
			local plan, goal = self:planBestGoal(state, goals, agent, context)
			totalEvaluations += 1

			table.insert(results, {
				agent = agent,
				plan = plan,
				goal = goal,
				skipped = false,
			})

			-- Mark state as clean after planning
			if state.markClean then
				state:markClean()
			end
		else
			table.insert(results, {
				agent = agent,
				plan = nil,
				goal = nil,
				skipped = true,
			})
		end
	end

	return results
end

--// ============================================================================
--// PLAN VALIDATION
--// ============================================================================

--// Validates that a plan is still executable given current state.
--// Returns (isValid, failingStepIndex?).
function Planner:validatePlan(
	plan: PlanResult,
	currentState: State.State,
	agent: any?,
	context: any?
): (boolean, number?)
	if not plan.success or #plan.actions == 0 then
		return #plan.actions == 0, nil -- Empty plan is technically valid
	end

	local simulatedState = currentState:clone()

	for i, action in ipairs(plan.actions) do
		-- Use canExecute if available (comprehensive check)
		if action.canExecute then
			if not action:canExecute(simulatedState, agent, context) then
				return false, i
			end
		else
			if not action:checkPreconditions(simulatedState) then
				return false, i
			end
			if not action:isValid(simulatedState, agent) then
				return false, i
			end
		end
		simulatedState = action:applyEffects(simulatedState)
	end

	return true, nil
end

--// Calculates the remaining cost of a plan from a given step.
function Planner:getRemainingCost(plan: PlanResult, fromStep: number, worldState: State.State, agent: any?): number
	local cost = 0
	local simulatedState = worldState:clone()

	for i = fromStep, #plan.actions do
		local action = plan.actions[i]
		cost += action:getCost(simulatedState, agent)
		simulatedState = action:applyEffects(simulatedState)
	end

	return cost
end

--// ============================================================================
--// INTERRUPT HANDLING
--// ============================================================================

--// Checks if a new goal should interrupt the current plan.
function Planner:shouldInterrupt(currentGoal: Goal.Goal, newGoal: Goal.Goal, worldState: State.State): boolean
	if not currentGoal or not currentGoal:canInterrupt() then
		return false
	end

	return newGoal:shouldInterrupt(currentGoal, worldState)
end

--// Finds the highest priority goal that should interrupt current execution.
function Planner:findInterruptingGoal(currentGoal: Goal.Goal, goals: { Goal.Goal }, worldState: State.State): Goal.Goal?
	if not currentGoal or not currentGoal:canInterrupt() then
		return nil
	end

	local currentPriority = currentGoal:calculateRelevance(worldState)

	for _, goal in ipairs(goals) do
		if goal ~= currentGoal then
			local priority = goal:calculateRelevance(worldState)
			if priority > currentPriority and goal:isValid(worldState) and not goal:validate(worldState) then
				return goal
			end
		end
	end

	return nil
end

--// ============================================================================
--// PROFILING
--// ============================================================================

--// Gets profiling data. Only meaningful when enableProfiling is true.
function Planner:getProfilingData(): ProfilingData
	return {
		totalPlanTime = self._profilingData.totalPlanTime,
		planCount = self._profilingData.planCount,
		averagePlanTime = self._profilingData.averagePlanTime,
		lastPlanTime = self._profilingData.lastPlanTime,
		totalEvaluations = self._profilingData.totalEvaluations,
	}
end

--// Resets profiling data.
function Planner:resetProfiling()
	self._profilingData = {
		totalPlanTime = 0,
		planCount = 0,
		averagePlanTime = 0,
		lastPlanTime = 0,
		totalEvaluations = 0,
	}
end

--// ============================================================================
--// DEBUGGING
--// ============================================================================

--// String representation for debugging.
function Planner:__tostring(): string
	return `Planner\{actions={#self._actions}, maxIterations={self.maxIterations}}`
end

--// Creates a debug summary of this planner.
function Planner:debugSummary(): string
	local lines = {
		"Planner Configuration",
		`  Max Iterations: {self.maxIterations}`,
		`  Max Plan Length: {self.maxPlanLength}`,
		`  Heuristic Weight: {self.heuristicWeight}`,
		`  Performance Mode: {self.performanceMode}`,
		`  Priority Threshold: {self.priorityThreshold}`,
		`  Cache TTL: {self.cacheTTL}s`,
		`  Profiling Enabled: {self.enableProfiling}`,
		`  Registered Actions: {#self._actions}`,
	}

	-- Action groups
	local groupCount = 0
	for _ in pairs(self._actionGroups) do
		groupCount += 1
	end
	if groupCount > 0 then
		table.insert(lines, `  Action Groups: {groupCount}`)
		for groupName, actions in pairs(self._actionGroups) do
			table.insert(lines, `    {groupName}: {#actions} actions`)
		end
	end

	-- Profiling data
	if self.enableProfiling and self._profilingData.planCount > 0 then
		table.insert(lines, "  Profiling Stats:")
		table.insert(lines, `    Plans Generated: {self._profilingData.planCount}`)
		table.insert(lines, string.format("    Average Time: %.4fs", self._profilingData.averagePlanTime))
		table.insert(lines, string.format("    Last Time: %.4fs", self._profilingData.lastPlanTime))
		table.insert(lines, `    Total Evaluations: {self._profilingData.totalEvaluations}`)
	end

	return table.concat(lines, "\n")
end

--// ============================================================================
--// ACTOR SUPPORT (Thread Management)
--// ============================================================================

--// Checks if this planner is running inside an Actor.
--// Result is cached after first call.
function Planner:isInActor(): boolean
	if self._inActor == nil then
		local currentScript = script
		self._inActor = currentScript:FindFirstAncestorOfClass("Actor") ~= nil
	end
	return self._inActor
end

--// Switches to parallel execution mode (only works inside an Actor).
--// Safe to call outside Actors (will be a no-op).
--// Returns true if successfully desynced.
function Planner:desync(): boolean
	if self:isInActor() then
		task_desynchronize()
		return true
	end
	return false
end

--// Returns to synchronized execution mode.
--// Safe to call outside Actors (will be a no-op).
function Planner:sync()
	if self._inActor then
		task_synchronize()
	end
end

--// ============================================================================
--// STATE CLONING
--// ============================================================================

--// Clones a state for thread-safe planning.
--// Handles State objects, tables with getData(), and raw tables.
function Planner:_cloneState(state: State.State): State.State
	if type(state) == "table" and state.clone then
		return state:clone()
	end
	if type(state) == "table" and state.getData then
		return State.new(state:getData())
	end
	return State.new(state :: any)
end

--// Plans with automatic state cloning for thread-safety.
--// Use this when planning from within an Actor or when state might be modified.
function Planner:planSafe(startState: State.State, goal: Goal.Goal, agent: any?, context: any?): PlanResult
	local stateCopy = self:_cloneState(startState)
	return self:plan(stateCopy, goal, agent, context)
end

--// Plans for best goal with automatic state cloning.
function Planner:planBestGoalSafe(
	startState: State.State,
	goals: { Goal.Goal },
	agent: any?,
	context: any?
): (PlanResult, Goal.Goal?)
	local stateCopy = self:_cloneState(startState)
	return self:planBestGoal(stateCopy, goals, agent, context)
end

--// ============================================================================
--// PARALLEL PLANNING (Actor Support)
--// ============================================================================

--// Plans in parallel mode within an Actor.
--// Automatically handles desync/sync and state cloning for thread-safety.
--// Safe to call outside Actors (falls back to synchronous planning).
--//
--// @param startState The initial world state
--// @param goal The goal to achieve
--// @param agent Optional agent context
--// @param context Optional additional context
--// @return PlanResult The planning result
function Planner:planParallel(startState: State.State, goal: Goal.Goal, agent: any?, context: any?): PlanResult
	-- Clone state for thread safety (required before desync)
	local stateCopy = self:_cloneState(startState)

	-- Switch to parallel execution if in Actor
	local wasDesynced = self:desync()

	-- Perform planning (this can now run in parallel)
	local result = self:plan(stateCopy, goal, agent, context)

	-- Return to synchronized execution before returning
	if wasDesynced then
		self:sync()
	end

	return result
end

--// Plans for best goal in parallel mode within an Actor.
--// Automatically handles desync/sync and state cloning for thread-safety.
--// Safe to call outside Actors (falls back to synchronous planning).
--//
--// @param startState The initial world state
--// @param goals Array of goals to consider
--// @param agent Optional agent context
--// @param context Optional additional context
--// @return (PlanResult, Goal?) The planning result and selected goal
function Planner:planBestGoalParallel(
	startState: State.State,
	goals: { Goal.Goal },
	agent: any?,
	context: any?
): (PlanResult, Goal.Goal?)
	-- Clone state for thread safety (required before desync)
	local stateCopy = self:_cloneState(startState)

	-- Switch to parallel execution if in Actor
	local wasDesynced = self:desync()

	-- Perform planning (this can now run in parallel)
	local result, selectedGoal = self:planBestGoal(stateCopy, goals, agent, context)

	-- Return to synchronized execution before returning
	if wasDesynced then
		self:sync()
	end

	return result, selectedGoal
end

--// Checks if parallel planning is available (running inside an Actor).
--// Use this to decide whether to use parallel or synchronous planning.
function Planner:canPlanParallel(): boolean
	return self:isInActor()
end

--// ============================================================================
--// PLAN EXECUTION
--// ============================================================================

--// Executes a single action.
--// Call sync() first if running in parallel mode.
function Planner:executeAction(action: Action.Action, agent: any?, context: any?): boolean
	self._executionStats.actionsExecuted += 1
	local success = action:execute(agent, context)
	if not success then
		self._executionStats.executionsFailed += 1
	end
	return success
end

--// Executes an entire plan sequentially.
--// Returns (success, completedCount).
function Planner:executePlan(plan: PlanResult, agent: any?, context: any?): (boolean, number)
	if not plan.success then
		return false, 0
	end

	self._executionStats.plansExecuted += 1
	local completed = 0

	for _, action in plan.actions do
		local success = action:execute(agent, context)
		self._executionStats.actionsExecuted += 1
		if not success then
			self._executionStats.executionsFailed += 1
			return false, completed
		end
		completed += 1
	end

	return true, completed
end

--// Gets execution statistics.
function Planner:getExecutionStats(): {
	plansExecuted: number,
	actionsExecuted: number,
	executionsFailed: number,
	successRate: number,
}
	local total = self._executionStats.actionsExecuted
	local failed = self._executionStats.executionsFailed
	local successRate = if total > 0 then (total - failed) / total else 1

	return {
		plansExecuted = self._executionStats.plansExecuted,
		actionsExecuted = total,
		executionsFailed = failed,
		successRate = successRate,
	}
end

--// Resets execution statistics.
function Planner:resetExecutionStats()
	self._executionStats.plansExecuted = 0
	self._executionStats.actionsExecuted = 0
	self._executionStats.executionsFailed = 0
end

--// ============================================================================
--// MEMORY MANAGEMENT
--// ============================================================================

--// Maximum cache size to prevent unbounded growth.
local MAX_PRIORITY_CACHE_SIZE: number = 100
local MAX_PLAN_CACHE_SIZE: number = 50

--// Clears the node pool to free memory.
--// Call this during low-activity periods or when memory pressure is high.
function Planner:clearNodePool()
	self._nodePool:clear()
end

--// Gets node pool statistics for monitoring.
function Planner:getNodePoolStats(): { poolSize: number, totalCreated: number, totalReused: number, reuseRate: number }
	return self._nodePool:getStats()
end

--// Enforces cache size limits to prevent unbounded memory growth.
--// Called automatically when adding to cache, but can be called manually.
function Planner:_enforceCacheLimits()
	-- Enforce priority cache size
	local priorityCacheSize = 0
	for _ in pairs(self._priorityCache) do
		priorityCacheSize += 1
	end

	if priorityCacheSize > MAX_PRIORITY_CACHE_SIZE then
		-- Clear oldest entries (simple strategy: clear all and rebuild)
		table.clear(self._priorityCache)
		table.clear(self._cacheTimestamps)
	end

	-- Enforce plan cache size
	local planCacheSize = 0
	for _ in pairs(self._planCache) do
		planCacheSize += 1
	end

	if planCacheSize > MAX_PLAN_CACHE_SIZE then
		table.clear(self._planCache)
	end
end

--// Destroys the planner and releases all resources.
--// IMPORTANT: Call this when the planner is no longer needed to prevent memory leaks.
--// After calling destroy(), the planner should not be used.
function Planner:destroy()
	-- Clear all caches
	self:invalidateCache()

	-- Clear node pool
	self._nodePool:clear()

	-- Clear action references
	table.clear(self._actions)
	table.clear(self._actionGroups)

	-- Clear profiling data
	self._profilingData = nil

	-- Clear execution stats
	self._executionStats = nil

	-- Clear last plan references
	self._lastPlanResult = nil
	self._lastPlanGoal = nil
	self._sortedGoalsCache = nil
end

--// ============================================================================
--// TYPE EXPORT
--// ============================================================================

--// Export type for external use.
export type Planner = typeof(Planner.new())

return Planner
