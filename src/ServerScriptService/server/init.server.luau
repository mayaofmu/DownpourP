local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WCS = require(ReplicatedStorage.Modules.wcs)
local NetRay = require(ReplicatedStorage.Modules.NetRay)



-- Load Systems
local Systems = ServerScriptService.Systems
local DamagePipeline = require(Systems.DamagePipeline)
local _ItemSystem = require(Systems.ItemSystem)
local MasterSystem = require(Systems.MasterSystem)
local DirectorSystem = require(Systems.DirectorSystem)
local _TagSystem = require(Systems.TagSystem)
local ProgressionSystem = require(Systems.ProgressionSystem)
local MasterySystem = require(Systems.MasterySystem)
local MobSystem = require(Systems.MobSystem)

-- Setup Content
DamagePipeline.Content.SetupEffects()

local Server = WCS.CreateServer()

-- Game Events -- 

local InventoryUpdated = NetRay:RegisterEvent("InventoryChanged") 
local StatsUpdated = NetRay:RegisterEvent("StatsUpdated")



-- Register Directories
Server:RegisterDirectory(ReplicatedStorage.Core.Classes)
if ReplicatedStorage:FindFirstChild("movesets") then
	Server:RegisterDirectory(ReplicatedStorage.movesets)
end

Server:Start()
MobSystem.Start()
DirectorSystem.Start()

-- Global Progression Listeners
ProgressionSystem.LevelUp:Connect(function(character, newLevel)
	-- Give Mastery Exp on level up?
	local player = game.Players:GetPlayerFromCharacter(character)
	if player then
		MasterySystem.AddExp(player, 50) -- Example: 50 Mastery Exp per Level Up
	end
end)

ProgressionSystem.ExpChanged:Connect(function(character, exp, maxExp)
	-- print(string.format("[Progression] %s Exp: %d / %d", character.Name, exp, maxExp))
end)

ProgressionSystem.MoneyChanged:Connect(function(character, money)
	-- print(string.format("[Progression] %s Money: %d", character.Name, money))
end)

-- Character Setup
local function OnCharacterAdded(player, characterModel)
	local humanoid = characterModel:WaitForChild("Humanoid", 5)
	if not humanoid then return end


    local CameraOffsetAttachment = script.CameraAttachment:Clone()
    CameraOffsetAttachment.Parent = characterModel.Head

	

	local wcsChar = WCS.Character.new(characterModel)
	
	-- 1. Get Persistent Inventory
	local inventory = MasterSystem.GetPlayerInventory(player)
	   
	-- 2. Setup Stats & Link Inventory   
	local statBlock = DamagePipeline.SetupCharacter(wcsChar)
	
	-- Swap to Persistent Inventory
	-- wcsChar:SetMetadata("Inventory", inventory) -- Old Method
	DamagePipeline.SetCharacterData(wcsChar, "Inventory", inventory) -- New Method
	
	-- Listen for changes
	local function Recalc()
		if wcsChar.Instance and wcsChar.Instance.Parent then
			DamagePipeline.RecalculateStats(wcsChar)
		end
	end 
	
	-- Initial Recalc
	Recalc()
	
	-- Hook listener (and clean up when char dies)
	inventory:AddListener(function() 
		task.wait() 
		Recalc()
		-- Replicate Inventory to Client
		if player then
			InventoryUpdated:FireClient(player, inventory.Stacks)
			-- Force stat replication after inventory update to ensure new stats from items are sent
			StatsUpdated:FireClient(player, statBlock._stats)
		end
	end)
	
	-- Hook Stat Changes
	local pendingReplication = false
	statBlock.Changed:Connect(function()

		if not pendingReplication then
			pendingReplication = true
			task.delay(0.05, function()
				-- Recalc() -- Removed to avoid recursive loop. Recalc should be triggered by source changes (Inventory, Buffs).
				-- task.wait(.05)
				pendingReplication = false
				if player then
					statBlock:UpdateAll() -- Force update cached values before replication
					StatsUpdated:FireClient(player, statBlock._stats)
				end
			end)
		end 
	end)
	
	-- Initial Replication
	if player then
		InventoryUpdated:FireClient(player, inventory.Stacks)
		-- Send all stats initially
			StatsUpdated:FireClient(player, statBlock._stats)
	end
	 
	wcsChar.Destroyed:Connect(function()
		inventory:RemoveListener(Recalc)
	end)
	
	humanoid.Died:Connect(function()
		-- Reset inventory on death (unless prevented by Golden Apple, which prevents Death entirely)
		print("[Server] Player died, clearing inventory...")
		inventory:Clear()
	end)

	-- Assign Moveset
	wcsChar:ApplyMoveset("Glaive")
	
	print(string.format("[System] Character Setup for %s (Glaive)", player.Name))
	
	-- Starter Items
		inventory:AddItem("Green Tea", 2) 
		inventory:AddItem("Med Pack", 1)
		inventory:AddItem("Turtle Shell", 1)
		inventory:AddItem("Kunai", 1)
		inventory:AddItem("Shooting Stars", 1)
		inventory:AddItem("Golden Apple", 1)
		inventory:AddItem("Gungnir", 3) 
end
 
game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char) 
		OnCharacterAdded(player, char)
	end)
end)    

-- Spawn Enemy––
task.spawn(function()
	task.wait(2)
	
    -- Locate Template
	local template = workspace:FindFirstChild("Mobs") and workspace.Mobs:FindFirstChild("Enemy")
    local mobSpawns = workspace:FindFirstChild("MobSpawns")
    
    if template and template:FindFirstChild("Humanoid") and mobSpawns then
        -- Hide Template
        template.Parent = ServerScriptService -- Store away safely
        
		-- Enemy Base Stats: HIGH DEFENSE, VERY HIGH HP
		local enemyStats = {
			MaxHealth = {Base = 1000, PerLevel = 0},
			Damage = {Base = 20, PerLevel = 0},
			Regen = {Base = 20, PerLevel = 0},
			Armor = {Base = 30, PerLevel = 0},
			AttackSpeed = {Base = 3, PerLevel = 0},
			CritChance = {Base = 0, PerLevel = 0},
			MoveSpeed = {Base = 12, PerLevel = 0},
			CritDamage = {Base = 2.0, PerLevel = 0}
		}
        
        -- Spawn at ONE random spawn point
        local spawns = mobSpawns:GetChildren()
        if #spawns > 0 then
            local spawnPoint = spawns[math.random(1, #spawns)]
            
            if spawnPoint:IsA("BasePart") then
                local clone = template:Clone()
                clone.Parent = workspace.Mobs
                clone:PivotTo(spawnPoint.CFrame + Vector3.new(0, 3, 0)) -- Slight offset up
                
                -- Use MobSystem to spawn (Attaches AI + Stats)
                local mob = MobSystem.Spawn("Noob", clone, enemyStats)
                
                if mob then
                    print("[System] Spawned Boss Enemy at " .. spawnPoint.Name)
                end
            end
        end
		
	else
		warn("[System] Missing 'Mobs.Enemy' template or 'MobSpawns' folder in Workspace!")
	end
end)
