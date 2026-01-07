--!strict
--[[
	Perception.lua
	Sensory awareness system for realistic AI perception.

	Perception provides a comprehensive sensory system for NPCs including
	vision, hearing, and awareness tracking. This enables realistic detection
	behaviors like guards that can be snuck past, enemies that investigate
	sounds, and NPCs with varying levels of alertness.

	┌─────────────────────────────────────────────────────────────────────────┐
	│                       PERCEPTION ARCHITECTURE                           │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│                         ┌─────────────┐                                 │
	│                         │   STIMULI   │                                 │
	│                         │  (Inputs)   │                                 │
	│                         └──────┬──────┘                                 │
	│                                │                                        │
	│              ┌─────────────────┼─────────────────┐                      │
	│              ▼                 ▼                 ▼                      │
	│       ┌──────────┐      ┌──────────┐      ┌──────────┐                 │
	│       │  VISION  │      │ HEARING  │      │  OTHER   │                 │
	│       │  Sense   │      │  Sense   │      │  Senses  │                 │
	│       └────┬─────┘      └────┬─────┘      └────┬─────┘                 │
	│            │                 │                 │                        │
	│            └─────────────────┼─────────────────┘                        │
	│                              ▼                                          │
	│                    ┌─────────────────┐                                  │
	│                    │   AWARENESS     │                                  │
	│                    │    TRACKER      │                                  │
	│                    │  ┌───────────┐  │                                  │
	│                    │  │ Suspicion │  │                                  │
	│                    │  │   Level   │  │                                  │
	│                    │  └───────────┘  │                                  │
	│                    └────────┬────────┘                                  │
	│                             │                                           │
	│              ┌──────────────┼──────────────┐                            │
	│              ▼              ▼              ▼                            │
	│         ┌────────┐    ┌────────┐    ┌────────┐                         │
	│         │UNAWARE │    │CURIOUS │    │ ALERT  │                         │
	│         │  0-30% │    │ 30-70% │    │70-100% │                         │
	│         └────────┘    └────────┘    └────────┘                         │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class Perception
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Features

	- **Vision System**: Configurable FOV, range, and obstruction checks
	- **Hearing System**: Sound detection with falloff and type filtering
	- **Awareness Tracking**: Suspicion levels that build up over time
	- **Multiple Targets**: Track awareness of multiple entities
	- **Stimuli Processing**: Queue and process sensory events
	- **State Transitions**: Unaware -> Suspicious -> Alert -> Combat

	## Basic Usage

	```lua
	local Perception = require(path.to.Perception)

	-- Create perception for a guard NPC
	local perception = Perception.new({
		visionRange = 50,
		visionAngle = 120,
		hearingRange = 30,
		awarenessDecayRate = 5, -- Per second when no stimuli
	})

	-- Check if target is visible
	local canSee = perception:canSee(guardPosition, guardForward, targetPosition)

	-- Process a sound stimulus
	perception:hearSound("footstep", soundPosition, 0.5)

	-- Get current awareness state
	local state = perception:getAwarenessState("player_1")
	if state == "alert" then
		enterCombat()
	end
	```
]]

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

--[=[
	@type AwarenessState "unaware" | "curious" | "suspicious" | "alert" | "combat"
	@within Perception
	The current awareness state of the perceiver toward a target.
]=]
export type AwarenessState = "unaware" | "curious" | "suspicious" | "alert" | "combat"

--[=[
	@type StimulusType "visual" | "audio" | "damage" | "proximity" | "communication"
	@within Perception
	Types of sensory stimuli that can be processed.
]=]
export type StimulusType = "visual" | "audio" | "damage" | "proximity" | "communication"

--[=[
	@interface Stimulus
	@within Perception
	.type StimulusType -- Type of stimulus
	.sourceId string -- ID of the source entity
	.position Vector3? -- World position of stimulus
	.intensity number -- Intensity/strength (0-1)
	.timestamp number -- When the stimulus occurred
	.data { [string]: any }? -- Additional data
]=]
export type Stimulus = {
	type: StimulusType,
	sourceId: string,
	position: Vector3?,
	intensity: number,
	timestamp: number,
	data: { [string]: any }?,
}

--[=[
	@interface AwarenessEntry
	@within Perception
	.targetId string -- ID of the target being tracked
	.level number -- Current awareness level (0-100)
	.state AwarenessState -- Current awareness state
	.lastKnownPosition Vector3? -- Last known position
	.lastSeen number -- Timestamp of last detection
	.lastHeard number -- Timestamp of last sound
	.timesSpotted number -- Number of visual detections
	.timesHeard number -- Number of audio detections
]=]
export type AwarenessEntry = {
	targetId: string,
	level: number,
	state: AwarenessState,
	lastKnownPosition: Vector3?,
	lastSeen: number,
	lastHeard: number,
	timesSpotted: number,
	timesHeard: number,
}

--[=[
	@interface VisionConfig
	@within Perception
	.range number? -- Maximum vision range (default: 50)
	.angle number? -- Field of view in degrees (default: 120)
	.peripheralRange number? -- Range for peripheral vision (default: range * 0.6)
	.peripheralAngle number? -- Peripheral FOV bonus degrees (default: 40)
	.peripheralMultiplier number? -- Awareness multiplier for peripheral (default: 0.5)
	.obstructionCheck ((from: Vector3, to: Vector3) -> boolean)? -- Custom obstruction check
]=]
export type VisionConfig = {
	range: number?,
	angle: number?,
	peripheralRange: number?,
	peripheralAngle: number?,
	peripheralMultiplier: number?,
	obstructionCheck: ((from: Vector3, to: Vector3) -> boolean)?,
}

--[=[
	@interface HearingConfig
	@within Perception
	.range number? -- Maximum hearing range (default: 30)
	.sensitivity number? -- Hearing sensitivity multiplier (default: 1.0)
	.soundTypes { [string]: number }? -- Sound type -> awareness multiplier
]=]
export type HearingConfig = {
	range: number?,
	sensitivity: number?,
	soundTypes: { [string]: number }?,
}

--[=[
	@interface AwarenessConfig
	@within Perception
	.decayRate number? -- Awareness decay per second (default: 5)
	.buildupMultiplier number? -- Awareness buildup multiplier (default: 1.0)
	.thresholds { curious: number?, suspicious: number?, alert: number?, combat: number? }? -- State thresholds
	.instantAlertOnDamage boolean? -- Immediately alert when damaged (default: true)
	.maxAwareness number? -- Maximum awareness level (default: 100)
]=]
export type AwarenessConfig = {
	decayRate: number?,
	buildupMultiplier: number?,
	thresholds: {
		curious: number?,
		suspicious: number?,
		alert: number?,
		combat: number?,
	}?,
	instantAlertOnDamage: boolean?,
	maxAwareness: number?,
}

--[=[
	@interface PerceptionConfig
	@within Perception
	.vision VisionConfig? -- Vision settings
	.hearing HearingConfig? -- Hearing settings
	.awareness AwarenessConfig? -- Awareness settings
	.enabled boolean? -- Whether perception is active (default: true)
]=]
export type PerceptionConfig = {
	vision: VisionConfig?,
	hearing: HearingConfig?,
	awareness: AwarenessConfig?,
	enabled: boolean?,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

--- Default vision configuration.
local DEFAULT_VISION: VisionConfig = table.freeze({
	range = 50,
	angle = 120,
	peripheralRange = 30,
	peripheralAngle = 40,
	peripheralMultiplier = 0.5,
	obstructionCheck = nil,
})

--- Default hearing configuration.
local DEFAULT_HEARING: HearingConfig = table.freeze({
	range = 30,
	sensitivity = 1.0,
	soundTypes = {
		footstep = 0.3,
		gunshot = 1.0,
		explosion = 1.0,
		voice = 0.5,
		door = 0.4,
		glass_break = 0.8,
	},
})

--- Default awareness configuration.
local DEFAULT_AWARENESS: AwarenessConfig = table.freeze({
	decayRate = 5,
	buildupMultiplier = 1.0,
	thresholds = {
		curious = 20,
		suspicious = 40,
		alert = 70,
		combat = 90,
	},
	instantAlertOnDamage = true,
	maxAwareness = 100,
})

--- Log prefix for messages.
local LOG_PREFIX = "[Goal.Perception]"

-- ============================================================================
-- CLASS DEFINITION
-- ============================================================================

--[=[
	@class Perception
	@tag UtilityAI

	A sensory awareness system for realistic NPC perception.
	Handles vision, hearing, and awareness tracking.
]=]
local Perception = {}
Perception.__index = Perception

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

--[=[
	Creates a new Perception system.

	@param config PerceptionConfig? -- Optional configuration
	@return Perception -- The newly created perception system

	@example Basic Perception
	```lua
	local perception = Perception.new()
	```

	@example Configured Perception
	```lua
	local perception = Perception.new({
		vision = {
			range = 60,
			angle = 90,
		},
		hearing = {
			range = 40,
			sensitivity = 1.2,
		},
		awareness = {
			decayRate = 3,
			thresholds = {
				alert = 60,
				combat = 80,
			},
		},
	})
	```
]=]
function Perception.new(config: PerceptionConfig?): Perception
	local self = setmetatable({}, Perception)

	local cfg = config or {}

	-- Vision configuration
	local visionCfg = cfg.vision or {}
	self.visionRange = visionCfg.range or DEFAULT_VISION.range
	self.visionAngle = visionCfg.angle or DEFAULT_VISION.angle
	self.peripheralRange = visionCfg.peripheralRange or (self.visionRange * 0.6)
	self.peripheralAngle = visionCfg.peripheralAngle or DEFAULT_VISION.peripheralAngle
	self.peripheralMultiplier = visionCfg.peripheralMultiplier or DEFAULT_VISION.peripheralMultiplier
	self._obstructionCheck = visionCfg.obstructionCheck

	-- Hearing configuration
	local hearingCfg = cfg.hearing or {}
	self.hearingRange = hearingCfg.range or DEFAULT_HEARING.range
	self.hearingSensitivity = hearingCfg.sensitivity or DEFAULT_HEARING.sensitivity
	self.soundTypes = if hearingCfg.soundTypes
		then table.clone(hearingCfg.soundTypes)
		else table.clone(DEFAULT_HEARING.soundTypes :: { [string]: number })

	-- Awareness configuration
	local awarenessCfg = cfg.awareness or {}
	self.awarenessDecayRate = awarenessCfg.decayRate or DEFAULT_AWARENESS.decayRate
	self.awarenessBuildupMultiplier = awarenessCfg.buildupMultiplier or DEFAULT_AWARENESS.buildupMultiplier
	self.instantAlertOnDamage = if awarenessCfg.instantAlertOnDamage ~= nil
		then awarenessCfg.instantAlertOnDamage
		else DEFAULT_AWARENESS.instantAlertOnDamage
	self.maxAwareness = awarenessCfg.maxAwareness or DEFAULT_AWARENESS.maxAwareness

	-- Awareness thresholds
	local defaultThresholds = DEFAULT_AWARENESS.thresholds :: {
		curious: number?,
		suspicious: number?,
		alert: number?,
		combat: number?,
	}
	local thresholdsCfg = awarenessCfg.thresholds or {}
	self.thresholds = {
		curious = thresholdsCfg.curious or defaultThresholds.curious or 20,
		suspicious = thresholdsCfg.suspicious or defaultThresholds.suspicious or 40,
		alert = thresholdsCfg.alert or defaultThresholds.alert or 70,
		combat = thresholdsCfg.combat or defaultThresholds.combat or 90,
	}

	-- State
	self.enabled = if cfg.enabled ~= nil then cfg.enabled else true
	self._awarenessMap = {} :: { [string]: AwarenessEntry }
	self._stimulusQueue = {} :: { Stimulus }
	self._lastUpdate = os.clock()

	return self
end

-- ============================================================================
-- VISION SYSTEM
-- ============================================================================

--[=[
	Checks if a target position is visible from the perceiver's position.

	@param perceiverPosition Vector3 -- The perceiver's world position
	@param perceiverForward Vector3 -- The perceiver's forward direction (normalized)
	@param targetPosition Vector3 -- The target's world position
	@param checkObstruction boolean? -- Whether to check for obstructions (default: true)
	@return boolean -- Whether the target is visible
	@return number -- Detection quality (0-1, higher = better visibility)
	@return string -- Detection zone ("center" | "peripheral" | "none")

	@example
	```lua
	local canSee, quality, zone = perception:canSee(
		guard.Position,
		guard.CFrame.LookVector,
		player.Position
	)

	if canSee then
		print("Target visible in", zone, "vision with quality", quality)
	end
	```
]=]
function Perception:canSee(
	perceiverPosition: Vector3,
	perceiverForward: Vector3,
	targetPosition: Vector3,
	checkObstruction: boolean?
): (boolean, number, string)
	if not self.enabled then
		return false, 0, "none"
	end

	-- Calculate direction and distance to target
	local toTarget = targetPosition - perceiverPosition
	local distance = toTarget.Magnitude

	-- Check range
	if distance > self.visionRange then
		return false, 0, "none"
	end

	-- Normalize direction
	local direction = toTarget.Unit

	-- Calculate angle between forward and target direction
	local dotProduct = perceiverForward:Dot(direction)
	local angleDegrees = math.deg(math.acos(math.clamp(dotProduct, -1, 1)))

	-- Check if in central vision cone
	local halfAngle = self.visionAngle / 2
	local halfPeripheralAngle = (self.visionAngle + self.peripheralAngle) / 2

	local zone: string
	local quality: number

	if angleDegrees <= halfAngle then
		-- Central vision
		zone = "center"
		-- Quality based on distance (closer = better)
		local distanceFactor = 1 - (distance / self.visionRange)
		-- Quality based on angle (center = better)
		local angleFactor = 1 - (angleDegrees / halfAngle)
		quality = distanceFactor * 0.6 + angleFactor * 0.4
	elseif angleDegrees <= halfPeripheralAngle and distance <= self.peripheralRange then
		-- Peripheral vision
		zone = "peripheral"
		local distanceFactor = 1 - (distance / self.peripheralRange)
		quality = distanceFactor * self.peripheralMultiplier
	else
		-- Outside vision cone
		return false, 0, "none"
	end

	-- Check obstruction if enabled and callback provided
	if (checkObstruction ~= false) and self._obstructionCheck then
		local isObstructed = self._obstructionCheck(perceiverPosition, targetPosition)
		if isObstructed then
			return false, 0, "none"
		end
	end

	return true, quality, zone
end

--[=[
	Sets a custom obstruction check function.

	@param checkFn ((from: Vector3, to: Vector3) -> boolean)? -- Function that returns true if obstructed

	@example
	```lua
	perception:setObstructionCheck(function(from, to)
		local result = workspace:Raycast(from, to - from)
		return result ~= nil
	end)
	```
]=]
function Perception:setObstructionCheck(checkFn: ((from: Vector3, to: Vector3) -> boolean)?)
	self._obstructionCheck = checkFn
end

--[=[
	Gets the vision range.

	@return number -- Current vision range
]=]
function Perception:getVisionRange(): number
	return self.visionRange
end

--[=[
	Sets the vision range.

	@param range number -- New vision range
]=]
function Perception:setVisionRange(range: number)
	assert(type(range) == "number" and range >= 0, `{LOG_PREFIX} range must be a non-negative number`)
	self.visionRange = range
end

--[=[
	Gets the vision angle (field of view).

	@return number -- Current FOV in degrees
]=]
function Perception:getVisionAngle(): number
	return self.visionAngle
end

--[=[
	Sets the vision angle (field of view).

	@param angle number -- New FOV in degrees
]=]
function Perception:setVisionAngle(angle: number)
	assert(type(angle) == "number" and angle > 0 and angle <= 360, `{LOG_PREFIX} angle must be between 0 and 360`)
	self.visionAngle = angle
end

-- ============================================================================
-- HEARING SYSTEM
-- ============================================================================

--[=[
	Checks if a sound at a position can be heard.

	@param perceiverPosition Vector3 -- The perceiver's world position
	@param soundPosition Vector3 -- Where the sound originated
	@param soundVolume number? -- Sound volume (0-1, default: 1.0)
	@return boolean -- Whether the sound can be heard
	@return number -- Perceived loudness (0-1)

	@example
	```lua
	local canHear, loudness = perception:canHear(
		guard.Position,
		soundPosition,
		0.8
	)

	if canHear and loudness > 0.5 then
		print("Heard a loud sound!")
	end
	```
]=]
function Perception:canHear(perceiverPosition: Vector3, soundPosition: Vector3, soundVolume: number?): (boolean, number)
	if not self.enabled then
		return false, 0
	end

	local volume = soundVolume or 1.0
	local distance = (soundPosition - perceiverPosition).Magnitude

	-- Check range
	if distance > self.hearingRange then
		return false, 0
	end

	-- Calculate perceived loudness with distance falloff
	local distanceFactor = 1 - (distance / self.hearingRange)
	local loudness = volume * distanceFactor * self.hearingSensitivity

	-- Clamp to valid range
	loudness = math.clamp(loudness, 0, 1)

	return loudness > 0.01, loudness
end

--[=[
	Processes a sound event and updates awareness.

	@param soundType string -- Type of sound (footstep, gunshot, etc.)
	@param soundPosition Vector3 -- Where the sound originated
	@param sourceId string -- ID of the entity that made the sound
	@param perceiverPosition Vector3 -- The perceiver's position
	@param volume number? -- Sound volume (0-1, default: 1.0)
	@return boolean -- Whether the sound was heard
	@return number -- Awareness increase amount

	@example
	```lua
	local heard, awarenessGain = perception:hearSound(
		"gunshot",
		gunPosition,
		"player_1",
		guard.Position,
		1.0
	)
	```
]=]
function Perception:hearSound(
	soundType: string,
	soundPosition: Vector3,
	sourceId: string,
	perceiverPosition: Vector3,
	volume: number?
): (boolean, number)
	local canHear, loudness = self:canHear(perceiverPosition, soundPosition, volume)

	if not canHear then
		return false, 0
	end

	-- Get sound type multiplier
	local typeMultiplier = self.soundTypes[soundType] or 0.5

	-- Calculate awareness increase
	local awarenessIncrease = loudness * typeMultiplier * 30 * self.awarenessBuildupMultiplier

	-- Add stimulus
	self:addStimulus({
		type = "audio",
		sourceId = sourceId,
		position = soundPosition,
		intensity = loudness,
		timestamp = os.clock(),
		data = { soundType = soundType },
	})

	-- Update awareness
	self:_increaseAwareness(sourceId, awarenessIncrease, soundPosition, "audio")

	return true, awarenessIncrease
end

--[=[
	Sets the hearing range.

	@param range number -- New hearing range
]=]
function Perception:setHearingRange(range: number)
	assert(type(range) == "number" and range >= 0, `{LOG_PREFIX} range must be a non-negative number`)
	self.hearingRange = range
end

--[=[
	Sets the hearing sensitivity multiplier.

	@param sensitivity number -- New sensitivity (1.0 = normal)
]=]
function Perception:setHearingSensitivity(sensitivity: number)
	assert(type(sensitivity) == "number" and sensitivity >= 0, `{LOG_PREFIX} sensitivity must be non-negative`)
	self.hearingSensitivity = sensitivity
end

--[=[
	Registers a new sound type with an awareness multiplier.

	@param soundType string -- Sound type name
	@param multiplier number -- Awareness multiplier (0-1)

	@example
	```lua
	perception:registerSoundType("alarm", 1.0) -- Very alerting
	perception:registerSoundType("whisper", 0.2) -- Barely noticeable
	```
]=]
function Perception:registerSoundType(soundType: string, multiplier: number)
	assert(type(soundType) == "string", `{LOG_PREFIX} soundType must be a string`)
	assert(type(multiplier) == "number", `{LOG_PREFIX} multiplier must be a number`)
	self.soundTypes[soundType] = math.clamp(multiplier, 0, 1)
end

-- ============================================================================
-- AWARENESS SYSTEM
-- ============================================================================

--[=[
	Gets the awareness level for a specific target.

	@param targetId string -- The target's ID
	@return number -- Awareness level (0-100)

	@example
	```lua
	local awareness = perception:getAwarenessLevel("player_1")
	print("Awareness:", awareness, "%")
	```
]=]
function Perception:getAwarenessLevel(targetId: string): number
	local entry = self._awarenessMap[targetId]
	return if entry then entry.level else 0
end

--[=[
	Gets the awareness state for a specific target.

	@param targetId string -- The target's ID
	@return AwarenessState -- Current awareness state

	@example
	```lua
	local state = perception:getAwarenessState("player_1")
	if state == "alert" then
		searchForTarget()
	elseif state == "combat" then
		engageTarget()
	end
	```
]=]
function Perception:getAwarenessState(targetId: string): AwarenessState
	local entry = self._awarenessMap[targetId]
	return if entry then entry.state else "unaware"
end

--[=[
	Gets the full awareness entry for a target.

	@param targetId string -- The target's ID
	@return AwarenessEntry? -- Full awareness data, or nil if not tracked

	@example
	```lua
	local entry = perception:getAwarenessEntry("player_1")
	if entry then
		print("Last seen at:", entry.lastKnownPosition)
		print("Times spotted:", entry.timesSpotted)
	end
	```
]=]
function Perception:getAwarenessEntry(targetId: string): AwarenessEntry?
	return self._awarenessMap[targetId]
end

--[=[
	Gets the last known position of a target.

	@param targetId string -- The target's ID
	@return Vector3? -- Last known position, or nil

	@example
	```lua
	local lastPos = perception:getLastKnownPosition("player_1")
	if lastPos then
		investigatePosition(lastPos)
	end
	```
]=]
function Perception:getLastKnownPosition(targetId: string): Vector3?
	local entry = self._awarenessMap[targetId]
	return if entry then entry.lastKnownPosition else nil
end

--[=[
	Sets awareness level for a target directly.

	@param targetId string -- The target's ID
	@param level number -- New awareness level (0-100)

	@example
	```lua
	-- Force full alert
	perception:setAwarenessLevel("player_1", 100)
	```
]=]
function Perception:setAwarenessLevel(targetId: string, level: number)
	local clampedLevel = math.clamp(level, 0, self.maxAwareness)
	local entry = self:_getOrCreateEntry(targetId)
	entry.level = clampedLevel
	entry.state = self:_calculateState(clampedLevel)
end

--[=[
	Clears awareness of a specific target.

	@param targetId string -- The target's ID

	@example
	```lua
	-- Target escaped, reset awareness
	perception:clearAwareness("player_1")
	```
]=]
function Perception:clearAwareness(targetId: string)
	self._awarenessMap[targetId] = nil
end

--[=[
	Clears awareness of all targets.
]=]
function Perception:clearAllAwareness()
	table.clear(self._awarenessMap)
end

--[=[
	Gets all targets currently being tracked.

	@return { string } -- Array of target IDs

	@example
	```lua
	local targets = perception:getTrackedTargets()
	for _, targetId in ipairs(targets) do
		print("Tracking:", targetId, "State:", perception:getAwarenessState(targetId))
	end
	```
]=]
function Perception:getTrackedTargets(): { string }
	local targets = {}
	for targetId in pairs(self._awarenessMap) do
		table.insert(targets, targetId)
	end
	return targets
end

--[=[
	Gets targets in a specific awareness state.

	@param state AwarenessState -- The state to filter by
	@return { AwarenessEntry } -- Entries matching the state

	@example
	```lua
	local alertTargets = perception:getTargetsInState("alert")
	for _, entry in ipairs(alertTargets) do
		prioritizeTarget(entry.targetId)
	end
	```
]=]
function Perception:getTargetsInState(state: AwarenessState): { AwarenessEntry }
	local results = {}
	for _, entry in pairs(self._awarenessMap) do
		if entry.state == state then
			table.insert(results, entry)
		end
	end
	return results
end

--[=[
	Gets the most aware target (highest awareness level).

	@return AwarenessEntry? -- The entry with highest awareness, or nil

	@example
	```lua
	local primary = perception:getMostAwareTarget()
	if primary and primary.state == "combat" then
		engageTarget(primary.targetId)
	end
	```
]=]
function Perception:getMostAwareTarget(): AwarenessEntry?
	local best: AwarenessEntry? = nil
	local bestLevel = 0

	for _, entry in pairs(self._awarenessMap) do
		if entry.level > bestLevel then
			best = entry
			bestLevel = entry.level
		end
	end

	return best
end

--[=[
	Internal: Increases awareness for a target.
	@private
]=]
function Perception:_increaseAwareness(targetId: string, amount: number, position: Vector3?, source: string)
	local entry = self:_getOrCreateEntry(targetId)
	local now = os.clock()

	-- Increase awareness
	entry.level = math.min(self.maxAwareness, entry.level + amount)
	entry.state = self:_calculateState(entry.level)

	-- Update tracking data
	if position then
		entry.lastKnownPosition = position
	end

	if source == "visual" then
		entry.lastSeen = now
		entry.timesSpotted = entry.timesSpotted + 1
	elseif source == "audio" then
		entry.lastHeard = now
		entry.timesHeard = entry.timesHeard + 1
	end
end

--[=[
	Internal: Gets or creates an awareness entry.
	@private
]=]
function Perception:_getOrCreateEntry(targetId: string): AwarenessEntry
	local entry = self._awarenessMap[targetId]
	if not entry then
		entry = {
			targetId = targetId,
			level = 0,
			state = "unaware" :: AwarenessState,
			lastKnownPosition = nil,
			lastSeen = 0,
			lastHeard = 0,
			timesSpotted = 0,
			timesHeard = 0,
		}
		self._awarenessMap[targetId] = entry
	end
	return entry
end

--[=[
	Internal: Calculates awareness state from level.
	@private
]=]
function Perception:_calculateState(level: number): AwarenessState
	if level >= self.thresholds.combat then
		return "combat"
	elseif level >= self.thresholds.alert then
		return "alert"
	elseif level >= self.thresholds.suspicious then
		return "suspicious"
	elseif level >= self.thresholds.curious then
		return "curious"
	else
		return "unaware"
	end
end

-- ============================================================================
-- STIMULUS PROCESSING
-- ============================================================================

--[=[
	Adds a stimulus to the processing queue.

	@param stimulus Stimulus -- The stimulus to add

	@example
	```lua
	perception:addStimulus({
		type = "visual",
		sourceId = "player_1",
		position = playerPosition,
		intensity = 0.8,
		timestamp = os.clock(),
	})
	```
]=]
function Perception:addStimulus(stimulus: Stimulus)
	table.insert(self._stimulusQueue, stimulus)
end

--[=[
	Processes visual detection of a target.

	@param targetId string -- ID of the detected target
	@param perceiverPosition Vector3 -- Perceiver's position
	@param perceiverForward Vector3 -- Perceiver's forward direction
	@param targetPosition Vector3 -- Target's position
	@return boolean -- Whether the target was detected
	@return number -- Awareness increase amount

	@example
	```lua
	local detected, awarenessGain = perception:processVisualDetection(
		"player_1",
		guard.Position,
		guard.CFrame.LookVector,
		player.Position
	)
	```
]=]
function Perception:processVisualDetection(
	targetId: string,
	perceiverPosition: Vector3,
	perceiverForward: Vector3,
	targetPosition: Vector3
): (boolean, number)
	local canSee, quality, _zone = self:canSee(perceiverPosition, perceiverForward, targetPosition)

	if not canSee then
		return false, 0
	end

	-- Calculate awareness increase based on detection quality
	local awarenessIncrease = quality * 40 * self.awarenessBuildupMultiplier

	-- Add stimulus
	self:addStimulus({
		type = "visual",
		sourceId = targetId,
		position = targetPosition,
		intensity = quality,
		timestamp = os.clock(),
	})

	-- Update awareness
	self:_increaseAwareness(targetId, awarenessIncrease, targetPosition, "visual")

	return true, awarenessIncrease
end

--[=[
	Processes damage received from a source.

	@param sourceId string -- ID of the damage source
	@param damage number -- Amount of damage
	@param sourcePosition Vector3? -- Position of the attacker

	@example
	```lua
	perception:processDamage("player_1", 25, player.Position)
	```
]=]
function Perception:processDamage(sourceId: string, damage: number, sourcePosition: Vector3?)
	-- Add damage stimulus
	self:addStimulus({
		type = "damage",
		sourceId = sourceId,
		position = sourcePosition,
		intensity = math.clamp(damage / 100, 0, 1),
		timestamp = os.clock(),
		data = { damage = damage },
	})

	-- Instant alert on damage if configured
	if self.instantAlertOnDamage then
		self:setAwarenessLevel(sourceId, self.thresholds.combat)
		if sourcePosition then
			local entry = self._awarenessMap[sourceId]
			if entry then
				entry.lastKnownPosition = sourcePosition
			end
		end
	else
		-- Just increase awareness significantly
		self:_increaseAwareness(sourceId, 50, sourcePosition, "damage")
	end
end

--[=[
	Gets pending stimuli from the queue.

	@return { Stimulus } -- Array of pending stimuli
]=]
function Perception:getPendingStimuli(): { Stimulus }
	return self._stimulusQueue
end

--[=[
	Clears the stimulus queue.
]=]
function Perception:clearStimuli()
	table.clear(self._stimulusQueue)
end

-- ============================================================================
-- UPDATE LOOP
-- ============================================================================

--[=[
	Updates the perception system (decay awareness, process stimuli).

	Should be called each frame or at regular intervals.

	@param deltaTime number? -- Time since last update (auto-calculated if nil)

	@example
	```lua
	-- In game update loop
	RunService.Heartbeat:Connect(function(dt)
		perception:update(dt)
	end)
	```
]=]
function Perception:update(deltaTime: number?)
	if not self.enabled then
		return
	end

	local now = os.clock()
	local dt = deltaTime or (now - self._lastUpdate)
	self._lastUpdate = now

	-- Decay awareness for all tracked targets
	local toRemove = {}
	for targetId, entry in pairs(self._awarenessMap) do
		-- Decay awareness over time
		entry.level = math.max(0, entry.level - (self.awarenessDecayRate * dt))
		entry.state = self:_calculateState(entry.level)

		-- Remove entries with zero awareness
		if entry.level <= 0 then
			table.insert(toRemove, targetId)
		end
	end

	-- Clean up zero-awareness entries
	for _, targetId in ipairs(toRemove) do
		self._awarenessMap[targetId] = nil
	end

	-- Clear processed stimuli
	self:clearStimuli()
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

--[=[
	Enables or disables the perception system.

	@param enabled boolean -- Whether perception is active
]=]
function Perception:setEnabled(enabled: boolean)
	self.enabled = enabled
end

--[=[
	Checks if perception is enabled.

	@return boolean -- Whether perception is active
]=]
function Perception:isEnabled(): boolean
	return self.enabled
end

--[=[
	Sets the awareness decay rate.

	@param rate number -- Decay per second
]=]
function Perception:setAwarenessDecayRate(rate: number)
	assert(type(rate) == "number" and rate >= 0, `{LOG_PREFIX} rate must be non-negative`)
	self.awarenessDecayRate = rate
end

--[=[
	Sets an awareness threshold.

	@param state "curious" | "suspicious" | "alert" | "combat" -- The state
	@param threshold number -- New threshold value

	@example
	```lua
	perception:setThreshold("alert", 60) -- Alert at 60% instead of 70%
	```
]=]
function Perception:setThreshold(state: "curious" | "suspicious" | "alert" | "combat", threshold: number)
	assert(self.thresholds[state] ~= nil, `{LOG_PREFIX} Invalid state: {state}`)
	self.thresholds[state] = math.clamp(threshold, 0, self.maxAwareness)
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	String representation for debugging.

	@return string -- Formatted string
]=]
function Perception:__tostring(): string
	local tracked = 0
	for _ in pairs(self._awarenessMap) do
		tracked += 1
	end
	return `Perception\{vision={self.visionRange}m, hearing={self.hearingRange}m, tracking={tracked}}`
end

--[=[
	Creates a debug summary of the perception state.

	@return string -- Multi-line debug summary
]=]
function Perception:debugSummary(): string
	local lines = {
		"Perception System",
		`  Enabled: {self.enabled}`,
		`  Vision: {self.visionRange}m range, {self.visionAngle}° FOV`,
		`  Hearing: {self.hearingRange}m range, {self.hearingSensitivity}x sensitivity`,
		`  Awareness Decay: {self.awarenessDecayRate}/sec`,
		`  Thresholds: curious={self.thresholds.curious}, suspicious={self.thresholds.suspicious}, alert={self.thresholds.alert}, combat={self.thresholds.combat}`,
	}

	-- Tracked targets
	local targetCount = 0
	for _ in pairs(self._awarenessMap) do
		targetCount += 1
	end

	table.insert(lines, `  Tracked Targets: {targetCount}`)

	if targetCount > 0 then
		for targetId, entry in pairs(self._awarenessMap) do
			table.insert(lines, `    - {targetId}: {string.format("%.0f", entry.level)}% ({entry.state})`)
		end
	end

	return table.concat(lines, "\n")
end

-- ============================================================================
-- MEMORY MANAGEMENT
-- ============================================================================

--[=[
	Destroys the perception system and releases all resources.

	IMPORTANT: Call this when the NPC is despawned to prevent memory leaks.
	This clears all awareness tracking, stimuli queue, and callback references.
	After calling destroy(), the perception system should not be used.

	@example
	```lua
	-- When NPC is despawned
	perception:destroy()
	```
]=]
function Perception:destroy()
	-- Clear awareness tracking
	table.clear(self._awarenessMap)

	-- Clear stimuli queue
	table.clear(self._stimulusQueue)

	-- Clear obstruction check callback (may hold external references)
	self._obstructionCheck = nil

	-- Disable to prevent further processing
	self.enabled = false
end

--[=[
	Gets memory statistics for monitoring.

	@return { trackedTargets: number, pendingStimuli: number }
]=]
function Perception:getMemoryStats(): { trackedTargets: number, pendingStimuli: number }
	local targetCount = 0
	for _ in pairs(self._awarenessMap) do
		targetCount += 1
	end

	return {
		trackedTargets = targetCount,
		pendingStimuli = #self._stimuliQueue,
	}
end

-- ============================================================================
-- TYPE EXPORT
-- ============================================================================

--- Export type for external use.
export type Perception = typeof(Perception.new())

return Perception
