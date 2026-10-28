--!strict
-- Alien index (collection book): every alien in a little 3D viewport. Found aliens show
-- in colour with their rarity chip; missing ones are dark silhouettes with a lock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Aliens = require(Shared.Config.Aliens)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)

local SILHOUETTE = Color3.fromRGB(27, 31, 58)
local UNKNOWN_CHIP = Color3.fromRGB(166, 174, 194)

local IndexController = {}

local gui: ScreenGui
local grid: ScrollingFrame
local template: Frame
local countLabel: TextLabel
local lastSignature = ""

-- Frames the camera on the model's front (models face -Z, pivot at the feet).
local function frameModel(viewport: ViewportFrame, model: Model, alienId: string)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local meta = AssetLibrary.meta("Alien_" .. alienId)
	local minY, maxY, width = 0, 2, 2
	if meta then
		minY, maxY = meta.bounds.min.Y, meta.bounds.max.Y
		width = math.max(meta.bounds.max.X - meta.bounds.min.X, meta.bounds.max.Z - meta.bounds.min.Z)
	else
		local _, size = model:GetBoundingBox()
		maxY, width = size.Y, math.max(size.X, size.Z)
	end
	local height = maxY - minY
	local center = Vector3.new(0, (minY + maxY) / 2, 0)
	local distance = math.max(height, width) * 2.4 + 1
	-- Three-quarter view: a little from the side and above.
	local eye = center + Vector3.new(distance * 0.42, height * 0.35, -distance * 0.9)
	camera.CFrame = CFrame.lookAt(eye, center)
end

local function silhouette(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") then
			d.TextureID = ""
			d.Material = Enum.Material.SmoothPlastic
			d.Color = SILHOUETTE
			d.Transparency = 0
		elseif d:IsA("BasePart") then
			d.Color = SILHOUETTE
			d.Material = Enum.Material.SmoothPlastic
		elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
end

local function render()
	local data = State.data
	if not data then
		return
	end
	local found = {}
	for id in data.Index do
		table.insert(found, id)
	end
	table.sort(found)
	local signature = table.concat(found, ",") .. (if AssetLibrary.isReady() then "|3d" else "")
	if signature == lastSignature then
		return
	end
	lastSignature = signature

	for _, child in grid:GetChildren() do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end
	local count = 0
	for i, def in Aliens.List do
		local known = data.Index[def.Id] == true
		if known then
			count += 1
		end
		local rarity = Eggs.ByName[def.Rarity]
		local card = template:Clone()
		card.Name = def.Id
		card.LayoutOrder = i
		card.Visible = true
		local stroke = card:FindFirstChild("Stroke") :: UIStroke?
		if stroke and known then
			stroke.Color = rarity.Color
		end
		;(card:FindFirstChild("Name") :: TextLabel).Text = if known then def.Name else "???"
		local chip = card:FindFirstChild("Rarity") :: Frame
		chip.BackgroundColor3 = if known then rarity.Color else UNKNOWN_CHIP
		local studs = chip:FindFirstChild("Studs") :: ImageLabel?
		if studs then
			studs.ImageColor3 = chip.BackgroundColor3
		end
		Ui.setText(chip, def.Rarity)
		;(card:FindFirstChild("Income") :: TextLabel).Text = if known then `+{Format.cash(def.Income)}/s` else ""
		;(card:FindFirstChild("Lock") :: ImageLabel).Visible = not known

		local viewport = card:FindFirstChild("Viewport") :: ViewportFrame
		local model = AssetLibrary.alien(def.Id)
		model:PivotTo(CFrame.new())
		if not known then
			silhouette(model)
		end
		model.Parent = viewport
		frameModel(viewport, model, def.Id)
		card.Parent = grid
	end
	countLabel.Text = `{count} / {#Aliens.List}`
end

function IndexController:Toggle()
	Ui.toggle("Index")
	render()
end

function IndexController:Init()
	gui = Ui.screen("Index")
	grid = Ui.find(gui, "Window.Grid")
	template = Ui.find(gui, "Window.Grid.Template")
	countLabel = Ui.find(gui, "Window.Count.Label")
end

function IndexController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Index")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Index")
	end)
	State.Changed:Connect(function()
		if gui.Enabled then
			render()
		end
	end)
end

return IndexController
