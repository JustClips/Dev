--!strict
-- Gear window (screen "Garage"; Dev renamed it from Tools), opened from Gear in the HUD's Upgrade menu
-- (the plaza Garage stall was removed on 2026-10-30):
--   Tools tab: the tool ladder. Buy the next tool with cash or skip to it with Robux.
--   Cars tab: every car with its stats, buy with cash, spawn it at your feet, unlock/rent
--   with Robux.
-- Cars then live in hotbar slot 2.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)
local Prices = require(Client.Prices)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Tools = require(Shared.Config.Tools)

local GREEN = Color3.fromRGB(61, 220, 90)
local BLUE = Color3.fromRGB(76, 141, 255)
local GREY = Color3.fromRGB(166, 174, 194)
local GOLD = Color3.fromRGB(255, 176, 32)
local ORANGE = Color3.fromRGB(255, 140, 60)

local GarageController = {}

local C: any
local gui: ScreenGui
local list: ScrollingFrame
local template: TextButton
local tabTools: TextButton
local tabCars: TextButton
local hint: TextLabel
local tab = "Tools"

local function toast(ok: boolean, message: string?)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
end

local function liveProduct(key: string)
	local def = Products.ProductByKey[key]
	return if def and def.Id ~= 0 then def else nil
end

local function promptRobux(key: string)
	local ok, message = Net.func("PromptPurchase"):InvokeServer(key)
	if not ok then
		toast(false, message)
	end
end

-- Layout C (Dev, 2026-11-01): small tiles on the left, details of the tapped one on the
-- right. Each tab turns its tools / cars into entries; the tiles and the panel draw them.
type Entry = {
	key: string,
	order: number,
	name: string,
	image: string,
	width: number,
	power: number,
	holds: number,
	state: string, -- OWNED, EQUIPPED, NEXT, LOCKED, RENTED, BUY, REBIRTH n
	color: Color3,
	shadow: boolean, -- locked: drawn as a dark shadow
	price: string?, -- on the tile
	mainText: string,
	mainColor: Color3,
	onMain: () -> (),
	robux: any?,
	robuxVerb: string,
}

local detail: Frame
local picked: { [string]: string? } = {}
-- The details panel's buttons are wired once; these say what they do right now.
local mainAction: () -> () = function() end
local robuxAction: () -> () = function() end

local function toolEntries(data): ({ Entry }, Entry?)
	local entries = {}
	local current = data.EffectiveTier or data.ToolTier
	local now: Entry? = nil
	for _, tool in Tools.List do
		local owned = tool.Tier <= data.ToolTier
		local isNext = tool.Tier == data.ToolTier + 1
		local toolPrice = if tool.Tier == 2 then Tools.tutorialPrice(tool.Price, BigNum.toNumber(data.Cash), data.Flags.TutorialDone == true) else tool.Price
		local afford = BigNum.gte(data.Cash, toolPrice)
		local e: Entry = {
			key = tostring(tool.Tier),
			order = tool.Tier,
			name = tool.Name,
			image = AssetLibrary.toolIcon(tool.Id),
			width = tool.Radius,
			power = tool.Power,
			holds = tool.Capacity,
			state = "LOCKED",
			color = GREY,
			shadow = false,
			mainText = "",
			mainColor = GREY,
			onMain = function() end,
			robux = nil,
			robuxVerb = "Get now",
		}
		if owned then
			local equipped = tool.Tier == current
			e.state = if equipped then "EQUIPPED" else "OWNED"
			e.color = if equipped then BLUE else GREEN
			e.mainText = if equipped then "Equipped" else "Equip"
			e.mainColor = if equipped then GREY else BLUE
			e.onMain = function()
				if tool.Tier ~= (State.data and State.data.EffectiveTier or data.ToolTier) then
					toast(Net.func("EquipTool"):InvokeServer(tool.Tier))
				end
			end
			if equipped then
				now = e
			end
		elseif isNext then
			e.state = "NEXT"
			e.color = GOLD
			e.price = if toolPrice == 0 then "FREE!" else Format.cash(toolPrice)
			e.mainText = if toolPrice == 0 then "FREE!" else `Buy {Format.cash(toolPrice)}`
			e.mainColor = if afford then GREEN else GREY
			e.onMain = function()
				local teaching = State.data ~= nil and State.data.TutorialStep == "Upgrade"
				local ok, message = Net.func("BuyNextTool"):InvokeServer()
				toast(ok, message)
				-- Tutorial (Dev, 2026-11-01): after the free Broom, Gear closes by itself a
				-- second later and the Upgrade menu opens, so the next step's spotlight lands
				-- straight on the Upgrades tile.
				if ok and teaching then
					task.delay(1, function()
						Ui.close("Garage")
						C.MenuController:Open("UpgradeMenu")
					end)
				end
			end
			e.robux = if tool.Tier > Tools.FreeTier then liveProduct("ToolSkip" .. tool.Tier) else nil
		else
			e.shadow = true
			e.price = Format.cash(tool.Price)
			e.mainText = Format.cash(tool.Price)
			e.onMain = function()
				toast(false, `Get the {Tools.get(tool.Tier - 1).Name} first`)
			end
		end
		table.insert(entries, e)
	end
	return entries, now
end

local function carEntries(data): ({ Entry }, Entry?)
	local entries = {}
	local now: Entry? = nil
	for i, car in Tools.Vehicles do
		local owned = Tools.hasVehicle(data.Vehicles, car.Id)
		local rented = not owned and data.RentedVehicle == car.Id
		local locked = not owned and not rented and data.Rebirths < car.RequiredRebirths
		local e: Entry = {
			key = car.Id,
			order = i,
			name = car.Name,
			image = AssetLibrary.carIcon(car.Id),
			width = car.Radius,
			-- Your best hand tool powers the car's brush too (Tools.carBoost).
			power = math.floor(car.Power * Tools.carBoost(data.ToolTier)),
			holds = car.Capacity,
			state = "BUY",
			color = GOLD,
			shadow = false,
			mainText = "",
			mainColor = GREY,
			onMain = function() end,
			robux = nil,
			robuxVerb = "Get",
		}
		if owned or rented then
			-- Equip picks the car slot 2 spawns; the equipped one spawns right here.
			local equipped = data.BestVehicle == car.Id
			e.state = if equipped then "EQUIPPED" elseif owned then "OWNED" else "RENTED"
			e.color = if equipped then BLUE elseif owned then GREEN else ORANGE
			if equipped then
				now = e
				e.mainText = "Spawn"
				e.mainColor = GREEN
				e.onMain = function()
					local ok, message = Net.func("SpawnVehicle"):InvokeServer(car.Id)
					if ok then
						Ui.close("Garage")
					else
						toast(false, message)
					end
				end
			else
				e.mainText = "Equip"
				e.mainColor = BLUE
				e.onMain = function()
					toast(Net.func("EquipVehicle"):InvokeServer(car.Id))
				end
			end
		elseif locked then
			e.state = `REBIRTH {car.RequiredRebirths}`
			e.color = GREY
			e.shadow = true
			e.price = Format.cash(car.Price)
			e.mainText = Format.cash(car.Price)
			e.onMain = function()
				toast(false, `Reach Rebirth {car.RequiredRebirths} to unlock the {car.Name}`)
			end
		else
			e.price = Format.cash(car.Price)
			e.mainText = `Buy {Format.cash(car.Price)}`
			e.mainColor = if BigNum.gte(data.Cash, car.Price) then GREEN else GREY
			e.onMain = function()
				toast(Net.func("BuyVehicle"):InvokeServer(car.Id))
			end
			-- Robux: unlock (until rebirth), or rent for this run if unlock isn't on sale.
			e.robux = liveProduct(car.UnlockKey) or liveProduct(car.RentKey)
			e.robuxVerb = if e.robux and e.robux.Kind == "VehicleRental" then "Rent" else "Get"
		end
		table.insert(entries, e)
	end
	return entries, now
end

-- Which tile is picked when a tab opens: the next tool / the equipped car.
local function defaultPick(entries: { Entry }): string?
	for _, state in { "NEXT", "EQUIPPED", "BUY" } do
		for _, e in entries do
			if e.state == state then
				return e.key
			end
		end
	end
	return if entries[1] then entries[1].key else nil
end

local function setStat(name: string, now: number?, new: number, prefix: string)
	local cell = detail:FindFirstChild(name) :: Frame
	local value = cell:FindFirstChild("Value") :: TextLabel
	local fmt = function(n: number): string
		return prefix .. (if n == math.floor(n) then Format.number(n) else tostring(n))
	end
	if now and now ~= new then
		local color = if new > now then "#22A83A" else "#E0475A"
		value.Text = `{fmt(now)} → <font color="{color}">{fmt(new)}</font>`
	else
		value.Text = fmt(new)
	end
	local top = math.max(now or 0, new) * 1.15
	local bar = cell:FindFirstChild("Bar") :: Frame
	;(bar:FindFirstChild("New") :: Frame).Size = UDim2.fromScale(if top > 0 then new / top else 0, 1)
	;(bar:FindFirstChild("Now") :: Frame).Size = UDim2.fromScale(if top > 0 and now then math.min(now, new) / top else 0, 1)
end

local function showDetail(e: Entry, now: Entry?)
	local pill = detail:FindFirstChild("Status") :: Frame
	pill.BackgroundColor3 = e.color
	Ui.setText(pill, e.state)
	local image = detail:FindFirstChild("Icon") :: ImageLabel
	image.Image = e.image
	image.ImageColor3 = if e.shadow then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
	image.ImageTransparency = if e.shadow then 0.45 else 0
	;(detail:FindFirstChild("Name") :: TextLabel).Text = e.name
	local base = if now and now ~= e then now else nil
	setStat("Width", base and base.width, e.width, "")
	setStat("Leaves", base and base.power, e.power, "x")
	setStat("Holds", base and base.holds, e.holds, "")
	local main = detail:FindFirstChild("Main") :: TextButton
	Ui.setText(main, e.mainText)
	main.BackgroundColor3 = e.mainColor
	mainAction = e.onMain
	local robux = detail:FindFirstChild("Robux") :: TextButton
	robux.Visible = e.robux ~= nil
	if e.robux then
		local product = e.robux
		Ui.setText(robux, `{e.robuxVerb} {Ui.ROBUX}{Prices.of(product)}`)
		robuxAction = function()
			promptRobux(product.Key)
		end
	end
end

local render: (keepScroll: boolean?) -> ()

local function drawTiles(entries: { Entry }, pick: string?)
	for _, e in entries do
		local tile = template:Clone() :: TextButton
		tile.Name = e.key
		tile.LayoutOrder = e.order
		tile.Visible = true
		tile.BackgroundColor3 = e.color
		;(tile:FindFirstChild("Tier") :: TextLabel).Text = tostring(e.order)
		;(tile:FindFirstChild("Mark") :: TextLabel).Text = if e.state == "EQUIPPED" then "ON" else ""
		;(tile:FindFirstChild("Lock") :: ImageLabel).Visible = e.shadow
		local image = tile:FindFirstChild("Icon") :: ImageLabel
		image.Image = e.image
		image.ImageColor3 = if e.shadow then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
		image.ImageTransparency = if e.shadow then 0.45 else 0
		;(tile:FindFirstChild("Price") :: TextLabel).Text = e.price or ""
		;(tile:FindFirstChild("Picked") :: Frame).Visible = e.key == pick
		local key = e.key
		Ui.button(tile, function()
			picked[tab] = key
			render(true)
		end)
		tile.Parent = list
	end
end

-- keepScroll: redraws after a purchase, equip or tile tap stay where you were in the list
-- (Dev: buying jumped back to the top). Opening or switching tabs starts at the top.
render = function(keepScroll: boolean?)
	local data = State.data
	if not data or not gui.Enabled then
		return
	end
	local scroll = list.CanvasPosition
	for _, child in list:GetChildren() do
		if child:IsA("GuiButton") and child ~= template then
			child:Destroy()
		end
	end
	tabTools.BackgroundTransparency = if tab == "Tools" then 0 else 0.45
	tabCars.BackgroundTransparency = if tab == "Cars" then 0 else 0.45
	-- How much your best tool powers your cars (Tools.carBoost), shown on both tabs.
	local boost = math.floor((Tools.carBoost(data.ToolTier) - 1) * 100 + 0.5)
	local fromName = Tools.get(Tools.CarBoost.FromTier + 1).Name
	local perTier = math.floor(Tools.CarBoost.PerTier * 100 + 0.5)
	local entries, now
	if tab == "Tools" then
		hint.Text = if boost > 0
			then `Your tool sets your bag on foot and boosts every car's Power +{boost}%.`
			else `Your tool sets your bag on foot. From the {fromName} up, each tool boosts cars +{perTier}%.`
		entries, now = toolEntries(data)
	else
		hint.Text = if boost > 0
			then `Your {Tools.get(data.ToolTier).Name} boosts car Power +{boost}% (shown). Spawn the equipped car here or from slot 2.`
			else `Equip a car, then spawn it here or from slot 2.`
		entries, now = carEntries(data)
	end
	local pick = picked[tab]
	local found: Entry? = nil
	for _, e in entries do
		if e.key == pick then
			found = e
		end
	end
	if not found then
		pick = defaultPick(entries)
		picked[tab] = pick
		for _, e in entries do
			if e.key == pick then
				found = e
			end
		end
	end
	drawTiles(entries, pick)
	if found then
		showDetail(found, now)
	end
	if keepScroll then
		list.CanvasPosition = scroll
		task.defer(function()
			list.CanvasPosition = scroll
		end)
	else
		list.CanvasPosition = Vector2.zero
		-- Scroll only when the picked tile would be out of view.
		task.defer(function()
			local tile = pick and list:FindFirstChild(pick) :: GuiObject?
			if not tile then
				return
			end
			local top = tile.AbsolutePosition.Y - list.AbsolutePosition.Y
			if top + tile.AbsoluteSize.Y <= list.AbsoluteSize.Y then
				return
			end
			local layout = list:FindFirstChildOfClass("UIGridLayout") :: UIGridLayout?
			local cellY = layout and layout.CellSize.Y.Offset or 0
			local k = if cellY > 0 then tile.AbsoluteSize.Y / cellY else 1
			list.CanvasPosition = Vector2.new(0, math.max(0, top / math.max(k, 0.01) - 6))
		end)
	end
end

function GarageController:Open(which: string?)
	tab = which or tab
	-- The tutorial's free Broom is on the Tools tab.
	if not which and State.data and State.data.Flags.TutorialDone ~= true then
		tab = "Tools"
	end
	picked = {} -- opens on the next tool / the equipped car
	Ui.open("Garage")
	render()
end

-- The Buy button of the next tool's card while the Tools tab is open (the tutorial and
-- the first Quest Master job point at it), else nil.
function GarageController:NextToolButton(): GuiObject?
	if not Ui.isOpen(gui) or tab ~= "Tools" then
		return nil
	end
	local data = State.data
	if not data or data.ToolTier >= Tools.MaxTier then
		return nil
	end
	local key = tostring(data.ToolTier + 1)
	-- Its Buy button when the next tool is the one shown, else its tile (tap it first).
	if picked.Tools == key then
		local main = detail:FindFirstChild("Main")
		return if main and main:IsA("GuiObject") then main else nil
	end
	local tile = list:FindFirstChild(key)
	return if tile and tile:IsA("GuiObject") then tile else nil
end

function GarageController:Toggle()
	if Ui.isOpen(gui) then
		Ui.close("Garage")
	else
		GarageController:Open()
	end
end

function GarageController:Init(controllers)
	C = controllers
	gui = Ui.screen("Garage")
	list = Ui.find(gui, "Window.List")
	-- The old card template was a Frame of the same name (LiveSync keeps removed children).
	for _, child in list:GetChildren() do
		if child.Name == "Template" and not child:IsA("TextButton") then
			child:Destroy()
		end
	end
	template = Ui.find(gui, "Window.List.Template")
	detail = Ui.find(gui, "Window.Detail")
	tabTools = Ui.find(gui, "Window.Tabs.TabTools")
	tabCars = Ui.find(gui, "Window.Tabs.TabCars")
	hint = Ui.find(gui, "Window.Hint")
end

function GarageController:Start()
	Ui.button(detail:FindFirstChild("Main") :: GuiButton, function()
		mainAction()
	end)
	Ui.button(detail:FindFirstChild("Robux") :: GuiButton, function()
		robuxAction()
	end)
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Garage")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Garage")
	end)
	Ui.button(tabTools, function()
		tab = "Tools"
		render()
	end)
	Ui.button(tabCars, function()
		tab = "Cars"
		render()
	end)
	local lastSignature = ""
	State.Changed:Connect(function(data)
		local parts = { tostring(data.RentedVehicle), tostring(data.BestVehicle), tostring(data.ToolTier), tostring(data.EffectiveTier) }
		for _, tool in Tools.List do
			table.insert(parts, tostring(BigNum.gte(data.Cash, tool.Price)))
		end
		for _, car in Tools.Vehicles do
			table.insert(parts, `{car.Id}:{data.Vehicles[car.Id] == true}:{BigNum.gte(data.Cash, car.Price)}:{data.Rebirths >= car.RequiredRebirths}`)
		end
		local signature = table.concat(parts, "|")
		if signature ~= lastSignature then
			lastSignature = signature
			render(true)
		end
	end)
end

return GarageController
