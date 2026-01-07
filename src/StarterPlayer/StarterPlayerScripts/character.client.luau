local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local NetRay = require(ReplicatedStorage.Modules.NetRay)
local WCS = require(ReplicatedStorage.Modules.wcs)
local Character = WCS.Character

local inventoryChangedEvent =NetRay:GetEvent("InventoryChanged")
local statsUpdatedEvent =NetRay:GetEvent("StatsUpdated")

local PlayerGui
local HUD
local HUDRender



Player.CharacterAdded:Connect(function(CharacterModel)
	PlayerGui = Player:WaitForChild("PlayerGui")
	HUD = PlayerGui:WaitForChild("HUD")
	
	if not HUDRender then
		HUDRender = require(HUD.HUDRender):Init()
	end
end)


inventoryChangedEvent:OnEvent(function(data)
    if HUDRender and HUDRender.Inventory then
        HUDRender.Inventory:UpdateUI(data)
    end
end)
 
statsUpdatedEvent:OnEvent(function(data)
    if HUDRender and HUDRender.Stats then
        HUDRender.Stats:UpdateUI(data)
    end
end)
