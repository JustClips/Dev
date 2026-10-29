--!strict
-- Hover text for pets and eggs in any pet park: point the mouse at one (or tap it on a
-- phone). Minimal, no panel: name, cash per second (pets) or time left (eggs), weight, and
-- effects (mutation and its cash bonus, Huge, weather speeding up eggs).
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
local PetPassives = require(Shared.PetPassives)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Weights = require(Shared.Config.Weights)
local Weather = require(Shared.Config.Weather)

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

-- The effects line: the mutation and what it does, in its colour.
local function showEffects(lines: { string }, color: Color3?)
	extraLabel.Visible = #lines > 0
	extraLabel.Text = table.concat(lines, " · ")
	extraLabel.TextColor3 = color or Color3.fromRGB(200, 208, 232)
end

local function mutationLine(mutation: string?): (string?, Color3?)
	local def = mutation and Eggs.MutationByName[mutation]
	if not def then
		return nil, nil
	end
	return `{def.Label} x{def.IncomeMult} cash`, def.Color
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
	weightLabel.Text = `{Weights.format(weight)} · {class.Name}`
	weightLabel.TextColor3 = class.Color
	incomeLabel.Text = `+{Format.cash(model:GetAttribute("Income") or 0)}/s`
	incomeLabel.TextColor3 = Color3.fromRGB(124, 255, 140)
	local lines = {}
	local text, color = mutationLine(model:GetAttribute("Mutation"))
	if text then
		table.insert(lines, text)
	end
	if huge then
		table.insert(lines, "HUGE")
		color = color or Color3.fromRGB(255, 200, 60)
	end
	local passive = PetPassives.describe(alienId, huge)
	if passive then
		table.insert(lines, passive)
		color = color or Color3.fromRGB(150, 220, 255)
	end
	showEffects(lines, color)
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
	local left = (model:GetAttribute("EndsAt") or 0) - State.now()
	incomeLabel.Text = if left > 0 then `Ready in {Format.time(left)}` else "Ready to open!"
	incomeLabel.TextColor3 = if left > 0 then Color3.new(1, 1, 1) else Color3.fromRGB(124, 255, 140)
	local lines = {}
	local text, color = mutationLine(model:GetAttribute("Mutation"))
	if text then
		table.insert(lines, text)
	end
	-- Weather speeding up growing eggs right now.
	local weather = Weather.ById[State.server("Weather") or ""]
	if left > 0 and weather and weather.GrowMult and weather.GrowMult > 1 then
		table.insert(lines, `{weather.GrowMult}x growth ({weather.Name})`)
		color = color or weather.Color
	end
	showEffects(lines, color)
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
