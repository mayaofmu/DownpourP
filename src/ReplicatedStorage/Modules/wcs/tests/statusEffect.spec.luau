-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local Janitor = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "janitor", "src").Janitor
local RunService = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "services").RunService
local _exports = TS.import(script, script.Parent.Parent, "exports")
local Character = _exports.Character
local StatusEffect = _exports.StatusEffect
local StatusEffectDecorator = _exports.StatusEffectDecorator
return function()
	local janitor = Janitor.new()
	local emptyStatus
	do
		local super = StatusEffect
		emptyStatus = setmetatable({}, {
			__tostring = function()
				return "emptyStatus"
			end,
			__index = super,
		})
		emptyStatus.__index = emptyStatus
		function emptyStatus.new(...)
			local self = setmetatable({}, emptyStatus)
			return self:constructor(...) or self
		end
		function emptyStatus:constructor(...)
			super.constructor(self, ...)
		end
		function emptyStatus:changeMeta(newMeta)
			self:SetMetadata(newMeta)
		end
		function emptyStatus:clearMeta()
			self:ClearMetadata()
		end
		emptyStatus = StatusEffectDecorator(emptyStatus) or emptyStatus
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
		it("should create a new status", function()
			expect(emptyStatus.new(makeChar())).to.be.ok()
		end)
		it("should not allow double registration", function()
			expect(function()
				local emptyStatus
				do
					local super = StatusEffect
					emptyStatus = setmetatable({}, {
						__tostring = function()
							return "emptyStatus"
						end,
						__index = super,
					})
					emptyStatus.__index = emptyStatus
					function emptyStatus.new(...)
						local self = setmetatable({}, emptyStatus)
						return self:constructor(...) or self
					end
					function emptyStatus:constructor(...)
						super.constructor(self, ...)
					end
					emptyStatus = StatusEffectDecorator(emptyStatus) or emptyStatus
				end
			end).to:throw()
		end)
		it("should check for applied decorator", function()
			local wrongStatus
			do
				local super = StatusEffect
				wrongStatus = setmetatable({}, {
					__tostring = function()
						return "wrongStatus"
					end,
					__index = super,
				})
				wrongStatus.__index = wrongStatus
				function wrongStatus.new(...)
					local self = setmetatable({}, wrongStatus)
					return self:constructor(...) or self
				end
				function wrongStatus:constructor(...)
					super.constructor(self, ...)
				end
			end
			expect(function()
				return wrongStatus.new(makeChar())
			end).to:throw("decorator")
		end)
	end)
	describe("startup / ending", function()
		it("should start a status", function()
			local char = makeChar()
			local status = emptyStatus.new(char)
			local changed = false
			status.Started:Connect(function()
				changed = true
			end)
			status:Start()
			RunService.Heartbeat:Wait()
			expect(#char:GetAllActiveStatusEffects()).to.be.equal(1)
			expect(changed).to.be.equal(true)
			expect(status:GetState().IsActive).to.be.equal(true)
		end)
		it("should end a status", function()
			local char = makeChar()
			local status = emptyStatus.new(char)
			status:Start()
			local changed = false
			status.Ended:Connect(function()
				changed = true
			end)
			status:End()
			RunService.Heartbeat:Wait()
			expect(#char:GetAllActiveStatusEffects()).to.be.equal(0)
			expect(status:GetState().IsActive).to.be.equal(false)
			expect(changed).to.be.equal(true)
		end)
		it("should destroy a status", function()
			local status = emptyStatus.new(makeChar())
			expect(status:IsDestroyed()).to.be.equal(false)
			local changed = false
			status.Destroyed:Connect(function()
				changed = true
			end)
			status:Destroy()
			RunService.Heartbeat:Wait()
			expect(status:IsDestroyed()).to.be.equal(true)
			expect(changed).to.be.equal(true)
		end)
	end)
	describe("methods / callbacks", function()
		it("should set/get metadata", function()
			local status = emptyStatus.new(makeChar())
			expect(status:GetMetadata()).to.never.be.ok()
			local changed = false
			status.MetadataChanged:Connect(function()
				changed = true
			end)
			status:changeMeta(5)
			RunService.Heartbeat:Wait()
			expect(status:GetMetadata()).to.be.equal(5)
			expect(changed).to.be.equal(true)
		end)
		it("should clear metadata", function()
			local status = emptyStatus.new(makeChar())
			status:changeMeta(5)
			status:clearMeta()
			RunService.Heartbeat:Wait()
			expect(status:GetMetadata()).to.never.be.ok()
		end)
		it("should fire callbacks", function()
			local changed = {}
			local statusWithCallback
			do
				local super = StatusEffect
				statusWithCallback = setmetatable({}, {
					__tostring = function()
						return "statusWithCallback"
					end,
					__index = super,
				})
				statusWithCallback.__index = statusWithCallback
				function statusWithCallback.new(...)
					local self = setmetatable({}, statusWithCallback)
					return self:constructor(...) or self
				end
				function statusWithCallback:constructor(...)
					super.constructor(self, ...)
				end
				function statusWithCallback:OnStartServer()
					table.insert(changed, true)
				end
				function statusWithCallback:OnConstruct()
					table.insert(changed, true)
				end
				function statusWithCallback:OnConstructServer()
					table.insert(changed, true)
				end
				statusWithCallback = StatusEffectDecorator(statusWithCallback) or statusWithCallback
			end
			local status = statusWithCallback.new(makeChar())
			status:Start()
			RunService.Heartbeat:Wait()
			expect(#changed).to.be.equal(3)
		end)
	end)
	describe("destruction", function()
		it("should destroy a status", function()
			local status = emptyStatus.new(makeChar())
			expect(status:IsDestroyed()).to.be.equal(false)
			local changed = false
			status.Destroyed:Connect(function()
				changed = true
			end)
			status:Destroy()
			RunService.Heartbeat:Wait()
			expect(status:IsDestroyed()).to.be.equal(true)
			expect(changed).to.be.equal(true)
		end)
	end)
	afterAll(function()
		return janitor:Cleanup()
	end)
end
