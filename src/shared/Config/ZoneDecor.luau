--!strict
-- Landmarks inside each zone's leaf field (Blender models from art/blender/landmarks.py,
-- placed by MapBuilder.buildProps). Each one is an island: no leaves grow within Clear
-- studs of it (Zones.luau adds the exclusions), so the field still has plenty to sweep.
--
-- At = (x, d): x across the zone (-120..120), d = studs in from the gate edge (zone Max.Z).
-- Keep x -14..14 near d 0..20 free for the entrance and the quest NPC at (16, 10).
-- Yaw: 180 faces the gate, -90 faces +X (use on the left side), 90 faces -X (right side).
-- Clear is the no-leaves radius (0 = leaves grow right up to it, for thin things).

-- Holes: extra no-leaf circles (x, d offsets from At, z = radius) for wide pieces whose
-- footprint is only a few posts, like the ski lift towers.
export type Decor = { Asset: string, At: Vector2, Yaw: number, Clear: number, Scale: number?, Holes: { Vector3 }? }

local function d(asset: string, x: number, dist: number, yaw: number, clear: number, scale: number?): Decor
	return { Asset = asset, At = Vector2.new(x, dist), Yaw = yaw, Clear = clear, Scale = scale }
end

local ZoneDecor: { [string]: { Decor } } = {}

-- Park (id Crater): fountain plaza in the middle, playground, duck pond, gazebo, picnics.
ZoneDecor.Crater = {
	d("Park_Fountain", 0, 105, 180, 11.5),
	d("Park_FlowerBed", -17, 88, 0, 4),
	d("Park_FlowerBed", 17, 88, 0, 4),
	d("Park_FlowerBed", -17, 122, 0, 4),
	d("Park_FlowerBed", 17, 122, 0, 4),
	d("Park_Bench", -14, 105, -90, 2.5), -- benches facing the fountain
	d("Park_Bench", 14, 105, 90, 2.5),
	d("Park_Playground", -70, 58, 180, 13),
	d("Park_DuckPond", 70, 60, 180, 12.5),
	d("Park_Bench", 70, 76, 180, 2.5),
	d("Park_Gazebo", 72, 160, 180, 8.5),
	d("Park_Picnic", -62, 140, 160, 4.5),
	d("Park_Picnic", -84, 158, 200, 4.5),
	d("Park_Picnic", -50, 172, 175, 4.5),
	d("Park_Lamp", -9, 30, 0, 1.5),
	d("Park_Lamp", 9, 50, 0, 1.5),
	d("Park_Lamp", -9, 70, 0, 1.5),
	d("Park_Lamp", -28, 105, 0, 1.5),
	d("Park_Lamp", 28, 105, 0, 1.5),
	d("Park_Lamp", 9, 140, 0, 1.5),
	d("Park_Lamp", -9, 165, 0, 1.5),
	d("Park_TreeRound", -104, 28, 30, 3, 1.2),
	d("Park_TreeTall", -100, 100, 120, 3, 1.3),
	d("Park_TreeAutumn", 104, 110, 80, 3, 1.25),
	d("Park_TreeRound", 100, 200, 10, 3, 1.3),
	d("Park_TreeTall", 30, 198, 200, 3, 1.25),
	d("Park_TreeAutumn", -30, 200, 40, 3, 1.25),
	d("Park_TreeAutumn", -104, 196, 70, 3, 1.2),
	d("Park_TreeRound", 40, 30, 150, 3, 1.1),
	d("Park_Rock1", 50, 175, 0, 3, 1.1),
	d("Park_Rock2", -40, 30, 0, 2.5, 1.2),
	d("Park_Rock1", -105, 140, 0, 3, 1.2),
	d("Park_Bush", -60, 105, 0, 2),
	d("Park_Bush", 60, 105, 0, 2),
	d("Park_TreeAutumn", 88, 48, 30, 3, 1.1),
	d("Park_TreeRound", -88, 78, 60, 3, 1.1),
	d("Park_Bench", 58, 160, -90, 2.5),
}

-- Beach (id DarkSide): hut row on the left, lifeguard tower, sandcastle, lighthouse at the back.
ZoneDecor.DarkSide = {
	d("Beach_HutA", -104, 30, -90, 5.5),
	d("Beach_HutB", -104, 48, -90, 5.5),
	d("Beach_HutC", -104, 66, -90, 5.5),
	d("Beach_HutA", -104, 84, -90, 5.5),
	d("Beach_HutB", -104, 102, -90, 5.5),
	d("Beach_Surfboards", -104, 122, -90, 3),
	d("Beach_Lifeguard", 0, 112, 180, 8),
	d("Beach_Sandcastle", 52, 92, 180, 7.5),
	d("Beach_IceCream", 100, 40, 90, 6),
	d("Beach_Volleyball", -50, 152, 90, 8),
	d("Beach_Boat", 72, 176, 30, 5),
	d("Beach_Lighthouse", 96, 196, 180, 9),
	d("Mushroom_Mars", 30, 42, 0, 4),
	d("Mushroom_Mars", -34, 62, 40, 4),
	d("Mushroom_Mars", -64, 100, 80, 4),
	d("Mushroom_Mars", 40, 140, 20, 4),
	d("Mushroom_Mars", -18, 186, 60, 4),
	d("Crystal_Red", 104, 72, 0, 2.5, 1.5),
	d("Crystal_Red", 104, 124, 140, 2.5, 1.7),
	d("Crystal_Red", -104, 172, 60, 2.5, 1.6),
	d("Crystal_Red", 50, 204, 220, 2.5, 1.5),
	d("Crystal_Red", -60, 204, 300, 2.5, 1.7),
	d("Rock_Mars2", 20, 160, 40, 4),
	d("Rock_Mars1", -80, 190, 0, 3),
}

-- City (id Mars): shop rows down both sides with street lamps, a hero statue in the middle.
ZoneDecor.Mars = {
	d("City_ShopA", -108, 32, -90, 9),
	d("City_ShopB", -108, 54, -90, 9),
	d("City_ShopC", -108, 76, -90, 9),
	d("City_ShopD", -108, 98, -90, 9),
	d("City_ShopB", -108, 120, -90, 9),
	d("City_ShopC", 108, 32, 90, 9),
	d("City_ShopD", 108, 54, 90, 9),
	d("City_ShopA", 108, 76, 90, 9),
	d("City_ShopC", 108, 98, 90, 9),
	d("City_ShopD", 108, 120, 90, 9),
	d("City_StreetLamp", -92, 43, -90, 1.2),
	d("City_StreetLamp", -92, 87, -90, 1.2),
	d("City_StreetLamp", -92, 131, -90, 1.2),
	d("City_StreetLamp", 92, 43, 90, 1.2),
	d("City_StreetLamp", 92, 87, 90, 1.2),
	d("City_StreetLamp", 92, 131, 90, 1.2),
	d("City_TrafficLight", -92, 150, -90, 1.2),
	d("City_TrafficLight", 92, 150, 90, 1.2),
	d("City_BusStop", -100, 168, -90, 5),
	d("City_Statue", 0, 108, 180, 6),
	d("Mushroom_Glow", -8, 100, -90, 2.5),
	d("Mushroom_Glow", 8, 100, 90, 2.5),
	d("City_HotDog", 42, 62, 200, 4),
	d("City_Newsstand", -42, 62, 160, 4),
	d("City_Billboard", -60, 204, 180, 3),
	d("City_Billboard", 60, 204, 180, 3),
	d("Crystal_Purple", 30, 150, 0, 1.5),
	d("Crystal_Purple", -30, 30, 0, 1.5),
	d("Rock_Dark1", 82, 170, 0, 1.5),
	d("Rock_Dark1", -82, 70, 0, 1.5),
	d("Rock_Dark2", 102, 172, 90, 4),
}

-- Snowy Peaks (id Europa): ski lodge, ski lift, frozen pond, igloo, snowmen, pines.
ZoneDecor.Europa = {
	d("Snow_Lodge", -96, 72, -90, 10.5),
	d("Snow_Cocoa", -34, 42, 160, 5),
	{ Asset = "Snow_SkiLift", At = Vector2.new(100, 80), Yaw = 0, Clear = 0, Holes = { Vector3.new(0, -18, 3), Vector3.new(0, 18, 3) } },
	d("Snow_FrozenPond", 0, 122, 180, 11.5),
	d("Snow_Igloo", 62, 168, 200, 6),
	d("Snow_Snowman", 24, 46, 200, 2),
	d("Snow_Snowman", -32, 118, 120, 2),
	d("Snow_Snowman", 70, 116, 250, 2),
	d("Snow_Snowman", -64, 182, 160, 2),
	d("Snow_Sled", -12, 64, 30, 2),
	d("Snow_Sled", 84, 150, 200, 2),
	d("Crystal_Ice", -104, 120, 0, 2.5, 1.8),
	d("Crystal_Ice", -96, 140, 60, 2.5, 1.5),
	d("Crystal_Ice", -108, 160, 120, 2.5, 2),
	d("Crystal_Ice", -100, 200, 20, 2.5, 1.7),
	d("Crystal_Ice", -30, 200, 90, 2.5, 1.9),
	d("Crystal_Ice", 20, 196, 0, 2.5, 1.6),
	d("Crystal_Ice", 104, 200, 45, 2.5, 2),
	d("Crystal_Ice", 104, 128, 10, 2.5, 1.7),
	d("Crystal_Ice", 50, 30, 80, 2.5, 1.5),
	d("Crystal_Ice", -60, 22, 30, 2.5, 1.6),
	d("Rock_Ice2", -40, 160, 30, 4),
	d("Rock_Ice1", 40, 90, 0, 3),
}

return ZoneDecor
