--!strict
-- Pet index (Steal an Egg style). One zone at a time (arrows on the zone panel): cards in
-- their rarity colour with the pet in 3D, dark silhouettes and "???" for pets you haven't
-- hatched. Tap a found pet to see it big on the right. Bars show the zone's progress and
-- the whole collection.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Zones = require(Shared.Config.Zones)

local SILHOUETTE = Color3.fromRGB(27, 31, 58)
local LOCKED_CARD = Color3.fromRGB(74, 81, 112)

local IndexController = {}

local gui: ScreenGui
local grid: ScrollingFrame
local template: TextButton
local zoneName: TextLabel
local zonePanel: Frame
local progress: Frame
local total: Frame
local detail: Frame
local zoneIndex = 1
local selectedId: string? = nil
local lastSignature = ""

local function silhouette(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") then
			d.TextureID = ""
			d.Material = Enum.Material.SmoothPlastic
			d.Color = SILHOUETTE
			d.Transparency = 0
		elseif d:IsA("BasePart") then
			d.Color = SILHOUETTE
			d.Material = Enum.Material.SmoothPlastic
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
end

local function tint(frame: GuiObject, color: Color3)
	frame.BackgroundColor3 = color
	local studs = frame:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = color
	end
end

local function setBar(bar: Frame, have: number, of: number, label: string)
	local fill = bar:FindFirstChild("Fill") :: Frame
	fill.Size = UDim2.fromScale(if of > 0 then have / of else 0, 1)
	Ui.setText(bar, label)
end

local function zonePets(zoneId: string)
	local list = {}
	for _, def in Aliens.List do
		if (def.Zone or "Landing") == zoneId then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Eggs.order(a.Rarity), Eggs.order(b.Rarity)
		if ra == rb then
			return a.Income < b.Income
		end
		return ra < rb
	end)
	return list
end

local function renderDetail(data)
	local viewport = detail:FindFirstChild("Viewport") :: ViewportFrame
	local nameLabel = detail:FindFirstChild("Name") :: TextLabel
	local rarityLabel = detail:FindFirstChild("Rarity") :: TextLabel
	local incomeLabel = detail:FindFirstChild("Income") :: TextLabel
	local hint = detail:FindFirstChild("Hint") :: TextLabel
	local def = selectedId and Aliens.ById[selectedId]
	local known = def ~= nil and data.Index[def.Id] == true
	viewport.Visible = def ~= nil
	if not def then
		nameLabel.Text = ""
		rarityLabel.Text = ""
		incomeLabel.Text = ""
		hint.Text = "Tap a pet to see it here."
		return
	end
	local model = ModelView.show(viewport, AssetLibrary.alien(def.Id), "Alien_" .. def.Id, 1.1)
	if not known then
		silhouette(model)
	end
	local rarity = Eggs.ByName[def.Rarity]
	nameLabel.Text = if known then def.Name else "???"
	rarityLabel.Text = def.Rarity
	rarityLabel.TextColor3 = rarity.Color
	incomeLabel.Text = if known then `{Format.cash(def.Income)}/s` else ""
	local zone = Zones.ById[def.Zone or "Landing"]
	hint.Text = if known
		then "Hatched! Golden and Rainbow ones earn even more."
		else `Hatch a {def.Rarity} egg from {zone and zone.Name or "the Moon"} to find it.`
end

local function render(force: boolean?)
	local data = State.data
	if not data then
		return
	end
	local zone = Zones.List[zoneIndex]
	local found = 0
	for _ in data.Index do
		found += 1
	end
	local signature = table.concat({ zone.Id, found, selectedId or "", if AssetLibrary.isReady() then "3d" else "" }, "|")
	if signature == lastSignature and not force then
		return
	end
	lastSignature = signature

	zoneName.Text = zone.Name
	tint(zonePanel, zone.DustColor:Lerp(Color3.new(0, 0, 0), 0.25))
	for _, child in grid:GetChildren() do
		if child:IsA("GuiButton") and child ~= template then
			child:Destroy()
		end
	end
	local pets = zonePets(zone.Id)
	local have = 0
	for i, def in pets do
		local known = data.Index[def.Id] == true
		if known then
			have += 1
		end
		local card = template:Clone()
		card.Name = def.Id
		card.LayoutOrder = i
		card.Visible = true
		tint(card, if known then Eggs.ByName[def.Rarity].Color else LOCKED_CARD)
		local stroke = card:FindFirstChild("Stroke") :: UIStroke?
		if stroke then
			stroke.Color = if def.Id == selectedId then Color3.new(1, 1, 1) else SILHOUETTE
			stroke.Thickness = if def.Id == selectedId then 5 else 3
		end
		;(card:FindFirstChild("Name") :: TextLabel).Text = if known then def.Name else "???"
		local model = ModelView.show(card:FindFirstChild("Viewport") :: ViewportFrame, AssetLibrary.alien(def.Id), "Alien_" .. def.Id)
		if not known then
			silhouette(model)
		end
		Ui.button(card, function()
			selectedId = def.Id
			render(true)
		end)
		card.Parent = grid
	end
	setBar(progress, have, #pets, `{have}/{#pets}`)
	setBar(total, found, #Aliens.List, `Unlocked: {found}/{#Aliens.List}`)
	renderDetail(data)
end

local function step(delta: number)
	zoneIndex = (zoneIndex - 1 + delta) % #Zones.List + 1
	selectedId = nil
	render(true)
end

function IndexController:Toggle()
	Ui.toggle("Index")
	render(true)
end

function IndexController:Init()
	gui = Ui.screen("Index")
	grid = Ui.find(gui, "Window.Body.Grid")
	template = Ui.find(gui, "Window.Body.Grid.Template")
	zonePanel = Ui.find(gui, "Window.Body.Zone")
	zoneName = Ui.find(gui, "Window.Body.Zone.Name")
	progress = Ui.find(gui, "Window.Body.Progress")
	detail = Ui.find(gui, "Window.Body.Detail")
	total = Ui.find(gui, "Window.Total")
end

function IndexController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Index")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Index")
	end)
	Ui.button(Ui.find(gui, "Window.Body.Zone.Prev"), function()
		step(-1)
	end)
	Ui.button(Ui.find(gui, "Window.Body.Zone.Next"), function()
		step(1)
	end)
	State.Changed:Connect(function()
		if gui.Enabled then
			render(false)
		end
	end)
end

return IndexController
