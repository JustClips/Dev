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
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local Grid = require(Shared.Grid)
local Net = require(Shared.Net)

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
local DEFAULT_GROUND = { "Ground_Autumn1", "Ground_Autumn2", "Ground_Autumn3" }

type Tile = {
	id: number,
	part: BasePart,
	decal: Decal,
	base: CFrame,
	size: Vector3,
	trash: Model?,
	trashBase: CFrame?,
	trashScale: number,
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

type Fly = { tile: Tile, start: number, from: CFrame, target: (() -> Vector3)?, spin: number, swirl: number }
local flying: { Fly } = {}
type Grow = { tile: Tile, start: number }
local growing: { Grow } = {}
local shaking: { [Tile]: number } = {}
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

local function setGoldLook(tile: Tile, on: boolean)
	local zg = Grid.zoneGridOfId(tile.id)
	local ground = zg and zg.Zone.Ground or DEFAULT_GROUND
	tile.decal.Texture = image(if on then GOLD_IMAGE else ground[math.floor(Grid.hash(tile.id, 3) * #ground) + 1])
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
	local tile: Tile = { id = id, part = part, decal = decal, base = base, size = s, trashScale = 1 }
	setGoldLook(tile, golden[id] == true)
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

local function release(tile: Tile)
	if tiles[tile.id] == tile then
		tiles[tile.id] = nil
	end
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

-- Where a player's sweeper swallows leaves: the car's brush, the tool's tip, or the player.
local function suctionPoint(character: Model): (() -> Vector3)?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	local seat = humanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") and seat.Parent then
		local brush = seat.Parent:FindFirstChild("Brush", true)
		local part: BasePart = if brush and brush:IsA("BasePart") then brush else seat
		return function()
			return part.Position
		end
	end
	local tool = character:FindFirstChildOfClass("Tool")
	local handle = tool and tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		local tip = handle:FindFirstChild("Tip")
		if tip and tip:IsA("Attachment") then
			return function()
				return tip.WorldPosition
			end
		end
		return function()
			return handle.Position
		end
	end
	return function()
		return root.Position
	end
end

local function flyAway(tile: Tile, target: (() -> Vector3)?)
	tiles[tile.id] = nil
	shaking[tile] = nil
	local from = tile.part.CFrame
	table.insert(flying, {
		tile = tile,
		start = os.clock() + Grid.hash(tile.id, 10) * 0.08, -- a little stagger so they stream in
		from = from,
		target = target,
		spin = (Grid.hash(tile.id, 9) - 0.5) * 18,
		swirl = Grid.hash(tile.id, 11) * math.pi * 2,
	})
	burstPart.Position = from.Position
	local e = bursts[burstKind(tile.id)]
	if e then
		e:Emit(if golden[tile.id] then 6 else 2)
	end
end

local HOP = 0.25 -- part of the flight spent hopping up before the pull starts

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
		tile.part.CFrame = cf
		tile.part.Size = tile.size * Vector3.new(k, 1, k)
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
		if t >= 1 then
			tile.part.Size = tile.size
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
				if tile.trash and tile.trashBase then
					tile.trash:PivotTo(tile.trashBase)
				end
			end
			continue
		end
		local a = math.sin(t * math.pi * 6) * 0.12 * (1 - t)
		local lift = math.sin(t * math.pi) * 0.25
		tile.part.CFrame = tile.base * CFrame.new(0, lift, 0) * CFrame.Angles(a * 0.5, a, 0)
		if tile.trash and tile.trashBase then
			tile.trash:PivotTo(tile.trashBase * CFrame.new(0, lift * 1.5, 0) * CFrame.Angles(a, 0, a))
		end
	end
end

------------------------------------------------------------------ server events

local function onCleared(packed: buffer)
	local at = focus()
	-- Everyone sweeping nearby: their cleared leaves get sucked into their tool or car.
	local sweepers: { { root: Vector3, target: () -> Vector3 } } = {}
	if at then
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and root and root:IsA("BasePart") and (root.Position - at).Magnitude < FLY_DISTANCE + SUCK_RANGE then
				local target = suctionPoint(character)
				if target then
					table.insert(sweepers, { root = root.Position, target = target })
				end
			end
		end
	end
	for _, id in Grid.unpack(packed) do
		cleared[id] = true
		local tile = tiles[id]
		if tile then
			local p = tile.base.Position
			local near = at ~= nil and (p - at).Magnitude < FLY_DISTANCE
			if near and #flying < MAX_FLYING then
				local best, bestD = nil, SUCK_RANGE
				for _, s in sweepers do
					local d = (s.root - p).Magnitude
					if d < bestD then
						best, bestD = s.target, d
					end
				end
				flyAway(tile, best)
			else
				release(tile)
			end
		end
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

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		stepFlying(now)
		stepGrowing(now)
		stepShaking(now)
		if not ready then
			return
		end
		acc += dt
		if acc > 0.25 then
			acc = 0
			refreshChunks()
		end
		buildSome()
	end)
end

return LeafController
