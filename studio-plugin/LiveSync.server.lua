--!strict
-- LiveSync Studio plugin.
-- Long-polls the LiveSync server (hosted on Railway) and applies the GitHub
-- repo's scripts into the open place, like `rojo serve` but in the cloud.
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

local TAG = "LiveSync"
local PATH_ATTR = "LiveSyncPath"
local WAIT_SECONDS = 20

type Node = {
	path: { string },
	className: string,
	source: string?,
	value: string?,
	container: boolean?,
}

-- ---------- UI ----------

local toolbar = plugin:CreateToolbar("LiveSync")
local button = toolbar:CreateButton("LiveSync", "Connect to the cloud LiveSync server", "rbxassetid://4458901886")
button.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"LiveSyncWidget",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 320, 190, 280, 170)
)
widget.Title = "LiveSync"

local frame = Instance.new("Frame")
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundColor3 = Color3.fromRGB(46, 46, 46)
frame.BorderSizePixel = 0
frame.Parent = widget

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = frame

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.Parent = frame

local function textBox(order: number, placeholder: string, text: string): TextBox
	local box = Instance.new("TextBox")
	box.LayoutOrder = order
	box.Size = UDim2.new(1, 0, 0, 28)
	box.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	box.BorderSizePixel = 0
	box.TextColor3 = Color3.new(1, 1, 1)
	box.PlaceholderText = placeholder
	box.Text = text
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Font = Enum.Font.Code
	box.TextSize = 14
	box.Parent = frame
	return box
end

local urlBox = textBox(1, "https://your-server.up.railway.app", plugin:GetSetting("url") or "")
local keyBox = textBox(2, "Sync key", plugin:GetSetting("key") or "")

local connectButton = Instance.new("TextButton")
connectButton.LayoutOrder = 3
connectButton.Size = UDim2.new(1, 0, 0, 30)
connectButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
connectButton.BorderSizePixel = 0
connectButton.TextColor3 = Color3.new(1, 1, 1)
connectButton.Font = Enum.Font.SourceSansBold
connectButton.TextSize = 16
connectButton.Text = "Connect"
connectButton.Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.LayoutOrder = 4
statusLabel.Size = UDim2.new(1, 0, 0, 60)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Font = Enum.Font.SourceSans
statusLabel.TextSize = 14
statusLabel.Text = "Not connected"
statusLabel.Parent = frame

local function setStatus(text: string)
	statusLabel.Text = text
end

-- ---------- applying a snapshot ----------

local function keyOf(segs: { string }): string
	return table.concat(segs, "/")
end

local function getRoot(name: string): Instance?
	local ok, service = pcall(function()
		return game:GetService(name :: any)
	end)
	if ok and service then
		return service
	end
	return game:FindFirstChild(name)
end

local function setSource(script: LuaSourceContainer, source: string)
	if (script :: any).Source == source then
		return
	end
	-- UpdateSourceAsync keeps open script tabs in sync; fall back to .Source.
	local ok = pcall(function()
		ScriptEditorService:UpdateSourceAsync(script, function()
			return source
		end)
	end)
	if not ok then
		(script :: any).Source = source
	end
end

local function create(node: Node, parent: Instance): Instance
	local inst = Instance.new(node.className :: any)
	inst.Name = node.path[#node.path]
	inst:SetAttribute(PATH_ATTR, keyOf(node.path))
	CollectionService:AddTag(inst, TAG)
	if node.source then
		setSource(inst :: any, node.source)
	end
	if node.value and inst:IsA("StringValue") then
		inst.Value = node.value
	end
	inst.Parent = parent
	return inst
end

local function apply(nodes: { Node }): (number, number)
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
			else
				warn("[LiveSync] no service named " .. name)
			end
			continue
		end

		local parent = byKey[keyOf(table.move(node.path, 1, #node.path - 1, 1, {}))]
		if not parent then
			continue -- parent was skipped
		end

		local existing = parent:FindFirstChild(name)
		if existing and node.container then
			byKey[key] = existing
			continue
		end

		if existing and existing.ClassName ~= node.className then
			if CollectionService:HasTag(existing, TAG) then
				existing:Destroy()
				existing = nil
			else
				warn(`[LiveSync] {existing:GetFullName()} is a {existing.ClassName} not made by LiveSync; repo wants a {node.className}. Skipping.`)
				continue
			end
		end

		if existing then
			if not CollectionService:HasTag(existing, TAG) then
				CollectionService:AddTag(existing, TAG)
			end
			existing:SetAttribute(PATH_ATTR, key)
			if node.source and (existing :: any).Source ~= node.source then
				setSource(existing :: any, node.source)
				changed += 1
			end
			if node.value and existing:IsA("StringValue") and existing.Value ~= node.value then
				existing.Value = node.value
				changed += 1
			end
			byKey[key] = existing
		else
			byKey[key] = create(node, parent)
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

-- ---------- polling ----------

local session = 0 -- bumps on every connect/disconnect so old loops stop

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
		return false, `HTTP {res.StatusCode}: {res.Body}`
	end
	return true, HttpService:JSONDecode(res.Body)
end

local function disconnect(reason: string?)
	session += 1
	button:SetActive(false)
	connectButton.Text = "Connect"
	connectButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
	setStatus(reason or "Not connected")
end

local function connect()
	local url = string.gsub(string.gsub(urlBox.Text, "%s", ""), "/+$", "")
	local key = string.gsub(keyBox.Text, "%s", "")
	if url == "" or key == "" then
		setStatus("Enter the server URL and sync key first.")
		return
	end
	if not string.match(url, "^https?://") then
		url = "https://" .. url
	end
	plugin:SetSetting("url", url)
	plugin:SetSetting("key", key)

	session += 1
	local mySession = session
	button:SetActive(true)
	connectButton.Text = "Disconnect"
	connectButton.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
	setStatus("Connecting to " .. url)

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
				if string.find(data, "HTTP 401") then
					disconnect("Wrong sync key.")
					break
				end
				setStatus(`Retrying ({failures})... {string.sub(data, 1, 120)}`)
				task.wait(math.min(2 ^ failures, 30))
				continue
			end
			failures = 0
			if data.nodes then
				local recording = ChangeHistoryService:TryBeginRecording("LiveSync update")
				local applied, changed, removed = pcall(apply, data.nodes)
				if recording then
					ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
				end
				version = data.version
				local commit = string.sub(data.commit or "?", 1, 7)
				if applied then
					setStatus(`Synced commit {commit} at {os.date("%H:%M:%S")}\n{changed} changed, {removed} removed`)
					if changed > 0 or removed > 0 then
						print(`[LiveSync] commit {commit}: {changed} changed, {removed} removed`)
					end
				else
					setStatus("Apply failed: " .. tostring(changed))
					warn("[LiveSync] apply failed:", changed)
				end
			elseif data.error then
				setStatus("Server error: " .. tostring(data.error))
			end
		end
	end)
end

connectButton.MouseButton1Click:Connect(function()
	if button:GetActive() or connectButton.Text == "Disconnect" then
		disconnect()
	else
		connect()
	end
end)

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	button:SetActive(connectButton.Text == "Disconnect")
end)

plugin.Unloading:Connect(function()
	session += 1
end)
