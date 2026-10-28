--!strict
-- Map layout. Studs, Roblox axes. The hub runs along Z: a long dust field with the Rocket
-- in the middle and 4 bases on each side (like Steal an Egg). Zones continue north (-Z),
-- each behind a gated corridor.
--
--   z = -1208 .. -992 Europa Ice           (TileSize 6)
--   z = -992 .. -956  corridor + Gate_Europa
--   z = -956 .. -740  Mars Plains          (TileSize 6)
--   z = -740 .. -704  corridor + Gate_Mars
--   z = -704 .. -488  Dark Side            (TileSize 6)
--   z = -488 .. -452  corridor + Gate_DarkSide
--   z = -452 .. -232  Crater (floor y = -8) (TileSize 5)
--   z = -232 .. -196  corridor + Gate_Crater
--   z = -196 ..  150  Landing Site dust field, Rocket launch pad at the origin
--   z =  150 ..  198  South plaza: Garage (west) and Upgrade station (east)
--   bases at x = +-62..150 on both sides of the field, on raised stud platforms
--
-- Base local frame: -Z points at the field (the entrance), +X is the base's right.
-- tools/gen_world.py writes src/workspace/Moon from these numbers, so keep them in sync.

local World = {}

World.Field = { Min = Vector2.new(-56, -196), Max = Vector2.new(56, 150) }
World.RocketPosition = Vector3.new(0, 0, 0)
World.SellRadius = 15
World.RocketClearRadius = 20
World.LaunchPadRadius = 18
World.Walkway = 6 -- paved strip between the dust field and the bases

-- South plaza (between the field and the hub's south wall).
World.Plaza = { Min = Vector2.new(-62, 150), Max = Vector2.new(62, 198) }
-- Stations face the field (-Z). Garage cars spawn on its pad and drive north.
World.Garage = CFrame.lookAt(Vector3.new(-34, 0, 178), Vector3.new(-34, 0, 100))
World.GarageSpawn = CFrame.lookAt(Vector3.new(-34, 0, 158), Vector3.new(-34, 0, 100))
World.UpgradeStation = CFrame.lookAt(Vector3.new(34, 0, 178), Vector3.new(34, 0, 100))

World.BaseCount = 8
World.BaseSize = Vector2.new(92, 88) -- width (local X), depth (local Z)
World.BaseInner = 62 -- distance from the hub centre line to a base's entrance edge
World.BaseFloorY = 1 -- bases sit on a 1-stud stud-plate platform
-- One colour per base: platform trim, corner lights and the name sign.
World.BaseColors = {
	Color3.fromRGB(76, 141, 255), -- blue
	Color3.fromRGB(255, 120, 60), -- orange
	Color3.fromRGB(61, 220, 90), -- green
	Color3.fromRGB(180, 110, 255), -- purple
	Color3.fromRGB(255, 200, 60), -- gold
	Color3.fromRGB(255, 90, 150), -- pink
	Color3.fromRGB(60, 210, 220), -- teal
	Color3.fromRGB(255, 77, 94), -- red
}

-- CFrame of base i on its platform floor, facing the field.
function World.baseCFrame(i: number): CFrame
	local side = if i <= 4 then -1 else 1
	local row = (i - 1) % 4
	local z = -147 + row * 98
	local x = side * (World.BaseInner + World.BaseSize.Y / 2)
	local pos = Vector3.new(x, World.BaseFloorY, z)
	return CFrame.lookAt(pos, Vector3.new(0, World.BaseFloorY, z))
end

-- Positions in the base local frame.
World.Base = {
	Arch = Vector3.new(0, 0, -42),
	Hatchery = Vector3.new(0, 0, -28),
	HatcheryRadius = 9,
	Spawn = Vector3.new(-18, 0, -31),
	Lamps = { Vector3.new(-40, 0, -40), Vector3.new(40, 0, -40) },
	Incubators = { Vector3.new(-13, 0, -24), Vector3.new(13, 0, -24) },
	-- The fenced pet park. Pets wander inside it.
	ParkMin = Vector2.new(-42, -14),
	ParkMax = Vector2.new(42, 42),
	ParkGateWidth = 12,
	-- Props inside the park. Radius keeps wandering pets out of them.
	ParkProps = {
		{ Asset = "Habitat", Position = Vector3.new(-29, 0, 31), Yaw = 200, Radius = 10 },
		{ Asset = "Pond", Position = Vector3.new(19, 0, 22), Yaw = 0, Radius = 7 },
		{ Asset = "Tree_Bulb", Position = Vector3.new(36, 0, -6), Yaw = 30, Radius = 3 },
		{ Asset = "Tree_Puff", Position = Vector3.new(-37, 0, 2), Yaw = 80, Radius = 3 },
		{ Asset = "Tree_Tall", Position = Vector3.new(4, 0, 37), Yaw = 140, Radius = 3 },
		{ Asset = "Mushroom_Glow", Position = Vector3.new(-12, 0, 12), Yaw = 0, Radius = 3 },
		{ Asset = "Rock_Moon1", Position = Vector3.new(34, 0, 36), Yaw = 60, Radius = 3 },
		{ Asset = "Crystal_Blue", Position = Vector3.new(-40, 0, 38), Yaw = 10, Radius = 2 },
		{ Asset = "Rock_Moon3", Position = Vector3.new(28, 0, 8), Yaw = 0, Radius = 1.5 },
	},
}

-- Incubator spots on the hatchery pad (local to the hatchery centre): a ring of 8,
-- starting at the front (facing the field) and going round.
World.HatchSpots = {}
for i = 0, 7 do
	local a = math.pi + i * math.pi / 4
	table.insert(World.HatchSpots, Vector3.new(math.sin(a) * 5.6, 0, math.cos(a) * 5.6))
end

-- Corridors between zones, with the gate across the middle.
World.Corridors = {
	{ Zone = "Crater", Min = Vector2.new(-12, -232), Max = Vector2.new(12, -196), GateZ = -205, FromY = 0, ToY = -8 },
	{ Zone = "DarkSide", Min = Vector2.new(-12, -488), Max = Vector2.new(12, -452), GateZ = -479, FromY = -8, ToY = 0 },
	{ Zone = "Mars", Min = Vector2.new(-12, -740), Max = Vector2.new(12, -704), GateZ = -713, FromY = 0, ToY = 0 },
	{ Zone = "Europa", Min = Vector2.new(-12, -992), Max = Vector2.new(12, -956), GateZ = -965, FromY = 0, ToY = 0 },
}

-- Teleport targets for the HUD buttons (Base uses your own spawn).
World.Teleports = {
	Rocket = CFrame.lookAt(Vector3.new(0, 4, 24), Vector3.new(0, 4, 0)),
	Crater = CFrame.lookAt(Vector3.new(0, -4, -240), Vector3.new(0, -4, -300)),
	DarkSide = CFrame.lookAt(Vector3.new(0, 4, -494), Vector3.new(0, 4, -560)),
	Mars = CFrame.lookAt(Vector3.new(0, 4, -746), Vector3.new(0, 4, -800)),
	Europa = CFrame.lookAt(Vector3.new(0, 4, -998), Vector3.new(0, 4, -1050)),
}

-- Terrain materials per area (colours are set at runtime).
World.TerrainColors = {
	Sand = Color3.fromRGB(176, 174, 168), -- moon regolith
	Slate = Color3.fromRGB(118, 132, 164), -- crater
	Basalt = Color3.fromRGB(62, 50, 88), -- dark side
	Sandstone = Color3.fromRGB(178, 92, 62), -- mars
	Glacier = Color3.fromRGB(170, 214, 240), -- europa ice
	Grass = Color3.fromRGB(88, 196, 160), -- alien moss in pet parks
	Concrete = Color3.fromRGB(196, 202, 214), -- base floors
	Pavement = Color3.fromRGB(120, 128, 148), -- paths
	Rock = Color3.fromRGB(132, 130, 126), -- moon mountains
}

-- Far away in the sky, built by each client.
World.EarthPosition = Vector3.new(-650, 420, -1100)
World.EarthScale = 22

return World
