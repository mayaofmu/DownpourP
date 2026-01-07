--!strict
--[[
	Action.lua
	Represents an action in the GOAP system.

	Actions define state transitions with preconditions (requirements) and
	effects (changes). The planner chains actions together to transform the
	current world state into a goal state.

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          ACTION ANATOMY                                 │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│    ┌─────────────────────────────────────────────────────────────────┐  │
	│    │                     ACTION: ChopWood                            │  │
	│    ├─────────────────────────────────────────────────────────────────┤  │
	│    │  PRECONDITIONS              │  EFFECTS                          │  │
	│    │  ─────────────              │  ───────                          │  │
	│    │  • hasAxe = true            │  • hasWood = true                 │  │
	│    │  • nearTree = true          │                                   │  │
	│    ├─────────────────────────────┴───────────────────────────────────┤  │
	│    │  COST: 2    COOLDOWN: 5s    RESOURCES: stamina(10)              │  │
	│    └─────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          API QUICK REFERENCE                            │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│  CONSTRUCTOR                                                            │
	│    Action.new(config)              Create a new action                  │
	│                                                                         │
	│  IDENTITY                                                               │
	│    :getName()                      Get action name                      │
	│    :getGroup()                     Get action group                     │
	│    :hasTag(tag)                    Check if action has tag              │
	│    :getTags()                      Get all tags                         │
	│                                                                         │
	│  CONDITIONS & EFFECTS                                                   │
	│    :getPreconditions()             Get required state                   │
	│    :getEffects()                   Get state changes                    │
	│    :checkPreconditions(state)      Check if conditions met              │
	│    :applyEffects(state)            Apply effects to state               │
	│                                                                         │
	│  COST                                                                   │
	│    :getCost(state?, agent?)        Get action cost (static or dynamic)  │
	│                                                                         │
	│  VALIDATION & EXECUTION                                                 │
	│    :isValid(state, agent?)         Check custom validation              │
	│    :canExecute(state, agent?)      Full validation (preconds + valid)   │
	│    :execute(agent, context?)       Execute the action                   │
	│    :executeWithResources(...)      Execute with resource checking       │
	│                                                                         │
	│  COOLDOWN MANAGEMENT                                                    │
	│    :isOnCooldown()                 Check if on cooldown                 │
	│    :startCooldown()                Start cooldown timer                 │
	│    :resetCooldown()                Clear cooldown                       │
	│    :getRemainingCooldown()         Get time/turns remaining             │
	│    :advanceTurn()                  Advance turn-based cooldown          │
	│                                                                         │
	│  RESOURCE CHECKING                                                      │
	│    :hasResourceCosts()             Check if has resource costs          │
	│    :getResourceCosts()             Get resource cost array              │
	│    :canAfford(resourceGetter)      Check if can afford costs            │
	│                                                                         │
	│  INTERRUPT HANDLING                                                     │
	│    :canInterrupt()                 Check if interruptible               │
	│    :interrupt(agent?)              Handle interruption                  │
	│                                                                         │
	│  DEBUGGING                                                              │
	│    :debugSummary()                 Get human-readable summary           │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class Action
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Features

	- **Static & Dynamic Costs**: Use costFn for context-aware costing
	- **Preconditions**: Requirements that must be met before execution
	- **Effects**: State changes produced by the action
	- **Cooldown System**: Time-based or turn-based cooldowns
	- **Resource Costs**: Consume mana, stamina, items, etc.
	- **Interrupt Handling**: Graceful cancellation support
	- **Grouping & Tagging**: Organize actions by group and tags

	## Basic Action

	```lua
	local chopWood = Action.new({
		name = "ChopWood",
		cost = 2,
		preconditions = { hasAxe = true, nearTree = true },
		effects = { hasWood = true },
	})
	```

	## Action with Dynamic Cost

	```lua
	local walkTo = Action.new({
		name = "WalkToTarget",
		cost = 1,
		effects = { atTarget = true },
		costFn = function(worldState, agent)
			local distance = worldState:get("distanceToTarget") or 10
			return distance * 0.5
		end,
	})
	```

	## Action with Cooldown and Resources

	```lua
	local castFireball = Action.new({
		name = "CastFireball",
		cost = 3,
		preconditions = { hasWand = true },
		effects = { enemyBurning = true },
		cooldownTime = 5,
		cooldownMode = "seconds",
		resourceCosts = {
			{ resource = "mana", amount = 25 },
		},
	})
	```

	## Configuration Options

	| Option         | Type          | Description                            |
	|----------------|---------------|----------------------------------------|
	| name           | string        | Unique action identifier (required)    |
	| cost           | number?       | Base cost (default: 1)                 |
	| costFn         | function?     | Dynamic cost calculator                |
	| preconditions  | table?        | Required state conditions              |
	| effects        | table?        | State changes when executed            |
	| executeFn      | function?     | Custom execution logic                 |
	| validateFn     | function?     | Custom validation logic                |
	| cooldownTime   | number?       | Cooldown duration (default: 0)         |
	| cooldownMode   | string?       | "seconds" or "turns" (default)         |
	| resourceCosts  | array?        | Array of {resource, amount}            |
	| interruptible  | boolean?      | Can be interrupted (default: true)     |
	| onInterrupt    | function?     | Called when interrupted                |
	| group          | string?       | Action group for organization          |
	| tags           | {string}?     | Array of tags                          |
]]

local State = require(script.Parent.State)

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

--[=[
	@type CooldownMode "seconds" | "turns"
	@within Action
	Determines how cooldown is measured.
]=]
export type CooldownMode = "seconds" | "turns"

--[=[
	@interface ResourceCost
	@within Action
	.resource string -- Name of the resource (e.g., "mana", "gold")
	.amount number -- Amount required
]=]
export type ResourceCost = {
	resource: string,
	amount: number,
}

--[=[
	@type ValidateFn (worldState: State, agent: any?) -> boolean
	@within Action
	Function that performs runtime validation.
]=]
type ValidateFn = (worldState: State.State, agent: any?) -> boolean

--[=[
	@type ExecuteFn (agent: any?, context: any?) -> boolean
	@within Action
	Function that executes the action.
]=]
type ExecuteFn = (agent: any?, context: any?) -> boolean

--[=[
	@type CostFn (worldState: State, agent: any?) -> number
	@within Action
	Function that calculates dynamic cost.
]=]
type CostFn = (worldState: State.State, agent: any?) -> number

--[=[
	@type OnInterruptFn (agent: any?, context: any?) -> ()
	@within Action
	Callback invoked when the action is interrupted.
]=]
type OnInterruptFn = (agent: any?, context: any?) -> ()

--[=[
	@interface ActionConfig
	@within Action
	.name string -- Unique identifier for the action (REQUIRED)
	.cost number? -- Base cost for planning (default: 1)
	.preconditions { [string]: any }? -- Required state conditions
	.effects { [string]: any }? -- State changes when action completes
	.validateFn ValidateFn? -- Runtime validation
	.executeFn ExecuteFn? -- Execution logic
	.costFn CostFn? -- Dynamic cost calculation
	.cooldownTime number? -- Cooldown duration (default: 0)
	.cooldownMode CooldownMode? -- Cooldown mode (default: "seconds")
	.resourceCosts { ResourceCost }? -- Resource requirements
	.interruptible boolean? -- Can be interrupted (default: true)
	.onInterrupt OnInterruptFn? -- Interrupt callback
	.group string? -- Group for organizing actions
	.tags { string }? -- Tags for filtering actions
]=]
export type ActionConfig = {
	name: string,
	cost: number?,
	preconditions: { [string]: any }?,
	effects: { [string]: any }?,
	validateFn: ValidateFn?,
	executeFn: ExecuteFn?,
	costFn: CostFn?,
	cooldownTime: number?,
	cooldownMode: CooldownMode?,
	resourceCosts: { ResourceCost }?,
	interruptible: boolean?,
	onInterrupt: OnInterruptFn?,
	group: string?,
	tags: { string }?,
}

--[=[
	@interface ExecutionContext
	@within Action
	.currentTime number? -- Current time for cooldown checks
	.currentTurn number? -- Current turn for turn-based cooldowns
	.target any? -- Target of the action
	... -- Additional context fields
]=]
export type ExecutionContext = {
	currentTime: number?,
	currentTurn: number?,
	target: any?,
	[string]: any,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

--- Default base cost for actions.
local DEFAULT_COST: number = 1

--- Default cooldown time.
local DEFAULT_COOLDOWN_TIME: number = 0

--- Default cooldown mode.
local DEFAULT_COOLDOWN_MODE: CooldownMode = "seconds"

--- Log prefix for warning/error messages.
local LOG_PREFIX = "[Goal.Action]"

-- ============================================================================
-- CLASS DEFINITION
-- ============================================================================

--[=[
	@class Action

	Represents an action that can be performed by an agent.
	Actions define how agents can change the world state.
]=]
local Action = {}
Action.__index = Action

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

--[=[
	Creates a new Action.

	@param config ActionConfig -- Action configuration table
	@return Action -- The newly created action

	@error "Action config must have a 'name' field" -- When name is missing

	@example
	```lua
	local action = Action.new({
		name = "GatherBerries",
		cost = 1,
		preconditions = { nearBush = true },
		effects = { hasFood = true },
		group = "gathering",
		tags = { "food", "survival" },
	})
	```
]=]
function Action.new(config: ActionConfig): Action
	-- Validate required fields
	assert(
		config.name ~= nil and type(config.name) == "string",
		`{LOG_PREFIX} Action config must have a 'name' field (string)`
	)

	local self = setmetatable({}, Action)

	-- Required properties
	self.name = config.name

	-- Cost
	self.baseCost = config.cost or DEFAULT_COST

	-- State conditions
	self.preconditions = State.new(config.preconditions or {})
	self.effects = State.new(config.effects or {})

	-- Callback functions
	self._validateFn = config.validateFn
	self._executeFn = config.executeFn
	self._costFn = config.costFn
	self._onInterrupt = config.onInterrupt

	-- Cooldown system
	self.cooldownTime = config.cooldownTime or DEFAULT_COOLDOWN_TIME
	self.cooldownMode = config.cooldownMode or DEFAULT_COOLDOWN_MODE
	self._lastUsedTime = 0
	self._lastUsedTurn = 0

	-- Resource costs
	self.resourceCosts = if config.resourceCosts then table.clone(config.resourceCosts) else {}

	-- Interrupt handling
	self.interruptible = if config.interruptible ~= nil then config.interruptible else true
	self._isExecuting = false

	-- Organization
	self.group = config.group
	self.tags = if config.tags then table.clone(config.tags) else {}

	return self
end

-- ============================================================================
-- BASIC PROPERTIES
-- ============================================================================

--[=[
	Gets the name of this action.

	@return string -- The action's unique identifier

	@example
	```lua
	local name = action:getName()
	print("Executing action:", name)
	```
]=]
function Action:getName(): string
	return self.name
end

--[=[
	Gets the preconditions required for this action.

	Preconditions are state conditions that must be satisfied
	before the action can be performed.

	@return State -- State object containing required conditions

	@example
	```lua
	local preconditions = action:getPreconditions()
	for key, value in preconditions:pairs() do
		print("Requires:", key, "=", value)
	end
	```
]=]
function Action:getPreconditions(): State.State
	return self.preconditions
end

--[=[
	Gets the effects this action produces.

	Effects describe how the world state changes when
	this action is successfully completed.

	@return State -- State object containing effect conditions

	@example
	```lua
	local effects = action:getEffects()
	for key, value in effects:pairs() do
		print("Produces:", key, "=", value)
	end
	```
]=]
function Action:getEffects(): State.State
	return self.effects
end

--[=[
	Calculates the cost of this action.

	If a costFn was provided, it's called to compute dynamic cost
	based on the current state and agent. Otherwise returns baseCost.

	@param worldState State? -- The current world state
	@param agent any? -- Optional agent context
	@return number -- The calculated cost

	@example
	```lua
	local cost = action:getCost(worldState, agent)
	print("Action cost:", cost)
	```
]=]
function Action:getCost(worldState: State.State?, agent: any?): number
	if self._costFn and worldState then
		return self._costFn(worldState, agent)
	end
	return self.baseCost
end

--[=[
	Gets the base cost of this action (ignoring costFn).

	@return number -- The base cost value

	@example
	```lua
	local baseCost = action:getBaseCost()
	```
]=]
function Action:getBaseCost(): number
	return self.baseCost
end

--[=[
	Sets the base cost of this action.

	@param cost number -- The new base cost

	@example
	```lua
	-- Reduce cost with a buff
	action:setBaseCost(action:getBaseCost() * 0.5)
	```
]=]
function Action:setBaseCost(cost: number)
	assert(type(cost) == "number" and cost >= 0, `{LOG_PREFIX} cost must be a non-negative number`)
	self.baseCost = cost
end

-- ============================================================================
-- PRECONDITION CHECKING
-- ============================================================================

--[=[
	Checks if this action's preconditions are met.

	@param worldState State -- The current world state
	@return boolean -- True if all preconditions are satisfied

	@example
	```lua
	if action:checkPreconditions(worldState) then
		print("Action can be performed")
	end
	```
]=]
function Action:checkPreconditions(worldState: State.State): boolean
	return worldState:satisfies(self.preconditions)
end

--[=[
	Validates if this action can be performed.

	This is more dynamic than preconditions and can check runtime
	conditions that aren't part of the formal state model.

	@param worldState State -- The current world state
	@param agent any? -- Optional agent context
	@return boolean -- True if the action is valid

	@example
	```lua
	local action = Action.new({
		name = "Attack",
		validateFn = function(state, agent)
			-- Check if target is still alive
			local target = state:get("currentTarget")
			return target and target:isAlive()
		end,
	})
	```
]=]
function Action:isValid(worldState: State.State, agent: any?): boolean
	if self._validateFn then
		return self._validateFn(worldState, agent)
	end
	return true
end

--[=[
	Gets the unsatisfied preconditions for this action.

	Useful for debugging why an action can't be performed.

	@param worldState State -- The current world state
	@return { string } -- Array of unsatisfied precondition keys

	@example
	```lua
	local missing = action:getUnsatisfiedPreconditions(worldState)
	for _, key in ipairs(missing) do
		print("Missing precondition:", key)
	end
	```
]=]
function Action:getUnsatisfiedPreconditions(worldState: State.State): { string }
	return worldState:difference(self.preconditions)
end

-- ============================================================================
-- EFFECTS
-- ============================================================================

--[=[
	Applies this action's effects to a state.

	Creates a new state with the effects merged in.
	Does not modify the original state.

	@param state State -- The state to modify
	@return State -- New state with effects applied

	@example
	```lua
	local newState = action:applyEffects(currentState)
	-- currentState is unchanged
	-- newState has the action's effects
	```
]=]
function Action:applyEffects(state: State.State): State.State
	local newState = state:clone()
	newState:merge(self.effects)
	return newState
end

--[=[
	Checks if this action can contribute to achieving a goal state.

	Returns true if any of this action's effects match conditions
	in the goal state.

	@param goalState State -- The desired goal state
	@return boolean -- True if action contributes to the goal

	@example
	```lua
	local goal = State.new({ hasFood = true })
	if action:contributesToGoal(goal) then
		print("This action helps achieve the goal")
	end
	```
]=]
function Action:contributesToGoal(goalState: State.State): boolean
	for key, value in self.effects:pairs() do
		local goalValue = goalState:get(key)
		if goalValue ~= nil and goalValue == value then
			return true
		end
	end
	return false
end

-- ============================================================================
-- EXECUTION
-- ============================================================================

--[=[
	Executes this action.

	Calls the executeFn if one was provided, otherwise returns true.
	This method does NOT handle cooldowns or resources - use
	executeWithResources() for that.

	@param agent any? -- The agent performing the action
	@param context ExecutionContext? -- Additional context for execution
	@return boolean -- True if execution succeeded

	@example
	```lua
	local success = action:execute(agent, { target = enemy })
	if success then
		print("Action completed!")
	end
	```
]=]
function Action:execute(agent: any?, context: ExecutionContext?): boolean
	if self._executeFn then
		return self._executeFn(agent, context)
	end
	return true
end

--[=[
	Enhanced execute that handles cooldowns and resources.

	This method:
	1. Checks cooldown
	2. Checks resources
	3. Marks action as started
	4. Consumes resources
	5. Executes the action
	6. Marks action as finished
	7. Starts cooldown on success

	@param agent any? -- The agent performing the action
	@param context ExecutionContext? -- Additional context for execution
	@return boolean -- True if execution succeeded

	@example
	```lua
	local context = {
		currentTime = os.clock(),
		currentTurn = gameState.turn,
	}

	if action:executeWithResources(agent, context) then
		print("Action executed successfully!")
	else
		print("Action failed (cooldown, resources, or execution)")
	end
	```
]=]
function Action:executeWithResources(agent: any?, context: ExecutionContext?): boolean
	-- Extract timing info from context
	local currentTime = context and context.currentTime
	local currentTurn = context and context.currentTurn

	-- Check cooldown
	if self:isOnCooldown(currentTime, currentTurn) then
		return false
	end

	-- Check and consume resources
	if not self:checkResources(agent) then
		return false
	end

	self:markStarted()

	-- Consume resources before execution
	self:consumeResources(agent)

	-- Execute the action
	local success = self:execute(agent, context)

	self:markFinished()

	-- Start cooldown on success
	if success then
		self:startCooldown(currentTime, currentTurn)
	end

	return success
end

--[=[
	Checks if this action can be executed (preconditions, cooldown, resources).

	Comprehensive check that verifies:
	1. Preconditions are satisfied
	2. Validation function passes
	3. Not on cooldown
	4. Agent has required resources

	@param worldState State -- The current world state
	@param agent any? -- Optional agent context
	@param context ExecutionContext? -- Additional context (currentTime, currentTurn)
	@return boolean -- True if action can be executed

	@example
	```lua
	local context = { currentTime = os.clock() }

	if action:canExecute(worldState, agent, context) then
		action:executeWithResources(agent, context)
	end
	```
]=]
function Action:canExecute(worldState: State.State, agent: any?, context: ExecutionContext?): boolean
	-- Check preconditions
	if not self:checkPreconditions(worldState) then
		return false
	end

	-- Check validation
	if not self:isValid(worldState, agent) then
		return false
	end

	-- Check cooldown
	local currentTime = context and context.currentTime
	local currentTurn = context and context.currentTurn
	if self:isOnCooldown(currentTime, currentTurn) then
		return false
	end

	-- Check resources
	if not self:checkResources(agent) then
		return false
	end

	return true
end

-- ============================================================================
-- COOLDOWN SYSTEM
-- ============================================================================

--[=[
	Checks if this action is currently on cooldown.

	@param currentTime number? -- Current time in seconds (uses os.clock if nil)
	@param currentTurn number? -- Current turn number (for turn-based cooldowns)
	@return boolean -- True if action is on cooldown

	@example Time-based Cooldown
	```lua
	if not action:isOnCooldown() then
		action:execute(agent)
		action:startCooldown()
	end
	```

	@example Turn-based Cooldown
	```lua
	if not action:isOnCooldown(nil, currentTurn) then
		action:execute(agent)
		action:startCooldown(nil, currentTurn)
	end
	```
]=]
function Action:isOnCooldown(currentTime: number?, currentTurn: number?): boolean
	if self.cooldownTime <= 0 then
		return false
	end

	if self.cooldownMode == "turns" then
		local turn = currentTurn or 0
		return (turn - self._lastUsedTurn) < self.cooldownTime
	else
		local time = currentTime or os.clock()
		return (time - self._lastUsedTime) < self.cooldownTime
	end
end

--[=[
	Gets the remaining cooldown time/turns.

	@param currentTime number? -- Current time in seconds
	@param currentTurn number? -- Current turn number
	@return number -- Remaining cooldown (0 if not on cooldown)

	@example
	```lua
	local remaining = action:getRemainingCooldown()
	if remaining > 0 then
		print("Cooldown:", remaining, "seconds remaining")
	end
	```
]=]
function Action:getRemainingCooldown(currentTime: number?, currentTurn: number?): number
	if self.cooldownTime <= 0 then
		return 0
	end

	if self.cooldownMode == "turns" then
		local turn = currentTurn or 0
		local remaining = self.cooldownTime - (turn - self._lastUsedTurn)
		return math.max(0, remaining)
	else
		local time = currentTime or os.clock()
		local remaining = self.cooldownTime - (time - self._lastUsedTime)
		return math.max(0, remaining)
	end
end

--[=[
	Starts the cooldown for this action.

	Should be called after successfully executing the action.

	@param currentTime number? -- Current time in seconds
	@param currentTurn number? -- Current turn number

	@example
	```lua
	local success = action:execute(agent)
	if success then
		action:startCooldown()
	end
	```
]=]
function Action:startCooldown(currentTime: number?, currentTurn: number?)
	if self.cooldownMode == "turns" then
		self._lastUsedTurn = currentTurn or 0
	else
		self._lastUsedTime = currentTime or os.clock()
	end
end

--[=[
	Resets the cooldown for this action.

	Immediately makes the action available again.

	@example
	```lua
	-- Reset all action cooldowns
	for _, action in ipairs(actions) do
		action:resetCooldown()
	end
	```
]=]
function Action:resetCooldown()
	self._lastUsedTime = 0
	self._lastUsedTurn = 0
end

--[=[
	Gets the cooldown time/turns for this action.

	@return number -- The cooldown duration

	@example
	```lua
	local cooldown = action:getCooldownTime()
	print("This action has a", cooldown, "second cooldown")
	```
]=]
function Action:getCooldownTime(): number
	return self.cooldownTime
end

--[=[
	Sets the cooldown time/turns for this action.

	@param time number -- The new cooldown duration

	@example
	```lua
	-- Reduce cooldown with a buff
	action:setCooldownTime(action:getCooldownTime() * 0.5)
	```
]=]
function Action:setCooldownTime(time: number)
	assert(type(time) == "number" and time >= 0, `{LOG_PREFIX} cooldown time must be a non-negative number`)
	self.cooldownTime = time
end

--[=[
	Gets the cooldown mode for this action.

	@return CooldownMode -- "seconds" or "turns"
]=]
function Action:getCooldownMode(): CooldownMode
	return self.cooldownMode
end

--[=[
	Sets the cooldown mode for this action.

	@param mode CooldownMode -- "seconds" or "turns"
]=]
function Action:setCooldownMode(mode: CooldownMode)
	assert(mode == "seconds" or mode == "turns", `{LOG_PREFIX} cooldown mode must be "seconds" or "turns"`)
	self.cooldownMode = mode
end

-- ============================================================================
-- RESOURCE SYSTEM
-- ============================================================================

--[=[
	Gets the resource costs for this action.

	@return { ResourceCost } -- Array of resource cost tables

	@example
	```lua
	local costs = action:getResourceCosts()
	for _, cost in ipairs(costs) do
		print("Requires", cost.amount, cost.resource)
	end
	```
]=]
function Action:getResourceCosts(): { ResourceCost }
	return self.resourceCosts
end

--[=[
	Adds a resource cost to this action.

	@param resource string -- The resource name (e.g., "mana", "gold")
	@param amount number -- The amount required

	@example
	```lua
	action:addResourceCost("mana", 25)
	action:addResourceCost("gold", 10)
	```
]=]
function Action:addResourceCost(resource: string, amount: number)
	assert(type(resource) == "string", `{LOG_PREFIX} resource must be a string`)
	assert(type(amount) == "number" and amount > 0, `{LOG_PREFIX} amount must be a positive number`)
	table.insert(self.resourceCosts, { resource = resource, amount = amount })
end

--[=[
	Removes a resource cost from this action.

	@param resource string -- The resource name to remove
	@return boolean -- True if the resource cost was removed

	@example
	```lua
	if action:removeResourceCost("gold") then
		print("Gold cost removed")
	end
	```
]=]
function Action:removeResourceCost(resource: string): boolean
	for i, cost in ipairs(self.resourceCosts) do
		if cost.resource == resource then
			table.remove(self.resourceCosts, i)
			return true
		end
	end
	return false
end

--[=[
	Clears all resource costs from this action.

	@example
	```lua
	action:clearResourceCosts()
	```
]=]
function Action:clearResourceCosts()
	table.clear(self.resourceCosts)
end

--[=[
	Checks if the agent has enough resources for this action.

	Supports multiple agent resource APIs:
	- agent:getResource(name) method
	- agent.resources table
	- agent[resourceName] properties

	@param agent any? -- The agent to check
	@return boolean -- True if agent has sufficient resources

	@example
	```lua
	if action:checkResources(agent) then
		print("Agent has enough resources")
	else
		print("Insufficient resources")
	end
	```
]=]
function Action:checkResources(agent: any?): boolean
	if #self.resourceCosts == 0 then
		return true
	end

	if not agent then
		return false
	end

	for _, cost in ipairs(self.resourceCosts) do
		local available = self:_getAgentResource(agent, cost.resource)
		if available < cost.amount then
			return false
		end
	end

	return true
end

--[=[
	Consumes resources from the agent for this action.

	Supports multiple agent resource APIs:
	- agent:consumeResource(name, amount) method
	- agent.resources table (directly modified)
	- agent[resourceName] properties (directly modified)

	@param agent any? -- The agent to consume resources from
	@return boolean -- True if resources were consumed successfully

	@example
	```lua
	if action:consumeResources(agent) then
		-- Resources deducted, proceed with action
		action:execute(agent)
	end
	```
]=]
function Action:consumeResources(agent: any?): boolean
	if not self:checkResources(agent) then
		return false
	end

	for _, cost in ipairs(self.resourceCosts) do
		self:_consumeAgentResource(agent, cost.resource, cost.amount)
	end

	return true
end

--[=[
	Gets a resource value from an agent using various API patterns.

	@param agent any -- The agent
	@param resource string -- Resource name
	@return number -- Available amount (0 if not found)
	@private
]=]
function Action:_getAgentResource(agent: any, resource: string): number
	-- Try method first
	if type(agent.getResource) == "function" then
		return agent:getResource(resource) or 0
	end

	-- Try resources table
	if type(agent.resources) == "table" then
		return agent.resources[resource] or 0
	end

	-- Try direct property
	if type(agent[resource]) == "number" then
		return agent[resource]
	end

	return 0
end

--[=[
	Consumes a resource from an agent using various API patterns.

	@param agent any -- The agent
	@param resource string -- Resource name
	@param amount number -- Amount to consume
	@private
]=]
function Action:_consumeAgentResource(agent: any, resource: string, amount: number)
	-- Try method first
	if type(agent.consumeResource) == "function" then
		agent:consumeResource(resource, amount)
		return
	end

	-- Try resources table
	if type(agent.resources) == "table" then
		agent.resources[resource] = (agent.resources[resource] or 0) - amount
		return
	end

	-- Try direct property
	if type(agent[resource]) == "number" then
		agent[resource] = agent[resource] - amount
	end
end

-- ============================================================================
-- INTERRUPT SYSTEM
-- ============================================================================

--[=[
	Checks if this action can be interrupted.

	An action can be interrupted if:
	1. The interruptible property is true (default)
	2. The action is currently executing

	@return boolean -- True if the action can be interrupted

	@example
	```lua
	if action:canInterrupt() then
		action:interrupt(agent)
	end
	```
]=]
function Action:canInterrupt(): boolean
	return self.interruptible and self._isExecuting
end

--[=[
	Interrupts this action if possible.

	Marks the action as not executing and calls the onInterrupt
	callback if one was provided.

	@param agent any? -- The agent performing the action
	@param context ExecutionContext? -- Additional context
	@return boolean -- True if interrupt was successful

	@example
	```lua
	local action = Action.new({
		name = "LongCast",
		onInterrupt = function(agent, context)
			print("Spell interrupted!")
			agent:playAnimation("flinch")
		end,
	})

	action:markStarted()
	-- Later, when damaged...
	action:interrupt(agent)
	```
]=]
function Action:interrupt(agent: any?, context: ExecutionContext?): boolean
	if not self:canInterrupt() then
		return false
	end

	self._isExecuting = false

	if self._onInterrupt then
		self._onInterrupt(agent, context)
	end

	return true
end

--[=[
	Checks if this action is currently executing.

	@return boolean -- True if action is in progress

	@example
	```lua
	if action:isExecuting() then
		print("Action in progress...")
	end
	```
]=]
function Action:isExecuting(): boolean
	return self._isExecuting
end

--[=[
	Marks the action as started (for interrupt tracking).

	Should be called when beginning to execute the action.

	@example
	```lua
	action:markStarted()
	-- Perform long-running action...
	action:markFinished()
	```
]=]
function Action:markStarted()
	self._isExecuting = true
end

--[=[
	Marks the action as finished (for interrupt tracking).

	Should be called when the action completes or fails.

	@example
	```lua
	action:markStarted()
	local success = performAction()
	action:markFinished()
	```
]=]
function Action:markFinished()
	self._isExecuting = false
end

-- ============================================================================
-- GROUPING & TAGS
-- ============================================================================

--[=[
	Gets the group this action belongs to.

	@return string? -- The group name, or nil if not grouped

	@example
	```lua
	local group = action:getGroup()
	if group == "combat" then
		-- Combat action logic
	end
	```
]=]
function Action:getGroup(): string?
	return self.group
end

--[=[
	Sets the group for this action.

	@param group string -- The group name

	@example
	```lua
	action:setGroup("combat")
	```
]=]
function Action:setGroup(group: string)
	assert(type(group) == "string", `{LOG_PREFIX} group must be a string`)
	self.group = group
end

--[=[
	Gets all tags for this action.

	@return { string } -- Array of tag strings

	@example
	```lua
	local tags = action:getTags()
	```
]=]
function Action:getTags(): { string }
	return self.tags
end

--[=[
	Checks if this action has a specific tag.

	@param tag string -- The tag to check for
	@return boolean -- True if the action has the tag

	@example
	```lua
	if action:hasTag("ranged") then
		-- Ranged action handling
	end
	```
]=]
function Action:hasTag(tag: string): boolean
	for _, existingTag in ipairs(self.tags) do
		if existingTag == tag then
			return true
		end
	end
	return false
end

--[=[
	Adds a tag to this action.

	Does nothing if the tag already exists.

	@param tag string -- The tag to add

	@example
	```lua
	action:addTag("offensive")
	```
]=]
function Action:addTag(tag: string)
	assert(type(tag) == "string", `{LOG_PREFIX} tag must be a string`)
	if not self:hasTag(tag) then
		table.insert(self.tags, tag)
	end
end

--[=[
	Removes a tag from this action.

	@param tag string -- The tag to remove
	@return boolean -- True if the tag was removed

	@example
	```lua
	action:removeTag("deprecated")
	```
]=]
function Action:removeTag(tag: string): boolean
	for i, existingTag in ipairs(self.tags) do
		if existingTag == tag then
			table.remove(self.tags, i)
			return true
		end
	end
	return false
end

--[=[
	Clears all tags from this action.

	@example
	```lua
	action:clearTags()
	```
]=]
function Action:clearTags()
	table.clear(self.tags)
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	String representation for debugging.

	@return string -- Formatted string describing the action

	@example
	```lua
	print(action) -- "Action{name=ChopWood, cost=2}"
	```
]=]
function Action:__tostring(): string
	return `Action\{name={self.name}, cost={self.baseCost}}`
end

--[=[
	Creates a debug summary of this action.

	Provides detailed information useful for debugging.

	@param worldState State? -- Optional world state for condition checking
	@param agent any? -- Optional agent for resource checking
	@return string -- Multi-line debug summary

	@example
	```lua
	print(action:debugSummary(worldState, agent))
	-- Action: ChopWood
	--   Base Cost: 2
	--   Preconditions: hasAxe=true, nearTree=true
	--   Effects: hasWood=true
	--   Cooldown: 5 seconds (ready)
	--   Resources: stamina(10)
	```
]=]
function Action:debugSummary(worldState: State.State?, agent: any?): string
	local lines = {
		`Action: {self.name}`,
		`  Base Cost: {self.baseCost}`,
	}

	-- Preconditions
	local precondParts = {}
	for key, value in self.preconditions:pairs() do
		table.insert(precondParts, `{key}={tostring(value)}`)
	end
	if #precondParts > 0 then
		table.insert(lines, `  Preconditions: {table.concat(precondParts, ", ")}`)
	else
		table.insert(lines, "  Preconditions: (none)")
	end

	-- Effects
	local effectParts = {}
	for key, value in self.effects:pairs() do
		table.insert(effectParts, `{key}={tostring(value)}`)
	end
	if #effectParts > 0 then
		table.insert(lines, `  Effects: {table.concat(effectParts, ", ")}`)
	else
		table.insert(lines, "  Effects: (none)")
	end

	-- Cooldown
	if self.cooldownTime > 0 then
		local remaining = self:getRemainingCooldown()
		local status = if remaining > 0 then string.format("%.1f remaining", remaining) else "ready"
		table.insert(lines, `  Cooldown: {self.cooldownTime} {self.cooldownMode} ({status})`)
	end

	-- Resources
	if #self.resourceCosts > 0 then
		local resourceParts = {}
		for _, cost in ipairs(self.resourceCosts) do
			table.insert(resourceParts, `{cost.resource}({cost.amount})`)
		end
		table.insert(lines, `  Resources: {table.concat(resourceParts, ", ")}`)
	end

	-- Status checks
	if worldState then
		table.insert(lines, `  Preconditions Met: {self:checkPreconditions(worldState)}`)
	end
	if agent then
		table.insert(lines, `  Resources Available: {self:checkResources(agent)}`)
	end

	if self.group then
		table.insert(lines, `  Group: {self.group}`)
	end

	if #self.tags > 0 then
		table.insert(lines, `  Tags: {table.concat(self.tags, ", ")}`)
	end

	return table.concat(lines, "\n")
end

-- ============================================================================
-- TYPE EXPORT
-- ============================================================================

--- Export type for external use.
export type Action = typeof(Action.new({ name = "" }))

return Action
