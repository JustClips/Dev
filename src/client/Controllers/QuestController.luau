--!strict
-- Quests (server: QuestService, config: Config/Quests). After the tutorial the step card
-- above the hotbar becomes the quest tracker (TutorialController asks Tracker()), and
-- tapping it opens the Quests window: the story quest, the 3 daily quests and the chest.
-- Quests pay out by themselves; QuestDone flashes the card and toasts the reward.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local QuestController = {}

local C: any
local gui: ScreenGui
local window: Frame

export type Tracker = { Label: string, Text: string, Fraction: number, Icon: string }

local function setBar(bar: Frame, progress: number, goal: number)
	local fill = bar:FindFirstChild("Fill") :: Frame
	local label = bar:FindFirstChild("Label") :: TextLabel
	local fraction = if goal > 0 then math.clamp(progress / goal, 0, 1) else 1
	TweenService:Create(fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.max(fraction, 0.02), 1) }):Play()
	label.Text = `{Format.number(progress)}/{Format.number(goal)}`
end

local function render()
	local quests = State.data and State.data.Quests
	if not quests or not Ui.isOpen(gui) then
		return
	end
	local story = Ui.find(window, "Story")
	local s = quests.Story
	if s then
		Ui.find(story, "Step").Text = `STORY QUEST {quests.StoryIndex}/{quests.StoryTotal}`
		Ui.find(story, "Text").Text = s.Text
		Ui.find(story, "Icon").Image = AssetLibrary.image(s.Icon)
		Ui.find(story, "Reward.Icon").Image = AssetLibrary.image(s.RewardIcon)
		Ui.find(story, "Reward.Label").Text = s.Reward
		Ui.find(story, "Bar").Visible = true
		setBar(Ui.find(story, "Bar"), s.Progress, s.Goal)
	else
		Ui.find(story, "Step").Text = "STORY QUESTS"
		Ui.find(story, "Text").Text = "All story quests done! More coming soon."
		Ui.find(story, "Bar").Visible = false
		Ui.find(story, "Reward.Label").Text = "-"
	end
	for i = 1, 3 do
		local row = Ui.find(window, "Daily" .. i)
		local d = quests.Daily[i]
		row.Visible = d ~= nil
		if d then
			Ui.find(row, "Text").Text = d.Text
			Ui.find(row, "Icon").Image = AssetLibrary.image(d.Icon)
			Ui.find(row, "RewardIcon").Image = AssetLibrary.image(d.RewardIcon)
			Ui.find(row, "Reward").Text = d.Reward
			setBar(Ui.find(row, "Bar"), d.Progress, d.Goal)
			Ui.find(row, "Done").Visible = d.Done
		end
	end
	local chest = Ui.find(window, "Chest")
	Ui.find(chest, "Text").Text = if quests.Chest then "Daily chest claimed! Come back tomorrow" else `Finish all 3: {quests.ChestReward}`
	Ui.find(chest, "Streak").Text = `Streak: {quests.Streak} day{if quests.Streak == 1 then "" else "s"}`
	Ui.find(window, "DailyHead.Resets").Text = `New quests in {Format.countdown(math.max(0, quests.ResetsAt - State.now()))}`
end

-- The one quest the card above the hotbar shows: the story quest, or the first open daily
-- quest once the story is done. nil = nothing to show.
function QuestController:Tracker(): Tracker?
	local quests = State.data and State.data.Quests
	if not quests then
		return nil
	end
	local s = quests.Story
	if s then
		return {
			Label = `QUEST {quests.StoryIndex}/{quests.StoryTotal}  ·  {s.Reward}`,
			Text = `{s.Text}  ({Format.number(s.Progress)}/{Format.number(s.Goal)})`,
			Fraction = s.Progress / math.max(1, s.Goal),
			Icon = s.Icon,
		}
	end
	for _, d in quests.Daily do
		if not d.Done then
			return {
				Label = `DAILY QUEST  ·  {d.Reward}`,
				Text = `{d.Text}  ({Format.number(d.Progress)}/{Format.number(d.Goal)})`,
				Fraction = d.Progress / math.max(1, d.Goal),
				Icon = d.Icon,
			}
		end
	end
	return nil
end

function QuestController:Open()
	if not Ui.isOpen(gui) then
		Ui.open("Quests")
	end
	render()
end

function QuestController:Init(controllers)
	C = controllers
	gui = Ui.screen("Quests")
	window = Ui.find(gui, "Window")
end

function QuestController:Start()
	local function close()
		Ui.close("Quests")
	end
	Ui.button(Ui.find(window, "Close"), close)
	Ui.button(Ui.find(gui, "Dim"), close)
	Net.event("QuestDone").OnClientEvent:Connect(function(info)
		local what = if info.Kind == "Chest" then info.Text else `Quest done: {info.Text}`
		C.HudController:Toast(`{what}  +{info.Reward}`, "Good")
		C.TutorialController:Flash()
	end)
	State.Changed:Connect(render)
	task.spawn(function()
		while true do
			task.wait(1)
			render()
		end
	end)
end

return QuestController
