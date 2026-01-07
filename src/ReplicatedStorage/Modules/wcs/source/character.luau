-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local _charm = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "charm")
local observe = _charm.observe
local subscribe = _charm.subscribe
local Janitor = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "janitor", "src").Janitor
local Players = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "services").Players
local Signal = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "sleitnick-signal")
local _actions = TS.import(script, script.Parent, "actions")
local deleteCharacterData = _actions.deleteCharacterData
local patchCharacterData = _actions.patchCharacterData
local setCharacterData = _actions.setCharacterData
local Flags = TS.import(script, script.Parent, "flags").Flags
local GetMovesetObjectByName = TS.import(script, script.Parent, "moveset").GetMovesetObjectByName
local ServerEvents = TS.import(script, script.Parent, "networking").ServerEvents
local GetRegisteredSkillConstructor = TS.import(script, script.Parent, "skill").GetRegisteredSkillConstructor
local _statusEffect = TS.import(script, script.Parent, "statusEffect")
local GetRegisteredStatusEffectConstructor = _statusEffect.GetRegisteredStatusEffectConstructor
local StatusEffect = _statusEffect.StatusEffect
local _utility = TS.import(script, script.Parent, "utility")
local GetParamsFromMoveset = _utility.GetParamsFromMoveset
local clientAtom = _utility.clientAtom
local freezeCheck = _utility.freezeCheck
local getActiveHandler = _utility.getActiveHandler
local isClientContext = _utility.isClientContext
local isConstructor = _utility.isConstructor
local isServerContext = _utility.isServerContext
local logError = _utility.logError
local logWarning = _utility.logWarning
local mapToArray = _utility.mapToArray
local nextId = 0
local function generateId()
	if isClientContext() then
		logError("Why are you trying to call this on client?")
	end
	nextId += 1
	return tostring(nextId)
end
local Character
do
	Character = setmetatable({}, {
		__tostring = function()
			return "Character"
		end,
	})
	Character.__index = Character
	function Character.new(...)
		local self = setmetatable({}, Character)
		return self:constructor(...) or self
	end
	function Character:constructor(Instance, canCreateClient)
		self._internal_janitor = Janitor.new()
		self.SkillAdded = Signal.new()
		self.SkillRemoved = Signal.new()
		self.StatusEffectAdded = Signal.new()
		self.StatusEffectRemoved = Signal.new()
		self.SkillStarted = Signal.new()
		self.SkillEnded = Signal.new()
		self.StatusEffectStarted = Signal.new()
		self.StatusEffectEnded = Signal.new()
		self.HumanoidPropertiesUpdated = Signal.new()
		self.DamageTaken = Signal.new()
		self.DamageDealt = Signal.new()
		self.Destroyed = Signal.new()
		self.MovesetChanged = Signal.new()
		self.DisableSkills = false
		self._internal_statusEffects = {}
		self._internal_skills = {}
		self._internal_defaultProps = {
			WalkSpeed = 16,
			JumpPower = 65,
			AutoRotate = true,
			JumpHeight = 15,
		}
		self._internal_currentlyAppliedProps = self:GetDefaultProps()
		self._internal_destroyed = false
		if isClientContext() and canCreateClient ~= Flags.CanCreateCharacterClient then
			logError("Attempted to manually create a character on client. \n On client side character are created by the handler automatically, \n doing this manually can lead to a possible desync")
		end
		local __internal_currentCharMap = Character._internal_currentCharMap
		local _instance = Instance
		if __internal_currentCharMap[_instance] then
			logError("Attempted to create 2 different characters over a same instance.")
		end
		if not getActiveHandler() then
			logError("Attempted to instantiate a character before server has started.")
		end
		local humanoid = Instance:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			logError("Attempted to instantiate a character over an instance without humanoid.")
		end
		self.Instance = Instance
		self.Humanoid = humanoid
		self.Player = Players:GetPlayerFromCharacter(self.Instance)
		self._internal_id = if isServerContext() then generateId() else "0"
		local __internal_currentCharMap_1 = Character._internal_currentCharMap
		local _instance_1 = Instance
		local _self = self
		__internal_currentCharMap_1[_instance_1] = _self
		Character.CharacterCreated:Fire(self)
		self:_internal_setupReplication_Client()
		self._internal_janitor:Add(self.StatusEffectAdded:Connect(function(status)
			return status:GetHumanoidData() and self:_internal_updateHumanoidProps()
		end))
		self._internal_janitor:Add(self.StatusEffectRemoved:Connect(function(status)
			return status:GetHumanoidData() and self:_internal_updateHumanoidProps()
		end))
		self._internal_janitor:Add(function()
			self.StatusEffectAdded:Destroy()
			self.StatusEffectRemoved:Destroy()
			self.SkillAdded:Destroy()
			self.SkillRemoved:Destroy()
			self.SkillStarted:Destroy()
			self.SkillEnded:Destroy()
			self.StatusEffectStarted:Destroy()
			self.StatusEffectEnded:Destroy()
			self.HumanoidPropertiesUpdated:Destroy()
			self.DamageDealt:Destroy()
			self.DamageTaken:Destroy()
		end)
		if isServerContext() then
			local server = getActiveHandler()
			setCharacterData(self._internal_id, self:_internal_packData())
			self.DamageTaken:Connect(function(Container)
				for _, player in Players:GetPlayers() do
					if not server:_internal_filterReplicatedCharacters(player, self) then
						continue
					end
					ServerEvents.damageTaken:fire(player, Container.Damage)
				end
			end)
			self.DamageDealt:Connect(function(_, Container)
				for _1, player in Players:GetPlayers() do
					if not server:_internal_filterReplicatedCharacters(player, self) then
						continue
					end
					local _2 = ServerEvents.damageDealt
					local _result = Container.Source
					if _result ~= nil then
						_result = _result:_internal_GetId()
					end
					_2:fire(player, _result, if TS.instanceof(Container.Source, StatusEffect) then "Status" else "Skill", Container.Damage)
				end
			end)
		end
	end
	function Character:_internal_GetId()
		return self._internal_id
	end
	function Character:Destroy(flag)
		if isClientContext() and flag ~= Flags.CanDestroyLocallyClient then
			logError("Attempted to manually destroy a character on client. \n On client side character is destroyed by the handler automatically, \n doing this manually can lead to a possible desync")
		end
		if self._internal_destroyed then
			return nil
		end
		local __internal_currentCharMap = Character._internal_currentCharMap
		local _instance = self.Instance
		__internal_currentCharMap[_instance] = nil
		Character.CharacterDestroyed:Fire(self)
		self.Destroyed:Fire()
		self._internal_janitor:Cleanup()
		self._internal_destroyed = true
		local _exp = self._internal_skills
		-- ▼ ReadonlyMap.forEach ▼
		local _callback = function(Skill)
			return Skill:Destroy(Flags.CanDestroyLocallyClient)
		end
		for _k, _v in _exp do
			_callback(_v, _k, _exp)
		end
		-- ▲ ReadonlyMap.forEach ▲
		local _exp_1 = self._internal_statusEffects
		-- ▼ ReadonlyMap.forEach ▼
		local _callback_1 = function(Status)
			return Status:Destroy()
		end
		for _k, _v in _exp_1 do
			_callback_1(_v, _k, _exp_1)
		end
		-- ▲ ReadonlyMap.forEach ▲
		if isServerContext() then
			deleteCharacterData(self._internal_id)
		end
	end
	function Character:IsDestroyed()
		return self._internal_destroyed
	end
	function Character:TakeDamage(Container)
		if isClientContext() then
			logError("Cannot use :TakeDamage() on client")
		end
		local modifiedDamage = self:PredictDamage(Container).Damage
		local _object = table.clone(Container)
		setmetatable(_object, nil)
		_object.Damage = modifiedDamage
		local container = _object
		self.DamageTaken:Fire(container)
		local _result = Container.Source
		if _result ~= nil then
			_result = _result.Character.DamageDealt:Fire(self, container)
		end
		return container
	end
	function Character:PredictDamage(Container)
		if isClientContext() then
			logError("Cannot use :TakeDamage() on client")
		end
		local originalDamage = Container.Damage
		local modifiedDamage = originalDamage
		local _exp = self:GetAllActiveStatusEffects()
		table.sort(_exp, function(a, b)
			return a:GetModificationPriority() < b:GetModificationPriority()
		end)
		-- ▼ ReadonlyArray.forEach ▼
		local _callback = function(Status)
			modifiedDamage = Status:HandleDamage(modifiedDamage, originalDamage, Container.Source)
		end
		for _k, _v in _exp do
			_callback(_v, _k - 1, _exp)
		end
		-- ▲ ReadonlyArray.forEach ▲
		local _object = table.clone(Container)
		setmetatable(_object, nil)
		_object.Damage = modifiedDamage
		local container = _object
		return container
	end
	function Character:_internal_addStatus(Status)
		local __internal_statusEffects = self._internal_statusEffects
		local _arg0 = Status:_internal_GetId()
		local _status = Status
		__internal_statusEffects[_arg0] = _status
		Status.HumanoidDataChanged:Connect(function()
			return self:_internal_updateHumanoidProps()
		end)
		Status.StateChanged:Connect(function()
			if not Status:GetHumanoidData() then
				return nil
			end
			self:_internal_updateHumanoidProps()
		end)
		Status.Started:Connect(function()
			return self.StatusEffectStarted:Fire(Status)
		end)
		Status.Ended:Connect(function()
			return self.StatusEffectEnded:Fire(Status)
		end)
		Status.Destroyed:Connect(function()
			local __internal_statusEffects_1 = self._internal_statusEffects
			local _arg0_1 = Status:_internal_GetId()
			__internal_statusEffects_1[_arg0_1] = nil
			self.StatusEffectRemoved:Fire(Status)
			if not Status:GetHumanoidData() then
				return nil
			end
			self:_internal_updateHumanoidProps()
		end)
		self.StatusEffectAdded:Fire(Status)
	end
	function Character:_internal_addSkill(Skill)
		local name = Skill:GetName()
		if self._internal_skills[name] ~= nil then
			logError(`Skill with name {name} is already registered for character {self.Instance}`)
		end
		Skill.Started:Connect(function()
			return self.SkillStarted:Fire(Skill)
		end)
		Skill.Ended:Connect(function()
			return self.SkillEnded:Fire(Skill)
		end)
		local __internal_skills = self._internal_skills
		local _skill = Skill
		__internal_skills[name] = _skill
		Skill.Destroyed:Connect(function()
			self.SkillRemoved:Fire(Skill)
			local _result = self._internal_skills[name]
			if _result ~= nil then
				_result = _result._internal_id
			end
			if _result ~= Skill._internal_id then
				return nil
			end
			self._internal_skills[name] = nil
		end)
		self.SkillAdded:Fire(Skill)
	end
	function Character:_internal_packData()
		local packedStatusEffect = {}
		local _exp = self._internal_statusEffects
		-- ▼ ReadonlyMap.forEach ▼
		local _callback = function(Status, Id)
			local _id = Id
			local _arg1 = Status:_internal_packData()
			packedStatusEffect[_id] = _arg1
			return packedStatusEffect
		end
		for _k, _v in _exp do
			_callback(_v, _k, _exp)
		end
		-- ▲ ReadonlyMap.forEach ▲
		return {
			instance = self.Instance,
			statusEffects = packedStatusEffect,
			defaultProps = self._internal_defaultProps,
			moveset = self._internal_moveset,
			skills = {},
		}
	end
	function Character:SetDefaultProps(Props)
		local _object = table.clone(self._internal_defaultProps)
		setmetatable(_object, nil)
		for _k, _v in Props do
			_object[_k] = _v
		end
		self._internal_defaultProps = _object
		freezeCheck(self._internal_defaultProps)
		self:_internal_updateHumanoidProps()
		if isServerContext() then
			patchCharacterData(self._internal_id, {
				defaultProps = self._internal_defaultProps,
			})
		end
	end
	function Character:GetDefaultProps()
		return self._internal_defaultProps
	end
	function Character.GetCharacterMap()
		return table.freeze(table.clone(Character._internal_currentCharMap))
	end
	function Character.GetLocalCharacter()
		local localCharacter = Players.LocalPlayer.Character
		if not localCharacter then
			return nil
		end
		return Character._internal_currentCharMap[localCharacter]
	end
	function Character._internal_GetCharacterFromId(Id)
		for _, _Character in pairs(Character._internal_currentCharMap) do
			if _Character:_internal_GetId() == Id then
				return _Character
			end
		end
	end
	function Character.GetCharacterFromInstance(Instance)
		local __internal_currentCharMap = Character._internal_currentCharMap
		local _instance = Instance
		return __internal_currentCharMap[_instance]
	end
	function Character:GetAllStatusEffects()
		return mapToArray(self._internal_statusEffects)
	end
	function Character:GetAllActiveStatusEffects()
		local _exp = mapToArray(self._internal_statusEffects)
		-- ▼ ReadonlyArray.filter ▼
		local _newValue = {}
		local _callback = function(T)
			return T:GetState().IsActive
		end
		local _length = 0
		for _k, _v in _exp do
			if _callback(_v, _k - 1, _exp) == true then
				_length += 1
				_newValue[_length] = _v
			end
		end
		-- ▲ ReadonlyArray.filter ▲
		return _newValue
	end
	function Character:GetAllStatusEffectsOfType(Constructor)
		local _exp = mapToArray(self._internal_statusEffects)
		-- ▼ ReadonlyArray.filter ▼
		local _newValue = {}
		local _callback = function(T)
			return tostring((getmetatable(T))) == tostring(Constructor)
		end
		local _length = 0
		for _k, _v in _exp do
			if _callback(_v, _k - 1, _exp) == true then
				_length += 1
				_newValue[_length] = _v
			end
		end
		-- ▲ ReadonlyArray.filter ▲
		return _newValue
	end
	function Character:GetAllActiveStatusEffectsOfType(Constructor)
		local _exp = mapToArray(self._internal_statusEffects)
		-- ▼ ReadonlyArray.filter ▼
		local _newValue = {}
		local _callback = function(T)
			return tostring((getmetatable(T))) == tostring(Constructor) and T:GetState().IsActive
		end
		local _length = 0
		for _k, _v in _exp do
			if _callback(_v, _k - 1, _exp) == true then
				_length += 1
				_newValue[_length] = _v
			end
		end
		-- ▲ ReadonlyArray.filter ▲
		return _newValue
	end
	function Character:HasStatusEffects(Constructors)
		if isConstructor(Constructors) then
			for _, Effect in pairs(self._internal_statusEffects) do
				if not Effect:GetState().IsActive or not (TS.instanceof(Effect, Constructors)) then
					continue
				end
				return true
			end
			return false
		end
		local ConstrucorsArray = Constructors
		for _, Effect in pairs(self._internal_statusEffects) do
			if not Effect:GetState().IsActive then
				continue
			end
			-- ▼ ReadonlyArray.find ▼
			local _callback = function(T)
				return TS.instanceof(Effect, T)
			end
			local _result
			for _i, _v in ConstrucorsArray do
				if _callback(_v, _i - 1, ConstrucorsArray) == true then
					_result = _v
					break
				end
			end
			-- ▲ ReadonlyArray.find ▲
			if _result ~= nil then
				return true
			end
		end
		return false
	end
	function Character:GetSkills()
		return mapToArray(self._internal_skills)
	end
	function Character:GetAllActiveSkills()
		local _exp = mapToArray(self._internal_skills)
		-- ▼ ReadonlyArray.filter ▼
		local _newValue = {}
		local _callback = function(T)
			return T:GetState().IsActive
		end
		local _length = 0
		for _k, _v in _exp do
			if _callback(_v, _k - 1, _exp) == true then
				_length += 1
				_newValue[_length] = _v
			end
		end
		-- ▲ ReadonlyArray.filter ▲
		return _newValue
	end
	function Character:GetSkillFromString(Name)
		local __internal_skills = self._internal_skills
		local _name = Name
		return __internal_skills[_name]
	end
	function Character:GetSkillFromConstructor(Constructor)
		local __internal_skills = self._internal_skills
		local _arg0 = tostring(Constructor)
		return __internal_skills[_arg0]
	end
	function Character:GetSkillsDerivedFrom(Constructor)
		local _exp = mapToArray(self._internal_skills)
		-- ▼ ReadonlyArray.filter ▼
		local _newValue = {}
		local _callback = function(T)
			return TS.instanceof(T, Constructor)
		end
		local _length = 0
		for _k, _v in _exp do
			if _callback(_v, _k - 1, _exp) == true then
				_length += 1
				_newValue[_length] = _v
			end
		end
		-- ▲ ReadonlyArray.filter ▲
		return _newValue
	end
	function Character:ApplyMoveset(Moveset)
		if not isServerContext() then
			logWarning("Attempted to apply moveset on client")
			return nil
		end
		local _moveset = Moveset
		local movesetObject = if type(_moveset) == "string" then GetMovesetObjectByName(Moveset) else Moveset
		if not movesetObject then
			logError("The provided moveset is invalid")
		end
		if movesetObject.Name == self._internal_moveset then
			return nil
		end
		self:_internal_cleanupMovesetSkills()
		local _exp = movesetObject.Skills
		-- ▼ ReadonlyArray.forEach ▼
		local _callback = function(SkillConstructor)
			local params = (GetParamsFromMoveset(movesetObject, SkillConstructor) or {})
			SkillConstructor.new(self, unpack(params))
		end
		for _k, _v in _exp do
			_callback(_v, _k - 1, _exp)
		end
		-- ▲ ReadonlyArray.forEach ▲
		local oldMoveset = self._internal_moveset
		if oldMoveset ~= "" and oldMoveset then
			local oldMovesetObject = GetMovesetObjectByName(oldMoveset)
			oldMovesetObject.OnCharacterRemoved:Fire(self)
		end
		self:_internal_setMovesetServer(movesetObject.Name)
		self.MovesetChanged:Fire(movesetObject.Name, oldMoveset)
		movesetObject.OnCharacterAdded:Fire(self)
	end
	function Character:GetMovesetName()
		return self._internal_moveset
	end
	function Character:GetMoveset()
		local _value = self._internal_moveset
		return if _value ~= "" and _value then GetMovesetObjectByName(self._internal_moveset) else nil
	end
	function Character:GetMovesetSkills(Moveset)
		if Moveset == nil then
			Moveset = self:GetMoveset()
		end
		if not Moveset then
			return {}
		end
		local _exp = mapToArray(self._internal_skills)
		-- ▼ ReadonlyArray.filter ▼
		local _newValue = {}
		local _callback = function(skill)
			for _, ctor in Moveset.Skills do
				if TS.instanceof(skill, ctor) then
					return true
				end
			end
			return false
		end
		local _length = 0
		for _k, _v in _exp do
			if _callback(_v, _k - 1, _exp) == true then
				_length += 1
				_newValue[_length] = _v
			end
		end
		-- ▲ ReadonlyArray.filter ▲
		return _newValue
	end
	function Character:ClearMoveset()
		if not isServerContext() then
			logError("Attempted to clear moveset on client")
		end
		local _value = self._internal_moveset
		if not (_value ~= "" and _value) then
			return nil
		end
		self:_internal_cleanupMovesetSkills()
		local oldMoveset = self._internal_moveset
		local oldMovesetObject = GetMovesetObjectByName(oldMoveset)
		self:_internal_setMovesetServer(nil)
		self.MovesetChanged:Fire(self._internal_moveset, oldMoveset)
		oldMovesetObject.OnCharacterRemoved:Fire(self)
	end
	function Character:_internal_setMovesetServer(to)
		self._internal_moveset = to
		patchCharacterData(self._internal_id, {
			moveset = self._internal_moveset,
		})
	end
	function Character:_internal_cleanupMovesetSkills()
		local _value = self._internal_moveset
		if not (_value ~= "" and _value) then
			return nil
		end
		local movesetObject = GetMovesetObjectByName(self._internal_moveset)
		if not movesetObject then
			return nil
		end
		local _exp = movesetObject.Skills
		-- ▼ ReadonlyArray.forEach ▼
		local _callback = function(SkillConstructor)
			local name = tostring(SkillConstructor)
			local _result = self._internal_skills[name]
			if _result ~= nil then
				_result:Destroy()
			end
			self._internal_skills[name] = nil
		end
		for _k, _v in _exp do
			_callback(_v, _k - 1, _exp)
		end
		-- ▲ ReadonlyArray.forEach ▲
	end
	function Character:ApplySkillsFromMoveset(Moveset)
		local _exp = Moveset.Skills
		-- ▼ ReadonlyArray.forEach ▼
		local _callback = function(SkillConstructor)
			local name = tostring(SkillConstructor)
			local _result = self._internal_skills[name]
			if _result ~= nil then
				_result:Destroy()
			end
			self._internal_skills[name] = nil
			local params = (GetParamsFromMoveset(Moveset, SkillConstructor) or {})
			SkillConstructor.new(self, unpack(params))
		end
		for _k, _v in _exp do
			_callback(_v, _k - 1, _exp)
		end
		-- ▲ ReadonlyArray.forEach ▲
	end
	function Character:_internal_statusObserver(Data, Id)
		local constructor = GetRegisteredStatusEffectConstructor(Data.className)
		if not constructor then
			logError(`Replication Error: Could not find a registered StatusEffect with name {Data.className}. \n Try doing :RegisterDirectory() on the file directory.`)
		end
		local flaggedAsDestroyed = false
		local status = nil
		task.spawn(function()
			status = constructor.new({
				Character = self,
				Flag = {
					flag = Flags.CanAssignCustomId,
					data = Id,
				},
			}, unpack(Data.constructorArgs))
			if flaggedAsDestroyed then
				status:Destroy()
			end
		end)
		return function()
			flaggedAsDestroyed = true
			local _result = status
			if _result ~= nil then
				_result:Destroy()
			end
		end
	end
	function Character:_internal_skillObserver(Data, Name)
		local constructor = GetRegisteredSkillConstructor(Name)
		if not constructor then
			logError(`Replication Error: Could not find a registered Skill with name {Name}. \n Try doing :RegisterDirectory() on the file directory.`)
		end
		local flaggedAsDestroyed = false
		local skill = nil
		task.spawn(function()
			skill = constructor.new({
				Character = self,
				Flag = Flags.CanInstantiateSkillClient,
			}, unpack(Data.constructorArguments))
			if flaggedAsDestroyed then
				skill:Destroy()
			end
		end)
		return function()
			flaggedAsDestroyed = true
			local _result = skill
			if _result ~= nil then
				_result:Destroy(Flags.CanDestroyLocallyClient)
			end
		end
	end
	function Character:_internal_setupReplication_Client()
		if not isClientContext() then
			return nil
		end
		if not getActiveHandler() then
			return nil
		end
		local processMovesetChange = function(New, Old)
			self._internal_moveset = New
			self.MovesetChanged:Fire(New, Old)
			if New ~= "" and New then
				local newMovesetObject = GetMovesetObjectByName(New)
				newMovesetObject.OnCharacterAdded:Fire(self)
			end
			if Old ~= "" and Old then
				local oldMovesetObject = GetMovesetObjectByName(Old)
				oldMovesetObject.OnCharacterRemoved:Fire(self)
			end
		end
		local processDataUpdate = function(CharacterData)
			if not CharacterData then
				return nil
			end
			if CharacterData.moveset ~= self._internal_moveset then
				processMovesetChange(CharacterData.moveset, self._internal_moveset)
			end
			if CharacterData.defaultProps ~= self._internal_defaultProps then
				self:SetDefaultProps(CharacterData.defaultProps)
			end
		end
		self._internal_janitor:Add(observe(function()
			local _result = clientAtom()
			if _result ~= nil then
				_result = _result.statusEffects
			end
			local _condition = _result
			if _condition == nil then
				_condition = {}
			end
			return _condition
		end, function(value, key)
			return self:_internal_statusObserver(value, key)
		end))
		self._internal_janitor:Add(observe(function()
			local _result = clientAtom()
			if _result ~= nil then
				_result = _result.skills
			end
			local _condition = _result
			if _condition == nil then
				_condition = {}
			end
			return _condition
		end, function(value, key)
			return self:_internal_skillObserver(value, key)
		end))
		self._internal_janitor:Add(subscribe(clientAtom, processDataUpdate))
		self:_internal_updateHumanoidProps()
	end
	function Character:_internal_updateHumanoidProps()
		if isServerContext() and self.Player then
			return nil
		end
		local propsToApply = self:_internal_calculateAppliedProps()
		self.HumanoidPropertiesUpdated:Fire(propsToApply)
		for PropertyName, Value in pairs(propsToApply) do
			self.Humanoid[PropertyName] = Value
		end
	end
	function Character:_internal_calculateAppliedProps()
		local statuses = {}
		local _exp = self._internal_statusEffects
		-- ▼ ReadonlyMap.forEach ▼
		local _callback = function(Status)
			if Status:GetHumanoidData() and Status:GetState().IsActive then
				local _status = Status
				table.insert(statuses, _status)
			end
		end
		for _k, _v in _exp do
			_callback(_v, _k, _exp)
		end
		-- ▲ ReadonlyMap.forEach ▲
		local propsToApply = table.clone(self:GetDefaultProps())
		local incPriorityList = {
			WalkSpeed = 0,
			JumpPower = 0,
			AutoRotate = 0,
			JumpHeight = 0,
		}
		-- ▼ ReadonlyArray.forEach ▼
		local _callback_1 = function(StatusEffect)
			local humanoidData = StatusEffect:GetHumanoidData()
			if not humanoidData then
				return nil
			end
			local priority = humanoidData.Priority
			for PropertyName, PropertyData in pairs(humanoidData.Props) do
				if PropertyData[2] == "Increment" then
					propsToApply[PropertyName] = (PropertyData[1] + propsToApply[PropertyName])
				elseif priority > incPriorityList[PropertyName] then
					propsToApply[PropertyName] = PropertyData[1]
					incPriorityList[PropertyName] = priority
				end
			end
		end
		for _k, _v in statuses do
			_callback_1(_v, _k - 1, statuses)
		end
		-- ▲ ReadonlyArray.forEach ▲
		freezeCheck(propsToApply)
		self._internal_currentlyAppliedProps = propsToApply
		return propsToApply
	end
	function Character:GetAppliedProps()
		return self._internal_currentlyAppliedProps
	end
	Character._internal_currentCharMap = {}
	Character.CharacterCreated = Signal.new()
	Character.CharacterDestroyed = Signal.new()
end
return {
	Character = Character,
}
