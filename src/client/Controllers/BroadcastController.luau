--!strict
-- What admins send to the whole server (AdminService): announcements (a big card in the
-- middle of the screen for a few seconds) and polls (a card at the top where everyone taps
-- an answer and sees the votes come in). Shown to every player.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local BroadcastController = {}

local FONT = "rbxasset://fonts/families/Montserrat.json"
local BG = Color3.fromRGB(16, 19, 34)
local OPTION = Color3.fromRGB(44, 52, 84)
local FILL = Color3.fromRGB(76, 141, 255)
local PICKED = Color3.fromRGB(64, 196, 99)
local GOLD = Color3.fromRGB(255, 196, 46)
local WHITE = Color3.new(1, 1, 1)
local SUB = Color3.fromRGB(170, 180, 210)

local gui: ScreenGui
local announceCard: Frame
local pollCard: Frame

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local obj = Instance.new(class)
	for k, v in props do
		(obj :: any)[k] = v
	end
	if parent then
		obj.Parent = parent
	end
	return obj
end

local function stroke(parent: Instance, thickness: number?, color: Color3?)
	make("UIStroke", {
		Thickness = thickness or 2.5,
		Color = color or Color3.new(0, 0, 0),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function label(parent: Instance, text: string, ts: number, color: Color3, weight: Enum.FontWeight, order: number): TextLabel
	return make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color,
		FontFace = Font.new(FONT, weight),
		TextSize = ts,
		TextWrapped = true,
		LayoutOrder = order,
	}, parent)
end

----------------------------------------------------------------------- announcements

local queue: { any } = {}
local showing = false

local function showNext()
	if showing then
		return
	end
	local info = table.remove(queue, 1)
	if not info then
		return
	end
	showing = true
	for _, child in announceCard:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local title = if type(info.Title) == "string" then info.Title else "ANNOUNCEMENT"
	label(announceCard, title, 15, GOLD, Enum.FontWeight.Heavy, 1)
	label(announceCard, info.Text, 24, WHITE, Enum.FontWeight.Heavy, 2)
	label(announceCard, `from {info.From}{if info.Global then " · every server" else ""}`, 13, SUB, Enum.FontWeight.Bold, 3)
	announceCard.Visible = true
	Ui.sound("Announce")
	local scale = announceCard:FindFirstChild("Pop") :: UIScale
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(math.clamp(tonumber(info.Seconds) or 8, 3, 60), function()
		local out = TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.05 })
		out:Play()
		out.Completed:Wait()
		announceCard.Visible = false
		showing = false
		showNext()
	end)
end

------------------------------------------------------------------------------ polls

local current: any = nil
local myVote: number? = nil
local pollId = -1
local optionRows: { TextButton } = {}
local questionLabel: TextLabel
local timerLabel: TextLabel

local function renderPoll()
	local poll = current
	if not poll then
		pollCard.Visible = false
		return
	end
	if poll.Id ~= pollId then
		pollId = poll.Id
		myVote = nil
		for _, b in optionRows do
			b:Destroy()
		end
		table.clear(optionRows)
		for i, option in poll.Options do
			local b = make("TextButton", {
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundColor3 = OPTION,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Text = "",
				LayoutOrder = 10 + i,
				ClipsDescendants = true,
			}, pollCard)
			stroke(b, 2)
			make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = FILL, BorderSizePixel = 0 }, b)
			make("TextLabel", {
				Name = "Text",
				Size = UDim2.new(1, -70, 1, 0),
				Position = UDim2.fromOffset(10, 0),
				BackgroundTransparency = 1,
				Text = option,
				TextColor3 = WHITE,
				FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 2,
			}, b)
			make("TextLabel", {
				Name = "Pct",
				Size = UDim2.new(0, 60, 1, 0),
				Position = UDim2.new(1, -8, 0, 0),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Text = "",
				TextColor3 = WHITE,
				FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 2,
			}, b)
			b.Activated:Connect(function()
				if current and not current.Ended then
					myVote = i
					Ui.sound("Click")
					Net.event("PollVote"):FireServer(i)
					renderPoll()
				end
			end)
			table.insert(optionRows, b)
		end
		Ui.sound("Notify")
	end
	questionLabel.Text = poll.Question
	local total = 0
	for _, v in poll.Votes do
		total += v
	end
	local best = 0
	for _, v in poll.Votes do
		best = math.max(best, v)
	end
	for i, b in optionRows do
		local votes = poll.Votes[i] or 0
		local share = if total > 0 then votes / total else 0
		local fill = b:FindFirstChild("Fill") :: Frame
		TweenService:Create(fill, TweenInfo.new(0.3), { Size = UDim2.fromScale(share, 1) }):Play()
		local winner = poll.Ended and votes == best and best > 0
		fill.BackgroundColor3 = if winner then GOLD:Lerp(Color3.new(0, 0, 0), 0.2) elseif myVote == i then PICKED else FILL
		;(b:FindFirstChild("Pct") :: TextLabel).Text = `{math.floor(share * 100 + 0.5)}%`
		local s = b:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = if myVote == i then WHITE else Color3.new(0, 0, 0)
		end
	end
	pollCard.Visible = true
end

local function tickTimer()
	local poll = current
	if not poll then
		return
	end
	local total = 0
	for _, v in poll.Votes do
		total += v
	end
	local left = math.max(0, poll.EndsAt - Workspace:GetServerTimeNow())
	timerLabel.Text = if poll.Ended
		then `Poll ended · {total} vote{if total == 1 then "" else "s"}`
		else `{Format.time(math.ceil(left))} left · {total} vote{if total == 1 then "" else "s"} · tap to vote`
end

------------------------------------------------------------------------------ setup

function BroadcastController:Init() end

function BroadcastController:Start()
	gui = make("ScreenGui", {
		Name = "Broadcast",
		ResetOnSpawn = false,
		DisplayOrder = 45,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))

	announceCard = make("Frame", {
		Size = UDim2.fromOffset(520, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromScale(0.5, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	stroke(announceCard, 3, GOLD)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, announceCard)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}, announceCard)
	make("UIScale", { Name = "Pop" }, announceCard)

	pollCard = make("Frame", {
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 0, 48),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = BG,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	stroke(pollCard, 3)
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, pollCard)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, pollCard)
	label(pollCard, "POLL", 13, GOLD, Enum.FontWeight.Heavy, 1)
	questionLabel = label(pollCard, "", 18, WHITE, Enum.FontWeight.Heavy, 2)
	timerLabel = label(pollCard, "", 12, SUB, Enum.FontWeight.Bold, 50)

	-- Both cards follow the HUD scale (small on phones).
	local popScale = make("UIScale", {}, pollCard)
	Ui.onScale(function(s: number)
		popScale.Scale = s
		local pop = announceCard:FindFirstChild("Pop") :: UIScale
		announceCard.Size = UDim2.fromOffset(math.floor(520 * math.max(0.75, s)), 0)
		if not showing then
			pop.Scale = 1
		end
	end)

	Net.event("Broadcast").OnClientEvent:Connect(function(info)
		if type(info) == "table" and type(info.Text) == "string" then
			table.insert(queue, info)
			showNext()
		end
	end)
	Net.event("Poll").OnClientEvent:Connect(function(poll)
		current = poll
		renderPoll()
		tickTimer()
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			tickTimer()
		end
	end)
end

return BroadcastController
