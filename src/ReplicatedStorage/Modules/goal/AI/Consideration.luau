--!strict
--[[
	Consideration.lua
	Utility AI response curves for nuanced decision-making.

	Considerations transform raw input values (health, distance, ammo, etc.)
	into normalized utility scores (0.0 - 1.0) using response curves.
	Multiple considerations can be combined to create sophisticated AI decisions.

	┌─────────────────────────────────────────────────────────────────────────┐
	│                        UTILITY AI OVERVIEW                              │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│    Input Value ──► Response Curve ──► Utility Score ──► Decision        │
	│                                                                         │
	│    Example: Health = 25%                                                │
	│                                                                         │
	│    Linear:     ████░░░░░░  0.25  (proportional)                        │
	│    Quadratic:  █░░░░░░░░░  0.06  (low health = very urgent)            │
	│    Inverse:    █████████░  0.94  (low health = retreat urgency)        │
	│    Threshold:  ██████████  1.00  (below 30% = full alarm)              │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	┌─────────────────────────────────────────────────────────────────────────┐
	│                          RESPONSE CURVES                                │
	├─────────────────────────────────────────────────────────────────────────┤
	│                                                                         │
	│  LINEAR          QUADRATIC        INVERSE          LOGISTIC             │
	│  ───────         ─────────        ───────          ────────             │
	│  █               █                    █            ██                   │
	│  █▄              █▄                  ▄█             ▄█                  │
	│  ██▄             ██▄                ▄██              ▄██                │
	│  ███▄            ███▄              ▄███               ▄███              │
	│  ████▄▄▄▄▄       █████▄▄▄▄▄    ▄▄▄▄████           ▄▄▄▄████              │
	│                                                                         │
	│  STEP            SMOOTHSTEP     EXPONENTIAL      BELL                   │
	│  ────            ──────────     ───────────      ────                   │
	│  █████           █████              █            ▄██▄                   │
	│  █████            ▄███             ▄█           ▄████▄                  │
	│       █████       ▄███            ▄██          ▄██████▄                 │
	│       █████      ███              ███         ██████████                │
	│       █████     ████▄▄▄▄▄    ▄▄▄▄████        ████████████               │
	│                                                                         │
	└─────────────────────────────────────────────────────────────────────────┘

	@class Consideration
	@author Goal GOAP System
	@version 1.0.0
	@license MIT

	## Features

	- **Response Curves**: Linear, quadratic, exponential, logistic, and more
	- **Curve Parameters**: Slope, exponent, midpoint, steepness
	- **Value Clamping**: Automatic normalization to 0-1 range
	- **Curve Inversion**: Easy inversion for opposite behaviors
	- **Composition**: Combine multiple considerations with AND/OR logic
	- **Custom Curves**: Define your own response functions

	## Basic Usage

	```lua
	local Consideration = require(path.to.Consideration)

	-- Create a consideration for health urgency
	local healthConsideration = Consideration.new({
		name = "LowHealthUrgency",
		curve = "inverse_quadratic",
		inputFn = function(state, agent)
			return state:get("health") / agent.maxHealth
		end,
	})

	-- Evaluate the consideration
	local urgency = healthConsideration:evaluate(worldState, agent)
	-- Low health (0.2) with inverse_quadratic might return 0.96 (very urgent)
	```

	## Combining Considerations

	```lua
	-- Multiple considerations combined
	local attackUtility = Consideration.combine({
		healthConsideration,      -- Am I healthy enough to fight?
		ammoConsideration,        -- Do I have ammo?
		distanceConsideration,    -- Is enemy in range?
	}, "multiply") -- or "min", "max", "average"
	```
]]

local State = require(script.Parent.Parent.State)

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

--[=[
	@type CurveType "linear" | "quadratic" | "inverse" | "inverse_quadratic" | "exponential" | "logistic" | "step" | "smoothstep" | "bell" | "custom"
	@within Consideration
	Built-in response curve types.
]=]
export type CurveType =
	"linear"
	| "quadratic"
	| "inverse"
	| "inverse_quadratic"
	| "exponential"
	| "logistic"
	| "step"
	| "smoothstep"
	| "bell"
	| "custom"

--[=[
	@type CombineMode "multiply" | "min" | "max" | "average" | "sum"
	@within Consideration
	How to combine multiple consideration scores.
]=]
export type CombineMode = "multiply" | "min" | "max" | "average" | "sum"

--[=[
	@type InputFn (worldState: State, agent: any?, context: any?) -> number
	@within Consideration
	Function that extracts a raw input value from the world state.
]=]
type InputFn = (worldState: State.State, agent: any?, context: any?) -> number

--[=[
	@type CustomCurveFn (normalizedInput: number, params: CurveParams) -> number
	@within Consideration
	Custom curve function that transforms normalized input to output.
]=]
type CustomCurveFn = (normalizedInput: number, params: CurveParams) -> number

--[=[
	@interface CurveParams
	@within Consideration
	.slope number? -- Slope for linear curves (default: 1.0)
	.exponent number? -- Exponent for power curves (default: 2.0)
	.midpoint number? -- Center point for logistic/bell curves (default: 0.5)
	.steepness number? -- Steepness for logistic curves (default: 10.0)
	.threshold number? -- Threshold for step curves (default: 0.5)
	.width number? -- Width for bell curves (default: 0.3)
]=]
export type CurveParams = {
	slope: number?,
	exponent: number?,
	midpoint: number?,
	steepness: number?,
	threshold: number?,
	width: number?,
}

--[=[
	@interface ConsiderationConfig
	@within Consideration
	.name string -- Unique identifier (REQUIRED)
	.inputFn InputFn -- Function to get raw input value (REQUIRED)
	.curve CurveType? -- Response curve type (default: "linear")
	.curveParams CurveParams? -- Curve parameters
	.customCurve CustomCurveFn? -- Custom curve function (when curve = "custom")
	.inputMin number? -- Minimum expected input value (default: 0)
	.inputMax number? -- Maximum expected input value (default: 1)
	.invert boolean? -- Invert the output (1 - output) (default: false)
	.clamp boolean? -- Clamp output to 0-1 (default: true)
	.weight number? -- Weight for combining (default: 1.0)
	.description string? -- Human-readable description
]=]
export type ConsiderationConfig = {
	name: string,
	inputFn: InputFn,
	curve: CurveType?,
	curveParams: CurveParams?,
	customCurve: CustomCurveFn?,
	inputMin: number?,
	inputMax: number?,
	invert: boolean?,
	clamp: boolean?,
	weight: number?,
	description: string?,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

--- Default curve parameters.
local DEFAULT_CURVE_PARAMS: CurveParams = table.freeze({
	slope = 1.0,
	exponent = 2.0,
	midpoint = 0.5,
	steepness = 10.0,
	threshold = 0.5,
	width = 0.3,
})

--- Log prefix for warning/error messages.
local LOG_PREFIX = "[Goal.Consideration]"

--- Lookup table resolution for pre-computed curves.
local LOOKUP_TABLE_SIZE = 256

-- ============================================================================
-- LOOKUP TABLE GENERATION
-- ============================================================================

--// Pre-computed lookup tables for common curves.
--// This avoids expensive math operations during hot paths.
local CurveLookupTables: { [string]: { number } } = {}

--// Generates a lookup table for a curve function.
local function generateLookupTable(curveFn: (number, CurveParams) -> number, params: CurveParams): { number }
	local lut = table.create(LOOKUP_TABLE_SIZE + 1)
	for i = 0, LOOKUP_TABLE_SIZE do
		local x = i / LOOKUP_TABLE_SIZE
		lut[i] = curveFn(x, params)
	end
	return lut
end

--// Samples a value from a lookup table with linear interpolation.
local function sampleLookupTable(lut: { number }, x: number): number
	local clamped = math.clamp(x, 0, 1)
	local index = clamped * LOOKUP_TABLE_SIZE
	local low = math.floor(index)
	local high = math.min(low + 1, LOOKUP_TABLE_SIZE)
	local t = index - low
	return lut[low] + (lut[high] - lut[low]) * t
end

-- ============================================================================
-- CLASS DEFINITION
-- ============================================================================

--[=[
	@class Consideration
	@tag UtilityAI

	A utility consideration that transforms input values into utility scores
	using response curves. Forms the foundation of utility-based AI decisions.
]=]
local Consideration = {}
Consideration.__index = Consideration

-- ============================================================================
-- BUILT-IN CURVE FUNCTIONS
-- ============================================================================

--- Collection of built-in response curve implementations.
local CurveFunctions: { [CurveType]: CustomCurveFn } = {}

--[=[
	Linear curve: output = input * slope
	Direct proportional mapping.
	@private
]=]
CurveFunctions.linear = function(x: number, params: CurveParams): number
	local slope = params.slope or DEFAULT_CURVE_PARAMS.slope
	return x * slope
end

--[=[
	Quadratic curve: output = input ^ exponent
	Low values produce very low output, high values accelerate.
	Good for: "urgency increases rapidly as value decreases"
	@private
]=]
CurveFunctions.quadratic = function(x: number, params: CurveParams): number
	local exponent = params.exponent or DEFAULT_CURVE_PARAMS.exponent
	return x ^ exponent
end

--[=[
	Inverse linear: output = 1 - input
	Simple inversion.
	Good for: "higher input = lower urgency"
	@private
]=]
CurveFunctions.inverse = function(x: number, _params: CurveParams): number
	return 1 - x
end

--[=[
	Inverse quadratic: output = 1 - (input ^ exponent)
	Inverse with acceleration.
	Good for: "low health = very high urgency"
	@private
]=]
CurveFunctions.inverse_quadratic = function(x: number, params: CurveParams): number
	local exponent = params.exponent or DEFAULT_CURVE_PARAMS.exponent
	return 1 - (x ^ exponent)
end

--[=[
	Exponential curve: output = (e^(input * steepness) - 1) / (e^steepness - 1)
	Slow start, rapid acceleration.
	Good for: "only care when value is very high"
	@private
]=]
CurveFunctions.exponential = function(x: number, params: CurveParams): number
	local steepness = params.steepness or DEFAULT_CURVE_PARAMS.steepness
	local expMax = math.exp(steepness) - 1
	if expMax == 0 then
		return x
	end
	return (math.exp(x * steepness) - 1) / expMax
end

--[=[
	Logistic (sigmoid) curve: output = 1 / (1 + e^(-steepness * (input - midpoint)))
	S-shaped curve, smooth transition around midpoint.
	Good for: "gradual transition with clear threshold"
	@private
]=]
CurveFunctions.logistic = function(x: number, params: CurveParams): number
	local midpoint = params.midpoint or DEFAULT_CURVE_PARAMS.midpoint
	local steepness = params.steepness or DEFAULT_CURVE_PARAMS.steepness
	return 1 / (1 + math.exp(-steepness * (x - midpoint)))
end

--[=[
	Step curve: output = 0 if input < threshold, else 1
	Binary on/off behavior.
	Good for: "only care above/below a specific value"
	@private
]=]
CurveFunctions.step = function(x: number, params: CurveParams): number
	local threshold = params.threshold or DEFAULT_CURVE_PARAMS.threshold
	return if x >= threshold then 1 else 0
end

--[=[
	Smoothstep curve: output = 3x² - 2x³ (Hermite interpolation)
	Smooth S-curve between 0 and 1.
	Good for: "smooth transition without sharp edges"
	@private
]=]
CurveFunctions.smoothstep = function(x: number, _params: CurveParams): number
	-- Clamp x to [0, 1] for smoothstep
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

--[=[
	Bell curve: output = e^(-((input - midpoint) / width)²)
	Gaussian-like peak around midpoint.
	Good for: "prefer a specific value range"
	@private
]=]
CurveFunctions.bell = function(x: number, params: CurveParams): number
	local midpoint = params.midpoint or DEFAULT_CURVE_PARAMS.midpoint
	local width = params.width or DEFAULT_CURVE_PARAMS.width
	if width == 0 then
		return if x == midpoint then 1 else 0
	end
	local distance = (x - midpoint) / width
	return math.exp(-(distance * distance))
end

--[=[
	Custom curve placeholder (uses customCurve from config).
	@private
]=]
CurveFunctions.custom = function(x: number, _params: CurveParams): number
	return x -- Will be overridden by customCurve
end

-- ============================================================================
-- CONSTRUCTOR
-- ============================================================================

--[=[
	Creates a new Consideration.

	@param config ConsiderationConfig -- Consideration configuration
	@return Consideration -- The newly created consideration

	@error "Consideration config must have a 'name' field" -- When name is missing
	@error "Consideration config must have an 'inputFn' field" -- When inputFn is missing

	@example Linear Health
	```lua
	local healthConsideration = Consideration.new({
		name = "Health",
		curve = "linear",
		inputFn = function(state, agent)
			return state:get("health") / 100
		end,
	})
	```

	@example Inverse Quadratic for Urgency
	```lua
	local urgencyConsideration = Consideration.new({
		name = "LowHealthUrgency",
		curve = "inverse_quadratic",
		curveParams = { exponent = 2.5 },
		inputFn = function(state, agent)
			return state:get("health") / agent.maxHealth
		end,
		description = "High urgency when health is low",
	})
	```

	@example Distance-Based with Bell Curve
	```lua
	local optimalRangeConsideration = Consideration.new({
		name = "OptimalCombatRange",
		curve = "bell",
		curveParams = { midpoint = 0.5, width = 0.2 },
		inputFn = function(state, agent)
			local distance = state:get("targetDistance") or 100
			return math.clamp(distance / 50, 0, 1) -- Normalize to 0-1
		end,
		description = "Prefer medium range combat",
	})
	```
]=]
function Consideration.new(config: ConsiderationConfig): Consideration
	-- Validate required fields
	assert(
		config.name ~= nil and type(config.name) == "string",
		`{LOG_PREFIX} Consideration config must have a 'name' field (string)`
	)
	assert(
		config.inputFn ~= nil and type(config.inputFn) == "function",
		`{LOG_PREFIX} Consideration config must have an 'inputFn' field (function)`
	)

	local self = setmetatable({}, Consideration)

	-- Required properties
	self.name = config.name
	self._inputFn = config.inputFn

	-- Curve configuration
	self.curve = config.curve or "linear"
	self.curveParams = if config.curveParams then table.clone(config.curveParams) else table.clone(DEFAULT_CURVE_PARAMS)
	self._customCurve = config.customCurve

	-- Input normalization
	self.inputMin = config.inputMin or 0
	self.inputMax = config.inputMax or 1

	-- Output modifiers
	self.invert = config.invert or false
	self.clamp = if config.clamp ~= nil then config.clamp else true
	self.weight = config.weight or 1.0

	-- Metadata
	self.description = config.description

	-- Pre-computed lookup table (opt-in via enableLookupTable())
	self._lookupTable = nil :: { number }?

	-- Validate curve type
	if self.curve == "custom" and not self._customCurve then
		warn(`{LOG_PREFIX} Curve type 'custom' requires a customCurve function`)
	end

	return self
end

--[=[
	Enables pre-computed lookup table for this consideration.
	Call explicitly for expensive curves (exponential, logistic, bell).
	Trades ~1KB memory per unique curve config for faster evaluation.
]=]
function Consideration:enableLookupTable()
	if self.curve == "custom" or self._lookupTable then
		return
	end

	local curveFn = CurveFunctions[self.curve]
	if not curveFn then
		return
	end

	local params = self.curveParams
	local cacheKey =
		`{self.curve}_{params.slope or 0}_{params.exponent or 0}_{params.midpoint or 0}_{params.steepness or 0}_{params.threshold or 0}_{params.width or 0}`

	local cached = CurveLookupTables[cacheKey]
	if cached then
		self._lookupTable = cached
	else
		-- Enforce cache size limit before adding new entry
		local cacheSize = 0
		for _ in pairs(CurveLookupTables) do
			cacheSize += 1
		end
		if cacheSize >= 50 then
			table.clear(CurveLookupTables)
		end

		self._lookupTable = generateLookupTable(curveFn, params)
		CurveLookupTables[cacheKey] = self._lookupTable
	end
end

--[=[
	Disables the lookup table.
]=]
function Consideration:disableLookupTable()
	self._lookupTable = nil
end

-- ============================================================================
-- CORE EVALUATION
-- ============================================================================

--[=[
	Evaluates this consideration and returns a utility score.

	Process:
	1. Get raw input value from inputFn
	2. Normalize input to 0-1 range based on inputMin/inputMax
	3. Apply response curve
	4. Apply weight
	5. Optionally invert and clamp

	@param worldState State -- The current world state
	@param agent any? -- Optional agent context
	@param context any? -- Additional context
	@return number -- Utility score (typically 0.0 - 1.0)

	@example
	```lua
	local consideration = Consideration.new({
		name = "Health",
		curve = "inverse_quadratic",
		inputFn = function(state, agent)
			return state:get("health") / 100
		end,
	})

	local utility = consideration:evaluate(worldState, agent)
	print("Health urgency:", utility)
	```
]=]
function Consideration:evaluate(worldState: State.State, agent: any?, context: any?): number
	-- Get raw input
	local rawInput = self._inputFn(worldState, agent, context)

	-- Normalize to 0-1
	local inputMin = self.inputMin
	local inputMax = self.inputMax
	local range = inputMax - inputMin
	local normalizedInput: number

	if range == 0 then
		normalizedInput = if rawInput >= inputMin then 1 else 0
	else
		normalizedInput = (rawInput - inputMin) / range
		if normalizedInput < 0 then
			normalizedInput = 0
		elseif normalizedInput > 1 then
			normalizedInput = 1
		end
	end

	-- Apply response curve (use lookup table if available)
	local output: number
	local lut = self._lookupTable
	if lut then
		output = sampleLookupTable(lut, normalizedInput)
	else
		local curveFn = if self.curve == "custom" and self._customCurve
			then self._customCurve
			else CurveFunctions[self.curve] or CurveFunctions.linear
		output = curveFn(normalizedInput, self.curveParams)
	end

	-- Apply weight
	output = output * self.weight

	-- Invert if requested
	if self.invert then
		output = 1 - output
	end

	-- Clamp if requested
	if self.clamp then
		if output < 0 then
			output = 0
		elseif output > 1 then
			output = 1
		end
	end

	return output
end

--[=[
	Deprecated: Caching removed for performance. This is a no-op for API compatibility.
]=]
function Consideration:setCacheEnabled(_enabled: boolean, _ttl: number?)
	-- No-op for backward compatibility
end

--[=[
	Deprecated: Caching removed for performance. This is a no-op for API compatibility.
]=]
function Consideration:invalidateCache()
	-- No-op for backward compatibility
end

--[=[
	Gets the name of this consideration.

	@return string -- The consideration's name
]=]
function Consideration:getName(): string
	return self.name
end

--[=[
	Gets the weight of this consideration.

	@return number -- The weight value
]=]
function Consideration:getWeight(): number
	return self.weight
end

--[=[
	Sets the weight of this consideration.

	@param weight number -- New weight value
]=]
function Consideration:setWeight(weight: number)
	assert(type(weight) == "number" and weight >= 0, `{LOG_PREFIX} weight must be a non-negative number`)
	self.weight = weight
end

--[=[
	Gets the curve type of this consideration.

	@return CurveType -- The curve type
]=]
function Consideration:getCurve(): CurveType
	return self.curve
end

--[=[
	Gets the curve parameters.

	@return CurveParams -- Copy of the curve parameters
]=]
function Consideration:getCurveParams(): CurveParams
	return table.clone(self.curveParams)
end

--[=[
	Updates a curve parameter.

	@param param string -- Parameter name (slope, exponent, midpoint, etc.)
	@param value number -- New value
]=]
function Consideration:setCurveParam(param: string, value: number)
	assert(type(value) == "number", `{LOG_PREFIX} curve param value must be a number`)
	self.curveParams[param] = value
end

-- ============================================================================
-- STATIC COMBINATION METHODS
-- ============================================================================

--[=[
	Combines multiple considerations into a single utility score.

	@param considerations { Consideration } -- Array of considerations to combine
	@param mode CombineMode -- How to combine the scores
	@param worldState State -- The current world state
	@param agent any? -- Optional agent context
	@param context any? -- Additional context
	@return number -- Combined utility score

	@example
	```lua
	local combinedUtility = Consideration.combine(
		{ healthConsideration, ammoConsideration, distanceConsideration },
		"multiply",
		worldState,
		agent
	)
	```
]=]
function Consideration.combine(
	considerations: { Consideration },
	mode: CombineMode,
	worldState: State.State,
	agent: any?,
	context: any?
): number
	if #considerations == 0 then
		return 0
	end

	-- Evaluate all considerations
	local scores: { number } = {}
	for _, consideration in ipairs(considerations) do
		table.insert(scores, consideration:evaluate(worldState, agent, context))
	end

	-- Combine based on mode
	if mode == "multiply" then
		local result = 1
		for _, score in ipairs(scores) do
			result = result * score
		end
		return result
	elseif mode == "min" then
		local result = scores[1]
		for i = 2, #scores do
			result = math.min(result, scores[i])
		end
		return result
	elseif mode == "max" then
		local result = scores[1]
		for i = 2, #scores do
			result = math.max(result, scores[i])
		end
		return result
	elseif mode == "average" then
		local sum = 0
		for _, score in ipairs(scores) do
			sum = sum + score
		end
		return sum / #scores
	elseif mode == "sum" then
		local sum = 0
		for _, score in ipairs(scores) do
			sum = sum + score
		end
		return math.clamp(sum, 0, 1)
	end

	return 0
end

--[=[
	Creates a combined consideration from multiple considerations.

	Returns a new consideration that internally evaluates and combines
	multiple other considerations.

	@param name string -- Name for the combined consideration
	@param considerations { Consideration } -- Considerations to combine
	@param mode CombineMode -- How to combine the scores
	@return Consideration -- New combined consideration

	@example
	```lua
	local combatReadiness = Consideration.createCombined(
		"CombatReadiness",
		{ healthConsideration, ammoConsideration, staminaConsideration },
		"multiply"
	)

	-- Use like any other consideration
	local readiness = combatReadiness:evaluate(worldState, agent)
	```
]=]
function Consideration.createCombined(name: string, considerations: { Consideration }, mode: CombineMode): Consideration
	return Consideration.new({
		name = name,
		curve = "linear",
		inputFn = function(worldState: State.State, agent: any?, context: any?): number
			return Consideration.combine(considerations, mode, worldState, agent, context)
		end,
		description = `Combined consideration ({mode}) of {#considerations} sub-considerations`,
	})
end

-- ============================================================================
-- FACTORY METHODS FOR COMMON PATTERNS
-- ============================================================================

--[=[
	Creates a consideration for health-based urgency.

	Low health produces high urgency using inverse quadratic curve.

	@param healthKey string -- State key for health value
	@param maxHealth number -- Maximum health for normalization
	@param exponent number? -- Urgency curve exponent (default: 2.0)
	@return Consideration -- Health urgency consideration

	@example
	```lua
	local healUrgency = Consideration.createHealthUrgency("health", 100, 2.5)
	local urgency = healUrgency:evaluate(worldState, agent) -- 0.9 at 20% health
	```
]=]
function Consideration.createHealthUrgency(healthKey: string, maxHealth: number, exponent: number?): Consideration
	return Consideration.new({
		name = "HealthUrgency",
		curve = "inverse_quadratic",
		curveParams = { exponent = exponent or 2.0 },
		inputFn = function(worldState: State.State, _agent: any?, _context: any?): number
			local health = worldState:get(healthKey) or 0
			return health / maxHealth
		end,
		description = `Urgency based on {healthKey} (max: {maxHealth})`,
	})
end

--[=[
	Creates a consideration for distance-based targeting.

	Closer targets produce higher scores.

	@param distanceKey string -- State key for distance value
	@param maxDistance number -- Maximum relevant distance
	@return Consideration -- Distance consideration

	@example
	```lua
	local targetProximity = Consideration.createDistanceConsideration("targetDistance", 50)
	local proximity = targetProximity:evaluate(worldState, agent) -- Higher when closer
	```
]=]
function Consideration.createDistanceConsideration(distanceKey: string, maxDistance: number): Consideration
	return Consideration.new({
		name = "TargetProximity",
		curve = "inverse",
		inputFn = function(worldState: State.State, _agent: any?, _context: any?): number
			local distance = worldState:get(distanceKey) or maxDistance
			return math.clamp(distance / maxDistance, 0, 1)
		end,
		description = `Proximity based on {distanceKey} (max: {maxDistance})`,
	})
end

--[=[
	Creates a consideration for resource availability.

	Higher resource levels produce higher scores.

	@param resourceKey string -- State key for resource value
	@param maxResource number -- Maximum resource for normalization
	@param threshold number? -- Minimum threshold (below = 0) (default: 0)
	@return Consideration -- Resource consideration

	@example
	```lua
	local hasAmmo = Consideration.createResourceConsideration("ammo", 30, 5)
	-- Returns 0 if ammo < 5, otherwise proportional to max
	```
]=]
function Consideration.createResourceConsideration(
	resourceKey: string,
	maxResource: number,
	threshold: number?
): Consideration
	local minThreshold = threshold or 0

	return Consideration.new({
		name = `Resource_{resourceKey}`,
		curve = "linear",
		inputFn = function(worldState: State.State, _agent: any?, _context: any?): number
			local resource = worldState:get(resourceKey) or 0
			if resource < minThreshold then
				return 0
			end
			return math.clamp(resource / maxResource, 0, 1)
		end,
		description = `Resource availability: {resourceKey} (max: {maxResource}, min: {minThreshold})`,
	})
end

--[=[
	Creates a consideration for boolean conditions.

	Returns 1.0 if condition is true, 0.0 if false.

	@param conditionKey string -- State key for boolean value
	@param invertCondition boolean? -- Invert the result (default: false)
	@return Consideration -- Boolean consideration

	@example
	```lua
	local hasTarget = Consideration.createBooleanConsideration("targetAcquired")
	local canEngage = hasTarget:evaluate(worldState, agent) -- 1.0 if target acquired
	```
]=]
function Consideration.createBooleanConsideration(conditionKey: string, invertCondition: boolean?): Consideration
	return Consideration.new({
		name = `Condition_{conditionKey}`,
		curve = "linear",
		invert = invertCondition or false,
		inputFn = function(worldState: State.State, _agent: any?, _context: any?): number
			local value = worldState:get(conditionKey)
			return if value then 1 else 0
		end,
		description = `Boolean condition: {conditionKey}`,
	})
end

--[=[
	Creates a consideration for time-based decay.

	Higher elapsed time produces lower scores.

	@param timestampKey string -- State key for timestamp
	@param decayTime number -- Time in seconds for full decay
	@return Consideration -- Time decay consideration

	@example
	```lua
	local threatRecency = Consideration.createTimeDecayConsideration("lastThreatTime", 30)
	-- Returns 1.0 immediately, decays to 0.0 over 30 seconds
	```
]=]
function Consideration.createTimeDecayConsideration(timestampKey: string, decayTime: number): Consideration
	return Consideration.new({
		name = `TimeDecay_{timestampKey}`,
		curve = "inverse",
		inputFn = function(worldState: State.State, _agent: any?, _context: any?): number
			local timestamp = worldState:get(timestampKey)
			if not timestamp then
				return 0
			end
			local elapsed = os.clock() - timestamp
			return math.clamp(elapsed / decayTime, 0, 1)
		end,
		description = `Time decay from {timestampKey} over {decayTime}s`,
	})
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

-- ============================================================================
-- MEMORY MANAGEMENT
-- ============================================================================

--// Maximum lookup table cache size to prevent unbounded growth.
local MAX_LOOKUP_TABLE_CACHE_SIZE = 50

--[=[
	Clears the global lookup table cache.

	Lookup tables are shared across all Consideration instances to save memory.
	Call this during level transitions or when memory pressure is high.

	@return number -- Number of cached tables cleared
]=]
function Consideration.clearLookupTableCache(): number
	local count = 0
	for _ in pairs(CurveLookupTables) do
		count += 1
	end
	table.clear(CurveLookupTables)
	return count
end

--[=[
	Gets statistics about the global lookup table cache.

	@return { size: number, maxSize: number }
]=]
function Consideration.getLookupTableCacheStats(): { size: number, maxSize: number }
	local count = 0
	for _ in pairs(CurveLookupTables) do
		count += 1
	end
	return {
		size = count,
		maxSize = MAX_LOOKUP_TABLE_CACHE_SIZE,
	}
end

--[=[
	Destroys the consideration and releases its resources.

	IMPORTANT: Call this when the consideration is no longer needed.
	This clears the lookup table reference and input function.
	After calling destroy(), the consideration should not be used.

	@example
	```lua
	-- When cleaning up utility AI
	consideration:destroy()
	```
]=]
function Consideration:destroy()
	-- Clear lookup table reference (the table itself is shared)
	self._lookupTable = nil

	-- Clear input function (may hold references to external objects)
	self._inputFn = nil

	-- Clear custom curve function
	self._customCurve = nil

	-- Clear curve params
	self.curveParams = nil
end

-- ============================================================================
-- DEBUGGING
-- ============================================================================

--[=[
	String representation for debugging.

	@return string -- Formatted string describing the consideration
]=]
function Consideration:__tostring(): string
	return `Consideration\{name={self.name}, curve={self.curve}, weight={self.weight}}`
end

--[=[
	Creates a debug summary of this consideration.

	@param worldState State? -- Optional world state for live evaluation
	@param agent any? -- Optional agent for live evaluation
	@return string -- Multi-line debug summary
]=]
function Consideration:debugSummary(worldState: State.State?, agent: any?): string
	local lines = {
		`Consideration: {self.name}`,
		`  Curve: {self.curve}`,
		`  Weight: {self.weight}`,
		`  Input Range: [{self.inputMin}, {self.inputMax}]`,
		`  Invert: {self.invert}`,
		`  Clamp: {self.clamp}`,
	}

	-- Add curve params
	local paramParts = {}
	for key, value in pairs(self.curveParams) do
		table.insert(paramParts, `{key}={value}`)
	end
	if #paramParts > 0 then
		table.insert(lines, `  Curve Params: {table.concat(paramParts, ", ")}`)
	end

	if self.description then
		table.insert(lines, `  Description: {self.description}`)
	end

	-- Live evaluation
	if worldState then
		local score = self:evaluate(worldState, agent)
		table.insert(lines, string.format("  Current Score: %.3f", score))
	end

	return table.concat(lines, "\n")
end

-- ============================================================================
-- TYPE EXPORT
-- ============================================================================

--- Export type for external use.
export type Consideration = typeof(Consideration.new({
	name = "",
	inputFn = function()
		return 0
	end,
}))

return Consideration
