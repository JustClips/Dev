--!strict
-- Small life for the park decor (art/blender/parkdecor.py). The server tags placed decor
-- that has moving bits "ParkFx". This client then:
--   * plays each part listed in the model's meta "anim" (sway / swing / spin about the
--     part's joint): swings, the spring duck, reeds, flowers, tree tops, the weathervane...
--   * swims a duck family round the duck pond with ripples behind them, and makes a fish
--     jump now and then (meta fx: center, rx, rz, fish)
--   * drops a few fluttering leaves from trees (meta fx: canopy, radius, leaves)
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
type Mover = { part: BasePart, base: CFrame, hub: CFrame, kind: string, amp: number, speed: number, axis: string, phase: number }
type Entry = { model: Model, folder: Folder, run: (number, number) -> (), visible: boolean }

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

	-- parts that move about their joint
	local movers: { Mover } = {}
	for partName, spec in (meta.anim or {}) :: { [string]: any } do
		local part = model:FindFirstChild(partName)
		local pm = meta.parts and meta.parts[partName]
		if part and part:IsA("BasePart") and pm and pm.joint then
			local hub = CFrame.new(pm.joint * s)
			table.insert(movers, {
				part = part,
				base = pivot:ToObjectSpace(part.CFrame),
				hub = hub,
				kind = spec.kind,
				amp = spec.amp,
				speed = spec.speed,
				axis = spec.axis or "y",
				phase = rng:NextNumber(0, math.pi * 2),
			})
		end
	end

	local fx = meta.fx or {}

	-- duck pond: mum, three ducklings, ripples, a jumping fish
	local ducks: { Fx } = {}
	local wakes: { { fx: Fx, at: CFrame, born: number } } = {}
	local fish: Fx?, fishSplash: Fx?, fishRipple: Fx?
	local pondCentre: CFrame?
	if fx.center and fx.rx then
		pondCentre = pivot * CFrame.new(fx.center * s)
		local mum = make("PondFx_Duck", box)
		if mum then
			table.insert(ducks, mum)
		end
		for _ = 1, 3 do
			local d = make("PondFx_Duckling", box)
			if d then
				table.insert(ducks, d)
			end
		end
		for _ = 1, 4 do
			local r = make("FountainFx_Ripple", box)
			if r then
				r.part.Transparency = 1
				table.insert(wakes, { fx = r, at = CFrame.new(), born = -10 })
			end
		end
		fish = make("PondFx_Fish", box)
		fishSplash = make("FountainFx_Splash", box)
		fishRipple = make("FountainFx_Ripple", box)
	end

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

	local nextWake = 0
	local wakeIndex = 0
	local fishStart, fishSpot, fishDir = -100, Vector3.zero, Vector3.xAxis

	local function run(t: number, dt: number)
		for _, m in movers do
			m.part.CFrame = pivot * m.hub * rotation(m, t) * m.hub:Inverse() * m.base
		end
		if pondCentre then
			local c = pondCentre
			local rx, rz = fx.rx * s, fx.rz * s
			for i, d in ducks do
				local th = t * 0.22 - (i - 1) * 0.32 - (if i > 1 then 0.15 else 0)
				local pos = c * Vector3.new(math.cos(th) * rx, 0, math.sin(th) * rz)
				local ahead = c * Vector3.new(math.cos(th + 0.05) * rx, 0, math.sin(th + 0.05) * rz)
				local bob = 0.05 * math.sin(t * 4 + i)
				local cf = CFrame.lookAt(pos, ahead) * CFrame.new(0, bob - 0.05 * s, 0) * CFrame.Angles(0, 0, 0.06 * math.sin(t * 3 + i))
				put(d, cf, Vector3.one * s)
				if i == 1 and t >= nextWake then
					nextWake = t + 0.45
					wakeIndex = wakeIndex % #wakes + 1
					local w = wakes[wakeIndex]
					if w then
						w.at = CFrame.new(pos + Vector3.new(0, 0.02, 0))
						w.born = t
					end
				end
			end
			for _, w in wakes do
				local u = (t - w.born) / 1.6
				if u >= 1 then
					w.fx.part.Transparency = 1
				else
					local r = (0.5 + 1.2 * u) * s
					put(w.fx, w.at, Vector3.new(r, s, r))
					w.fx.part.Transparency = 0.25 + 0.75 * u
				end
			end
			-- a fish jumps every few seconds
			if fish and fx.fish and #fx.fish > 0 then
				local u = (t - fishStart) / 1.1
				if u > 4 then
					fishStart = t
					fishSpot = (pivot * CFrame.new(fx.fish[rng:NextInteger(1, #fx.fish)] * s)).Position
					local a = rng:NextNumber(0, math.pi * 2)
					fishDir = Vector3.new(math.cos(a), 0, math.sin(a))
					u = 0
				end
				if u <= 1 then
					local p = fishSpot + fishDir * (u - 0.5) * 2.2 * s + Vector3.new(0, 4 * u * (1 - u) * 1.6 * s - 0.2 * s, 0)
					local pitch = math.rad(70) * (1 - 2 * u)
					put(fish, CFrame.lookAt(p, p + fishDir) * CFrame.Angles(pitch, 0, 0), Vector3.one * s)
					fish.part.Transparency = 0
				else
					fish.part.Transparency = 1
				end
				-- splash + ripple at the start and at the landing
				local function splashAt(spot: Vector3, age: number)
					if fishSplash and age >= 0 and age < 0.5 then
						put(fishSplash, CFrame.new(spot.X, c.Position.Y, spot.Z), Vector3.new(1, 0.4 + 1.2 * math.sin(age / 0.5 * math.pi), 1) * s)
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
						put(fishRipple, CFrame.new(landing.X, c.Position.Y + 0.02, landing.Z), Vector3.new(r, s, r))
						fishRipple.part.Transparency = 0.2 + 0.8 * ru
					else
						fishRipple.part.Transparency = 1
					end
				end
			end
		end
		for _, l in leaves do
			local age = t - l.born
			if age > l.life or age < 0 then
				respawn(l, t)
				age = 0
			end
			local fall = l.start.Y - groundY
			local y = l.start.Y - fall * (age / l.life)
			local p = Vector3.new(l.start.X + math.sin(age * 2.2) * 0.6 * s, math.max(y, groundY + 0.05), l.start.Z + math.cos(age * 1.7) * 0.4 * s)
			put(l.fx, CFrame.new(p) * CFrame.Angles(age * l.spin.X, age * l.spin.Y, math.sin(age * 3) * 0.8), Vector3.one * s * 1.3)
			l.fx.part.Transparency = if age > l.life - 0.3 then (age - (l.life - 0.3)) / 0.3 else 0
		end
	end

	if #movers == 0 and #ducks == 0 and #leaves == 0 then
		box:Destroy()
		return nil
	end
	return { model = model, folder = box, run = run, visible = true }
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
