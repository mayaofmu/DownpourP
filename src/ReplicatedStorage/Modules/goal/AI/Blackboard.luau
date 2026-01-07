--!strict
--[[
	Blackboard.lua
	Shared knowledge system for coordinated AI behavior.

	A Blackboard provides a central repository for shared information
	between multiple NPCs and AI systems. This enables coordinated
	behaviors like squad tactics, target assignment, and shared awareness.

	┌─────────────────────────────────────────────────────────────────────────┐
	│                        BLACKBOARD ARCHITECTURE                          │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│                        ┌──────────────────┐                             │
	│                        │    BLACKBOARD    │                             │
	│                        │                  │                             │
	│                        │  ┌────────────┐  │                             │
	│   ┌─────────┐         │  │  Targets   │  │         ┌─────────┐        │
	│   │  NPC 1  │◄───────►│  │  Threats   │  │◄───────►│  NPC 3  │        │
	│   └─────────┘         │  │  Positions │  │         └─────────┘        │
	│                        │  │  Orders    │  │                             │
	│   ┌─────────┐         │  │  Signals   │  │         ┌─────────┐        │
	│   │  NPC 2  │◄───────►│  └────────────┘  │◄───────►│  NPC 4  │        │
	│   └─────────┘         │                  │         └─────────┘        │
	│                        └──────────────────┘                             │
	│                                                                         │
	│   Read/Write Operations:                                                │
	│   • post(key, value, owner)     - Share information                    │
	│   • read(key)                   - Get shared information               │
	│   • claim(key, owner)           - Claim exclusive access               │
	│   • subscribe(key, callback)    - React to changes                     │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class Blackboard
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Features

	- **Shared Knowledge**: Central repository for NPC coordination
	- **Ownership Tracking**: Know which NPC posted each entry
	- **Expiration**: Entries can auto-expire after a duration
	- **Subscriptions**: React to blackboard changes
	- **Channels**: Organize entries by logical channels
	- **Thread-Safe Design**: Safe for concurrent access patterns

	## Basic Usage

	```lua
	local Blackboard = require(path.to.Blackboard)

	-- Create a squad blackboard
	local squadBoard = Blackboard.new({ name = "Alpha Squad" })

	-- NPC posts target information
	squadBoard:post("primary_target", {
		id = "player_1",
		position = Vector3.new(10, 0, 5),
		threat = 0.8,
	}, "guard_1", 30) -- Expires in 30 seconds

	-- Another NPC reads the target
	local target = squadBoard:read("primary_target")

	-- NPCs claim targets to avoid duplication
	local claimed = squadBoard:claim("primary_target", "guard_2")
	```

	## Squad Coordination

	```lua
	-- Create shared awareness
	squadBoard:post("enemy_spotted", {
		position = enemyPos,
		count = 3,
	}, myId)

	-- Check if anyone else is handling a target
	local claimedBy = squadBoard:getOwner("target_1")
	if not claimedBy or claimedBy == myId then
		-- Take action
	end

	-- Subscribe to alerts
	squadBoard:subscribe("alert", function(key, value, owner)
		respondToAlert(value)
	end)
	```
]]

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

--[=[
	@interface BlackboardEntry
	@within Blackboard
	.key string -- Entry key
	.value any -- Entry value
	.owner string? -- Who posted this entry
	.timestamp number -- When it was posted
	.expiresAt number? -- When it expires (nil = never)
	.channel string -- Channel this entry belongs to
	.metadata { [string]: any }? -- Optional metadata
]=]
export type BlackboardEntry = {
	key: string,
	value: any,
	owner: string?,
	timestamp: number,
	expiresAt: number?,
	channel: string,
	metadata: { [string]: any }?,
}

--[=[
	@interface BlackboardConfig
	@within Blackboard
	.name string? -- Blackboard name for debugging
	.defaultExpiration number? -- Default expiration time in seconds (default: nil = never)
	.maxEntries number? -- Maximum entries to store (default: 1000)
	.cleanupInterval number? -- Seconds between auto-cleanup (default: 10)
]=]
export type BlackboardConfig = {
	name: string?,
	defaultExpiration: number?,
	maxEntries: number?,
	cleanupInterval: number?,
}

--[=[
	@type SubscriptionCallback (key: string, value: any, owner: string?, entry: BlackboardEntry) -> ()
	@within Blackboard
	Callback function for blackboard subscriptions.
]=]
type SubscriptionCallback = (key: string, value: any, owner: string?, entry: BlackboardEntry) -> ()

--[=[
	@interface Subscription
	@within Blackboard
	.id string -- Unique subscription ID
	.pattern string -- Key pattern to match (supports * wildcard)
	.channel string? -- Channel to filter by
	.callback SubscriptionCallback -- Function to call on match
]=]
type Subscription = {
	id: string,
	pattern: string,
	channel: string?,
	callback: SubscriptionCallback,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

--- Default configuration values.
local DEFAULT_CONFIG: BlackboardConfig = table.freeze({
	name = "Blackboard",
	defaultExpiration = nil,
	maxEntries = 1000,
	cleanupInterval = 10,
})

--- Default channel name.
local DEFAULT_CHANNEL = "default"

--- Log prefix for warning/error messages.
local LOG_PREFIX = "[Goal.Blackboard]"

-- ============================================================================
-- CLASS DEFINITION
-- ============================================================================

--[=[
	@class Blackboard
	@tag UtilityAI

	A shared knowledge repository for coordinated AI behavior.
	Enables NPCs to share information, claim targets, and react to events.
]=]
local Blackboard = {}
Blackboard.__index = Blackboard

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

--[=[
	Creates a new Blackboard.

	@param config BlackboardConfig? -- Optional configuration
	@return Blackboard -- The newly created blackboard

	@example Basic Blackboard
	```lua
	local board = Blackboard.new()
	```

	@example Named Blackboard with Expiration
	```lua
	local squadBoard = Blackboard.new({
		name = "Alpha Squad",
		defaultExpiration = 60, -- Entries expire after 60s by default
	})
	```
]=]
function Blackboard.new(config: BlackboardConfig?): Blackboard
	local self = setmetatable({}, Blackboard)

	local cfg = config or {}

	-- Configuration
	self.name = cfg.name or DEFAULT_CONFIG.name
	self.defaultExpiration = cfg.defaultExpiration
	self.maxEntries = cfg.maxEntries or DEFAULT_CONFIG.maxEntries
	self.cleanupInterval = cfg.cleanupInterval or DEFAULT_CONFIG.cleanupInterval

	-- Storage
	self._entries = {} :: { [string]: BlackboardEntry }
	self._channels = {} :: { [string]: { string } } -- Channel -> keys
	self._claims = {} :: { [string]: string } -- Key -> claimant
	self._subscriptions = {} :: { Subscription }

	-- State
	self._lastCleanup = os.clock()
	self._entryCount = 0
	self._subscriptionCounter = 0

	return self
end

-- ============================================================================
-- CORE OPERATIONS
-- ============================================================================

--[=[
	Posts a value to the blackboard.

	@param key string -- Entry key
	@param value any -- Entry value
	@param owner string? -- Who is posting this (optional)
	@param expiresIn number? -- Seconds until expiration (optional)
	@param channel string? -- Channel to post to (default: "default")
	@param metadata { [string]: any }? -- Optional metadata
	@return BlackboardEntry -- The created entry

	@example
	```lua
	-- Post target location
	board:post("target_position", Vector3.new(10, 0, 5), "scout_1", 30)

	-- Post with channel
	board:post("suppression_needed", true, "squad_lead", nil, "combat")

	-- Post with metadata
	board:post("threat", enemyData, "scout", 60, "default", {
		priority = "high",
		confirmedBy = 2,
	})
	```
]=]
function Blackboard:post(
	key: string,
	value: any,
	owner: string?,
	expiresIn: number?,
	channel: string?,
	metadata: { [string]: any }?
): BlackboardEntry
	local now = os.clock()
	local channelName = channel or DEFAULT_CHANNEL

	-- Calculate expiration
	local expiration: number? = nil
	if expiresIn then
		expiration = now + expiresIn
	elseif self.defaultExpiration then
		expiration = now + self.defaultExpiration
	end

	-- Create entry
	local entry: BlackboardEntry = {
		key = key,
		value = value,
		owner = owner,
		timestamp = now,
		expiresAt = expiration,
		channel = channelName,
		metadata = metadata,
	}

	-- Store entry
	local isNew = self._entries[key] == nil
	self._entries[key] = entry

	if isNew then
		self._entryCount += 1
	end

	-- Update channel index
	if not self._channels[channelName] then
		self._channels[channelName] = {}
	end
	if isNew then
		table.insert(self._channels[channelName], key)
	end

	-- Notify subscribers
	self:_notifySubscribers(key, value, owner, entry)

	-- Enforce max entries
	if self._entryCount > self.maxEntries then
		self:_pruneOldestEntries()
	end

	return entry
end

--[=[
	Reads a value from the blackboard.

	@param key string -- Entry key
	@return any? -- The value, or nil if not found/expired

	@example
	```lua
	local targetPos = board:read("target_position")
	if targetPos then
		moveTo(targetPos)
	end
	```
]=]
function Blackboard:read(key: string): any?
	local entry = self._entries[key]
	if not entry then
		return nil
	end

	-- Check expiration
	if entry.expiresAt and os.clock() > entry.expiresAt then
		self:remove(key)
		return nil
	end

	return entry.value
end

--[=[
	Gets the full entry for a key.

	@param key string -- Entry key
	@return BlackboardEntry? -- The full entry, or nil

	@example
	```lua
	local entry = board:getEntry("target")
	if entry then
		print("Posted by:", entry.owner)
		print("Posted at:", entry.timestamp)
	end
	```
]=]
function Blackboard:getEntry(key: string): BlackboardEntry?
	local entry = self._entries[key]
	if not entry then
		return nil
	end

	-- Check expiration
	if entry.expiresAt and os.clock() > entry.expiresAt then
		self:remove(key)
		return nil
	end

	return entry
end

--[=[
	Checks if a key exists and is not expired.

	@param key string -- Entry key
	@return boolean -- True if key exists and is valid

	@example
	```lua
	if board:has("primary_target") then
		-- Target is known
	end
	```
]=]
function Blackboard:has(key: string): boolean
	return self:read(key) ~= nil
end

--[=[
	Removes an entry from the blackboard.

	@param key string -- Entry key
	@return boolean -- True if entry was removed

	@example
	```lua
	board:remove("old_target")
	```
]=]
function Blackboard:remove(key: string): boolean
	local entry = self._entries[key]
	if not entry then
		return false
	end

	-- Remove from entries
	self._entries[key] = nil
	self._entryCount -= 1

	-- Remove from channel index
	local channelKeys = self._channels[entry.channel]
	if channelKeys then
		for i, k in ipairs(channelKeys) do
			if k == key then
				table.remove(channelKeys, i)
				break
			end
		end
	end

	-- Remove any claims
	self._claims[key] = nil

	return true
end

--[=[
	Gets the owner of an entry.

	@param key string -- Entry key
	@return string? -- The owner, or nil

	@example
	```lua
	local claimedBy = board:getOwner("target_1")
	if claimedBy == nil then
		-- Nobody is handling this target
	end
	```
]=]
function Blackboard:getOwner(key: string): string?
	local entry = self._entries[key]
	return if entry then entry.owner else nil
end

-- ============================================================================
-- CLAIMING SYSTEM
-- ============================================================================

--[=[
	Claims exclusive access to a key.

	Claiming prevents multiple NPCs from acting on the same target.
	Only one NPC can claim a key at a time.

	@param key string -- Entry key to claim
	@param claimant string -- Who is claiming
	@return boolean -- True if claim was successful

	@example
	```lua
	-- Try to claim a target
	if board:claim("target_1", myId) then
		-- I'm now responsible for this target
		attackTarget(board:read("target_1"))
	else
		-- Someone else already claimed it
		findAnotherTarget()
	end
	```
]=]
function Blackboard:claim(key: string, claimant: string): boolean
	-- Check if entry exists
	if not self:has(key) then
		return false
	end

	-- Check if already claimed
	local currentClaimant = self._claims[key]
	if currentClaimant and currentClaimant ~= claimant then
		return false
	end

	self._claims[key] = claimant
	return true
end

--[=[
	Releases a claim on a key.

	@param key string -- Entry key
	@param claimant string -- Who is releasing (must match current claimant)
	@return boolean -- True if claim was released

	@example
	```lua
	-- Done with target
	board:releaseClaim("target_1", myId)
	```
]=]
function Blackboard:releaseClaim(key: string, claimant: string): boolean
	local currentClaimant = self._claims[key]
	if currentClaimant == claimant then
		self._claims[key] = nil
		return true
	end
	return false
end

--[=[
	Gets who claimed a key.

	@param key string -- Entry key
	@return string? -- The claimant, or nil

	@example
	```lua
	local claimant = board:getClaimant("target_1")
	if claimant and claimant ~= myId then
		-- Someone else is handling this
	end
	```
]=]
function Blackboard:getClaimant(key: string): string?
	return self._claims[key]
end

--[=[
	Checks if a key is claimed.

	@param key string -- Entry key
	@return boolean -- True if claimed

	@example
	```lua
	if not board:isClaimed("target_1") then
		board:claim("target_1", myId)
	end
	```
]=]
function Blackboard:isClaimed(key: string): boolean
	return self._claims[key] ~= nil
end

--[=[
	Gets all unclaimed entries.

	@param channel string? -- Optional channel filter
	@return { BlackboardEntry } -- Unclaimed entries

	@example
	```lua
	local availableTargets = board:getUnclaimed("targets")
	for _, entry in ipairs(availableTargets) do
		if canHandle(entry.value) then
			board:claim(entry.key, myId)
			break
		end
	end
	```
]=]
function Blackboard:getUnclaimed(channel: string?): { BlackboardEntry }
	local results = {}
	local now = os.clock()

	for key, entry in pairs(self._entries) do
		-- Check expiration
		if entry.expiresAt and now > entry.expiresAt then
			continue
		end

		-- Check channel
		if channel and entry.channel ~= channel then
			continue
		end

		-- Check if claimed
		if not self._claims[key] then
			table.insert(results, entry)
		end
	end

	return results
end

-- ============================================================================
-- CHANNEL OPERATIONS
-- ============================================================================

--[=[
	Gets all entries in a channel.

	@param channel string -- Channel name
	@return { BlackboardEntry } -- Entries in the channel

	@example
	```lua
	local combatData = board:getChannel("combat")
	for _, entry in ipairs(combatData) do
		processCombatInfo(entry)
	end
	```
]=]
function Blackboard:getChannel(channel: string): { BlackboardEntry }
	local results = {}
	local keys = self._channels[channel]
	local now = os.clock()

	if keys then
		for _, key in ipairs(keys) do
			local entry = self._entries[key]
			if entry and (not entry.expiresAt or now <= entry.expiresAt) then
				table.insert(results, entry)
			end
		end
	end

	return results
end

--[=[
	Clears all entries in a channel.

	@param channel string -- Channel name

	@example
	```lua
	-- Clear old combat data when entering safe zone
	board:clearChannel("combat")
	```
]=]
function Blackboard:clearChannel(channel: string)
	local keys = self._channels[channel]
	if keys then
		-- Clone keys array since we're modifying it
		local keysToRemove = table.clone(keys)
		for _, key in ipairs(keysToRemove) do
			self:remove(key)
		end
	end
end

--[=[
	Gets all channel names.

	@return { string } -- Array of channel names
]=]
function Blackboard:getChannels(): { string }
	local channels = {}
	for channel in pairs(self._channels) do
		table.insert(channels, channel)
	end
	return channels
end

-- ============================================================================
-- SUBSCRIPTIONS
-- ============================================================================

--[=[
	Subscribes to blackboard changes.

	@param pattern string -- Key pattern to match (use * for wildcard)
	@param callback SubscriptionCallback -- Function to call on match
	@param channel string? -- Optional channel filter
	@return string -- Subscription ID (for unsubscribing)

	@example Simple Subscription
	```lua
	local subId = board:subscribe("alert", function(key, value, owner)
		respondToAlert(value)
	end)
	```

	@example Wildcard Subscription
	```lua
	-- Subscribe to all target updates
	board:subscribe("target_*", function(key, value, owner)
		updateTargetDisplay(key, value)
	end)
	```

	@example Channel-Filtered Subscription
	```lua
	-- Only combat channel
	board:subscribe("*", function(key, value, owner)
		processCombatUpdate(key, value)
	end, "combat")
	```
]=]
function Blackboard:subscribe(pattern: string, callback: SubscriptionCallback, channel: string?): string
	self._subscriptionCounter += 1
	local id = `sub_{self._subscriptionCounter}`

	table.insert(self._subscriptions, {
		id = id,
		pattern = pattern,
		channel = channel,
		callback = callback,
	})

	return id
end

--[=[
	Unsubscribes from blackboard changes.

	@param subscriptionId string -- The subscription ID to remove
	@return boolean -- True if subscription was removed

	@example
	```lua
	local subId = board:subscribe("alert", alertHandler)
	-- Later...
	board:unsubscribe(subId)
	```
]=]
function Blackboard:unsubscribe(subscriptionId: string): boolean
	for i, sub in ipairs(self._subscriptions) do
		if sub.id == subscriptionId then
			table.remove(self._subscriptions, i)
			return true
		end
	end
	return false
end

--[=[
	Notifies subscribers of a change.
	@private
]=]
function Blackboard:_notifySubscribers(key: string, value: any, owner: string?, entry: BlackboardEntry)
	for _, sub in ipairs(self._subscriptions) do
		-- Check channel filter
		if sub.channel and sub.channel ~= entry.channel then
			continue
		end

		-- Check pattern match
		if self:_matchesPattern(key, sub.pattern) then
			-- Call subscriber (protected)
			task.spawn(function()
				local success, err = pcall(sub.callback, key, value, owner, entry)
				if not success then
					warn(`{LOG_PREFIX} Subscription callback error: {err}`)
				end
			end)
		end
	end
end

--[=[
	Checks if a key matches a subscription pattern.
	@private
]=]
function Blackboard:_matchesPattern(key: string, pattern: string): boolean
	-- Exact match
	if pattern == key then
		return true
	end

	-- Wildcard match
	if pattern == "*" then
		return true
	end

	-- Prefix wildcard (e.g., "target_*")
	if string.sub(pattern, -1) == "*" then
		local prefix = string.sub(pattern, 1, -2)
		return string.sub(key, 1, #prefix) == prefix
	end

	-- Suffix wildcard (e.g., "*_alert")
	if string.sub(pattern, 1, 1) == "*" then
		local suffix = string.sub(pattern, 2)
		return string.sub(key, -#suffix) == suffix
	end

	return false
end

-- ============================================================================
-- QUERY OPERATIONS
-- ============================================================================

--[=[
	Queries entries by predicate.

	@param predicate (entry: BlackboardEntry) -> boolean -- Filter function
	@return { BlackboardEntry } -- Matching entries

	@example
	```lua
	-- Find all high-priority threats
	local threats = board:query(function(entry)
		return entry.channel == "threats" and
			entry.metadata and
			entry.metadata.priority == "high"
	end)
	```
]=]
function Blackboard:query(predicate: (entry: BlackboardEntry) -> boolean): { BlackboardEntry }
	local results = {}
	local now = os.clock()

	for _, entry in pairs(self._entries) do
		-- Check expiration
		if entry.expiresAt and now > entry.expiresAt then
			continue
		end

		if predicate(entry) then
			table.insert(results, entry)
		end
	end

	return results
end

--[=[
	Gets all entries by owner.

	@param owner string -- Owner to filter by
	@return { BlackboardEntry } -- Entries posted by this owner

	@example
	```lua
	local myPosts = board:getByOwner("scout_1")
	```
]=]
function Blackboard:getByOwner(owner: string): { BlackboardEntry }
	return self:query(function(entry)
		return entry.owner == owner
	end)
end

--[=[
	Gets all keys matching a prefix.

	@param prefix string -- Key prefix
	@return { string } -- Matching keys

	@example
	```lua
	local targetKeys = board:getKeysWithPrefix("target_")
	```
]=]
function Blackboard:getKeysWithPrefix(prefix: string): { string }
	local keys = {}
	for key in pairs(self._entries) do
		if string.sub(key, 1, #prefix) == prefix then
			table.insert(keys, key)
		end
	end
	return keys
end

-- ============================================================================
-- MAINTENANCE
-- ============================================================================

--[=[
	Updates the blackboard (cleanup expired entries).

	Should be called periodically.

	@param deltaTime number? -- Time since last update
]=]
function Blackboard:update(_deltaTime: number?)
	local now = os.clock()

	-- Only cleanup periodically
	if now - self._lastCleanup < self.cleanupInterval then
		return
	end
	self._lastCleanup = now

	-- Remove expired entries
	local expiredKeys = {}
	for key, entry in pairs(self._entries) do
		if entry.expiresAt and now > entry.expiresAt then
			table.insert(expiredKeys, key)
		end
	end

	for _, key in ipairs(expiredKeys) do
		self:remove(key)
	end
end

--[=[
	Prunes oldest entries when at capacity.
	@private
]=]
function Blackboard:_pruneOldestEntries()
	-- Sort entries by timestamp
	local sorted = {}
	for _, entry in pairs(self._entries) do
		table.insert(sorted, entry)
	end
	table.sort(sorted, function(a, b)
		return a.timestamp < b.timestamp
	end)

	-- Remove oldest 10%
	local toRemove = math.ceil(#sorted * 0.1)
	for i = 1, toRemove do
		if sorted[i] then
			self:remove(sorted[i].key)
		end
	end
end

--[=[
	Clears all entries.

	@example
	```lua
	board:clear()
	```
]=]
function Blackboard:clear()
	table.clear(self._entries)
	table.clear(self._channels)
	table.clear(self._claims)
	self._entryCount = 0
end

--[=[
	Gets the number of entries.

	@return number -- Entry count
]=]
function Blackboard:size(): number
	return self._entryCount
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	String representation for debugging.

	@return string -- Formatted string
]=]
function Blackboard:__tostring(): string
	return `Blackboard\{name={self.name}, entries={self._entryCount}}`
end

-- ============================================================================
-- MEMORY MANAGEMENT
-- ============================================================================

--[=[
	Clears all subscriptions.

	IMPORTANT: Call this before destroying the blackboard or when cleaning up
	an NPC that has subscribed to this blackboard. Failing to clear subscriptions
	can cause memory leaks as callbacks may hold references to destroyed objects.

	@example
	```lua
	-- When despawning all NPCs
	board:clearSubscriptions()
	```
]=]
function Blackboard:clearSubscriptions()
	table.clear(self._subscriptions)
	self._subscriptionCounter = 0
end

--[=[
	Removes all subscriptions for a specific owner.

	Use this when an NPC is despawned to clean up its subscriptions.
	This prevents callbacks from being called on destroyed objects.

	@param owner string -- Owner identifier whose subscriptions to remove
	@return number -- Number of subscriptions removed

	@example
	```lua
	-- When NPC with ID "guard_1" is despawned
	local removed = board:clearSubscriptionsForOwner("guard_1")
	print("Removed", removed, "subscriptions")
	```
]=]
function Blackboard:clearSubscriptionsForOwner(owner: string): number
	local newSubscriptions = {}
	local removedCount = 0

	for _, sub in ipairs(self._subscriptions) do
		-- Check if subscription ID contains owner (convention: sub_N_ownerID)
		if not string.find(sub.id, owner, 1, true) then
			table.insert(newSubscriptions, sub)
		else
			removedCount += 1
		end
	end

	self._subscriptions = newSubscriptions
	return removedCount
end

--[=[
	Subscribes with an owner ID for easier cleanup.

	@param pattern string -- Key pattern to match
	@param callback SubscriptionCallback -- Function to call on match
	@param owner string -- Owner identifier for cleanup
	@param channel string? -- Optional channel filter
	@return string -- Subscription ID

	@example
	```lua
	local subId = board:subscribeWithOwner("alert", alertHandler, "guard_1")
	-- Later, when guard_1 is despawned:
	board:clearSubscriptionsForOwner("guard_1")
	```
]=]
function Blackboard:subscribeWithOwner(
	pattern: string,
	callback: SubscriptionCallback,
	owner: string,
	channel: string?
): string
	self._subscriptionCounter += 1
	local id = `sub_{self._subscriptionCounter}_{owner}`

	table.insert(self._subscriptions, {
		id = id,
		pattern = pattern,
		channel = channel,
		callback = callback,
	})

	return id
end

--[=[
	Removes all entries by a specific owner.

	Use this when an NPC is despawned to clean up its posted entries.

	@param owner string -- Owner whose entries to remove
	@return number -- Number of entries removed

	@example
	```lua
	-- When NPC is despawned
	board:clearEntriesForOwner("scout_1")
	```
]=]
function Blackboard:clearEntriesForOwner(owner: string): number
	local keysToRemove = {}

	for key, entry in pairs(self._entries) do
		if entry.owner == owner then
			table.insert(keysToRemove, key)
		end
	end

	for _, key in ipairs(keysToRemove) do
		self:remove(key)
	end

	return #keysToRemove
end

--[=[
	Forces cleanup of all expired entries immediately.

	Unlike update() which only cleans up periodically, this forces
	immediate cleanup. Useful when you need to free memory immediately.

	@return number -- Number of entries removed

	@example
	```lua
	local cleaned = board:cleanup()
	print("Removed", cleaned, "expired entries")
	```
]=]
function Blackboard:cleanup(): number
	local now = os.clock()
	local keysToRemove = {}

	for key, entry in pairs(self._entries) do
		if entry.expiresAt and now > entry.expiresAt then
			table.insert(keysToRemove, key)
		end
	end

	for _, key in ipairs(keysToRemove) do
		self:remove(key)
	end

	self._lastCleanup = now
	return #keysToRemove
end

--[=[
	Destroys the blackboard and releases all resources.

	IMPORTANT: Call this when the blackboard is no longer needed to prevent memory leaks.
	This clears all entries, subscriptions, and claims. After calling destroy(),
	the blackboard should not be used.

	@example
	```lua
	-- When squad is disbanded
	squadBlackboard:destroy()
	```
]=]
function Blackboard:destroy()
	-- Clear all subscriptions (prevents callbacks from being called)
	table.clear(self._subscriptions)

	-- Clear all entries
	table.clear(self._entries)

	-- Clear channel index
	table.clear(self._channels)

	-- Clear claims
	table.clear(self._claims)

	-- Reset counters
	self._entryCount = 0
	self._subscriptionCounter = 0
end

--[=[
	Gets memory statistics for monitoring.

	@return { entries: number, subscriptions: number, channels: number, claims: number }
]=]
function Blackboard:getMemoryStats(): {
	entries: number,
	subscriptions: number,
	channels: number,
	claims: number,
}
	local channelCount = 0
	for _ in pairs(self._channels) do
		channelCount += 1
	end

	local claimCount = 0
	for _ in pairs(self._claims) do
		claimCount += 1
	end

	return {
		entries = self._entryCount,
		subscriptions = #self._subscriptions,
		channels = channelCount,
		claims = claimCount,
	}
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	Creates a debug summary.

	@return string -- Multi-line debug summary
]=]
function Blackboard:debugSummary(): string
	local lines = {
		`Blackboard: {self.name}`,
		`  Entries: {self._entryCount}`,
		`  Subscriptions: {#self._subscriptions}`,
	}

	-- Channels
	local channelCount = 0
	for channel, keys in pairs(self._channels) do
		if #keys > 0 then
			channelCount += 1
			table.insert(lines, `  Channel '{channel}': {#keys} entries`)
		end
	end

	-- Claims
	local claimCount = 0
	for _ in pairs(self._claims) do
		claimCount += 1
	end
	table.insert(lines, `  Active Claims: {claimCount}`)

	-- Recent entries
	local recentEntries = {}
	for _, entry in pairs(self._entries) do
		table.insert(recentEntries, entry)
	end
	table.sort(recentEntries, function(a, b)
		return a.timestamp > b.timestamp
	end)

	if #recentEntries > 0 then
		table.insert(lines, "  Recent Entries:")
		for i = 1, math.min(5, #recentEntries) do
			local entry = recentEntries[i]
			local age = string.format("%.1f", os.clock() - entry.timestamp)
			local owner = entry.owner or "anonymous"
			table.insert(lines, `    - {entry.key} by {owner} ({age}s ago)`)
		end
	end

	return table.concat(lines, "\n")
end

-- ============================================================================
-- TYPE EXPORT
-- ============================================================================

--- Export type for external use.
export type Blackboard = typeof(Blackboard.new())

return Blackboard
