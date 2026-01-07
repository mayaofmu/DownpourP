local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _ServerScriptService = game:GetService("ServerScriptService")

local _WCS = require(ReplicatedStorage.Modules.wcs)
local NetRay = require(ReplicatedStorage.Modules.NetRay)
local ItemSystem = require(script.Parent.ItemSystem)
local StatSystem = require(script.Parent.StatSystem)
local ProgressionSystem = require(script.Parent.ProgressionSystem)

local DamagePipeline = {}

DamagePipeline.Content = {
	SetupEffects = function()
		require(ReplicatedStorage.Core.StatusEffects)
	end,
}

local DamageEvent = NetRay:RegisterEvent("DamageEvent")

-- Metadata Registry (Weak Keys)
local CharacterData = setmetatable({}, {__mode = "k"})

function DamagePipeline.SetCharacterData(character, key, value)
	if not CharacterData[character] then
		CharacterData[character] = {}
	end
	CharacterData[character][key] = value
end

function DamagePipeline.GetCharacterData(character, key)
	return CharacterData[character] and CharacterData[character][key]
end

-- Helpers for common data
function DamagePipeline.GetStatBlock(character)
	return DamagePipeline.GetCharacterData(character, "StatBlock")
end

function DamagePipeline.GetInventory(character)
	return DamagePipeline.GetCharacterData(character, "Inventory")
end

-- Types
export type DamageType = "Generic" | "Bleed" | "Ignite" | "Poison" | "Stun" | "Freeze"

export type DamageInfo = {
	Attacker: any?, -- WCS Character
	Inflictor: Instance?, -- The object dealing damage (projectile, etc)
	Damage: number,
	Crit: boolean,
	ProcCoefficient: number,
	DamageType: {[DamageType]: boolean}?, -- e.g. {Bleed = true}
	Position: Vector3,
	Force: Vector3,
	ProcChainMask: number, -- Counter for recursion depth
}

-- Helpers for common data

-- Recalculate Stats (Nuke and Rebuild)
function DamagePipeline.RecalculateStats(character)
	local statBlock = DamagePipeline.GetStatBlock(character)
	local inventory = DamagePipeline.GetInventory(character)
	if not statBlock then return end
	
	statBlock:ClearModifiers()
	
	-- 1. Apply Inventory Stats
	if inventory then
		for name, count in pairs(inventory.Stacks) do
			local def = ItemSystem.GetItem(name)
			if def and def.ApplyStats then
				def.ApplyStats(inventory, count, statBlock)
			end
		end
	end
	
	-- Force a stat changed event on critical stats if they haven't changed (to ensure replication catches up)
	-- This is a bit hacky but ensures client UI refreshes if they missed the boat.
	-- Or rely on StatSystem dirty flags.
	
	-- 2. Apply Buff Stats (StatusEffects)
	for _, effect in pairs(character:GetAllActiveStatusEffects()) do
		local name = effect.Name
		
		if name == "MedPackBuff" then
			statBlock:AddModifier("Regen", 2, "Multiplicative", "MedPackBuff")
		end
		
		if name == "SprintBuff" then
			statBlock:AddModifier("MoveSpeed", 1.45, "Multiplicative", "SprintBuff")
		end

        if name == "Stun" then
            -- Mobs (and players) should stop entirely when stunned
            statBlock:AddModifier("MoveSpeed", 0, "Multiplicative", "Stun")
        end
		-- Add other buffs here
	end  
	
	-- Force Update Humanoid
	local hum = character.Humanoid
	if hum then
		local newSpeed = statBlock:Get("MoveSpeed")
		-- Update WCS Default Props to prevent overwriting
		character:SetDefaultProps({
			WalkSpeed = newSpeed
		})
		-- Also set directly just in case
		hum.WalkSpeed = newSpeed
		hum.MaxHealth = statBlock:Get("MaxHealth")
	end
end

-- Core Processing
function DamagePipeline.ProcessDamage(damageInfo: DamageInfo, target: any)
	local source = damageInfo.Attacker
	local _sourceStats = source and DamagePipeline.GetStatBlock(source)
	local sourceInv = source and DamagePipeline.GetInventory(source)
	
	local targetStats = DamagePipeline.GetStatBlock(target)
	local targetInv = DamagePipeline.GetInventory(target)
	
	-- 1. Mitigation (Armor)
	if targetStats then
		local armor = targetStats:Get("Armor")
		local reduction = armor / (armor + 100)
		if reduction < 0 then reduction = 0 end
		local multiplier = 100 / (100 + armor)
		damageInfo.Damage = damageInfo.Damage * multiplier
	end
	
	-- 2. OnHit (Source) - Procs
	if sourceInv and damageInfo.ProcCoefficient > 0 then
		for name, count in pairs(sourceInv.Stacks) do
			local def = ItemSystem.GetItem(name)
			if def and def.OnHit then
				-- We pass the full DamageInfo and the Target
				def.OnHit(sourceInv, count, damageInfo, target)
			end
		end
	end
	
	-- 3. WCS TakeDamage (Skill/Effect Modifiers)
	local container = {
		Damage = damageInfo.Damage,
		Source = nil -- WCS expects Skill|StatusEffect, passing Character crashes it.
	}
	container = target:TakeDamage(container)
	damageInfo.Damage = container.Damage
	
	-- 4. OnTakeDamage (Target)
	if targetInv then
		for name, count in pairs(targetInv.Stacks) do
			local def = ItemSystem.GetItem(name)
			if def and def.OnTakeDamage then
				def.OnTakeDamage(targetInv, count, damageInfo)
			end
		end
	end
	
	-- 5. Apply Health
	local humanoid = target.Humanoid
	if humanoid then
		local newHealth = humanoid.Health - damageInfo.Damage
		
		-- Record Last Attacker for Rewards
		if source and source.Instance then
			target.Instance:SetAttribute("LastAttacker", source.Instance.Name)
			DamagePipeline.SetCharacterData(target, "LastAttacker", source)
		end

		-- Fire Damage Event for Numbers
		local pos = damageInfo.Position
		if not pos and target.Instance.PrimaryPart then
			pos = target.Instance.PrimaryPart.Position
		end
		
		DamageEvent:FireAllClients({
			Amount = math.floor(damageInfo.Damage),
			Position = pos or Vector3.zero,
			Crit = damageInfo.Crit,
			Type = "Generic", -- Expand if needed
			Attacker = source and source.Player, -- Pass the player who dealt damage
			Target = target.Instance -- Pass the character who took damage
		})
		
		if newHealth <= 0 then
			-- Check Death Prevention
			local deathPrevented = false
			if targetInv then
				for name, count in pairs(targetInv.Stacks) do
					local def = ItemSystem.GetItem(name)
					if def and def.OnDeath then
						if def.OnDeath(targetInv, count) then
							deathPrevented = true
							break
						end
					end
				end
			end
			
			if deathPrevented then
				humanoid.Health = humanoid.MaxHealth
			else
				humanoid.Health = 0
				-- Maybe fire OnDeath event here? WCS handles it usually.
			end
		else
			humanoid.Health = newHealth
		end
	end
end

function DamagePipeline.DealDamage(attacker, target, damageCoeff, procCoeff, damageTypeString)
	local stats = attacker and DamagePipeline.GetStatBlock(attacker)
	local baseDamage = stats and stats:Get("Damage") or 10
	local critChance = stats and stats:Get("CritChance") or 0 -- Now Flat 0-100
	local critDamage = stats and stats:Get("CritDamage") or 2.0
	
	local rng = Random.new()
	local isCrit = false
	if rng:NextNumber() * 100 <= critChance then
		isCrit = true
		baseDamage = baseDamage * critDamage
	end
	
	local dmgInfo: DamageInfo = {
		Attacker = attacker,
		Inflictor = nil, -- Could be passed in
		Damage = baseDamage * damageCoeff,
		Crit = isCrit,
		ProcCoefficient = procCoeff,
		DamageType = {[damageTypeString or "Generic"] = true},
		Position = target.Instance.PrimaryPart and target.Instance.PrimaryPart.Position or Vector3.zero,
		Force = Vector3.zero,
		ProcChainMask = 0
	}
	
	DamagePipeline.ProcessDamage(dmgInfo, target)
end

function DamagePipeline.SetupCharacter(wcsChar, baseStatsOverride)
	local defaultConfig = {
		MaxHealth = {Base = 100, PerLevel = 20},
		Damage = {Base = 12, PerLevel = 2.4},
		Regen = {Base = 1, PerLevel = 0.2},
		Armor = {Base = 0, PerLevel = 0},
		AttackSpeed = {Base = 1, PerLevel = 0},
		CritChance = {Base = 1, PerLevel = 0}, -- 1%
		MoveSpeed = {Base = 16, PerLevel = 0},
		CritDamage = {Base = 2.0, PerLevel = 0} -- 200%
	}
	
	local config = baseStatsOverride or defaultConfig
	
	local statBlock = StatSystem.new(config)
	
	-- Hook Progression System
	ProgressionSystem.LevelUp:Connect(function(character, level)
		if character == wcsChar.Instance then
			statBlock:SetLevel(level)
			DamagePipeline.RecalculateStats(wcsChar)
			
			-- Full heal on level up (RoR2 style)
			local hum = wcsChar.Humanoid
			if hum then
				hum.Health = hum.MaxHealth
			end
		end
	end)

	-- wcsChar:SetMetadata("StatBlock", statBlock) -- ERROR FIX: Use internal registry
	DamagePipeline.SetCharacterData(wcsChar, "StatBlock", statBlock)
	
	-- Loop for Regen/Updates (Simple)
	local hum = wcsChar.Humanoid
	if hum then
		hum.MaxHealth = statBlock:Get("MaxHealth")
		hum.Health = hum.MaxHealth
		
		task.spawn(function()
			while wcsChar.Instance and wcsChar.Instance.Parent do
				-- Recalc periodically or on event? 
				-- Usually event driven, but for regen we tick.
				local regen = statBlock:Get("Regen")
				if hum.Health < hum.MaxHealth and hum.Health > 0 then
					local healAmount = regen * 0.5
					hum.Health = math.min(hum.Health + healAmount, hum.MaxHealth)
					
					-- Fire Heal Event
					if healAmount > 1 then -- Only show integers or significant heals? 
						-- Client side filters < 1 usually, or we can send it all.
						-- Let's only send if it's visible > 0.5 to reduce spam for micro-regen.
						
						local pos = wcsChar.Instance.PrimaryPart and wcsChar.Instance.PrimaryPart.Position
						if pos then
							DamageEvent:FireAllClients({
								Amount = math.floor(healAmount),
								Position = pos,
								Crit = false,
								Type = "Heal"
							})
						end
					end
				end
				task.wait(0.5)
			end
		end)
	end
	
	return statBlock
end

return DamagePipeline
