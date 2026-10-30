--!strict
-- Minimal session-locked profile store (ProfileStore-style), written for this game.
-- Record in the DataStore: { Data = <profile data>, Meta = { Session = {JobId, Token, Time}?, LastUpdate, LoadCount } }
-- * Load takes the session lock with UpdateAsync. A lock held by another live server is
--   respected; a lock older than staleSeconds is stolen.
-- * Save and Release only write while we still hold the lock (same Token). If someone stole
--   it, the profile is "lost" and the owner should kick the player.
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local MAX_LOAD_ATTEMPTS = 8
local STUDIO_LOAD_ATTEMPTS = 24 -- Studio waits long enough to outlast STUDIO_STALE
local LOCKED_RETRY_SECONDS = 5
-- In Studio, a lock nobody has written to for this long is dead: a live server autosaves
-- (and so refreshes its lock) every Economy.AutosaveSeconds (60).
local STUDIO_STALE = 100
local MAX_WRITE_ATTEMPTS = 4

export type Profile = {
	Key: string,
	Data: any,
	Token: string,
	Lost: boolean,
	Released: boolean,
	SaveAsync: (Profile) -> boolean,
	ReleaseAsync: (Profile) -> boolean,
	_store: any,
}

local ProfileStore = {}
ProfileStore.__index = ProfileStore

local activeTokens: { [string]: boolean } = {}

local Profile = {}
Profile.__index = Profile

function ProfileStore.new(dataStore: any, staleSeconds: number)
	return setmetatable({ _ds = dataStore, _stale = staleSeconds }, ProfileStore)
end

local function backoff(attempt: number)
	task.wait(math.min(2 ^ attempt, 16))
end

-- Wraps UpdateAsync with retries. Returns ok, result.
function ProfileStore:_update(key: string, transform: (any) -> any, attempts: number): (boolean, any)
	local lastErr
	for attempt = 1, attempts do
		local ok, result = pcall(function()
			return self._ds:UpdateAsync(key, transform)
		end)
		if ok then
			return true, result
		end
		lastErr = result
		warn(`[ProfileStore] UpdateAsync {key} failed (try {attempt}/{attempts}): {result}`)
		if attempt < attempts then
			backoff(attempt)
		end
	end
	return false, lastErr
end

-- Loads and locks a profile. isActive() should return false once the player left.
-- Returns the profile, or nil and a reason ("left", "locked", "error").
function ProfileStore:LoadAsync(key: string, isActive: () -> boolean): (Profile?, string?)
	local token = HttpService:GenerateGUID(false)
	local studio = RunService:IsStudio()
	local staleAfter = if studio then math.min(self._stale, STUDIO_STALE) else self._stale
	local lockAge = 0
	for _ = 1, if studio then STUDIO_LOAD_ATTEMPTS else MAX_LOAD_ATTEMPTS do
		if not isActive() then
			return nil, "left"
		end
		local locked = false
		local loaded: any = nil
		local ok, err = self:_update(key, function(old)
			-- UpdateAsync may run this more than once; only the last run counts.
			locked = false
			loaded = nil
			local record = old or { Data = nil, Meta = {} }
			record.Meta = record.Meta or {}
			local session = record.Meta.Session
			local now = os.time()
			if session and session.Token ~= token then
				lockAge = now - (record.Meta.LastUpdate or 0)
				local stale = lockAge >= staleAfter
				-- Same JobId but not one of our live sessions: a dead Studio run. Safe to take.
				local deadLocal = session.JobId == game.JobId and not activeTokens[session.Token]
				-- A Studio test run takes over a lock left by an earlier Studio run (a stopped
				-- run often can't release it, and waiting left the loading screen stuck), but
				-- never one held by a live server: that kicked a player out of the real game.
				local oldStudioRun = studio and session.Studio == true
				if not stale and not deadLocal and not oldStudioRun then
					locked = true
					return nil -- cancel the write
				end
			end
			record.Meta.Session = { JobId = game.JobId, Token = token, Time = now, Studio = RunService:IsStudio() }
			record.Meta.LastUpdate = now
			record.Meta.LoadCount = (record.Meta.LoadCount or 0) + 1
			loaded = record
			return record
		end, 3)
		if ok and loaded then
			activeTokens[token] = true
			local profile = setmetatable({
				Key = key,
				Data = loaded.Data,
				Token = token,
				Lost = false,
				Released = false,
				_store = self,
			}, Profile)
			return (profile :: any) :: Profile, nil
		end
		if not ok then
			warn(`[ProfileStore] could not load {key}: {err}`)
			return nil, "error"
		end
		if locked then
			-- Usually the player's previous server is still saving. Give it a moment.
			warn(`[ProfileStore] {key} is still locked by another server (last saved {lockAge}s ago, taken over at {staleAfter}s), retrying in {LOCKED_RETRY_SECONDS}s`)
			task.wait(LOCKED_RETRY_SECONDS)
		end
	end
	return nil, "locked"
end

local function write(self: any, release: boolean): boolean
	if self.Released or self.Lost then
		return false
	end
	local lost = false
	local data = self.Data
	local token = self.Token
	local ok = self._store:_update(self.Key, function(old)
		lost = false
		if not old or not old.Meta or not old.Meta.Session or old.Meta.Session.Token ~= token then
			lost = true
			return nil
		end
		old.Data = data
		old.Meta.LastUpdate = os.time()
		if release then
			old.Meta.Session = nil
		end
		return old
	end, MAX_WRITE_ATTEMPTS)
	if lost then
		self.Lost = true
		activeTokens[token] = nil
		return false
	end
	if ok and release then
		self.Released = true
		activeTokens[token] = nil
	end
	return ok
end

function Profile:SaveAsync(): boolean
	return write(self, false)
end

function Profile:ReleaseAsync(): boolean
	return write(self, true)
end

return ProfileStore
