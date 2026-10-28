--!strict
-- Every player's top 3 aliens float behind them (from the "Followers" player attribute
-- the server sets). Rendered locally with a simple lerp follow, only when nearby.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)

local SCALE = 0.6
local RENDER_DISTANCE = 150
local OFFSETS = { Vector3.new(-3.5, 1.5, 4), Vector3.new(3.5, 1.5, 4), Vector3.new(0, 3, 6) }

local FollowerController = {}

type Entry = { key: string, models: { Model } }
local entries: { [Player]: Entry } = {}
local folder: Folder

local function clear(player: Player)
	local entry = entries[player]
	if entry then
		for _, model in entry.models do
			model:Destroy()
		end
		entries[player] = nil
	end
end

local function rebuild(player: Player)
	local key = player:GetAttribute("Followers") or ""
	local entry = entries[player]
	if entry and entry.key == key then
		return
	end
	clear(player)
	local models = {}
	for spec in string.gmatch(key, "[^,]+") do
		local id, mutation = string.match(spec, "^([^:]+):?(.*)$")
		if id then
			local model = AlienModel.build(id, if mutation and mutation ~= "" then mutation else nil)
			model:ScaleTo(SCALE)
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
				end
			end
			model.Parent = folder
			table.insert(models, model)
		end
	end
	entries[player] = { key = key, models = models }
end

local function watch(player: Player)
	rebuild(player)
	player:GetAttributeChangedSignal("Followers"):Connect(function()
		rebuild(player)
	end)
end

function FollowerController:Init()
	folder = Instance.new("Folder")
	folder.Name = "Followers"
	folder.Parent = Workspace
end

function FollowerController:Start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clear)

	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local focus = if camera then camera.Focus.Position else Vector3.zero
		local alpha = math.min(1, dt * 6)
		local bob = math.sin(os.clock() * 3) * 0.4
		for player, entry in entries do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			for i, model in entry.models do
				if not root or (root.Position - focus).Magnitude > RENDER_DISTANCE then
					model:PivotTo(CFrame.new(0, -500, 0))
					continue
				end
				local target = root.CFrame * CFrame.new(OFFSETS[i] + Vector3.new(0, bob, 0))
				local current = model:GetPivot()
				if (current.Position - target.Position).Magnitude > 40 then
					model:PivotTo(target)
				else
					model:PivotTo(current:Lerp(target, alpha))
				end
			end
		end
	end)
end

return FollowerController
