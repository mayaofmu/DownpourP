local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)
local RunService = game:GetService("RunService")

local FireBolt = require(script.Parent.Abilities.FireBolt)
local Sprint = require(ReplicatedStorage.Core.Classes.Sprint)

local Moveset = WCS.CreateMoveset("EnergyBlaster", {
	FireBolt,  
	Sprint
})

local function AttachItem(char: Instance, asset: Model)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if not hrp then return end

	local rightHand = char:WaitForChild("RightHand", 5)
	if not rightHand then return end

	local clone = asset:Clone()
	clone.Parent = char

	-- Prefer a part named "Handle"
	local handle = clone.PrimaryPart or clone:FindFirstChild("Handle", true) or clone:FindFirstChildWhichIsA("BasePart", true)

	if handle then
		-- Ensure all parts are unanchored so they move with the Motor6D
		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end

		local motor = handle:FindFirstChild("Motor6D") or Instance.new("Motor6D")
		motor.Name = "HandleMotor"
		motor.Part0 = rightHand
		motor.Part1 = handle
		motor.Parent = handle

		-- Adjust orientation if needed. Blaster might need a different Grip than Glaive.
		-- Defaulting to identity for now as requested "same must be done".
	else
		warn("Blaster asset has no Handle/BasePart!")
	end

	return clone
end

local spawnedItems = {}

Moveset.OnCharacterAdded:Connect(function(char)
	if not RunService:IsServer() then return end

	local instance = char.Instance
	if not instance then return end

	-- Spawn Blaster
	local blasterAsset = script.Parent.Assets.Blaster
	if blasterAsset then
		local item = AttachItem(instance, blasterAsset)
		if item then
			spawnedItems[instance] = item

			-- Ensure cleanup if character is destroyed without removing moveset
			char.Destroyed:Once(function()
				if spawnedItems[instance] then
					spawnedItems[instance]:Destroy()
					spawnedItems[instance] = nil
				end
			end)
		end
	end
end)

Moveset.OnCharacterRemoved:Connect(function(char)
	local instance = char.Instance
	if instance and spawnedItems[instance] then
		spawnedItems[instance]:Destroy()
		spawnedItems[instance] = nil
	end  
end)

return Moveset
