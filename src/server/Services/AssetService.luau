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

local PARALLEL = 8

local AssetService = {
	Ready = Signal.new() :: Signal.Signal<>,
}

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
		for name, meta in Assets.Models do
			table.insert(queue, { name = name, id = meta.id, fallback = meta.fallback })
		end
		local running = 0
		for _, job in queue do
			while running >= PARALLEL do
				task.wait()
			end
			running += 1
			task.spawn(function()
				loadOne(job.name, job.id, job.fallback)
				running -= 1
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
