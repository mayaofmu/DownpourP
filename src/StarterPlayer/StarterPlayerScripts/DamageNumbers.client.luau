local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local NetRay = require(ReplicatedStorage.Modules.NetRay)

local DamageEvent = NetRay:GetEvent("DamageEvent")

local RNG = Random.new()

-- Configuration
local CONFIG = {
	LifeTime = .8,
	DriftSpeed = 2,
	Gravity = 33, -- Increased gravity significantly to force falling
	PopForce = 7, -- Increased initial upward force to compensate slightly before fall
	Spread = 17, 
	
	NormalColor = Color3.fromRGB(255, 255, 255),
	CritColor = Color3.fromRGB(255, 255, 0), -- Yellow
	HealColor = Color3.fromRGB(50, 255, 50), -- Green
	
	NormalScale = 0.45, 
	CritScale = 1,
	HealScale = 0.3,
}

local function FlashCharacter(character)
	if not character then return end
	
	-- Only flash if not already flashing
	if character:GetAttribute("IsFlashing") then return end
	character:SetAttribute("IsFlashing", true)
	
	local parts = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			parts[part] = part.Color
		end
	end
	
	-- Flash Red
	for part, _ in pairs(parts) do
		part.Color = Color3.fromRGB(255, 100, 100)
	end
	
	task.delay(0.1, function()
		for part, originalColor in pairs(parts) do
			if part.Parent then
				part.Color = originalColor
			end
		end
		character:SetAttribute("IsFlashing", nil)
	end)
end

local function CreateDamageNumber(data)
	local amount = data.Amount
	local pos = data.Position + Vector3.new(0, 3, 0) -- Hover above
	local isCrit = data.Crit
	local type = data.Type or "Generic" -- "Generic" or "Heal"
	local target = data.Target
	
	if target and type ~= "Heal" then
		FlashCharacter(target)
	end
	
	-- Randomize start pos slightly to avoid overlap
	local offset = Vector3.new(
		RNG:NextNumber(-1, 1),
		RNG:NextNumber(-1, 1),
		RNG:NextNumber(-1, 1)
	) * 0.5
	
	local startPos = pos + offset
	
	-- Create UI
	local bb = Instance.new("BillboardGui")
	bb.Name = "DamageNumber"
	bb.Adornee = nil -- We will set WorldPosition manually if we want, or just Adornee to an invisible part. 
	-- Actually, for smooth movement independent of the target, we should use a Part or just update StudsOffset if Adornee is set.
	-- But Adornee might move/die. Better to use a temporary Part or just WorldPosition?
	-- BillboardGui doesn't have WorldPosition. It needs an Adornee (Part/Attachment) or Parent to a Part.
	-- Best approach: Create a temporary transparent Part anchored at the location.
	
	local part = Instance.new("Part")
	part.Name = "DamageNumAnchor"
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = startPos
	part.Parent = workspace.Terrain
	
	bb.Adornee = part
	bb.Size = UDim2.new(0, 200, 0, 50)
	bb.AlwaysOnTop = true
	bb.Parent = part
	
	local label = Instance.new("TextLabel") 
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	
	if type == "Heal" then
		label.Text = "+" .. tostring(amount)
		label.TextColor3 = CONFIG.HealColor
	else
		label.Text = tostring(amount)
		label.TextColor3 = isCrit and CONFIG.CritColor or CONFIG.NormalColor
	end
	
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = bb
	
	-- Initial State
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	
	-- Animation Physics
	-- 45 degree cone upwards: Y > abs(X) + abs(Z) roughly
	local angle = RNG:NextNumber() * math.pi * 2
	local radius = RNG:NextNumber(0, 1)
	local x = math.cos(angle) * radius * CONFIG.Spread
	local z = math.sin(angle) * radius * CONFIG.Spread
	local y = CONFIG.PopForce + RNG:NextNumber(0, 5) 
	
	local velocity = Vector3.new(x, y, z)
	
	local scale
	if type == "Heal" then
		scale = CONFIG.HealScale
	else
		scale = isCrit and CONFIG.CritScale or CONFIG.NormalScale
	end
	
	bb.Size = UDim2.new(0, 200 * scale, 0, 50 * scale)
	
	-- Pop Animation (Tween Size)
	-- Start small
	label.Size = UDim2.fromScale(0, 0)
	label.Position = UDim2.fromScale(0.5, 0.5)
	
	local popTween = TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5)
	})
	popTween:Play()
	
	-- Physics Loop
	local t = 0
	local connection
	
	connection = RunService.Heartbeat:Connect(function(dt)
		t += dt
		if t >= CONFIG.LifeTime then
			connection:Disconnect()
			part:Destroy() -- Cleans up BB too
			return
		end
		
		-- Apply Gravity
		velocity = velocity - Vector3.new(0, CONFIG.Gravity * dt, 0)
		
		-- Apply Velocity
		part.Position = part.Position + (velocity * dt)
		
		-- Fade Out near end
		-- Fade starts at 50% life, moves up until end
		if t > CONFIG.LifeTime * 0.5 then
			local alpha = (t - (CONFIG.LifeTime * 0.5)) / (CONFIG.LifeTime * 0.5)
			label.TextTransparency = alpha
			label.TextStrokeTransparency = alpha
		end

		-- Shrink at 2/3rds life
		if t > CONFIG.LifeTime * (2/3) and not label:GetAttribute("Shrinking") then
			label:SetAttribute("Shrinking", true)
			local shrinkTween = TweenService:Create(label, TweenInfo.new(CONFIG.LifeTime * (1/3), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = UDim2.new(0, 0, 0, 0)
			})
			shrinkTween:Play()
		end
	end)
	
	Debris:AddItem(part, CONFIG.LifeTime + 0.5)
end

if DamageEvent then
	DamageEvent:OnEvent(function(data)
		CreateDamageNumber(data)
	end)
end

