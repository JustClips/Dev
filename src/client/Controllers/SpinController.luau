--!strict
-- Turns parts the server tagged "SpinPart" (windmill sails) about their hub, locally on
-- each client so it's smooth and costs no network. Attributes set by MapBuilder.spinSails:
-- SpinHub (CFrame, spin about its Z axis), SpinBase (the part's resting CFrame) and
-- SpinSpeed (radians per second).
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SpinController = {}

local MAX_DISTANCE = 400

function SpinController:Init() end

function SpinController:Start()
	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		local t = os.clock()
		for i, part in CollectionService:GetTagged("SpinPart") do
			if not part:IsA("BasePart") then
				continue
			end
			local hub = part:GetAttribute("SpinHub")
			local base = part:GetAttribute("SpinBase")
			local speed = part:GetAttribute("SpinSpeed")
			if typeof(hub) ~= "CFrame" or typeof(base) ~= "CFrame" or type(speed) ~= "number" then
				continue
			end
			if camera and (camera.CFrame.Position - hub.Position).Magnitude > MAX_DISTANCE then
				continue
			end
			local angle = t * speed + i * 1.7
			part.CFrame = hub * CFrame.Angles(0, 0, angle) * hub:Inverse() * base
		end
	end)
end

return SpinController
