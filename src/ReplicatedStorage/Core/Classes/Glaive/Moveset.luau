local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)

local GlaiveCombat = require(script.Parent.Abilities.Glaive)
local Sprint = require(ReplicatedStorage.Core.Classes.Sprint)

local Moveset = WCS.CreateMoveset("Glaive", {
	GlaiveCombat,
	Sprint
})

-- Handle Glaive model creation and welding
Moveset.OnCharacterAdded:Connect(function(wcsChar)
	local char = wcsChar.Instance
	
	-- Only spawn the model on the server to ensure replication, or on client for local effects
	-- WCS OnCharacterAdded fires on both. Usually we spawn visuals on client or let server replicate.
	-- If it's a tool-like object, server-side spawning is usually preferred for hitbox consistency.
	local Assets = script.Parent:FindFirstChild("Assets")
	local GlaiveAsset = Assets and Assets:FindFirstChild("Glaive")
	print("Glaive asset found:", GlaiveAsset and GlaiveAsset.Name)
	if GlaiveAsset then
		local glaive = GlaiveAsset:Clone()
		glaive.Name = "Glaive"
		
		-- Find the correct hand to weld to
		local rightHand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
		if rightHand then
			glaive.Parent = char
			
			-- Use existing motor reference "Handle" in the MeshPart
			local meshPart = glaive:FindFirstChild("MeshPart")
			local motor = meshPart and meshPart:FindFirstChild("Handle")
			
			if motor and motor:IsA("Motor6D") then
				motor.Part0 = rightHand
				motor.Part1 = meshPart
			else
				-- Fallback if motor is missing
				local newMotor = Instance.new("Motor6D")
				newMotor.Name = "Handle"
				newMotor.Part0 = rightHand
				newMotor.Part1 = meshPart or glaive.PrimaryPart or glaive:FindFirstChildWhichIsA("BasePart")
				newMotor.C0 = CFrame.new(0, -1, 0)
				newMotor.Parent = meshPart or glaive.PrimaryPart
			end
		end
	end
end)

Moveset.OnCharacterRemoved:Connect(function(wcsChar)
	local char = wcsChar.Instance
	local glaive = char:FindFirstChild("Glaive")
	if glaive then
		glaive:Destroy()
	end
end)

return Moveset

