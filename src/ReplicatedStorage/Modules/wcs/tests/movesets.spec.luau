-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
--/ <reference types="@rbxts/testez/globals" />
local Janitor = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "janitor", "src").Janitor
local _services = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "services")
local RunService = _services.RunService
local Workspace = _services.Workspace
local _exports = TS.import(script, script.Parent.Parent, "exports")
local Character = _exports.Character
local CreateMoveset = _exports.CreateMoveset
local GetMovesetObjectByName = _exports.GetMovesetObjectByName
local Skill = _exports.Skill
local SkillDecorator = _exports.SkillDecorator
return function()
	local janitor = Janitor.new()
	local function makeChar()
		local part = Instance.new("Part")
		Instance.new("Humanoid", part)
		janitor:Add(part)
		local character = Character.new(part)
		janitor:Add(character)
		return character
	end
	it("should register a moveset", function()
		expect(CreateMoveset("__any", {})).to.be.ok()
	end)
	it("should index a moveset", function()
		local moveset = CreateMoveset("____any", {})
		expect(GetMovesetObjectByName(moveset.Name)).to.be.equal(moveset)
	end)
	it("should error if not a valid array", function()
		expect(function()
			return CreateMoveset("_smhsmh", Workspace)
		end).to:throw("array")
	end)
	it("should respect constructor arguments", function()
		local passedArg
		local test_skill1
		do
			local super = Skill
			test_skill1 = setmetatable({}, {
				__tostring = function()
					return "test_skill1"
				end,
				__index = super,
			})
			test_skill1.__index = test_skill1
			function test_skill1.new(...)
				local self = setmetatable({}, test_skill1)
				return self:constructor(...) or self
			end
			function test_skill1:constructor(...)
				super.constructor(self, ...)
			end
			function test_skill1:OnConstructServer(Args_0)
				passedArg = Args_0
			end
			test_skill1 = SkillDecorator(test_skill1) or test_skill1
		end
		local moveset = CreateMoveset("someMoveset", { test_skill1 }, {
			test_skill1 = { 10 },
		})
		local char = makeChar()
		char:ApplyMoveset(moveset)
		RunService.Heartbeat:Wait()
		expect(passedArg).to.be.equal(10)
	end)
	it("should fire events", function()
		local i = 0
		local test_skill2
		do
			local super = Skill
			test_skill2 = setmetatable({}, {
				__tostring = function()
					return "test_skill2"
				end,
				__index = super,
			})
			test_skill2.__index = test_skill2
			function test_skill2.new(...)
				local self = setmetatable({}, test_skill2)
				return self:constructor(...) or self
			end
			function test_skill2:constructor(...)
				super.constructor(self, ...)
			end
			test_skill2 = SkillDecorator(test_skill2) or test_skill2
		end
		local moveset = CreateMoveset("someMoveset2", { test_skill2 })
		moveset.OnCharacterAdded:Once(function()
			local _original = i
			i += 1
			return _original
		end)
		moveset.OnCharacterRemoved:Once(function()
			local _original = i
			i += 1
			return _original
		end)
		local char = makeChar()
		char:ApplyMoveset(moveset)
		char:ClearMoveset()
		expect(i).to.be.equal(2)
	end)
	it("should not accept invalid skills", function()
		expect(function()
			return CreateMoveset("_smhsrmh", { {} })
		end).to:throw("constructor")
	end)
	it("should be okay if valid", function()
		local someskill111
		do
			local super = Skill
			someskill111 = setmetatable({}, {
				__tostring = function()
					return "someskill111"
				end,
				__index = super,
			})
			someskill111.__index = someskill111
			function someskill111.new(...)
				local self = setmetatable({}, someskill111)
				return self:constructor(...) or self
			end
			function someskill111:constructor(...)
				super.constructor(self, ...)
			end
			someskill111 = SkillDecorator(someskill111) or someskill111
		end
		expect(function()
			return CreateMoveset("_somemovset1", { someskill111 })
		end).to.be.ok()
	end)
	afterAll(function()
		return janitor:Cleanup()
	end)
end
