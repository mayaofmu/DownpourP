-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local subscribe = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "charm").subscribe
local Janitor = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "janitor", "src").Janitor
local _services = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local RunService = _services.RunService
local Workspace = _services.Workspace
local Signal = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "sleitnick-signal")
local t = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "t", "lib", "ts").t
local _timer = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "timer", "out")
local Timer = _timer.Timer
local TimerState = _timer.TimerState
local _actions = TS.import(script, script.Parent, "actions")
local deleteSkillData = _actions.deleteSkillData
local patchSkillData = _actions.patchSkillData
local setSkillData = _actions.setSkillData
local Flags = TS.import(script, script.Parent, "flags").Flags
local ClientEvents = TS.import(script, script.Parent, "networking").ClientEvents
local skillRequestSerializer = TS.import(script, script.Parent, "serdes").skillRequestSerializer
local _utility = TS.import(script, script.Parent, "utility")
local clientAtom = _utility.clientAtom
local createIdGenerator = _utility.createIdGenerator
local freezeCheck = _utility.freezeCheck
local getActiveHandler = _utility.getActiveHandler
local isClientContext = _utility.isClientContext
local isServerContext = _utility.isServerContext
local logError = _utility.logError
local logWarning = _utility.logWarning
local SkillType = {
	Default = "Default",
	Holdable = "Holdable",
}
--* @hidden @internal 
--* @hidden 
local nextId = createIdGenerator()
local registeredSkills = {}
--* @hidden 
local SkillBase
do
	SkillBase = {}
	function SkillBase:constructor(Props, ...)
		local Args = { ... }
		self._internal_janitor = Janitor.new()
		self._internal_id = nextId()
		self.Janitor = Janitor.new()
		self.CooldownTimer = Timer.new(1)
		self.Started = Signal.new()
		self.Ended = Signal.new()
		self.StateChanged = Signal.new()
		self.Destroyed = Signal.new()
		self.MetadataChanged = Signal.new()
		self.CheckOthersActive = true
		self.CheckedByOthers = true
		self.MutualExclusives = {}
		self.Requirements = {}
		self.CheckClientState = false
		self._internal_state = {
			IsActive = false,
			Debounce = false,
			StarterParams = {},
		}
		self._internal_destroyed = false
		self.Name = tostring((getmetatable(self)))
		self._internal_skillType = SkillType.Default
		local _binding = if tostring((getmetatable(Props))) ~= "Character" then Props else {
			Character = Props,
			Flag = nil,
		}
		local Character = _binding.Character
		local Flag = _binding.Flag
		self.Character = Character
		if not self.Character or tostring((getmetatable(self.Character))) ~= "Character" then
			logError("Not provided a valid character for Skill constructor")
		end
		if not getActiveHandler() then
			logError("Attempted to instantiate a skill before server has started.")
		end
		local _arg0 = tostring((getmetatable(self)))
		if not (registeredSkills[_arg0] ~= nil) then
			logError(`{tostring((getmetatable(self)))} is not a valid skill. Did you forget to apply a decorator?`)
		end
		if isClientContext() and Flag ~= Flags.CanInstantiateSkillClient then
			logError("Attempted to instantiate a skill on client")
		end
		self.Player = Players:GetPlayerFromCharacter(self.Character.Instance)
		self.ConstructorArguments = Args
		self.CooldownTimer.completed:Connect(function()
			if not self:GetState().Debounce then
				return nil
			end
			self:_internal_setState({
				Debounce = false,
			})
		end)
		self.Ended:Connect(function()
			return self.Janitor:Cleanup()
		end)
		self._internal_janitor:Add(function()
			self.Janitor:Destroy()
			self.StateChanged:Destroy()
			self.Destroyed:Destroy()
			self.Started:Destroy()
			self.Ended:Destroy()
			self.CooldownTimer:destroy()
			self.MetadataChanged:Destroy()
		end)
		self.StateChanged:Connect(function(New, Old)
			return self:_internal_stateDependentCallbacks(New, Old)
		end)
		self._internal_isReplicated = isClientContext()
	end
	function SkillBase:_internal_init()
		self.Character:_internal_addSkill(self)
		self:_internal_startReplication()
		if not self._internal_isReplicated then
			setSkillData(self.Character:_internal_GetId(), self.Name, self:_internal_packData())
		end
		local Args = self.ConstructorArguments
		self:OnConstruct(unpack(Args))
		if isServerContext() then
			self:OnConstructServer(unpack(Args))
		else
			self:OnConstructClient(unpack(Args))
		end
	end
	function SkillBase:Start(...)
		local params = { ... }
		if self.Character.DisableSkills then
			return nil
		end
		local isClient = isClientContext()
		local state = self:GetState()
		local sendStartRequest = function()
			local serialized = skillRequestSerializer.serialize({ self.Name, "Start", params })
			ClientEvents.requestSkill:fire(serialized)
		end
		if isClient and not self.CheckClientState then
			sendStartRequest()
			if self.AssumeStart == SkillBase.AssumeStart then
				return nil
			end
		end
		if state.IsActive or state.Debounce then
			return nil
		end
		if self.ParamValidators and not t.strictArray(unpack(self.ParamValidators))(params) then
			return nil
		end
		local filterReplicated = function(T)
			return if RunService:IsClient() then T._internal_isReplicated else true
		end
		for _, Exclusive in pairs(self.MutualExclusives) do
			local _exp = self.Character:GetAllActiveStatusEffectsOfType(Exclusive)
			-- ▼ ReadonlyArray.filter ▼
			local _newValue = {}
			local _length = 0
			for _k, _v in _exp do
				if filterReplicated(_v, _k - 1, _exp) == true then
					_length += 1
					_newValue[_length] = _v
				end
			end
			-- ▲ ReadonlyArray.filter ▲
			if not (#_newValue == 0) then
				return nil
			end
		end
		for _, Requirement in pairs(self.Requirements) do
			local _exp = self.Character:GetAllActiveStatusEffectsOfType(Requirement)
			-- ▼ ReadonlyArray.filter ▼
			local _newValue = {}
			local _length = 0
			for _k, _v in _exp do
				if filterReplicated(_v, _k - 1, _exp) == true then
					_length += 1
					_newValue[_length] = _v
				end
			end
			-- ▲ ReadonlyArray.filter ▲
			if #_newValue == 0 then
				return nil
			end
		end
		local _condition = self.CheckOthersActive
		if _condition then
			local _exp = self.Character:GetAllActiveSkills()
			-- ▼ ReadonlyArray.filter ▼
			local _newValue = {}
			local _callback = function(T)
				return T.CheckedByOthers
			end
			local _length = 0
			for _k, _v in _exp do
				if _callback(_v, _k - 1, _exp) == true then
					_length += 1
					_newValue[_length] = _v
				end
			end
			-- ▲ ReadonlyArray.filter ▲
			_condition = #_newValue > 0
		end
		if _condition then
			return nil
		end
		if not self:ShouldStart(unpack(params)) then
			return nil
		end
		if isClient then
			if self.CheckClientState then
				sendStartRequest()
			end
			task.spawn(function()
				return self:AssumeStart(unpack(params))
			end)
			return nil
		end
		self:_internal_setState({
			IsActive = true,
			StarterParams = params,
			Debounce = false,
		})
	end
	function SkillBase:IsDestroyed()
		return self._internal_destroyed
	end
	function SkillBase:End()
		if isClientContext() then
			local serialized = skillRequestSerializer.serialize({ self.Name, "End", {} })
			ClientEvents.requestSkill:fire(serialized)
			return nil
		end
		self:_internal_setState({
			IsActive = false,
			StarterParams = {},
		})
	end
	function SkillBase:Stop()
		self:End()
	end
	function SkillBase:GetSkillType()
		return self._internal_skillType
	end
	function SkillBase:Destroy(flag)
		if isClientContext() and flag ~= Flags.CanDestroyLocallyClient then
			logError("Attempted to manually destroy a skill on client. \n On client side skills are destroyed by the handler automatically, \n doing this manually can lead to a possible desync")
		end
		if self._internal_destroyed then
			return nil
		end
		self:_internal_setState({
			IsActive = false,
			Debounce = false,
			StarterParams = {},
		})
		if isServerContext() then
			deleteSkillData(self.Character:_internal_GetId(), self.Name)
		end
		self._internal_destroyed = true
		self.Destroyed:Fire()
		self._internal_janitor:Cleanup()
	end
	function SkillBase:_internal_stateDependentCallbacks(State, PreviousState)
		if not PreviousState.IsActive and State.IsActive then
			self.Started:Fire()
			self._internal_executionThread = task.spawn(function()
				if isClientContext() then
					self:OnStartClient(unpack((State.StarterParams)))
				else
					self:OnStartServer(unpack((State.StarterParams)))
				end
				self._internal_executionThread = nil
				if isServerContext() then
					self:End()
				end
			end)
		elseif PreviousState.IsActive and not State.IsActive then
			if self._internal_executionThread and coroutine.status(self._internal_executionThread) ~= "normal" then
				task.cancel(self._internal_executionThread)
				self._internal_executionThread = nil
			end
			if isClientContext() then
				self:OnEndClient()
			else
				self:OnEndServer()
			end
			self.Ended:Fire()
		end
	end
	function SkillBase:GetDebounceEndTimestamp()
		if not self._internal_state.Debounce then
			return nil
		end
		return self._internal_state._timerEndTimestamp
	end
	function SkillBase:GetState()
		return self._internal_state
	end
	function SkillBase:GetName()
		return self.Name
	end
	function SkillBase:_internal_GetId()
		return self.Name
	end
	function SkillBase:ClearMetadata()
		if self._internal_isReplicated then
			logError("Cannot :ClearMetadata() of skill on client! \n This can lead to a possible desync")
		end
		self.MetadataChanged:Fire(nil, self._internal_metadata)
		self._internal_metadata = nil
		if isServerContext() then
			patchSkillData(self.Character:_internal_GetId(), self.Name, {
				metadata = nil,
			})
		end
	end
	function SkillBase:SetMetadata(NewMeta)
		if self._internal_isReplicated then
			logError("Cannot :SetMetadata() of skill on client! \n This can lead to a possible desync")
		end
		if t.table(NewMeta) then
			freezeCheck(NewMeta)
		end
		self.MetadataChanged:Fire(NewMeta, self._internal_metadata)
		self._internal_metadata = NewMeta
		if isServerContext() then
			patchSkillData(self.Character:_internal_GetId(), self.Name, {
				metadata = NewMeta,
			})
		end
	end
	function SkillBase:GetMetadata()
		return self._internal_metadata
	end
	function SkillBase:CreateDamageContainer(Damage)
		return {
			Damage = Damage,
			Source = self,
		}
	end
	function SkillBase:ApplyCooldown(Duration)
		if not isServerContext() then
			logWarning("Cannot :ApplyCooldown() on client.")
			return nil
		end
		if Duration <= 0 then
			return nil
		end
		if self.CooldownTimer:getState() == TimerState.Running then
			self.CooldownTimer:stop()
		end
		if self.CooldownTimer:getState() == TimerState.Paused then
			self.CooldownTimer:resume()
			self.CooldownTimer:stop()
		end
		self.CooldownTimer:setLength(Duration)
		self.CooldownTimer:start()
		self:_internal_setState({
			Debounce = true,
			_timerEndTimestamp = Workspace:GetServerTimeNow() + self.CooldownTimer:getTimeLeft(),
		})
	end
	function SkillBase:CancelCooldown()
		if not isServerContext() then
			logWarning("Cannot :CancelCooldown() on client.")
			return nil
		end
		if not self:GetState().Debounce then
			return nil
		end
		if self.CooldownTimer:getState() == TimerState.Running then
			self.CooldownTimer:stop()
		end
		if self.CooldownTimer:getState() == TimerState.Paused then
			self.CooldownTimer:resume()
			self.CooldownTimer:stop()
		end
		self:_internal_setState({
			Debounce = false,
			_timerEndTimestamp = nil,
		})
	end
	function SkillBase:ExtendCooldown(Duration)
		if self.CooldownTimer:getTimeLeft() + Duration < 0 then
			self:CancelCooldown()
			return nil
		end
		self:ApplyCooldown(self.CooldownTimer:getTimeLeft() + Duration)
	end
	function SkillBase:_internal_setState(Patch)
		local _object = table.clone(self._internal_state)
		setmetatable(_object, nil)
		for _k, _v in Patch do
			_object[_k] = _v
		end
		local newState = _object
		local oldState = self._internal_state
		freezeCheck(newState)
		self._internal_state = newState
		if isServerContext() then
			patchSkillData(self.Character:_internal_GetId(), self.Name, {
				state = newState,
			})
		end
		self.StateChanged:Fire(newState, oldState)
	end
	function SkillBase:ShouldStart(...)
		local params = { ... }
		return true
	end
	function SkillBase:_internal_processDataUpdate(NewData, OldData)
		if OldData == nil then
			OldData = self:_internal_packData()
		end
		if not NewData then
			return nil
		end
		if NewData.state ~= OldData.state then
			freezeCheck(NewData.state)
			self._internal_state = NewData.state
			self.StateChanged:Fire(NewData.state, OldData.state)
		end
		if NewData.metadata ~= OldData.metadata then
			if t.table(NewData.metadata) then
				freezeCheck(NewData.metadata)
			end
			self._internal_metadata = NewData.metadata
			self.MetadataChanged:Fire(NewData.metadata, OldData.metadata)
		end
	end
	function SkillBase:_internal_startReplication()
		if not self._internal_isReplicated then
			return nil
		end
		local disconnect = subscribe(function()
			local _result = clientAtom()
			if _result ~= nil then
				local _skills = _result.skills
				local _name = self.Name
				_result = _skills[_name]
			end
			return _result
		end, function(current, old)
			return self:_internal_processDataUpdate(current, old)
		end)
		local state = clientAtom()
		local _self = self
		local _result = state
		if _result ~= nil then
			local _skills = _result.skills
			local _name = self.Name
			_result = _skills[_name]
		end
		_self:_internal_processDataUpdate(_result)
		self.Destroyed:Connect(disconnect)
	end
	function SkillBase:_internal_packData()
		return {
			state = self._internal_state,
			constructorArguments = self.ConstructorArguments,
			metadata = self._internal_metadata,
		}
	end
	function SkillBase:OnConstruct(...)
		local Args = { ... }
	end
	function SkillBase:OnConstructClient(...)
		local Args = { ... }
	end
	function SkillBase:OnConstructServer(...)
		local Args = { ... }
	end
	function SkillBase:OnStartServer(...)
		local Params = { ... }
	end
	function SkillBase:OnStartClient(...)
		local Params = { ... }
	end
	function SkillBase:OnEndClient()
	end
	function SkillBase:OnEndServer()
	end
	function SkillBase:AssumeStart(...)
		local Params = { ... }
	end
end
--* A skill class. 
local Skill
do
	local super = SkillBase
	Skill = setmetatable({}, {
		__tostring = function()
			return "Skill"
		end,
		__index = super,
	})
	Skill.__index = Skill
	function Skill:constructor(Character, ...)
		local Args = { ... }
		super.constructor(self, Character, unpack(Args))
		self:_internal_init()
	end
end
--[[
	*
	 * A decorator function that registers a skill.
	 
]]
local function SkillDecorator(Constructor)
	local name = tostring(Constructor)
	if registeredSkills[name] ~= nil then
		logError(`StatusEffect with name {name} was already registered before`)
	end
	local _constructor = Constructor
	registeredSkills[name] = _constructor
end
--[[
	*
	 * Retrieves the constructor function of a registered skill by name.
	 
]]
local function GetRegisteredSkillConstructor(Name)
	local _name = Name
	return registeredSkills[_name]
end
--[[
	*
	 * @internal
	 * @hidden
	 
]]
local function GetRegisteredSkills()
	return table.freeze(table.clone(registeredSkills))
end
return {
	SkillDecorator = SkillDecorator,
	GetRegisteredSkillConstructor = GetRegisteredSkillConstructor,
	GetRegisteredSkills = GetRegisteredSkills,
	SkillType = SkillType,
	SkillBase = SkillBase,
	Skill = Skill,
}
