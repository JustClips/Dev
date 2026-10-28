--!strict
-- Every player's top 3 aliens follow them around (from the "Followers" player attribute
-- the server sets). Rendered locally with a lerp follow and walk/idle animations,
-- only when nearby.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)

local SCALE = 0.8
local RENDER_DISTANCE = 150
local OFFSETS = { Vector3.new(-3.5, 0, 4), Vector3.new(3.5, 0, 4), Vector3.new(0, 0, 7) }
local FLOAT_HEIGHT = 1.5
local MOVING = 1.5

local FollowerController = {}

type Follower = { model: Model, floats: boolean, walk: AnimationTrack?, walking: boolean }
type Entry = { key: string, models: { Follower } }
local entries: { [Player]: Entry } = {}
local folder: Folder

local function clear(player: Player)
	local entry = entries[player]
	if entry then
		for _, follower in entry.models do
			follower.model:Destroy()
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
			local model = AssetLibrary.alien(id, if mutation and mutation ~= "" then mutation else nil)
			model:ScaleTo(SCALE)
			if model:GetAttribute("Placeholder") then
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
					end
				end
			end
			model.Parent = folder
			local meta = AssetLibrary.meta("Alien_" .. id)
			local idle = AssetLibrary.loadTrack(model, "Pet_Idle")
			if idle then
				idle:Play()
			end
			table.insert(models, {
				model = model,
				floats = meta ~= nil and meta.float == true,
				walk = AssetLibrary.loadTrack(model, "Pet_Walk"),
				walking = false,
			})
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
	AssetLibrary.waitReady(45)
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
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			for i, follower in entry.models do
				local model = follower.model
				if not root or not humanoid or (root.Position - focus).Magnitude > RENDER_DISTANCE then
					model:PivotTo(CFrame.new(0, -500, 0))
					continue
				end
				-- Feet on the ground under the player (pivot is at the pet's feet).
				local groundY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
				local offset = root.CFrame:VectorToWorldSpace(OFFSETS[i])
				local lift = if follower.floats then FLOAT_HEIGHT + bob else 0
				local position = Vector3.new(root.Position.X + offset.X, groundY + lift, root.Position.Z + offset.Z)
				local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
				local target = if look.Magnitude > 0.01
					then CFrame.lookAt(position, position + look.Unit)
					else CFrame.new(position)
				local current = model:GetPivot()
				if (current.Position - target.Position).Magnitude > 40 then
					model:PivotTo(target)
				else
					model:PivotTo(current:Lerp(target, alpha))
				end
				local moving = root.AssemblyLinearVelocity.Magnitude > MOVING
				if moving ~= follower.walking and follower.walk then
					follower.walking = moving
					if moving then
						follower.walk:Play(0.2)
					else
						follower.walk:Stop(0.25)
					end
				end
			end
		end
	end)
end

return FollowerController
