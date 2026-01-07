local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Goal = require(ReplicatedStorage.Modules.goal)
local _WCS = require(ReplicatedStorage.Modules.wcs)
local Systems = ServerScriptService.Systems
local DamagePipeline = require(Systems.DamagePipeline)
local MasterSystem = require(Systems.MasterSystem)
local MobSystem = script.Parent.Parent
local Mob = require(MobSystem.Mob)



local Template = setmetatable({}, {__index = Mob})
Template.__index = Template

function Template.new(model, config)
	local self = Mob.new(model, config)
	
    setmetatable(self, Template)  
	
	local stats = config.Stats
    local wcsMob = self.WCSCharacter
		
    -- Apply Mob Moveset
	local MobMoveset = require(ReplicatedStorage.Core.Classes.Mobs.Moveset)
	wcsMob:ApplyMoveset(MobMoveset)

	local statBlock = DamagePipeline.SetupCharacter(wcsMob, stats)
	
	-- Persistent Enemy Inventory
	local mobInv = MasterSystem.RegisterMob(model)
	DamagePipeline.SetCharacterData(wcsMob, "Inventory", mobInv)
	
    -- Assign Team Attribute
    model:SetAttribute("Team", "Enemy")

	-- Initial Calculation
	if statBlock then
		DamagePipeline.RecalculateStats(wcsMob)
	end

	self:SetupBehavior()
    
    -- [Strategy Cooldowns]
    self.lastStrafeTime = 0
    self.lastFlankTime = 0
    self.lastRoamTime = 0
	
	return self
end

function Template:OnGetState(state)
    local skill = self.WCSCharacter:GetSkillFromString("EnemyProjectile")
    if skill then
        state:set("canRangedAttack", not skill:GetState().Debounce)
    else
        state:set("canRangedAttack", false)
    end
end

-- [BEHAVIOR SETUP]
-- This is where you define the "Personality" of the mob.
function Template:SetupBehavior()
	
	-- 1. DEFINE ACTIONS (Transitions)
	-- "I can [Action] if [Preconditions] to achieve [Effects]"
	
    self.Navigation = Goal.Navigation.new({
        gridSize = 4, 
        maxIterations = 400, 
        moveSpeed = 16, 
        minCoverageHeight = 3
    }) 
    
    -- Config Overrides
    if self.Config.Navigation then
        for k, v in pairs(self.Config.Navigation) do
            -- Re-instantiate if needed, or simply override properties if supported
            -- Since Navigation.new creates a new object, we rely on Mob.luau's base logic mostly, 
            -- but since Noob.lua overwrites self.Navigation, we should respect config here too.
        end
        -- Actually, better to just use the one from Mob.luau if it exists?
        -- But Noob.lua defines specific parameters like minCoverageHeight.
        -- Let's merge the config.
        local navConfig = self.Config.Navigation or {}
        self.Navigation = Goal.Navigation.new({
            gridSize = navConfig.gridSize or 4,
            maxIterations = 400,
            moveSpeed = navConfig.moveSpeed or 16,
            minCoverageHeight = 3
        })
    end 

	local idleAction = Goal.Action.new({
		name = "Idle",
		cost = 4, -- Increased cost so Wander is preferred
		preconditions = {}, -- Always possible
		effects = { isIdling = true },
		executeFn = function(agent)
			-- print(agent.Id, "is idling...")
			return true -- Success
		end,
	})
	
    local strafeAction = Goal.Action.new({
        name = "Strafe",
        cost = 3, -- Cheap combat maneuver
        preconditions = {
            hasTarget = true,
            canSeePlayer = true
        },
        effects = {
            isStrafing = true
        },
        executeFn = function(agent)
            local target = agent.State:get("target")
            if not target then return true end
            
            local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
            if not hum then return true end
            
            -- Initialize strafe if not already executing
            if not agent._currentStrafeDest then
                local hrp = agent.Instance:FindFirstChild("HumanoidRootPart")
                if not hrp then return true end
                local startPos = hrp.Position
                local targetPos = target.PrimaryPart.Position
                
                -- Direction to target
                local toTarget = (targetPos - startPos).Unit
                local right = toTarget:Cross(Vector3.new(0, 1, 0))
                
                -- Pick a random side
                local side = math.random() > 0.5 and 1 or -1
                local strafeDir = right * side
                
                local strafeDest = startPos + (strafeDir * 15) -- 15 studs strafe
                
                -- Raycast to ensure we don't strafe into a wall
                local params = RaycastParams.new()
                params.FilterDescendantsInstances = {agent.Instance}
                params.FilterType = Enum.RaycastFilterType.Exclude
                
                local result = workspace:Raycast(startPos, strafeDir * 15, params)
                if result then
                     -- If blocked, try other side
                     strafeDir = right * (-side)
                     strafeDest = startPos + (strafeDir * 15)
                     local result2 = workspace:Raycast(startPos, strafeDir * 15, params)
                     if result2 then
                         return true -- Both sides blocked, fail
                     end
                end
                
                agent._currentStrafeDest = strafeDest
                hum.WalkSpeed = 18
                hum:MoveTo(strafeDest)
                
                 -- Jump occasionally while strafing for variation
                if math.random() < 0.3 then
                    hum.Jump = true
                end
                
                return false -- Start moving
            end

            -- Check arrival
            local hrp = agent.Instance:FindFirstChild("HumanoidRootPart")
            if not hrp then return true end
            local dist = (hrp.Position - agent._currentStrafeDest).Magnitude
            if dist < 4 then
                 agent._currentStrafeDest = nil
                 agent.lastStrafeTime = os.clock() -- Set cooldown
                 return true -- Done
            end
            
            -- Keep moving (refresh in case of friction)
            hum:MoveTo(agent._currentStrafeDest)
            
            return false
        end,
        onInterrupt = function(agent)
             agent._currentStrafeDest = nil
        end
    })

    local wanderAction = Goal.Action.new({
        name = "Roam",
        cost = 1, -- Cheaper than Idle
        preconditions = {},
        effects = { isRoaming = true },
        executeFn = function(agent)
            local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
            local hrp = agent.Instance:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp then return true end
            
            local startPos = hrp.Position
            
            -- If we don't have a wander target, find one
            if not agent._wanderTarget or (startPos - agent._wanderTarget).Magnitude < 4 then
                local angle = math.random() * math.pi * 2
                local dist = math.random(15, 30)
                local offset = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
                agent._wanderTarget = startPos + offset
                
                -- Verify it's walkable (simple raycast down)
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Include
                -- Check against workspace to be safe, filter descendants if needed
                params.FilterDescendantsInstances = {workspace} 
                
                -- Random Jump while roaming
                if math.random() < 0.2 then
                    hum.Jump = true
                end

                agent._wanderTarget = startPos + offset
            end
            
            hum:MoveTo(agent._wanderTarget)
            agent.lastRoamTime = os.clock()
            return false -- Keep wandering until interrupted or reached
        end,
        onInterrupt = function(agent)
            agent._wanderTarget = nil
            agent.lastRoamTime = os.clock()
        end
    })

    local retreatAction = Goal.Action.new({
        name = "Retreat",
        cost = 1,
        preconditions = {
            isLowHealth = true,
            hasTarget = true
        },
        effects = {
            safeFromTarget = true
        },
        executeFn = function(agent)
            local target = agent.State:get("target")
            if not target then return true end
            
            local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
            local hrp = agent.Instance:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp then return true end
            
            local startPos = hrp.Position
            local targetPos = target.PrimaryPart.Position
            
            -- Use a path cache for retreat to avoid jank
            local now = os.clock()
            local targetMoved = agent._lastRetreatTargetPos and (targetPos - agent._lastRetreatTargetPos).Magnitude > 10
            local pathExpired = (now - (agent._lastRetreatPathUpdate or 0)) > 1.0 -- Update flee path less often
            local noPath = not agent._cachedRetreatPath or not agent._cachedRetreatPath.pathFound
            
            if noPath or pathExpired or targetMoved then
                local fleePath = agent.Navigation:findFleePath(startPos, {targetPos}, 60) -- Increased distance
                if fleePath.pathFound then
                    agent._cachedRetreatPath = fleePath
                    agent._lastRetreatPathUpdate = now
                    agent._lastRetreatTargetPos = targetPos
                    agent._retreatWaypointIndex = 2 -- Skip start
                end
            end
            
            if agent._cachedRetreatPath and agent._cachedRetreatPath.pathFound then
                local waypoints = agent._cachedRetreatPath.waypoints
                if agent._retreatWaypointIndex <= #waypoints then
                    local wpPos = waypoints[agent._retreatWaypointIndex]
                    local distToWp = (startPos - wpPos).Magnitude
                    
                    if distToWp < 5 then
                        agent._retreatWaypointIndex = agent._retreatWaypointIndex + 1
                    end
                    
                    if agent._retreatWaypointIndex <= #waypoints then
                        hum.WalkSpeed = 22
                        local movePos = waypoints[agent._retreatWaypointIndex]
                        -- Add separation during retreat too
                        local separation = agent:GetSeparationVector(10)
                        hum:MoveTo(movePos + (separation * 4))
                    end
                else
                    -- Reached end of flee path
                    local dir = (startPos - targetPos).Unit
                    hum:MoveTo(startPos + dir * 20)
                end
            else
                -- Fallback: just move away
                local dir = (startPos - targetPos).Unit
                hum:MoveTo(startPos + dir * 20)
            end
            
            -- Check if we are safe (matches Mob.lua hysteresis threshold)
            if (startPos - targetPos).Magnitude > 60 then
                return true -- Successfully retreated
            end
            
            return false
        end,
        onInterrupt = function(agent)
            local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.WalkSpeed = 16
            end
            agent._cachedRetreatPath = nil
        end
    })

    local circleAction = Goal.Action.new({
        name = "CircleTarget",
        cost = 5, -- More expensive than chasing directly
        preconditions = {
            hasTarget = true,
            canSeePlayer = true
        },
        effects = {
            isCircling = true
        },
        executeFn = function(agent)
            local target = agent.State:get("target")
            if not target then return true end
            
            local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
            local hrp = agent.Instance:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp then return true end
            
            local startPos = hrp.Position
            local targetPos = target.PrimaryPart.Position
            
            -- Maintain a distance of ~18-22 studs while circling
            local desiredDist = 20
            
            -- Dynamic angle based on ID and time for variety
            local idHash = tonumber(string.sub(agent.Id, 1, 1), 16) or 0
            local timeScale = 0.3 + (idHash % 5) * 0.1
            local angleOffset = os.clock() * timeScale
            
            if idHash % 2 == 0 then
                angleOffset = -angleOffset
            end
            
            local dirToTarget = (startPos - targetPos).Unit
            local baseAngle = math.atan2(dirToTarget.Z, dirToTarget.X)
            
            -- Add a "pulse" to the distance to make movement less circular and more organic
            local pulse = math.sin(os.clock() * 2) * 5
            local currentDesiredDist = desiredDist + pulse
            
            local circleAngle = baseAngle + (if idHash % 2 == 0 then 0.4 else -0.4)
            
            local circlePos = targetPos + Vector3.new(
                math.cos(circleAngle) * currentDesiredDist,
                0,
                math.sin(circleAngle) * currentDesiredDist
            )
            
            -- Add separation
            local separation = agent:GetSeparationVector(12)
            hum.WalkSpeed = 15
            hum:MoveTo(circlePos + (separation * 6))
            
            return false -- Keep circling
        end,
        onInterrupt = function(agent)
            local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.WalkSpeed = 16
            end
        end
    })

    local flankAction = Goal.Action.new({
        name = "FlankTarget",
        cost = 4,
        preconditions = {
            hasTarget = true,
            canSeePlayer = true
        },
        effects = {
            isFlanking = true
        },
        executeFn = function(agent)
            local target = agent.State:get("target")
            if not target then return true end
            
            local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
            local hrp = agent.Instance:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp then return true end
            
            local startPos = hrp.Position
            local targetPos = target.PrimaryPart.Position
            
            -- If we have a current flank destination, check if we reached it
            if agent._currentFlankDest then
                local dist = (startPos - agent._currentFlankDest).Magnitude
                if dist < 5 then
                    -- Reached flank position
                    agent._currentFlankDest = nil
                    agent.lastFlankTime = os.clock() -- Set cooldown
                    return true -- Success
                end
                
                -- Keep moving to it
                hum.WalkSpeed = 20
                hum:MoveTo(agent._currentFlankDest)
                return false
            end
            
            -- CALCULATE NEW FLANK DESTINATION
            local targetFacing = target.PrimaryPart.CFrame.LookVector
            
            -- Use ID to pick a consistent but varied flank side
            local idHash = tonumber(string.sub(agent.Id, 1, 1), 16) or 0
            local preferLeft = idHash % 2 == 0
            
            -- Coordination: Check if our preferred side is already "claimed" on the blackboard
            local sideKey = string.format("target_%s_%s", target.Name, preferLeft and "left" or "right")
            if agent.Blackboard:isClaimed(sideKey) and agent.Blackboard:getClaimant(sideKey) ~= agent.Id then
                preferLeft = not preferLeft
                sideKey = string.format("target_%s_%s", target.Name, preferLeft and "left" or "right")
            end
            
            -- Claim this side for 5 seconds (enough to complete action)
            agent.Blackboard:claim(sideKey, agent.Id)
            
            -- Get flank positions from Navigation system
            local flankPositions = agent.Navigation:getFlankPositions(targetPos, 25, targetFacing)
            
            if #flankPositions > 0 then
                -- Filter and sort based on our ID-driven preference
                table.sort(flankPositions, function(a, b)
                    local aDir = (a.position - targetPos).Unit
                    local bDir = (b.position - targetPos).Unit
                    local targetRight = target.PrimaryPart.CFrame.RightVector
                    local aDot = aDir:Dot(targetRight)
                    local bDot = bDir:Dot(targetRight)
                    
                    local aSideScore = preferLeft and -aDot or aDot
                    local bSideScore = preferLeft and -bDot or bDot
                    
                    return (aSideScore + a.advantage) > (bSideScore + b.advantage)
                end)
                
                local bestPos = flankPositions[1].position
                agent._currentFlankDest = bestPos + agent:GetSeparationVector(10) * 5
                
                hum.WalkSpeed = 20
                hum:MoveTo(agent._currentFlankDest)
                return false -- Started flanking
            else
                -- Fallback to direct approach if no flank found
                hum:MoveTo(targetPos)
                return true -- Fail cleanly so we pick another action
            end
        end,
        onInterrupt = function(agent)
            local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.WalkSpeed = 16
            end
            agent._currentFlankDest = nil
        end
    })

    local moveAction = Goal.Action.new({
        name = "Chase",
        cost = 1,
        preconditions = {
            hasTarget = true
        },
        effects = {
            targetInMeleeRange = true
        },
        executeFn = function(agent)
            local target = agent.State:get("target")
            if not target then 
                -- Clear cached path if no target
                agent._cachedPath = nil
                return false 
            end

            local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
            local hrp = agent.Instance:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp then return true end
     

            local startPos = hrp.Position
            local targetPos = target.PrimaryPart.Position
            local dist = (startPos - targetPos).Magnitude
            
            -- Speed variation based on distance
            if dist > 40 then
                hum.WalkSpeed = 24 -- Sprint when far
            elseif dist < 15 then
                hum.WalkSpeed = 16 -- Normal speed when close
            else
                hum.WalkSpeed = 20 -- Fast chase
            end

            -- Check if we're close enough to attack
            if dist < 5 then
                hum:MoveTo(startPos) -- Stop moving
                agent.State:set("targetInMeleeRange", true)
                agent._cachedPath = nil -- Clear path
                return true -- Reached destination
            end
            
            agent.State:set("targetInMeleeRange", false)
            
            -- DIRECT PURSUIT: If we have line of sight, just move to the player
            -- This is much smoother than pathfinding waypoints when in the open
            local canSee = agent.State:get("canSeePlayer")
            
            -- [ENHANCED JUMP LOGIC]
            -- Check for elevated terrain and vertical gaps
            local myPos = agent.Instance.PrimaryPart.Position
            local lookDir = agent.Instance.PrimaryPart.CFrame.LookVector
            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = {agent.Instance}
            rayParams.FilterType = Enum.RaycastFilterType.Exclude
            
            -- Check for ground directly in front
            local floorRay = workspace:Raycast(myPos + (lookDir * 5), Vector3.new(0, -10, 0), rayParams)
            if not floorRay then
                -- Gap detected! Jump to clear it.
                hum.Jump = true
            end

            local lowRay = workspace:Raycast(myPos - Vector3.new(0, 2, 0), lookDir * 4, rayParams)
            if lowRay then
                -- Obstacle low? Check high for vaulting
                local highRay = workspace:Raycast(myPos + Vector3.new(0, 1, 0), lookDir * 4, rayParams)
                if not highRay then
                    hum.Jump = true
                elseif (dist < 15) then
                    -- If very close and blocked, try to jump/climb
                    hum.Jump = true
                end
            end

            if canSee then
                -- Add a "swerve" or "arc" to the movement to avoid being a straight line
                local idHash = tonumber(string.sub(agent.Id, 1, 1), 16) or 0
                local swerveAmount = math.sin(os.clock() * 1.5 + idHash) * 8
                
                local rightVec = hrp.CFrame.RightVector
                
                local separation = agent:GetSeparationVector(8)
                local movePos = targetPos + (separation * 5) + (rightVec * swerveAmount)
                hum:MoveTo(movePos)
                agent._cachedPath = nil -- Clear path as we're not using waypoints
                return false
            end

            -- PATHFINDING: Use Roblox Pathfinding when LOS is lost
            local now = os.clock()
            local targetMoved = agent._lastTargetPosition and (targetPos - agent._lastTargetPosition).Magnitude > 8
            local pathExpired = (now - agent._lastPathUpdate) > 0.8 -- Slightly slower update for pathfinding
            local noPath = not agent._cachedPath or not agent._cachedPath.success
            
            if noPath or pathExpired or targetMoved then
                -- Use the higher-quality Roblox PathfindingAdapter
                local pathResult = agent.Pathfinder:findPath(startPos, targetPos)
                
                if pathResult and pathResult.success and #pathResult.waypoints > 0 then
                    agent._cachedPath = pathResult
                    agent._lastPathUpdate = now
                    agent._lastTargetPosition = targetPos
                    
                    -- Start from the second waypoint (first is start position)
                    agent._currentWaypointIndex = math.min(2, #pathResult.waypoints)
                else
                    -- Fallback to grid navigation if pathfinding fails
                    local gridPath = agent.Navigation:findPath(startPos, targetPos)
                    if gridPath and gridPath.pathFound then
                        agent._cachedPath = {
                            success = true,
                            waypoints = gridPath.waypoints
                        }
                        agent._currentWaypointIndex = 1
                    end
                end
            end
            
            -- Use cached path to navigate
            if agent._cachedPath and agent._cachedPath.success and agent._cachedPath.waypoints then
                local waypoints = agent._cachedPath.waypoints
                
                if agent._currentWaypointIndex <= #waypoints then
                    local currentWaypoint = waypoints[agent._currentWaypointIndex]
                    local waypointPos = typeof(currentWaypoint) == "Vector3" and currentWaypoint or currentWaypoint.Position
                    local waypointDist = (startPos - waypointPos).Magnitude
                    
                    -- Check for jumping required by waypoint
                    if typeof(currentWaypoint) == "table" and currentWaypoint.Action == Enum.PathWaypointAction.Jump then
                        hum.Jump = true
                    end

                    if waypointDist < 4.0 then
                        agent._currentWaypointIndex = agent._currentWaypointIndex + 1
                    end
                    
                    if agent._currentWaypointIndex <= #waypoints then
                        local targetWaypoint = waypoints[agent._currentWaypointIndex]
                        local targetWaypointPos = typeof(targetWaypoint) == "Vector3" and targetWaypoint or targetWaypoint.Position
                        
                        local separation = agent:GetSeparationVector(8)
                        hum:MoveTo(targetWaypointPos + (separation * 4))
                    else
                        local separation = agent:GetSeparationVector(8)
                        hum:MoveTo(targetPos + (separation * 4))
                    end
                else
                    local separation = agent:GetSeparationVector(8)
                    hum:MoveTo(targetPos + (separation * 4))
                end
            else
                -- Fallback: move towards target
                local separation = agent:GetSeparationVector(8)
                hum:MoveTo(targetPos + (separation * 4))
            end
            
            return false -- Still moving
        end,
        onInterrupt = function(agent)
            -- Reset speed when stopped/interrupted
            local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.WalkSpeed = 16
            end
            -- Clear cached path so it recalculates next time
            agent._cachedPath = nil
            agent._currentWaypointIndex = 1
        end,
    })

	local meleeAttackAction = Goal.Action.new({
		name = "Attack",
		cost = 5, -- High cost = do only if necessary
		preconditions = { 
			targetInMeleeRange = true, -- Needs this state to be true

		}, 
		effects = { 
			targetDead = true -- This action achieves 'targetDead'
		},
		cooldownTime = 1.8,
		executeFn = function(agent)
			local target = agent.State:get("target")
			if not target then return false end

			local hrp = agent.Instance:FindFirstChild("HumanoidRootPart")
			if not hrp then return true end

			local dist = (hrp.Position - target.PrimaryPart.Position).Magnitude
			if dist > 8 then 
                agent.State:set("targetInMeleeRange", false)

                return false end -- Too far to attack

			-- trigger MobPunch skill via WCS
            local skill = agent.WCSCharacter:GetSkillFromString("MobPunch")
            if skill then
                skill:Start()
            end

			return true
		end,
	})

    local rangedAttackAction = Goal.Action.new({
        name = "Shoot",
        cost = 5, -- Lower cost than melee to encourage shooting
        preconditions = {
            hasTarget = true,
            canSeePlayer = true,
            canRangedAttack = true
        },
        effects = {
            targetDead = true
        },
        executeFn = function(agent)
            local target = agent.State:get("target")
            if not target then return true end

            -- [Precise Raycast Check]
            -- Ensure we actually have a clean shot before firing
            local origin = agent.Instance.PrimaryPart.Position
            local targetPos = target.PrimaryPart.Position
            local dir = targetPos - origin
            
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {agent.Instance}
            
            local result = workspace:Raycast(origin, dir, params)
            
            -- If we hit something that ISN'T the target (or a descendant of it)
            if result and result.Instance and not result.Instance:IsDescendantOf(target) then
                -- Check if it's transparent/can be shot through? For now, strict check.
                 if result.Instance.Transparency < 0.5 and result.Instance.CanCollide then
                    return false -- Shot blocked, fail action
                 end
            end
            
            local skill = agent.WCSCharacter:GetSkillFromString("EnemyProjectile")
            if skill and not skill:GetState().Debounce then
                -- Use Prediction: Aim where the player is going
                local targetHRP = target:FindFirstChild("HumanoidRootPart")
                local targetHum = target:FindFirstChild("Humanoid")
                
                targetPos = targetHRP.Position -- Reset to actual position
                if targetHum and targetHum.MoveDirection.Magnitude > 0 then
                    -- Enhanced prediction: account for player speed and projectile travel time
                    local hrp = agent.Instance:FindFirstChild("HumanoidRootPart")
                    if not hrp then return true end
                    
                    local dist = (hrp.Position - targetPos).Magnitude
                    local bulletSpeed = 150 -- Fallback to default projectile speed
                    local travelTime = dist / bulletSpeed
                    
                    -- Project player position forward
                    local velocity = targetHum.MoveDirection * targetHum.WalkSpeed
                    targetPos = targetPos + (velocity * travelTime)
                    
                    -- Second pass for better accuracy if target is far
                    if dist > 50 then
                        local newDist = (hrp.Position - targetPos).Magnitude
                        local newTravelTime = newDist / bulletSpeed
                        targetPos = targetHRP.Position + (velocity * newTravelTime)
                    end
                end
                
                skill:Start(targetPos)
            end
            
            return true 
        end
    })

    local investigateAction = Goal.Action.new({
        name = "Investigate",
        cost = 2, -- Cheaper than Idle, more expensive than Chase
        preconditions = {
            -- Implicitly requires investigatePos to exist in state, but Goal check handles it
        },
        effects = {
            investigated = true
        },
        executeFn = function(agent)
             local pos = agent.State:get("investigatePos")
             if not pos then return true end -- Done/Invalid
             
             local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
             local hrp = agent.Instance:FindFirstChild("HumanoidRootPart")
             if not hum or not hrp then return true end
             
             local startPos = hrp.Position
             
             local dist = (startPos - pos).Magnitude
             if dist < 5 then
                 agent.State:set("investigatePos", nil) -- Arrived
                 return true
             end
             
             -- Move to investigation point
             hum.WalkSpeed = 20 -- Run to investigate
             hum:MoveTo(pos)
             return false
        end,
        onInterrupt = function(agent)
            local hum = agent.Instance:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.WalkSpeed = 16
            end
        end
    })

	-- Register them to the Brain
	self.Planner:registerAction(idleAction)
    self.Planner:registerAction(wanderAction)
    self.Planner:registerAction(circleAction)
    self.Planner:registerAction(flankAction)
    self.Planner:registerAction(retreatAction)
	self.Planner:registerAction(meleeAttackAction)
    self.Planner:registerAction(rangedAttackAction)
	self.Planner:registerAction(moveAction)
    self.Planner:registerAction(strafeAction)
    self.Planner:registerAction(investigateAction)



	-- 2. DEFINE GOALS (Desires)
	-- "I want [DesiredState] with [Priority]"
	
	self.IdleGoal = Goal.Goal.new({
		name = "JustChill",
		priority = 1, -- Low priority
		desiredState = { isIdling = true },
	})
    
    self.RoamGoal = Goal.Goal.new({
        name = "RoamAround",
        priority = 2, -- Higher priority than Idle to force roaming
        desiredState = { isRoaming = true },
        isValidFn = function(state)
            local now = os.clock()
            local cooldown = 8 -- Roam every 8 seconds (allows for Idle time)
            return (now - (self.lastRoamTime or 0) > cooldown)
        end
    })
	
    self.RetreatGoal = Goal.Goal.new({
        name = "Survive",
        priority = 15, -- Highest priority
        desiredState = { safeFromTarget = true },
        isValidFn = function(state)
            return state:get("isLowHealth") and state:get("hasTarget")
        end
    })

    self.FlankGoal = Goal.Goal.new({
        name = "TacticalFlank",
        priority = 12, -- Higher than Kill (10) so we flank occasionally
        desiredState = { isFlanking = true },
        isValidFn = function(state)
            local dist = state:get("distToPlayer") or 0
            local now = os.clock()
            local cooldown = 10 -- Flank every 10 seconds
            
            -- Only flank if at a reasonable distance, not too close, and off cooldown
            return state:get("canSeePlayer") 
                and dist > 25 and dist < 60 
                and not state:get("isLowHealth")
                and (now - (self.lastFlankTime or 0) > cooldown)
        end
    })

    self.CircleGoal = Goal.Goal.new({
        name = "TacticalCircle",
        priority = 5,
        desiredState = { isCircling = true },
        isValidFn = function(state)
            -- Only circle if we can see the player, aren't in melee range, and aren't low health
            return state:get("canSeePlayer") 
                and not state:get("targetInMeleeRange") 
                and not state:get("isLowHealth")
                and (state:get("distToPlayer") or 0) > 10 -- Only circle if not already very close
        end
    })

    self.CombatStrafeGoal = Goal.Goal.new({
        name = "CombatStrafe",
        priority = 12, -- Higher than Kill (10)
        desiredState = { isStrafing = true },
        isValidFn = function(state)
            local dist = state:get("distToPlayer") or 0
            local now = os.clock()
            local cooldown = 4 -- Strafe every 4 seconds
            
            return state:get("canSeePlayer") 
                and dist > 10 and dist < 40 
                and not state:get("isLowHealth")
                and (now - (self.lastStrafeTime or 0) > cooldown)
        end
    })


    self.InvestigateGoal = Goal.Goal.new({
        name = "InvestigateNoise",
        priority = 11, -- High priority, GREATER than Kill (10) to force checking last known position (RoR2 Style)
        desiredState = { investigated = true },
        isValidFn = function(state)
            return state:get("investigatePos") ~= nil and not state:get("hasTarget")
        end
    })

	self.KillGoal = Goal.Goal.new({
		name = "KillTarget",
		priority = 10, -- High priority (overrides Idle)
		desiredState = { targetDead = true },
	})
end

-- [DYNAMIC GOAL SELECTION]
-- Which goals are active right now?
function Template:GetGoals()
	local goals = { self.IdleGoal }
	
	-- Only want to kill if we have a target
	if self.State:get("hasTarget") then
        if self.State:get("isLowHealth") then
            table.insert(goals, self.RetreatGoal)
        else
            table.insert(goals, self.KillGoal)
            table.insert(goals, self.CircleGoal)
            table.insert(goals, self.FlankGoal)
            table.insert(goals, self.CombatStrafeGoal)
        end
    else
        -- If no target, check if we should investigate
        if self.State:get("investigatePos") then
             table.insert(goals, self.InvestigateGoal)
        else
             -- If nothing else, roam
             table.insert(goals, self.RoamGoal)
        end
	end
	
	return goals
end

return Template 