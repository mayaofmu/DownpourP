--!strict
--// State.lua
--// Represents the world state as a collection of key-value pairs.
--//
--// The State class is the foundation of the GOAP system - it represents
--// what the world looks like at any given moment. Actions have preconditions
--// (required state) and effects (state changes they produce).
--//
--// Features:
--// - O(1) cached hashing for efficient A* planning
--// - Dirty tracking for change detection
--// - JSON serialization for DataStore persistence
--// - Batch operations for efficiency

local HttpService = game:GetService("HttpService")

--// ============================================================================
--// TYPE DEFINITIONS
--// ============================================================================

--// Values that can be stored in a State. Must be JSON-serializable.
export type StateValue = string | number | boolean | { [string]: StateValue }

--// The internal data structure of a State.
export type StateData = { [string]: StateValue }

--// Serialized entry with type information
type SerializedEntry = {
	type: string,
	value: string | number | boolean,
}

--// Complete serialized state structure
type SerializedState = {
	_version: number,
	_timestamp: number,
	data: { [string]: SerializedEntry },
}

--// ============================================================================
--// CONSTANTS
--// ============================================================================

local SERIALIZE_VERSION: number = 1
local LOG_PREFIX = "[Goal.State]"

local SERIALIZABLE_TYPES: { [string]: boolean } = table.freeze({
	string = true,
	number = true,
	boolean = true,
	table = true,
})

--// ============================================================================
--// CLASS DEFINITION
--// ============================================================================

local State = {}
State.__index = State
State.SERIALIZE_VERSION = SERIALIZE_VERSION

--// ============================================================================
--// CONSTRUCTOR
--// ============================================================================

--// Binary search to find insertion index for sorted array
local function binarySearchInsertIndex(arr: { string }, value: string): number
	local low, high = 1, #arr
	while low <= high do
		local mid = math.floor((low + high) / 2)
		if arr[mid] < value then
			low = mid + 1
		else
			high = mid - 1
		end
	end
	return low
end

--// Binary search to find key index (returns nil if not found)
local function binarySearchFind(arr: { string }, value: string): number?
	local low, high = 1, #arr
	while low <= high do
		local mid = math.floor((low + high) / 2)
		if arr[mid] == value then
			return mid
		elseif arr[mid] < value then
			low = mid + 1
		else
			high = mid - 1
		end
	end
	return nil
end

--// Creates a new State object with optional initial data.
function State.new(initialData: StateData?): State
	local self = setmetatable({}, State)

	--// Clone initial data to prevent external mutations
	self._data = if initialData then table.clone(initialData) else {}
	self._dirty = true
	self._version = SERIALIZE_VERSION

	--// Hash caching for O(1) hash lookups (critical for A* planning performance)
	self._hash = nil :: string?
	self._sortedKeys = {} :: { string }

	--// Build sorted keys from initial data
	if initialData then
		for key in pairs(initialData) do
			table.insert(self._sortedKeys, key)
		end
		table.sort(self._sortedKeys)
	end

	return self
end

--// ============================================================================
--// HASH CACHING (Performance Critical)
--// ============================================================================

--// Returns a unique hash string for this state.
--// Uses O(1) cached lookup when state hasn't changed.
--// This is critical for A* planning performance.
function State:getHash(): string
	if self._hash then
		return self._hash
	end

	--// Fast hash using buffer (avoids table allocation)
	local data = self._data
	local sortedKeys = self._sortedKeys
	local keyCount = #sortedKeys
	if keyCount == 0 then
		self._hash = ""
		return ""
	end

	--// Build hash string directly using buffer pattern
	local buffer = table.create(keyCount * 2)
	local idx = 0
	for i = 1, keyCount do
		local key = sortedKeys[i]
		idx += 1
		buffer[idx] = key
		idx += 1
		local val = data[key]
		--// Fast value to string (avoid tostring for common types)
		local t = type(val)
		if t == "boolean" then
			buffer[idx] = if val then "T" else "F"
		elseif t == "number" then
			--// Round to reduce hash changes from float drift
			buffer[idx] = string.format("%.2f", val)
		else
			buffer[idx] = tostring(val)
		end
	end

	self._hash = table.concat(buffer)
	return self._hash
end

--// Invalidates the hash cache (called on mutations)
function State:_invalidateHash()
	self._hash = nil
end

--// Inserts a key into the sorted keys array (binary insertion)
function State:_insertKey(key: string)
	local idx = binarySearchInsertIndex(self._sortedKeys, key)
	table.insert(self._sortedKeys, idx, key)
end

--// Removes a key from the sorted keys array (binary search + remove)
function State:_removeKey(key: string)
	local idx = binarySearchFind(self._sortedKeys, key)
	if idx then
		table.remove(self._sortedKeys, idx)
	end
end

--// ============================================================================
--// BASIC GETTERS & SETTERS
--// ============================================================================

--// Gets a value from the state by key.
--// Returns nil if the key doesn't exist.
function State:get(key: string): StateValue?
	return self._data[key]
end

--// Sets a value in the state.
--// Only marks dirty and invalidates hash if value actually changed.
function State:set(key: string, value: StateValue)
	local data = self._data
	local oldValue = data[key]
	if oldValue ~= value then
		data[key] = value
		--// Only invalidate hash if not already dirty (avoids redundant nil assignment)
		if not self._dirty then
			self._dirty = true
			self._hash = nil
		elseif self._hash then
			self._hash = nil
		end
		if oldValue == nil then
			self:_insertKey(key)
		end
	end
end

--// Removes a key from the state.
--// Only marks dirty if the key existed.
function State:remove(key: string)
	if self._data[key] ~= nil then
		self._data[key] = nil
		self._dirty = true
		self:_invalidateHash()
		self:_removeKey(key)
	end
end

--// Checks if the state contains a key.
--// This checks key existence, not truthiness - a key with value `false` returns true.
function State:has(key: string): boolean
	return self._data[key] ~= nil
end

--// Returns a copy of all state data as a table.
--// The returned table is a clone, so modifications won't affect the original.
function State:getData(): StateData
	return table.clone(self._data)
end

--// ============================================================================
--// CLONING & MERGING
--// ============================================================================

--// Creates a deep clone of this state.
--// The clone is independent and preserves the cached hash for efficiency.
function State:clone(): State
	local cloned = setmetatable({}, State)
	cloned._data = table.clone(self._data)
	cloned._dirty = self._dirty
	cloned._version = self._version
	--// Preserve hash cache and sorted keys for efficiency
	cloned._hash = self._hash
	cloned._sortedKeys = table.clone(self._sortedKeys)
	return cloned
end

--// Creates a clone with modifications applied.
--// More efficient than clone() + setMultiple() for A* planning.
function State:cloneWithChanges(changes: StateData): State
	local cloned = setmetatable({}, State)
	local newData = table.clone(self._data)
	local newSortedKeys = table.clone(self._sortedKeys)

	--// Apply changes and update sorted keys
	for key, value in changes do
		local isNew = newData[key] == nil
		newData[key] = value
		if isNew then
			--// Binary insert for new key
			local low, high = 1, #newSortedKeys
			while low <= high do
				local mid = math.floor((low + high) / 2)
				if newSortedKeys[mid] < key then
					low = mid + 1
				else
					high = mid - 1
				end
			end
			table.insert(newSortedKeys, low, key)
		end
	end

	cloned._data = newData
	cloned._dirty = true
	cloned._version = self._version
	cloned._hash = nil --// Must recompute hash
	cloned._sortedKeys = newSortedKeys
	return cloned
end

--// Merges another state into this one.
--// Values from the other state overwrite values in this state.
function State:merge(other: State)
	local changed = false
	for key, value in pairs(other._data) do
		local isNew = self._data[key] == nil
		if self._data[key] ~= value then
			self._data[key] = value
			changed = true
			if isNew then
				self:_insertKey(key)
			end
		end
	end
	if changed then
		self._dirty = true
		self:_invalidateHash()
	end
end

--// ============================================================================
--// CONDITION CHECKING
--// ============================================================================

--// Checks if this state satisfies all conditions in another state.
--// Core method used by Planner to check preconditions and goal achievement.
--// This is a hot path - direct table access for maximum performance.
function State:satisfies(conditions: State): boolean
	local selfData = self._data
	local condData = conditions._data
	for key, value in condData do
		if selfData[key] ~= value then
			return false
		end
	end
	return true
end

--// Fast satisfies check using raw table (for internal use).
--// Avoids metatable overhead when checking simple conditions.
function State:satisfiesRaw(conditions: { [string]: StateValue }): boolean
	local selfData = self._data
	for key, value in conditions do
		if selfData[key] ~= value then
			return false
		end
	end
	return true
end

--// Gets the keys that differ between this state and a goal state.
--// Useful for debugging why a goal isn't satisfied.
function State:difference(goalState: State): { string }
	local diff = {}
	local selfData = self._data
	for key, value in goalState._data do
		if selfData[key] ~= value then
			table.insert(diff, key)
		end
	end
	return diff
end

--// Counts the number of unsatisfied conditions.
--// Used by the Planner's heuristic function for A* search - lower is better.
--// This is a hot path - direct table access for maximum performance.
function State:countUnsatisfied(conditions: State): number
	local count = 0
	local selfData = self._data
	for key, value in conditions._data do
		if selfData[key] ~= value then
			count += 1
		end
	end
	return count
end

--// Fast count using raw table (for internal use).
function State:countUnsatisfiedRaw(conditions: { [string]: StateValue }): number
	local count = 0
	local selfData = self._data
	for key, value in conditions do
		if selfData[key] ~= value then
			count += 1
		end
	end
	return count
end

--// ============================================================================
--// ITERATION
--// ============================================================================

--// Returns an iterator over all key-value pairs in the state.
function State:pairs(): () -> (string?, StateValue?)
	return pairs(self._data) :: () -> (string?, StateValue?)
end

--// Returns the number of entries in the state.
--// Uses cached sorted keys array for O(1) performance.
function State:size(): number
	return #self._sortedKeys
end

--// Returns all keys in the state as an array.
--// Returns a copy of the sorted keys array.
function State:keys(): { string }
	return table.clone(self._sortedKeys)
end

--// Returns all values in the state as an array.
function State:values(): { StateValue }
	local result = table.create(#self._sortedKeys)
	for i, key in ipairs(self._sortedKeys) do
		result[i] = self._data[key]
	end
	return result
end

--// ============================================================================
--// DIRTY FLAG SYSTEM
--// ============================================================================

--// Checks if the state has been modified since the last markClean() call.
--// Used by the Planner in performance mode to skip unnecessary replanning.
function State:isDirty(): boolean
	return self._dirty
end

--// Marks the state as clean (not modified).
--// Call this after processing state changes (e.g., after replanning).
function State:markClean()
	self._dirty = false
end

--// Marks the state as dirty (modified).
--// Use this to force replanning even without set() calls.
function State:markDirty()
	self._dirty = true
end

--// ============================================================================
--// SERIALIZATION
--// ============================================================================

--// Serializes the state to a JSON-safe table with type information.
--// Tables nested in the state must be JSON-compatible.
function State:serialize(): SerializedState
	local serialized: SerializedState = {
		_version = self._version,
		_timestamp = os.time(),
		data = {},
	}

	for key, value in pairs(self._data) do
		local valueType = type(value)

		if not SERIALIZABLE_TYPES[valueType] then
			warn(`{LOG_PREFIX} serialize: Unsupported type '{valueType}' for key '{key}'`)
			continue
		end

		if valueType == "table" then
			local success, encoded = pcall(function()
				return HttpService:JSONEncode(value)
			end)
			if success then
				serialized.data[key] = {
					type = "table",
					value = encoded,
				}
			else
				warn(`{LOG_PREFIX} serialize: Failed to serialize table for key '{key}'`)
			end
		else
			serialized.data[key] = {
				type = valueType,
				value = value,
			}
		end
	end

	return serialized
end

--// Serializes the state to a JSON string ready for DataStore.
--// Returns (json, nil) on success or (nil, errorMessage) on failure.
function State:toJSON(): (string?, string?)
	local serialized = self:serialize()
	local success, result = pcall(function()
		return HttpService:JSONEncode(serialized)
	end)

	if success then
		return result, nil
	else
		return nil, tostring(result)
	end
end

--// Deserializes a state from a serialized table.
--// Returns (state, nil) on success or (nil, errorMessage) on failure.
function State.deserialize(serialized: SerializedState): (State?, string?)
	if type(serialized) ~= "table" then
		return nil, "Invalid serialized data: expected table"
	end

	local version = serialized._version or 0
	if version > SERIALIZE_VERSION then
		return nil, `Incompatible version: data version {version} is newer than supported version {SERIALIZE_VERSION}`
	end

	if not serialized.data then
		return nil, "Invalid serialized data: missing 'data' field"
	end

	local data: StateData = {}

	for key, entry in pairs(serialized.data) do
		if type(entry) ~= "table" or not entry.type then
			warn(`{LOG_PREFIX} deserialize: Skipping invalid entry for key '{key}'`)
			continue
		end

		local valueType = entry.type
		local value = entry.value

		if valueType == "string" or valueType == "number" or valueType == "boolean" then
			data[key] = value
		elseif valueType == "table" then
			local success, decoded = pcall(function()
				return HttpService:JSONDecode(value)
			end)
			if success then
				data[key] = decoded
			else
				warn(`{LOG_PREFIX} deserialize: Failed to decode table for key '{key}'`)
			end
		end
	end

	local state = State.new(data)
	state._dirty = false

	return state, nil
end

--// Deserializes a state from a JSON string (e.g., from DataStore).
--// Returns (state, nil) on success or (nil, errorMessage) on failure.
function State.fromJSON(json: string): (State?, string?)
	if type(json) ~= "string" then
		return nil, "Invalid JSON: expected string"
	end

	local success, decoded = pcall(function()
		return HttpService:JSONDecode(json)
	end)

	if not success then
		return nil, `Failed to decode JSON: {tostring(decoded)}`
	end

	return State.deserialize(decoded)
end

--// ============================================================================
--// FACTORY METHODS
--// ============================================================================

--// Creates a state from a simple key-value table.
--// Alias for State.new() for more descriptive code.
function State.fromTable(data: StateData): State
	return State.new(data)
end

--// Exports the state to a simple key-value table.
--// Alias for getData() for more descriptive code.
function State:toTable(): StateData
	return self:getData()
end

--// ============================================================================
--// BATCH OPERATIONS
--// ============================================================================

--// Sets multiple values at once.
--// More efficient than calling set() multiple times.
function State:setMultiple(values: StateData)
	local changed = false
	for key, value in pairs(values) do
		local isNew = self._data[key] == nil
		if self._data[key] ~= value then
			self._data[key] = value
			changed = true
			if isNew then
				self:_insertKey(key)
			end
		end
	end
	if changed then
		self._dirty = true
		self:_invalidateHash()
	end
end

--// Gets multiple values at once.
function State:getMultiple(keys: { string }): StateData
	local result: StateData = {}
	for _, key in ipairs(keys) do
		result[key] = self._data[key]
	end
	return result
end

--// Removes multiple keys at once.
function State:removeMultiple(keys: { string })
	local changed = false
	for _, key in ipairs(keys) do
		if self._data[key] ~= nil then
			self._data[key] = nil
			self:_removeKey(key)
			changed = true
		end
	end
	if changed then
		self._dirty = true
		self:_invalidateHash()
	end
end

--// Clears all data from the state.
function State:clear()
	if next(self._data) ~= nil then
		table.clear(self._data)
		table.clear(self._sortedKeys)
		self._dirty = true
		self:_invalidateHash()
	end
end

--// ============================================================================
--// COMPARISON
--// ============================================================================

--// Checks if this state is equal to another state.
--// Two states are equal if they have the same key-value pairs.
function State:equals(other: State): boolean
	--// Quick check: different key counts means not equal
	if #self._sortedKeys ~= #other._sortedKeys then
		return false
	end

	--// Check all keys in self exist in other with same values
	for key, value in pairs(self._data) do
		if other._data[key] ~= value then
			return false
		end
	end

	return true
end

--// Checks if this state is a subset of another state.
--// Returns true if all key-value pairs in this state exist in the other.
function State:isSubsetOf(other: State): boolean
	for key, value in pairs(self._data) do
		if other._data[key] ~= value then
			return false
		end
	end
	return true
end

--// ============================================================================
--// DEBUGGING
--// ============================================================================

--// String representation for debugging.
--// Uses cached sorted keys for consistent output order.
function State:__tostring(): string
	local parts = table.create(#self._sortedKeys)
	for i, key in ipairs(self._sortedKeys) do
		parts[i] = `{key}={tostring(self._data[key])}`
	end
	return `State\{{table.concat(parts, ", ")}}`
end

--// ============================================================================
--// OBJECT POOLING
--// ============================================================================

--// Resets the state for reuse (clears all data and caches).
--// More efficient than creating new State objects when pooling.
function State:reset(initialData: StateData?)
	table.clear(self._data)
	table.clear(self._sortedKeys)
	self._dirty = true
	self._hash = nil

	if initialData then
		for key, value in initialData do
			self._data[key] = value
			table.insert(self._sortedKeys, key)
		end
		table.sort(self._sortedKeys)
	end
end

--// Populates state data directly without creating a new object.
--// Faster than set() for bulk population when you have all data upfront.
function State:populate(data: StateData)
	local selfData = self._data
	local sortedKeys = self._sortedKeys
	local needsSort = false

	for key, value in data do
		local isNew = selfData[key] == nil
		selfData[key] = value
		if isNew then
			table.insert(sortedKeys, key)
			needsSort = true
		end
	end

	if needsSort then
		table.sort(sortedKeys)
	end

	self._dirty = true
	self._hash = nil
end

--// ============================================================================
--// STATE POOL (Object Recycling)
--// ============================================================================

--// Pool for reusing State objects to reduce GC pressure.
--// Critical for 800+ NPCs where each NPC rebuilds state every frame.
local StatePool = {}
StatePool.__index = StatePool

function StatePool.new(initialSize: number?): typeof(StatePool.new())
	local self = setmetatable({}, StatePool)
	local size = initialSize or 64
	self._pool = table.create(size) :: { State }
	self._poolSize = 0
	self._totalCreated = 0
	self._totalReused = 0
	return self
end

--// Acquires a state from the pool or creates a new one.
function StatePool:acquire(initialData: StateData?): State
	if self._poolSize > 0 then
		local state = self._pool[self._poolSize]
		self._pool[self._poolSize] = nil
		self._poolSize -= 1
		self._totalReused += 1
		state:reset(initialData)
		return state
	end

	self._totalCreated += 1
	return State.new(initialData)
end

--// Returns a state to the pool for reuse.
function StatePool:release(state: State)
	local poolSize = self._poolSize + 1
	self._poolSize = poolSize
	self._pool[poolSize] = state
end

--// Clears the pool (for memory cleanup).
function StatePool:clear()
	table.clear(self._pool)
	self._poolSize = 0
end

--// Gets pool statistics.
function StatePool:getStats(): { poolSize: number, totalCreated: number, totalReused: number, reuseRate: number }
	local total = self._totalCreated + self._totalReused
	return {
		poolSize = self._poolSize,
		totalCreated = self._totalCreated,
		totalReused = self._totalReused,
		reuseRate = if total > 0 then self._totalReused / total else 0,
	}
end

--// Export pool class
State.Pool = StatePool

--// ============================================================================
--// TYPE EXPORT
--// ============================================================================

--// Export type for external use.
export type State = typeof(State.new())
export type StatePool = typeof(StatePool.new())

return State
