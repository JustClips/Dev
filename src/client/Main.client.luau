local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hello = require(ReplicatedStorage.Shared.Hello)

print("[client]", Hello.greet(game:GetService("Players").LocalPlayer.Name))
