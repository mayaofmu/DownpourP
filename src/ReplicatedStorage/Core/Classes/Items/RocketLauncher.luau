local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)

local RocketLauncher = WCS.RegisterSkill("RocketLauncher")

function RocketLauncher:OnStartServer(Target: any)
	if not Target then return end
	 
	local char = self.Character
	
	if typeof(Target) == "Instance" then
		Target = WCS.Character.GetCharacterFromInstance(Target)
	end
	
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	local ProjectileSystem = require(game:GetService("ServerScriptService").Systems.ProjectileSystem)
	local inventory = DamagePipeline.GetInventory(char)
	
	local count = inventory and inventory:GetCount("Rocket Launcher") or 1
	
	-- Logic:
	-- Base Damage: 250% (+150% stack) = 2.5 + 1.5 * (count - 1)
	local damageMult = 2.5 + (1.5 * (count - 1))
	local procCoeff = 1.0
	
	print(string.format("[ItemSkill] Rocket Launcher Proc! x%d (Mult: %.1f)", count, damageMult))
	
	local origin = char.Instance.HumanoidRootPart.Position + Vector3.new(0, 5, 0)
	local targetPos = Target.Instance.HumanoidRootPart.Position
	local direction = (targetPos - origin).Unit
	
	ProjectileSystem.FireProjectile({
		attacker = char, 
		origin = origin, 
		direction = direction, 
		speed = 60, 
		range = 100, 
		damageCoeff = damageMult, 
		procCoeff = procCoeff
	})
end

function RocketLauncher:OnStartClient(Target)
	print("Visuals: *Whoosh* (Rocket)")
end

return RocketLauncher
