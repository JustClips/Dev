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
local template: Frame
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

local function newRow(order: number, name: string): Frame
	local row = template:Clone()
	row.Name = name
	row.LayoutOrder = order
	row.Visible = true
	return row
end

-- Card details shared by tools and cars.
local function setStats(row: Frame, width: number, power: number, holds: number)
	local stats = { Width = tostring(width), Leaves = `x{Format.number(power)}`, Holds = Format.number(holds) }
	for name, value in stats do
		local cell = row:FindFirstChild(name)
		local label = cell and cell:FindFirstChild("Value") :: TextLabel?
		if label then
			label.Text = value
		end
	end
end

-- The corner pill: where you stand with this one (nil hides it).
local function setStatus(row: Frame, text: string?, color: Color3?)
	local pill = row:FindFirstChild("Status") :: Frame
	pill.Visible = text ~= nil
	if text then
		pill.BackgroundColor3 = color or GREEN
		Ui.setText(pill, text)
	end
end

local function setMain(row: Frame, text: string, color: Color3, fn: () -> ())
	local main = row:FindFirstChild("Main") :: TextButton
	Ui.setText(main, text)
	main.BackgroundColor3 = color
	Ui.button(main, fn)
end

local function setRobux(row: Frame, product: any, verb: string)
	local robux = row:FindFirstChild("Robux") :: TextButton
	robux.Visible = product ~= nil
	if product then
		Ui.setText(robux, `{verb} {Ui.ROBUX}{Prices.of(product)}`)
		Ui.button(robux, function()
			promptRobux(product.Key)
		end)
	end
end

local function toolRows(data)
	local current = data.EffectiveTier or data.ToolTier
	for _, tool in Tools.List do
		local row = newRow(tool.Tier, tool.Id)
		local owned = tool.Tier <= data.ToolTier
		local isNext = tool.Tier == data.ToolTier + 1
		local toolPrice = if tool.Tier == 2 then Tools.tutorialPrice(tool.Price, BigNum.toNumber(data.Cash), data.Flags.TutorialDone == true) else tool.Price
		local afford = BigNum.gte(data.Cash, toolPrice)
		;(row:FindFirstChild("Name") :: TextLabel).Text = tool.Name
		;(row:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.toolIcon(tool.Id)
		setStats(row, tool.Radius, tool.Power, tool.Capacity)
		if owned then
			local equipped = tool.Tier == current
			setStatus(row, if equipped then "EQUIPPED" else "OWNED", if equipped then BLUE else GREEN)
			setMain(row, if equipped then "Equipped" else "Equip", if equipped then GREY else BLUE, function()
				if tool.Tier ~= (State.data and State.data.EffectiveTier or data.ToolTier) then
					toast(Net.func("EquipTool"):InvokeServer(tool.Tier))
				end
			end)
		elseif isNext then
			setStatus(row, "NEXT", GOLD)
			-- The price is on the button (Dev: it was easy to miss under the name).
			setMain(row, if toolPrice == 0 then "Get it FREE" else `Buy {Format.cash(toolPrice)}`, if afford then GREEN else GREY, function()
				toast(Net.func("BuyNextTool"):InvokeServer())
			end)
		else
			setStatus(row, "LOCKED", GREY)
			setMain(row, Format.cash(tool.Price), GREY, function()
				toast(false, `Get the {Tools.get(tool.Tier - 1).Name} first`)
			end)
		end
		setRobux(row, if isNext and tool.Tier > Tools.FreeTier then liveProduct("ToolSkip" .. tool.Tier) else nil, "Get now")
		row.Parent = list
	end
end

local function carRows(data)
	for i, car in Tools.Vehicles do
		local row = newRow(i, car.Id)
		local owned = Tools.hasVehicle(data.Vehicles, car.Id)
		local rented = not owned and data.RentedVehicle == car.Id
		local locked = not owned and not rented and data.Rebirths < car.RequiredRebirths
		;(row:FindFirstChild("Name") :: TextLabel).Text = car.Name
		;(row:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.carIcon(car.Id)
		-- Your best hand tool powers the car's brush too (Tools.carBoost).
		setStats(row, car.Radius, math.floor(car.Power * Tools.carBoost(data.ToolTier)), car.Capacity)
		if owned or rented then
			-- Equip picks the car slot 2 spawns; the equipped one spawns right here.
			local equipped = data.BestVehicle == car.Id
			setStatus(row, if equipped then "EQUIPPED" elseif owned then "OWNED" else "RENTED", if equipped then BLUE elseif owned then GREEN else ORANGE)
			if equipped then
				setMain(row, "Spawn", GREEN, function()
					local ok, message = Net.func("SpawnVehicle"):InvokeServer(car.Id)
					if ok then
						Ui.close("Garage")
					else
						toast(false, message)
					end
				end)
			else
				setMain(row, "Equip", BLUE, function()
					toast(Net.func("EquipVehicle"):InvokeServer(car.Id))
				end)
			end
		elseif locked then
			setStatus(row, `REBIRTH {car.RequiredRebirths}`, GREY)
			setMain(row, Format.cash(car.Price), GREY, function()
				toast(false, `Reach Rebirth {car.RequiredRebirths} to unlock the {car.Name}`)
			end)
		else
			setStatus(row, nil)
			setMain(row, `Buy {Format.cash(car.Price)}`, if BigNum.gte(data.Cash, car.Price) then GREEN else GREY, function()
				toast(Net.func("BuyVehicle"):InvokeServer(car.Id))
			end)
		end
		-- Robux: unlock (until rebirth), or rent for this run if unlock isn't on sale.
		local product = if owned or rented or locked then nil else (liveProduct(car.UnlockKey) or liveProduct(car.RentKey))
		setRobux(row, product, if product and product.Kind == "VehicleRental" then "Rent" else "Get")
		row.Parent = list
	end
end

-- keepScroll: redraws after a purchase or equip stay where you were in the list
-- (Dev: buying jumped back to the top). Opening or switching tabs starts at the top.
local function render(keepScroll: boolean?)
	local data = State.data
	if not data or not gui.Enabled then
		return
	end
	local scroll = list.CanvasPosition
	for _, child in list:GetChildren() do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end
	tabTools.BackgroundTransparency = if tab == "Tools" then 0 else 0.45
	tabCars.BackgroundTransparency = if tab == "Cars" then 0 else 0.45
	-- How much your best tool powers your cars (Tools.carBoost), shown on both tabs.
	local boost = math.floor((Tools.carBoost(data.ToolTier) - 1) * 100 + 0.5)
	local fromName = Tools.get(Tools.CarBoost.FromTier + 1).Name
	local perTier = math.floor(Tools.CarBoost.PerTier * 100 + 0.5)
	if tab == "Tools" then
		hint.Text = if boost > 0
			then `Your tool sets your bag on foot. It also boosts every car's Power +{boost}% (+{perTier}% per tool).`
			else `Your tool sets your bag on foot. From the {fromName} up, each tool boosts cars +{perTier}%.`
		toolRows(data)
	else
		hint.Text = if boost > 0
			then `Your {Tools.get(data.ToolTier).Name} boosts car Power +{boost}% (shown). Equip a car, then spawn it here or from slot 2.`
			else `Equip a car, then spawn it here or from slot 2. From the {fromName} up, tools boost cars +{perTier}%.`
		carRows(data)
	end
	if keepScroll then
		list.CanvasPosition = scroll
		-- The canvas grows back after the layout updates; set it again once it has.
		task.defer(function()
			list.CanvasPosition = scroll
		end)
	else
		list.CanvasPosition = Vector2.zero
		-- Tools open at the top, and only scroll when the next tool's card would be out of
		-- view (Dev 2026-10-31: the window opened half-scrolled with the Broom cut off).
		if tab == "Tools" then
			local focus = Tools.List[math.min(data.ToolTier + 1, Tools.MaxTier)]
			task.defer(function()
				local card = focus and list:FindFirstChild(focus.Id) :: GuiObject?
				if not card then
					return
				end
				local top = card.AbsolutePosition.Y - list.AbsolutePosition.Y
				local bottom = top + card.AbsoluteSize.Y
				if bottom <= list.AbsoluteSize.Y then
					return
				end
				-- Screen pixels to layout units (the window has a UIScale).
				local layout = list:FindFirstChildOfClass("UIGridLayout") :: UIGridLayout?
				local cellY = layout and layout.CellSize.Y.Offset or 0
				local k = if cellY > 0 then card.AbsoluteSize.Y / cellY else 1
				list.CanvasPosition = Vector2.new(0, math.max(0, top / math.max(k, 0.01) - 6))
			end)
		end
	end
end

function GarageController:Open(which: string?)
	tab = which or tab
	Ui.open("Garage")
	render()
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
	template = Ui.find(gui, "Window.List.Template")
	tabTools = Ui.find(gui, "Window.Tabs.TabTools")
	tabCars = Ui.find(gui, "Window.Tabs.TabCars")
	hint = Ui.find(gui, "Window.Hint")
end

function GarageController:Start()
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
