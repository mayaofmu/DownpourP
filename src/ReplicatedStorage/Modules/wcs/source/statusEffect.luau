-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local subscribe = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "charm").subscribe
local Janitor = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "janitor", "src").Janitor
local _services = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "services")
local Players = _services.Players
local Workspace = _services.Workspace
local Signal = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "sleitnick-signal")
local t = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "t", "lib", "ts").t
local _timer = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "timer", "out")
local Timer = _timer.Timer
local TimerState = _timer.TimerState
local _actions = TS.import(script, script.Parent, "actions")
local deleteStatusData = _actions.deleteStatusData
local patchStatusData = _actions.patchStatusData
local setStatusData = _actions.setStatusData
local Flags = TS.import(script, script.Parent, "flags").Flags
local _utility = TS.import(script, script.Parent, "utility")
local clientAtom = _utility.clientAtom
local createIdGenerator = _utility.createIdGenerator
local freezeCheck = _utility.freezeCheck
local getActiveHandler = _utility.getActiveHandler
local isClientContext = _utility.isClientContext
local isServerContext = _utility.isServerContext
local logError = _utility.logError
local logWarning = _utility.logWarning
--* @hidden 
local registeredStatuses = {}
local nextId = createIdGenerator(0, if isServerContext() then 1 else -1)
--[[
	*
	 * A status effect class.
	 
]]
local StatusEffect
do
	StatusEffect = setmetatable({}, {
		__tostring = function()
			return "StatusEffect"
		end,
	})
	StatusEffect.__index = StatusEffect
	function StatusEffect.new(...)
		local self = setmetatable({}, StatusEffect)
		return self:constructor(...) or self
	end
	function StatusEffect:constructor(Props, ...)
		local Args = { ... }
		self._internal_janitor = Janitor.new()
		self.Janitor = Janitor.new()
		self.MetadataChanged = Signal.new()
		self.StateChanged = Signal.new()
		self.HumanoidDataChanged = Signal.new()
		self.Destroyed = Signal.new()
		self.Started = Signal.new()
		self.Ended = Signal.new()
		self.Name = tostring((getmetatable(self)))
		self.DamageModificationPriority = 1
		self.DestroyOnEnd = true
		self._internal_state = {
			IsActive = false,
		}
		self._internal_isDestroyed = false
		self._internal_timer = Timer.new(1)
		local _binding = if tostring((getmetatable(Props))) ~= "Character" then Props else {
			Character = Props,
			Flag = nil,
		}
		local Character = _binding.Character
		local Flag = _binding.Flag
		self._internal_id = if Flag and Flag.flag == Flags.CanAssignCustomId then Flag.data else tostring(nextId())
		self.Character = Character
		if not self.Character or tostring((getmetatable(self.Character))) ~= "Character" then
			logError("Not provided a valid character for StatusEffect constructor")
		end
		if not getActiveHandler() then
			logError("Attempted to instantiate a character before server has started.")
		end
		local _arg0 = tostring((getmetatable(self)))
		if not (registeredStatuses[_arg0] ~= nil) then
			logError(`{tostring((getmetatable(self)))} is not a valid status effect. Did you forget to apply a decorator?`)
		end
		self.Player = Players:GetPlayerFromCharacter(self.Character.Instance)
		self._internal_isReplicated = isClientContext() and tonumber(self._internal_id) > 0
		self.ConstructorArguments = Args
		self.StateChanged:Connect(function(New, Old)
			return self:_internal_stateDependentCallbacks(New, Old)
		end)
		self.Ended:Connect(function()
			return self.Janitor:Cleanup()
		end)
		self.Ended:Connect(function()
			if self.DestroyOnEnd and (isServerContext() or not self._internal_isReplicated) then
				self:Destroy()
			end
		end)
		self._internal_timer.completed:Connect(function()
			return self:End()
		end)
		self._internal_janitor:Add(function()
			self.Janitor:Cleanup()
			self.StateChanged:Destroy()
			self.MetadataChanged:Destroy()
			self.HumanoidDataChanged:Destroy()
			self.Destroyed:Destroy()
			self.Started:Destroy()
			self.Ended:Destroy()
			self._internal_timer:destroy()
		end)
		Character:_internal_addStatus(self)
		self:_internal_startReplicationClient()
		if isServerContext() then
			setStatusData(self.Character:_internal_GetId(), self._internal_id, self:_internal_packData())
		end
		self:OnConstruct(unpack(Args))
		if isServerContext() then
			self:OnConstructServer(unpack(Args))
		else
			self:OnConstructClient(unpack(Args))
		end
	end
	function StatusEffect:Start(Time)
		if self._internal_isReplicated then
			return logWarning("Cannot perform this action on a replicated status")
		end
		if self._internal_timer:getState() == TimerState.Running then
			return nil
		end
		if self._internal_timer:getState() == TimerState.Paused then
			self._internal_timer:resume()
			self._internal_timer:stop()
		end
		if Time ~= nil and Time > 0 then
			self._internal_timer:setLength(Time)
			self._internal_timer:start()
		end
		local timestamp = if self._internal_timer:getState() ~= TimerState.NotRunning then Workspace:GetServerTimeNow() + self._internal_timer:getTimeLeft() else nil
		self:setState({
			IsActive = true,
			_startTimestamp = Workspace:GetServerTimeNow(),
			_timerEndTimestamp = timestamp,
		})
	end
	function StatusEffect:GetEndTimestamp()
		return self._internal_state._timerEndTimestamp
	end
	function StatusEffect:Stop()
		self:End()
	end
	function StatusEffect:Pause()
		if self._internal_isReplicated then
			return logWarning("Cannot perform this action on a replicated status")
		end
		if self._internal_timer:getState() ~= TimerState.Running then
			return nil
		end
		self:setState({
			_timerEndTimestamp = nil,
		})
		self._internal_timer:pause()
	end
	function StatusEffect:Resume()
		if self._internal_isReplicated then
			return logWarning("Cannot perform this action on a replicated status")
		end
		if self._internal_timer:getState() ~= TimerState.Paused then
			return nil
		end
		self._internal_timer:resume()
		self:setState({
			_timerEndTimestamp = Workspace:GetServerTimeNow() + self._internal_timer:getTimeLeft(),
		})
	end
	function StatusEffect:End()
		if self._internal_isReplicated then
			return logWarning("Cannot perform this action on a replicated status")
		end
		if not self:GetState().IsActive then
			return nil
		end
		self:setState({
			IsActive = false,
			_startTimestamp = nil,
			_timerEndTimestamp = nil,
		})
		if self._internal_timer:getState() == TimerState.NotRunning then
			return nil
		end
		if self._internal_timer:getState() == TimerState.Paused then
			self._internal_timer:resume()
			self._internal_timer:stop()
			return nil
		end
		self._internal_timer:stop()
	end
	function StatusEffect:GetStartTimestamp()
		return self._internal_state._startTimestamp
	end
	function StatusEffect:SetHumanoidData(Props, Priority)
		if Priority == nil then
			Priority = 1
		end
		local newData = {
			Props = Props,
			Priority = Priority,
		}
		local old = self._internal_humanoidData
		self._internal_humanoidData = newData
		self.HumanoidDataChanged:Fire(newData, old)
		if isServerContext() then
			patchStatusData(self.Character:_internal_GetId(), self._internal_id, {
				humanoidData = self._internal_humanoidData,
			})
		end
	end
	function StatusEffect:ClearHumanoidData()
		self._internal_humanoidData = nil
		self.HumanoidDataChanged:Fire(nil, self._internal_humanoidData)
		if isServerContext() then
			patchStatusData(self.Character:_internal_GetId(), self._internal_id, {
				humanoidData = nil,
			})
		end
	end
	function StatusEffect:ClearMetadata()
		if self._internal_isReplicated then
			logError("Cannot :ClearMetadata() of replicated status effect on client! \n This can lead to a possible desync")
		end
		self.MetadataChanged:Fire(nil, self._internal_metadata)
		self._internal_metadata = nil
		if isServerContext() then
			patchStatusData(self.Character:_internal_GetId(), self._internal_id, {
				metadata = nil,
			})
		end
	end
	function StatusEffect:setState(Patch)
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
			patchStatusData(self.Character:_internal_GetId(), self._internal_id, {
				state = newState,
			})
		end
		self.StateChanged:Fire(newState, oldState)
	end
	function StatusEffect:SetMetadata(NewMeta)
		if self._internal_isReplicated then
			logError("Cannot :SetMetadata() of replicated status effect on client! \n This can lead to a possible desync")
		end
		if t.table(NewMeta) then
			freezeCheck(NewMeta)
		end
		self.MetadataChanged:Fire(NewMeta, self._internal_metadata)
		self._internal_metadata = NewMeta
		if isServerContext() then
			patchStatusData(self.Character:_internal_GetId(), self._internal_id, {
				metadata = NewMeta,
			})
		end
	end
	function StatusEffect:GetState()
		return self._internal_state
	end
	function StatusEffect:GetHumanoidData()
		return self._internal_humanoidData
	end
	function StatusEffect:GetMetadata()
		return self._internal_metadata
	end
	function StatusEffect:IsDestroyed()
		return self._internal_isDestroyed
	end
	function StatusEffect:_internal_GetId()
		return self._internal_id
	end
	function StatusEffect:HandleDamage(Modified, Original, Source)
		return Modified
	end
	function StatusEffect:GetModificationPriority()
		return self.DamageModificationPriority
	end
	function StatusEffect:Destroy()
		if self._internal_isDestroyed then
			return nil
		end
		if isServerContext() then
			self:End()
			deleteStatusData(self.Character:_internal_GetId(), self._internal_id)
		else
			self:setState({
				IsActive = false,
			})
		end
		self._internal_isDestroyed = true
		self.Destroyed:Fire()
		self._internal_janitor:Cleanup()
	end
	function StatusEffect:CreateDamageContainer(Damage)
		return {
			Damage = Damage,
			Source = self,
		}
	end
	function StatusEffect:_internal_packData()
		return {
			className = tostring((getmetatable(self))),
			state = self._internal_state,
			constructorArgs = self.ConstructorArguments,
		}
	end
	function StatusEffect:_internal_stateDependentCallbacks(State, PreviousState)
		if PreviousState.IsActive == State.IsActive then
			return nil
		end
		if not PreviousState.IsActive and State.IsActive then
			self.Started:Fire()
			self._internal_executionThread = task.spawn(function()
				if isClientContext() then
					self:OnStartClient()
				else
					self:OnStartServer()
				end
				self._internal_executionThread = nil
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
	function StatusEffect:_internal_processDataUpdate(StatusData, PreviousData)
		if PreviousData == nil then
			PreviousData = self:_internal_packData()
		end
		if not StatusData then
			return nil
		end
		if StatusData.state ~= PreviousData.state then
			freezeCheck(StatusData.state)
			self._internal_state = StatusData.state
			self.StateChanged:Fire(StatusData.state, PreviousData.state)
		end
		if StatusData.metadata ~= PreviousData.metadata then
			if t.table(StatusData.metadata) then
				freezeCheck(StatusData.metadata)
			end
			self._internal_metadata = StatusData.metadata
			self.MetadataChanged:Fire(StatusData.metadata, PreviousData.metadata)
		end
		if StatusData.humanoidData ~= PreviousData.humanoidData then
			if StatusData.humanoidData then
				freezeCheck(StatusData.humanoidData)
			end
			self._internal_humanoidData = StatusData.humanoidData
			self.HumanoidDataChanged:Fire(StatusData.humanoidData, PreviousData.humanoidData)
		end
	end
	function StatusEffect:_internal_startReplicationClient()
		if not self._internal_isReplicated then
			return nil
		end
		local subscription = subscribe(function()
			local _result = clientAtom()
			if _result ~= nil then
				local _statusEffects = _result.statusEffects
				local __internal_id = self._internal_id
				_result = _statusEffects[__internal_id]
			end
			return _result
		end, function(current, old)
			return self:_internal_processDataUpdate(current, old)
		end)
		local _state = clientAtom()
		if _state ~= nil then
			local _statusEffects = _state.statusEffects
			local __internal_id = self._internal_id
			_state = _statusEffects[__internal_id]
		end
		local state = _state
		self:_internal_processDataUpdate(state)
		self._internal_janitor:Add(subscription)
	end
	function StatusEffect:OnConstruct(...)
		local Args = { ... }
	end
	function StatusEffect:OnConstructClient(...)
		local Args = { ... }
	end
	function StatusEffect:OnConstructServer(...)
		local Args = { ... }
	end
	function StatusEffect:OnStartServer()
	end
	function StatusEffect:OnStartClient()
	end
	function StatusEffect:OnEndClient()
	end
	function StatusEffect:OnEndServer()
	end
end
local function StatusEffectDecorator(Constructor)
	local name = tostring(Constructor)
	if registeredStatuses[name] ~= nil then
		logError(`StatusEffect with name {name} was already registered before`)
	end
	local _constructor = Constructor
	registeredStatuses[name] = _constructor
end
local function GetRegisteredStatusEffectConstructor(Name)
	local _name = Name
	return registeredStatuses[_name]
end
return {
	StatusEffectDecorator = StatusEffectDecorator,
	GetRegisteredStatusEffectConstructor = GetRegisteredStatusEffectConstructor,
	StatusEffect = StatusEffect,
}
