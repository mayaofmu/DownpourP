local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local WCS = require(ReplicatedStorage.Modules.wcs)
local StatusEffects = require(ReplicatedStorage.Core.StatusEffects)
local Hitbox = require(ReplicatedStorage.Modules.Hitbox)
local CombatMovement = require(ReplicatedStorage.Modules.CombatMovement)
local AutoTargeting = require(ReplicatedStorage.Modules.AutoTargeting)

local RunService = game:GetService("RunService")

local GlaiveCombat = WCS.RegisterSkill("GlaiveCombat")

-- Configuration
local Config = {
	DamageCoefficient = 1.4, -- Increased for hack and slash feel
	KnockbackForce = 35,
	KnockbackDuration = 0.2,
	BaseCooldown = 0.68, -- Restored from 0.7
	
	-- Combo System
	ComboCount = 3,
	ComboWindow = 1.0, -- Time window to continue combo
	
	-- Hitbox Configuration
	HitboxSize = Vector3.new(10, 8, 10), -- Larger hitbox
	HitboxOffset = CFrame.new(0, 0, -5), -- Further in front to account for lunge
	HitboxDuration = 0.25,
	
	-- Movement
	LungeDistance = 6.5, -- Reduced from 9
	LungeDuration = 0.18, -- Increased from 0.15 for smoothness
	MagnetRange = 16, -- Reduced from 22
}

function GlaiveCombat:OnConstruct()
	self._hitCache = {}
	self._comboIndex = 0
	self._lastAttackTime = 0
	self._glaiveModel = nil
	self._animTracks = {}
	self.CheckClientState = true
	
	-- Metadata for replication (Only set on server)
	if RunService:IsServer() and not self:GetMetadata() then
		self:SetMetadata({
			ComboIndex = 0
		})
	end
end

function GlaiveCombat:ShouldStart()
	return true
end

function GlaiveCombat:GetGlaiveModel()
	if self._glaiveModel and self._glaiveModel.Parent then
		return self._glaiveModel
	end
	
	local char = self.Character.Instance
	local glaive = char:FindFirstChild("Glaive")
	
	self._glaiveModel = glaive
	return glaive
end

function GlaiveCombat:GetAnimationTrack(animName, animObject)
	if self._animTracks[animName] then
		return self._animTracks[animName]
	end

	local char = self.Character.Instance
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

	if animator then
		local track = animator:LoadAnimation(animObject) 
		self._animTracks[animName] = track
		return track
	end

	return nil
end

function GlaiveCombat:PerformLunge(lookDirection)
	local char = self.Character.Instance
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end
	
	-- Determine movement intent
	local moveDirection = humanoid.MoveDirection
	local hasMoveInput = moveDirection.Magnitude > 0.1
	
	-- If no lookDirection provided, fallback to character's current look direction
	lookDirection = lookDirection or hrp.CFrame.LookVector
	
	-- Safety check for zero vector
	if lookDirection.Magnitude < 0.01 then
		lookDirection = hrp.CFrame.LookVector
	end
	
	-- The actual direction we want to lunge if no target is found
	-- Prioritize movement direction if the player is actively moving
	local lungeDirection = hasMoveInput and moveDirection or lookDirection
	
	-- Hack and Slash Magnetism: Find a target to lunge towards
	-- If moving, we search in the direction of movement instead of just camera look
	local target = AutoTargeting.GetBestTarget(CFrame.lookAt(hrp.Position, hrp.Position + lungeDirection), char, {
		Range = Config.MagnetRange,
		Angle = 120,
	})
	
	if target then
		-- Face the target and dash towards them
		CombatMovement.FacePosition(char, target:GetPivot().Position, 0.1)
		CombatMovement.DashToTarget(char, target, {
			Speed = Config.LungeDistance / Config.LungeDuration,
			Duration = Config.LungeDuration,
			StopDistance = 3 
		})
	else
		-- Face the lunge direction (movement or camera) and dash
		local targetPos = hrp.Position + lungeDirection * 10
		CombatMovement.FacePosition(char, targetPos, 0.1)
		
		-- Raycast to prevent flinging into walls
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {char}
		
		local rayResult = workspace:Raycast(hrp.Position, lungeDirection * Config.LungeDistance, raycastParams)
		local finalDistance = Config.LungeDistance
		if rayResult then
			finalDistance = math.max(0, (rayResult.Position - hrp.Position).Magnitude - 1.5)
		end
		
		if finalDistance > 0 then
			CombatMovement.DashDirection(char, lungeDirection, {
				Speed = finalDistance / Config.LungeDuration,
				Duration = Config.LungeDuration
			})
		end
	end
end

function GlaiveCombat:OnStartServer(lookDirection)
	-- Update combo
	local currentTime = tick()
	if currentTime - self._lastAttackTime > Config.ComboWindow then
		self._comboIndex = 0 -- Reset combo if too much time passed
	else
		self._comboIndex = (self._comboIndex + 1) % Config.ComboCount
	end
	self._lastAttackTime = currentTime
	
	-- Calculate cooldown based on attack speed
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	local statBlock = DamagePipeline.GetStatBlock(self.Character)
	local attackSpeed = statBlock and statBlock:Get("AttackSpeed") or 1
	local cooldownTime = Config.BaseCooldown / attackSpeed

	-- Sync combo index and attack speed to client
	self:SetMetadata({
		ComboIndex = self._comboIndex,
		AttackSpeed = attackSpeed
	})
	
	-- Perform lunge and hitbox with a delay to sync with animation windup
	task.delay(0.1, function()
		-- Perform lunge movement
		self:PerformLunge(lookDirection)

		local char = self.Character.Instance
		local hrp = char:FindFirstChild("HumanoidRootPart")

		if hrp then
			-- Latency compensation: shift hitbox based on velocity
			local velocityOffset = hrp.AssemblyLinearVelocity * 0.1
			local finalOffset = Config.HitboxOffset * CFrame.new(velocityOffset)

			-- Create hitbox using EZ-Hitbox module
			local hitbox = Hitbox.new({
				SizeOrPart = Config.HitboxSize,
				SpatialOption = "InBox",
				LookingFor = "Humanoid",
				LifeTime = Config.HitboxDuration,
				DebounceTime = 0,
				Blacklist = {char},
				Debug = false
			})

			-- Position hitbox in front of character
			hitbox:WeldTo(hrp, finalOffset)

			-- Handle hits
			hitbox.OnHit:Connect(function(hitCharacters)
				local hitSomething = false
				for _, hitModel in ipairs(hitCharacters) do
					if self._hitCache[hitModel] then continue end

					local targetWCS = WCS.Character.GetCharacterFromInstance(hitModel)
					if targetWCS and targetWCS ~= self.Character then
						self._hitCache[hitModel] = true
						hitSomething = true

						-- Combo damage scaling: 1.0x, 1.1x, 1.5x (Finisher)
						local comboMultipliers = {1.0, 1.1, 1.5}
						local comboMultiplier = comboMultipliers[self._comboIndex + 1] or 1.0
						local finalDamage = Config.DamageCoefficient * comboMultiplier
						
						DamagePipeline.DealDamage(self.Character, targetWCS, finalDamage, 1.0, "GlaiveCombat")
						
						-- Apply Stun (Every hit flinches the enemy)
						local stun = StatusEffects.Stun.new(targetWCS, 0.2)
						stun:Start()

						-- Apply Knockback (Increased for finisher)
						local targetHrp = hitModel.PrimaryPart
						if hrp and targetHrp then
							local dir = (targetHrp.Position - hrp.Position).Unit
							local force = Config.KnockbackForce * (self._comboIndex == 2 and 1.5 or 1)
							-- Add slight upward force to prevent "sliding" and make it feel more "airborne"
							local kbDir = (dir + Vector3.new(0, 0.2, 0)).Unit
							local kb = StatusEffects.Knockback.new(targetWCS, kbDir, force, Config.KnockbackDuration)
							kb:Start()
						end
					end
				end

				if hitSomething then
					self:SetMetadata({
						LastHitTime = tick(),
						ComboIndex = self._comboIndex,
						AttackSpeed = attackSpeed
					})
				end
			end)

			-- Start the hitbox
			hitbox:Start()
		end

		-- Reset hit cache for next attack
		task.delay(Config.HitboxDuration, function()
			self._hitCache = {}
		end)
	end)

	self:ApplyCooldown(cooldownTime)
end

function GlaiveCombat:OnStartClient(lookDirection)
	-- Ensure glaive is equipped
	self:GetGlaiveModel()

	-- Update local combo for immediate visual feedback
	-- This prevents the "same animation" bug caused by metadata replication lag
	local currentTime = tick()
	if currentTime - self._lastAttackTime > Config.ComboWindow then
		self._comboIndex = 0
	else
		self._comboIndex = (self._comboIndex + 1) % Config.ComboCount
	end
	self._lastAttackTime = currentTime

	-- Get data from metadata (as backup/sync)
	local metadata = self:GetMetadata()
	local comboIndex = self._comboIndex
	local attackSpeed = metadata and metadata.AttackSpeed or 1

	-- Start lunge locally with a delay to sync with animation windup
	task.delay(0.1, function()
		self:PerformLunge(lookDirection)
	end)

	-- Play attack animation based on combo (M1, M2, M3)
	local animations = ReplicatedStorage.Core.Classes.Glaive:FindFirstChild("Animations")

	if animations then
		local animName = "M" .. (comboIndex + 1)
		local comboAnim = animations:FindFirstChild(animName)
		if comboAnim then
			local track = self:GetAnimationTrack(animName, comboAnim)
			if track then
				track.Looped = false
				track:Play()

				track:AdjustSpeed(1.4 * attackSpeed)

				-- RoR2 Hitstop Effect: Pause animation briefly on hit
				self._hitConnection = self.MetadataChanged:Connect(function(newMeta)
					if newMeta and newMeta.LastHitTime then
						track:AdjustSpeed(0.01) -- Nearly pause
						task.wait(0.05)
						if track.IsPlaying then
							track:AdjustSpeed(1.4 * attackSpeed)
						end
					end
				end)

				task.delay(track.Length / (1.4 * attackSpeed), function()
					if self._hitConnection then
						self._hitConnection:Disconnect()
						self._hitConnection = nil
					end
				end)
			end
		end
	end

	-- Visual effects
	local glaive = self:GetGlaiveModel()
	if glaive then
		local primaryPart = glaive.PrimaryPart or glaive:FindFirstChildWhichIsA("BasePart")
		if primaryPart then
			-- Quick flash effect on the weapon
			local originalColor = primaryPart.Color

			TweenService:Create(primaryPart, TweenInfo.new(0.05), {
				Color = Color3.fromRGB(255, 255, 255),
			}):Play()

			task.delay(0.1, function()
				TweenService:Create(primaryPart, TweenInfo.new(0.15), {
					Color = originalColor,
				}):Play()
			end)
		end
	end

	-- Play swing sound
	local soundFolder = script:FindFirstChild("Sounds")
	if soundFolder then
		local swingSound = soundFolder:FindFirstChild("Swing" .. (comboIndex + 1))
		if swingSound and swingSound:IsA("Sound") then
			swingSound:Play()
		end
	end
end

function GlaiveCombat:OnEndServer()
end

function GlaiveCombat:OnEndClient()
end

return GlaiveCombat

