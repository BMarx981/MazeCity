-- PetAnimator (LocalScript) -> StarterPlayer.StarterPlayerScripts
-- Drives the joints of every follower in workspace.LivePets, this machine's copy
-- of them, once a frame. PetRigDriver is the trigonometry; this is the loop, the
-- bookkeeping and the one thing the driver refuses to know, which is what a pet's
-- ability is doing right now.
--
-- Client rather than server, which is PET_LOOKS_PLAN's open decision settled. A
-- follower's position is the server's, because every player sees the same pet in
-- the same place and the maze it is crossing is authoritative. Its pose is not:
-- the recipes carrying the motion parameters are in ReplicatedStorage already,
-- the joints are on a rig every client has, and a wing angle nobody can act on
-- has no business being computed once and replicated N times. So the server pays
-- nothing for motion and this pays one CFrame per joint per visible pet.
--
-- Nothing here writes anything the server reads. Motor6D.Transform written on a
-- client is local to that client, and the server writes Transform on nothing, so
-- there is no channel for the two to disagree over.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local PetCatalog = require(ReplicatedStorage:WaitForChild("PetCatalog"))
local PetModelGenerator = require(ReplicatedStorage:WaitForChild("PetModelGenerator"))
local PetRigDriver = require(ReplicatedStorage:WaitForChild("PetRigDriver"))

if not Config.Pets.Enabled then
	return
end

local live = workspace:WaitForChild("LivePets")

-- model -> { model, rig, phase, tries, retryAt, ability, wardDroppedAt }
local rigs = {}

-- A rig arrives with its parts, but not necessarily in one replication step, so
-- rigOf is retried rather than trusted on the first frame. It also returns nil
-- forever for a model an artist put in ServerStorage/Pets: that model has its own
-- look and its own idea of how it moves, and nothing here should be driving it.
-- Both cases look identical from here, hence the try count rather than a warning.
local RETRY_SECONDS = 0.25
local MAX_TRIES = 12

-- Two of the same pet flapping in lockstep is one rig drawn twice, so each gets
-- its clock pushed along by a hash of its own name. Deterministic rather than
-- random: the same follower animates the same way on every machine watching it,
-- which costs nothing and means a bug is reproducible.
local function phaseOf(name)
	local hash = 0
	for index = 1, #name do
		hash = (hash * 31 + string.byte(name, index)) % 65536
	end
	return hash / 65536 * 10
end

local function abilityOf(model)
	local petConfig = PetCatalog[model:GetAttribute("PetId")]
	return petConfig and petConfig.ability or nil
end

local function track(model)
	if rigs[model] then
		return
	end
	rigs[model] = {
		model = model,
		rig = nil,
		phase = phaseOf(model.Name),
		tries = 0,
		retryAt = 0,
		ability = nil,
		wardDroppedAt = nil,
	}
end

for _, model in ipairs(live:GetChildren()) do
	track(model)
end
live.ChildAdded:Connect(track)
live.ChildRemoved:Connect(function(model)
	rigs[model] = nil
end)

-- The ward's state, rebuilt from the one thing that crosses the wire. PetService
-- publishes WardRadius on the rig while a ward is running and clears it when it
-- lapses; the recharge that follows is a fixed length on the pet's own catalogue
-- row, so the moment the attribute goes is enough to draw the bar filling back
-- up. Nothing new is replicated for this, and the reconstruction cannot drift
-- into a lie: a full collar means ready, and PetService only re-arms a ready
-- ward, so the worst case is a collar sitting full while the corridor is empty,
-- which is what ready looks like.
local function wardTell(entry, clock)
	local params = entry.ability.params or {}
	if entry.model:GetAttribute("WardRadius") then
		entry.wardDroppedAt = nil
		return { up = true, charge = 1 }
	end
	if not entry.wardDroppedAt then
		return { up = false, charge = 1 }
	end
	local recharge = params.rechargeSeconds or 10
	return { up = false, charge = math.clamp((clock - entry.wardDroppedAt) / recharge, 0, 1) }
end

local function tellFor(entry, clock)
	local ability = entry.ability
	if not ability then
		return nil
	end
	if ability.type == "Glow" then
		return { glow = true }
	end
	if ability.type == "Ward" then
		return { ward = wardTell(entry, clock) }
	end
	return nil
end

-- One pass over the followers in the server, culled to what this camera can
-- plausibly see. A rig outside the range keeps whatever pose it was left in,
-- which is correct: it is a hundred studs away and about to be behind a wall.
RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local range = Config.Pets.AnimateRange
	local clock = os.clock()

	for model, entry in pairs(rigs) do
		if not model.Parent then
			rigs[model] = nil
		else
			if not entry.rig and entry.tries < MAX_TRIES and clock >= entry.retryAt then
				entry.tries = entry.tries + 1
				entry.retryAt = clock + RETRY_SECONDS
				entry.rig = PetModelGenerator.rigOf(model)
				if entry.rig then
					entry.ability = abilityOf(model)
					-- Bound the attribute rather than polling it: a ward that lapses
					-- while its pet is off-camera still starts its recharge, so the
					-- collar is right the moment it comes back into range.
					if entry.ability and entry.ability.type == "Ward" then
						model:GetAttributeChangedSignal("WardRadius"):Connect(function()
							if not model:GetAttribute("WardRadius") then
								entry.wardDroppedAt = os.clock()
							end
						end)
					end
				end
			end

			local rig = entry.rig
			if rig and rig.joints.body.Parent then
				local at = model:GetPivot().Position
				if (at - eye).Magnitude <= range then
					PetRigDriver.animate(rig, clock + entry.phase, tellFor(entry, clock))
				end
			end
		end
	end
end)
