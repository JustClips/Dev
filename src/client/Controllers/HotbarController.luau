--!strict
-- Our own hotbar (the default Roblox backpack is hidden):
--   1 = your sweeping tool (equip / put away)
--   2 = your car (spawn under you / put away). With no car it points you to the Garage.
--   3 = your bag (inventory). A badge shows eggs ready to open / waiting to be placed.
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
		C.HudController:Toast("No car yet! Buy one at the Garage on the south plaza.", "Info")
		return
	end
	local ok, message = Net.func("ToggleVehicle"):InvokeServer()
	if not ok and message then
		C.HudController:Toast(message, "Bad")
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
	local car = Tools.vehicle(data.BestVehicle or "")
	local carName = carSlot:FindFirstChild("Name") :: TextLabel
	local carIcon = carSlot:FindFirstChild("Icon") :: ImageLabel
	carName.Text = if car then car.Name else "No car"
	carName.TextColor3 = if car then INK else GREY
	carIcon.Image = AssetLibrary.image(if car then "Icon_Vehicle" else "Icon_Lock")
	setSelected(carSlot, data.InVehicle)
	-- Badge: eggs ready to open, else eggs waiting for a free incubator.
	local ready, waiting = 0, 0
	for _, entry in data.Hatching do
		if entry.EndsAt <= State.now() then
			ready += 1
		end
	end
	if #data.Hatching < data.Incubators then
		for _ in data.Eggs or {} do
			waiting += 1
		end
	end
	local badge = bagSlot:FindFirstChild("Badge") :: Frame
	local shown = if ready > 0 then ready else waiting
	badge.Visible = shown > 0
	badge.BackgroundColor3 = if ready > 0 then Color3.fromRGB(255, 200, 60) else Color3.fromRGB(255, 77, 94)
	Ui.setText(badge, tostring(math.min(shown, 99)))
	setSelected(toolSlot, not data.InVehicle and sweepTool(player.Character) ~= nil)
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
end

function HotbarController:Start()
	task.spawn(hideDefaultBackpack)
	Ui.button(toolSlot, toggleTool)
	Ui.button(carSlot, toggleCar)
	Ui.button(bagSlot, function()
		C.InventoryController:Toggle()
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
