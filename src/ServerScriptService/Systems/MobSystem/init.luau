local PhysicsService = game:GetService("PhysicsService")

local MobSystem = {}

-- Create collision group for mobs to pass through each other
pcall(function()
    PhysicsService:RegisterCollisionGroup("Mobs")
    PhysicsService:CollisionGroupSetCollidable("Mobs", "Mobs", false)
end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Systems = ServerScriptService.Systems

local Goal = require(ReplicatedStorage.Modules.goal)

local spatialGrid = Goal.SpatialGrid.new(10) -- 10 stud cells for mob avoidance

-- Module Loader
local Enemies = {}
local EnemiesFolder = script:WaitForChild("Enemies")

local function LoadEnemies() 
	for _, module in ipairs(EnemiesFolder:GetChildren()) do
		if module:IsA("ModuleScript") then
			Enemies[module.Name] = require(module)
		end
	end
end
LoadEnemies()

local activeMobs = {} -- [MobId] -> MobObject
local scheduler -- NPCScheduler Instance

-- [SYSTEM STARTUP]
-- Initializes the "Heartbeat" of the AI.
function MobSystem.Start()
	-- The NPCScheduler manages the CPU budget.
	-- Instead of every mob thinking every frame (Lag!), 
	-- it updates a few mobs each frame based on their priority.
	scheduler = Goal.NPCScheduler.new({
		tickBudget = 0.002, -- 4ms max per frame for AI
		maxNPCsPerTick = 20,
		updateInterval = 0.1, -- Each mob thinks ~5 times/sec
	})

	scheduler:start()
	

	print("MobSystem Started")
end

-- [FACTORY SPAWNER]
function MobSystem.Spawn(mobType, model, stats, cframe, config)
	local MobClass = Enemies[mobType]
	if not MobClass then
		warn("Mob type not found:", mobType)
		return nil
	end


	-- 1. Create Subclass Instance
	-- Wraps the Roblox Model with our AI Logic
	if stats then
		config = config or {}
		config.Stats = stats
	end
	
	if cframe and model:IsA("Model") then
		model:PivotTo(CFrame.new(cframe))
	elseif cframe and model:IsA("BasePart") then
		model.CFrame = CFrame.new(cframe)
	end
	
	model.Parent = workspace.Mobs -- Parent it!  

    -- Apply collision group to all parts in the model
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CollisionGroup = "Mobs"
        end
    end

	local mob = MobClass.new(model, config or {})
	activeMobs[mob.Id] = mob

	mob.Died:Connect(function()
		
		local deathEffect = script.Assets.DeathEffect:Clone()
		deathEffect.Parent = workspace.Effects 
		deathEffect.Position = model.Head.Position
		deathEffect.Attachment.Death:Emit(1)
		
		task.delay(.8, function()
		    deathEffect:Destroy()	
		end)
		
		activeMobs[mob.Id] = nil
        spatialGrid:remove(mob.Id)
		if scheduler then
			scheduler:unregisterNPC(mob.Id)
		end
	end)
	       
	-- Verify ID is a string before registering
	if type(mob.Id) ~= "string" or mob.Id == "" then
		warn("[MobSystem] Invalid Mob ID:", mob.Id, " - generating fallback.")
		mob.Id = tostring(game:GetService("HttpService"):GenerateGUID(false))
	end

    -- Update spatial grid initially
    spatialGrid:insert(mob.Id, model.PrimaryPart.Position)

	-- 2. Register with Scheduler
	-- This tells the Goal library: "Manage this mob's brain for me"
	if scheduler then
		scheduler:registerNPC(mob.Id, mob:GetCallbacks())
        -- SYNC ACTIONS: The scheduler creates its own planner, so we must 
        -- register the mob's actions to the scheduler's planner.
        scheduler:registerActions(mob.Id, mob.Planner:getActions())
	else
		warn("[MobSystem] Scheduler not initialized. Did you forget to call MobSystem.Start()?")
	end
	
	return mob
end

function MobSystem.GetMob(id)
	return activeMobs[id]
end

function MobSystem.RemoveMob(id)
	activeMobs[id] = nil
    spatialGrid:remove(id)
	if scheduler then
		scheduler:unregisterNPC(id)
	end
end

function MobSystem.GetMobs()
	return activeMobs
end

function MobSystem.UpdateSpatialGrid(id, position)
    spatialGrid:update(id, position)
end

function MobSystem.QuerySpatialGrid(position, radius)
    return spatialGrid:query(position, radius)
end

function MobSystem.QuerySpatialGridTo(position, radius, results)
    spatialGrid:queryTo(position, radius, results)
end

return MobSystem