--!strict
-- Placeholder alien models built from parts (used on bases, as followers and in the
-- hatch reveal). Swap this module for real models later; callers only use build().
local Aliens = require(script.Parent.Config.Aliens)
local Eggs = require(script.Parent.Config.Eggs)

local AlienModel = {}

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- Returns an anchored Model whose PrimaryPart ("Body") sits with its bottom at the pivot.
function AlienModel.build(alienId: string, mutation: string?): Model
	local def = Aliens.ById[alienId] or Aliens.List[1]
	local rarity = Eggs.ByName[def.Rarity]
	local mutationDef = mutation and Eggs.MutationByName[mutation]
	local size = def.Size
	local color = if mutationDef then def.Color:Lerp(mutationDef.Color, 0.6) else def.Color

	local model = Instance.new("Model")
	model.Name = def.Id

	local body = part("Body", Vector3.new(size, size, size), color, if mutationDef then Enum.Material.Neon else nil)
	body.Shape = Enum.PartType.Ball
	body.CFrame = CFrame.new(0, size / 2, 0)
	body.PivotOffset = CFrame.new(0, -size / 2, 0) -- pivot at the feet
	body.Parent = model
	model.PrimaryPart = body

	for _, side in { -1, 1 } do
		local eye = part("Eye", Vector3.new(size * 0.28, size * 0.28, size * 0.28), Color3.new(1, 1, 1))
		eye.Shape = Enum.PartType.Ball
		eye.CFrame = body.CFrame * CFrame.new(side * size * 0.2, size * 0.12, -size * 0.4)
		eye.Parent = model
		local pupil = part("Pupil", Vector3.new(size * 0.14, size * 0.14, size * 0.14), Color3.fromRGB(20, 20, 30))
		pupil.Shape = Enum.PartType.Ball
		pupil.CFrame = eye.CFrame * CFrame.new(0, 0, -size * 0.1)
		pupil.Parent = model
	end

	local antenna = part("Antenna", Vector3.new(0.15, size * 0.45, 0.15), color:Lerp(Color3.new(0, 0, 0), 0.3))
	antenna.CFrame = body.CFrame * CFrame.new(0, size * 0.65, 0)
	antenna.Parent = model
	local tip = part("Tip", Vector3.new(size * 0.18, size * 0.18, size * 0.18), rarity.Color, Enum.Material.Neon)
	tip.Shape = Enum.PartType.Ball
	tip.CFrame = antenna.CFrame * CFrame.new(0, size * 0.25, 0)
	tip.Parent = model

	-- Rarity ring under the alien (GAME_PLAN §8 color rings).
	local ring = part("Ring", Vector3.new(0.15, size * 1.3, size * 1.3), rarity.Color, Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.3
	ring.Parent = model

	model:SetAttribute("AlienId", def.Id)
	model:SetAttribute("Rarity", def.Rarity)
	if mutation then
		model:SetAttribute("Mutation", mutation)
	end
	return model
end

-- Display name including mutation, e.g. "Golden Zorblax".
function AlienModel.displayName(alienId: string, mutation: string?): string
	local def = Aliens.ById[alienId]
	local name = if def then def.Name else alienId
	local mutationDef = mutation and Eggs.MutationByName[mutation]
	return if mutationDef then mutationDef.Label .. " " .. name else name
end

return AlienModel
