-- Services
local TweenService = game:GetService("TweenService")

-------------------------------------------------------------------------------------]

local TweenSequence = {}
TweenSequence.__index = TweenSequence

-- Constructor
function TweenSequence.new(instance: Instance, property: string, tweenInfo: TweenInfo, startSequence, endSequence)
	local self = setmetatable({}, TweenSequence)
	self.instance = instance
	self.property = property
	self.tweenInfo = tweenInfo
	self.startSequence = startSequence
	self.endSequence = endSequence
	self.driver = Instance.new("NumberValue") -- Driver for tweening
	self.driver.Value = 0
	return self
end

-- Interpolates NumberSequence
function TweenSequence:LerpNumberSequence(alpha: number)
	local keypoints = {}
	local maxCount = math.max(#self.startSequence.Keypoints, #self.endSequence.Keypoints)

	for i = 1, maxCount do
		local startKeypoint = self.startSequence.Keypoints[i]
		local endKeypoint = self.endSequence.Keypoints[i]

		local sequenceTime = 0
		local startValue = 0
		local startEnvelope = 0
		local endValue = 0
		local endEnvelope = 0

		if startKeypoint then
			sequenceTime = math.clamp(startKeypoint.Time,0,1)
			startValue = startKeypoint.Value
			startEnvelope = startKeypoint.Envelope
		end

		if endKeypoint then
			sequenceTime = math.clamp(endKeypoint.Time,0,1) -- Use the end keypoint's sequenceTime if available
			endValue = endKeypoint.Value
			endEnvelope = endKeypoint.Envelope
		end

		local value = startValue + (endValue - startValue) * alpha
		local envelope = startEnvelope + (endEnvelope - startEnvelope) * alpha

		table.insert(keypoints, NumberSequenceKeypoint.new(sequenceTime, value, envelope))
	end

	return NumberSequence.new(keypoints)
end

-- Interpolates ColorSequence
function TweenSequence:LerpColorSequence(alpha: number)
	local keypoints = {}
	local maxCount = math.max(#self.startSequence.Keypoints, #self.endSequence.Keypoints)

	for i = 1, maxCount do
		local startKeypoint = self.startSequence.Keypoints[i]
		local endKeypoint = self.endSequence.Keypoints[i]

		local sequenceTime = 0
		local startColor = Color3.new(0, 0, 0)
		local endColor = Color3.new(0, 0, 0)

		if startKeypoint then
			sequenceTime = math.clamp(startKeypoint.Time,0,1)
			startColor = startKeypoint.Value
		end

		if endKeypoint then
			sequenceTime = math.clamp(endKeypoint.Time,0,1) -- Use the end keypoint's sequenceTime if available
			endColor = endKeypoint.Value
		end

		local color = Color3.new(
			math.round(startColor.R + (endColor.R - startColor.R) * alpha),
			math.round(startColor.G + (endColor.G - startColor.G) * alpha),
			math.round(startColor.B + (endColor.B - startColor.B) * alpha)
		)

		table.insert(keypoints, ColorSequenceKeypoint.new(sequenceTime, color))
	end

	return ColorSequence.new(keypoints)
end

-- Play function to tween
function TweenSequence:Play()
	local tween = TweenService:Create(self.driver, self.tweenInfo, { Value = 1 })

	self.driver.Changed:Connect(function(newValue)
		local currentSequence
		if typeof(self.startSequence) == "NumberSequence" then
			currentSequence = self:LerpNumberSequence(newValue)
		elseif typeof(self.startSequence) == "ColorSequence" then
			currentSequence = self:LerpColorSequence(newValue)
		end

		self.instance[self.property] = currentSequence
	end)

	tween:Play()
	tween.Completed:Connect(function()
		self.driver:Destroy() -- Clean up after tween completes
	end)

	return tween
end

return TweenSequence
