--!strict
-- Garage window (opened at the Garage kiosk on the south plaza): every car with its stats,
-- buy with cash, spawn on the Garage pad, or unlock/rent with Robux when those products
-- have IDs. Cars then live in hotbar slot 2.
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

local function toast(ok: boolean, message: string?)
	if message and message ~= "" then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
end

local function liveProduct(key: string)
	local def = Products.ProductByKey[key]
	return if def and def.Id ~= 0 then def else nil
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
	for i, car in Tools.Vehicles do
		local row = template:Clone()
		row.Name = car.Id
		row.LayoutOrder = i
		row.Visible = true
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
				local ok, message = Net.func("PromptPurchase"):InvokeServer(product.Key)
				if not ok then
					toast(false, message)
				end
			end)
		end
		row.Parent = list
	end
end

function GarageController:Open()
	Ui.open("Garage")
	render()
end

function GarageController:Init(controllers)
	C = controllers
	gui = Ui.screen("Garage")
	list = Ui.find(gui, "Window.List")
	template = Ui.find(gui, "Window.List.Template")
end

function GarageController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Garage")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Garage")
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") == "Garage" then
			GarageController:Open()
		end
	end)
	local lastSignature = ""
	State.Changed:Connect(function(data)
		local parts = { tostring(data.RentedVehicle) }
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
