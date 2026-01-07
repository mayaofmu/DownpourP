local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local FastCast = require(ReplicatedStorage.Modules.FastCastRedux)

local ProjectileSystem = {}
local DamagePipeline -- Lazy load

export type ProjectileOptions = {
	attacker: any,
	origin: Vector3 | CFrame,
	direction: Vector3,
	speed: number,
	range: number,
	damageCoeff: number,
	procCoeff: number,
	modelTemplate: BasePart?, 
	onImpact: ((RaycastResult) -> ())?,
	onFire: ((cosmeticBullet: Instance) -> ())?,  
	modelOffset: CFrame?,
	collisionGroup: string?,
} 

-- -- FastCast Setup --
local Caster = FastCast.new()

-- Create projectiles folder
local projectilesFolder = workspace:FindFirstChild("Projectiles") or Instance.new("Folder", workspace)
projectilesFolder.Name = "Projectiles"  

-- Default Bullet Template
local defaultBullet = Instance.new("Part")
defaultBullet.Name = "EnergyBolt"
defaultBullet.Size = Vector3.new(0.5, 0.5, 2)
defaultBullet.Color = Color3.fromRGB(255, 255, 0)
defaultBullet.Material = Enum.Material.Neon
defaultBullet.CanCollide = false
defaultBullet.Anchored = true

-- -- Handlers --
local function OnRayHit(cast, result, velocity, bullet)
	local userData = cast.UserData
	local onImpact = userData.onImpact
	local attacker = userData.attacker
 
	local onImpactHitRegistered = onImpact and onImpact(result, bullet) or false 
	if not onImpactHitRegistered then
		-- Default Hit Logic
		local hitChar = result.Instance:FindFirstAncestorOfClass("Model")
		local damageCoeff = userData.damageCoeff
		local procCoeff = userData.procCoeff

		-- Friendly Fire Check
		if attacker and attacker.Instance and hitChar then
			local attackerTeam = attacker.Instance:GetAttribute("Team")
			local hitTeam = hitChar:GetAttribute("Team")
			
			-- Check if both are enemies (e.g. Mob vs Mob)
			if attackerTeam == "Enemy" and hitTeam == "Enemy" then
				return -- Ignore hit completely (no damage, no impact effect)
			end

			if attackerTeam and hitTeam and attackerTeam == hitTeam then
				return
			end
		end

		if not DamagePipeline then
			DamagePipeline = require(ServerScriptService.Systems.DamagePipeline)
		end
		
		-- Resolve WCS
		local WCS = require(ReplicatedStorage.Modules.wcs)
		local targetWCS = WCS.Character.GetCharacterFromInstance(hitChar)
		
		if targetWCS then
			DamagePipeline.DealDamage(attacker, targetWCS, damageCoeff, procCoeff, "EnergyBolt")
		elseif hitChar then
			local hum = hitChar:FindFirstChild("Humanoid")
			if hum then
				hum:TakeDamage(10)
			end
		end
	end
end

local function OnLengthChanged(cast, lastPoint, rayDir, displacement, segmentVelocity, cosmeticBulletObject)
	if cosmeticBulletObject then
		local bulletLength = cosmeticBulletObject.Size.Z / 2
		local baseCFrame = CFrame.new(lastPoint, lastPoint + rayDir)
		
		-- Apply custom adjustment if exists
		local userData = cast.UserData
		if userData and userData.modelOffset then
			cosmeticBulletObject.CFrame = (baseCFrame * CFrame.new(0, 0, -(displacement - bulletLength))) * userData.modelOffset

		else 
			cosmeticBulletObject.CFrame = (baseCFrame * CFrame.new(0, 0, -(displacement - bulletLength))) 
		end
		
		-- Handle onFire callback (runs once)
		if userData and userData.onFire and not userData.hasFired then
			userData.hasFired = true
			userData.onFire(cosmeticBulletObject)
		end
	end
end

local function OnCastTerminating(cast)

	local bullet = cast.RayInfo.CosmeticBulletObject
		if not bullet then return end
		
		-- 1. Make physically uninteractable
		bullet.Anchored = true
		bullet.CanCollide = false
		bullet.CanTouch = false
		bullet.CanQuery = false
		bullet.Transparency = 1 
		
		-- 2. Handle Visuals
		for _, desc in ipairs(bullet:GetDescendants()) do
			-- Check for "PlayVFX" attribute on self or parent to skip disabling
			local hasAttr = desc:GetAttribute("PlayVFX") or (desc.Parent and desc.Parent:GetAttribute("PlayVFX"))
			
			if desc:IsA("BasePart") then
				desc.Transparency = 1
			elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
				if not hasAttr then
					desc.Enabled = false
				end
			elseif desc:IsA("Light") then
				if not hasAttr then

				end
			end
		end
		
		-- 3. Grace time
		task.wait(1)
		
		-- 4. Destroy
		if bullet then
			bullet:Destroy()
		end
end

Caster.RayHit:Connect(OnRayHit)
Caster.LengthChanged:Connect(OnLengthChanged)
Caster.CastTerminating:Connect(OnCastTerminating)

function ProjectileSystem.FireProjectile(options: ProjectileOptions)
	assert(typeof(options) == "table", "[ProjectileSystem] FireProjectile now requires a dictionary as the only argument.")
	
	local behavior = FastCast.newBehavior()
	behavior.MaxDistance = options.range
	behavior.AutoIgnoreContainer = true
	behavior.CosmeticBulletContainer = projectilesFolder
	
	-- Raycast Params
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local filter = {projectilesFolder, workspace.DroppedItems, workspace.Effects}
	if options.attacker and options.attacker.Instance then
		table.insert(filter, options.attacker.Instance)
	end
	
	rayParams.FilterDescendantsInstances = filter
	behavior.RaycastParams = rayParams
	
	if options.collisionGroup then
		rayParams.CollisionGroup = options.collisionGroup
	end
	
	-- Template
	if options.modelTemplate then
		behavior.CosmeticBulletTemplate = options.modelTemplate
	else
		behavior.CosmeticBulletTemplate = defaultBullet
	end
	
	-- Handle Origin as CFrame or Vector3
	local startPos = options.origin
	if typeof(options.origin) == "CFrame" then
		startPos = options.origin.Position
	end
	
	local cast = Caster:Fire(startPos, options.direction, options.speed, behavior)
	 
	cast.UserData = {
		attacker = options.attacker,
		damageCoeff = options.damageCoeff,
		procCoeff = options.procCoeff,
		onImpact = options.onImpact,
		onFire = options.onFire,
		modelOffset = options.modelOffset,
		manualCleanup = true,
		hasFired = false
	}

end

return ProjectileSystem
