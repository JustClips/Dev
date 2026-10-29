--!strict
-- The Pet Trader on your base (TraderService). "Talk" opens his dialog (DialogController):
--   Sell this pet     the pet you hold out (bag -> tap a pet), after a price and a "Deal?"
--   Sell all pets     every pet in your bag (pets on your base stay), after a "Deal?"
--   What's it worth?  the held pet's price, or your whole bag's
--   Leave
-- Selling goes through the Inventory remote (SellHeld, SellAllPets, Appraise).
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local TraderController = {}

local NAME = "Pet Trader"
local GREEN = Color3.fromRGB(46, 170, 80)
local ORANGE = Color3.fromRGB(230, 120, 40)
local BLUE = Color3.fromRGB(56, 120, 230)
local GREY = Color3.fromRGB(90, 96, 110)

local C: any

local function invoke(action: string, arg: string?): (boolean, string?)
	local ok, a, b = pcall(function()
		return Net.func("Inventory"):InvokeServer(action, arg)
	end)
	if not ok then
		return false, "Something went wrong, try again"
	end
	return a, b
end

-- "Glorp|$180" -> "Glorp", "$180"
local function priced(message: string?): (string, string)
	local name, value = string.match(message or "", "^(.-)|(.+)$")
	return name or "pet", value or "?"
end

local menu: () -> ()

local function leave()
	C.DialogController:Say("See you around! Come back with more pets.", {})
	task.delay(1.2, function()
		C.DialogController:Close()
	end)
end

local function back(): { text: string, color: Color3?, pick: () -> () }
	return { text = "Back", color = GREY, pick = menu }
end

local function notHolding()
	C.DialogController:Say("You're not holding a pet! Open your bag and tap a pet to hold it out.", {
		{
			text = "Open my bag",
			color = BLUE,
			pick = function()
				C.DialogController:Close()
				C.InventoryController:Open("Pets")
			end,
		},
		back(),
	})
end

local function sellHeld()
	local ok, message = invoke("Appraise")
	if not ok then
		notHolding()
		return
	end
	local name, value = priced(message)
	C.DialogController:Say(`I'll give you {value} for that {name}. Deal?`, {
		{
			text = `Deal! +{value}`,
			color = GREEN,
			pick = function()
				local sold, result = invoke("SellHeld")
				if sold then
					Ui.sound("Sell")
					C.HudController:Toast(result or "Sold!", "Sell")
					C.DialogController:Say("Pleasure doing business! Got any more?", {
						{ text = "Sell another", color = GREEN, pick = menu },
						{ text = "Leave", color = GREY, pick = leave },
					})
				else
					C.DialogController:Say(result or "Hmm, that didn't work.", { back() })
				end
			end,
		},
		{ text = "No thanks", color = GREY, pick = menu },
	})
end

local function sellAll()
	local ok, message = invoke("Appraise", "All")
	if not ok then
		C.DialogController:Say("You don't have any pets in your bag. Pets on your base are safe with you.", { back() })
		return
	end
	C.DialogController:Say(`I'll take all of them: {message}. The pets on your base stay with you. Deal?`, {
		{
			text = "Sell them all!",
			color = ORANGE,
			pick = function()
				local sold, result = invoke("SellAllPets")
				if sold then
					Ui.sound("Sell")
					C.HudController:Toast(result or "Sold!", "Sell")
					C.DialogController:Say("Wow, what a haul! Thanks!", {
						{ text = "Leave", color = GREY, pick = leave },
					})
				else
					C.DialogController:Say(result or "Hmm, that didn't work.", { back() })
				end
			end,
		},
		{ text = "No thanks", color = GREY, pick = menu },
	})
end

local function appraise()
	local ok, message = invoke("Appraise")
	if ok then
		local name, value = priced(message)
		C.DialogController:Say(`That {name} is worth {value} to me.`, {
			{ text = "Sell it", color = GREEN, pick = sellHeld },
			back(),
		})
		return
	end
	C.DialogController:Say("Hold a pet out and I'll tell you what it's worth. Or should I price your whole bag?", {
		{
			text = "Price my bag",
			color = BLUE,
			pick = function()
				local okAll, all = invoke("Appraise", "All")
				C.DialogController:Say(if okAll then `Your bag: {all}.` else "Your bag has no pets in it.", { back() })
			end,
		},
		back(),
	})
end

menu = function()
	local held = C.PlacementController:HeldPet()
	C.DialogController:Say(if held then "Ooh, nice pet! What can I do for you?" else "Hey there! I buy pets. Hold one out from your bag and I'll make you an offer.", {
		{ text = "Sell this pet", color = GREEN, pick = sellHeld },
		{ text = "Sell all pets", color = ORANGE, pick = sellAll },
		{ text = "What's it worth?", color = BLUE, pick = appraise },
		{ text = "Leave", color = GREY, pick = leave },
	})
end

function TraderController:Init(controllers)
	C = controllers
end

function TraderController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Opens") ~= "Trader" then
			return
		end
		local at = prompt.Parent
		C.DialogController:Open(NAME, if at and at:IsA("BasePart") then at else nil)
		menu()
	end)
end

return TraderController
