-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
--/ <reference types="@rbxts/testez/globals" />
local CreateClient = TS.import(script, script.Parent.Parent, "exports").CreateClient
return function()
	describe("client", function()
		it("should not be instantiated on server side", function()
			expect(CreateClient).to:throw()
		end)
	end)
end
