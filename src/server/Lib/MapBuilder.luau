--!strict
-- Builds the map at server start from Config/World:
--   buildTerrain     grass and per-zone ground (park, beach, city, snow), walkways, hills
--   buildStructures  part-built pieces that need no uploaded models: the launch pad,
--                    base platforms + name signs, garage, upgrade station, sell signs
--   buildProps       every Blender prop (rocket, arches, hatcheries, fences, trees, rocks)
-- Gameplay parts (pads, gates, walls) come from src/workspace/Moon instead.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local World = require(Shared.Config.World)
local Zones = require(Shared.Config.Zones)

local MapBuilder = {}

local M = Enum.Material
local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local INK = Color3.fromRGB(27, 31, 58)
local WHITE = Color3.new(1, 1, 1)
local SURFACE = Color3.fromRGB(233, 238, 247)
local MINT = Color3.fromRGB(124, 245, 200)
local GOLD = Color3.fromRGB(255, 200, 60)

-- Terrain ------------------------------------------------------------------------

-- Smooth terrain is 4-stud voxels: a FillBlock whose top is at y renders (and collides)
-- the ground at y + 2. Checked on a live server, so every surface below is filled 2 lower.
local LIFT = 2

-- Ground slab with its walkable surface at surfaceY. cf gives x/z and rotation.
local function slab(terrain: Terrain, cf: CFrame, sx: number, sz: number, surfaceY: number, material: Enum.Material, depth: number?)
	local d = depth or 8
	local p = cf.Position
	terrain:FillBlock(CFrame.new(p.X, surfaceY - LIFT - d / 2, p.Z) * cf.Rotation, Vector3.new(sx, d, sz), material)
end

-- Empties a box (keep the edges on the 4-stud grid so no partial voxels are left).
local function carve(terrain: Terrain, x0: number, z0: number, x1: number, z1: number, y0: number, y1: number)
	terrain:FillBlock(
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Vector3.new(math.abs(x1 - x0), y1 - y0, math.abs(z1 - z0)),
		M.Air
	)
end

-- A strip of mountains: balls along a line from a to b (x, z), pushed outward.
local function ridge(terrain: Terrain, rng: Random, a: Vector2, b: Vector2, material: Enum.Material, spacing: number, rMin: number, rMax: number, baseY: number)
	local length = (b - a).Magnitude
	local steps = math.max(1, math.floor(length / spacing))
	for i = 0, steps do
		local p = a:Lerp(b, i / steps)
		local r = rng:NextNumber(rMin, rMax)
		local jitter = Vector3.new(rng:NextNumber(-spacing * 0.4, spacing * 0.4), rng:NextNumber(-6, 2), rng:NextNumber(-spacing * 0.4, spacing * 0.4))
		terrain:FillBall(Vector3.new(p.X, baseY, p.Y) + jitter, r, material)
	end
end

local function rect(terrain: Terrain, x0: number, z0: number, x1: number, z1: number, surfaceY: number, material: Enum.Material, depth: number?)
	slab(terrain, CFrame.new((x0 + x1) / 2, 0, (z0 + z1) / 2), math.abs(x1 - x0), math.abs(z1 - z0), surfaceY, material, depth)
end

function MapBuilder.buildTerrain()
	local terrain = Workspace.Terrain
	-- No animated grass blades: they grew over the leaf tiles (Dev, 2026-10-28).
	pcall(function()
		(terrain :: any).Decoration = false
	end)
	for name, color in World.TerrainColors do
		terrain:SetMaterialColor((M :: any)[name], color)
	end
	local rng = Random.new(42)

	-- Grass everywhere (surface y = 0), with a ground band per zone.
	slab(terrain, CFrame.new(0, 0, -410), 1000, 1860, 0, M.Grass, 36)
	rect(terrain, -500, -1340, 500, -976, 0, M.Snow) -- Snowy Peaks and beyond
	rect(terrain, -500, -976, 500, -720, 0, M.Asphalt) -- City band
	rect(terrain, -500, -720, 500, -472, 0, M.Sand) -- Beach band
	rect(terrain, -500, -472, 500, -212, 0, M.LeafyGrass) -- Park band

	-- Park dip (zone id Crater): floor 8 studs down, raised banks on both sides.
	local crater = Zones.ById.Crater
	local cMin, cMax = crater.Min, crater.Max
	carve(terrain, cMin.X, cMin.Y, cMax.X, cMax.Y, -16, 12)
	rect(terrain, cMin.X, cMin.Y, cMax.X, cMax.Y, crater.GroundY, M.LeafyGrass, 24)
	rect(terrain, cMin.X - 28, cMin.Y - 28, cMin.X, cMax.Y + 28, 4, M.Grass, 12)
	rect(terrain, cMax.X, cMin.Y - 28, cMax.X + 28, cMax.Y + 28, 4, M.Grass, 12)

	-- Corridors between zones: paved, with a ramp where the height changes.
	for _, c in World.Corridors do
		rect(terrain, c.Min.X, c.Min.Y, c.Max.X, c.Max.Y, math.max(c.FromY, c.ToY), M.Pavement)
		if c.FromY ~= c.ToY then
			local mid = (c.Min.Y + c.Max.Y) / 2
			-- The ramp half sits on the low side (next to the crater).
			local z0, z1 = if c.FromY > c.ToY then c.Min.Y else mid, if c.FromY > c.ToY then mid + 2 else c.Max.Y
			carve(terrain, -12, z0, 12, z1, -16, 12)
			rect(terrain, -12, z0, 12, z1, math.min(c.FromY, c.ToY), M.Grass, 24)
		end
	end

	-- Hub: paved walkways around the dust field and the south plaza.
	local f = World.Field
	local w = World.Walkway
	-- Short lawn (LeafyGrass has no tall grass blades) under the leaves, so the blades
	-- never hide what there is to sweep.
	rect(terrain, f.Min.X, f.Min.Y, f.Max.X, f.Max.Y, 0, M.LeafyGrass)
	rect(terrain, f.Min.X - w, f.Min.Y, f.Min.X, f.Max.Y, 0, M.Pavement)
	rect(terrain, f.Max.X, f.Min.Y, f.Max.X + w, f.Max.Y, 0, M.Pavement)
	local plaza = World.Plaza
	rect(terrain, plaza.Min.X, plaza.Min.Y, plaza.Max.X, plaza.Max.Y + 4, 0, M.Pavement)
	-- Under each base platform (it's raised 1 stud; this keeps the edges tidy).
	for i = 1, World.BaseCount do
		local cf = World.baseCFrame(i)
		slab(terrain, cf, World.BaseSize.X + 4, World.BaseSize.Y + 4, 0, M.Concrete)
	end

	-- Mountains around everything.
	local hubX = World.BaseInner + World.BaseSize.Y + 2
	ridge(terrain, rng, Vector2.new(-hubX - 53, 250), Vector2.new(-hubX - 53, -210), M.Grass, 24, 22, 36, -6)
	ridge(terrain, rng, Vector2.new(hubX + 53, 250), Vector2.new(hubX + 53, -210), M.Grass, 24, 22, 36, -6)
	ridge(terrain, rng, Vector2.new(-hubX - 53, 258), Vector2.new(hubX + 53, 258), M.Grass, 24, 22, 36, -6)
	-- passes between zones
	for _, c in World.Corridors do
		local z = (c.Min.Y + c.Max.Y) / 2
		-- thin ridges so they never cover dust in the zones on either side
		ridge(terrain, rng, Vector2.new(30, z), Vector2.new(170, z), M.Grass, 10, 8, 11, 0)
		ridge(terrain, rng, Vector2.new(-30, z), Vector2.new(-170, z), M.Grass, 10, 8, 11, 0)
	end
	local zoneMaterial = { Crater = M.LeafyGrass, DarkSide = M.Sandstone, Mars = M.Concrete, Europa = M.Glacier }
	for _, zone in Zones.List do
		local material = zoneMaterial[zone.Id]
		if material then
			ridge(terrain, rng, Vector2.new(zone.Min.X - 62, zone.Max.Y), Vector2.new(zone.Min.X - 62, zone.Min.Y), material, 24, 20, 34, -4)
			ridge(terrain, rng, Vector2.new(zone.Max.X + 62, zone.Max.Y), Vector2.new(zone.Max.X + 62, zone.Min.Y), material, 24, 20, 34, -4)
		end
	end
	-- Back wall behind the last zone.
	local last = Zones.List[#Zones.List]
	ridge(terrain, rng, Vector2.new(last.Min.X - 60, last.Min.Y - 58), Vector2.new(last.Max.X + 60, last.Min.Y - 58), zoneMaterial[last.Id] or M.Grass, 24, 22, 36, -4)
end

-- Lighting -----------------------------------------------------------------------

local function effect(className: string, name: string): Instance
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		existing.Name = name
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

-- Sunny afternoon under a blue sky with clouds (Sweep the World).
function MapBuilder.setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(110, 110, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 247, 232)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.ExposureCompensation = 0

	local atmosphere = effect("Atmosphere", "WorldAtmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(199, 226, 255)
	atmosphere.Decay = Color3.fromRGB(110, 150, 196)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1

	local bloom = effect("BloomEffect", "WorldBloom") :: BloomEffect
	bloom.Intensity = 0.3
	bloom.Size = 24
	bloom.Threshold = 2

	local grade = effect("ColorCorrectionEffect", "WorldGrade") :: ColorCorrectionEffect
	grade.Saturation = 0.18
	grade.Contrast = 0.06
	grade.Brightness = 0.02
	grade.TintColor = Color3.fromRGB(255, 252, 245)

	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Intensity = 0.06
	end

	-- Roblox's own daytime sky (blue with soft clouds), no stars.
	local sky = effect("Sky", "WorldSky") :: Sky
	for _, face in { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" } do
		(sky :: any)["Skybox" .. face] = `rbxasset://textures/sky/sky512_{string.lower(face)}.tex`
	end
	sky.StarCount = 0
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 8

	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = Workspace.Terrain
end

-- Part helpers --------------------------------------------------------------------

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className) :: any
	if inst:IsA("BasePart") then
		inst.Anchored = true
		inst.TopSurface = Enum.SurfaceType.Smooth
		inst.BottomSurface = Enum.SurfaceType.Smooth
		inst.Material = M.SmoothPlastic
	end
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): BasePart
	local p = make("Part", { Name = name, Size = size, CFrame = cf, Color = color, Material = material or M.SmoothPlastic }, nil)
	if extra then
		for k, v in extra do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- Trim pieces. Only lamps glow (Sweep the World: no neon strips, Dev 2026-10-28).
local function glow(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): BasePart
	local material = if string.find(name, "Light") then M.Neon else M.SmoothPlastic
	return block(parent, name, size, cf, color, material, { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
end

-- The UI's stud texture on a part's top face, so floors match the HUD.
local function studs(p: BasePart, color: Color3, studsPerTile: number?)
	local image = AssetLibrary.image("Stud")
	if image == "" then
		return
	end
	make("Texture", {
		Texture = image,
		Face = Enum.NormalId.Top,
		StudsPerTileU = studsPerTile or 5,
		StudsPerTileV = studsPerTile or 5,
		Color3 = color,
	}, p)
end

local WOOD = Color3.fromRGB(196, 142, 92)
local WOOD_DARK = Color3.fromRGB(128, 84, 52)
local DIRT = Color3.fromRGB(150, 118, 86)
local LANTERN = Color3.fromRGB(255, 214, 140)

local function lighten(c: Color3, t: number): Color3
	return c:Lerp(WHITE, t)
end

export type Sign = { Board: BasePart, Titles: { TextLabel }, Subs: { TextLabel }, Avatars: { ImageLabel } }

-- A wooden sign board with a lighter wood frame; text on the front face.
local function sign(parent: Instance, name: string, cf: CFrame, width: number, height: number, accent: Color3, title: string, sub: string?, withAvatar: boolean?): Sign
	local board = block(parent, name, Vector3.new(width, height, 0.6), cf, WOOD_DARK, M.WoodPlanks)
	block(board, "Trim", Vector3.new(width + 0.6, height + 0.6, 0.4), cf, WOOD, M.Wood, { CanCollide = false, CanQuery = false, CanTouch = false })
	local result: Sign = { Board = board, Titles = {}, Subs = {}, Avatars = {} }
	-- Text on the front only (Dev: no text on the back of signs).
	for _, face in { Enum.NormalId.Front } do
		local gui = make("SurfaceGui", {
			Name = "Sign" .. face.Name,
			Face = face,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 40,
			LightInfluence = 0.4,
			MaxDistance = 400,
		}, board)
		-- Room for the owner's avatar; text uses the full board until an avatar is shown
		-- (MapBuilder.setSignAvatar).
		local pad = if withAvatar then height * 40 else 0
		gui:SetAttribute("AvatarPad", pad)
		local avatar = make("ImageLabel", {
			Name = "Avatar",
			Size = UDim2.new(0, pad - 24, 0, pad - 24),
			Position = UDim2.new(0, 14, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = lighten(accent, 0.3),
			Visible = false,
			Image = "",
		}, gui)
		make("UIStroke", { Color = WHITE, Thickness = 6 }, avatar)
		table.insert(result.Avatars, avatar)
		local titleLabel = make("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -28, if sub then 0.6 else 0.86, 0),
			Position = UDim2.new(0, 14, if sub then 0.06 else 0.07, 0),
			Text = title,
			TextScaled = true,
			TextColor3 = WHITE,
			FontFace = Font.new(MONTSERRAT, Enum.FontWeight.Heavy),
		}, gui)
		make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 4, Transparency = 0.3 }, titleLabel)
		table.insert(result.Titles, titleLabel)
		local subLabel = make("TextLabel", {
			Name = "Sub",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -28, 0.3, 0),
			Position = UDim2.new(0, 14, 0.64, 0),
			Text = sub or "",
			Visible = sub ~= nil,
			TextScaled = true,
			TextColor3 = lighten(accent, 0.55),
			FontFace = Font.new(MONTSERRAT, Enum.FontWeight.ExtraBold),
		}, gui)
		make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3, Transparency = 0.4 }, subLabel)
		table.insert(result.Subs, subLabel)
	end
	return result
end

-- A sign on two posts, standing on the ground at cf (sign faces cf.LookVector).
local function signOnPosts(parent: Instance, name: string, cf: CFrame, width: number, height: number, accent: Color3, title: string, sub: string?): Sign
	local postHeight = 4 + height
	for _, x in { -width / 2 + 1, width / 2 - 1 } do
		block(parent, name .. "Post", Vector3.new(0.7, postHeight, 0.7), cf * CFrame.new(x, postHeight / 2, 0.4), WOOD_DARK, M.Wood)
	end
	return sign(parent, name, cf * CFrame.new(0, 4 + height / 2, 0), width, height, accent, title, sub)
end

-- Flat text on the floor (thin invisible slab with a top SurfaceGui).
local function floorText(parent: Instance, cf: CFrame, width: number, depth: number, text: string, color: Color3)
	local p = block(parent, "FloorText", Vector3.new(width, 0.05, depth), cf, WHITE, nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local gui = make("SurfaceGui", {
		Face = Enum.NormalId.Top,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 30,
		LightInfluence = 0.3,
	}, p)
	local label = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		TextColor3 = color,
		FontFace = Font.new(MONTSERRAT, Enum.FontWeight.Heavy),
	}, gui)
	make("UIStroke", { Color = INK, Thickness = 5 }, label)
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number?)
	make("PointLight", { Color = color, Range = range, Brightness = brightness or 1.5, Shadows = false }, parent)
end

local function prompt(parent: BasePart, opens: string, action: string, object: string)
	local p = make("ProximityPrompt", {
		Name = opens .. "Prompt",
		ActionText = action,
		ObjectText = object,
		HoldDuration = 0,
		MaxActivationDistance = 14,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.E,
	}, parent)
	p:SetAttribute("Opens", opens)
end

-- Structures ---------------------------------------------------------------------

local structures: Folder
local baseSigns: { [number]: Sign } = {}

local function launchPad()
	local model = make("Model", { Name = "LaunchPad" }, structures)
	local r = World.LaunchPadRadius
	local center = World.RocketPosition
	-- Rotate cylinders so their axis is vertical.
	local up = CFrame.Angles(0, 0, math.rad(90))
	-- A round cobblestone plaza with a wooden rim; the sell ring is painted green on it.
	block(model, "Pad", Vector3.new(1, r * 2, r * 2), CFrame.new(center) * up, Color3.fromRGB(200, 192, 178), M.Cobblestone)
	block(model, "Rim", Vector3.new(0.8, r * 2 + 2, r * 2 + 2), CFrame.new(center + Vector3.new(0, -0.15, 0)) * up, WOOD_DARK, M.Wood)
	glow(model, "SellRing", Vector3.new(0.14, World.SellRadius * 2 + 1.2, World.SellRadius * 2 + 1.2), CFrame.new(center + Vector3.new(0, 0.52, 0)) * up, Color3.fromRGB(92, 200, 92))
	block(model, "SellFloor", Vector3.new(0.16, World.SellRadius * 2 - 0.4, World.SellRadius * 2 - 0.4), CFrame.new(center + Vector3.new(0, 0.53, 0)) * up, WOOD, M.WoodPlanks)
	-- One sign per side; players arrive from the field ends and from the bases.
	local d = World.RocketClearRadius - 2.5
	for _, yaw in { 0, 90, 180, 270 } do
		local cf = CFrame.new(center) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.new(0, 0, d)
		signOnPosts(model, "SellSign", CFrame.lookAt(cf.Position, cf.Position + (cf.Position - center) * Vector3.new(1, 0, 1)), 13, 3.6, MINT, "SELL LEAVES", "Stand on the ring")
	end
end

local function fieldEdges()
	local model = make("Model", { Name = "FieldEdges" }, structures)
	local f = World.Field
	local y = 0.08
	local length = f.Max.Y - f.Min.Y
	for _, x in { f.Min.X, f.Max.X } do
		glow(model, "Edge", Vector3.new(0.35, 0.16, length), CFrame.new(x, y, (f.Min.Y + f.Max.Y) / 2), WOOD_DARK)
	end
	glow(model, "Edge", Vector3.new(f.Max.X - f.Min.X, 0.16, 0.35), CFrame.new(0, y, f.Max.Y), WOOD_DARK)
end

-- Raised stud-plate platform in the base colour, corner lights, low walls and a name sign.
function MapBuilder.buildBaseStructure(index: number): Sign
	local cf = World.baseCFrame(index)
	local color = World.BaseColors[((index - 1) % #World.BaseColors) + 1]
	local model = make("Model", { Name = "BasePlatform" .. index }, structures)
	local w, d = World.BaseSize.X, World.BaseSize.Y
	local floorY = World.BaseFloorY

	-- Wooden deck: warm planks, darker wood trim, log posts with lanterns and a rail
	-- fence. The base colour only shows on the rails, post bands and lantern light.
	-- Parts that sit on the floor stay at least 0.1 stud above it so nothing flickers.
	block(model, "Floor", Vector3.new(w, floorY + 1, d), cf * CFrame.new(0, -(floorY + 1) / 2, 0), WOOD, M.WoodPlanks)
	local trimH = floorY + 1.1
	for _, side in { -1, 1 } do
		block(model, "Trim", Vector3.new(2, trimH, d), cf * CFrame.new(side * (w / 2 - 1), -(floorY + 1) / 2 + 0.05, 0), WOOD_DARK, M.Wood)
	end
	block(model, "Trim", Vector3.new(w - 4, trimH, 2), cf * CFrame.new(0, -(floorY + 1) / 2 + 0.05, d / 2 - 1), WOOD_DARK, M.Wood)
	block(model, "Trim", Vector3.new(w - 4, trimH, 2), cf * CFrame.new(0, -(floorY + 1) / 2 + 0.05, -d / 2 + 1), WOOD_DARK, M.Wood)
	-- (a WedgePart's high side is its +Z, here the platform edge)
	make("WedgePart", {
		Name = "Ramp",
		Size = Vector3.new(w, floorY, 3),
		CFrame = cf * CFrame.new(0, -floorY / 2, -d / 2 - 1.5),
		Color = WOOD_DARK,
		Material = M.WoodPlanks,
	}, model)
	-- dirt walkway from the arch to the hatchery
	local path = block(model, "Path", Vector3.new(10, 0.2, 13), cf * CFrame.new(0, 0.1, -35), DIRT, M.Ground)
	path.CanCollide = false
	-- grass park
	local pMin, pMax = World.Base.ParkMin, World.Base.ParkMax
	local parkCenter = (pMin + pMax) / 2
	local park = block(model, "Park", Vector3.new(pMax.X - pMin.X, 0.3, pMax.Y - pMin.Y), cf * CFrame.new(parkCenter.X, 0.05, parkCenter.Y), World.TerrainColors.Grass:Lerp(Color3.new(0, 0, 0), 0.15), M.Grass)
	park.CanCollide = false
	-- corner log posts with a lantern on top
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local at = cf * CFrame.new(x * (w / 2 - 1.5), 0, z * (d / 2 - 1.5))
			make("Part", {
				Name = "Pillar",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(7, 2.2, 2.2),
				CFrame = at * CFrame.new(0, 3.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color = WOOD_DARK,
				Material = M.Wood,
			}, model)
			block(model, "PillarBand", Vector3.new(2.5, 0.6, 2.5), at * CFrame.new(0, 1.2, 0), color, M.SmoothPlastic)
			block(model, "LanternTop", Vector3.new(2.2, 0.4, 2.2), at * CFrame.new(0, 8.3, 0), WOOD_DARK, M.Wood)
			local cap = glow(model, "PillarLight", Vector3.new(1.4, 1.2, 1.4), at * CFrame.new(0, 7.5, 0), LANTERN)
			light(cap, LANTERN, 16, 0.7)
		end
	end
	-- wooden rail fence on the sides and back (the front stays open)
	local wallH = 3
	for _, side in { -1, 1 } do
		for _, y in { 1, 2.4 } do
			block(model, "Wall", Vector3.new(0.5, 0.5, d - 5), cf * CFrame.new(side * (w / 2 - 0.4), y, 0), WOOD, M.Wood)
		end
		block(model, "WallRail", Vector3.new(0.8, 0.4, d - 5), cf * CFrame.new(side * (w / 2 - 0.4), wallH + 0.2, 0), WOOD_DARK, M.Wood)
		for k = -4, 4 do
			block(model, "Post", Vector3.new(0.7, wallH, 0.7), cf * CFrame.new(side * (w / 2 - 0.4), wallH / 2, k * (d - 6) / 8), WOOD_DARK, M.Wood)
		end
	end
	for _, y in { 1, 2.4 } do
		block(model, "Wall", Vector3.new(w - 5, 0.5, 0.5), cf * CFrame.new(0, y, d / 2 - 0.4), WOOD, M.Wood)
	end
	block(model, "WallRail", Vector3.new(w - 5, 0.4, 0.8), cf * CFrame.new(0, wallH + 0.2, d / 2 - 0.4), WOOD_DARK, M.Wood)
	for k = -4, 4 do
		block(model, "Post", Vector3.new(0.7, wallH, 0.7), cf * CFrame.new(k * (w - 6) / 8, wallH / 2, d / 2 - 0.4), WOOD_DARK, M.Wood)
	end
	-- name sign above the arch, facing the field
	local arch = World.Base.Arch
	local s = sign(model, "NameSign", cf * CFrame.new(arch + Vector3.new(0, 15.4, 0)), 19, 4.6, color, "Free Base", "Claim it by joining!", true)
	baseSigns[index] = s
	return s
end

-- Shows the owner's headshot on a sign (or hides it) and moves the text over to make room.
function MapBuilder.setSignAvatar(s: Sign, userId: number?)
	for _, avatar in s.Avatars do
		local gui = avatar.Parent :: Instance
		local pad = if userId then (gui:GetAttribute("AvatarPad") :: number?) or 0 else 0
		avatar.Visible = userId ~= nil and pad > 0
		avatar.Image = if userId then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else ""
		for _, label in { gui:FindFirstChild("Title"), gui:FindFirstChild("Sub") } do
			if label and label:IsA("TextLabel") then
				label.Size = UDim2.new(1, -(pad + 28), label.Size.Y.Scale, 0)
				label.Position = UDim2.new(0, pad + 14, label.Position.Y.Scale, 0)
			end
		end
	end
end

function MapBuilder.getBaseSign(index: number): Sign?
	return baseSigns[index]
end

-- Open carport with a car on display, a kiosk and a spawn pad in front.
local function garage()
	local cf = World.Garage
	local model = make("Model", { Name = "Garage" }, structures)
	local orange = Color3.fromRGB(255, 154, 60)
	local floor = block(model, "Floor", Vector3.new(28, 0.6, 22), cf * CFrame.new(0, 0.3, 0), WOOD, M.WoodPlanks)
	floor.CanCollide = true
	for _, x in { -13, 13 } do
		for _, z in { -10, 10 } do
			block(model, "Pillar", Vector3.new(1.4, 10, 1.4), cf * CFrame.new(x, 5.3, z), SURFACE)
		end
	end
	block(model, "Roof", Vector3.new(30, 1.2, 24), cf * CFrame.new(0, 10.9, 0), orange)
	glow(model, "RoofTrim", Vector3.new(30.4, 0.4, 0.4), cf * CFrame.new(0, 10.2, -12), WOOD_DARK)
	local back = block(model, "BackWall", Vector3.new(26, 10, 0.8), cf * CFrame.new(0, 5.3, 10.6), SURFACE)
	studs(back, SURFACE, 4)
	local ceiling = glow(model, "CeilingLight", Vector3.new(18, 0.2, 2), cf * CFrame.new(0, 10.2, 0), WHITE)
	light(ceiling, WHITE, 24, 1.4)
	sign(model, "GarageSign", cf * CFrame.new(0, 13.6, -11.4), 18, 4.2, orange, "GARAGE", "Buy and spawn cars")
	-- kiosk with the prompt
	local kiosk = block(model, "Kiosk", Vector3.new(3, 4, 2), cf * CFrame.new(-9.5, 2.6, -7), SURFACE)
	glow(model, "KioskScreen", Vector3.new(2.4, 1.6, 0.2), cf * CFrame.new(-9.5, 3.4, -8.05), Color3.fromRGB(76, 141, 255))
	prompt(kiosk, "Garage", "Open Garage", "Cars")
	-- spawn pad: neon square outline + floor text
	local spawn = World.GarageSpawn
	for _, x in { -7, 7 } do
		glow(model, "SpawnEdge", Vector3.new(0.4, 0.12, 14), spawn * CFrame.new(x, 0.06, 0), orange)
	end
	for _, z in { -7, 7 } do
		glow(model, "SpawnEdge", Vector3.new(14, 0.12, 0.4), spawn * CFrame.new(0, 0.06, z), orange)
	end
	floorText(model, spawn * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, math.rad(180), 0), 12, 3, "CAR SPAWN", orange)
end

-- Upgrade booth: canopy, counter with the prompt, big floating arrow icon.
local function upgradeStation()
	local cf = World.UpgradeStation
	local model = make("Model", { Name = "UpgradeStation" }, structures)
	local purple = Color3.fromRGB(150, 100, 255)
	block(model, "Floor", Vector3.new(24, 0.6, 18), cf * CFrame.new(0, 0.3, 0), WOOD, M.WoodPlanks)
	for _, x in { -11, 11 } do
		for _, z in { -8, 8 } do
			block(model, "Pillar", Vector3.new(1.4, 9, 1.4), cf * CFrame.new(x, 4.8, z), SURFACE)
		end
	end
	block(model, "Roof", Vector3.new(26, 1.2, 20), cf * CFrame.new(0, 9.9, 0), purple)
	glow(model, "RoofTrim", Vector3.new(26.4, 0.4, 0.4), cf * CFrame.new(0, 9.2, -10), GOLD)
	local counter = block(model, "Counter", Vector3.new(14, 3.4, 3), cf * CFrame.new(0, 2.3, -1), SURFACE)
	studs(counter, SURFACE, 3)
	block(model, "CounterTop", Vector3.new(14.6, 0.4, 3.6), cf * CFrame.new(0, 4.2, -1), purple)
	glow(model, "CounterStrip", Vector3.new(14.2, 0.3, 0.2), cf * CFrame.new(0, 3.4, -2.55), GOLD)
	prompt(counter, "Upgrades", "Upgrade", "Upgrade Station")
	local ceiling = glow(model, "CeilingLight", Vector3.new(14, 0.2, 2), cf * CFrame.new(0, 9.2, 0), WHITE)
	light(ceiling, purple, 24, 1.4)
	sign(model, "UpgradeSign", cf * CFrame.new(0, 12.6, -9.4), 18, 4.2, GOLD, "UPGRADES", "Backpack, speed, power, luck")
	-- floating icon over the counter (the client spins it)
	local holo = block(model, "Hologram", Vector3.new(1, 1, 1), cf * CFrame.new(0, 7, -1), WHITE, nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local bb = make("BillboardGui", { Size = UDim2.fromScale(5, 5), LightInfluence = 0, MaxDistance = 160 }, holo)
	make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = AssetLibrary.image("Icon_Upgrade") }, bb)
	holo:SetAttribute("Bob", true)
end

-- Big screen on the south wall with the game logo.
local function plazaScreen()
	local model = make("Model", { Name = "PlazaScreen" }, structures)
	local cf = CFrame.lookAt(Vector3.new(0, 0, 194), Vector3.new(0, 0, 0))
	for _, x in { -15, 15 } do
		block(model, "Leg", Vector3.new(1.4, 10, 1.4), cf * CFrame.new(x, 5, 0.8), WOOD_DARK, M.Wood)
	end
	local screen = block(model, "Screen", Vector3.new(34, 14, 1), cf * CFrame.new(0, 16, 0), INK)
	glow(model, "Frame", Vector3.new(35, 15, 0.6), cf * CFrame.new(0, 16, 0.3), WOOD_DARK)
	local gui = make("SurfaceGui", {
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 24,
		LightInfluence = 0,
		Brightness = 1.4,
	}, screen)
	make("ImageLabel", {
		Size = UDim2.fromScale(0.92, 0.92),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Image = AssetLibrary.image("Logo"),
	}, gui)
end

-- Event board in the plaza: a big sign (RewardService writes the event name and the
-- countdown on it), a sign-up kiosk with a prompt, and a floating event icon.
local eventSign: Sign? = nil

local function eventBoard()
	local cf = World.EventBoard
	local model = make("Model", { Name = "EventBoard" }, structures)
	local pink = Color3.fromRGB(255, 120, 230)
	block(model, "Floor", Vector3.new(20, 0.6, 10), cf * CFrame.new(0, 0.3, 0), WOOD, M.WoodPlanks)
	glow(model, "FloorTrim", Vector3.new(20.4, 0.2, 0.4), cf * CFrame.new(0, 0.62, -5), pink)
	eventSign = signOnPosts(model, "EventSign", cf * CFrame.new(0, 0, 3), 18, 7, GOLD, "EVENTS", "Sign up here!")
	local kiosk = block(model, "Kiosk", Vector3.new(4, 3.6, 2), cf * CFrame.new(0, 2.4, -1.5), SURFACE)
	studs(kiosk, SURFACE, 3)
	glow(model, "KioskTop", Vector3.new(4.4, 0.4, 2.4), cf * CFrame.new(0, 4.4, -1.5), pink)
	prompt(kiosk, "Event", "Sign up", "Event")
	local holo = block(model, "Hologram", Vector3.new(1, 1, 1), cf * CFrame.new(0, 7.2, -1.5), WHITE, nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local bb = make("BillboardGui", { Size = UDim2.fromScale(4, 4), LightInfluence = 0, MaxDistance = 160 }, holo)
	make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = AssetLibrary.image("Icon_Event") }, bb)
	holo:SetAttribute("Bob", true)
end

function MapBuilder.getEventSign(): Sign?
	return eventSign
end

-- Ramps where a corridor changes height (terrain under them is carved by buildTerrain).
local function corridorRamps()
	local model = make("Model", { Name = "Ramps" }, structures)
	for _, c in World.Corridors do
		if c.FromY == c.ToY then
			continue
		end
		local mid = (c.Min.Y + c.Max.Y) / 2
		local low, high = math.min(c.FromY, c.ToY), math.max(c.FromY, c.ToY)
		-- Ramp z range and which end is high (the end away from the crater).
		local z0, z1 = if c.FromY > c.ToY then c.Min.Y else mid, if c.FromY > c.ToY then mid else c.Max.Y
		local highAtMaxZ = c.FromY > c.ToY
		local length = z1 - z0
		local rot = if highAtMaxZ then CFrame.identity else CFrame.Angles(0, math.rad(180), 0)
		make("WedgePart", {
			Name = "Ramp",
			-- 3 studs wider on each side than the carved cut, so its sides tuck into the
			-- terrain walls (smooth terrain rounds its edges and left a visible gap).
			Size = Vector3.new(c.Max.X - c.Min.X + 6, high - low, length),
			CFrame = CFrame.new(0, (low + high) / 2, (z0 + z1) / 2) * rot,
			Color = World.TerrainColors.Pavement,
			Material = M.Concrete,
		}, model)
		for _, x in { c.Min.X, c.Max.X } do
			glow(model, "RampEdge", Vector3.new(0.3, 0.2, math.sqrt(length ^ 2 + (high - low) ^ 2)), CFrame.new(x, (low + high) / 2 + 0.1, (z0 + z1) / 2) * rot * CFrame.Angles(-math.atan2(high - low, length), 0, 0), WOOD_DARK)
		end
	end
end

-- Everything above, plus base platforms. Needs only images (no models), so it runs at boot.
function MapBuilder.buildStructures()
	structures = Instance.new("Folder")
	structures.Name = "Structures"
	structures.Parent = Workspace
	launchPad()
	fieldEdges()
	corridorRamps()
	garage()
	upgradeStation()
	plazaScreen()
	eventBoard()
	for i = 1, World.BaseCount do
		MapBuilder.buildBaseStructure(i)
	end
end

-- Props --------------------------------------------------------------------------

local propsFolder: Folder

local function place(name: string, cf: CFrame, scale: number?, parent: Instance?): Model?
	local model = AssetLibrary.get(name)
	if not model then
		return nil
	end
	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:PivotTo(cf)
	model.Parent = parent or propsFolder
	return model
end

local function yaw(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end

-- Fence along a line in base-local space, in segments of about 8 studs.
local function fenceLine(baseCf: CFrame, a: Vector2, b: Vector2, parent: Instance)
	local length = (b - a).Magnitude
	local count = math.max(1, math.ceil(length / 8))
	local scale = length / (count * 8)
	local dir = (b - a).Unit
	local angle = math.atan2(-dir.Y, dir.X)
	for k = 0, count - 1 do
		local mid = a + dir * ((k + 0.5) * length / count)
		place("Fence", baseCf * CFrame.new(mid.X, 0, mid.Y) * CFrame.Angles(0, angle, 0), scale, parent)
	end
end

function MapBuilder.buildBase(index: number): Model
	local baseCf = World.baseCFrame(index)
	local model = Instance.new("Model")
	model.Name = "BaseProps" .. index
	local B = World.Base
	place("BaseArch", baseCf * CFrame.new(B.Arch), 1, model)
	place("Hatchery", baseCf * CFrame.new(B.Hatchery), 1, model)
	for _, p in B.Incubators do
		place("Incubator", baseCf * CFrame.new(p), 1, model)
	end
	for _, p in B.Lamps do
		place("Lamp", baseCf * CFrame.new(p) * yaw(180), 1, model)
	end
	-- park fence with a gate gap at the front
	local mn, mx, gap = B.ParkMin, B.ParkMax, B.ParkGateWidth / 2
	fenceLine(baseCf, Vector2.new(mn.X, mn.Y), Vector2.new(-gap, mn.Y), model)
	fenceLine(baseCf, Vector2.new(gap, mn.Y), Vector2.new(mx.X, mn.Y), model)
	fenceLine(baseCf, Vector2.new(mx.X, mn.Y), Vector2.new(mx.X, mx.Y), model)
	fenceLine(baseCf, Vector2.new(mx.X, mx.Y), Vector2.new(mn.X, mx.Y), model)
	fenceLine(baseCf, Vector2.new(mn.X, mx.Y), Vector2.new(mn.X, mn.Y), model)
	for _, prop in B.ParkProps do
		place(prop.Asset, baseCf * CFrame.new(prop.Position) * yaw(prop.Yaw), 1, model)
	end
	model.Parent = propsFolder
	return model
end

-- Bins, dumpster, hydrant, bench, beach umbrella.
local FIXED_SIZE = { Rock_Dark1 = true, Rock_Dark2 = true, Crystal_Purple = true, Mushroom_Glow = true, Mushroom_Mars = true }

local function scatter(rng: Random, zone, names: { string }, count: number)
	for _ = 1, count do
		local name = names[rng:NextInteger(1, #names)]
		local x, z
		local band = rng:NextInteger(1, 3)
		if band == 1 then
			x = zone.Min.X - rng:NextNumber(5, 26)
			z = rng:NextNumber(zone.Min.Y, zone.Max.Y)
		elseif band == 2 then
			x = zone.Max.X + rng:NextNumber(5, 26)
			z = rng:NextNumber(zone.Min.Y, zone.Max.Y)
		else
			-- along the far edge, away from the corridor
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			x = side * rng:NextNumber(24, zone.Max.X)
			z = zone.Min.Y - rng:NextNumber(4, 18)
		end
		local y = if zone.Id == "Crater" then 4 else zone.GroundY
		-- Street furniture stays near life size; rocks, bushes and trees vary more.
		local scale = if FIXED_SIZE[name] then rng:NextNumber(0.9, 1.2) else rng:NextNumber(0.8, 2.0)
		place(name, CFrame.new(x, y, z) * yaw(rng:NextNumber(0, 360)), scale)
	end
end

-- Rocks and crystals outside the hub walls, between the bases and the mountains.
local function hubDecor(rng: Random)
	local names = { "Rock_Moon1", "Rock_Moon2", "Rock_Moon3", "Crystal_Blue", "Rock_Moon2" }
	local hubX = World.BaseInner + World.BaseSize.Y + 2
	for _ = 1, 26 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x = side * rng:NextNumber(hubX + 6, hubX + 30)
		local z = rng:NextNumber(-200, 240)
		place(names[rng:NextInteger(1, #names)], CFrame.new(x, 0, z) * yaw(rng:NextNumber(0, 360)), rng:NextNumber(1.2, 2.6))
	end
	for _ = 1, 10 do
		local x = rng:NextNumber(-hubX, hubX)
		local z = rng:NextNumber(206, 232)
		place(names[rng:NextInteger(1, #names)], CFrame.new(x, 0, z) * yaw(rng:NextNumber(0, 360)), rng:NextNumber(1.2, 2.6))
	end
end

function MapBuilder.buildProps()
	propsFolder = Instance.new("Folder")
	propsFolder.Name = "Props"
	propsFolder.Parent = Workspace
	local rng = Random.new(7)

	-- The market hall where leaves are sold (asset name kept from the rocket it replaced).
	local hallCf = CFrame.new(World.RocketPosition + Vector3.new(0, 0.5, 0)) * yaw(180)
	local hall = place("Rocket", hallCf)
	local meta = AssetLibrary.meta("Rocket")
	if hall and meta and meta.sign then
		-- Name on the blank board over the front (front = -Z in the model).
		local board = block(hall, "MarketSign", Vector3.new(11, 2.6, 0.05), hallCf * CFrame.new(meta.sign + Vector3.new(0, 0, -0.35)), WHITE, nil, {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		local gui = make("SurfaceGui", {
			Face = Enum.NormalId.Front,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 40,
			LightInfluence = 0.4,
			MaxDistance = 400,
		}, board)
		local label = make("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "MARKET",
			TextScaled = true,
			TextColor3 = Color3.fromRGB(46, 120, 52),
			FontFace = Font.new(MONTSERRAT, Enum.FontWeight.Heavy),
		}, gui)
		make("UIStroke", { Color = WHITE, Thickness = 4 }, label)
	end
	-- lamps along both walkways, flags and satellites on the plaza
	local f = World.Field
	for z = f.Min.Y + 25, f.Max.Y, 57 do
		place("Lamp", CFrame.new(f.Min.X - 1.5, 0, z) * yaw(90))
		place("Lamp", CFrame.new(f.Max.X + 1.5, 0, z) * yaw(-90))
	end
	place("Flag", CFrame.new(-10, 0, 186) * yaw(20))
	place("Flag", CFrame.new(10, 0, 186) * yaw(-20))
	place("Satellite", CFrame.new(-56, 0, 194) * yaw(150), 1.4)
	place("Satellite", CFrame.new(56, 0, 194) * yaw(210), 1.4)
	for _, z in { -120, 60 } do
		place("Satellite", CFrame.new(-190, 6, z) * yaw(rng:NextNumber(0, 360)), 1.6)
		place("Satellite", CFrame.new(190, 6, z + 40) * yaw(rng:NextNumber(0, 360)), 1.6)
	end
	-- a car on display in the garage
	place("Vehicle_SweeperCart", World.Garage * CFrame.new(3, 0.6, 2) * yaw(-25))
	-- zone gates (sign faces the hub)
	for _, c in World.Corridors do
		place("ZoneGate", CFrame.new(0, math.max(c.FromY, c.ToY), c.GateZ) * yaw(180))
	end
	scatter(rng, Zones.ById.Crater, { "Rock_Crater1", "Rock_Crater2", "Crystal_Blue" }, 30)
	-- Beach (id DarkSide): sandy rocks, palms, umbrellas. City (id Mars): bins, dumpsters,
	-- hydrants, benches. (Prop names are kept from the Moon version.)
	scatter(rng, Zones.ById.DarkSide, { "Rock_Mars1", "Rock_Mars2", "Crystal_Red", "Mushroom_Mars" }, 30)
	scatter(rng, Zones.ById.Mars, { "Rock_Dark1", "Rock_Dark2", "Crystal_Purple", "Mushroom_Glow" }, 30)
	scatter(rng, Zones.ById.Europa, { "Rock_Ice1", "Rock_Ice2", "Crystal_Ice", "Crystal_Ice" }, 30)
	hubDecor(rng)

	for i = 1, World.BaseCount do
		MapBuilder.buildBase(i)
	end
end

return MapBuilder
