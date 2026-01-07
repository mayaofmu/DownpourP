-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local Reflect = TS.import(script, script.Parent.Parent, "include", "node_modules", "@flamework", "core", "out").Reflect
local atom = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "charm").atom
local CharmSync = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "charm-sync")
local Players = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "services").Players
local t = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "t", "lib", "ts").t
local _utility = TS.import(script, script.Parent, "utility")
local isClientContext = _utility.isClientContext
local logError = _utility.logError
local logMessage = _utility.logMessage
local logWarning = _utility.logWarning
local setActiveHandler = _utility.setActiveHandler
local RestoreArgs = TS.import(script, script.Parent, "arg-converter").RestoreArgs
local Character = TS.import(script, script.Parent, "character").Character
local _message = TS.import(script, script.Parent, "message")
local INVALID_MESSAGE_STR = _message.INVALID_MESSAGE_STR
local ValidateArgs = _message.ValidateArgs
local _networking = TS.import(script, script.Parent, "networking")
local ServerEvents = _networking.ServerEvents
local ServerFunctions = _networking.ServerFunctions
local _serdes = TS.import(script, script.Parent, "serdes")
local messageSerializer = _serdes.messageSerializer
local skillRequestSerializer = _serdes.skillRequestSerializer
local currentInstance = nil
local Server
do
	Server = setmetatable({}, {
		__tostring = function()
			return "Server"
		end,
	})
	Server.__index = Server
	function Server.new(...)
		local self = setmetatable({}, Server)
		return self:constructor(...) or self
	end
	function Server:constructor()
		self._internal_isActive = false
		self._internal_registeredModules = {}
		self._internal_atom = atom({})
		self._internal_syncer = CharmSync.server({
			atoms = {
				atom = self._internal_atom,
			},
			preserveHistory = true,
		})
		currentInstance = self
	end
	function Server:_internal_filterReplicatedCharacters(Player, Character)
		return Character.Instance == Player.Character
	end
	function Server:RegisterDirectory(Directory)
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
	function Server:Start()
		if self._internal_isActive then
			logWarning("Attempted to :Start() server twice!")
			return nil
		end
		local assignedIdentifiers = {}
		Players.PlayerRemoving:Connect(function(player)
			local _player = player
			-- ▼ Map.delete ▼
			local _valueExisted = assignedIdentifiers[_player] ~= nil
			assignedIdentifiers[_player] = nil
			-- ▲ Map.delete ▲
			return _valueExisted
		end)
		self._internal_syncer:connect(function(player, ...)
			local payloads = { ... }
			local _result
			if player.Character then
				local _result_1 = Character.GetCharacterFromInstance(player.Character)
				if _result_1 ~= nil then
					_result_1 = _result_1:_internal_GetId()
				end
				_result = _result_1
			else
				_result = nil
			end
			local _condition = _result
			if _condition == nil then
				local _player = player
				_condition = assignedIdentifiers[_player]
			end
			local correspondingId = _condition
			if not (correspondingId ~= "" and correspondingId) then
				return nil
			end
			local _player = player
			assignedIdentifiers[_player] = correspondingId
			local modified = {}
			for _, payload in payloads do
				if payload.type == "init" then
					local data = payload.data.atom
					local characterData = data[correspondingId]
					if characterData then
						local _arg0 = {
							type = "init",
							data = {
								atom = characterData,
							},
						}
						table.insert(modified, _arg0)
					end
					continue
				end
				local data = payload.data.atom
				if data == nil then
					continue
				end
				local characterData = data[correspondingId]
				if characterData == nil then
					continue
				end
				local _arg0 = {
					type = "patch",
					data = {
						atom = characterData,
					},
				}
				table.insert(modified, _arg0)
			end
			ServerEvents.sync:fire(player, modified)
		end)
		ServerEvents.start:connect(function(player)
			return self._internal_syncer:hydrate(player)
		end)
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
		ServerEvents.requestSkill:connect(function(Player, serialized)
			local _binding = skillRequestSerializer.deserialize(serialized.buffer, serialized.blobs)
			local SkillName = _binding[1]
			local Action = _binding[2]
			local Params = _binding[3]
			local playerCharacter = Player.Character
			if not playerCharacter then
				return nil
			end
			local character = Character.GetCharacterFromInstance(playerCharacter)
			if not character or character.Player ~= Player then
				return nil
			end
			local skill = character:GetSkillFromString(SkillName)
			if not skill then
				return nil
			end
			if Action == "Start" then
				skill:Start(unpack(Params))
			else
				skill:End()
			end
		end)
		local eventHandler = function(Player, serialized)
			local _binding = messageSerializer.deserialize(serialized.buffer, serialized.blobs)
			local Name = _binding[1]
			local MethodName = _binding[2]
			local PackedArgs = _binding[3]
			local playerCharacter = Player.Character
			if not playerCharacter then
				return nil
			end
			local character = Character.GetCharacterFromInstance(playerCharacter)
			if not character or character.Player ~= Player then
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
		ServerEvents.messageToServer:connect(eventHandler)
		ServerEvents.messageToServer_urel:connect(eventHandler)
		ServerFunctions.messageToServer:setCallback(function(Player, serialized)
			local _binding = messageSerializer.deserialize(serialized.buffer, serialized.blobs)
			local Name = _binding[1]
			local MethodName = _binding[2]
			local PackedArgs = _binding[3]
			local playerCharacter = Player.Character
			if not playerCharacter then
				return nil
			end
			local character = Character.GetCharacterFromInstance(playerCharacter)
			if not character or character.Player ~= Player then
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
				local _, value = returnedValue:await()
				return value
			end
			return returnedValue
		end)
		setActiveHandler(self)
		self._internal_isActive = true
		logMessage("Started Server successfully")
	end
	function Server:IsActive()
		return self._internal_isActive
	end
end
local function CreateServer()
	if isClientContext() then
		logError("Attempted to instantiate server handler on client side!")
	end
	if currentInstance then
		logWarning("Attempted to instantiate server twice. \n Framework does not allow multiple server instances!")
		return currentInstance
	end
	return Server.new()
end
return {
	CreateServer = CreateServer,
}
