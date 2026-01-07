
local HUDScreenGui = script.Parent.Parent
local _ReplicatedStorage = game:GetService("ReplicatedStorage")

local _Players = game:GetService("Players")
local _TweenService = game:GetService("TweenService")
local Difficulty = {} 



Difficulty.__index = Difficulty

function Difficulty.new()
    local self = setmetatable({}, Difficulty)

    self.DifficultyFrame = HUDScreenGui:WaitForChild("Difficulty")
    self.DifficultyScrollingFrame = self.DifficultyFrame:WaitForChild("Scaling")

    -- ScrollingFrame is of CanvasSize {6, 0},{0, 0}  
    -- CanvasPosition of 100, 0 means that the scrollingframe will go from hovering over the very easy difficulty to the hard difficulty  

    -- Game has Easy, Normal, and Hard difficulty modifiers which shift difficulty scaling 
    self.Timer = self.DifficultyFrame:WaitForChild("Timer") 
    self.EnemyLvl = self.DifficultyFrame:WaitForChild("EnemyLvl") 
 
    self.Connections = {}

    table.insert(self.Connections, workspace.AttributeChanged:Connect(function(attr)
        if attr == "Timer" then

            local timerSeconds = math.floor(workspace:GetAttribute("Timer")) 
            local minutes = math.floor(timerSeconds / 60)
            local seconds = timerSeconds % 60

            self.Timer.Text = string.format("Timer: %02d:%02d", minutes, seconds)

        elseif attr == "EnemyLevel" then
            self.EnemyLvl.Text = "Enemy Lvl: " .. workspace:GetAttribute("EnemyLevel")
        elseif attr == "DifficultyCoefficient" then
            self.DifficultyScrollingFrame.CanvasPosition = Vector2.new(-100 + workspace:GetAttribute("DifficultyCoefficient") * 100, 0)                  
      end 
    end))

    -- Initial values
    self.Timer.Text = "Timer: " .. (workspace:GetAttribute("Timer") or 0)
    self.EnemyLvl.Text = "Enemy Level: " .. (workspace:GetAttribute("EnemyLevel") or 1)
    if workspace:GetAttribute("DifficultyCoefficient") then
        self.DifficultyScrollingFrame.CanvasPosition = Vector2.new(-100 + workspace:GetAttribute("DifficultyCoefficient") * 100, 0)
    end

    return self
end

function Difficulty:Destroy()
    for _, conn in ipairs(self.Connections) do
        conn:Disconnect()
    end
    self.Connections = {}
end

return Difficulty