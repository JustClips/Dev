--!strict
-- The three goals above the cash panel (server: GoalService, config: Config/Goals). Shown
-- once the tutorial is done. A goal that ticks off pops its row with a chime; all three
-- give a free wheel spin and the next round slides in.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local GoalController = {}

local C: any
local panel: Frame

local GREEN = Color3.fromRGB(61, 220, 90)
local DARK = Color3.fromRGB(20, 23, 29)

local function render()
	local goals = State.data and State.data.Goal
	panel.Visible = goals ~= nil
	if not goals then
		return
	end
	for i = 1, 3 do
		local row = panel:FindFirstChild("Row" .. i) :: Frame
		local g = goals.List[i]
		row.Visible = g ~= nil
		if g then
			local check = row:FindFirstChild("Check") :: Frame
			check.BackgroundColor3 = if g.Done then GREEN else DARK
			;(check:FindFirstChild("Mark") :: TextLabel).Text = if g.Done then "✓" else ""
			local label = row:FindFirstChild("Text") :: TextLabel
			label.Text = g.Text
			label.TextTransparency = if g.Done then 0.35 else 0
			;(row:FindFirstChild("Progress") :: TextLabel).Text = if g.Done then "DONE" else g.Progress
		end
	end
end

function GoalController:Init(controllers)
	C = controllers
	panel = Ui.find(Ui.screen("Hud"), "Wallet.Goals")
end

function GoalController:Start()
	Net.event("GoalDone").OnClientEvent:Connect(function(info)
		Ui.sound("Tutorial")
		if info.Round then
			C.HudController:Toast(`All 3 goals done! You got {info.Reward}!`, "Good")
		else
			C.HudController:Toast(`Goal done: {info.Text}!`, "Good")
		end
		Ui.popFrame(panel)
	end)
	State.Changed:Connect(render)
	render()
end

return GoalController
