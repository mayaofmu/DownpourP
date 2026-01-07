local CameraService = {}
local activeCamera = nil
local TweenService = game:GetService("TweenService")

function CameraService.Register(camera)
	activeCamera = camera
end

function CameraService.Get()
	return activeCamera
end

function CameraService.SetFOV(fov, duration)
	duration = duration or 0.3
	local target = activeCamera or workspace.CurrentCamera
	
	if not target then return end

	if typeof(target) == "Instance" then
		local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(target, tweenInfo, {FieldOfView = fov})
		tween:Play()
	elseif type(target) == "table" and target.FOV ~= nil then
		-- For custom camera tables (like ShiftUnlocked)
		local numberValue = Instance.new("NumberValue")
		numberValue.Value = target.FOV
		
		local connection
		connection = numberValue.Changed:Connect(function(val)
			target.FOV = val
		end)
		
		local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(numberValue, tweenInfo, {Value = fov})
		
		tween.Completed:Connect(function()
			connection:Disconnect()
			numberValue:Destroy()
		end)
		
		tween:Play()
	end
end

return CameraService
