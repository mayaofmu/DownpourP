local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemSystem = {}
ItemSystem.__index = ItemSystem

local ItemDatabase = require(ReplicatedStorage.Core.Data.Items)

export type ItemTier = "White" | "Green" | "Red" | "Boss" | "Lunar"

-- Augment ItemDef with Server-Side Logic
export type ItemDef = {
	Name: string,
	Tier: ItemTier,
	Description: string,
	
	ApplyStats: ((inventory: any, count: number, statBlock: any) -> ())?,
	OnHit: ((inventory: any, count: number, damageInfo: any, target: any) -> ())?,
	OnFire: ((inventory: any, count: number, attacker: any, origin: Vector3, targetPos: Vector3) -> ())?,
	OnTakeDamage: ((inventory: any, count: number, damageInfo: any) -> ())?,
	OnDeath: ((inventory: any, count: number) -> boolean)?,
}

local Items: {[string]: ItemDef} = {}

-- Helper to register logic for items defined in DB
function ItemSystem.RegisterLogic(name: string, logic: any)
	local def = ItemDatabase[name]
	if not def then
		warn("Attempted to register logic for unknown item:", name)
		return
	end
	
	-- Merge DB def with Logic
	local fullDef = setmetatable(logic, {__index = def})
	fullDef.Name = name -- Ensure name matches
	Items[name] = fullDef
end

function ItemSystem.GetItem(name: string)
	-- If logic exists, return that. If not, return raw DB entry (passive items without logic?)
	return Items[name] or ItemDatabase[name]
end

function ItemSystem.GetAllItems()
	-- Return merged list
	local all = {}
	for k, v in pairs(ItemDatabase) do
		if typeof(v) == "function" then continue end
		all[k] = ItemSystem.GetItem(k)
	end
	return all
end

-- Inventory Class
local Inventory = {}
Inventory.__index = Inventory

function Inventory.new()
	local self = setmetatable({
		Stacks = {} :: {[string]: number},
		Listeners = {} :: {() -> ()},
		Rng = Random.new(),
	}, Inventory)
	return self
end

function Inventory:AddItem(itemName: string, amount: number?)
	amount = amount or 1
	if not ItemDatabase[itemName] then 
		warn("Item not found:", itemName) 
		return 
	end
	
	local current = self.Stacks[itemName] or 0
	self.Stacks[itemName] = current + amount
	
	self:FireChanged()
end

function Inventory:RemoveItem(itemName: string, amount: number?)
	amount = amount or 1
	if not self.Stacks[itemName] then return end
	
	local current = self.Stacks[itemName] 
	local newAmount = math.max(0, current - amount)
	
	self.Stacks[itemName] = newAmount
	
	if newAmount == 0 then
		self.Stacks[itemName] = nil
	end
	
	self:FireChanged()
end

function Inventory:Clear()
	self.Stacks = {}
	self:FireChanged()
end

function Inventory:FireChanged()
	for _, listener in ipairs(self.Listeners) do
		task.spawn(listener)
	end
end

function Inventory:AddListener(callback: () -> ())
	table.insert(self.Listeners, callback)
end

function Inventory:RemoveListener(callback: () -> ())
	for i, v in ipairs(self.Listeners) do
		if v == callback then
			table.remove(self.Listeners, i)
			break
		end
	end
end

function Inventory:GetCount(itemName: string)
	return self.Stacks[itemName] or 0
end


function ItemSystem.FireOnFire(inventory, attacker, origin: Vector3, targetPos: Vector3)
	if not inventory then return end
	
	for name, count in pairs(inventory.Stacks) do
		local def = ItemSystem.GetItem(name)
		if def and def.OnFire then
			def.OnFire(inventory, count, attacker, origin, targetPos)
		end
	end
end

-- =========================================================================================
-- ITEM LOGIC REGISTRY
-- =========================================================================================
-- This doesn't belong here. 
-- Green Tea
ItemSystem.RegisterLogic("Green Tea", {
	ApplyStats = function(inv, count, statBlock)
		statBlock:AddModifier("AttackSpeed", 0.07 * count, "Additive", "GreenTea")
		statBlock:AddModifier("MoveSpeed", 0.05 * count, "Additive", "GreenTea")
		statBlock:AddModifier("MaxHealth", 15 * count, "Flat", "GreenTea")
	end,
})

-- Feral Claws
ItemSystem.RegisterLogic("Feral Claws", {
	ApplyStats = function(inv, count, statBlock)
		statBlock:AddModifier("AttackSpeed", 0.1 * count, "Additive", "FeralClaws")
	
        
    end,
})

-- Med Pack   
ItemSystem.RegisterLogic("Med Pack", {
	ApplyStats = function(inv, count, statBlock)
		statBlock:AddModifier("Regen", 0.08 * count, "Additive", "MedPack_Passive")
	end,
})

-- Turtle Shell
ItemSystem.RegisterLogic("Turtle Shell", {
	ApplyStats = function(inv, count, statBlock)
		statBlock:AddModifier("Armor", 15 * count, "Flat", "TurtleShell")
	end,
})

-- Scouter
ItemSystem.RegisterLogic("Scouter", {  
	ApplyStats = function(inv, count, statBlock) 
		statBlock:AddModifier("CritChance", 8 * count, "Flat", "Scouter")
		statBlock:AddModifier("Damage", 2 * count, "Flat", "Scouter")
	end,
})

-- Hermetic Boots
ItemSystem.RegisterLogic("Hermetic Boots", {
	ApplyStats = function(inv, count, statBlock)
		statBlock:AddModifier("MoveSpeed", 0.14 * count, "Additive", "HermeticBoots")
	end,
})

--[[
ItemSystem.RegisterLogic("Spear", {
	OnHit = function(inv, count, dmgInfo, target)
		if dmgInfo.ProcCoefficient <= 0 then return end
		if inv.Rng:NextNumber() <= 0.08 * dmgInfo.ProcCoefficient then
			local char = dmgInfo.Attacker
			if char then
				local hasSkill = char:GetSkillFromString("Spear")
				if not hasSkill then
					local SpearClass = require(ReplicatedStorage.Core.Classes.Items.Spear)
					local skill = SpearClass.new(char)
					skill:Start(target.Instance)
				else
					hasSkill:Start(target.Instance)
				end
			end
		end
	end,
}) --]]

-- Kunai (Trigger WCS Skill)
ItemSystem.RegisterLogic("Kunai", {
	OnHit = function(inv, count, dmgInfo, target)
		if dmgInfo.ProcChainMask > 0 then return end
		if dmgInfo.ProcCoefficient <= 0 then return end
		
		if inv.Rng:NextNumber() <= 0.10 * dmgInfo.ProcCoefficient then
			-- Trigger WCS Skill
			local char = dmgInfo.Attacker -- WCS Character
			if char then
				local hasSkill = char:GetSkillFromString("Kunai")
				if not hasSkill then
					local KunaiClass = require(ReplicatedStorage.Core.Classes.Items.Kunai)
					local skill = KunaiClass.new(char)
					skill:Start(target.Instance)
				else
					hasSkill:Start(target.Instance)
				end
			end
		end
	end,
})

-- Gungnir (Red Item)
-- 50% to fire on using LMB attack, scales with stacks
ItemSystem.RegisterLogic("Gungnir", {
	OnFire = function(inv, count, attacker, origin, targetPos)
		local totalChance = 0.5 * count
		local spearCount = math.floor(totalChance)
		local extraChance = totalChance - spearCount
		
		if inv.Rng:NextNumber() <= extraChance then
			spearCount += 1
		end

		if spearCount > 0 then
			local char = attacker
			if char then
				local hasSkill = char:GetSkillFromString("Gungnir")

				if not hasSkill then
					local GungnirClass = require(ReplicatedStorage.Core.Classes.Items.Gungnir)
					local skill = GungnirClass.new(char)
					skill:Start(targetPos, spearCount)
				else
					hasSkill:Start(targetPos, spearCount)
				end
			end
		end
	end,
})

-- Weakpoint Analyzer
ItemSystem.RegisterLogic("Weakpoint Analyzer", {
	ApplyStats = function(inv, count, statBlock)
		statBlock:AddModifier("CritDamage", 0.05 * count, "Additive", "WeakpointAnalyzer")
        statBlock:AddModifier("Damage", 4 * count, "Flat", "WeakpointAnalyzer")

    end,    
})

-- Corrosive Barrel
ItemSystem.RegisterLogic("Corrosive Barrel", {
	OnHit = function(inv, count, dmgInfo, target)
		if dmgInfo.ProcCoefficient <= 0 then return end
		if inv.Rng:NextNumber() <= 0.15 * dmgInfo.ProcCoefficient then
			local char = dmgInfo.Attacker
			if char then
				local hasSkill = char:GetSkillFromString("CorrosiveBarrel")
				if not hasSkill then
					local BarrelClass = require(ReplicatedStorage.Core.Classes.Items.CorrosiveBarrel)
					local skill = BarrelClass.new(char)
					skill:Start(target.Instance)
				else
					hasSkill:Start(target.Instance)
				end
			end
		end
	end,
}) 

-- Rocket Launcher
ItemSystem.RegisterLogic("Rocket Launcher", {
	OnHit = function(inv, count, dmgInfo, target)
		if dmgInfo.ProcCoefficient <= 0 then return end
		if inv.Rng:NextNumber() <= 0.15 * dmgInfo.ProcCoefficient then
			local char = dmgInfo.Attacker
			if char then
				local hasSkill = char:GetSkillFromString("RocketLauncher")
				if not hasSkill then
					local RocketClass = require(ReplicatedStorage.Core.Classes.Items.RocketLauncher)
					local skill = RocketClass.new(char)
					skill:Start(target.Instance)
				else
					hasSkill:Start(target.Instance)
				end
			end
		end
	end,
})

-- Shooting Stars
ItemSystem.RegisterLogic("Shooting Stars", {
	OnHit = function(inv, count, dmgInfo, target)
		if dmgInfo.ProcCoefficient <= 0 then return end
		if inv.Rng:NextNumber() <= 0.20 * dmgInfo.ProcCoefficient then
			local char = dmgInfo.Attacker
			if char then
				-- Check if skill exists before requiring/instantiating
				local hasSkill = char:GetSkillFromString("ShootingStars")
				if not hasSkill then
					local StarClass = require(ReplicatedStorage.Core.Classes.Items.ShootingStars)
					local skill = StarClass.new(char)
					skill:Start(target.Instance, 1, count)
				else
					hasSkill:Start(target.Instance, 1, count)
				end
			end
		end
	end,
})

-- Golden Apple
ItemSystem.RegisterLogic("Golden Apple", {
    ApplyStats = function(inv, count, statBlock)
		statBlock:AddModifier("CritDamage", .1 * count, "Additive", "Golden Apple")
		statBlock:AddModifier("Damage", .1 * count, "Additive", "Golden Apple")
	end,
	OnDeath = function(inv, count)
		if count > 0 then
			inv:RemoveItem("Golden Apple", 1)
			return true
		end
		return false
	end,
})

ItemSystem.Inventory = Inventory

return ItemSystem
