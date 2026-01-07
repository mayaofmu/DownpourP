--!nocheck

return {
	["objects"] = {
		[1] = {
			["name"] = "Part",
			["id"] = 1,
			["class"] = "Part",
			["ghosted"] = false,
			["children"] = {
				[1] = {
					["name"] = "ParticleEmitter",
					["id"] = 2,
					["class"] = "ParticleEmitter",
					["ghosted"] = false,
					["children"] = {},
				},
				[2] = {
					["name"] = "Texture1",
					["id"] = 3,
					["class"] = "Beam",
					["ghosted"] = false,
					["children"] = {},
				},
				[3] = {
					["name"] = "Texture2",
					["id"] = 4,
					["class"] = "Beam",
					["ghosted"] = false,
					["children"] = {},
				},
				[4] = {
					["name"] = "Texture3",
					["id"] = 5,
					["class"] = "Beam",
					["ghosted"] = false,
					["children"] = {},
				},
				[5] = {
					["name"] = "rain",
					["id"] = 6,
					["class"] = "Beam",
					["ghosted"] = false,
					["children"] = {},
				},
				[6] = {
					["name"] = "Texture",
					["id"] = 7,
					["class"] = "Beam",
					["ghosted"] = false,
					["children"] = {},
				},
				[7] = {
					["name"] = "Origin",
					["id"] = 8,
					["class"] = "Attachment",
					["ghosted"] = false,
					["children"] = {},
				},
				[8] = {
					["name"] = "End",
					["id"] = 9,
					["class"] = "Attachment",
					["ghosted"] = false,
					["children"] = {
						[1] = {
							["name"] = "ParticleEmitter",
							["id"] = 10,
							["class"] = "ParticleEmitter",
							["ghosted"] = false,
							["children"] = {},
						},
						[2] = {
							["name"] = "Whirl",
							["id"] = 11,
							["class"] = "ParticleEmitter",
							["ghosted"] = false,
							["children"] = {},
						},
					},
				},
			},
		},
	},
	["properties"] = {
		[1] = {
			["Transparency"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["BottomSurface"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.SurfaceType.Smooth, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["CFrame"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = CFrame.new(62, 0.025, -91, 0, 0, -1, 0, 1, 0, 1, 0, 0), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Size"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Vector3.new(4, 0.001, 4), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["TopSurface"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.SurfaceType.Smooth, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[2] = {
			["Color"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.2, 0.2)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.2, 0.2))}), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Drag"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 2, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["ZOffset"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Lifetime"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(0.8299999833106995, 1.5), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(12.774999618530273, 26.423999786376953), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Brightness"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 12, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["FlipbookLayout"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.ParticleFlipbookLayout.Grid4x4, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Size"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.0109376907348633, 0), NumberSequenceKeypoint.new(1, 1.8136205673217773, 0.6794790625572205)}), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Enabled"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = false, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["FlipbookMode"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.ParticleFlipbookMode.OneShot, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Rate"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 42, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Rotation"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(45, 45), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Orientation"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.ParticleOrientation.VelocityParallel, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["SpreadAngle"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Vector2.new(45, 333), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["EmissionDirection"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.NormalId.Right, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["LightEmission"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0.04, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Acceleration"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Vector3.new(0, 18, 0), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Shape"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.ParticleEmitterShape.Disc, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Texture"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = "rbxassetid://17635380117", ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[3] = {
			["Enabled"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = true, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["FaceCamera"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = true, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Color"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.129412, 0.0156863, 0.0156863)), ColorSequenceKeypoint.new(1, Color3.new(0.129412, 0.0156863, 0.0156863))}), ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.129412, 0.0156863, 0.0156863)), ColorSequenceKeypoint.new(1, Color3.new(0.129412, 0.0156863, 0.0156863))}), ["ease"] = "OutLinear", ["time"] = 0.16667,},
					[3] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.121569, 0.121569)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.121569, 0.121569))}), ["ease"] = "OutLinear", ["time"] = 0.28333,},
					[4] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.129412, 0.0156863, 0.0156863)), ColorSequenceKeypoint.new(1, Color3.new(0.129412, 0.0156863, 0.0156863))}), ["ease"] = "OutLinear", ["time"] = 0.38333,},
				},
			},
			["ZOffset"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = -0.01, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Attachment1"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Attachment0"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberSequence.new({NumberSequenceKeypoint.new(0, 0, 0), NumberSequenceKeypoint.new(1, 0, 0)}), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = 14, ["ease"] = "OutLinear", ["time"] = 0.3,},
					[3] = {["value"] = 6, ["ease"] = "OutLinear", ["time"] = 0.56667,},
					[4] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0.68333,},
				},
			},
			["Width1"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = 14, ["ease"] = "OutLinear", ["time"] = 0.3,},
					[3] = {["value"] = 6, ["ease"] = "OutLinear", ["time"] = 0.56667,},
					[4] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0.68333,},
				},
			},
			["TextureLength"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 64, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Brightness"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 12, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["TextureMode"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.TextureMode.Static, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Texture"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = "rbxassetid://133752892201347", ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[4] = {
			["Enabled"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = true, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["FaceCamera"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = true, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Color"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.933333, 0.12549, 0.12549)), ColorSequenceKeypoint.new(1, Color3.new(0.933333, 0.12549, 0.12549))}), ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.933333, 0.12549, 0.12549)), ColorSequenceKeypoint.new(1, Color3.new(0.933333, 0.12549, 0.12549))}), ["ease"] = "OutLinear", ["time"] = 0.06667,},
					[3] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.933333, 0.12549, 0.12549)), ColorSequenceKeypoint.new(1, Color3.new(0.933333, 0.12549, 0.12549))}), ["ease"] = "OutLinear", ["time"] = 0.23333,},
					[4] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(0.933333, 0.12549, 0.12549)), ColorSequenceKeypoint.new(1, Color3.new(0.933333, 0.12549, 0.12549))}), ["ease"] = "OutLinear", ["time"] = 0.61667,},
				},
			},
			["TextureSpeed"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 2, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Attachment1"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Attachment0"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberSequence.new({NumberSequenceKeypoint.new(0, 0, 0), NumberSequenceKeypoint.new(1, 0, 0)}), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = 5, ["ease"] = "OutLinear", ["time"] = 0.33333,},
					[3] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0.58333,},
				},
			},
			["Width1"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = 7, ["ease"] = "OutLinear", ["time"] = 0.33333,},
					[3] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0.58333,},
				},
			},
			["TextureLength"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 32, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Brightness"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 12, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["TextureMode"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.TextureMode.Static, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Texture"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = "rbxassetid://133752892201347", ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[5] = {
			["Enabled"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = true, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["FaceCamera"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = true, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Color"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.406723, 0.406723)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.406723, 0.406723))}), ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.406723, 0.406723)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.406723, 0.406723))}), ["ease"] = "OutLinear", ["time"] = 0.31667,},
					[3] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.406723, 0.406723)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.406723, 0.406723))}), ["ease"] = "OutLinear", ["time"] = 0.9,},
				},
			},
			["TextureSpeed"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 3, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Attachment1"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Attachment0"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5, 0), NumberSequenceKeypoint.new(0.4674185514450073, 0.19374996423721313, 0), NumberSequenceKeypoint.new(1, 0, 0)}), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0.31667,},
					[3] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0.5,},
				},
			},
			["Width1"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0.31667,},
					[3] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0.5,},
				},
			},
			["TextureLength"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 64, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Brightness"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 3, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["TextureMode"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.TextureMode.Static, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Texture"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = "rbxassetid://82386449519032", ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[6] = {
			["Enabled"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = true, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["FaceCamera"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = true, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Color"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.406723, 0.406723)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.406723, 0.406723))}), ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.406723, 0.406723)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.406723, 0.406723))}), ["ease"] = "OutLinear", ["time"] = 0.33333,},
				},
			},
			["TextureSpeed"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 2, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Attachment1"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Attachment0"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5, 0), NumberSequenceKeypoint.new(0.4674185514450073, 0.19374996423721313, 0), NumberSequenceKeypoint.new(1, 0, 0)}), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0.33333,},
					[3] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0.65,},
				},
			},
			["Width1"] = {
				["ghosted"] = true,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0.33333,},
					[3] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0.65,},
				},
			},
			["TextureLength"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 32, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Brightness"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 3, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["TextureMode"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.TextureMode.Static, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Texture"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = "rbxassetid://3339218899", ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[7] = {
			["Enabled"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = false, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["FaceCamera"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = true, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Attachment1"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Color"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.258824, 0.258824)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.258824, 0.258824))}), ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.258824, 0.258824)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.258824, 0.258824))}), ["ease"] = "OutLinear", ["time"] = 0.78333,},
				},
			},
			["TextureSpeed"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 2, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["ZOffset"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0.1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Texture"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = "rbxassetid://81055823203465", ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Attachment0"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberSequence.new({NumberSequenceKeypoint.new(0, 1, 0), NumberSequenceKeypoint.new(0.13727958500385284, 0.5, 0), NumberSequenceKeypoint.new(0.4674185514450073, 0.19374996423721313, 0), NumberSequenceKeypoint.new(1, 0, 0)}), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 16, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width1"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 21, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["LightEmission"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0.45, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Brightness"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 4, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["TextureMode"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.TextureMode.Static, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["TextureLength"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 21, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[8] = {
			["CFrame"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = CFrame.new(0, 18.11087, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[9] = {
			["CFrame"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = CFrame.new(0, 18, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), ["ease"] = "OutLinear", ["time"] = 0,},
					[2] = {["value"] = CFrame.new(0, 0.025, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), ["ease"] = "OutLinear", ["time"] = 0.3,},
				},
			},
		},
		[10] = {
			["Color"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.32549, 0.32549)), ColorSequenceKeypoint.new(0.5934256315231323, Color3.new(1, 0.32549, 0.32549)), ColorSequenceKeypoint.new(1, Color3.new(1, 0, 0))}), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Drag"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 13.69486, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["ZOffset"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0.4, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Lifetime"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(0.27827829122543335, 0.48698705434799194), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(0.27324211597442627, 0.27324211597442627), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Brightness"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 4, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["FlipbookLayout"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.ParticleFlipbookLayout.Grid4x4, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Size"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberSequence.new({NumberSequenceKeypoint.new(0, 8.845682144165039, 0), NumberSequenceKeypoint.new(0.2070239931344986, 11.909133911132812, 3.6670074462890625), NumberSequenceKeypoint.new(1, 17.69199562072754, 5.729205131530762)}), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Enabled"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = false, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["FlipbookMode"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.ParticleFlipbookMode.OneShot, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["RotSpeed"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(1, 1), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["LockedToPart"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = true, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Rate"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 5.57801, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Rotation"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(-360, 360), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Orientation"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.ParticleOrientation.VelocityPerpendicular, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["SpreadAngle"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Vector2.new(3, 3), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Texture"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = "rbxassetid://12844593455", ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[11] = {
			["Color"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.new(1, 0.278431, 0.278431)), ColorSequenceKeypoint.new(1, Color3.new(1, 0.278431, 0.278431))}), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Drag"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 9.52745, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["ZOffset"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0.4, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Lifetime"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(0.20991969108581543, 0.41983938217163086), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(0.24982891976833344, 0.24982891976833344), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Brightness"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 12, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["FlipbookLayout"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.ParticleFlipbookLayout.Grid4x4, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Size"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberSequence.new({NumberSequenceKeypoint.new(0, 4.996580600738525, 0), NumberSequenceKeypoint.new(0.2070239931344986, 6.727004528045654, 2.0713491439819336), NumberSequenceKeypoint.new(1, 9.993526458740234, 3.236205577850342)}), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Enabled"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = false, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["FlipbookMode"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.ParticleFlipbookMode.OneShot, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["RotSpeed"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(76.21963500976562, 295.35125732421875), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["LockedToPart"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = true, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Rate"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 7.14559, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Rotation"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(-360, 360), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Orientation"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Enum.ParticleOrientation.VelocityPerpendicular, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["SpreadAngle"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = Vector2.new(3, 3), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Texture"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = "rbxassetid://10196107097", ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
	},
	["attributes"] = {
		[3] = {
			["EmitDelay"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width1_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 5, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency_Scale_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 5, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["EffectDuration"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(1, 1), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 5, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency_Scale_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width1_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 5, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[4] = {
			["EmitDelay"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width1_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 5, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency_Scale_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 5, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["EffectDuration"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(1, 1), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 5, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency_Scale_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width1_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 5, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[5] = {
			["EmitDelay"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width1_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency_Scale_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["EffectDuration"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(1, 1), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency_Scale_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width1_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[6] = {
			["EmitDelay"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width1_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency_Scale_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["EffectDuration"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(1, 1), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency_Scale_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width1_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 8, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
		[7] = {
			["EmitDelay"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 0, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width1_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 13, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency_Scale_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 13, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Speed_Start"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["EffectDuration"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = NumberRange.new(1, 1), ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width0_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 13, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Transparency_Scale_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 1, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
			["Width1_End"] = {
				["ghosted"] = false,
				["data"] = {
					[1] = {["value"] = 13, ["ease"] = "OutLinear", ["time"] = 0,},
				},
			},
		},
	},
	["tags"] = {},
	["events"] = {},
	["length"] = 1,
	["_version"] = 5,
	["methods"] = {
		[10] = {
			["Emit"] = {
				["ghosted"] = false,
				["data"] = {},
			},
		},
		[2] = {
			["Emit"] = {
				["ghosted"] = false,
				["data"] = {},
			},
		},
		[11] = {
			["Emit"] = {
				["ghosted"] = false,
				["data"] = {},
			},
		},
	},
}