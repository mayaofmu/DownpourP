local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)

local FireBolt = WCS.RegisterSkill("FireBolt")

local Assets = script.Assets 
local _Animations = script.Animations 

local BoltBullet = Assets.Bolt

-- Configuration
local Config = {
	Speed = 225,
	Range = 200,
	DamageCoefficient = 1.0, -- 100% of Base Damage
	ProcCoefficient = 1.0,   -- 100% Proc Chance for items
	Bullet = BoltBullet,
	Spread = 0.1, -- 10% Spread
}

function FireBolt:OnConstruct()
	-- self.Cooldown = 0.5 -- Default, but we want dynamic
	self.CheckClientState = true
end

function FireBolt:ShouldStart()
	-- Check dynamic cooldown here if WCS supports it, or use normal Cooldown and modify it.
	-- We'll modify Cooldown in OnStartServer/Client
	return true
end

function FireBolt:OnStartServer(ClientOrigin: Vector3, MouseHitPosition: Vector3)
	local char = self.Character
	
	-- Validation: Ensure ClientOrigin is not too far from Server HRP (Anticheat / Sanity Check)
	-- Max discrepancy allowed: 10 studs (latency + speed)
	local serverPos = char.Instance.HumanoidRootPart.Position
	if (ClientOrigin - serverPos).Magnitude > 10 then
		warn("[FireBolt] Client origin too far from server position. Resyncing.")
		ClientOrigin = serverPos -- Fallback to server position
	end
	
	-- Use DamagePipeline to get data
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	local statBlock = DamagePipeline.GetStatBlock(char)
	local inventory = DamagePipeline.GetInventory(char)
	
	-- Fire OnFire Items (e.g. Gungnir)
	local ItemSystem = require(game:GetService("ServerScriptService").Systems.ItemSystem)
	ItemSystem.FireOnFire(inventory, char, ClientOrigin, MouseHitPosition)
	
	-- Calculate Attack Speed
	local attackSpeed = statBlock and statBlock:Get("AttackSpeed") or 1
	local cooldownTime = .5 / attackSpeed
	
	self:ApplyCooldown(cooldownTime)
	
	-- Calculate Projectile Origin and Direction
	local origin = ClientOrigin
	
	-- Try to find a better origin (like a tool's muzzle or head) if possible
	-- For now, we trust ClientOrigin but ensure it's validated against Server HRP
	
	local direction = (MouseHitPosition - origin).Unit
	
	-- Apply Spread
	local rng = Random.new()
	local spread = Vector3.new(
		(rng:NextNumber() - 0.5) * 2,
		(rng:NextNumber() - 0.5) * 2,
		(rng:NextNumber() - 0.5) * 2
	) * (Config.Spread / 2)
	
	direction = (direction + spread).Unit

	local onImpact = function(result, bullet)
		local hitTarget = false



		for _, particle in pairs(bullet.Effects:GetChildren()) do
			if particle:IsA("ParticleEmitter") then
				particle.Enabled = false

				if particle:GetAttribute("EmitCount") then
					particle:Emit(particle:GetAttribute("EmitCount"))
				end
			end
		end
  
		bullet.Impact:Play()

		return false
	end

	local onFire = function(bullet)
		bullet.Shoot:Play()
	end
	-- Fire Projectile
	local ProjectileSystem = require(game:GetService("ServerScriptService").Systems.ProjectileSystem)
	ProjectileSystem.FireProjectile({
		attacker = char, 
		origin = origin, 
		direction = direction, 
		speed = Config.Speed, 
		range = Config.Range, 
		damageCoeff = Config.DamageCoefficient, 
		procCoeff = Config.ProcCoefficient,
		modelTemplate = Config.Bullet,
		onImpact = onImpact,
		onFire = onFire
	})
	
	print("[FireBolt] Fired! AS:", attackSpeed, "CD:", cooldownTime)
end

function FireBolt:OnStartClient(...)
	-- Visuals only
	-- We could play animation here
	print(...)
end

return FireBolt
