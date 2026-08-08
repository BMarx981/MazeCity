-- EnemyRig (ModuleScript) -> ServerScriptService.Enemy.EnemyRig
-- What a live rig looks and sounds like from moment to moment: the tell flash,
-- the fade a Lurker hides behind, its growl, its one-shot noises, and the joint
-- animation.
--
-- Not in the plan's file layout, and here for the same reason the animation
-- itself is not in the plan: it arrived in commit 7f259c3 after the plan was
-- written. EnemyService is bootstrap and registry now, and eighty lines of joint
-- trigonometry is not either of those. ModelGenerator builds a rig once and
-- stops; this drives the one it built.
--
-- Everything here is presentation and none of it decides anything. A behavior
-- calls flash to say a hit is coming; whether the hit lands is EnemyCombat's
-- answer and is checked again after the flash has played.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))

local EnemyRig = {}

function EnemyRig.playOnce(root, soundId, volume, pitch)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMaxDistance = Config.Juice.EnemyGrowlRange
	sound.Parent = root
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(4, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

function EnemyRig.makeGrowl(root)
	local growl = Instance.new("Sound")
	growl.Name = "Growl"
	growl.SoundId = Config.Sounds.EnemyGrowl
	growl.Volume = Config.Juice.EnemyGrowlVolume
	growl.Looped = true
	growl.RollOffMode = Enum.RollOffMode.Linear
	growl.RollOffMinDistance = Config.Juice.EnemyGrowlNearRange
	growl.RollOffMaxDistance = Config.Juice.EnemyGrowlRange
	growl.PlaybackSpeed = Config.Juice.EnemyGrowlPitchFar
	growl.Parent = root
	return growl
end

-- Repaints the skin for the length of the windup and puts the original colours
-- back. Reading them off the recorded skin rather than off the parts means a
-- second flash landing inside the first cannot make the first one's restore write
-- the flash colour back permanently, which is a thing that could happen when the
-- colours were sampled live. Eyes are excluded so there is still something legible
-- on a rig that has gone entirely red.
function EnemyRig.flash(controller, seconds)
	if controller.flashing then
		return
	end
	controller.flashing = true
	for _, item in ipairs(controller.skin) do
		if not string.find(item.part.Name, "Eye") then
			item.part.Color = Config.Juice.EnemyTellColor
		end
	end
	task.delay(seconds, function()
		controller.flashing = false
		if not controller.alive then
			return
		end
		for _, item in ipairs(controller.skin) do
			if item.part.Parent then
				item.part.Color = item.color
			end
		end
	end)
end

function EnemyRig.setHidden(controller, hidden)
	controller.hidden = hidden
	for _, item in ipairs(controller.skin) do
		if item.part.Parent then
			local base = item.transparency
			item.part.Transparency = hidden and math.max(base, Config.Juice.EnemyLurkerHiddenTransparency) or base
		end
	end
	local wisp = controller.model:FindFirstChild("Wisp", true)
	if wisp then
		wisp.Enabled = not hidden
	end
end

-- Tracks whether there is something to growl at, pitching up as it closes. Silent
-- otherwise: a city holds thousands of these and a permanent drone off every one
-- of them is not atmosphere, it is noise.
function EnemyRig.updateGrowl(controller)
	local growl = controller.growl
	local target = controller.target
	if not target then
		growl.Playing = false
		return
	end
	local juice = Config.Juice
	local distance = (target.Position - controller.root.Position).Magnitude
	local closeness = 1 - math.clamp(distance / controller.stats.leash, 0, 1)
	growl.Playing = true
	growl.PlaybackSpeed = juice.EnemyGrowlPitchFar + (juice.EnemyGrowlPitchNear - juice.EnemyGrowlPitchFar) * closeness
end

-- ============================================================
-- Animation
-- ============================================================

function EnemyRig.animate(controller, dt)
	local anim = controller.anim
	if not anim then
		return
	end
	-- Held while frozen, so a frozen enemy is frozen rather than a frozen enemy
	-- doing its idle bob.
	if controller.frozen then
		return
	end

	local juice = Config.Juice
	local joints, bases, look = anim.joints, anim.bases, anim.look
	controller.animClock = controller.animClock + dt
	-- bobRate and bobScale are the motion half of a type's identity: a Sentry
	-- barely moves at rest and a Swarmer never stops, which is legible further down
	-- a corridor than any of the geometry is.
	local phase = controller.animClock * juice.EnemyBobRate * look.bobRate + controller.phase
	local moving = math.clamp(controller.root.AssemblyLinearVelocity.Magnitude / 16, 0, 1)

	local bob = math.sin(phase) * juice.EnemyBobHeight * look.bobScale * (1 - moving * 0.4)
	joints.root.C0 = CFrame.new(0, bob, 0) * CFrame.Angles(-juice.EnemyLeanAngle * moving, 0, 0)

	-- Hands drift counter-phase to the body, which is what stops the whole rig
	-- reading as one rigid object going up and down.
	local orbit = math.sin(phase + math.pi) * juice.EnemyHandOrbit
	if joints.handL then
		joints.handL.C0 = bases.handL * CFrame.new(0, orbit, -orbit * 0.5)
		joints.handR.C0 = bases.handR * CFrame.new(0, -orbit, -orbit * 0.5)
	end
	if joints.core then
		joints.core.C0 = bases.core * CFrame.new(0, bob * 0.25, 0)
	end
	if joints.hood then
		joints.hood.C0 = bases.hood * CFrame.Angles(0, 0, math.sin(phase * 0.7) * 0.08)
	end

	local tailCount = #joints.tails
	for i, tail in ipairs(joints.tails) do
		local lag = i * 0.55
		local swing = math.sin(phase - lag) * juice.EnemyTailSway * (i / tailCount)
		tail.C0 = CFrame.Angles(0, 0, swing) * CFrame.Angles(swing * 0.4 * moving, 0, 0) * bases.tails[i]
	end

	-- A crown ripples around its ring rather than swaying as one piece, which is
	-- what makes the Lurker's tendrils read as hanging and the Sentry's spikes as
	-- idling rather than as a hat.
	for i, spike in ipairs(joints.crown) do
		local ripple = math.sin(phase * 0.8 - i * 0.9) * 0.12
		spike.C0 = bases.crown[i] * CFrame.Angles(ripple, 0, ripple * 0.5)
	end

	-- Motes orbit on their own clock. Evenly spaced around the ring and bobbing out
	-- of phase with each other, so three of them never line up into one blob.
	if look.motes and #joints.motes > 0 then
		local motes = look.motes
		local spin = controller.animClock * (motes.rate or 1.5)
		for i, mote in ipairs(joints.motes) do
			local angle = spin + (i - 1) / #joints.motes * math.pi * 2
			mote.C0 = CFrame.new(
				math.sin(angle) * motes.radius * look.scale,
				(motes.height + math.sin(phase + i) * 0.3) * look.scale,
				math.cos(angle) * motes.radius * look.scale
			)
		end
	end

	-- The head keeps the player in view independently of which way the body is
	-- walking, so a shade retreating to its post is still watching you go.
	local watching = controller.target
	if watching and watching.Parent then
		local dir = (watching.Position - controller.root.Position)
		if dir.Magnitude > 0.5 then
			local localDir = controller.torso.CFrame:VectorToObjectSpace(dir.Unit)
			local yaw = math.clamp(math.atan2(-localDir.X, -localDir.Z), -juice.EnemyLookYaw, juice.EnemyLookYaw)
			local pitch =
				math.clamp(math.asin(math.clamp(localDir.Y, -1, 1)), -juice.EnemyLookPitch, juice.EnemyLookPitch)
			joints.neck.C0 = bases.neck * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		end
	else
		joints.neck.C0 = bases.neck * CFrame.Angles(0, math.sin(phase * 0.35) * 0.4, 0)
	end
end

return EnemyRig
