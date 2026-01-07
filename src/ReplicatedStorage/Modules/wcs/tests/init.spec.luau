-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
--/ <reference types="@rbxts/testez/globals" />
local Workspace = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "services").Workspace
local CreateServer = TS.import(script, script.Parent.Parent, "exports").CreateServer
return function()
	local server
	describe("server", function()
		it("should create a server", function()
			server = CreateServer()
			expect(server).to.be.ok()
		end)
		it("should register directories", function()
			server:RegisterDirectory(Workspace)
		end)
		it("should run the server", function()
			server:Start()
		end)
		it("should be active", function()
			expect(server:IsActive()).equal(true)
		end)
		it("should be a singleton", function()
			expect(server).equal(CreateServer())
		end)
	end)
end
