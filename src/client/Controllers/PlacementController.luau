--!strict
-- Holding an egg to put it down in your pet park (Steal an Egg style). Hold(uid) asks the
-- server to put the egg in your hands, then a see-through ghost egg follows the mouse (or
-- your finger) with a ring that is green where the egg may go and red where it may not
-- (Shared/EggSpots, the same rules the server checks). Click or tap to place it. If you
-- still have eggs and room, the next best egg is in your hands right away. Q, Backspace,
-- Cancel or equipping a tool puts it away.
-- Pets from the bag or hotbar can be held out too (HoldPet): carry it to your base, then
-- click or tap anywhere to let it out in your park. Put away (Q) puts it back, and the
-- Pet Trader buys what you hold.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local ModelView = require(Client.ModelView)
local State = require(Client.State)
local Ui = require(Client.Ui)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetLibrary = require(Shared.AssetLibrary)
local AlienModel = require(Shared.AlienModel)
local Aliens = require(Shared.Config.Aliens)
local EggSpots = require(Shared.EggSpots)
local Eggs = require(Shared.Config.Eggs)
local Net = require(Shared.Net)
local PetPassives = require(Shared.PetPassives)
local Weights = require(Shared.Config.Weights)
local World = require(Shared.Config.World)

local GOOD = Color3.fromRGB(61, 220, 90)
local BAD = Color3.fromRGB(255, 77, 94)
local NEAR_BASE = 80 -- studs from the park centre to place by clicking
local PARK_TOP = 0.2 -- the park floor's top, base local
local SNAP_REACH = 5 -- studs a click may be nudged to the nearest free spot
local SNAP_PAD = 0.1 -- a little stricter than the server, so it always agrees

local PlacementController = {}

local C: any
local gui: ScreenGui
local titleLabel: TextLabel
local subLabel: TextLabel
local goBase: GuiButton
local icon: ImageLabel
local modelView: ViewportFrame

local holding: string? = nil
local heldPet: string? = nil
local placePet: GuiButton
local cancelButton: GuiButton
local ghost: Model? = nil
local ring: BasePart? = nil
local ghostOffset = 0
local spotOk = false
local spotWorld: Vector3? = nil
local spotProblem: string? = nil
local stepConn: RBXScriptConnection? = nil
local busy = false
local pointer: Vector2? = nil -- last touch position (touch screens)
local touchStart: Vector2? = nil -- where the current touch began (drags move the camera)
local TAP_SLOP = 14 -- pixels a tap may move and still place

local function toast(text: string, kind: string)
	C.HudController:Toast(text, kind)
end

local function invoke(action: string, arg: string?, position: Vector3?): (boolean, string?)
	return Net.func("Inventory"):InvokeServer(action, arg, position)
end

local function baseCFrame(): CFrame?
	local data = State.data
	if not data or not data.BaseIndex or data.BaseIndex == 0 then
		return nil
	end
	return World.baseCFrame(data.BaseIndex)
end

local function parkCentre(cf: CFrame): Vector3
	local c = (World.Base.ParkMin + World.Base.ParkMax) / 2
	return cf * Vector3.new(c.X, 0, c.Y)
end

-- True when you're close enough to your park to let a pet out.
local function nearBase(): boolean
	local cf = baseCFrame()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not cf or not root then
		return false
	end
	local centre = parkCentre(cf)
	return (Vector3.new(root.Position.X, centre.Y, root.Position.Z) - centre).Magnitude <= NEAR_BASE
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	if ring then
		ring:Destroy()
		ring = nil
	end
end

local function makeGhost(egg)
	clearGhost()
	local model = AssetLibrary.egg(egg.Rarity)
	model:SetAttribute("Rarity", egg.Rarity)
	local scale = Weights.visualScale(Weights.eggMult(egg.Rarity, egg.Weight))
	model:ScaleTo(scale * 1.25)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = math.max(d.Transparency, 0.35)
		end
	end
	model.Parent = Workspace
	ghost = model
	ghostOffset = 0.35
	local r = Instance.new("Part")
	r.Name = "PlaceRing"
	r.Shape = Enum.PartType.Cylinder
	r.Size = Vector3.new(0.15, EggSpots.Spacing, EggSpots.Spacing)
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.CanTouch = false
	r.CastShadow = false
	r.Material = Enum.Material.SmoothPlastic
	r.Transparency = 0.35
	r.Parent = Workspace
	ring = r
end

local function screenPoint(): Vector2
	if pointer then
		return pointer
	end
	-- Controller: aim a few studs in front of you.
	if Ui.gamepad() then
		local camera = Workspace.CurrentCamera
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if camera and root then
			local at = camera:WorldToViewportPoint(root.Position + root.CFrame.LookVector * 6 - Vector3.new(0, 2.5, 0))
			return Vector2.new(at.X, at.Y)
		end
	end
	return UserInputService:GetMouseLocation()
end

-- Finds the park spot under the mouse / finger and colours the ring.
local function update()
	local camera = Workspace.CurrentCamera
	local cf = baseCFrame()
	local data = State.data
	if not camera or not cf or not data or not ghost or not ring then
		return
	end
	-- Held before the egg models finished loading: swap the stand-in for the real egg.
	if ghost:GetAttribute("Placeholder") and holding then
		local egg = data.Eggs and data.Eggs[holding]
		local rarity = ghost:GetAttribute("Rarity")
		if egg and AssetLibrary.meta("Egg_" .. tostring(rarity)) and AssetLibrary.has("Egg_" .. tostring(rarity)) then
			makeGhost(egg)
		end
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local far = root == nil or (root.Position - parkCentre(cf)).Magnitude > NEAR_BASE
	goBase.Visible = far
	if far then
		titleLabel.Text = "Go to your base to place it"
	else
		titleLabel.Text = if Ui.gamepad()
			then "Face a green spot and press R2"
			elseif UserInputService.TouchEnabled then "Tap a spot in your pet park"
			else "Click a spot in your pet park"
	end

	-- Where the pointer meets the park floor. A flat plane instead of a raycast, so props,
	-- fences, pets and other eggs in front never turn a good spot red.
	local point = screenPoint()
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local origin = cf:PointToObjectSpace(ray.Origin)
	local direction = cf:VectorToObjectSpace(ray.Direction)
	if direction.Y > -0.02 then
		spotOk, spotWorld = false, nil
		ring.Transparency = 1
		return
	end
	local t = (PARK_TOP - origin.Y) / direction.Y
	local aim = origin + direction * t
	-- Snap to the closest free spot near the pointer (a click by an egg or a rock still
	-- lands right next to it).
	local x, z, why = EggSpots.nearest(data.Hatching, aim.X, aim.Z, SNAP_REACH, SNAP_PAD)
	spotOk = x ~= nil and not far
	spotProblem = if far then "Go to your base first!" else why
	local lx, lz = x or aim.X, z or aim.Z
	local snapped = cf * CFrame.new(lx, PARK_TOP, lz)
	spotWorld = if x then snapped.Position else nil
	ring.Transparency = 0.35
	ring.Color = if spotOk then GOOD else BAD
	ring.CFrame = snapped * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90))
	local bob = math.sin(os.clock() * 4) * 0.25
	ghost:PivotTo(snapped * CFrame.new(0, ghostOffset + 1 + bob, 0))
end

local function nextEgg(data, skip: { [string]: boolean }): string?
	local best, bestScore = nil, -math.huge
	for uid, egg in data.Eggs or {} do
		if not skip[uid] then
			local score = Eggs.order(egg.Rarity) * 100 + Weights.eggMult(egg.Rarity, egg.Weight)
			if score > bestScore then
				best, bestScore = uid, score
			end
		end
	end
	return best
end

function PlacementController:IsHolding(): boolean
	return holding ~= nil
end

-- The pet or egg in your hands, if any.
function PlacementController:HeldKey(): string?
	return holding or heldPet
end

function PlacementController:HeldPet(): string?
	return heldPet
end

local function refreshBag()
	if C.InventoryController then
		C.InventoryController:RefreshHeld()
	end
	if C.HotbarController and C.HotbarController.Refresh then
		C.HotbarController:Refresh()
	end
end

local function stopPet(silent: boolean?)
	if not heldPet then
		return
	end
	heldPet = nil
	if not holding then
		gui.Enabled = false
	end
	placePet.Visible = false
	if not silent then
		task.spawn(invoke, "StopHolding")
	end
	refreshBag()
end

function PlacementController:HoldPet(uid: string)
	local data = State.data
	local pet = data and data.Pets and data.Pets[uid]
	if not data or not pet or pet.Placed then
		return
	end
	if holding then
		PlacementController:Stop(true)
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
	heldPet = uid
	local def = Aliens.ById[pet.Id]
	local rarity = def and Eggs.ByName[def.Rarity]
	titleLabel.Text = "Holding " .. (if pet.Huge then "Huge " else "") .. AlienModel.displayName(pet.Id, pet.Mutation)
	local kg = pet.Weight or Weights.petKg(def and def.Rarity or "Common")
	local passive = PetPassives.short(pet.Id, pet.Huge) -- short form: the full one got cut off
	subLabel.Text = `{def and def.Rarity or ""} · {Weights.format(kg)}` .. (if passive then ` · {passive}` else "")
	subLabel.TextColor3 = if rarity then rarity.Color else Color3.new(1, 1, 1)
	icon.Visible = false
	modelView.Visible = true
	ModelView.show(modelView, AssetLibrary.alien(pet.Id, pet.Mutation), "Alien_" .. pet.Id)
	goBase.Visible = false
	placePet.Visible = false -- tap anywhere at your base instead (Dev)
	Ui.setText(cancelButton, if Ui.gamepad() then "Put away (B)" else "Put away (Q)")
	gui.Enabled = true
	Ui.popIn(gui)
	refreshBag()
	task.spawn(function()
		local ok, message = invoke("HoldPet", uid)
		if not ok and heldPet == uid then
			stopPet(true)
			if message then
				toast(message, "Bad")
			end
		end
	end)
end

function PlacementController:Stop(silent: boolean?)
	if heldPet and not holding then
		stopPet(silent)
		return
	end
	if not holding then
		return
	end
	holding = nil
	pointer = nil
	clearGhost()
	if stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
	gui.Enabled = false
	if not silent then
		task.spawn(invoke, "StopHolding")
	end
	refreshBag()
end

function PlacementController:Hold(uid: string)
	local data = State.data
	local egg = data and data.Eggs and data.Eggs[uid]
	if not data or not egg then
		return
	end
	if #data.Hatching >= data.Incubators then
		toast(`Only {data.Incubators} eggs can grow at once. Open one first!`, "Bad")
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
	if heldPet then
		heldPet = nil -- the server swaps the pet for the egg
		placePet.Visible = false
	end
	Ui.setText(cancelButton, if Ui.gamepad() then "Cancel (B)" else "Cancel (Q)")
	holding = uid
	makeGhost(egg)
	local left = 0
	for _ in data.Eggs do
		left += 1
	end
	local size = egg.Size or "Normal"
	subLabel.Text = `{if size ~= "Normal" then size .. " " else ""}{egg.Rarity} Egg · {Weights.format(egg.Weight or Weights.eggKg(egg.Rarity))} · {left} in bag`
	subLabel.TextColor3 = Eggs.ByName[egg.Rarity].Color
	icon.Visible = false
	modelView.Visible = true
	ModelView.show(modelView, AssetLibrary.egg(egg.Rarity), "Egg_" .. egg.Rarity)
	gui.Enabled = true
	Ui.popIn(gui)
	if not stepConn then
		stepConn = RunService.RenderStepped:Connect(update)
	end
	task.spawn(function()
		local ok, message = invoke("HoldEgg", uid)
		if not ok and holding == uid then
			PlacementController:Stop(true)
			if message then
				toast(message, "Bad")
			end
		end
	end)
end

local placedThisRun: { [string]: boolean } = {}

local function place()
	local uid = holding
	if not uid or busy then
		return
	end
	if not spotOk or not spotWorld then
		toast(spotProblem or "Tap a green spot in your pet park!", "Bad")
		return
	end
	busy = true
	local ok, message = invoke("PlaceEggAt", uid, spotWorld)
	busy = false
	if not ok then
		toast(message or "Can't place it there", "Bad")
		return
	end
	Ui.sound("Egg")
	placedThisRun[uid] = true
	PlacementController:Stop(true)
	-- Keep going with the next best egg while there's room.
	task.delay(0.35, function()
		local data = State.data
		if not data or holding then
			return
		end
		local growing = #data.Hatching
		if growing >= data.Incubators then
			toast(`Your park is growing {growing} eggs, that's the max! Open them when they're ready.`, "Info")
			return
		end
		local nextUid = nextEgg(data, placedThisRun)
		if nextUid then
			PlacementController:Hold(nextUid)
		end
	end)
end

function PlacementController:Init(controllers)
	C = controllers
	gui = Ui.screen("Placing")
	titleLabel = Ui.find(gui, "Bar.Title")
	subLabel = Ui.find(gui, "Bar.Sub")
	goBase = Ui.find(gui, "Bar.GoBase")
	icon = Ui.find(gui, "Bar.Icon")
	modelView = Ui.find(gui, "Bar.Model")
	placePet = Ui.find(gui, "Bar.PlacePet")
	cancelButton = Ui.find(gui, "Bar.Cancel")
end

function PlacementController:Start()
	Ui.button(cancelButton, function()
		PlacementController:Stop()
	end)
	-- Let the held pet out in your park (a click or tap anywhere while at your base).
	local releasing = false
	local function releasePet()
		local uid = heldPet
		if not uid or releasing then
			return
		end
		if not nearBase() then
			toast("Take your pet to your base, then tap anywhere to let it out!", "Info")
			return
		end
		releasing = true
		local ok, message = invoke("PlacePet", uid)
		releasing = false
		if ok then
			Ui.sound("Pop")
			stopPet(true)
			toast("Your pet is in your park now!", "Good")
		elseif message then
			toast(message, "Bad")
		end
	end
	Ui.button(placePet, function()
		task.spawn(releasePet)
	end)
	-- The bar says what to do: go home first, or tap to let it out.
	task.spawn(function()
		while true do
			task.wait(0.3)
			if heldPet and not holding and gui.Enabled then
				local near = nearBase()
				titleLabel.Text = if not near then "Take it to your base"
					elseif Ui.gamepad() then "Press R2 to let it out!"
					else "Tap anywhere to let it out!"
				goBase.Visible = not near
			end
		end
	end)
	local petTouch: Vector2? = nil
	Ui.button(goBase, function()
		Net.func("Teleport"):InvokeServer("Base")
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		local cancel = input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Backspace or (input.KeyCode == Enum.KeyCode.ButtonB and not Ui.anyWindowOpen())
		if heldPet and not holding and cancel then
			stopPet()
			return
		end
		if heldPet and not holding and not processed then
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
				task.spawn(releasePet)
			elseif input.UserInputType == Enum.UserInputType.Touch then
				petTouch = Vector2.new(input.Position.X, input.Position.Y)
			end
			return
		end
		if not holding then
			return
		end
		if cancel then
			PlacementController:Stop()
			return
		end
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			pointer = nil
			place()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			pointer = Vector2.new(input.Position.X, input.Position.Y)
			touchStart = pointer
		end
	end)
	UserInputService.InputEnded:Connect(function(input, processed)
		local start = petTouch
		if heldPet and not holding and start and input.UserInputType == Enum.UserInputType.Touch then
			petTouch = nil
			-- A tap lets it out; a drag only turned the camera.
			if not processed and (Vector2.new(input.Position.X, input.Position.Y) - start).Magnitude <= TAP_SLOP then
				task.spawn(releasePet)
			end
			return
		end
		if holding and not processed and input.UserInputType == Enum.UserInputType.Touch and pointer then
			-- A tap places where the finger is; a drag only turned the camera.
			local now = Vector2.new(input.Position.X, input.Position.Y)
			local start = touchStart
			touchStart = nil
			if start and (now - start).Magnitude <= TAP_SLOP then
				pointer = now
				update()
				place()
			end
		end
	end)
	-- Equipping a tool or respawning puts the egg away.
	local function watch(character: Model)
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and (holding or heldPet) then
				PlacementController:Stop()
			end
		end)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				PlacementController:Stop(true)
				stopPet()
			end)
		end
	end
	local player = Players.LocalPlayer
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(watch)
	State.Changed:Connect(function(data)
		-- The egg left the bag some other way (auto place, sold...).
		if holding and data.Eggs and not data.Eggs[holding] then
			PlacementController:Stop(true)
		end
		-- The held pet was sold or placed.
		local pet = heldPet and data.Pets and data.Pets[heldPet]
		if heldPet and data.Pets and (not pet or pet.Placed) then
			stopPet(true)
		end
	end)
end

return PlacementController
