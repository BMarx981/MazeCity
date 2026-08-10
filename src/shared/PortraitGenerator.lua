-- PortraitGenerator (ModuleScript) -> ReplicatedStorage.PortraitGenerator
-- A ViewportFrame of a model a client built for itself, drawn from the same
-- recipes the server spawns from. This is the payoff of the generators living
-- in src/shared (plan decision D11): the client builds the rig locally, so a
-- bestiary card, an inventory row or a hatch reveal costs the server nothing
-- and needs no replicated template folder.
--
-- Two entry points and the split is the whole design. `of` frames a model that
-- is already built and knows nothing about what made it; `portrait` is the
-- enemy convenience over ModelGenerator. Pets go through `of` with a
-- PetModelGenerator rig, which is why this module requires one generator and
-- not both: framing a model is geometry, and coupling it to every generator in
-- the game would be a require per silhouette family for no shared code.
--
-- The frame is self-contained: its own WorldModel, its own Camera framed off
-- the model's bounding box at a three-quarter angle, lit from the camera's
-- side. Pass spin to have the model turn slowly in place; the connection is
-- cut when the frame is destroyed, and asking for one on the server is an
-- error because RenderStepped is a client clock.
--
-- The Humanoid and any billboard are stripped from the model. Neither renders
-- in a viewport, and a portrait is a picture rather than a thing that could
-- wake up.

local RunService = game:GetService("RunService")

local ModelGenerator = require(script.Parent:WaitForChild("ModelGenerator"))

-- A narrow lens flatters a small model: less perspective distortion on
-- something two studs wide. Padding is the air around the silhouette, and the
-- pose angles are the three-quarter turn every portrait holds.
local FIELD_OF_VIEW = 40
local PADDING = 1.15
local POSE_YAW = math.rad(35)
local POSE_PITCH = math.rad(-12)
local SPIN_RATE = math.rad(40)

local PortraitGenerator = {}

-- Returns a ViewportFrame showing model, which this takes ownership of.
-- opts.spin turns it slowly; everything else about the frame (size, position,
-- background) is the caller's to set, which is why none of it is set here.
function PortraitGenerator.of(model, opts)
	opts = opts or {}

	local frame = Instance.new("ViewportFrame")
	frame.Name = model.Name .. "Portrait"
	frame.BackgroundTransparency = 1
	frame.Ambient = Color3.fromRGB(140, 140, 150)
	frame.LightColor = Color3.fromRGB(255, 255, 245)

	local world = Instance.new("WorldModel")
	world.Parent = frame

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
		-- Both generators hand back loose parts on joints and a viewport steps no
		-- physics to hold them together, so anchoring is what makes a portrait a
		-- picture. A follower in the world is posed by PetRigDriver writing those
		-- joints; a portrait deliberately is not, being a thing a player reads
		-- rather than watches. The reveal turns the model instead.
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	model:PivotTo(CFrame.new())
	model.Parent = world

	local boundsCF, boundsSize = model:GetBoundingBox()
	local radius = math.max(boundsSize.Magnitude / 2, 0.5)
	local distance = (radius * PADDING) / math.tan(math.rad(FIELD_OF_VIEW / 2))
	local pose = CFrame.fromEulerAnglesYXZ(POSE_PITCH, POSE_YAW, 0)
	local cameraPosition = boundsCF.Position + pose:VectorToWorldSpace(Vector3.new(0, 0, distance))

	local camera = Instance.new("Camera")
	camera.FieldOfView = FIELD_OF_VIEW
	camera.CFrame = CFrame.lookAt(cameraPosition, boundsCF.Position)
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.LightDirection = (boundsCF.Position - cameraPosition).Unit

	if opts.spin then
		assert(RunService:IsClient(), "PortraitGenerator: spin needs a client clock")
		local base = model:GetPivot()
		local turned = 0
		local connection = RunService.RenderStepped:Connect(function(dt)
			turned = turned + dt * SPIN_RATE
			model:PivotTo(base * CFrame.Angles(0, turned, 0))
		end)
		frame.Destroying:Connect(function()
			connection:Disconnect()
		end)
	end

	return frame
end

function PortraitGenerator.portrait(typeName, opts)
	return PortraitGenerator.of(ModelGenerator.build(typeName), opts)
end

return PortraitGenerator
