--!strict
--[[
	Utilities.lua
	Helper functions and data structures for the GOAP system.

	This module provides essential utilities used throughout the GOAP package:
	- PriorityQueue: Min-heap implementation for A* search
	- Table utilities: Deep clone, shallow clone, merge, equality
	- Math utilities: Clamp, lerp
	- Debug utilities: Table formatting, timing measurement

	@class Utilities
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	@example PriorityQueue Usage
	```lua
	local Utilities = require(path.to.Utilities)
	local pq = Utilities.PriorityQueue.new()

	pq:push("high priority", 1)
	pq:push("low priority", 10)
	pq:push("medium priority", 5)

	print(pq:pop()) -- "high priority"
	print(pq:pop()) -- "medium priority"
	print(pq:pop()) -- "low priority"
	```

	@example Table Utilities
	```lua
	local original = { nested = { value = 42 } }
	local cloned = Utilities.deepClone(original)
	cloned.nested.value = 100
	print(original.nested.value) -- 42 (unchanged)
	```
]]

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

--[=[
	@type HeapEntry { item: any, priority: number }
	@within Utilities
	Entry stored in the priority queue heap.
]=]
type HeapEntry = {
	item: any,
	priority: number,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

--- Default indentation string for formatted output.
local DEFAULT_INDENT_STRING = "  "

--- Maximum recursion depth for deep operations to prevent stack overflow.
local MAX_RECURSION_DEPTH = 100

-- ============================================================================
-- MODULE
-- ============================================================================

local Utilities = {}

-- ============================================================================
-- PRIORITY QUEUE (MIN-HEAP) - OPTIMIZED
-- ============================================================================

--[[
	Priority Queue Implementation (Optimized)

	A min-heap based priority queue optimized for A* search.
	Lower priority values are dequeued first (min-heap behavior).

	OPTIMIZATIONS:
	- Separate arrays for items and priorities (better cache locality)
	- Bit shift for parent/child calculations (faster than math.floor)
	- Local variable caching to reduce table lookups
	- Pre-allocated capacity option to reduce reallocations

	Time Complexity:
	- push: O(log n)
	- pop: O(log n)
	- peek: O(1)
	- isEmpty: O(1)
	- size: O(1)

	Space Complexity: O(n)

	                    Heap Structure (Min-Heap)
	                    ========================

	                           [1] (root)
	                          /         \
	                       [2]           [3]
	                      /   \         /   \
	                    [4]   [5]     [6]   [7]

	Parent of node i: bit32.rshift(i, 1) or floor(i / 2)
	Left child of i:  bit32.lshift(i, 1) or i * 2
	Right child of i: bit32.lshift(i, 1) + 1 or i * 2 + 1

	INVARIANT: parent.priority <= child.priority for all nodes
]]

--[=[
	@class PriorityQueue
	@within Utilities

	A min-heap priority queue where lower priority values are dequeued first.
	Used by the Planner for A* search to always expand the lowest-cost node.
]=]
local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

--// Local references for performance
local bit32_rshift = bit32.rshift
local bit32_lshift = bit32.lshift

--[=[
	Creates a new empty PriorityQueue.

	@param initialCapacity number? -- Optional initial capacity for pre-allocation
	@return PriorityQueue -- A new empty priority queue

	@example
	```lua
	local pq = Utilities.PriorityQueue.new()
	assert(pq:isEmpty())

	-- Pre-allocate for better performance with known size
	local pq2 = Utilities.PriorityQueue.new(100)
	```
]=]
function PriorityQueue.new(initialCapacity: number?): PriorityQueue
	local self = setmetatable({}, PriorityQueue)
	local capacity = initialCapacity or 16
	--// Separate arrays for better cache locality
	self._items = table.create(capacity) :: { any }
	self._priorities = table.create(capacity) :: { number }
	self._size = 0
	return self
end

--[=[
	Pushes an item onto the queue with the given priority.
	Lower priority values will be dequeued first.

	@param item any -- The item to enqueue
	@param priority number -- Priority value (lower = higher priority)

	@example
	```lua
	local pq = Utilities.PriorityQueue.new()
	pq:push("urgent", 1)
	pq:push("normal", 5)
	pq:push("low", 10)
	```

	Time Complexity: O(log n)
]=]
function PriorityQueue:push(item: any, priority: number)
	local size = self._size + 1
	self._size = size
	self._items[size] = item
	self._priorities[size] = priority

	--// Inline bubble up for performance
	local items = self._items
	local priorities = self._priorities
	local index = size

	while index > 1 do
		local parentIndex = bit32_rshift(index, 1)
		local parentPriority = priorities[parentIndex]

		if priority >= parentPriority then
			break
		end

		--// Swap with parent (separate arrays)
		items[index] = items[parentIndex]
		priorities[index] = parentPriority
		items[parentIndex] = item
		priorities[parentIndex] = priority

		index = parentIndex
	end
end

--[=[
	Removes and returns the item with the lowest priority value.

	@return any? -- The highest-priority item, or nil if queue is empty

	@example
	```lua
	local pq = Utilities.PriorityQueue.new()
	pq:push("a", 5)
	pq:push("b", 1)
	print(pq:pop()) -- "b" (lower priority value)
	print(pq:pop()) -- "a"
	print(pq:pop()) -- nil
	```

	Time Complexity: O(log n)
]=]
function PriorityQueue:pop(): any?
	local size = self._size
	if size == 0 then
		return nil
	end

	local items = self._items
	local priorities = self._priorities
	local topItem = items[1]

	--// Move last element to root
	local lastItem = items[size]
	local lastPriority = priorities[size]
	items[size] = nil
	priorities[size] = nil
	size -= 1
	self._size = size

	if size == 0 then
		return topItem
	end

	--// Place at root and bubble down (inline for performance)
	items[1] = lastItem
	priorities[1] = lastPriority

	local index = 1
	while true do
		local leftChild = bit32_lshift(index, 1)
		local rightChild = leftChild + 1
		local smallest = index
		local smallestPriority = lastPriority

		--// Check left child
		if leftChild <= size then
			local leftPriority = priorities[leftChild]
			if leftPriority < smallestPriority then
				smallest = leftChild
				smallestPriority = leftPriority
			end
		end

		--// Check right child
		if rightChild <= size then
			local rightPriority = priorities[rightChild]
			if rightPriority < smallestPriority then
				smallest = rightChild
			end
		end

		if smallest == index then
			break
		end

		--// Swap with smaller child
		items[index] = items[smallest]
		priorities[index] = priorities[smallest]
		items[smallest] = lastItem
		priorities[smallest] = lastPriority

		index = smallest
	end

	return topItem
end

--[=[
	Returns the item with the lowest priority without removing it.

	@return any? -- The highest-priority item, or nil if queue is empty

	@example
	```lua
	local pq = Utilities.PriorityQueue.new()
	pq:push("item", 5)
	print(pq:peek()) -- "item"
	print(pq:size()) -- 1 (still in queue)
	```

	Time Complexity: O(1)
]=]
function PriorityQueue:peek(): any?
	return self._items[1]
end

--[=[
	Returns the priority of the top item without removing it.

	@return number? -- Priority of the top item, or nil if queue is empty

	@example
	```lua
	local pq = Utilities.PriorityQueue.new()
	pq:push("item", 5)
	print(pq:peekPriority()) -- 5
	```

	Time Complexity: O(1)
]=]
function PriorityQueue:peekPriority(): number?
	return self._priorities[1]
end

--[=[
	Checks if the queue is empty.

	@return boolean -- True if the queue has no items

	@example
	```lua
	local pq = Utilities.PriorityQueue.new()
	print(pq:isEmpty()) -- true
	pq:push("item", 1)
	print(pq:isEmpty()) -- false
	```

	Time Complexity: O(1)
]=]
function PriorityQueue:isEmpty(): boolean
	return self._size == 0
end

--[=[
	Returns the number of items in the queue.

	@return number -- Number of items currently in the queue

	@example
	```lua
	local pq = Utilities.PriorityQueue.new()
	print(pq:size()) -- 0
	pq:push("a", 1)
	pq:push("b", 2)
	print(pq:size()) -- 2
	```

	Time Complexity: O(1)
]=]
function PriorityQueue:size(): number
	return self._size
end

--[=[
	Removes all items from the queue.

	@example
	```lua
	pq:push("a", 1)
	pq:push("b", 2)
	pq:clear()
	print(pq:isEmpty()) -- true
	```

	Time Complexity: O(1)
]=]
function PriorityQueue:clear()
	table.clear(self._items)
	table.clear(self._priorities)
	self._size = 0
end

--[=[
	Reserves capacity for the queue to reduce reallocations.

	@param capacity number -- Number of items to reserve space for
]=]
function PriorityQueue:reserve(capacity: number)
	--// Pre-extend arrays if needed (Luau handles this efficiently)
	local currentSize = self._size
	if capacity > currentSize then
		for i = currentSize + 1, capacity do
			self._items[i] = false
			self._priorities[i] = 0
		end
		for i = currentSize + 1, capacity do
			self._items[i] = nil
			self._priorities[i] = nil
		end
	end
end

--[=[
	String representation for debugging.

	@return string -- Description of the queue
]=]
function PriorityQueue:__tostring(): string
	return `PriorityQueue(size={self._size})`
end

-- Export PriorityQueue type
export type PriorityQueue = typeof(PriorityQueue.new())

Utilities.PriorityQueue = PriorityQueue

-- ============================================================================
-- TABLE UTILITIES
-- ============================================================================

--[=[
	Deep clones a table, recursively copying all nested tables.

	@param source any -- The value to clone (returns non-tables unchanged)
	@param _depth number? -- Internal recursion depth tracker
	@return any -- The cloned value

	@example
	```lua
	local original = {
		name = "test",
		nested = { value = 42 },
		array = { 1, 2, 3 },
	}
	local cloned = Utilities.deepClone(original)

	cloned.nested.value = 100
	print(original.nested.value) -- 42 (unchanged)
	```

	@warning Does not handle circular references. Will overflow stack on circular tables.
	@warning Does not clone metatables. Use for data tables only.
]=]
function Utilities.deepClone(source: any, _depth: number?): any
	if type(source) ~= "table" then
		return source
	end

	local depth = (_depth or 0) + 1
	if depth > MAX_RECURSION_DEPTH then
		warn("[Goal] Utilities.deepClone: Maximum recursion depth exceeded, possible circular reference")
		return source
	end

	local clone = {}
	for key, value in pairs(source) do
		if type(value) == "table" then
			clone[key] = Utilities.deepClone(value, depth)
		else
			clone[key] = value
		end
	end

	return clone
end

--[=[
	Shallow clones a table (one level deep).
	Nested tables are referenced, not copied.

	@param source { [any]: any } -- The table to clone
	@return { [any]: any } -- The cloned table

	@example
	```lua
	local original = { a = 1, nested = { b = 2 } }
	local cloned = Utilities.shallowClone(original)

	cloned.a = 100
	print(original.a) -- 1 (unchanged)

	cloned.nested.b = 200
	print(original.nested.b) -- 200 (shared reference!)
	```
]=]
function Utilities.shallowClone(source: { [any]: any }): { [any]: any }
	assert(type(source) == "table", "shallowClone requires a table")
	return table.clone(source)
end

--[=[
	Merges multiple tables into a new table.
	Later tables override keys from earlier tables.

	@param ... { [any]: any } -- Tables to merge (variadic)
	@return { [any]: any } -- New merged table

	@example
	```lua
	local defaults = { timeout = 30, retries = 3 }
	local userConfig = { timeout = 60 }
	local config = Utilities.merge(defaults, userConfig)

	print(config.timeout) -- 60 (overridden)
	print(config.retries) -- 3 (from defaults)
	```
]=]
function Utilities.merge(...: { [any]: any }): { [any]: any }
	local result = {}
	local sources = { ... }

	for _, source in ipairs(sources) do
		if type(source) == "table" then
			for key, value in pairs(source) do
				result[key] = value
			end
		end
	end

	return result
end

--[=[
	Checks if two values are deeply equal.
	Recursively compares nested tables.

	@param valueA any -- First value to compare
	@param valueB any -- Second value to compare
	@param _depth number? -- Internal recursion depth tracker
	@return boolean -- True if values are deeply equal

	@example
	```lua
	local a = { nested = { value = 42 } }
	local b = { nested = { value = 42 } }
	local c = { nested = { value = 99 } }

	print(Utilities.deepEqual(a, b)) -- true
	print(Utilities.deepEqual(a, c)) -- false
	```

	@warning Does not handle circular references.
]=]
function Utilities.deepEqual(valueA: any, valueB: any, _depth: number?): boolean
	-- Type mismatch = not equal
	if type(valueA) ~= type(valueB) then
		return false
	end

	-- Non-tables: direct comparison
	if type(valueA) ~= "table" then
		return valueA == valueB
	end

	-- Check recursion depth
	local depth = (_depth or 0) + 1
	if depth > MAX_RECURSION_DEPTH then
		warn("[Goal] Utilities.deepEqual: Maximum recursion depth exceeded")
		return false
	end

	-- Check all keys in A exist in B with equal values
	for key, value in pairs(valueA) do
		if not Utilities.deepEqual(value, valueB[key], depth) then
			return false
		end
	end

	-- Check all keys in B exist in A
	for key in pairs(valueB) do
		if valueA[key] == nil then
			return false
		end
	end

	return true
end

--[=[
	Checks if a table is empty (has no entries).

	@param tbl { [any]: any } -- Table to check
	@return boolean -- True if table has no entries

	@example
	```lua
	print(Utilities.isEmpty({})) -- true
	print(Utilities.isEmpty({ a = 1 })) -- false
	```
]=]
function Utilities.isEmpty(tbl: { [any]: any }): boolean
	return next(tbl) == nil
end

--[=[
	Returns the number of entries in a dictionary-style table.
	Unlike #, this works for tables with non-integer keys.

	@param tbl { [any]: any } -- Table to count
	@return number -- Number of key-value pairs

	@example
	```lua
	local dict = { a = 1, b = 2, c = 3 }
	print(#dict) -- 0 (Lua's # doesn't work on dictionaries)
	print(Utilities.tableSize(dict)) -- 3
	```
]=]
function Utilities.tableSize(tbl: { [any]: any }): number
	local count = 0
	for _ in pairs(tbl) do
		count += 1
	end
	return count
end

-- ============================================================================
-- STRING UTILITIES
-- ============================================================================

--[=[
	Creates a unique identifier string.
	Uses random numbers to generate a 16-character hex ID.

	@return string -- A 16-character hexadecimal identifier

	@example
	```lua
	local id1 = Utilities.generateId() -- e.g., "a1b2c3d4e5f6g7h8"
	local id2 = Utilities.generateId() -- Different ID each call
	```

	@warning Not cryptographically secure. Use only for debugging/tracking.
]=]
function Utilities.generateId(): string
	return string.format("%08x%08x", math.random(0, 0xFFFFFFFF), math.random(0, 0xFFFFFFFF))
end

--[=[
	Formats a table as a human-readable string for debugging.
	Handles nested tables with proper indentation.

	@param tbl any -- Value to format (non-tables return tostring)
	@param indent number? -- Current indentation level (default: 0)
	@return string -- Formatted string representation

	@example
	```lua
	local state = { health = 100, inventory = { sword = true, shield = false } }
	print(Utilities.formatTable(state))
	-- {
	--   health = 100,
	--   inventory = {
	--     shield = false,
	--     sword = true,
	--   },
	-- }
	```
]=]
function Utilities.formatTable(tbl: any, indent: number?): string
	if type(tbl) ~= "table" then
		return tostring(tbl)
	end

	local currentIndent = indent or 0
	local indentString = string.rep(DEFAULT_INDENT_STRING, currentIndent)
	local nextIndentString = string.rep(DEFAULT_INDENT_STRING, currentIndent + 1)

	-- Check for empty table
	if next(tbl) == nil then
		return "{}"
	end

	local lines = { "{" }

	-- Sort keys for consistent output
	local keys = {}
	for key in pairs(tbl) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		-- Sort by type first, then by value
		local typeA, typeB = type(a), type(b)
		if typeA ~= typeB then
			return typeA < typeB
		end
		if typeA == "number" or typeA == "string" then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)

	for _, key in ipairs(keys) do
		local value = tbl[key]
		local keyString = type(key) == "string" and key or `[{tostring(key)}]`
		local valueString = type(value) == "table" and Utilities.formatTable(value, currentIndent + 1)
			or tostring(value)
		table.insert(lines, `{nextIndentString}{keyString} = {valueString},`)
	end

	table.insert(lines, `{indentString}}`)

	return table.concat(lines, "\n")
end

-- ============================================================================
-- MATH UTILITIES
-- ============================================================================

--[=[
	Clamps a number between minimum and maximum bounds.

	@param value number -- Value to clamp
	@param minValue number -- Minimum bound (inclusive)
	@param maxValue number -- Maximum bound (inclusive)
	@return number -- Clamped value

	@example
	```lua
	print(Utilities.clamp(5, 0, 10))   -- 5
	print(Utilities.clamp(-5, 0, 10))  -- 0
	print(Utilities.clamp(15, 0, 10))  -- 10
	```
]=]
function Utilities.clamp(value: number, minValue: number, maxValue: number): number
	assert(type(value) == "number", "value must be a number")
	assert(type(minValue) == "number", "minValue must be a number")
	assert(type(maxValue) == "number", "maxValue must be a number")
	assert(minValue <= maxValue, "minValue must be <= maxValue")

	return math.max(minValue, math.min(maxValue, value))
end

--[=[
	Linearly interpolates between two values.

	@param startValue number -- Start value (returned when t = 0)
	@param endValue number -- End value (returned when t = 1)
	@param alpha number -- Interpolation factor (typically 0-1)
	@return number -- Interpolated value

	@example
	```lua
	print(Utilities.lerp(0, 100, 0.0))  -- 0
	print(Utilities.lerp(0, 100, 0.5))  -- 50
	print(Utilities.lerp(0, 100, 1.0))  -- 100
	print(Utilities.lerp(0, 100, 1.5))  -- 150 (extrapolation)
	```

	@note Does not clamp alpha. Values outside 0-1 will extrapolate.
]=]
function Utilities.lerp(startValue: number, endValue: number, alpha: number): number
	return startValue + (endValue - startValue) * alpha
end

--[=[
	Returns the sign of a number.

	@param value number -- Number to check
	@return number -- -1 if negative, 0 if zero, 1 if positive

	@example
	```lua
	print(Utilities.sign(-5))  -- -1
	print(Utilities.sign(0))   -- 0
	print(Utilities.sign(5))   -- 1
	```
]=]
function Utilities.sign(value: number): number
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	else
		return 0
	end
end

-- ============================================================================
-- TIMING UTILITIES
-- ============================================================================

--[=[
	Measures the execution time of a function.

	@param fn (...any) -> ...any -- Function to measure
	@param ... any -- Arguments to pass to the function
	@return any -- The function's return value
	@return number -- Elapsed time in seconds

	@example
	```lua
	local function expensiveOperation(n)
		local sum = 0
		for i = 1, n do sum += i end
		return sum
	end

	local result, elapsed = Utilities.measureTime(expensiveOperation, 1000000)
	print("Result:", result)
	print("Time:", elapsed, "seconds")
	```
]=]
function Utilities.measureTime(fn: (...any) -> ...any, ...: any): (any, number)
	local startTime = os.clock()
	local result = fn(...)
	local endTime = os.clock()
	return result, endTime - startTime
end

--[=[
	Creates a simple rate limiter that tracks if enough time has passed.

	@param intervalSeconds number -- Minimum seconds between allowed calls
	@return () -> boolean -- Function that returns true if interval has passed

	@example
	```lua
	local canPlan = Utilities.createRateLimiter(0.5) -- 2 per second max

	-- In update loop:
	if canPlan() then
		planner:plan(state, goal)
	end
	```
]=]
function Utilities.createRateLimiter(intervalSeconds: number): () -> boolean
	assert(type(intervalSeconds) == "number" and intervalSeconds > 0, "intervalSeconds must be a positive number")

	local lastCallTime = 0

	return function(): boolean
		local currentTime = os.clock()
		if currentTime - lastCallTime >= intervalSeconds then
			lastCallTime = currentTime
			return true
		end
		return false
	end
end

-- ============================================================================
-- VALIDATION UTILITIES
-- ============================================================================

--[=[
	Validates that a value is of the expected type.
	Throws an error with a descriptive message if validation fails.

	@param value any -- Value to validate
	@param expectedType string -- Expected Luau type
	@param paramName string -- Parameter name for error message

	@example
	```lua
	function setHealth(amount)
		Utilities.assertType(amount, "number", "amount")
		-- ...
	end

	setHealth("100") -- Error: "amount must be a number, got string"
	```
]=]
function Utilities.assertType(value: any, expectedType: string, paramName: string)
	local actualType = type(value)
	if actualType ~= expectedType then
		error(`{paramName} must be a {expectedType}, got {actualType}`, 2)
	end
end

--[=[
	Validates that a value is not nil.
	Throws an error with a descriptive message if value is nil.

	@param value any -- Value to validate
	@param paramName string -- Parameter name for error message

	@example
	```lua
	function processAction(action)
		Utilities.assertNotNil(action, "action")
		-- ...
	end

	processAction(nil) -- Error: "action cannot be nil"
	```
]=]
function Utilities.assertNotNil(value: any, paramName: string)
	if value == nil then
		error(`{paramName} cannot be nil`, 2)
	end
end

--[=[
	Validates that a number is within a range.
	Throws an error if the value is outside the bounds.

	@param value number -- Value to validate
	@param minValue number -- Minimum allowed value
	@param maxValue number -- Maximum allowed value
	@param paramName string -- Parameter name for error message

	@example
	```lua
	function setPriority(priority)
		Utilities.assertInRange(priority, 0, 100, "priority")
		-- ...
	end

	setPriority(150) -- Error: "priority must be between 0 and 100, got 150"
	```
]=]
function Utilities.assertInRange(value: number, minValue: number, maxValue: number, paramName: string)
	Utilities.assertType(value, "number", paramName)
	if value < minValue or value > maxValue then
		error(`{paramName} must be between {minValue} and {maxValue}, got {value}`, 2)
	end
end

return Utilities
