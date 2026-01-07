local Tween = game:GetService("TweenService")
local module = {} 


local Camera = workspace.CurrentCamera

local snapAnim = game.ReplicatedStorage.StarFall.Animations.Snap
local impactAnim = game.ReplicatedStorage.StarFall.Animations.Impact

module.Throw = function(character, position, unit)      
	local star = workspace.StarMesh:Clone()
	star.Parent = Camera 

	local characterHumanoidRootPart = character:WaitForChild("HumanoidRootPart")


	if not characterHumanoidRootPart then 
		return 
	end 


	local lookingAtPosition = CFrame.new(characterHumanoidRootPart.Position, position).LookVector * Vector3.new(1, 0, 1)

	local distanceBetweenPosition = (characterHumanoidRootPart.Position - position).magnitude

	local starDescendPoint = characterHumanoidRootPart.Position + (lookingAtPosition * distanceBetweenPosition*3) + Vector3.new(0,13 + distanceBetweenPosition/1.6, 0)


	star:SetAttribute("Flying", true)



	local snapAnimation = character.Humanoid:LoadAnimation(snapAnim)
	local impactAnimation = unit.Humanoid:LoadAnimation(impactAnim)


	local started = os.clock() 


	snapAnimation:Play()

	task.spawn(function()
		while star:GetAttribute("Flying") do

			local timeElapsed = (os.clock() - started) -- elapsed time

			star.CFrame = CFrame.new(star.Position, position) * CFrame.Angles( math.rad(90 + timeElapsed * -124), math.rad(-90), math.rad((435 - timeElapsed * 214)*timeElapsed))
			task.wait() 
		end
		impactAnimation:Play() 
	end) 

	star.Position = starDescendPoint
	star.CFrame = CFrame.new(star.Position, position) * CFrame.Angles(math.rad(1), math.rad(90), 0)


	local fallingStar = Tween:Create(star, TweenInfo.new(.9, Enum.EasingStyle.Sine), {Position = position})


	fallingStar.Completed:Connect(function()    
		star:SetAttribute("Flying", false)

		for _, particleEmitter in pairs(star:GetDescendants()) do 
			if particleEmitter:IsA("ParticleEmitter") then  
				particleEmitter.Enabled = false
			end
		end

		for _, texture in pairs(star:GetChildren()) do 
			if texture:IsA("Texture") then 
				local fadeTexture = Tween:Create(texture, TweenInfo.new(.1), {Transparency = 1})
				fadeTexture:Play() 
			end
		end

		local fadeStar = Tween:Create(star, TweenInfo.new(.1), {Transparency = 1})
		fadeStar:Play() 
	end)

	fallingStar:Play()


	task.delay(1.5, function() 

		unit.HumanoidRootPart.CFrame = CFrame.new(position)

		star:Destroy() 
	end)
end

module.Throw(workspace.Thrower, workspace.SummonPosition.Position, workspace.GokuSSJG)

return module 