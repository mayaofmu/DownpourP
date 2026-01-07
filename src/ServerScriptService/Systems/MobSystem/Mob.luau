local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local _ServerScriptService = game:GetService("ServerScriptService")

local _Signal = require(ReplicatedStorage.Modules.Signal)
local Goal = require(ReplicatedStorage.Modules.goal)
local WCS = require(ReplicatedStorage.Modules.wcs)
local DamagePipeline = require(script.Parent.Parent.DamagePipeline)

--[[
	BASE MOB CLASS
	   
	The Architecture:
	1. State: The "World View". Just data. e.g. { hasAmmo = false }
	2. Goals: The "Desire". e.g. { hasAmmo = true }
	3. Planner: The "Brain". Finds path from Current State -> Desired State.
	4. Actions: The "Tools". e.g. Reload (Cost: 1, Effect: hasAmmo = true)
	
	Flow:
	Scheduler calls GetCallbacks() -> Planner checks State vs Goals -> Planner finds Actions -> Scheduler runs onPlanReady
]]


local Mob = {}
Mob.__index = Mob

function Mob.new(model, config)
	local self = setmetatable({}, Mob)  
	
	self.Instance = model
	self.Id = model:GetAttribute("MobId") or HttpService:GenerateGUID(false)
	self.Config = config or {}
    self.Config.Debug = false -- Disable debug by default to prevent lag
	
    self.Config.Id = self.Id
	
	-- Assign default team
	self.Instance:SetAttribute("Team", "Enemy")
	
	self.Died = _Signal() -- Public signal for death events
	
	-- [0] WCS INTEGRATION
	self.WCSCharacter = WCS.Character.new(model)
	
    -- [STAT SCALING]
    local baseStats = config.Stats or {}
    
    -- Clone stats to avoid mutating shared data, especially for Elites
    local effectiveStats = {}
    for k, v in pairs(baseStats) do
        if type(v) == "table" then
            effectiveStats[k] = {Base = v.Base, PerLevel = v.PerLevel}
        else
            effectiveStats[k] = v
        end
    end

    -- ELITE MODIFIERS
    if config.IsElite then
        -- Stats: x4 Health, x2 Damage
        if effectiveStats.MaxHealth then effectiveStats.MaxHealth.Base *= 4 end
        if effectiveStats.Damage then effectiveStats.Damage.Base *= 2 end
        
        -- Rewards
        self.Config.ExpReward = (self.Config.ExpReward or 10) * 4
        self.Config.MoneyReward = (self.Config.MoneyReward or 5) * 4
        
        -- Visuals: Scale up and Tint
        if self.Instance:IsA("Model") then
            self.Instance:ScaleTo(self.Instance:GetScale() * 1.5)
            
            for _, part in ipairs(self.Instance:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Color = Color3.fromRGB(255, 170, 0) -- Elite Orange
                    part.Material = Enum.Material.Neon
                end
            end
        end
        
        -- Name tag update handled in CreateOverheadUI if we update Config
        self.Config.MobType = "Elite " .. (self.Config.MobType or "Enemy")
    end
    
    -- Ensure PerLevel stats exist if not provided
    if not effectiveStats.MaxHealth or not effectiveStats.MaxHealth.PerLevel then
        effectiveStats.MaxHealth = { Base = config.Health or 100, PerLevel = (config.Health or 100) * 0.3 }
    end
    if not effectiveStats.Damage or not effectiveStats.Damage.PerLevel then
        effectiveStats.Damage = { Base = 10, PerLevel = 2 } -- Default fallback
    end
    
    local statBlock = DamagePipeline.SetupCharacter(self.WCSCharacter, effectiveStats)
    local level = config.Level or 1
    statBlock:SetLevel(level)
    DamagePipeline.RecalculateStats(self.WCSCharacter)
    
    self:CreateOverheadUI(level)
   
	-- [1] STATE
	-- "The Source of Truth". The Planner only sees what is in here.
	-- You must update this in GetCallbacks().getState or via Signals.
	self.State = Goal.State.new({
		health = statBlock:Get("MaxHealth"), -- Initialize with calculated max health
		isDead = false,
        isStunned = false,
		target = nil,
        canSeePlayer = false, 
        distToPlayer = 0
		-- Add dynamic state here: 'distToPlayer', 'canSeePlayer', etc.
	})
	
	-- [2] PLANNER
	-- The A* engine that chains actions together.
	self.Planner = Goal.Planner.new({
		enableProfiling = false, -- Set true to see performance stats
	})
	
	-- [3] MEMORY
	-- Stores temporary facts (e.g. "LastKnownPlayerPos")
	self.Memory = Goal.Memory.new()
	

	-- [4] PERCEPTION
	-- Automatically handles vision cones and hearing.
	self.Perception = Goal.Perception.new({
        vision = { 
            range = 500, -- RoR2 Style: Higher vision range (was 300)
            angle = 360, -- 360 Vision (Aggressive)
            obstructionCheck = function(from, to)
                local dir = to - from
                local dist = dir.Magnitude
                -- Shorten ray slightly to avoid hitting the target itself
                local rayDir = dir.Unit * math.max(0, dist - 2)
                
                local params = RaycastParams.new()
                params.FilterDescendantsInstances = {self.Instance}
                params.FilterType = Enum.RaycastFilterType.Exclude
                
                local result = workspace:Raycast(from, rayDir, params)
                return result ~= nil -- True if obstructed
            end
        },
		awareness = { decayRate = 0.2 } -- RoR2 Style: Slow decay (Hold grudges much longer, was 0.5)
	})

    -- [5] NAVIGATION
    -- Handles pathfinding and spatial awareness
    local navConfig = self.Config.Navigation or {}
    self.Navigation = Goal.Navigation.new({
        gridSize = navConfig.gridSize or 4,
        moveSpeed = navConfig.moveSpeed or 16,
    })
    
    local pathfinderConfig = self.Config.Pathfinder or {}
    self.Pathfinder = Goal.PathfindingAdapter.new({
        agentRadius = pathfinderConfig.agentRadius or 5,
        agentHeight = pathfinderConfig.agentHeight or 5,
    })

    -- [6] BLACKBOARD
    -- Stores shared knowledge
    self.Blackboard = Goal.Blackboard.new({
        name = "GlobalBlackBoard",
        cleanupInterval = 10 
    })
    
    -- Register this mob with its navigation system for squad coordination
    self.Navigation:setBlackboard(self.Blackboard, self.Id)
    
    -- [7] PATH CACHING (for smooth movement)
    self._cachedPath = nil
    self._currentWaypointIndex = 1
    self._lastPathUpdate = 0
    self._lastTargetPosition = nil
    self._pathUpdateInterval = 0.3 -- Recalculate path every 0.5 seconds max
    
    -- [8] ACTION TRACKING
    self._currentAction = nil
    
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    
    local died; died = humanoid.Died:Connect(function()
        died:Disconnect()
        self.State:set("isDead", true)
		self.Died:Fire()

        -- Handle rewards
        local ProgressionSystem = require(script.Parent.Parent.ProgressionSystem)
        
        local attacker = DamagePipeline.GetCharacterData(self.WCSCharacter, "LastAttacker")
        if attacker and attacker.Instance and attacker.Instance:IsA("Model") then
            local expReward = self.Config.ExpReward or 10
            local moneyReward = self.Config.MoneyReward or 5
            
            -- Apply scaling (RoR2 style)
            local difficulty = workspace:GetAttribute("DifficultyCoefficient") or 1
            
            -- RoR2: Money scales linearly with difficulty, EXP scales slightly slower (coeff^0.7)
            local finalExp = math.floor(expReward * (difficulty ^ 0.7))
            local finalMoney = math.floor(moneyReward * difficulty)
            
            ProgressionSystem.AddExp(attacker.Instance, finalExp)
            ProgressionSystem.AddMoney(attacker.Instance, finalMoney)
        end

        self:Destroy() 
    end)
    
	-- [AGGRESSION]
    -- Hook into damage taken to aggro attackers
    local lastHealth = humanoid.Health
    humanoid.HealthChanged:Connect(function(health)
        if health < lastHealth then
             -- Taken damage
             local attacker = self.Instance:GetAttribute("LastAttacker")
             if attacker then
                local player = game.Players:FindFirstChild(attacker)
                if player and player.Character then
                    -- HARD AGGRO: Immediately set target and share info
                    self.State:set("hasTarget", true)
                    self.State:set("target", player.Character)
                    self.Perception:setAwarenessLevel(attacker, 100)
                    
                    -- Update Hard Aggro
                    self.State:set("hardAggroTarget", player.Character)
                    self.State:set("lastAggroTime", os.clock())
                    
                    self.Memory:recordEvent("saw_player", { pos = player.Character.PrimaryPart.Position })
                    self.Blackboard:post("LastKnownTargetPos", player.Character.PrimaryPart.Position, self.Id, 20.0) -- Extended life (was 10.0)
                end
             end
        end
        lastHealth = health
    
        self.State:set("health", health)
        if self.HPFill then
             local percent = math.clamp(health / humanoid.MaxHealth, 0, 1)
             self.HPFill:TweenSize(UDim2.new(percent, 0, 1, 0), "Out", "Quad", 0.1, true)
        end
    end)

	return self
end

function Mob:CreateOverheadUI(level)
    local head = self.Instance:FindFirstChild("Head") or self.Instance.PrimaryPart
    if not head then return end
    
    local bb = Instance.new("BillboardGui")
    bb.Name = "OverheadUI"
    bb.Adornee = head
    bb.Size = UDim2.new(8, 0, 2, 0)
    bb.StudsOffset = Vector3.new(0, 4.5, 0)
    bb.AlwaysOnTop = true
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.Parent = bb
    
    -- Level Badge
    local levelFrame = Instance.new("Frame")
    levelFrame.Size = UDim2.new(0.2, 0, 0.8, 0) 
    levelFrame.SizeConstraint = Enum.SizeConstraint.RelativeYY
    levelFrame.Position = UDim2.new(0, 0, 0.1, 0)
    levelFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    levelFrame.BorderSizePixel = 0
    levelFrame.Parent = frame
    
    local uiCorner = Instance.new("UICorner")
    uiCorner.CornerRadius = UDim.new(0.5, 0)
    uiCorner.Parent = levelFrame
    
    local uiStroke = Instance.new("UIStroke")
    uiStroke.Color = Color3.fromRGB(220, 60, 60)
    uiStroke.Thickness = 2
    uiStroke.Parent = levelFrame
    
    local levelLabel = Instance.new("TextLabel")
    levelLabel.Size = UDim2.new(1, 0, 1, 0)
    levelLabel.BackgroundTransparency = 1
    levelLabel.Text = tostring(level)
    levelLabel.TextColor3 = Color3.new(1, 1, 1)
    levelLabel.Font = Enum.Font.GothamBlack
    levelLabel.TextScaled = true
    levelLabel.Parent = levelFrame
    
    -- Name Label
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(0.7, 0, 0.4, 0)
    nameLabel.Position = UDim2.new(0.25, 0, 0.1, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = (self.Config.MobType or "Enemy") .. " " .. (self.Instance.Name)
    -- Clean up name (remove 'Clone' etc)
    nameLabel.Text = self.Instance.Name
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextScaled = true
    nameLabel.Parent = frame
    
    -- Health Bar
    local hpBg = Instance.new("Frame")
    hpBg.Size = UDim2.new(0.7, 0, 0.15, 0)
    hpBg.Position = UDim2.new(0.25, 0, 0.6, 0)
    hpBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    hpBg.BorderSizePixel = 0
    hpBg.Parent = frame
    
    local uiCornerHp = Instance.new("UICorner")
    uiCornerHp.CornerRadius = UDim.new(0.5, 0)
    uiCornerHp.Parent = hpBg

    local hpFill = Instance.new("Frame")
    hpFill.Size = UDim2.new(1, 0, 1, 0)
    hpFill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    hpFill.BorderSizePixel = 0
    hpFill.Parent = hpBg
    
    local uiCornerFill = Instance.new("UICorner")
    uiCornerFill.CornerRadius = UDim.new(0.5, 0)
    uiCornerFill.Parent = hpFill
    
    self.HPFill = hpFill
    
    bb.Parent = head
    self.BillboardGui = bb
end

-- Virtual method: Subclasses should override this
-- This is where you call self.Planner:registerAction(...)
function Mob:SetupBehavior()
	warn("Mob:SetupBehavior() not implemented for " .. tostring(self.Config.MobType))
end

-- [SCHEDULER INTERFACE]
-- The NPCScheduler calls these functions to drive the AI.
function Mob:GetCallbacks()
	return {
		-- A. Get Current World State5
		-- You should update dynamic variables here before returning
		getState = function() 
			-- 1. Update Perception
			self.Perception:update(0.1)

            -- 1b. Update Spatial Grid & Avoidance  
            local MobSystem = require(script.Parent)
            local hrp = self.Instance:FindFirstChild("HumanoidRootPart")
            if not hrp then return self.State end -- Exit if destroyed/invalid
            
            local currentPos = hrp.Position
            
            -- Only update spatial grid if moved significantly (optimization)
            if not self._lastGridUpdatePos or (currentPos - self._lastGridUpdatePos).Magnitude > 2 then
                MobSystem.UpdateSpatialGrid(self.Id, currentPos)
                self._lastGridUpdatePos = currentPos
            end

            -- Clear old avoidance zones
            self.Navigation:clearAvoidanceZones()

            -- Share destination with the squad blackboard (prevents clustering)
            self.Navigation:sharePosition()

            -- Query nearby mobs (within 20 studs)
            if not self._nearbyTable then self._nearbyTable = {} end
            table.clear(self._nearbyTable)
            MobSystem.QuerySpatialGridTo(currentPos, 20, self._nearbyTable)
            local nearby = self._nearbyTable
            
            -- Sort by distance to only include the closest ones (optimization)
            table.sort(nearby, function(a, b)
                local distA = (a.position - currentPos).Magnitude
                local distB = (b.position - currentPos).Magnitude
                return distA < distB
            end)

            local maxZones = 5 -- Only avoid the 5 closest mobs
            local zonesAdded = 0
            
            for _, entry in ipairs(nearby) do
                if entry.id ~= self.Id then
                    -- Increase cost significantly (25) to force paths around other mobs
                    -- and use a slightly larger radius (8) to account for movement
                    self.Navigation:addAvoidanceZone(entry.position, 8, 25)
                    zonesAdded += 1
                    if zonesAdded >= maxZones then break end
                end
            end

            -- Update Stun State
            local isStunned = DamagePipeline.GetCharacterData(self.WCSCharacter, "IsDisabled") or false
            self.State:set("isStunned", isStunned)

            -- Update dynamic state
            local health = self.State:get("health") or 100
            self.State:set("isLowHealth", health < 30)

            local closestPlayer = nil
            local minBodyDist = math.huge
			
			-- Handle Hard Aggro
			local hardAggroTarget = self.State:get("hardAggroTarget")
			local lastAggroTime = self.State:get("lastAggroTime") or 0
			local now = os.clock()
			
			if hardAggroTarget then
				local targetHum = hardAggroTarget:FindFirstChildOfClass("Humanoid")
				if not hardAggroTarget.Parent or not targetHum or targetHum.Health <= 0 then
					-- Target invalid
					self.State:set("hardAggroTarget", nil)
					hardAggroTarget = nil
				else
					local hardAggroHrp = self.Instance:FindFirstChild("HumanoidRootPart")
					if not hardAggroHrp then return self.State end
					
					local myPos = hardAggroHrp.Position
					local targetPos = hardAggroTarget.PrimaryPart.Position
					local dist = (myPos - targetPos).Magnitude
					
					-- Drop Condition: > 1000 studs AND > 60s since last aggro proc (RoR2 Style: Persistent)
					if dist > 1000 and (now - lastAggroTime > 60) then
						self.State:set("hardAggroTarget", nil)
						hardAggroTarget = nil
					else
						-- Maintain lock
						closestPlayer = hardAggroTarget
						minBodyDist = dist
						
						-- Refresh awareness
						self.Perception:setAwarenessLevel(hardAggroTarget.Name, 100)
						self.Memory:recordEvent("saw_player", { pos = targetPos })
						self.Blackboard:post("LastKnownTargetPos", targetPos, self.Id, 15.0) -- Extended sharing (was 5.0)
					end
				end
			end

			-- 2. Check for players (if no hard aggro)
			if not hardAggroTarget then
				for _, player in ipairs(game.Players:GetPlayers()) do
					if player.Character and player.Character.PrimaryPart then
                        local playerCheckHrp = self.Instance:FindFirstChild("HumanoidRootPart")
						if not playerCheckHrp then continue end -- Use continue instead of return early to check other players
						
	                    -- Use processVisualDetection for comprehensive check (angle, range, obstruction)
	                    local detected, _quality = self.Perception:processVisualDetection(
	                        player.Name,
	                        playerCheckHrp.Position,
	                        playerCheckHrp.CFrame.LookVector,
	                        player.Character.PrimaryPart.Position
	                    )
						
	                    local dist = (playerCheckHrp.Position - player.Character.PrimaryPart.Position).Magnitude
	                    
            -- Proximity check (always detect if very close)
            if not detected and dist < 15 then
                detected = true
                self.Perception:setAwarenessLevel(player.Name, 100)
            end
	
						if detected then
	                        if dist < minBodyDist then
	                            minBodyDist = dist
	                            closestPlayer = player.Character
	                        end
							self.Memory:recordEvent("saw_player", { pos = player.Character.PrimaryPart.Position })
							
							-- Share with squad via Blackboard (Persistent Sharing)
							self.Blackboard:post("LastKnownTargetPos", player.Character.PrimaryPart.Position, self.Id, 15.0) -- Extended sharing (was 5.0)
						end
					end
				end
			end

            if closestPlayer then
                self.State:set("hasTarget", true)
                self.State:set("target", closestPlayer)
                self.State:set("canSeePlayer", true)
                self.State:set("distToPlayer", minBodyDist)
                self.State:set("targetInMeleeRange", minBodyDist < 6)
                
                -- Hysteresis for safety state
                local wasSafe = self.State:get("safeFromTarget")
                if wasSafe then
                    self.State:set("safeFromTarget", minBodyDist > 40) -- Stays safe until player gets within 40
                else
                    self.State:set("safeFromTarget", minBodyDist > 60) -- Needs 60 studs to become safe
                end

                -- Check if target is actually dead
                local targetHum = closestPlayer:FindFirstChild("Humanoid")
                if targetHum and targetHum.Health <= 0 then
                    self.State:set("targetDead", true)
                else
                    self.State:set("targetDead", false)
                end
            else
                self.State:set("hasTarget", false)
                self.State:set("canSeePlayer", false)
                self.State:set("targetDead", false)
            end

            -- 3. Check Blackboard for shared info
            local squadTarget = self.Blackboard:read("LastKnownTargetPos")
            if squadTarget and not self.State:get("hasTarget") then 
                self.State:set("investigatePos", squadTarget) 
            end 

            -- [DEBUG] State
            if self.Config.Debug then
      
            end
			
			if self.OnGetState then
				self:OnGetState(self.State)
			end

			return self.State 
		end,
		
		-- B. Get Active Goals
		-- Return only goals relevant to the current situation
		getGoals = function() return self:GetGoals() end,
		
		-- C. Execute the Plan
		-- Called when the Planner has found a valid sequence of actions
		onPlanReady = function(plan) 
            -- [DEBUG] Plan
            if self.Config.Debug then
                local goals = self:GetGoals()
                for _, g in ipairs(goals) do
                    local _rel = g:calculateRelevance(self.State)
                    local _valid = g:isValid(self.State)
                    local _satisfied = g:isSatisfied(self.State)
                end
 
                for _, _action in ipairs(self.Planner:getActions()) do
                end

            end
            self:OnPlanReady(plan) 
        end,
	}
end

function Mob:GetGoals()
	return {} -- Override in subclass to return list of active Goal objects
end

function Mob:OnPlanReady(plan)
    -- If stunned or dead, clear current action and do nothing
    if self.State:get("isStunned") or self.State:get("isDead") then
        if self._currentAction then
            self._currentAction:interrupt(self)
            self._currentAction = nil
        end
        return
    end

	if plan.success and #plan.actions > 0 then
		-- In a tick-based system, we only execute the FIRST action of the plan.
        -- As that action progresses, the world state changes, and the next 
        -- scheduler tick will either continue this action or start the next one.
        local action = plan.actions[1]
        
        -- Handle Interruption
        if self._currentAction and self._currentAction ~= action then
            if self._currentAction:isExecuting() then
                if self.Config.Debug then
                    print(string.format("--- [Mob %s] Interrupting: %s -> New Action: %s ---", self.Id, self._currentAction:getName(), action:getName()))
                end
                self._currentAction:interrupt(self)
            end
        end
        
        self._currentAction = action
        
        -- [DEBUG] Execution
        if self.Config.Debug then
            -- Only print if it's a new action or debug is verbose
            -- print(string.format("--- [Mob %s] Executing: %s ---", self.Id, action:getName()))
        end

        if not action:isExecuting() then
            action:markStarted()
        end

        local finished = action:execute(self)
        
        if finished then
            action:markFinished()
            action:startCooldown()
            self._currentAction = nil
        end
	else
        -- Plan failed or no actions, interrupt current action if any
        if self._currentAction and self._currentAction:isExecuting() then
            if self.Config.Debug then
                print(string.format("--- [Mob %s] Plan Failed: Interrupting current action %s ---", self.Id, self._currentAction:getName()))
            end
            self._currentAction:interrupt(self)
        end
        self._currentAction = nil
    end
end

function Mob:Destroy()
    if self._animConnection then self._animConnection:Disconnect() end
	if self.Planner then self.Planner:invalidateCache() end
	if self.WCSCharacter then self.WCSCharacter:Destroy() end


    task.delay(1, function() 
    	if self.Instance then self.Instance:Destroy() end

    end)
end

function Mob:GetSeparationVector(radius)
    local now = os.clock()
    if self._lastSeparationUpdate == now and self._lastSeparationRadius == radius then
        return self._currentSeparation or Vector3.new(0, 0, 0)
    end
    
    local MobSystem = require(script.Parent)
    local hrp = self.Instance:FindFirstChild("HumanoidRootPart")
    if not hrp then return Vector3.new(0, 0, 0) end
    
    local currentPos = hrp.Position
    
    if not self._nearbyTable then self._nearbyTable = {} end
    table.clear(self._nearbyTable)
    MobSystem.QuerySpatialGridTo(currentPos, radius or 6, self._nearbyTable)
    local nearby = self._nearbyTable
    
    local separation = Vector3.new(0, 0, 0)
    local count = 0
    
    for _, entry in ipairs(nearby) do
        if entry.id ~= self.Id then
            local diff = currentPos - entry.position
            local dist = diff.Magnitude
            if dist > 0 and dist < (radius or 6) then
                -- Weight by inverse distance
                separation = separation + (diff.Unit * (1 - dist/(radius or 6)))
                count = count + 1
            end
        end
    end
    
    local targetSeparation = if count > 0 then separation / count else Vector3.new(0, 0, 0)
    
    -- Smooth the separation vector to avoid jitter
    if not self._currentSeparation then
        self._currentSeparation = targetSeparation
    else
        -- Simple lerp for smoothing (alpha 0.2 per tick)
        self._currentSeparation = self._currentSeparation:Lerp(targetSeparation, 0.2)
    end
    
    self._lastSeparationUpdate = now
    self._lastSeparationRadius = radius
    
    return self._currentSeparation
end

return Mob