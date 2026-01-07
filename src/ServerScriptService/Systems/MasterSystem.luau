local MasterSystem = {}

local ItemSystem = require(script.Parent.ItemSystem)
local Inventory = ItemSystem.Inventory

local PlayerInventories = {} -- [Player] = Inventory
local MobInventories = {} -- [Model] = Inventory (For AI Masters)

-- Initialize for Players
function MasterSystem.GetPlayerInventory(player: Player)
	if not PlayerInventories[player] then
		print("[MasterSystem] Creating new persistent inventory for", player.Name)
		PlayerInventories[player] = Inventory.new()
	end
	return PlayerInventories[player]
end

-- Cleanup
game.Players.PlayerRemoving:Connect(function(player)
	PlayerInventories[player] = nil
end)

-- AI / Mobs
function MasterSystem.RegisterMob(model: Model)
	if not MobInventories[model] then
		MobInventories[model] = Inventory.new()
	end
	return MobInventories[model]
end

function MasterSystem.UnregisterMob(model: Model)
	MobInventories[model] = nil
end

return MasterSystem

