local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TagSystem = {}

local HOVER_TAG = "Hover"
local ROTATE_TAG = "Rotate"

local activeObjects = {}


function TagSystem.Start()
	RunService.Heartbeat:Connect(function()
		for instance, _ in activeObjects do
			if not instance.Parent then
				activeObjects[instance] = nil
				continue
			end
			updateObject(instance)
		end
	end)
	
	local function onTagAdded(instance)
		if not (instance:IsA("Model") or instance:IsA("BasePart")) then return end
		if not activeObjects[instance] then
			activeObjects[instance] = {
				BaseCFrame = getBaseCFrame(instance)
			}
		end
	end
	
	local function onTagRemoved(instance)
		if not CollectionService:HasTag(instance, HOVER_TAG) and not CollectionService:HasTag(instance, ROTATE_TAG) then
			activeObjects[instance] = nil
		end
	end
	

end

return TagSystem
