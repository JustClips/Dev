--!strict
-- The three goals (server: GoalService, config: Config/Goals), shown once the tutorial is
-- done as a slim strip under the World Cleaned bar: "GOALS 1/3  Clean 150 leaves 40/150".
-- Tap it to drop down all three (it folds back up by itself). A goal that ticks off chimes
-- and pops the strip (it never opens by itself); all three give a free wheel spin.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local GoalController = {}

local C: any
local strip: GuiButton
local list: Frame

local GREEN = Color3.fromRGB(61, 220, 90)
local DARK = Color3.fromRGB(20, 23, 29)
local OPEN_SECONDS = 5

local openToken = 0

local function setOpen(open: boolean, seconds: number?)
	openToken += 1
	local token = openToken
	list.Visible = open
	;(strip:FindFirstChild("Arrow") :: TextLabel).Text = if open then "^" else "v"
	if open and seconds then
		task.delay(seconds, function()
			if token == openToken then
				setOpen(false)
			end
		end)
	end
end

local function render()
	local goals = State.data and State.data.Goal
	local show = goals ~= nil
	if strip.Visible ~= show then
		strip.Visible = show
		C.HudController:Relayout()
	end
	if not goals then
		return
	end
	local done = 0
	local nextGoal = nil
	for i = 1, 3 do
		local row = list:FindFirstChild("Row" .. i) :: Frame
		local g = goals.List[i]
		row.Visible = g ~= nil
		if g then
			if g.Done then
				done += 1
			elseif not nextGoal then
				nextGoal = g
			end
			local check = row:FindFirstChild("Check") :: Frame
			check.BackgroundColor3 = if g.Done then GREEN else DARK
			;(check:FindFirstChild("Mark") :: TextLabel).Text = if g.Done then "✓" else ""
			local label = row:FindFirstChild("Text") :: TextLabel
			label.Text = g.Text
			label.TextTransparency = if g.Done then 0.35 else 0
			;(row:FindFirstChild("Progress") :: TextLabel).Text = if g.Done then "DONE" else g.Progress
		end
	end
	;(strip:FindFirstChild("Count") :: TextLabel).Text = `GOALS {done}/{#goals.List}`
	;(strip:FindFirstChild("Next") :: TextLabel).Text = if nextGoal then `{nextGoal.Text}  {nextGoal.Progress}` else "All done!"
end

function GoalController:Init(controllers)
	C = controllers
	strip = Ui.find(Ui.screen("Hud"), "Goals")
	list = Ui.find(strip, "List")
	Ui.fitText(strip:FindFirstChild("Next") :: TextLabel, 16, 8)
end

function GoalController:Start()
	Ui.button(strip, function()
		setOpen(not list.Visible, OPEN_SECONDS)
	end)
	Net.event("GoalDone").OnClientEvent:Connect(function(info)
		Ui.sound("Tutorial")
		if info.Round then
			C.HudController:Toast(`All 3 goals done! You got {info.Reward}!`, "Good")
		else
			C.HudController:Toast(`Goal done: {info.Text}!`, "Good")
		end
		Ui.popFrame(strip)
	end)
	State.Changed:Connect(render)
	render()
end

return GoalController
