--!strict
--[[
	Logger.lua
	Debug logging system for the GOAP package.

	Provides configurable logging with multiple severity levels.
	All logging is opt-in - by default, nothing is logged.

	┌─────────────────────────────────────────────────────────────────────┐
	│                        LOGGING ARCHITECTURE                          │
	├─────────────────────────────────────────────────────────────────────┤
	│                                                                      │
	│   Log Levels (ascending verbosity):                                  │
	│                                                                      │
	│      NONE (0) ──► No output                                          │
	│         │                                                            │
	│      ERROR (1) ──► Critical failures                                 │
	│         │                                                            │
	│      WARN (2) ──► Potential issues                                   │
	│         │                                                            │
	│      INFO (3) ──► General information                                │
	│         │                                                            │
	│      DEBUG (4) ──► Detailed debugging                                │
	│         │                                                            │
	│      TRACE (5) ──► Verbose tracing (performance-intensive)           │
	│                                                                      │
	├─────────────────────────────────────────────────────────────────────┤
	│                                                                      │
	│   Category-Based Filtering:                                          │
	│                                                                      │
	│   ┌──────────────┐     ┌──────────────┐     ┌──────────────┐        │
	│   │   Planner    │     │    Action    │     │     Goal     │        │
	│   │  Level: DEBUG│     │  Level: WARN │     │  Level: INFO │        │
	│   └──────────────┘     └──────────────┘     └──────────────┘        │
	│         │                    │                    │                  │
	│         ▼                    ▼                    ▼                  │
	│   ┌─────────────────────────────────────────────────────────────┐   │
	│   │                    Output Handler                           │   │
	│   │   (Default: print/warn   OR   Custom: customOutputFn)       │   │
	│   └─────────────────────────────────────────────────────────────┘   │
	│                                                                      │
	└─────────────────────────────────────────────────────────────────────┘

	@class Logger
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	@example Basic Usage
	```lua
	local Logger = require(path.to.Logger)

	Logger.setLevel(Logger.Level.DEBUG)
	Logger.info("Planning", "Starting plan for goal: %s", goalName)
	Logger.debug("Planning", "Found %d valid actions", #actions)
	```

	@example With Planner Integration
	```lua
	local Goal = require(path.to.goal)

	-- Enable debug logging
	Goal.Planner.setLogLevel(Goal.Logger.Level.DEBUG)

	-- Now planning will output debug information
	local plan = planner:plan(state, goal)
	```

	@example Category-Specific Logging
	```lua
	-- Only debug the planner, keep everything else quiet
	Logger.setLevel(Logger.Level.WARN)
	Logger.setCategoryLevel("Planner", Logger.Level.DEBUG)
	```

	@example Custom Output Handler
	```lua
	Logger.setOutputFunction(function(level, category, message)
		-- Send to remote logging service
		RemoteLogging:Log(level, category, message)
	end)
	```
]]

local Logger = {}

--------------------------------------------------------------------------------
-- Type Definitions
--------------------------------------------------------------------------------

--[=[
	@type LogLevel number
	@within Logger
	Numeric log level value (0-5).
]=]
export type LogLevel = number

--[=[
	@type OutputFunction (level: number, category: string, message: string) -> ()
	@within Logger
	Custom output function signature for redirecting log output.
]=]
export type OutputFunction = (level: number, category: string, message: string) -> ()

--[=[
	@type ScopedLogger { error: (string, ...any) -> (), warn: (string, ...any) -> (), ... }
	@within Logger
	A logger instance bound to a specific category.
]=]
export type ScopedLogger = {
	error: (message: string, ...any) -> (),
	warn: (message: string, ...any) -> (),
	info: (message: string, ...any) -> (),
	debug: (message: string, ...any) -> (),
	trace: (message: string, ...any) -> (),
	isEnabled: (level: number) -> boolean,
}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

--[=[
	@interface LogLevel
	@within Logger
	.NONE number -- No logging (default)
	.ERROR number -- Only errors
	.WARN number -- Errors and warnings
	.INFO number -- General information
	.DEBUG number -- Detailed debugging
	.TRACE number -- Very detailed tracing
]=]
Logger.Level = table.freeze({
	NONE = 0,
	ERROR = 1,
	WARN = 2,
	INFO = 3,
	DEBUG = 4,
	TRACE = 5,
})

--- Prefix for all log messages
local LOG_PREFIX = "[Goal]"

--- Level names for output (frozen for safety)
local LEVEL_NAMES: { [number]: string } = table.freeze({
	[Logger.Level.ERROR] = "ERROR",
	[Logger.Level.WARN] = "WARN",
	[Logger.Level.INFO] = "INFO",
	[Logger.Level.DEBUG] = "DEBUG",
	[Logger.Level.TRACE] = "TRACE",
})

--- Minimum valid log level
local MIN_LEVEL = Logger.Level.NONE

--- Maximum valid log level
local MAX_LEVEL = Logger.Level.TRACE

--------------------------------------------------------------------------------
-- Private State
--------------------------------------------------------------------------------

--- Current global log level (default: no logging)
local currentLevel: number = Logger.Level.NONE

--- Optional custom output function
local customOutputFn: OutputFunction? = nil

--- Category-specific log levels (allows enabling debug for specific systems)
local categoryLevels: { [string]: number } = {}

--------------------------------------------------------------------------------
-- Private Helper Functions
--------------------------------------------------------------------------------

--[=[
	Validates that a log level is within the valid range.

	@param level number -- Level to validate
	@param context string -- Context for error message
	@private
]=]
local function validateLevel(level: number, context: string): ()
	assert(
		type(level) == "number" and level >= MIN_LEVEL and level <= MAX_LEVEL,
		`{LOG_PREFIX} {context}: level must be a number between {MIN_LEVEL} and {MAX_LEVEL}, got {level}`
	)
end

--[=[
	Internal function to check if a message should be logged.

	@param level number -- Message level
	@param category string -- Message category
	@return boolean -- True if the message should be logged
	@private
]=]
local function shouldLog(level: number, category: string): boolean
	local effectiveLevel = categoryLevels[category] or currentLevel
	return level <= effectiveLevel
end

--[=[
	Internal function to format and output a log message.

	@param level number -- Message level
	@param category string -- Message category
	@param message string -- Message to log
	@private
]=]
local function output(level: number, category: string, message: string): ()
	if customOutputFn then
		customOutputFn(level, category, message)
		return
	end

	local levelName = LEVEL_NAMES[level] or "UNKNOWN"
	local formattedMessage = `{LOG_PREFIX} [{levelName}] [{category}] {message}`

	if level == Logger.Level.ERROR or level == Logger.Level.WARN then
		warn(formattedMessage)
	else
		print(formattedMessage)
	end
end

--------------------------------------------------------------------------------
-- Level Configuration
--------------------------------------------------------------------------------

--[=[
	Sets the global log level.
	Only messages at or below this level will be output.

	@param level number -- One of Logger.Level values (0-5)
	@return Logger -- Returns Logger for chaining
	@error "level must be a number between 0 and 5" -- If level is invalid

	@example
	```lua
	Logger.setLevel(Logger.Level.DEBUG)
	```
]=]
function Logger.setLevel(level: number): typeof(Logger)
	validateLevel(level, "setLevel")
	currentLevel = level
	return Logger
end

--[=[
	Gets the current global log level.

	@return number -- Current log level
]=]
function Logger.getLevel(): number
	return currentLevel
end

--[=[
	Sets the log level for a specific category.
	Allows fine-grained control over logging.

	@param category string -- Category name (e.g., "Planner", "Action")
	@param level number -- One of Logger.Level values (0-5)
	@return Logger -- Returns Logger for chaining
	@error "category must be a non-empty string" -- If category is invalid
	@error "level must be a number between 0 and 5" -- If level is invalid

	@example
	```lua
	-- Only debug the planner, keep everything else quiet
	Logger.setLevel(Logger.Level.WARN)
	Logger.setCategoryLevel("Planner", Logger.Level.DEBUG)
	```
]=]
function Logger.setCategoryLevel(category: string, level: number): typeof(Logger)
	assert(
		type(category) == "string" and #category > 0,
		`{LOG_PREFIX} setCategoryLevel: category must be a non-empty string`
	)
	validateLevel(level, "setCategoryLevel")
	categoryLevels[category] = level
	return Logger
end

--[=[
	Removes the log level for a specific category.
	The category will fall back to the global log level.

	@param category string -- Category name to remove
	@return Logger -- Returns Logger for chaining

	@example
	```lua
	Logger.removeCategoryLevel("Planner")
	```
]=]
function Logger.removeCategoryLevel(category: string): typeof(Logger)
	categoryLevels[category] = nil
	return Logger
end

--[=[
	Gets the effective log level for a category.
	Returns the category-specific level if set, otherwise the global level.

	@param category string -- Category name
	@return number -- Effective log level for the category
]=]
function Logger.getCategoryLevel(category: string): number
	return categoryLevels[category] or currentLevel
end

--[=[
	Gets all configured category names.

	@return {string} -- Array of category names with custom levels
]=]
function Logger.getCategories(): { string }
	local categories: { string } = {}
	for category in categoryLevels do
		table.insert(categories, category)
	end
	table.sort(categories)
	return categories
end

--[=[
	Clears all category-specific log levels.

	@return Logger -- Returns Logger for chaining
]=]
function Logger.clearCategoryLevels(): typeof(Logger)
	table.clear(categoryLevels)
	return Logger
end

--[=[
	Gets the human-readable name for a log level.

	@param level number -- Log level value
	@return string -- Level name (e.g., "DEBUG", "INFO") or "UNKNOWN"

	@example
	```lua
	print(Logger.getLevelName(Logger.Level.DEBUG)) -- "DEBUG"
	```
]=]
function Logger.getLevelName(level: number): string
	return LEVEL_NAMES[level] or "UNKNOWN"
end

--[=[
	Sets a custom output function for log messages.
	Use this to redirect logs to a custom system (e.g., remote logging).

	@param fn OutputFunction? -- Custom output function, or nil to use default
	@return Logger -- Returns Logger for chaining

	@example
	```lua
	Logger.setOutputFunction(function(level, category, message)
		-- Send to remote logging service
		RemoteLogging:Log(level, category, message)
	end)
	```
]=]
function Logger.setOutputFunction(fn: OutputFunction?): typeof(Logger)
	customOutputFn = fn
	return Logger
end

--------------------------------------------------------------------------------
-- Logging Methods
--------------------------------------------------------------------------------

--[=[
	Logs an error message.
	Errors indicate serious problems that may prevent correct operation.

	@param category string -- Category for the message (e.g., "Planner")
	@param message string -- Message format string
	@param ... any -- Format arguments
	@return Logger -- Returns Logger for chaining

	@example
	```lua
	Logger.error("Planner", "Failed to find plan for goal: %s", goal:getName())
	```
]=]
function Logger.error(category: string, message: string, ...: any): typeof(Logger)
	if shouldLog(Logger.Level.ERROR, category) then
		output(Logger.Level.ERROR, category, string.format(message, ...))
	end
	return Logger
end

--[=[
	Logs a warning message.
	Warnings indicate potential issues that don't prevent operation.

	@param category string -- Category for the message
	@param message string -- Message format string
	@param ... any -- Format arguments
	@return Logger -- Returns Logger for chaining

	@example
	```lua
	Logger.warn("Action", "Action '%s' has no executeFn defined", action:getName())
	```
]=]
function Logger.warn(category: string, message: string, ...: any): typeof(Logger)
	if shouldLog(Logger.Level.WARN, category) then
		output(Logger.Level.WARN, category, string.format(message, ...))
	end
	return Logger
end

--[=[
	Logs an informational message.
	Info messages provide general operational information.

	@param category string -- Category for the message
	@param message string -- Message format string
	@param ... any -- Format arguments
	@return Logger -- Returns Logger for chaining

	@example
	```lua
	Logger.info("Planner", "Plan found with %d actions, cost: %.2f", #plan.actions, plan.totalCost)
	```
]=]
function Logger.info(category: string, message: string, ...: any): typeof(Logger)
	if shouldLog(Logger.Level.INFO, category) then
		output(Logger.Level.INFO, category, string.format(message, ...))
	end
	return Logger
end

--[=[
	Logs a debug message.
	Debug messages provide detailed information useful for debugging.

	@param category string -- Category for the message
	@param message string -- Message format string
	@param ... any -- Format arguments
	@return Logger -- Returns Logger for chaining

	@example
	```lua
	Logger.debug("Planner", "Evaluating goal '%s' with priority %d", goal:getName(), priority)
	```
]=]
function Logger.debug(category: string, message: string, ...: any): typeof(Logger)
	if shouldLog(Logger.Level.DEBUG, category) then
		output(Logger.Level.DEBUG, category, string.format(message, ...))
	end
	return Logger
end

--[=[
	Logs a trace message.
	Trace messages provide very detailed information, including performance-intensive data.

	@param category string -- Category for the message
	@param message string -- Message format string
	@param ... any -- Format arguments
	@return Logger -- Returns Logger for chaining

	@warning Trace logging can significantly impact performance.
	Only enable for specific debugging sessions.

	@example
	```lua
	Logger.trace("Planner", "A* iteration %d: visiting state %s", iteration, stateHash)
	```
]=]
function Logger.trace(category: string, message: string, ...: any): typeof(Logger)
	if shouldLog(Logger.Level.TRACE, category) then
		output(Logger.Level.TRACE, category, string.format(message, ...))
	end
	return Logger
end

--[=[
	Checks if a specific log level is enabled for a category.
	Useful to avoid expensive operations when logging is disabled.

	@param level number -- Log level to check
	@param category string? -- Category to check (optional, uses global if not specified)
	@return boolean -- True if the level is enabled

	@example
	```lua
	-- Avoid expensive table formatting if debug is disabled
	if Logger.isEnabled(Logger.Level.DEBUG, "Planner") then
		Logger.debug("Planner", "State: %s", formatState(state))
	end
	```
]=]
function Logger.isEnabled(level: number, category: string?): boolean
	return shouldLog(level, category or "")
end

--------------------------------------------------------------------------------
-- Utility Methods
--------------------------------------------------------------------------------

--[=[
	Resets the logger to default state.
	Clears all category levels, custom output function, and sets global level to NONE.

	@return Logger -- Returns Logger for chaining
]=]
function Logger.reset(): typeof(Logger)
	currentLevel = Logger.Level.NONE
	table.clear(categoryLevels)
	customOutputFn = nil
	return Logger
end

--[=[
	Creates a scoped logger for a specific category.
	Useful for modules that want to log without specifying category each time.

	@param category string -- Category for all messages
	@return ScopedLogger -- Scoped logger with error, warn, info, debug, trace methods

	@example
	```lua
	local log = Logger.scoped("Planner")
	log.debug("Found %d valid actions", #actions)
	log.info("Plan complete")
	```
]=]
function Logger.scoped(category: string): ScopedLogger
	assert(type(category) == "string" and #category > 0, `{LOG_PREFIX} scoped: category must be a non-empty string`)

	return {
		error = function(message: string, ...: any)
			Logger.error(category, message, ...)
		end,
		warn = function(message: string, ...: any)
			Logger.warn(category, message, ...)
		end,
		info = function(message: string, ...: any)
			Logger.info(category, message, ...)
		end,
		debug = function(message: string, ...: any)
			Logger.debug(category, message, ...)
		end,
		trace = function(message: string, ...: any)
			Logger.trace(category, message, ...)
		end,
		isEnabled = function(level: number): boolean
			return Logger.isEnabled(level, category)
		end,
	}
end

--[=[
	Returns a debug summary of the logger configuration.
	Useful for debugging and diagnostics.

	@return string -- Multi-line debug summary

	@example
	```lua
	print(Logger.debugSummary())
	-- Output:
	-- Logger Configuration:
	--   Global Level: DEBUG (4)
	--   Custom Output: No
	--   Category Levels:
	--     Planner: TRACE (5)
	--     Action: WARN (2)
	```
]=]
function Logger.debugSummary(): string
	local lines: { string } = {
		"Logger Configuration:",
		`  Global Level: {Logger.getLevelName(currentLevel)} ({currentLevel})`,
		`  Custom Output: {customOutputFn and "Yes" or "No"}`,
	}

	local categories = Logger.getCategories()
	if #categories > 0 then
		table.insert(lines, "  Category Levels:")
		for _, category in categories do
			local level = categoryLevels[category]
			table.insert(lines, `    {category}: {Logger.getLevelName(level)} ({level})`)
		end
	else
		table.insert(lines, "  Category Levels: (none)")
	end

	return table.concat(lines, "\n")
end

return Logger
