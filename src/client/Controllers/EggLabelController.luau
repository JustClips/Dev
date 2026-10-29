--!strict
-- Names over eggs lying on the ground. With an Egg Rain the field fills with eggs and
-- every label at once was a wall of text (Dev), so only a few show: the eggs closest to
-- you, plus rare ones (Epic and up) a bit further out. The server makes every label
-- hidden; this turns the chosen ones on, four times a second.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)

local NEAR = 28 -- studs: eggs this close can show their name
local NEAR_COUNT = 3 -- at most this many of them
local RARE_RANGE = 70 -- Epic and better show from this far
local RARE_COUNT = 3
local RARE_ORDER = Eggs.order("Epic")

local EggLabelController = {}

type Candidate = { label: BillboardGui, dist: number }

local function update(folder: Instance)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local near: { Candidate } = {}
	local rare: { Candidate } = {}
	local labels: { BillboardGui } = {}
	for _, egg in folder:GetChildren() do
		local label = egg:FindFirstChild("Label")
		if not label or not label:IsA("BillboardGui") or not egg:IsA("BasePart") then
			continue
		end
		table.insert(labels, label)
		if root then
			local dist = (egg.Position - root.Position).Magnitude
			local rarity = egg:GetAttribute("Rarity")
			if type(rarity) == "string" and Eggs.order(rarity) >= RARE_ORDER and dist <= RARE_RANGE then
				table.insert(rare, { label = label, dist = dist })
			elseif dist <= NEAR then
				table.insert(near, { label = label, dist = dist })
			end
		end
	end
	local byDist = function(a: Candidate, b: Candidate)
		return a.dist < b.dist
	end
	table.sort(near, byDist)
	table.sort(rare, byDist)
	local show: { [BillboardGui]: boolean } = {}
	for i = 1, math.min(NEAR_COUNT, #near) do
		show[near[i].label] = true
	end
	for i = 1, math.min(RARE_COUNT, #rare) do
		show[rare[i].label] = true
	end
	for _, label in labels do
		local on = show[label] == true
		if label.Enabled ~= on then
			label.Enabled = on
		end
	end
end

function EggLabelController:Start()
	task.spawn(function()
		local folder = Workspace:WaitForChild("Eggs", 60)
		if not folder then
			return
		end
		while true do
			update(folder)
			task.wait(0.25)
		end
	end)
end

return EggLabelController
