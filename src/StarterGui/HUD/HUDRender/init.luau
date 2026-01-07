local HUD = {} 



function HUD:Init()
    self.Stats = require(script.Stats).new()
    self.Inventory = require(script.Inventory).new()
    self.Crosshair = require(script.Crosshair).new()
    self.Difficulty = require(script.Difficulty).new()


    return self
end

 
return HUD       