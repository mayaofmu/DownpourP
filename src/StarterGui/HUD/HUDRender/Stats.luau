local HUDScreenGui = script.Parent.Parent 
local _ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Stats = {}
Stats.__index = Stats

function Stats.new()
    local self = setmetatable({}, Stats)

    self.InfoFrame = HUDScreenGui:WaitForChild("Info")
    
    self.HealthBar = self.InfoFrame:WaitForChild("HealthBar")
    self.HealthAmount = self.InfoFrame:WaitForChild("HealthAmount")
    

    self.HealthBarBackground = self.InfoFrame:WaitForChild("HealthBarBG")

    self.LevelBar = self.InfoFrame:WaitForChild("LevelBar")
    self.LevelNumber = self.InfoFrame:FindFirstChild("LevelNumber")
    self.LevelBarBackground = self.InfoFrame:WaitForChild("LvlBarBG")

    self.MoneyFrame = HUDScreenGui:WaitForChild("Money")
    self.MoneyAmount = self.MoneyFrame:WaitForChild("Amount")
    
    self.StatsFrame = HUDScreenGui:WaitForChild("StatsFrame")
    self.StatsGrid = self.StatsFrame:WaitForChild("Stats") 
    
    self.LastCash = nil
    self.MoneyResetTask = nil
    
    self:StartUpdateLoop()
    
    return self 
end 

function Stats:AnimateMoney(gain, newTotal)
    if not self.MoneyAmount then return end

    -- Cancel existing reset task
    if self.MoneyResetTask then
        task.cancel(self.MoneyResetTask)
        self.MoneyResetTask = nil
    end
    
    -- Ensure UIStroke exists for glow
    local uiStroke = self.MoneyAmount:FindFirstChild("MoneyGlow")
    if not uiStroke then
        uiStroke = Instance.new("UIStroke")
        uiStroke.Name = "MoneyGlow"
        uiStroke.Parent = self.MoneyAmount
        uiStroke.Thickness = 2
        uiStroke.Color = Color3.fromRGB(255, 255, 192) -- Gold-ish
        uiStroke.Transparency = 1 -- Hidden by default
    end
    
    -- Capture original values if not set
    if not self.OriginalMoneySize then 
        self.OriginalMoneySize = self.MoneyAmount.Size 
    end
    if not self.OriginalTextColor then
        self.OriginalTextColor = self.MoneyAmount.TextColor3
    end

    -- Update Text with Gain
    self.MoneyAmount.Text = "$: " .. tostring(math.floor(newTotal)) .. " (+" .. tostring(math.floor(gain)) .. ")"
    self.MoneyAmount.TextColor3 = Color3.fromRGB(255, 255, 200) -- Lighter/Brighter

    -- Animate Size (Expand)
    local targetSize = UDim2.new(
        self.OriginalMoneySize.X.Scale * 1.2, 
        self.OriginalMoneySize.X.Offset, 
        self.OriginalMoneySize.Y.Scale * 1.2, 
        self.OriginalMoneySize.Y.Offset
    )
    
    -- Tween Size and Glow
    local expandTween = TweenService:Create(self.MoneyAmount, TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        Size = targetSize
    })
    local glowTween = TweenService:Create(uiStroke, TweenInfo.new(0.14), {
        Transparency = .4
    })
    
    expandTween:Play()
    glowTween:Play()
    
    -- Schedule Reset
    self.MoneyResetTask = task.delay(1.0, function()
        -- Reset Text
        self.MoneyAmount.Text = "$: " .. tostring(math.floor(newTotal))
        self.MoneyAmount.TextColor3 = self.OriginalTextColor or Color3.fromRGB(255, 255, 255)

        -- Reset Size
        local resetTween = TweenService:Create(self.MoneyAmount, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
            Size = self.OriginalMoneySize
        })
        -- Reset Glow
        local unGlowTween = TweenService:Create(uiStroke, TweenInfo.new(0.3), {
            Transparency = 1
        })
        
        resetTween:Play()
        unGlowTween:Play()
        
        self.MoneyResetTask = nil
    end)
end

function Stats:StartUpdateLoop()
    task.spawn(function()
        local player = Players.LocalPlayer
        while true do
            local character = player.Character
            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    -- Update Health
                    local health = humanoid.Health
                    local maxHealth = humanoid.MaxHealth
                    if self.HealthBar and self.HealthBarBackground then
                        local alpha = math.clamp(health / maxHealth, 0, 1)
                        self.HealthBar.Size = UDim2.new(
                            self.HealthBarBackground.Size.X.Scale * alpha,
                            self.HealthBarBackground.Size.X.Offset * alpha,
                            self.HealthBarBackground.Size.Y.Scale,
                            self.HealthBarBackground.Size.Y.Offset
                        )
                    end
                    if self.HealthAmount then
                        self.HealthAmount.Text = string.format("%d / %d", math.floor(health), math.floor(maxHealth))
                    end
                end
                
                -- Update Level & EXP
                local level = character:GetAttribute("Level") or 1
                local exp = character:GetAttribute("Exp") or 0
                local maxExp = character:GetAttribute("RequiredExp") or 100
                
                if self.InfoFrame then
                    for _, child in ipairs(self.InfoFrame:GetChildren()) do
                        if child.Name == "LevelNumber" and child:IsA("TextLabel") then
                            child.Text = tostring(level)
                        end 
                    end
                end
                
                if self.LevelBar and self.LevelBarBackground then
                    local alpha = math.clamp(exp / maxExp, 0, 1)
                    self.LevelBar.Size = UDim2.new(
                        self.LevelBarBackground.Size.X.Scale * alpha,
                        self.LevelBarBackground.Size.X.Offset * alpha,
                        self.LevelBarBackground.Size.Y.Scale,
                        self.LevelBarBackground.Size.Y.Offset
                    )
                end

                if self.MoneyAmount then
                    local cash = character:GetAttribute("Cash") or 0
                    
                    -- Initial Setup
                    if self.LastCash == nil then
                        self.LastCash = cash
                        self.OriginalMoneySize = self.MoneyAmount.Size
                        self.OriginalTextColor = self.MoneyAmount.TextColor3
                        self.MoneyAmount.Text = "$: " .. tostring(math.floor(cash))
                    end

                    if cash ~= self.LastCash then
                        if cash > self.LastCash then
                            self:AnimateMoney(cash - self.LastCash, cash)
                        else
                            -- Reset visuals if money decreases
                            if self.MoneyResetTask then
                                task.cancel(self.MoneyResetTask)
                                self.MoneyResetTask = nil
                                self.MoneyAmount.Size = self.OriginalMoneySize
                                self.MoneyAmount.TextColor3 = self.OriginalTextColor
                                local uiStroke = self.MoneyAmount:FindFirstChild("MoneyGlow")
                                if uiStroke then uiStroke.Transparency = 1 end
                            end
                            self.MoneyAmount.Text = "$: " .. tostring(math.floor(cash))
                        end
                        self.LastCash = cash
                    else
                        -- Only update text if not animating
                        if not self.MoneyResetTask then
                            self.MoneyAmount.Text = "$: " .. tostring(math.floor(cash))
                        end
                    end
                end
            end
            task.wait(0.1)
        end
    end)
end

function Stats:UpdateUI(stats)
    for name, value in pairs(stats) do
        local statLabel = self.StatsGrid:FindFirstChild(name)
        if statLabel then
            statLabel.Text = name .. ": " .. math.round(value.CachedValue*100)/100
        end
    end
end

return Stats