--!strict
-- The Pet Trader: an NPC behind a market stall on every base (stall: MapBuilder). Talking
-- to him (a "Talk" prompt) opens the trader dialog on the client (TraderController), which
-- sells through the Inventory remote: SellHeld, SellAllPets, Appraise. Those check IsNear.
-- The figure itself is built by Lib/Npc (shared with the Quest Master).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = require(Shared.Config.World)
local Npc = require(script.Parent.Parent.Lib.Npc)

local TraderService = {}

local SELL_DISTANCE = 18 -- the server's check (a little looser than the prompt)

local folder: Folder
local roots: { BasePart } = {}

local function build(index: number)
	local root = Npc.build({
		Name = "PetTrader" .. index,
		Title = "Pet Trader",
		Sub = "Sells your pets",
		TitleColor = Color3.fromRGB(255, 200, 60),
		Opens = "Trader",
		Skin = Color3.fromRGB(255, 204, 153),
		Shirt = Color3.fromRGB(74, 164, 82),
		Pants = Color3.fromRGB(120, 84, 52),
	}, World.traderCFrame(index), folder)
	if root then
		table.insert(roots, root)
	end
end

-- True when the player stands close to a Pet Trader.
function TraderService:IsNear(player: Player): boolean
	return Npc.isNear(player, roots, SELL_DISTANCE)
end

function TraderService:Init(_services)
	folder = Instance.new("Folder")
	folder.Name = "Traders"
	folder.Parent = Workspace
end

function TraderService:Start()
	for i = 1, World.BaseCount do
		task.spawn(build, i)
	end
end

return TraderService
