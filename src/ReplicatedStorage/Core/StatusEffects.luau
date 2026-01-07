local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)

local StatusEffects = {}

-- [[ Sprint Buff ]]
StatusEffects.SprintBuff = WCS.RegisterStatusEffect("SprintBuff")
function StatusEffects.SprintBuff:OnStartServer()
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	DamagePipeline.RecalculateStats(self.Character)
end
function StatusEffects.SprintBuff:OnEndServer()
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	DamagePipeline.RecalculateStats(self.Character)
end

-- [[ MedPack Buff ]]
StatusEffects.MedPackBuff = WCS.RegisterStatusEffect("MedPackBuff")
StatusEffects.MedPackBuff.DamageModificationPriority = 10
function StatusEffects.MedPackBuff:OnConstruct()
	self.Duration = 5
end
function StatusEffects.MedPackBuff:OnStartServer()
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	DamagePipeline.RecalculateStats(self.Character)
end
function StatusEffects.MedPackBuff:OnEndServer()
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	DamagePipeline.RecalculateStats(self.Character)
end

-- [[ Corrosion ]]
StatusEffects.Corrosion = WCS.RegisterStatusEffect("Corrosion")
function StatusEffects.Corrosion:OnConstruct(stacks)
	self.Stacks = stacks or 1
	self.Duration = 5
	self.Interval = 0.5
	self.Timer = 0
end
function StatusEffects.Corrosion:OnStartServer()
	self.Janitor:Add(game:GetService("RunService").Heartbeat:Connect(function(dt)
		self.Timer = self.Timer + dt
		if self.Timer >= self.Interval then
			self.Timer = 0
			local dmg = 5 * self.Stacks -- Placeholder formula
			
			local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
			local dmgInfo = {
				Attacker = self.Source,
				Inflictor = nil,
				Damage = dmg,
				Crit = false,
				ProcCoefficient = 0, -- DoTs don't proc usually
				Position = self.Character.Instance.PrimaryPart and self.Character.Instance.PrimaryPart.Position or Vector3.zero,
				Force = Vector3.zero,
				ProcChainMask = 1
			}
			
			DamagePipeline.ProcessDamage(dmgInfo, self.Character) 
		end
	end))
end

-- [[ Knockback ]]
StatusEffects.Knockback = WCS.RegisterStatusEffect("Knockback")
function StatusEffects.Knockback:OnConstruct(direction: Vector3, force: number, duration: number?)
	self.Direction = direction
	self.Force = force
	self.Duration = duration or 0.2
end

function StatusEffects.Knockback:OnStartServer()
	local char = self.Character
	local hrp = char.Instance:FindFirstChild("HumanoidRootPart")
	local humanoid = char.Instance:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end
	
	-- Disable AI movement during knockback
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	DamagePipeline.SetCharacterData(char, "IsDisabled", true)
	
	-- Stop current movement
	humanoid:Move(Vector3.zero)
	
	-- Clean up old knockback
	for _, child in ipairs(hrp:GetChildren()) do
		if child.Name == "KnockbackVelocity" then
			child:Destroy()
		end
	end

	local attachment = hrp:FindFirstChild("RootAttachment") or hrp:FindFirstChild("RootRigAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "KnockbackAttachment"
		attachment.Parent = hrp
	end

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "KnockbackVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = 2000000 -- Increased force
	linearVelocity.VectorVelocity = self.Direction * self.Force
	linearVelocity.Parent = hrp

	task.delay(self.Duration, function()
		if linearVelocity and linearVelocity.Parent then
			linearVelocity:Destroy()
		end
		if attachment and attachment.Name == "KnockbackAttachment" then
			attachment:Destroy()
		end
		
		-- Re-enable AI
		DamagePipeline.SetCharacterData(char, "IsDisabled", false)
		self:Stop() -- End the status effect
	end)
end

-- [[ Stun ]]
StatusEffects.Stun = WCS.RegisterStatusEffect("Stun")
function StatusEffects.Stun:OnConstruct(duration: number?)
	self.Duration = duration or 0.5
end

function StatusEffects.Stun:OnStartServer()
	local char = self.Character
	local humanoid = char.Instance:FindFirstChildOfClass("Humanoid")
	local DamagePipeline = require(game:GetService("ServerScriptService").Systems.DamagePipeline)
	
	DamagePipeline.SetCharacterData(char, "IsDisabled", true)
	if humanoid then
		humanoid:Move(Vector3.zero)
	end
	
	task.delay(self.Duration, function()
		DamagePipeline.SetCharacterData(char, "IsDisabled", false)
		self:Stop()
	end)
end

return StatusEffects
