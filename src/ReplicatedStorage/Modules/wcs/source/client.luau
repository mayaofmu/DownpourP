-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local Reflect = TS.import(script, script.Parent.Parent, "include", "node_modules", "@flamework", "core", "out").Reflect
local subscribe = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "charm").subscribe
local CharmSync = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "charm-sync")
local t = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "t", "lib", "ts").t
local _utility = TS.import(script, script.Parent, "utility")
local clientAtom = _utility.clientAtom
local isServerContext = _utility.isServerContext
local logError = _utility.logError
local logMessage = _utility.logMessage
local logWarning = _utility.logWarning
local setActiveHandler = _utility.setActiveHandler
local RestoreArgs = TS.import(script, script.Parent, "arg-converter").RestoreArgs
local Character = TS.import(script, script.Parent, "character").Character
local Flags = TS.import(script, script.Parent, "flags").Flags
local _message = TS.import(script, script.Parent, "message")
local INVALID_MESSAGE_STR = _message.INVALID_MESSAGE_STR
local ValidateArgs = _message.ValidateArgs
local _networking = TS.import(script, script.Parent, "networking")
local ClientEvents = _networking.ClientEvents
local ClientFunctions = _networking.ClientFunctions
local messageSerializer = TS.import(script, script.Parent, "serdes").messageSerializer
local currentInstance = nil
local Client
do
	Client = setmetatable({}, {
		__tostring = function()
			return "Client"
		end,
	})
	Client.__index = Client
	function Client.new(...)
		local self = setmetatable({}, Client)
		return self:constructor(...) or self
	end
	function Client:constructor()
		self._internal_isActive = false
		self._internal_registeredModules = {}
		self._internal_clientSyncer = CharmSync.client({
			atoms = {
				atom = clientAtom,
			},
			ignoreUnhydrated = false,
		})
		currentInstance = self
	end
	function Client:RegisterDirectory(Directory)
		if self._internal_isActive then
			logWarning("Cannot register directory after :Start()")
			return nil
		end
		if not t.Instance(Directory) then
			logWarning("Provided directory is not an instance!")
			return nil
		end
		local _exp = Directory:GetDescendants()
		-- ▼ ReadonlyArray.forEach ▼
		local _callback = function(Descendant)
			if not Descendant:IsA("ModuleScript") then
				return nil
			end
			local __internal_registeredModules = self._internal_registeredModules
			local _descendant = Descendant
			table.insert(__internal_registeredModules, _descendant)
		end
		for _k, _v in _exp do
			_callback(_v, _k - 1, _exp)
		end
		-- ▲ ReadonlyArray.forEach ▲
	end
	function Client:Start()
		if self._internal_isActive then
			logWarning("Attempted to :Start() Client twice!")
			return nil
		end
		local _exp = self._internal_registeredModules
		-- ▼ ReadonlyArray.forEach ▼
		local _callback = function(v)
			return require(v)
		end
		for _k, _v in _exp do
			_callback(_v, _k - 1, _exp)
		end
		-- ▲ ReadonlyArray.forEach ▲
		table.clear(self._internal_registeredModules)
		self._internal_isActive = true
		setActiveHandler(self)
		self:_internal_setupCharacterReplication()
		ClientEvents.sync:connect(function(payloads)
			self._internal_clientSyncer:sync(unpack(payloads))
		end)
		ClientEvents.start()
		ClientEvents.damageTaken:connect(function(Damage)
			local character = Character.GetLocalCharacter()
			if character then
				character.DamageTaken:Fire({
					Damage = Damage,
					Source = nil,
				})
			end
		end)
		ClientEvents.damageDealt:connect(function(SourceId, Type, Damage)
			local character = Character.GetLocalCharacter()
			local source = nil
			if not character then
				return nil
			end
			for _, object in character[if Type == "Skill" then "GetSkills" else "GetAllStatusEffects"](character) do
				if object:_internal_GetId() == SourceId then
					source = object
					break
				end
			end
			character.DamageDealt:Fire(nil, {
				Damage = Damage,
				Source = source,
			})
		end)
		local eventHandler = function(serialized)
			local _binding = messageSerializer.deserialize(serialized.buffer, serialized.blobs)
			local Name = _binding[1]
			local MethodName = _binding[2]
			local PackedArgs = _binding[3]
			local character = Character.GetLocalCharacter()
			if not character then
				return nil
			end
			local skill = character:GetSkillFromString(Name)
			if not skill then
				return nil
			end
			local args = RestoreArgs(PackedArgs)
			local config = Reflect.getMetadata(skill, `Config_{MethodName}`)
			local _result = config
			if _result ~= nil then
				_result = _result.OnlyWhenActive
			end
			local _condition = _result
			if _condition then
				_condition = not skill:GetState().IsActive
			end
			if _condition then
				return nil
			end
			local _result_1 = config
			if _result_1 ~= nil then
				_result_1 = _result_1.Validators
			end
			if _result_1 then
				if not ValidateArgs(config.Validators, args) then
					return nil
				end
			end
			local method = skill[MethodName]
			method(skill, unpack(args))
		end
		ClientEvents.messageToClient:connect(eventHandler)
		ClientEvents.messageToClient_urel:connect(eventHandler)
		ClientFunctions.messageToClient:setCallback(function(serialized)
			local _binding = messageSerializer.deserialize(serialized.buffer, serialized.blobs)
			local Name = _binding[1]
			local MethodName = _binding[2]
			local PackedArgs = _binding[3]
			local character = Character.GetLocalCharacter()
			if not character then
				return nil
			end
			local skill = character:GetSkillFromString(Name)
			if not skill then
				return nil
			end
			local args = RestoreArgs(PackedArgs)
			local config = Reflect.getMetadata(skill, `Config_{MethodName}`)
			local _result = config
			if _result ~= nil then
				_result = _result.OnlyWhenActive
			end
			local _condition = _result
			if _condition then
				_condition = not skill:GetState().IsActive
			end
			if _condition then
				return INVALID_MESSAGE_STR
			end
			local _result_1 = config
			if _result_1 ~= nil then
				_result_1 = _result_1.Validators
			end
			if _result_1 then
				if not ValidateArgs(config.Validators, args) then
					return INVALID_MESSAGE_STR
				end
			end
			local method = skill[MethodName]
			local returnedValue = method(skill, unpack(args))
			if TS.Promise.is(returnedValue) then
				local success, value = returnedValue:await()
				return if success then value else INVALID_MESSAGE_STR
			end
			return returnedValue
		end)
		logMessage("Started Client successfully")
	end
	function Client:_internal_setupCharacterReplication()
		local character
		subscribe(clientAtom, function(data)
			local _condition = not data
			if not _condition then
				local _result = character
				if _result ~= nil then
					_result = _result.Instance
				end
				_condition = _result ~= data.instance
			end
			if _condition then
				local _result = character
				if _result ~= nil then
					_result:Destroy(Flags.CanDestroyLocallyClient)
				end
				character = nil
			end
			if data and not character then
				character = Character.new(data.instance, Flags.CanCreateCharacterClient)
			end
		end)
	end
end
local function CreateClient()
	if isServerContext() then
		logError("Attempted to instantiate Client handler on server side!")
	end
	if currentInstance then
		logWarning("Attempted to instantiate Client twice. \n Framework does not allow multiple Client instances!")
		return currentInstance
	end
	return Client.new()
end
return {
	CreateClient = CreateClient,
}
