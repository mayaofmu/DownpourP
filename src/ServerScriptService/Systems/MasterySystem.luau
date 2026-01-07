local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MasterySystem = {}

-- Constants
local BASE_EXP = 500
local EXP_MULTIPLIER = 1.5

-- Helper
local function CalculateMaxExp(level: number)
	return math.floor(BASE_EXP * (EXP_MULTIPLIER ^ (level - 1)))
end

-- We don't strictly need a cache if we trust Attributes as the source of truth for runtime,
-- but for server logic, it's safer to have a cache and sync to attributes.
local MasteryData = {} -- [Player] = {Level=1, Exp=0}

function MasterySystem.Initialize(player: Player)
	if MasteryData[player] then return end
	
	-- In a real game, Load from DataStore here
	local data = {
		Level = 1,
		Exp = 0
	}
	MasteryData[player] = data
	
	MasterySystem.UpdateAttributes(player)
end

function MasterySystem.UpdateAttributes(player: Player)
	local data = MasteryData[player]
	if not data then return end
	
	player:SetAttribute("MasteryLevel", data.Level)
	player:SetAttribute("MasteryExp", data.Exp)
	player:SetAttribute("MasteryMaxExp", CalculateMaxExp(data.Level))
end

function MasterySystem.AddExp(player: Player, amount: number)
	local data = MasteryData[player]
	if not data then return end
	
	data.Exp += amount
	
	local maxExp = CalculateMaxExp(data.Level)
	while data.Exp >= maxExp do
		data.Exp -= maxExp
		data.Level += 1
		maxExp = CalculateMaxExp(data.Level)
		-- Trigger Level Up Effects?
		print(string.format("[Mastery] %s Leveled Up to %d!", player.Name, data.Level))
	end
	
	MasterySystem.UpdateAttributes(player)
end

function MasterySystem.GetLevel(player: Player)
	return MasteryData[player] and MasteryData[player].Level or 1
end

-- Cleanup
Players.PlayerRemoving:Connect(function(player)
	MasteryData[player] = nil
end)

Players.PlayerAdded:Connect(function(player)
	MasterySystem.Initialize(player)
end)

-- Init existing
for _, player in ipairs(Players:GetPlayers()) do
	MasterySystem.Initialize(player)
end

return MasterySystem

