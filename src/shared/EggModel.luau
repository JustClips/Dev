--!strict
-- Eggs built from Roblox parts with real stud surfaces (Dev wants the exact Roblox stud
-- look, like Steal an Egg): stacked square layers in an egg shape, a coloured band, a
-- few plates stuck on the sides, and a topper per rarity. Thin layers clip the 1-stud
-- stud squares into the little C and L marks. Pivot at the bottom centre, facing -Z.
local EggModel = {}

local STUDS = Enum.SurfaceType.Studs
local SIZE = 0.8
local FACES = { "TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" }

type Theme = {
	main: Color3,
	band: Color3,
	cap: Color3,
	accent: Color3?,
	glow: Color3?,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local THEMES: { [string]: Theme } = {
	Common = { main = rgb(245, 243, 236), band = rgb(196, 186, 172), cap = rgb(226, 222, 212) },
	Uncommon = { main = rgb(126, 214, 104), band = rgb(70, 150, 70), cap = rgb(160, 228, 120), accent = rgb(122, 84, 52) },
	Rare = { main = rgb(225, 236, 255), band = rgb(96, 140, 220), cap = rgb(150, 186, 245) },
	Epic = { main = rgb(150, 96, 230), band = rgb(92, 52, 170), cap = rgb(190, 150, 250), glow = rgb(220, 140, 255) },
	Legendary = { main = rgb(255, 210, 70), band = rgb(232, 150, 30), cap = rgb(255, 236, 140), glow = rgb(255, 240, 150) },
	Mythic = { main = rgb(40, 42, 58), band = rgb(24, 26, 38), cap = rgb(60, 62, 82), accent = rgb(230, 222, 200), glow = rgb(255, 130, 30) },
	Cosmic = { main = rgb(34, 40, 96), band = rgb(232, 96, 210), cap = rgb(60, 70, 150), glow = rgb(255, 160, 240) },
}

-- Layers from the bottom: { width, height, band? }. About 3 wide and 3.6 tall.
local LAYERS = {
	{ 2.4, 0.6, false },
	{ 3.0, 0.6, false },
	{ 3.2, 0.6, true },
	{ 3.0, 0.6, false },
	{ 2.4, 0.6, false },
	{ 1.6, 0.6, false },
}

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.Plastic
	if not neon then
		for _, face in FACES do
			(p :: any)[face] = STUDS
		end
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Parent = model
	return p
end

local function wedge(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, neon: boolean?): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = if neon then Enum.Material.Neon else Enum.Material.Plastic
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.Parent = model
	return w
end

function EggModel.build(rarity: string): Model
	local theme = THEMES[rarity] or THEMES.Common
	local model = Instance.new("Model")
	model.Name = rarity .. "Egg"
	model:SetAttribute("PartEgg", true)

	local y = 0
	local tops: { number } = {}
	local body: Part? = nil
	for i, layer in LAYERS do
		local w, h, isBand = layer[1], layer[2], layer[3]
		local color = if isBand then theme.band elseif i == #LAYERS then theme.cap else theme.main
		local p = part(model, if i == 3 then "Body" else "Layer" .. i, Vector3.new(w, h, w), CFrame.new(0, y + h / 2, 0), color)
		if i == 3 then
			body = p
		end
		y += h
		tops[i] = y
	end
	local top = y

	-- Plates stuck on the sides (like the reference eggs), half sunk into their layer.
	local plates = {
		{ 2, Vector3.new(1.4, 0.4, 0.3), CFrame.new(-0.3, tops[2] - 0.3, -1.55) },
		{ 2, Vector3.new(0.3, 0.4, 1.2), CFrame.new(1.55, tops[2] - 0.3, 0.4) },
		{ 4, Vector3.new(1.2, 0.4, 0.3), CFrame.new(0.4, tops[4] - 0.3, -1.55) },
		{ 4, Vector3.new(0.3, 0.4, 1.0), CFrame.new(-1.55, tops[4] - 0.3, -0.3) },
		{ 5, Vector3.new(0.9, 0.4, 0.3), CFrame.new(-0.3, tops[5] - 0.3, -1.25) },
	}
	for k, plate in plates do
		part(model, "Plate" .. k, plate[2], plate[3], theme.main)
	end
	-- top block
	part(model, "Cap", Vector3.new(0.8, 0.3, 0.8), CFrame.new(0, top + 0.15, 0), theme.cap)

	if rarity == "Uncommon" then
		-- a sprout: stem and two leaves
		part(model, "Stem", Vector3.new(0.2, 0.6, 0.2), CFrame.new(0, top + 0.6, 0), theme.accent :: Color3)
		part(model, "LeafL", Vector3.new(0.6, 0.15, 0.35), CFrame.new(-0.35, top + 0.85, 0) * CFrame.Angles(0, 0, math.rad(20)), theme.band)
		part(model, "LeafR", Vector3.new(0.6, 0.15, 0.35), CFrame.new(0.35, top + 0.85, 0) * CFrame.Angles(0, 0, math.rad(-20)), theme.band)
	elseif rarity == "Rare" then
		-- knobs on the band
		for _, x in { -1, 1 } do
			part(model, "Knob", Vector3.new(0.4, 0.8, 0.8), CFrame.new(x * 1.75, tops[3] - 0.3, 0), theme.band)
		end
	elseif rarity == "Epic" then
		-- crystals on the top
		for k, spot in { Vector3.new(-0.5, 0, -0.3), Vector3.new(0.45, 0, 0.35), Vector3.new(0.1, 0, -0.55) } do
			local h = 0.9 - k * 0.15
			part(model, "Crystal" .. k, Vector3.new(0.3, h, 0.3), CFrame.new(spot.X * 0.9, top + h / 2 - 0.1, spot.Z * 0.9) * CFrame.Angles(math.rad(10 * k - 20), math.rad(30 * k), 0), theme.glow :: Color3, true)
		end
	elseif rarity == "Legendary" then
		-- crown points around the top
		for k = 0, 3 do
			local a = math.rad(45 + 90 * k)
			part(model, "Crown" .. k, Vector3.new(0.3, 0.6, 0.3), CFrame.new(math.cos(a) * 0.55, top + 0.3, math.sin(a) * 0.55), theme.band)
			part(model, "Gem" .. k, Vector3.new(0.18, 0.18, 0.18), CFrame.new(math.cos(a) * 0.55, top + 0.68, math.sin(a) * 0.55), theme.glow :: Color3, true)
		end
	elseif rarity == "Mythic" then
		-- horns and lava glowing through the bottom
		for _, x in { -1, 1 } do
			local horn = wedge(model, "Horn", Vector3.new(0.35, 0.9, 0.5), CFrame.new(x * 0.95, tops[5] + 0.4, 0) * CFrame.Angles(0, math.rad(x * 90), 0), theme.accent :: Color3)
			horn.CFrame = horn.CFrame * CFrame.Angles(math.rad(-15), 0, 0)
		end
		for k, spot in { Vector3.new(-0.7, 0.3, -1.21), Vector3.new(0.5, 0.25, -1.21), Vector3.new(1.21, 0.3, 0.4), Vector3.new(-1.21, 0.25, 0.2) } do
			local along = math.abs(spot.Z) > 1 and Vector3.new(0.6, 0.35, 0.05) or Vector3.new(0.05, 0.35, 0.6)
			part(model, "Lava" .. k, along, CFrame.new(spot), theme.glow :: Color3, true)
		end
	elseif rarity == "Cosmic" then
		-- a ring around the band and star blocks
		local ring = part(model, "Ring", Vector3.new(3.7, 0.15, 3.7), CFrame.new(0, tops[3] - 0.3, 0) * CFrame.Angles(0, math.rad(45), math.rad(10)), theme.band)
		ring.Transparency = 0.15
		for k, spot in { Vector3.new(-0.6, 0, -1.55), Vector3.new(0.7, 0, -1.55), Vector3.new(1.55, 0, 0.5) } do
			part(model, "Star" .. k, Vector3.new(0.25, 0.25, 0.25), CFrame.new(spot.X, tops[2] - 0.3 + (k - 2) * 0.2, spot.Z), theme.glow :: Color3, true)
		end
	end

	-- Shrink to about the old egg size (2.6 wide, 3.1 tall). Done on the parts, not with
	-- Model:ScaleTo, because callers use ScaleTo for their own sizes.
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			d.Size *= SIZE
			d.CFrame = cf - cf.Position + cf.Position * SIZE
		end
	end

	local primary = body :: Part
	model.PrimaryPart = primary
	primary.PivotOffset = CFrame.new(0, -primary.Position.Y, 0)
	return model
end

return EggModel
