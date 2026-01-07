task.wait(.5)
local star = script.Parent 
star:SetAttribute("TextureShift", true)

for _, texture in pairs(star:GetChildren()) do 
	if texture:IsA("Texture") then 
		task.spawn(function()
			local dt = .01
			while star:GetAttribute("TextureShift") do 
				local speed = star:GetAttribute("Speed")

				texture.OffsetStudsV += speed * dt 
				dt = task.wait() 
			end 
		end)
	end 
end
