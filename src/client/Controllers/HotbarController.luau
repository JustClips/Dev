--!strict
-- Our own hotbar (the default Roblox backpack is hidden):
--   1 = your sweeping tool (equip / put away)
--   2 = your car (spawn under you / put away). With no car it points you to the Garage.
--   3 = your bag (inventory). A badge counts what's new in it since you last opened it.
--   4 (or G) = drop the egg on your head. Only shown while you carry one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Net = require(Shared.Net)
local Tools = require(Shared.Config.Tools)

local INK = Color3.fromRGB(27, 31, 58)
local GREY = Color3.fromRGB(150, 156, 176)
local MINT = Color3.fromRGB(124, 245, 200)

local HotbarController = {}

local C: any
local player = Players.LocalPlayer
local toolSlot: TextButton
local carSlot: TextButton
local bagSlot: TextButton
local dropSlot: TextButton
local dropping = false

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function sweepTool(container: Instance?): Tool?
	if not container then
		return nil
	end
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("SweepTool") then
			return child
		end
	end
	return nil
end

local function toggleTool()
	local h = humanoid()
	if not h or h.SeatPart then
		return
	end
	if sweepTool(player.Character) then
		h:UnequipTools()
	else
		local tool = sweepTool(player:FindFirstChildOfClass("Backpack"))
		if tool then
			h:EquipTool(tool)
		end
	end
end

local function toggleCar()
	local data = State.data
	if data and not data.BestVehicle and not data.InVehicle then
		C.HudController:Toast("No car yet! Pick one in Tools.", "Info")
		C.GarageController:Open("Cars")
		return
	end
	local ok, message = Net.func("ToggleVehicle"):InvokeServer()
	if not ok and message then
		C.HudController:Toast(message, "Bad")
	end
end

local function dropEgg()
	local data = State.data
	if dropping or not data or #(data.CarriedEggs or {}) == 0 then
		return
	end
	dropping = true
	local ok, message = Net.func("Inventory"):InvokeServer("DropEgg")
	dropping = false
	if message then
		C.HudController:Toast(message, if ok then "Info" else "Bad")
	end
end

-- The selected slot gets a thick mint outline instead of the navy one.
local function setSelected(slot: TextButton, on: boolean)
	local stroke = slot:FindFirstChild("Stroke") :: UIStroke?
	if stroke then
		stroke.Color = if on then MINT else INK
		stroke.Thickness = if on then 6 else 4
	end
end

local function render(_: any?)
	local data = State.data
	if not data then
		return
	end
	local tool = Tools.get(data.ToolTier)
	;(toolSlot:FindFirstChild("Name") :: TextLabel).Text = tool.Name
	;(toolSlot:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.toolIcon(tool.Id)
	local car = Tools.vehicle(data.BestVehicle or "")
	local carName = carSlot:FindFirstChild("Name") :: TextLabel
	local carIcon = carSlot:FindFirstChild("Icon") :: ImageLabel
	carName.Text = if car then car.Name else "No car"
	carName.TextColor3 = if car then INK else GREY
	carIcon.Image = if car then AssetLibrary.carIcon(car.Id) else AssetLibrary.image("Icon_Lock")
	setSelected(carSlot, data.InVehicle)
	-- Badge: what's new in the bag since you last opened it (ready eggs in your park have
	-- their own badge on the Eggs button, so they don't count here).
	Ui.setBadge(bagSlot:FindFirstChild("Badge") :: Frame, C.InventoryController:NewCount())
	setSelected(toolSlot, not data.InVehicle and sweepTool(player.Character) ~= nil)
	local carrying = #(data.CarriedEggs or {})
	dropSlot.Visible = carrying > 0
	;(dropSlot:FindFirstChild("Name") :: TextLabel).Text = if carrying > 1 then `Drop 1 of {carrying}` else "Drop egg"
end

local function hideDefaultBackpack()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(1)
	end
end

function HotbarController:Init(controllers)
	C = controllers
	local hud = Ui.screen("Hud")
	toolSlot = Ui.find(hud, "Hotbar.ToolSlot")
	carSlot = Ui.find(hud, "Hotbar.CarSlot")
	bagSlot = Ui.find(hud, "Hotbar.BagSlot")
	dropSlot = Ui.find(hud, "Hotbar.DropSlot")
end

function HotbarController:Start()
	task.spawn(hideDefaultBackpack)
	Ui.button(toolSlot, toggleTool)
	Ui.button(carSlot, toggleCar)
	Ui.button(bagSlot, function()
		C.InventoryController:Toggle()
	end)
	Ui.button(dropSlot, function()
		task.spawn(dropEgg)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.One then
			toggleTool()
		elseif input.KeyCode == Enum.KeyCode.Two then
			toggleCar()
		elseif input.KeyCode == Enum.KeyCode.Three then
			C.InventoryController:Toggle()
		elseif input.KeyCode == Enum.KeyCode.Four or input.KeyCode == Enum.KeyCode.G then
			task.spawn(dropEgg)
		end
	end)
	State.observe(render)
	-- Eggs turn ready on their own: refresh the badge now and then.
	task.spawn(function()
		while true do
			task.wait(1)
			render()
		end
	end)
	-- Equipping happens on the character; refresh the highlight when tools move.
	local function watch(character: Model)
		character.ChildAdded:Connect(render)
		character.ChildRemoved:Connect(render)
		render()
	end
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(watch)
end

return HotbarController
