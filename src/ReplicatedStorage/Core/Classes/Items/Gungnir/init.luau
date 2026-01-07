local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)

local Gungnir = WCS.RegisterSkill("Gungnir")

local Spear = script.Assets.spear

function Gungnir:OnConstruct()
	self.CheckOthersActive = false
	self.CheckedByOthers = false 
end


local Config = {
	Spread = 0.1, -- 10% Spread
}
function Gungnir:OnStartServer(TargetPos: Vector3, spearCount: number?)
	local char = self.Character
	local finalSpearCount: number = spearCount or 1
	
	-- Check for items in inventory to scale damage
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	local ProjectileSystem = require(game:GetService("ServerScriptService").Systems.ProjectileSystem)
	local inventory = DamagePipeline.GetInventory(char) 
	
	local count = inventory and inventory:GetCount("Gungnir") or 1
	local damageMult = 3.0 
	local procCoeff = 1.0 -- Standard for explosion
	
	local rng = Random.new()
	local spread = Vector3.new(
		(rng:NextNumber() - 0.5) * 2,
		(rng:NextNumber() - 0.5) * 2,
		(rng:NextNumber() - 0.5) * 2
	) * (Config.Spread / 2)

	for i = 1, finalSpearCount do
		-- Use the requested Random logic for offsets
		local offsetX = rng:NextInteger(-100, 100) / 40 -- Random X spread
		local offsetY = rng:NextInteger(-100, 100) / 100 -- Random height variation
		local offsetZ = rng:NextInteger(-100, 100) / 40 + 4 -- Position it behind/around character
		

		local xPositiveOrNegative = Random.new():NextInteger(0, 1) == 1 and 1.3 or -1

		local spawnX = (rng:NextInteger(10, 40) / 10) * xPositiveOrNegative
		local spawnY = rng:NextInteger(-25, 30) / 10
		local spawnZ = rng:NextInteger(45, 70) / 10
		local GungnirSpawnOffset = Vector3.new(spawnX, spawnY, spawnZ)
		local origin = (char.Instance.HumanoidRootPart.CFrame * CFrame.new(GungnirSpawnOffset).Position) + Vector3.new(0, 3, 0)
		local direction = (TargetPos - origin).Unit
			
	direction = (direction + spread).Unit
		
		local distance = (TargetPos - origin).Magnitude
		
		-- Fire Projectile with Custom Impact
		-- Fix orientation: Spear model points Up (Y+), but needs to point Forward (-Z)
		local modelOffset = CFrame.Angles(math.rad(-90), 0, 0)
		
		local function projectileFireEffect(projectile)
			local effects = projectile:FindFirstChild("Effects")
			if not effects then return end

			for _, effect in pairs(effects:GetChildren()) do
				if effect:IsA("ParticleEmitter") then
					local emitCount = effect:GetAttribute("EmitCount")
					effect:Emit(emitCount or 1)
				end
			end
		end

		ProjectileSystem.FireProjectile({
			attacker = char, 
			origin = origin, 
			direction = direction, 
			speed = 180, 
			range = distance + 5, 
			damageCoeff = damageMult, 
			procCoeff = procCoeff, 
			modelTemplate = Spear,
			onFire = projectileFireEffect,
			onImpact = function(result)
				-- Explosion Logic
				local hitPos = result.Position
				local radius = 12
				
				-- Area Damage
				local victims = {}
				local overlapParams = OverlapParams.new()
				overlapParams.FilterDescendantsInstances = {char.Instance}
				overlapParams.FilterType = Enum.RaycastFilterType.Exclude
				
				local hitTarget
				local parts = workspace:GetPartBoundsInRadius(hitPos, radius, overlapParams)
				for _, part in ipairs(parts) do
					local victimChar = part.Parent
					if victimChar and victimChar:FindFirstChild("Humanoid") and not victims[victimChar] then
						victims[victimChar] = true
						
						local targetWCS = WCS.Character.GetCharacterFromInstance(victimChar)
						if targetWCS then
							hitTarget = true 
							DamagePipeline.DealDamage(char, targetWCS, damageMult, procCoeff, "GungnirExplosion")
						else
							local hum = victimChar:FindFirstChild("Humanoid")
							if hum then
								hum:TakeDamage(10 * damageMult) -- Fallback
							end
						end
					end
					
				end

				return hitTarget
			end,
			modelOffset = modelOffset
		})
	end
end

function Gungnir:OnStartClient(Target)
end

return Gungnir
