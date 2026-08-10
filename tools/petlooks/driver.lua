-- Builds every pet at every stage and reports what came out, so Set 1's
-- geometry is checked before anyone presses Play.

local ids = {}
for petId in pairs(PetCatalog) do
	table.insert(ids, petId)
end
table.sort(ids)

local function finite(v)
	return v == v and v ~= math.huge and v ~= -math.huge
end

local failures = 0
local function check(cond, message)
	if not cond then
		failures = failures + 1
		print("   FAIL: " .. message)
	end
end

print(string.format("%-26s %5s %7s %7s %7s %7s %7s", "look", "parts", "width", "height", "depth", "lowY", "highY"))

for _, petId in ipairs(ids) do
	local petConfig = PetCatalog[petId]
	for stage = 0, #petConfig.evolutions do
		CREATED = {}
		local model = PetModelGenerator.build(petId, stage)
		local evolution = stage > 0 and petConfig.evolutions[stage] or nil
		local label = petConfig.name .. (evolution and (" " .. (evolution.displaySuffix or stage)) or "")

		local minX, maxX = math.huge, -math.huge
		local minY, maxY = math.huge, -math.huge
		local minZ, maxZ = math.huge, -math.huge
		local parts, attachments = 0, 0

		-- The body and head as ellipsoids, so an accent can be tested for being
		-- inside one. Every part here is a sphere mesh filling its Size, which is
		-- what makes the test exact rather than a bounding box guess.
		local solids = {}
		for _, inst in ipairs(CREATED) do
			if inst.ClassName == "Part" and (inst.Name == "Body" or inst.Name == "Head") then
				table.insert(solids, { p = inst.CFrame.Position, s = inst.Size })
			end
		end

		local function insideSolid(p)
			for _, solid in ipairs(solids) do
				local dx = (p.X - solid.p.X) / (solid.s.X / 2)
				local dy = (p.Y - solid.p.Y) / (solid.s.Y / 2)
				local dz = (p.Z - solid.p.Z) / (solid.s.Z / 2)
				if dx * dx + dy * dy + dz * dz < 1 then
					return true
				end
			end
			return false
		end

		for _, inst in ipairs(CREATED) do
			if inst.ClassName == "Attachment" then
				attachments = attachments + 1
				check(finite(inst.Position.Y), label .. ": attachment " .. inst.Name .. " has a non-finite position")
			elseif inst.ClassName == "Part" then
				parts = parts + 1
				local p, s = inst.CFrame.Position, inst.Size
				check(finite(p.X) and finite(p.Y) and finite(p.Z), label .. ": part " .. inst.Name .. " is at NaN")
				check(s.X > 0 and s.Y > 0 and s.Z > 0, label .. ": part " .. inst.Name .. " has a non-positive size")
				-- The accent groups are the ability made visible, so one buried in
				-- the chest is the ability going unread. Eyes and pupils are
				-- deliberately not tested: a pupil is supposed to sit on an eye.
				local accent = inst.Name:match("^Collar")
					or inst.Name:match("^Halo")
					or inst.Name:match("^Mote")
					or inst.Name:match("^Charm")
					or inst.Name == "Crest"
				if accent then
					check(
						not insideSolid(inst.CFrame.Position),
						label .. ": accent " .. inst.Name .. " is buried inside the body or head"
					)
				end
				if inst.Name ~= "Root" then
					minX, maxX = math.min(minX, p.X - s.X / 2), math.max(maxX, p.X + s.X / 2)
					minY, maxY = math.min(minY, p.Y - s.Y / 2), math.max(maxY, p.Y + s.Y / 2)
					minZ, maxZ = math.min(minZ, p.Z - s.Z / 2), math.max(maxZ, p.Z + s.Z / 2)
				end
			end
		end

		-- Motion, checked against the same silhouette the geometry was. A minute of
		-- it runs here in milliseconds because animate reads no clock of its own,
		-- and the two things it can get wrong are both caught by asking where a
		-- part actually ends up: an accent that swings into the chest it was placed
		-- to clear, and a hinge with a sign error that throws one across the room.
		--
		-- The tell is driven through every state a pet can be in rather than left
		-- at rest, because a running ward is the one that moves furthest.
		local rig = PetModelGenerator.rigOf(model)
		check(rig ~= nil, label .. ": rigOf read back nothing from a rig this module built")
		if rig then
			local body = model:FindFirstChild("Body")
			-- Accents are tested for burying themselves as well as for leaving the
			-- silhouette; a wing is not, its root being inside the body by design.
			-- Eyes are left out of both: a blink is an eye going inside the head on
			-- purpose.
			local watched = {}
			local function watch(motors, motorBases, accent)
				for index, motor in ipairs(motors) do
					table.insert(watched, { motor = motor, base = motorBases[index], accent = accent })
				end
			end
			local function watchOne(motor, base, accent)
				if motor then
					table.insert(watched, { motor = motor, base = base, accent = accent })
				end
			end
			watch(rig.joints.collar, rig.bases.collar, true)
			watch(rig.joints.halo, rig.bases.halo, true)
			watch(rig.joints.motes, rig.bases.motes, true)
			watch(rig.joints.charms, rig.bases.charms, true)
			watchOne(rig.joints.crest, rig.bases.crest, true)
			watchOne(rig.joints.wingL, rig.bases.wingL, false)
			watchOne(rig.joints.wingR, rig.bases.wingR, false)
			watchOne(rig.joints.earL, rig.bases.earL, false)
			watchOne(rig.joints.earR, rig.bases.earR, false)
			watchOne(rig.joints.antennaL, rig.bases.antennaL, false)
			watchOne(rig.joints.antennaR, rig.bases.antennaR, false)
			watchOne(rig.joints.tail, rig.bases.tail, false)

			local function poseAt(clock, tell)
				PetRigDriver.animate(rig, clock, tell)
				local at = {}
				for index, item in ipairs(watched) do
					at[index] = (body.CFrame * (item.base * item.motor.Transform)).Position
				end
				return at
			end

			-- Two frames two milliseconds apart, ten hours into a session, with a
			-- ward recharging across them. Nothing may have moved more than a tenth
			-- of a stud, and this is the only check here that would have caught the
			-- driver's first draft: it slowed the collar as the ward drained, and a
			-- phase of `clock * rate` with a rate that moves has an angular speed of
			-- `rate + clock * rateChange`, which at ten hours is thousands of turns a
			-- second. From a clock starting at zero it looks perfectly correct, which
			-- is why the pass below is not enough on its own.
			local HOURS = 36000
			local STEP = 0.002
			local before = poseAt(HOURS, { glow = true, ward = { up = false, charge = 0.5 } })
			local after = poseAt(HOURS + STEP, { glow = true, ward = { up = false, charge = 0.5 + STEP / 10 } })
			for index, item in ipairs(watched) do
				local moved = (after[index] - before[index]).Magnitude
				check(
					finite(moved) and moved < 0.1,
					label .. ": " .. item.motor.Name .. string.format(" moved %.2f studs in 2ms ten hours in", moved)
				)
			end

			for step = 0, 240 do
				local clock = step / 4
				local ward = { up = step % 8 < 3, charge = (step % 40) / 40 }
				PetRigDriver.animate(rig, clock, { glow = true, ward = ward })

				for _, item in ipairs(watched) do
					local at = (body.CFrame * (item.base * item.motor.Transform)).Position
					local name = item.motor.Name
					check(
						finite(at.X) and finite(at.Y) and finite(at.Z),
						label .. ": " .. name .. " reaches NaN at " .. clock .. "s"
					)
					if item.accent then
						check(
							not insideSolid(at),
							label .. ": accent " .. name .. " swings inside the body at " .. clock .. "s"
						)
					end
					-- A stud of slack on the silhouette it was built with. Motion is
					-- meant to be read at corridor distance, not to redraw the pet.
					check(
						at.X > minX - 1 and at.X < maxX + 1 and at.Y > minY - 1 and at.Y < maxY + 1,
						label .. ": " .. name .. " leaves the silhouette at " .. clock .. "s"
					)
				end
			end
		end

		check(model.PrimaryPart ~= nil, label .. ": no PrimaryPart")
		check(attachments == 4, label .. ": " .. attachments .. " slot attachments, expected 4")
		check(model:GetAttribute("PetId") == petId, label .. ": PetId attribute missing")
		check(model:GetAttribute("PetStage") == stage, label .. ": PetStage attribute missing")

		-- MazeGenerator.CFG: CELL 25, WALL_THICKNESS 2, so a corridor is 23 studs
		-- of clear floor. A follower is anchored and non-colliding and will pass
		-- through a wall regardless; this is about a pet that visibly does.
		check(maxX - minX < 23, label .. string.format(": %.2f studs wide, wider than a corridor", maxX - minX))

		print(
			string.format(
				"%-26s %5d %7.2f %7.2f %7.2f %7.2f %7.2f",
				label,
				parts,
				maxX - minX,
				maxY - minY,
				maxZ - minZ,
				minY,
				maxY
			)
		)
	end
end

print("")
if failures > 0 then
	-- Level 0 so the message is the message rather than a stack trace, and so
	-- the CLI exits non-zero: this is meant to be runnable as a check, not only
	-- read.
	error(failures .. " failures", 0)
end
print("all looks built, no failures")
