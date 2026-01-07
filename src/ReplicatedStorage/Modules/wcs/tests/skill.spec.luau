-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
--/ <reference types="@rbxts/testez/globals" />
local Janitor = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "janitor", "src").Janitor
local RunService = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "services").RunService
local t = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "t", "lib", "ts").t
local _exports = TS.import(script, script.Parent.Parent, "exports")
local Character = _exports.Character
local HoldableSkill = _exports.HoldableSkill
local Skill = _exports.Skill
local SkillDecorator = _exports.SkillDecorator
local SkillType = _exports.SkillType
return function()
	local janitor = Janitor.new()
	local yieldingSkill
	do
		local super = Skill
		yieldingSkill = setmetatable({}, {
			__tostring = function()
				return "yieldingSkill"
			end,
			__index = super,
		})
		yieldingSkill.__index = yieldingSkill
		function yieldingSkill.new(...)
			local self = setmetatable({}, yieldingSkill)
			return self:constructor(...) or self
		end
		function yieldingSkill:constructor(...)
			super.constructor(self, ...)
		end
		function yieldingSkill:OnStartServer()
			task.wait(1)
		end
		function yieldingSkill:setCheckedByOthers(check)
			self.CheckedByOthers = check
		end
		yieldingSkill = SkillDecorator(yieldingSkill) or yieldingSkill
	end
	local yieldingSkill2
	do
		local super = Skill
		yieldingSkill2 = setmetatable({}, {
			__tostring = function()
				return "yieldingSkill2"
			end,
			__index = super,
		})
		yieldingSkill2.__index = yieldingSkill2
		function yieldingSkill2.new(...)
			local self = setmetatable({}, yieldingSkill2)
			return self:constructor(...) or self
		end
		function yieldingSkill2:constructor(...)
			super.constructor(self, ...)
		end
		function yieldingSkill2:OnStartServer()
			task.wait(1)
		end
		yieldingSkill2 = SkillDecorator(yieldingSkill2) or yieldingSkill2
	end
	local emptySkill
	do
		local super = Skill
		emptySkill = setmetatable({}, {
			__tostring = function()
				return "emptySkill"
			end,
			__index = super,
		})
		emptySkill.__index = emptySkill
		function emptySkill.new(...)
			local self = setmetatable({}, emptySkill)
			return self:constructor(...) or self
		end
		function emptySkill:constructor(...)
			super.constructor(self, ...)
		end
		function emptySkill:changeMeta(meta)
			self:SetMetadata(meta)
		end
		function emptySkill:setCheckOthers(check)
			self.CheckOthersActive = check
		end
		emptySkill = SkillDecorator(emptySkill) or emptySkill
	end
	local holdableSkill
	do
		local super = HoldableSkill
		holdableSkill = setmetatable({}, {
			__tostring = function()
				return "holdableSkill"
			end,
			__index = super,
		})
		holdableSkill.__index = holdableSkill
		function holdableSkill.new(...)
			local self = setmetatable({}, holdableSkill)
			return self:constructor(...) or self
		end
		function holdableSkill:constructor(...)
			super.constructor(self, ...)
		end
		function holdableSkill:OnConstructServer()
			self:SetMaxHoldTime(5)
		end
		function holdableSkill:setTime(newTime)
			self:SetMaxHoldTime(newTime)
		end
		holdableSkill = SkillDecorator(holdableSkill) or holdableSkill
	end
	local debounceSkill
	do
		local super = Skill
		debounceSkill = setmetatable({}, {
			__tostring = function()
				return "debounceSkill"
			end,
			__index = super,
		})
		debounceSkill.__index = debounceSkill
		function debounceSkill.new(...)
			local self = setmetatable({}, debounceSkill)
			return self:constructor(...) or self
		end
		function debounceSkill:constructor(...)
			super.constructor(self, ...)
		end
		function debounceSkill:OnStartServer()
			self:ApplyCooldown(2)
		end
		debounceSkill = SkillDecorator(debounceSkill) or debounceSkill
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
		it("should instantiate a skill", function()
			expect(emptySkill.new(makeChar())).to.be.ok()
		end)
		it("should check for applied decorator", function()
			local wrongSkill
			do
				local super = Skill
				wrongSkill = setmetatable({}, {
					__tostring = function()
						return "wrongSkill"
					end,
					__index = super,
				})
				wrongSkill.__index = wrongSkill
				function wrongSkill.new(...)
					local self = setmetatable({}, wrongSkill)
					return self:constructor(...) or self
				end
				function wrongSkill:constructor(...)
					super.constructor(self, ...)
				end
			end
			expect(function()
				return wrongSkill.new(makeChar())
			end).to:throw("decorator")
		end)
		it("should not allow double registration", function()
			expect(function()
				local emptySkill
				do
					local super = Skill
					emptySkill = setmetatable({}, {
						__tostring = function()
							return "emptySkill"
						end,
						__index = super,
					})
					emptySkill.__index = emptySkill
					function emptySkill.new(...)
						local self = setmetatable({}, emptySkill)
						return self:constructor(...) or self
					end
					function emptySkill:constructor(...)
						super.constructor(self, ...)
					end
					emptySkill = SkillDecorator(emptySkill) or emptySkill
				end
			end).to:throw()
		end)
	end)
	describe("startup / ending", function()
		it("should start a skill", function()
			local skill = yieldingSkill.new(makeChar())
			local changed = false
			skill.Started:Connect(function()
				changed = true
			end)
			skill:Start()
			RunService.Heartbeat:Wait()
			expect(changed).to.be.equal(true)
			expect(skill:GetState().IsActive).to.be.equal(true)
		end)
		it("should pass starter params", function()
			local param
			local sum_skill_a
			do
				local super = Skill
				sum_skill_a = setmetatable({}, {
					__tostring = function()
						return "sum_skill_a"
					end,
					__index = super,
				})
				sum_skill_a.__index = sum_skill_a
				function sum_skill_a.new(...)
					local self = setmetatable({}, sum_skill_a)
					return self:constructor(...) or self
				end
				function sum_skill_a:constructor(...)
					super.constructor(self, ...)
				end
				function sum_skill_a:OnStartServer(a)
					param = a
				end
				sum_skill_a = SkillDecorator(sum_skill_a) or sum_skill_a
			end
			local char = makeChar()
			local skill = sum_skill_a.new(char)
			skill:Start(10)
			RunService.Heartbeat:Wait()
			expect(param).to.be.equal(10)
		end)
		it("should validate starter params", function()
			local sum_skill_b
			do
				local super = Skill
				sum_skill_b = setmetatable({}, {
					__tostring = function()
						return "sum_skill_b"
					end,
					__index = super,
				})
				sum_skill_b.__index = sum_skill_b
				function sum_skill_b.new(...)
					local self = setmetatable({}, sum_skill_b)
					return self:constructor(...) or self
				end
				function sum_skill_b:constructor(...)
					super.constructor(self, ...)
					self.ParamValidators = { t.number }
				end
				function sum_skill_b:OnStartServer(a)
					task.wait(1)
				end
				sum_skill_b = SkillDecorator(sum_skill_b) or sum_skill_b
			end
			local skill = sum_skill_b.new(makeChar())
			skill:Start("")
			RunService.Heartbeat:Wait()
			expect(skill:GetState().IsActive).to.be.equal(false)
		end)
		it("should check if other skills are active", function()
			local char = makeChar()
			local skill_a = yieldingSkill.new(char)
			local skill_b = yieldingSkill2.new(char)
			skill_a:Start()
			skill_b:Start()
			RunService.Heartbeat:Wait()
			expect(skill_b:GetState().IsActive).to.be.equal(false)
		end)
		it("should cancel the execution thread on end", function()
			local thread
			local yieldingSkill3
			do
				local super = Skill
				yieldingSkill3 = setmetatable({}, {
					__tostring = function()
						return "yieldingSkill3"
					end,
					__index = super,
				})
				yieldingSkill3.__index = yieldingSkill3
				function yieldingSkill3.new(...)
					local self = setmetatable({}, yieldingSkill3)
					return self:constructor(...) or self
				end
				function yieldingSkill3:constructor(...)
					super.constructor(self, ...)
				end
				function yieldingSkill3:OnStartServer()
					thread = coroutine.running()
					task.wait(5)
				end
				yieldingSkill3 = SkillDecorator(yieldingSkill3) or yieldingSkill3
			end
			local skill = yieldingSkill3.new(makeChar())
			skill:Start()
			RunService.Heartbeat:Wait()
			expect(thread).to.be.a("thread")
			skill:End()
			RunService.Heartbeat:Wait()
			expect(coroutine.status(thread)).to.be.equal("dead")
		end)
		it("should respect checked by others", function()
			local char = makeChar()
			local skill_a = yieldingSkill.new(char)
			local skill_b = yieldingSkill2.new(char)
			skill_a:setCheckedByOthers(false)
			skill_a:Start()
			skill_b:Start()
			RunService.Heartbeat:Wait()
			expect(skill_b:GetState().IsActive).to.be.equal(true)
		end)
		it("should end a skill", function()
			local skill = yieldingSkill.new(makeChar())
			skill:Start()
			local changed = false
			skill.Ended:Connect(function()
				changed = true
			end)
			skill:End()
			RunService.Heartbeat:Wait()
			expect(skill:GetState().IsActive).to.be.equal(false)
			expect(changed).to.be.equal(true)
		end)
		it("should clean the janitor after skill ends", function()
			local changed = false
			local sumsumSkill
			do
				local super = Skill
				sumsumSkill = setmetatable({}, {
					__tostring = function()
						return "sumsumSkill"
					end,
					__index = super,
				})
				sumsumSkill.__index = sumsumSkill
				function sumsumSkill.new(...)
					local self = setmetatable({}, sumsumSkill)
					return self:constructor(...) or self
				end
				function sumsumSkill:constructor(...)
					super.constructor(self, ...)
				end
				function sumsumSkill:OnConstructServer()
					self.Janitor:Add(function()
						changed = true
					end)
				end
				sumsumSkill = SkillDecorator(sumsumSkill) or sumsumSkill
			end
			local skill = sumsumSkill.new(makeChar())
			skill:Start()
			RunService.Heartbeat:Wait()
			expect(changed).to.be.equal(true)
		end)
	end)
	describe("destruction", function()
		it("should destroy a skill", function()
			local skill = emptySkill.new(makeChar())
			expect(skill:IsDestroyed()).to.be.equal(false)
			local changed = false
			skill.Destroyed:Connect(function()
				changed = true
			end)
			skill:Destroy()
			RunService.Heartbeat:Wait()
			expect(skill:IsDestroyed()).to.be.equal(true)
			expect(changed).to.be.equal(true)
		end)
	end)
	describe("methods / callbacks", function()
		it("should set/get metadata", function()
			local skill = emptySkill.new(makeChar())
			expect(skill:GetMetadata()).to.never.be.ok()
			local changed = false
			skill.MetadataChanged:Connect(function()
				changed = true
			end)
			skill:changeMeta(5)
			RunService.Heartbeat:Wait()
			expect(skill:GetMetadata()).to.be.equal(5)
			expect(changed).to.be.equal(true)
		end)
		it("should give end timestamp if is on cooldown", function()
			local skill = debounceSkill.new(makeChar())
			expect(skill:GetDebounceEndTimestamp()).to.never.be.ok()
			skill:Start()
			RunService.Heartbeat:Wait()
			expect(skill:GetDebounceEndTimestamp()).to.be.a("number")
		end)
		it("should fire callbacks", function()
			local changed = {}
			local skillWithCallback
			do
				local super = Skill
				skillWithCallback = setmetatable({}, {
					__tostring = function()
						return "skillWithCallback"
					end,
					__index = super,
				})
				skillWithCallback.__index = skillWithCallback
				function skillWithCallback.new(...)
					local self = setmetatable({}, skillWithCallback)
					return self:constructor(...) or self
				end
				function skillWithCallback:constructor(...)
					super.constructor(self, ...)
				end
				function skillWithCallback:OnStartServer()
					table.insert(changed, true)
				end
				function skillWithCallback:OnConstruct()
					table.insert(changed, true)
				end
				function skillWithCallback:OnConstructServer()
					table.insert(changed, true)
				end
				skillWithCallback = SkillDecorator(skillWithCallback) or skillWithCallback
			end
			local skill = skillWithCallback.new(makeChar())
			skill:Start()
			RunService.Heartbeat:Wait()
			expect(#changed).to.be.equal(3)
		end)
		it("should return a valid skill type", function()
			local skill = emptySkill.new(makeChar())
			expect(skill:GetSkillType()).to.be.equal(SkillType.Default)
		end)
		it("should return a valid name", function()
			local skill = emptySkill.new(makeChar())
			expect(skill:GetName()).to.be.equal(tostring(emptySkill))
		end)
	end)
	describe("holdable", function()
		it("should instantiate a skill", function()
			expect(holdableSkill.new(makeChar())).to.be.ok()
		end)
		it("should set/get max hold time", function()
			local skill = holdableSkill.new(makeChar())
			skill:setTime(5)
			expect(skill:GetMaxHoldTime()).to.be.equal(5)
		end)
	end)
	afterAll(function()
		return janitor:Cleanup()
	end)
end
