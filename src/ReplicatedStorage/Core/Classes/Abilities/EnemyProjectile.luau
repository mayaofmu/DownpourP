local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)

local EnemyProjectile = WCS.RegisterSkill("EnemyProjectile")

-- Configuration
local Config = {
	Speed = 150,
	Range = 150,
	DamageCoefficient = 1.2, -- Moderately hard hitting
	ProcCoefficient = 0.5,
}

-- Custom Bullet for Enemies
local MobBullet = Instance.new("Part")
MobBullet.Name = "MobBolt"
MobBullet.Size = Vector3.new(0.7, 0.7, 2.5)
MobBullet.Color = Color3.fromRGB(255, 50, 50) -- Red for danger
MobBullet.Material = Enum.Material.Neon
MobBullet.CanCollide = false
MobBullet.Anchored = true

function EnemyProjectile:OnConstruct()
end

function EnemyProjectile:ShouldStart()
	return true
end

function EnemyProjectile:OnStartServer(TargetPosition: Vector3)
	local char = self.Character
	local hrp = char.Instance:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
    
	-- Validation: Enemies are server-side, so we just use their HRP position
	local origin = hrp.Position + (hrp.CFrame.LookVector * 2)
	
	-- Calculate Projectile Direction
	local direction = (TargetPosition - origin).Unit
	
    -- Apply Cooldown (User requested 1.25s)
	self:ApplyCooldown(1.25)
	
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
		modelTemplate = MobBullet,
		collisionGroup = "Mobs"
	})
end

return EnemyProjectile

