--!strict
-- Effects at the tip of your hand tool while you use it: toothbrush foam, broom dust, mop
-- splashes, leaf blower air and leaves, vacuum suction. Only your own: every player has
-- their own leaf field, so other players' effects would show over leaves you still see.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)

local ToolFxController = {}

local C: any
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

type Fx = { emitters: { ParticleEmitter }, on: boolean }
local built: { [Tool]: Fx } = setmetatable({}, { __mode = "k" }) :: any

local function img(name: string, fallback: string): string
	local id = Assets.Images[name]
	return if id and id ~= "" then id else fallback
end

local function seq(a: number, b: number): NumberSequence
	return NumberSequence.new(a, b)
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- props: any ParticleEmitter properties.
local function emitter(parent: Attachment, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightInfluence = 0.5
	e.EmissionDirection = Enum.NormalId.Top
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function dust(at: Attachment, rate: number, speed: number): ParticleEmitter
	return emitter(at, {
		Texture = SMOKE,
		Rate = rate,
		Lifetime = NumberRange.new(0.4, 0.75),
		Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(80, 80),
		Size = seq(0.4, 1.5),
		Transparency = seq(0.45, 1),
		Color = ColorSequence.new(rgb(225, 205, 165)),
		Acceleration = Vector3.new(0, 1.5, 0),
		Drag = 2,
	})
end

local function leaves(at: Attachment, rate: number, speed: number, color: Color3): ParticleEmitter
	return emitter(at, {
		Texture = img("FxLeaf", SMOKE),
		Rate = rate,
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(speed * 0.6, speed),
		SpreadAngle = Vector2.new(25, 25),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.25) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(color),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
		Acceleration = Vector3.new(0, -8, 0),
		Drag = 2.5,
	})
end

-- The suction point sits in front of the nozzle; particles fly back into it and shrink.
local function suction(tip: Attachment, glow: Color3?): { ParticleEmitter }
	local suck = Instance.new("Attachment")
	suck.Name = "Suck"
	suck.CFrame = tip.CFrame * CFrame.new(0, 2.2, 0)
	suck.Parent = tip.Parent
	local list = {
		emitter(suck, {
			Texture = SMOKE,
			EmissionDirection = Enum.NormalId.Bottom,
			Rate = 26,
			Lifetime = NumberRange.new(0.22, 0.28),
			Speed = NumberRange.new(7.5, 9),
			SpreadAngle = Vector2.new(30, 30),
			Size = seq(0.7, 0.1),
			Transparency = seq(0.35, 0.7),
			Color = ColorSequence.new(rgb(215, 195, 160)),
		}),
		emitter(suck, {
			Texture = img("FxLeaf", SMOKE),
			EmissionDirection = Enum.NormalId.Bottom,
			Rate = 6,
			Lifetime = NumberRange.new(0.24, 0.28),
			Speed = NumberRange.new(7.5, 8.5),
			SpreadAngle = Vector2.new(25, 25),
			Size = seq(0.3, 0.08),
			Color = ColorSequence.new(rgb(170, 120, 60), rgb(110, 170, 70)),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-500, 500),
		}),
	}
	if glow then
		table.insert(list, emitter(suck, {
			Texture = img("Sparkle", SMOKE),
			EmissionDirection = Enum.NormalId.Bottom,
			Rate = 22,
			Lifetime = NumberRange.new(0.2, 0.26),
			Speed = NumberRange.new(8, 10),
			SpreadAngle = Vector2.new(40, 40),
			Size = seq(0.45, 0.1),
			Color = ColorSequence.new(glow),
			LightEmission = 1,
			LightInfluence = 0,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-400, 400),
		}))
		table.insert(list, emitter(tip, {
			Texture = img("Glow", SMOKE),
			Rate = 10,
			Lifetime = NumberRange.new(0.15, 0.2),
			Speed = NumberRange.new(0, 0),
			Size = seq(0.9, 0.6),
			Transparency = seq(0.5, 1),
			Color = ColorSequence.new(glow),
			LightEmission = 1,
			LightInfluence = 0,
		}))
	end
	return list
end

local STYLES: { [string]: (Attachment) -> { ParticleEmitter } } = {
	Toothbrush = function(tip)
		return {
			emitter(tip, {
				Texture = img("FxBubble", SMOKE),
				Rate = 16,
				Lifetime = NumberRange.new(0.5, 0.9),
				Speed = NumberRange.new(1, 2.5),
				SpreadAngle = Vector2.new(180, 180),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(1, 0.22) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.85, 0.1), NumberSequenceKeypoint.new(1, 1) }),
				Color = ColorSequence.new(rgb(235, 250, 255), rgb(170, 225, 255)),
				Acceleration = Vector3.new(0, 3, 0),
				Drag = 3,
			}),
			emitter(tip, {
				Texture = img("Sparkle", SMOKE),
				Rate = 5,
				Lifetime = NumberRange.new(0.3, 0.5),
				Speed = NumberRange.new(1, 2),
				SpreadAngle = Vector2.new(180, 180),
				Size = seq(0.35, 0),
				Color = ColorSequence.new(rgb(200, 240, 255)),
				LightEmission = 0.7,
			}),
		}
	end,
	Broom = function(tip)
		return { dust(tip, 14, 4), leaves(tip, 4, 5, rgb(160, 115, 60)) }
	end,
	Mop = function(tip)
		return {
			emitter(tip, {
				Texture = img("FxDrop", SMOKE),
				Rate = 14,
				Lifetime = NumberRange.new(0.35, 0.55),
				Speed = NumberRange.new(3, 5.5),
				SpreadAngle = Vector2.new(70, 70),
				Size = seq(0.22, 0.14),
				Color = ColorSequence.new(rgb(150, 210, 255)),
				Acceleration = Vector3.new(0, -28, 0),
				Orientation = Enum.ParticleOrientation.VelocityParallel,
			}),
			emitter(tip, {
				Texture = img("FxBubble", SMOKE),
				Rate = 8,
				Lifetime = NumberRange.new(0.5, 0.8),
				Speed = NumberRange.new(0.5, 1.5),
				SpreadAngle = Vector2.new(180, 180),
				Size = seq(0.15, 0.3),
				Color = ColorSequence.new(rgb(230, 245, 255)),
				Acceleration = Vector3.new(0, 2, 0),
			}),
		}
	end,
	LeafBlower = function(tip)
		return {
			emitter(tip, {
				Texture = img("FxStreak", SMOKE),
				Rate = 34,
				Lifetime = NumberRange.new(0.18, 0.28),
				Speed = NumberRange.new(26, 34),
				SpreadAngle = Vector2.new(9, 9),
				Size = seq(0.5, 0.9),
				Transparency = seq(0.35, 1),
				Color = ColorSequence.new(rgb(240, 250, 255)),
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				LightEmission = 0.3,
			}),
			leaves(tip, 7, 18, rgb(120, 180, 70)),
			leaves(tip, 5, 16, rgb(230, 140, 50)),
			dust(tip, 8, 10),
		}
	end,
	ShopVac = function(tip)
		return suction(tip, nil)
	end,
	TurboVacuum = function(tip)
		return suction(tip, rgb(90, 255, 240))
	end,
}

local function build(tool: Tool): Fx?
	local fx = built[tool]
	if fx then
		return fx
	end
	local id = tool:GetAttribute("ToolId")
	local handle = tool:FindFirstChild("Handle")
	local tip = handle and handle:FindFirstChild("Tip")
	local style = type(id) == "string" and STYLES[id] or nil
	if not tip or not tip:IsA("Attachment") or not style then
		return nil
	end
	fx = { emitters = style(tip), on = false }
	built[tool] = fx :: Fx
	return fx
end

local function setOn(fx: Fx, on: boolean)
	if fx.on == on then
		return
	end
	fx.on = on
	for _, e in fx.emitters do
		e.Enabled = on
	end
end

local function update()
	local char = Players.LocalPlayer.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if not tool or not tool:GetAttribute("SweepTool") then
		return
	end
	local fx = build(tool)
	if fx then
		setOn(fx, C.SweepController:IsToolActive())
	end
end

function ToolFxController:Init(controllers)
	C = controllers
end

function ToolFxController:Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			update()
		end
	end)
end

return ToolFxController
