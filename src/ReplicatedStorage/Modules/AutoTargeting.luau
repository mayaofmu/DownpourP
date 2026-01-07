local AutoTargeting = {}

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local DEFAULT_PARAMS = {
    Range = 25,
    Angle = 100, -- Degrees in front
    TeamCheck = true,
}

-- Return the best target Model or nil
function AutoTargeting.GetBestTarget(originCFrame, character, params)
    params = params or DEFAULT_PARAMS
    local range = params.Range or DEFAULT_PARAMS.Range
    local maxAngle = params.Angle or DEFAULT_PARAMS.Angle
    
    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Include
    
    local mobsFolder = workspace:FindFirstChild("Mobs")
    local filterList = {}
    if mobsFolder then
        table.insert(filterList, mobsFolder)
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and player.Character ~= character then
            table.insert(filterList, player.Character)
        end
    end
    
    if #filterList == 0 then return nil end
    
    overlapParams.FilterDescendantsInstances = filterList
    
    -- Broad phase: Get everything nearby
    local parts = workspace:GetPartBoundsInRadius(originCFrame.Position, range, overlapParams)
    
    local bestTarget = nil
    local bestScore = -math.huge 
    
    local processedModels = {}
    
    for _, part in ipairs(parts) do
        local model = part:FindFirstAncestorOfClass("Model")
        
        -- Basic Validation
        if model and model ~= character and not processedModels[model] then
            processedModels[model] = true
            
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local hrp = model:FindFirstChild("HumanoidRootPart")
            
            if humanoid and hrp and humanoid.Health > 0 then
                
                local dirToTarget = (hrp.Position - originCFrame.Position).Unit
                local lookDir = originCFrame.LookVector
                
                -- Angle Check (Dot Product)
                local dot = lookDir:Dot(dirToTarget)
                
                -- Optimization: Compare Dot Product directly against Cosine Threshold
                -- cos(angle) decreases as angle increases (0 to 180)
                -- So we want dot >= cos(halfAngle)
                local threshold = math.cos(math.rad(maxAngle / 2))
                
                if dot >= threshold then
                    -- Raycast for visibility (Line of Sight)
                    local rayParams = RaycastParams.new()
                    rayParams.FilterDescendantsInstances = {character, model}
                    rayParams.FilterType = Enum.RaycastFilterType.Exclude
                    
                    local dist = (hrp.Position - originCFrame.Position).Magnitude
                    local result = workspace:Raycast(originCFrame.Position, dirToTarget * (dist - 1), rayParams)
                    
                    if not result then
                        -- Score Calculation: 
                        -- Prioritize closer targets, but also favor those directly in front
                        -- Score = -Distance + (Dot * Factor) -> Reward being centered
                        
                        local angleBonus = (dot - threshold) * 10 -- Bonus for being dead center
                        local score = -dist + angleBonus
                        
                        if score > bestScore then
                            bestScore = score
                            bestTarget = model
                        end
                    end
                end
            end
        end
    end
    
    return bestTarget
end

return AutoTargeting
