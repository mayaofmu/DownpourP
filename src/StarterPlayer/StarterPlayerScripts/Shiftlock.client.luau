
local Players = game:GetService("Players")
local Player = Players.LocalPlayer



local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShiftUnlockedModule = require(ReplicatedStorage.Modules.ShiftUnlocked)
local CameraService = require(ReplicatedStorage.Core.CameraService)

-- Create camera object
local ShiftUnlockedCamera = ShiftUnlockedModule.new()

-- Configure camera settings
ShiftUnlockedCamera.MinZoom = 14
ShiftUnlockedCamera.MaxZoom = 35 
ShiftUnlockedCamera.CameraOffset = Vector3.new(2.7, 3.3, 0) -- Adjusted Z to be closer for RoR2 feel
ShiftUnlockedCamera.LockedIcon = "rbxassetid://113309236647209"
ShiftUnlockedCamera.RotateCharacter = true -- RoR2 style: character faces reticle
 
ShiftUnlockedCamera:SetEnabled(true)

-- Register camera with CameraService so other scripts can access it
CameraService.Register(ShiftUnlockedCamera) 






