--!strict
-- Draws the leaf field around you, like Clean all the Leaves: every tile is a clump of
-- separate leaves (or seaweed, paper litter, snow) lying on the grass, turned at random, so
-- the ground reads as a thick carpet. Some tiles hold a piece of trash instead (cans,
-- bottles, pizza boxes...), which pays more (Grid.trashKind, Economy.TrashMult).
--
-- The server only keeps data (DustService). This controller loads a snapshot (GetDust) and
-- follows TilesCleared / TilesRestored / TilesGolden. Only chunks near you are built, from a
-- pool of parts, so phones stay smooth. Feel:
--   * the leaves under your tool wiggle while you sweep (Disturb),
--   * a cleared tile's leaves hop up, swirl and get sucked into the sweeper's tool tip (or
--     the car's brush), shrinking as they go, with a small leaf burst,
--   * grown-back tiles pop in, golden piles shine.
-- Close to you every tile also gets a few real 3D leaves (LeafMeshes) on top of its ground
-- image. Walking or driving through kicks them up and aside, they flutter down and lie where
-- they land; sweeping makes them hop; clearing a tile sends each leaf flying into the
-- nozzle on its own path while the ground image fades. Trash uses the Trash_* meshes.
-- Once the Clump_* meshes load, every tile is a real 3D pile instead of an image (Drift_*
-- heaps pile up against fences and edges). Each tool clears differently: brooms push the
-- leaves along the ground and flick them into your backpack, the leaf blower throws them
-- up and away, vacuums (and cars) suck them into the nozzle. Wind gusts lift leaves now
-- and then, single leaves flutter, and walking through leaves rustles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local LeafMeshes = require(Client.LeafMeshes)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Assets = require(Shared.Config.Assets)
local Grid = require(Shared.Grid)
local Net = require(Shared.Net)
local Sounds = require(Shared.Config.Sounds)

local LeafController = {}

local CHUNK = 8 -- tiles per chunk side
-- Phones draw a smaller circle around you (a few thousand parts at most).
local TOUCH = game:GetService("UserInputService").TouchEnabled
local DRAW_DISTANCE = if TOUCH then 95 else 130 -- studs: chunks closer than this are drawn
local KEEP_DISTANCE = if TOUCH then 125 else 165 -- studs: drawn chunks further than this are put away
local BUILD_BUDGET = 90 -- tiles built per frame at most
local FLY_DISTANCE = 100 -- cleared tiles closer than this fly away, the rest just vanish
local MAX_FLYING = 120
local FLY_TIME = 0.5
local SUCK_RANGE = 45 -- cleared tiles this close to a player get sucked into their tool / car
local GROW_TIME = 0.35
local SHAKE_TIME = 0.25
local TILE_SPREAD = 1.4 -- ground image size vs the tile (clumps overlap into a carpet)
local GOLD_IMAGE = "Ground_Gold"
-- 3D leaves (only near you, so phones stay smooth).
local MESH_DISTANCE = if TOUCH then 30 else 44 -- tiles closer than this get 3D leaves
local MESH_KEEP = MESH_DISTANCE + 10
local LEAVES_PER_TILE = if TOUCH then 4 else 7
local EDGE_LEAVES = 3 -- extra leaves on tiles against a fence or edge (drifts)
local EXTRA_FLYERS = if TOUCH then 1 else 2 -- more leaves fly off a cleared tile than lie on it
local MAX_LEAF_FLIGHTS = if TOUCH then 220 else 450
local DETAIL_BUDGET = 40 -- tiles given leaves per pass
local MAX_DRIFT = 3 -- studs a kicked leaf can end up from its spot
local KICK_SPEED = 3 -- walking slower than this doesn't move leaves
local HOP = 0.25 -- part of a flight spent hopping up before the pull starts
local DEFAULT_GROUND = { "Ground_Autumn1", "Ground_Autumn2", "Ground_Autumn3" }
-- 3D piles (models thread): how many variants each look has.
local CLUMPS = { Autumn = 4, Park = 3, Seaweed = 2, Paper = 2, Snow = 2 }
local DRIFTS = { Autumn = 2, Park = 1, Snow = 1 }
local GOLD_CLUMP = "Clump_Gold1"
local DRIFT_CHANCE = 0.65 -- edge tiles that get a drift heap
-- Wind
local GUST_EVERY = { 8, 15 } -- seconds between gusts
local GUST_SPEED = 24 -- studs per second the gust front travels
local GUST_SHARE = 0.35 -- part of the leaves a gust lifts

type Tile = {
	id: number,
	part: BasePart,
	decal: Decal,
	base: CFrame,
	size: Vector3,
	trash: Model?,
	trashBase: CFrame?,
	trashScale: number,
	leaves: { Leaf }?,
	props: { Prop }?,
	edge: Vector3?,
}
-- A solid mesh on a tile (its pile or drift heap). rel is relative to the tile's part.
type Prop = { part: BasePart, name: string, scale: Vector3, rel: CFrame, clump: boolean }
-- A 3D leaf lying on a tile. `off` is how far it was kicked from its spot.
type Leaf = {
	part: BasePart,
	tile: Tile,
	home: Vector3,
	off: Vector3,
	vel: Vector3,
	rot: Vector3,
	spin: Vector3,
	size: Vector3,
	color: Color3,
	phase: number,
	kicked: number,
}
type Chunk = { ids: { number }, center: Vector3, radius: number, built: boolean }

local folder: Folder
local cleared: { [number]: boolean } = {}
local golden: { [number]: boolean } = {}
local tiles: { [number]: Tile } = {}
local chunks: { Chunk } = {}
local chunkOf: { [number]: Chunk } = {}
local buildQueue: { number } = {} -- tile ids waiting to be built
local pool: { BasePart } = {}
local ready = false
local queued: { () -> () } = {}

type Fly = { tile: Tile, start: number, from: CFrame, target: (() -> Vector3)?, spin: number, swirl: number, fade: boolean }
local clumpsOn = false -- the Clump_* meshes are loaded and tiles use them
local flying: { Fly } = {}
type Grow = { tile: Tile, start: number }
local growing: { Grow } = {}
local shaking: { [Tile]: number } = {}
local detailed: { [Tile]: boolean } = {} -- tiles that have 3D leaves
local detailList: { Tile } = {} -- the same tiles as a list (random picks)
local moving: { [Leaf]: boolean } = {} -- kicked leaves still in the air or sliding
-- Who cleared a tile: where their leaves go and how (tool style).
type Sweeper = { root: Vector3, target: () -> Vector3, style: string }
type LeafFlight = {
	part: BasePart,
	style: string,
	push: Vector3,
	from: Vector3,
	rot: Vector3,
	spin: Vector3,
	start: number,
	time: number,
	target: (() -> Vector3)?,
	swirl: number,
	side: number,
	hop: number,
	size: Vector3,
}
local leafFlights: { LeafFlight } = {}
local bursts: { [string]: ParticleEmitter } = {}
local burstPart: BasePart

local function image(name: string): string
	return Assets.Images[name] or ""
end

------------------------------------------------------------------ trash

local function piece(model: Model, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local CAN_COLORS = { Color3.fromRGB(230, 50, 50), Color3.fromRGB(50, 120, 230), Color3.fromRGB(60, 190, 90), Color3.fromRGB(255, 150, 40) }
local SILVER = Color3.fromRGB(200, 205, 215)
local BLOCK, CYL, BALL = Enum.PartType.Block, Enum.PartType.Cylinder, Enum.PartType.Ball

-- Each builder makes the piece around the origin, lying on the ground (y = 0 is the grass).
local TRASH: { [string]: (Model, number) -> () } = {
	Can = function(m, k)
		local c = CAN_COLORS[math.floor(k * #CAN_COLORS) + 1]
		piece(m, CYL, Vector3.new(1.3, 0.75, 0.75), CFrame.new(0, 0.37, 0), c)
		piece(m, CYL, Vector3.new(0.08, 0.72, 0.72), CFrame.new(0.68, 0.37, 0), SILVER, Enum.Material.Metal)
		piece(m, CYL, Vector3.new(0.08, 0.72, 0.72), CFrame.new(-0.68, 0.37, 0), SILVER, Enum.Material.Metal)
		piece(m, CYL, Vector3.new(1.32, 0.77, 0.77), CFrame.new(0, 0.37, 0), Color3.new(1, 1, 1), nil, 0.85)
	end,
	Bottle = function(m)
		piece(m, CYL, Vector3.new(1.6, 0.7, 0.7), CFrame.new(0, 0.35, 0), Color3.fromRGB(150, 210, 255), Enum.Material.Glass, 0.35)
		piece(m, CYL, Vector3.new(0.45, 0.36, 0.36), CFrame.new(1.0, 0.35, 0), Color3.fromRGB(150, 210, 255), Enum.Material.Glass, 0.35)
		piece(m, CYL, Vector3.new(0.18, 0.4, 0.4), CFrame.new(1.3, 0.35, 0), Color3.fromRGB(60, 140, 240))
		piece(m, CYL, Vector3.new(0.6, 0.72, 0.72), CFrame.new(-0.1, 0.35, 0), Color3.fromRGB(255, 255, 255))
	end,
	PaperBall = function(m)
		piece(m, BALL, Vector3.new(0.95, 0.95, 0.95), CFrame.new(0, 0.45, 0), Color3.fromRGB(245, 245, 240))
		piece(m, BALL, Vector3.new(0.6, 0.6, 0.6), CFrame.new(0.32, 0.6, 0.18), Color3.fromRGB(230, 232, 236))
		piece(m, BALL, Vector3.new(0.55, 0.55, 0.55), CFrame.new(-0.3, 0.4, -0.22), Color3.fromRGB(236, 236, 228))
	end,
	JuiceBox = function(m, k)
		local c = if k < 0.5 then Color3.fromRGB(255, 120, 40) else Color3.fromRGB(150, 70, 220)
		piece(m, BLOCK, Vector3.new(0.9, 0.55, 1.3), CFrame.new(0, 0.28, 0), c)
		piece(m, BLOCK, Vector3.new(0.92, 0.3, 0.5), CFrame.new(0, 0.3, 0.1), Color3.new(1, 1, 1))
		piece(m, CYL, Vector3.new(0.9, 0.1, 0.1), CFrame.new(0.2, 0.62, -0.5) * CFrame.Angles(0, 0, math.rad(60)), Color3.fromRGB(255, 255, 255))
	end,
	ChipBag = function(m, k)
		local c = if k < 0.5 then Color3.fromRGB(255, 210, 40) else Color3.fromRGB(230, 60, 60)
		piece(m, BLOCK, Vector3.new(1.3, 0.3, 1.7), CFrame.new(0, 0.15, 0), c, Enum.Material.Foil)
		piece(m, BLOCK, Vector3.new(1.34, 0.12, 0.18), CFrame.new(0, 0.1, 0.86), Color3.fromRGB(200, 200, 205))
		piece(m, BLOCK, Vector3.new(1.34, 0.12, 0.18), CFrame.new(0, 0.1, -0.86), Color3.fromRGB(200, 200, 205))
	end,
	Bucket = function(m)
		piece(m, CYL, Vector3.new(1.1, 1.0, 1.0), CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(240, 70, 80))
		piece(m, CYL, Vector3.new(0.12, 1.12, 1.12), CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 200, 60))
	end,
	Shell = function(m)
		piece(m, BALL, Vector3.new(1.0, 0.35, 0.9), CFrame.new(0, 0.15, 0), Color3.fromRGB(255, 190, 200))
		piece(m, BALL, Vector3.new(0.3, 0.25, 0.3), CFrame.new(0, 0.12, 0.45), Color3.fromRGB(255, 160, 175))
	end,
	PizzaBox = function(m)
		piece(m, BLOCK, Vector3.new(2.0, 0.28, 2.0), CFrame.new(0, 0.14, 0), Color3.fromRGB(200, 150, 96), Enum.Material.Cardboard)
		piece(m, BLOCK, Vector3.new(1.4, 0.04, 1.4), CFrame.new(0, 0.29, 0), Color3.fromRGB(220, 60, 50))
	end,
	Cup = function(m)
		piece(m, CYL, Vector3.new(1.2, 0.7, 0.7), CFrame.new(0, 0.35, 0), Color3.fromRGB(250, 250, 250))
		piece(m, CYL, Vector3.new(0.14, 0.76, 0.76), CFrame.new(0.62, 0.35, 0), Color3.fromRGB(110, 70, 50))
		piece(m, CYL, Vector3.new(0.5, 0.74, 0.74), CFrame.new(0, 0.35, 0), Color3.fromRGB(80, 170, 110))
	end,
}

local function buildTrash(kind: string, id: number, at: CFrame, scale: number): Model?
	-- The Blender piece when it's loaded (pivot on the ground, lying on its side).
	local mesh = AssetLibrary.get("Trash_" .. kind)
	if mesh then
		for _, d in mesh:GetDescendants() do
			if d:IsA("BasePart") then
				d.CastShadow = false
			end
		end
		mesh:SetAttribute("Mesh", true)
		mesh:ScaleTo(scale)
		mesh:PivotTo(at)
		mesh.Parent = folder
		return mesh
	end
	local builder = TRASH[kind]
	if not builder then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "Trash_" .. kind
	builder(m, Grid.hash(id, 7))
	m.WorldPivot = CFrame.new() -- builders work around the origin, y = 0 on the grass
	m:ScaleTo(scale)
	m:PivotTo(at)
	m.Parent = folder
	return m
end

------------------------------------------------------------------ tiles

local function takePart(): BasePart
	local p = table.remove(pool)
	if p then
		return p
	end
	local part = Instance.new("Part")
	part.Name = "Leaves"
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local decal = Instance.new("Decal")
	decal.Name = "Ground"
	decal.Face = Enum.NormalId.Top
	decal.Parent = part
	return part
end

local function leafColor(id: number, k: number, look: LeafMeshes.Look): Color3
	return look.colors[math.floor(Grid.hash(id, 100 + k) * #look.colors) + 1]
end

------------------------------------------------------------------ 3D piles

local meshTemplates: { [string]: BasePart } = {}
local meshPools: { [string]: { BasePart } } = {}

local function takeMesh(name: string): BasePart?
	local list = meshPools[name]
	local part = list and table.remove(list)
	if part then
		return part
	end
	local t = meshTemplates[name]
	if not t then
		local model = AssetLibrary.get(name)
		local found = model and model:FindFirstChildWhichIsA("BasePart")
		if not found then
			if model then
				model:Destroy()
			end
			return nil
		end
		found.Parent = nil
		model:Destroy()
		found.Anchored = true
		found.CanCollide = false
		found.CanQuery = false
		found.CanTouch = false
		found.CastShadow = false
		found.Name = name
		found:SetAttribute("BaseSize", found.Size)
		-- Every pile of a zone shares that zone's one texture atlas.
		local meta = Assets.Models[name] :: any
		local atlas = meta and meta.atlas and Assets.Images[meta.atlas]
		if atlas and found:IsA("MeshPart") then
			found.TextureID = atlas
		end
		local partMeta = meta and meta.parts and meta.parts.Clump
		if partMeta and partMeta.material == "Foil" then
			found.Material = Enum.Material.Foil -- the gold pile shines
		end
		meshTemplates[name] = found
		t = found
	end
	return (t :: BasePart):Clone()
end

local function giveMesh(part: BasePart)
	part.Parent = nil
	local list = meshPools[part.Name]
	if not list then
		list = {}
		meshPools[part.Name] = list
	end
	table.insert(list, part)
end

local function clumpName(id: number, look: LeafMeshes.Look): string
	local n = CLUMPS[look.name] or 0
	return `Clump_{look.name}{math.floor(Grid.hash(id, 15) * n) + 1}`
end

-- The side of a tile that has no tile next to it (a fence, wall, path or the zone's edge).
local function edgeOf(id: number): Vector3?
	local zg = Grid.zoneGridOfId(id)
	if not zg then
		return nil
	end
	local index = id - zg.FirstId
	local col, row = index % zg.Cols, index // zg.Cols
	local function missing(c: number, r: number): boolean
		return c < 0 or r < 0 or c >= zg.Cols or r >= zg.Rows or not zg.Exists[r * zg.Cols + c]
	end
	if missing(col + 1, row) then
		return Vector3.new(1, 0, 0)
	elseif missing(col - 1, row) then
		return Vector3.new(-1, 0, 0)
	elseif missing(col, row + 1) then
		return Vector3.new(0, 0, 1)
	elseif missing(col, row - 1) then
		return Vector3.new(0, 0, -1)
	end
	return nil
end

-- Puts the tile's meshes where its part is, at `k` times their size (grow / shrink).
local function placeProps(tile: Tile, k: number, sink: number?)
	local props = tile.props
	if not props then
		return
	end
	local frame = tile.part.CFrame
	for _, prop in props do
		local base = LeafMeshes.baseSize(prop.part)
		local size = base * prop.scale * math.max(k, 0.02)
		prop.part.Size = size
		prop.part.CFrame = frame * prop.rel * CFrame.new(0, size.Y / 2 - 0.03 - (sink or 0), 0)
	end
end

local function addProp(tile: Tile, name: string, scale: Vector3, rel: CFrame, clump: boolean): Prop?
	local part = takeMesh(name)
	if not part then
		return nil
	end
	local prop: Prop = { part = part, name = name, scale = scale, rel = rel, clump = clump }
	local props = tile.props or {}
	tile.props = props
	table.insert(props, prop)
	part.Parent = folder
	return prop
end

local function dropProps(tile: Tile)
	for _, prop in tile.props or {} do
		giveMesh(prop.part)
	end
	tile.props = nil
end

-- The pile and, against an edge, a drift heap.
local function buildProps(tile: Tile)
	local id = tile.id
	local zg = Grid.zoneGridOfId(id)
	if not zg then
		return
	end
	local look = LeafMeshes.lookOf(id)
	-- The piles are modelled for a 5-stud grid (about 5.8 across, so neighbours overlap)
	-- and close into one carpet when turned in 90° steps; free turns leave corner gaps.
	local s = zg.Zone.TileSize / 5
	local spread = s * (0.98 + Grid.hash(id, 16) * 0.08)
	local height = s * (0.85 + Grid.hash(id, 17) * 0.4)
	local name = if golden[id] then GOLD_CLUMP else clumpName(id, look)
	-- Turned in 90° steps on the grid (tile.part itself is turned at random).
	local centre = tile.base.Position
	local square = CFrame.new(centre) * CFrame.Angles(0, math.floor(Grid.hash(id, 18) * 4) * math.pi / 2, 0)
	if addProp(tile, name, Vector3.new(spread, height, spread), tile.part.CFrame:ToObjectSpace(square), true) then
		tile.decal.Transparency = 1
	end
	local edge = tile.edge
	local drifts = DRIFTS[look.name] or DRIFTS.Autumn
	if edge and Grid.hash(id, 14) < DRIFT_CHANCE then
		local name2 = `Drift_{if DRIFTS[look.name] then look.name else "Autumn"}{math.floor(Grid.hash(id, 19) * drifts) + 1}`
		-- High side (+Z) against the edge, sloping down toward the open ground.
		local at = centre + edge * zg.Zone.TileSize * 0.3
		local world = CFrame.lookAt(at, at - edge)
		addProp(tile, name2, Vector3.new(s, s * (0.7 + Grid.hash(id, 20) * 0.25), s), tile.part.CFrame:ToObjectSpace(world), false)
	end
	placeProps(tile, 1)
end

local function setGoldLook(tile: Tile, on: boolean)
	local zg = Grid.zoneGridOfId(tile.id)
	local ground = zg and zg.Zone.Ground or DEFAULT_GROUND
	tile.decal.Texture = image(if on then GOLD_IMAGE else ground[math.floor(Grid.hash(tile.id, 3) * #ground) + 1])
	if tile.props then
		for _, prop in tile.props do
			if prop.clump then
				local name = if on then GOLD_CLUMP else clumpName(tile.id, LeafMeshes.lookOf(tile.id))
				local part = if name ~= prop.name then takeMesh(name) else nil
				if part then
					giveMesh(prop.part)
					prop.part, prop.name = part, name
					part.Parent = folder
				end
			end
		end
		placeProps(tile, 1)
	end
	if tile.leaves then
		local look = LeafMeshes.lookOf(tile.id)
		for k, leaf in tile.leaves do
			leaf.color = if on then LeafMeshes.Gold else leafColor(tile.id, k, look)
			leaf.part.Color = leaf.color
		end
	end
	local sparkle = tile.part:FindFirstChild("Gold")
	if on and not sparkle then
		local e = Instance.new("ParticleEmitter")
		e.Name = "Gold"
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 215, 80))
		e.Size = NumberSequence.new(0.7, 0)
		e.Rate = 6
		e.Lifetime = NumberRange.new(0.8, 1.2)
		e.Speed = NumberRange.new(1.5, 3)
		e.LightEmission = 1
		e.Parent = tile.part
	elseif not on and sparkle then
		sparkle:Destroy()
	end
end

local function makeTile(id: number): Tile?
	if tiles[id] or cleared[id] then
		return nil
	end
	local zg = Grid.zoneGridOfId(id)
	local position = Grid.tilePosition(id)
	if not zg or not position then
		return nil
	end
	local size = zg.Zone.TileSize
	local y = zg.Zone.GroundY + 0.04 + Grid.hash(id, 4) * 0.05
	local base = CFrame.new(position.X, y, position.Z) * CFrame.Angles(0, Grid.hash(id, 5) * math.pi * 2, 0)
	local part = takePart()
	local s = Vector3.new(size * TILE_SPREAD, 0.05, size * TILE_SPREAD)
	part.Size = s
	part.CFrame = base
	local decal = part:FindFirstChild("Ground") :: Decal
	decal.Transparency = 0
	local tile: Tile = { id = id, part = part, decal = decal, base = base, size = s, trashScale = 1, edge = edgeOf(id) }
	setGoldLook(tile, golden[id] == true)
	if clumpsOn then
		buildProps(tile)
	end
	local kind = Grid.trashKind(id)
	if kind then
		local at = CFrame.new(position.X, zg.Zone.GroundY + 0.05, position.Z) * CFrame.Angles(0, Grid.hash(id, 6) * math.pi * 2, 0)
		tile.trashScale = size / 4 * 1.35
		tile.trash = buildTrash(kind, id, at, tile.trashScale)
		tile.trashBase = at
	end
	part.Parent = folder
	tiles[id] = tile
	return tile
end

------------------------------------------------------------------ 3D leaves

local function leafCFrame(leaf: Leaf): CFrame
	local p = leaf.home + leaf.off
	return CFrame.new(p) * CFrame.fromEulerAnglesYXZ(leaf.rot.X, leaf.rot.Y, leaf.rot.Z)
end

-- Lays a few real leaves on a tile (on top of its ground image).
local function addLeaves(tile: Tile)
	if tile.leaves then
		return
	end
	local id = tile.id
	local zg = Grid.zoneGridOfId(id)
	if not zg then
		return
	end
	local size = zg.Zone.TileSize
	local look = LeafMeshes.lookOf(id)
	local center = tile.base.Position
	local groundY = zg.Zone.GroundY + 0.07
	local edge = tile.edge
	local n = if tile.trash then 2 else LEAVES_PER_TILE + (if edge then EDGE_LEAVES else 0)
	local pile = if tile.props then 0.38 * size / 5 else 0 -- leaves lie on top of a 3D pile
	local leaves = {}
	for k = 1, n do
		local r = size * 0.55 * math.sqrt(Grid.hash(id, 20 + k))
		local a = Grid.hash(id, 40 + k) * math.pi * 2
		local onTop = pile * math.max(0, 1 - r / (size * 0.55))
		local shift = Vector3.zero
		if edge and k > n - EDGE_LEAVES then
			shift = edge * size * 0.35 -- the extra ones heap up against the edge
			onTop += pile
		end
		local kind = look.kinds[math.floor(Grid.hash(id, 80 + k) * #look.kinds) + 1]
		local color = if golden[id] then LeafMeshes.Gold else leafColor(id, k, look)
		local scale = size / 4 * (0.9 + Grid.hash(id, 60 + k) * 0.6)
		local part = LeafMeshes.take(kind, color, scale)
		if not part then
			break
		end
		local leaf: Leaf = {
			part = part,
			tile = tile,
			home = Vector3.new(center.X + math.cos(a) * r, groundY + onTop + k * 0.015, center.Z + math.sin(a) * r) + shift,
			off = Vector3.zero,
			vel = Vector3.zero,
			rot = Vector3.new(Grid.hash(id, 120 + k) * 0.5 - 0.25, Grid.hash(id, 140 + k) * math.pi * 2, Grid.hash(id, 160 + k) * 0.5 - 0.25),
			spin = Vector3.zero,
			size = part.Size,
			color = color,
			phase = Grid.hash(id, 180 + k) * math.pi * 2,
			kicked = 0,
		}
		part.CFrame = leafCFrame(leaf)
		part.Parent = folder
		table.insert(leaves, leaf)
	end
	tile.leaves = leaves
	detailed[tile] = true
end

local function stripLeaves(tile: Tile)
	local leaves = tile.leaves
	detailed[tile] = nil
	if not leaves then
		return
	end
	tile.leaves = nil
	for _, leaf in leaves do
		moving[leaf] = nil
		LeafMeshes.give(leaf.part)
	end
end

local function release(tile: Tile)
	if tiles[tile.id] == tile then
		tiles[tile.id] = nil
	end
	stripLeaves(tile)
	dropProps(tile)
	shaking[tile] = nil
	local sparkle = tile.part:FindFirstChild("Gold")
	if sparkle then
		sparkle:Destroy()
	end
	tile.part.Parent = nil
	table.insert(pool, tile.part)
	if tile.trash then
		tile.trash:Destroy()
		tile.trash = nil
	end
end

------------------------------------------------------------------ chunks

local function buildChunks()
	for _, zg in Grid.Zones do
		local cols, rows = zg.Cols, zg.Rows
		local size = zg.Zone.TileSize
		for cy = 0, rows - 1, CHUNK do
			for cx = 0, cols - 1, CHUNK do
				local ids = {}
				for row = cy, math.min(rows - 1, cy + CHUNK - 1) do
					for col = cx, math.min(cols - 1, cx + CHUNK - 1) do
						local index = row * cols + col
						if zg.Exists[index] then
							table.insert(ids, zg.FirstId + index)
						end
					end
				end
				if #ids > 0 then
					local w = math.min(CHUNK, cols - cx) * size
					local h = math.min(CHUNK, rows - cy) * size
					local chunk: Chunk = {
						ids = ids,
						center = Vector3.new(zg.Zone.Min.X + cx * size + w / 2, zg.Zone.GroundY, zg.Zone.Min.Y + cy * size + h / 2),
						radius = math.sqrt(w * w + h * h) / 2,
						built = false,
					}
					table.insert(chunks, chunk)
					for _, id in ids do
						chunkOf[id] = chunk
					end
				end
			end
		end
	end
end

local function focus(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.Focus.Position else nil
end

-- Which chunks to draw or put away (a few times a second).
local function refreshChunks()
	local at = focus()
	if not at then
		return
	end
	-- The 3D piles just finished loading: rebuild what's drawn so every tile gets one.
	if not clumpsOn and AssetLibrary.has("Clump_Autumn1") then
		clumpsOn = true
		for _, chunk in chunks do
			if chunk.built then
				chunk.built = false
				for _, id in chunk.ids do
					local tile = tiles[id]
					if tile then
						release(tile)
					end
				end
			end
		end
	end
	local flat = Vector3.new(at.X, 0, at.Z)
	local wanted = {}
	for _, chunk in chunks do
		local d = (Vector3.new(chunk.center.X, 0, chunk.center.Z) - flat).Magnitude - chunk.radius
		if not chunk.built and d < DRAW_DISTANCE then
			chunk.built = true
			table.insert(wanted, { chunk = chunk, d = d })
		elseif chunk.built and d > KEEP_DISTANCE then
			chunk.built = false
			for _, id in chunk.ids do
				local tile = tiles[id]
				if tile then
					release(tile)
				end
			end
		end
	end
	-- Nearest first.
	table.sort(wanted, function(a, b)
		return a.d > b.d
	end)
	for _, w in wanted do
		for _, id in w.chunk.ids do
			table.insert(buildQueue, id)
		end
	end
end

local function buildSome()
	local n = 0
	while n < BUILD_BUDGET and #buildQueue > 0 do
		local id = table.remove(buildQueue) :: number
		local chunk = chunkOf[id]
		if chunk and chunk.built then
			makeTile(id)
			n += 1
		end
	end
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Gives tiles close to you their 3D leaves and takes them off tiles you've left behind.
local function refreshDetail()
	local at = focus()
	if not at then
		return
	end
	for tile in detailed do
		if tiles[tile.id] ~= tile or flatDistance(tile.base.Position, at) > MESH_KEEP then
			stripLeaves(tile)
		end
	end
	if not LeafMeshes.ready() then
		return
	end
	table.clear(detailList)
	for tile in detailed do
		table.insert(detailList, tile)
	end
	local budget = DETAIL_BUDGET
	Grid.forEachInRadius(at, MESH_DISTANCE, function(id)
		if budget <= 0 then
			return
		end
		local tile = tiles[id]
		if tile and not tile.leaves then
			budget -= 1
			addLeaves(tile)
			-- Trash built before the meshes loaded: swap in the Blender piece.
			if tile.trash and not tile.trash:GetAttribute("Mesh") and tile.trashBase then
				local kind = Grid.trashKind(id)
				local mesh = kind and AssetLibrary.has("Trash_" .. kind) and buildTrash(kind, id, tile.trashBase, tile.trashScale)
				if mesh then
					tile.trash:Destroy()
					tile.trash = mesh
				end
			end
		end
	end)
end

------------------------------------------------------------------ sounds

-- Short clips played where the leaves are (positional, cut off with a quick fade).
local soundRoot: BasePart? = nil
type Voice = { attachment: Attachment, sound: Sound, token: number }
local voices: { Voice } = {}
local nextVoice = 1
local MAX_VOICES = 6

local function playAt(name: string, position: Vector3, duration: number, volume: number, pitch: number)
	local def = Sounds.Sfx[name]
	local root = soundRoot
	if not def or def.Id == "" or not root then
		return
	end
	local voice = voices[nextVoice]
	if not voice then
		local attachment = Instance.new("Attachment")
		attachment.Parent = root
		local sound = Instance.new("Sound")
		sound.RollOffMinDistance = 10
		sound.RollOffMaxDistance = 90
		sound.SoundGroup = Ui.soundGroup("SFX")
		sound.Parent = attachment
		voice = { attachment = attachment, sound = sound, token = 0 }
		voices[nextVoice] = voice
	end
	nextVoice = nextVoice % MAX_VOICES + 1
	local v = voice :: Voice
	v.token += 1
	local mine = v.token
	v.attachment.Position = position
	if v.sound.SoundId ~= def.Id then
		v.sound.SoundId = def.Id
	end
	v.sound.Volume = def.Volume * volume
	v.sound.PlaybackSpeed = pitch
	v.sound.TimePosition = 0
	v.sound:Play()
	task.delay(duration, function()
		if v.token ~= mine then
			return
		end
		local steps = 6
		for i = steps - 1, 0, -1 do
			task.wait(0.025)
			if v.token ~= mine then
				return
			end
			v.sound.Volume = def.Volume * volume * i / steps
		end
		v.sound:Stop()
	end)
end

local RUSTLES = { Autumn = "Rustle", Park = "Rustle", Seaweed = "RustleSeaweed", Paper = "RustlePaper", Snow = "RustleSnow" }

local function rustleName(id: number): string
	return RUSTLES[LeafMeshes.lookOf(id).name] or "Rustle"
end

-- Someone walks or drives through: leaves in front of them get kicked up and aside.
-- Returns how many leaves moved and one of their tiles (for the rustle sound).
local function kick(at: Vector3, radius: number, velocity: Vector3, now: number): (number, number?)
	local count, someTile = 0, nil
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	Grid.forEachInRadius(at, radius + 2, function(id)
		local tile = tiles[id]
		if not tile or not tile.leaves then
			return
		end
		for _, leaf in tile.leaves do
			if now - leaf.kicked < 0.3 then
				continue
			end
			local p = leaf.home + leaf.off
			local dx, dz = p.X - at.X, p.Z - at.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > radius or math.abs(p.Y - at.Y) > 4 then
				continue
			end
			local dir = if d > 0.05 then Vector3.new(dx / d, 0, dz / d) else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
			local push = 1 - d / radius * 0.6
			local add = dir * (2.5 + speed * 0.45) * push + Vector3.new(velocity.X, 0, velocity.Z) * 0.2 + Vector3.new(0, (2 + speed * 0.3) * push, 0)
			local v = leaf.vel + add
			if v.Magnitude > 22 then
				v = v.Unit * 22
			end
			leaf.vel = v
			leaf.spin += Vector3.new(math.random() * 16 - 8, math.random() * 12 - 6, math.random() * 16 - 8) * push
			leaf.kicked = now
			moving[leaf] = true
			count += 1
			someTile = id
		end
	end)
	return count, someTile
end

local lastRustle: { [Player]: number } = {}

-- Rustle where a player's feet (or car) went through leaves.
local function rustle(player: Player, at: Vector3, count: number, id: number?, now: number, speed: number)
	if count <= 0 or not id or now - (lastRustle[player] or 0) < 0.28 then
		return
	end
	lastRustle[player] = now
	local volume = math.min(1, 0.35 + count / 6) * math.clamp(speed / 16, 0.5, 1)
	playAt(rustleName(id), at, 0.45, volume, 0.9 + math.random() * 0.25)
end

local function kickers(now: number)
	local at = focus()
	if not at then
		return
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not humanoid then
			continue
		end
		if flatDistance(root.Position, at) > MESH_KEEP then
			continue
		end
		local seat = humanoid.SeatPart
		if seat and seat:IsA("VehicleSeat") and seat.Parent then
			local v = seat.AssemblyLinearVelocity
			if Vector3.new(v.X, 0, v.Z).Magnitude > KICK_SPEED then
				local brush = seat.Parent:FindFirstChild("Brush", true)
				local p = if brush and brush:IsA("BasePart") then brush.Position else seat.Position
				local count, id = kick(Vector3.new(p.X, root.Position.Y - 3, p.Z), 5, v, now)
				rustle(player, p, count, id, now, v.Magnitude)
			end
		else
			local v = root.AssemblyLinearVelocity
			if Vector3.new(v.X, 0, v.Z).Magnitude > KICK_SPEED then
				local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
				local count, id = kick(feet, 2.4, v, now)
				rustle(player, feet, count, id, now, v.Magnitude)
			end
		end
	end
end

------------------------------------------------------------------ wind

type GustLeaf = { leaf: Leaf, at: number, dir: Vector3 }
local gustQueue: { GustLeaf } = {}
local nextGust = os.clock() + 6
local flutterAcc = 0
local FLUTTER_RATE = 8 -- single leaves a second that lift a little on their own

local function blow(leaf: Leaf, force: Vector3, now: number)
	leaf.vel += force
	leaf.spin += Vector3.new(math.random() * 10 - 5, math.random() * 8 - 4, math.random() * 10 - 5)
	leaf.kicked = now
	moving[leaf] = true
end

-- A gust sweeps across the area: its front passes over the leaves one row at a time,
-- lifting some and carrying them a little way downwind.
local function startGust(now: number)
	local at = focus()
	if not at or #detailList == 0 then
		return
	end
	local angle = 0.35 + (math.random() * 2 - 1) * 0.7
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	for tile in detailed do
		for _, leaf in tile.leaves or {} do
			if math.random() < GUST_SHARE then
				local along = (leaf.home - at):Dot(dir)
				table.insert(gustQueue, { leaf = leaf, at = now + (along + MESH_KEEP) / GUST_SPEED + math.random() * 0.25, dir = dir })
			end
		end
	end
	playAt("Gust", at - dir * 20 + Vector3.new(0, 4, 0), 2.6, 1, 0.95 + math.random() * 0.15)
end

local function stepWind(now: number, dt: number)
	if now >= nextGust then
		nextGust = now + GUST_EVERY[1] + math.random() * (GUST_EVERY[2] - GUST_EVERY[1])
		startGust(now)
	end
	for i = #gustQueue, 1, -1 do
		local g = gustQueue[i]
		if now >= g.at then
			table.remove(gustQueue, i)
			local tile = g.leaf.tile
			if tile.leaves and tiles[tile.id] == tile then
				blow(g.leaf, g.dir * (4 + math.random() * 5) + Vector3.new(0, 2 + math.random() * 3, 0), now)
			end
		end
	end
	-- Now and then a single leaf lifts a little and settles again.
	flutterAcc += dt * FLUTTER_RATE
	while flutterAcc >= 1 do
		flutterAcc -= 1
		local tile = detailList[math.random(1, math.max(1, #detailList))]
		local leaves = tile and tile.leaves
		if leaves and #leaves > 0 and tiles[tile.id] == tile then
			local leaf = leaves[math.random(1, #leaves)]
			if not moving[leaf] then
				blow(leaf, Vector3.new(math.random() * 0.8 - 0.4, 0.8 + math.random() * 0.9, math.random() * 0.8 - 0.4), now)
			end
		end
	end
end

-- Kicked leaves: fly, flutter down, slide to a stop and lie flat where they land.
local movedParts: { BasePart } = {}
local movedCFrames: { CFrame } = {}
local function stepMoving(now: number, dt: number)
	table.clear(movedParts)
	table.clear(movedCFrames)
	dt = math.min(dt, 1 / 20)
	for leaf in moving do
		local v, o = leaf.vel, leaf.off
		if o.Y > 0.001 or v.Y > 0 then
			-- In the air: heavy drag and a side-to-side flutter, falling slowly.
			local drag = math.max(0, 1 - 1.8 * dt)
			local fx = math.sin(now * 7 + leaf.phase) * 9 * dt
			local fz = math.cos(now * 6 + leaf.phase) * 9 * dt
			v = Vector3.new(v.X * drag + fx, math.max(v.Y - 24 * dt, -4.5), v.Z * drag + fz)
		else
			v = Vector3.new(v.X, 0, v.Z) * math.max(0, 1 - 9 * dt)
		end
		o += v * dt
		if o.Y < 0 then
			o = Vector3.new(o.X, 0, o.Z)
			v = Vector3.new(v.X * 0.5, 0, v.Z * 0.5)
		end
		local flat = Vector3.new(o.X, 0, o.Z)
		if flat.Magnitude > MAX_DRIFT then
			flat = flat.Unit * MAX_DRIFT
			o = Vector3.new(flat.X, o.Y, flat.Z)
		end
		local r = leaf.rot + leaf.spin * dt
		if o.Y <= 0 then
			-- On the ground: settle flat again.
			leaf.spin *= math.max(0, 1 - 10 * dt)
			local k = math.min(1, 8 * dt)
			local rx = (r.X + math.pi) % (math.pi * 2) - math.pi
			local rz = (r.Z + math.pi) % (math.pi * 2) - math.pi
			r = Vector3.new(rx * (1 - k), r.Y, rz * (1 - k))
		else
			leaf.spin *= math.max(0, 1 - 1.2 * dt)
		end
		leaf.vel, leaf.off, leaf.rot = v, o, r
		if o.Y <= 0 and v.Magnitude < 0.15 and leaf.spin.Magnitude < 0.3 then
			moving[leaf] = nil
		end
		table.insert(movedParts, leaf.part)
		table.insert(movedCFrames, leafCFrame(leaf))
	end
	if #movedParts > 0 then
		Workspace:BulkMoveTo(movedParts, movedCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- A leaf leaving a cleared tile on its own path, by the sweeper's tool:
--   vacuum (and cars): a hop, then sucked into the nozzle with a swirl,
--   broom: pushed along the ground ahead of the sweep, then flicked into the backpack,
--   blower: thrown up and away in a cone, spinning, and gone,
--   nobody close: puffed up and faded.
local function launchLeaf(part: BasePart, from: Vector3, rot: Vector3, sweeper: Sweeper?, delay: number)
	if #leafFlights >= MAX_LEAF_FLIGHTS then
		LeafMeshes.give(part)
		return
	end
	part.Parent = folder
	local style = if sweeper then sweeper.style else "puff"
	local away = if sweeper then Vector3.new(from.X - sweeper.root.X, 0, from.Z - sweeper.root.Z) else Vector3.zero
	if away.Magnitude < 0.05 then
		local a = math.random() * math.pi * 2
		away = Vector3.new(math.cos(a), 0, math.sin(a))
	end
	away = away.Unit
	local push: Vector3
	local time: number
	if style == "blower" then
		local side = Vector3.new(-away.Z, 0, away.X) * (math.random() * 2 - 1) * 5
		push = away * (11 + math.random() * 7) + side + Vector3.new(0, 9 + math.random() * 6, 0)
		time = 1 + math.random() * 0.3
	elseif style == "broom" then
		push = away * (1.5 + math.random() * 1.8)
		time = FLY_TIME * (1.3 + math.random() * 0.4)
	else
		push = Vector3.zero
		time = FLY_TIME * (0.8 + math.random() * 0.5)
	end
	table.insert(leafFlights, {
		part = part,
		style = style,
		push = push,
		from = from,
		rot = rot,
		spin = Vector3.new(math.random() * 24 - 12, math.random() * 16 - 8, math.random() * 24 - 12) * (if style == "blower" then 1.8 else 1),
		start = os.clock() + delay,
		time = time,
		target = if sweeper then sweeper.target else nil,
		swirl = math.random() * math.pi * 2,
		side = 0.6 + math.random() * 1.2,
		hop = 1 + math.random() * 1.8,
		size = part.Size,
	})
end

local BROOM_SKID = 0.55 -- part of a broom flight spent sliding along the ground

local flightParts: { BasePart } = {}
local flightCFrames: { CFrame } = {}
local function stepLeafFlights(now: number)
	table.clear(flightParts)
	table.clear(flightCFrames)
	for i = #leafFlights, 1, -1 do
		local f = leafFlights[i]
		local t = math.max(0, (now - f.start) / f.time)
		if t >= 1 then
			table.remove(leafFlights, i)
			LeafMeshes.give(f.part)
			continue
		end
		local pos: Vector3
		local k = 1
		local r = f.rot + f.spin * t
		if f.style == "blower" then
			local secs = t * f.time
			pos = f.from + f.push * secs * (1 - secs * 0.3) + Vector3.new(0, -11 * secs * secs, 0)
			f.part.Transparency = if t > 0.6 then (t - 0.6) / 0.4 else 0
		elseif f.style == "broom" and f.target then
			if t < BROOM_SKID then
				-- Tumbling along the ground ahead of the broom, in little bounces.
				local u = t / BROOM_SKID
				local e = 1 - (1 - u) * (1 - u)
				pos = f.from + f.push * e + Vector3.new(0, math.abs(math.sin(u * math.pi * 3)) * 0.35 * (1 - u), 0)
				r = Vector3.new(f.rot.X + u * 6, f.rot.Y + f.spin.Y * t, f.rot.Z)
			else
				-- Flicked up in an arc into the backpack.
				local u = (t - BROOM_SKID) / (1 - BROOM_SKID)
				local start = f.from + f.push
				pos = start:Lerp(f.target(), u * u) + Vector3.new(0, math.sin(u * math.pi) * 2.2, 0)
				k = 1 - 0.7 * u
			end
		elseif not f.target then
			local e = t * t * (3 - 2 * t)
			local hop = f.from + Vector3.new(0, f.hop, 0)
			pos = f.from:Lerp(hop + Vector3.new(math.cos(f.swirl) * 2, 3, math.sin(f.swirl) * 2), e)
			f.part.Transparency = t * t
		elseif t < HOP then
			local u = t / HOP
			pos = f.from:Lerp(f.from + Vector3.new(0, f.hop, 0), 1 - (1 - u) * (1 - u))
		else
			local u = (t - HOP) / (1 - HOP)
			local hop = f.from + Vector3.new(0, f.hop, 0)
			local line = hop:Lerp(f.target(), u * u)
			local side = (1 - u) * f.side
			local a = f.swirl + u * 10
			pos = line + Vector3.new(math.cos(a) * side, math.sin(u * math.pi) * 0.8, math.sin(a) * side)
			k = 0.85 * (1 - u) + 0.15
		end
		if k < 1 then
			f.part.Size = f.size * k
		end
		table.insert(flightParts, f.part)
		table.insert(flightCFrames, CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(r.X, r.Y, r.Z))
	end
	if #flightParts > 0 then
		Workspace:BulkMoveTo(flightParts, flightCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

------------------------------------------------------------------ feel

local function makeBursts()
	burstPart = Instance.new("Part")
	burstPart.Name = "LeafBurst"
	burstPart.Anchored = true
	burstPart.CanCollide = false
	burstPart.CanQuery = false
	burstPart.CanTouch = false
	burstPart.Transparency = 1
	burstPart.Size = Vector3.new(3, 0.2, 3)
	burstPart.Parent = folder
	local textures = {
		Leaf = image("Vfx_LeafMaple"),
		Oval = image("Vfx_LeafOval"),
		Green = image("Vfx_LeafGreen"),
		Snow = image("Vfx_Snow"),
		Paper = "rbxasset://textures/particles/sparkles_main.dds",
	}
	for name, texture in textures do
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.Texture = if texture ~= "" then texture else "rbxasset://textures/particles/sparkles_main.dds"
		e.Enabled = false
		e.Lifetime = NumberRange.new(0.7, 1.2)
		e.Speed = NumberRange.new(8, 14)
		e.SpreadAngle = Vector2.new(35, 35)
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, -26, 0)
		e.Drag = 1.5
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-400, 400)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.6) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) })
		e.LightInfluence = 0.8
		e.Parent = burstPart
		bursts[name] = e
	end
	local shine = Instance.new("ParticleEmitter")
	shine.Name = "Shine"
	shine.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	shine.Color = ColorSequence.new(Color3.fromRGB(220, 255, 190), Color3.fromRGB(140, 235, 110))
	shine.Enabled = false
	shine.LightEmission = 0.8
	shine.Lifetime = NumberRange.new(0.5, 0.8)
	shine.Speed = NumberRange.new(1, 2.5)
	shine.EmissionDirection = Enum.NormalId.Top
	shine.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 1.1), NumberSequenceKeypoint.new(1, 0) })
	shine.Parent = burstPart
	bursts.Shine = shine
end

local function burstKind(id: number): string
	local zg = Grid.zoneGridOfId(id)
	local ground = zg and zg.Zone.Ground or DEFAULT_GROUND
	local first = ground[1] or ""
	if string.find(first, "Snow") then
		return "Snow"
	elseif string.find(first, "Seaweed") then
		return "Green"
	elseif string.find(first, "Paper") then
		return "Oval"
	elseif string.find(first, "Park") then
		return if Grid.hash(id, 8) < 0.5 then "Oval" else "Green"
	end
	return if Grid.hash(id, 8) < 0.6 then "Leaf" else "Oval"
end

local VACUUMS = { ShopVac = true, TurboVacuum = true }

-- A player's sweeper: where their leaves go (the car's brush, the vacuum's nozzle, their
-- backpack for brooms) and how they clear (style).
local function sweeperOf(character: Model): Sweeper?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	local rootPart: BasePart = root
	local seat = humanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") and seat.Parent then
		local brush = seat.Parent:FindFirstChild("Brush", true)
		local part: BasePart = if brush and brush:IsA("BasePart") then brush else seat
		return { root = part.Position, style = "vacuum", target = function()
			return part.Position
		end }
	end
	local tool = character:FindFirstChildOfClass("Tool")
	local toolId = tool and tool:GetAttribute("ToolId")
	local handle = tool and tool:FindFirstChild("Handle")
	if toolId == "LeafBlower" then
		return { root = rootPart.Position, style = "blower", target = function()
			return rootPart.Position
		end }
	end
	if handle and handle:IsA("BasePart") and VACUUMS[toolId :: any] then
		local tip = handle:FindFirstChild("Tip")
		return { root = rootPart.Position, style = "vacuum", target = function()
			return if tip and tip:IsA("Attachment") then tip.WorldPosition else handle.Position
		end }
	end
	-- Brooms, mops, toothbrushes: into the backpack on your back.
	local bag = character:FindFirstChild("LeafBag")
	local body = bag and bag:FindFirstChild("Body")
	return { root = rootPart.Position, style = "broom", target = function()
		if body and body:IsA("BasePart") and body.Parent then
			return body.Position + Vector3.new(0, body.Size.Y * 0.4, 0)
		end
		return rootPart.Position + Vector3.new(0, 1, 0)
	end }
end

local function flyAway(tile: Tile, sweeper: Sweeper?)
	local target = if sweeper and sweeper.style ~= "blower" then sweeper.target else nil
	tiles[tile.id] = nil
	shaking[tile] = nil
	local from = tile.part.CFrame
	-- With 3D leaves, every leaf flies on its own and the ground image just fades.
	local leaves = tile.leaves
	local fade = leaves ~= nil
	if leaves then
		tile.leaves = nil
		detailed[tile] = nil
		for k, leaf in leaves do
			moving[leaf] = nil
			launchLeaf(leaf.part, leaf.home + leaf.off, leaf.rot, sweeper, k * 0.03 + math.random() * 0.05)
		end
		local zg = Grid.zoneGridOfId(tile.id)
		local size = zg and zg.Zone.TileSize or 4
		local look = LeafMeshes.lookOf(tile.id)
		for k = 1, EXTRA_FLYERS do
			local part = if golden[tile.id] then LeafMeshes.take(look.kinds[1], LeafMeshes.Gold, size / 4) else LeafMeshes.random(look, size / 4 * (0.9 + math.random() * 0.5))
			if part then
				local a = math.random() * math.pi * 2
				local r = math.random() * size * 0.4
				local at = from.Position + Vector3.new(math.cos(a) * r, 0.05, math.sin(a) * r)
				launchLeaf(part, at, Vector3.new(0, math.random() * math.pi * 2, 0), sweeper, 0.05 + k * 0.04)
			end
		end
	end
	table.insert(flying, {
		tile = tile,
		start = os.clock() + (if fade then 0 else Grid.hash(tile.id, 10) * 0.08), -- a little stagger so they stream in
		from = from,
		target = target,
		spin = (Grid.hash(tile.id, 9) - 0.5) * 18,
		swirl = Grid.hash(tile.id, 11) * math.pi * 2,
		fade = fade,
	})
	burstPart.Position = from.Position
	local e = bursts[burstKind(tile.id)]
	if e then
		e:Emit(if golden[tile.id] then 6 else 2)
	end
	-- Clean ground: a little green-white glint where the leaves were.
	if fade and Grid.hash(tile.id, 21) < 0.5 then
		local shine = bursts.Shine
		if shine then
			shine:Emit(1)
		end
	end
end


local function stepFlying(now: number)
	for i = #flying, 1, -1 do
		local f = flying[i]
		local t = math.max(0, (now - f.start) / FLY_TIME)
		local tile = f.tile
		if t >= 1 then
			table.remove(flying, i)
			release(tile)
			continue
		end
		local start = f.from.Position
		local hop = start + Vector3.new(0, 1.6, 0)
		local pos: Vector3
		local k: number
		if not f.target then
			-- Nobody close: just puff up and fade.
			local e = t * t * (3 - 2 * t)
			pos = start:Lerp(start + Vector3.new(0, 6, 0), e)
			k = 1 - 0.6 * t
			tile.decal.Transparency = t * t
		elseif t < HOP then
			local u = t / HOP
			pos = start:Lerp(hop, 1 - (1 - u) * (1 - u))
			k = 1 - 0.15 * u
			tile.decal.Transparency = 0
		else
			-- Sucked in: speeds up toward the nozzle, swirling around the line, shrinking.
			local u = (t - HOP) / (1 - HOP)
			local into = f.target()
			local e = u * u
			local line = hop:Lerp(into, e)
			local side = (1 - u) * 1.4
			local a = f.swirl + u * 9
			pos = line + Vector3.new(math.cos(a) * side, math.sin(u * math.pi) * 1.2, math.sin(a) * side)
			k = 0.85 * (1 - u) + 0.08
			tile.decal.Transparency = if u > 0.85 then (u - 0.85) / 0.15 else 0
		end
		local cf = CFrame.new(pos) * f.from.Rotation * CFrame.Angles(t * f.spin * 0.4, t * f.spin, 0)
		if f.fade then
			-- The leaves fly on their own: the ground image (or 3D pile) stays put and fades
			-- or sinks away fast.
			tile.part.CFrame = f.from
			tile.decal.Transparency = math.min(1, t * 3)
			placeProps(tile, math.max(0.02, 1 - t * 1.8), t * 0.3)
		else
			tile.part.CFrame = cf
			tile.part.Size = tile.size * Vector3.new(k, 1, k)
			placeProps(tile, k)
		end
		if tile.trash then
			tile.trash:PivotTo(cf * CFrame.Angles(t * 6, 0, t * 4))
			if f.target and t > HOP then
				tile.trash:ScaleTo(math.max(0.05, tile.trashScale * k))
			end
		end
	end
end

local function stepGrowing(now: number)
	for i = #growing, 1, -1 do
		local g = growing[i]
		local t = math.min(1, (now - g.start) / GROW_TIME)
		local tile = g.tile
		if tiles[tile.id] ~= tile then
			table.remove(growing, i)
			continue
		end
		-- Overshoot a little, then settle.
		local k = if t < 0.7 then t / 0.7 * 1.12 else 1.12 - (t - 0.7) / 0.3 * 0.12
		tile.part.Size = tile.size * Vector3.new(math.max(k, 0.05), 1, math.max(k, 0.05))
		placeProps(tile, math.max(k, 0.05))
		if tile.leaves then
			for _, leaf in tile.leaves do
				leaf.part.Size = leaf.size * math.clamp(k, 0.05, 1.12)
			end
		end
		if t >= 1 then
			tile.part.Size = tile.size
			placeProps(tile, 1)
			if tile.leaves then
				for _, leaf in tile.leaves do
					leaf.part.Size = leaf.size
				end
			end
			table.remove(growing, i)
		end
	end
end

local function stepShaking(now: number)
	for tile, started in shaking do
		local t = (now - started) / SHAKE_TIME
		if t >= 1 or tiles[tile.id] ~= tile then
			shaking[tile] = nil
			if tiles[tile.id] == tile then
				tile.part.CFrame = tile.base
				placeProps(tile, 1)
				if tile.trash and tile.trashBase then
					tile.trash:PivotTo(tile.trashBase)
				end
			end
			continue
		end
		local a = math.sin(t * math.pi * 6) * 0.12 * (1 - t)
		local lift = math.sin(t * math.pi) * 0.25
		if tile.props then
			-- A 3D pile ruffles (squashes and swells) instead of jumping.
			placeProps(tile, 1 + math.sin(t * math.pi * 6) * 0.07 * (1 - t))
		else
			tile.part.CFrame = tile.base * CFrame.new(0, lift, 0) * CFrame.Angles(a * 0.5, a, 0)
		end
		if tile.trash and tile.trashBase then
			tile.trash:PivotTo(tile.trashBase * CFrame.new(0, lift * 1.5, 0) * CFrame.Angles(a, 0, a))
		end
	end
end

------------------------------------------------------------------ server events

local lastClearSound = 0

local function onCleared(packed: buffer)
	local at = focus()
	-- Everyone sweeping nearby: their cleared leaves get sucked into their tool or car.
	local sweepers: { Sweeper } = {}
	if at then
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and root and root:IsA("BasePart") and (root.Position - at).Magnitude < FLY_DISTANCE + SUCK_RANGE then
				local sweeper = sweeperOf(character)
				if sweeper then
					table.insert(sweepers, sweeper)
				end
			end
		end
	end
	local nearCount = 0
	for _, id in Grid.unpack(packed) do
		cleared[id] = true
		local tile = tiles[id]
		if tile then
			local p = tile.base.Position
			local near = at ~= nil and (p - at).Magnitude < FLY_DISTANCE
			if near and #flying < MAX_FLYING then
				local best, bestD = nil, SUCK_RANGE
				for _, sw in sweepers do
					local d = (sw.root - p).Magnitude
					if d < bestD then
						best, bestD = sw, d
					end
				end
				if at and (p - at).Magnitude < 30 then
					nearCount += 1
				end
				flyAway(tile, best)
			else
				release(tile)
			end
		end
	end
	-- One rustle for a batch of leaves cleared near you.
	local now = os.clock()
	if at and nearCount > 0 and now - lastClearSound > 0.16 then
		lastClearSound = now
		playAt("RustleBig", at, 0.35, math.min(1, 0.3 + nearCount / 8), 0.95 + math.random() * 0.2)
	end
end

local function onRestored(packed: buffer)
	local now = os.clock()
	for _, id in Grid.unpack(packed) do
		cleared[id] = nil
		local chunk = chunkOf[id]
		if chunk and chunk.built then
			local tile = makeTile(id)
			if tile then
				tile.part.Size = tile.size * Vector3.new(0.05, 1, 0.05)
				table.insert(growing, { tile = tile, start = now })
			end
		end
	end
end

local function onGolden(packed: buffer)
	for _, raw in Grid.unpack(packed) do
		local on = raw < 32768
		local id = if on then raw else raw - 32768
		golden[id] = if on then true else nil
		local tile = tiles[id]
		if tile then
			setGoldLook(tile, on)
		end
	end
end

------------------------------------------------------------------ public

-- Your tool is sweeping here: the leaves under it wiggle (also on tiles that need several
-- hits in the harder zones).
function LeafController:Disturb(position: Vector3, radius: number)
	local now = os.clock()
	Grid.forEachInRadius(position, radius, function(id)
		local tile = tiles[id]
		if tile and not shaking[tile] then
			shaking[tile] = now - math.random() * 0.1
			-- 3D leaves hop and spin a little.
			for _, leaf in tile.leaves or {} do
				if now - leaf.kicked > 0.25 then
					leaf.kicked = now
					leaf.vel += Vector3.new(math.random() * 3 - 1.5, 2.5 + math.random() * 2.5, math.random() * 3 - 1.5)
					leaf.spin += Vector3.new(math.random() * 10 - 5, math.random() * 8 - 4, math.random() * 10 - 5)
					moving[leaf] = true
				end
			end
		end
	end)
end

-- How many tiles are drawn right now (debug / tests).
function LeafController:DrawnCount(): number
	local n = 0
	for _ in tiles do
		n += 1
	end
	return n
end

function LeafController:Init()
	folder = Instance.new("Folder")
	folder.Name = "Leaves"
	folder.Parent = Workspace
	local root = Instance.new("Part")
	root.Name = "LeafSounds"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Transparency = 1
	root.Size = Vector3.one
	root.CFrame = CFrame.new()
	root.Parent = folder
	soundRoot = root
	buildChunks()
	makeBursts()
end

function LeafController:Start()
	-- Events that arrive before the snapshot wait for it.
	local function later(fn: (buffer) -> ()): (buffer) -> ()
		return function(packed: buffer)
			if ready then
				fn(packed)
			else
				table.insert(queued, function()
					fn(packed)
				end)
			end
		end
	end
	Net.event("TilesCleared").OnClientEvent:Connect(later(onCleared))
	Net.event("TilesRestored").OnClientEvent:Connect(later(onRestored))
	Net.event("TilesGolden").OnClientEvent:Connect(later(onGolden))

	task.spawn(function()
		for _ = 1, 5 do
			local ok, clearedIds, goldenIds = pcall(function()
				return Net.func("GetDust"):InvokeServer()
			end)
			if ok and clearedIds then
				for _, id in Grid.unpack(clearedIds) do
					cleared[id] = true
				end
				for _, id in Grid.unpack(goldenIds) do
					golden[id] = true
				end
				break
			end
			task.wait(1)
		end
		ready = true
		for _, fn in queued do
			fn()
		end
		queued = {}
	end)

	local acc, detailAcc = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		stepFlying(now)
		stepLeafFlights(now)
		stepGrowing(now)
		stepShaking(now)
		kickers(now)
		stepWind(now, dt)
		stepMoving(now, dt)
		if not ready then
			return
		end
		acc += dt
		if acc > 0.25 then
			acc = 0
			refreshChunks()
		end
		detailAcc += dt
		if detailAcc > 0.1 then
			detailAcc = 0
			refreshDetail()
		end
		buildSome()
	end)
end

return LeafController
