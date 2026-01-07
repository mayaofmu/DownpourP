local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)

local Kunai = WCS.RegisterSkill("Kunai")

function Kunai:OnStartServer(Target: any)
	-- Target is the WCS Character we hit, passed from ItemSystem
	if not Target then return end
	
	if typeof(Target) == "Instance" then
		Target = WCS.Character.GetCharacterFromInstance(Target)
	end
	
	local char = self.Character
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	local inventory = DamagePipeline.GetInventory(char)
	
	local count = inventory and inventory:GetCount("Kunai") or 1
	
	-- Logic: 80% Base Damage (+50% per stack)
	local damageMult = 0.8 + (0.5 * (count - 1))
	local procCoeff = 1.0 -- Kunais can proc things? Maybe 0 to prevent infinite chains if we want.
	
	-- We could spawn a physical projectile here, or just instant damage since it's a "proc"
	-- For visual flair, let's spawn a projectile that seeks the target or just hit instantly.
	-- Since OnStartServer handles logic, we deal damage here.
	
	DamagePipeline.DealDamage(char, Target, damageMult, procCoeff, "Generic")
end

function Kunai:OnStartClient(Target)
	-- Visuals
	-- Play sound
	-- Show flying Kunai effect hitting the target
end

return Kunai

