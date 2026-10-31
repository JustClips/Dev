--!strict
-- Quests (server: QuestService, config: Config/Quests). Replaced the 3-goal strip on
-- 2026-10-31.
--   Strip    under the World Cleaned bar: "JOB 3  Hatch 3 eggs  1/3" with a thin bar and a
--            red "!" when something can be claimed. Tap = the Quests window.
--   Window   screen "Quests" (tools/gen_ui.py quests()): Jobs tab (current job, reward, Go
--            to Quest Master) and Daily tab (3 quests with Claim, the all-3 bonus, timer).
--   NPC      the Quest Master on the left of every base (prompt Opens = "Quests"): his
--            dialog hands over finished jobs. A bouncing "!" floats over your own one
--            while something is ready.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Format = require(Shared.Format)
local Items = require(Shared.Config.Items)
local Net = require(Shared.Net)
local Quests = require(Shared.Config.Quests)

local QuestController = {}

local GREEN = Color3.fromRGB(61, 220, 90)
local GREY = Color3.fromRGB(166, 174, 194)
local BLUE = Color3.fromRGB(76, 141, 255)
local DARK_BLUE = Color3.fromRGB(40, 90, 190)
local ORANGE = Color3.fromRGB(230, 120, 40)
local GOLD = Color3.fromRGB(255, 200, 60)

local C: any
local strip: GuiButton
local gui: ScreenGui
local tab = "Jobs"
local busy = false
local marker: BillboardGui? = nil

local function invoke(action: string, arg: any?): (boolean, string?)
	local ok, a, b = pcall(function()
		return Net.func("Quests"):InvokeServer(action, arg)
	end)
	if not ok then
		return false, "Something went wrong, try again"
	end
	return a, b
end

local function paint(button: GuiButton, label: string, color: Color3)
	Ui.setText(button, label)
	button.BackgroundColor3 = color
	local studs = button:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = color
	end
end

local function rewardIcon(kind: string?, item: string?): string
	if kind == "Item" then
		local def = Items.ById[item or ""]
		return AssetLibrary.image(if def then def.Icon else "Icon_Potion")
	elseif kind == "Egg" then
		return AssetLibrary.image("Icon_Egg")
	elseif kind == "Spin" then
		return AssetLibrary.image("Icon_Spin")
	end
	return AssetLibrary.image("Icon_Cash")
end

local function setReward(box: Instance, q)
	local iconImage = box:FindFirstChild("Icon") :: ImageLabel
	iconImage.Image = rewardIcon(q.RewardKind, q.RewardItem)
	local label = box:FindFirstChild("Label") :: TextLabel
	label.Text = q.Reward or ""
end

local function setBar(bar: Instance, fraction: number, label: string)
	local fill = bar:FindFirstChild("Fill") :: Frame
	fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	;(bar:FindFirstChild("Label") :: TextLabel).Text = label
end

-------------------------------------------------------------------------- strip

local function renderStrip(quests)
	-- The Quests button under Gear (BasePanels) shows the same "!" as the strip.
	local ready = if quests and (quests.Ready or 0) > 0 then quests.Ready else nil
	Ui.setBadge(Ui.find(Ui.screen("BasePanels"), "Buttons.QuestsButton.Badge") :: GuiObject, ready)
	local show = quests ~= nil and quests.Job ~= nil
	if strip.Visible ~= show then
		strip.Visible = show
		C.HudController:Relayout()
	end
	if not show then
		return
	end
	local job = quests.Job
	;(strip:FindFirstChild("Count") :: TextLabel).Text = `JOB {job.Number}`
	local nextLabel = strip:FindFirstChild("Next") :: TextLabel
	local progress = strip:FindFirstChild("Progress") :: TextLabel
	if job.Done then
		nextLabel.Text = "Done! Claim at Quest Master"
		nextLabel.TextColor3 = GOLD
		progress.Text = ""
	else
		nextLabel.Text = job.Text
		nextLabel.TextColor3 = Color3.new(1, 1, 1)
		progress.Text = job.Progress
	end
	local fill = Ui.find(strip, "Bar.Fill") :: Frame
	fill.Size = UDim2.fromScale(math.clamp(job.Fraction or 0, 0, 1), 1)
	Ui.setBadge(strip:FindFirstChild("Badge") :: GuiObject, if quests.Ready > 0 then quests.Ready else nil)
end

-------------------------------------------------------------------------- window

local function renderJob(job)
	local page = Ui.find(gui, "Window.Job") :: Frame
	local card = page:FindFirstChild("Card") :: Frame
	;(card:FindFirstChild("Number") :: TextLabel).Text = `JOB {job.Number}`
	;(card:FindFirstChild("Text") :: TextLabel).Text = job.Text
	setBar(card:FindFirstChild("Bar") :: Frame, job.Fraction, if job.Done then "DONE!" else job.Progress)
	setReward(card:FindFirstChild("Reward") :: Frame, job)
	local hint = page:FindFirstChild("Hint") :: TextLabel
	local go = page:FindFirstChild("Go") :: GuiButton
	if job.Done then
		hint.Text = "Job done! Talk to the Quest Master on your base to get your reward."
		paint(go, "Go claim it!", GREEN)
	else
		hint.Text = "Finish the job, then talk to the Quest Master on your base."
		paint(go, "Go to Quest Master", BLUE)
	end
end

local function renderDaily(daily)
	local page = Ui.find(gui, "Window.Daily") :: Frame
	for i = 1, 3 do
		local row = Ui.find(page, `List.Row{i}`) :: Frame
		local q = daily.List[i]
		row.Visible = q ~= nil
		if q then
			local textLabel = row:FindFirstChild("Text") :: TextLabel
			textLabel.Text = q.Text
			setBar(row:FindFirstChild("Bar") :: Frame, q.Fraction, if q.Done then "DONE!" else q.Progress)
			setReward(row:FindFirstChild("Reward") :: Frame, q)
			local claim = row:FindFirstChild("Claim") :: GuiButton
			if q.Claimed then
				paint(claim, "Claimed", GREY)
			elseif q.Done then
				paint(claim, "Claim", GREEN)
			else
				paint(claim, "Claim", GREY)
			end
		end
	end
	local bonus = page:FindFirstChild("Bonus") :: Frame
	local claim = bonus:FindFirstChild("Claim") :: GuiButton
	local text = bonus:FindFirstChild("Text") :: TextLabel
	if daily.BonusClaimed then
		text.Text = "Bonus claimed! New quests tomorrow."
		paint(claim, "Claimed", GREY)
	else
		text.Text = `Claim all 3 for {daily.Bonus}!`
		paint(claim, "Claim", if daily.BonusReady then GOLD else GREY)
	end
	local left = math.max(0, (daily.ResetsAt or 0) - State.now())
	;(page:FindFirstChild("Timer") :: TextLabel).Text = `New quests in {Format.countdown(left)}`
end

local function render()
	local quests = State.data and State.data.Quests
	renderStrip(quests)
	if marker then
		marker.Enabled = quests ~= nil and quests.Ready > 0
	end
	if not Ui.isOpen(gui) then
		return
	end
	if not quests then
		Ui.close("Quests")
		return
	end
	local jobsTab = Ui.find(gui, "Window.JobsTab") :: GuiButton
	local dailyTab = Ui.find(gui, "Window.DailyTab") :: GuiButton
	paint(jobsTab, "Jobs", if tab == "Jobs" then BLUE else DARK_BLUE)
	paint(dailyTab, "Daily", if tab == "Daily" then BLUE else DARK_BLUE)
	local dailyReady = 0
	if quests.Daily then
		for _, q in quests.Daily.List do
			if q.Done and not q.Claimed then
				dailyReady += 1
			end
		end
		if quests.Daily.BonusReady then
			dailyReady += 1
		end
	end
	Ui.setBadge(jobsTab:FindFirstChild("Badge") :: GuiObject, if quests.Job and quests.Job.Done then 1 else nil)
	Ui.setBadge(dailyTab:FindFirstChild("Badge") :: GuiObject, if dailyReady > 0 then dailyReady else nil)
	local jobPage = Ui.find(gui, "Window.Job") :: Frame
	local dailyPage = Ui.find(gui, "Window.Daily") :: Frame
	jobPage.Visible = tab == "Jobs" and quests.Job ~= nil
	dailyPage.Visible = tab == "Daily" and quests.Daily ~= nil
	if quests.Job then
		renderJob(quests.Job)
	end
	if quests.Daily then
		renderDaily(quests.Daily)
	end
end

function QuestController:Open(which: string?)
	if not (State.data and State.data.Quests) then
		C.HudController:Toast("Finish the tutorial to unlock quests!", "Info")
		return
	end
	if which then
		tab = which
	end
	if not Ui.isOpen(gui) then
		Ui.open("Quests")
	end
	render()
end

local function claimDaily(i: number)
	local quests = State.data and State.data.Quests
	local q = quests and quests.Daily and quests.Daily.List[i]
	if busy or not q or q.Claimed then
		return
	end
	if not q.Done then
		C.HudController:Toast(`Not done yet: {q.Text} ({q.Progress})`, "Info")
		return
	end
	busy = true
	local ok, got = invoke("ClaimDaily", i)
	busy = false
	if ok then
		Ui.sound("Reveal")
		C.HudController:Toast(`Quest reward: {got}!`, "Good")
	else
		C.HudController:Toast(got or "Couldn't claim that", "Bad")
	end
end

local function claimBonus()
	local quests = State.data and State.data.Quests
	local daily = quests and quests.Daily
	if busy or not daily or daily.BonusClaimed then
		return
	end
	if not daily.BonusReady then
		C.HudController:Toast("Claim all 3 daily quests first!", "Info")
		return
	end
	busy = true
	local ok, got = invoke("ClaimBonus")
	busy = false
	if ok then
		Ui.sound("Reveal")
		C.HudController:Toast(`Daily bonus: {got}!`, "Good")
	else
		C.HudController:Toast(got or "Couldn't claim that", "Bad")
	end
end

local function goToMaster()
	Ui.close("Quests")
	-- Already on your base: the 3D arrow path shows the way when a job is done.
	task.spawn(function()
		local data = State.data
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local master = data and Workspace:FindFirstChild("QuestMasters") and (Workspace :: any).QuestMasters:FindFirstChild("QuestMaster" .. tostring(data.BaseIndex))
		local head = master and master:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and head and (root.Position - head.Position).Magnitude < 60 then
			return
		end
		local ok, message = pcall(function()
			return Net.func("Teleport"):InvokeServer("Base")
		end)
		if ok and message and type(message) == "string" and message ~= "" then
			C.HudController:Toast(message, "Info")
		end
	end)
end

-------------------------------------------------------------------------- NPC dialog

local talk: () -> ()

local function bye()
	C.DialogController:Say("Good luck out there! Come back when you're done.", {})
	task.delay(1.2, function()
		C.DialogController:Close()
	end)
end

local function claimJob()
	if busy then
		return
	end
	busy = true
	local ok, got = invoke("ClaimJob")
	busy = false
	if not ok then
		C.DialogController:Say(got or "Hmm, that didn't work.", {
			{ text = "Okay", color = GREY, pick = talk },
		})
		return
	end
	Ui.sound("Reveal")
	C.HudController:Toast(`Job reward: {got}!`, "Good")
	-- The next job arrives with the next snapshot.
	task.wait(0.35)
	local job = State.data and State.data.Quests and State.data.Quests.Job
	local nextLine = if job and not job.Done then ` Your next job: {job.Text}.` else ""
	C.DialogController:Say(`Great work! Here's your reward: {got}!{nextLine}`, {
		{ text = "On it!", color = GREEN, pick = bye },
		{
			text = "Show my quests",
			color = BLUE,
			pick = function()
				C.DialogController:Close()
				QuestController:Open("Jobs")
			end,
		},
	})
end

talk = function()
	local quests = State.data and State.data.Quests
	if not quests or not quests.Job then
		C.DialogController:Say("Hi there! Finish the tutorial first, then come see me for jobs and rewards.", {
			{ text = "Okay!", color = GREEN, pick = bye },
		})
		return
	end
	local job = quests.Job
	local dailyOption = {
		text = "Daily quests",
		color = ORANGE,
		pick = function()
			C.DialogController:Close()
			QuestController:Open("Daily")
		end,
	}
	if job.Done then
		C.DialogController:Say(`You did it: {job.Text}! I've got {job.Reward} for you.`, {
			{ text = `Claim {job.Reward}!`, color = GREEN, pick = claimJob },
			dailyOption,
		})
		return
	end
	C.DialogController:Say(`Your job: {job.Text}. You're at {job.Progress}. Come back when it's done and I'll pay you {job.Reward}!`, {
		{ text = "On it!", color = GREEN, pick = bye },
		dailyOption,
		{
			text = "Show my quests",
			color = BLUE,
			pick = function()
				C.DialogController:Close()
				QuestController:Open("Jobs")
			end,
		},
	})
end

-------------------------------------------------------------------------- "!" over your Quest Master

local function buildMarker()
	local data = State.data
	if not data or not data.BaseIndex or data.BaseIndex == 0 then
		return
	end
	local folder = Workspace:FindFirstChild("QuestMasters")
	local master = folder and folder:FindFirstChild("QuestMaster" .. data.BaseIndex)
	local head = master and master:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	if marker and marker.Adornee == head then
		return
	end
	if marker then
		marker:Destroy()
	end
	local board = Instance.new("BillboardGui")
	board.Name = "QuestMarker"
	board.Adornee = head
	board.Size = UDim2.fromScale(2.4, 2.4)
	board.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.MaxDistance = 220
	board.Enabled = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
	label.Parent = board
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(23, 25, 30)
	stroke.Parent = label
	board.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	marker = board
end

-------------------------------------------------------------------------- lifecycle

function QuestController:Init(controllers)
	C = controllers
	strip = Ui.find(Ui.screen("Hud"), "Quests")
	gui = Ui.screen("Quests")
	Ui.fitText(strip:FindFirstChild("Next") :: TextLabel, 16, 9)
	Ui.fitText(strip:FindFirstChild("Progress") :: TextLabel, 15, 9)
end

function QuestController:Start()
	Ui.button(strip, function()
		QuestController:Open(nil)
	end)
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Quests")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Quests")
	end)
	Ui.button(Ui.find(gui, "Window.JobsTab"), function()
		tab = "Jobs"
		render()
	end)
	Ui.button(Ui.find(gui, "Window.DailyTab"), function()
		tab = "Daily"
		render()
	end)
	Ui.button(Ui.find(gui, "Window.Job.Go"), goToMaster)
	for i = 1, 3 do
		Ui.button(Ui.find(gui, `Window.Daily.List.Row{i}.Claim`), function()
			claimDaily(i)
		end)
	end
	Ui.button(Ui.find(gui, "Window.Daily.Bonus.Claim"), claimBonus)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") ~= "Quests" then
			return
		end
		local at = prompt.Parent
		C.DialogController:Open(Quests.NpcName, if at and at:IsA("BasePart") then at else nil)
		talk()
	end)
	Net.event("QuestReady").OnClientEvent:Connect(function(info)
		Ui.sound("Tutorial")
		if info.Job then
			C.HudController:Toast(`Job done: {info.Text}! Go see the Quest Master.`, "Good")
		else
			C.HudController:Toast(`Daily quest done: {info.Text}! Claim it in Quests.`, "Good")
		end
		Ui.popFrame(strip)
	end)
	State.Changed:Connect(render)
	render()
	-- Keeps the "!" on your own Quest Master (he loads in after you, and bases can change),
	-- bobs it, and ticks the daily timer while the window is open.
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		if marker and marker.Enabled then
			marker.StudsOffsetWorldSpace = Vector3.new(0, 4.6 + math.abs(math.sin(t * 3)) * 0.8, 0)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			buildMarker()
			if marker then
				local quests = State.data and State.data.Quests
				marker.Enabled = quests ~= nil and quests.Ready > 0
			end
			if Ui.isOpen(gui) then
				render()
			end
		end
	end)
end

return QuestController
