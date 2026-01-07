--!strict
--// SharedBlackboard.lua
--// Thread-safe shared knowledge system for parallel AI execution.
--// Uses Roblox SharedTable API for cross-Actor communication.

local HttpService = game:GetService("HttpService")

--// Type Definitions

export type SharedBlackboardConfig = {
	name: string?,
	defaultTTL: number?,
}

export type BlackboardEntry = {
	value: any,
	timestamp: number,
	ttl: number?,
	owner: string?,
}

--// Constants

local DEFAULT_TTL = 30
local CLEANUP_INTERVAL = 5

--// Class Definition

local SharedBlackboard = {}
SharedBlackboard.__index = SharedBlackboard

--// Creates a new SharedBlackboard (call on main thread).
function SharedBlackboard.new(config: SharedBlackboardConfig?): SharedBlackboard
	local cfg = config or {}
	local self = setmetatable({}, SharedBlackboard)

	self._name = cfg.name or "SharedBlackboard"
	self._defaultTTL = cfg.defaultTTL or DEFAULT_TTL
	self._id = HttpService:GenerateGUID(false)
	self._sharedTable = SharedTable.new()
	self._metadata = {}
	self._subscribers = {} :: { [string]: { (string, any) -> () } }
	self._isOwner = true
	self._lastCleanup = os.clock()

	return self
end

--// Creates from existing SharedTable (use in Actor scripts).
function SharedBlackboard.fromSharedTable(sharedTable: SharedTable, config: SharedBlackboardConfig?): SharedBlackboard
	local cfg = config or {}
	local self = setmetatable({}, SharedBlackboard)

	self._name = cfg.name or "SharedBlackboard"
	self._defaultTTL = cfg.defaultTTL or DEFAULT_TTL
	self._id = HttpService:GenerateGUID(false)
	self._sharedTable = sharedTable
	self._metadata = {}
	self._subscribers = {}
	self._isOwner = false
	self._lastCleanup = os.clock()

	return self
end

--// Core Operations

function SharedBlackboard:set(key: string, value: any, ttl: number?, owner: string?)
	local serializedValue = self:_serializeValue(value)

	SharedTable.update(self._sharedTable, key, function()
		return {
			v = serializedValue,
			t = os.clock(),
			ttl = ttl,
			o = owner,
		}
	end)

	self:_notifySubscribers(key, value)
end

function SharedBlackboard:get(key: string): any?
	local entry = self._sharedTable[key]
	if not entry then
		return nil
	end

	if entry.ttl and (os.clock() - entry.t) > entry.ttl then
		self:remove(key)
		return nil
	end

	return self:_deserializeValue(entry.v)
end

function SharedBlackboard:has(key: string): boolean
	return self:get(key) ~= nil
end

function SharedBlackboard:remove(key: string): boolean
	local existed = self._sharedTable[key] ~= nil

	SharedTable.update(self._sharedTable, key, function()
		return nil
	end)

	if existed then
		self:_notifySubscribers(key, nil)
	end

	return existed
end

--// Atomic Operations

function SharedBlackboard:increment(key: string, delta: number): number
	local newValue = 0

	SharedTable.update(self._sharedTable, key, function(current)
		local currentValue = 0
		if current and current.v then
			currentValue = current.v
		end
		newValue = currentValue + delta
		return {
			v = newValue,
			t = os.clock(),
			ttl = current and current.ttl or nil,
			o = current and current.o or nil,
		}
	end)

	self:_notifySubscribers(key, newValue)
	return newValue
end

function SharedBlackboard:atomicUpdate(key: string, updateFn: (any?) -> any): any
	local newValue: any = nil

	SharedTable.update(self._sharedTable, key, function(current)
		local currentValue = nil
		if current and current.v then
			currentValue = self:_deserializeValue(current.v)
		end

		newValue = updateFn(currentValue)
		local serialized = self:_serializeValue(newValue)

		return {
			v = serialized,
			t = os.clock(),
			ttl = current and current.ttl or nil,
			o = current and current.o or nil,
		}
	end)

	self:_notifySubscribers(key, newValue)
	return newValue
end

function SharedBlackboard:setIfNotExists(key: string, value: any, ttl: number?): boolean
	local wasSet = false

	SharedTable.update(self._sharedTable, key, function(current)
		if current ~= nil then
			local isExpired = current.ttl and (os.clock() - current.t) > current.ttl
			if not isExpired then
				return current
			end
		end

		wasSet = true
		return {
			v = self:_serializeValue(value),
			t = os.clock(),
			ttl = ttl,
			o = nil,
		}
	end)

	if wasSet then
		self:_notifySubscribers(key, value)
	end

	return wasSet
end

function SharedBlackboard:compareAndSwap(key: string, expected: any, newValue: any): boolean
	local swapped = false

	SharedTable.update(self._sharedTable, key, function(current)
		local currentValue = nil
		if current and current.v then
			currentValue = self:_deserializeValue(current.v)
		end

		if currentValue == expected then
			swapped = true
			return {
				v = self:_serializeValue(newValue),
				t = os.clock(),
				ttl = current and current.ttl or nil,
				o = current and current.o or nil,
			}
		end

		return current
	end)

	if swapped then
		self:_notifySubscribers(key, newValue)
	end

	return swapped
end

--// Target Claiming

function SharedBlackboard:claimTarget(targetId: string, claimerId: string, ttl: number?): boolean
	return self:setIfNotExists("_claim_" .. targetId, claimerId, ttl or 30)
end

function SharedBlackboard:releaseTarget(targetId: string, claimerId: string): boolean
	local claimKey = "_claim_" .. targetId
	local currentOwner = self:get(claimKey)

	if currentOwner == claimerId then
		self:remove(claimKey)
		return true
	end

	return false
end

function SharedBlackboard:getTargetClaimer(targetId: string): string?
	return self:get("_claim_" .. targetId)
end

function SharedBlackboard:isTargetClaimedBy(targetId: string, claimerId: string): boolean
	return self:getTargetClaimer(targetId) == claimerId
end

--// Team Alerts

function SharedBlackboard:broadcastAlert(alertType: string, data: { [string]: any }, ttl: number?)
	self:set("_alert_" .. alertType, {
		data = data,
		timestamp = os.clock(),
	}, ttl or 10)
end

function SharedBlackboard:getAlert(alertType: string): { data: { [string]: any }, timestamp: number }?
	return self:get("_alert_" .. alertType)
end

function SharedBlackboard:clearAlert(alertType: string)
	self:remove("_alert_" .. alertType)
end

--// Subscriptions (Local Only)

function SharedBlackboard:subscribe(key: string, callback: (string, any) -> ()): () -> ()
	if not self._subscribers[key] then
		self._subscribers[key] = {}
	end

	table.insert(self._subscribers[key], callback)

	return function()
		local subs = self._subscribers[key]
		if subs then
			local idx = table.find(subs, callback)
			if idx then
				table.remove(subs, idx)
			end
		end
	end
end

function SharedBlackboard:_notifySubscribers(key: string, value: any)
	local subs = self._subscribers[key]
	if subs then
		for _, callback in ipairs(subs) do
			task.spawn(callback, key, value)
		end
	end
end

--// Cleanup

function SharedBlackboard:cleanup(): number
	local removed = 0
	local now = os.clock()

	if now - self._lastCleanup < CLEANUP_INTERVAL then
		return 0
	end
	self._lastCleanup = now

	for key, entry in self._sharedTable do
		if entry and entry.ttl then
			if (now - entry.t) > entry.ttl then
				self:remove(key)
				removed += 1
			end
		end
	end

	return removed
end

function SharedBlackboard:clear()
	SharedTable.clear(self._sharedTable)
end

--// Accessors

function SharedBlackboard:getSharedTable(): SharedTable
	return self._sharedTable
end

function SharedBlackboard:getId(): string
	return self._id
end

function SharedBlackboard:getName(): string
	return self._name
end

function SharedBlackboard:isOwner(): boolean
	return self._isOwner
end

--// Serialization

function SharedBlackboard:_serializeValue(value: any): any
	local valueType = typeof(value)

	if valueType == "string" or valueType == "number" or valueType == "boolean" or value == nil then
		return value
	end

	if valueType == "Vector3" then
		return { _t = "v3", x = value.X, y = value.Y, z = value.Z }
	end

	if valueType == "CFrame" then
		return { _t = "cf", c = { value:GetComponents() } }
	end

	if valueType == "Color3" then
		return { _t = "c3", r = value.R, g = value.G, b = value.B }
	end

	if valueType == "table" then
		local copy = {}
		for k, v in pairs(value) do
			copy[k] = self:_serializeValue(v)
		end
		return copy
	end

	if valueType == "Instance" then
		return { _t = "inst", path = value:GetFullName() }
	end

	return tostring(value)
end

function SharedBlackboard:_deserializeValue(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local typeMarker = value._t

	if typeMarker == "v3" then
		return Vector3.new(value.x, value.y, value.z)
	end

	if typeMarker == "cf" then
		return CFrame.new(unpack(value.c))
	end

	if typeMarker == "c3" then
		return Color3.new(value.r, value.g, value.b)
	end

	if typeMarker == "inst" then
		local parts = string.split(value.path, ".")
		local current: Instance? = game

		for i = 2, #parts do
			if current then
				current = current:FindFirstChild(parts[i])
			end
		end

		return current
	end

	local copy = {}
	for k, v in pairs(value) do
		if k ~= "_t" then
			copy[k] = self:_deserializeValue(v)
		end
	end
	return copy
end

--// Debugging

function SharedBlackboard:__tostring(): string
	local count = 0
	for _ in self._sharedTable do
		count += 1
	end
	return string.format("SharedBlackboard{name=%s, entries=%d}", self._name, count)
end

function SharedBlackboard:debugSummary(): string
	local lines = {
		"SharedBlackboard: " .. self._name,
		string.format("  ID: %s", self._id),
		string.format("  Owner: %s", tostring(self._isOwner)),
		"  Entries:",
	}

	local count = 0
	for key, entry in self._sharedTable do
		count += 1
		local expired = ""
		if entry.ttl then
			local remaining = entry.ttl - (os.clock() - entry.t)
			expired = if remaining > 0 then string.format(" (%.1fs)", remaining) else " (EXPIRED)"
		end
		table.insert(lines, string.format("    %s: %s%s", key, tostring(entry.v), expired))
		if count > 10 then
			table.insert(lines, "    ...")
			break
		end
	end

	if count == 0 then
		table.insert(lines, "    (empty)")
	end

	return table.concat(lines, "\n")
end

export type SharedBlackboard = typeof(SharedBlackboard.new())

return SharedBlackboard
