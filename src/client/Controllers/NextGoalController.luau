--!strict
-- Next goal chip under World Cleaned (retention pass, 2026-11-01).
-- Real saves showed most new players holding enough cash for the next tool or the Park and
-- never buying it (they didn't find Gear or the gate), so their earnings never grew and they
-- left around minute 2-5. This chip always names the next thing to buy: the cheaper of the
-- next tool and the next zone you can open. The bar fills with your cash; once you can pay,
-- the right side turns into a green BUY! and one tap buys it (a zone also takes you there).
-- Hidden during the tutorial (it has its own steps) and once there's nothing left to buy
-- before a rebirth (the Rebirth tile shows that progress).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Tools = require(Shared.Config.Tools)
local Zones = require(Shared.Config.Zones)
local ZoneQuests = require(Shared.Config.ZoneQuests)

local NextGoalController = {}

-- Below this tool tier an affordable tool also gets a toast and the tutorial arrow.
local NUDGE_BELOW_TIER = 7

type Goal = { Kind: string, Id: string, Name: string, Price: number, Icon: string }

local C: any
local chip: GuiButton
local title: TextLabel
local fill: Frame
local value: TextLabel
local buy: GuiButton
local percent: TextLabel
local iconLabel: ImageLabel
local current: Goal? = nil
local wasReady = false
local busy = false

local function zoneCost(data, zone): number
	local passes = data.Flags and data.Flags.ZonePass
	local hasPass = type(passes) == "table" and passes[zone.Id] == true
	return if hasPass then math.floor(zone.UnlockCost * ZoneQuests.PassDiscount) else zone.UnlockCost
end

-- The cheaper of the next tool and the next zone you're allowed to open.
local function pick(data): Goal?
	local best: Goal? = nil
	if data.ToolTier < Tools.MaxTier then
		local tool = Tools.get(data.ToolTier + 1)
		local price = if tool.Tier == Tools.FreeTier then 0 else tool.Price
		best = { Kind = "Tool", Id = tool.Id, Name = tool.Name, Price = price, Icon = AssetLibrary.toolIcon(tool.Id) }
	end
	for _, zone in Zones.List do
		if zone.UnlockCost > 0 and not data.ZonesUnlocked[zone.Id] then
			if zone.RequiredRebirths <= (data.Rebirths or 0) then
				local cost = zoneCost(data, zone)
				-- The "Open the Park" starter goal (Config/Quests) puts the zone first.
				local job = data.Quests and data.Quests.Job
				local zoneJob = job ~= nil and job.Kind == "Zones" and (job.Number or 99) <= 3
				if best == nil or cost < best.Price or zoneJob then
					best = { Kind = "Zone", Id = zone.Id, Name = zone.Name, Price = cost, Icon = AssetLibrary.image("Icon_Zones") }
				end
			end
			break -- zones open in order: only the first locked one counts
		end
	end
	return best
end

local function setVisible(on: boolean)
	if chip.Visible ~= on then
		chip.Visible = on
		if C and C.HudController and C.HudController.Relayout then
			C.HudController:Relayout()
		end
	end
end

local function render()
	local data = State.data
	if not data then
		return
	end
	local goal = if data.Flags and data.Flags.TutorialDone then pick(data) else nil
	current = goal
	if not goal then
		setVisible(false)
		return
	end
	local cash = BigNum.toNumber(data.Cash)
	local ready = BigNum.gte(data.Cash, goal.Price)
	local frac = if goal.Price <= 0 then 1 else math.clamp(cash / goal.Price, 0, 1)
	title.Text = if goal.Kind == "Zone" then `NEXT: Open {goal.Name}` else `NEXT: {goal.Name}`
	iconLabel.Image = goal.Icon
	value.Text = if goal.Price <= 0 then "FREE!" else `{Format.cash(math.min(cash, goal.Price))} / {Format.cash(goal.Price)}`
	fill.Size = UDim2.fromScale(frac, 1)
	fill.BackgroundColor3 = if ready then Color3.fromRGB(76, 209, 55) else Color3.fromRGB(255, 196, 46)
	buy.Visible = ready
	percent.Visible = not ready
	percent.Text = `{math.floor(frac * 100)}%`
	setVisible(true)
	-- The moment it becomes affordable: pop the chip and play a sound, once.
	if ready and not wasReady then
		Ui.sound("Sparkle")
		-- Early on also say it in words (2026-11-03 funnel check: 31% of new players left
		-- holding enough cash for their next tool, the chip alone wasn't noticed).
		if goal.Kind == "Tool" and data.ToolTier < NUDGE_BELOW_TIER and C and C.HudController then
			C.HudController:Toast(`You can buy the {goal.Name}! Tap BUY!`, "Good")
		end
		if not Ui.reducedMotion() then
			local pop = chip:FindFirstChild("Pop") :: UIScale?
			if not pop then
				local made = Instance.new("UIScale")
				made.Name = "Pop"
				made.Parent = chip
				pop = made
			end
			local p = pop :: UIScale
			p.Scale = 1.15
			TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	wasReady = ready
end

local function activate()
	local goal = current
	local data = State.data
	if not goal or not data or busy then
		return
	end
	if not BigNum.gte(data.Cash, goal.Price) then
		if goal.Kind == "Tool" then
			C.GarageController:Open()
		else
			local short = goal.Price - BigNum.toNumber(data.Cash)
			C.HudController:Toast(`{Format.cash(short)} more to open {goal.Name}. Keep sweeping!`)
		end
		return
	end
	busy = true
	local ok, message
	if goal.Kind == "Tool" then
		ok, message = Net.func("BuyNextTool"):InvokeServer()
	else
		ok, message = Net.func("UnlockZone"):InvokeServer(goal.Id)
	end
	busy = false
	if message then
		C.HudController:Toast(message, if ok then "Good" else "Bad")
	end
end

-- The BUY! button while the next goal is an affordable early tool and nothing else is on
-- screen (TutorialController points its arrow at it, no dimming), else nil.
function NextGoalController:Pointer(): GuiObject?
	local goal = current
	local data = State.data
	if not goal or not data or goal.Kind ~= "Tool" or data.ToolTier >= NUDGE_BELOW_TIER then
		return nil
	end
	if not chip.Visible or not buy.Visible or Ui.anyWindowOpen() then
		return nil
	end
	return buy
end

-- The id of the next zone while it's the Next goal and you can pay for it, else nil
-- (ArrowController leads you to its gate).
function NextGoalController:AffordableZone(): string?
	local goal = current
	local data = State.data
	if not goal or not data or goal.Kind ~= "Zone" or not BigNum.gte(data.Cash, goal.Price) then
		return nil
	end
	return goal.Id
end

function NextGoalController:Init(controllers)
	C = controllers
	local hud = Ui.screen("Hud")
	chip = Ui.find(hud, "NextGoal")
	title = Ui.find(chip, "Title")
	fill = Ui.find(chip, "Bar.Fill")
	value = Ui.find(chip, "Bar.Value")
	buy = Ui.find(chip, "Buy")
	percent = Ui.find(chip, "Percent")
	iconLabel = Ui.find(chip, "Icon")
end

function NextGoalController:Start()
	Ui.button(chip, activate)
	Ui.button(buy, activate)
	State.Changed:Connect(render)
	render()
end

return NextGoalController
