--!strict
-- What admins send to the whole server (AdminService), drawn like the popular admin
-- systems (HD Admin / Adonis style message banners), in our game style:
--   * announcements and admin events: a compact banner at the top middle with the sender's
--     avatar, an ADMIN / ADMIN EVENT tag and their name. The message types itself out
--     letter by letter with soft ticks, stays a few seconds (a bar runs down), then slides
--     away. Tap it to close early. Several queue up.
--   * polls: a card in the same style under the banner, where everyone taps an answer and
--     sees the votes come in.
-- Square plates, Montserrat, solid fills (docs/UI_STYLE.md). Shown to every player.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local BroadcastController = {}

local FONT = "rbxasset://fonts/families/Montserrat.json"
local BG = Color3.fromRGB(20, 26, 51) -- night navy plate
local PLATE = Color3.fromRGB(34, 42, 78) -- avatar backing, option rows
local INK = Color3.fromRGB(27, 31, 58)
local FILL = Color3.fromRGB(76, 141, 255)
local PICKED = Color3.fromRGB(61, 220, 90)
local GOLD = Color3.fromRGB(255, 200, 60)
local PURPLE = Color3.fromRGB(170, 110, 255)
local BLUE = Color3.fromRGB(59, 79, 168)
local WHITE = Color3.new(1, 1, 1)
local SUB = Color3.fromRGB(175, 185, 215)

local WIDTH = 500 -- banner width on a big screen (UI units, before the HUD scale)
local AVATAR = 64
local TYPE_RATE = 45 -- letters a second while a message types out
local TYPE_MAX = 1.8 -- seconds; long messages type faster

local gui: ScreenGui
local stack: Frame -- top-middle column: banner, then the poll card
local stackScale: UIScale

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

local function stroke(parent: Instance, thickness: number, color: Color3)
	return make("UIStroke", {
		Thickness = thickness,
		Color = color,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	}, parent)
end

local function textStroke(label: TextLabel)
	make("UIStroke", { Thickness = 1.5, Color = INK, LineJoinMode = Enum.LineJoinMode.Round }, label)
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end

-- A solid tag block like "ADMIN" (auto width).
local function tag(parent: Instance, value: string, color: Color3, order: number): TextLabel
	local t = text(parent, {
		Text = value,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		TextColor3 = INK,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = order,
	})
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, t)
	stroke(t, 2, INK)
	return t
end

-- Avatar headshots, cached per user (the fetch can yield, so it fills in when ready).
local headshots: { [number]: string } = {}
local function setAvatar(image: ImageLabel, userId: number?)
	image.Image = AssetLibrary.image("Icon_Event")
	if not userId or userId <= 0 then
		return
	end
	if headshots[userId] then
		image.Image = headshots[userId]
		return
	end
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and type(url) == "string" then
			headshots[userId] = url
			image.Image = url
		end
	end)
end

-- Types `label`'s text out letter by letter. Returns the seconds it takes.
local typingToken = 0
local function typeOut(label: TextLabel): number
	typingToken += 1
	local token = typingToken
	local total = utf8.len(label.ContentText) or #label.ContentText
	if Ui.reducedMotion() or total == 0 then
		label.MaxVisibleGraphemes = -1
		return 0
	end
	local rate = math.max(TYPE_RATE, total / TYPE_MAX)
	label.MaxVisibleGraphemes = 0
	task.spawn(function()
		local shown = 0
		local start = os.clock()
		while shown < total and token == typingToken and label.Parent do
			task.wait()
			local now = math.min(total, math.floor((os.clock() - start) * rate))
			if now ~= shown then
				-- A soft tick every few letters (not on spaces).
				if math.floor(now / 3) ~= math.floor(shown / 3) then
					local ch = string.sub(label.ContentText, now, now)
					if ch ~= " " then
						Ui.sound("Click", 1.5 + math.random() * 0.2)
					end
				end
				shown = now
				label.MaxVisibleGraphemes = shown
			end
		end
		label.MaxVisibleGraphemes = -1
	end)
	return total / rate
end

-------------------------------------------------------------------------- banner

type Banner = {
	frame: TextButton,
	accent: Frame,
	avatar: ImageLabel,
	avatarStroke: UIStroke,
	icon: ImageLabel,
	tags: Frame,
	kindTag: TextLabel,
	globalTag: TextLabel,
	name: TextLabel,
	timer: TextLabel,
	body: TextLabel,
	blurb: TextLabel,
	bar: Frame,
	pop: UIScale,
}
local banner: Banner

local queue: { any } = {}
local showing = false
local closeNow: (() -> ())? = nil
local eventEndsAt = 0

local function buildBanner(): Banner
	local frame = make("TextButton", {
		Name = "Announcement",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		Visible = false,
		LayoutOrder = 1,
		ClipsDescendants = false,
	}, stack)
	stroke(frame, 3, INK)
	local pop = make("UIScale", { Name = "Pop" }, frame)
	-- Coloured strip down the left edge (gold = message, purple = event).
	local accent = make("Frame", {
		Name = "Accent",
		-- offsets undo the card's padding (padding moves every child)
		Size = UDim2.new(0, 6, 1, 24),
		Position = UDim2.fromOffset(-16, -10),
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
	}, frame)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 12),
	}, frame)

	local avatarBox = make("Frame", {
		Name = "Avatar",
		Size = UDim2.fromOffset(AVATAR, AVATAR),
		BackgroundColor3 = PLATE,
		BorderSizePixel = 0,
	}, frame)
	local avatarStroke = stroke(avatarBox, 3, GOLD)
	local avatar = make("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
	}, avatarBox)
	-- Event icon, sitting on the avatar's bottom-right corner.
	local icon = make("ImageLabel", {
		Name = "EventIcon",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(1, 8, 1, 8),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = PURPLE,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
	}, avatarBox)
	stroke(icon, 2, INK)

	local right = make("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -(AVATAR + 12), 0, 0),
		Position = UDim2.fromOffset(AVATAR + 12, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, frame)
	make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, right)

	local tags = make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, right)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tags)
	local kindTag = tag(tags, "ADMIN", GOLD, 1)
	local globalTag = tag(tags, "ALL SERVERS", Color3.fromRGB(120, 200, 255), 2)
	local name = text(tags, {
		Name = "Name",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 16,
		TextColor3 = SUB,
		LayoutOrder = 3,
	})
	local timer = text(tags, {
		Name = "Timer",
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = BLUE,
		BorderSizePixel = 0,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 4,
		Visible = false,
	})
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, timer)
	stroke(timer, 2, INK)

	local body = text(right, {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 20,
		TextWrapped = true,
		LayoutOrder = 2,
	})
	textStroke(body)
	local blurb = text(right, {
		Name = "Blurb",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		FontFace = Font.new(FONT, Enum.FontWeight.Bold),
		TextSize = 14,
		TextColor3 = SUB,
		TextWrapped = true,
		LayoutOrder = 3,
	})

	-- Time left on screen, along the top edge.
	local barBack = make("Frame", {
		Name = "Bar",
		Size = UDim2.new(1, 22, 0, 4),
		Position = UDim2.fromOffset(-10, -10),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
	}, frame)
	local bar = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, barBack)

	frame.Activated:Connect(function()
		if closeNow then
			closeNow()
		end
	end)

	return {
		frame = frame,
		accent = accent,
		avatar = avatar,
		avatarStroke = avatarStroke,
		icon = icon,
		tags = tags,
		kindTag = kindTag,
		globalTag = globalTag,
		name = name,
		timer = timer,
		body = body,
		blurb = blurb,
		bar = bar,
		pop = pop,
	}
end

local function showNext()
	if showing then
		return
	end
	local info = table.remove(queue, 1)
	if not info then
		return
	end
	showing = true
	local isEvent = info.Kind == "Event"
	local color = if isEvent then PURPLE else GOLD
	local b = banner

	b.accent.BackgroundColor3 = color
	b.avatarStroke.Color = color
	b.bar.BackgroundColor3 = color
	b.kindTag.Text = if type(info.Title) == "string" then info.Title else "ADMIN"
	b.kindTag.BackgroundColor3 = color
	b.globalTag.Visible = info.Global == true
	b.name.Text = if type(info.From) == "string" then info.From else "Admin"
	setAvatar(b.avatar, tonumber(info.FromId))

	local icon = if type(info.Icon) == "string" then AssetLibrary.image(info.Icon) else ""
	b.icon.Image = icon
	b.icon.Visible = icon ~= ""
	eventEndsAt = if isEvent then tonumber(info.EndsAt) or 0 else 0
	b.timer.Visible = eventEndsAt > 0

	b.body.Text = info.Text
	b.body.TextSize = if isEvent then 22 else 20
	b.body.TextColor3 = if isEvent then GOLD else WHITE
	b.blurb.Text = if type(info.Blurb) == "string" then info.Blurb else ""
	b.blurb.Visible = b.blurb.Text ~= ""
	b.body.MaxVisibleGraphemes = 0

	-- Slide down and pop in.
	b.frame.Visible = true
	b.bar.Size = UDim2.fromScale(1, 1)
	Ui.sound(if isEvent then "Attention" else "Announce")
	if Ui.reducedMotion() then
		b.pop.Scale = 1
	else
		b.pop.Scale = 0.7
		TweenService:Create(b.pop, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.wait(0.15)
	local typing = typeOut(b.body)
	local stay = math.clamp(tonumber(info.Seconds) or 8, 3, 60)
	TweenService:Create(b.bar, TweenInfo.new(typing + stay, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()

	local done = false
	local function close()
		if done then
			return
		end
		done = true
		closeNow = nil
		typingToken += 1
		if not Ui.reducedMotion() then
			local out = TweenService:Create(b.pop, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.05 })
			out:Play()
			out.Completed:Wait()
		end
		b.frame.Visible = false
		showing = false
		showNext()
	end
	closeNow = close
	task.delay(typing + stay, close)
end

------------------------------------------------------------------------------ polls

local pollCard: Frame
local pollAvatar: ImageLabel
local pollName: TextLabel
local pollGlobal: TextLabel
local current: any = nil
local myVote: number? = nil
local pollId = -1
local optionRows: { TextButton } = {}
local questionLabel: TextLabel
local timerLabel: TextLabel

local function buildPoll()
	pollCard = make("Frame", {
		Name = "Poll",
		Size = UDim2.new(1, -60, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		Visible = false,
		LayoutOrder = 2,
	}, stack)
	stroke(pollCard, 3, FILL)
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, pollCard)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, pollCard)

	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 1 }, pollCard)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, head)
	local box = make("Frame", { Size = UDim2.fromOffset(30, 30), BackgroundColor3 = PLATE, BorderSizePixel = 0, LayoutOrder = 0 }, head)
	stroke(box, 2, FILL)
	pollAvatar = make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop }, box)
	tag(head, "POLL", FILL, 1)
	pollGlobal = tag(head, "ALL SERVERS", Color3.fromRGB(120, 200, 255), 2)
	pollName = text(head, {
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 15,
		TextColor3 = SUB,
		LayoutOrder = 3,
	})

	questionLabel = text(pollCard, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 18,
		TextWrapped = true,
		LayoutOrder = 2,
	})
	textStroke(questionLabel)
	timerLabel = text(pollCard, {
		Size = UDim2.new(1, 0, 0, 16),
		FontFace = Font.new(FONT, Enum.FontWeight.Bold),
		TextSize = 12,
		TextColor3 = SUB,
		LayoutOrder = 50,
	})
end

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
				Size = UDim2.new(1, 0, 0, 32),
				BackgroundColor3 = PLATE,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Text = "",
				LayoutOrder = 10 + i,
				ClipsDescendants = true,
			}, pollCard)
			stroke(b, 2, INK)
			make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = FILL, BorderSizePixel = 0 }, b)
			local t = text(b, {
				Name = "Text",
				Size = UDim2.new(1, -70, 1, 0),
				Position = UDim2.fromOffset(10, 0),
				Text = option,
				TextSize = 15,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 2,
			})
			textStroke(t)
			local pct = text(b, {
				Name = "Pct",
				Size = UDim2.new(0, 60, 1, 0),
				Position = UDim2.new(1, -8, 0, 0),
				AnchorPoint = Vector2.new(1, 0),
				Text = "",
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 2,
			})
			textStroke(pct)
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
		pollName.Text = if type(poll.From) == "string" then poll.From else "Admin"
		pollGlobal.Visible = poll.Global == true
		setAvatar(pollAvatar, tonumber(poll.FromId))
		questionLabel.Text = poll.Question
		pollCard.Visible = true
		Ui.sound("Notify")
		typeOut(questionLabel)
	end
	local total = 0
	local best = 0
	for _, v in poll.Votes do
		total += v
		best = math.max(best, v)
	end
	for i, b in optionRows do
		local votes = poll.Votes[i] or 0
		local share = if total > 0 then votes / total else 0
		local fill = b:FindFirstChild("Fill") :: Frame
		TweenService:Create(fill, TweenInfo.new(0.3), { Size = UDim2.fromScale(share, 1) }):Play()
		local winner = poll.Ended and votes == best and best > 0
		fill.BackgroundColor3 = if winner then GOLD:Lerp(Color3.new(0, 0, 0), 0.2) elseif myVote == i then PICKED else FILL
		local pct = b:FindFirstChild("Pct") :: TextLabel
		pct.Text = `{math.floor(share * 100 + 0.5)}%`
		local s = b:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = if myVote == i then WHITE else INK
		end
	end
	pollCard.Visible = true
end

local function tick()
	if banner.timer.Visible then
		banner.timer.Text = Format.time(math.max(0, math.ceil(eventEndsAt - os.time())))
	end
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

	-- Top middle, just under the Roblox top bar.
	stack = make("Frame", {
		Name = "Stack",
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 0, 6),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, stack)
	stackScale = make("UIScale", {}, stack)

	banner = buildBanner()
	buildPoll()

	-- Follow the HUD scale and never run past the screen edges (phones).
	local function fit()
		local s = math.max(0.6, Ui.scale())
		stackScale.Scale = s
		local camera = Workspace.CurrentCamera
		local screen = if camera then camera.ViewportSize.X else 1000
		stack.Size = UDim2.fromOffset(math.floor(math.min(WIDTH, (screen - 32) / s)), 0)
	end
	Ui.onScale(fit)

	Net.event("Broadcast").OnClientEvent:Connect(function(info)
		if type(info) == "table" and type(info.Text) == "string" then
			table.insert(queue, info)
			task.spawn(showNext)
		end
	end)
	Net.event("Poll").OnClientEvent:Connect(function(poll)
		current = poll
		renderPoll()
		tick()
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			tick()
		end
	end)
end

return BroadcastController
