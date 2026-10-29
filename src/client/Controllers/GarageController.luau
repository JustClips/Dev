--!strict
-- Tools window (screen "Garage"), opened from the Tools button on the right or the Garage
-- kiosk on the south plaza:
--   Tools tab: the tool ladder. Buy the next tool with cash or skip to it with Robux.
--   Cars tab: every car with its stats, buy with cash, spawn it (at the Garage pad when
--   you're there, else at your feet), unlock/rent with Robux, and Go to Garage.
-- Cars then live in hotbar slot 2.
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

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

local GarageController = {}

local C: any
local gui: ScreenGui
local list: ScrollingFrame
local template: Frame
local tabTools: TextButton
local tabCars: TextButton
local hint: TextLabel
local goGarage: TextButton
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

local function toolRows(data)
	for _, tool in Tools.List do
		local row = newRow(tool.Tier, tool.Id)
		local owned = tool.Tier <= data.ToolTier
		local isNext = tool.Tier == data.ToolTier + 1
		;(row:FindFirstChild("Name") :: TextLabel).Text = tool.Name
		;(row:FindFirstChild("Stats") :: TextLabel).Text =
			`Width {tool.Radius} · Power {tool.Power} · Holds {Format.number(tool.Capacity)}`
		;(row:FindFirstChild("Price") :: TextLabel).Text = if tool.Tier == data.ToolTier
			then "In your hands"
			elseif owned then "Owned"
			else Format.cash(tool.Price)
		;(row:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.toolIcon(tool.Id)
		local main = row:FindFirstChild("Main") :: TextButton
		if owned then
			Ui.setText(main, if tool.Tier == data.ToolTier then "Equipped" else "Owned")
			main.BackgroundColor3 = GREY
			Ui.button(main, function() end)
		elseif isNext then
			Ui.setText(main, `Buy {Format.cash(tool.Price)}`)
			main.BackgroundColor3 = if BigNum.gte(data.Cash, tool.Price) then GREEN else GREY
			Ui.button(main, function()
				toast(Net.func("BuyNextTool"):InvokeServer())
			end)
		else
			Ui.setText(main, "Locked")
			main.BackgroundColor3 = GREY
			Ui.button(main, function()
				toast(false, `Get the {Tools.get(tool.Tier - 1).Name} first`)
			end)
		end
		local robux = row:FindFirstChild("Robux") :: TextButton
		local product = if isNext then liveProduct("ToolSkip" .. tool.Tier) else nil
		robux.Visible = product ~= nil
		if product then
			Ui.setText(robux, `Get now {Ui.ROBUX}{product.Price}`)
			Ui.button(robux, function()
				promptRobux(product.Key)
			end)
		end
		row.Parent = list
	end
end

local function carRows(data)
	for i, car in Tools.Vehicles do
		local row = newRow(i, car.Id)
		local owned = data.Vehicles[car.Id] == true
		local rented = data.RentedVehicle == car.Id
		local locked = not owned and not rented and data.Rebirths < car.RequiredRebirths
		;(row:FindFirstChild("Name") :: TextLabel).Text = car.Name
		;(row:FindFirstChild("Stats") :: TextLabel).Text =
			`Width {car.Radius} · Power {car.Power} · Holds {Format.number(car.Capacity)}`
		;(row:FindFirstChild("Price") :: TextLabel).Text = if owned
			then "Owned"
			elseif rented then "Rented for this run"
			elseif locked then `Needs Rebirth {car.RequiredRebirths} · {Format.cash(car.Price)}`
			else Format.cash(car.Price)
		;(row:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.carIcon(car.Id)

		local main = row:FindFirstChild("Main") :: TextButton
		if owned or rented then
			Ui.setText(main, "Spawn")
			main.BackgroundColor3 = BLUE
			Ui.button(main, function()
				local ok, message = Net.func("SpawnVehicle"):InvokeServer(car.Id)
				if ok then
					Ui.close("Garage")
				else
					toast(false, message)
				end
			end)
		elseif locked then
			Ui.setText(main, "Locked")
			main.BackgroundColor3 = GREY
			Ui.button(main, function()
				toast(false, `Reach Rebirth {car.RequiredRebirths} to unlock the {car.Name}`)
			end)
		else
			Ui.setText(main, "Buy")
			main.BackgroundColor3 = if BigNum.gte(data.Cash, car.Price) then GREEN else GREY
			Ui.button(main, function()
				toast(Net.func("BuyVehicle"):InvokeServer(car.Id))
			end)
		end

		-- Robux: unlock (until rebirth), or rent for this run if unlock isn't on sale.
		local robux = row:FindFirstChild("Robux") :: TextButton
		local product = if owned or rented or locked then nil else (liveProduct(car.UnlockKey) or liveProduct(car.RentKey))
		robux.Visible = product ~= nil
		if product then
			local verb = if product.Kind == "VehicleRental" then "Rent" else "Get"
			Ui.setText(robux, `{verb} {Ui.ROBUX}{product.Price}`)
			Ui.button(robux, function()
				promptRobux(product.Key)
			end)
		end
		row.Parent = list
	end
end

local function render()
	local data = State.data
	if not data or not gui.Enabled then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end
	tabTools.BackgroundTransparency = if tab == "Tools" then 0 else 0.45
	tabCars.BackgroundTransparency = if tab == "Cars" then 0 else 0.45
	goGarage.Visible = tab == "Cars"
	if tab == "Tools" then
		hint.Text = "Better tools sweep wider, faster and hold more leaves."
		toolRows(data)
	else
		hint.Text = "Cars sweep a huge area and hold more. Spawn one here or from slot 2."
		carRows(data)
	end
	list.CanvasPosition = Vector2.zero
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
	goGarage = Ui.find(gui, "Window.GoGarage")
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
	Ui.button(goGarage, function()
		local ok, message = Net.func("Teleport"):InvokeServer("Garage")
		if ok then
			Ui.close("Garage")
		else
			toast(false, message)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") == "Garage" then
			GarageController:Open("Cars")
		end
	end)
	local lastSignature = ""
	State.Changed:Connect(function(data)
		local parts = { tostring(data.RentedVehicle), tostring(data.ToolTier) }
		for _, tool in Tools.List do
			table.insert(parts, tostring(BigNum.gte(data.Cash, tool.Price)))
		end
		for _, car in Tools.Vehicles do
			table.insert(parts, `{car.Id}:{data.Vehicles[car.Id] == true}:{BigNum.gte(data.Cash, car.Price)}:{data.Rebirths >= car.RequiredRebirths}`)
		end
		local signature = table.concat(parts, "|")
		if signature ~= lastSignature then
			lastSignature = signature
			render()
		end
	end)
end

return GarageController
