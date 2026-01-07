local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)
local StatusEffects = require(ReplicatedStorage.Core.StatusEffects)

local CorrosiveBarrel = WCS.RegisterSkill("CorrosiveBarrel")

function CorrosiveBarrel:OnStartServer(Target: any)
	if not Target then return end
	
	if typeof(Target) == "Instance" then
		Target = WCS.Character.GetCharacterFromInstance(Target)
	end
	
	if Target then
		local effect = StatusEffects.Corrosion.new(Target)
		effect:Start(1) -- Apply 1 stack
	end
end

function CorrosiveBarrel:OnStartClient(Target)
end

return CorrosiveBarrel

