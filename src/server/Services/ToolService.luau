--!strict
-- Tool ladder: buying tier N+1, the tool in hand, vehicle rentals and the vehicle itself.
-- Vehicle tiers (7-9): on foot you sweep with the best hand tool; in the vehicle you get
-- the vehicle's radius and power. Driving is done by the client (it owns the physics).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Tools = require(Shared.Config.Tools)

local ToolService = {}

local S: any

function ToolService:GetEffectiveTier(player: Player): number
	local session = S.DataService:GetSession(player)
	if not session then
		return 1
	end
	return math.max(session.Data.ToolTier, session.Runtime.RentedTier or 0)
end

function ToolService:GetCapacity(player: Player): number
	return Tools.get(ToolService:GetEffectiveTier(player)).Capacity
end

function ToolService:IsInVehicle(player: Player): boolean
	local session = S.DataService:GetSession(player)
	local vehicle = session and session.Runtime.Vehicle
	if not vehicle or not vehicle.Parent then
		return false
	end
	local seat = vehicle:FindFirstChild("Seat") :: VehicleSeat?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return seat ~= nil and humanoid ~= nil and seat.Occupant == humanoid
end

-- The stats used for sweeping right now.
function ToolService:GetSweepTool(player: Player)
	local tier = ToolService:GetEffectiveTier(player)
	if Tools.get(tier).IsVehicle and not ToolService:IsInVehicle(player) then
		tier = math.min(tier, Tools.MaxHandTier)
	end
	return Tools.get(tier)
end

local function buildTool(def): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = `Hold to sweep (radius {def.Radius})`
	tool:SetAttribute("SweepTool", true)
	tool:SetAttribute("Tier", def.Tier)

	local scale = def.Scale
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, 3.2 * scale)
	handle.Color = Color3.fromRGB(235, 235, 240)
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.4 * scale, 0.5 * scale, 0.7 * scale)
	head.Color = def.Color
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.Massless = true
	head.CFrame = handle.CFrame * CFrame.new(0, 0, -1.6 * scale)
	head.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = head

	-- Point the head down and forward, like holding a broom.
	tool.Grip = CFrame.new(0, 0, 0.6 * scale) * CFrame.Angles(math.rad(60), 0, 0)
	return tool
end

local function giveTool(player: Player, equip: boolean)
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not character or not backpack then
		return
	end
	for _, container in { backpack, character } do
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("SweepTool") then
				child:Destroy()
			end
		end
	end
	local def = Tools.get(math.min(ToolService:GetEffectiveTier(player), Tools.MaxHandTier))
	local tool = buildTool(def)
	tool.Parent = backpack
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if equip and humanoid then
		humanoid:EquipTool(tool)
	end
end

local function destroyVehicle(player: Player)
	local session = S.DataService:GetSession(player)
	if session and session.Runtime.Vehicle then
		session.Runtime.Vehicle:Destroy()
		session.Runtime.Vehicle = nil
		S.StateService:Mark(player)
	end
end

local function buildVehicle(player: Player, def): Model
	local s = def.Scale
	local model = Instance.new("Model")
	model.Name = player.Name .. "_" .. def.Id
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(6 * s, 1.6 * s, 9 * s)
	chassis.Color = def.Color
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local function attach(part: BasePart, offset: CFrame)
		part.CFrame = chassis.CFrame * offset
		part.Massless = true
		part.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassis
		weld.Part1 = part
		weld.Parent = part
	end

	local seat = Instance.new("VehicleSeat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.Color = Color3.fromRGB(40, 40, 50)
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = def.VehicleSpeed or 30
	seat:SetAttribute("Speed", def.VehicleSpeed or 30)
	seat:SetAttribute("OwnerUserId", player.UserId)
	attach(seat, CFrame.new(0, 0.8 * s + 0.5, 1 * s))

	local brush = Instance.new("Part")
	brush.Name = "Brush"
	brush.Shape = Enum.PartType.Cylinder
	brush.Size = Vector3.new(6.5 * s, 1.4 * s, 1.4 * s)
	brush.Color = Color3.fromRGB(255, 230, 120)
	brush.Material = Enum.Material.Fabric
	brush.CanCollide = false
	attach(brush, CFrame.new(0, -0.3 * s, -5 * s))

	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local wheel = Instance.new("Part")
			wheel.Name = "Wheel"
			wheel.Shape = Enum.PartType.Cylinder
			wheel.Size = Vector3.new(0.8 * s, 2 * s, 2 * s)
			wheel.Color = Color3.fromRGB(30, 30, 35)
			wheel.CanCollide = false
			attach(wheel, CFrame.new(x * 3.1 * s, -0.4 * s, z * 3 * s))
		end
	end

	-- Keeps the vehicle upright; the driving client turns it by updating the CFrame.
	local rootAttachment = Instance.new("Attachment")
	rootAttachment.Name = "Root"
	rootAttachment.Parent = chassis
	local align = Instance.new("AlignOrientation")
	align.Name = "Upright"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = rootAttachment
	align.MaxTorque = math.huge
	align.Responsiveness = 40
	align.Parent = chassis
	return model
end

local function spawnVehicle(player: Player): (boolean, string?)
	local session = S.DataService:GetSession(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not session or not humanoid or not root or humanoid.Health <= 0 then
		return false, "Not ready"
	end
	local def = Tools.get(ToolService:GetEffectiveTier(player))
	if not def.IsVehicle then
		return false, "You need a vehicle first"
	end
	destroyVehicle(player)
	local model = buildVehicle(player, def)
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local yaw = if look.Magnitude > 0.01 then CFrame.lookAt(Vector3.zero, look.Unit) else CFrame.identity
	model:PivotTo(CFrame.new(root.Position + Vector3.new(0, 3 * def.Scale, 0)) * yaw)
	local align = model.PrimaryPart:FindFirstChild("Upright") :: AlignOrientation
	align.CFrame = yaw
	model.Parent = Workspace
	session.Runtime.Vehicle = model
	local chassis = model.PrimaryPart :: BasePart
	chassis:SetNetworkOwner(player)

	local seat = model:FindFirstChild("Seat") :: VehicleSeat
	seat:Sit(humanoid)
	-- Leaving the seat puts the vehicle away.
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		S.StateService:Mark(player)
		if seat.Occupant == nil then
			task.delay(1, function()
				if seat.Occupant == nil and session.Runtime.Vehicle == model then
					destroyVehicle(player)
				end
			end)
		end
	end)
	S.StateService:Mark(player)
	return true, nil
end

-- Sets the owned tier (bought or skipped via product). Fills every tier below it.
function ToolService:SetTier(player: Player, tier: number)
	local data = S.DataService:GetData(player)
	if not data then
		return
	end
	tier = math.clamp(tier, 1, Tools.MaxTier)
	data.ToolTier = tier
	data.OwnedTools = {}
	for t = 1, tier do
		data.OwnedTools[t] = true
	end
	giveTool(player, true)
	if tier >= 2 then
		S.AnalyticsService:Funnel(player, "FirstTool")
	end
	S.StateService:Mark(player)
end

function ToolService:Rent(player: Player, tier: number)
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	session.Runtime.RentedTier = math.max(session.Runtime.RentedTier or 0, tier)
	giveTool(player, false)
	S.StateService:Mark(player)
	Net.fire("Notify", player, `{Tools.get(tier).Name} unlocked for this run! Press Drive.`, "Good")
end

function ToolService:ResetForRebirth(player: Player)
	local session = S.DataService:GetSession(player)
	if not session then
		return
	end
	session.Runtime.RentedTier = 0
	destroyVehicle(player)
	ToolService:SetTier(player, 1)
end

local function buyNext(player: Player): (boolean, string)
	local data = S.DataService:GetData(player)
	if not data then
		return false, "Still loading"
	end
	local nextTier = data.ToolTier + 1
	if nextTier > Tools.MaxTier then
		return false, "You have the best tool!"
	end
	local def = Tools.get(nextTier)
	if BigNum.lt(data.Cash, def.Price) then
		return false, `Need {Format.cash(def.Price)}`
	end
	data.Cash = BigNum.sub(data.Cash, def.Price)
	S.AnalyticsService:Sink(player, def.Price, Enum.AnalyticsEconomyTransactionType.Shop, "Tool_" .. def.Id)
	ToolService:SetTier(player, nextTier)
	S.OfferService:OnToolBought(player)
	return true, `Got the {def.Name}!`
end

function ToolService:Init(services)
	S = services
	Net.onInvoke("BuyNextTool", buyNext)
	Net.onInvoke("ToggleVehicle", function(player)
		local session = S.DataService:GetSession(player)
		if session and session.Runtime.Vehicle then
			destroyVehicle(player)
			return true, nil
		end
		return spawnVehicle(player)
	end)
	Net.onInvoke("EquipTool", function(player)
		giveTool(player, true)
		return true
	end)
	S.BaseService.CharacterReady:Connect(function(player: Player, character: Model)
		destroyVehicle(player)
		character:WaitForChild("Humanoid", 10)
		giveTool(player, true)
	end)
	S.DataService.ProfileReleasing:Connect(function(player)
		destroyVehicle(player)
	end)
end

function ToolService:Start()
	Players.PlayerRemoving:Connect(function(player)
		destroyVehicle(player)
	end)
end

return ToolService
