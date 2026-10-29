--!strict
-- The leaf heap inside everyone's backpack (BackpackService welds the "LeafBag" model on
-- every character). The heap grows from the bottom of the bag as the player's BagFill
-- attribute goes up, bulging over the rim when full, and sinks while they dump. A small
-- bounce plays each time it grows, so sweeping feels like stuffing the bag.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BackpackController = {}

local MIN_FILL = 0.04 -- below this the heap is hidden
local EASE = 6 -- how fast the shown fill follows the real one

type Bag = { fill: BasePart, weld: Weld, full: Vector3, bottom: Vector3, c0: CFrame, shown: number, bounce: number, goal: number }
local bags: { [Player]: Bag } = {}

local function find(player: Player): Bag?
	local existing = bags[player]
	if existing and existing.fill.Parent and existing.weld.Parent then
		return existing
	end
	bags[player] = nil
	local character = player.Character
	local model = character and character:FindFirstChild("LeafBag")
	local fill = model and model:FindFirstChild("Fill")
	local weld = fill and fill:FindFirstChild("FillWeld")
	if not fill or not fill:IsA("BasePart") or not weld or not weld:IsA("Weld") then
		return nil
	end
	local full = fill:GetAttribute("FullSize")
	local bottom = fill:GetAttribute("Bottom")
	if typeof(full) ~= "Vector3" or typeof(bottom) ~= "Vector3" then
		return nil
	end
	local bag: Bag = { fill = fill, weld = weld, full = full, bottom = bottom, c0 = weld.C0, shown = -1, bounce = 0, goal = 0 }
	bags[player] = bag
	return bag
end

local function apply(bag: Bag, f: number)
	if f < MIN_FILL then
		bag.fill.Transparency = 1
		return
	end
	bag.fill.Transparency = 0
	local squash = 1 + bag.bounce * 0.12
	local height = math.max(0.05, f)
	bag.fill.Size = Vector3.new(bag.full.X * squash, bag.full.Y * height, bag.full.Z * squash)
	-- Keep the heap's bottom on the bag's floor: only the centre's height above it scales.
	local centre = bag.c0.Position
	local y = bag.bottom.Y + (centre.Y - bag.bottom.Y) * height
	bag.weld.C0 = CFrame.new(centre.X, y, centre.Z) * bag.c0.Rotation
end

function BackpackController:Start()
	Players.PlayerRemoving:Connect(function(player)
		bags[player] = nil
	end)
	RunService.RenderStepped:Connect(function(dt)
		for _, player in Players:GetPlayers() do
			local bag = find(player)
			if not bag then
				continue
			end
			local target = player:GetAttribute("BagFill")
			local goal = if type(target) == "number" then target else 0
			if bag.shown < 0 then
				bag.shown = goal
				bag.goal = goal
				apply(bag, goal)
			end
			if goal > bag.goal then
				bag.bounce = 1 -- more leaves went in
			end
			bag.goal = goal
			if math.abs(goal - bag.shown) < 0.002 and bag.bounce <= 0 then
				continue
			end
			bag.shown += (goal - bag.shown) * math.min(1, dt * EASE)
			bag.bounce = math.max(0, bag.bounce - dt * 4)
			apply(bag, bag.shown)
		end
	end)
end

return BackpackController
