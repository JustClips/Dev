--!strict
-- "Are you sure?" popup (Confirm screen), shown over whatever is open without closing it.
--   ConfirmController:Ask({ title = "Use item?", name = "Luck Potion", text = "2x egg luck",
--     icon = "Icon_PotionLuck", yes = "Use" }, function() ... end)
-- Yes runs the callback; No, the X and tapping outside just close it.
local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)

local ConfirmController = {}

export type Question = { title: string, name: string, text: string?, icon: string?, yes: string?, no: string? }

local gui: ScreenGui
local pending: (() -> ())? = nil

local function close()
	pending = nil
	if Ui.isOpen(gui) then
		Ui.hide(gui)
	end
end

function ConfirmController:Ask(q: Question, onYes: () -> ())
	pending = onYes
	Ui.setText(Ui.find(gui, "Window.Header.Title"), q.title)
	Ui.find(gui, "Window.Name").Text = q.name
	Ui.find(gui, "Window.Text").Text = q.text or ""
	if q.icon then
		Ui.find(gui, "Window.Big").Image = AssetLibrary.image(q.icon)
	end
	Ui.setText(Ui.find(gui, "Window.Yes"), q.yes or "Yes")
	Ui.setText(Ui.find(gui, "Window.No"), q.no or "Cancel")
	if not Ui.isOpen(gui) then
		Ui.show(gui)
	end
end

function ConfirmController:Init()
	gui = Ui.screen("Confirm")
end

function ConfirmController:Start()
	Ui.button(Ui.find(gui, "Window.Yes"), function()
		local fn = pending
		close()
		if fn then
			fn()
		end
	end)
	Ui.button(Ui.find(gui, "Window.No"), close)
	Ui.button(Ui.find(gui, "Window.Close"), close)
	Ui.find(gui, "Dim").Activated:Connect(close)
end

return ConfirmController
