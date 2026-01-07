local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)
local StatusEffects = require(ReplicatedStorage.Core.StatusEffects)

local Sprint = WCS.RegisterHoldableSkill("Sprint")

function Sprint:OnStartServer()
	local char = self.Character
	
	-- Apply Sprinting Status Effect
	local sprintBuff = char:GetAllActiveStatusEffectsOfType(StatusEffects.SprintBuff)[1]
	if not sprintBuff then
		local buff = StatusEffects.SprintBuff.new(char)
		buff:Start()
	end
end

function Sprint:OnEndServer()
	local char = self.Character
	
	local sprintBuff = char:GetAllActiveStatusEffectsOfType(StatusEffects.SprintBuff)[1]
	if sprintBuff then
		sprintBuff:Stop()
	end
end

return Sprint

