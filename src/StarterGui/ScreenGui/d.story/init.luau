local controls = {
	Visible = true,
}

local story = {
	controls = {Visible = true},
	render = function(props)

		local baseHoldingFrame = Instance.new("Frame")
		baseHoldingFrame.Size = UDim2.fromScale(1.6, .9)
		baseHoldingFrame.Position = UDim2.fromOffset(.5, .5)
		baseHoldingFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
		baseHoldingFrame.Parent = props.target
		baseHoldingFrame.AnchorPoint = Vector2.new(.5, .5)
		baseHoldingFrame.Visible = true 
		local unsubscribe = props.subscribe(function(values, infos) --
			local info = infos.Visible -- This will be a GenericInfo<boolean>

			if (info.__new ~= info.__old) then
				baseHoldingFrame.Visible = info.__new
			end
		end)

		local Loadout = script.Parent.Loadout:Clone() 

		local tabs = script.Parent.Tabs:Clone()

		local Teams = script.Parent.Teams:Clone() 

		Loadout.Parent = baseHoldingFrame
		tabs.Parent = baseHoldingFrame 
		Teams.Parent = baseHoldingFrame




		return function() -- Cleanup your story haere
			baseHoldingFrame:Destroy()
		end
	end
}

return story 