local StatSystem = {}
StatSystem.__index = StatSystem

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Modules.Signal)

export type StatType = "MaxHealth" | "Regen" | "Damage" | "Armor" | "AttackSpeed" | "CritChance" | "MoveSpeed" | "CritDamage" | "Cooldown" | "BlockChance"

export type ModifierType = "Flat" | "Additive" | "Multiplicative" | "Hyperbolic"

type StatModifier = {
	Value: number,
	Type: ModifierType,
	Source: any, -- Item or Buff
}

type Stat = {
	Base: number,
	PerLevel: number,
	Level: number,
	Modifiers: {StatModifier},
	CachedValue: number,
	Dirty: boolean,
	Formula: string, -- "Linear" | "HyperbolicDecay" | "HyperbolicGrowth"
}

-- Formula Definitions
local Formulas = {
	-- Standard: (Base + Flat) * (1 + Additive) * Multiplicative
	Linear = function(base, flat, additive, multiplicative, hyperbolic)
		return (base + flat) * (1 + additive) * multiplicative
	end,
	
	-- Hyperbolic Decay (e.g. Cooldowns): Linear * (1 / (1 + HyperbolicSum))
	-- Result scales down as HyperbolicSum increases.
	HyperbolicDecay = function(base, flat, additive, multiplicative, hyperbolic)
		local val = (base + flat) * (1 + additive) * multiplicative
		if hyperbolic > 0 then
			val = val * (1 / (1 + hyperbolic))
		end
		return val
	end,
	
	-- Hyperbolic Growth (e.g. Block Chance): 1 - (1 / (1 + HyperbolicSum))
	-- Result approaches 1 as HyperbolicSum increases.
	-- Usually ignores Base/Flat/Additive for the hyperbolic portion, 
	-- but we can support adding them if needed. 
	-- RoR2 Block is purely items, so Base=0.
	HyperbolicGrowth = function(base, flat, additive, multiplicative, hyperbolic)
		-- If we want to support base chance + hyperbolic chance:
		-- It's complex. RoR2 Tougher Times is simple: 1 - 1/(1 + 0.15*stack).
		-- We'll return just the hyperbolic factor for now as it's the primary use case.
		if hyperbolic > 0 then
			return 1 - (1 / (1 + hyperbolic))
		end
		return 0
	end
}

-- Default Behaviors
local StatBehaviors = {
	MaxHealth = "Linear",
	Regen = "Linear",
	Damage = "Linear",
	Armor = "Linear", -- Armor is linear stats, handled as mitigation formula later.
	AttackSpeed = "Linear",
	CritChance = "Linear", -- Now Flat points (0-100)
	MoveSpeed = "Linear",
	CritDamage = "Linear",
	Cooldown = "HyperbolicDecay",
	BlockChance = "HyperbolicGrowth",
}

local function CreateStat(base: number, perLevel: number, formula: string): Stat
	return {
		Base = base,
		PerLevel = perLevel,
		Level = 1,
		Modifiers = {},
		CachedValue = base,
		Dirty = true,
		Formula = formula or "Linear"
	}
end

local function Recalculate(stat: Stat)
	if not stat.Dirty then return stat.CachedValue end

	local base = stat.Base + (stat.PerLevel * (stat.Level - 1))
	local flat = 0
	local additive = 0
	local multiplicative = 1
	local hyperbolicSum = 0

	for _, mod in ipairs(stat.Modifiers) do
		if mod.Type == "Flat" then
			flat += mod.Value
		elseif mod.Type == "Additive" then
			additive += mod.Value
		elseif mod.Type == "Multiplicative" then
			multiplicative *= mod.Value
		elseif mod.Type == "Hyperbolic" then
			hyperbolicSum += mod.Value
		end
	end
	
	local formulaFunc = Formulas[stat.Formula] or Formulas.Linear
	stat.CachedValue = formulaFunc(base, flat, additive, multiplicative, hyperbolicSum)
	stat.Dirty = false
	return stat.CachedValue
end

function StatSystem.new(config: {[StatType]: {Base: number, PerLevel: number}})
	local self = setmetatable({}, StatSystem)
	self._stats = {} :: {[StatType]: Stat}
	self.StatChanged = Signal()
	self.Changed = Signal()
	
	for statName, data in pairs(config) do
		local formula = StatBehaviors[statName] or "Linear"
		self._stats[statName] = CreateStat(data.Base, data.PerLevel or 0, formula)
	end
	
	-- Ensure defaults exist
	local defaults = {
		MaxHealth = 100, Regen = 1, Damage = 12, Armor = 0, 
		AttackSpeed = 1, CritChance = 1, MoveSpeed = 16, CritDamage = 2.0,
		Cooldown = 0, BlockChance = 0
	}
	
	for name, val in pairs(defaults) do
		if not self._stats[name] then
			local formula = StatBehaviors[name] or "Linear"
			self._stats[name] = CreateStat(val, 0, formula)
		end
	end

	return self
end

function StatSystem:Get(statName: StatType): number
	local stat = self._stats[statName]
	if not stat then return 0 end
	return Recalculate(stat)
end

function StatSystem:AddModifier(statName: StatType, value: number, type: ModifierType, source: any)
	local stat = self._stats[statName]
	if not stat then 
		-- Auto-create if missing (e.g. for dynamic stats)
		local formula = StatBehaviors[statName] or "Linear"
		stat = CreateStat(0, 0, formula)
		self._stats[statName] = stat
	end
	
	table.insert(stat.Modifiers, {
		Value = value,
		Type = type,
		Source = source
	})
	stat.Dirty = true
	self.StatChanged:Fire(statName)
	self.Changed:Fire()
end 

function StatSystem:ClearModifiers()
	for statName, stat in pairs(self._stats) do
		table.clear(stat.Modifiers)
		stat.Dirty = true
		self.StatChanged:Fire(statName)
	end
	self.Changed:Fire()
end

function StatSystem:RemoveModifier(source: any)
	for statName, stat in pairs(self._stats) do
		local changed = false
		for i = #stat.Modifiers, 1, -1 do
			if stat.Modifiers[i].Source == source then
				table.remove(stat.Modifiers, i)
				stat.Dirty = true
				changed = true
			end
		end
		if changed then
			self.StatChanged:Fire(statName)
		end
	end
	self.Changed:Fire()
end

function StatSystem:SetLevel(level: number)
	for statName, stat in pairs(self._stats) do
		stat.Level = level
		stat.Dirty = true
		self.StatChanged:Fire(statName)
	end
	self.Changed:Fire()
end

function StatSystem:UpdateAll()
	for _, stat in pairs(self._stats) do
		Recalculate(stat)
	end
end

return StatSystem
