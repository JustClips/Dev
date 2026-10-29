--!strict
-- Loads every Blender model from Config/Assets once at server start (InsertService works
-- for assets owned by the game's creator), cleans them up with AssetLibrary.prepare and
-- stores them in ReplicatedStorage.Assets for server and client code to clone.
-- Sets Assets.Ready when done. Models that fail to load fall back to placeholders.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local Assets = require(Shared.Config.Assets)
local Signal = require(Shared.Signal)

local PARALLEL = 12

local AssetService = {
	Ready = Signal.new() :: Signal.Signal<>,
	-- Eggs load first, then pets, then everything else, so bases and the hotbar show the
	-- real models within a few seconds instead of after every model is in.
	EggsReady = Signal.new() :: Signal.Signal<>,
	CoreReady = Signal.new() :: Signal.Signal<>,
}

-- 0 = eggs, 1 = pets, 2 = the rest.
local function rank(name: string): number
	if string.sub(name, 1, 4) == "Egg_" then
		return 0
	elseif string.sub(name, 1, 6) == "Alien_" then
		return 1
	end
	return 2
end

local folder: Folder
local loaded = 0
local failed: { string } = {}

local primaryLoaded = 0
local fallbackLoaded = 0

local function tryLoad(id: number): Instance?
	for attempt = 1, 2 do
		local ok, result = pcall(function()
			return InsertService:LoadAsset(id)
		end)
		if ok and result then
			return result
		end
		if attempt == 1 then
			task.wait(1)
		end
	end
	return nil
end

-- Primary id first. A game can only insert models owned by its own creator, so when the
-- primary account isn't the game's owner the fallback (owner's) copy is used instead.
local function loadOne(name: string, id: number?, fallback: number?)
	local result = if id then tryLoad(id) else nil
	if result then
		primaryLoaded += 1
	elseif fallback then
		result = tryLoad(fallback)
		if result then
			fallbackLoaded += 1
		end
	end
	if result then
		local model = AssetLibrary.prepare(name, result)
		model.Parent = folder
		loaded += 1
	else
		table.insert(failed, name)
	end
end

function AssetService:IsReady(): boolean
	return folder:GetAttribute("Ready") == true
end

function AssetService:IsCoreReady(): boolean
	return folder:GetAttribute("CoreReady") == true
end

function AssetService:WaitReady(timeout: number?)
	local deadline = os.clock() + (timeout or 60)
	while not AssetService:IsReady() and os.clock() < deadline do
		task.wait(0.2)
	end
end

function AssetService:Init()
	folder = Instance.new("Folder")
	folder.Name = "Assets"
	folder.Parent = ReplicatedStorage
	-- Start loading right away; other services wait for Ready when they need models.
	task.spawn(function()
		local started = os.clock()
		local queue = {}
		local pending = { [0] = 0, [1] = 0, [2] = 0 }
		for name, meta in Assets.Models do
			local r = rank(name)
			pending[r] += 1
			table.insert(queue, { name = name, id = meta.id, fallback = meta.fallback, rank = r })
		end
		table.sort(queue, function(a, b)
			return a.rank < b.rank
		end)
		local function milestones()
			if pending[0] == 0 and folder:GetAttribute("EggsReady") ~= true then
				folder:SetAttribute("EggsReady", true)
				AssetService.EggsReady:Fire()
			end
			if pending[0] == 0 and pending[1] == 0 and folder:GetAttribute("CoreReady") ~= true then
				folder:SetAttribute("CoreReady", true)
				print(string.format("[AssetService] eggs and pets ready in %.1f s", os.clock() - started))
				AssetService.CoreReady:Fire()
			end
		end
		milestones()
		local running = 0
		for _, job in queue do
			while running >= PARALLEL do
				task.wait()
			end
			running += 1
			task.spawn(function()
				loadOne(job.name, job.id, job.fallback)
				running -= 1
				pending[job.rank] -= 1
				milestones()
			end)
		end
		while running > 0 do
			task.wait()
		end
		if #failed > 0 then
			warn(`[AssetService] {#failed} models failed to load (placeholders used): {table.concat(failed, ", ")}`)
		end
		-- Animations follow the same owner rule, so play the fallback account's copies
		-- when the models had to come from there.
		folder:SetAttribute("UseFallback", fallbackLoaded > primaryLoaded)
		print(
			string.format(
				"[AssetService] %d models ready in %.1f s (%d primary, %d fallback)",
				loaded,
				os.clock() - started,
				primaryLoaded,
				fallbackLoaded
			)
		)
		folder:SetAttribute("Ready", true)
		AssetService.Ready:Fire()
	end)
end

return AssetService
