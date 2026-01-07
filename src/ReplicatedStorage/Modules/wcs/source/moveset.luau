-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local Signal = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "sleitnick-signal")
local t = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "t", "lib", "ts").t
local SkillBase = TS.import(script, script.Parent, "skill").SkillBase
local _utility = TS.import(script, script.Parent, "utility")
local freezeCheck = _utility.freezeCheck
local instanceofConstructor = _utility.instanceofConstructor
local logError = _utility.logError
local registeredMovesets = {}
--[[
	*
	 * Creates a moveset with the given name and skills.
	 
]]
local function CreateMoveset(Name, Skills, ConstructorParams)
	local _name = Name
	if registeredMovesets[_name] ~= nil then
		logError(`Moveset with name {Name} was already registered before`)
	end
	if not t.table(Skills) then
		logError("Skills you provided is not a valid array")
	end
	-- ▼ ReadonlyArray.forEach ▼
	local _callback = function(T)
		if not t.table(T) or not instanceofConstructor(T, SkillBase) then
			logError(`{T} is not a valid skill constructor`)
		end
	end
	for _k, _v in Skills do
		_callback(_v, _k - 1, Skills)
	end
	-- ▲ ReadonlyArray.forEach ▲
	local moveset = {
		Name = Name,
		Skills = Skills,
		ConstructorParams = ConstructorParams,
		OnCharacterAdded = Signal.new(),
		OnCharacterRemoved = Signal.new(),
	}
	local _name_1 = Name
	registeredMovesets[_name_1] = moveset
	setmetatable(moveset, {
		__tostring = function()
			return Name
		end,
	})
	freezeCheck(moveset)
	freezeCheck(moveset.Skills)
	return moveset
end
--[[
	*
	 * Retrieves the moveset object by its name.
	 
]]
local function GetMovesetObjectByName(Name)
	local _name = Name
	return registeredMovesets[_name]
end
return {
	CreateMoveset = CreateMoveset,
	GetMovesetObjectByName = GetMovesetObjectByName,
}
