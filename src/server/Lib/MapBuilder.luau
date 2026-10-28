--!strict
-- Builds the map at server start from Config/World: terrain (moon ground, crater bowl,
-- pet-park moss, mountains) and every Blender prop (rocket, base pieces, fences, rocks).
-- Gameplay parts (pads, gates, walls) come from src/workspace/Moon instead.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local World = require(Shared.Config.World)
local Zones = require(Shared.Config.Zones)

local MapBuilder = {}

local M = Enum.Material

-- Terrain ------------------------------------------------------------------------

local function block(terrain: Terrain, cf: CFrame, size: Vector3, material: Enum.Material)
	terrain:FillBlock(cf, size, material)
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

-- Steps from fromY to toY along -Z between z0 and z1 (z0 > z1), inside a corridor.
local function stairs(terrain: Terrain, halfWidth: number, z0: number, z1: number, fromY: number, toY: number, material: Enum.Material)
	local steps = 8
	local dz = (z0 - z1) / steps
	local low = math.min(fromY, toY)
	block(terrain, CFrame.new(0, (low + math.max(fromY, toY)) / 2 + 4, (z0 + z1) / 2), Vector3.new(halfWidth * 2, math.abs(fromY - toY) + 8, z0 - z1), M.Air)
	for k = 1, steps do
		local top = fromY + (toY - fromY) * (k - 0.5) / steps
		local zc = z0 - (k - 0.5) * dz
		block(terrain, CFrame.new(0, (top + low - 12) / 2, zc), Vector3.new(halfWidth * 2, top - (low - 12), dz), material)
	end
end

function MapBuilder.buildTerrain()
	local terrain = Workspace.Terrain
	for name, color in World.TerrainColors do
		terrain:SetMaterialColor((M :: any)[name], color)
	end
	local rng = Random.new(42)

	-- One big slab of moon ground, then a top layer per area.
	block(terrain, CFrame.new(0, -20, -380), Vector3.new(1000, 40, 1800), M.Sand)
	block(terrain, CFrame.new(0, -4, -1000), Vector3.new(1000, 8, 560), M.Sandstone) -- Mars and beyond
	block(terrain, CFrame.new(0, -4, -596), Vector3.new(1000, 8, 252), M.Basalt) -- Dark Side band
	block(terrain, CFrame.new(0, -4, -342), Vector3.new(1000, 8, 256), M.Slate) -- Crater band

	-- Crater bowl: floor 8 studs down, with a raised rim around it.
	local crater = Zones.ById.Crater
	local cMin, cMax = crater.Min, crater.Max
	local cCenter = Vector3.new((cMin.X + cMax.X) / 2, 0, (cMin.Y + cMax.Y) / 2)
	local cSize = Vector2.new(cMax.X - cMin.X, cMax.Y - cMin.Y)
	block(terrain, CFrame.new(cCenter.X, -4, cCenter.Z), Vector3.new(cSize.X, 8, cSize.Y), M.Air)
	block(terrain, CFrame.new(cCenter.X, -12, cCenter.Z), Vector3.new(cSize.X, 8, cSize.Y), M.Slate)
	block(terrain, CFrame.new(cMin.X - 14, 2, cCenter.Z), Vector3.new(28, 4, cSize.Y + 56), M.Slate)
	block(terrain, CFrame.new(cMax.X + 14, 2, cCenter.Z), Vector3.new(28, 4, cSize.Y + 56), M.Slate)

	-- Corridors: paved, with stairs into and out of the crater.
	for _, c in World.Corridors do
		local zc = (c.Min.Y + c.Max.Y) / 2
		local len = c.Max.Y - c.Min.Y
		block(terrain, CFrame.new(0, -1, zc), Vector3.new(24, 2, len), M.Pavement)
		if c.FromY ~= c.ToY then
			if c.FromY > c.ToY then
				-- going down at the far (north) end of the corridor
				stairs(terrain, 12, c.Min.Y + len / 2, c.Min.Y, c.FromY, c.ToY, M.Pavement)
			else
				-- coming up at the near (south) end
				stairs(terrain, 12, c.Max.Y, c.Max.Y - len / 2, c.FromY, c.ToY, M.Pavement)
			end
		end
	end

	-- Hub: rocket plaza, base floors, pet-park moss, paths.
	terrain:FillCylinder(CFrame.new(World.RocketPosition + Vector3.new(0, -1, 0)), 2, World.SellRadius + 9, M.Pavement)
	for i = 1, World.BaseCount do
		local cf = World.baseCFrame(i)
		block(terrain, cf * CFrame.new(0, -1, 0), Vector3.new(World.BaseSize.X, 2, World.BaseSize.Y), M.Concrete)
		local pMin, pMax = World.Base.ParkMin, World.Base.ParkMax
		local parkCenter = (pMin + pMax) / 2
		block(terrain, cf * CFrame.new(parkCenter.X, -1, parkCenter.Y), Vector3.new(pMax.X - pMin.X, 2, pMax.Y - pMin.Y), M.Grass)
		block(terrain, cf * CFrame.new(0, -1, -36), Vector3.new(10, 2, 16), M.Pavement)
	end

	-- Mountains around everything.
	local hubX = World.BaseInner + World.BaseSize.Y + 2
	ridge(terrain, rng, Vector2.new(-hubX - 53, 250), Vector2.new(-hubX - 53, -210), M.Rock, 24, 22, 36, -6)
	ridge(terrain, rng, Vector2.new(hubX + 53, 250), Vector2.new(hubX + 53, -210), M.Rock, 24, 22, 36, -6)
	ridge(terrain, rng, Vector2.new(-hubX - 53, 258), Vector2.new(hubX + 53, 258), M.Rock, 24, 22, 36, -6)
	-- passes between zones
	for _, c in World.Corridors do
		local z = (c.Min.Y + c.Max.Y) / 2
		-- thin ridges so they never cover dust in the zones on either side
		ridge(terrain, rng, Vector2.new(30, z), Vector2.new(170, z), M.Rock, 10, 8, 11, 0)
		ridge(terrain, rng, Vector2.new(-30, z), Vector2.new(-170, z), M.Rock, 10, 8, 11, 0)
	end
	local zoneMaterial = { Crater = M.Slate, DarkSide = M.Basalt, Mars = M.Sandstone }
	for _, zone in Zones.List do
		local material = zoneMaterial[zone.Id]
		if material then
			ridge(terrain, rng, Vector2.new(zone.Min.X - 62, zone.Max.Y), Vector2.new(zone.Min.X - 62, zone.Min.Y), material, 24, 20, 34, -4)
			ridge(terrain, rng, Vector2.new(zone.Max.X + 62, zone.Max.Y), Vector2.new(zone.Max.X + 62, zone.Min.Y), material, 24, 20, 34, -4)
		end
	end
	local mars = Zones.ById.Mars
	ridge(terrain, rng, Vector2.new(mars.Min.X - 60, mars.Min.Y - 58), Vector2.new(mars.Max.X + 60, mars.Min.Y - 58), M.Sandstone, 24, 22, 36, -4)
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
		place(name, CFrame.new(x, y, z) * yaw(rng:NextNumber(0, 360)), rng:NextNumber(0.8, 2.0))
	end
end

function MapBuilder.buildProps()
	propsFolder = Instance.new("Folder")
	propsFolder.Name = "Props"
	propsFolder.Parent = Workspace
	local rng = Random.new(7)

	place("Rocket", CFrame.new(World.RocketPosition) * yaw(180))
	-- lamps along both sides of the field, flags by the rocket
	for z = -171, 171, 57 do
		place("Lamp", CFrame.new(-59, 0, z) * yaw(90))
		place("Lamp", CFrame.new(59, 0, z) * yaw(-90))
	end
	place("Flag", CFrame.new(-22, 0, 26) * yaw(20))
	place("Satellite", CFrame.new(24, 0, 30) * yaw(150))
	for _, z in { -120, 60 } do
		place("Satellite", CFrame.new(-190, 6, z) * yaw(rng:NextNumber(0, 360)), 1.6)
		place("Satellite", CFrame.new(190, 6, z + 40) * yaw(rng:NextNumber(0, 360)), 1.6)
	end
	-- zone gates (sign faces the hub)
	for _, c in World.Corridors do
		local gy = if c.Zone == "DarkSide" then 0 else c.FromY
		place("ZoneGate", CFrame.new(0, gy, c.GateZ) * yaw(180))
	end
	scatter(rng, Zones.ById.Crater, { "Rock_Crater1", "Rock_Crater2", "Crystal_Blue" }, 30)
	scatter(rng, Zones.ById.DarkSide, { "Rock_Dark1", "Rock_Dark2", "Crystal_Purple", "Mushroom_Glow" }, 30)
	scatter(rng, Zones.ById.Mars, { "Rock_Mars1", "Rock_Mars2", "Crystal_Red", "Mushroom_Mars" }, 30)

	for i = 1, World.BaseCount do
		MapBuilder.buildBase(i)
	end
end

return MapBuilder
