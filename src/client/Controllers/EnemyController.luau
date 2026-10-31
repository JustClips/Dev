--!strict
-- Draws the enemies your pets fight (Config/Enemies; dust bunnies first). The server moves
-- one invisible anchor part per enemy at 10 Hz (EnemyService, workspace.Enemies); here
-- each anchor gets its modelled mesh, which follows it smoothly and plays idle / hop / run
-- animations to match how fast it moves. Also:
--   * a health bar over each enemy while it's hurt or fighting
--   * damage numbers from the CombatHits batches (CombatService), knock-back on hits and a
--     lunge when the enemy attacks a pet
--   * tap / click an enemy to send your pets at it (PetAttack)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Combat = require(Shared.Combat)
local Enemies = require(Shared.Config.Enemies)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Zones = require(Shared.Config.Zones)

local Client = script.Parent.Parent
local Ui = require(Client:WaitForChild("Ui"))

local FOLLOW = 10 -- how fast the model catches up with its anchor (per second)
local DRAW_DISTANCE = 180
local BAR_DISTANCE = 75
local NUMBER_DISTANCE = 70
local NUMBER_SECONDS = 0.8
local MAX_NUMBERS = 28
local TAP_PIXELS = 70

local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
local FONT_BOLD = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
local INK = Color3.fromRGB(16, 18, 28)
local HP_FULL = Color3.fromRGB(235, 64, 52)
local HP_BACK = Color3.fromRGB(40, 22, 26)

type Visual = {
	anchor: BasePart,
	def: Enemies.EnemyDef?,
	model: Model,
	real: boolean, -- the modelled mesh (false: the ball placeholder until it loads)
	cframe: CFrame,
	tracks: { [string]: AnimationTrack },
	playing: string?,
	speed: number,
	kick: number, -- knock-back left (seconds)
	lunge: number, -- attack lunge left (seconds)
	lungeAt: Vector3?,
	bar: BillboardGui,
	fill: Frame,
	hpText: TextLabel,
}

type Number = { gui: BillboardGui, att: Attachment, label: TextLabel, stroke: UIStroke, born: number, from: Vector3, drift: number }

local EnemyController = {}

local controllers: any
local visuals: { [BasePart]: Visual } = {}
local byName: { [string]: Visual } = {}
local holder: Folder
local numbers: { Number } = {}
local spare: { Number } = {}
local soundAt: { [string]: number } = {}
local localPlayer = Players.LocalPlayer

local function sound(name: string, gap: number)
	local now = os.clock()
	if now - (soundAt[name] or 0) >= gap then
		soundAt[name] = now
		Ui.sound(name)
	end
end

local function placeholder(zoneId: string?): Model
	local model = Instance.new("Model")
	local zone = zoneId and Zones.ById[zoneId]
	local fur = if zone then (zone.DustColor :: Color3):Lerp(Color3.new(1, 1, 1), 0.55) else Color3.fromRGB(240, 230, 214)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(2.6, 2.6, 2.6)
	body.Color = fur
	body.Material = Enum.Material.Sand
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CFrame = CFrame.new(0, 1.3, 0)
	body.Parent = model
	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Transparency = 1
	root.Size = Vector3.new(1, 1, 1)
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	return model
end

-- Health bar: name on top, a solid bar with the health number in it (no rounded corners).
local function makeBar(def: Enemies.EnemyDef?): (BillboardGui, Frame, TextLabel)
	local boss = def ~= nil and def.Boss == true
	local width = if boss then 220 else 120
	local gui = Instance.new("BillboardGui")
	gui.Name = "EnemyBar"
	gui.Size = UDim2.fromOffset(width, if boss then 46 else 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, if def then def.BarHeight else 4, 0)
	gui.MaxDistance = BAR_DISTANCE
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, if boss then 22 else 16)
	name.FontFace = FONT
	name.TextSize = if boss then 20 else 15
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Text = if def then def.Name else "Enemy"
	name.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = name
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.BackgroundColor3 = HP_BACK
	back.BorderSizePixel = 0
	back.Position = UDim2.new(0, 0, 0, if boss then 24 else 17)
	back.Size = UDim2.new(1, 0, 0, if boss then 20 else 15)
	back.Parent = gui
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = 2
	edge.LineJoinMode = Enum.LineJoinMode.Miter
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = HP_FULL
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	local hpText = Instance.new("TextLabel")
	hpText.BackgroundTransparency = 1
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.FontFace = FONT_BOLD
	hpText.TextSize = if boss then 15 else 12
	hpText.TextColor3 = Color3.new(1, 1, 1)
	hpText.ZIndex = 2
	hpText.Parent = back
	local hpStroke = stroke:Clone()
	hpStroke.Thickness = 1.5
	hpStroke.Parent = hpText
	gui.Parent = holder
	return gui, fill, hpText
end

local function makeModel(visual: Visual)
	if visual.model then
		visual.model:Destroy()
	end
	table.clear(visual.tracks)
	visual.playing = nil
	local def = visual.def
	local modelName = if def then def.Model else "Mob_DustBunny"
	local model = AssetLibrary.get(modelName)
	visual.real = model ~= nil
	if not model then
		model = placeholder(visual.anchor:GetAttribute("Zone") :: string?)
	elseif def and def.Scale and def.Scale ~= 1 then
		model:ScaleTo(def.Scale)
	end
	model.Name = visual.anchor.Name
	model:PivotTo(visual.cframe)
	model.Parent = holder
	visual.model = model
	visual.bar.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if visual.real then
		for _, key in { "Idle", "Walk", "Run" } do
			local track = AssetLibrary.loadTrack(model, `{modelName}_{key}`)
			if track then
				track.Looped = true
				visual.tracks[key] = track
			end
		end
	end
end

local function play(visual: Visual, key: string)
	if visual.playing == key then
		return
	end
	local old = visual.playing and visual.tracks[visual.playing]
	if old then
		old:Stop(0.15)
	end
	local track = visual.tracks[key]
	if track then
		track:Play(0.15)
	end
	visual.playing = key
end

local function refreshBar(visual: Visual)
	local hp = visual.anchor:GetAttribute("Hp")
	local maxHp = visual.anchor:GetAttribute("MaxHp")
	if type(hp) ~= "number" or type(maxHp) ~= "number" or maxHp <= 0 then
		return
	end
	local share = math.clamp(hp / maxHp, 0, 1)
	visual.fill.Size = UDim2.fromScale(share, 1)
	visual.hpText.Text = `{Format.number(math.ceil(hp))} / {Format.number(math.ceil(maxHp))}`
end

local function add(anchor: Instance)
	if not anchor:IsA("BasePart") or visuals[anchor] then
		return
	end
	local defId = anchor:GetAttribute("Enemy")
	local def = if type(defId) == "string" then Enemies.ById[defId] else nil
	local bar, fill, hpText = makeBar(def)
	local visual: Visual = {
		anchor = anchor,
		def = def,
		model = nil :: any,
		real = false,
		cframe = anchor.CFrame,
		tracks = {},
		playing = nil,
		speed = 0,
		kick = 0,
		lunge = 0,
		lungeAt = nil,
		bar = bar,
		fill = fill,
		hpText = hpText,
	}
	visuals[anchor] = visual
	byName[anchor.Name] = visual
	makeModel(visual)
	refreshBar(visual)
	anchor:GetAttributeChangedSignal("Hp"):Connect(function()
		refreshBar(visual)
	end)
	anchor:GetAttributeChangedSignal("MaxHp"):Connect(function()
		refreshBar(visual)
	end)
end

local function remove(anchor: Instance)
	local visual = visuals[anchor :: BasePart]
	if visual then
		visual.model:Destroy()
		visual.bar:Destroy()
		visuals[anchor :: BasePart] = nil
		if byName[anchor.Name] == visual then
			byName[anchor.Name] = nil
		end
	end
end

-- Damage numbers: pooled billboards that pop up, drift and fade.
local function popNumber(at: Vector3, text: string, color: Color3, size: number)
	local camera = Workspace.CurrentCamera
	if not camera or (at - camera.CFrame.Position).Magnitude > NUMBER_DISTANCE then
		return
	end
	local n = table.remove(spare)
	if not n then
		if #numbers >= MAX_NUMBERS then
			n = table.remove(numbers, 1)
		else
			-- Each number sits on an attachment in Terrain that moves up as it floats.
			local att = Instance.new("Attachment")
			att.Name = "DamageNumber"
			att.Parent = Workspace.Terrain
			local gui = Instance.new("BillboardGui")
			gui.Name = "DamageNumber"
			gui.Adornee = att
			gui.Size = UDim2.fromOffset(140, 40)
			gui.AlwaysOnTop = true
			gui.LightInfluence = 0
			gui.ResetOnSpawn = false
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.FontFace = FONT
			label.Parent = gui
			local stroke = Instance.new("UIStroke")
			stroke.Color = INK
			stroke.Thickness = 2.5
			stroke.LineJoinMode = Enum.LineJoinMode.Miter
			stroke.Parent = label
			gui.Parent = holder
			n = { gui = gui, att = att, label = label, stroke = stroke, born = 0, from = Vector3.zero, drift = 0 }
		end
	end
	local num = n :: Number
	num.born = os.clock()
	num.from = at
	num.drift = math.random(-10, 10) / 10
	num.label.Text = text
	num.label.TextColor3 = color
	num.label.TextSize = size
	num.label.TextTransparency = 0
	num.stroke.Transparency = 0
	num.att.WorldPosition = at
	num.gui.Enabled = true
	table.insert(numbers, num)
end

local function stepNumbers(now: number)
	for i = #numbers, 1, -1 do
		local n = numbers[i]
		local t = (now - n.born) / NUMBER_SECONDS
		if t >= 1 then
			n.gui.Enabled = false
			table.remove(numbers, i)
			table.insert(spare, n)
		else
			-- Pop up fast, then slow down; fade over the last part.
			local rise = 1 - (1 - t) ^ 3
			n.label.TextTransparency = math.max(0, (t - 0.6) / 0.4)
			n.stroke.Transparency = n.label.TextTransparency
			n.att.WorldPosition = n.from + Vector3.new(n.drift * rise, 2.4 * rise, 0)
		end
	end
end

local function onHits(list: any)
	if type(list) ~= "table" then
		return
	end
	local myId = localPlayer.UserId
	for _, hit in list do
		local visual = byName[hit.E]
		if not visual then
			continue
		end
		local mine = hit.U == myId
		local top = visual.cframe.Position + Vector3.new(0, (if visual.def then visual.def.BarHeight else 4) * 0.7, 0)
		if hit.P then
			-- The enemy hit a pet: it lunges at it, the pet shows red damage.
			local petAt = controllers.FollowerController:PetPosition(hit.U, hit.S)
			visual.lunge = 0.25
			visual.lungeAt = petAt
			if petAt then
				popNumber(petAt + Vector3.new(0, 2.5, 0), "-" .. Format.number(hit.D), Color3.fromRGB(255, 84, 84), if mine then 24 else 18)
			end
			if mine then
				sound("PetHurt", 0.15)
				if hit.K then
					sound("PetSleep", 0.5)
				end
			end
		else
			visual.kick = 0.18
			if hit.S and hit.S > 0 then
				controllers.FollowerController:Lunge(hit.U, hit.S, visual.cframe.Position)
			end
			local color = if hit.C then Color3.fromRGB(255, 214, 51) elseif hit.S == 0 then Color3.fromRGB(150, 220, 255) else Color3.new(1, 1, 1)
			local text = Format.number(hit.D)
			if hit.C then
				text = "CRIT " .. text
			end
			popNumber(top, text, color, (if mine then 26 else 18) + (if hit.C then 6 else 0))
			if mine then
				sound("PetHit", 0.08)
			end
		end
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local focus = if camera then camera.Focus.Position else Vector3.zero
	local alpha = 1 - math.exp(-FOLLOW * dt)
	local now = os.clock()
	for anchor, visual in visuals do
		local target = anchor.CFrame
		local far = (target.Position - focus).Magnitude > DRAW_DISTANCE
		if (target.Position - visual.cframe.Position).Magnitude > 12 then
			visual.cframe = target -- respawned somewhere else: jump there
		end
		local before = visual.cframe.Position
		visual.cframe = visual.cframe:Lerp(target, alpha)
		local moved = ((visual.cframe.Position - before) * Vector3.new(1, 0, 1)).Magnitude / math.max(dt, 1e-3)
		visual.speed += (moved - visual.speed) * math.min(1, dt * 8)
		if far then
			if visual.model.Parent ~= nil then
				visual.model.Parent = nil
				visual.playing = nil
			end
			visual.bar.Enabled = false
			continue
		end
		if visual.model.Parent ~= holder then
			visual.model.Parent = holder
		end
		-- Knock-back when hit, lunge when it attacks.
		local offset = Vector3.zero
		if visual.kick > 0 then
			visual.kick -= dt
			offset -= visual.cframe.LookVector * math.sin(math.max(visual.kick, 0) / 0.18 * math.pi) * 0.6
		end
		if visual.lunge > 0 then
			visual.lunge -= dt
			local toward = if visual.lungeAt then (visual.lungeAt - visual.cframe.Position) * Vector3.new(1, 0, 1) else visual.cframe.LookVector
			if toward.Magnitude > 0.01 then
				offset += toward.Unit * math.sin(math.max(visual.lunge, 0) / 0.25 * math.pi) * 1.4
			end
			offset += Vector3.new(0, math.sin(math.max(visual.lunge, 0) / 0.25 * math.pi) * 0.8, 0)
		end
		visual.model:PivotTo(visual.cframe + offset)
		local hp = anchor:GetAttribute("Hp")
		local maxHp = anchor:GetAttribute("MaxHp")
		local hurt = type(hp) == "number" and type(maxHp) == "number" and hp < maxHp
		visual.bar.Enabled = hurt or anchor:GetAttribute("Fighting") == true or (visual.def ~= nil and visual.def.Boss == true)
		if visual.real then
			if anchor:GetAttribute("Running") == true then
				play(visual, "Run")
			elseif visual.speed > 0.6 then
				play(visual, "Walk")
			else
				play(visual, "Idle")
			end
		end
	end
	stepNumbers(now)
end

-- Tap / click near an enemy on screen: your pets go for it.
local function onTap(screen: Vector2)
	local camera = Workspace.CurrentCamera
	if not camera or (localPlayer:GetAttribute("Followers") or "") == "" then
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local best, bestDistance = nil, TAP_PIXELS
	for anchor, visual in visuals do
		if visual.model.Parent and (anchor.Position - root.Position).Magnitude <= Combat.TapRange then
			local point, onScreen = camera:WorldToViewportPoint(visual.cframe.Position + Vector3.new(0, 1.5, 0))
			if onScreen then
				local d = (Vector2.new(point.X, point.Y) - screen).Magnitude
				if d < bestDistance then
					best, bestDistance = anchor, d
				end
			end
		end
	end
	if best and localPlayer:GetAttribute("CombatTarget") ~= best.Name then
		Net.event("PetAttack"):FireServer(best.Name)
		Ui.sound("Click")
	end
end

-- Where an enemy is drawn (for pets running to it).
function EnemyController:Position(name: string): Vector3?
	local visual = byName[name]
	return visual and visual.cframe.Position
end

function EnemyController:Def(name: string): Enemies.EnemyDef?
	local visual = byName[name]
	return visual and visual.def
end

function EnemyController:Init(all)
	controllers = all
end

function EnemyController:Start()
	holder = Instance.new("Folder")
	holder.Name = "EnemyModels"
	holder.Parent = Workspace
	local folder = Workspace:WaitForChild("Enemies")
	folder.ChildAdded:Connect(add)
	folder.ChildRemoved:Connect(remove)
	for _, anchor in folder:GetChildren() do
		add(anchor)
	end
	-- Swap the placeholders for the real models once they have loaded.
	task.spawn(function()
		while true do
			local waiting = false
			for _, visual in visuals do
				if not visual.real then
					local name = if visual.def then visual.def.Model else "Mob_DustBunny"
					if AssetLibrary.has(name) then
						makeModel(visual)
					else
						waiting = true
					end
				end
			end
			if not waiting and next(visuals) ~= nil then
				break
			end
			task.wait(1)
		end
	end)
	Net.event("CombatHits").OnClientEvent:Connect(onHits)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			onTap(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return EnemyController
