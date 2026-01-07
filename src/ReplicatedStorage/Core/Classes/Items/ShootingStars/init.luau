local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)

local ShootingStars = WCS.RegisterSkill("ShootingStars")

local StarModel = script.Assets.Star -- Placeholder, assumes using Spear for now or user replaces it

function ShootingStars:OnConstruct()
	self.CheckOthersActive = false
	self.CheckedByOthers = false 
end

function ShootingStars:OnStartServer(Target: Instance | Vector3, starCount: number?)
	local TargetPos: Vector3
	
	if typeof(Target) == "Instance" then
		if Target:IsA("Model") then
			TargetPos = Target.PrimaryPart and Target.PrimaryPart.Position or Target:GetPivot().Position
		elseif Target:IsA("BasePart") then
			TargetPos = Target.Position
		end
	elseif typeof(Target) == "Vector3" then
		TargetPos = Target
	end
	
	if not TargetPos then return end

	local char = self.Character
	local finalStarCount: number = starCount or 1

	-- Check for items in inventory to scale damage
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	local ProjectileSystem = require(game:GetService("ServerScriptService").Systems.ProjectileSystem)
	local inventory = DamagePipeline.GetInventory(char) 

	local count = inventory and inventory:GetCount("ShootingStars") or 1
	local damageMult = 3.0 * count
	local procCoeff = 1.0 -- Standard for explosion

	local rng = Random.new()

	for i = 1, finalStarCount do
		-- Shooting Stars fall from the sky
		
		-- Destination: Around the target position
		local spread = 15
		local targetOffsetX = rng:NextNumber(-spread, spread)
		local targetOffsetZ = rng:NextNumber(-spread, spread)
		local destination = TargetPos + Vector3.new(targetOffsetX, 0, targetOffsetZ)

		-- Origin: High above, maybe slightly offset to give an angle
		local height = 120
		local skySpread = 40
		local skyOffsetX = rng:NextNumber(-skySpread, skySpread)
		local skyOffsetZ = rng:NextNumber(-skySpread, skySpread)
		local origin = TargetPos + Vector3.new(skyOffsetX, height, skyOffsetZ)

		local direction = (destination - origin).Unit
		local distance = (destination - origin).Magnitude

		-- Fix orientation: Model points Up (Y+), but needs to point Forward (-Z) relative to travel
		local modelOffset = CFrame.Angles(math.rad(-90), 0, 0)

		local function projectileFireEffect(projectile)
			local effects = projectile:FindFirstChild("Effects")
			if not effects then return end

			for _, effect in pairs(effects:GetDescendants()) do
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
			speed = 200, -- Faster fall
			range = distance + 10, 
			damageCoeff = damageMult, 
			procCoeff = procCoeff, 
			modelTemplate = StarModel,
			onFire = projectileFireEffect,
			onImpact = function(result)
				-- Explosion Logic
				local hitPos = result.Position
				local radius = 12


				for _, particle in pairs(result.Instance:GetDescendants()) do
					if particle:IsA("ParticleEmitter") then
						particle.Enabled = false

						if particle:GetAttribute("EmitCount") then
							particle:Emit(particle:GetAttribute("EmitCount"))
						end
					elseif particle:IsA("Trail") then
						particle.Enabled = false
					end
				end
				
                
				-- Area Damage
				local victims = {}
				local overlapParams = OverlapParams.new()
				overlapParams.FilterDescendantsInstances = {char.Instance}
				overlapParams.FilterType = Enum.RaycastFilterType.Exclude

				local hitTarget = false
				local parts = workspace:GetPartBoundsInRadius(hitPos, radius, overlapParams)
				for _, part in ipairs(parts) do
					local victimChar = part.Parent
					if victimChar and victimChar:FindFirstChild("Humanoid") and not victims[victimChar] then
						victims[victimChar] = true

						local targetWCS = WCS.Character.GetCharacterFromInstance(victimChar)
						if targetWCS then
							hitTarget = true
							DamagePipeline.DealDamage(char, targetWCS, damageMult, procCoeff, "ShootingStarsExplosion")
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

function ShootingStars:OnStartClient(Target)
end

return ShootingStars
