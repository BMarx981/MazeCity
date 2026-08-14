-- ZipRider (LocalScript) -> StarterPlayer.StarterPlayerScripts
-- The rider's own half of the roof zipline: the camera, and the one decision
-- the rider gets to make.
--
-- Everything here is presentation or input. The ride itself is the server's,
-- the curve is ZipPath's, and this script knows neither: the payload carries
-- the ride's speed ramp as three numbers and nothing else, so the camera is
-- extrapolated on this machine the same way AbilityGui extrapolates the charge
-- between pushes. A camera driven by a stream of per-frame updates would be a
-- feed nobody else needs, and it would stutter at exactly the moment it is
-- meant to look fast.
--
-- The camera is not taken over. CameraType stays Custom and the player keeps
-- their mouse look the whole way down; what changes is the field of view, and
-- Humanoid.CameraOffset, which the default camera already honours. Going
-- Scriptable would give finer control over the roll and take the player's own
-- camera away from them for six seconds to get it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local UiTheme = require(ReplicatedStorage:WaitForChild("UiTheme"))

local Updates = ReplicatedStorage:WaitForChild("TraversalUpdate")
local Intents = ReplicatedStorage:WaitForChild("TraversalIntent")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ride = nil
local connection = nil

-- One chip, bottom centre, on the same slabs as the rest of the HUD. It exists
-- because letting go is a verb with no pedestal, no purchase and no shop row:
-- a player who is never told is a player for whom the wrap is a cutscene.
local gui = Instance.new("ScreenGui")
gui.Name = "ZipRiderGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local hint = UiTheme.chip(gui, UDim2.new(0, 190, 0, 34), UDim2.new(0.5, 0, 1, -108), { anchor = Vector2.new(0.5, 0) })
local hintLabel = UiTheme.label(hint, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), UiTheme.BodyBold, 14, UiTheme.Rune)
hintLabel.Text = "Jump to let go"

local function characterParts()
	local character = player.Character
	if not character then
		return nil, nil
	end
	return character:FindFirstChild("HumanoidRootPart"), character:FindFirstChildOfClass("Humanoid")
end

local function releaseCamera(punch)
	local _, humanoid = characterParts()
	if humanoid then
		humanoid.CameraOffset = Vector3.zero
	end

	local baseFov = ride and ride.baseFov or camera.FieldOfView
	if punch and punch > 0 then
		-- A dismount is the one moment the camera is allowed to shout. It kicks
		-- out and settles back, rather than easing down from wherever the ramp
		-- had got to, so letting go at speed feels different from arriving.
		camera.FieldOfView = baseFov + punch
	end
	TweenService:Create(
		camera,
		TweenInfo.new(Config.Juice.ZipCameraReleaseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = baseFov }
	):Play()
end

local function stop(reason)
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if not ride then
		return
	end
	local punch = (reason == "dismount") and Config.Juice.ZipCameraDismountPunch or 0
	releaseCamera(punch)
	ride = nil
	gui.Enabled = false
end

local function step(dt)
	local root, humanoid = characterParts()
	if not root or not humanoid or not ride then
		stop("lost")
		return
	end

	local elapsed = os.clock() - ride.startedAt
	local speed = math.min(ride.speedMax, ride.speedStart + ride.accel * elapsed)
	local pace = (speed - ride.speedStart) / math.max(1, ride.speedMax - ride.speedStart)
	camera.FieldOfView = ride.baseFov + Config.Juice.ZipCameraFovGain * pace

	-- The rider is anchored and moved by the server, so their velocity is not on
	-- the assembly to be read: it is the difference between where they were last
	-- frame and where they are now. That difference is what the corkscrew is,
	-- and dragging the camera against its sideways part is what makes a turn
	-- something the camera is being pulled through rather than something drawn
	-- in front of it.
	local position = root.Position
	if ride.lastPosition and dt > 0 then
		local velocity = (position - ride.lastPosition) / dt
		local sideways = root.CFrame:VectorToObjectSpace(velocity)
		local target = Vector3.new(-sideways.X, -sideways.Y, 0) * Config.Juice.ZipCameraLag
		if target.Magnitude > Config.Juice.ZipCameraLagMax then
			target = target.Unit * Config.Juice.ZipCameraLagMax
		end
		local alpha = math.min(1, dt * Config.Juice.ZipCameraLagSmoothing)
		humanoid.CameraOffset = humanoid.CameraOffset:Lerp(target, alpha)
	end
	ride.lastPosition = position
end

Updates.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.kind == "zipStart" then
		stop("restart")
		ride = {
			startedAt = os.clock(),
			-- Taken from the camera as it is now, never from a number in the
			-- config: a player who has set their own field of view has to get
			-- that one back at the bottom.
			baseFov = camera.FieldOfView,
			speedStart = payload.speedStart,
			speedMax = payload.speedMax,
			accel = payload.accel,
		}
		gui.Enabled = true
		connection = RunService.RenderStepped:Connect(step)
	elseif payload.kind == "zipEnd" then
		stop(payload.reason)
	end
end)

-- JumpRequest rather than the jump key, because it is the one signal every
-- input device already funnels into: keyboard, gamepad and the mobile jump
-- button all arrive here, and the rider is under PlatformStand so none of them
-- is going to make the humanoid jump instead.
UserInputService.JumpRequest:Connect(function()
	if ride then
		Intents:FireServer({ kind = "dismount" })
	end
end)

-- A death mid-ride ends it server-side, but the camera is this machine's and
-- nothing else would hand it back.
player.CharacterAdded:Connect(function()
	stop("respawn")
end)
