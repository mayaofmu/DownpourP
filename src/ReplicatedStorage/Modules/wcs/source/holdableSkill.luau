-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local _timer = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "timer", "out")
local Timer = _timer.Timer
local TimerState = _timer.TimerState
local _skill = TS.import(script, script.Parent, "skill")
local SkillBase = _skill.SkillBase
local SkillType = _skill.SkillType
local _utility = TS.import(script, script.Parent, "utility")
local isClientContext = _utility.isClientContext
local isServerContext = _utility.isServerContext
local logError = _utility.logError
local HoldableSkill
do
	local super = SkillBase
	HoldableSkill = setmetatable({}, {
		__tostring = function()
			return "HoldableSkill"
		end,
		__index = super,
	})
	HoldableSkill.__index = HoldableSkill
	function HoldableSkill:constructor(Props, ...)
		local Args = { ... }
		super.constructor(self, Props, unpack(Args))
		self.HoldTimer = Timer.new(10)
		self._internal_skillType = SkillType.Holdable
		if isServerContext() then
			self._internal_janitor:Add(self.HoldTimer.completed:Connect(function()
				return self:GetState().IsActive and self:End()
			end), "Disconnect")
		end
		self._internal_janitor:Add(self.HoldTimer, "destroy")
		self:_internal_init()
	end
	function HoldableSkill:_internal_stateDependentCallbacks(State, PreviousState)
		if not PreviousState.IsActive and State.IsActive then
			if self:GetState().MaxHoldTime ~= nil then
				self.HoldTimer:start()
			end
			self.Started:Fire()
			self._internal_executionThread = task.spawn(function()
				if isClientContext() then
					self:OnStartClient(unpack((State.StarterParams)))
				else
					self:OnStartServer(unpack((State.StarterParams)))
				end
			end)
		elseif PreviousState.IsActive and not State.IsActive then
			if self.HoldTimer:getState() == TimerState.Running then
				self.HoldTimer:stop()
			end
			if self._internal_executionThread then
				task.cancel(self._internal_executionThread)
			end
			if isClientContext() then
				self:OnEndClient()
			else
				self:OnEndServer()
			end
			self.Ended:Fire()
		end
		if State.MaxHoldTime ~= PreviousState.MaxHoldTime then
			local _value = State.MaxHoldTime
			if _value ~= 0 and _value == _value and _value then
				self.HoldTimer:setLength(State.MaxHoldTime)
			end
		end
	end
	function HoldableSkill:SetMaxHoldTime(MaxHoldTime)
		local _condition = MaxHoldTime
		if _condition ~= 0 and _condition == _condition and _condition then
			_condition = MaxHoldTime <= 0
		end
		if _condition ~= 0 and _condition == _condition and _condition then
			logError("Max Hold Time can't be lower or equal to zero")
		end
		self:_internal_setState({
			MaxHoldTime = MaxHoldTime,
		})
		if MaxHoldTime ~= 0 and MaxHoldTime == MaxHoldTime and MaxHoldTime then
			self.HoldTimer:setLength(MaxHoldTime)
		end
	end
	function HoldableSkill:GetMaxHoldTime()
		return self:GetState().MaxHoldTime
	end
end
return {
	HoldableSkill = HoldableSkill,
}
