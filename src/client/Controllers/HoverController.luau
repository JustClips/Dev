--!strict
-- Hover card for pets and eggs in any pet park: point the mouse at one (or tap it on a
-- phone) to see its name, weight and size class, cash per second, and for eggs the time
-- left and the pet weights it can hatch.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Weights = require(Shared.Config.Weights)

local TAP_SECONDS = 3

local HoverController = {}

local card: Frame
local nameLabel: TextLabel
local weightLabel: TextLabel
local incomeLabel: TextLabel
local extraLabel: TextLabel
local tapUntil = 0
local tapPoint: Vector2? = nil
local lastTarget: Instance? = nil

-- The pet or egg model under a screen point, if any.
local function targetAt(point: Vector2): Model?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 250, params)
	local node: Instance? = hit and hit.Instance
	while node and node ~= Workspace do
		if node:IsA("Model") and (node:GetAttribute("AlienId") ~= nil or node:GetAttribute("EndsAt") ~= nil) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function showPet(model: Model)
	local alienId = model:GetAttribute("AlienId") :: string
	local def = Aliens.ById[alienId]
	if not def then
		return false
	end
	local rarity = Eggs.ByName[def.Rarity]
	local huge = model:GetAttribute("Huge") == true
	nameLabel.Text = (if huge then "HUGE " else "") .. AlienModel.displayName(alienId, model:GetAttribute("Mutation"))
	nameLabel.TextColor3 = rarity.Color
	local mult = model:GetAttribute("WeightMult") or 1
	local class = Weights.classFor(mult)
	local weight = model:GetAttribute("Weight") or Weights.petKg(def.Rarity)
	weightLabel.Text = `{Weights.format(weight)} · {class.Name} (x{string.format("%.2f", mult)} cash)`
	weightLabel.TextColor3 = class.Color
	incomeLabel.Text = `+{Format.cash(model:GetAttribute("Income") or 0)}/s`
	extraLabel.Text = `{def.Rarity}{if huge then " · Huge x" .. Aliens.HugeIncomeMult else ""}`
	return true
end

local function showEgg(model: Model)
	local rarityName = model:GetAttribute("Rarity") :: string
	local rarity = Eggs.ByName[rarityName]
	if not rarity then
		return false
	end
	local size = model:GetAttribute("Size") or "Normal"
	local weight = model:GetAttribute("Weight") or Weights.eggKg(rarityName)
	local class = Weights.ByName[size] or Weights.Classes[1]
	nameLabel.Text = `{if size ~= "Normal" then size .. " " else ""}{rarityName} Egg`
	nameLabel.TextColor3 = rarity.Color
	weightLabel.Text = `{Weights.format(weight)} · {class.Name}`
	weightLabel.TextColor3 = class.Color
	local endsAt = model:GetAttribute("EndsAt") or 0
	local left = endsAt - State.now()
	local grown = Eggs.progress(model:GetAttribute("StartsAt"), endsAt, Workspace:GetServerTimeNow())
	incomeLabel.Text = if left > 0 then `Grown {math.floor(grown * 100)}% · ready in {Format.time(left)}` else "Ready to open!"
	local low, high = Weights.petRange(rarityName, rarityName, weight)
	extraLabel.Text = `Pets: {Weights.format(low)} - {Weights.format(high)}`
	return true
end

local function render(point: Vector2?)
	local target = if point then targetAt(point) else nil
	local shown = false
	if target then
		shown = if target:GetAttribute("AlienId") then showPet(target) else showEgg(target)
	end
	card.Visible = shown
	if shown and point then
		local scale = Ui.scale()
		local view = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1000, 800)
		local width = card.AbsoluteSize.X
		local x = point.X + 18
		if x + width > view.X - 8 then
			x = point.X - width - 18
		end
		card.Position = UDim2.fromOffset(x, point.Y + 12 * scale)
	end
	if target ~= lastTarget then
		lastTarget = target
	end
end

function HoverController:Init()
	local gui = Ui.screen("Hover")
	card = Ui.find(gui, "Card")
	nameLabel = Ui.find(card, "Name")
	weightLabel = Ui.find(card, "Weight")
	incomeLabel = Ui.find(card, "Income")
	extraLabel = Ui.find(card, "Extra")
end

function HoverController:Start()
	UserInputService.InputEnded:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		tapPoint = Vector2.new(input.Position.X, input.Position.Y)
		tapUntil = os.clock() + TAP_SECONDS
	end)
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.05 then
			return
		end
		accumulator = 0
		if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
			render(UserInputService:GetMouseLocation())
		elseif os.clock() < tapUntil then
			render(tapPoint)
		else
			card.Visible = false
		end
	end)
end

return HoverController
