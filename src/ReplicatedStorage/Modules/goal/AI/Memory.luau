--!strict
--[[
	Memory.lua
	Short-term and long-term memory system for intelligent AI agents.

	Memory allows NPCs to remember past events, track patterns, and adapt
	their behavior over time. This creates more believable, learning AI
	that responds to player tactics and environmental changes.

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          MEMORY ARCHITECTURE                            │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│   ┌───────────────────────────────────────────────────────────────┐     │
	│   │                     WORKING MEMORY                            │     │
	│   │   Recent events, active targets, current threats              │     │
	│   │   Duration: seconds to minutes                                │     │
	│   │   Purpose: Immediate tactical decisions                       │     │
	│   └───────────────────────────────────────────────────────────────┘     │
	│                              │                                          │
	│                              ▼ (consolidation)                          │
	│   ┌───────────────────────────────────────────────────────────────┐     │
	│   │                     EPISODIC MEMORY                           │     │
	│   │   Specific events: "Player flanked left at 2:30"              │     │
	│   │   Duration: minutes to hours (with decay)                     │     │
	│   │   Purpose: Pattern recognition, learning                      │     │
	│   └───────────────────────────────────────────────────────────────┘     │
	│                              │                                          │
	│                              ▼ (pattern extraction)                     │
	│   ┌───────────────────────────────────────────────────────────────┐     │
	│   │                     SEMANTIC MEMORY                           │     │
	│   │   Learned facts: "Player prefers flanking (73%)"              │     │
	│   │   Duration: permanent (with reinforcement)                    │     │
	│   │   Purpose: Strategic planning, predictions                    │     │
	│   └───────────────────────────────────────────────────────────────┘     │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class Memory
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Features

	- **Working Memory**: Immediate, short-lived memories for tactical decisions
	- **Episodic Memory**: Event-based memories with timestamps and decay
	- **Semantic Memory**: Long-term learned facts and patterns
	- **Automatic Decay**: Memories fade over time based on importance
	- **Pattern Recognition**: Extract patterns from repeated events
	- **Serialization**: Save and load memory state

	## Basic Usage

	```lua
	local Memory = require(path.to.Memory)

	-- Create memory for an NPC
	local memory = Memory.new({
		workingMemoryDuration = 10,   -- 10 seconds
		episodicDecayRate = 0.1,      -- 10% per minute
		maxEpisodicMemories = 100,
	})

	-- Remember an event
	memory:recordEvent("player_attack", {
		direction = "left",
		damage = 25,
		position = Vector3.new(10, 0, 5),
	})

	-- Check if we remember something
	if memory:hasRecentEvent("player_attack", 5) then
		-- Player attacked in last 5 seconds
	end

	-- Learn from patterns
	memory:recordFact("player_flank_preference", "left", 0.8)
	local preference = memory:getFact("player_flank_preference")
	```
]]

local HttpService = game:GetService("HttpService")

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

--[=[
	@interface MemoryEvent
	@within Memory
	.type string -- Event type/category
	.data { [string]: any } -- Event data
	.timestamp number -- When the event occurred
	.importance number -- How important this event is (0-1)
	.decayRate number -- How fast this memory fades
]=]
export type MemoryEvent = {
	type: string,
	data: { [string]: any },
	timestamp: number,
	importance: number,
	decayRate: number,
}

--[=[
	@interface MemoryFact
	@within Memory
	.key string -- Fact identifier
	.value any -- The learned fact
	.confidence number -- How confident we are (0-1)
	.lastUpdated number -- When this fact was last updated
	.updateCount number -- Number of times this fact was reinforced
]=]
export type MemoryFact = {
	key: string,
	value: any,
	confidence: number,
	lastUpdated: number,
	updateCount: number,
}

--[=[
	@interface MemoryConfig
	@within Memory
	.workingMemoryDuration number? -- How long working memories last (default: 10s)
	.episodicDecayRate number? -- Decay rate per minute for episodic (default: 0.05)
	.maxEpisodicMemories number? -- Max episodic memories to keep (default: 100)
	.maxWorkingMemories number? -- Max working memories to keep (default: 20)
	.factDecayEnabled boolean? -- Whether facts decay without reinforcement (default: false)
	.factDecayRate number? -- Decay rate per hour for unreinforced facts (default: 0.01)
	.patternThreshold number? -- Occurrences needed to form a pattern (default: 3)
]=]
export type MemoryConfig = {
	workingMemoryDuration: number?,
	episodicDecayRate: number?,
	maxEpisodicMemories: number?,
	maxWorkingMemories: number?,
	factDecayEnabled: boolean?,
	factDecayRate: number?,
	patternThreshold: number?,
}

--[=[
	@interface PatternMatch
	@within Memory
	.pattern string -- The pattern type
	.occurrences number -- Number of times observed
	.confidence number -- Confidence in the pattern (0-1)
	.lastOccurrence number -- Timestamp of last occurrence
	.data any -- Associated pattern data
]=]
export type PatternMatch = {
	pattern: string,
	occurrences: number,
	confidence: number,
	lastOccurrence: number,
	data: any,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

--- Default configuration values.
local DEFAULT_CONFIG: MemoryConfig = table.freeze({
	workingMemoryDuration = 10,
	episodicDecayRate = 0.05,
	maxEpisodicMemories = 100,
	maxWorkingMemories = 20,
	factDecayEnabled = false,
	factDecayRate = 0.01,
	patternThreshold = 3,
})

--- Serialization version.
local SERIALIZE_VERSION = 1

-- ============================================================================
-- CLASS DEFINITION
-- ============================================================================

--[=[
	@class Memory
	@tag UtilityAI

	A memory system for AI agents that tracks events, learns patterns,
	and remembers facts over time.
]=]
local Memory = {}
Memory.__index = Memory

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

--[=[
	Creates a new Memory system.

	@param config MemoryConfig? -- Optional configuration
	@return Memory -- The newly created memory system

	@example Basic Memory
	```lua
	local memory = Memory.new()
	```

	@example Configured Memory
	```lua
	local memory = Memory.new({
		workingMemoryDuration = 15,
		maxEpisodicMemories = 200,
		patternThreshold = 5,
	})
	```
]=]
function Memory.new(config: MemoryConfig?): Memory
	local self = setmetatable({}, Memory)

	local cfg = config or {}

	-- Configuration
	self.workingMemoryDuration = cfg.workingMemoryDuration or DEFAULT_CONFIG.workingMemoryDuration
	self.episodicDecayRate = cfg.episodicDecayRate or DEFAULT_CONFIG.episodicDecayRate
	self.maxEpisodicMemories = cfg.maxEpisodicMemories or DEFAULT_CONFIG.maxEpisodicMemories
	self.maxWorkingMemories = cfg.maxWorkingMemories or DEFAULT_CONFIG.maxWorkingMemories
	self.factDecayEnabled = cfg.factDecayEnabled or DEFAULT_CONFIG.factDecayEnabled
	self.factDecayRate = cfg.factDecayRate or DEFAULT_CONFIG.factDecayRate
	self.patternThreshold = cfg.patternThreshold or DEFAULT_CONFIG.patternThreshold

	-- Memory stores
	self._workingMemory = {} :: { MemoryEvent }
	self._episodicMemory = {} :: { MemoryEvent }
	self._semanticMemory = {} :: { [string]: MemoryFact }
	self._patterns = {} :: { [string]: PatternMatch }

	-- Tracking
	self._lastCleanup = os.clock()
	self._eventCounts = {} :: { [string]: number }

	return self
end

-- ============================================================================
-- WORKING MEMORY (Immediate/Tactical)
-- ============================================================================

--[=[
	Records an event to working memory.

	Working memory holds recent events for immediate tactical decisions.
	These memories automatically expire after workingMemoryDuration.

	@param eventType string -- Category of the event
	@param data { [string]: any }? -- Associated data
	@param importance number? -- Importance (0-1, default: 0.5)

	@example
	```lua
	memory:recordEvent("enemy_spotted", {
		enemyId = "guard_1",
		position = Vector3.new(10, 0, 5),
		threat = 0.8,
	}, 0.9)
	```
]=]
function Memory:recordEvent(eventType: string, data: { [string]: any }?, importance: number?)
	local event: MemoryEvent = {
		type = eventType,
		data = data or {},
		timestamp = os.clock(),
		importance = importance or 0.5,
		decayRate = self.episodicDecayRate,
	}

	-- Add to working memory
	table.insert(self._workingMemory, event)

	-- Track event counts for pattern detection
	self._eventCounts[eventType] = (self._eventCounts[eventType] or 0) + 1

	-- Enforce working memory limit
	while #self._workingMemory > self.maxWorkingMemories do
		local removed = table.remove(self._workingMemory, 1)
		-- Important events go to episodic memory
		if removed and removed.importance >= 0.5 then
			self:_consolidateToEpisodic(removed)
		end
	end

	-- Check for patterns
	self:_detectPatterns(eventType, data)
end

--[=[
	Checks if an event of the given type occurred recently.

	@param eventType string -- The event type to check
	@param withinSeconds number? -- Time window (default: workingMemoryDuration)
	@return boolean -- True if event occurred within the time window

	@example
	```lua
	if memory:hasRecentEvent("player_attack", 3) then
		-- Player attacked within last 3 seconds
		npc:enterCombatStance()
	end
	```
]=]
function Memory:hasRecentEvent(eventType: string, withinSeconds: number?): boolean
	local timeWindow = withinSeconds or self.workingMemoryDuration
	local cutoff = os.clock() - timeWindow

	for _, event in ipairs(self._workingMemory) do
		if event.type == eventType and event.timestamp >= cutoff then
			return true
		end
	end

	return false
end

--[=[
	Gets the most recent event of a given type.

	@param eventType string -- The event type to find
	@return MemoryEvent? -- The most recent matching event, or nil

	@example
	```lua
	local lastAttack = memory:getRecentEvent("player_attack")
	if lastAttack then
		local direction = lastAttack.data.direction
		-- React to attack direction
	end
	```
]=]
function Memory:getRecentEvent(eventType: string): MemoryEvent?
	-- Search backwards (most recent first)
	for i = #self._workingMemory, 1, -1 do
		local event = self._workingMemory[i]
		if event.type == eventType then
			return event
		end
	end
	return nil
end

--[=[
	Gets all recent events of a given type.

	@param eventType string -- The event type to find
	@param withinSeconds number? -- Time window (default: workingMemoryDuration)
	@return { MemoryEvent } -- Array of matching events

	@example
	```lua
	local recentDamage = memory:getRecentEvents("damage_taken", 10)
	local totalDamage = 0
	for _, event in ipairs(recentDamage) do
		totalDamage += event.data.amount
	end
	```
]=]
function Memory:getRecentEvents(eventType: string, withinSeconds: number?): { MemoryEvent }
	local timeWindow = withinSeconds or self.workingMemoryDuration
	local cutoff = os.clock() - timeWindow
	local results = {}

	for _, event in ipairs(self._workingMemory) do
		if event.type == eventType and event.timestamp >= cutoff then
			table.insert(results, event)
		end
	end

	return results
end

--[=[
	Gets the count of recent events of a given type.

	@param eventType string -- The event type to count
	@param withinSeconds number? -- Time window
	@return number -- Count of matching events

	@example
	```lua
	local hitCount = memory:countRecentEvents("hit_received", 5)
	if hitCount >= 3 then
		-- Taking heavy fire, find cover
	end
	```
]=]
function Memory:countRecentEvents(eventType: string, withinSeconds: number?): number
	return #self:getRecentEvents(eventType, withinSeconds)
end

-- ============================================================================
-- EPISODIC MEMORY (Event History)
-- ============================================================================

--[=[
	Consolidates a working memory event to episodic memory.

	@param event MemoryEvent -- The event to consolidate
	@private
]=]
function Memory:_consolidateToEpisodic(event: MemoryEvent)
	table.insert(self._episodicMemory, event)

	-- Enforce episodic memory limit (remove oldest, least important)
	if #self._episodicMemory > self.maxEpisodicMemories then
		self:_pruneEpisodicMemory()
	end
end

--[=[
	Prunes episodic memory to stay within limits.

	Removes memories based on age and importance.
	@private
]=]
function Memory:_pruneEpisodicMemory()
	-- Sort by importance * recency
	local now = os.clock()
	table.sort(self._episodicMemory, function(a, b)
		local scoreA = a.importance * (1 - math.min(1, (now - a.timestamp) / 3600))
		local scoreB = b.importance * (1 - math.min(1, (now - b.timestamp) / 3600))
		return scoreA > scoreB
	end)

	-- Keep only the top N
	while #self._episodicMemory > self.maxEpisodicMemories do
		table.remove(self._episodicMemory)
	end
end

--[=[
	Queries episodic memory for events matching criteria.

	@param filter { type: string?, minImportance: number?, withinSeconds: number? } -- Filter criteria
	@return { MemoryEvent } -- Matching events

	@example
	```lua
	local importantCombatEvents = memory:queryEpisodic({
		type = "combat",
		minImportance = 0.7,
		withinSeconds = 300, -- Last 5 minutes
	})
	```
]=]
function Memory:queryEpisodic(
	filter: { type: string?, minImportance: number?, withinSeconds: number? }
): { MemoryEvent }
	local results = {}
	local now = os.clock()
	local cutoff = if filter.withinSeconds then now - filter.withinSeconds else 0

	for _, event in ipairs(self._episodicMemory) do
		local matches = true

		if filter.type and event.type ~= filter.type then
			matches = false
		end

		if filter.minImportance and event.importance < filter.minImportance then
			matches = false
		end

		if event.timestamp < cutoff then
			matches = false
		end

		if matches then
			table.insert(results, event)
		end
	end

	return results
end

--[=[
	Gets the time since the last event of a given type.

	@param eventType string -- The event type
	@return number? -- Seconds since last event, or nil if never occurred

	@example
	```lua
	local timeSinceAttack = memory:getTimeSinceEvent("player_attack")
	if timeSinceAttack and timeSinceAttack > 30 then
		-- Haven't been attacked in 30 seconds, relax vigilance
	end
	```
]=]
function Memory:getTimeSinceEvent(eventType: string): number?
	local now = os.clock()

	-- Check working memory first
	for i = #self._workingMemory, 1, -1 do
		if self._workingMemory[i].type == eventType then
			return now - self._workingMemory[i].timestamp
		end
	end

	-- Check episodic memory
	for i = #self._episodicMemory, 1, -1 do
		if self._episodicMemory[i].type == eventType then
			return now - self._episodicMemory[i].timestamp
		end
	end

	return nil
end

-- ============================================================================
-- SEMANTIC MEMORY (Long-term Facts)
-- ============================================================================

--[=[
	Records or updates a fact in semantic memory.

	Facts are long-term learned information that persists and can be
	reinforced over time.

	@param key string -- Unique identifier for the fact
	@param value any -- The fact value
	@param confidence number? -- Confidence level (0-1, default: 0.5)

	@example
	```lua
	-- Record a learned fact about player behavior
	memory:recordFact("player_attack_pattern", "flanking", 0.7)

	-- Record NPC knowledge
	memory:recordFact("patrol_route_clear", true, 0.9)
	```
]=]
function Memory:recordFact(key: string, value: any, confidence: number?)
	local existing = self._semanticMemory[key]
	local now = os.clock()

	if existing then
		-- Reinforce existing fact
		existing.value = value
		existing.confidence = math.min(1, (existing.confidence + (confidence or 0.5)) / 2 + 0.1)
		existing.lastUpdated = now
		existing.updateCount = existing.updateCount + 1
	else
		-- Create new fact
		self._semanticMemory[key] = {
			key = key,
			value = value,
			confidence = confidence or 0.5,
			lastUpdated = now,
			updateCount = 1,
		}
	end
end

--[=[
	Gets a fact from semantic memory.

	@param key string -- The fact key
	@return any? -- The fact value, or nil if not found
	@return number? -- The confidence level, or nil if not found

	@example
	```lua
	local pattern, confidence = memory:getFact("player_attack_pattern")
	if pattern and confidence > 0.6 then
		-- Use the learned pattern for prediction
	end
	```
]=]
function Memory:getFact(key: string): (any?, number?)
	local fact = self._semanticMemory[key]
	if fact then
		return fact.value, fact.confidence
	end
	return nil, nil
end

--[=[
	Checks if a fact exists with sufficient confidence.

	@param key string -- The fact key
	@param minConfidence number? -- Minimum confidence required (default: 0.5)
	@return boolean -- True if fact exists with sufficient confidence

	@example
	```lua
	if memory:hasFact("enemy_weakness_fire", 0.7) then
		-- Confident that enemy is weak to fire
		selectFireAttacks()
	end
	```
]=]
function Memory:hasFact(key: string, minConfidence: number?): boolean
	local fact = self._semanticMemory[key]
	if fact then
		return fact.confidence >= (minConfidence or 0.5)
	end
	return false
end

--[=[
	Gets all facts matching a prefix.

	@param prefix string -- Key prefix to match
	@return { [string]: MemoryFact } -- Matching facts

	@example
	```lua
	local playerFacts = memory:getFactsByPrefix("player_")
	for key, fact in pairs(playerFacts) do
		print(key, fact.value, fact.confidence)
	end
	```
]=]
function Memory:getFactsByPrefix(prefix: string): { [string]: MemoryFact }
	local results = {}
	for key, fact in pairs(self._semanticMemory) do
		if string.sub(key, 1, #prefix) == prefix then
			results[key] = fact
		end
	end
	return results
end

--[=[
	Removes a fact from semantic memory.

	@param key string -- The fact key to remove
	@return boolean -- True if fact was removed
]=]
function Memory:forgetFact(key: string): boolean
	if self._semanticMemory[key] then
		self._semanticMemory[key] = nil
		return true
	end
	return false
end

--[=[
	Degrades confidence in a fact (for incorrect predictions).

	@param key string -- The fact key
	@param amount number? -- Amount to degrade (default: 0.2)

	@example
	```lua
	-- Our prediction was wrong
	memory:degradeFact("player_attack_pattern", 0.3)
	```
]=]
function Memory:degradeFact(key: string, amount: number?)
	local fact = self._semanticMemory[key]
	if fact then
		fact.confidence = math.max(0, fact.confidence - (amount or 0.2))
		-- Remove facts with zero confidence
		if fact.confidence <= 0 then
			self._semanticMemory[key] = nil
		end
	end
end

-- ============================================================================
-- PATTERN DETECTION
-- ============================================================================

--[=[
	Detects patterns from event history.

	@param eventType string -- The event type
	@param data { [string]: any }? -- Event data
	@private
]=]
function Memory:_detectPatterns(eventType: string, data: { [string]: any }?)
	-- Simple pattern: repeated event type
	local count = self._eventCounts[eventType] or 0

	if count >= self.patternThreshold then
		local patternKey = "repeat_" .. eventType
		local existing = self._patterns[patternKey]

		if existing then
			existing.occurrences = count
			existing.confidence = math.min(1, count / 10)
			existing.lastOccurrence = os.clock()
		else
			self._patterns[patternKey] = {
				pattern = "repeated_event",
				occurrences = count,
				confidence = count / 10,
				lastOccurrence = os.clock(),
				data = { eventType = eventType },
			}
		end
	end

	-- Check for data-based patterns (e.g., repeated direction)
	if data then
		for key, value in pairs(data) do
			if type(value) == "string" or type(value) == "number" then
				local patternKey = `{eventType}_{key}_{tostring(value)}`
				local current = self._patterns[patternKey]

				if current then
					current.occurrences = current.occurrences + 1
					current.confidence = math.min(1, current.occurrences / self.patternThreshold)
					current.lastOccurrence = os.clock()
				else
					self._patterns[patternKey] = {
						pattern = `{eventType}_{key}`,
						occurrences = 1,
						confidence = 1 / self.patternThreshold,
						lastOccurrence = os.clock(),
						data = { key = key, value = value },
					}
				end
			end
		end
	end
end

--[=[
	Gets detected patterns of a given type.

	@param patternType string? -- Filter by pattern type (optional)
	@param minConfidence number? -- Minimum confidence (default: 0.5)
	@return { PatternMatch } -- Matching patterns

	@example
	```lua
	local attackPatterns = memory:getPatterns("player_attack", 0.6)
	for _, pattern in ipairs(attackPatterns) do
		print("Pattern:", pattern.pattern, "Confidence:", pattern.confidence)
	end
	```
]=]
function Memory:getPatterns(patternType: string?, minConfidence: number?): { PatternMatch }
	local results = {}
	local threshold = minConfidence or 0.5

	for _, pattern in pairs(self._patterns) do
		local matches = pattern.confidence >= threshold

		if patternType and not string.find(pattern.pattern, patternType, 1, true) then
			matches = false
		end

		if matches then
			table.insert(results, pattern)
		end
	end

	-- Sort by confidence
	table.sort(results, function(a, b)
		return a.confidence > b.confidence
	end)

	return results
end

--[=[
	Gets the most confident pattern for a prediction.

	@param prefix string -- Pattern prefix to match
	@return PatternMatch? -- The most confident pattern, or nil

	@example
	```lua
	local bestPattern = memory:getBestPattern("player_attack_direction")
	if bestPattern and bestPattern.confidence > 0.7 then
		local predictedDirection = bestPattern.data.value
		-- Prepare defense for predicted direction
	end
	```
]=]
function Memory:getBestPattern(prefix: string): PatternMatch?
	local best: PatternMatch? = nil
	local bestConfidence = 0

	for key, pattern in pairs(self._patterns) do
		if string.find(key, prefix, 1, true) and pattern.confidence > bestConfidence then
			best = pattern
			bestConfidence = pattern.confidence
		end
	end

	return best
end

-- ============================================================================
-- MEMORY MANAGEMENT
-- ============================================================================

--[=[
	Updates memory state (decay, cleanup, consolidation).

	Should be called periodically (e.g., once per second).

	@param deltaTime number? -- Time since last update (default: calculates automatically)

	@example
	```lua
	-- In game update loop
	memory:update(deltaTime)
	```
]=]
function Memory:update(deltaTime: number?)
	local now = os.clock()
	local dt = deltaTime or (now - self._lastCleanup)
	self._lastCleanup = now

	-- Clean expired working memory
	local workingCutoff = now - self.workingMemoryDuration
	local i = 1
	while i <= #self._workingMemory do
		local event = self._workingMemory[i]
		if event.timestamp < workingCutoff then
			-- Consolidate important events before removing
			if event.importance >= 0.5 then
				self:_consolidateToEpisodic(event)
			end
			table.remove(self._workingMemory, i)
		else
			i = i + 1
		end
	end

	-- Decay episodic memories
	local minutesPassed = dt / 60
	local decayAmount = self.episodicDecayRate * minutesPassed

	i = 1
	while i <= #self._episodicMemory do
		local event = self._episodicMemory[i]
		event.importance = event.importance - (decayAmount * event.decayRate)
		if event.importance <= 0 then
			table.remove(self._episodicMemory, i)
		else
			i = i + 1
		end
	end

	-- Decay facts if enabled
	if self.factDecayEnabled then
		local hoursPassed = dt / 3600
		local factDecay = self.factDecayRate * hoursPassed

		for key, fact in pairs(self._semanticMemory) do
			-- Only decay facts that haven't been updated recently
			local timeSinceUpdate = now - fact.lastUpdated
			if timeSinceUpdate > 60 then -- More than 1 minute old
				fact.confidence = fact.confidence - factDecay
				if fact.confidence <= 0 then
					self._semanticMemory[key] = nil
				end
			end
		end
	end

	-- Decay patterns
	for key, pattern in pairs(self._patterns) do
		local timeSince = now - pattern.lastOccurrence
		if timeSince > 300 then -- 5 minutes without occurrence
			pattern.confidence = pattern.confidence - (0.1 * minutesPassed)
			if pattern.confidence <= 0 then
				self._patterns[key] = nil
			end
		end
	end
end

--[=[
	Clears all working memory.

	@example
	```lua
	-- Clear tactical memory (e.g., when entering safe zone)
	memory:clearWorkingMemory()
	```
]=]
function Memory:clearWorkingMemory()
	table.clear(self._workingMemory)
end

--[=[
	Clears all memory (working, episodic, and semantic).

	@example
	```lua
	-- Full memory reset
	memory:clearAll()
	```
]=]
function Memory:clearAll()
	table.clear(self._workingMemory)
	table.clear(self._episodicMemory)
	table.clear(self._semanticMemory)
	table.clear(self._patterns)
	table.clear(self._eventCounts)
end

-- ============================================================================
-- SERIALIZATION
-- ============================================================================

--[=[
	Serializes memory state for persistence.

	Only serializes semantic memory and patterns (long-term knowledge).
	Working and episodic memory are considered temporary.

	@return { [string]: any } -- Serialized memory data

	@example
	```lua
	local data = memory:serialize()
	DataStore:SetAsync(npcId, HttpService:JSONEncode(data))
	```
]=]
function Memory:serialize(): { [string]: any }
	return {
		_version = SERIALIZE_VERSION,
		_timestamp = os.time(),
		semanticMemory = self._semanticMemory,
		patterns = self._patterns,
		eventCounts = self._eventCounts,
	}
end

--[=[
	Deserializes memory state from saved data.

	@param data { [string]: any } -- Serialized memory data
	@return Memory -- The restored memory system

	@example
	```lua
	local json = DataStore:GetAsync(npcId)
	local data = HttpService:JSONDecode(json)
	local memory = Memory.deserialize(data)
	```
]=]
function Memory.deserialize(data: { [string]: any }): Memory
	local memory = Memory.new()

	if data._version and data._version <= SERIALIZE_VERSION then
		if data.semanticMemory then
			memory._semanticMemory = data.semanticMemory
		end
		if data.patterns then
			memory._patterns = data.patterns
		end
		if data.eventCounts then
			memory._eventCounts = data.eventCounts
		end
	end

	return memory
end

--[=[
	Converts memory to JSON string.

	@return string? -- JSON string, or nil on error
	@return string? -- Error message, or nil on success
]=]
function Memory:toJSON(): (string?, string?)
	local success, result = pcall(function()
		return HttpService:JSONEncode(self:serialize())
	end)

	if success then
		return result, nil
	else
		return nil, tostring(result)
	end
end

--[=[
	Creates memory from JSON string.

	@param json string -- JSON string
	@return Memory? -- Restored memory, or nil on error
	@return string? -- Error message, or nil on success
]=]
function Memory.fromJSON(json: string): (Memory?, string?)
	local success, decoded = pcall(function()
		return HttpService:JSONDecode(json)
	end)

	if not success then
		return nil, `Failed to decode JSON: {tostring(decoded)}`
	end

	return Memory.deserialize(decoded), nil
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	String representation for debugging.

	@return string -- Formatted string describing the memory
]=]
function Memory:__tostring(): string
	return `Memory\{working={#self._workingMemory}, episodic={#self._episodicMemory}, facts={self:_countFacts()}}`
end

--[=[
	Counts semantic facts.
	@private
]=]
function Memory:_countFacts(): number
	local count = 0
	for _ in pairs(self._semanticMemory) do
		count = count + 1
	end
	return count
end

--[=[
	Creates a debug summary of the memory state.

	@return string -- Multi-line debug summary
]=]
function Memory:debugSummary(): string
	local lines = {
		"Memory State",
		`  Working Memory: {#self._workingMemory} events`,
		`  Episodic Memory: {#self._episodicMemory} events`,
		`  Semantic Facts: {self:_countFacts()}`,
	}

	-- Show working memory summary
	if #self._workingMemory > 0 then
		table.insert(lines, "  Recent Events:")
		for i = math.max(1, #self._workingMemory - 4), #self._workingMemory do
			local event = self._workingMemory[i]
			table.insert(lines, `    - {event.type} ({string.format("%.1f", os.clock() - event.timestamp)}s ago)`)
		end
	end

	-- Show patterns
	local patternCount = 0
	for _ in pairs(self._patterns) do
		patternCount = patternCount + 1
	end
	if patternCount > 0 then
		table.insert(lines, `  Detected Patterns: {patternCount}`)
		for key, pattern in pairs(self._patterns) do
			if pattern.confidence >= 0.5 then
				table.insert(lines, string.format("    - %s (%.0f%%)", key, pattern.confidence * 100))
			end
		end
	end

	return table.concat(lines, "\n")
end

-- ============================================================================
-- MEMORY MANAGEMENT
-- ============================================================================

--[=[
	Destroys the memory system and releases all resources.

	IMPORTANT: Call this when the NPC is despawned to prevent memory leaks.
	This clears all working, episodic, and semantic memory.
	After calling destroy(), the memory system should not be used.

	@example
	```lua
	-- When NPC is despawned
	memory:destroy()
	```
]=]
function Memory:destroy()
	-- Clear all memory stores
	table.clear(self._workingMemory)
	table.clear(self._episodicMemory)
	table.clear(self._semanticMemory)
	table.clear(self._patterns)

	-- Clear any indexes
	if self._episodicIndex then
		table.clear(self._episodicIndex)
	end
end

--[=[
	Gets memory statistics for monitoring.

	@return { workingMemory: number, episodicMemory: number, semanticFacts: number, patterns: number }
]=]
function Memory:getMemoryStats(): {
	workingMemory: number,
	episodicMemory: number,
	semanticFacts: number,
	patterns: number,
}
	local patternCount = 0
	for _ in pairs(self._patterns) do
		patternCount += 1
	end

	return {
		workingMemory = #self._workingMemory,
		episodicMemory = #self._episodicMemory,
		semanticFacts = self:_countFacts(),
		patterns = patternCount,
	}
end

-- ============================================================================
-- TYPE EXPORT
-- ============================================================================

--- Export type for external use.
export type Memory = typeof(Memory.new())

return Memory
