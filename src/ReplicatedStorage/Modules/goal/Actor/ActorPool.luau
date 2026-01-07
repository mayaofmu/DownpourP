--!strict
--// ActorPool.lua
--// High-performance concurrent task scheduler with efficient data structures.
--//
--// NOTE: For true parallel execution of GOAP planning, use ParallelPlanner
--// which leverages task.desynchronize(). This module provides efficient
--// concurrent task management with O(1) operations.

--// Type Definitions

export type ActorPoolConfig = {
	poolSize: number?,
	name: string?,
}

export type WorkItem<T> = {
	callback: (number) -> T,
	thread: thread,
	startTime: number,
}

export type PoolStats = {
	poolSize: number,
	busyCount: number,
	idleCount: number,
	queuedCount: number,
	totalProcessed: number,
	averageProcessTime: number,
}

--// Constants

local DEFAULT_POOL_SIZE = 4
local DEFAULT_NAME = "GoalWorker"

--// Class Definition

local ActorPool = {}
ActorPool.__index = ActorPool

--// Creates a new concurrent task pool.
function ActorPool.new(config: ActorPoolConfig?): ActorPool
	local cfg = config or {}
	local self = setmetatable({}, ActorPool)

	self._poolSize = cfg.poolSize or DEFAULT_POOL_SIZE
	self._baseName = cfg.name or DEFAULT_NAME

	--// Worker slots (simple integers representing available workers)
	self._idleStack = {} :: { number } --// Stack for O(1) push/pop
	self._busyMap = {} :: { [number]: WorkItem<any> } --// Track busy workers

	--// Work queue (deque with head/tail for O(1) enqueue/dequeue)
	self._queue = {} :: { WorkItem<any> }
	self._queueHead = 1
	self._queueTail = 0

	--// Stats
	self._totalProcessed = 0
	self._totalProcessTime = 0

	--// Initialize all workers as idle
	for i = 1, self._poolSize do
		table.insert(self._idleStack, i)
	end

	return self
end

--// Work Submission

--// Submits work to be processed. Blocks until complete.
function ActorPool:submit<T>(callback: (number) -> T): T
	local workerId = self:_popIdleWorker()

	if workerId then
		return self:_executeWork(workerId, callback)
	else
		return self:_enqueueWork(callback)
	end
end

--// Submit work without blocking. Returns handle to await result.
function ActorPool:submitAsync<T>(callback: (number) -> T): {
	await: () -> T,
	isComplete: () -> boolean,
}
	local complete = false
	local result: T
	local waitingThread: thread? = nil

	task.spawn(function()
		result = self:submit(callback)
		complete = true
		if waitingThread then
			task.spawn(waitingThread, result)
		end
	end)

	return {
		await = function(): T
			if complete then
				return result
			end
			waitingThread = coroutine.running()
			return coroutine.yield()
		end,
		isComplete = function(): boolean
			return complete
		end,
	}
end

--// O(1) Operations

function ActorPool:_popIdleWorker(): number?
	local count = #self._idleStack
	if count == 0 then
		return nil
	end
	local workerId = self._idleStack[count]
	self._idleStack[count] = nil
	return workerId
end

function ActorPool:_pushIdleWorker(workerId: number)
	table.insert(self._idleStack, workerId)
end

function ActorPool:_enqueue(item: WorkItem<any>)
	self._queueTail += 1
	self._queue[self._queueTail] = item
end

function ActorPool:_dequeue(): WorkItem<any>?
	if self._queueHead > self._queueTail then
		return nil
	end

	local item = self._queue[self._queueHead]
	self._queue[self._queueHead] = nil
	self._queueHead += 1

	--// Reset when empty to prevent unbounded index growth
	if self._queueHead > self._queueTail then
		self._queueHead = 1
		self._queueTail = 0
	end

	return item
end

--// Work Execution

function ActorPool:_executeWork<T>(workerId: number, callback: (number) -> T): T
	local thread = coroutine.running()
	local startTime = os.clock()

	self._busyMap[workerId] = {
		callback = callback,
		thread = thread,
		startTime = startTime,
	}

	--// Execute in a new thread to allow yielding
	task.spawn(function()
		local success, result = pcall(callback, workerId)
		local elapsed = os.clock() - startTime

		--// Update stats
		self._totalProcessed += 1
		self._totalProcessTime += elapsed

		--// Clear busy state
		self._busyMap[workerId] = nil

		--// Process next queued work or return worker to pool
		local nextWork = self:_dequeue()
		if nextWork then
			task.spawn(function()
				local nextResult = self:_executeWork(workerId, nextWork.callback)
				task.spawn(nextWork.thread, nextResult)
			end)
		else
			self:_pushIdleWorker(workerId)
		end

		--// Resume original caller
		if success then
			task.spawn(thread, result)
		else
			--// Propagate error
			task.spawn(function()
				coroutine.resume(thread)
				error(result)
			end)
		end
	end)

	return coroutine.yield()
end

function ActorPool:_enqueueWork<T>(callback: (number) -> T): T
	local thread = coroutine.running()

	self:_enqueue({
		callback = callback,
		thread = thread,
		startTime = os.clock(),
	})

	return coroutine.yield()
end

--// Batch Processing

--// Process multiple items concurrently (not parallel - use ParallelPlanner for that)
function ActorPool:processBatch<T, R>(items: { T }, processor: (T, number) -> R): { R }
	local count = #items
	if count == 0 then
		return {}
	end

	local results = table.create(count)
	local completed = 0
	local mainThread = coroutine.running()

	for i, item in ipairs(items) do
		task.spawn(function()
			results[i] = self:submit(function(workerId)
				return processor(item, workerId)
			end)
			completed += 1

			if completed == count then
				task.spawn(mainThread)
			end
		end)
	end

	if completed < count then
		coroutine.yield()
	end

	return results
end

--// Process with explicit concurrency limit
function ActorPool:processBatchLimited<T, R>(items: { T }, processor: (T, number) -> R, limit: number?): { R }
	local count = #items
	if count == 0 then
		return {}
	end

	local maxConcurrent = math.min(limit or self._poolSize, count)
	local results = table.create(count)
	local nextIndex = 1
	local completed = 0
	local running = 0
	local mainThread = coroutine.running()

	local function startNext()
		while running < maxConcurrent and nextIndex <= count do
			local i = nextIndex
			nextIndex += 1
			running += 1

			task.spawn(function()
				results[i] = self:submit(function(workerId)
					return processor(items[i], workerId)
				end)
				running -= 1
				completed += 1

				if completed == count then
					task.spawn(mainThread)
				else
					startNext()
				end
			end)
		end
	end

	startNext()

	if completed < count then
		coroutine.yield()
	end

	return results
end

--// Pool Management

function ActorPool:getStats(): PoolStats
	local busyCount = 0
	for _ in pairs(self._busyMap) do
		busyCount += 1
	end

	local queuedCount = math.max(0, self._queueTail - self._queueHead + 1)

	local avgTime = 0
	if self._totalProcessed > 0 then
		avgTime = self._totalProcessTime / self._totalProcessed
	end

	return {
		poolSize = self._poolSize,
		busyCount = busyCount,
		idleCount = #self._idleStack,
		queuedCount = queuedCount,
		totalProcessed = self._totalProcessed,
		averageProcessTime = avgTime,
	}
end

function ActorPool:getPoolSize(): number
	return self._poolSize
end

function ActorPool:getIdleCount(): number
	return #self._idleStack
end

function ActorPool:getBusyCount(): number
	local count = 0
	for _ in pairs(self._busyMap) do
		count += 1
	end
	return count
end

function ActorPool:getQueueSize(): number
	return math.max(0, self._queueTail - self._queueHead + 1)
end

function ActorPool:resize(newSize: number)
	assert(newSize > 0, "Pool size must be positive")

	if newSize > self._poolSize then
		--// Add workers
		for i = self._poolSize + 1, newSize do
			table.insert(self._idleStack, i)
		end
		self._poolSize = newSize
	elseif newSize < self._poolSize then
		--// Remove idle workers from the end
		local newIdleStack = {}
		for _, workerId in ipairs(self._idleStack) do
			if workerId <= newSize then
				table.insert(newIdleStack, workerId)
			end
		end
		self._idleStack = newIdleStack
		self._poolSize = newSize
	end
end

function ActorPool:destroy()
	--// Resume any queued work with nil
	while true do
		local work = self:_dequeue()
		if not work then
			break
		end
		task.spawn(work.thread)
	end

	--// Note: Cannot cancel busy work, let it complete
	self._idleStack = {}
	self._busyMap = {}
	self._poolSize = 0
end

--// Debugging

function ActorPool:__tostring(): string
	local stats = self:getStats()
	return string.format(
		"ActorPool{size=%d, busy=%d, idle=%d, queued=%d}",
		stats.poolSize,
		stats.busyCount,
		stats.idleCount,
		stats.queuedCount
	)
end

function ActorPool:debugSummary(): string
	local stats = self:getStats()
	return table.concat({
		"ActorPool (Concurrent Scheduler)",
		string.format("  Pool Size: %d workers", stats.poolSize),
		string.format("  Status: %d busy, %d idle, %d queued", stats.busyCount, stats.idleCount, stats.queuedCount),
		string.format("  Processed: %d tasks", stats.totalProcessed),
		string.format("  Avg Time: %.4fs per task", stats.averageProcessTime),
	}, "\n")
end

export type ActorPool = typeof(ActorPool.new())

return ActorPool
