--!strict
--[[
	Task.lua
	Represents a task in the HTN (Hierarchical Task Network) system.

	Tasks are the building blocks of HTN planning. There are two types:
	- PRIMITIVE: Directly executable tasks that map to Actions
	- COMPOUND: High-level tasks that decompose into subtasks via Methods

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          TASK HIERARCHY                                 │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│                      ┌──────────────────┐                               │
	│                      │  ClearRoom       │  COMPOUND                     │
	│                      │  (high-level)    │                               │
	│                      └────────┬─────────┘                               │
	│                               │                                         │
	│              ┌────────────────┼────────────────┐                        │
	│              ▼                ▼                ▼                        │
	│     ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │
	│     │ ScanForEnemy │  │ EngageEnemy  │  │ SecureExits  │  COMPOUND     │
	│     └──────┬───────┘  └──────┬───────┘  └──────┬───────┘               │
	│            │                 │                 │                        │
	│            ▼                 ▼                 ▼                        │
	│     ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │
	│     │    Look      │  │    Shoot     │  │  MoveToDoor  │  PRIMITIVE    │
	│     │   (Action)   │  │   (Action)   │  │   (Action)   │               │
	│     └──────────────┘  └──────────────┘  └──────────────┘               │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          API QUICK REFERENCE                            │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│  CONSTRUCTORS                                                           │
	│    Task.newPrimitive(config)        Create primitive task (with Action) │
	│    Task.newCompound(config)         Create compound task (with Methods) │
	│                                                                         │
	│  IDENTITY                                                               │
	│    :getName()                       Get task name                       │
	│    :getType()                       Get "primitive" or "compound"       │
	│    :isPrimitive()                   Check if primitive task             │
	│    :isCompound()                    Check if compound task              │
	│                                                                         │
	│  PRIMITIVE TASK METHODS                                                 │
	│    :getAction()                     Get underlying Action               │
	│    :checkPreconditions(state)       Check Action preconditions          │
	│    :applyEffects(state)             Apply Action effects                │
	│                                                                         │
	│  COMPOUND TASK METHODS                                                  │
	│    :getMethods()                    Get decomposition methods           │
	│    :addMethod(method)               Add a decomposition method          │
	│    :removeMethod(name)              Remove method by name               │
	│    :getMethodCount()                Get number of methods               │
	│                                                                         │
	│  DEBUGGING                                                              │
	│    :debugSummary()                  Get human-readable summary          │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class Task
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Primitive Task (Maps to Action)

	```lua
	local shootTask = Task.newPrimitive({
		name = "Shoot",
		action = Action.new({
			name = "Shoot",
			preconditions = { hasAmmo = true, targetVisible = true },
			effects = { targetDamaged = true },
			executeFn = function(agent) return true end
		})
	})
	```

	## Compound Task (Decomposes via Methods)

	```lua
	local engageTask = Task.newCompound({
		name = "EngageEnemy",
		methods = {
			Method.new({
				name = "DirectAttack",
				preconditions = { hasAmmo = true },
				subtasks = { "Shoot" },
			}),
			Method.new({
				name = "ReloadFirst",
				preconditions = { hasAmmo = false },
				subtasks = { "Reload", "Shoot" },
			}),
		}
	})
	```
]]

local Action = require(script.Parent.Parent.Action)
local State = require(script.Parent.Parent.State)

--// ============================================================================
--// TYPE DEFINITIONS
--// ============================================================================

--// Task type: primitive (executable) or compound (decomposable)
export type TaskType = "primitive" | "compound"

--// Forward declaration for Method (defined in Method.lua)
export type MethodLike = {
	getName: (self: MethodLike) -> string,
	checkPreconditions: (self: MethodLike, worldState: State.State) -> boolean,
	isValid: (self: MethodLike, worldState: State.State, agent: any?) -> boolean,
	getSubtasks: (self: MethodLike) -> { string },
	getCost: (self: MethodLike) -> number,
}

--// Configuration for creating a primitive task
export type PrimitiveTaskConfig = {
	name: string,
	action: Action.Action?,
	actionConfig: Action.ActionConfig?,
}

--// Configuration for creating a compound task
export type CompoundTaskConfig = {
	name: string,
	methods: { MethodLike }?,
}

--// ============================================================================
--// CONSTANTS
--// ============================================================================

local LOG_PREFIX = "[Goal.Task]"

--// ============================================================================
--// CLASS DEFINITION
--// ============================================================================

local Task = {}
Task.__index = Task

--// ============================================================================
--// CONSTRUCTORS
--// ============================================================================

--[[
	Creates a new primitive task backed by an Action.

	Primitive tasks are the "leaf nodes" of HTN planning - they map directly
	to executable Actions. When the HTN planner reaches a primitive task,
	it adds the underlying Action to the plan.

	@param config PrimitiveTaskConfig -- Configuration with name and action
	@return Task -- New primitive task
]]
function Task.newPrimitive(config: PrimitiveTaskConfig): Task
	assert(config.name and #config.name > 0, LOG_PREFIX .. " Primitive task requires a name")
	assert(config.action or config.actionConfig, LOG_PREFIX .. " Primitive task requires an action or actionConfig")

	local self = setmetatable({}, Task)

	self._name = config.name
	self._type = "primitive" :: TaskType
	self._methods = nil :: { MethodLike }?

	-- Create action from config if provided, otherwise use direct action
	if config.actionConfig then
		self._action = Action.new(config.actionConfig)
	else
		self._action = config.action
	end

	return self
end

--[[
	Creates a new compound task that decomposes into subtasks.

	Compound tasks are high-level behaviors that break down into sequences
	of simpler tasks. Each compound task has one or more Methods that define
	how to decompose it based on the current world state.

	@param config CompoundTaskConfig -- Configuration with name and methods
	@return Task -- New compound task
]]
function Task.newCompound(config: CompoundTaskConfig): Task
	assert(config.name and #config.name > 0, LOG_PREFIX .. " Compound task requires a name")

	local self = setmetatable({}, Task)

	self._name = config.name
	self._type = "compound" :: TaskType
	self._action = nil :: Action.Action?
	self._methods = config.methods or {} :: { MethodLike }

	return self
end

--// ============================================================================
--// IDENTITY METHODS
--// ============================================================================

--[[
	Gets the name of this task.

	@return string -- Task name
]]
function Task:getName(): string
	return self._name
end

--[[
	Gets the type of this task.

	@return TaskType -- "primitive" or "compound"
]]
function Task:getType(): TaskType
	return self._type
end

--[[
	Checks if this is a primitive (directly executable) task.

	@return boolean -- True if primitive
]]
function Task:isPrimitive(): boolean
	return self._type == "primitive"
end

--[[
	Checks if this is a compound (decomposable) task.

	@return boolean -- True if compound
]]
function Task:isCompound(): boolean
	return self._type == "compound"
end

--// ============================================================================
--// PRIMITIVE TASK METHODS
--// ============================================================================

--[[
	Gets the underlying Action for a primitive task.

	@return Action? -- The action, or nil if compound task
]]
function Task:getAction(): Action.Action?
	if self._type ~= "primitive" then
		warn(LOG_PREFIX .. " getAction() called on compound task: " .. self._name)
		return nil
	end
	return self._action
end

--[[
	Checks if the primitive task's Action preconditions are satisfied.

	@param worldState State -- Current world state
	@return boolean -- True if preconditions are met
]]
function Task:checkPreconditions(worldState: State.State): boolean
	if self._type ~= "primitive" then
		warn(LOG_PREFIX .. " checkPreconditions() called on compound task: " .. self._name)
		return false
	end

	if not self._action then
		return false
	end

	return self._action:checkPreconditions(worldState)
end

--[[
	Applies the primitive task's Action effects to a state.

	@param state State -- State to modify (creates new state)
	@return State -- New state with effects applied
]]
function Task:applyEffects(state: State.State): State.State
	if self._type ~= "primitive" then
		warn(LOG_PREFIX .. " applyEffects() called on compound task: " .. self._name)
		return state:clone()
	end

	if not self._action then
		return state:clone()
	end

	return self._action:applyEffects(state)
end

--[[
	Checks if the primitive task can be executed.

	@param worldState State -- Current world state
	@param agent any? -- Optional agent context
	@return boolean -- True if can execute
]]
function Task:canExecute(worldState: State.State, agent: any?): boolean
	if self._type ~= "primitive" then
		return false
	end

	if not self._action then
		return false
	end

	return self._action:canExecute(worldState, agent)
end

--[[
	Executes the primitive task's Action.

	@param agent any? -- Optional agent context
	@param context any? -- Optional execution context
	@return boolean -- True if execution succeeded
]]
function Task:execute(agent: any?, context: any?): boolean
	if self._type ~= "primitive" then
		warn(LOG_PREFIX .. " execute() called on compound task: " .. self._name)
		return false
	end

	if not self._action then
		return false
	end

	return self._action:execute(agent, context)
end

--// ============================================================================
--// COMPOUND TASK METHODS
--// ============================================================================

--[[
	Gets all decomposition methods for a compound task.

	@return { MethodLike } -- Array of methods (empty if primitive)
]]
function Task:getMethods(): { MethodLike }
	if self._type ~= "compound" then
		return {}
	end
	return self._methods or {}
end

--[[
	Adds a decomposition method to a compound task.

	@param method MethodLike -- Method to add
]]
function Task:addMethod(method: MethodLike): ()
	if self._type ~= "compound" then
		warn(LOG_PREFIX .. " addMethod() called on primitive task: " .. self._name)
		return
	end

	if not self._methods then
		self._methods = {}
	end

	table.insert(self._methods, method)
end

--[[
	Removes a decomposition method by name.

	@param methodName string -- Name of method to remove
	@return boolean -- True if method was found and removed
]]
function Task:removeMethod(methodName: string): boolean
	if self._type ~= "compound" or not self._methods then
		return false
	end

	for i, method in ipairs(self._methods) do
		if method:getName() == methodName then
			table.remove(self._methods, i)
			return true
		end
	end

	return false
end

--[[
	Gets the number of decomposition methods.

	@return number -- Method count (0 if primitive)
]]
function Task:getMethodCount(): number
	if self._type ~= "compound" or not self._methods then
		return 0
	end
	return #self._methods
end

--[[
	Gets valid methods for the current world state.

	@param worldState State -- Current world state
	@param agent any? -- Optional agent context
	@return { MethodLike } -- Array of valid methods
]]
function Task:getValidMethods(worldState: State.State, agent: any?): { MethodLike }
	if self._type ~= "compound" or not self._methods then
		return {}
	end

	local validMethods: { MethodLike } = {}

	for _, method in ipairs(self._methods) do
		if method:checkPreconditions(worldState) and method:isValid(worldState, agent) then
			table.insert(validMethods, method)
		end
	end

	return validMethods
end

--// ============================================================================
--// DEBUGGING
--// ============================================================================

--[[
	Gets a human-readable summary of this task.

	@return string -- Debug summary
]]
function Task:debugSummary(): string
	local lines: { string } = {}

	table.insert(lines, string.format("Task: %s [%s]", self._name, self._type))

	if self._type == "primitive" then
		if self._action then
			table.insert(lines, "  Action: " .. self._action:getName())
			local preconds = self._action:getPreconditions()
			if preconds then
				local precondData = preconds:getData()
				local precondStr = {}
				for k, v in pairs(precondData) do
					table.insert(precondStr, string.format("%s=%s", k, tostring(v)))
				end
				if #precondStr > 0 then
					table.insert(lines, "  Preconditions: " .. table.concat(precondStr, ", "))
				end
			end
		else
			table.insert(lines, "  Action: (none)")
		end
	else
		local methodCount = self._methods and #self._methods or 0
		table.insert(lines, string.format("  Methods: %d", methodCount))
		if self._methods then
			for _, method in ipairs(self._methods) do
				table.insert(lines, "    - " .. method:getName())
			end
		end
	end

	return table.concat(lines, "\n")
end

--// ============================================================================
--// TYPE EXPORT
--// ============================================================================

export type Task = typeof(Task.newPrimitive({
	name = "",
	actionConfig = { name = "" },
}))

return Task
