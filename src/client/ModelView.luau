--!strict
-- Shows a model in a ViewportFrame with a three-quarter camera (used by the inventory,
-- the index and the hatch screen). Models face -Z with the pivot at their feet.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AssetLibrary"))

local ModelView = {}

-- Frames the camera on the model. metaName ("Alien_Blip", "Egg_Rare") gives exact bounds
-- for Blender models; placeholders use their bounding box.
function ModelView.frame(viewport: ViewportFrame, model: Model, metaName: string?, zoom: number?)
	local camera = viewport.CurrentCamera
	if not camera then
		local c = Instance.new("Camera")
		c.FieldOfView = 30
		c.Parent = viewport
		viewport.CurrentCamera = c
		camera = c
	end
	local meta = metaName and AssetLibrary.meta(metaName)
	local minY, maxY, width = 0, 2, 2
	if meta then
		local scale = model:GetScale()
		local lo, hi = meta.bounds.min, meta.bounds.max
		minY, maxY = lo.Y * scale, hi.Y * scale
		width = math.max(hi.X - lo.X, hi.Z - lo.Z) * scale
	else
		local _, size = model:GetBoundingBox()
		maxY, width = size.Y, math.max(size.X, size.Z)
	end
	local height = maxY - minY
	local center = Vector3.new(0, (minY + maxY) / 2, 0)
	local distance = (math.max(height, width) * 2.4 + 1) / (zoom or 1)
	local eye = center + Vector3.new(distance * 0.42, height * 0.35, -distance * 0.9)
	;(camera :: Camera).CFrame = CFrame.lookAt(eye, center)
end

-- Clears a viewport and shows a new model in it. Returns the model.
function ModelView.show(viewport: ViewportFrame, model: Model, metaName: string?, zoom: number?): Model
	for _, child in viewport:GetChildren() do
		if not child:IsA("Camera") then
			child:Destroy()
		end
	end
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	ModelView.frame(viewport, model, metaName, zoom)
	return model
end

return ModelView
