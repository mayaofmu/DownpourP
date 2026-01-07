--!strict
--[[
	Method.lua
	Represents a decomposition method for HTN compound tasks.

	Methods define how compound tasks break down into subtasks. Each method
	has preconditions that determine when it's applicable and a sequence of
	subtasks to execute when chosen.

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          METHOD SELECTION                               │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│    Compound Task: EngageEnemy                                           │
	│    World State: { hasAmmo = false, health = 30 }                        │
	│                                                                         │
	│    ┌─────────────────────────────────────────────────────────────────┐  │
	│    │  Method 1: DirectAttack                                        │  │
	│    │  Preconditions: { hasAmmo = true }           ❌ NOT VALID       │  │
	│    │  Subtasks: [ Shoot ]                                           │  │
	│    │  Cost: 1                                                       │  │
	│    └─────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	│    ┌─────────────────────────────────────────────────────────────────┐  │
	│    │  Method 2: ReloadAndAttack                                     │  │
	│    │  Preconditions: { hasAmmo = false }          ✓ VALID           │  │
	│    │  Subtasks: [ Reload, Shoot ]                                   │  │
	│    │  Cost: 2                                                       │  │
	│    └─────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	│    ┌─────────────────────────────────────────────────────────────────┐  │
	│    │  Method 3: CautiousApproach                                    │  │
	│    │  Preconditions: {}                           ✓ VALID           │  │
	│    │  ValidateFn: health < 50 → true              ✓ PASSES          │  │
	│    │  Subtasks: [ TakeCover, Reload, Shoot ]                        │  │
	│    │  Cost: 3                                                       │  │
	│    └─────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	│    Selected: Method 2 (lowest cost among valid methods)                 │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          API QUICK REFERENCE                            │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│  CONSTRUCTOR                                                            │
	│    Method.new(config)               Create a new method                 │
	│                                                                         │
	│  IDENTITY                                                               │
	│    :getName()                       Get method name                     │
	│                                                                         │
	│  VALIDATION                                                             │
	│    :checkPreconditions(state)       Check state preconditions           │
	│    :isValid(state, agent?)          Check custom validation             │
	│    :canApply(state, agent?)         Full check (preconds + valid)       │
	│                                                                         │
	│  DECOMPOSITION                                                          │
	│    :getSubtasks()                   Get ordered subtask names           │
	│    :getSubtaskCount()               Get number of subtasks              │
	│                                                                         │
	│  COST                                                                   │
	│    :getCost()                       Get method selection cost           │
	│                                                                         │
	│  DEBUGGING                                                              │
	│    :debugSummary()                  Get human-readable summary          │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class Method
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Basic Method

	```lua
	local directAttack = Method.new({
		name = "DirectAttack",
		preconditions = { hasAmmo = true, targetVisible = true },
		subtasks = { "Shoot" },
		cost = 1,
	})
	```

	## Method with Custom Validation

	```lua
	local cautiousApproach = Method.new({
		name = "CautiousApproach",
		preconditions = {},
		subtasks = { "TakeCover", "Reload", "Shoot" },
		cost = 3,
		validateFn = function(state, agent)
			local health = state:get("health") or 100
			return health < 50  -- Only valid when low health
		end
	})
	```
]]

local State = require(script.Parent.Parent.State)

--// ============================================================================
--// TYPE DEFINITIONS
--// ============================================================================

--// Custom validation function type
export type ValidateFn = (worldState: State.State, agent: any?) -> boolean

--// Configuration for creating a method
export type MethodConfig = {
	name: string,
	preconditions: { [string]: State.StateValue }?,
	subtasks: { string },
	cost: number?,
	validateFn: ValidateFn?,
}

--// ============================================================================
--// CONSTANTS
--// ============================================================================

local LOG_PREFIX = "[Goal.Method]"
local DEFAULT_COST = 1

--// ============================================================================
--// CLASS DEFINITION
--// ============================================================================

local Method = {}
Method.__index = Method

--// ============================================================================
--// CONSTRUCTOR
--// ============================================================================

--[[
	Creates a new decomposition method.

	Methods define how compound tasks break down into sequences of subtasks.
	The HTN planner selects methods based on preconditions and cost.

	@param config MethodConfig -- Configuration with name, preconditions, subtasks
	@return Method -- New method
]]
function Method.new(config: MethodConfig): Method
	assert(config.name and #config.name > 0, LOG_PREFIX .. " Method requires a name")
	assert(config.subtasks, LOG_PREFIX .. " Method requires subtasks array")

	local self = setmetatable({}, Method)

	self._name = config.name
	self._preconditions = State.new(config.preconditions or {})
	self._subtasks = config.subtasks
	self._cost = config.cost or DEFAULT_COST
	self._validateFn = config.validateFn

	return self
end

--// ============================================================================
--// IDENTITY METHODS
--// ============================================================================

--[[
	Gets the name of this method.

	@return string -- Method name
]]
function Method:getName(): string
	return self._name
end

--// ============================================================================
--// VALIDATION METHODS
--// ============================================================================

--[[
	Checks if the method's state preconditions are satisfied.

	@param worldState State -- Current world state
	@return boolean -- True if preconditions are met
]]
function Method:checkPreconditions(worldState: State.State): boolean
	return worldState:satisfies(self._preconditions)
end

--[[
	Checks if the method passes custom validation.

	@param worldState State -- Current world state
	@param agent any? -- Optional agent context
	@return boolean -- True if valid (or no validateFn defined)
]]
function Method:isValid(worldState: State.State, agent: any?): boolean
	if not self._validateFn then
		return true
	end
	return self._validateFn(worldState, agent)
end

--[[
	Performs full validation: preconditions AND custom validation.

	@param worldState State -- Current world state
	@param agent any? -- Optional agent context
	@return boolean -- True if method can be applied
]]
function Method:canApply(worldState: State.State, agent: any?): boolean
	return self:checkPreconditions(worldState) and self:isValid(worldState, agent)
end

--[[
	Gets the preconditions State object.

	@return State -- Preconditions state
]]
function Method:getPreconditions(): State.State
	return self._preconditions
end

--// ============================================================================
--// DECOMPOSITION METHODS
--// ============================================================================

--[[
	Gets the ordered list of subtask names.

	@return { string } -- Array of subtask names
]]
function Method:getSubtasks(): { string }
	return self._subtasks
end

--[[
	Gets the number of subtasks.

	@return number -- Subtask count
]]
function Method:getSubtaskCount(): number
	return #self._subtasks
end

--// ============================================================================
--// COST METHODS
--// ============================================================================

--[[
	Gets the cost of selecting this method.

	Lower cost methods are preferred when multiple methods are valid.

	@return number -- Method cost
]]
function Method:getCost(): number
	return self._cost
end

--// ============================================================================
--// DEBUGGING
--// ============================================================================

--[[
	Gets a human-readable summary of this method.

	@return string -- Debug summary
]]
function Method:debugSummary(): string
	local lines: { string } = {}

	table.insert(lines, string.format("Method: %s", self._name))
	table.insert(lines, string.format("  Cost: %d", self._cost))

	-- Preconditions
	local precondData = self._preconditions:getData()
	local precondStr = {}
	for k, v in pairs(precondData) do
		table.insert(precondStr, string.format("%s=%s", k, tostring(v)))
	end
	if #precondStr > 0 then
		table.insert(lines, "  Preconditions: " .. table.concat(precondStr, ", "))
	else
		table.insert(lines, "  Preconditions: (none)")
	end

	-- Subtasks
	table.insert(lines, "  Subtasks: " .. table.concat(self._subtasks, " → "))

	-- Custom validation
	if self._validateFn then
		table.insert(lines, "  Has custom validateFn: yes")
	end

	return table.concat(lines, "\n")
end

--// ============================================================================
--// TYPE EXPORT
--// ============================================================================

export type Method = typeof(Method.new({
	name = "",
	subtasks = {},
}))

return Method
