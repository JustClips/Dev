--!strict
-- Base picker (Dev, 2026-10-30: base skins left the Shop). The "Change Base" sign at your
-- base opens a window with every base. Tap one to try it on: your base shows it, the camera
-- swings round to look at it, and a bar above the hotbar shows what it needs (ticks for
-- rebirths and Index, a 3D tile per pet with a tick, tap a tile to see where to find it)
-- and one button: Unlock / Equip / Equipped / Locked. < > flip through the bases, X puts
-- your own base back. A "NEW BASE READY!" tag floats over your sign when one can be unlocked.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local BaseSkins = require(Shared.Config.BaseSkins)
local Net = require(Shared.Net)
local World = require(Shared.Config.World)
local Zones = require(Shared.Config.Zones)

local GREEN = Color3.fromRGB(61, 220, 90)
local BLUE = Color3.fromRGB(76, 141, 255)
local GOLD = Color3.fromRGB(255, 200, 60)
local GREY = Color3.fromRGB(166, 174, 194)
local INK = Color3.fromRGB(23, 25, 30)
local WHITE = Color3.new(1, 1, 1)
local TILE_FOUND = Color3.fromRGB(46, 120, 70)
local TILE_MISSING = Color3.fromRGB(42, 50, 96)
local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
local CAMERA_TWEEN = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local BasePickerController = {}

local C: any
local picker: ScreenGui
local list: ScrollingFrame
local template: Frame
local preview: ScreenGui
local bar: Frame
local selected = 1
local previewing = false
local readyTag: BillboardGui? = nil

type Status = "Equipped" | "Owned" | "Ready" | "Locked"

local function rarityOf(id: string): string?
	local def = Aliens.ById[id]
	return if def then def.Rarity else nil
end

-- While trying a base on, the HUD (and its toasts) is hidden, so messages show on a card
-- just above the bar (Dev 2026-11-01: the status line was too small to read).
local noteSerial = 0
local function toast(ok: boolean, message: string?)
	if not message or message == "" then
		return
	end
	local note = previewing and preview and preview:FindFirstChild("Note") :: Frame?
	if note then
		local label = note:FindFirstChild("Label") :: TextLabel
		label.Text = message
		label.TextColor3 = if ok then Color3.fromRGB(124, 255, 140) else Color3.fromRGB(255, 214, 90)
		note.Visible = true
		Ui.popFrame(note)
		noteSerial += 1
		local serial = noteSerial
		task.delay(3.5, function()
			if serial == noteSerial then
				note.Visible = false
			end
		end)
		return
	end
	C.HudController:Toast(message, if ok then "Good" else "Bad")
end

-- Dev 2026-11-01: on phones the HUD covered the base being tried on. Every other screen is
-- hidden while the try-on bar is up and comes back as it was afterwards.
local hiddenScreens: { ScreenGui } = {}
local function hideOtherScreens(on: boolean)
	if on then
		local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not gui then
			return
		end
		for _, screen in gui:GetChildren() do
			if screen:IsA("ScreenGui") and screen.Enabled and screen ~= preview and screen.Name ~= "TouchGui"
				and screen.Name ~= "BasePicker" -- closing already (its tween ends it)
			then
				screen.Enabled = false
				table.insert(hiddenScreens, screen)
			end
		end
	else
		for _, screen in hiddenScreens do
			if screen.Parent then
				screen.Enabled = true
			end
		end
		table.clear(hiddenScreens)
	end
end

-- Where you stand with a base, and how many of its requirements are done.
local function statusOf(data, def: BaseSkins.SkinDef): (Status, BaseSkins.Progress, number, number)
	local skins = data.BaseSkins or { Owned = {}, Equipped = BaseSkins.Default }
	local p = BaseSkins.progress(def, data.Rebirths, data.Index or {}, rarityOf)
	local req = def.Requires
	local total, done = 2, 0
	if p.Rebirths >= req.Rebirths then
		done += 1
	end
	if p.IndexCount >= req.IndexCount then
		done += 1
	end
	for _, id in req.Pets do
		total += 1
		if p.Pets[id] then
			done += 1
		end
	end
	if req.AnyCosmic then
		total += 1
		if p.HasCosmic then
			done += 1
		end
	end
	local status: Status
	if (skins.Equipped or BaseSkins.Default) == def.Id then
		status = "Equipped"
	elseif skins.Owned[def.Id] or def.Id == BaseSkins.Default then
		status = "Owned"
	elseif p.Met then
		status = "Ready"
	else
		status = "Locked"
	end
	return status, p, done, total
end

local STATUS_LOOK: { [string]: { text: string, color: Color3 } } = {
	Equipped = { text = "IN USE", color = GOLD },
	Owned = { text = "OWNED", color = BLUE },
	Ready = { text = "READY!", color = GREEN },
	Locked = { text = "LOCKED", color = GREY },
}

-------------------------------------------------------------------------- camera

local function myBase(): CFrame?
	local data = State.data
	if data and data.BaseIndex and data.BaseIndex ~= 0 then
		return World.baseCFrame(data.BaseIndex)
	end
	return nil
end

-- Swings the camera out in front of your base, looking in.
local function cameraOn()
	local cf = myBase()
	local camera = Workspace.CurrentCamera
	if not cf or not camera then
		return
	end
	local eye = (cf * CFrame.new(0, 38, -92)).Position
	local look = (cf * CFrame.new(0, 2, -2)).Position
	camera.CameraType = Enum.CameraType.Scriptable
	local goal = CFrame.lookAt(eye, look)
	if Ui.reducedMotion() then
		camera.CFrame = goal
	else
		TweenService:Create(camera, CAMERA_TWEEN, { CFrame = goal }):Play()
	end
end

local function cameraOff()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

-------------------------------------------------------------------------- bar

local function clear(holder: Instance)
	for _, child in holder:GetChildren() do
		if child:GetAttribute("Built") then
			child:Destroy()
		end
	end
end

local function checkBox(ok: boolean, size: number): Frame
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.Size = UDim2.fromOffset(size, size)
	box.BackgroundColor3 = if ok then GREEN else WHITE
	box.ZIndex = 5
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.Parent = box
	if ok then
		local tick = Instance.new("TextLabel")
		tick.BackgroundTransparency = 1
		tick.Size = UDim2.fromScale(1, 1)
		tick.FontFace = FONT
		tick.Text = "✓"
		tick.TextScaled = true
		tick.TextColor3 = WHITE
		tick.ZIndex = 6
		tick.Parent = box
	end
	return box
end

local function label(text: string, size: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, size)
	l.FontFace = FONT
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color or WHITE
	l.ZIndex = 5
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.Parent = l
	return l
end

-- One requirement as a ticked or empty box with its text ("Rebirth 1/2").
local function addCheck(holder: Instance, order: number, ok: boolean, text: string)
	local cell = Instance.new("Frame")
	cell:SetAttribute("Built", true)
	cell.BackgroundTransparency = 1
	cell.AutomaticSize = Enum.AutomaticSize.X
	cell.Size = UDim2.fromOffset(0, 20)
	cell.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = cell
	local box = checkBox(ok, 16)
	box.LayoutOrder = 1
	box.Parent = cell
	local text_ = label(text, 14, if ok then WHITE else Color3.fromRGB(255, 215, 120))
	text_.LayoutOrder = 2
	text_.Parent = cell
	cell.Parent = holder
end

-- A pet the base needs: the pet in 3D and a tick once it's in your Index. Tap it for its
-- name and where to find it.
local function addPetTile(holder: Instance, order: number, found: boolean, petId: string?)
	local tile = Instance.new("TextButton")
	tile:SetAttribute("Built", true)
	tile.Name = "Pet"
	tile.Text = ""
	tile.AutoButtonColor = false
	tile.LayoutOrder = order
	tile.Size = UDim2.fromOffset(54, 60)
	tile.BackgroundColor3 = if found then TILE_FOUND else TILE_MISSING
	tile.ZIndex = 3
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = tile
	local def = petId and Aliens.ById[petId]
	local name = if def then def.Name else "Any Cosmic"
	if def then
		local view = Instance.new("ViewportFrame")
		view.BackgroundTransparency = 1
		view.Size = UDim2.new(1, -4, 1, -4)
		view.Position = UDim2.fromOffset(2, 2)
		view.Ambient = Color3.fromRGB(200, 208, 232)
		view.LightColor = WHITE
		view.LightDirection = Vector3.new(-1, -1, -1)
		view.ZIndex = 4
		view.Parent = tile
		ModelView.show(view, AssetLibrary.alien(def.Id), "Alien_" .. def.Id)
		if not found then
			-- Faded until you've hatched it, so the ones you still need stand out.
			view.ImageTransparency = 0.45
		end
	else
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(40, 40)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Image = AssetLibrary.image("Icon_Egg")
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = 4
		img.Parent = tile
	end
	local box = checkBox(found, 15)
	box.Position = UDim2.new(1, -2, 0, 2)
	box.AnchorPoint = Vector2.new(1, 0)
	box.Parent = tile
	Ui.button(tile, function()
		if found then
			toast(true, `{name}: found! It's in your Index.`)
		elseif def then
			local zone = Zones.ById[def.Zone or "Landing"]
			local article = if string.match(def.Rarity, "^[AEIOU]") then "an" else "a"
			toast(false, `Missing {def.Name}: {article} {def.Rarity} pet. Hatch it from {if zone then zone.Name else "zone"} eggs.`)
		else
			toast(false, "Missing: any Cosmic pet. Hatch one to tick this off.")
		end
	end)
	tile.Parent = holder
end

local function renderBar()
	local data = State.data
	local def = BaseSkins.List[selected]
	if not data or not def then
		return
	end
	local status, p, done, total = statusOf(data, def)
	local req = def.Requires
	Ui.find(bar, "Title").Text = def.Name
	local statusLabel = Ui.find(bar, "Status") :: TextLabel
	if status == "Equipped" then
		statusLabel.Text = "This is your base"
	elseif status == "Owned" then
		statusLabel.Text = "You own this one"
	elseif status == "Ready" then
		statusLabel.Text = "Everything done. Unlock it!"
	else
		statusLabel.Text = `{done} of {total} done`
	end
	local checks = Ui.find(bar, "Checks")
	local pets = Ui.find(bar, "Pets")
	clear(checks)
	clear(pets)
	local free = status == "Equipped" or status == "Owned"
	checks.Visible = not free
	pets.Visible = not free and (#req.Pets > 0 or req.AnyCosmic == true)
	if not free then
		addCheck(checks, 1, p.Rebirths >= req.Rebirths, `Rebirth {math.min(p.Rebirths, req.Rebirths)}/{req.Rebirths}`)
		addCheck(checks, 2, p.IndexCount >= req.IndexCount, `Index {math.min(p.IndexCount, req.IndexCount)}/{req.IndexCount}`)
		for i, id in req.Pets do
			addPetTile(pets, i, p.Pets[id] == true, id)
		end
		if req.AnyCosmic then
			addPetTile(pets, #req.Pets + 1, p.HasCosmic, nil)
		end
	end
	local main = Ui.find(bar, "Main") :: TextButton
	local look = {
		Equipped = { "Equipped", GOLD },
		Owned = { "Equip", BLUE },
		Ready = { "Unlock", GREEN },
		Locked = { "Locked", GREY },
	}
	main.BackgroundColor3 = look[status][2]
	local studs = main:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = look[status][2]
	end
	Ui.setText(main, look[status][1])
end

local function skinAction(action: string, id: string)
	task.spawn(function()
		local ok, message = Net.func("BaseSkin"):InvokeServer(action, id)
		if action == "Unlock" or action == "Equip" then
			toast(ok, message)
		end
	end)
end

local function tryOn(i: number)
	local def = BaseSkins.List[i]
	if not def then
		return
	end
	selected = i
	Ui.close("BasePicker")
	skinAction("Preview", def.Id)
	if not previewing then
		previewing = true
		hideOtherScreens(true)
		preview.Enabled = true
		Ui.popFrame(bar)
	end
	cameraOn()
	renderBar()
end

local function stopPreview()
	if not previewing then
		return
	end
	previewing = false
	noteSerial += 1
	local note = preview:FindFirstChild("Note") :: Frame?
	if note then
		note.Visible = false
	end
	preview.Enabled = false
	hideOtherScreens(false)
	cameraOff()
	skinAction("EndPreview", BaseSkins.Default)
end

-------------------------------------------------------------------------- window

local function renderList()
	local data = State.data
	if not data then
		return
	end
	clear(list)
	for i, def in BaseSkins.List do
		local status, _, done, total = statusOf(data, def)
		local card = template:Clone()
		card.Name = def.Id
		card:SetAttribute("Built", true)
		card.LayoutOrder = i
		card.Visible = true
		Ui.find(card, "Image").Image = AssetLibrary.image(def.Image or "Icon_Base")
		Ui.find(card, "Name").Text = def.Name
		local look = STATUS_LOOK[status]
		local pill = Ui.find(card, "Status") :: Frame
		pill.BackgroundColor3 = look.color
		Ui.find(pill, "Label").Text = look.text
		Ui.find(card, "Sub").Text = if status == "Locked" then `{done}/{total} done` elseif status == "Ready" then "Tap to unlock" else "Tap to try on"
		Ui.button(Ui.find(card, "Hit"), function()
			tryOn(i)
		end)
		card.Parent = list
	end
end

function BasePickerController:Open()
	stopPreview()
	renderList()
	Ui.open("BasePicker")
end

-------------------------------------------------------------------------- the sign

local function unlockable(data): number
	local count = 0
	for _, def in BaseSkins.List do
		if (statusOf(data, def)) == "Ready" then
			count += 1
		end
	end
	return count
end

-- Only your own base's sign shows its prompt; a tag floats over it when a base is ready.
local function syncSigns()
	local data = State.data
	local structures = Workspace:FindFirstChild("Structures")
	if not data or not structures then
		return
	end
	local mine: BasePart? = nil
	for i = 1, World.BaseCount do
		local platform = structures:FindFirstChild("BasePlatform" .. i)
		local prompt = platform and platform:FindFirstChild("BasePickerPrompt", true) :: ProximityPrompt?
		if prompt then
			prompt.Enabled = prompt:GetAttribute("Base") == data.BaseIndex
			if prompt.Enabled and prompt.Parent and prompt.Parent:IsA("BasePart") then
				mine = prompt.Parent
			end
		end
	end
	local ready = unlockable(data)
	if ready > 0 and mine then
		if not readyTag then
			local tag = Instance.new("BillboardGui")
			tag.Name = "BaseReadyTag"
			tag.Size = UDim2.fromOffset(220, 44)
			tag.StudsOffset = Vector3.new(0, 3.4, 0)
			tag.AlwaysOnTop = true
			tag.MaxDistance = 140
			local text = label("NEW BASE READY!", 26, Color3.fromRGB(255, 230, 90))
			text.AutomaticSize = Enum.AutomaticSize.None
			text.Size = UDim2.fromScale(1, 1)
			text.Parent = tag
			tag.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
			readyTag = tag
		end
		(readyTag :: BillboardGui).Adornee = mine
		;(readyTag :: BillboardGui).Enabled = true
	elseif readyTag then
		readyTag.Enabled = false
	end
end

function BasePickerController:Init(controllers)
	C = controllers
	picker = Ui.screen("BasePicker")
	list = Ui.find(picker, "Window.List")
	template = Ui.find(picker, "Window.List.Template")
	preview = Ui.screen("BasePreview")
	bar = Ui.find(preview, "Bar")
end

function BasePickerController:Start()
	Ui.button(Ui.find(picker, "Window.Close"), function()
		Ui.close("BasePicker")
	end)
	Ui.button(Ui.find(picker, "Dim"), function()
		Ui.close("BasePicker")
	end)
	Ui.button(Ui.find(bar, "Close"), stopPreview)
	Ui.button(Ui.find(bar, "Prev"), function()
		tryOn((selected - 2) % #BaseSkins.List + 1)
	end)
	Ui.button(Ui.find(bar, "Next"), function()
		tryOn(selected % #BaseSkins.List + 1)
	end)
	Ui.button(Ui.find(bar, "Main"), function()
		local data = State.data
		local def = BaseSkins.List[selected]
		if not data or not def then
			return
		end
		local status = statusOf(data, def)
		if status == "Ready" then
			skinAction("Unlock", def.Id)
		elseif status == "Owned" then
			skinAction("Equip", def.Id)
		elseif status == "Locked" then
			toast(false, "Tick every box to unlock it")
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") == "BasePicker" then
			local data = State.data
			if data and prompt:GetAttribute("Base") == data.BaseIndex then
				BasePickerController:Open()
			end
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(stopPreview)
	task.spawn(function()
		local structures = Workspace:WaitForChild("Structures", 60)
		if structures then
			structures.DescendantAdded:Connect(function(d)
				if d.Name == "BasePickerPrompt" then
					task.defer(syncSigns)
				end
			end)
			syncSigns()
		end
	end)
	local lastSignature = ""
	State.Changed:Connect(function(data)
		local owned = {}
		for id in (data.BaseSkins and data.BaseSkins.Owned) or {} do
			table.insert(owned, id)
		end
		table.sort(owned)
		local indexCount = 0
		for _ in data.Index or {} do
			indexCount += 1
		end
		local signature = table.concat({
			tostring(data.BaseIndex),
			data.Rebirths,
			indexCount,
			table.concat(owned, ","),
			if data.BaseSkins then tostring(data.BaseSkins.Equipped) else "",
		}, "|")
		if signature == lastSignature then
			return
		end
		lastSignature = signature
		syncSigns()
		if previewing then
			renderBar()
		end
		if Ui.isOpen(picker) then
			renderList()
		end
	end)
end

return BasePickerController
