--!strict
-- Egg showcase in the hub: every egg on its own plinth with its name, slowly turning, so
-- players (and Dev) can see all the egg models. Rigged eggs play their idle animation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Eggs = require(Shared.Config.Eggs)

local ShowcaseService = {}

-- A row across the field, south of the market hall, facing the bases on both sides.
local CENTRE = Vector3.new(0, 0, 72)
local SPACING = 13
local EGG_SCALE = 1.3
local TURN_SPEED = math.rad(25) -- degrees a second

local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)

local function block(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function nameplate(parent: BasePart, text: string, color: Color3, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggName"
	gui.Size = UDim2.fromOffset(170, 38)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	local plate = Instance.new("Frame")
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Color3.fromRGB(20, 22, 34)
	plate.BorderSizePixel = 0
	plate.Parent = gui
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 5)
	bar.Position = UDim2.new(0, 0, 1, -5)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.Parent = plate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, -5)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextSize = 22
	label.TextColor3 = color
	label.Text = text
	label.Parent = plate
	gui.Parent = parent
end

function ShowcaseService:Init(_services) end

function ShowcaseService:Start()
	task.spawn(function()
		AssetLibrary.waitReady(90)
		local folder = Instance.new("Folder")
		folder.Name = "EggShowcase"
		local n = #Eggs.Rarities
		local spinning: { { model: Model, base: CFrame } } = {}
		for i, rarity in Eggs.Rarities do
			local x = (i - (n + 1) / 2) * SPACING
			local big = rarity.Name == "Cosmic"
			local width = if big then 8 else 6
			local plinth = block(rarity.Name .. "Plinth", Vector3.new(width, 2, width), CFrame.new(CENTRE + Vector3.new(x, 1, 0)),
				Color3.fromRGB(46, 50, 72), Enum.Material.SmoothPlastic, folder)
			block("Trim", Vector3.new(width + 0.6, 0.5, width + 0.6), CFrame.new(CENTRE + Vector3.new(x, 2.1, 0)),
				rarity.Color, Enum.Material.Neon, folder).CanCollide = false
			local egg = AssetLibrary.egg(rarity.Name)
			local scale = if big then EGG_SCALE * 1.15 else EGG_SCALE
			egg:ScaleTo(scale)
			local base = CFrame.new(CENTRE + Vector3.new(x, 2.35, 0))
			egg:PivotTo(base)
			egg.Parent = folder
			nameplate(plinth, rarity.Name .. " Egg", rarity.Color, 1 + 4.2 * scale + (if big then 1.2 else 0))
			table.insert(spinning, { model = egg, base = base })
		end
		folder.Parent = Workspace
		local angle = 0
		RunService.Heartbeat:Connect(function(dt)
			angle = (angle + TURN_SPEED * dt) % (2 * math.pi)
			for _, s in spinning do
				if s.model.Parent then
					s.model:PivotTo(s.base * CFrame.Angles(0, angle, 0))
				end
			end
		end)
	end)
end

return ShowcaseService
