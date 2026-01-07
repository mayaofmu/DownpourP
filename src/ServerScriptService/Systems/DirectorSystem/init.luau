local DirectorSystem = {}

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _Players = game:GetService("Players")
local _RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Systems = ServerScriptService.Systems
local ItemSystem = require(Systems.ItemSystem)
local MasterSystem = require(Systems.MasterSystem)
local MobSystem = require(Systems.MobSystem)
local ProgressionSystem = require(Systems.ProgressionSystem)
local Mobs = require(ReplicatedStorage.Core.Mobs)

local _WCS = require(ReplicatedStorage.Modules.wcs)
local _DamagePipeline = require(Systems.DamagePipeline)
local ItemAssets = ReplicatedStorage.Core.Data.Items

local ItemContainer = Instance.new("Folder")
ItemContainer.Name = "DroppedItems"
ItemContainer.Parent = workspace

local ChestSpawns = workspace:FindFirstChild("ChestSpawns")
if not ChestSpawns then
	ChestSpawns = Instance.new("Folder")
	ChestSpawns.Name = "ChestSpawns"
	ChestSpawns.Parent = workspace
end

local CHEST_COST = 25

local TierColors = {
	White = Color3.fromRGB(255, 255, 255),
	Green = Color3.fromRGB(94, 255, 0),
	Red = Color3.fromRGB(255, 0, 0),
}

local TierWeights = {
	White = 73,  
	Green = 24,
	Red = 3
}

local Rng = Random.new()

DirectorSystem.DifficultyCoefficient = 1
DirectorSystem.StartTime = os.clock()
DirectorSystem.Credits = 0 -- Director Credits (RoR2 Style)
DirectorSystem.TotalCreditsEarned = 0 -- For stats/debugging

task.spawn(function()
	while true do
		local elapsed = os.clock() - DirectorSystem.StartTime
		-- RoR2-ish scaling: increase difficulty over time
		-- 0.2 coefficient increase per minute
		DirectorSystem.DifficultyCoefficient = 1 + (elapsed / 60) * 0.2
		
		-- Calculate Level based on difficulty
		-- Level 1 at Diff 1. Level 99 at Diff ~33.
		DirectorSystem.CurrentEnemyLevel = math.max(1, math.floor(3 * (DirectorSystem.DifficultyCoefficient - 1) + 1))
		
		workspace:SetAttribute("DifficultyCoefficient", DirectorSystem.DifficultyCoefficient)
		workspace:SetAttribute("EnemyLevel", DirectorSystem.CurrentEnemyLevel)
            workspace:SetAttribute("DirectorCredits", math.floor(DirectorSystem.Credits))
		workspace:SetAttribute("Timer", elapsed)
		task.wait(1)
	end
end)

local function GetRandomItem()   
	local roll = Rng:NextInteger(1, 100)
	local tier = "White"
	
	if roll > 100 - TierWeights.Red then
		tier = "Red"
	elseif roll > 100 - (TierWeights.Red + TierWeights.Green) then
		tier = "Green"
	end 
	
	local candidates = {}
	for _, item in pairs(ItemSystem.GetAllItems()) do 
		if item.Tier == tier then
			table.insert(candidates, item)
		end
	end
	
	if #candidates == 0 then return nil end
	return candidates[Rng:NextInteger(1, #candidates)]
end
   
function DirectorSystem.SpawnItem(position: Vector3, itemDef: any)
	if not itemDef then return end
	
	local part = Instance.new("Part")
	part.Name = "ItemPickup"
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position + Vector3.new(0, 3.5, 0)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 0.78
	part.Color = TierColors[itemDef.Tier] or Color3.new(1,1,1)
	part.Material = Enum.Material.Neon
	part.Shape = Enum.PartType.Ball
	
	-- Tags for animation
	CollectionService:AddTag(part, "Hover")
	CollectionService:AddTag(part, "Rotate")
	
	-- Visuals
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(3, 0, 3, 0)
	bb.StudsOffset = Vector3.new(0, 0, 0)  
	bb.AlwaysOnTop = true
	bb.Parent = part
	
	local asset = ItemAssets.Models:FindFirstChild(itemDef.Name) or ItemAssets.Icons:FindFirstChild(itemDef.Name)
	if asset then
		-- Load model (prioritize model/part from Models folder)
		local model = ItemAssets.Models:FindFirstChild(itemDef.Name) 
			or (asset:IsA("Model") and asset) 
			or (asset:IsA("BasePart") and asset)
			or asset:FindFirstChildWhichIsA("Model") 
			or asset:FindFirstChildWhichIsA("BasePart")

		local clonedModel 
		if model then
			 clonedModel = model:Clone()
				clonedModel:PivotTo(part.CFrame)
 				if clonedModel.PrimaryPart then
					clonedModel.PrimaryPart.Anchored = false
				end
	 
			clonedModel.Parent = part
		end

		if clonedModel then
			local weldConstraint = Instance.new("WeldConstraint")
			weldConstraint.Parent = part
			weldConstraint.Part0 = part
			weldConstraint.Part1 = clonedModel.PrimaryPart 
		end
	end
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(.6, 12, .21, 12)
    label.Position = UDim2.new(.5, 0, .2, 0)
    label.AnchorPoint = Vector2.new(.5, .5)
	label.BackgroundTransparency = 1
	label.Text = itemDef.Name 
	label.TextColor3 = part.Color
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = bb
    label.ZIndex =3
	
	-- Interaction
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = itemDef.Name .. " (" .. itemDef.Tier .. ")"
	prompt.HoldDuration = 0.01
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		local inv = MasterSystem.GetPlayerInventory(player)
		if inv then
			inv:AddItem(itemDef.Name)
			
			-- Visual Feedback
			-- Could play sound here
			
			part:Destroy()
		end
	end)
	
	part.Parent = ItemContainer
end

function DirectorSystem.SpawnChest(spawner: BasePart)
	if spawner:GetAttribute("HasChest") then return end

	spawner:SetAttribute("HasChest", true)

	local chest = Instance.new("Part")
	chest.Name = "Chest"
	chest.Size = Vector3.new(4, 4, 4)
	local rayOrigin = spawner.Position + Vector3.new(0, 10, 0)
	local rayDirection = Vector3.new(0, -100, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {spawner, ItemContainer, workspace:FindFirstChild("Mobs")}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayResult = workspace:Raycast(rayOrigin, rayDirection, rayParams)
	local spawnPos = spawner.Position

	if rayResult then
		spawnPos = rayResult.Position
	end

	chest.Position = spawnPos + Vector3.new(0, 4, 0)
	chest.Anchored = true
	chest.CanCollide = true
	chest.Material = Enum.Material.Wood
	chest.Color = Color3.fromRGB(139, 69, 19)
	
	CollectionService:AddTag(chest, "Hover")
	CollectionService:AddTag(chest, "Rotate")
	
	chest.Parent = workspace

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Buy Chest ($" .. CHEST_COST .. ")"
	prompt.ObjectText = "Item Chest"
	prompt.HoldDuration = 0.5
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = chest

	prompt.Triggered:Connect(function(player)
		local char = player.Character
		if not char then return end

		local money = ProgressionSystem.GetMoney(char)
		if money >= CHEST_COST then
			ProgressionSystem.AddMoney(char, -CHEST_COST)

			local item = GetRandomItem()
			if item then
				DirectorSystem.SpawnItem(chest.Position, item)
			end

			spawner:SetAttribute("HasChest", false)
			chest:Destroy()
		end
	end)
end

function DirectorSystem.AttemptSpawnChest()
	local spawners = ChestSpawns:GetChildren()
	local available = {}
	for _, spawner in ipairs(spawners) do
		if spawner:IsA("BasePart") and not spawner:GetAttribute("HasChest") then
			table.insert(available, spawner)
		end
	end

	if #available > 0 then
		local spawner = available[Rng:NextInteger(1, #available)]
		DirectorSystem.SpawnChest(spawner)
	end
end

-- Updated to support credit-based selection
function DirectorSystem.SelectMob(credits)
    local candidates = {}
    local totalWeight = 0
    
    for name, data in pairs(Mobs) do
        local cost = data.DirectorCost or 15
        if cost <= credits then
            -- Simple weighting: Cheaper mobs are more likely when credits are low, 
            -- but we mostly just want availability.
            -- Let's just gather all valid candidates.
            table.insert(candidates, {Name = name, Data = data, Cost = cost})
        end
    end
    
    if #candidates == 0 then return nil end
    
    -- Pick random candidate
    local choice = candidates[Rng:NextInteger(1, #candidates)]
    
    -- Clone model logic is handled by Spawn
	return choice.Name, choice.Data.Model:Clone(), choice.Data.Stats, choice.Cost
end

function DirectorSystem.Start()

	-- Initial Spawns
	local spawners = ChestSpawns:GetChildren()
	local available = {}
	for _, spawner in ipairs(spawners) do
		if spawner:IsA("BasePart") then
			table.insert(available, spawner)
		end
	end

	-- Shuffle available to pick random 7
	for i = #available, 2, -1 do
		local j = Rng:NextInteger(1, i)
		available[i], available[j] = available[j], available[i]
	end

	for i = 1, math.min(7, #available) do
		DirectorSystem.SpawnChest(available[i])
	end

	task.spawn(function()
		while true do
			task.wait(20) -- Spawn every 20 seconds
			DirectorSystem.AttemptSpawnChest()
		end
	end)

    -- [DIRECTOR AI LOOP]
	task.spawn(function()    
		task.wait(2)

		while true do    
            local diff = DirectorSystem.DifficultyCoefficient or 1
            
            -- 1. Credit Accumulation
            -- Base Rate: 0.75 credits/tick (approx 7.5/sec at 0.1 wait? No, let's do per second logic)
            -- We want spawning to be bursty.
            
            -- Credits per second = 10 * Difficulty^0.5
            local creditsPerSecond = 8 * (diff ^ 0.5)
            local tickRate = 0.5 -- Run loop every 0.5 seconds
            
            local creditsToAdd = creditsPerSecond * tickRate
            DirectorSystem.Credits += creditsToAdd
            DirectorSystem.TotalCreditsEarned += creditsToAdd

            -- 2. Mob Cap Check
			local mobsCurrentlySpawned = 0 
			local activeMobs = MobSystem.GetMobs()
			for _, mob in activeMobs do
				if mob.Instance.Parent == workspace.Mobs then
					mobsCurrentlySpawned += 1
				end
			end

            -- Scale mob cap with difficulty
            -- Base 15, +3 per difficulty coefficient
            local mobCap = 8 + math.floor((diff - 1) * 3)
            
            -- Only spawn if under cap and we have credits
			if mobsCurrentlySpawned < mobCap then
				
                -- Try to buy a mob
                -- We only buy if we have enough credits for at least the cheapest mob (approx 15)
                if DirectorSystem.Credits >= 15 then
                    local mobType, mobModel, mobStats, cost = DirectorSystem.SelectMob(DirectorSystem.Credits) 
                    
                    if mobType then
                         -- Find a random spawn point
                        local mobSpawns = workspace:FindFirstChild("MobSpawns")
                        local spawnPos = Vector3.new(0, 5, 0) -- Default fallback
                        
                        if mobSpawns then
                            local allSpawns = {}
                            for _, part in pairs(mobSpawns:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    table.insert(allSpawns, part)
                                end
                            end
                            
                            if #allSpawns > 0 then
                                local randomSpawn = allSpawns[Rng:NextInteger(1, #allSpawns)]
                                spawnPos = randomSpawn.Position + Vector3.new(0, 3, 0)
                            end
                        end
                        
                        -- Pass level in config
                        local level = DirectorSystem.CurrentEnemyLevel or 1
                        
                        -- ELITE LOGIC (RoR2 Style)
                        local isElite = false
                        -- Cost for Elite is 6x
                        local eliteCost = cost * 6
                        
                        -- Only attempt elite if we have credits and difficulty is > 1.5
                        if DirectorSystem.Credits >= eliteCost and diff > 1.5 then
                            -- 15% chance, scaling slightly with difficulty
                            if Rng:NextNumber() < 0.15 then
                                isElite = true
                                cost = eliteCost
                            end
                        end

                        -- SPEND CREDITS
                        DirectorSystem.Credits -= cost
                        
                        MobSystem.Spawn(mobType, mobModel, mobStats, spawnPos, {
                            Level = level,
                            IsElite = isElite
                        })
                        
                        -- Small delay between spawns to prevent instant stacking
                        -- If we have tons of credits, we spawn fast (0.1s), otherwise slower
                        local spawnDelay = if DirectorSystem.Credits > 40 then 0.5 else 2
                        task.wait(spawnDelay)
                        continue -- Skip the main loop wait to potentially spawn again immediately
                    end
                end
			end
            
            task.wait(tickRate)
		end
	end)
end

return DirectorSystem