--!strict
-- Small life for the zone decor (art/blender/parkdecor.py, beach.py, city.py, snowpeaks.py).
-- The server tags placed decor that has moving bits "ParkFx". This client then:
--   * plays each part listed in the model's meta "anim" about the part's joint:
--     sway / swing / spin (swings, reeds, flags, the lighthouse beam...), bounce (the beach
--     ball) and blink (traffic lights)
--   * sends critters round ellipses (meta fx.loops): ducks with ripples on the pond, crabs,
--     gulls, pigeons, penguins; and makes a pond fish jump now and then (fx.fish)
--   * puffs smoke or steam (fx.puffs) and runs ski lift chairs along the cable (fx.lifts)
--   * drops a few fluttering leaves from trees (fx.canopy, radius, leaves)
-- Everything is local and only runs while the camera is close.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)

local ParkFxController = {}

local TAG = "ParkFx"
local RANGE = 220

type Fx = { part: MeshPart, base: CFrame, size: Vector3 }
type Mover = {
	part: BasePart,
	base: CFrame,
	hub: CFrame,
	kind: string,
	amp: number,
	speed: number,
	axis: string,
	phase: number,
	on: boolean?,
	color: Color3,
	material: Enum.Material,
}
type Entry = { model: Model, folder: Folder, run: (number, number) -> (), visible: boolean, ref: BasePart? }

local entries: { [Model]: Entry } = {}
local root: Folder

local LEAF_COLORS = {
	autumn = { Color3.fromRGB(242, 138, 46), Color3.fromRGB(216, 88, 42), Color3.fromRGB(255, 194, 74) },
	round = { Color3.fromRGB(93, 187, 74), Color3.fromRGB(139, 216, 94), Color3.fromRGB(255, 194, 74) },
}

local function make(name: string, parent: Instance): Fx?
	local model = AssetLibrary.get(name)
	local part = model and model.PrimaryPart
	if not model or not part or not part:IsA("MeshPart") then
		if model then
			model:Destroy()
		end
		return nil
	end
	local base = part.PivotOffset:Inverse()
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	model:Destroy()
	return { part = part, base = base, size = part.Size }
end

local function put(fx: Fx, origin: CFrame, scale: Vector3)
	local b = fx.base
	fx.part.Size = fx.size * scale
	fx.part.CFrame = origin * CFrame.new(b.Position * scale) * b.Rotation
end

local function rotation(m: Mover, t: number): CFrame
	local w = math.pi * 2 * m.speed
	local a = math.rad(m.amp)
	if m.kind == "spin" then
		local angle = t * w + m.phase
		if m.axis == "x" then
			return CFrame.Angles(angle, 0, 0)
		elseif m.axis == "z" then
			return CFrame.Angles(0, 0, angle)
		end
		return CFrame.Angles(0, angle, 0)
	elseif m.kind == "swing" then
		local angle = a * math.sin(t * w + m.phase)
		if m.axis == "z" then
			return CFrame.Angles(0, 0, angle)
		end
		return CFrame.Angles(angle, 0, 0)
	end
	-- sway: around the vertical for "y", otherwise a gentle tilt in two directions
	if m.axis == "y" then
		return CFrame.Angles(0, a * math.sin(t * w + m.phase), 0)
	end
	return CFrame.Angles(a * math.sin(t * w + m.phase), 0, a * 0.6 * math.sin(t * w * 1.37 + m.phase + 1))
end

local PUFF_TINT = {
	smoke = Color3.fromRGB(196, 198, 206),
	steam = Color3.fromRGB(250, 252, 255),
	white = Color3.fromRGB(250, 252, 255),
}

local function build(model: Model): Entry?
	local meta = AssetLibrary.meta(model.Name) :: any
	if not meta then
		return nil
	end
	local pivot = model:GetPivot()
	local s = model:GetScale()
	local box = Instance.new("Folder")
	box.Name = model.Name
	box.Parent = root
	local seed = math.floor(pivot.Position.X * 7 + pivot.Position.Z * 13)
	local rng = Random.new(seed)
	local blinkOffset = rng:NextNumber()
	local live = 0

	-- parts that move about their joint, bounce or blink
	local movers: { Mover } = {}
	for partName, spec in (meta.anim or {}) :: { [string]: any } do
		local part = model:FindFirstChild(partName)
		local pm = meta.parts and meta.parts[partName]
		if part and part:IsA("BasePart") and pm and (pm.joint or spec.kind == "blink") then
			if string.sub(partName, 1, 4) == "Beam" then
				part.Transparency = 0.55
			end
			table.insert(movers, {
				part = part,
				base = pivot:ToObjectSpace(part.CFrame),
				hub = if pm.joint then CFrame.new(pm.joint * s) else CFrame.new(),
				kind = spec.kind,
				amp = spec.amp,
				speed = spec.speed,
				axis = spec.axis or "y",
				phase = if spec.kind == "blink"
					then (spec.phase or 0) + blinkOffset
					else (spec.phase or 0) + rng:NextNumber(0, math.pi * 2),
				color = part.Color,
				material = part.Material,
			})
		end
	end
	live += #movers

	local fx = meta.fx or {}

	-- critters going round an ellipse: ducks, crabs, gulls, pigeons, penguins
	type Walker = { fx: Fx, spec: any, centre: CFrame, wake: boolean, i: number }
	local walkers: { Walker } = {}
	local wakes: { { fx: Fx, at: CFrame, born: number } } = {}
	for i, spec in (fx.loops or {}) :: { any } do
		local f = make(spec.asset, box)
		if f then
			table.insert(
				walkers,
				{ fx = f, spec = spec, centre = pivot * CFrame.new(spec.center * s), wake = spec.wake == true, i = i }
			)
			if spec.wake and #wakes == 0 then
				for _ = 1, 4 do
					local r = make("FountainFx_Ripple", box)
					if r then
						r.part.Transparency = 1
						table.insert(wakes, { fx = r, at = CFrame.new(), born = -10 })
					end
				end
			end
		end
	end
	live += #walkers

	-- a pond fish that jumps now and then
	local fish: Fx?, fishSplash: Fx?, fishRipple: Fx?
	if fx.fish and #fx.fish > 0 then
		fish = make("PondFx_Fish", box)
		fishSplash = make("FountainFx_Splash", box)
		fishRipple = make("FountainFx_Ripple", box)
		if fish then
			live += 1
		end
	end

	-- smoke and steam puffs
	type Puff = { fx: Fx, at: Vector3, size: number, life: number, offset: number, drift: Vector3 }
	local puffs: { Puff } = {}
	for _, spec in (fx.puffs or {}) :: { any } do
		local n = 4
		local rate = math.max(spec.rate or 1, 0.1)
		local at = (pivot * CFrame.new(spec.at * s)).Position
		local a = rng:NextNumber(0, math.pi * 2)
		local drift = Vector3.new(math.cos(a), 0, math.sin(a))
		for k = 1, n do
			local f = make("ParkFx_Puff", box)
			if f then
				f.part.Material = Enum.Material.SmoothPlastic
				f.part.Color = PUFF_TINT[spec.tint] or PUFF_TINT.white
				table.insert(puffs, {
					fx = f,
					at = at,
					size = (spec.size or 1) * s,
					life = n / rate,
					offset = (k - 1) / rate,
					drift = drift,
				})
			end
		end
	end
	live += #puffs

	-- ski lift chairs riding the cable
	type Chair = { fx: Fx, from: Vector3, to: Vector3, speed: number, offset: number }
	local chairs: { Chair } = {}
	for _, spec in (fx.lifts or {}) :: { any } do
		local from = (pivot * CFrame.new(spec.from * s)).Position
		local to = (pivot * CFrame.new(spec.to * s)).Position
		for k = 1, spec.count or 3 do
			local f = make("SnowFx_Chair", box)
			if f then
				table.insert(
					chairs,
					{ fx = f, from = from, to = to, speed = spec.speed or 0.05, offset = (k - 1) / (spec.count or 3) }
				)
			end
		end
	end
	live += #chairs

	-- falling leaves under a tree
	type Leaf = { fx: Fx, start: Vector3, born: number, life: number, spin: Vector3 }
	local leaves: { Leaf } = {}
	local colors = fx.leaves and LEAF_COLORS[fx.leaves]
	local canopy: Vector3? = if fx.canopy then (pivot * CFrame.new(fx.canopy * s)).Position else nil
	local radius = (fx.radius or 2) * s
	local groundY = pivot.Position.Y
	local function respawn(l: Leaf, now: number)
		local c = canopy :: Vector3
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0.2, 0.9) * radius
		l.start = c + Vector3.new(math.cos(a) * r, -radius * 0.4, math.sin(a) * r)
		l.born = now
		l.life = (l.start.Y - groundY) / rng:NextNumber(1.6, 2.4)
		l.spin = Vector3.new(rng:NextNumber(1, 3), rng:NextNumber(1, 3), rng:NextNumber(1, 3))
		if colors then
			l.fx.part.Color = colors[rng:NextInteger(1, #colors)]
		end
	end
	if canopy and colors then
		for k = 1, 3 do
			local f = make("ParkFx_Leaf", box)
			if f then
				f.part.Material = Enum.Material.SmoothPlastic
				local l = { fx = f, start = canopy, born = 0, life = 1, spin = Vector3.one }
				respawn(l, os.clock() - k * 1.7)
				table.insert(leaves, l)
			end
		end
	end
	live += #leaves

	local nextWake = 0
	local wakeIndex = 0
	local fishStart, fishSpot, fishDir = -100, Vector3.zero, Vector3.xAxis

	local function run(t: number, _dt: number)
		for _, m in movers do
			if m.kind == "blink" then
				local on = ((t * m.speed + m.phase) % 1) < m.amp
				if on ~= m.on then
					m.on = on
					m.part.Material = if on then m.material else Enum.Material.SmoothPlastic
					m.part.Color = if on then m.color else m.color:Lerp(Color3.new(0, 0, 0), 0.7)
				end
			elseif m.kind == "bounce" then
				local u = math.abs(math.sin(t * math.pi * m.speed + m.phase))
				m.part.CFrame = pivot * CFrame.new(0, m.amp * s * u, 0) * m.base
			else
				m.part.CFrame = pivot * m.hub * rotation(m, t) * m.hub:Inverse() * m.base
			end
		end

		for _, w in walkers do
			local spec = w.spec
			local c = w.centre
			local rx, rz = spec.rx * s, spec.rz * s
			local th = t * spec.speed + spec.phase
			local pos = c * Vector3.new(math.cos(th) * rx, 0, math.sin(th) * rz)
			local ahead = c * Vector3.new(math.cos(th + 0.05) * rx, 0, math.sin(th + 0.05) * rz)
			local bob = spec.bob or 0
			local flying = bob >= 0.3
			local y = bob * s * math.sin(t * (if flying then 1.3 else 4) + w.i)
			local roll = if flying then -0.35 else 0.06 * math.sin(t * 3 + w.i)
			local hop = spec.hop or 0
			if hop > 0 then
				-- quick little steps with a waddle
				y += hop * s * math.abs(math.sin(t * 9 + w.i))
				roll = 0.14 * math.sin(t * 9 + w.i)
			end
			local cf = CFrame.lookAt(pos, ahead)
				* CFrame.new(0, y - (if spec.wake then 0.05 * s else 0), 0)
				* CFrame.Angles(0, 0, roll)
			put(w.fx, cf, Vector3.one * s)
			if w.wake and #wakes > 0 and t >= nextWake then
				nextWake = t + 0.45
				wakeIndex = wakeIndex % #wakes + 1
				local r = wakes[wakeIndex]
				r.at = CFrame.new(pos + Vector3.new(0, 0.02, 0))
				r.born = t
			end
		end
		for _, r in wakes do
			local u = (t - r.born) / 1.6
			if u >= 1 then
				r.fx.part.Transparency = 1
			else
				local rr = (0.5 + 1.2 * u) * s
				put(r.fx, r.at, Vector3.new(rr, s, rr))
				r.fx.part.Transparency = 0.25 + 0.75 * u
			end
		end

		-- a fish jumps every few seconds
		if fish then
			local u = (t - fishStart) / 1.1
			if u > 4 then
				fishStart = t
				fishSpot = (pivot * CFrame.new(fx.fish[rng:NextInteger(1, #fx.fish)] * s)).Position
				local a = rng:NextNumber(0, math.pi * 2)
				fishDir = Vector3.new(math.cos(a), 0, math.sin(a))
				u = 0
			end
			if u <= 1 then
				local p = fishSpot
					+ fishDir * (u - 0.5) * 2.2 * s
					+ Vector3.new(0, 4 * u * (1 - u) * 1.6 * s - 0.2 * s, 0)
				local pitch = math.rad(70) * (1 - 2 * u)
				put(fish, CFrame.lookAt(p, p + fishDir) * CFrame.Angles(pitch, 0, 0), Vector3.one * s)
				fish.part.Transparency = 0
			else
				fish.part.Transparency = 1
			end
			-- splash + ripple at the start and at the landing
			local function splashAt(spot: Vector3, age: number)
				if fishSplash and age >= 0 and age < 0.5 then
					put(fishSplash, CFrame.new(spot), Vector3.new(1, 0.4 + 1.2 * math.sin(age / 0.5 * math.pi), 1) * s)
					fishSplash.part.Transparency = age / 0.5 * 0.6
					return true
				end
				return false
			end
			local landing = fishSpot + fishDir * 1.1 * s
			local launch = fishSpot - fishDir * 1.1 * s
			local age = (t - fishStart)
			if not splashAt(launch, age) and not splashAt(landing, age - 1.1) and fishSplash then
				fishSplash.part.Transparency = 1
			end
			if fishRipple then
				local ru = (age - 1.1) / 1.4
				if ru >= 0 and ru < 1 then
					local r = (0.4 + 1.8 * ru) * s
					put(fishRipple, CFrame.new(landing + Vector3.new(0, 0.02, 0)), Vector3.new(r, s, r))
					fishRipple.part.Transparency = 0.2 + 0.8 * ru
				else
					fishRipple.part.Transparency = 1
				end
			end
		end

		-- puffs rise, grow, drift with the wind and fade
		for _, p in puffs do
			local u = ((t + p.offset) % p.life) / p.life
			local pos = p.at
				+ Vector3.new(0, 5 * p.size * u, 0)
				+ p.drift * (1.6 * p.size * u * u)
				+ Vector3.new(0.25 * p.size * math.sin(t * 1.7 + p.offset * 3), 0, 0)
			put(p.fx, CFrame.new(pos) * CFrame.Angles(0, u * 2 + p.offset, 0), Vector3.one * p.size * (0.45 + 1.4 * u))
			p.fx.part.Transparency = if u < 0.08 then 1 - u / 0.08 * 0.85 else 0.15 + 0.85 * u ^ 1.5
		end

		-- lift chairs: ride from -> to, fade at the towers, swing a little
		for k, c in chairs do
			local u = (t * c.speed + c.offset) % 1
			local pos = c.from:Lerp(c.to, u)
			local dir = Vector3.new(c.to.X - c.from.X, 0, c.to.Z - c.from.Z)
			if dir.Magnitude < 0.01 then
				dir = Vector3.zAxis
			end
			local cf = CFrame.lookAt(pos, pos + dir.Unit) * CFrame.Angles(0.05 * math.sin(t * 1.8 + k), 0, 0)
			put(c.fx, cf, Vector3.one * s)
			local edge = math.min(u, 1 - u)
			c.fx.part.Transparency = if edge < 0.04 then 1 - edge / 0.04 else 0
		end

		for _, l in leaves do
			local age = t - l.born
			if age > l.life or age < 0 then
				respawn(l, t)
				age = 0
			end
			local fall = l.start.Y - groundY
			local y = l.start.Y - fall * (age / l.life)
			local p = Vector3.new(
				l.start.X + math.sin(age * 2.2) * 0.6 * s,
				math.max(y, groundY + 0.05),
				l.start.Z + math.cos(age * 1.7) * 0.4 * s
			)
			put(
				l.fx,
				CFrame.new(p) * CFrame.Angles(age * l.spin.X, age * l.spin.Y, math.sin(age * 3) * 0.8),
				Vector3.one * s * 1.3
			)
			l.fx.part.Transparency = if age > l.life - 0.3 then (age - (l.life - 0.3)) / 0.3 else 0
		end
	end

	if live == 0 then
		box:Destroy()
		return nil
	end
	-- a base skin hides the classic base props (Transparency 1): hide their extras too
	local ref = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	return { model = model, folder = box, run = run, visible = true, ref = ref }
end

local function add(model: Instance)
	if not model:IsA("Model") or entries[model] then
		return
	end
	local e = build(model)
	if e then
		entries[model] = e
	end
end

local function remove(model: Instance)
	local e = entries[model :: Model]
	if e then
		e.folder:Destroy()
		entries[model :: Model] = nil
	end
end

function ParkFxController:Start()
	root = Instance.new("Folder")
	root.Name = "ParkFx"
	root.Parent = Workspace
	task.spawn(function()
		if not AssetLibrary.waitFor("Ready", 600) then
			return
		end
		CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
		CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
		for _, m in CollectionService:GetTagged(TAG) do
			add(m)
		end
		RunService.Heartbeat:Connect(function(dt)
			local cam = Workspace.CurrentCamera
			if not cam then
				return
			end
			local t = os.clock()
			local eye = cam.CFrame.Position
			for model, e in entries do
				if not model.Parent then
					remove(model)
					continue
				end
				local near = (model:GetPivot().Position - eye).Magnitude < RANGE
				if near and e.ref and e.ref.Transparency >= 1 then
					near = false
				end
				if near ~= e.visible then
					e.visible = near
					e.folder.Parent = if near then root else nil
				end
				if near then
					e.run(t, dt)
				end
			end
		end)
	end)
end

return ParkFxController
