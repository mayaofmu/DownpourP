-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local createBinarySerializer = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "flamework-binary-serializer", "out").createBinarySerializer
local skillRequestSerializer = createBinarySerializer({ "tuple", { { "string" }, { "literal", { "End", "Start" }, 0 }, { "array", { "optional", { "blob" } } } }, nil })
local messageSerializer = createBinarySerializer({ "tuple", { { "string" }, { "string" }, { "map", { "f64" }, { "optional", { "blob" } } } }, nil })
return {
	skillRequestSerializer = skillRequestSerializer,
	messageSerializer = messageSerializer,
}
