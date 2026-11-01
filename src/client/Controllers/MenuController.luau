--!strict
-- The HUD's core buttons (Dev, 2026-11-01: "3-4 core buttons, the rest indicators, core
-- buttons open a small menu"). Four tiles down the left edge (Hud.Rail):
--   Shop     opens the Shop (HudController).
--   Upgrade  opens a small menu: Gear, Upgrades (tree), Rebirth.
--   Base     takes you home onto your base's own leaf dump, which sells your bag.
--   More     opens a small menu: Quests, Daily, Gifts, Teleport (zones), Index, Free.
-- A menu opens beside its button; tapping outside, the button again, or anything that
-- opens a window closes it. A core button shows a red badge while something inside its
-- menu has one.
-- Also here: the Gear badge (next tool affordable).
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Tools = require(Shared.Config.Tools)

local MenuController = {}

local C: any
local hud: ScreenGui
local rail: Frame
local away: GuiButton
local menus: { [string]: Frame } = {}
local cores: { [string]: GuiButton } = {}
local openName: string? = nil

-- Menu name -> the core button that opens it.
local CORE = { UpgradeMenu = "UpgradesButton", MoreMenu = "MoreButton" }

local function place(name: string)
	local menu = menus[name]
	local button = cores[name]
	local origin = hud.AbsolutePosition
	-- Far enough right that the core button's badge (sticking out of its corner) stays
	-- visible next to the menu (Dev, 2026-11-01: the menu covered it).
	local x = button.AbsolutePosition.X + button.AbsoluteSize.X + math.ceil(22 * Ui.scale()) - origin.X
	local y = button.AbsolutePosition.Y + button.AbsoluteSize.Y / 2 - origin.Y
	-- Keep the whole strip (and its title above it) on screen.
	local half = menu.AbsoluteSize.Y / 2
	local maxY = hud.AbsoluteSize.Y - half - 6
	y = math.clamp(y, half + 28, math.max(half + 28, maxY))
	menu.AnchorPoint = Vector2.new(0, 0.5)
	menu.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

function MenuController:Close()
	for _, menu in menus do
		menu.Visible = false
	end
	if openName then
		openName = nil
	end
	local picker = hud:FindFirstChild("ZonePicker") :: GuiObject?
	away.Visible = picker ~= nil and picker.Visible
end

function MenuController:Open(name: string)
	MenuController:Close()
	-- Opening a menu closes the open window first; otherwise the "a window is open" check
	-- below shut the menu right away (Dev, 2026-11-01: Upgrade over the inventory flashed).
	Ui.closeWindows()
	local menu = menus[name]
	if not menu then
		return
	end
	openName = name
	menu.Visible = true
	place(name)
	task.defer(place, name) -- AutomaticSize settles a frame later
	Ui.popFrame(menu)
	-- Controller: the selection moves onto the first tile.
	if Ui.gamepad() then
		for _, tile in (menu:FindFirstChild("Items") :: Instance):GetChildren() do
			if tile:IsA("GuiButton") and tile.Visible and tile.LayoutOrder == 1 then
				GuiService.SelectedObject = tile
			end
		end
	end
end

function MenuController:Toggle(name: string)
	if openName == name then
		MenuController:Close()
	else
		MenuController:Open(name)
	end
end

function MenuController:IsOpen(name: string): boolean
	return openName == name
end

-- A tile inside a menu ("UpgradeMenu", "ToolsButton").
function MenuController:Item(menu: string, item: string): GuiObject
	return Ui.find(menus[menu], "Items." .. item)
end

-- What to point at for a menu item: the item while its menu is open, else the core
-- button that opens the menu (tutorial and quest pointers).
function MenuController:PointerFor(menu: string, item: string): GuiObject
	if openName == menu then
		return MenuController:Item(menu, item)
	end
	return cores[menu]
end

-- Called by the ZonePicker (HudController): the click-away also closes the picker.
function MenuController:SetAway(on: boolean)
	away.Visible = on
end

local function inside(gui: GuiObject, at: Vector2): boolean
	local p, size = gui.AbsolutePosition, gui.AbsoluteSize
	return at.X >= p.X and at.X <= p.X + size.X and at.Y >= p.Y and at.Y <= p.Y + size.Y
end

local function anyBadge(menu: Frame): number
	local count = 0
	for _, tile in (menu:FindFirstChild("Items") :: Instance):GetChildren() do
		local b = tile:FindFirstChild("Badge") :: GuiObject?
		if tile:IsA("GuiObject") and tile.Visible and b and b.Visible then
			count += 1
		end
	end
	return count
end

local function render()
	local data = State.data
	if not data then
		return
	end
	-- Gear: a badge when the next tool is affordable.
	local nextTool = Tools.get(data.ToolTier + 1)
	Ui.setBadge(
		Ui.find(menus.UpgradeMenu, "Items.ToolsButton.Badge"),
		if data.ToolTier < Tools.MaxTier and (nextTool.Tier == Tools.FreeTier or BigNum.gte(data.Cash, nextTool.Price)) then 1 else nil
	)
	-- Core buttons carry their menu's badges.
	for name, menu in menus do
		local n = anyBadge(menu)
		Ui.setBadge(cores[name]:FindFirstChild("Badge") :: GuiObject?, if n > 0 then n else nil, true)
	end
end

function MenuController:Init(controllers)
	C = controllers
	hud = Ui.screen("Hud")
	rail = Ui.find(hud, "Rail")
	away = Ui.find(hud, "MenuAway")
	for name, coreName in CORE do
		menus[name] = Ui.find(hud, name)
		cores[name] = Ui.find(rail, coreName)
	end
	-- The Eggs / Pets / Gear / Quests column and its two popups are gone (2026-11-01).
	-- LiveSync never deletes screens from Dev's Studio place, so drop the old ones.
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, old in { "BasePanels", "PetsPanel", "EggsPanel" } do
		local stale = playerGui:FindFirstChild(old)
		if stale then
			stale:Destroy()
		end
	end
end

function MenuController:Start()
	Ui.button(cores.UpgradeMenu, function()
		MenuController:Toggle("UpgradeMenu")
	end)
	Ui.button(cores.MoreMenu, function()
		MenuController:Toggle("MoreMenu")
	end)
	Ui.button(Ui.find(rail, "BaseButton"), function()
		MenuController:Close()
		C.HudController:GoHome()
	end)
	Ui.button(Ui.find(rail, "ShopButton"), function()
		MenuController:Close()
		C.ShopController:Toggle()
	end)
	away.Activated:Connect(function()
		MenuController:Close()
		C.HudController:CloseZones()
	end)
	-- Menu tiles that open a window. Daily, Gifts and Free are wired by their own
	-- controllers (RewardsController, GroupRewardController); every tile closes the menu.
	local actions: { [string]: () -> () } = {
		ToolsButton = function()
			C.GarageController:Toggle()
		end,
		TreeButton = function()
			C.UpgradeController:Toggle()
		end,
		RebirthButton = function()
			C.RebirthController:Toggle()
		end,
		QuestsButton = function()
			C.QuestController:Open(nil)
		end,
		IndexButton = function()
			C.IndexController:Toggle()
		end,
		ZonesButton = function()
			C.HudController:OpenZones()
		end,
	}
	for _, menu in menus do
		for _, tile in (menu:FindFirstChild("Items") :: Instance):GetChildren() do
			if tile:IsA("GuiButton") then
				local action = actions[tile.Name]
				if action then
					Ui.button(tile, function()
						MenuController:Close()
						action()
					end)
				else
					tile.Activated:Connect(function()
						MenuController:Close()
					end)
				end
			end
		end
	end
	-- A tap outside the open menu closes it, and that same tap still reaches whatever it
	-- hit (Dev, 2026-11-01: a full-screen click catcher ate the first click). Taps on the
	-- menu or its own core button are left to them.
	UserInputService.InputBegan:Connect(function(input)
		local name = openName
		if not name then
			return
		end
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		local at = Vector2.new(input.Position.X, input.Position.Y)
		local menu, core = menus[name], cores[name]
		if inside(menu, at) or inside(core, at) then
			return
		end
		task.defer(function()
			if openName == name then
				MenuController:Close()
			end
		end)
	end)
	Ui.onScale(function()
		if openName then
			place(openName)
		end
	end)
	State.Changed:Connect(render)
	task.spawn(function()
		while true do
			task.wait(0.5)
			-- A window opening (from anywhere) closes the menu.
			if openName and Ui.anyWindowOpen() then
				MenuController:Close()
			end
			render()
		end
	end)
end

return MenuController
