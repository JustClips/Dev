--!strict
-- Animated water on the Park fountain (art/blender/fountain.py). The server tags each
-- placed Park_Fountain "Fountain"; this client adds the FountainFx_* water meshes on top
-- and moves them every frame: the jet pulses, the palm spray turns and drips drops into
-- the top bowl, drop blobs slide down the water ribbons, foam rings bob where the water
-- lands, ripples grow and fade on the pool, and the frogs' spouts wobble.
-- Everything is local (no replication) and only runs while the camera is close.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)

local FountainController = {}

local TAG = "Fountain"
local RANGE = 260 -- studs from the camera; past this the water stops moving
local GRAVITY = 40

-- One FX mesh: base = where the part sits relative to the mesh's Blender origin.
type Fx = { part: MeshPart, base: CFrame, size: Vector3 }

type Drop = { fx: Fx, phase: number }
type Fountain = {
	model: Model,
	folder: Folder,
	run: (number) -> (),
	visible: boolean,
}

local fountains: { [Model]: Fountain } = {}
local folder: Folder

local function make(name: string, parent: Instance, transparency: number?): Fx?
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
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.Parent = parent
	model:Destroy()
	return { part = part, base = base, size = part.Size }
end

-- Puts the mesh's Blender origin at `origin`, stretched by `scale` (x, y, z).
local function put(fx: Fx, origin: CFrame, scale: Vector3)
	local b = fx.base
	fx.part.Size = fx.size * scale
	fx.part.CFrame = origin * CFrame.new(b.Position * scale) * b.Rotation
end

local ONE = Vector3.one

local function build(model: Model): Fountain?
	local meta = AssetLibrary.meta("Park_Fountain")
	local fxMeta = meta and (meta :: any).fx
	if not fxMeta then
		return nil
	end
	local box = Instance.new("Folder")
	box.Name = "FountainFx"
	box.Parent = folder

	local s = model:GetScale()
	local pivot = model:GetPivot()
	local function at(v: Vector3): CFrame
		return pivot * CFrame.new(v * s)
	end

	local jetBase = at(fxMeta.jet)
	local jetTop = at(fxMeta.jetTop)
	local bowl1, bowl2 = at(fxMeta.bowl1), at(fxMeta.bowl2)
	local bowl1Water, bowl2Water = at(fxMeta.bowl1Water), at(fxMeta.bowl2Water)
	local pool = at(fxMeta.pool)
	local drop1 = (fxMeta.bowl1.Y - fxMeta.pool.Y) * s
	local drop2 = (fxMeta.bowl2.Y - fxMeta.bowl1Water.Y) * s
	local R1, R2, poolR = fxMeta.bowl1R * s, fxMeta.bowl2R * s, fxMeta.poolR * s

	local jet = make("FountainFx_Jet", box)
	local spray = make("FountainFx_Umbrella", box)
	local curtain1 = make("FountainFx_Curtain1", box, 0.2)
	local curtain2 = make("FountainFx_Curtain2", box, 0.2)
	local foam1 = make("FountainFx_SplashRing1", box)
	local foam2 = make("FountainFx_SplashRing2", box)
	if curtain1 then
		put(curtain1, bowl1, ONE * s)
	end
	if curtain2 then
		put(curtain2, bowl2, ONE * s)
	end

	-- drop blobs sliding down the ribbons (two rings per bowl, half a cycle apart)
	local drips1: { Drop } = {}
	local drips2: { Drop } = {}
	for k = 1, 2 do
		local a = make("FountainFx_Drips1", box)
		if a then
			table.insert(drips1, { fx = a, phase = (k - 1) / 2 })
		end
		local b = make("FountainFx_Drips2", box)
		if b then
			table.insert(drips2, { fx = b, phase = (k - 1) / 2 + 0.25 })
		end
	end

	-- ripples: three on the pool round the falling water, two in bowl 1
	local ripples: { { fx: Fx, phase: number, origin: CFrame, r0: number, r1: number, period: number } } = {}
	for k = 1, 3 do
		local r = make("FountainFx_Ripple", box)
		if r then
			table.insert(ripples, { fx = r, phase = (k - 1) / 3, origin = pool * CFrame.new(0, 0.03 * s, 0), r0 = R1 + 0.6 * s, r1 = poolR - 0.3 * s, period = 2.4 })
		end
	end
	for k = 1, 2 do
		local r = make("FountainFx_Ripple", box)
		if r then
			table.insert(ripples, { fx = r, phase = (k - 1) / 2, origin = bowl1Water * CFrame.new(0, 0.03 * s, 0), r0 = R2 + 0.6 * s, r1 = R1 - 0.25 * s, period = 1.8 })
		end
	end

	-- frog spouts, each with a splash and a ripple where it lands
	local land = (AssetLibrary.meta("FountainFx_Arc") :: any)
	local landAt: Vector3 = if land and land.fx then land.fx.land else Vector3.new(0, -1.15, -2.6)
	local frogs = {}
	for i, mouth in fxMeta.frogs :: { Vector3 } do
		local m = at(mouth).Position
		local centre = Vector3.new(pivot.Position.X, m.Y, pivot.Position.Z)
		local cf = CFrame.lookAt(m, centre)
		local hit = cf:PointToWorldSpace(landAt * s)
		local splashCf = CFrame.new(hit.X, pool.Position.Y, hit.Z)
		local arc = make("FountainFx_Arc", box)
		local splash = make("FountainFx_Splash", box)
		local ripple = make("FountainFx_Ripple", box)
		table.insert(frogs, { cf = cf, splashCf = splashCf, arc = arc, splash = splash, ripple = ripple, phase = i * 0.37 })
	end

	-- drops that fall from the spray's tips into the top bowl
	local umbMeta = (AssetLibrary.meta("FountainFx_Umbrella") :: any)
	local reach = (if umbMeta and umbMeta.fx then umbMeta.fx.reach else 1.3) * s
	local umbDrop = (if umbMeta and umbMeta.fx then umbMeta.fx.drop else 1.7) * s
	local sprayDrops: { Drop } = {}
	for k = 1, 8 do
		local d = make("FountainFx_Drop", box)
		if d then
			table.insert(sprayDrops, { fx = d, phase = (k - 1) / 8 })
		end
	end
	local fallH = jetTop.Position.Y - umbDrop - bowl2Water.Position.Y
	local jetH = (fxMeta.jetTop.Y - fxMeta.jet.Y) * s

	local function run(t: number)
		-- jet: bouncy column
		local pulse = math.sin(t * 6)
		local stretch = 0.88 + 0.16 * (pulse + 1) / 2
		if jet then
			put(jet, jetBase * CFrame.Angles(0, t * 1.5, 0), Vector3.new(1 + 0.06 * pulse, stretch, 1 + 0.06 * pulse) * s)
		end
		local spin = t * 0.8
		local top = jetTop * CFrame.new(0, (stretch - 1) * jetH, 0)
		if spray then
			local k = 1 + 0.06 * math.sin(t * 6 + 0.8)
			put(spray, top * CFrame.Angles(0, spin, 0), Vector3.new(k, 1 / k, k) * s)
		end
		-- drops falling off the spray tips
		for i, d in sprayDrops do
			local u = (t * 0.9 + d.phase) % 1
			-- spray tip i in the spray's own space (Blender angle a -> Roblox (-cos a, sin a))
			local a = (i - 1) * math.pi / 4
			local fallT = math.sqrt(2 * math.max(fallH, 0.5) / GRAVITY)
			local tt = u * fallT
			local r = reach * 1.08 + 0.6 * tt * s
			local y = -umbDrop - 0.5 * GRAVITY * tt * tt
			put(d.fx, top * CFrame.Angles(0, spin, 0) * CFrame.new(-math.cos(a) * r, y, math.sin(a) * r), ONE * s)
			d.fx.part.Transparency = if u > 0.92 then 1 else 0.05
		end
		-- ribbons shimmer
		local w = math.sin(t * 9)
		if curtain1 then
			put(curtain1, bowl1, Vector3.new(1 + 0.012 * w, 1 + 0.02 * math.sin(t * 7), 1 + 0.012 * w) * s)
		end
		if curtain2 then
			put(curtain2, bowl2, Vector3.new(1 - 0.012 * w, 1 + 0.02 * math.sin(t * 7 + 1), 1 - 0.012 * w) * s)
		end
		-- drop blobs slide down, speeding up, and follow the ribbons' flare
		local function slide(list: { Drop }, origin: CFrame, R: number, drop: number, speed: number)
			for _, d in list do
				local u = (t * speed + d.phase) % 1
				local fall = u * u
				local r = (R + 0.1 * s + 0.4 * s * fall ^ 1.5) / (R + 0.16 * s)
				put(d.fx, origin * CFrame.new(0, -drop * fall, 0), Vector3.new(r, 1, r) * s)
				d.fx.part.Transparency = if u > 0.9 then 0.3 + (u - 0.9) * 7 else 0.05
			end
		end
		slide(drips1, bowl1, R1, drop1, 0.75)
		slide(drips2, bowl2, R2, drop2, 0.95)
		-- foam rings bob where the ribbons land
		if foam1 then
			put(foam1, pool * CFrame.Angles(0, -t * 0.3, 0), Vector3.new(1, 0.75 + 0.35 * (math.sin(t * 7) + 1) / 2, 1) * s)
		end
		if foam2 then
			put(foam2, bowl1Water * CFrame.Angles(0, t * 0.35, 0), Vector3.new(1, 0.75 + 0.35 * (math.sin(t * 8 + 1) + 1) / 2, 1) * s)
		end
		-- ripples grow and fade
		for _, r in ripples do
			local u = (t / r.period + r.phase) % 1
			local radius = r.r0 + (r.r1 - r.r0) * u
			put(r.fx, r.origin, Vector3.new(radius, s, radius))
			r.fx.part.Transparency = 0.15 + 0.85 * u * u
		end
		-- frog spouts
		for _, f in frogs do
			local p = math.sin(t * 5 + f.phase * 6)
			if f.arc then
				put(f.arc, f.cf, Vector3.new(1 + 0.08 * p, 1 + 0.1 * p, 1 + 0.03 * p) * s)
			end
			if f.splash then
				put(f.splash, f.splashCf * CFrame.Angles(0, t * 0.5 + f.phase, 0), Vector3.new(1, 0.7 + 0.5 * (p + 1) / 2, 1) * s)
			end
			if f.ripple then
				local u = (t / 1.3 + f.phase) % 1
				local radius = (0.4 + 1.3 * u) * s
				put(f.ripple, f.splashCf * CFrame.new(0, 0.03 * s, 0), Vector3.new(radius, s, radius))
				f.ripple.part.Transparency = 0.2 + 0.8 * u * u
			end
		end
	end

	run(0)
	return { model = model, folder = box, run = run, visible = true }
end

local function setVisible(f: Fountain, on: boolean)
	if f.visible == on then
		return
	end
	f.visible = on
	-- parked under nil while far away, so far fountains cost nothing to draw either
	f.folder.Parent = if on then folder else nil
end

local function add(model: Instance)
	if not model:IsA("Model") or fountains[model] then
		return
	end
	local f = build(model)
	if f then
		fountains[model] = f
	end
end

local function remove(model: Instance)
	local f = fountains[model :: Model]
	if f then
		f.folder:Destroy()
		fountains[model :: Model] = nil
	end
end

function FountainController:Start()
	folder = Instance.new("Folder")
	folder.Name = "FountainWater"
	folder.Parent = Workspace
	task.spawn(function()
		-- the FX meshes come with every other model
		if not AssetLibrary.waitFor("Ready", 600) then
			return
		end
		CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
		CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
		for _, m in CollectionService:GetTagged(TAG) do
			add(m)
		end
		RunService.Heartbeat:Connect(function()
			local cam = Workspace.CurrentCamera
			if not cam then
				return
			end
			local t = os.clock()
			local eye = cam.CFrame.Position
			for model, f in fountains do
				if not model.Parent then
					remove(model)
					continue
				end
				local near = (model:GetPivot().Position - eye).Magnitude < RANGE
				setVisible(f, near)
				if near then
					f.run(t)
				end
			end
		end)
	end)
end

return FountainController
