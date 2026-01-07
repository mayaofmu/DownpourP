-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local _core = TS.import(script, script.Parent.Parent, "include", "node_modules", "@flamework", "core", "out")
local Flamework = _core.Flamework
local Reflect = _core.Reflect
local RunService = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "services").RunService
local t = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "t", "lib", "ts").t
local ConvertArgs = TS.import(script, script.Parent, "arg-converter").ConvertArgs
local _networking = TS.import(script, script.Parent, "networking")
local ClientEvents = _networking.ClientEvents
local ClientFunctions = _networking.ClientFunctions
local ServerEvents = _networking.ServerEvents
local ServerFunctions = _networking.ServerFunctions
local messageSerializer = TS.import(script, script.Parent, "serdes").messageSerializer
local SkillBase = TS.import(script, script.Parent, "skill").SkillBase
local _utility = TS.import(script, script.Parent, "utility")
local instanceofConstructor = _utility.instanceofConstructor
local isClientContext = _utility.isClientContext
local isServerContext = _utility.isServerContext
local logError = _utility.logError
--[[
	*
	 * @hidden
	 
]]
local INVALID_MESSAGE_STR = "__WCS_INVALID_MESSAGE"
local registeredMessages = {}
local optionsGuard = Flamework.createGuard(t.interface({
	Unreliable = t.optional(t.boolean),
	Destination = t.literal("Server", "Client"),
	Type = t.literal("Event", "Request"),
	Validators = t.optional(t.array(t.callback)),
	OnlyWhenActive = t.optional(t.boolean),
	ValueValidator = t.optional(t.callback),
}))
--* @internal @hidden 
local function ValidateArgs(validators, args)
	if not t.strictArray(unpack(validators))(args) then
		return false
	end
	return true
end
local function Message(Options)
	return function(ctor, methodName, _)
		if not instanceofConstructor(ctor, SkillBase) then
			logError(`{ctor} is not a valid skill constructor.`)
		end
		local _value = rawget(ctor, methodName)
		if not (_value ~= 0 and _value == _value and _value ~= "" and _value) then
			logError(`{ctor} does not have a method named {methodName}.`)
		end
		if Options.Destination ~= "Server" and Options.Destination ~= "Client" then
			logError(`Invalid message destination. Must be "Server" or "Client".`)
		end
		if Options.Type ~= "Event" and Options.Type ~= "Request" then
			logError(`Invalid message type. Must be "Event" or "Request".`)
		end
		if Options.Type ~= "Event" and Options.Unreliable then
			logError(`Unreliable messages must be of type "Event."`)
		end
		if Options.ValueValidator and Options.Type ~= "Request" then
			logError("Value Validator can only be used with requests.")
		end
		if not optionsGuard(Options) then
			logError("Invalid message options. Your Options object did not pass the guard.")
		end
		local _ctor = ctor
		local _result = registeredMessages[_ctor]
		if _result ~= nil then
			local _methodName = methodName
			_result = table.find(_result, _methodName) ~= nil
		end
		if _result then
			logError(`Message {methodName} is already registered.`)
		end
		local _exp = ctor
		local _array = {}
		local _length = #_array
		local _ctor_1 = ctor
		local _condition = registeredMessages[_ctor_1]
		if _condition == nil then
			_condition = {}
		end
		local _Length = #_condition
		table.move(_condition, 1, _Length, _length + 1, _array)
		_length += _Length
		_array[_length + 1] = methodName
		registeredMessages[_exp] = _array
		local current = if RunService:IsServer() then "Server" else "Client"
		if Options.Validators and current == Options.Destination then
			Reflect.defineMetadata(ctor, `Config_{methodName}`, Options)
		end
		if current == Options.Destination then
			return nil
		end
		ctor[methodName] = function(self, ...)
			local args = { ... }
			if not self.Player then
				return nil
			end
			local serialized = messageSerializer.serialize({ self.Name, methodName, ConvertArgs(args) })
			if Options.Type == "Event" then
				if RunService:IsServer() then
					local event = if Options.Unreliable then ServerEvents.messageToClient_urel else ServerEvents.messageToClient
					event:fire(self.Player, serialized)
					return nil
				end
				if RunService:IsClient() then
					local event = if Options.Unreliable then ClientEvents.messageToServer_urel else ClientEvents.messageToServer
					event:fire(serialized)
					return nil
				end
				return nil
			end
			local promise
			if isServerContext() then
				promise = ServerFunctions.messageToClient:invoke(self.Player, serialized)
			elseif isClientContext() then
				promise = ClientFunctions.messageToServer:invoke(serialized)
			end
			local outputPromise = TS.Promise.new(function(resolve, reject)
				promise:andThen(function(value)
					return if value == INVALID_MESSAGE_STR or (Options.ValueValidator and not Options.ValueValidator(value)) then reject("Arguments did not pass validation.") else resolve(value)
				end, reject)
			end)
			local connection = self.Destroyed:Once(function()
				return outputPromise:cancel()
			end)
			outputPromise:finally(function()
				return connection:Disconnect()
			end)
			return outputPromise
		end
	end
end
return {
	ValidateArgs = ValidateArgs,
	Message = Message,
	INVALID_MESSAGE_STR = INVALID_MESSAGE_STR,
}
