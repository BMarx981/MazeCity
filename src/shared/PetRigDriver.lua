-- PetRigDriver (ModuleScript) -> ReplicatedStorage.PetRigDriver
-- What a pet rig does from moment to moment: wings flap, ears twitch, tails
-- sway, rings ripple, eyes blink, and the two abilities that have a tell show it.
-- PetModelGenerator builds a rig once and stops; this drives the one it built,
-- which is the same split EnemyRig makes over ModelGenerator and it is here for
-- the same reason: eighty lines of joint trigonometry is not model building.
--
-- ============================================================
-- Three things about it that are decisions
-- ============================================================
-- **It writes Motor6D.Transform, never C0.** C0 is the as-built offset that
-- rigOf reads its bases back from, so a driver that wrote C0 would be writing
-- into its own measuring stick. Transform is the channel the engine reserves for
-- exactly this, it composes on top of C0 rather than replacing it, and it is
-- local to whoever writes it. Nothing here ever needs to put a joint back.
--
-- **It runs on the client.** PetAnimator drives every rig in workspace.LivePets
-- once a frame per machine; the server does not animate and does not know this
-- module exists. Motion is presentation, the recipes carrying its parameters are
-- already replicated (this file and PetCatalog are both shared), and the
-- alternative was a per-pet per-frame cost on the server beside the follow loop,
-- paid so that every client could receive joint transforms it can compute for
-- itself. PetService still owns where a pet is; this owns what it is doing there.
--
-- **It is pure.** No services, no yielding, no instances beyond the joints handed
-- to it and the parts those joints already point at, and `clock` arrives as an
-- argument rather than being read here. That is what lets tools/petlooks run it
-- outside Roblox over a simulated minute and check that nothing drifts, comes out
-- NaN or swings a wing further than a wing goes.
--
-- ============================================================
-- The baseline lives here
-- ============================================================
-- DEFAULT_MOTION below is to motion what PetModelGenerator's DEFAULT_LOOK is to
-- geometry, and it is here rather than in Config.Juice for the reason that plan
-- gave for the look vocabulary: editing a flap angle is editing how a pet is
-- built, not turning a knob between playtests. It also keeps the whole pet-look
-- family runnable under the luau CLI, which needs no MazeConfig stub as long as
-- nothing in it requires one. (The enemies put theirs in Config.Juice, and that
-- is not an inconsistency to fix: EnemyRig is a server module inside a system
-- whose every other number is already there.)
--
-- A recipe's `look.motion` overrides these key by key, with absolute values
-- rather than multipliers, because a rate you can read is worth more than a rate
-- you have to multiply out. It is the one look group read key by key rather than
-- replaced whole; PetModelGenerator's DEFAULT_LOOK says why.

local PetRigDriver = {}

local DEFAULT_MOTION = {
	-- The body nods and carries the whole rig with it, every part but the root
	-- being jointed to it. Small: the follower is already bobbing and turning
	-- under PetService's follow loop, and this reads on top of that rather than
	-- competing with it.
	breatheRate = 1.7, -- radians per second
	breatheAngle = 0.06, -- radians the body pitches
	headRate = 0.75,
	headAngle = 0.13, -- radians the head drifts off-body, looking around

	-- Wings. Rate and angle are separately named because they are the whole of a
	-- flier's identity: the Lumen Moth is slow and deep, the Coin Bat is fast and
	-- shallow, and those are the same two numbers in opposite corners.
	flapRate = 5.5,
	flapAngle = 0.42,

	swayRate = 2.2, -- tail
	swayAngle = 0.34,

	-- A twitch is off most of the time. A sine over the whole cycle is a pet
	-- permanently mid-twitch, which reads as a tic rather than as an ear.
	twitchEvery = 3.4, -- seconds between flicks
	twitchSeconds = 0.4, -- how long one takes
	twitchAngle = 0.34,

	antennaRate = 1.1,
	antennaAngle = 0.2,
	crestRate = 0.9,
	crestAngle = 0.1,

	-- Collars, halos and motes. ringWave is studs a bead rides outward on the
	-- ripple and is why a ring reads at all; see `ring` below.
	ringRate = 1.2, -- radians per second the ring turns
	ringWave = 0.13,

	charmRate = 1.5,
	charmBob = 0.14, -- studs a carried prop rises and falls
	charmBreath = 0.1, -- studs it drifts away from the body and back

	blinkEvery = 4.6,
	blinkSeconds = 0.12,

	-- Feet move in named gait groups instead of every leg sharing one bounce.
	-- This makes the Hound's diagonal pairs and the Moth's alternating tripods
	-- read as walking while paws remain aligned with their leg columns.
	stepRate = 5.2,
	stepAngle = 0.18,
	stepLift = 0.07,
}

-- The two ability tells, in multiples of the rest state so a pet with a strong
-- ability is the same pet doing more of what it already does.
--
-- Both are amplitudes and shapes, never rates, and that is a rule rather than a
-- preference. Everything here reads an absolute clock, so a phase computed as
-- `clock * rate` with a rate that changes while the pet is standing there turns
-- into an angular speed of `rate + clock * rateChange`: at an hour of uptime a
-- collar recharging over ten seconds would spin thousands of times a second. A
-- stateless driver may vary how far a thing moves and how the wave is shaped
-- around a ring, and may not vary how fast its clock runs.
local RING_SPREAD = 1.1 -- radians of wave between one bead and the next, at rest
local WARD_UP_WAVE = 2.4 -- how much wider a collar rides while the ward is up
local WARD_UP_SPREAD = 2.6 -- and how much tighter the wave wraps around it
local WARD_LOW_WAVE = 0.12 -- what it falls to on an empty charge, not a stop
local GLOW_BREATH = 2.6 -- how much further a lantern swings on a Glow pet

local function rate(motion, key)
	local value = motion and motion[key]
	if value ~= nil then
		return value
	end
	return DEFAULT_MOTION[key]
end

-- One smooth arc of `width` seconds every `every` seconds, and nothing at all in
-- between.
local function pulse(clock, every, width)
	local phase = clock % every
	if phase >= width then
		return 0
	end
	return math.sin(phase / width * math.pi)
end

-- A rotation about a point on the part rather than about its centre. Everything
-- that hangs off a pet is jointed at its middle, because that is where `place`
-- put it, so a wing turned as-is pivots halfway along its own span and reads as a
-- plate see-sawing rather than as a wing.
local function hinge(pivot, angles)
	return CFrame.new(pivot) * angles * CFrame.new(-pivot)
end

local function flap(motor, side, angle)
	if not motor or not motor.Part1 then
		return
	end
	local span = motor.Part1.Size.X / 2
	motor.Transform = hinge(Vector3.new(-side * span, 0, 0), CFrame.Angles(0, 0, side * angle))
end

local function twitch(motor, side, angle, lean)
	if not motor or not motor.Part1 then
		return
	end
	local height = motor.Part1.Size.Y / 2
	motor.Transform = hinge(Vector3.new(0, -height, 0), CFrame.Angles(lean, 0, -side * angle))
end

local function sway(motor, yaw, pitch)
	if not motor or not motor.Part1 then
		return
	end
	local reach = motor.Part1.Size.Z / 2
	motor.Transform = hinge(Vector3.new(0, 0, -reach), CFrame.Angles(pitch, yaw, 0))
end

local function wave(motor, side, angle, curl)
	if not motor or not motor.Part1 then
		return
	end
	local reach = motor.Part1.Size.Z / 2
	motor.Transform = hinge(Vector3.new(0, 0, reach), CFrame.Angles(curl, 0, side * angle))
end

local function offset(base, shift)
	return base:Inverse() * (CFrame.new(shift) * base)
end

local function outward(from, distance)
	local length = from.Magnitude
	if length < 0.001 then
		return Vector3.zero
	end
	return from * (distance / length)
end

local function gaitPhase(motor)
	local phase = motor:GetAttribute("PetGaitSide") == 1 and math.pi or 0
	local gait = motor:GetAttribute("PetGait")
	if gait == "houndBack" or gait == "mothMiddle" then
		return phase + math.pi
	end
	return phase
end

-- A ring turns about its own axis and rides a ripple outward from its centre.
-- Turning alone is invisible on the twelve identical beads of a collar, which is
-- why the ripple exists; turning is what reads on the four beads of a mote ring.
-- Both are needed and neither is decoration: the collar *is* the ward and the
-- motes *are* the Solar Firefly, so a still one is an ability that looks switched
-- off.
--
-- The centre is the mean of the beads' own base positions rather than the ring
-- spec's height and z, so this needs to know nothing about how the ring was
-- placed, and an upright ring turns about Z where a flat one turns about Y.
local function ring(motors, bases, upright, turn, ripple, phase, spread)
	local count = #motors
	if count == 0 then
		return
	end

	local centre = Vector3.zero
	for _, base in ipairs(bases) do
		centre = centre + base.Position
	end
	centre = centre * (1 / count)

	local spin = upright and CFrame.Angles(0, 0, turn) or CFrame.Angles(0, turn, 0)
	local about = CFrame.new(centre) * spin * CFrame.new(-centre)

	for index, motor in ipairs(motors) do
		local base = bases[index]
		-- Outward only. A ripple that pulled beads inward would put the back of a
		-- collar inside the ribs it was sized to clear, which is the exact failure
		-- tools/petlooks checks the recipes for at build time.
		local push = ripple * (0.5 + 0.5 * math.sin(phase - (index - 1) * spread))
		motor.Transform = base:Inverse() * (about * (CFrame.new(outward(base.Position - centre, push)) * base))
	end
end

-- `clock` is seconds and is the caller's to offset per rig: two of the same pet
-- side by side flapping in lockstep is one rig drawn twice.
--
-- `tell` is what the pet's ability is doing, and it is passed in rather than read
-- off the rig because this module has no business knowing that a ward publishes
-- an attribute. Both fields are optional:
--   tell.ward  = { up = boolean, charge = 0..1 } for a pet that wards
--   tell.glow  = true while a Glow light is on the rig
function PetRigDriver.animate(rig, clock, tell)
	local joints, bases, look = rig.joints, rig.bases, rig.look
	local motion = look.motion

	joints.body.Transform =
		CFrame.Angles(math.sin(clock * rate(motion, "breatheRate")) * rate(motion, "breatheAngle"), 0, 0)

	if joints.head then
		local headRate, headAngle = rate(motion, "headRate"), rate(motion, "headAngle")
		joints.head.Transform = CFrame.Angles(
			math.sin(clock * headRate * 0.7) * headAngle * 0.45,
			math.sin(clock * headRate) * headAngle,
			0
		)
	end

	if joints.wingL then
		local angle = math.sin(clock * rate(motion, "flapRate")) * rate(motion, "flapAngle")
		flap(joints.wingL, -1, angle)
		flap(joints.wingR, 1, angle)
	end

	-- Offset by half a cycle between the two, because a dog flicking both ears at
	-- once is a dog shaking its head.
	if joints.earL then
		local every, width = rate(motion, "twitchEvery"), rate(motion, "twitchSeconds")
		local angle = rate(motion, "twitchAngle")
		local left = pulse(clock, every, width)
		local right = pulse(clock + every / 2, every, width)
		twitch(joints.earL, -1, left * angle, left * angle * 0.4)
		twitch(joints.earR, 1, right * angle, right * angle * 0.4)
	end

	if joints.antennaL then
		local antennaRate, angle = rate(motion, "antennaRate"), rate(motion, "antennaAngle")
		wave(
			joints.antennaL,
			-1,
			math.sin(clock * antennaRate) * angle,
			math.sin(clock * antennaRate * 1.3) * angle * 0.5
		)
		wave(
			joints.antennaR,
			1,
			math.sin(clock * antennaRate + 0.8) * angle,
			math.sin(clock * antennaRate * 1.3 + 0.8) * angle * 0.5
		)
	end

	if joints.tail then
		local swayRate, angle = rate(motion, "swayRate"), rate(motion, "swayAngle")
		sway(joints.tail, math.sin(clock * swayRate) * angle, math.sin(clock * swayRate * 2) * angle * 0.25)
	end

	if joints.crest and joints.crest.Part1 then
		local crestRate, angle = rate(motion, "crestRate"), rate(motion, "crestAngle")
		local height = joints.crest.Part1.Size.Y / 2
		joints.crest.Transform = hinge(
			Vector3.new(0, -height, 0),
			CFrame.Angles(math.sin(clock * crestRate) * angle, 0, math.sin(clock * crestRate * 0.6) * angle)
		)
	end

	local ringRate, ringWave = rate(motion, "ringRate"), rate(motion, "ringWave")
	local turn, ripple = clock * ringRate, clock * ringRate * 2
	ring(joints.halo, bases.halo, look.halo and look.halo.upright, turn, ringWave, ripple, RING_SPREAD)
	ring(joints.motes, bases.motes, look.motes and look.motes.upright, turn, ringWave, ripple, RING_SPREAD)

	-- The collar is the ward made visible, so it carries the ward's state: a wide
	-- tight wave chasing round it while the ward is up, almost flat on an empty
	-- charge and swelling back as it recharges. A pet with no ward runs its collar
	-- at rest. The ring keeps turning at its own rate throughout, for the reason
	-- the tell constants give.
	local ward = tell and tell.ward
	local collarWave, collarSpread = ringWave, RING_SPREAD
	if ward then
		if ward.up then
			collarWave = ringWave * WARD_UP_WAVE
			collarSpread = RING_SPREAD * WARD_UP_SPREAD
		else
			collarWave = ringWave * (WARD_LOW_WAVE + (1 - WARD_LOW_WAVE) * ward.charge)
			collarSpread = RING_SPREAD * (1 + (WARD_UP_SPREAD - 1) * ward.charge)
		end
	end
	ring(joints.collar, bases.collar, look.collar and look.collar.upright, turn, collarWave, ripple, collarSpread)

	-- A carried prop breathes away from the body and back, and on a Glow pet it
	-- breathes a lot further: the lantern *is* the Glow, so the light having a
	-- pulse is the ability being legible without touching the PointLight, which
	-- is the server's and replicates once for everyone.
	local charmRate = rate(motion, "charmRate")
	local breath = rate(motion, "charmBreath") * ((tell and tell.glow) and GLOW_BREATH or 1)
	local bob = math.sin(clock * charmRate) * rate(motion, "charmBob")
	local reach = (0.5 + 0.5 * math.sin(clock * charmRate * 0.6)) * breath
	for index, motor in ipairs(joints.charms) do
		local base = bases.charms[index]
		motor.Transform = offset(base, outward(base.Position, reach) + Vector3.new(0, bob, 0))
	end

	for _, motor in ipairs(joints.steps) do
		local phase = clock * rate(motion, "stepRate") + gaitPhase(motor)
		local stride = math.sin(phase)
		local lift = math.max(0, stride) * rate(motion, "stepLift")
		motor.Transform = CFrame.new(0, lift, 0) * CFrame.Angles(stride * rate(motion, "stepAngle"), 0, 0)
	end

	-- A pet with no eyelids blinks by taking its eyes away: the joint sinks the
	-- eye back into the face for a tenth of a second and the pupil rides in on
	-- its own joint. Depth comes off the eye itself, so it is buried on a Ward
	-- Hound and on a Firefly a third the size.
	local blink = pulse(clock, rate(motion, "blinkEvery"), rate(motion, "blinkSeconds"))
	for _, motor in ipairs(joints.eyes) do
		if motor.Part1 then
			motor.Transform = CFrame.new(0, 0, blink * motor.Part1.Size.Z * 0.9)
		end
	end
end

return PetRigDriver
