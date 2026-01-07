-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
--/ <reference types="@rbxts/testez/globals" />
local Janitor = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "janitor", "src").Janitor
local _services = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "services")
local RunService = _services.RunService
local Workspace = _services.Workspace
local _exports = TS.import(script, script.Parent.Parent, "exports")
local Character = _exports.Character
local Skill = _exports.Skill
local SkillDecorator = _exports.SkillDecorator
local StatusEffect = _exports.StatusEffect
local StatusEffectDecorator = _exports.StatusEffectDecorator
local shallowEqual = TS.import(script, script.Parent.Parent, "source", "utility").shallowEqual
local function haveKeys(object, keys)
	for i, v in pairs(keys) do
		if not (object[v] ~= nil) then
			return false
		end
	end
	return true
end
return function()
	local janitor = Janitor.new()
	local someSkill
	do
		local super = Skill
		someSkill = setmetatable({}, {
			__tostring = function()
				return "someSkill"
			end,
			__index = super,
		})
		someSkill.__index = someSkill
		function someSkill.new(...)
			local self = setmetatable({}, someSkill)
			return self:constructor(...) or self
		end
		function someSkill:constructor(...)
			super.constructor(self, ...)
			self.DamageModificationPriority = 2
		end
		someSkill = SkillDecorator(someSkill) or someSkill
	end
	local someStatus
	do
		local super = StatusEffect
		someStatus = setmetatable({}, {
			__tostring = function()
				return "someStatus"
			end,
			__index = super,
		})
		someStatus.__index = someStatus
		function someStatus.new(...)
			local self = setmetatable({}, someStatus)
			return self:constructor(...) or self
		end
		function someStatus:constructor(...)
			super.constructor(self, ...)
		end
		someStatus = StatusEffectDecorator(someStatus) or someStatus
	end
	local nullifyingStatus
	do
		local super = StatusEffect
		nullifyingStatus = setmetatable({}, {
			__tostring = function()
				return "nullifyingStatus"
			end,
			__index = super,
		})
		nullifyingStatus.__index = nullifyingStatus
		function nullifyingStatus.new(...)
			local self = setmetatable({}, nullifyingStatus)
			return self:constructor(...) or self
		end
		function nullifyingStatus:constructor(...)
			super.constructor(self, ...)
			self.DamageModificationPriority = 2
		end
		function nullifyingStatus:HandleDamage(Modified, Original)
			return 0
		end
		nullifyingStatus = StatusEffectDecorator(nullifyingStatus) or nullifyingStatus
	end
	local increaseStatus
	do
		local super = StatusEffect
		increaseStatus = setmetatable({}, {
			__tostring = function()
				return "increaseStatus"
			end,
			__index = super,
		})
		increaseStatus.__index = increaseStatus
		function increaseStatus.new(...)
			local self = setmetatable({}, increaseStatus)
			return self:constructor(...) or self
		end
		function increaseStatus:constructor(...)
			super.constructor(self, ...)
		end
		function increaseStatus:HandleDamage(Modified, Original)
			return Modified + 10
		end
		increaseStatus = StatusEffectDecorator(increaseStatus) or increaseStatus
	end
	local function makeChar()
		local part = Instance.new("Part")
		Instance.new("Humanoid", part)
		janitor:Add(part)
		local character = Character.new(part)
		janitor:Add(character)
		return character
	end
	describe("instantiation", function()
		it("should instantiate a character over a valid instance", function()
			expect(makeChar()).to.be.ok()
		end)
		it("should throw if instance is invalid", function()
			expect(function()
				return Character.new(Workspace)
			end).to:throw()
		end)
	end)
	describe("humanoid props", function()
		it("should have valid humanoid props", function()
			expect(haveKeys(makeChar():GetDefaultProps(), { "WalkSpeed", "JumpPower", "JumpHeight", "AutoRotate" })).to.be.equal(true)
		end)
		it("should set new props", function()
			local char = makeChar()
			local props = {
				WalkSpeed = 0,
				JumpPower = 0,
				JumpHeight = 0,
				AutoRotate = false,
			}
			char:SetDefaultProps(props)
			expect(shallowEqual(char:GetDefaultProps(), props)).to.be.equal(true)
		end)
		it("should calculate props", function()
			local propsChangingStatus
			do
				local super = StatusEffect
				propsChangingStatus = setmetatable({}, {
					__tostring = function()
						return "propsChangingStatus"
					end,
					__index = super,
				})
				propsChangingStatus.__index = propsChangingStatus
				function propsChangingStatus.new(...)
					local self = setmetatable({}, propsChangingStatus)
					return self:constructor(...) or self
				end
				function propsChangingStatus:constructor(...)
					super.constructor(self, ...)
				end
				function propsChangingStatus:OnConstructServer()
					self:SetHumanoidData({
						WalkSpeed = { 0, "Set" },
					})
				end
				propsChangingStatus = StatusEffectDecorator(propsChangingStatus) or propsChangingStatus
			end
			local char = makeChar()
			local status = propsChangingStatus.new(char)
			status:Start()
			RunService.Heartbeat:Wait()
			expect(char:GetAppliedProps().WalkSpeed).to.be.equal(0)
			status:Destroy()
			RunService.Heartbeat:Wait()
			expect(char:GetAppliedProps().WalkSpeed).to.be.equal(16)
		end)
	end)
	describe("skills", function()
		it("should add a skill", function()
			local char = makeChar()
			someSkill.new(char)
			RunService.Heartbeat:Wait()
			expect(char:GetSkillFromConstructor(someSkill)).to.be.ok()
			expect(char:GetSkillFromString(tostring(someSkill))).to.be.ok()
		end)
		it("should fire events", function()
			local char = makeChar()
			local changed = 0
			char.SkillAdded:Connect(function()
				local _original = changed
				changed += 1
				return _original
			end)
			char.SkillRemoved:Connect(function()
				local _original = changed
				changed += 1
				return _original
			end)
			char.SkillStarted:Connect(function()
				local _original = changed
				changed += 1
				return _original
			end)
			char.SkillEnded:Connect(function()
				local _original = changed
				changed += 1
				return _original
			end)
			local x = someSkill.new(char)
			x:Start()
			RunService.Heartbeat:Wait()
			x:Destroy()
			RunService.Heartbeat:Wait()
			expect(changed).to.be.equal(4)
		end)
		it("should get derived skills", function()
			local baseSkill
			do
				local super = Skill
				baseSkill = setmetatable({}, {
					__tostring = function()
						return "baseSkill"
					end,
					__index = super,
				})
				baseSkill.__index = baseSkill
				function baseSkill.new(...)
					local self = setmetatable({}, baseSkill)
					return self:constructor(...) or self
				end
				function baseSkill:constructor(...)
					super.constructor(self, ...)
				end
				baseSkill = SkillDecorator(baseSkill) or baseSkill
			end
			local derivedFromBaseSkill
			do
				local super = baseSkill
				derivedFromBaseSkill = setmetatable({}, {
					__tostring = function()
						return "derivedFromBaseSkill"
					end,
					__index = super,
				})
				derivedFromBaseSkill.__index = derivedFromBaseSkill
				function derivedFromBaseSkill.new(...)
					local self = setmetatable({}, derivedFromBaseSkill)
					return self:constructor(...) or self
				end
				function derivedFromBaseSkill:constructor(...)
					super.constructor(self, ...)
				end
				derivedFromBaseSkill = SkillDecorator(derivedFromBaseSkill) or derivedFromBaseSkill
			end
			local char = makeChar()
			local skill = derivedFromBaseSkill.new(char)
			expect(char:GetSkillsDerivedFrom(baseSkill)[1]).to.be.equal(skill)
		end)
		it("should remove skills", function()
			local char = makeChar()
			someSkill.new(char)
			local _exp = char:GetSkills()
			-- ▼ ReadonlyArray.forEach ▼
			local _callback = function(T)
				return T:Destroy()
			end
			for _k, _v in _exp do
				_callback(_v, _k - 1, _exp)
			end
			-- ▲ ReadonlyArray.forEach ▲
			RunService.Heartbeat:Wait()
			expect(#char:GetSkills()).to.be.equal(0)
		end)
	end)
	describe("statuses", function()
		it("should add a status", function()
			expect(someStatus.new(makeChar())).to.be.ok()
		end)
		it("should list the added status", function()
			local char = makeChar()
			someStatus.new(char)
			expect(#char:GetAllStatusEffects()).to.be.equal(1)
			expect(#char:GetAllStatusEffectsOfType(someStatus)).to.be.equal(1)
		end)
		it("should list an active status", function()
			local char = makeChar()
			local status = someStatus.new(char)
			status:Start()
			expect(#char:GetAllActiveStatusEffectsOfType(someStatus)).to.be.equal(1)
		end)
		it("should fire events", function()
			local char = makeChar()
			local changed = 0
			char.StatusEffectAdded:Connect(function()
				local _original = changed
				changed += 1
				return _original
			end)
			char.StatusEffectRemoved:Connect(function()
				local _original = changed
				changed += 1
				return _original
			end)
			char.StatusEffectStarted:Connect(function()
				local _original = changed
				changed += 1
				return _original
			end)
			char.StatusEffectEnded:Connect(function()
				local _original = changed
				changed += 1
				return _original
			end)
			local x = someStatus.new(char)
			x:Start()
			RunService.Heartbeat:Wait()
			x:End()
			RunService.Heartbeat:Wait()
			x:Destroy()
			expect(changed).to.be.equal(4)
		end)
		it("should remove a status", function()
			local char = makeChar()
			someStatus.new(char)
			local _exp = char:GetAllStatusEffects()
			-- ▼ ReadonlyArray.forEach ▼
			local _callback = function(T)
				return T:Destroy()
			end
			for _k, _v in _exp do
				_callback(_v, _k - 1, _exp)
			end
			-- ▲ ReadonlyArray.forEach ▲
			RunService.Heartbeat:Wait()
			expect(#char:GetAllStatusEffects()).to.be.equal(0)
		end)
	end)
	describe("static callbacks", function()
		it("should fire static callbacks", function()
			local changed = {}
			Character.CharacterDestroyed:Connect(function()
				table.insert(changed, true)
				return #changed
			end)
			Character.CharacterCreated:Connect(function()
				table.insert(changed, true)
				return #changed
			end)
			makeChar():Destroy()
			RunService.Heartbeat:Wait()
			expect(#changed).to.be.equal(2)
		end)
	end)
	describe("damage", function()
		it("should take damage", function()
			makeChar():TakeDamage({
				Source = nil,
				Damage = 10,
			})
		end)
		it("should fire damage taken callback", function()
			local char = makeChar()
			local pass = false
			char.DamageTaken:Connect(function()
				pass = true
			end)
			char:TakeDamage({
				Source = nil,
				Damage = 10,
			})
			RunService.Heartbeat:Wait()
			expect(pass).to.be.equal(true)
		end)
		it("should modify damage", function()
			local char = makeChar()
			increaseStatus.new(char):Start()
			RunService.Heartbeat:Wait()
			expect(char:PredictDamage({
				Damage = 100,
				Source = nil,
			}).Damage).to.be.equal(110)
		end)
		it("should respect modification priority", function()
			local char = makeChar()
			nullifyingStatus.new(char):Start()
			increaseStatus.new(char):Start()
			RunService.Heartbeat:Wait()
			expect(char:PredictDamage({
				Damage = 100,
				Source = nil,
			}).Damage).to.be.equal(0)
		end)
		it("should fire damage dealt callback", function()
			local char1 = makeChar()
			local char2 = makeChar()
			local __skill
			do
				local super = Skill
				__skill = setmetatable({}, {
					__tostring = function()
						return "__skill"
					end,
					__index = super,
				})
				__skill.__index = __skill
				function __skill.new(...)
					local self = setmetatable({}, __skill)
					return self:constructor(...) or self
				end
				function __skill:constructor(...)
					super.constructor(self, ...)
				end
				function __skill:OnStartServer()
					char2:TakeDamage(self:CreateDamageContainer(10))
				end
				__skill = SkillDecorator(__skill) or __skill
			end
			local skill = __skill.new(char1)
			local container = nil
			local enemy = nil
			char1.DamageDealt:Connect(function(_enemy, _container)
				enemy = _enemy
				container = _container
			end)
			skill:Start()
			RunService.Heartbeat:Wait()
			expect(container).to.be.ok()
			expect(enemy).to.be.equal(char2)
			local _result = container
			if _result ~= nil then
				_result = _result.Damage
			end
			expect(_result).to.be.equal(10)
			local _result_1 = container
			if _result_1 ~= nil then
				_result_1 = _result_1.Source
			end
			expect(_result_1).to.be.equal(skill)
		end)
	end)
	describe("destroy", function()
		it("should destroy successfully", function()
			local pass = false
			local char = makeChar()
			char.Destroyed:Connect(function()
				pass = true
			end)
			char:Destroy()
			RunService.Heartbeat:Wait()
			expect(pass).to.be.equal(true)
			expect(char:IsDestroyed()).to.be.equal(true)
		end)
		it("should destroy all skills and statuses", function()
			local char = makeChar()
			someStatus.new(char)
			someSkill.new(char)
			char:Destroy()
			RunService.Heartbeat:Wait()
			expect(#char:GetAllStatusEffects()).to.be.equal(0)
			expect(#char:GetSkills()).to.be.equal(0)
		end)
	end)
	describe("static", function()
		it("should return a valid character map", function()
			local map = Character.GetCharacterMap()
			expect(map).to.be.a("table")
			expect(table.isfrozen(map)).to.be.equal(true)
		end)
		it("should get the character using static methods", function()
			local char = makeChar()
			expect(Character.GetCharacterFromInstance(char.Instance)).to.be.equal(char)
			expect(Character._internal_GetCharacterFromId(char:_internal_GetId())).to.be.equal(char)
		end)
	end)
	afterAll(function()
		return janitor:Cleanup()
	end)
end
