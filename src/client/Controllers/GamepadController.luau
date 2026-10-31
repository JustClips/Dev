--!strict
-- Console / controller support. Roblox already moves you (left stick), turns the camera
-- (right stick), jumps (A), presses proximity prompts (X) and presses the selected button
-- (A). This adds the rest:
--   Windows: opening one puts the selection on its main button and keeps it inside the
--     window; B closes it (its Close button). Full-screen click catchers (Dim, ClickAway,
--     Backdrop) are never selected.
--   D-pad left: the left menu (Shop, Index, Upgrades...). D-pad right: the base menu
--     (Eggs, Pets, Gear). B leaves either.
--   D-pad up: car. D-pad down: drop the egg you carry. Y: bag.
--   LB / RB: previous / next hotbar slot (tool, then pets and eggs).
--   R2: sweep (SweepController), place an egg or let a pet out (PlacementController).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local GamepadController = {}

local C: any
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

-- Never selected: they cover the whole screen behind a window.
local CATCHERS = { Dim = true, ClickAway = true, Backdrop = true }
-- Screens that are part of the HUD, not popups (no auto selection when they show).
local NOT_POPUPS = {
	Hud = true,
	Topbar = true,
	BasePanels = true,
	Hover = true,
	Gained = true,
	Hatch = true,
	Loading = true,
	Placing = true,
	Leave = true,
	Upgrades = true, -- UpgradeController selects the first hex itself
}
-- The button a window starts on, best first (else the top-left one).
local PREFER = {
	"ClaimDaily",
	"Collect",
	"Stay",
	"Yes",
	"Ok",
	"SpinButton",
	"Redeem",
	"RebirthButton",
	"EquipBest",
	"OpenAll",
	"Claim",
	"JoinButton",
	"Action",
	"Main",
	"Hit",
	"Select",
}

-- Popups that show up on their own start on Close, so a jump (A) never buys anything.
local START_ON_CLOSE = { Offer = true }
-- Popups that are a frame inside an always-on screen.
local FRAME_POPUPS = { Stay = "Popup", Hud = "ZonePicker" }

local openStack: { GuiObject | ScreenGui } = {} -- open popups, newest last
local lastSelected: GuiObject? = nil
local lastSelectedAt = 0

local function shown(object: Instance): boolean
	local current: Instance? = object
	while current and current ~= playerGui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("ScreenGui") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return current == playerGui
end

local function screenOf(object: Instance): ScreenGui?
	local current: Instance? = object
	while current and not current:IsA("ScreenGui") do
		current = current.Parent
	end
	return current :: ScreenGui?
end

local function candidates(root: Instance): { GuiButton }
	local list = {}
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and d.Selectable and d.Active ~= false and not CATCHERS[d.Name] and d.Name ~= "Close" and shown(d) then
			table.insert(list, d)
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = a.AbsolutePosition, b.AbsolutePosition
		if math.abs(pa.Y - pb.Y) > 8 then
			return pa.Y < pb.Y
		end
		return pa.X < pb.X
	end)
	return list
end

-- The visible Close button of a popup (the innermost one, e.g. the gift picker in the shop).
local function closeButton(root: Instance): GuiButton?
	local best: GuiButton? = nil
	local bestDepth = -1
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and d.Name == "Close" and Ui.handler(d) and shown(d) then
			local depth = 0
			local p = d.Parent
			while p and p ~= root do
				depth += 1
				p = p.Parent
			end
			if depth > bestDepth then
				best, bestDepth = d, depth
			end
		end
	end
	return best
end

local function pick(root: Instance): GuiButton?
	if START_ON_CLOSE[root.Name] then
		local close = closeButton(root)
		if close then
			return close
		end
	end
	local list = candidates(root)
	for _, name in PREFER do
		for _, b in list do
			if b.Name == name then
				return b
			end
		end
	end
	return list[1] or closeButton(root)
end

-- The part of a popup that holds its buttons (kept as a selection group).
local function container(root: GuiObject | ScreenGui): GuiObject?
	if root:IsA("GuiObject") then
		return root:FindFirstChild("Window") :: GuiObject? or root
	end
	return (root:FindFirstChild("Window") or root:FindFirstChild("Bar")) :: GuiObject?
end

local function focus(root: GuiObject | ScreenGui)
	if not Ui.gamepad() then
		return
	end
	-- Let the window lay out (lists fill in, buttons show) first.
	task.delay(0.1, function()
		if not shown(root) or not Ui.gamepad() then
			return
		end
		local current = GuiService.SelectedObject
		if current and current:IsDescendantOf(root) and shown(current) then
			return
		end
		local box = container(root)
		if box then
			box.SelectionGroup = true
			box.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
			box.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
			box.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
			box.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
		end
		local target = pick(root)
		if target then
			GuiService.SelectedObject = target
		end
	end)
end

local function topPopup(): (GuiObject | ScreenGui)?
	for i = #openStack, 1, -1 do
		local root = openStack[i]
		if shown(root) then
			return root
		end
		table.remove(openStack, i)
	end
	return nil
end

local function opened(root: GuiObject | ScreenGui)
	local at = table.find(openStack, root)
	if at then
		table.remove(openStack, at)
	end
	table.insert(openStack, root)
	focus(root)
end

local function closed(root: GuiObject | ScreenGui)
	local at = table.find(openStack, root)
	if at then
		table.remove(openStack, at)
	end
	task.delay(0.05, function()
		local current = GuiService.SelectedObject
		if current and shown(current) then
			return
		end
		local top = topPopup()
		if top then
			focus(top)
		elseif current then
			GuiService.SelectedObject = nil
		end
	end)
end

local function watchScreen(gui: Instance)
	if not gui:IsA("ScreenGui") then
		return
	end
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiButton") and CATCHERS[d.Name] then
			d.Selectable = false
		end
	end
	gui.DescendantAdded:Connect(function(d)
		if d:IsA("GuiButton") and CATCHERS[d.Name] then
			d.Selectable = false
		end
	end)
	local frameName = FRAME_POPUPS[gui.Name]
	local popup = if frameName then gui:WaitForChild(frameName, 10) :: GuiObject? else nil
	if popup then
		popup:GetPropertyChangedSignal("Visible"):Connect(function()
			if popup.Visible then
				opened(popup)
			else
				closed(popup)
			end
		end)
		return
	end
	if NOT_POPUPS[gui.Name] then
		return
	end
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			opened(gui)
		else
			closed(gui)
		end
	end)
	if gui.Enabled then
		opened(gui)
	end
end

-- Selects the first shown button of a HUD menu (or leaves it if it's already there).
local function toggleMenu(buttons: { GuiButton })
	local current = GuiService.SelectedObject
	for _, b in buttons do
		if current == b then
			GuiService.SelectedObject = nil
			return
		end
	end
	for _, b in buttons do
		if shown(b) then
			GuiService.SelectedObject = b
			return
		end
	end
end

local function leftMenu(): { GuiButton }
	local hud = playerGui:FindFirstChild("Hud")
	local rail = hud and hud:FindFirstChild("Rail")
	local list = if rail then candidates(rail) else {}
	local spin = hud and hud:FindFirstChild("SpinButton")
	if spin and spin:IsA("GuiButton") then
		table.insert(list, spin)
	end
	return list
end

local function rightMenu(): { GuiButton }
	local panels = playerGui:FindFirstChild("BasePanels")
	local buttons = panels and panels:FindFirstChild("Buttons")
	return if buttons then candidates(buttons) else {}
end

-- B: close the window the selection is in (or the newest one), or leave a HUD menu.
local function back()
	local current = GuiService.SelectedObject
	if not current and lastSelected and os.clock() - lastSelectedAt < 0.2 then
		current = lastSelected -- Roblox may have dropped the selection on this same press
	end
	local root: (GuiObject | ScreenGui)? = nil
	if current then
		for i = #openStack, 1, -1 do
			if current:IsDescendantOf(openStack[i]) then
				root = openStack[i]
				break
			end
		end
	end
	local inHud = false
	if current then
		local screen = screenOf(current)
		inHud = screen ~= nil and NOT_POPUPS[screen.Name] == true
	end
	if not root and not inHud then
		root = topPopup()
	end
	-- The upgrade board has no popup entry: close it like the others.
	local upgrades = playerGui:FindFirstChild("Upgrades") :: ScreenGui?
	if not root and upgrades and upgrades.Enabled then
		root = upgrades
	end
	if root then
		local close = closeButton(root)
		local fn = close and Ui.handler(close)
		if fn then
			Ui.sound("Click")
			fn()
			return
		end
		if root:IsA("GuiObject") and root.Name == "ZonePicker" then
			root.Visible = false
			return
		end
	end
	if GuiService.SelectedObject then
		GuiService.SelectedObject = nil
	end
end

function GamepadController:Init(controllers)
	C = controllers
end

function GamepadController:Start()
	for _, gui in playerGui:GetChildren() do
		task.spawn(watchScreen, gui)
	end
	playerGui.ChildAdded:Connect(watchScreen)

	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local current = GuiService.SelectedObject
		if current then
			lastSelected = current
		end
		lastSelectedAt = os.clock()
	end)

	-- Picking up the controller with a window open selects its button; putting it down
	-- (mouse, keys, touch) clears the selection box.
	UserInputService.LastInputTypeChanged:Connect(function()
		task.defer(function()
			if Ui.gamepad() then
				local top = topPopup()
				if top and not GuiService.SelectedObject then
					focus(top)
				end
			elseif GuiService.SelectedObject then
				GuiService.SelectedObject = nil
			end
		end)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonB then
			back()
			return
		end
		local inventory = playerGui:FindFirstChild("Inventory") :: ScreenGui?
		if key == Enum.KeyCode.ButtonY and inventory and Ui.isOpen(inventory) then
			C.InventoryController:Toggle()
			return
		end
		-- The rest only while playing (no window, nothing selected).
		if processed or GuiService.SelectedObject or Ui.anyWindowOpen() or topPopup() then
			return
		end
		if key == Enum.KeyCode.DPadLeft then
			toggleMenu(leftMenu())
		elseif key == Enum.KeyCode.DPadRight then
			toggleMenu(rightMenu())
		elseif key == Enum.KeyCode.DPadUp then
			C.HotbarController:ToggleCar()
		elseif key == Enum.KeyCode.DPadDown then
			C.HotbarController:DropEgg()
		elseif key == Enum.KeyCode.ButtonY then
			C.InventoryController:Toggle()
		elseif key == Enum.KeyCode.ButtonR1 then
			C.HotbarController:Cycle(1)
		elseif key == Enum.KeyCode.ButtonL1 then
			C.HotbarController:Cycle(-1)
		end
	end)
end

return GamepadController
