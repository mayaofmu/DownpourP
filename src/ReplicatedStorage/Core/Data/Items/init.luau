local Items = {}

export type ItemTier = "White" | "Green" | "Red" | "Boss" | "Lunar"

export type ItemDef = {
	Name: string,
	Tier: ItemTier,
	Description: string,
	Icon: string?, -- AssetId
	Model: string?, -- AssetId or Name if in ReplicatedStorage
}

function Items.Define(def: ItemDef)
	Items[def.Name] = def
end

-- White Items
Items.Define({
	Name = "Green Tea",
	Tier = "White",
	Description = "Increases attack speed by 7%, and movement speed 5%, increases health by 15",
      Model = script.Models["Green Tea"],
	Icon = script.Icons["Green Tea"],
})

Items.Define({
	Name = "Med Pack",
	Tier = "White",
	Description = "Increases health regen by 8%, and doubles health regen for 5 seconds after being hit",
	Model = script.Models["Med Pack"],
	Icon = script.Icons["Med Pack"],
})

Items.Define({
	Name = "Turtle Shell",
	Tier = "White",
	Description = "Increases armor by 15",
	Model = script.Models["Turtle Shell"],
	Icon = script.Icons["Turtle Shell"],
})

Items.Define({
	Name = "Scouter",
	Tier = "White",
	Description = "Increases Crit Chance by 8%",
	Model = script.Models["Scouter"],
	Icon = script.Icons["Scouter"],
})

Items.Define({
	Name = "Hermetic Boots",
	Tier = "White",
	Description = "Increases movement speed by 14%",
	Model = script.Models["Hermetic Boots"],
	Icon = script.Icons["Hermetic Boots"],
})


Items.Define({
	Name = "Feral Claws",
	Tier = "White",
	Description = "Increases attack speed by 15%",
	Model = script.Models["Feral Claws"],
	Icon = script.Icons["Feral Claws"],
})

-- Green Items
Items.Define({
	Name = "Kunai",
	Tier = "Green",
	Description = "10% proc chance on hit, pierces 2 enemies (+1 on stack), does 80% base damage (+50% on stack)",
	Model = script.Models["Kunai"],
	Icon = script.Icons["Kunai"],
})

Items.Define({
	Name = "Weakpoint Analyzer",
	Tier = "Green",
	Description = "Increases Crit Damage by 5%",
	Model = script.Models["Weakpoint Analyzer"],
	Icon = script.Icons["Weakpoint Analyzer"],
})

Items.Define({
	Name = "Corrosive Barrel",
	Tier = "Green",
	Description = "15% to apply a stack of corrosion on hit",
	Model = script.Models["Corrosive Barrel"],
	Icon = script.Icons["Corrosive Barrel"],
})

Items.Define({
	Name = "Rocket Launcher",
	Tier = "Green",
	Description = "15% chance on hitting an enemy to proc a rocket that fires towards target for 250% damage (+150% on stack), (+25% chance to fire another missile on stack)",
	Model = script.Models["Rocket Launcher"],
	Icon = script.Icons["Rocket Launcher"],
})

-- Red Items
Items.Define({
	Name = "Shooting Stars",
	Tier = "Red",
	Description = "20% chance on hit to fire 1 shooting star that does 800% base damage, 15 stud area of effect",
	Model = script.Models["Shooting Stars"],
	Icon = script.Icons["Shooting Stars"],
})

Items.Define({
	Name = "Golden Apple",
	Tier = "Red",
	Description = "Allows user to respawn on death",
	Model = script.Models["Golden Apple"],
	Icon = script.Icons["Golden Apple"],
})

Items.Define({
	Name = "Gungnir",
	Tier = "Red",
	Description = "20% chance on attack to fire a spear that deals 300% damage in a 12 stud radius",
	Model = script.Models["Gungnir"],
	Icon = script.Icons["Gungnir"],
})

return Items
