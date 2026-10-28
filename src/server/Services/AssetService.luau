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

local function loadOne(name: string, id: number)
	for attempt = 1, 2 do
		local ok, result = pcall(function()
			return InsertService:LoadAsset(id)
		end)
		if ok and result then
			local model = AssetLibrary.prepare(name, result)
			model.Parent = folder
			loaded += 1
			return
		end
		if attempt == 2 then
			table.insert(failed, name)
		else
			task.wait(1)
		end
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
			table.insert(queue, { name = name, id = meta.id })
		end
		local running = 0
		for _, job in queue do
			while running >= PARALLEL do
				task.wait()
			end
			running += 1
			task.spawn(function()
				loadOne(job.name, job.id)
				running -= 1
			end)
		end
		while running > 0 do
			task.wait()
		end
		if #failed > 0 then
			warn(`[AssetService] {#failed} models failed to load (placeholders used): {table.concat(failed, ", ")}`)
		end
		print(string.format("[AssetService] %d models ready in %.1f s", loaded, os.clock() - started))
		folder:SetAttribute("Ready", true)
		AssetService.Ready:Fire()
	end)
end

return AssetService
