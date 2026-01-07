local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)

local Spear = WCS.RegisterSkill("Spear")

function Spear:OnStartServer(Target: any)
	if not Target then return end  
	
	if typeof(Target) == "Instance" then
		Target = WCS.Character.GetCharacterFromInstance(Target)
	end
	
	local char = self.Character
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	local inventory = DamagePipeline.GetInventory(char)
	
	local count = inventory and inventory:GetCount("Spear") or 1
	
	-- Logic: 20% Base Damage
	local damageMult = 0.20
	-- Proc Bleed
	
	DamagePipeline.DealDamage(char, Target, damageMult, 0, "Bleed")
end
  
function Spear:OnStartClient(Target)
end

return Spear
