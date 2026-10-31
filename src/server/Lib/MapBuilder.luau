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
local BaseSkins = require(Shared.Config.BaseSkins)
local Eggs = require(Shared.Config.Eggs)
local Items = require(Shared.Config.Items)
local Rewards = require(Shared.Config.Rewards)
local SkyLooks = require(Shared.Config.SkyLooks)
local World = require(Shared.Config.World)
local ZoneDecor = require(Shared.Config.ZoneDecor)
local Zones = require(Shared.Config.Zones)

local MapBuilder = {}

local M = Enum.Material
local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local INK = Color3.fromRGB(27, 31, 58)
local WHITE = Color3.new(1, 1, 1)

-- Terrain ------------------------------------------------------------------------

-- Smooth terrain is 4-stud voxels: a FillBlock whose top is at y renders (and collides)
-- the ground at y + 2. Checked on a live server, so every surface below is filled 2 lower.
local LIFT = 2

-- The cliff walls around the map (buildProps, Cliff_* pieces), as lines of the front row.
local HUB_X = World.BaseInner + World.BaseSize.Y + 2 -- outer edge of the bases
local HUB_WALL = HUB_X + 23 -- hub sides
local HUB_BACK = 236 -- behind the plaza
local ZONE_WALL = 160 -- zone sides
local ZONE_BACK = Zones.List[#Zones.List].Min.Y - 36 -- behind the last zone

-- Where a corridor's ramp sits: z0..z1, snapped out to the 4-stud terrain grid so the
-- carved cut and the ramp part line up exactly (an off-grid cut left a slot at the top).
local function rampSpan(c): (number, number, boolean)
	local mid = (c.Min.Y + c.Max.Y) / 2
	local highAtMaxZ = c.FromY > c.ToY -- the high end is away from the lower zone
	if highAtMaxZ then
		return c.Min.Y, math.ceil(mid / 4) * 4, true
	end
	return math.floor(mid / 4) * 4, c.Max.Y, false
end

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

local function rect(terrain: Terrain, x0: number, z0: number, x1: number, z1: number, surfaceY: number, material: Enum.Material, depth: number?)
	slab(terrain, CFrame.new((x0 + x1) / 2, 0, (z0 + z1) / 2), math.abs(x1 - x0), math.abs(z1 - z0), surfaceY, material, depth)
end

-- The ground stops a little past the front of the cliff walls, under their back row, so
-- it never runs on to the horizon (Dev, 2026-10-29). Hub and zones are two boxes.
local EDGE = 24
local GROUND_BOXES = {
	{ -(HUB_WALL + EDGE), -232, HUB_WALL + EDGE, HUB_BACK + EDGE },
	{ -(ZONE_WALL + EDGE), ZONE_BACK - EDGE, ZONE_WALL + EDGE, -214 },
}

-- rect, cut to the ground boxes.
local function ground(terrain: Terrain, x0: number, z0: number, x1: number, z1: number, surfaceY: number, material: Enum.Material, depth: number?)
	for _, b in GROUND_BOXES do
		local ax0, az0 = math.max(math.min(x0, x1), b[1]), math.max(math.min(z0, z1), b[2])
		local ax1, az1 = math.min(math.max(x0, x1), b[3]), math.min(math.max(z0, z1), b[4])
		if ax1 > ax0 and az1 > az0 then
			rect(terrain, ax0, az0, ax1, az1, surfaceY, material, depth)
		end
	end
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
	-- Grass everywhere (surface y = 0), with a ground band per zone.
	ground(terrain, -500, -1340, 500, 520, 0, M.Grass, 36)
	ground(terrain, -500, -1340, 500, -976, 0, M.Snow) -- Snowy Peaks
	ground(terrain, -500, -976, 500, -720, 0, M.Asphalt) -- City band
	ground(terrain, -500, -720, 500, -472, 0, M.Sand) -- Beach band
	ground(terrain, -500, -472, 500, -212, 0, M.LeafyGrass) -- Park band

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
			-- The ramp half sits on the low side (next to the crater).
			local z0, z1 = rampSpan(c)
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
	-- The walls around everything are Cliff_* models (buildProps), not terrain.
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

-- The default clear-day look (Config/SkyLooks). Clients fade to their zone's look on top.
function MapBuilder.setupLighting()
	local look = SkyLooks.ById[SkyLooks.Default]
	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 35
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	local function set(target: Instance, props: { [string]: any })
		local anyTarget = target :: any
		for prop, value in props do
			anyTarget[prop] = value
		end
	end
	set(Lighting, look.Lighting)
	set(effect("Atmosphere", "WorldAtmosphere"), look.Atmosphere)
	set(effect("BloomEffect", "WorldBloom"), look.Bloom)
	set(effect("ColorCorrectionEffect", "WorldGrade"), look.Grade)
	set(effect("SunRaysEffect", "WorldSunRays"), look.SunRays)
	set(effect("Sky", "WorldSky"), SkyLooks.skyProps(look, AssetLibrary.image))

	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	set(clouds, look.Clouds)
	-- Roblox's own clouds stay off: the sky has drifting cartoon cloud meshes instead
	-- (WeatherController). The object stays so the weather presets have its colour.
	clouds.Enabled = false
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
	-- A round cobblestone plaza with a wooden rim under the market hall.
	block(model, "Pad", Vector3.new(1, r * 2, r * 2), CFrame.new(center) * up, Color3.fromRGB(200, 192, 178), M.Cobblestone)
	block(model, "Rim", Vector3.new(0.8, r * 2 + 2, r * 2 + 2), CFrame.new(center + Vector3.new(0, -0.15, 0)) * up, WOOD_DARK, M.Wood)
end

-- Leaf dumps beside the market hall: a green shredder bin with a yellow hopper on top, two
-- rollers inside (spun by DumpController while someone dumps), a leaf pile that rises, a
-- coin slot at the front and a round standing spot in front of it. Front = -Z (the field).
local DUMP_GREEN = Color3.fromRGB(74, 164, 82)
local DUMP_DARK = Color3.fromRGB(44, 112, 56)
local DUMP_YELLOW = Color3.fromRGB(255, 200, 60)
local STEEL = Color3.fromRGB(150, 156, 168)

local function leafDump(index: number, cf: CFrame)
	local model = make("Model", { Name = "LeafDump" .. index }, structures)
	local deco = { CanCollide = false, CanQuery = false, CanTouch = false }
	local up = CFrame.Angles(0, 0, math.rad(90))
	-- Bin.
	block(model, "Plinth", Vector3.new(9, 0.6, 8), cf * CFrame.new(0, 0.3, 0), Color3.fromRGB(120, 124, 132), M.Concrete)
	block(model, "Body", Vector3.new(8, 4, 7), cf * CFrame.new(0, 2.6, 0), DUMP_GREEN)
	for _, y in { 1.3, 4.1 } do
		block(model, "Band", Vector3.new(8.2, 0.35, 7.2), cf * CFrame.new(0, y, 0), DUMP_DARK, nil, deco)
	end
	-- Hopper rim (open on top) with the pit inside.
	local rimY = 5.4
	block(model, "RimFront", Vector3.new(9, 1.6, 0.5), cf * CFrame.new(0, rimY, -3.75), DUMP_YELLOW)
	block(model, "RimBack", Vector3.new(9, 1.6, 0.5), cf * CFrame.new(0, rimY, 3.75), DUMP_YELLOW)
	block(model, "RimLeft", Vector3.new(0.5, 1.6, 7), cf * CFrame.new(-4.25, rimY, 0), DUMP_YELLOW)
	block(model, "RimRight", Vector3.new(0.5, 1.6, 7), cf * CFrame.new(4.25, rimY, 0), DUMP_YELLOW)
	block(model, "Pit", Vector3.new(8, 0.2, 7), cf * CFrame.new(0, 4.7, 0), Color3.fromRGB(58, 40, 30), nil, deco)
	for i, z in { -1.3, 1.3 } do
		local roller = block(model, "Roller" .. i, Vector3.new(7.6, 1.2, 1.2), cf * CFrame.new(0, 5.0, z), STEEL, M.DiamondPlate, deco)
		roller.Shape = Enum.PartType.Cylinder
	end
	-- The leaf pile (DumpController raises it while leaves pour in).
	block(model, "Pile", Vector3.new(7.4, 0.1, 6.4), cf * CFrame.new(0, 4.85, 0), WHITE, nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	-- Where the leaves fly in, and where coins come out (front, toward the player).
	make("Attachment", { Name = "Mouth", CFrame = CFrame.new(0, 3.2, 0) }, model:FindFirstChild("Body"))
	local slot = block(model, "CoinSlot", Vector3.new(3, 0.6, 0.2), cf * CFrame.new(0, 3, -3.55), Color3.fromRGB(30, 34, 40), nil, deco)
	make("Attachment", { Name = "CoinOut", CFrame = CFrame.new(0, 0, -0.3) }, slot)
	-- Sign above the back of the hopper, facing the field.
	for _, x in { -3.8, 3.8 } do
		block(model, "SignPost", Vector3.new(0.6, 9.6, 0.6), cf * CFrame.new(x, 4.8, 4.3), WOOD_DARK, M.Wood)
	end
	sign(model, "DumpSign", cf * CFrame.new(0, 8.6, 4.3), 9, 2.4, DUMP_YELLOW, "DUMP TRASH", "Stand on the circle")
	-- Standing spot: a ring with a lighter floor, flush with the ground (cars drive over it).
	local spot = World.dumpSpot(index)
	local r = World.DumpRadius
	glow(model, "SpotRing", Vector3.new(0.14, r * 2 + 1, r * 2 + 1), CFrame.new(spot + Vector3.new(0, 0.08, 0)) * up, DUMP_YELLOW)
	block(model, "Spot", Vector3.new(0.16, r * 2 - 0.4, r * 2 - 0.4), CFrame.new(spot + Vector3.new(0, 0.1, 0)) * up, Color3.fromRGB(236, 226, 196), M.Concrete, deco)
	floorText(model, CFrame.lookAt(spot, Vector3.new(cf.Position.X, spot.Y, cf.Position.Z)) * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, math.rad(90), 0), r * 1.3, 3.2, "DUMP", DUMP_DARK)
	model.PrimaryPart = model:FindFirstChild("Body") :: BasePart
end

local function leafDumps()
	for i, cf in World.Dumps do
		leafDump(i, cf)
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

-- Market stall frame (Pet Trader and Quest Master): four posts, a beam along each side
-- from the front post to the back post, and an 8-stripe awning resting on the beams. The
-- awning tilts down toward the customer (-Z) and ends at the posts, so nothing pokes out
-- the back, and every post reaches the beam above it (Dev, 2026-10-31). cf = where the
-- NPC stands, facing -Z.
local STALL_TILT = math.rad(-8)
local STALL_FRONT, STALL_BACK = -3.4, 1.8 -- post rows (z)
local STALL_MID = (STALL_FRONT + STALL_BACK) / 2
local STALL_DEPTH = STALL_BACK - STALL_FRONT + 0.5 -- to the posts' outer faces
local AWNING_Y = 8.3 -- awning centre (y) at STALL_MID

-- Height of the awning's top face (relative to cf) at depth z.
local function awningTop(z: number): number
	return AWNING_Y + 0.125 - (z - STALL_MID) * math.sin(STALL_TILT)
end

local function stallFrame(model: Instance, cf: CFrame, stripeA: Color3, stripeB: Color3)
	local tilt = CFrame.Angles(STALL_TILT, 0, 0)
	local beamY = AWNING_Y - 0.125 - 0.2 -- beam centre, right under the awning
	for _, x in { -3.6, 3.6 } do
		block(model, "Beam", Vector3.new(0.5, 0.4, STALL_DEPTH), cf * CFrame.new(x, beamY, STALL_MID) * tilt, WOOD_DARK, M.Wood)
		for _, z in { STALL_FRONT, STALL_BACK } do
			-- Up to the middle of the beam above (it's higher at the back).
			local top = beamY - (z - STALL_MID) * math.sin(STALL_TILT)
			block(model, "Post", Vector3.new(0.5, top, 0.5), cf * CFrame.new(x, top / 2, z), WOOD_DARK, M.Wood)
		end
	end
	for k = 0, 7 do
		block(model, "Awning", Vector3.new(1, 0.25, STALL_DEPTH), cf * CFrame.new(-3.5 + k, AWNING_Y, STALL_MID) * tilt,
			if k % 2 == 0 then stripeA else stripeB, nil, { CanCollide = false })
	end
end

-- Two legs behind a stall's sign, standing on the awning (not hanging under it).
local function stallSignLegs(model: Instance, cf: CFrame)
	local z = 0.12 -- touching the back of the sign board
	local bottom = awningTop(z) - 0.05
	local top = 10.6
	for _, x in { -2.8, 2.8 } do
		block(model, "SignLeg", Vector3.new(0.45, top - bottom, 0.45), cf * CFrame.new(x, (top + bottom) / 2, z), WOOD_DARK, M.Wood,
			{ CanCollide = false })
	end
end

-- The Pet Trader's market stall (the NPC itself is TraderService's): a counter in front,
-- four posts with a green and white striped awning, and a sign on top. cf = where the NPC
-- stands, facing the customer (-Z).
local function traderStall(parent: Instance, cf: CFrame)
	local model = make("Model", { Name = "TraderStall" }, parent)
	local green = Color3.fromRGB(74, 164, 82)
	block(model, "Counter", Vector3.new(7, 3, 1.8), cf * CFrame.new(0, 1.5, -2.4), WOOD, M.WoodPlanks)
	block(model, "CounterTop", Vector3.new(7.6, 0.3, 2.3), cf * CFrame.new(0, 3.15, -2.4), green)
	stallFrame(model, cf, green, WHITE)
	-- The sign sits on the awning with two wooden legs behind it, so from the base side (its
	-- blank back) it reads as part of the stall, not a board floating in the air (Dev,
	-- 2026-10-31).
	sign(model, "TraderSign", cf * CFrame.new(0, 9.75, -0.4), 8, 2.2, Color3.fromRGB(255, 200, 60), "PET TRADER", "Sell your pets")
	stallSignLegs(model, cf)
end

-- The Quest Master's stall on the left of every base (the NPC is QuestService's): the
-- trader's stall shape with a blue and yellow awning, a notice board full of job notes
-- behind him and a rolled scroll on the counter. cf = where he stands, facing -Z.
local function questStall(parent: Instance, cf: CFrame)
	local model = make("Model", { Name = "QuestStall" }, parent)
	local blue = Color3.fromRGB(47, 130, 230)
	local yellow = Color3.fromRGB(255, 200, 60)
	local paper = Color3.fromRGB(250, 240, 210)
	block(model, "Counter", Vector3.new(7, 3, 1.8), cf * CFrame.new(0, 1.5, -2.4), WOOD, M.WoodPlanks)
	block(model, "CounterTop", Vector3.new(7.6, 0.3, 2.3), cf * CFrame.new(0, 3.15, -2.4), blue)
	stallFrame(model, cf, blue, yellow)
	-- Like the trader's: the sign rests on the awning with two legs, not floating.
	sign(model, "QuestSign", cf * CFrame.new(0, 9.75, -0.4), 8, 2.2, Color3.fromRGB(110, 190, 255), "QUESTS", "Jobs and rewards")
	stallSignLegs(model, cf)
	-- Notice board behind him, pinned with job notes.
	local boardCf = cf * CFrame.new(0, 4.6, 1.9)
	block(model, "Board", Vector3.new(6.7, 3.6, 0.3), boardCf, Color3.fromRGB(176, 120, 72), M.Wood, { CanCollide = false })
	for i, at in { Vector2.new(-2.2, 0.8), Vector2.new(-0.6, 0.6), Vector2.new(1.2, 0.9), Vector2.new(-1.5, -0.8), Vector2.new(0.6, -0.7), Vector2.new(2.3, -0.6) } do
		local tilt = CFrame.Angles(0, 0, math.rad(((i * 37) % 17) - 8))
		block(model, "Note", Vector3.new(1.2, 1.4, 0.06), boardCf * CFrame.new(at.X, at.Y, -0.18) * tilt, paper, M.SmoothPlastic, { CanCollide = false })
		block(model, "Pin", Vector3.new(0.18, 0.18, 0.1), boardCf * CFrame.new(at.X, at.Y + 0.55, -0.24), if i % 2 == 0 then blue else Color3.fromRGB(255, 77, 94), M.SmoothPlastic, { CanCollide = false })
	end
	-- A rolled scroll on the counter.
	local scroll = block(model, "Scroll", Vector3.new(2.2, 0.5, 0.5), cf * CFrame.new(-1.6, 3.55, -2.4) * CFrame.Angles(0, math.rad(20), 0), paper, M.SmoothPlastic, { CanCollide = false })
	scroll.Shape = Enum.PartType.Cylinder
	block(model, "Ribbon", Vector3.new(0.2, 0.56, 0.56), cf * CFrame.new(-1.6, 3.55, -2.4) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(255, 77, 94), M.SmoothPlastic, { CanCollide = false })
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
	traderStall(model, World.traderCFrame(index))
	questStall(model, World.questCFrame(index))
	-- name sign above the arch, facing the field
	local arch = World.Base.Arch
	local s = sign(model, "NameSign", cf * CFrame.new(arch + Vector3.new(0, 15.4, 0)), 19, 4.6, color, "Free Base", "Claim it by joining!", true)
	baseSigns[index] = s
	-- "Change Base" sign by the entrance (BasePickerController opens the picker, owner only).
	-- The model's name ends in "Sign" so it stays visible under every skin.
	local skinSign = make("Model", { Name = "SkinSign" }, model)
	local at = cf * CFrame.new(World.Base.SkinSign)
	-- Two slim posts behind the board, from the floor up to its top edge, on small feet
	-- (Dev: posts poking out under the board looked odd).
	for _, x in { -2.4, 2.4 } do
		block(skinSign, "Post", Vector3.new(0.5, 7.1, 0.5), at * CFrame.new(x, 3.55, 0.65), WOOD_DARK, M.Wood)
		block(skinSign, "Foot", Vector3.new(1.1, 0.3, 1.1), at * CFrame.new(x, 0.15, 0.65), WOOD_DARK, M.Wood)
	end
	local board = sign(skinSign, "BoardSign", at * CFrame.new(0, 5.6, 0), 7, 3, color, "CHANGE BASE", "Try on base skins").Board
	prompt(board, "BasePicker", "Change Base", "Base Skins")
	local basePrompt = board:FindFirstChild("BasePickerPrompt")
	if basePrompt then
		basePrompt:SetAttribute("Base", index)
	end
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

-- Big screen on the south wall with the game logo.
local function plazaScreen()
	local model = make("Model", { Name = "PlazaScreen" }, structures)
	local cf = CFrame.lookAt(Vector3.new(0, 0, 194), Vector3.new(0, 0, 0))
	-- Raised so the middle leaderboard stand fits under it (2026-10-30).
	for _, x in { -15, 15 } do
		block(model, "Leg", Vector3.new(1.4, 16, 1.4), cf * CFrame.new(x, 8, 0.8), WOOD_DARK, M.Wood)
	end
	local screen = block(model, "Screen", Vector3.new(34, 14, 1), cf * CFrame.new(0, 22, 0), INK)
	glow(model, "Frame", Vector3.new(35, 15, 0.6), cf * CFrame.new(0, 22, 0.3), WOOD_DARK)
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

-- Lucky Wheel stand (World.Wheel, front = -Z toward the field): a 15-stud wheel on two wooden
-- posts with the same face, prizes and pointer as the wheel window, a sign on top and the
-- prompt that opens the window. The face turns slowly on each client (SpinController).
local function luckyWheel()
	local cf = World.Wheel
	local model = make("Model", { Name = "LuckyWheel" }, structures)
	local blue = Color3.fromRGB(76, 141, 255)
	local axle = cf * CFrame.new(0, 8.4, 0)
	local plinth = block(model, "Plinth", Vector3.new(12, 0.8, 4.4), cf * CFrame.new(0, 0.4, 0.4), WOOD, M.WoodPlanks)
	for _, x in { -4.5, 4.5 } do
		block(model, "Post", Vector3.new(1.2, 8, 1.2), cf * CFrame.new(x, 4.4, 1.4), WOOD_DARK, M.Wood)
	end
	block(model, "Axle", Vector3.new(10.2, 0.9, 0.9), axle * CFrame.new(0, 0, 1.4), WOOD_DARK, M.Wood)
	-- Back disc (cylinder axis turned to face the field) and a dark rim behind the face.
	make("Part", {
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 15.4, 15.4),
		CFrame = axle * CFrame.new(0, 0, 0.5) * CFrame.Angles(0, math.rad(90), 0),
		Color = INK,
		Material = M.SmoothPlastic,
		Anchored = true,
	}, model)
	local face = block(model, "Face", Vector3.new(15, 15, 0.1), axle * CFrame.new(0, 0, 0), WHITE, nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local gui = make("SurfaceGui", {
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 32,
		LightInfluence = 0.2,
		MaxDistance = 400,
	}, face)
	make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = AssetLibrary.image("SpinWheel") }, gui)
	for i, seg in Rewards.Wheel.Segments do
		local reward = seg.Reward
		local image, tint = "Icon_Gift", WHITE
		if reward.Kind == "Cash" then
			image = "Icon_Cash"
		elseif reward.Kind == "Item" then
			local item = Items.ById[reward.Item or ""]
			image = if item then item.Icon else image
		elseif reward.Kind == "Egg" then
			local rarity = Eggs.ByName[reward.Rarity or "Common"]
			image, tint = "Icon_Egg", if rarity then rarity.Color else WHITE
		end
		local a = math.rad((i - 0.5) * 45)
		make("ImageLabel", {
			Name = "Seg" .. i,
			Size = UDim2.fromScale(0.17, 0.17),
			Position = UDim2.fromScale(0.5 + math.sin(a) * 0.3, 0.5 - math.cos(a) * 0.3),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = (i - 0.5) * 45,
			BackgroundTransparency = 1,
			Image = AssetLibrary.image(image),
			ImageColor3 = tint,
		}, gui)
	end
	face:SetAttribute("SpinHub", face.CFrame)
	face:SetAttribute("SpinBase", face.CFrame)
	face:SetAttribute("SpinSpeed", 0.06 * math.pi * 2)
	face:AddTag("SpinPart")
	-- Pointer over the top of the wheel (doesn't turn).
	local pointer = block(model, "Pointer", Vector3.new(3, 3, 0.1), axle * CFrame.new(0, 7.5, -0.3), WHITE, nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local pgui = make("SurfaceGui", { Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 32, LightInfluence = 0.2 }, pointer)
	make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = AssetLibrary.image("SpinPointer") }, pgui)
	-- Name board low on the front of the stand (the big screen is right above the wheel).
	sign(model, "WheelSign", cf * CFrame.new(0, 1.3, -2.1), 9, 1.8, blue, "LUCKY WHEEL", "Eggs, potions and cash!")
	local lamp = glow(model, "WheelLight", Vector3.new(0.2, 0.2, 0.2), axle * CFrame.new(0, 0, -5), WHITE)
	lamp.Transparency = 1
	light(lamp, Color3.fromRGB(255, 230, 170), 26, 1.2)
	prompt(plinth, "Wheel", "Spin", "Lucky Wheel")
end

-- Traveling Merchant cart (World.Merchant, front = -Z toward the field): a wooden wagon with
-- big wheels, a striped canopy, a counter and a name board. MerchantService puts the
-- merchant and his goods in "Goods" while he's visiting and turns the prompt on.
local function merchantCart()
	local cf = World.Merchant
	local model = make("Model", { Name = "MerchantCart" }, structures)
	-- Cobblestone path from the market hall's round pad out under the cart, same height and
	-- look as the pad (top at y 0.5), so the cart stands on paving joined to the hall.
	local path = World.MerchantPath
	local x = cf.Position.X
	block(model, "Path", Vector3.new(path.Width, 1, path.FromZ - path.ToZ), CFrame.new(x, -0.02, (path.FromZ + path.ToZ) / 2), Color3.fromRGB(200, 192, 178), M.Cobblestone)
	block(model, "PathRim", Vector3.new(path.Width + 2, 0.8, path.FromZ - path.ToZ + 1), CFrame.new(x, -0.15, (path.FromZ + path.ToZ) / 2 - 0.5), WOOD_DARK, M.Wood)
	local red = Color3.fromRGB(230, 70, 70)
	local cream = Color3.fromRGB(255, 240, 210)
	block(model, "Bed", Vector3.new(9, 0.8, 4.6), cf * CFrame.new(0, 1.9, 0.6), WOOD, M.WoodPlanks)
	block(model, "Back", Vector3.new(9, 2.4, 0.5), cf * CFrame.new(0, 3.5, 2.65), WOOD_DARK, M.Wood)
	for _, x in { -4.6, 4.6 } do
		make("Part", {
			Name = "Wheel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 3.4, 3.4),
			CFrame = cf * CFrame.new(x, 1.7, 0.6),
			Color = WOOD_DARK,
			Material = M.Wood,
		}, model)
		for _, z in { -1.4, 2.6 } do
			block(model, "Post", Vector3.new(0.5, 6, 0.5), cf * CFrame.new(x * 0.93, 5.3, z), WOOD_DARK, M.Wood)
		end
	end
	-- Striped canopy: alternating red and cream slats.
	for i = 0, 7 do
		local x = -4.5 + 0.5625 + i * 1.125
		block(model, "Canopy", Vector3.new(1.125, 0.3, 5.4), cf * CFrame.new(x, 8.45, 0.6) * CFrame.Angles(math.rad(-8), 0, 0),
			if i % 2 == 0 then red else cream, M.Fabric)
	end
	local counter = block(model, "Counter", Vector3.new(8, 1.2, 1.2), cf * CFrame.new(0, 2.9, -1.2), WOOD, M.WoodPlanks)
	block(model, "Pole", Vector3.new(0.3, 3, 0.3), cf * CFrame.new(-5.6, 1.5, -2.4) * CFrame.Angles(0, 0, math.rad(-20)), WOOD_DARK, M.Wood)
	sign(model, "MerchantSign", cf * CFrame.new(0, 7.2, -1.6), 7.5, 1.6, red, "TRAVELING MERCHANT", "Rare items, rare eggs!")
	local lamp = glow(model, "MerchantLight", Vector3.new(0.3, 0.3, 0.3), cf * CFrame.new(0, 7.8, 0.6), LANTERN)
	light(lamp, LANTERN, 18, 1.2)
	make("Folder", { Name = "Goods" }, model)
	local p = make("ProximityPrompt", {
		Name = "MerchantPrompt",
		ActionText = "Shop",
		ObjectText = "Traveling Merchant",
		HoldDuration = 0,
		MaxActivationDistance = 14,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.E,
		Enabled = false,
	}, counter)
	p:SetAttribute("Opens", "Merchant")
end

-- Ramps where a corridor changes height (terrain under them is carved by buildTerrain).
local function corridorRamps()
	local model = make("Model", { Name = "Ramps" }, structures)
	for _, c in World.Corridors do
		if c.FromY == c.ToY then
			continue
		end
		local low, high = math.min(c.FromY, c.ToY), math.max(c.FromY, c.ToY)
		-- Same z range as the cut in the terrain; highAtMaxZ: which end is high.
		local z0, z1, highAtMaxZ = rampSpan(c)
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
		-- A flat landing over the top edge: smooth terrain rounds off where it was cut, so
		-- without it there's a dip between the path and the ramp.
		local topZ = if highAtMaxZ then z1 else z0
		local out = if highAtMaxZ then 1 else -1
		make("Part", {
			Name = "Landing",
			Size = Vector3.new(c.Max.X - c.Min.X + 6, 2, 8),
			CFrame = CFrame.new(0, high - 0.95, topZ + out * 3.5),
			Color = World.TerrainColors.Pavement,
			Material = M.Concrete,
		}, model)
		for _, x in { c.Min.X, c.Max.X } do
			glow(model, "RampEdge", Vector3.new(0.3, 0.2, math.sqrt(length ^ 2 + (high - low) ^ 2)), CFrame.new(x, (low + high) / 2 + 0.1, (z0 + z1) / 2) * rot * CFrame.Angles(-math.atan2(high - low, length), 0, 0), WOOD_DARK)
		end
	end
end

-- Global leaderboards (Dev, 2026-10-30): one stand per board on the paved strip in front of
-- the "Sweep the World" screen, facing the field (World.Leaderboards X). Each stand: two
-- posts, the board, a coloured roof and feet. LeaderboardService fills the "Rows" frame
-- of each board part "Board_<Key>".
local function leaderboards()
	local model = make("Model", { Name = "Leaderboards" }, structures)
	local w, h, bottom = 13, 11, 1.6
	for _, board in World.Leaderboards do
		local pos = Vector3.new(board.X, 0, World.LeaderboardZ)
		local cf = CFrame.lookAt(pos, pos - Vector3.new(0, 0, 1))
		local stand = make("Model", { Name = "Stand_" .. board.Key }, model)
		for _, x in { -w / 2 - 0.3, w / 2 + 0.3 } do
			block(stand, "Post", Vector3.new(0.8, bottom + h + 0.8, 0.8), cf * CFrame.new(x, (bottom + h + 0.8) / 2, 0.2), WOOD_DARK, M.Wood)
			block(stand, "Foot", Vector3.new(1.6, 0.4, 1.6), cf * CFrame.new(x, 0.2, 0.2), WOOD_DARK, M.Wood)
		end
		block(stand, "Roof", Vector3.new(w + 2.4, 0.8, 2.2), cf * CFrame.new(0, bottom + h + 1.2, 0.1), board.Color, M.SmoothPlastic)
		local part = block(stand, "Board_" .. board.Key, Vector3.new(w, h, 0.6), cf * CFrame.new(0, bottom + h / 2, 0), INK)
		block(part, "Trim", Vector3.new(w + 0.5, h + 0.5, 0.4), cf * CFrame.new(0, bottom + h / 2, 0.15), board.Color, M.SmoothPlastic, { CanCollide = false, CanQuery = false, CanTouch = false })
		local gui = make("SurfaceGui", {
			Name = "BoardGui",
			Face = Enum.NormalId.Front,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 40,
			LightInfluence = 0,
			Brightness = 1.3,
			MaxDistance = 260,
		}, part)
		local header = make("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = board.Color, BorderSizePixel = 0 }, gui)
		local title = make("TextLabel", {
			Size = UDim2.new(1, -20, 1, -12),
			Position = UDim2.fromOffset(10, 6),
			BackgroundTransparency = 1,
			Text = board.Title,
			TextScaled = true,
			TextColor3 = WHITE,
			FontFace = Font.new(MONTSERRAT, Enum.FontWeight.Heavy),
		}, header)
		make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3, Transparency = 0.2 }, title)
		local rows = make("Frame", { Name = "Rows", Size = UDim2.new(1, -20, 1, -82), Position = UDim2.fromOffset(10, 76), BackgroundTransparency = 1 }, gui)
		make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, rows)
	end
end

-- Everything above, plus base platforms. Needs only images (no models), so it runs at boot.
function MapBuilder.buildStructures()
	structures = Instance.new("Folder")
	structures.Name = "Structures"
	structures.Parent = Workspace
	launchPad()
	leafDumps()
	fieldEdges()
	corridorRamps()
	plazaScreen()
	luckyWheel()
	leaderboards()
	merchantCart()
	for i = 1, World.BaseCount do
		MapBuilder.buildBaseStructure(i)
	end
end

-- Props --------------------------------------------------------------------------

local propsFolder: Folder
local skinOf: { [number]: string } = {} -- base index -> skin id (Config/BaseSkins)

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
	if name == "Park_Fountain" then
		model:AddTag("Fountain") -- FountainController (client) adds the moving water
	else
		-- ParkFxController (client) plays swaying/spinning parts, critters, smoke, leaves
		local meta = AssetLibrary.meta(name) :: any
		if meta and (meta.anim or meta.fx) then
			model:AddTag("ParkFx")
		end
	end
	return model
end

-- Tags a windmill's "Sails" part for SpinController (client), which turns it about the hub
-- (meta joint) on the model's front axis. speed in turns per second.
local function spinSails(model: Model?, speed: number)
	local sails = model and model:FindFirstChild("Sails") :: BasePart?
	local meta = AssetLibrary.meta("Satellite")
	local joint = meta and meta.parts.Sails and meta.parts.Sails.joint
	if not model or not sails or not joint then
		return
	end
	local hub = model:GetPivot() * CFrame.new(joint * model:GetScale())
	sails:SetAttribute("SpinHub", hub)
	sails:SetAttribute("SpinBase", sails.CFrame)
	sails:SetAttribute("SpinSpeed", speed * math.pi * 2)
	sails:AddTag("SpinPart")
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
		place("Base_Fence", baseCf * CFrame.new(mid.X, 0, mid.Y) * CFrame.Angles(0, angle, 0), scale, parent)
	end
end

function MapBuilder.buildBase(index: number): Model
	local baseCf = World.baseCFrame(index)
	local model = Instance.new("Model")
	model.Name = "BaseProps" .. index
	local B = World.Base
	place("Base_Arch", baseCf * CFrame.new(B.Arch), 1, model)
	place("Base_Hatchery", baseCf * CFrame.new(B.Hatchery), 1, model)
	for _, p in B.Incubators do
		place("Base_Incubator", baseCf * CFrame.new(p), 1, model)
	end
	for _, p in B.Lamps do
		place("Base_Lamp", baseCf * CFrame.new(p) * yaw(180), 1, model)
	end
	-- park fence with a gate gap at the front
	local mn, mx, gap = B.ParkMin, B.ParkMax, B.ParkGateWidth / 2
	fenceLine(baseCf, Vector2.new(mn.X, mn.Y), Vector2.new(-gap, mn.Y), model)
	fenceLine(baseCf, Vector2.new(gap, mn.Y), Vector2.new(mx.X, mn.Y), model)
	fenceLine(baseCf, Vector2.new(mx.X, mn.Y), Vector2.new(mx.X, mx.Y), model)
	fenceLine(baseCf, Vector2.new(mx.X, mx.Y), Vector2.new(mn.X, mx.Y), model)
	fenceLine(baseCf, Vector2.new(mn.X, mx.Y), Vector2.new(mn.X, mn.Y), model)
	for _, prop in B.ParkProps do
		place(prop.Asset, baseCf * CFrame.new(prop.Position) * yaw(prop.Yaw), prop.Scale, model)
	end
	model.Parent = propsFolder
	if skinOf[index] and skinOf[index] ~= BaseSkins.Default then
		MapBuilder.applySkin(index, skinOf[index])
	end
	return model
end

-- Bins, dumpster, hydrant, bench, beach umbrella.
local FIXED_SIZE = { City_Bin = true, City_Dumpster = true, City_Hydrant = true, City_Bench = true, Beach_Umbrella = true }

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

local CLIFFS = { "Cliff_1", "Cliff_2", "Cliff_3", "Cliff_4" }
local BOULDERS = { "Boulder_1", "Boulder_2", "Boulder_3", "Boulder_1", "Boulder_3" }

-- A row of cliff pieces from a to b (x, z), stepped front facing inward. Pieces overlap a
-- little (their turf tops run past the ends), so the wall has no gaps. scale > 1 makes a
-- taller back row.
local function cliffRow(rng: Random, a: Vector2, b: Vector2, inward: Vector2, scale: number)
	-- Cliff_* pieces are 24 long with the same profile at both ends, so they join edge to
	-- edge into one wall: space them exactly one piece apart (scaled to fit the row), all
	-- the same size and facing, so the joins line up.
	local dir = (b - a).Unit
	local length = (b - a).Magnitude
	local count = math.max(1, math.round(length / (24 * scale)))
	local s = length / (count * 24)
	local face = Vector3.new(inward.X, 0, inward.Y)
	local last = ""
	for k = 0, count - 1 do
		local p = a + dir * (length * (k + 0.5) / count)
		local name = CLIFFS[rng:NextInteger(1, #CLIFFS)]
		if name == last then
			name = CLIFFS[(table.find(CLIFFS, name) :: number) % #CLIFFS + 1]
		end
		last = name
		local pos = Vector3.new(p.X, 0, p.Y)
		place(name, CFrame.lookAt(pos, pos + face), s)
	end
end

-- Boulders from a to b, rotated freely; spacing keeps them touching.
local function boulderRow(rng: Random, a: Vector2, b: Vector2, spread: number)
	local dir = (b - a).Unit
	local side = Vector2.new(-dir.Y, dir.X)
	local length = (b - a).Magnitude
	local d = 0
	while d <= length do
		local name = BOULDERS[rng:NextInteger(1, #BOULDERS)]
		local meta = AssetLibrary.meta(name)
		local width = if meta then meta.bounds.max.X - meta.bounds.min.X else 8
		local scale = rng:NextNumber(0.9, 1.4)
		local p = a + dir * d + side * rng:NextNumber(-spread, spread)
		place(name, CFrame.new(p.X, 0, p.Y) * yaw(rng:NextNumber(0, 360)), scale)
		d += width * scale * 0.6
	end
end

-- Cliff walls round the hub and the zones (two rows: the back one bigger, so the edge
-- reads as a tall cliff), boulders at their foot and along the ridges between zones.
local function rockWalls(rng: Random)
	local hx, zx = HUB_WALL, ZONE_WALL
	local BACK = 15 -- back row this far behind the front row
	for _, side in { -1, 1 } do
		local inward = Vector2.new(-side, 0)
		local out = side * BACK
		cliffRow(rng, Vector2.new(side * hx, HUB_BACK), Vector2.new(side * hx, -214), inward, 1)
		cliffRow(rng, Vector2.new(side * (hx + BACK), HUB_BACK + BACK), Vector2.new(side * (hx + BACK), -214), inward, 1.7)
		cliffRow(rng, Vector2.new(side * hx, -214), Vector2.new(side * zx, -232), inward, 1)
		cliffRow(rng, Vector2.new(side * (hx + BACK), -214), Vector2.new(side * (zx + BACK), -232), inward, 1.7)
		cliffRow(rng, Vector2.new(side * zx, -232), Vector2.new(side * zx, ZONE_BACK), inward, 1)
		cliffRow(rng, Vector2.new(side * zx + out, -232), Vector2.new(side * zx + out, ZONE_BACK - BACK), inward, 1.7)
		-- a few boulders at the foot of the hub walls (clear of the bases)
		boulderRow(rng, Vector2.new(side * (hx - 8), HUB_BACK - 30), Vector2.new(side * (hx - 8), -200), 1.5)
		-- low boulder ridges between zones
		for _, c in World.Corridors do
			local z = (c.Min.Y + c.Max.Y) / 2
			boulderRow(rng, Vector2.new(side * 36, z), Vector2.new(side * (zx - 6), z), 2)
		end
	end
	cliffRow(rng, Vector2.new(-hx, HUB_BACK), Vector2.new(hx, HUB_BACK), Vector2.new(0, -1), 1)
	cliffRow(rng, Vector2.new(-hx - BACK, HUB_BACK + BACK), Vector2.new(hx + BACK, HUB_BACK + BACK), Vector2.new(0, -1), 1.7)
	cliffRow(rng, Vector2.new(-zx, ZONE_BACK), Vector2.new(zx, ZONE_BACK), Vector2.new(0, 1), 1)
	cliffRow(rng, Vector2.new(-zx - BACK, ZONE_BACK - BACK), Vector2.new(zx + BACK, ZONE_BACK - BACK), Vector2.new(0, 1), 1.7)
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
	place("Flag", CFrame.new(-56, 0, 192) * yaw(20))
	place("Flag", CFrame.new(56, 0, 192) * yaw(-20))
	-- Windmills face the hub (front = -Z, sails on that side), and their sails turn.
	for i, x in { -56, 56 } do
		local pos = Vector3.new(x, 0, 194)
		spinSails(place("Satellite", CFrame.lookAt(pos, Vector3.new(0, 0, 0)), 2.8), 0.4 + 0.08 * i)
	end
	-- zone gates (sign faces the hub)
	for _, c in World.Corridors do
		place("ZoneGate", CFrame.new(0, math.max(c.FromY, c.ToY), c.GateZ) * yaw(180))
	end
	scatter(rng, Zones.ById.Crater, { "Park_Rock1", "Park_Rock2", "Park_Bush" }, 30)
	-- Beach (id DarkSide): sandy rocks, palms, umbrellas. City (id Mars): bins, dumpsters,
	-- hydrants, benches. (Prop names are kept from the Moon version.)
	scatter(rng, Zones.ById.DarkSide, { "Beach_Rock1", "Beach_Rock2", "Beach_Palm", "Beach_Umbrella" }, 30)
	scatter(rng, Zones.ById.Mars, { "City_Bin", "City_Dumpster", "City_Hydrant", "City_Bench" }, 30)
	scatter(rng, Zones.ById.Europa, { "Snow_Rock1", "Snow_Rock2", "Snow_Pine", "Snow_Pine" }, 30)
	-- Landmarks inside each zone's leaf field (Config/ZoneDecor; leaves keep clear of them).
	for zoneId, list in ZoneDecor do
		local zone = Zones.ById[zoneId]
		if not zone then
			continue
		end
		local folder = Instance.new("Folder")
		folder.Name = "Decor_" .. zoneId
		folder.Parent = propsFolder
		for _, decor in list do
			local at = Zones.decorPosition(zone, decor.At)
			place(decor.Asset, CFrame.new(at.X, zone.GroundY, at.Y) * yaw(decor.Yaw), decor.Scale, folder)
		end
	end
	rockWalls(rng)

	for i = 1, World.BaseCount do
		MapBuilder.buildBase(i)
	end
end


-- Base skins ---------------------------------------------------------------------
-- A skin (Config/BaseSkins) is one model over the whole base. The classic base stays where
-- it is for every collision but turns invisible; its name sign and the Pet Trader stall
-- stay visible (the stall's awning takes the skin colour).

-- Hidden classic props that keep colliding (the skin draws them in the same place).
local KEEP_COLLIDE = {
	Base_Fence = true,
	Base_Arch = true,
	Base_PetHouse = true,
	Base_Hatchery = true,
	Base_Incubator = true,
	Base_Lamp = true,
}

local function remember(inst: Instance, attr: string, value: any): any
	local saved = inst:GetAttribute(attr)
	if saved == nil then
		inst:SetAttribute(attr, value)
		return value
	end
	return saved
end

local function setClassicVisible(index: number, visible: boolean, accent: Color3?)
	local platform = structures and structures:FindFirstChild("BasePlatform" .. index)
	local props = propsFolder and propsFolder:FindFirstChild("BaseProps" .. index)
	for _, root in { platform, props } do
		if not root then
			continue
		end
		for _, d in root:GetDescendants() do
			-- The Quest Master's stall stays as it is under every skin.
			if d:FindFirstAncestor("QuestStall") or d.Name == "QuestStall" then
				continue
			end
			local stall = d:FindFirstAncestor("TraderStall")
			if stall or d.Name == "TraderStall" then
				if d:IsA("BasePart") and d.Name == "Awning" then
					local original = remember(d, "SkinColor", d.Color)
					if visible or not accent then
						d.Color = original
					elseif original ~= WHITE then
						d.Color = accent
					end
				end
				continue
			end
			local signPart = string.sub(d.Name, -4) == "Sign" or (d.Parent and string.sub(d.Parent.Name, -4) == "Sign")
			if signPart or d:FindFirstAncestorOfClass("SurfaceGui") then
				continue
			end
			if d:IsA("BasePart") then
				local t = remember(d, "SkinT", d.Transparency)
				local shadow = remember(d, "SkinShadow", d.CastShadow)
				d.Transparency = if visible then t else 1
				d.CastShadow = visible and shadow
				if root == props then
					local top: Instance = d
					while top.Parent and top.Parent ~= props do
						top = top.Parent
					end
					if not KEEP_COLLIDE[top.Name] then
						local collide = remember(d, "SkinCollide", d.CanCollide)
						d.CanCollide = visible and collide
					end
				end
			elseif d:IsA("Decal") or d:IsA("Texture") then
				local t = remember(d, "SkinT", d.Transparency)
				d.Transparency = if visible then t else 1
			elseif d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("SurfaceGui") then
				local on = remember(d, "SkinOn", d.Enabled)
				d.Enabled = visible and on
			end
		end
	end
	-- the name sign hangs higher over the taller skin arches
	local s = baseSigns[index]
	if s then
		local lift = 0
		local def = BaseSkins.ById[skinOf[index] or ""]
		if def and not visible then
			lift = def.SignLift
		end
		local base = remember(s.Board, "SkinCFrame", s.Board.CFrame)
		local target = base + Vector3.new(0, lift, 0)
		local delta = target.Position - s.Board.Position
		if delta.Magnitude > 0.001 then
			for _, part in { s.Board :: Instance, table.unpack(s.Board:GetChildren()) } do
				if part:IsA("BasePart") then
					part.CFrame += delta
				end
			end
		end
	end
end

-- Shows skin `skinId` on base `index` ("Classic" = the classic base). Before the props are
-- built it only remembers the choice; buildBase calls it again once they exist.
function MapBuilder.applySkin(index: number, skinId: string)
	local def = BaseSkins.ById[skinId] or BaseSkins.ById[BaseSkins.Default]
	skinOf[index] = def.Id
	if not propsFolder then
		return
	end
	local old = propsFolder:FindFirstChild("BaseSkin" .. index)
	if old then
		old:Destroy()
	end
	local model = if def.Asset then place(def.Asset, World.baseCFrame(index), 1, propsFolder) else nil
	if model then
		model.Name = "BaseSkin" .. index
		model:SetAttribute("Skin", def.Id)
		setClassicVisible(index, false, def.Color)
	else
		-- classic, or the skin's model isn't loaded (offline Studio): show the classic base
		setClassicVisible(index, true)
	end
end

function MapBuilder.getSkin(index: number): string
	return skinOf[index] or BaseSkins.Default
end

-- Runs fn once the Blender props are placed (now if they already are).
function MapBuilder.onPropsReady(fn: () -> ())
	if Workspace:GetAttribute("PropsReady") then
		task.spawn(fn)
		return
	end
	local conn: RBXScriptConnection
	conn = Workspace:GetAttributeChangedSignal("PropsReady"):Connect(function()
		if Workspace:GetAttribute("PropsReady") then
			conn:Disconnect()
			fn()
		end
	end)
end

return MapBuilder
