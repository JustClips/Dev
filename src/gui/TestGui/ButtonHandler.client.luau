-- Counts clicks on the test button. Text comes from the button's Message attribute.
local gui = script.Parent
local panel = gui:WaitForChild("Panel")
local button = panel:WaitForChild("ClickButton") :: TextButton
local counter = panel:WaitForChild("Counter") :: TextLabel

local clicks = 0
button.Activated:Connect(function()
	clicks += 1
	panel:SetAttribute("Clicks", clicks)
	counter.Text = `Clicks: {clicks}`
	button.Text = button:GetAttribute("Message") or "Clicked"
end)
