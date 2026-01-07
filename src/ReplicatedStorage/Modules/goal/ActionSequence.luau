--!strict
--[[
	ActionSequence.lua
	Chains multiple actions together for complex multi-step behaviors.

	ActionSequence allows you to define ordered sequences of actions
	that execute one after another. Useful for:
	- Combat combos (light attack -> heavy attack -> finisher)
	- Crafting recipes (gather materials -> craft item -> store)
	- Complex behaviors (patrol -> investigate -> return)

	┌─────────────────────────────────────────────────────────────────────────┐
	│                       SEQUENCE EXECUTION FLOW                           │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│    ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌──────────┐              │
	│    │ Action1 │──▶│ Action2 │──▶│ Action3 │──▶│ Complete │              │
	│    └────┬────┘   └────┬────┘   └────┬────┘   └──────────┘              │
	│         │             │             │                                   │
	│         ▼             ▼             ▼                                   │
	│    On Failure:   On Failure:   On Failure:                              │
	│    • skip        • retry       • abort                                  │
	│    • retry       • skip        (configurable)                           │
	│    • abort       • abort                                                │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          API QUICK REFERENCE                            │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│  CONSTRUCTOR                                                            │
	│    ActionSequence.new(config)      Create a new sequence                │
	│                                                                         │
	│  IDENTITY                                                               │
	│    :getName()                      Get sequence name                    │
	│    :getGroup()                     Get sequence group                   │
	│    :hasTag(tag)                    Check if has tag                     │
	│    :getTags()                      Get all tags                         │
	│                                                                         │
	│  ACTION MANAGEMENT                                                      │
	│    :addAction(action)              Add action to end                    │
	│    :addActions(actions)            Add multiple actions                 │
	│    :getActions()                   Get all actions                      │
	│    :getAction(index)               Get action by index                  │
	│    :getActionCount()               Get number of actions                │
	│    :isEmpty()                      Check if no actions                  │
	│    :clearActions()                 Remove all actions                   │
	│                                                                         │
	│  EXECUTION                                                              │
	│    :start()                        Begin execution                      │
	│    :executeStep(agent, context?)   Execute next step                    │
	│    :executeAll(agent, context?)    Execute all steps                    │
	│    :reset()                        Reset to beginning                   │
	│                                                                         │
	│  STATUS                                                                 │
	│    :isExecuting()                  Check if currently running           │
	│    :isComplete()                   Check if finished                    │
	│    :getCurrentStep()               Get current step number              │
	│    :getCurrentAction()             Get current action                   │
	│    :getProgress()                  Get {current, total, percent}        │
	│    :getCompletedSteps()            Get count of completed steps         │
	│    :wasInterrupted()               Check if was interrupted             │
	│                                                                         │
	│  VALIDATION                                                             │
	│    :checkPreconditions(state)      Check if can start                   │
	│    :canExecute(state, agent?)      Full validation check                │
	│                                                                         │
	│  COST & EFFECTS                                                         │
	│    :getCost(state?, agent?)        Get total sequence cost              │
	│    :applyEffects(state)            Apply all effects                    │
	│    :getPreconditions()             Get first action preconditions       │
	│    :getEffects()                   Get combined effects                 │
	│                                                                         │
	│  INTERRUPT HANDLING                                                     │
	│    :canInterrupt()                 Check if interruptible               │
	│    :interrupt(agent?)              Interrupt execution                  │
	│                                                                         │
	│  DEBUGGING                                                              │
	│    :debugSummary()                 Get human-readable summary           │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class ActionSequence
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Features

	- **Ordered Execution**: Execute actions one after another
	- **Failure Strategies**: skip, retry, or abort on failure
	- **Progress Callbacks**: Track step-by-step progress
	- **Interrupt Support**: Graceful cancellation
	- **Combined Effects**: Calculates total cost and effects

	## Basic Sequence

	```lua
	local attackCombo = ActionSequence.new({
		name = "AttackCombo",
		actions = { lightAttack, heavyAttack, finisher },
		failureStrategy = "abort",
	})

	-- Execute step by step
	while attackCombo:isExecuting() do
		local success, status = attackCombo:executeStep(agent)
		if status == "complete" then break end
	end
	```

	## With Callbacks

	```lua
	local craftSequence = ActionSequence.new({
		name = "CraftItem",
		actions = { gatherMaterials, useWorkbench, craftItem },
		onStepComplete = function(step, action, success)
			print("Step", step, ":", action:getName(), success and "OK" or "FAILED")
		end,
		onSequenceComplete = function(success, completedSteps)
			print("Crafting", success and "complete!" or "failed at step", completedSteps)
		end,
	})
	```

	## Configuration Options

	| Option             | Type       | Description                          |
	|--------------------|------------|--------------------------------------|
	| name               | string     | Sequence identifier (required)       |
	| actions            | array      | Actions to execute (required)        |
	| failureStrategy    | string?    | "abort", "skip", "retry" (default)   |
	| maxRetries         | number?    | Max retries per action (default: 3)  |
	| onStepComplete     | function?  | Called after each step               |
	| onSequenceComplete | function?  | Called when sequence ends            |
	| interruptible      | boolean?   | Can be interrupted (default: true)   |
	| onInterrupt        | function?  | Called when interrupted              |
	| group              | string?    | Sequence group                       |
	| tags               | {string}?  | Array of tags                        |
]]

local Action = require(script.Parent.Action)
local State = require(script.Parent.State)

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

--[=[
	@type FailureStrategy "skip" | "retry" | "abort"
	@within ActionSequence

	Defines how the sequence handles action failures:
	- "skip": Skip the failed action and continue to the next
	- "retry": Retry the failed action (up to maxRetries)
	- "abort": Stop the sequence immediately (default)
]=]
export type FailureStrategy = "skip" | "retry" | "abort"

--[=[
	@type ExecutionStatus "complete" | "continue" | "skipped" | "retrying" | "interrupted" | "aborted" | "max_retries_exceeded"
	@within ActionSequence

	Status returned by executeStep():
	- "complete": Sequence finished successfully
	- "continue": Step succeeded, more steps remaining
	- "skipped": Step failed but was skipped
	- "retrying": Step failed and will retry
	- "interrupted": Sequence was interrupted
	- "aborted": Sequence aborted due to failure
	- "max_retries_exceeded": Failed after max retry attempts
]=]
export type ExecutionStatus =
	"complete"
	| "continue"
	| "skipped"
	| "retrying"
	| "interrupted"
	| "aborted"
	| "max_retries_exceeded"

--[=[
	@type OnStepCompleteFn (stepIndex: number, action: Action, success: boolean) -> ()
	@within ActionSequence
	Callback invoked after each step.
]=]
type OnStepCompleteFn = (stepIndex: number, action: Action.Action, success: boolean) -> ()

--[=[
	@type OnSequenceCompleteFn (success: boolean, completedSteps: number) -> ()
	@within ActionSequence
	Callback invoked when sequence ends.
]=]
type OnSequenceCompleteFn = (success: boolean, completedSteps: number) -> ()

--[=[
	@type OnInterruptFn (stepIndex: number, action: Action) -> ()
	@within ActionSequence
	Callback invoked when sequence is interrupted.
]=]
type OnInterruptFn = (stepIndex: number, action: Action.Action) -> ()

--[=[
	@interface ActionSequenceConfig
	@within ActionSequence
	.name string -- Unique identifier for the sequence (REQUIRED)
	.actions { Action } -- Array of actions to execute in order (REQUIRED)
	.failureStrategy FailureStrategy? -- How to handle failures (default: "abort")
	.maxRetries number? -- Max retries per action when using "retry" strategy (default: 3)
	.onStepComplete OnStepCompleteFn? -- Called after each step
	.onSequenceComplete OnSequenceCompleteFn? -- Called when sequence ends
	.onInterrupt OnInterruptFn? -- Called when interrupted
	.interruptible boolean? -- Can be interrupted (default: true)
]=]
export type ActionSequenceConfig = {
	name: string,
	actions: { Action.Action },
	failureStrategy: FailureStrategy?,
	maxRetries: number?,
	onStepComplete: OnStepCompleteFn?,
	onSequenceComplete: OnSequenceCompleteFn?,
	onInterrupt: OnInterruptFn?,
	interruptible: boolean?,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

--- Default failure strategy.
local DEFAULT_FAILURE_STRATEGY: FailureStrategy = "abort"

--- Default maximum retry attempts per action.
local DEFAULT_MAX_RETRIES: number = 3

--- Log prefix for warning/error messages.
local LOG_PREFIX = "[Goal.ActionSequence]"

-- ============================================================================
-- CLASS DEFINITION
-- ============================================================================

--[=[
	@class ActionSequence

	Chains multiple actions together for complex multi-step behaviors.
	Supports ordered execution with failure handling strategies.
]=]
local ActionSequence = {}
ActionSequence.__index = ActionSequence

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

--[=[
	Creates a new ActionSequence.

	@param config ActionSequenceConfig -- Sequence configuration table
	@return ActionSequence -- The newly created sequence

	@error "ActionSequence config must have a 'name' field" -- When name is missing
	@error "ActionSequence config must have an 'actions' field" -- When actions is missing

	@example
	```lua
	local sequence = ActionSequence.new({
		name = "GatherAndBuild",
		actions = { gatherWood, gatherStone, buildShelter },
		failureStrategy = "skip",
		onSequenceComplete = function(success, steps)
			print("Completed", steps, "steps")
		end,
	})
	```
]=]
function ActionSequence.new(config: ActionSequenceConfig): ActionSequence
	-- Validate required fields
	assert(
		config.name ~= nil and type(config.name) == "string",
		`{LOG_PREFIX} ActionSequence config must have a 'name' field (string)`
	)
	assert(
		config.actions ~= nil and type(config.actions) == "table",
		`{LOG_PREFIX} ActionSequence config must have an 'actions' field (array)`
	)

	-- Validate failure strategy if provided
	if config.failureStrategy ~= nil then
		assert(
			config.failureStrategy == "skip" or config.failureStrategy == "retry" or config.failureStrategy == "abort",
			`{LOG_PREFIX} failureStrategy must be "skip", "retry", or "abort"`
		)
	end

	local self = setmetatable({}, ActionSequence)

	-- Configuration
	self.name = config.name
	self._actions = table.clone(config.actions)
	self.failureStrategy = config.failureStrategy or DEFAULT_FAILURE_STRATEGY
	self.maxRetries = config.maxRetries or DEFAULT_MAX_RETRIES
	self.interruptible = if config.interruptible ~= nil then config.interruptible else true

	-- Callbacks
	self._onStepComplete = config.onStepComplete
	self._onSequenceComplete = config.onSequenceComplete
	self._onInterrupt = config.onInterrupt

	-- Execution state
	self._currentStep = 0
	self._isExecuting = false
	self._wasInterrupted = false
	self._retryCount = 0
	self._completedSteps = 0

	return self
end

-- ============================================================================
-- BASIC PROPERTIES
-- ============================================================================

--[=[
	Gets the name of this sequence.

	@return string -- The sequence's unique identifier

	@example
	```lua
	print("Executing sequence:", sequence:getName())
	```
]=]
function ActionSequence:getName(): string
	return self.name
end

--[=[
	Gets all actions in the sequence.

	@return { Action } -- Array of actions in execution order

	@example
	```lua
	local actions = sequence:getActions()
	for i, action in ipairs(actions) do
		print(i, action:getName())
	end
	```
]=]
function ActionSequence:getActions(): { Action.Action }
	return self._actions
end

--[=[
	Gets the action at a specific index.

	@param index number -- The 1-based index
	@return Action? -- The action at that index, or nil if invalid

	@example
	```lua
	local firstAction = sequence:getAction(1)
	```
]=]
function ActionSequence:getAction(index: number): Action.Action?
	return self._actions[index]
end

--[=[
	Gets the number of actions in the sequence.

	@return number -- Count of actions

	@example
	```lua
	print("Sequence has", sequence:getLength(), "steps")
	```
]=]
function ActionSequence:getLength(): number
	return #self._actions
end

--[=[
	Checks if the sequence is empty.

	@return boolean -- True if sequence has no actions

	@example
	```lua
	if sequence:isEmpty() then
		warn("Sequence has no actions!")
	end
	```
]=]
function ActionSequence:isEmpty(): boolean
	return #self._actions == 0
end

-- ============================================================================
-- ACTION MANAGEMENT
-- ============================================================================

--[=[
	Adds an action to the end of the sequence.

	@param action Action -- The action to add

	@example
	```lua
	sequence:addAction(newAction)
	```
]=]
function ActionSequence:addAction(action: Action.Action)
	assert(action ~= nil, `{LOG_PREFIX} action cannot be nil`)
	table.insert(self._actions, action)
end

--[=[
	Inserts an action at a specific position.

	@param index number -- The position to insert at (1-based)
	@param action Action -- The action to insert

	@example
	```lua
	-- Insert at the beginning
	sequence:insertAction(1, prepareAction)
	```
]=]
function ActionSequence:insertAction(index: number, action: Action.Action)
	assert(type(index) == "number" and index >= 1, `{LOG_PREFIX} index must be a positive number`)
	assert(action ~= nil, `{LOG_PREFIX} action cannot be nil`)
	table.insert(self._actions, index, action)
end

--[=[
	Removes an action at a specific position.

	@param index number -- The position to remove from (1-based)
	@return Action? -- The removed action, or nil if index invalid

	@example
	```lua
	local removed = sequence:removeAction(3)
	if removed then
		print("Removed:", removed:getName())
	end
	```
]=]
function ActionSequence:removeAction(index: number): Action.Action?
	if index < 1 or index > #self._actions then
		return nil
	end
	return table.remove(self._actions, index)
end

--[=[
	Clears all actions from the sequence.

	@example
	```lua
	sequence:clearActions()
	```
]=]
function ActionSequence:clearActions()
	table.clear(self._actions)
	self:reset()
end

-- ============================================================================
-- EXECUTION STATE
-- ============================================================================

--[=[
	Gets the current step index (1-based).

	Returns 0 if the sequence hasn't started yet.

	@return number -- Current step index

	@example
	```lua
	local step = sequence:getCurrentStep()
	print("On step", step, "of", sequence:getLength())
	```
]=]
function ActionSequence:getCurrentStep(): number
	return self._currentStep
end

--[=[
	Gets the action currently being executed.

	@return Action? -- Current action, or nil if not executing

	@example
	```lua
	local current = sequence:getCurrentAction()
	if current then
		print("Currently executing:", current:getName())
	end
	```
]=]
function ActionSequence:getCurrentAction(): Action.Action?
	if self._currentStep >= 1 and self._currentStep <= #self._actions then
		return self._actions[self._currentStep]
	end
	return nil
end

--[=[
	Checks if the sequence is currently executing.

	@return boolean -- True if sequence is in progress

	@example
	```lua
	if sequence:isExecuting() then
		print("Sequence in progress...")
	end
	```
]=]
function ActionSequence:isExecuting(): boolean
	return self._isExecuting
end

--[=[
	Checks if the sequence has been completed (either success or failure).

	@return boolean -- True if sequence has finished

	@example
	```lua
	if sequence:isComplete() then
		print("Sequence finished")
	end
	```
]=]
function ActionSequence:isComplete(): boolean
	return not self._isExecuting and self._currentStep >= #self._actions
end

--[=[
	Gets the progress through the sequence as a percentage.

	@return number -- Progress from 0 to 1

	@example
	```lua
	local progress = sequence:getProgress()
	print(string.format("%.0f%% complete", progress * 100))
	```
]=]
function ActionSequence:getProgress(): number
	if #self._actions == 0 then
		return 1
	end
	return self._currentStep / #self._actions
end

--[=[
	Resets the sequence to initial state.

	Clears execution state so the sequence can be run again.

	@example
	```lua
	sequence:reset()
	-- Now sequence can be executed from the beginning
	```
]=]
function ActionSequence:reset()
	self._currentStep = 0
	self._isExecuting = false
	self._wasInterrupted = false
	self._retryCount = 0
	self._completedSteps = 0
end

-- ============================================================================
-- INTERRUPT HANDLING
-- ============================================================================

--[=[
	Checks if the sequence can be interrupted.

	A sequence can be interrupted if:
	1. The interruptible property is true (default)
	2. The sequence is currently executing
	3. The current action (if any) is interruptible

	@return boolean -- True if sequence can be interrupted

	@example
	```lua
	if sequence:canInterrupt() then
		sequence:interrupt()
	end
	```
]=]
function ActionSequence:canInterrupt(): boolean
	if not self.interruptible then
		return false
	end

	if not self._isExecuting then
		return false
	end

	-- Check if current action is interruptible
	local currentAction = self:getCurrentAction()
	if currentAction and currentAction.interruptible == false then
		return false
	end

	return true
end

--[=[
	Interrupts the sequence execution.

	Stops the sequence and calls the onInterrupt callback if provided.

	@return boolean -- True if interrupt was successful

	@example
	```lua
	-- During execution, something urgent happens
	if sequence:interrupt() then
		print("Sequence interrupted at step", sequence:getCurrentStep())
	end
	```
]=]
function ActionSequence:interrupt(): boolean
	if not self:canInterrupt() then
		return false
	end

	self._wasInterrupted = true
	self._isExecuting = false

	if self._onInterrupt then
		local currentAction = self:getCurrentAction()
		if currentAction then
			self._onInterrupt(self._currentStep, currentAction)
		end
	end

	return true
end

--[=[
	Checks if the sequence was interrupted.

	@return boolean -- True if sequence was interrupted

	@example
	```lua
	if sequence:wasInterrupted() then
		print("Sequence did not complete naturally")
	end
	```
]=]
function ActionSequence:wasInterrupted(): boolean
	return self._wasInterrupted
end

-- ============================================================================
-- COST & EFFECT CALCULATION
-- ============================================================================

--[=[
	Calculates the total cost of all actions in the sequence.

	Simulates applying each action's effects to calculate accurate
	costs throughout the sequence.

	@param worldState State -- The current world state
	@param agent any? -- Optional agent context
	@return number -- Total cost of all actions

	@example
	```lua
	local totalCost = sequence:getTotalCost(worldState, agent)
	print("Sequence will cost:", totalCost)
	```
]=]
function ActionSequence:getTotalCost(worldState: State.State, agent: any?): number
	local totalCost = 0
	local simulatedState = worldState:clone()

	for _, action in ipairs(self._actions) do
		totalCost += action:getCost(simulatedState, agent)
		simulatedState = action:applyEffects(simulatedState)
	end

	return totalCost
end

--[=[
	Gets the combined effects of all actions.

	Merges all action effects into a single State object.

	@return State -- Combined effects of all actions

	@example
	```lua
	local effects = sequence:getCombinedEffects()
	for key, value in effects:pairs() do
		print("Effect:", key, "=", value)
	end
	```
]=]
function ActionSequence:getCombinedEffects(): State.State
	local combined = State.new({})
	for _, action in ipairs(self._actions) do
		combined:merge(action:getEffects())
	end
	return combined
end

--[=[
	Gets the preconditions of the first action.

	The sequence's preconditions are the preconditions of its first
	action, since that's what must be satisfied to begin.

	@return State -- Preconditions of the first action

	@example
	```lua
	local preconditions = sequence:getPreconditions()
	if worldState:satisfies(preconditions) then
		print("Sequence can start")
	end
	```
]=]
function ActionSequence:getPreconditions(): State.State
	if #self._actions > 0 then
		return self._actions[1]:getPreconditions()
	end
	return State.new({})
end

-- ============================================================================
-- VALIDATION
-- ============================================================================

--[=[
	Checks if all actions in the sequence can be executed.

	Simulates the sequence to verify each action's preconditions,
	validity, cooldowns, and resources can be satisfied.

	@param worldState State -- The current world state
	@param agent any? -- Optional agent context
	@return boolean -- True if all actions can execute
	@return number? -- Index of failing action (if any)
	@return string? -- Reason for failure (if any)

	@example
	```lua
	local canExecute, failingStep, reason = sequence:canExecute(worldState, agent)
	if not canExecute then
		print("Sequence blocked at step", failingStep, ":", reason)
	end
	```
]=]
function ActionSequence:canExecute(worldState: State.State, agent: any?): (boolean, number?, string?)
	if #self._actions == 0 then
		return false, nil, "sequence is empty"
	end

	local simulatedState = worldState:clone()

	for i, action in ipairs(self._actions) do
		-- Check preconditions
		if not action:checkPreconditions(simulatedState) then
			return false, i, "preconditions not met"
		end
		-- Check validation function
		if not action:isValid(simulatedState, agent) then
			return false, i, "validation failed"
		end
		-- Check cooldown if action has it
		if action.isOnCooldown and action:isOnCooldown() then
			return false, i, "action on cooldown"
		end
		-- Check resources if action has them
		if action.checkResources and not action:checkResources(agent) then
			return false, i, "insufficient resources"
		end
		-- Apply effects for next action's simulation
		simulatedState = action:applyEffects(simulatedState)
	end

	return true, nil, nil
end

-- ============================================================================
-- STEP-BY-STEP EXECUTION
-- ============================================================================

--[=[
	Executes the next step in the sequence.

	Advances the sequence by one action. Call repeatedly until
	the sequence completes or fails.

	@param agent any? -- The agent performing the action
	@param context any? -- Additional context
	@return boolean -- True if step succeeded
	@return ExecutionStatus -- Status of the execution

	@example
	```lua
	local success, status = sequence:executeStep(agent)

	if status == "complete" then
		print("All done!")
	elseif status == "continue" then
		print("More steps remaining")
	elseif status == "aborted" then
		print("Sequence failed")
	end
	```
]=]
function ActionSequence:executeStep(agent: any?, context: any?): (boolean, ExecutionStatus)
	-- Check for interruption
	if self._wasInterrupted then
		self._isExecuting = false
		return false, "interrupted"
	end

	-- Check if already complete
	if self._currentStep >= #self._actions then
		self._isExecuting = false
		if self._onSequenceComplete then
			self._onSequenceComplete(true, self._currentStep)
		end
		return true, "complete"
	end

	-- Start executing
	self._isExecuting = true
	self._currentStep += 1

	-- Execute current action
	local action = self._actions[self._currentStep]
	local success = action:execute(agent, context)

	-- Notify step completion
	if self._onStepComplete then
		self._onStepComplete(self._currentStep, action, success)
	end

	-- Handle failure
	if not success then
		return self:_handleFailure(agent, context)
	end

	-- Reset retry count on success
	self._retryCount = 0
	self._completedSteps = self._currentStep

	-- Check if sequence is complete
	if self._currentStep >= #self._actions then
		self._isExecuting = false
		if self._onSequenceComplete then
			self._onSequenceComplete(true, self._currentStep)
		end
		return true, "complete"
	end

	return true, "continue"
end

--[=[
	Handles action failure based on the configured strategy.

	@param agent any? -- The agent
	@param context any? -- The context
	@return boolean -- Success status
	@return ExecutionStatus -- Status message
	@private
]=]
function ActionSequence:_handleFailure(_agent: any?, _context: any?): (boolean, ExecutionStatus)
	if self.failureStrategy == "skip" then
		-- Skip failed action and continue
		self._completedSteps = self._currentStep - 1

		-- Check if this was the last action
		if self._currentStep >= #self._actions then
			self._isExecuting = false
			if self._onSequenceComplete then
				self._onSequenceComplete(true, self._completedSteps)
			end
			return true, "complete"
		end

		return true, "skipped"
	elseif self.failureStrategy == "retry" then
		-- Retry the failed action
		self._retryCount += 1
		if self._retryCount >= self.maxRetries then
			self._isExecuting = false
			if self._onSequenceComplete then
				self._onSequenceComplete(false, self._completedSteps)
			end
			return false, "max_retries_exceeded"
		end
		self._currentStep -= 1 -- Go back to retry
		return true, "retrying"
	else -- "abort"
		self._isExecuting = false
		if self._onSequenceComplete then
			self._onSequenceComplete(false, self._completedSteps)
		end
		return false, "aborted"
	end
end

-- ============================================================================
-- COMPLETE EXECUTION
-- ============================================================================

--[=[
	Executes the entire sequence synchronously.

	Runs all actions in order until completion, failure, or interruption.

	@param agent any? -- The agent performing the actions
	@param context any? -- Additional context
	@return boolean -- True if sequence completed successfully
	@return number -- Number of completed steps

	@example
	```lua
	local success, completedSteps = sequence:executeAll(agent)
	if success then
		print("All", completedSteps, "steps completed!")
	else
		print("Failed after", completedSteps, "steps")
	end
	```
]=]
function ActionSequence:executeAll(agent: any?, context: any?): (boolean, number)
	self:reset()

	if #self._actions == 0 then
		return true, 0
	end

	while self._currentStep < #self._actions do
		local _, status = self:executeStep(agent, context)

		if status == "complete" then
			return true, #self._actions
		elseif status == "aborted" or status == "max_retries_exceeded" or status == "interrupted" then
			return false, self._completedSteps
		end
		-- "continue", "skipped", "retrying" all continue the loop
	end

	return true, self._completedSteps
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	String representation for debugging.

	@return string -- Formatted string describing the sequence

	@example
	```lua
	print(sequence)
	-- "ActionSequence{name=AttackCombo, steps=3}"
	```
]=]
function ActionSequence:__tostring(): string
	return `ActionSequence\{name={self.name}, steps={#self._actions}}`
end

-- ============================================================================
-- MEMORY MANAGEMENT
-- ============================================================================

--[=[
	Clears all callback references.

	Use this when you want to stop receiving callbacks but keep the sequence.
	Useful when reusing sequences or when the callback targets are being destroyed.
]=]
function ActionSequence:clearCallbacks()
	self._onStepComplete = nil
	self._onSequenceComplete = nil
	self._onInterrupt = nil
end

--[=[
	Destroys the sequence and releases all resources.

	IMPORTANT: Call this when the sequence is no longer needed to prevent memory leaks.
	This clears all callbacks and action references. After calling destroy(),
	the sequence should not be used.

	@example
	```lua
	-- When NPC is despawned
	sequence:destroy()
	```
]=]
function ActionSequence:destroy()
	-- Stop any ongoing execution
	self._isExecuting = false
	self._wasInterrupted = true

	-- Clear all callbacks (prevents closures from holding references)
	self._onStepComplete = nil
	self._onSequenceComplete = nil
	self._onInterrupt = nil

	-- Clear action references
	table.clear(self._actions)

	-- Reset state
	self._currentStep = 0
	self._retryCount = 0
	self._completedSteps = 0
end

--[=[
	Checks if the sequence has been destroyed.

	@return boolean -- True if destroy() has been called
]=]
function ActionSequence:isDestroyed(): boolean
	return self._wasInterrupted and #self._actions == 0 and self._onStepComplete == nil
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	Creates a debug summary of this sequence.

	Provides detailed information useful for debugging.

	@param worldState State? -- Optional world state for validation
	@param agent any? -- Optional agent for resource checking
	@return string -- Multi-line debug summary

	@example
	```lua
	print(sequence:debugSummary(worldState, agent))
	-- ActionSequence: AttackCombo
	--   Steps: 3
	--   Progress: 1/3 (33%)
	--   Status: executing
	--   Actions:
	--     1. LightAttack [current]
	--     2. HeavyAttack
	--     3. Finisher
	```
]=]
function ActionSequence:debugSummary(worldState: State.State?, agent: any?): string
	local lines = {
		`ActionSequence: {self.name}`,
		`  Steps: {#self._actions}`,
	}

	-- Progress info
	if self._isExecuting then
		local progressPercent = math.floor(self:getProgress() * 100)
		table.insert(lines, `  Progress: {self._currentStep}/{#self._actions} ({progressPercent}%)`)
	end

	-- Status
	local status = "idle"
	if self._isExecuting then
		status = "executing"
	elseif self._wasInterrupted then
		status = "interrupted"
	elseif self:isComplete() then
		status = "complete"
	end
	table.insert(lines, `  Status: {status}`)

	-- Failure strategy
	table.insert(lines, `  Failure Strategy: {self.failureStrategy}`)
	if self.failureStrategy == "retry" then
		table.insert(lines, `  Max Retries: {self.maxRetries}`)
	end

	-- Validation
	if worldState then
		local canExec, failStep, reason = self:canExecute(worldState, agent)
		if canExec then
			table.insert(lines, "  Can Execute: true")
		else
			table.insert(lines, `  Can Execute: false (step {failStep}: {reason})`)
		end
	end

	-- Action list
	if #self._actions > 0 then
		table.insert(lines, "  Actions:")
		for i, action in ipairs(self._actions) do
			local marker = ""
			if i == self._currentStep then
				marker = " [current]"
			elseif i < self._currentStep then
				marker = " [done]"
			end
			table.insert(lines, `    {i}. {action:getName()}{marker}`)
		end
	else
		table.insert(lines, "  Actions: (none)")
	end

	return table.concat(lines, "\n")
end

-- ============================================================================
-- TYPE EXPORT
-- ============================================================================

--- Export type for external use.
export type ActionSequence = typeof(ActionSequence.new({
	name = "",
	actions = {},
}))

return ActionSequence
