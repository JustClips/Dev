--!strict
-- Boots client controllers: all Init() first, then all Start().
local Client = script.Parent
local State = require(Client:WaitForChild("State"))
local Ui = require(Client:WaitForChild("Ui"))

-- LoadingController comes first so its Init puts the loading screen up right away.
local ORDER = {
	"LoadingController",
	"HudController",
	"FlyController",
	"HotbarController",
	"LeafController",
	"DumpController",
	"CoinController",
	"DropController",
	"MerchantController",
	"ChatController",
	"BackpackController",
	"HoldPoseController",
	"SweepController",
	"ToolFxController",
	"ToolGroundController",
	"ZoneController",
	"ArrowController",
	"HatchController",
	"ShopController",
	"IndexController",
	"InventoryController",
	"PlacementController",
	"PromptController",
	"ConfirmController",
	"PetInfoController",
	"EggLabelController",
	"DialogController",
	"TraderController",
	"HoverController",
	"AudioController",
	"TutorialController",
	"QuestController",
	"BasePanelsController",
	"RewardsController",
	"GroupRewardController",
	"WheelController",
	"CodesController",
	"RebirthController",
	"OfferController",
	"FavoriteController",
	"FollowerController",
	"VehicleController",
	"PetController",
	"EnemyController",
	"GarageController",
	"BasePickerController",
	"UpgradeController",
	"WeatherController",
	"FountainController",
	"SpinController",
	"BroadcastController",
	"AdminController",
	"GamepadController",
}

local folder = Client:WaitForChild("Controllers")
local controllers: { [string]: any } = {}
for _, name in ORDER do
	controllers[name] = require(folder:WaitForChild(name) :: ModuleScript)
end

State.init()
Ui.initScaling()
for _, name in ORDER do
	local controller = controllers[name]
	if controller.Init then
		controller:Init(controllers)
	end
end
for _, name in ORDER do
	local controller = controllers[name]
	if controller.Start then
		task.spawn(controller.Start, controller)
	end
end
