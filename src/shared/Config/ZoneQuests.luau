--!strict
-- Zone questlines (Dev, 2026-10-31). Every zone has its own quest giver standing just
-- inside it (World.ZoneNpc). Each one has a short chain of story quests that only count
-- what you do IN that zone. You claim each step by talking to them, so you have to go
-- there. The last step pays a Huge pet from that zone and a Zone Pass: the next zone's
-- gate costs half for you, and the NPC tells you who's waiting there.
-- The chain starts once the zone is unlocked (the Backyard one after the tutorial).
-- The first time you walk into a zone you also get a free egg of that zone (FirstVisitEgg).
-- Server: QuestService. Client: QuestController (dialog, Zones tab, "!" markers).
--
-- Kinds (counted in this zone from when the step started, Stats.Zone[zoneId]):
--   Leaves, Eggs (eggs found), Golden (golden piles), Bunnies, Trash, Hatches (this
--   zone's eggs hatched)
-- Kind that checks what you have now:
--   Pets (different pets of this zone discovered)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

export type Reward = { Kind: string, Seconds: number?, Floor: number?, Item: string?, Amount: number?, Rarity: string?, Pet: string?, Huge: boolean?, Zone: string?, Bonus: Reward? }
export type Step = { Kind: string, Goal: number, Say: string, Reward: Reward }
export type Line = {
	Zone: string,
	Npc: string, -- name tag
	Sub: string, -- line under the name
	Color: Color3, -- name colour
	Skin: Color3,
	Shirt: Color3,
	Pants: Color3,
	Hello: string, -- first time you talk to them
	Steps: { Step },
	Done: string, -- after the whole chain
	Next: string?, -- the zone the Zone Pass is for
	NextNpc: string?, -- who's waiting there
}

local ZoneQuests = {}

-- Counted kinds -> the per-zone counter they read.
ZoneQuests.Counted = { Leaves = true, Eggs = true, Golden = true, Bunnies = true, Trash = true, Hatches = true } :: { [string]: boolean }

-- Zone Pass: the next zone's unlock price is multiplied by this for you.
ZoneQuests.PassDiscount = 0.5

-- Free egg the first time you walk into a zone (the Backyard has the tutorial egg).
ZoneQuests.FirstVisitEgg = {
	Crater = "Rare",
	DarkSide = "Rare",
	Mars = "Epic",
	Europa = "Epic",
} :: { [string]: string }

ZoneQuests.ClaimDistance = 18

local function CASH(seconds: number, floor: number?): Reward
	return { Kind = "Cash", Seconds = seconds, Floor = floor or 0.3 }
end
local function ITEM(id: string, amount: number?): Reward
	return { Kind = "Item", Item = id, Amount = amount or 1 }
end
local function EGG(rarity: string, zone: string): Reward
	return { Kind = "Egg", Rarity = rarity, Zone = zone }
end
local function SPIN(amount: number): Reward
	return { Kind = "Spin", Amount = amount }
end
local function HUGE(pet: string, bonus: Reward?): Reward
	return { Kind = "Pet", Pet = pet, Huge = true, Bonus = bonus }
end

ZoneQuests.Lines = {
	{
		Zone = "Landing",
		Npc = "Grandpa Gus",
		Sub = "Backyard quests",
		Color = Color3.fromRGB(255, 176, 60),
		Skin = Color3.fromRGB(234, 184, 146),
		Shirt = Color3.fromRGB(196, 72, 52),
		Pants = Color3.fromRGB(58, 92, 160),
		Hello = "Well hello there, youngster! This old backyard is a mess and my back isn't what it used to be. Help me out and I'll make it worth your while!",
		Steps = {
			{ Kind = "Leaves", Goal = 250, Say = "Let's start easy. Sweep up some of these leaves for me!", Reward = CASH(120) },
			{ Kind = "Golden", Goal = 2, Say = "See those shiny golden piles? They're worth a fortune. Grab a couple!", Reward = ITEM("LuckPotion") },
			{ Kind = "Bunnies", Goal = 1, Say = "A dust bunny keeps hiding in my leaves. Catch it for me!", Reward = CASH(180) },
			{ Kind = "Trash", Goal = 8, Say = "Folks keep tossing cans and bottles in my yard. Pick them up!", Reward = EGG("Uncommon", "Landing") },
			{ Kind = "Hatches", Goal = 3, Say = "Eggs from my yard hatch the cutest pets. Hatch a few!", Reward = ITEM("SpeedPotion") },
			{ Kind = "Pets", Goal = 6, Say = "I love seeing new faces. Discover 6 different Backyard pets!", Reward = EGG("Rare", "Landing") },
			{ Kind = "Leaves", Goal = 1500, Say = "Last one, and it's a big one. Clean the whole yard for me!", Reward = HUGE("Tiger", ITEM("HatchPotion", 2)) },
		},
		Done = "My yard has never looked better! Go help Ranger Rosa in the Park.",
		Next = "Crater",
		NextNpc = "Ranger Rosa",
	},
	{
		Zone = "Crater",
		Npc = "Ranger Rosa",
		Sub = "Park quests",
		Color = Color3.fromRGB(120, 210, 90),
		Skin = Color3.fromRGB(198, 140, 100),
		Shirt = Color3.fromRGB(96, 120, 60),
		Pants = Color3.fromRGB(130, 104, 70),
		Hello = "Welcome to the Park! I'm Ranger Rosa. The leaves fall faster than I can sweep. Will you help me keep this place green?",
		Steps = {
			{ Kind = "Leaves", Goal = 500, Say = "First, clear the paths so people can walk again!", Reward = CASH(180) },
			{ Kind = "Eggs", Goal = 5, Say = "Park eggs hide under the leaves. Find 5 of them!", Reward = ITEM("LuckPotion") },
			{ Kind = "Golden", Goal = 4, Say = "Golden piles pop up all over the Park. Sweep 4!", Reward = CASH(240) },
			{ Kind = "Bunnies", Goal = 3, Say = "Dust bunnies are chewing my flowers! Catch 3 of them.", Reward = ITEM("SpeedPotion", 2) },
			{ Kind = "Trash", Goal = 20, Say = "Picnic trash everywhere. Pick up 20 pieces!", Reward = EGG("Epic", "Crater") },
			{ Kind = "Hatches", Goal = 5, Say = "Hatch 5 Park eggs. The animals here are special!", Reward = ITEM("SuperLuckPotion") },
			{ Kind = "Pets", Goal = 8, Say = "I keep a list of every Park animal. Discover 8 of them!", Reward = SPIN(2) },
			{ Kind = "Leaves", Goal = 4000, Say = "The big autumn clean-up! Sweep the whole Park!", Reward = HUGE("Koi", ITEM("HatchPotion", 2)) },
		},
		Done = "The Park is spotless thanks to you! Lifeguard Leo on the Beach could use a hand.",
		Next = "DarkSide",
		NextNpc = "Lifeguard Leo",
	},
	{
		Zone = "DarkSide",
		Npc = "Lifeguard Leo",
		Sub = "Beach quests",
		Color = Color3.fromRGB(255, 96, 86),
		Skin = Color3.fromRGB(226, 170, 120),
		Shirt = Color3.fromRGB(230, 52, 52),
		Pants = Color3.fromRGB(250, 200, 60),
		Hello = "Hey, beach buddy! I'm Leo. The tide keeps washing up seaweed and junk. Help me clean my beach!",
		Steps = {
			{ Kind = "Leaves", Goal = 800, Say = "Clear the seaweed off the sand!", Reward = CASH(240) },
			{ Kind = "Eggs", Goal = 8, Say = "Beach eggs wash up with the seaweed. Find 8!", Reward = ITEM("LuckPotion", 2) },
			{ Kind = "Trash", Goal = 30, Say = "Bottles, cans, buckets... Pick up 30 pieces of trash!", Reward = CASH(300) },
			{ Kind = "Golden", Goal = 6, Say = "Golden piles shine in the sun. Sweep 6 of them!", Reward = ITEM("MagnetPotion") },
			{ Kind = "Bunnies", Goal = 4, Say = "Sandy dust bunnies keep digging holes! Catch 4.", Reward = EGG("Epic", "DarkSide") },
			{ Kind = "Hatches", Goal = 8, Say = "Hatch 8 Beach eggs. Sea creatures are the best!", Reward = ITEM("SuperLuckPotion") },
			{ Kind = "Pets", Goal = 10, Say = "Discover 10 different Beach pets!", Reward = SPIN(3) },
			{ Kind = "Leaves", Goal = 6000, Say = "Big wave coming! Clean the whole beach before it hits!", Reward = HUGE("Dolphin", ITEM("MegaCashPotion")) },
		},
		Done = "Best lifeguard partner ever! Chief Sweeps in the City needs you next.",
		Next = "Mars",
		NextNpc = "Chief Sweeps",
	},
	{
		Zone = "Mars",
		Npc = "Chief Sweeps",
		Sub = "City quests",
		Color = Color3.fromRGB(255, 210, 60),
		Skin = Color3.fromRGB(176, 120, 86),
		Shirt = Color3.fromRGB(255, 150, 30),
		Pants = Color3.fromRGB(50, 56, 70),
		Hello = "Listen up, rookie! I'm Chief Sweeps, head of the City clean-up crew. This city makes more mess than anywhere. You in?",
		Steps = {
			{ Kind = "Leaves", Goal = 1000, Say = "Clear the litter off the main street!", Reward = CASH(300) },
			{ Kind = "Trash", Goal = 40, Say = "Pizza boxes everywhere! Pick up 40 pieces of trash.", Reward = ITEM("CashPotion", 2) },
			{ Kind = "Eggs", Goal = 10, Say = "City eggs hide in the litter. Find 10!", Reward = ITEM("SuperLuckPotion") },
			{ Kind = "Golden", Goal = 8, Say = "Sweep 8 golden piles before anyone else grabs them!", Reward = CASH(450) },
			{ Kind = "Bunnies", Goal = 5, Say = "Street dust bunnies! Catch 5 of the little rascals.", Reward = EGG("Legendary", "Mars") },
			{ Kind = "Hatches", Goal = 10, Say = "Hatch 10 City eggs. Robots, neon, you name it!", Reward = ITEM("HugeCharm") },
			{ Kind = "Pets", Goal = 12, Say = "Discover 12 different City pets!", Reward = SPIN(3) },
			{ Kind = "Leaves", Goal = 8000, Say = "The mayor is visiting! Clean the WHOLE city, fast!", Reward = HUGE("NeonCat", ITEM("MegaCashPotion", 2)) },
		},
		Done = "Best crew member I've ever had! Ski Patrol Sam is up on Snowy Peaks.",
		Next = "Europa",
		NextNpc = "Ski Patrol Sam",
	},
	{
		Zone = "Europa",
		Npc = "Ski Patrol Sam",
		Sub = "Snowy Peaks quests",
		Color = Color3.fromRGB(140, 210, 255),
		Skin = Color3.fromRGB(240, 200, 170),
		Shirt = Color3.fromRGB(220, 40, 50),
		Pants = Color3.fromRGB(40, 44, 60),
		Hello = "Brrr! Welcome to Snowy Peaks. I'm Sam from the Ski Patrol. Snow drifts are blocking every trail. Grab your gear and help!",
		Steps = {
			{ Kind = "Leaves", Goal = 1200, Say = "Clear the snow off the ski trails!", Reward = CASH(300) },
			{ Kind = "Eggs", Goal = 12, Say = "Frozen eggs hide in the drifts. Find 12!", Reward = ITEM("SuperLuckPotion") },
			{ Kind = "Golden", Goal = 10, Say = "Golden piles sparkle in the snow. Sweep 10!", Reward = CASH(450) },
			{ Kind = "Bunnies", Goal = 6, Say = "Snow bunnies are everywhere! Catch 6.", Reward = ITEM("MegaCashPotion") },
			{ Kind = "Trash", Goal = 25, Say = "Lost cups and bottles in the snow. Pick up 25!", Reward = EGG("Legendary", "Europa") },
			{ Kind = "Hatches", Goal = 12, Say = "Hatch 12 Snowy Peaks eggs!", Reward = ITEM("HugeCharm", 2) },
			{ Kind = "Pets", Goal = 14, Say = "Discover 14 different Snowy Peaks pets!", Reward = SPIN(5) },
			{ Kind = "Leaves", Goal = 10000, Say = "Blizzard incoming! Clear the whole mountain!", Reward = HUGE("PolarBear", EGG("Mythic", "Europa")) },
		},
		Done = "You're a legend of the mountain! More places to clean are coming soon.",
	},
} :: { Line }

ZoneQuests.ByZone = {} :: { [string]: Line }
for _, line in ZoneQuests.Lines do
	ZoneQuests.ByZone[line.Zone] = line
end

function ZoneQuests.text(step: Step): string
	local n = step.Goal
	local num = Format.number(n)
	local k = step.Kind
	if k == "Leaves" then
		return `Clean {num} leaves here`
	elseif k == "Eggs" then
		return if n == 1 then "Find an egg here" else `Find {num} eggs here`
	elseif k == "Golden" then
		return if n == 1 then "Sweep a golden pile here" else `Sweep {num} golden piles here`
	elseif k == "Bunnies" then
		return if n == 1 then "Catch a dust bunny here" else `Catch {num} dust bunnies here`
	elseif k == "Trash" then
		return `Pick up {num} trash here`
	elseif k == "Hatches" then
		return `Hatch {num} eggs from here`
	elseif k == "Pets" then
		return `Discover {num} pets from here`
	end
	return "?"
end

return ZoneQuests
