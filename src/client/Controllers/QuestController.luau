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
--   Zones    each zone's quest giver (Config/ZoneQuests, prompt Opens = "ZoneQuest" with a
--            Zone attribute): their story dialog hands over finished steps. The Zones tab
--            lists every questline with a Go button, and a "!" floats over any zone NPC
--            with a finished step. GuideTarget() lets the arrow path lead to them.
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
local World = require(Shared.Config.World)
local ZoneQuests = require(Shared.Config.ZoneQuests)

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
local zoneMarkers: { [string]: BillboardGui } = {}
local guide: { Zone: string, Until: number }? = nil -- arrow to a zone NPC after pressing Go
local GUIDE_SECONDS = 60

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
	elseif kind == "Pet" then
		return AssetLibrary.image("Icon_Alien")
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
		nextLabel.Text = "Done! Claim it in Quests"
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
		hint.Text = "Job done! Claim your reward here."
		paint(go, "Claim", GREEN)
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

local function zoneEntry(zoneId: string): any
	local quests = State.data and State.data.Quests
	for _, z in (quests and quests.Zones) or {} do
		if z.Zone == zoneId then
			return z
		end
	end
	return nil
end

local function renderZones(list)
	local page = Ui.find(gui, "Window.Zones") :: Frame
	for i = 1, 5 do
		local row = Ui.find(page, `List.Row{i}`) :: Frame
		local z = list[i]
		row.Visible = z ~= nil
		if not z then
			continue
		end
		;(row:FindFirstChild("Who") :: TextLabel).Text = string.upper(`{z.Npc} · {z.ZoneName}`)
		local textLabel = row:FindFirstChild("Text") :: TextLabel
		local bar = row:FindFirstChild("Bar") :: Frame
		local reward = row:FindFirstChild("Reward") :: Frame
		local go = row:FindFirstChild("Go") :: GuiButton
		if not z.Open then
			textLabel.Text = `Unlock the {z.ZoneName} to meet {z.Npc}`
			setBar(bar, 0, "LOCKED")
			reward.Visible = false
			paint(go, "Locked", GREY)
		elseif z.Finished then
			textLabel.Text = "All quests done!"
			setBar(bar, 1, `{z.Steps}/{z.Steps}`)
			reward.Visible = false
			paint(go, "Go", BLUE)
		else
			textLabel.Text = `{z.Step}/{z.Steps}  {z.Text}`
			setBar(bar, z.Fraction, if z.Done then "DONE!" else z.Progress)
			reward.Visible = true
			setReward(reward, z)
			paint(go, if z.Done then "Claim" else "Go", if z.Done then GREEN else BLUE)
		end
	end
end

local function render()
	local quests = State.data and State.data.Quests
	renderStrip(quests)
	if marker then
		marker.Enabled = quests ~= nil and quests.Ready - (quests.ZoneReady or 0) > 0
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
	local zonesTab = Ui.find(gui, "Window.ZonesTab") :: GuiButton
	paint(jobsTab, "Jobs", if tab == "Jobs" then BLUE else DARK_BLUE)
	paint(dailyTab, "Daily", if tab == "Daily" then BLUE else DARK_BLUE)
	paint(zonesTab, "Zones", if tab == "Zones" then BLUE else DARK_BLUE)
	local zonesReady = 0
	for _, z in quests.Zones or {} do
		if z.Done then
			zonesReady += 1
		end
	end
	Ui.setBadge(zonesTab:FindFirstChild("Badge") :: GuiObject, if zonesReady > 0 then zonesReady else nil)
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
	local zonesPage = Ui.find(gui, "Window.Zones") :: Frame
	zonesPage.Visible = tab == "Zones" and quests.Zones ~= nil
	if quests.Zones then
		renderZones(quests.Zones)
	end
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

-- Claim from the Quests window: only gives the reward, never moves you.
local function claimFromWindow(action: string, arg: any?, label: string)
	if busy then
		return
	end
	busy = true
	local ok, got = invoke(action, arg)
	busy = false
	if ok then
		Ui.sound("Reveal")
		C.HudController:Toast(`{label}: {got}!`, "Good")
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

-- Zones tab Go: teleport to that zone and let the arrow lead to its quest giver.
local function goToZoneNpc(i: number)
	local quests = State.data and State.data.Quests
	local z = quests and quests.Zones and quests.Zones[i]
	if not z then
		return
	end
	if not z.Open then
		C.HudController:Toast(`Unlock the {z.ZoneName} first!`, "Info")
		return
	end
	Ui.close("Quests")
	guide = { Zone = z.Zone, Until = os.clock() + GUIDE_SECONDS }
	task.spawn(function()
		local spot = World.ZoneNpc[z.Zone]
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and spot and (root.Position - spot).Magnitude < 90 then
			return
		end
		-- Land right next to the quest giver (zone teleports land elsewhere, and the
		-- Backyard one is the sell spot).
		local target = `Npc:{z.Zone}`
		local ok, message = pcall(function()
			return Net.func("Teleport"):InvokeServer(target)
		end)
		if ok and message and type(message) == "string" and message ~= "" then
			C.HudController:Toast(message, "Info")
		end
	end)
end

-- Where the arrow path should lead for zone quests: the NPC of a finished step in the zone
-- you're standing in, or the one you just pressed Go for.
function QuestController:GuideTarget(position: Vector3): Vector3?
	local quests = State.data and State.data.Quests
	if not quests or not quests.Zones then
		return nil
	end
	if guide and os.clock() > guide.Until then
		guide = nil
	end
	for _, z in quests.Zones do
		local spot = World.ZoneNpc[z.Zone]
		if spot and z.Open then
			local guided = guide ~= nil and guide.Zone == z.Zone
			local nearby = (spot - position).Magnitude < 260
			if (z.Done and nearby) or guided then
				if guided and (spot - position).Magnitude < 12 then
					guide = nil
				end
				return spot + Vector3.new(-3, 0, 3)
			end
		end
	end
	return nil
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

-- Tutorial's last step: accept your first quest.
local function acceptFirst()
	if busy then
		return
	end
	busy = true
	local ok, message = invoke("Accept")
	busy = false
	if not ok then
		C.DialogController:Say(message or "Hmm, that didn't work.", {
			{ text = "Okay", color = GREY, pick = talk },
		})
		return
	end
	Ui.sound("Reveal")
	-- The first job arrives with the next snapshot.
	local job = nil
	for _ = 1, 10 do
		task.wait(0.2)
		job = State.data and State.data.Quests and State.data.Quests.Job
		if job then
			break
		end
	end
	local line = if job
		then `Your first job: {job.Text}! Come back to me when it's done and I'll pay you {job.Reward}.`
		else "You're all set! Check the Quests bar at the top for your first job."
	C.DialogController:Say(line, {
		{ text = "On it!", color = GREEN, pick = bye },
	})
end

talk = function()
	if State.data and State.data.TutorialStep == "Quest" then
		C.DialogController:Say("Hi! I'm the Quest Master. I hand out jobs with awesome rewards. Want your first one?", {
			{ text = "Accept quest!", color = GREEN, pick = acceptFirst },
		})
		return
	end
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

-------------------------------------------------------------------------- zone NPC dialog

local talkZone: (zoneId: string) -> ()

local function claimZone(zoneId: string)
	if busy then
		return
	end
	local line = ZoneQuests.ByZone[zoneId]
	local before = zoneEntry(zoneId)
	busy = true
	local ok, got = invoke("ClaimZone", zoneId)
	busy = false
	if not ok then
		C.DialogController:Say(got or "Hmm, that didn't work.", {
			{ text = "Okay", color = GREY, pick = function()
				talkZone(zoneId)
			end },
		})
		return
	end
	Ui.sound("Reveal")
	C.HudController:Toast(`Quest reward: {got}!`, "Good")
	task.wait(0.35)
	local lastStep = before and before.Last
	if lastStep and line then
		local pass = if line.Next and line.NextNpc
			then ` And take this Zone Pass: the gate to the next zone costs you HALF now. {line.NextNpc} is waiting for you there!`
			else ""
		C.DialogController:Say(`You did it all! Here's your {got}!{pass}`, {
			{ text = "Thank you!", color = GREEN, pick = bye },
		})
		return
	end
	local z = zoneEntry(zoneId)
	local nextLine = if z and z.Say and not z.Done then ` Next: {z.Say}` else ""
	C.DialogController:Say(`Thanks a bunch! Here's your reward: {got}!{nextLine}`, {
		{ text = "On it!", color = GREEN, pick = bye },
	})
end

talkZone = function(zoneId: string)
	local line = ZoneQuests.ByZone[zoneId]
	local z = zoneEntry(zoneId)
	if not line then
		C.DialogController:Close()
		return
	end
	if not z or not z.Open then
		C.DialogController:Say("Hi there! Finish the tutorial first, then come see me for quests.", {
			{ text = "Okay!", color = GREEN, pick = bye },
		})
		return
	end
	if z.Finished then
		C.DialogController:Say(line.Done, {
			{ text = "Bye!", color = GREEN, pick = bye },
		})
		return
	end
	if z.Done then
		C.DialogController:Say(`You did it: {z.Text}! I've got {z.Reward} for you.`, {
			{ text = `Claim {z.Reward}!`, color = GREEN, pick = function()
				claimZone(zoneId)
			end },
		})
		return
	end
	local hello = if z.Fresh then line.Hello .. " " else ""
	C.DialogController:Say(`{hello}{z.Say} ({z.Progress}) I'll give you {z.Reward}!`, {
		{ text = "On it!", color = GREEN, pick = bye },
		{
			text = "Show my quests",
			color = BLUE,
			pick = function()
				C.DialogController:Close()
				QuestController:Open("Zones")
			end,
		},
	})
end

-- A bouncing "!" over every zone NPC with a finished step.
local function updateZoneMarkers()
	local quests = State.data and State.data.Quests
	local folder = Workspace:FindFirstChild("ZoneNpcs")
	for _, line in ZoneQuests.Lines do
		local z = zoneEntry(line.Zone)
		local npc = folder and folder:FindFirstChild("ZoneNpc_" .. line.Zone)
		local head = npc and npc:FindFirstChild("Head") :: BasePart?
		local board = zoneMarkers[line.Zone]
		if head and (not board or board.Adornee ~= head) then
			if board then
				board:Destroy()
			end
			board = Instance.new("BillboardGui")
			board.Name = "ZoneQuestMarker"
			board.Adornee = head
			board.Size = UDim2.fromScale(2.4, 2.4)
			board.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
			board.AlwaysOnTop = true
			board.LightInfluence = 0
			board.MaxDistance = 260
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
			zoneMarkers[line.Zone] = board
		end
		if board then
			-- "!" when a step is done, or a fresh questline nobody has started yet.
			board.Enabled = quests ~= nil and z ~= nil and z.Open and (z.Done == true or z.Fresh == true)
			local label = board:FindFirstChildOfClass("TextLabel")
			if label then
				label.TextColor3 = if z and z.Done then GOLD else Color3.fromRGB(120, 210, 255)
			end
		end
	end
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
	Ui.button(Ui.find(gui, "Window.Job.Go"), function()
		local job = State.data and State.data.Quests and State.data.Quests.Job
		if job and job.Done then
			claimFromWindow("ClaimJob", nil, "Job reward")
		else
			goToMaster()
		end
	end)
	for i = 1, 3 do
		Ui.button(Ui.find(gui, `Window.Daily.List.Row{i}.Claim`), function()
			claimDaily(i)
		end)
	end
	Ui.button(Ui.find(gui, "Window.Daily.Bonus.Claim"), claimBonus)
	Ui.button(Ui.find(gui, "Window.ZonesTab"), function()
		tab = "Zones"
		render()
	end)
	for i = 1, 5 do
		Ui.button(Ui.find(gui, `Window.Zones.List.Row{i}.Go`), function()
			local quests = State.data and State.data.Quests
			local z = quests and quests.Zones and quests.Zones[i]
			if z and z.Open and z.Done and not z.Finished then
				claimFromWindow("ClaimZone", z.Zone, "Quest reward")
			else
				goToZoneNpc(i)
			end
		end)
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") == "ZoneQuest" then
			local zoneId = prompt:GetAttribute("Zone")
			local line = type(zoneId) == "string" and ZoneQuests.ByZone[zoneId]
			if line then
				local at = prompt.Parent
				C.DialogController:Open(line.Npc, if at and at:IsA("BasePart") then at else nil)
				talkZone(zoneId :: string)
			end
			return
		end
		if prompt:GetAttribute("Opens") ~= "Quests" then
			return
		end
		local at = prompt.Parent
		C.DialogController:Open(Quests.NpcName, if at and at:IsA("BasePart") then at else nil)
		talk()
	end)
	Net.event("QuestReady").OnClientEvent:Connect(function(info)
		Ui.sound("Tutorial")
		if info.Npc then
			C.HudController:Toast(`Quest done: {info.Text}! Claim it in Quests.`, "Good")
		elseif info.Job then
			C.HudController:Toast(`Job done: {info.Text}! Claim it in Quests.`, "Good")
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
		local bob = Vector3.new(0, 4.6 + math.abs(math.sin(t * 3)) * 0.8, 0)
		if marker and marker.Enabled then
			marker.StudsOffsetWorldSpace = bob
		end
		for _, board in zoneMarkers do
			if board.Enabled then
				board.StudsOffsetWorldSpace = bob
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			buildMarker()
			updateZoneMarkers()
			if marker then
				local quests = State.data and State.data.Quests
				marker.Enabled = quests ~= nil and quests.Ready - (quests.ZoneReady or 0) > 0
			end
			if Ui.isOpen(gui) then
				render()
			end
		end
	end)
end

return QuestController
