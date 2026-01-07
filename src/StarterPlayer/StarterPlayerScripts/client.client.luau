--!strict
--[[
	Client Controller
	Manages client-side combat, movement, and input handling
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local _TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer                                                                                

local WCS = require(ReplicatedStorage.Modules.wcs)
local CameraService = require(ReplicatedStorage.Core.CameraService)

-- Constants
local DEFAULT_FOV = 70
local SPRINT_FOV = 80
local STATIONARY_THRESHOLD = 0.1 -- Lowered for responsiveness
local RAYCAST_DISTANCE = 1000
local RAYCAST_OFFSET = 10 -- Skip player's character

-- Initialize WCS
local Client = WCS.CreateClient()
Client:RegisterDirectory(ReplicatedStorage.Core.Classes)
require(ReplicatedStorage.Core.StatusEffects)
Client:Start()


-- State Management
local InputState = {
	isFiring = false,
	isSprintKeyHeld = false,
}

local SprintState = {
	isActive = false,
	stationaryTime = 0,
}

-- Prevent hammering the server with skill start requests
local lastSkillStartTimes = {}
local SKILL_RETRY_DELAY = 0.2 -- Seconds to wait before retrying a skill start if server hasn't responded

-- Mouse Targeting Utility
local function getMouseWorldPosition(): Vector3
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero
	end
	
	local mouseLocation = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	
	-- Offset origin to skip player's character and accessories
	local rayOrigin = unitRay.Origin + (unitRay.Direction * RAYCAST_OFFSET)
	local rayDirection = unitRay.Direction * RAYCAST_DISTANCE
	
	-- Setup raycast filter
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local filterList = { camera }
	
	if Player.Character then
		table.insert(filterList, Player.Character)
	end
	
	local projectilesFolder = workspace:FindFirstChild("Projectiles")
	if projectilesFolder then
		table.insert(filterList, projectilesFolder)
	end
	
	raycastParams.FilterDescendantsInstances = filterList
	
	-- Perform raycast
	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	return result and result.Position or (rayOrigin + rayDirection)
end

-- Sprint Management
local function getLocalCharacter()
	return WCS.Character.GetLocalCharacter()
end

local function stopSprint()
	local char = getLocalCharacter()
	if not char then return end
	
	local sprintSkill = char:GetSkillFromString("Sprint")
	if not sprintSkill then return end
	
	local state = sprintSkill:GetState()
	if state and state.IsActive then
		sprintSkill:Stop()
		SprintState.isActive = false
		
		-- Reset FOV through CameraService with tween
		CameraService.SetFOV(DEFAULT_FOV, 0.4)
	end
end

local function startSprint()
	local char = getLocalCharacter()
	if not char then return end
	
	local sprintSkill = char:GetSkillFromString("Sprint")
	if not sprintSkill then return end
	
	SprintState.stationaryTime = 0
	sprintSkill:Start()
	SprintState.isActive = true
	
	-- Increase FOV through CameraService with tween
	CameraService.SetFOV(SPRINT_FOV, 0.4)
end

-- Combat System
local function handleCombatInput()
	if not InputState.isFiring then return end
	
	local char = getLocalCharacter()
	if not char then return end
	
	-- Get camera look direction (flattened)
	local camera = workspace.CurrentCamera
	local lookDirection = camera.CFrame.LookVector
	local flatDirection = Vector3.new(lookDirection.X, 0, lookDirection.Z)
	
	if flatDirection.Magnitude > 0 then
		lookDirection = flatDirection.Unit
	else
		-- Fallback if looking straight up or down
		lookDirection = Vector3.new(camera.CFrame.RightVector.Z, 0, -camera.CFrame.RightVector.X).Unit
	end

	-- Try melee combat first
	local glaiveSkill = char:GetSkillFromString("GlaiveCombat")
	if glaiveSkill then
		local now = tick()
		local glaiveState = glaiveSkill:GetState()
		local lastStart = lastSkillStartTimes["GlaiveCombat"] or 0
		
		local isAvailable = not (glaiveState and (glaiveState.Debounce or glaiveState.IsActive))
		if isAvailable then
			if (now - lastStart > SKILL_RETRY_DELAY) then
				lastSkillStartTimes["GlaiveCombat"] = now
				glaiveSkill:Start(lookDirection)
			end
			return -- Melee is either starting or already active/pending, so don't fall back to ranged yet
		end
	end
	
	-- Fallback to ranged combat
	local fireboltSkill = char:GetSkillFromString("FireBolt")
	if fireboltSkill then
		local now = tick()
		local fireboltState = fireboltSkill:GetState()
		local lastStart = lastSkillStartTimes["FireBolt"] or 0
		
		local isAvailable = not (fireboltState and (fireboltState.Debounce or fireboltState.IsActive))
		if isAvailable then
			if (now - lastStart > SKILL_RETRY_DELAY) then
				local hrp = char.Instance:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					local targetPosition = getMouseWorldPosition()
					lastSkillStartTimes["FireBolt"] = now
					fireboltSkill:Start(hrp.Position, targetPosition)
				end
			end
		end
	end
end

-- Sprint State Logic
local function updateSprintState(deltaTime: number)
	local char = getLocalCharacter()
	if not char then return end
	
	local humanoid = char.Humanoid
	if not humanoid then return end
	
	local isMoving = humanoid.MoveDirection.Magnitude > 0
	
	-- If key is held and we are moving, and NOT already sprinting -> Start
	if InputState.isSprintKeyHeld and isMoving and not SprintState.isActive and not InputState.isFiring then
		startSprint()
	end
	
	-- If sprinting but stopped moving or firing -> Stop
	if SprintState.isActive then
		if not isMoving then
			SprintState.stationaryTime += deltaTime
			if SprintState.stationaryTime >= STATIONARY_THRESHOLD then
				stopSprint()
			end
		else
			SprintState.stationaryTime = 0
		end
		
		if InputState.isFiring then
			stopSprint()
		end
	end
end

-- Input Handlers
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	
	-- Combat Input
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		InputState.isFiring = true
		handleCombatInput()
	end
	
	-- Sprint Key (Hold to run)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		InputState.isSprintKeyHeld = true
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	-- Combat Inputd
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		InputState.isFiring = false
	end
	
	-- Sprint Key
	if input.KeyCode == Enum.KeyCode.LeftShift then
		InputState.isSprintKeyHeld = false
		stopSprint()
	end
end)

-- Character Event Handlers
local function onCharacterCreated(char: any)
	if char.Instance ~= Player.Character then return end
	
	-- Stop sprint when taking damage
	char.DamageTaken:Connect(function(_damage: any)
		stopSprint()
	end)
end

-- Connect to character events
WCS.Character.CharacterCreated:Connect(onCharacterCreated)

-- Handle existing character
local currentCharacter = getLocalCharacter()
if currentCharacter then
	onCharacterCreated(currentCharacter)
end

-- Main Update Loop
RunService.Heartbeat:Connect(function(deltaTime: number)
	handleCombatInput()
	updateSprintState(deltaTime)
end)
