-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local atom = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "charm").atom
local RunService = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "services").RunService
local consolePrefix = "WCS"
local errorString = `--// [{consolePrefix}]: Caught an error in your code //--`
local function logWarning(Message, DisplayTraceback)
	if DisplayTraceback == nil then
		DisplayTraceback = true
	end
	warn(`[{consolePrefix}]: {Message} \n \n {if DisplayTraceback then debug.traceback() else nil}`)
end
local function logError(Message, DisplayTraceback)
	if DisplayTraceback == nil then
		DisplayTraceback = true
	end
	return error(`\n {errorString} \n {Message} \n \n {if DisplayTraceback then debug.traceback() else nil}`)
end
local function mapToArray(Map)
	local arr = {}
	-- ▼ ReadonlyMap.forEach ▼
	local _callback = function(Value)
		local _value = Value
		table.insert(arr, _value)
		return #arr
	end
	for _k, _v in Map do
		_callback(_v, _k, Map)
	end
	-- ▲ ReadonlyMap.forEach ▲
	return arr
end
local function isConstructor(obj)
	local ctor = obj
	return ctor.new ~= nil or ctor.constructor ~= nil
end
local function createIdGenerator(initialValue, increment)
	if initialValue == nil then
		initialValue = 0
	end
	if increment == nil then
		increment = 1
	end
	return function()
		initialValue += increment
		return initialValue
	end
end
local function logMessage(Message)
	print(`[{consolePrefix}]: {Message}`)
end
local function isServerContext()
	return RunService:IsServer()
end
local function isClientContext()
	return RunService:IsClient() and RunService:IsRunning()
end
local function GetParamsFromMoveset(moveset, skill)
	if not moveset.ConstructorParams then
		return nil
	end
	local _condition = rawget(moveset.ConstructorParams, skill)
	if not (_condition ~= 0 and _condition == _condition and _condition ~= "" and _condition) then
		_condition = rawget(moveset.ConstructorParams, `{skill}`)
	end
	local params = _condition
	if params and not (type(params) == "table") then
		return nil
	end
	return params
end
local function instanceofConstructor(constructor, constructor2)
	local currentClass = constructor
	local metatable = getmetatable(currentClass)
	while true do
		if currentClass == constructor2 then
			return true
		end
		if not currentClass or not metatable then
			break
		end
		currentClass = metatable.__index
		metatable = getmetatable(currentClass)
	end
	return false
end
local activeHandler = nil
--* @internal 
local clientAtom = atom(nil)
local function setActiveHandler(handler)
	if activeHandler then
		return nil
	end
	activeHandler = handler
end
local function getActiveHandler()
	return activeHandler
end
local function freezeCheck(obj)
	local _ = not table.isfrozen(obj) and table.freeze(obj)
end
local function shallowEqual(a, b)
	for key, value in pairs(a) do
		if b[key] ~= value then
			return false
		end
	end
	for key, value in pairs(b) do
		if a[key] ~= value then
			return false
		end
	end
	return true
end
return {
	logWarning = logWarning,
	logError = logError,
	mapToArray = mapToArray,
	isConstructor = isConstructor,
	createIdGenerator = createIdGenerator,
	logMessage = logMessage,
	isServerContext = isServerContext,
	isClientContext = isClientContext,
	GetParamsFromMoveset = GetParamsFromMoveset,
	instanceofConstructor = instanceofConstructor,
	setActiveHandler = setActiveHandler,
	getActiveHandler = getActiveHandler,
	freezeCheck = freezeCheck,
	shallowEqual = shallowEqual,
	consolePrefix = consolePrefix,
	clientAtom = clientAtom,
}
