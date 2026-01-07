local CombatMovement = {}

-- Smoothly rotates the character to face a position
function CombatMovement.FacePosition(character, targetPos, duration)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    -- Clean up old movers
    local oldAlign = hrp:FindFirstChild("CombatAlignOrientation")
    if oldAlign then oldAlign:Destroy() end
    
    -- Setup Attachment
    local att = hrp:FindFirstChild("RootAttachment") or hrp:FindFirstChild("RootRigAttachment")
    if not att then return end
    
    local align = Instance.new("AlignOrientation")
    align.Name = "CombatAlignOrientation"
    align.Mode = Enum.OrientationAlignmentMode.OneAttachment
    align.Attachment0 = att
    align.RigidityEnabled = false
    align.MaxTorque = 200000 
    align.Responsiveness = 40 -- Reduced from 80 for smoother turn
    align.Parent = hrp
    
    local currentPos = hrp.Position
    local lookAt = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
    local goalCFrame = CFrame.lookAt(currentPos, lookAt)
    
    align.CFrame = goalCFrame
    
    task.delay(duration, function()
        if align and align.Parent then
            align:Destroy()
        end
    end)
end

-- Dashes towards a target using BodyVelocity (Respects Gravity)
function CombatMovement.DashToTarget(character, targetModel, options)
    options = options or {}
    local speed = options.Speed or 50
    local stopDist = options.StopDistance or 4
    local duration = options.Duration or 0.2
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local targetHrp = targetModel and targetModel:FindFirstChild("HumanoidRootPart")
    
    if not hrp or not targetHrp then return end
    
    -- Stop if too close (Magnetism Check)
    local dist = (targetHrp.Position - hrp.Position).Magnitude
    if dist <= stopDist then return end
    
    -- Remove old movers
    local oldBv = hrp:FindFirstChild("CombatDashVelocity")
    if oldBv then oldBv:Destroy() end

    -- Using BodyVelocity for the duration to ensure smooth slide without flying
    -- BodyVelocity allows us to set MaxForce.Y = 0 so gravity still applies!
    local bv = Instance.new("BodyVelocity")
    bv.Name = "CombatDashVelocity"
    
    local dir = (targetHrp.Position - hrp.Position).Unit
    bv.Velocity = Vector3.new(dir.X, 0, dir.Z).Unit * speed -- Force flat velocity
    
    bv.MaxForce = Vector3.new(150000, 0, 150000) -- Reduced from 400000 to feel less "locked"
    bv.P = 1500 -- Slightly reduced for smoothness
    bv.Parent = hrp
    
    task.delay(duration, function()
        if bv and bv.Parent then bv:Destroy() end
    end)
end

-- Dash in a specific direction
function CombatMovement.DashDirection(character, direction, options)
    options = options or {}
    local speed = options.Speed or 50
    local duration = options.Duration or 0.2
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local oldBv = hrp:FindFirstChild("CombatDashVelocity")
    if oldBv then oldBv:Destroy() end

    local bv = Instance.new("BodyVelocity")
    bv.Name = "CombatDashVelocity"
    
    -- Flatten direction
    local flatDir = Vector3.new(direction.X, 0, direction.Z)
    if flatDir.Magnitude > 0 then
        flatDir = flatDir.Unit
    end
    
    bv.Velocity = flatDir * speed
    bv.MaxForce = Vector3.new(150000, 0, 150000) -- Consistent with DashToTarget
    bv.P = 1250 -- Reduced P for stability
    bv.Parent = hrp
    
    task.delay(duration, function()
        if bv and bv.Parent then bv:Destroy() end
    end)
end

return CombatMovement
