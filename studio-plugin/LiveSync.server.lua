--!nonstrict
-- LiveSync Studio plugin (v3).
-- Long-polls the LiveSync server (hosted on Railway) and applies the GitHub
-- repo into the open place: scripts, any instance type, properties,
-- attributes and tags. Like `rojo serve`, but in the cloud.
--
-- Install: save this file into your local Plugins folder
-- (Studio: Plugins tab > Plugins Folder), then restart Studio.

local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return -- don't sync into play-test sessions
end

local VERSION = "v3"
local TAG = "LiveSync"
local PATH_ATTR = "LiveSyncPath"
local WAIT_SECONDS = 20

local GREEN = Color3.fromRGB(76, 175, 80)
local YELLOW = Color3.fromRGB(255, 193, 7)
local RED = Color3.fromRGB(229, 83, 75)
local BLUE = Color3.fromRGB(100, 181, 246)
local STATUS_COLORS = { A = GREEN, M = YELLOW, D = RED, R = BLUE }

--------------------------------------------------------------------------------
-- Value decoding (Rojo-style JSON values -> Roblox types)
--------------------------------------------------------------------------------

local function num(v: any): number
	return tonumber(v) or 0
end

local function toColor3(v: any): Color3?
	if type(v) == "string" then
		local ok, c = pcall(Color3.fromHex, v)
		return if ok then c else nil
	elseif type(v) == "table" then
		if v.Color3uint8 then
			local t = v.Color3uint8
			return Color3.fromRGB(num(t[1]), num(t[2]), num(t[3]))
		end
		if type(v[1]) == "number" then
			local r, g, b = num(v[1]), num(v[2]), num(v[3])
			if r > 1 or g > 1 or b > 1 then
				return Color3.fromRGB(r, g, b)
			end
			return Color3.new(r, g, b)
		end
	end
	return nil
end

local function toVector3(v: any): Vector3?
	if type(v) == "table" then
		return Vector3.new(num(v[1]), num(v[2]), num(v[3]))
	elseif type(v) == "number" then
		return Vector3.new(v, v, v)
	end
	return nil
end

local function toVector2(v: any): Vector2?
	if type(v) == "table" then
		return Vector2.new(num(v[1]), num(v[2]))
	end
	return nil
end

local function toUDim(v: any): UDim?
	if type(v) == "table" then
		return UDim.new(num(v[1]), num(v[2]))
	elseif type(v) == "number" then
		return UDim.new(0, v)
	end
	return nil
end

local function toUDim2(v: any): UDim2?
	if type(v) == "table" then
		if type(v[1]) == "table" then
			return UDim2.new(num(v[1][1]), num(v[1][2]), num(v[2][1]), num(v[2][2]))
		elseif #v == 4 then
			return UDim2.new(num(v[1]), num(v[2]), num(v[3]), num(v[4]))
		end
	end
	return nil
end

local function toCFrame(v: any): CFrame?
	if type(v) ~= "table" then
		return nil
	end
	if v.position or v.orientation then
		local p = toVector3(v.position or { 0, 0, 0 }) :: Vector3
		local o = v.orientation
		if type(o) == "table" and type(o[1]) == "table" then
			-- Rojo's explicit form: orientation is a 3x3 rotation matrix (rows)
			return CFrame.new(p.X, p.Y, p.Z, o[1][1], o[1][2], o[1][3], o[2][1], o[2][2], o[2][3], o[3][1], o[3][2], o[3][3])
		end
		o = o or { 0, 0, 0 }
		return CFrame.new(p) * CFrame.fromOrientation(math.rad(num(o[1])), math.rad(num(o[2])), math.rad(num(o[3])))
	end
	if #v == 12 then
		return CFrame.new(table.unpack(v))
	elseif #v == 3 then
		return CFrame.new(num(v[1]), num(v[2]), num(v[3]))
	end
	return nil
end

local function toFont(v: any): Font?
	if type(v) == "string" then
		if string.find(v, "^rbxasset") then
			return Font.new(v)
		end
		local ok, item = pcall(function()
			return (Enum.Font :: any)[v]
		end)
		return if ok and item then Font.fromEnum(item) else nil
	elseif type(v) == "table" and v.family then
		local weight = Enum.FontWeight.Regular
		local style = Enum.FontStyle.Normal
		pcall(function()
			if v.weight then
				weight = (Enum.FontWeight :: any)[v.weight]
			end
			if v.style then
				style = (Enum.FontStyle :: any)[v.style]
			end
		end)
		return Font.new(v.family, weight, style)
	end
	return nil
end

local function toNumberRange(v: any): NumberRange?
	if type(v) == "number" then
		return NumberRange.new(v)
	elseif type(v) == "table" then
		return NumberRange.new(num(v[1]), num(v[2] or v[1]))
	end
	return nil
end

local function toNumberSequence(v: any): NumberSequence?
	if type(v) == "number" then
		return NumberSequence.new(v)
	elseif type(v) == "table" then
		local list = v.keypoints or v
		local points = {}
		for _, k in list do
			if type(k) == "table" then
				local t = k.time or k[1]
				local value = k.value or k[2]
				local env = k.envelope or k[3] or 0
				table.insert(points, NumberSequenceKeypoint.new(num(t), num(value), num(env)))
			end
		end
		if #points >= 2 then
			return NumberSequence.new(points)
		end
	end
	return nil
end

local function toColorSequence(v: any): ColorSequence?
	local single = toColor3(v)
	if single then
		return ColorSequence.new(single)
	end
	if type(v) == "table" then
		local list = v.keypoints or v
		local points = {}
		for _, k in list do
			if type(k) == "table" then
				local c = toColor3(k.color or k[2])
				if c then
					table.insert(points, ColorSequenceKeypoint.new(num(k.time or k[1]), c))
				end
			end
		end
		if #points >= 2 then
			return ColorSequence.new(points)
		end
	end
	return nil
end

local function toRect(v: any): Rect?
	if type(v) == "table" then
		if type(v[1]) == "table" then
			return Rect.new(num(v[1][1]), num(v[1][2]), num(v[2][1]), num(v[2][2]))
		elseif #v == 4 then
			return Rect.new(num(v[1]), num(v[2]), num(v[3]), num(v[4]))
		end
	end
	return nil
end

local function toEnum(enumType: any, v: any): EnumItem?
	if typeof(v) == "EnumItem" then
		return v
	end
	if type(v) == "string" then
		local name = string.match(v, "([^%.]+)$") -- accepts "Neon" or "Enum.Material.Neon"
		local ok, item = pcall(function()
			return enumType[name]
		end)
		return if ok then item else nil
	elseif type(v) == "number" then
		for _, item in enumType:GetEnumItems() do
			if item.Value == v then
				return item
			end
		end
	end
	return nil
end

local CONVERTERS: { [string]: (any) -> any } = {
	Vector3 = toVector3,
	Vector2 = toVector2,
	Color3 = toColor3,
	Color3uint8 = function(v)
		return toColor3({ Color3uint8 = v })
	end,
	UDim = toUDim,
	UDim2 = toUDim2,
	CFrame = toCFrame,
	Font = toFont,
	NumberRange = toNumberRange,
	NumberSequence = toNumberSequence,
	ColorSequence = toColorSequence,
	Rect = toRect,
	BrickColor = function(v)
		return BrickColor.new(v)
	end,
	String = tostring,
	Bool = function(v)
		return v == true
	end,
	Float32 = tonumber,
	Float64 = tonumber,
	Int32 = tonumber,
	Int64 = tonumber,
	Content = tostring,
	ContentId = tostring,
}

-- Rojo's explicit form: { "Vector3": [1, 2, 3] }. Returns (value, true) if v is one.
local function decodeExplicit(v: any, current: any): (any, boolean)
	if type(v) ~= "table" or v[1] ~= nil then
		return nil, false
	end
	local key, inner = next(v)
	if key == nil or next(v, key) ~= nil then
		return nil, false
	end
	if key == "Enum" and typeof(current) == "EnumItem" then
		return toEnum(current.EnumType, inner), true
	end
	local conv = CONVERTERS[key]
	if conv then
		return conv(inner), true
	end
	return nil, false
end

local function decodeProperty(inst: Instance, prop: string, v: any): (any, string?)
	local okCur, current = pcall(function()
		return (inst :: any)[prop]
	end)
	if not okCur then
		return nil, `{inst.ClassName} has no property "{prop}"`
	end
	local explicit, isExplicit = decodeExplicit(v, current)
	if isExplicit then
		return explicit, if explicit == nil then `bad value for {prop}` else nil
	end
	local t = typeof(current)
	local value
	if t == "EnumItem" then
		value = toEnum(current.EnumType, v)
	elseif t == "Instance" or (t == "nil" and type(v) == "table") then
		return nil, `{prop}: instance references aren't supported yet`
	elseif CONVERTERS[t] and type(v) ~= string.lower(t) then
		value = CONVERTERS[t](v)
	else
		value = v
	end
	if value == nil then
		return nil, `bad value for {prop} (expected {t})`
	end
	return value, nil
end

local function decodeAttribute(v: any): any
	local explicit, isExplicit = decodeExplicit(v, nil)
	if isExplicit then
		return explicit
	end
	if type(v) == "table" then
		return nil -- arrays need the explicit form, e.g. { "Vector3": [1,2,3] }
	end
	return v
end

--------------------------------------------------------------------------------
-- Applying a snapshot
--------------------------------------------------------------------------------

type Node = {
	path: { string },
	className: string,
	source: string?,
	value: string?,
	container: boolean?,
	properties: { [string]: any }?,
	attributes: { [string]: any }?,
	tags: { string }?,
}

-- Per-instance memory of what we applied, so removed props/attrs/tags get reset.
local applied = setmetatable({}, { __mode = "k" })
local templates: { [string]: any } = {}

local function template(className: string): Instance?
	if templates[className] == nil then
		local ok, inst = pcall(Instance.new, className)
		templates[className] = if ok then inst else false
	end
	return templates[className] or nil
end

local function keyOf(segs: { string }): string
	return table.concat(segs, "/")
end

local function getRoot(name: string): Instance?
	local ok, service = pcall(function()
		return game:GetService(name)
	end)
	if ok and service then
		return service
	end
	return game:FindFirstChild(name)
end

local function setSource(script: Instance, source: string)
	if (script :: any).Source == source then
		return
	end
	-- UpdateSourceAsync keeps open script tabs in sync; fall back to .Source.
	local ok = false
	if script.Parent ~= nil then
		ok = pcall(function()
			ScriptEditorService:UpdateSourceAsync(script, function()
				return source
			end)
		end)
	end
	if not ok then
		(script :: any).Source = source
	end
end

local warnings: { string } = {}

local function warnOnce(msg: string)
	if #warnings < 50 and not table.find(warnings, msg) then
		table.insert(warnings, msg)
	end
end

-- Applies properties, attributes, tags, source. Returns true if anything changed.
local function applyNode(inst: Instance, node: Node, key: string): boolean
	local spec = HttpService:JSONEncode({
		node.className,
		node.properties or false,
		node.attributes or false,
		node.tags or false,
		node.source or false,
		node.value or false,
	})
	local prev = applied[inst]
	if prev and prev.spec == spec then
		return false
	end
	local record = { spec = spec, props = {}, attrs = {}, tags = {} }

	if node.source and inst:IsA("LuaSourceContainer") then
		setSource(inst, node.source)
	end
	if node.value and inst:IsA("StringValue") then
		inst.Value = node.value
	end

	for prop, raw in node.properties or {} do
		local value, err = decodeProperty(inst, prop, raw)
		if err then
			warnOnce(`{key}: {err}`)
		else
			local ok, setErr = pcall(function()
				if (inst :: any)[prop] ~= value then
					(inst :: any)[prop] = value
				end
			end)
			if ok then
				record.props[prop] = true
			else
				warnOnce(`{key}: can't set {prop}: {setErr}`)
			end
		end
	end
	-- Reset properties that were removed from the file back to their defaults.
	if prev then
		local tmpl = template(inst.ClassName)
		for prop in prev.props do
			if not record.props[prop] and tmpl then
				pcall(function()
					(inst :: any)[prop] = (tmpl :: any)[prop]
				end)
			end
		end
	end

	for name, raw in node.attributes or {} do
		local value = decodeAttribute(raw)
		if value == nil then
			warnOnce(`{key}: attribute {name} needs a typed value like \{"Vector3": [1,2,3]}`)
		else
			local ok, err = pcall(inst.SetAttribute, inst, name, value)
			if ok then
				record.attrs[name] = true
			else
				warnOnce(`{key}: attribute {name}: {err}`)
			end
		end
	end
	if prev then
		for name in prev.attrs do
			if not record.attrs[name] then
				inst:SetAttribute(name, nil)
			end
		end
	end

	for _, tag in node.tags or {} do
		if tag ~= TAG then
			CollectionService:AddTag(inst, tag)
			record.tags[tag] = true
		end
	end
	if prev then
		for tag in prev.tags do
			if not record.tags[tag] then
				CollectionService:RemoveTag(inst, tag)
			end
		end
	end

	inst:SetAttribute(PATH_ATTR, key)
	CollectionService:AddTag(inst, TAG)
	applied[inst] = record
	return true
end

local function apply(nodes: { Node }): (number, number)
	table.clear(warnings)
	local byKey: { [string]: Instance } = {}
	local wanted: { [string]: boolean } = {}
	local changed, removed = 0, 0

	for _, node in nodes do
		local key = keyOf(node.path)
		wanted[key] = true
		local name = node.path[#node.path]

		if #node.path == 1 then
			local root = getRoot(name)
			if root then
				byKey[key] = root
				-- Services: only apply properties, never tag or rename.
				for prop, raw in node.properties or {} do
					local value, err = decodeProperty(root, prop, raw)
					if err then
						warnOnce(`{key}: {err}`)
					else
						pcall(function()
							(root :: any)[prop] = value
						end)
					end
				end
			else
				warnOnce("no service named " .. name)
			end
			continue
		end

		local parent = byKey[keyOf(table.move(node.path, 1, #node.path - 1, 1, {}))]
		if not parent then
			continue -- parent was skipped
		end

		local existing = parent:FindFirstChild(name)
		if existing and node.container and not node.properties then
			byKey[key] = existing
			continue
		end

		if existing and existing.ClassName ~= node.className and not node.container then
			if CollectionService:HasTag(existing, TAG) then
				-- Class changed: make the new instance and move children across.
				local ok, replacement = pcall(Instance.new, node.className)
				if ok then
					replacement.Name = name
					applyNode(replacement, node, key)
					for _, child in existing:GetChildren() do
						child.Parent = replacement
					end
					replacement.Parent = parent
					existing:Destroy()
					byKey[key] = replacement
					changed += 1
				else
					warnOnce(`{key}: unknown class {node.className}`)
				end
			else
				warnOnce(`{existing:GetFullName()} is a {existing.ClassName} not made by LiveSync; repo wants a {node.className}. Skipped.`)
			end
			continue
		end

		if existing then
			if applyNode(existing, node, key) then
				changed += 1
			end
			byKey[key] = existing
		else
			local ok, inst = pcall(Instance.new, node.className)
			if not ok then
				warnOnce(`{key}: unknown class {node.className}`)
				continue
			end
			inst.Name = name
			applyNode(inst, node, key)
			inst.Parent = parent
			byKey[key] = inst
			changed += 1
		end
	end

	-- Remove things LiveSync made earlier that are no longer in the repo.
	for _, inst in CollectionService:GetTagged(TAG) do
		local key = inst:GetAttribute(PATH_ATTR)
		if typeof(key) == "string" and not wanted[key] and inst.Parent then
			inst:Destroy()
			removed += 1
		end
	end

	return changed, removed
end

--------------------------------------------------------------------------------
-- UI helpers (colors follow the Studio theme, light or dark)
--------------------------------------------------------------------------------

local studio = settings().Studio
local bindings = {}

local function themeColor(styleName: string, modifier: string?): Color3
	local ok, color = pcall(function()
		local style = (Enum.StudioStyleGuideColor :: any)[styleName]
		if modifier then
			return studio.Theme:GetColor(style, (Enum.StudioStyleGuideModifier :: any)[modifier])
		end
		return studio.Theme:GetColor(style)
	end)
	return if ok and color then color else Color3.fromRGB(128, 128, 128)
end

local function themed(inst: Instance, prop: string, styleName: string, modifier: string?)
	table.insert(bindings, { inst, prop, styleName, modifier })
	;(inst :: any)[prop] = themeColor(styleName, modifier)
end

studio.ThemeChanged:Connect(function()
	for i = #bindings, 1, -1 do
		local b = bindings[i]
		local ok = pcall(function()
			b[1][b[2]] = themeColor(b[3], b[4])
		end)
		if not ok then
			table.remove(bindings, i)
		end
	end
end)

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius: number)
	return make("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function listLayout(gap: number, horizontal: boolean?)
	return make("UIListLayout", {
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
	})
end

local function padding(t: number, side: number?)
	return make("UIPadding", {
		PaddingTop = UDim.new(0, t),
		PaddingBottom = UDim.new(0, t),
		PaddingLeft = UDim.new(0, side or t),
		PaddingRight = UDim.new(0, side or t),
	})
end

local function label(props: { [string]: any }, style: string?): TextLabel
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = props.Font or Enum.Font.SourceSans,
		TextSize = props.TextSize or 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = props.Size or UDim2.new(1, 0, 0, 0),
		Text = props.Text or "",
		LayoutOrder = props.LayoutOrder or 0,
		RichText = props.RichText or false,
		Parent = props.Parent,
	})
	if props.TextColor3 then
		l.TextColor3 = props.TextColor3
	else
		themed(l, "TextColor3", style or "MainText")
	end
	return l
end

local function button(text: string, primary: boolean, parent: Instance, order: number): TextButton
	local b = make("TextButton", {
		Text = text,
		Font = Enum.Font.SourceSansBold,
		TextSize = 15,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, 32),
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	}, { corner(4) })
	if primary then
		themed(b, "BackgroundColor3", "DialogMainButton")
		themed(b, "TextColor3", "DialogMainButtonText")
	else
		themed(b, "BackgroundColor3", "Button")
		themed(b, "TextColor3", "ButtonText")
	end
	return b
end

local function input(placeholder: string, parent: Instance, order: number): TextBox
	local box = make("TextBox", {
		PlaceholderText = placeholder,
		Text = "",
		ClearTextOnFocus = false,
		Font = Enum.Font.Code,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 32),
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	}, { corner(4), padding(0, 8) })
	local stroke = make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = box })
	themed(stroke, "Color", "InputFieldBorder")
	themed(box, "BackgroundColor3", "InputFieldBackground")
	themed(box, "TextColor3", "MainText")
	themed(box, "PlaceholderColor3", "DimmedText")
	return box
end

local function badge(text: string, color: Color3, parent: Instance, order: number)
	return make("TextLabel", {
		Text = text,
		Font = Enum.Font.SourceSansBold,
		TextSize = 12,
		TextColor3 = color,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.85,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		LayoutOrder = order,
		Parent = parent,
	}, { corner(4), padding(2, 6) })
end

--------------------------------------------------------------------------------
-- UI layout
--------------------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("LiveSync")
local toolbarButton = toolbar:CreateButton("LiveSync", "Open the LiveSync panel", "rbxassetid://4458901886")
toolbarButton.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"LiveSyncWidget",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 360, 520, 280, 320)
)
widget.Title = "LiveSync"

local root = make("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Parent = widget })
themed(root, "BackgroundColor3", "MainBackground")

-- ----- login view -----

local loginView = make("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = root,
}, { listLayout(8), padding(16) })

label({ Text = "LiveSync", Font = Enum.Font.SourceSansBold, TextSize = 22, LayoutOrder = 1, Parent = loginView })
label({ Text = "Live sync from GitHub into this place through your cloud server. Your login is saved, so you only do this once.", LayoutOrder = 2, Parent = loginView }, "SubText")
label({ Text = "SERVER URL", Font = Enum.Font.SourceSansBold, TextSize = 12, LayoutOrder = 3, Parent = loginView }, "DimmedText")
local urlBox = input("https://your-server.up.railway.app", loginView, 4)
label({ Text = "SYNC KEY", Font = Enum.Font.SourceSansBold, TextSize = 12, LayoutOrder = 5, Parent = loginView }, "DimmedText")
local keyBox = input("Paste your sync key", loginView, 6)
local connectButton = button("Connect", true, loginView, 7)
local loginError = label({ Text = "", LayoutOrder = 8, TextColor3 = RED, Parent = loginView })

-- The key is shown as dots unless the box is focused.
local realKey = plugin:GetSetting("key") or ""
local function maskKey()
	keyBox.Text = if realKey == "" then "" else string.rep("•", math.min(#realKey, 24))
end
keyBox.Focused:Connect(function()
	keyBox.Text = realKey
end)
keyBox.FocusLost:Connect(function()
	realKey = string.gsub(keyBox.Text, "%s", "")
	maskKey()
end)
urlBox.Text = plugin:GetSetting("url") or ""
maskKey()

-- ----- connected view -----

local mainView = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = root })

local header = make("Frame", { Size = UDim2.new(1, 0, 0, 84), BorderSizePixel = 0, Parent = mainView }, { padding(10, 12) })
themed(header, "BackgroundColor3", "Titlebar")
local divider = make("Frame", { Size = UDim2.new(1, 24, 0, 1), Position = UDim2.new(0, -12, 1, 9), BorderSizePixel = 0, Parent = header })
themed(divider, "BackgroundColor3", "Border")

local dot = make("Frame", { Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(0, 5), BackgroundColor3 = YELLOW, BorderSizePixel = 0, Parent = header }, { corner(5) })
local statusText = make("TextLabel", {
	Text = "Connecting…",
	Font = Enum.Font.SourceSansBold,
	TextSize = 16,
	BackgroundTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.fromOffset(18, 0),
	Size = UDim2.new(1, -18, 0, 20),
	Parent = header,
})
themed(statusText, "TextColor3", "MainText")
local hostText = make("TextLabel", {
	Text = "",
	Font = Enum.Font.SourceSans,
	TextSize = 13,
	BackgroundTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.fromOffset(18, 20),
	Size = UDim2.new(1, -18, 0, 16),
	Parent = header,
})
themed(hostText, "TextColor3", "DimmedText")

local actions = make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = header }, { listLayout(6, true) })
local pauseButton = button("Pause", false, actions, 1)
pauseButton.Size = UDim2.new(0.5, -3, 0, 26)
local logoutButton = button("Log out", false, actions, 2)
logoutButton.Size = UDim2.new(0.5, -3, 0, 26)

local body = make("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 84),
	Size = UDim2.new(1, 0, 1, -84),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = mainView,
}, { listLayout(8), padding(12) })

local syncInfo = label({ Text = "", LayoutOrder = 1, RichText = true, Parent = body }, "SubText")
local warningBox = label({ Text = "", LayoutOrder = 2, TextColor3 = YELLOW, TextSize = 14, Parent = body })
warningBox.Visible = false
label({ Text = "HISTORY", Font = Enum.Font.SourceSansBold, TextSize = 12, LayoutOrder = 3, Parent = body }, "DimmedText")
local historyList = make("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = 4,
	Parent = body,
}, { listLayout(8) })

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local history = {}
local inStudioCommit: string? = nil
local appliedLog = {}
local lastCheckAt: string? = nil
local instanceCount = 0

local function relativeTime(iso: string): string
	local ok, dt = pcall(DateTime.fromIsoDate, iso)
	if not ok or not dt then
		return iso
	end
	local secs = os.time() - dt.UnixTimestamp
	local rel
	if secs < 60 then
		rel = "just now"
	elseif secs < 3600 then
		rel = `{secs // 60}m ago`
	elseif secs < 86400 then
		rel = `{secs // 3600}h ago`
	else
		rel = `{secs // 86400}d ago`
	end
	return `{rel} · {dt:FormatLocalTime("MMM D, h:mm A", "en-us")}`
end

local function escape(s: string): string
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	return s
end

-- Commit body without trailer lines such as "Co-Authored-By: ...".
local function commitBody(lines: { string }): string
	local kept = {}
	for i = 2, #lines do
		local line = lines[i]
		if not string.find(line, "^[%u][%w%-]+: ") then
			table.insert(kept, line)
		end
	end
	local text = table.concat(kept, "\n")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	return text
end

local function renderHistory()
	for _, child in historyList:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	if #history == 0 then
		label({ Text = "No commits yet.", Parent = historyList }, "DimmedText")
		return
	end
	for i, c in history do
		local card = make("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = historyList,
		}, { corner(6), padding(10), listLayout(4) })
		themed(card, "BackgroundColor3", "Titlebar")
		local isCurrent = c.sha == inStudioCommit
		if isCurrent then
			make("UIStroke", { Color = GREEN, Thickness = 1, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card })
		end

		local lines = string.split(c.message or "", "\n")
		label({ Text = escape(lines[1] or ""), RichText = true, Font = Enum.Font.SourceSansBold, TextSize = 15, LayoutOrder = 1, Parent = card })
		local rest = commitBody(lines)
		if rest ~= "" then
			label({ Text = rest, TextSize = 14, LayoutOrder = 2, Parent = card }, "SubText")
		end

		local meta = make("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 3,
			Parent = card,
		}, { listLayout(6, true) })
		local shaLabel = make("TextLabel", {
			Text = string.sub(c.sha, 1, 7),
			Font = Enum.Font.Code,
			TextSize = 13,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.new(),
			LayoutOrder = 1,
			Parent = meta,
		})
		themed(shaLabel, "TextColor3", "LinkText")
		local who = make("TextLabel", {
			Text = `{c.author} · {relativeTime(c.date)}`,
			Font = Enum.Font.SourceSans,
			TextSize = 13,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.new(),
			LayoutOrder = 2,
			Parent = meta,
		})
		themed(who, "TextColor3", "DimmedText")

		local log = appliedLog[c.sha]
		if isCurrent or log then
			local badges = make("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 4,
				Parent = card,
			}, { listLayout(6, true) })
			if isCurrent then
				badge("● IN STUDIO", GREEN, badges, 1)
			end
			if log then
				badge(`Applied {log.at} · {log.changed} changed, {log.removed} removed`, BLUE, badges, 2)
			end
		end

		if c.files and #c.files > 0 then
			local shown = math.min(#c.files, 8)
			local fileLines = {}
			for f = 1, shown do
				local file = c.files[f]
				local color = STATUS_COLORS[file.status] or YELLOW
				table.insert(fileLines, `<font color="#{color:ToHex()}"><b>{file.status}</b></font>  {escape(file.path)}`)
			end
			if #c.files > shown then
				table.insert(fileLines, `… and {#c.files - shown} more`)
			end
			label({ Text = table.concat(fileLines, "\n"), RichText = true, Font = Enum.Font.Code, TextSize = 12, LayoutOrder = 5, Parent = card }, "SubText")
		end
	end
end

local function renderInfo()
	local parts = {}
	if inStudioCommit then
		table.insert(parts, `In Studio: <b>{string.sub(inStudioCommit, 1, 7)}</b>`)
	end
	table.insert(parts, `{instanceCount} synced instances`)
	if lastCheckAt then
		table.insert(parts, `checked {lastCheckAt}`)
	end
	syncInfo.Text = table.concat(parts, "  ·  ")
	if #warnings > 0 then
		warningBox.Visible = true
		warningBox.Text = "⚠ " .. table.concat(warnings, "\n⚠ ")
	else
		warningBox.Visible = false
	end
end

local function setStatus(state: string, text: string)
	dot.BackgroundColor3 = if state == "connected" then GREEN elseif state == "error" then RED else YELLOW
	statusText.Text = text
end

local function showView(connectedView: boolean)
	loginView.Visible = not connectedView
	mainView.Visible = connectedView
	toolbarButton:SetActive(connectedView)
end

-- Refresh "5m ago" labels now and then.
task.spawn(function()
	while true do
		task.wait(30)
		if mainView.Visible and widget.Enabled then
			renderHistory()
		end
	end
end)

--------------------------------------------------------------------------------
-- Connection
--------------------------------------------------------------------------------

local session = 0 -- bumps on every connect/disconnect so old loops stop
local connected = false

local function request(url: string, key: string, since: string): (boolean, any)
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = `{url}/api/state?since={since}&wait={WAIT_SECONDS}`,
			Method = "GET",
			Headers = { ["X-Sync-Key"] = key },
		})
	end)
	if not ok then
		return false, tostring(res)
	end
	if not res.Success then
		return false, `HTTP {res.StatusCode}: {string.sub(res.Body, 1, 200)}`
	end
	local okJson, data = pcall(function()
		return HttpService:JSONDecode(res.Body)
	end)
	if not okJson then
		return false, "server sent bad JSON"
	end
	return true, data
end

-- Stops syncing. Keeps the saved login unless `forget` is true.
local function disconnect(reason: string?, forget: boolean?)
	session += 1
	connected = false
	plugin:SetSetting("autoConnect", false)
	if forget then
		realKey = ""
		plugin:SetSetting("key", "")
		maskKey()
	end
	showView(false)
	loginError.Text = reason or ""
end

local function connect()
	local url = string.gsub(urlBox.Text, "%s", "")
	url = string.gsub(url, "/+$", "")
	local key = realKey
	if url == "" or key == "" then
		loginError.Text = "Enter the server URL and sync key first."
		return
	end
	if not string.match(url, "^https?://") then
		url = "https://" .. url
	end
	urlBox.Text = url
	plugin:SetSetting("url", url)
	plugin:SetSetting("key", key)
	loginError.Text = ""

	session += 1
	connected = true
	local mySession = session
	showView(true)
	hostText.Text = string.gsub(url, "^https?://", "")
	setStatus("connecting", "Connecting…")
	print(`[LiveSync] {VERSION} connecting to {url}`)

	-- Studio asks once per domain before a plugin may use HTTP. Until that popup
	-- is answered the request just waits, so say so if nothing comes back.
	task.delay(6, function()
		if session == mySession and statusText.Text == "Connecting…" then
			setStatus("connecting", "Waiting for Studio's HTTP permission popup")
		end
	end)

	task.spawn(function()
		local version = ""
		local failures = 0
		while session == mySession do
			local ok, data = request(url, key, version)
			if session ~= mySession then
				break
			end
			if not ok then
				failures += 1
				warn("[LiveSync] request failed:", data)
				if string.find(data, "HTTP 401") then
					disconnect("Wrong sync key.", false)
					break
				end
				setStatus("retrying", `Reconnecting ({failures})…`)
				syncInfo.Text = escape(string.sub(data, 1, 200))
				task.wait(math.min(2 ^ failures, 30))
				continue
			end
			if failures > 0 or statusText.Text ~= "Connected" then
				failures = 0
				plugin:SetSetting("autoConnect", true)
				setStatus("connected", "Connected")
			end
			lastCheckAt = os.date("%H:%M:%S")
			if data.nodes then
				local recording = ChangeHistoryService:TryBeginRecording("LiveSync update")
				local okApply, changed, removed = pcall(apply, data.nodes)
				if recording then
					ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
				end
				version = data.version
				history = data.history or history
				instanceCount = #data.nodes
				for _, w in data.warnings or {} do
					warnOnce(w)
				end
				if okApply then
					inStudioCommit = data.commit
					if changed > 0 or removed > 0 then
						appliedLog[data.commit or "?"] = { at = os.date("%H:%M:%S"), changed = changed, removed = removed }
						print(`[LiveSync] {string.sub(data.commit or "?", 1, 7)}: {changed} changed, {removed} removed`)
					end
					for _, w in warnings do
						warn("[LiveSync]", w)
					end
				else
					warnOnce("Apply failed: " .. tostring(changed))
					warn("[LiveSync] apply failed:", changed)
				end
				renderHistory()
			elseif data.error then
				warnOnce("Server: " .. tostring(data.error))
			end
			renderInfo()
		end
	end)
end

local function safeConnect()
	local ok, err = pcall(connect)
	if not ok then
		showView(false)
		loginError.Text = "Error: " .. tostring(err)
		warn("[LiveSync] connect failed:", err)
	end
end

connectButton.MouseButton1Click:Connect(safeConnect)
pauseButton.MouseButton1Click:Connect(function()
	disconnect("Paused. Your login is saved; press Connect to resume.", false)
end)
logoutButton.MouseButton1Click:Connect(function()
	disconnect("Logged out.", true)
end)

toolbarButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	toolbarButton:SetActive(connected)
end)

plugin.Unloading:Connect(function()
	session += 1
end)

print(`[LiveSync] plugin loaded ({VERSION})`)

-- Reconnect automatically when a saved login exists (first run of v3 included).
local auto = plugin:GetSetting("autoConnect")
if auto ~= false and urlBox.Text ~= "" and realKey ~= "" then
	task.defer(safeConnect)
end
