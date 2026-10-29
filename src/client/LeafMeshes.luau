--!strict
-- The 3D leaf meshes (Leaf_Maple, Leaf_Oak, Leaf_Birch, Leaf_Seaweed, Leaf_Paper,
-- Leaf_Snow from art/blender/litter.py). They're untextured, so each leaf gets its colour
-- from the zone's palette. Parts are pooled: take() hands out a ready MeshPart, give()
-- puts it back. Until the models have loaded, ready() is false and callers use the flat
-- leaf images instead.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Grid = require(Shared.Grid)

local LeafMeshes = {}

export type Look = { kinds: { string }, colors: { Color3 } }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- What lies on the ground in each kind of zone.
local LOOKS: { [string]: Look } = {
	Autumn = {
		kinds = { "Leaf_Maple", "Leaf_Maple", "Leaf_Oak", "Leaf_Birch" },
		colors = { rgb(236, 118, 38), rgb(214, 66, 40), rgb(244, 186, 52), rgb(170, 98, 44), rgb(228, 148, 40), rgb(196, 52, 36) },
	},
	Park = {
		kinds = { "Leaf_Oak", "Leaf_Birch", "Leaf_Maple" },
		colors = { rgb(112, 176, 62), rgb(150, 196, 70), rgb(196, 204, 70), rgb(232, 182, 52), rgb(92, 150, 58) },
	},
	Seaweed = {
		kinds = { "Leaf_Seaweed" },
		colors = { rgb(58, 140, 82), rgb(40, 112, 92), rgb(104, 162, 62), rgb(132, 120, 52) },
	},
	Paper = {
		kinds = { "Leaf_Paper", "Leaf_Paper", "Leaf_Maple" },
		colors = { rgb(246, 246, 240), rgb(232, 226, 210), rgb(212, 226, 242), rgb(244, 232, 160) },
	},
	Snow = {
		kinds = { "Leaf_Snow" },
		colors = { rgb(246, 250, 255), rgb(226, 236, 250), rgb(236, 244, 255) },
	},
}
LeafMeshes.Gold = rgb(255, 206, 60)

local templates: { [string]: BasePart } = {}
local pools: { [string]: { BasePart } } = {}

-- The look for a ground image list (Zone.Ground).
function LeafMeshes.lookFor(ground: { string }?): Look
	local first = ground and ground[1] or ""
	if string.find(first, "Snow") then
		return LOOKS.Snow
	elseif string.find(first, "Seaweed") then
		return LOOKS.Seaweed
	elseif string.find(first, "Paper") then
		return LOOKS.Paper
	elseif string.find(first, "Park") then
		return LOOKS.Park
	end
	return LOOKS.Autumn
end

-- The look for a tile.
function LeafMeshes.lookOf(id: number): Look
	local zg = Grid.zoneGridOfId(id)
	return LeafMeshes.lookFor(zg and zg.Zone.Ground)
end

local function template(kind: string): BasePart?
	local t = templates[kind]
	if t then
		return t
	end
	local model = AssetLibrary.get(kind)
	local leaf = model and (model:FindFirstChild("Leaf") or model:FindFirstChildWhichIsA("BasePart"))
	if not leaf or not leaf:IsA("BasePart") then
		if model then
			model:Destroy()
		end
		return nil
	end
	leaf.Parent = nil
	if model then
		model:Destroy()
	end
	leaf.Anchored = true
	leaf.CanCollide = false
	leaf.CanQuery = false
	leaf.CanTouch = false
	leaf.CastShadow = false
	leaf.Material = Enum.Material.SmoothPlastic
	leaf.Transparency = 0
	leaf.Name = kind
	leaf:SetAttribute("BaseSize", leaf.Size)
	templates[kind] = leaf
	return leaf
end

-- True once the leaf models are loaded.
function LeafMeshes.ready(): boolean
	return templates.Leaf_Maple ~= nil or AssetLibrary.has("Leaf_Maple")
end

-- A leaf of this kind, `scale` times the modelled size (about 1 stud). Not parented.
function LeafMeshes.take(kind: string, color: Color3, scale: number): BasePart?
	local pool = pools[kind]
	local part = pool and table.remove(pool)
	if not part then
		local t = template(kind) or template("Leaf_Maple")
		if not t then
			return nil
		end
		part = t:Clone()
	end
	local p = part :: BasePart
	p.Color = color
	p.Transparency = 0
	p.Size = (p:GetAttribute("BaseSize") :: Vector3? or p.Size) * scale
	return p
end

-- A random leaf for a look.
function LeafMeshes.random(look: Look, scale: number): BasePart?
	local kind = look.kinds[math.random(1, #look.kinds)]
	return LeafMeshes.take(kind, look.colors[math.random(1, #look.colors)], scale)
end

-- Puts a leaf back in its pool.
function LeafMeshes.give(part: BasePart)
	part.Parent = nil
	local kind = part.Name
	local pool = pools[kind]
	if not pool then
		pool = {}
		pools[kind] = pool
	end
	table.insert(pool, part)
end

-- The modelled size of a leaf part, before scaling.
function LeafMeshes.baseSize(part: BasePart): Vector3
	return (part:GetAttribute("BaseSize") :: Vector3?) or part.Size
end

return LeafMeshes
