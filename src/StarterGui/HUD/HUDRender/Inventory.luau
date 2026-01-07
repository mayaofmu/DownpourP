local HUDScreenGui = script.Parent.Parent 
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inventory = {}

Inventory.__index = Inventory

function Inventory.new() 
 
    local self = setmetatable({}, Inventory)

    self.InventoryFrame = HUDScreenGui:WaitForChild("InventoryFrame")
    self.InventoryGrid = self.InventoryFrame:WaitForChild("Inventory")
 
    function self:UpdateUI(inventory)

        for _, icon in pairs(self.InventoryGrid:GetChildren()) do
            if not icon:IsA("ImageLabel") then
               continue 
            end
   
            local iconName = icon.Name

            local inInventory = inventory[iconName] 
   
            local amountLabel = icon:FindFirstChild("Amount")
            
            if inInventory then 
                icon.Visible = true      

				if inInventory > 1 then
					amountLabel.Visible = true
                    amountLabel.Text = inInventory
                else 
                    amountLabel.Text = ""
                    amountLabel.Visible = false
                end 
            else
                icon.Visible = false
            end
        end
    end 
    return self
end 




return Inventory 