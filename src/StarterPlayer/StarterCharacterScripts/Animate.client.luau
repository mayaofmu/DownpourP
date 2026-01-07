-- [[ SERVICES ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- [[ MODULES ]]
local WCS = require(ReplicatedStorage.Modules.wcs)

-- [[ VARIABLES ]]
local _Player = Players.LocalPlayer
local Character = script.Parent
local Humanoid = Character:WaitForChild("Humanoid")

-- Standard R15 fallback animations
local DEFAULT_ANIMATIONS = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
	Jump = "rbxassetid://507765000",
	Fall = "rbxassetid://507767968",
}

local currentTracks = {}
local activeMoveset = ""
local wcsChar = nil
local currentState = "Idle"

-- [[ FUNCTIONS ]]

local function stopAllTracks()
	for _, track in pairs(currentTracks) do
		track:Stop(0.1)
	end
end

local function loadAnimations(movesetName)
	stopAllTracks()
	currentTracks = {}
	
	local animFolder = nil
	if movesetName and movesetName ~= "" then
		-- Search in ReplicatedStorage.Core.Classes[MovesetName].Animations
		local movesetPath = ReplicatedStorage.Core.Classes:FindFirstChild(movesetName)
		if movesetPath then
			animFolder = movesetPath:FindFirstChild("Animations")
		end
	end
	
	for animName, defaultId in pairs(DEFAULT_ANIMATIONS) do
		local anim = animFolder and animFolder:FindFirstChild(animName)
		local animationObject
		
		if anim and anim:IsA("Animation") then
			animationObject = anim
		else
			animationObject = Instance.new("Animation")
			animationObject.AnimationId = defaultId
		end
		
		local track = Humanoid:LoadAnimation(animationObject)
		-- Set priorities
		if animName == "Idle" then
			track.Priority = Enum.AnimationPriority.Idle
		elseif animName == "Walk" or animName == "Run" then
			track.Priority = Enum.AnimationPriority.Movement
		else
			track.Priority = Enum.AnimationPriority.Action
		end
		
		currentTracks[animName] = track
	end
	
	-- Re-play current state
	if currentTracks[currentState] then
		currentTracks[currentState]:Play(0.1)
	end
end

local function updateState()
	local moveDir = Humanoid.MoveDirection
	local newState = "Idle"
	
	local humanoidState = Humanoid:GetState()
	
	if humanoidState == Enum.HumanoidStateType.Freefall then
		newState = "Fall"
	elseif humanoidState == Enum.HumanoidStateType.Jumping then
		newState = "Jump"
	elseif moveDir.Magnitude > 0 then
		-- Determine if Run or Walk based on speed
		if Humanoid.WalkSpeed > 18 then
			newState = "Run"
		else
			newState = "Walk"
		end
	end
	
	if newState ~= currentState then
		local oldTrack = currentTracks[currentState]
		if oldTrack then 
			oldTrack:Stop(0.2) 
		end
		
		currentState = newState
		local newTrack = currentTracks[currentState]
		if newTrack then
			newTrack:Play(0.2)
		end
	end
end

-- [[ WCS SETUP ]]

local function onWCSInit(char)
	wcsChar = char
	activeMoveset = wcsChar:GetMovesetName()
	loadAnimations(activeMoveset)
	
	wcsChar.MovesetChanged:Connect(function(new)
		activeMoveset = new
		loadAnimations(activeMoveset)
	end)
end

-- Try to get character immediately
local localWCS = WCS.Character.GetLocalCharacter()
if localWCS then
	onWCSInit(localWCS)
else
	WCS.Character.CharacterCreated:Connect(function(char)
		if char.Instance == Character then
			onWCSInit(char)
		end
	end)
end

-- [[ HEARTBEAT ]]
RunService.PostSimulation:Connect(updateState)

-- Cleanup default Roblox Animate script if it exists
local defaultAnimate = Character:FindFirstChild("Animate")
if defaultAnimate and defaultAnimate ~= script then
	defaultAnimate:Destroy()
end
