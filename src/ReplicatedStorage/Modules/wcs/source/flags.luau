-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local Symbol = TS.import(script, script.Parent.Parent, "symbol").Symbol
local Flags = {
	CanAssignCustomId = Symbol("__CanAssignCustomID_Flag"),
	CanCreateCharacterClient = Symbol("__CanCreateCharacterClient_Flag"),
	CanInstantiateSkillClient = Symbol("__CanInstantiateSkillClient_Flag"),
	CanDestroyLocallyClient = Symbol("__CanDestroyLocallyClient_Flag"),
}
return {
	Flags = Flags,
}
