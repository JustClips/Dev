--!strict
-- Quests (server: QuestService, config: Config/Quests). Overhauled 2026-11-01 (Dev: "the
-- quests UI has a lot of useless stuff", "why does it say job and not quest", "put it on
-- the right, like a list"). Everything is a "quest" to the player now.
--   List     Hud.QuestList on the right edge (placed by HudController): a QUESTS header
--            and a short row per open quest (icon, text, thin bar, 1/3). Finished rows go
--            green and say CLAIM: tapping one claims it right there. Other taps open the
--            window. HudController sets the MaxRows attribute so it fits the screen.
--   Window   screen "Quests" (tools/gen_ui.py quests()): one scrolling list of the same
--            rows (Quest Master quest, 3 dailies, daily bonus + reset timer, zone
--            questlines), each with one Claim / Go button. No tabs.
--   NPC      the Quest Master on the left of every base (prompt Opens = "Quests"): his
--            dialog hands over finished quests. A bouncing "!" floats over your own one
--            while something is ready.
--   Zones    each zone's quest giver (Config/ZoneQuests, prompt Opens = "ZoneQuest" with a
--            Zone attribute): their story dialog hands over finished steps. A "!" floats
--            over any zone NPC with a finished step. GuideTarget() lets the arrow path
--            lead to them.
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
local ORANGE = Color3.fromRGB(230, 120, 40)
local GOLD = Color3.fromRGB(255, 200, 60)

local C: any
local gui: ScreenGui
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

local function setBar(bar: Instance, fraction: number, label: string)
	local fill = bar:FindFirstChild("Fill") :: Frame
	fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	;(bar:FindFirstChild("Label") :: TextLabel).Text = label
end

-------------------------------------------------------------------------- quest entries

-- One quest as both the HUD list and the window show it.
type Entry = {
	Key: string,
	Order: number,
	Icon: string,
	Who: string,
	Text: string,
	Fraction: number,
	Progress: string,
	Done: boolean, -- can be claimed now
	Claimed: boolean, -- finished and paid (window only)
	Hud: boolean, -- shown in the HUD list
	Reward: string?,
	RewardKind: string?,
	RewardItem: string?,
	Go: string?, -- button text while not done ("Go"); nil = a grey Claim
	Section: string, -- window frame: "Main", "Daily" or "Zones"
}

local function zoneEntry(zoneId: string): any
	local quests = State.data and State.data.Quests
	for _, z in (quests and quests.Zones) or {} do
		if z.Zone == zoneId then
			return z
		end
	end
	return nil
end

local function entries(quests): { Entry }
	local list: { Entry } = {}
	local job = quests.Job
	if job then
		table.insert(list, {
			Key = "Main",
			Order = 1,
			Icon = "Icon_Quest",
			Who = `QUEST {job.Number}`,
			Section = "Main",
			Text = job.Text,
			Fraction = job.Fraction or 0,
			Progress = job.Progress or "",
			Done = job.Done == true,
			Claimed = false,
			Hud = true,
			Reward = job.Reward,
			RewardKind = job.RewardKind,
			RewardItem = job.RewardItem,
		})
	end
	local daily = quests.Daily
	if daily then
		local claimed = 0
		for i, q in daily.List do
			if q.Claimed then
				claimed += 1
			end
			table.insert(list, {
				Key = `Daily{i}`,
				Order = 10 + i,
				Icon = "Icon_Daily",
				Who = "",
				Section = "Daily",
				Text = q.Text,
				Fraction = q.Fraction or 0,
				Progress = q.Progress or "",
				Done = q.Done == true and not q.Claimed,
				Claimed = q.Claimed == true,
				Hud = not q.Claimed,
				Reward = q.Reward,
				RewardKind = q.RewardKind,
				RewardItem = q.RewardItem,
			})
		end
		local left = math.max(0, (daily.ResetsAt or 0) - State.now())
		table.insert(list, {
			Key = "Bonus",
			Order = 20,
			Icon = "Icon_Spin",
			Who = "BONUS",
			Section = "Daily",
			Text = "Claim all 3 dailies",
			Fraction = claimed / math.max(1, #daily.List),
			Progress = `{claimed}/{#daily.List}`,
			Done = daily.BonusReady == true and not daily.BonusClaimed,
			Claimed = daily.BonusClaimed == true,
			Hud = daily.BonusReady == true and not daily.BonusClaimed,
			Reward = daily.Bonus,
			RewardKind = "Spin",
		})
	end
	for i, z in quests.Zones or {} do
		-- Locked and finished questlines only cluttered the list.
		if z.Open and not z.Finished then
			table.insert(list, {
				Key = `Zone_{z.Zone}`,
				Order = 30 + i,
				Icon = "Icon_Zones",
				Who = string.upper(`{z.Npc} · STEP {z.Step}/{z.Steps}`),
				Section = "Zones",
				Text = z.Text,
				Fraction = z.Fraction or 0,
				Progress = z.Progress or "",
				Done = z.Done == true,
				Claimed = false,
				Hud = true,
				Reward = z.Reward,
				RewardKind = z.RewardKind,
				RewardItem = z.RewardItem,
				Go = "Go",
			})
		end
	end
	return list
end

-------------------------------------------------------------------------- HUD list

local list: Frame
local listRows: { [string]: GuiButton } = {}
local windowRows: { [string]: Frame } = {}
local current: { [string]: Entry } = {}
local act: (key: string, fromHud: boolean) -> ()

local function setRewardChip(box: Instance, e: Entry)
	(box :: GuiObject).Visible = e.Reward ~= nil and e.Reward ~= ""
	;(box:FindFirstChild("Icon") :: ImageLabel).Image = rewardIcon(e.RewardKind, e.RewardItem)
	;(box:FindFirstChild("Label") :: TextLabel).Text = e.Reward or ""
end

-- Keeps one clone of `template` per key, drops the ones whose quest is gone.
local function pool<T>(rows: { [string]: T }, keep: { [string]: boolean }, make: (key: string) -> T)
	for key, row in rows do
		if not keep[key] then
			(row :: any):Destroy()
			rows[key] = nil
		end
	end
	for key in keep do
		if not rows[key] then
			rows[key] = make(key)
		end
	end
end

local function renderList(quests)
	local ready = if quests and (quests.Ready or 0) > 0 then quests.Ready else nil
	Ui.setBadge(Ui.find(Ui.screen("Hud"), "MoreMenu.Items.QuestsButton.Badge") :: GuiObject, ready)
	Ui.setBadge(Ui.find(list, "Header.Badge") :: GuiObject, ready)
	local shown: { Entry } = {}
	if quests then
		for _, e in entries(quests) do
			if e.Hud then
				table.insert(shown, e)
			end
		end
	end
	-- Claimable first, then the ones closest to done (Dev, 2026-11-01).
	table.sort(shown, function(a, b)
		if a.Done ~= b.Done then
			return a.Done
		end
		if math.abs(a.Fraction - b.Fraction) > 0.001 then
			return a.Fraction > b.Fraction
		end
		return a.Order < b.Order
	end)
	local maxRows = list:GetAttribute("MaxRows")
	local limit = if type(maxRows) == "number" then maxRows else 4
	local keep: { [string]: boolean } = {}
	for i, e in shown do
		if i <= limit then
			keep[e.Key] = true
		end
	end
	list.Visible = quests ~= nil and #shown > 0
	local template = list:FindFirstChild("Row") :: GuiButton
	pool(listRows, keep, function(key)
		local row = template:Clone()
		row.Name = "Row_" .. key
		row.Visible = true
		row.Parent = list
		Ui.button(row, function()
			act(key, true)
		end)
		return row
	end)
	for i, e in shown do
		local row = listRows[e.Key]
		if not row then
			continue
		end
		row.LayoutOrder = i
		;(row:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.image(e.Icon)
		;(row:FindFirstChild("Text") :: TextLabel).Text = e.Text
		local fill = Ui.find(row, "Bar.Fill") :: Frame
		fill.Size = UDim2.fromScale(if e.Done then 1 else math.clamp(e.Fraction, 0, 1), 1)
		fill.BackgroundColor3 = if e.Done then GOLD else GREEN
		local progress = row:FindFirstChild("Progress") :: TextLabel
		progress.Text = if e.Done then "CLAIM!" else e.Progress
		progress.TextColor3 = if e.Done then GOLD else Color3.fromRGB(201, 208, 222)
		row.BackgroundColor3 = if e.Done then Color3.fromRGB(30, 120, 70) else Color3.fromRGB(23, 25, 30)
	end
end

-------------------------------------------------------------------------- window

local function renderWindow(quests)
	local scroll = Ui.find(gui, "Window.List") :: ScrollingFrame
	local template = scroll:FindFirstChild("Row") :: Frame
	local all = entries(quests)
	local keep: { [string]: boolean } = {}
	for _, e in all do
		keep[e.Key] = true
	end
	pool(windowRows, keep, function(key)
		local row = template:Clone()
		row.Name = "Row_" .. key
		row.Visible = true
		row.Parent = Ui.find(scroll, `{current[key].Section}.Rows`)
		Ui.button(row:FindFirstChild("Action") :: GuiButton, function()
			act(key, false)
		end)
		return row
	end)
	for _, e in all do
		local row = windowRows[e.Key]
		-- Claimed rows sink to the bottom of their group.
		row.LayoutOrder = e.Order + (if e.Claimed then 100 else 0)
		;(row:FindFirstChild("Icon") :: ImageLabel).Image = AssetLibrary.image(e.Icon)
		local who = row:FindFirstChild("Who") :: TextLabel
		who.Text = e.Who
		who.Visible = e.Who ~= ""
		local textLabel = row:FindFirstChild("Text") :: TextLabel
		textLabel.Text = e.Text
		-- No small title (dailies): the text and bar sit centred in the row.
		local shift = if e.Who == "" then -8 else 0
		textLabel.Position = UDim2.new(textLabel.Position.X.Scale, textLabel.Position.X.Offset, 0, 22 + shift)
		local bar = row:FindFirstChild("Bar") :: Frame
		bar.Position = UDim2.new(bar.Position.X.Scale, bar.Position.X.Offset, 0, 50 + shift)
		setBar(row:FindFirstChild("Bar") :: Frame, if e.Done or e.Claimed then 1 else e.Fraction, if e.Claimed
			then "DONE"
			elseif e.Done then "DONE!"
			else e.Progress)
		setRewardChip(row:FindFirstChild("Reward") :: Frame, e)
		local button = row:FindFirstChild("Action") :: GuiButton
		if e.Claimed then
			paint(button, "Done", GREY)
		elseif e.Done then
			paint(button, "Claim", if e.Key == "Bonus" then GOLD else GREEN)
		elseif e.Go then
			paint(button, e.Go, BLUE)
		else
			paint(button, "Claim", GREY)
		end
	end
end

-- Sections with nothing in them hide; the daily frame shows when new dailies come.
local function renderSections(quests)
	local scroll = Ui.find(gui, "Window.List") :: ScrollingFrame
	for _, name in { "Main", "Daily", "Zones" } do
		local section = scroll:FindFirstChild(name) :: Frame
		local rows = section:FindFirstChild("Rows") :: Frame
		local any = false
		for _, child in rows:GetChildren() do
			if child:IsA("GuiObject") then
				any = true
			end
		end
		section.Visible = any
	end
	local daily = quests.Daily
	local timer = Ui.find(scroll, "Daily.Header.Timer") :: TextLabel
	local left = math.max(0, ((daily and daily.ResetsAt) or 0) - State.now())
	timer.Text = `New dailies in {Format.countdown(left)}`
end

local function render()
	local quests = State.data and State.data.Quests
	for key in current do
		current[key] = nil
	end
	if quests then
		for _, e in entries(quests) do
			current[e.Key] = e
		end
	end
	renderList(quests)
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
	renderWindow(quests)
	renderSections(quests)
end

function QuestController:Open(_which: string?)
	if not (State.data and State.data.Quests) then
		C.HudController:Toast("Finish the tutorial to unlock quests!", "Info")
		return
	end
	if not Ui.isOpen(gui) then
		Ui.open("Quests")
		;(Ui.find(gui, "Window.List") :: ScrollingFrame).CanvasPosition = Vector2.zero
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
	-- Already on your base: the 3D arrow path shows the way when a quest is done.
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

-- Zone quest Go: teleport to that zone and let the arrow lead to its quest giver.
local function goToZoneNpc(zoneId: string)
	local z = zoneEntry(zoneId)
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

-- A tap on a quest row. Finished quests are claimed right there (never moves you).
-- Otherwise HUD rows open the window, and window buttons go to the quest giver.
act = function(key: string, fromHud: boolean)
	local e = current[key]
	if not e then
		return
	end
	local daily = tonumber(string.match(key, "^Daily(%d+)$"))
	local zone = string.match(key, "^Zone_(.+)$")
	if e.Done then
		if key == "Main" then
			claimFromWindow("ClaimJob", nil, "Quest reward")
		elseif key == "Bonus" then
			claimBonus()
		elseif daily then
			claimDaily(daily)
		elseif zone then
			claimFromWindow("ClaimZone", zone, "Quest reward")
		end
		return
	end
	if fromHud then
		QuestController:Open(nil)
	elseif e.Claimed then
		return
	elseif key == "Main" then
		goToMaster()
	elseif zone then
		goToZoneNpc(zone)
	elseif key == "Bonus" then
		claimBonus()
	elseif daily then
		claimDaily(daily)
	end
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
	C.HudController:Toast(`Quest reward: {got}!`, "Good")
	-- The next quest arrives with the next snapshot.
	task.wait(0.35)
	local job = State.data and State.data.Quests and State.data.Quests.Job
	local nextLine = if job and not job.Done then ` Your next quest: {job.Text}.` else ""
	C.DialogController:Say(`Great work! Here's your reward: {got}!{nextLine}`, {
		{ text = "On it!", color = GREEN, pick = bye },
		{
			text = "Show my quests",
			color = BLUE,
			pick = function()
				C.DialogController:Close()
				QuestController:Open(nil)
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
	-- The first quest arrives with the next snapshot.
	local job = nil
	for _ = 1, 10 do
		task.wait(0.2)
		job = State.data and State.data.Quests and State.data.Quests.Job
		if job then
			break
		end
	end
	local line = if job
		then `Your first quest: {job.Text}! Come back to me when it's done and I'll pay you {job.Reward}.`
		else "You're all set! Check the quest list on the right for your first quest."
	C.DialogController:Say(line, {
		{ text = "On it!", color = GREEN, pick = bye },
	})
end

talk = function()
	if State.data and State.data.TutorialStep == "Quest" then
		C.DialogController:Say("Hi! I'm the Quest Master. I hand out quests with awesome rewards. Want your first one?", {
			{ text = "Accept quest!", color = GREEN, pick = acceptFirst },
		})
		return
	end
	local quests = State.data and State.data.Quests
	if not quests or not quests.Job then
		C.DialogController:Say("Hi there! Finish the tutorial first, then come see me for quests and rewards.", {
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
			QuestController:Open(nil)
		end,
	}
	if job.Done then
		C.DialogController:Say(`You did it: {job.Text}! I've got {job.Reward} for you.`, {
			{ text = `Claim {job.Reward}!`, color = GREEN, pick = claimJob },
			dailyOption,
		})
		return
	end
	C.DialogController:Say(`Your quest: {job.Text}. You're at {job.Progress}. Come back when it's done and I'll pay you {job.Reward}!`, {
		{ text = "On it!", color = GREEN, pick = bye },
		dailyOption,
		{
			text = "Show my quests",
			color = BLUE,
			pick = function()
				C.DialogController:Close()
				QuestController:Open(nil)
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
				QuestController:Open(nil)
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
	local hud = Ui.screen("Hud")
	list = Ui.find(hud, "QuestList")
	gui = Ui.screen("Quests")
	-- LiveSync never deletes GUI children in Dev's Studio place: drop the old top JOB strip
	-- and the old window's tabs and pages (overhauled 2026-11-01).
	local old = hud:FindFirstChild("Quests")
	if old then
		old:Destroy()
	end
	local window = gui:FindFirstChild("Window")
	for _, name in { "JobsTab", "DailyTab", "ZonesTab", "Job", "Daily", "Zones" } do
		local stale = window and window:FindFirstChild(name)
		if stale then
			stale:Destroy()
		end
	end
end

function QuestController:Start()
	Ui.button(Ui.find(list, "Header"), function()
		QuestController:Open(nil)
	end)
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Quests")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Quests")
	end)
	list:GetAttributeChangedSignal("MaxRows"):Connect(render)
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
			C.HudController:Toast(`Quest done: {info.Text}! Tap it in your quest list to claim.`, "Good")
		elseif info.Job then
			C.HudController:Toast(`Quest done: {info.Text}! Tap it in your quest list to claim.`, "Good")
		else
			C.HudController:Toast(`Daily quest done: {info.Text}! Tap it in your quest list to claim.`, "Good")
		end
		Ui.popFrame(Ui.find(list, "Header"))
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
