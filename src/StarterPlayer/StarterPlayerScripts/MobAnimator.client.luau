-- [[ SERVICES ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- [[ MODULES ]]
local WCS = require(ReplicatedStorage.Modules.wcs)

-- [[ VARIABLES ]]
local _LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Standard R15 fallback animations
local DEFAULT_ANIMATIONS = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
	Jump = "rbxassetid://507765000",
	Fall = "rbxassetid://507767968",
}

local ANIMATION_DISTANCE = 250 -- Only animate mobs within this range

-- [[ DATA STRUCTURES ]]
local mobCache = {} -- [MobInstance] -> { wcsChar, currentTracks, currentState, currentMoveset }

-- [[ FUNCTIONS ]]

local function stopAllTracks(mobData)
	for _, track in pairs(mobData.currentTracks or {}) do
		track:Stop(0.1)
	end
end

local function loadMobAnimations(mobInstance, mobData)
	stopAllTracks(mobData)
	mobData.currentTracks = {}
	
	local movesetName = mobData.currentMoveset
	local animFolder = nil
	
	if movesetName and movesetName ~= "" then
		-- Search in ReplicatedStorage.Core.Classes.Mob.Movesets[MovesetName].Animations
		local movesetPath = ReplicatedStorage.Core.Classes.Mob.Movesets:FindFirstChild(movesetName)
		if movesetPath then
			animFolder = movesetPath:FindFirstChild("Animations")
		end
	end
	
	local humanoid = mobInstance:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	for animName, defaultId in pairs(DEFAULT_ANIMATIONS) do
		local anim = animFolder and animFolder:FindFirstChild(animName)
		local animationObject
		
		if anim and anim:IsA("Animation") then
			animationObject = anim
		else
			animationObject = Instance.new("Animation")
			animationObject.AnimationId = defaultId
		end
		
		local track = humanoid:LoadAnimation(animationObject)
		-- Set priorities
		if animName == "Idle" then
			track.Priority = Enum.AnimationPriority.Idle
		elseif animName == "Walk" or animName == "Run" then
			track.Priority = Enum.AnimationPriority.Movement
		else
			track.Priority = Enum.AnimationPriority.Action
		end
		
		mobData.currentTracks[animName] = track
	end
	
	-- Re-play current state
	local state = mobData.currentState or "Idle"
	if mobData.currentTracks[state] then
		mobData.currentTracks[state]:Play(0.1)
	end
end

local function updateMobState(mobInstance, mobData)
	local humanoid = mobInstance:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	local moveDir = humanoid.MoveDirection
	local newState = "Idle"
	
	local humanoidState = humanoid:GetState()
	
	if humanoidState == Enum.HumanoidStateType.Freefall then
		newState = "Fall"
	elseif humanoidState == Enum.HumanoidStateType.Jumping then
		newState = "Jump"
	elseif moveDir.Magnitude > 0 then
		-- Determine if Run or Walk based on speed
		if humanoid.WalkSpeed > 18 then
			newState = "Run"
		else
			newState = "Walk"
		end
	end
	
	if newState ~= mobData.currentState then
		local oldTrack = mobData.currentTracks[mobData.currentState]
		if oldTrack then 
			oldTrack:Stop(0.2) 
		end
		
		mobData.currentState = newState
		local newTrack = mobData.currentTracks[mobData.currentState]
		if newTrack then
			newTrack:Play(0.2)
		end
	end
end

local function onMobCreated(mobInstance)
	if not mobInstance:IsDescendantOf(workspace) then return end
	
	-- Wait for WCS Character
	local wcsChar = WCS.Character.GetCharacterFromInstance(mobInstance)
	if not wcsChar then
		-- Wait for it
		WCS.Character.CharacterCreated:Connect(function(char)
			if char.Instance == mobInstance then
				onMobCreated(mobInstance)
			end
		end)
		return
	end
	
	local mobData = {
		wcsChar = wcsChar,
		currentTracks = {},
		currentState = "Idle",
		currentMoveset = wcsChar:GetMovesetName(),
	}
	
	mobCache[mobInstance] = mobData
	loadMobAnimations(mobInstance, mobData)
	
	wcsChar.MovesetChanged:Connect(function(new)
		mobData.currentMoveset = new
		loadMobAnimations(mobInstance, mobData)
	end)
end

-- [[ TICK LOOP ]]
RunService.PostSimulation:Connect(function()
	local camPos = Camera.CFrame.Position
	
	for mobInstance, mobData in pairs(mobCache) do
		if not mobInstance or not mobInstance.Parent then
			mobCache[mobInstance] = nil
			continue
		end
		
		local hrp = mobInstance:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end
		
		local dist = (hrp.Position - camPos).Magnitude
		if dist < ANIMATION_DISTANCE then
			updateMobState(mobInstance, mobData)
		else
			-- Stop animations if too far (optional optimization)
			stopAllTracks(mobData)
			mobData.currentState = "" -- Signal to resume when close
		end
	end
end)

-- Initialize existing mobs if any
for _, child in ipairs(workspace:WaitForChild("Mobs"):GetChildren()) do
	if child:IsA("Model") then
		onMobCreated(child)
	end
end

-- Watch for new mobs
workspace:WaitForChild("Mobs").ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		onMobCreated(child)
	end
end)
