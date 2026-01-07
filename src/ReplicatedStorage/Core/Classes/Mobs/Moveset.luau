local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WCS = require(ReplicatedStorage.Modules.wcs)

local EnemyProjectile = require(ReplicatedStorage.Core.Classes.Abilities.EnemyProjectile)
local MobMoveset = WCS.CreateMoveset("MobMoveset", {
	EnemyProjectile
})

return MobMoveset

