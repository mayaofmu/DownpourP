local Mobs = {} 

Mobs.Noob = {
	Stats = {
		MaxHealth = {Base = 80, PerLevel = 45},
		Damage = {Base = 16, PerLevel = 8},
		Regen = {Base = 3, PerLevel = 5},
		Armor = {Base = 1, PerLevel = 1},
		AttackSpeed = {Base = 1, PerLevel = 0.07},
		CritChance = {Base = 2, PerLevel = .4},
		MoveSpeed = {Base = 12, PerLevel = .5},
		CritDamage = {Base = 2.0, PerLevel = 0.06}
	},

	Description = "Ah, a noob wandering robloxia..",
	Model = script.Noob,
	DirectorCost = 15, -- Base cost for spawning,
	AgentRadius = 3, 
	AgentHeight = 5
} 


Mobs.Astolfo = {
	Stats = {
		MaxHealth = {Base = 80, PerLevel = 45},
		Damage = {Base = 16, PerLevel = 8},
		Regen = {Base = 3, PerLevel = 5},
		Armor = {Base = 1, PerLevel = 1},
		AttackSpeed = {Base = 1, PerLevel = 0.07},
		CritChance = {Base = 2, PerLevel = .4},
		MoveSpeed = {Base = 12, PerLevel = .5},
		CritDamage = {Base = 2.0, PerLevel = 0.06}
	},

	Description = "Ah, a noob wandering robloxia..",
	Model = script.Noob,
	DirectorCost = 15, -- Base cost for spawning,
	AgentRadius = 3, 
	AgentHeight = 5,
	EliteClass = "Boss",
} 

return Mobs 