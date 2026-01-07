-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local t = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "t", "lib", "ts").t
local Networking = TS.import(script, script.Parent.Parent, "include", "node_modules", "@flamework", "networking", "out").Networking
local GlobalFunctions = Networking.createFunction("@rbxts/wcs:source/networking@GlobalFunctions")
local ServerFunctions = GlobalFunctions:createServer({}, {
	incomingIds = { "messageToServer" },
	incoming = {
		messageToServer = { { t.interface({
			buffer = t.typeof("buffer"),
			blobs = t.array(t.any),
		}) }, nil },
	},
	outgoingIds = { "messageToClient" },
	outgoing = {
		messageToClient = t.union(t.any, t.none),
	},
	namespaceIds = {},
	namespaces = {},
})
local ClientFunctions = GlobalFunctions:createClient({}, {
	incomingIds = { "messageToClient" },
	incoming = {
		messageToClient = { { t.interface({
			buffer = t.typeof("buffer"),
			blobs = t.array(t.any),
		}) }, nil },
	},
	outgoingIds = { "messageToServer" },
	outgoing = {
		messageToServer = t.union(t.any, t.none),
	},
	namespaceIds = {},
	namespaces = {},
})
local GlobalEvents = Networking.createEvent("@rbxts/wcs:source/networking@GlobalEvents")
local ServerEvents = GlobalEvents:createServer({}, {
	incomingIds = { "messageToServer", "start", "requestSkill", "messageToServer_urel" },
	incoming = {
		messageToServer = { { t.interface({
			buffer = t.typeof("buffer"),
			blobs = t.array(t.any),
		}) }, nil },
		start = { {}, nil },
		requestSkill = { { t.interface({
			buffer = t.typeof("buffer"),
			blobs = t.array(t.any),
		}) }, nil },
		messageToServer_urel = { { t.interface({
			buffer = t.typeof("buffer"),
			blobs = t.array(t.any),
		}) }, nil },
	},
	incomingUnreliable = {
		messageToServer_urel = true,
	},
	outgoingIds = { "messageToClient", "sync", "messageToClient_urel", "damageTaken", "damageDealt" },
	outgoingUnreliable = {
		messageToClient_urel = true,
	},
	namespaceIds = {},
	namespaces = {},
})
local ClientEvents = GlobalEvents:createClient({}, {
	incomingIds = { "messageToClient", "sync", "messageToClient_urel", "damageTaken", "damageDealt" },
	incoming = {
		messageToClient = { { t.interface({
			buffer = t.typeof("buffer"),
			blobs = t.array(t.any),
		}) }, nil },
		sync = { { t.array(t.union(t.interface({
			type = t.literal("init"),
			data = t.interface({
				atom = t.optional(t.interface({
					instance = t.instanceIsA("Instance"),
					statusEffects = t.map(t.string, t.interface({
						className = t.string,
						state = t.interface({
							_timerEndTimestamp = t.optional(t.number),
							_startTimestamp = t.optional(t.number),
							IsActive = t.boolean,
						}),
						endTimestamp = t.optional(t.number),
						humanoidData = t.optional(t.interface({
							Props = t.interface({
								WalkSpeed = t.optional(t.strictArray(t.number, t.literal("Set", "Increment"))),
								JumpPower = t.optional(t.strictArray(t.number, t.literal("Set", "Increment"))),
								AutoRotate = t.optional(t.strictArray(t.boolean, t.literal("Set", "Increment"))),
								JumpHeight = t.optional(t.strictArray(t.number, t.literal("Set", "Increment"))),
							}),
							Priority = t.number,
						})),
						constructorArgs = t.array(t.union(t.any, t.none)),
					})),
					skills = t.map(t.string, t.interface({
						state = t.interface({
							_timerEndTimestamp = t.optional(t.number),
							IsActive = t.boolean,
							Debounce = t.boolean,
							MaxHoldTime = t.optional(t.number),
							StarterParams = t.array(t.union(t.any, t.none)),
						}),
						constructorArguments = t.array(t.union(t.any, t.none)),
					})),
					moveset = t.optional(t.string),
					defaultProps = t.interface({
						WalkSpeed = t.number,
						JumpPower = t.number,
						AutoRotate = t.boolean,
						JumpHeight = t.number,
					}),
				})),
			}),
		}), t.interface({
			type = t.literal("patch"),
			data = t.interface({
				atom = t.optional(t.interface({
					instance = t.optional(t.instanceIsA("Instance")),
					statusEffects = t.optional(t.map(t.string, t.union(t.interface({
						__none = t.literal("__none"),
					}), t.interface({
						className = t.optional(t.string),
						state = t.optional(t.interface({
							_timerEndTimestamp = t.optional(t.number),
							_startTimestamp = t.optional(t.number),
							IsActive = t.optional(t.boolean),
						})),
						endTimestamp = t.optional(t.number),
						humanoidData = t.optional(t.interface({
							Props = t.optional(t.interface({
								WalkSpeed = t.optional(t.map(t.union(t.string, t.number), t.unionList({ t.number, t.interface({
									__none = t.literal("__none"),
								}), t.literal("Set", "Increment") }))),
								JumpPower = t.optional(t.map(t.union(t.string, t.number), t.unionList({ t.number, t.interface({
									__none = t.literal("__none"),
								}), t.literal("Set", "Increment") }))),
								AutoRotate = t.optional(t.map(t.union(t.string, t.number), t.unionList({ t.boolean, t.interface({
									__none = t.literal("__none"),
								}), t.literal("Set", "Increment") }))),
								JumpHeight = t.optional(t.map(t.union(t.string, t.number), t.unionList({ t.number, t.interface({
									__none = t.literal("__none"),
								}), t.literal("Set", "Increment") }))),
							})),
							Priority = t.optional(t.number),
						})),
						constructorArgs = t.optional(t.map(t.union(t.string, t.number), t.union(t.any, t.none))),
					})))),
					skills = t.optional(t.map(t.string, t.union(t.interface({
						__none = t.literal("__none"),
					}), t.interface({
						state = t.optional(t.interface({
							_timerEndTimestamp = t.optional(t.number),
							IsActive = t.optional(t.boolean),
							Debounce = t.optional(t.boolean),
							MaxHoldTime = t.optional(t.number),
							StarterParams = t.optional(t.map(t.union(t.string, t.number), t.union(t.any, t.none))),
						})),
						constructorArguments = t.optional(t.map(t.union(t.string, t.number), t.union(t.any, t.none))),
					})))),
					moveset = t.optional(t.string),
					defaultProps = t.optional(t.interface({
						WalkSpeed = t.optional(t.number),
						JumpPower = t.optional(t.number),
						AutoRotate = t.optional(t.boolean),
						JumpHeight = t.optional(t.number),
					})),
				})),
			}),
		}))) }, nil },
		messageToClient_urel = { { t.interface({
			buffer = t.typeof("buffer"),
			blobs = t.array(t.any),
		}) }, nil },
		damageTaken = { { t.number }, nil },
		damageDealt = { { t.string, t.literal("Skill", "Status"), t.number }, nil },
	},
	incomingUnreliable = {
		messageToClient_urel = true,
	},
	outgoingIds = { "messageToServer", "start", "requestSkill", "messageToServer_urel" },
	outgoingUnreliable = {
		messageToServer_urel = true,
	},
	namespaceIds = {},
	namespaces = {},
})
return {
	GlobalFunctions = GlobalFunctions,
	ServerFunctions = ServerFunctions,
	ClientFunctions = ClientFunctions,
	GlobalEvents = GlobalEvents,
	ServerEvents = ServerEvents,
	ClientEvents = ClientEvents,
}
