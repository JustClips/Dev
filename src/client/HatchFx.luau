--!strict
-- Effects for the egg hatch show (HatchController): our own Blender meshes
-- (art/blender/hatch_vfx.py) tinted and animated in code, flying brick shards, particles,
-- and a camera rig that leans the player's camera toward the egg without taking it away.
--
-- Everything works both in the world and inside the Hatch window's ViewportFrame (there
-- particles don't render and physics doesn't run, so shards are moved by hand).
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetLibrary = require(ReplicatedStorage:WaitForChild("Shared").AssetLibrary)

local HatchFx = {}

local WHITE = Color3.new(1, 1, 1)
local rng = Random.new()

------------------------------------------------------------------ meshes

local sources: { [string]: MeshPart } = {}

-- A fresh copy of one of the VFX meshes, or nil while it hasn't loaded.
local function mesh(name: string): MeshPart?
	local src = sources[name]
	if not src then
		local model = AssetLibrary.get(name)
		local part = model and model:FindFirstChildWhichIsA("MeshPart")
		if not part then
			return nil
		end
		part.Parent = nil
		sources[name] = part
		src = part
	end
	local m = src:Clone()
	m.Anchored = true
	m.CanCollide = false
	m.CanQuery = false
	m.CanTouch = false
	m.CastShadow = false
	m.TextureID = ""
	return m
end
HatchFx.mesh = mesh

-- A glowing VFX mesh (Neon, tinted).
local function glowMesh(name: string, color: Color3, parent: Instance): MeshPart?
	local m = mesh(name)
	if not m then
		return nil
	end
	m.Material = Enum.Material.Neon
	m.Color = color
	m.Parent = parent
	return m
end

------------------------------------------------------------------ colours

-- Brick colours of each egg's shell (art/blender/eggs.py), for the shards.
local SHELL: { [string]: { Color3 } } = {
	Common = { Color3.fromHex("FFF4DE"), Color3.fromHex("F2E4C6"), Color3.fromHex("B98B5E") },
	Uncommon = { Color3.fromHex("8FDF7A"), Color3.fromHex("6CC85E"), Color3.fromHex("3E9E46"), WHITE },
	Rare = { Color3.fromHex("7DBDFF"), Color3.fromHex("BFE0FF"), Color3.fromHex("4A84F2"), WHITE },
	Epic = { Color3.fromHex("C891FF"), Color3.fromHex("A66BFF"), Color3.fromHex("F3BFFF"), WHITE },
	Legendary = { Color3.fromHex("FFD24D"), Color3.fromHex("FFC83A"), Color3.fromHex("FFE58C"), WHITE },
	Mythic = { Color3.fromHex("3B2034"), Color3.fromHex("57304D"), Color3.fromHex("FF7A3C"), Color3.fromHex("45283D") },
	Cosmic = { Color3.fromHex("8FB8FF"), Color3.fromHex("B49CF6"), Color3.fromHex("9FF7FF"), Color3.fromHex("E7A8F2"), Color3.fromHex("F4F7FF") },
}

function HatchFx.shellColor(eggRarity: string): Color3
	local list = SHELL[eggRarity] or SHELL.Common
	return list[rng:NextInteger(1, #list)]
end

------------------------------------------------------------------ one frame loop for everything

type Updater = (dt: number) -> boolean -- return false when done
local updaters: { Updater } = {}
local loop: RBXScriptConnection? = nil

local function run(fn: Updater)
	table.insert(updaters, fn)
	if not loop then
		loop = RunService.RenderStepped:Connect(function(dt)
			for i = #updaters, 1, -1 do
				local ok, alive = pcall(updaters[i], dt)
				if not ok or not alive then
					table.remove(updaters, i)
				end
			end
			if #updaters == 0 and loop then
				loop:Disconnect()
				loop = nil
			end
		end)
	end
end
HatchFx.run = run

-- Tween-like helper: fn(alpha) each frame over `seconds`, then done().
function HatchFx.over(seconds: number, fn: (number) -> (), done: (() -> ())?)
	local t = 0
	run(function(dt)
		t += dt
		local a = math.clamp(t / seconds, 0, 1)
		fn(a)
		if a >= 1 then
			if done then
				done()
			end
			return false
		end
		return true
	end)
end

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end

------------------------------------------------------------------ effects

-- A shockwave ring racing out along the ground from `at` (bottom centre).
function HatchFx.shockwave(parent: Instance, at: CFrame, color: Color3, radius: number, seconds: number?, height: number?)
	local life = seconds or 0.6
	local ring = glowMesh("VfxHatchRing", color, parent)
	if not ring then
		-- Fallback: a flat neon cylinder.
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Parent = parent
		HatchFx.over(life, function(a)
			local r = 1 + (radius - 1) * easeOut(a)
			p.Size = Vector3.new(0.2, r * 2, r * 2)
			p.CFrame = at * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90))
			p.Transparency = 0.2 + 0.8 * a
		end, function()
			p:Destroy()
		end)
		return
	end
	local r0 = math.max(0.5, radius * 0.08)
	local h = height or math.max(0.4, radius * 0.12)
	HatchFx.over(life, function(a)
		local r = r0 + (radius - r0) * easeOut(a)
		ring.Size = Vector3.new(r * 2, h * (1 - a * 0.6), r * 2)
		ring.CFrame = at * CFrame.new(0, ring.Size.Y / 2, 0)
		ring.Transparency = 0.05 + 0.95 * a ^ 1.4
	end, function()
		ring:Destroy()
	end)
end

-- Brick shards flying off the egg: they spin, fall, bounce once on the ground and fade.
-- `from` is the egg centre, `floorY` the ground height.
type Shard = { part: BasePart, pos: Vector3, vel: Vector3, rot: CFrame, axis: Vector3, spin: number, size: Vector3, age: number, life: number, bounced: number }

function HatchFx.shards(parent: Instance, from: Vector3, floorY: number, eggRarity: string, count: number, speed: number, scale: number)
	local list: { Shard } = {}
	for i = 1, count do
		local kind = if i % 7 == 0 then "VfxShellChunk" elseif i % 3 == 0 then "VfxBrick2x1" else "VfxBrick1x1"
		local part: BasePart? = mesh(kind)
		local unit = scale * (if kind == "VfxShellChunk" then 0.55 else 0.42) * rng:NextNumber(0.8, 1.2)
		if not part then
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Size = Vector3.new(1, 0.7, 1)
			part = p
		end
		local s = part :: BasePart
		local size = s.Size * unit
		s.Size = size
		s.Material = Enum.Material.SmoothPlastic
		s.Color = HatchFx.shellColor(eggRarity)
		s.Parent = parent
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.15, 1.2), rng:NextNumber(-1, 1))
		if dir.Magnitude < 0.05 then
			dir = Vector3.yAxis
		end
		dir = dir.Unit
		table.insert(list, {
			part = s,
			pos = from + dir * scale * 0.6,
			vel = dir * speed * rng:NextNumber(0.55, 1.15),
			rot = CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)),
			axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit,
			spin = rng:NextNumber(6, 16),
			size = size,
			age = 0,
			life = rng:NextNumber(1.3, 2.1),
			bounced = 0,
		})
	end
	local gravity = 60 * math.max(0.4, scale / 2)
	run(function(dt)
		local alive = false
		for _, sh in list do
			if sh.age >= sh.life then
				continue
			end
			alive = true
			sh.age += dt
			sh.vel += Vector3.new(0, -gravity * dt, 0)
			sh.vel *= (1 - 0.6 * dt)
			sh.pos += sh.vel * dt
			local half = sh.size.Y * 0.5
			if sh.pos.Y < floorY + half then
				sh.pos = Vector3.new(sh.pos.X, floorY + half, sh.pos.Z)
				if sh.bounced < 2 and sh.vel.Y < -2 then
					sh.vel = Vector3.new(sh.vel.X * 0.6, -sh.vel.Y * 0.35, sh.vel.Z * 0.6)
					sh.bounced += 1
				else
					sh.vel = Vector3.new(sh.vel.X * 0.85, 0, sh.vel.Z * 0.85)
					sh.spin *= 0.9
				end
			end
			sh.rot = CFrame.fromAxisAngle(sh.axis, sh.spin * dt) * sh.rot
			local left = sh.life - sh.age
			local fade = math.clamp(left / 0.35, 0, 1)
			sh.part.Size = sh.size * math.max(0.05, fade)
			sh.part.CFrame = CFrame.new(sh.pos) * sh.rot
			if sh.age >= sh.life then
				sh.part:Destroy()
			end
		end
		return alive
	end)
end

-- Light rays poking out of the egg through its cracks. Returns a setter (power 0-1+,
-- color) and a remover.
function HatchFx.lightLeak(parent: Instance, center: Vector3, radius: number): ((number, Color3) -> (), () -> ())
	local spikes = glowMesh("VfxHatchSpikes", WHITE, parent)
	local power, color = 0, WHITE
	local angle = 0
	if spikes then
		spikes.Transparency = 1
		run(function(dt)
			if not spikes.Parent then
				return false
			end
			angle += dt * (0.6 + power * 1.4)
			local r = radius * (0.55 + 0.75 * power)
			spikes.Size = Vector3.new(r * 2, r * 2, r * 2)
			spikes.CFrame = CFrame.new(center) * CFrame.Angles(0, angle, 0)
			spikes.Color = color
			spikes.Transparency = if power <= 0.01 then 1 else 0.15
			return true
		end)
	end
	return function(p: number, c: Color3)
		power, color = p, c
	end, function()
		if spikes then
			spikes:Destroy()
		end
	end
end

-- A ribbon of energy spiralling up around the egg (Rare and up). Returns a setter
-- (speed, tighten 0-1, color) and a remover.
function HatchFx.swirl(parent: Instance, at: CFrame, radius: number, height: number): ((number, number, Color3) -> (), () -> ())
	local parts: { MeshPart } = {}
	for i = 1, 1 do -- one ribbon (two was too busy)
		local s = glowMesh("VfxHatchSwirl", WHITE, parent)
		if s then
			s.Transparency = 1
			table.insert(parts, s)
		end
	end
	local speed, tight, color = 2, 0, WHITE
	local angle, born = 0, 0
	run(function(dt)
		if #parts == 0 or not parts[1].Parent then
			return false
		end
		born = math.min(1, born + dt * 3)
		angle += dt * speed
		for i, s in parts do
			local r = radius * (1 - 0.45 * tight) * (if i == 2 then 0.8 else 1)
			local h = height * (0.5 + 0.5 * born) * (if i == 2 then 0.85 else 1)
			s.Size = Vector3.new(r * 2, h, r * 2)
			local turn = if i == 2 then -angle * 1.3 + math.pi else angle
			s.CFrame = at * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, turn, 0)
			s.Color = color
			s.Transparency = 1 - born * (if i == 2 then 0.45 else 0.7)
		end
		return true
	end)
	return function(sp: number, t: number, c: Color3)
		speed, tight, color = sp, t, c
	end, function()
		for _, s in parts do
			local part = s
			HatchFx.over(0.25, function(a)
				part.Transparency = 0.3 + 0.7 * a
			end, function()
				part:Destroy()
			end)
		end
	end
end

-- A pillar of light shooting up from the egg into the sky (Legendary and up).
function HatchFx.pillar(parent: Instance, at: CFrame, radius: number, height: number, color: Color3): (() -> ())
	local outer = glowMesh("VfxHatchPillar", color, parent)
	local inner = glowMesh("VfxHatchPillar", WHITE, parent)
	if not outer or not inner then
		if outer then
			outer:Destroy()
		end
		if inner then
			inner:Destroy()
		end
		return function() end
	end
	local o, n = outer :: MeshPart, inner :: MeshPart
	local t = 0
	local fading = false
	local fadeT = 0
	run(function(dt)
		if not o.Parent then
			return false
		end
		t += dt
		local grow = easeOut(math.clamp(t / 0.35, 0, 1))
		local pulse = 1 + 0.06 * math.sin(t * 14)
		local h = height * grow
		local fade = 0
		if fading then
			fadeT += dt
			fade = math.clamp(fadeT / 0.5, 0, 1)
		end
		o.Size = Vector3.new(radius * 2 * pulse, h, radius * 2 * pulse)
		o.CFrame = at * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, t * 2, 0)
		o.Transparency = 0.45 + 0.55 * fade
		n.Size = Vector3.new(radius * 1.1, h * 1.02, radius * 1.1)
		n.CFrame = at * CFrame.new(0, h * 1.02 / 2, 0)
		n.Transparency = 0.2 + 0.8 * fade
		if fade >= 1 then
			o:Destroy()
			n:Destroy()
			return false
		end
		return true
	end)
	return function()
		fading = true
	end
end

-- A crown of spikes bursting up out of the ground around the egg (Legendary and up).
function HatchFx.crown(parent: Instance, at: CFrame, radius: number, height: number, color: Color3)
	local c = glowMesh("VfxHatchCrown", color, parent)
	if not c then
		return
	end
	local crown = c :: MeshPart
	HatchFx.over(1.1, function(a)
		local up = if a < 0.25 then easeOut(a / 0.25) else 1 - math.clamp((a - 0.6) / 0.4, 0, 1)
		local h = height * up
		crown.Size = Vector3.new(radius * 2 * (1 + 0.15 * a), math.max(0.05, h), radius * 2 * (1 + 0.15 * a))
		crown.CFrame = at * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, a * 1.2, 0)
		crown.Transparency = 0.1 + 0.6 * a
	end, function()
		crown:Destroy()
	end)
end

-- A big sparkle star flash facing the camera at the moment of the burst.
function HatchFx.starFlash(parent: Instance, at: Vector3, size: number, color: Color3, camera: Camera)
	for i = 1, 2 do
		local s = glowMesh("VfxHatchStar", if i == 1 then color else WHITE, parent)
		if not s then
			return
		end
		local star = s :: MeshPart
		local k = if i == 1 then 1 else 0.6
		HatchFx.over(0.45, function(a)
			local grow = if a < 0.3 then easeOut(a / 0.3) else 1 - (a - 0.3) / 0.7
			local d = size * k * math.max(0.02, grow)
			star.Size = Vector3.new(d * 2, d * 2, d * 0.4)
			local face = CFrame.lookAt(at, camera.CFrame.Position)
			star.CFrame = face * CFrame.Angles(0, 0, a * (if i == 1 then 1.5 else -2))
			star.Transparency = 0.05 + 0.4 * a
		end, function()
			star:Destroy()
		end)
	end
end

-- Little stars orbiting the revealed pet (Epic and up). Returns a remover.
function HatchFx.orbitStars(parent: Instance, center: Vector3, radius: number, color: Color3, count: number): (() -> ())
	local stars: { MeshPart } = {}
	for i = 1, count do
		local s = glowMesh("VfxHatchStar", if i % 2 == 0 then WHITE else color, parent)
		if s then
			table.insert(stars, s)
		end
	end
	local t = 0
	local fade = -1
	run(function(dt)
		if #stars == 0 or not stars[1].Parent then
			return false
		end
		t += dt
		if fade >= 0 then
			fade += dt * 3
		end
		local grow = math.clamp(t * 3, 0, 1) * (if fade >= 0 then math.max(0, 1 - fade) else 1)
		for i, s in stars do
			local a = t * 1.6 + i / #stars * math.pi * 2
			local y = math.sin(t * 2.2 + i) * radius * 0.25
			local p = center + Vector3.new(math.cos(a) * radius, y, math.sin(a) * radius)
			local d = radius * 0.16 * (0.85 + 0.3 * math.sin(t * 6 + i)) * grow
			s.Size = Vector3.new(d * 2, d * 2, d * 0.5)
			s.CFrame = CFrame.new(p) * CFrame.Angles(0, -a, t * 3)
		end
		if fade >= 1 then
			for _, s in stars do
				s:Destroy()
			end
			return false
		end
		return true
	end)
	return function()
		fade = 0
	end
end

------------------------------------------------------------------ particles (world only)

local function anchorAt(parent: Instance, at: Vector3): (Part, Attachment)
	local p = Instance.new("Part")
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = CFrame.new(at)
	p.Parent = parent
	local a = Instance.new("Attachment")
	a.Parent = p
	return p, a
end

-- Sparks sucked into the egg while it charges. Returns a stopper.
function HatchFx.suckIn(parent: Instance, center: Vector3, radius: number, color: Color3, rate: number): (() -> ())
	local p = Instance.new("Part")
	p.Transparency = 1
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = CFrame.new(center)
	p.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Texture = AssetLibrary.image("Vfx_Sparkle")
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	e.Speed = NumberRange.new(radius * 1.6, radius * 2.2)
	e.Lifetime = NumberRange.new(0.4, 0.5)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0), NumberSequenceKeypoint.new(1, 0.2) })
	e.Color = ColorSequence.new(WHITE, color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = rate
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = p
	return function()
		e.Enabled = false
		task.delay(0.6, function()
			p:Destroy()
		end)
	end
end

-- A burst of sparkles and glowing dust from a point.
function HatchFx.burst(parent: Instance, at: Vector3, color: Color3, count: number, speed: number)
	local p, a = anchorAt(parent, at)
	local spark = Instance.new("ParticleEmitter")
	spark.Texture = AssetLibrary.image("Vfx_Star")
	spark.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.3, color), ColorSequenceKeypoint.new(1, color) })
	spark.LightEmission = 1
	spark.LightInfluence = 0
	spark.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
	spark.Lifetime = NumberRange.new(0.6, 1.3)
	spark.Speed = NumberRange.new(speed * 0.5, speed)
	spark.SpreadAngle = Vector2.new(180, 180)
	spark.Drag = 3
	spark.Acceleration = Vector3.new(0, -10, 0)
	spark.Rotation = NumberRange.new(0, 360)
	spark.RotSpeed = NumberRange.new(-260, 260)
	spark.Rate = 0
	spark.Parent = a
	spark:Emit(count)
	local puff = Instance.new("ParticleEmitter")
	puff.Texture = AssetLibrary.image("Vfx_Glow")
	puff.Color = ColorSequence.new(color)
	puff.LightEmission = 0.8
	puff.LightInfluence = 0
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	puff.Lifetime = NumberRange.new(0.5, 0.8)
	puff.Speed = NumberRange.new(speed * 0.2, speed * 0.4)
	puff.SpreadAngle = Vector2.new(180, 180)
	puff.Drag = 4
	puff.Rate = 0
	puff.Parent = a
	puff:Emit(math.ceil(count / 4))
	task.delay(1.8, function()
		p:Destroy()
	end)
end

-- Dust kicked up from the ground in a ring.
function HatchFx.dust(parent: Instance, at: Vector3, radius: number, count: number)
	local p = Instance.new("Part")
	p.Transparency = 1
	p.Size = Vector3.new(radius * 2, 0.2, radius * 2)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = CFrame.new(at)
	p.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Texture = AssetLibrary.image("Vfx_Glow")
	e.Color = ColorSequence.new(Color3.fromRGB(235, 225, 205))
	e.LightInfluence = 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.6, 1)
	e.Speed = NumberRange.new(3, 7)
	e.SpreadAngle = Vector2.new(70, 70)
	e.EmissionDirection = Enum.NormalId.Top
	e.Drag = 3
	e.Rate = 0
	e.Parent = p
	e:Emit(count)
	task.delay(1.2, function()
		p:Destroy()
	end)
end

-- Gold confetti raining down over the egg (Legendary and up).
function HatchFx.confettiRain(parent: Instance, at: Vector3, radius: number, colors: { Color3 }, seconds: number)
	local p = Instance.new("Part")
	p.Transparency = 1
	p.Size = Vector3.new(radius * 2, 0.2, radius * 2)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = CFrame.new(at)
	p.Parent = parent
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), c))
	end
	if #keys < 2 then
		keys = { ColorSequenceKeypoint.new(0, colors[1] or WHITE), ColorSequenceKeypoint.new(1, colors[1] or WHITE) }
	end
	local e = Instance.new("ParticleEmitter")
	e.Texture = AssetLibrary.image("Vfx_Confetti")
	e.Color = ColorSequence.new(keys)
	e.LightEmission = 0.3
	e.Size = NumberSequence.new(0.45)
	e.Lifetime = NumberRange.new(2.2, 3)
	e.Speed = NumberRange.new(1, 3)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.SpreadAngle = Vector2.new(25, 25)
	e.Acceleration = Vector3.new(0, -6, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-300, 300)
	e.Rate = 60
	e.Parent = p
	task.delay(seconds, function()
		e.Enabled = false
	end)
	task.delay(seconds + 3.2, function()
		p:Destroy()
	end)
end

------------------------------------------------------------------ the world darkens (Mythic and up)

function HatchFx.darken(color: Color3, seconds: number): (() -> ())
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "HatchDarken"
	cc.Parent = Lighting
	local target = { Brightness = -0.14, Contrast = 0.1, Saturation = -0.25, TintColor = Color3.new(1, 1, 1):Lerp(color, 0.25) }
	TweenService:Create(cc, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), target):Play()
	return function()
		local t = TweenService:Create(cc, TweenInfo.new(0.5), { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE })
		t:Play()
		t.Completed:Once(function()
			cc:Destroy()
		end)
	end
end

------------------------------------------------------------------ camera rig

-- Leans the player's camera toward a shot of the egg (weight 0 = your camera, 1 = the shot)
-- and adds shake and a zoom punch. The camera scripts read camera.CFrame back each frame,
-- so the rig puts their own result back just before they run (step "Pre") and only then
-- bends it (step "Post"): the player's camera never drifts and comes straight back.
export type Rig = {
	weight: (number, number) -> (), -- target weight, seconds to get there
	shake: (number, number) -> (), -- power (studs), seconds
	punch: (number) -> (), -- field of view kick (degrees, negative = zoom in)
	orbit: (number) -> (), -- degrees per second around the egg
	stop: () -> (),
}

local RIG_NAME = "HatchCameraRig"

function HatchFx.cameraRig(focus: Vector3, distance: number, ignore: { Instance }): Rig
	local camera = Workspace.CurrentCamera :: Camera
	local weight, from, to, blendT, blendLen = 0, 0, 0, 1, 1
	local shakeP, shakeUntil, shakeLen = 0, 0, 1
	local fovKick = 0
	local orbitSpeed, orbitAngle = 0, 0
	local baseFov = camera.FieldOfView
	local lastOffset = 0
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	-- Shot direction: from the egg toward where the camera was when the show started.
	local flat = camera.CFrame.Position - focus
	flat = Vector3.new(flat.X, 0, flat.Z)
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, 1)

	local playerCFrame: CFrame? = nil
	RunService:UnbindFromRenderStep(RIG_NAME .. "Pre")
	RunService:UnbindFromRenderStep(RIG_NAME)
	RunService:BindToRenderStep(RIG_NAME .. "Pre", Enum.RenderPriority.Camera.Value - 1, function()
		if playerCFrame and camera.CameraType == Enum.CameraType.Custom then
			camera.CFrame = playerCFrame
		end
	end)
	RunService:BindToRenderStep(RIG_NAME, Enum.RenderPriority.Camera.Value + 2, function(dt)
		if camera.CameraType ~= Enum.CameraType.Custom then
			playerCFrame = nil
			return
		end
		playerCFrame = camera.CFrame
		blendT = math.min(blendLen, blendT + dt)
		local a = blendT / blendLen
		a = a * a * (3 - 2 * a)
		weight = from + (to - from) * a
		orbitAngle += math.rad(orbitSpeed) * dt
		local player = camera.CFrame
		local out = player
		if weight > 0.001 then
			local d = (CFrame.Angles(0, orbitAngle, 0) * dir)
			local want = focus + d * distance + Vector3.new(0, distance * 0.32, 0)
			local hit = Workspace:Raycast(focus, want - focus, params)
			if hit then
				want = hit.Position + (focus - hit.Position).Unit * 0.8
			end
			local shot = CFrame.lookAt(want, focus)
			out = player:Lerp(shot, weight)
		end
		local now = os.clock()
		if now < shakeUntil then
			local p = shakeP * math.clamp((shakeUntil - now) / shakeLen, 0, 1)
			out *= CFrame.new(rng:NextNumber(-p, p), rng:NextNumber(-p, p), 0) * CFrame.Angles(rng:NextNumber(-p, p) * 0.02, rng:NextNumber(-p, p) * 0.02, 0)
		end
		camera.CFrame = out
		fovKick *= math.exp(-dt * 6)
		local offset = fovKick
		if math.abs(offset - lastOffset) > 0.01 then
			camera.FieldOfView = math.clamp(camera.FieldOfView - lastOffset + offset, 20, 110)
			lastOffset = offset
		end
	end)
	local rig: Rig
	rig = {
		weight = function(w: number, seconds: number)
			from = weight
			to = w
			blendT = 0
			blendLen = math.max(0.01, seconds)
		end,
		shake = function(power: number, seconds: number)
			shakeP = math.max(power, if os.clock() < shakeUntil then shakeP else 0)
			shakeLen = seconds
			shakeUntil = os.clock() + seconds
		end,
		punch = function(degrees: number)
			fovKick += degrees
		end,
		orbit = function(speed: number)
			orbitSpeed = speed
		end,
		stop = function()
			RunService:UnbindFromRenderStep(RIG_NAME .. "Pre")
			RunService:UnbindFromRenderStep(RIG_NAME)
			if playerCFrame and camera.CameraType == Enum.CameraType.Custom then
				camera.CFrame = playerCFrame
			end
			if math.abs(lastOffset) > 0.001 then
				camera.FieldOfView = math.clamp(camera.FieldOfView - lastOffset, 20, 110)
			end
			lastOffset = 0
			if math.abs(camera.FieldOfView - baseFov) < 0.5 then
				camera.FieldOfView = baseFov
			end
		end,
	}
	return rig
end

return HatchFx
