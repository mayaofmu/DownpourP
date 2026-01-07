--!strict
--// NPCScheduler.lua
--// High-level scheduler for managing NPC AI updates with tick budgeting.
--// Uses Planner for GOAP planning.

local RunService = game:GetService("RunService")

local Planner = require(script.Parent.Parent.Planner)

--// Type Definitions

export type NPCSchedulerConfig = {
	tickBudget: number?,
	maxNPCsPerTick: number?,
	updateInterval: number?,
	priorityDecay: number?,
}

export type NPCCallbacks = {
	getState: () -> any,
	getGoal: () -> any?,
	getGoals: (() -> { any })?,
	onPlanReady: (any) -> (),
	onError: ((string) -> ())?,
	getPriority: (() -> number)?,
}

export type NPCEntry = {
	id: string,
	callbacks: NPCCallbacks,
	planner: any,
	priority: number,
	basePriority: number,
	lastUpdate: number,
	updateCount: number,
	enabled: boolean,
}

export type SchedulerStats = {
	registeredNPCs: number,
	activeNPCs: number,
	updatesThisTick: number,
	totalUpdates: number,
	averageTickTime: number,
	tickBudgetUsage: number,
}

--// Constants

local DEFAULT_TICK_BUDGET = 0.004 --// 4ms per frame
local DEFAULT_MAX_NPCS_PER_TICK = 10
local DEFAULT_UPDATE_INTERVAL = 0.1
local DEFAULT_PRIORITY_DECAY = 0.95
local DEFAULT_BASE_PRIORITY = 1

--// Class Definition

local NPCScheduler = {}
NPCScheduler.__index = NPCScheduler

function NPCScheduler.new(config: NPCSchedulerConfig?): NPCScheduler
	local cfg = config or {}
	local self = setmetatable({}, NPCScheduler)

	self._tickBudget = cfg.tickBudget or DEFAULT_TICK_BUDGET
	self._maxNPCsPerTick = cfg.maxNPCsPerTick or DEFAULT_MAX_NPCS_PER_TICK
	self._updateInterval = cfg.updateInterval or DEFAULT_UPDATE_INTERVAL
	self._priorityDecay = cfg.priorityDecay or DEFAULT_PRIORITY_DECAY

	self._npcs = {} :: { [string]: NPCEntry }
	self._npcList = {} :: { string }
	self._running = false
	self._connection = nil :: RBXScriptConnection?

	--// Stats
	self._totalUpdates = 0
	self._tickTimes = {} :: { number }
	self._maxTickSamples = 60
	self._updatesThisTick = 0

	return self
end

--// NPC Registration

function NPCScheduler:registerNPC(id: string, callbacks: NPCCallbacks, plannerConfig: { [string]: any }?): NPCEntry
	assert(type(id) == "string" and #id > 0, "NPC id must be a non-empty string")
	assert(callbacks.getState, "callbacks.getState is required")
	assert(callbacks.getGoal or callbacks.getGoals, "callbacks.getGoal or callbacks.getGoals is required")
	assert(callbacks.onPlanReady, "callbacks.onPlanReady is required")

	local planner = Planner.new(plannerConfig)

	local entry: NPCEntry = {
		id = id,
		callbacks = callbacks,
		planner = planner,
		priority = DEFAULT_BASE_PRIORITY,
		basePriority = DEFAULT_BASE_PRIORITY,
		lastUpdate = 0,
		updateCount = 0,
		enabled = true,
	}

	self._npcs[id] = entry
	table.insert(self._npcList, id)
	return entry
end

function NPCScheduler:unregisterNPC(id: string): boolean
	local entry = self._npcs[id]
	if not entry then
		return false
	end

	self._npcs[id] = nil
	local idx = table.find(self._npcList, id)
	if idx then
		table.remove(self._npcList, idx)
	end

	return true
end

function NPCScheduler:getNPC(id: string): NPCEntry?
	return self._npcs[id]
end

function NPCScheduler:getPlanner(id: string): any?
	local entry = self._npcs[id]
	return if entry then entry.planner else nil
end

function NPCScheduler:registerActions(id: string, actions: { any })
	local planner = self:getPlanner(id)
	if planner then
		planner:registerActions(actions)
	end
end

function NPCScheduler:registerActionsForAll(actions: { any })
	for _, entry in pairs(self._npcs) do
		entry.planner:registerActions(actions)
	end
end

--// Priority Management

function NPCScheduler:setNPCPriority(id: string, priority: number)
	local entry = self._npcs[id]
	if entry then
		entry.basePriority = priority
		entry.priority = priority
	end
end

function NPCScheduler:setNPCEnabled(id: string, enabled: boolean)
	local entry = self._npcs[id]
	if entry then
		entry.enabled = enabled
	end
end

function NPCScheduler:boostPriority(id: string, boost: number)
	local entry = self._npcs[id]
	if entry then
		entry.priority += boost
	end
end

--// Scheduler Control

function NPCScheduler:start()
	if self._running then
		return
	end

	self._running = true
	self._connection = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
end

function NPCScheduler:stop()
	self._running = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

function NPCScheduler:isRunning(): boolean
	return self._running
end

function NPCScheduler:tick(dt: number?)
	self:_tick(dt or 0.016)
end

--// Core Tick Processing

function NPCScheduler:_tick(_dt: number)
	local tickStart = os.clock()
	self._updatesThisTick = 0

    if not self._candidatesCache then self._candidatesCache = {} end
    table.clear(self._candidatesCache)
	local candidates = self:_getCandidatesForUpdate(self._candidatesCache)

	for _, entry in ipairs(candidates) do
		--// Check budget
		if os.clock() - tickStart >= self._tickBudget then
			break
		end

		--// Check per-tick limit
		if self._updatesThisTick >= self._maxNPCsPerTick then
			break
		end

		self:_updateNPC(entry)
	end

	local tickTime = os.clock() - tickStart
	self:_recordTickTime(tickTime)
	self:_decayPriorities()
end

function NPCScheduler:_getCandidatesForUpdate(results: { NPCEntry }): { NPCEntry }
	local now = os.clock()
	
    -- Temporary table for sorting
    if not self._sortCache then self._sortCache = {} end
    local sortCache = self._sortCache
    table.clear(sortCache)

	for _, entry in pairs(self._npcs) do
		if not entry.enabled then
			continue
		end

		local timeSinceUpdate = now - entry.lastUpdate
		if timeSinceUpdate < self._updateInterval then
			continue
		end

		--// Priority boost based on time since last update
		local timeFactor = math.min(timeSinceUpdate / self._updateInterval, 5)
		local effectivePriority = entry.priority * timeFactor

		--// Dynamic priority from callback
		if entry.callbacks.getPriority then
			effectivePriority *= entry.callbacks.getPriority()
		end

		table.insert(sortCache, {
			entry = entry,
			effectivePriority = effectivePriority,
		})
	end

	--// Sort by effective priority (highest first)
	table.sort(sortCache, function(a, b)
		return a.effectivePriority > b.effectivePriority
	end)

	--// Extract entries
	for _, c in ipairs(sortCache) do
		table.insert(results, c.entry)
	end

	return results
end

function NPCScheduler:_updateNPC(entry: NPCEntry)
	local state = entry.callbacks.getState()

	--// Get goal(s)
	local goals
	local isMultiple = false

	if entry.callbacks.getGoals then
		goals = entry.callbacks.getGoals()
		isMultiple = goals and #goals > 0
	end

	if not isMultiple then
		goals = entry.callbacks.getGoal()
	end

	if not goals then
		return
	end

	--// Plan (uses parallel execution internally)
	local success, result = pcall(function()
		if isMultiple then
			return entry.planner:planBestGoalParallel(state, goals)
		else
			return entry.planner:planParallel(state, goals)
		end
	end)

	if success and result then
		entry.callbacks.onPlanReady(result)
		entry.lastUpdate = os.clock()
		entry.updateCount += 1
		self._totalUpdates += 1
		self._updatesThisTick += 1
	elseif not success and entry.callbacks.onError then
		entry.callbacks.onError(tostring(result))
	end
end

function NPCScheduler:_decayPriorities()
	for _, entry in pairs(self._npcs) do
		local diff = entry.priority - entry.basePriority
		entry.priority = entry.basePriority + diff * self._priorityDecay
	end
end

function NPCScheduler:_recordTickTime(time: number)
	table.insert(self._tickTimes, time)
	while #self._tickTimes > self._maxTickSamples do
		table.remove(self._tickTimes, 1)
	end
end

--// Immediate Updates

function NPCScheduler:forceUpdate(id: string): any?
	local entry = self._npcs[id]
	if not entry or not entry.enabled then
		return nil
	end

	self:_updateNPC(entry)
	return entry.planner:getProfilingData()
end

function NPCScheduler:forceUpdateAll(): number
	local count = 0
	for _, entry in pairs(self._npcs) do
		if entry.enabled then
			self:_updateNPC(entry)
			count += 1
		end
	end
	return count
end

--// Configuration

function NPCScheduler:setTickBudget(budget: number)
	assert(budget > 0, "Budget must be positive")
	self._tickBudget = budget
end

function NPCScheduler:setMaxNPCsPerTick(max: number)
	assert(max > 0, "Max must be positive")
	self._maxNPCsPerTick = max
end

function NPCScheduler:setUpdateInterval(interval: number)
	assert(interval > 0, "Interval must be positive")
	self._updateInterval = interval
end

--// Statistics

function NPCScheduler:getStats(): SchedulerStats
	local activeCount = 0
	for _, entry in pairs(self._npcs) do
		if entry.enabled then
			activeCount += 1
		end
	end

	local avgTickTime = 0
	if #self._tickTimes > 0 then
		local sum = 0
		for _, t in ipairs(self._tickTimes) do
			sum += t
		end
		avgTickTime = sum / #self._tickTimes
	end

	return {
		registeredNPCs = #self._npcList,
		activeNPCs = activeCount,
		updatesThisTick = self._updatesThisTick,
		totalUpdates = self._totalUpdates,
		averageTickTime = avgTickTime,
		tickBudgetUsage = if self._tickBudget > 0 then avgTickTime / self._tickBudget else 0,
	}
end

function NPCScheduler:getNPCStats(id: string): { updateCount: number, lastUpdate: number, priority: number }?
	local entry = self._npcs[id]
	if not entry then
		return nil
	end

	return {
		updateCount = entry.updateCount,
		lastUpdate = entry.lastUpdate,
		priority = entry.priority,
	}
end

function NPCScheduler:resetStats()
	self._totalUpdates = 0
	self._tickTimes = {}
	self._updatesThisTick = 0

	for _, entry in pairs(self._npcs) do
		entry.updateCount = 0
		entry.planner:resetStats()
	end
end

--// Cleanup

function NPCScheduler:destroy()
	self:stop()
	self._npcs = {}
	self._npcList = {}
end

--// Debugging

function NPCScheduler:__tostring(): string
	local stats = self:getStats()
	return string.format(
		"NPCScheduler{npcs=%d, active=%d, updates=%d, running=%s}",
		stats.registeredNPCs,
		stats.activeNPCs,
		stats.totalUpdates,
		tostring(self._running)
	)
end

function NPCScheduler:debugSummary(): string
	local stats = self:getStats()

	return table.concat({
		"NPCScheduler",
		string.format("  Running: %s", tostring(self._running)),
		string.format("  Budget: %.1fms / Max per tick: %d", self._tickBudget * 1000, self._maxNPCsPerTick),
		string.format("  NPCs: %d registered, %d active", stats.registeredNPCs, stats.activeNPCs),
		string.format("  Updates: %d total, %d this tick", stats.totalUpdates, stats.updatesThisTick),
		string.format("  Avg Tick: %.2fms (%.1f%% budget)", stats.averageTickTime * 1000, stats.tickBudgetUsage * 100),
	}, "\n")
end

export type NPCScheduler = typeof(NPCScheduler.new())

return NPCScheduler
