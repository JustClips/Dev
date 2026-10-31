--!strict
-- Starter goals (server: GoalService). After the tutorial the step card above the hotbar
-- shows the next goal (TutorialController asks Tracker()). A finished goal flashes the
-- card green and toasts its bonus.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local GoalController = {}

local C: any

export type Tracker = { Label: string, Text: string, Fraction: number, Icon: string }

function GoalController:Tracker(): Tracker?
	local g = State.data and State.data.Goal
	if not g then
		return nil
	end
	return {
		Label = `GOAL {g.Index}/{g.Total}  ·  BONUS: {g.Reward}`,
		Text = `{g.Text}  ({Format.number(g.Progress)}/{Format.number(g.Goal)})`,
		Fraction = g.Progress / math.max(1, g.Goal),
		Icon = g.Icon,
	}
end

function GoalController:Init(controllers)
	C = controllers
end

function GoalController:Start()
	Net.event("GoalDone").OnClientEvent:Connect(function(info)
		C.HudController:Toast(`Goal done: {info.Text}  +{info.Reward}`, "Good")
		C.TutorialController:Flash()
	end)
end

return GoalController
