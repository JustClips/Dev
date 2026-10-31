--!strict
-- Pet index (Dev, 2026-10-31, from a reference). One rarity at a time (tabs down the right,
-- plus Exclusive for the daily-streak pets): cards in the rarity's colour with the pet in 3D,
-- "1 in N" (its chance within an egg of its zone and rarity) and the zone; dark silhouettes
-- and "???" for pets you haven't hatched. Under the grid, "complete the set" with its reward
-- (claimed here once every pet of the rarity is found) and how many you've found.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Rewards = require(Shared.Config.Rewards)
local Zones = require(Shared.Config.Zones)

local SILHOUETTE = Color3.fromRGB(27, 31, 58)
local GREEN = Color3.fromRGB(61, 220, 90)
local GREY = Color3.fromRGB(181, 186, 198)
local TABS = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Cosmic", "Daily" }

local IndexController = {}

local C: any
local gui: ScreenGui
local grid: ScrollingFrame
local template: TextButton
local setPanel: Frame
local foundBar: Frame
local tab = "Common"
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

-- Pets on a tab: one rarity (exclusives aside), or the daily exclusives. Zone order, then
-- income.
local ZONE_ORDER: { [string]: number } = {}
for i, zone in Zones.List do
	ZONE_ORDER[zone.Id] = i
end

local function tabPets(name: string)
	local list = {}
	for _, def in Aliens.List do
		local pick = if name == "Daily" then def.Exclusive == "Daily" else def.Rarity == name and not def.Exclusive
		if pick then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		local za, zb = ZONE_ORDER[a.Zone or "Landing"] or 99, ZONE_ORDER[b.Zone or "Landing"] or 99
		if za == zb then
			return a.Income < b.Income
		end
		return za < zb
	end)
	return list
end

local function rewardText(reward: Rewards.Reward): (string, string)
	if reward.Kind == "Item" then
		local item = Items.ById[reward.Item or ""]
		local amount = reward.Amount or 1
		local name = if item then item.Name else "Item"
		return if item then item.Icon else "Icon_Gift", if amount > 1 then `{amount}x {name}` else name
	elseif reward.Kind == "Egg" then
		return "Icon_Egg", `{reward.Rarity} Egg`
	end
	return "Icon_Gift", "A prize"
end

local function setButton(button: GuiButton, label: string, color: Color3)
	Ui.setText(button, label)
	tint(button, color)
end

local function render(force: boolean?)
	local data = State.data
	if not data then
		return
	end
	local found = 0
	for _ in data.Index do
		found += 1
	end
	local info = data.Rewards
	local claimed = info and info.IndexSets and info.IndexSets[tab] == true
	local signature = table.concat({ tab, found, tostring(claimed), if AssetLibrary.isReady() then "3d" else "" }, "|")
	if signature == lastSignature and not force then
		return
	end
	lastSignature = signature

	for _, child in grid:GetChildren() do
		if child:IsA("GuiButton") and child ~= template then
			child:Destroy()
		end
	end
	local pets = tabPets(tab)
	local have = 0
	for i, def in pets do
		local known = data.Index[def.Id] == true
		if known then
			have += 1
		end
		local rarity = Eggs.ByName[def.Rarity]
		local color = if rarity then rarity.Color else GREY
		local card = template:Clone()
		card.Name = def.Id
		card.LayoutOrder = i
		card.Visible = true
		-- Unfound: the rarity colour, darkened.
		tint(card, if known then color else color:Lerp(Color3.new(0, 0, 0), 0.55))
		;(card:FindFirstChild("Name") :: TextLabel).Text = if known then def.Name else "???"
		local chance = card:FindFirstChild("Chance") :: TextLabel
		local zoneLabel = card:FindFirstChild("Zone") :: TextLabel
		if def.Exclusive then
			chance.Text = "Day 7"
			zoneLabel.Text = "Daily streak"
		else
			chance.Text = `1 in {#Aliens.pool(def.Zone, def.Rarity)}`
			local zone = Zones.ById[def.Zone or "Landing"]
			zoneLabel.Text = if zone then zone.Name else ""
		end
		local model = ModelView.show(card:FindFirstChild("Viewport") :: ViewportFrame, AssetLibrary.alien(def.Id), "Alien_" .. def.Id)
		if not known then
			silhouette(model)
		end
		card.Parent = grid
	end

	-- The set strip: reward, and a button that says how many you've found until you can
	-- claim it.
	local reward = Rewards.IndexSets[tab]
	local title = setPanel:FindFirstChild("Title") :: TextLabel
	local rewardLabel = setPanel:FindFirstChild("Reward") :: TextLabel
	local icon = setPanel:FindFirstChild("Icon") :: ImageLabel
	local claim = setPanel:FindFirstChild("Claim") :: TextButton
	if reward then
		local image, text = rewardText(reward)
		title.Text = `COMPLETE THE {string.upper(tab)} SET`
		rewardLabel.Text = text
		icon.Image = AssetLibrary.image(image)
		if claimed then
			setButton(claim, "CLAIMED", GREY)
		elseif have >= #pets and #pets > 0 then
			setButton(claim, "CLAIM!", GREEN)
		else
			setButton(claim, `{have}/{#pets} FOUND`, GREY)
		end
	else
		title.Text = "EXCLUSIVE PETS"
		rewardLabel.Text = "One every week from the day 7 daily reward"
		icon.Image = AssetLibrary.image("Icon_Daily")
		setButton(claim, `{have}/{#pets} FOUND`, GREY)
	end
	local fill = foundBar:FindFirstChild("Fill") :: Frame
	fill.Size = UDim2.fromScale(if #pets > 0 then have / #pets else 0, 1)
	Ui.setText(foundBar, `{have}/{#pets} Found`)
	;(Ui.find(gui, "Window.Total") :: TextLabel).Text = `Unlocked: {found}/{#Aliens.List}`

	-- The open tab is outlined white.
	for _, name in TABS do
		local button = Ui.find(gui, `Window.Tabs.{name}`) :: GuiButton
		local stroke = button:FindFirstChild("Stroke") :: UIStroke?
		if stroke then
			stroke.Color = if name == tab then Color3.new(1, 1, 1) else SILHOUETTE
			stroke.Thickness = if name == tab then 5 else 4
		end
	end
end

function IndexController:Toggle()
	Ui.toggle("Index")
	render(true)
end

function IndexController:Init(controllers)
	C = controllers
	gui = Ui.screen("Index")
	grid = Ui.find(gui, "Window.Body.Grid")
	template = Ui.find(gui, "Window.Body.Grid.Template")
	setPanel = Ui.find(gui, "Window.Set")
	foundBar = Ui.find(gui, "Window.Found")
end

function IndexController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Index")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Index")
	end)
	for _, name in TABS do
		Ui.button(Ui.find(gui, `Window.Tabs.{name}`), function()
			tab = name
			grid.CanvasPosition = Vector2.zero
			render(true)
		end)
	end
	Ui.button(Ui.find(gui, "Window.Set.Claim"), function()
		local ok, message = Net.func("Rewards"):InvokeServer("ClaimIndexSet", tab)
		if message and message ~= "" then
			C.HudController:Toast(message, if ok then "Good" else "Bad")
		end
		if ok then
			Ui.sound("Sell")
		end
	end)
	State.Changed:Connect(function()
		if gui.Enabled then
			render(false)
		end
	end)
end

return IndexController
