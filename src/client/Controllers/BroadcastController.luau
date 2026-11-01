--!strict
-- What admins send to the whole server (AdminService), in the style of the HUD toasts: no
-- box, big Montserrat text with a thick dark outline, the way admin-abuse games put admin
-- messages straight on the screen.
--   * messages and admin events: one line per message in a feed under the top bar (the
--     HUD places the feed, toasts go under it). Each line has the sender's avatar, their
--     name with an [ADMIN] / [ADMIN EVENT] tag, and the text typing itself out letter by
--     letter with soft ticks. Several messages in a row stack (newest at the bottom), each
--     fades on its own. Tap one to clear it.
--   * polls: the question in the same style, at the top of the feed, with solid answer
--     buttons; everyone taps one and sees the votes come in.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local BroadcastController = {}

local C: any
local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local DISPLAY = Font.new(MONTSERRAT, Enum.FontWeight.Heavy)
local BODY = Font.new(MONTSERRAT, Enum.FontWeight.ExtraBold)
local INK = Color3.fromRGB(23, 25, 30)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 200, 60)
local PURPLE = Color3.fromRGB(190, 130, 255)
local SKY = Color3.fromRGB(47, 155, 255)
local GREEN = Color3.fromRGB(61, 220, 90)
local SERVERS = Color3.fromRGB(140, 215, 255)

local MAX_W = 520 -- widest a message line gets (HUD units)
local AVATAR = 50
local MAX_LINES = 4 -- messages on screen at once; older ones make room
local TYPE_RATE = 45 -- letters a second while a message types out
local TYPE_MAX = 1.8 -- seconds; long messages type faster

local feed: Frame
local order = 0

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

-- Outlined text, like the toasts and boost chips.
local function text(parent: Instance, props: { [string]: any }, outline: number?): TextLabel
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		FontFace = DISPLAY,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
	}, parent)
	for k, v in props do
		(label :: any)[k] = v
	end
	make("UIStroke", { Thickness = outline or 3, Color = INK, LineJoinMode = Enum.LineJoinMode.Round }, label)
	return label
end

-- Width a text needs (capped at maxW), so wrapped lines hug their words.
local function widthOf(value: string, font: Font, size: number, maxW: number): number
	local ok, bounds = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = value
		params.Font = font
		params.Size = size
		params.Width = maxW
		return TextService:GetTextBoundsAsync(params)
	end)
	return if ok then math.min(maxW, math.ceil(bounds.X) + 4) else maxW
end

-- Avatar headshots, cached per user.
local headshots: { [number]: string } = {}
local function setAvatar(image: ImageLabel, userId: number?)
	if not userId or userId <= 0 then
		image.Image = AssetLibrary.image("Icon_Event")
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

-- Square avatar: solid colour block with the dark outline (like the HUD buttons).
local function avatarBox(parent: Instance, px: number, color: Color3, userId: number?, order_: number): Frame
	local box = make("Frame", {
		Name = "Avatar",
		Size = UDim2.fromOffset(px, px),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		LayoutOrder = order_,
	}, parent)
	make("UIStroke", { Thickness = 3, Color = INK, LineJoinMode = Enum.LineJoinMode.Miter }, box)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 200, 210)),
	}, box)
	local image = make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop }, box)
	setAvatar(image, userId)
	return box
end

-- Types a label's text out letter by letter. Returns the seconds it takes.
local function typeOut(label: TextLabel): number
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
		while shown < total and label.Parent do
			task.wait()
			local now = math.min(total, math.floor((os.clock() - start) * rate))
			if now ~= shown then
				if math.floor(now / 3) ~= math.floor(shown / 3) and string.sub(label.ContentText, now, now) ~= " " then
					Ui.sound("Click", 1.5 + math.random() * 0.2)
				end
				shown = now
				label.MaxVisibleGraphemes = shown
			end
		end
		label.MaxVisibleGraphemes = -1
	end)
	return total / rate
end

local function fadeOut(root: GuiObject, seconds: number)
	local info = TweenInfo.new(seconds)
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") then
			TweenService:Create(d, info, { TextTransparency = 1 }):Play()
		elseif d:IsA("ImageLabel") then
			TweenService:Create(d, info, { ImageTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		end
	end
	task.wait(seconds)
end

local function relayout()
	if C and C.HudController and C.HudController.Relayout then
		C.HudController:Relayout()
	end
end

---------------------------------------------------------------------------- messages

local lines: { GuiObject } = {}

local function removeLine(line: GuiObject)
	local i = table.find(lines, line)
	if i then
		table.remove(lines, i)
	end
	line:Destroy()
end

local function addLine(info: any)
	local isEvent = info.Kind == "Event"
	local color = if isEvent then PURPLE else GOLD
	order += 1

	local line = make("TextButton", {
		Name = "Message",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 10 + order,
	}, feed)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, line)
	local pop = make("UIScale", { Scale = if Ui.reducedMotion() then 1 else 0.5 }, line)

	local box = avatarBox(line, AVATAR, color, tonumber(info.FromId), 1)
	-- Event: its icon on the avatar's corner.
	local iconName = if type(info.Icon) == "string" then AssetLibrary.image(info.Icon) else ""
	if isEvent and iconName ~= "" then
		make("ImageLabel", {
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.new(1, 10, 1, 10),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			Image = iconName,
			ZIndex = 3,
		}, box)
	end

	local column = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
	}, line)
	make("UIListLayout", { Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder }, column)

	local tag = if type(info.Title) == "string" then info.Title else "ADMIN"
	local from = if type(info.From) == "string" then info.From else "Admin"
	local hex = color:ToHex()
	text(column, {
		Name = "From",
		RichText = true,
		Text = `<font color="#{hex}">[{tag}]</font> {from}{if info.Global
			then ` <font color="#{SERVERS:ToHex()}">· all servers</font>`
			else ""}`,
		TextSize = 17,
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
	}, 2.5)

	local size = if isEvent then 28 else 25
	local bodyW = widthOf(info.Text, DISPLAY, size, MAX_W)
	local body = text(column, {
		Name = "Body",
		Text = info.Text,
		TextColor3 = if isEvent then GOLD else WHITE,
		TextSize = size,
		TextWrapped = true,
		Size = UDim2.fromOffset(bodyW, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
	}, 3)
	body.MaxVisibleGraphemes = 0
	local blurb = if type(info.Blurb) == "string" then info.Blurb else ""
	if blurb ~= "" then
		text(column, {
			Name = "Blurb",
			Text = blurb,
			FontFace = BODY,
			TextSize = 16,
			TextWrapped = true,
			Size = UDim2.fromOffset(widthOf(blurb, BODY, 16, MAX_W), 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 3,
		}, 2.5)
	end

	table.insert(lines, line)
	while #lines > MAX_LINES do
		removeLine(lines[1])
	end

	Ui.sound(if isEvent then "Attention" else "Announce")
	TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local gone = false
	line.Activated:Connect(function()
		if not gone then
			gone = true
			removeLine(line)
		end
	end)
	task.wait(0.15)
	local typing = typeOut(body)
	local stay = math.clamp(tonumber(info.Seconds) or 8, 3, 60)
	task.delay(typing + stay, function()
		if gone or not line.Parent then
			return
		end
		gone = true
		fadeOut(line, 0.35)
		removeLine(line)
	end)
end

------------------------------------------------------------------------------ polls

local pollFrame: Frame
local pollFrom: TextLabel
local pollAvatar: Frame?
local pollHead: Frame
local questionLabel: TextLabel
local optionsFrame: Frame
local timerLabel: TextLabel
local current: any = nil
local myVote: number? = nil
local pollId = -1
local optionRows: { TextButton } = {}

local function buildPoll()
	pollFrame = make("Frame", {
		Name = "Poll",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		LayoutOrder = 0,
	}, feed)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, pollFrame)

	local head = make("Frame", {
		Name = "Head",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 1,
	}, pollFrame)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, head)
	pollHead = head
	local column = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
	}, head)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, column)
	pollFrom = text(column, {
		RichText = true,
		TextSize = 17,
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
	}, 2.5)
	questionLabel = text(column, {
		TextSize = 24,
		TextWrapped = true,
		Size = UDim2.fromOffset(MAX_W - AVATAR - 10, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
	}, 3)

	optionsFrame = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(MAX_W - 40, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
	}, pollFrame)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, optionsFrame)
	make("UIPadding", { PaddingLeft = UDim.new(0, AVATAR + 10), PaddingTop = UDim.new(0, 4) }, optionsFrame)

	timerLabel = text(pollFrame, {
		FontFace = BODY,
		TextSize = 15,
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 3,
	}, 2)
	make("UIPadding", { PaddingLeft = UDim.new(0, AVATAR + 10) }, timerLabel)
end

local function renderPoll()
	local poll = current
	if not poll then
		pollFrame.Visible = false
		relayout()
		return
	end
	if poll.Id ~= pollId then
		pollId = poll.Id
		myVote = nil
		for _, b in optionRows do
			b:Destroy()
		end
		table.clear(optionRows)
		if pollAvatar then
			pollAvatar:Destroy()
		end
		pollAvatar = avatarBox(pollHead, AVATAR, SKY, tonumber(poll.FromId), 1)
		pollFrom.Text = `<font color="#{SKY:ToHex()}">[POLL]</font> {if type(poll.From) == "string" then poll.From else "Admin"}{if poll.Global
			then ` <font color="#{SERVERS:ToHex()}">· all servers</font>`
			else ""}`
		questionLabel.Text = poll.Question
		for i, option in poll.Options do
			-- Solid answer buttons with the HUD outline; the fill shows the vote share.
			local b = make("TextButton", {
				Size = UDim2.new(1, 0, 0, 36),
				BackgroundColor3 = SKY,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Text = "",
				LayoutOrder = i,
				ClipsDescendants = true,
			}, optionsFrame)
			make("UIStroke", {
				Thickness = 3,
				Color = INK,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				LineJoinMode = Enum.LineJoinMode.Miter,
			}, b)
			make("Frame", {
				Name = "Fill",
				Size = UDim2.fromScale(0, 1),
				BackgroundColor3 = Color3.fromRGB(20, 95, 190),
				BorderSizePixel = 0,
			}, b)
			text(b, {
				Size = UDim2.new(1, -80, 1, 0),
				Position = UDim2.fromOffset(10, 0),
				Text = option,
				TextSize = 18,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 2,
			}, 2.5)
			text(b, {
				Name = "Pct",
				Size = UDim2.new(0, 64, 1, 0),
				Position = UDim2.new(1, -8, 0, 0),
				AnchorPoint = Vector2.new(1, 0),
				Text = "",
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 2,
			}, 2.5)
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
		pollFrame.Visible = true
		Ui.sound("Notify")
		typeOut(questionLabel)
	end
	local total, best = 0, 0
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
		b.BackgroundColor3 = if winner then GOLD elseif myVote == i then GREEN else SKY
		fill.BackgroundColor3 = b.BackgroundColor3:Lerp(INK, 0.35)
		local pct = b:FindFirstChild("Pct") :: TextLabel
		pct.Text = `{math.floor(share * 100 + 0.5)}%`
	end
	pollFrame.Visible = true
	relayout()
end

local function tickPoll()
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

function BroadcastController:Init(controllers)
	C = controllers
end

function BroadcastController:Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- Old card-style GUI from earlier builds (LiveSync'd Studio places).
	local old = playerGui:FindFirstChild("Broadcast")
	if old then
		old:Destroy()
	end
	-- The feed rides in the toast layer (same insets as the HUD, above windows); the HUD
	-- places it under the top bar and pushes the toasts below it (HudController layout).
	local layer = playerGui:WaitForChild("ToastLayer", 30) :: ScreenGui?
	if not layer then
		layer = make("ScreenGui", { Name = "ToastLayer", ResetOnSpawn = false, DisplayOrder = 20 }, playerGui)
	end
	feed = make("Frame", {
		Name = "AdminFeed",
		Size = UDim2.fromOffset(MAX_W + 80, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 0, 140),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
	}, layer)
	make("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, feed)
	local scale = make("UIScale", {}, feed)
	Ui.onScale(function(s: number)
		scale.Scale = s
		relayout()
	end)
	feed:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

	buildPoll()

	Net.event("Broadcast").OnClientEvent:Connect(function(info)
		if type(info) == "table" and type(info.Text) == "string" then
			task.spawn(addLine, info)
		end
	end)
	Net.event("Poll").OnClientEvent:Connect(function(poll)
		current = poll
		renderPoll()
		tickPoll()
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			tickPoll()
		end
	end)
end

return BroadcastController
