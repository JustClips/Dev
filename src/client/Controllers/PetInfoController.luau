--!strict
-- A pet's info card (PetInfo screen), opened by tapping a pet in the Pets panel: the pet
-- turning in a viewport, its name in its rarity colour, rarity and weight, cash per
-- second, mutation, and passive, with an Unequip (or Equip) button.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AlienModel = require(Shared.AlienModel)
local Aliens = require(Shared.Config.Aliens)
local AssetLibrary = require(Shared.AssetLibrary)
local Eggs = require(Shared.Config.Eggs)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local PetPassives = require(Shared.PetPassives)
local Weights = require(Shared.Config.Weights)

local GREEN = Color3.fromRGB(61, 220, 90)
local RED = Color3.fromRGB(255, 77, 94)
local GREY = Color3.fromRGB(166, 174, 194)

local PetInfoController = {}

local C: any
local gui: ScreenGui
local shownUid: string? = nil
local modelFor: string? = nil

local function close()
	shownUid = nil
	modelFor = nil
	if Ui.isOpen(gui) then
		Ui.hide(gui)
	end
end

local function fill(uid: string): boolean
	local data = State.data
	local pet = data and data.Pets and data.Pets[uid]
	local def = pet and Aliens.ById[pet.Id]
	if not data or not pet or not def then
		return false
	end
	local rarity = Eggs.ByName[def.Rarity]
	local name = Ui.find(gui, "Window.Name") :: TextLabel
	name.Text = (if pet.Huge then "Huge " else "") .. AlienModel.displayName(pet.Id, pet.Mutation)
	name.TextColor3 = if rarity then rarity.Color else Color3.new(0, 0, 0)
	local kg = pet.Weight or Weights.petKg(def.Rarity)
	Ui.find(gui, "Window.Rarity").Text = `{def.Rarity} · {Weights.format(kg)}`
	Ui.find(gui, "Window.Income").Text = `{Format.cash(Aliens.income(pet) * (data.CashMultiplier or 1))}/s`
	local mutation = pet.Mutation and Eggs.MutationByName[pet.Mutation]
	local mutationLabel = Ui.find(gui, "Window.Mutation") :: TextLabel
	if mutation then
		-- "Disco: 3x cash, 2x passive (x3 during Disco)" / "... · IN SEASON!"
		local text = `{mutation.Label}: {mutation.IncomeMult}x cash`
		if mutation.PassiveMult then
			text ..= `, {mutation.PassiveMult}x passive`
		end
		if PetPassives.inSeason(pet.Mutation, PetPassives.seasons()) then
			text ..= " · IN SEASON!"
		elseif mutation.Seasons then
			text ..= ` (x{PetPassives.SeasonMult} {PetPassives.seasonText(pet.Mutation)})`
		end
		mutationLabel.Text = text
		mutationLabel.TextColor3 = mutation.Color
	else
		mutationLabel.Text = if pet.Huge then "Huge: 2x passive" else "No mutation"
		mutationLabel.TextColor3 = Color3.fromRGB(91, 96, 112)
	end
	local box = Ui.find(gui, "Window.PassiveBox")
	local passive = def.Passive
	if passive then
		Ui.find(box, "Title").Text = `Passive: {passive.Name}`
		Ui.find(box, "Text").Text = PetPassives.short(pet.Id, pet.Huge, pet.Mutation, PetPassives.seasons()) or ""
	else
		Ui.find(box, "Title").Text = "Passive"
		Ui.find(box, "Text").Text = "None"
	end
	local action = Ui.find(gui, "Window.Action") :: TextButton
	local full = not pet.Placed and data.PlacedCount >= data.Slots
	Ui.setText(action, if pet.Placed then "Unequip" elseif full then "Slots full" else "Equip")
	action.BackgroundColor3 = if pet.Placed then RED elseif full then GREY else GREEN
	-- Only rebuild the model when it's another pet (this runs on every state change).
	local look = uid .. "|" .. (pet.Mutation or "")
	if look ~= modelFor then
		modelFor = look
		ModelView.show(Ui.find(gui, "Window.Stage.Viewport") :: ViewportFrame, AssetLibrary.alien(pet.Id, pet.Mutation), "Alien_" .. pet.Id)
	end
	return true
end

function PetInfoController:Open(uid: string)
	if not fill(uid) then
		return
	end
	shownUid = uid
	if not Ui.isOpen(gui) then
		Ui.show(gui)
	end
end

function PetInfoController:Init(controllers)
	C = controllers
	gui = Ui.screen("PetInfo")
end

function PetInfoController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), close)
	Ui.find(gui, "Dim").Activated:Connect(close)
	Ui.button(Ui.find(gui, "Window.Action"), function()
		local uid = shownUid
		local data = State.data
		local pet = uid and data and data.Pets and data.Pets[uid]
		if not uid or not pet then
			return
		end
		local ok, message = Net.func("Inventory"):InvokeServer(if pet.Placed then "PickUpPet" else "PlacePet", uid)
		if message and message ~= "" then
			C.HudController:Toast(message, if ok then "Good" else "Bad")
		end
		if ok then
			close()
		end
	end)
	-- Keep the card current while it's open (income, equipped state).
	State.Changed:Connect(function()
		local uid = shownUid
		if uid and Ui.isOpen(gui) and not fill(uid) then
			close()
		end
	end)
end

return PetInfoController
