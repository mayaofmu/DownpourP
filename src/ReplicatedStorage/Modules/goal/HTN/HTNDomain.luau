--!strict
--[[
	HTNDomain.lua
	Registry for HTN tasks and methods.

	The HTNDomain is a container that holds all tasks (primitive and compound)
	for a particular AI domain. It provides fast O(1) lookup by task name and
	validation to ensure domain consistency.

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          DOMAIN STRUCTURE                               │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│    HTNDomain: "CombatAI"                                                │
	│    ┌─────────────────────────────────────────────────────────────────┐  │
	│    │                                                                 │  │
	│    │  PRIMITIVE TASKS (leaf nodes - execute Actions)                 │  │
	│    │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │  │
	│    │  │  Shoot   │ │  Reload  │ │ TakeCover│ │   Move   │           │  │
	│    │  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │  │
	│    │                                                                 │  │
	│    │  COMPOUND TASKS (decompose via methods)                         │  │
	│    │  ┌──────────────────────────────────────────────────────────┐  │  │
	│    │  │  EngageEnemy                                             │  │  │
	│    │  │    Method 1: DirectAttack → [Shoot]                      │  │  │
	│    │  │    Method 2: ReloadFirst → [Reload, Shoot]               │  │  │
	│    │  └──────────────────────────────────────────────────────────┘  │  │
	│    │  ┌──────────────────────────────────────────────────────────┐  │  │
	│    │  │  ClearRoom                                               │  │  │
	│    │  │    Method 1: Systematic → [ScanArea, EngageEnemy, ...]   │  │  │
	│    │  └──────────────────────────────────────────────────────────┘  │  │
	│    │                                                                 │  │
	│    └─────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          API QUICK REFERENCE                            │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│  CONSTRUCTOR                                                            │
	│    HTNDomain.new(config)            Create a new domain                 │
	│                                                                         │
	│  IDENTITY                                                               │
	│    :getName()                       Get domain name                     │
	│                                                                         │
	│  TASK MANAGEMENT                                                        │
	│    :registerTask(task)              Add task to domain                  │
	│    :registerTasks(tasks)            Add multiple tasks                  │
	│    :getTask(name)                   Get task by name                    │
	│    :hasTask(name)                   Check if task exists                │
	│    :removeTask(name)                Remove task by name                 │
	│    :clearTasks()                    Remove all tasks                    │
	│                                                                         │
	│  QUERIES                                                                │
	│    :getTaskCount()                  Total task count                    │
	│    :getPrimitiveCount()             Count of primitive tasks            │
	│    :getCompoundCount()              Count of compound tasks             │
	│    :getAllTaskNames()               Get all task names                  │
	│    :getPrimitiveTasks()             Get all primitive tasks             │
	│    :getCompoundTasks()              Get all compound tasks              │
	│                                                                         │
	│  VALIDATION                                                             │
	│    :validate()                      Check domain consistency            │
	│                                                                         │
	│  DEBUGGING                                                              │
	│    :debugSummary()                  Get human-readable summary          │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class HTNDomain
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Creating a Domain

	```lua
	local domain = HTNDomain.new({ name = "CombatAI" })

	-- Register primitive tasks
	domain:registerTask(shootTask)
	domain:registerTask(reloadTask)
	domain:registerTask(takeCoverTask)

	-- Register compound tasks
	domain:registerTask(engageEnemyTask)
	domain:registerTask(clearRoomTask)

	-- Validate domain
	local isValid, errors = domain:validate()
	if not isValid then
		for _, err in errors do
			warn(err)
		end
	end
	```
]]

local Task = require(script.Parent.Task)

--// ============================================================================
--// TYPE DEFINITIONS
--// ============================================================================

--// Configuration for creating a domain
export type HTNDomainConfig = {
	name: string,
}

--// ============================================================================
--// CONSTANTS
--// ============================================================================

local LOG_PREFIX = "[Goal.HTNDomain]"

--// ============================================================================
--// CLASS DEFINITION
--// ============================================================================

local HTNDomain = {}
HTNDomain.__index = HTNDomain

--// ============================================================================
--// CONSTRUCTOR
--// ============================================================================

--[[
	Creates a new HTN domain.

	A domain is a registry of all tasks available for HTN planning.
	Tasks can be registered incrementally and the domain can be validated
	to ensure all task references are resolvable.

	@param config HTNDomainConfig -- Configuration with domain name
	@return HTNDomain -- New domain
]]
function HTNDomain.new(config: HTNDomainConfig): HTNDomain
	assert(config.name and #config.name > 0, LOG_PREFIX .. " Domain requires a name")

	local self = setmetatable({}, HTNDomain)

	self._name = config.name
	self._tasks = {} :: { [string]: Task.Task }
	self._primitiveCount = 0
	self._compoundCount = 0

	return self
end

--// ============================================================================
--// IDENTITY METHODS
--// ============================================================================

--[[
	Gets the name of this domain.

	@return string -- Domain name
]]
function HTNDomain:getName(): string
	return self._name
end

--// ============================================================================
--// TASK MANAGEMENT
--// ============================================================================

--[[
	Registers a task in the domain.

	@param task Task -- Task to register
	@return boolean -- True if registered (false if duplicate name)
]]
function HTNDomain:registerTask(task: Task.Task): boolean
	local name = task:getName()

	if self._tasks[name] then
		warn(LOG_PREFIX .. " Task already registered: " .. name)
		return false
	end

	self._tasks[name] = task

	if task:isPrimitive() then
		self._primitiveCount += 1
	else
		self._compoundCount += 1
	end

	return true
end

--[[
	Registers multiple tasks at once.

	@param tasks { Task } -- Array of tasks to register
	@return number -- Number of tasks successfully registered
]]
function HTNDomain:registerTasks(tasks: { Task.Task }): number
	local count = 0
	for _, task in ipairs(tasks) do
		if self:registerTask(task) then
			count += 1
		end
	end
	return count
end

--[[
	Gets a task by name.

	@param name string -- Task name
	@return Task? -- Task or nil if not found
]]
function HTNDomain:getTask(name: string): Task.Task?
	return self._tasks[name]
end

--[[
	Checks if a task exists in the domain.

	@param name string -- Task name
	@return boolean -- True if task exists
]]
function HTNDomain:hasTask(name: string): boolean
	return self._tasks[name] ~= nil
end

--[[
	Removes a task from the domain.

	@param name string -- Task name to remove
	@return boolean -- True if task was removed
]]
function HTNDomain:removeTask(name: string): boolean
	local task = self._tasks[name]
	if not task then
		return false
	end

	if task:isPrimitive() then
		self._primitiveCount -= 1
	else
		self._compoundCount -= 1
	end

	self._tasks[name] = nil
	return true
end

--[[
	Removes all tasks from the domain.
]]
function HTNDomain:clearTasks(): ()
	self._tasks = {}
	self._primitiveCount = 0
	self._compoundCount = 0
end

--// ============================================================================
--// QUERY METHODS
--// ============================================================================

--[[
	Gets the total number of registered tasks.

	@return number -- Task count
]]
function HTNDomain:getTaskCount(): number
	return self._primitiveCount + self._compoundCount
end

--[[
	Gets the number of primitive tasks.

	@return number -- Primitive task count
]]
function HTNDomain:getPrimitiveCount(): number
	return self._primitiveCount
end

--[[
	Gets the number of compound tasks.

	@return number -- Compound task count
]]
function HTNDomain:getCompoundCount(): number
	return self._compoundCount
end

--[[
	Gets all task names in the domain.

	@return { string } -- Array of task names
]]
function HTNDomain:getAllTaskNames(): { string }
	local names: { string } = {}
	for name in pairs(self._tasks) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

--[[
	Gets all primitive tasks.

	@return { Task } -- Array of primitive tasks
]]
function HTNDomain:getPrimitiveTasks(): { Task.Task }
	local tasks: { Task.Task } = {}
	for _, task in pairs(self._tasks) do
		if task:isPrimitive() then
			table.insert(tasks, task)
		end
	end
	return tasks
end

--[[
	Gets all compound tasks.

	@return { Task } -- Array of compound tasks
]]
function HTNDomain:getCompoundTasks(): { Task.Task }
	local tasks: { Task.Task } = {}
	for _, task in pairs(self._tasks) do
		if task:isCompound() then
			table.insert(tasks, task)
		end
	end
	return tasks
end

--// ============================================================================
--// VALIDATION
--// ============================================================================

--[[
	Validates the domain for consistency.

	Checks:
	- All subtask references in methods resolve to registered tasks
	- No circular dependencies (optional, expensive)

	@return (boolean, { string }?) -- (isValid, errors)
]]
function HTNDomain:validate(): (boolean, { string }?)
	local errors: { string } = {}

	-- Check all subtask references
	for taskName, task in pairs(self._tasks) do
		if task:isCompound() then
			local methods = task:getMethods()
			for _, method in ipairs(methods) do
				local subtasks = method:getSubtasks()
				for _, subtaskName in ipairs(subtasks) do
					if not self._tasks[subtaskName] then
						table.insert(
							errors,
							string.format(
								"Task '%s' method '%s' references unknown subtask '%s'",
								taskName,
								method:getName(),
								subtaskName
							)
						)
					end
				end
			end
		end
	end

	if #errors > 0 then
		return false, errors
	end

	return true, nil
end

--[[
	Finds all tasks that reference a given task name.

	Useful for understanding task dependencies.

	@param taskName string -- Task name to search for
	@return { string } -- Array of task names that reference this task
]]
function HTNDomain:findReferencingTasks(taskName: string): { string }
	local referencing: { string } = {}

	for name, task in pairs(self._tasks) do
		if task:isCompound() then
			local methods = task:getMethods()
			for _, method in ipairs(methods) do
				local subtasks = method:getSubtasks()
				for _, subtask in ipairs(subtasks) do
					if subtask == taskName then
						table.insert(referencing, name)
						break
					end
				end
			end
		end
	end

	return referencing
end

--// ============================================================================
--// DEBUGGING
--// ============================================================================

--[[
	Gets a human-readable summary of this domain.

	@return string -- Debug summary
]]
function HTNDomain:debugSummary(): string
	local lines: { string } = {}

	table.insert(lines, string.format("HTNDomain: %s", self._name))
	table.insert(lines, string.format("  Total Tasks: %d", self:getTaskCount()))
	table.insert(lines, string.format("  Primitive: %d", self._primitiveCount))
	table.insert(lines, string.format("  Compound: %d", self._compoundCount))

	-- List primitive tasks
	table.insert(lines, "\n  Primitive Tasks:")
	for _, task in pairs(self._tasks) do
		if task:isPrimitive() then
			local action = task:getAction()
			local actionName = action and action:getName() or "(no action)"
			table.insert(lines, string.format("    - %s → %s", task:getName(), actionName))
		end
	end

	-- List compound tasks
	table.insert(lines, "\n  Compound Tasks:")
	for _, task in pairs(self._tasks) do
		if task:isCompound() then
			local methods = task:getMethods()
			table.insert(lines, string.format("    - %s (%d methods)", task:getName(), #methods))
			for _, method in ipairs(methods) do
				local subtasks = method:getSubtasks()
				table.insert(lines, string.format("        %s: %s", method:getName(), table.concat(subtasks, " → ")))
			end
		end
	end

	-- Validation status
	local isValid, errors = self:validate()
	if isValid then
		table.insert(lines, "\n  Validation: PASSED")
	else
		table.insert(lines, "\n  Validation: FAILED")
		if errors then
			for _, err in ipairs(errors) do
				table.insert(lines, "    - " .. err)
			end
		end
	end

	return table.concat(lines, "\n")
end

--// ============================================================================
--// TYPE EXPORT
--// ============================================================================

export type HTNDomain = typeof(HTNDomain.new({ name = "" }))

return HTNDomain
