--!strict
--[[
	Personality.lua
	Trait-based personality system for varied AI behavior.

	Personality defines a set of traits that modify how an NPC makes decisions.
	Different personalities create diverse, believable AI behaviors - a brave
	warrior charges into battle while a cautious scout retreats to observe.

	┌─────────────────────────────────────────────────────────────────────────┐
	│                      PERSONALITY ARCHITECTURE                           │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│   ┌──────────────────────────────────────────────────────────────────┐  │
	│   │                         CORE TRAITS                              │  │
	│   ├──────────────────────────────────────────────────────────────────┤  │
	│   │                                                                  │  │
	│   │  AGGRESSION ═══════════════════════════════════════════════════  │  │
	│   │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │  │
	│   │  Passive ◄─────────────────────────────────────────► Aggressive  │  │
	│   │                                                                  │  │
	│   │  COURAGE ═══════════════════════════════════════════════════════  │  │
	│   │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │  │
	│   │  Cowardly ◄────────────────────────────────────────► Fearless    │  │
	│   │                                                                  │  │
	│   │  CAUTION ════════════════════════════════════════════════════════  │  │
	│   │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │  │
	│   │  Reckless ◄────────────────────────────────────────► Careful     │  │
	│   │                                                                  │  │
	│   │  LOYALTY ════════════════════════════════════════════════════════  │  │
	│   │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │  │
	│   │  Self-focused ◄────────────────────────────────────► Team-focused │  │
	│   │                                                                  │  │
	│   └──────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	│                          ▼ MODIFIES ▼                                   │
	│                                                                         │
	│   ┌──────────────────────────────────────────────────────────────────┐  │
	│   │                      DECISION WEIGHTS                            │  │
	│   ├──────────────────────────────────────────────────────────────────┤  │
	│   │  • Attack Priority     • Retreat Threshold                       │  │
	│   │  • Support Allies      • Risk Tolerance                          │  │
	│   │  • Patrol Diligence    • Aggro Range                             │  │
	│   └──────────────────────────────────────────────────────────────────┘  │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class Personality
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Features

	- **Core Traits**: Aggression, Courage, Caution, Loyalty, Patience, and more
	- **Trait Modifiers**: Apply personality to utility calculations
	- **Presets**: Common personality archetypes (Berserker, Guard, Coward, etc.)
	- **Randomization**: Generate varied personalities with constraints
	- **Mood System**: Temporary modifiers based on current emotional state
	- **Serialization**: Save and load personality data

	## Basic Usage

	```lua
	local Personality = require(path.to.Personality)

	-- Create a brave, aggressive warrior
	local warrior = Personality.new({
		aggression = 0.8,
		courage = 0.9,
		caution = 0.2,
	})

	-- Use personality to modify utility calculations
	local attackBonus = warrior:getModifier("attack") -- Returns 1.2+
	local retreatPenalty = warrior:getModifier("retreat") -- Returns 0.5-

	-- Apply to action priority
	local attackPriority = baseAttackPriority * attackBonus
	```
]]

local HttpService = game:GetService("HttpService")

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

--[=[
	@type TraitName "aggression" | "courage" | "caution" | "loyalty" | "patience" | "curiosity" | "discipline" | "selfPreservation"
	@within Personality
	Built-in personality trait names.
]=]
export type TraitName =
	"aggression"
	| "courage"
	| "caution"
	| "loyalty"
	| "patience"
	| "curiosity"
	| "discipline"
	| "selfPreservation"

--[=[
	@type MoodName "calm" | "angry" | "fearful" | "confident" | "bored" | "alert"
	@within Personality
	Built-in mood states.
]=]
export type MoodName = "calm" | "angry" | "fearful" | "confident" | "bored" | "alert"

--[=[
	@type PresetName "berserker" | "guard" | "coward" | "tactician" | "support" | "balanced" | "scout" | "veteran"
	@within Personality
	Built-in personality presets.
]=]
export type PresetName = "berserker" | "guard" | "coward" | "tactician" | "support" | "balanced" | "scout" | "veteran"

--[=[
	@interface Traits
	@within Personality
	.aggression number -- Tendency to attack (0 = passive, 1 = aggressive)
	.courage number -- Willingness to face danger (0 = cowardly, 1 = fearless)
	.caution number -- Tendency to be careful (0 = reckless, 1 = careful)
	.loyalty number -- Focus on team vs self (0 = selfish, 1 = team-focused)
	.patience number -- Willingness to wait (0 = impatient, 1 = patient)
	.curiosity number -- Interest in investigating (0 = disinterested, 1 = curious)
	.discipline number -- Following orders/protocols (0 = undisciplined, 1 = strict)
	.selfPreservation number -- Desire to survive (0 = suicidal, 1 = survival-focused)
]=]
export type Traits = {
	aggression: number,
	courage: number,
	caution: number,
	loyalty: number,
	patience: number,
	curiosity: number,
	discipline: number,
	selfPreservation: number,
}

--[=[
	@interface MoodModifiers
	@within Personality
	Temporary modifiers applied by the current mood state.
]=]
export type MoodModifiers = {
	aggression: number,
	courage: number,
	caution: number,
	patience: number,
}

--[=[
	@interface PersonalityConfig
	@within Personality
	.traits Traits? -- Initial trait values
	.name string? -- Personality name for debugging
	.preset PresetName? -- Use a preset as base
	.variance number? -- Random variance to apply (0-1)
]=]
export type PersonalityConfig = {
	traits: Traits?,
	name: string?,
	preset: PresetName?,
	variance: number?,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

--- Default trait values (balanced).
local DEFAULT_TRAITS: Traits = table.freeze({
	aggression = 0.5,
	courage = 0.5,
	caution = 0.5,
	loyalty = 0.5,
	patience = 0.5,
	curiosity = 0.5,
	discipline = 0.5,
	selfPreservation = 0.5,
})

--- Personality presets.
local PRESETS: { [PresetName]: Traits } = table.freeze({
	berserker = table.freeze({
		aggression = 0.95,
		courage = 0.9,
		caution = 0.1,
		loyalty = 0.3,
		patience = 0.1,
		curiosity = 0.2,
		discipline = 0.2,
		selfPreservation = 0.2,
	}),
	guard = table.freeze({
		aggression = 0.4,
		courage = 0.6,
		caution = 0.7,
		loyalty = 0.8,
		patience = 0.7,
		curiosity = 0.5,
		discipline = 0.8,
		selfPreservation = 0.6,
	}),
	coward = table.freeze({
		aggression = 0.1,
		courage = 0.1,
		caution = 0.9,
		loyalty = 0.2,
		patience = 0.3,
		curiosity = 0.3,
		discipline = 0.4,
		selfPreservation = 0.95,
	}),
	tactician = table.freeze({
		aggression = 0.5,
		courage = 0.6,
		caution = 0.8,
		loyalty = 0.7,
		patience = 0.8,
		curiosity = 0.7,
		discipline = 0.9,
		selfPreservation = 0.6,
	}),
	support = table.freeze({
		aggression = 0.2,
		courage = 0.5,
		caution = 0.6,
		loyalty = 0.95,
		patience = 0.7,
		curiosity = 0.4,
		discipline = 0.7,
		selfPreservation = 0.5,
	}),
	balanced = table.freeze({
		aggression = 0.5,
		courage = 0.5,
		caution = 0.5,
		loyalty = 0.5,
		patience = 0.5,
		curiosity = 0.5,
		discipline = 0.5,
		selfPreservation = 0.5,
	}),
	scout = table.freeze({
		aggression = 0.3,
		courage = 0.5,
		caution = 0.8,
		loyalty = 0.6,
		patience = 0.6,
		curiosity = 0.9,
		discipline = 0.6,
		selfPreservation = 0.7,
	}),
	veteran = table.freeze({
		aggression = 0.6,
		courage = 0.8,
		caution = 0.6,
		loyalty = 0.7,
		patience = 0.7,
		curiosity = 0.4,
		discipline = 0.8,
		selfPreservation = 0.5,
	}),
})

--- Mood modifiers.
local MOOD_MODIFIERS: { [MoodName]: MoodModifiers } = table.freeze({
	calm = table.freeze({ aggression = 0, courage = 0, caution = 0, patience = 0.1 }),
	angry = table.freeze({ aggression = 0.3, courage = 0.1, caution = -0.2, patience = -0.3 }),
	fearful = table.freeze({ aggression = -0.2, courage = -0.3, caution = 0.3, patience = -0.1 }),
	confident = table.freeze({ aggression = 0.1, courage = 0.2, caution = -0.1, patience = 0 }),
	bored = table.freeze({ aggression = -0.1, courage = 0, caution = -0.1, patience = -0.2 }),
	alert = table.freeze({ aggression = 0.1, courage = 0.1, caution = 0.1, patience = 0.1 }),
})

--- Log prefix for messages.
local LOG_PREFIX = "[Goal.Personality]"

--- Serialization version.
local SERIALIZE_VERSION = 1

-- ============================================================================
-- CLASS DEFINITION
-- ============================================================================

--[=[
	@class Personality
	@tag UtilityAI

	A trait-based personality system that modifies AI decision-making.
	Different personalities create varied, believable NPC behaviors.
]=]
local Personality = {}
Personality.__index = Personality

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

--[=[
	Creates a new Personality.

	@param config PersonalityConfig? -- Optional configuration
	@return Personality -- The newly created personality

	@example Basic Personality
	```lua
	local personality = Personality.new()
	```

	@example Custom Traits
	```lua
	local warrior = Personality.new({
		name = "Brave Warrior",
		traits = {
			aggression = 0.8,
			courage = 0.9,
			caution = 0.2,
		},
	})
	```

	@example From Preset with Variance
	```lua
	local guard = Personality.new({
		preset = "guard",
		variance = 0.1, -- +/- 10% randomness
	})
	```
]=]
function Personality.new(config: PersonalityConfig?): Personality
	local self = setmetatable({}, Personality)

	local cfg = config or {}

	-- Name
	self.name = cfg.name or "Unnamed"

	-- Initialize traits
	local baseTraits: Traits
	if cfg.preset and PRESETS[cfg.preset] then
		baseTraits = table.clone(PRESETS[cfg.preset])
	else
		baseTraits = table.clone(DEFAULT_TRAITS)
	end

	-- Apply custom traits
	if cfg.traits then
		for trait, value in pairs(cfg.traits) do
			if baseTraits[trait] ~= nil then
				baseTraits[trait] = math.clamp(value, 0, 1)
			end
		end
	end

	-- Apply variance
	if cfg.variance and cfg.variance > 0 then
		for trait, value in pairs(baseTraits) do
			local variance = (math.random() * 2 - 1) * cfg.variance
			baseTraits[trait] = math.clamp(value + variance, 0, 1)
		end
	end

	self.traits = baseTraits

	-- Mood system
	self.currentMood = "calm" :: MoodName
	self._moodExpiry = 0
	self._customModifiers = {} :: { [string]: number }

	return self
end

-- ============================================================================
-- TRAIT ACCESS
-- ============================================================================

--[=[
	Gets a trait value.

	@param traitName TraitName -- The trait to get
	@return number -- Trait value (0-1)

	@example
	```lua
	local aggression = personality:getTrait("aggression")
	if aggression > 0.7 then
		print("This NPC is aggressive!")
	end
	```
]=]
function Personality:getTrait(traitName: TraitName): number
	local base = self.traits[traitName]
	if base == nil then
		warn(`{LOG_PREFIX} Unknown trait: {traitName}`)
		return 0.5
	end

	-- Apply mood modifier
	local moodMod = self:_getMoodModifier(traitName)

	return math.clamp(base + moodMod, 0, 1)
end

--[=[
	Sets a trait value.

	@param traitName TraitName -- The trait to set
	@param value number -- New value (0-1)

	@example
	```lua
	personality:setTrait("aggression", 0.9)
	```
]=]
function Personality:setTrait(traitName: TraitName, value: number)
	if self.traits[traitName] == nil then
		warn(`{LOG_PREFIX} Unknown trait: {traitName}`)
		return
	end
	self.traits[traitName] = math.clamp(value, 0, 1)
end

--[=[
	Gets all traits.

	@return Traits -- Copy of all trait values

	@example
	```lua
	local traits = personality:getAllTraits()
	for name, value in pairs(traits) do
		print(name, "=", value)
	end
	```
]=]
function Personality:getAllTraits(): Traits
	local result = table.clone(self.traits)

	-- Apply mood modifiers
	local moodModifiers = MOOD_MODIFIERS[self.currentMood]
	if moodModifiers and os.clock() < self._moodExpiry then
		for trait, mod in pairs(moodModifiers) do
			if result[trait] then
				result[trait] = math.clamp(result[trait] + mod, 0, 1)
			end
		end
	end

	return result
end

--[=[
	Gets the base trait value without mood modifiers.

	@param traitName TraitName -- The trait to get
	@return number -- Base trait value (0-1)
]=]
function Personality:getBaseTrait(traitName: TraitName): number
	return self.traits[traitName] or 0.5
end

-- ============================================================================
-- DECISION MODIFIERS
-- ============================================================================

--[=[
	Gets a modifier value for a specific action/decision type.

	Modifiers translate traits into practical multipliers for utility
	calculations. Returns values typically between 0.5 and 1.5.

	@param modifierType string -- Type of modifier to get
	@return number -- Modifier multiplier (typically 0.5-1.5)

	@example
	```lua
	local attackMod = personality:getModifier("attack")
	local retreatMod = personality:getModifier("retreat")
	local investigateMod = personality:getModifier("investigate")

	-- Apply to priorities
	local attackPriority = baseAttack * attackMod
	local retreatPriority = baseRetreat * retreatMod
	```
]=]
function Personality:getModifier(modifierType: string): number
	-- Check custom modifiers first
	if self._customModifiers[modifierType] then
		return self._customModifiers[modifierType]
	end

	-- Built-in modifier calculations
	local aggression = self:getTrait("aggression")
	local courage = self:getTrait("courage")
	local caution = self:getTrait("caution")
	local loyalty = self:getTrait("loyalty")
	local patience = self:getTrait("patience")
	local curiosity = self:getTrait("curiosity")
	local discipline = self:getTrait("discipline")
	local selfPreservation = self:getTrait("selfPreservation")

	if modifierType == "attack" then
		-- Attack modifier: aggressive, courageous personalities attack more
		return 0.5 + (aggression * 0.5) + (courage * 0.3) - (caution * 0.2)
	elseif modifierType == "retreat" then
		-- Retreat modifier: cautious, self-preserving personalities retreat more
		return 0.5 + (selfPreservation * 0.4) + (caution * 0.3) - (courage * 0.3)
	elseif modifierType == "defend" then
		-- Defense modifier: cautious, disciplined personalities defend more
		return 0.5 + (caution * 0.3) + (discipline * 0.3)
	elseif modifierType == "support" then
		-- Support modifier: loyal personalities support allies more
		return 0.5 + (loyalty * 0.5) - (selfPreservation * 0.2)
	elseif modifierType == "investigate" then
		-- Investigation modifier: curious personalities investigate more
		return 0.5 + (curiosity * 0.5) - (caution * 0.2)
	elseif modifierType == "patrol" then
		-- Patrol modifier: disciplined, patient personalities patrol better
		return 0.5 + (discipline * 0.3) + (patience * 0.2)
	elseif modifierType == "wait" then
		-- Waiting modifier: patient personalities wait longer
		return 0.5 + (patience * 0.5)
	elseif modifierType == "charge" then
		-- Charge modifier: aggressive, courageous, reckless personalities charge
		return 0.4 + (aggression * 0.4) + (courage * 0.3) - (caution * 0.3)
	elseif modifierType == "flank" then
		-- Flanking modifier: tactical, cautious personalities flank
		return 0.5 + (caution * 0.3) + (discipline * 0.2) - (aggression * 0.1)
	elseif modifierType == "heal" then
		-- Healing modifier: self-preserving and loyal personalities heal more
		return 0.5 + (selfPreservation * 0.3) + (loyalty * 0.2)
	elseif modifierType == "risk" then
		-- Risk tolerance: opposite of caution and self-preservation
		return 0.5 + (courage * 0.3) - (caution * 0.3) - (selfPreservation * 0.2) + (aggression * 0.1)
	elseif modifierType == "teamwork" then
		-- Teamwork modifier: loyalty and discipline
		return 0.5 + (loyalty * 0.4) + (discipline * 0.2)
	else
		-- Unknown modifier type, return neutral
		return 1.0
	end
end

--[=[
	Sets a custom modifier value.

	@param modifierType string -- Modifier type name
	@param value number -- Modifier value

	@example
	```lua
	personality:setCustomModifier("stealth", 1.3)
	```
]=]
function Personality:setCustomModifier(modifierType: string, value: number)
	self._customModifiers[modifierType] = value
end

--[=[
	Removes a custom modifier.

	@param modifierType string -- Modifier type name
]=]
function Personality:removeCustomModifier(modifierType: string)
	self._customModifiers[modifierType] = nil
end

--[=[
	Gets the health threshold at which this personality considers retreating.

	@return number -- Health percentage (0-1) at which retreat is considered

	@example
	```lua
	local retreatThreshold = personality:getRetreatThreshold()
	if currentHealth / maxHealth < retreatThreshold then
		considerRetreat()
	end
	```
]=]
function Personality:getRetreatThreshold(): number
	local courage = self:getTrait("courage")
	local selfPreservation = self:getTrait("selfPreservation")
	local aggression = self:getTrait("aggression")

	-- Base threshold: 30%
	-- Cowardly characters retreat at higher health
	-- Courageous characters retreat at lower health
	local threshold = 0.3 + (selfPreservation * 0.3) - (courage * 0.2) - (aggression * 0.1)

	return math.clamp(threshold, 0.1, 0.7)
end

--[=[
	Gets the aggro range multiplier based on personality.

	@return number -- Multiplier for detection/aggro range

	@example
	```lua
	local baseRange = 50
	local actualRange = baseRange * personality:getAggroRangeMultiplier()
	```
]=]
function Personality:getAggroRangeMultiplier(): number
	local aggression = self:getTrait("aggression")
	local curiosity = self:getTrait("curiosity")
	local discipline = self:getTrait("discipline")

	-- Aggressive and curious characters have larger aggro range
	-- Disciplined characters stick to protocol (neutral)
	return 0.8 + (aggression * 0.3) + (curiosity * 0.2) - (discipline * 0.1)
end

-- ============================================================================
-- MOOD SYSTEM
-- ============================================================================

--[=[
	Sets the current mood.

	Moods temporarily modify traits for a duration.

	@param mood MoodName -- The mood to set
	@param duration number? -- Duration in seconds (default: 30)

	@example
	```lua
	-- NPC takes damage, becomes angry
	personality:setMood("angry", 60) -- Angry for 60 seconds
	```
]=]
function Personality:setMood(mood: MoodName, duration: number?)
	if not MOOD_MODIFIERS[mood] then
		warn(`{LOG_PREFIX} Unknown mood: {mood}`)
		return
	end

	self.currentMood = mood
	self._moodExpiry = os.clock() + (duration or 30)
end

--[=[
	Gets the current mood.

	@return MoodName -- Current mood
	@return number -- Seconds remaining (0 if expired)

	@example
	```lua
	local mood, remaining = personality:getMood()
	print("Current mood:", mood, "for", remaining, "more seconds")
	```
]=]
function Personality:getMood(): (MoodName, number)
	local now = os.clock()
	if now >= self._moodExpiry then
		self.currentMood = "calm"
		return "calm", 0
	end
	return self.currentMood, self._moodExpiry - now
end

--[=[
	Clears the current mood, returning to calm.
]=]
function Personality:clearMood()
	self.currentMood = "calm"
	self._moodExpiry = 0
end

--[=[
	Internal: Gets mood modifier for a trait.
	@private
]=]
function Personality:_getMoodModifier(traitName: TraitName): number
	if os.clock() >= self._moodExpiry then
		return 0
	end

	local moodModifiers = MOOD_MODIFIERS[self.currentMood]
	if moodModifiers and moodModifiers[traitName] then
		return moodModifiers[traitName]
	end

	return 0
end

-- ============================================================================
-- COMPARISON & COMPATIBILITY
-- ============================================================================

--[=[
	Calculates similarity to another personality.

	@param other Personality -- The other personality to compare
	@return number -- Similarity score (0-1, higher = more similar)

	@example
	```lua
	local similarity = personality1:similarityTo(personality2)
	if similarity > 0.8 then
		print("These personalities are very similar!")
	end
	```
]=]
function Personality:similarityTo(other: Personality): number
	local totalDiff = 0
	local traitCount = 0

	for trait, value in pairs(self.traits) do
		local otherValue = other.traits[trait]
		if otherValue then
			totalDiff = totalDiff + math.abs(value - otherValue)
			traitCount = traitCount + 1
		end
	end

	if traitCount == 0 then
		return 1
	end

	-- Convert average difference to similarity
	local avgDiff = totalDiff / traitCount
	return 1 - avgDiff
end

--[=[
	Checks if this personality is compatible with another for teamwork.

	@param other Personality -- The other personality
	@return boolean -- Whether they work well together
	@return string -- Reason for compatibility/incompatibility

	@example
	```lua
	local compatible, reason = leader:isCompatibleWith(follower)
	if not compatible then
		print("Team conflict:", reason)
	end
	```
]=]
function Personality:isCompatibleWith(other: Personality): (boolean, string)
	-- Check for major conflicts

	-- Two very aggressive personalities may clash
	if self:getTrait("aggression") > 0.8 and other:getTrait("aggression") > 0.8 then
		return false, "Both personalities are too aggressive"
	end

	-- Two very undisciplined personalities won't coordinate
	if self:getTrait("discipline") < 0.3 and other:getTrait("discipline") < 0.3 then
		return false, "Neither personality is disciplined enough for teamwork"
	end

	-- A very loyal personality needs someone to be loyal to
	if self:getTrait("loyalty") > 0.8 and other:getTrait("loyalty") < 0.3 then
		return false, "Loyalty mismatch - one is team-focused, other is self-focused"
	end

	-- Compatible by default
	return true, "Personalities are compatible"
end

-- ============================================================================
-- PRESETS & FACTORY METHODS
-- ============================================================================

--[=[
	Creates a personality from a preset.

	@param presetName PresetName -- The preset to use
	@param variance number? -- Random variance to apply
	@return Personality -- New personality from preset

	@example
	```lua
	local berserker = Personality.fromPreset("berserker")
	local guard = Personality.fromPreset("guard", 0.1) -- With 10% variance
	```
]=]
function Personality.fromPreset(presetName: PresetName, variance: number?): Personality
	return Personality.new({
		preset = presetName,
		variance = variance,
		name = presetName,
	})
end

--[=[
	Creates a random personality within constraints.

	@param constraints { [TraitName]: { min: number?, max: number? } }? -- Optional trait constraints
	@return Personality -- New random personality

	@example
	```lua
	-- Random personality
	local random = Personality.createRandom()

	-- Random aggressive personality
	local aggressive = Personality.createRandom({
		aggression = { min = 0.7 },
		courage = { min = 0.5 },
	})
	```
]=]
function Personality.createRandom(constraints: { [TraitName]: { min: number?, max: number? } }?): Personality
	local traits = {}

	for traitName in pairs(DEFAULT_TRAITS) do
		local min = 0
		local max = 1

		if constraints and constraints[traitName] then
			min = constraints[traitName].min or 0
			max = constraints[traitName].max or 1
		end

		traits[traitName] = min + math.random() * (max - min)
	end

	return Personality.new({
		traits = traits,
		name = "Random",
	})
end

--[=[
	Gets a list of available preset names.

	@return { PresetName } -- Array of preset names
]=]
function Personality.getPresetNames(): { PresetName }
	local names = {}
	for name in pairs(PRESETS) do
		table.insert(names, name)
	end
	return names
end

--[=[
	Gets a list of available trait names.

	@return { TraitName } -- Array of trait names
]=]
function Personality.getTraitNames(): { TraitName }
	local names = {}
	for name in pairs(DEFAULT_TRAITS) do
		table.insert(names, name :: TraitName)
	end
	return names
end

-- ============================================================================
-- SERIALIZATION
-- ============================================================================

--[=[
	Serializes personality for persistence.

	@return { [string]: any } -- Serialized data

	@example
	```lua
	local data = personality:serialize()
	DataStore:SetAsync(npcId, HttpService:JSONEncode(data))
	```
]=]
function Personality:serialize(): { [string]: any }
	return {
		_version = SERIALIZE_VERSION,
		name = self.name,
		traits = self.traits,
	}
end

--[=[
	Deserializes personality from saved data.

	@param data { [string]: any } -- Serialized data
	@return Personality -- Restored personality

	@example
	```lua
	local json = DataStore:GetAsync(npcId)
	local data = HttpService:JSONDecode(json)
	local personality = Personality.deserialize(data)
	```
]=]
function Personality.deserialize(data: { [string]: any }): Personality
	local personality = Personality.new({
		name = data.name,
		traits = data.traits,
	})
	return personality
end

--[=[
	Converts personality to JSON string.

	@return string? -- JSON string, or nil on error
	@return string? -- Error message, or nil on success
]=]
function Personality:toJSON(): (string?, string?)
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
	Creates personality from JSON string.

	@param json string -- JSON string
	@return Personality? -- Restored personality, or nil on error
	@return string? -- Error message, or nil on success
]=]
function Personality.fromJSON(json: string): (Personality?, string?)
	local success, decoded = pcall(function()
		return HttpService:JSONDecode(json)
	end)

	if not success then
		return nil, `Failed to decode JSON: {tostring(decoded)}`
	end

	return Personality.deserialize(decoded), nil
end

-- ============================================================================
-- MEMORY MANAGEMENT
-- ============================================================================

--[=[
	Destroys the personality and releases all resources.

	IMPORTANT: Call this when the NPC is despawned to prevent memory leaks.
	This clears all custom modifiers and resets the mood state.
	After calling destroy(), the personality should not be used.

	@example
	```lua
	-- When NPC is despawned
	personality:destroy()
	```
]=]
function Personality:destroy()
	-- Clear custom modifiers
	table.clear(self._customModifiers)

	-- Reset mood
	self.currentMood = "calm"
	self._moodExpiry = 0
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	String representation for debugging.

	@return string -- Formatted string
]=]
function Personality:__tostring(): string
	local mood, remaining = self:getMood()
	local moodStr = if remaining > 0 then ` [{mood}]` else ""
	return `Personality\{name={self.name}{moodStr}}`
end

--[=[
	Creates a debug summary of the personality.

	@return string -- Multi-line debug summary
]=]
function Personality:debugSummary(): string
	local lines = {
		`Personality: {self.name}`,
	}

	-- Current mood
	local mood, remaining = self:getMood()
	if remaining > 0 then
		table.insert(lines, `  Mood: {mood} ({string.format("%.0f", remaining)}s remaining)`)
	end

	-- Traits
	table.insert(lines, "  Traits:")
	for trait, value in pairs(self.traits) do
		local bar = string.rep("█", math.floor(value * 10))
		local empty = string.rep("░", 10 - math.floor(value * 10))
		table.insert(lines, string.format("    %s: %s%s %.0f%%", trait, bar, empty, value * 100))
	end

	-- Key modifiers
	table.insert(lines, "  Key Modifiers:")
	for _, modType in ipairs({ "attack", "retreat", "investigate", "teamwork" }) do
		local mod = self:getModifier(modType)
		table.insert(lines, string.format("    %s: %.2fx", modType, mod))
	end

	return table.concat(lines, "\n")
end

-- ============================================================================
-- TYPE EXPORT
-- ============================================================================

--- Export type for external use.
export type Personality = typeof(Personality.new())

return Personality
