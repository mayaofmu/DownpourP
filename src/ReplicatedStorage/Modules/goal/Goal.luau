--!strict
--[[
	Goal.lua
	Represents a goal in the GOAP system.

	Goals define desired world states that the AI should work towards.
	The planner finds sequences of actions to transition from the current
	state to a state that satisfies the goal's desired conditions.

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          GOAL PRIORITY FLOW                             │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│    Multiple Goals          Planner            Action Sequence           │
	│    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐            │
	│    │ Survive(10)  │───▶│  Select by   │───▶│   Execute    │            │
	│    │ Eat(5)       │    │  priority &  │    │   planned    │            │
	│    │ Explore(2)   │    │  validity    │    │   actions    │            │
	│    └──────────────┘    └──────────────┘    └──────────────┘            │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          API QUICK REFERENCE                            │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│  CONSTRUCTOR                                                            │
	│    Goal.new(config)                Create a new goal                    │
	│                                                                         │
	│  IDENTITY                                                               │
	│    :getName()                      Get goal name                        │
	│    :getGroup()                     Get goal group                       │
	│    :hasTag(tag)                    Check if goal has tag                │
	│    :getTags()                      Get all tags                         │
	│                                                                         │
	│  STATE                                                                  │
	│    :getDesiredState()              Get the desired world state          │
	│                                                                         │
	│  PRIORITY                                                               │
	│    :getPriority()                  Get base priority                    │
	│    :calculateRelevance(state)      Get context-aware priority           │
	│                                                                         │
	│  VALIDATION                                                             │
	│    :isValid(state)                 Check if goal is relevant            │
	│    :validate(state)                Check if goal is achieved            │
	│                                                                         │
	│  INTERRUPT HANDLING                                                     │
	│    :canInterrupt()                 Check if goal can be interrupted     │
	│    :shouldInterrupt(current,state) Check if should interrupt another    │
	│    :interrupt(state)               Handle being interrupted             │
	│                                                                         │
	│  DEBUGGING                                                              │
	│    :debugSummary()                 Get human-readable summary           │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class Goal
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Features

	- **Static & Dynamic Priority**: Use priorityFn for context-aware urgency
	- **Interrupt Handling**: Can be interrupted by higher-priority goals
	- **Validity Checking**: Skip irrelevant goals with isValidFn
	- **Custom Validation**: Define custom completion checks with validateFn
	- **Grouping & Tagging**: Organize goals by group and tags

	## Basic Goal

	```lua
	local survivalGoal = Goal.new({
		name = "Survive",
		desiredState = { isAlive = true, health = 100 },
		priority = 10,
	})
	```

	## Dynamic Priority Goal

	```lua
	local hungerGoal = Goal.new({
		name = "SatisfyHunger",
		desiredState = { isHungry = false },
		priority = 1,
		priorityFn = function(worldState)
			local hunger = worldState:get("hungerLevel") or 0
			return hunger * 2 -- More urgent when hungrier
		end,
	})
	```

	## Goal with Validation

	```lua
	local combatGoal = Goal.new({
		name = "DefeatEnemy",
		desiredState = { enemyDefeated = true },
		priority = 8,
		isValidFn = function(worldState)
			return worldState:get("enemyNearby") == true
		end,
		validateFn = function(worldState)
			return worldState:get("enemyHealth") <= 0
		end,
	})
	```

	## Configuration Options

	| Option         | Type       | Description                              |
	|----------------|------------|------------------------------------------|
	| name           | string     | Unique goal identifier (required)        |
	| desiredState   | table      | Target world state (required)            |
	| priority       | number?    | Base priority (default: 1)               |
	| priorityFn     | function?  | Dynamic priority calculator              |
	| isValidFn      | function?  | Check if goal is relevant                |
	| validateFn     | function?  | Check if goal is achieved                |
	| interruptible  | boolean?   | Can be interrupted (default: true)       |
	| onInterrupt    | function?  | Called when interrupted                  |
	| group          | string?    | Goal group for organization              |
	| tags           | {string}?  | Array of tags                            |
]]

local State = require(script.Parent.State)

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

--[=[
	@type ValidateFn (worldState: State) -> boolean
	@within Goal
	Function that checks if the goal has been achieved.
]=]
type ValidateFn = (worldState: State.State) -> boolean

--[=[
	@type IsValidFn (worldState: State) -> boolean
	@within Goal
	Function that checks if the goal is currently relevant/valid.
]=]
type IsValidFn = (worldState: State.State) -> boolean

--[=[
	@type PriorityFn (worldState: State) -> number
	@within Goal
	Function that calculates dynamic priority based on world state.
]=]
type PriorityFn = (worldState: State.State) -> number

--[=[
	@type OnInterruptFn (worldState: State) -> ()
	@within Goal
	Callback invoked when the goal is interrupted.
]=]
type OnInterruptFn = (worldState: State.State) -> ()

--[=[
	@interface GoalConfig
	@within Goal
	.name string -- Unique identifier for the goal (REQUIRED)
	.desiredState { [string]: any } -- State conditions that satisfy the goal (REQUIRED)
	.priority number? -- Base priority level (default: 1)
	.validateFn ValidateFn? -- Custom completion check
	.isValidFn IsValidFn? -- Checks if goal is currently relevant
	.priorityFn PriorityFn? -- Dynamic priority calculation
	.interruptible boolean? -- Can be interrupted by higher-priority goals (default: true)
	.onInterrupt OnInterruptFn? -- Called when goal is interrupted
	.group string? -- Group for organizing goals
	.tags { string }? -- Tags for filtering goals
	.minPriority number? -- Minimum priority threshold (default: 0)
]=]
export type GoalConfig = {
	name: string,
	desiredState: { [string]: any },
	priority: number?,
	validateFn: ValidateFn?,
	isValidFn: IsValidFn?,
	priorityFn: PriorityFn?,
	interruptible: boolean?,
	onInterrupt: OnInterruptFn?,
	group: string?,
	tags: { string }?,
	minPriority: number?,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

--- Default priority for goals without explicit priority.
local DEFAULT_PRIORITY: number = 1

--- Default minimum priority threshold.
local DEFAULT_MIN_PRIORITY: number = 0

--- Log prefix for warning/error messages.
local LOG_PREFIX = "[Goal.Goal]"

-- ============================================================================
-- CLASS DEFINITION
-- ============================================================================

--[=[
	@class Goal

	Represents a goal in the GOAP system.
	Goals define desired world states that agents should work towards.
]=]
local Goal = {}
Goal.__index = Goal

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

--[=[
	Creates a new Goal.

	@param config GoalConfig -- Goal configuration table
	@return Goal -- The newly created goal

	@error "Goal config must have a 'name' field" -- When name is missing
	@error "Goal config must have a 'desiredState' field" -- When desiredState is missing

	@example
	```lua
	local goal = Goal.new({
		name = "CollectResources",
		desiredState = { hasWood = true, hasStone = true },
		priority = 3,
		group = "gathering",
		tags = { "resource", "survival" },
	})
	```
]=]
function Goal.new(config: GoalConfig): Goal
	-- Validate required fields
	assert(
		config.name ~= nil and type(config.name) == "string",
		`{LOG_PREFIX} Goal config must have a 'name' field (string)`
	)
	assert(
		config.desiredState ~= nil and type(config.desiredState) == "table",
		`{LOG_PREFIX} Goal config must have a 'desiredState' field (table)`
	)

	local self = setmetatable({}, Goal)

	-- Required properties
	self.name = config.name
	self.desiredState = State.new(config.desiredState)

	-- Priority settings
	self.priority = config.priority or DEFAULT_PRIORITY
	self.minPriority = config.minPriority or DEFAULT_MIN_PRIORITY

	-- Callback functions (stored with underscore prefix for private access)
	self._validateFn = config.validateFn
	self._isValidFn = config.isValidFn
	self._priorityFn = config.priorityFn
	self._onInterrupt = config.onInterrupt

	-- Interrupt handling
	self.interruptible = if config.interruptible ~= nil then config.interruptible else true
	self._isActive = false

	-- Organization
	self.group = config.group
	self.tags = if config.tags then table.clone(config.tags) else {}

	return self
end

-- ============================================================================
-- BASIC PROPERTIES
-- ============================================================================

--[=[
	Gets the name of this goal.

	@return string -- The goal's unique identifier

	@example
	```lua
	local name = goal:getName()
	print("Pursuing goal:", name)
	```
]=]
function Goal:getName(): string
	return self.name
end

--[=[
	Gets the desired state for this goal.

	The desired state contains key-value pairs that must all be
	satisfied for the goal to be considered achieved.

	@return State -- State object containing desired conditions

	@example
	```lua
	local desired = goal:getDesiredState()
	for key, value in desired:pairs() do
		print(key, "should be", value)
	end
	```
]=]
function Goal:getDesiredState(): State.State
	return self.desiredState
end

--[=[
	Gets the base priority of this goal.

	Higher priority goals are pursued first when multiple goals
	are available. Use calculateRelevance() for dynamic priority.

	@return number -- The goal's base priority value

	@example
	```lua
	local priority = goal:getPriority()
	if priority > 5 then
		print("High priority goal!")
	end
	```
]=]
function Goal:getPriority(): number
	return self.priority
end

--[=[
	Sets the base priority of this goal.

	@param priority number -- The new priority value

	@example
	```lua
	-- Increase priority when health is low
	if currentHealth < 20 then
		healGoal:setPriority(10)
	end
	```
]=]
function Goal:setPriority(priority: number)
	assert(type(priority) == "number", `{LOG_PREFIX} priority must be a number`)
	self.priority = priority
end

-- ============================================================================
-- VALIDATION & RELEVANCE
-- ============================================================================

--[=[
	Checks if this goal is valid given the current world state.

	Invalid goals are skipped during planning. Use this to make goals
	context-dependent (e.g., combat goals only valid when enemies exist).

	@param worldState State -- The current world state
	@return boolean -- True if the goal is currently valid/relevant

	@example
	```lua
	local attackGoal = Goal.new({
		name = "Attack",
		desiredState = { enemyDefeated = true },
		isValidFn = function(state)
			return state:get("enemyVisible") == true
		end,
	})

	if attackGoal:isValid(worldState) then
		-- Goal is relevant, can be planned
	end
	```
]=]
function Goal:isValid(worldState: State.State): boolean
	if self._isValidFn then
		return self._isValidFn(worldState)
	end
	return true
end

--[=[
	Validates if this goal has been achieved.

	By default, checks if the world state satisfies all conditions
	in the desired state. Can be overridden with a custom validateFn.

	@param worldState State -- The current world state
	@return boolean -- True if the goal is achieved

	@example
	```lua
	local goal = Goal.new({
		name = "ReachDestination",
		desiredState = { atDestination = true },
		-- Custom validation that checks distance
		validateFn = function(state)
			local distance = state:get("distanceToTarget") or math.huge
			return distance < 1.0
		end,
	})

	if goal:validate(worldState) then
		print("Goal achieved!")
	end
	```
]=]
function Goal:validate(worldState: State.State): boolean
	if self._validateFn then
		return self._validateFn(worldState)
	end
	return worldState:satisfies(self.desiredState)
end

--[=[
	Calculates the relevance/urgency of this goal.

	If a priorityFn is provided, it's called to compute dynamic priority
	based on the current world state. Otherwise returns the base priority.

	@param worldState State -- The current world state
	@return number -- The calculated priority/relevance

	@example
	```lua
	local hungerGoal = Goal.new({
		name = "Eat",
		desiredState = { isHungry = false },
		priority = 1,
		priorityFn = function(state)
			local hunger = state:get("hunger") or 0
			if hunger > 80 then return 10 end -- Critical
			if hunger > 50 then return 5 end  -- Important
			return 1 -- Low priority
		end,
	})

	local urgency = hungerGoal:calculateRelevance(worldState)
	```
]=]
function Goal:calculateRelevance(worldState: State.State): number
	if self._priorityFn then
		return self._priorityFn(worldState)
	end
	return self.priority
end

--[=[
	Gets the distance (number of unsatisfied conditions) to this goal.

	Useful for heuristic calculations and progress tracking.

	@param worldState State -- The current world state
	@return number -- Count of unsatisfied conditions

	@example
	```lua
	local distance = goal:getDistance(worldState)
	print("Need to satisfy", distance, "more conditions")
	```
]=]
function Goal:getDistance(worldState: State.State): number
	return worldState:countUnsatisfied(self.desiredState)
end

--[=[
	Checks if this goal is already satisfied by the current state.

	Convenience method equivalent to calling validate() with the default behavior.

	@param worldState State -- The current world state
	@return boolean -- True if the goal is already satisfied

	@example
	```lua
	if goal:isSatisfied(worldState) then
		print("Goal already achieved, no planning needed")
	end
	```
]=]
function Goal:isSatisfied(worldState: State.State): boolean
	return worldState:satisfies(self.desiredState)
end

-- ============================================================================
-- INTERRUPT HANDLING
-- ============================================================================

--[=[
	Checks if this goal can be interrupted.

	A goal can be interrupted if:
	1. The interruptible property is true (default)
	2. The goal is currently active

	@return boolean -- True if the goal can be interrupted

	@example
	```lua
	if currentGoal:canInterrupt() then
		local newGoal = findHigherPriorityGoal()
		if newGoal then
			currentGoal:interrupt(worldState)
		end
	end
	```
]=]
function Goal:canInterrupt(): boolean
	return self.interruptible and self._isActive
end

--[=[
	Interrupts this goal if possible.

	Marks the goal as inactive and calls the onInterrupt callback
	if one was provided during construction.

	@param worldState State -- Current world state (passed to callback)
	@return boolean -- True if interrupt was successful

	@example
	```lua
	local goal = Goal.new({
		name = "Patrol",
		desiredState = { patrolComplete = true },
		onInterrupt = function(state)
			print("Patrol interrupted!")
			-- Save current patrol position for later
		end,
	})

	goal:markActive()
	-- Later, when something urgent happens...
	if goal:interrupt(worldState) then
		print("Successfully interrupted patrol")
	end
	```
]=]
function Goal:interrupt(worldState: State.State): boolean
	if not self:canInterrupt() then
		return false
	end

	self._isActive = false

	if self._onInterrupt then
		self._onInterrupt(worldState)
	end

	return true
end

--[=[
	Checks if this goal is currently being pursued.

	@return boolean -- True if the goal is active

	@example
	```lua
	if goal:isActive() then
		print("Currently working on:", goal:getName())
	end
	```
]=]
function Goal:isActive(): boolean
	return self._isActive
end

--[=[
	Marks the goal as active (being pursued).

	Should be called when the agent starts executing a plan for this goal.

	@example
	```lua
	local plan = planner:plan(worldState, goal)
	if plan.success then
		goal:markActive()
		-- Start executing plan...
	end
	```
]=]
function Goal:markActive()
	self._isActive = true
end

--[=[
	Marks the goal as inactive.

	Should be called when the agent stops pursuing this goal,
	either due to completion, failure, or interruption.

	@example
	```lua
	-- After completing or abandoning the goal
	goal:markInactive()
	```
]=]
function Goal:markInactive()
	self._isActive = false
end

--[=[
	Checks if this goal should interrupt another goal.

	Compares priorities using calculateRelevance and checks
	if the other goal can be interrupted.

	@param otherGoal Goal -- The goal to potentially interrupt
	@param worldState State -- Current world state
	@return boolean -- True if this goal should interrupt the other

	@example
	```lua
	local patrolGoal = Goal.new({ name = "Patrol", priority = 2, ... })
	local combatGoal = Goal.new({ name = "Combat", priority = 8, ... })

	patrolGoal:markActive()

	if combatGoal:shouldInterrupt(patrolGoal, worldState) then
		patrolGoal:interrupt(worldState)
		-- Switch to combat goal
	end
	```
]=]
function Goal:shouldInterrupt(otherGoal: Goal, worldState: State.State): boolean
	if not otherGoal:canInterrupt() then
		return false
	end

	local myPriority = self:calculateRelevance(worldState)
	local otherPriority = otherGoal:calculateRelevance(worldState)

	return myPriority > otherPriority
end

-- ============================================================================
-- GROUPING & TAGS
-- ============================================================================

--[=[
	Gets the group this goal belongs to.

	Groups allow organizing goals into categories for easier management.

	@return string? -- The group name, or nil if not grouped

	@example
	```lua
	local goal = Goal.new({
		name = "GatherWood",
		group = "resource_gathering",
		desiredState = { hasWood = true },
	})

	local group = goal:getGroup() -- "resource_gathering"
	```
]=]
function Goal:getGroup(): string?
	return self.group
end

--[=[
	Sets the group for this goal.

	@param group string -- The group name

	@example
	```lua
	goal:setGroup("combat")
	```
]=]
function Goal:setGroup(group: string)
	assert(type(group) == "string", `{LOG_PREFIX} group must be a string`)
	self.group = group
end

--[=[
	Gets all tags for this goal.

	@return { string } -- Array of tag strings

	@example
	```lua
	local tags = goal:getTags()
	for _, tag in ipairs(tags) do
		print("Tag:", tag)
	end
	```
]=]
function Goal:getTags(): { string }
	return self.tags
end

--[=[
	Checks if this goal has a specific tag.

	@param tag string -- The tag to check for
	@return boolean -- True if the goal has the tag

	@example
	```lua
	if goal:hasTag("urgent") then
		prioritizeGoal(goal)
	end
	```
]=]
function Goal:hasTag(tag: string): boolean
	for _, existingTag in ipairs(self.tags) do
		if existingTag == tag then
			return true
		end
	end
	return false
end

--[=[
	Adds a tag to this goal.

	Does nothing if the tag already exists.

	@param tag string -- The tag to add

	@example
	```lua
	goal:addTag("important")
	goal:addTag("survival")
	```
]=]
function Goal:addTag(tag: string)
	assert(type(tag) == "string", `{LOG_PREFIX} tag must be a string`)
	if not self:hasTag(tag) then
		table.insert(self.tags, tag)
	end
end

--[=[
	Removes a tag from this goal.

	@param tag string -- The tag to remove
	@return boolean -- True if the tag was removed

	@example
	```lua
	if goal:removeTag("temporary") then
		print("Tag removed")
	end
	```
]=]
function Goal:removeTag(tag: string): boolean
	for i, existingTag in ipairs(self.tags) do
		if existingTag == tag then
			table.remove(self.tags, i)
			return true
		end
	end
	return false
end

--[=[
	Clears all tags from this goal.

	@example
	```lua
	goal:clearTags()
	print(#goal:getTags()) -- 0
	```
]=]
function Goal:clearTags()
	table.clear(self.tags)
end

-- ============================================================================
-- PRIORITY THRESHOLD
-- ============================================================================

--[=[
	Gets the minimum priority threshold.

	Goals with calculated priority below this threshold are ignored.

	@return number -- The minimum priority threshold

	@example
	```lua
	local threshold = goal:getMinPriority()
	```
]=]
function Goal:getMinPriority(): number
	return self.minPriority
end

--[=[
	Sets the minimum priority threshold.

	@param threshold number -- The new threshold value

	@example
	```lua
	-- Only pursue this goal when it becomes urgent
	goal:setMinPriority(5)
	```
]=]
function Goal:setMinPriority(threshold: number)
	assert(type(threshold) == "number", `{LOG_PREFIX} threshold must be a number`)
	self.minPriority = threshold
end

--[=[
	Checks if this goal meets the minimum priority threshold.

	Uses calculateRelevance to get the current priority and
	compares it against minPriority.

	@param worldState State -- Current world state
	@return boolean -- True if current priority >= minPriority

	@example
	```lua
	-- Filter goals that meet their threshold
	local relevantGoals = {}
	for _, goal in ipairs(allGoals) do
		if goal:meetsThreshold(worldState) then
			table.insert(relevantGoals, goal)
		end
	end
	```
]=]
function Goal:meetsThreshold(worldState: State.State): boolean
	local currentPriority = self:calculateRelevance(worldState)
	return currentPriority >= self.minPriority
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	String representation for debugging.

	@return string -- Formatted string describing the goal

	@example
	```lua
	print(goal) -- "Goal{name=CollectResources, priority=3}"
	```
]=]
function Goal:__tostring(): string
	return `Goal\{name={self.name}, priority={self.priority}}`
end

--[=[
	Creates a debug summary of this goal.

	Provides detailed information useful for debugging.

	@param worldState State? -- Optional world state for dynamic values
	@return string -- Multi-line debug summary

	@example
	```lua
	print(goal:debugSummary(worldState))
	-- Goal: CollectResources
	--   Priority: 3 (dynamic: 7)
	--   Active: false
	--   Valid: true
	--   Satisfied: false
	--   Distance: 2
	```
]=]
function Goal:debugSummary(worldState: State.State?): string
	local lines = {
		`Goal: {self.name}`,
		`  Base Priority: {self.priority}`,
	}

	if worldState then
		local dynamicPriority = self:calculateRelevance(worldState)
		if dynamicPriority ~= self.priority then
			table.insert(lines, `  Dynamic Priority: {dynamicPriority}`)
		end
		table.insert(lines, `  Valid: {self:isValid(worldState)}`)
		table.insert(lines, `  Satisfied: {self:isSatisfied(worldState)}`)
		table.insert(lines, `  Distance: {self:getDistance(worldState)}`)
	end

	table.insert(lines, `  Active: {self._isActive}`)
	table.insert(lines, `  Interruptible: {self.interruptible}`)

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
export type Goal = typeof(Goal.new({
	name = "",
	desiredState = {},
}))

return Goal
