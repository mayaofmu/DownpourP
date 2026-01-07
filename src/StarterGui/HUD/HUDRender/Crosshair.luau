local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local NetRay = require(ReplicatedStorage.Modules.NetRay)
local DamageEvent = NetRay:GetEvent("DamageEvent")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Crosshair = {}
Crosshair.__index = Crosshair

function Crosshair.new()
	local self = setmetatable({}, Crosshair)
	
	self:CreateUI()
	self:SetupConnections()
	
	return self
end

function Crosshair:CreateUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CrosshairHUD"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = PlayerGui
	
	-- Container for crosshair elements to ensure centering
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.fromOffset(40, 40)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.Parent = screenGui
	self.Container = container
	
	-- Standard Crosshair
	local hLine = Instance.new("Frame")
	hLine.Name = "HLine"
	hLine.Size = UDim2.new(0, 14, 0, 2)
	hLine.Position = UDim2.fromScale(0.5, 0.5)
	hLine.AnchorPoint = Vector2.new(0.5, 0.5)
	hLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	hLine.BorderSizePixel = 0
	hLine.Parent = container
	
	local vLine = Instance.new("Frame")
	vLine.Name = "VLine"
	vLine.Size = UDim2.new(0, 2, 0, 14)
	vLine.Position = UDim2.fromScale(0.5, 0.5)
	vLine.AnchorPoint = Vector2.new(0.5, 0.5)
	vLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	vLine.BorderSizePixel = 0
	vLine.Parent = container
	
	self.ScreenGui = screenGui
end

function Crosshair:ShowHitMarker()
	if not self.Container then return end

	local hitMarker = Instance.new("ImageLabel")
	hitMarker.Name = "HitMarker"
	hitMarker.BackgroundTransparency = 1
	-- Start small for pop effect
	hitMarker.Size = UDim2.fromOffset(12, 12)
	hitMarker.Position = UDim2.fromScale(0.5, 0.5)
	hitMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	hitMarker.Image = "rbxassetid://8797893157" 
	hitMarker.ImageColor3 = Color3.fromRGB(255, 255, 255)
	hitMarker.ZIndex = 2 
	hitMarker.Parent = self.Container
	
	-- Random rotation for variety
	hitMarker.Rotation = math.random(-25, 25)

	-- Animation: Quick pop and fade
	-- Max visibility duration: 0.13s
	local duration = 0.13
	local targetSize = UDim2.fromOffset(36, 36)
	
	-- Tween 1: Grow fast
	local growInfo = TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local growTween = TweenService:Create(hitMarker, growInfo, {
		Size = targetSize,
		ImageTransparency = 1 -- Fade out as it grows to the end
	})
	
	growTween:Play()
	
	task.delay(duration, function()
		if hitMarker then
			hitMarker:Destroy()
		end
	end)
end

function Crosshair:SetupConnections()
	if DamageEvent then
		DamageEvent:OnEvent(function(data)
			-- Check if we are the attacker
			if data.Attacker == Player then
				self:ShowHitMarker()
			end
		end)
	else
		warn("Crosshair: DamageEvent not found in NetRay")
	end
end

return Crosshair

