--!strict
-- Rebirth screen: cost, multiplier now -> after, rebirth button and the Robux skip.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local State = require(Client.State)
local Ui = require(Client.Ui)
local Prices = require(Client.Prices)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)

local RebirthController = {}

local C: any
local gui: ScreenGui
local rebirthButton: TextButton
local skipButton: TextButton

local function skipKey(): string
	local skip = State.data and Products.skipRebirthFor(State.data.Rebirths)
	return if skip then skip.Key else "SkipRebirth"
end

local function mult(n: number): string
	local m = 1 + n * Economy.RebirthCashBonus
	return if m == math.floor(m) then tostring(m) else string.format("%.1f", m)
end

-- Like Dev's reference (2026-10-31): Rebirth N -> Rebirth N+1, a requirements bar, then
-- Rebirth OR Skip.
local function render()
	local data = State.data
	if not data then
		return
	end
	local n = data.Rebirths
	Ui.find(gui, "Window.Now.Title").Text = `Rebirth {n}`
	Ui.find(gui, "Window.Now.Mult").Text = `x{mult(n)} Cash`
	Ui.find(gui, "Window.Now.Extra").Text = "You are here"
	Ui.find(gui, "Window.Next.Title").Text = `Rebirth {n + 1}`
	Ui.find(gui, "Window.Next.Mult").Text = `x{mult(n + 1)} Cash`
	Ui.find(gui, "Window.Next.Extra").Text = "Opens more of the tree!"
	local affordable = BigNum.gte(data.Cash, data.RebirthCost)
	local ratio = if affordable then 1 else math.clamp(BigNum.toNumber(BigNum.div(data.Cash, data.RebirthCost)), 0, 1)
	Ui.find(gui, "Window.Req.Text").Text = `Have {Format.cash(data.RebirthCost)} (you have {Format.cash(data.Cash)})`
	;(Ui.find(gui, "Window.Req.Bar.Fill") :: Frame).Size = UDim2.fromScale(math.max(ratio, 0.02), 1)
	Ui.find(gui, "Window.Req.Bar.Pct").Text = if affordable then "READY!" else `{math.floor(ratio * 100)}%`
	-- Can't afford: the button goes grey.
	rebirthButton.BackgroundColor3 = if affordable then Color3.fromRGB(61, 220, 90) else Color3.fromRGB(166, 174, 194)
	local studs = rebirthButton:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageColor3 = rebirthButton.BackgroundColor3
	end
	-- The skip price grows with each rebirth (Products.skipRebirthFor).
	local skip = Products.skipRebirthFor(n)
	skipButton.Visible = skip ~= nil
	Ui.find(gui, "Window.Or").Visible = skip ~= nil
	if skip then
		Ui.find(skipButton, "Price").Text = `{Ui.ROBUX}{Prices.of(skip)}`
		Ui.find(skipButton, "Sub").Text = `[{math.floor(Economy.SkipRebirthMinShare * 100)}% of the cash needed]`
	end
end

function RebirthController:Toggle()
	Ui.toggle("Rebirth")
	render()
end

function RebirthController:Init(controllers)
	C = controllers
	gui = Ui.screen("Rebirth")
	rebirthButton = Ui.find(gui, "Window.RebirthButton")
	skipButton = Ui.find(gui, "Window.SkipButton")
end

function RebirthController:Start()
	Ui.button(Ui.find(gui, "Window.Close"), function()
		Ui.close("Rebirth")
	end)
	Ui.button(Ui.find(gui, "Dim"), function()
		Ui.close("Rebirth")
	end)
	Ui.button(rebirthButton, function()
		local ok, message = Net.func("Rebirth"):InvokeServer()
		C.HudController:Toast(message or "", if ok then "Good" else "Bad")
		if ok then
			Ui.close("Rebirth")
		end
	end)
	Ui.button(skipButton, function()
		local ok, message = Net.func("PromptPurchase"):InvokeServer(skipKey())
		if not ok and message then
			C.HudController:Toast(message, "Bad")
		end
	end)
	State.Changed:Connect(function()
		if gui.Enabled then
			render()
		end
	end)
end

return RebirthController
