local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local HOVER_TAG = "Hover"
local ROTATE_TAG = "Rotate"

local activeObjects = {}

local function getBaseCFrame(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	elseif instance:IsA("BasePart") then
		return instance.CFrame
	end
	return nil
end

local function setCFrame(instance, cframe)
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cframe
	end
end

local function updateObject(instance)
	local data = activeObjects[instance]
	if not data then return end
	
	local cframe = data.BaseCFrame
	local t = os.clock()
	
	if CollectionService:HasTag(instance, HOVER_TAG) then
		cframe = cframe * CFrame.new(0, math.sin(t * 2) * 2, 0)
	end
	
	if CollectionService:HasTag(instance, ROTATE_TAG) then
		cframe = cframe * CFrame.Angles(0, t * 2, 0)
	end
	
	setCFrame(instance, cframe)
end

RunService.RenderStepped:Connect(function()
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

CollectionService:GetInstanceAddedSignal(HOVER_TAG):Connect(onTagAdded)
CollectionService:GetInstanceAddedSignal(ROTATE_TAG):Connect(onTagAdded)
CollectionService:GetInstanceRemovedSignal(HOVER_TAG):Connect(onTagRemoved)
CollectionService:GetInstanceRemovedSignal(ROTATE_TAG):Connect(onTagRemoved)

for _, instance in CollectionService:GetTagged(HOVER_TAG) do onTagAdded(instance) end
for _, instance in CollectionService:GetTagged(ROTATE_TAG) do onTagAdded(instance) end

a