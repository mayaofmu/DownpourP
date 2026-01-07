local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Modules.Signal)

local ProgressionSystem = {}

-- Types
export type CharacterData = {
	Level: number,
	Exp: number,
	Money: number,
	MaxExp: number,
}

-- Signals
ProgressionSystem.LevelUp = Signal()
ProgressionSystem.ExpChanged = Signal()
ProgressionSystem.MoneyChanged = Signal()

-- Data Storage (Weak Keys for auto-cleanup on Destroy)
local CharacterDataMap = setmetatable({}, {__mode = "k"}) -- [Model] = CharacterData

-- Configuration
local BASE_EXP = 20
local EXP_EXPONENT = 1.55

local function CalculateMaxExp(level: number)
	return math.floor(BASE_EXP * (EXP_EXPONENT ^ (level - 1)))
end

local function UpdateAttributes(character: Model, data: CharacterData)
	character:SetAttribute("Level", data.Level)
	character:SetAttribute("Exp", data.Exp)
	character:SetAttribute("RequiredExp", data.MaxExp)
	character:SetAttribute("Cash", data.Money)
end

function ProgressionSystem.GetCharacterData(character: Model): CharacterData
	if not CharacterDataMap[character] then
		-- Default Data
		local data = {
			Level = 1,
			Exp = 0,
			Money = 0,
			MaxExp = CalculateMaxExp(1)
		}
		CharacterDataMap[character] = data
		UpdateAttributes(character, data)
	end
	return CharacterDataMap[character]
end

function ProgressionSystem.AddExp(character: Model, amount: number)
	local data = ProgressionSystem.GetCharacterData(character)
	data.Exp += amount
	
	-- Resolve Player for Signals (if exists)
	-- local player = Players:GetPlayerFromCharacter(character)
	
	-- Check Level Up
	while data.Exp >= data.MaxExp do
		data.Exp -= data.MaxExp
		data.Level += 1
		data.MaxExp = CalculateMaxExp(data.Level)
		
		ProgressionSystem.LevelUp:Fire(character, data.Level)
	end

	UpdateAttributes(character, data)
	ProgressionSystem.ExpChanged:Fire(character, data.Exp, data.MaxExp)
end

function ProgressionSystem.AddMoney(character: Model, amount: number)
	local data = ProgressionSystem.GetCharacterData(character)
	data.Money += amount
	UpdateAttributes(character, data)
	ProgressionSystem.MoneyChanged:Fire(character, data.Money)
end

function ProgressionSystem.GetLevel(character: Model)
	return ProgressionSystem.GetCharacterData(character).Level
end

function ProgressionSystem.GetMoney(character: Model)
	return ProgressionSystem.GetCharacterData(character).Money
end

-- Cleanup (Handled by Weak Table)

return ProgressionSystem

