-- LoreGui (LocalScript) -> StarterPlayer.StarterPlayerScripts
-- The unlock toast for the Cartographer's Trail, per docs/LORE.MD 9.2. Draws one
-- thing and reads no tags: LoreService says a fragment unlocked and this is what
-- that looks like.
--
-- **It is a toast and deliberately not a banner.** UiTheme.banner is the game's
-- celebration and it lands in the middle of the screen, which is the right shape
-- for topping out a tower and the wrong one for finding a wall writing halfway up
-- one: a discovery must never be something a player has to wait out or read
-- through a moving wall. So this is a chip on the free left edge, sliding in from
-- off-screen and back out on its own clock, at the one height nothing else in the
-- HUD uses. The top centre is the floor chip, the right column is score, coins,
-- powerup and ability, the bottom centre is the ability selector and the bottom
-- right is sprint.
--
-- Fragments arrive in runs, which is what banking is for: a player whose fifth
-- summit satisfies three fragments at once gets three of these in a row rather
-- than two drawn on top of each other. Hence the queue, and hence the payload
-- carrying its own index and total so a toast says where in the seventeen it
-- landed without this file holding a count it would have to keep in step.
--
-- Three payload kinds reach the queue and the fourth, the Codex projection, is
-- not one: this file draws moments and CodexGui draws state, off the same
-- remote for the reason PetService's is one remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local UiTheme = require(ReplicatedStorage:WaitForChild("UiTheme"))

local remote = ReplicatedStorage:WaitForChild("LoreUpdate")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WIDTH = 320
local HEIGHT = 132
local EDGE = 18
local Y = 0.54

local gui = Instance.new("ScreenGui")
gui.Name = "LoreGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local chip = UiTheme.chip(gui, UDim2.fromOffset(WIDTH, HEIGHT), UDim2.new(0, -WIDTH, Y, 0), { seam = true })
chip.Visible = false

local kicker = UiTheme.label(chip, UDim2.new(1, -28, 0, 16), UDim2.new(0, 14, 0, 10), UiTheme.Body, 12, UiTheme.Rune)
kicker.TextXAlignment = Enum.TextXAlignment.Left

local day = UiTheme.label(chip, UDim2.new(1, -28, 0, 30), UDim2.new(0, 14, 0, 26), UiTheme.Display, 26)
day.TextXAlignment = Enum.TextXAlignment.Left

-- Chalk rather than the body Text colour: it is somebody else's handwriting, and
-- the Lantern is the same face the world's plates letter a place name in.
local body = UiTheme.label(chip, UDim2.new(1, -28, 0, 60), UDim2.new(0, 14, 0, 58), UiTheme.Body, 14, UiTheme.Lantern)
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.TextWrapped = true

local queue = {}
local showing = false

local function present(payload)
	if payload.kind == "completed" then
		-- The end of the trail, and it is still a chip: the last fragment landed
		-- as one a moment before this and answering it with a banner would be the
		-- game shouting over the sentence the player is reading.
		kicker.Text = string.format("Journal %d/%d   The trail ends", payload.total, payload.total)
		day.Text = payload.title
		body.Text = "The Cartographer's own companion is at the Nest. The Codex has the whole of it."
	elseif payload.kind == "caughtUp" then
		-- The join summary. One line for a whole backlog, because everything in it
		-- was earned in an earlier session and a run of toasts for old news is a
		-- run of toasts for old news.
		kicker.Text = string.format("Journal %d/%d", payload.index, payload.total)
		day.Text = payload.count == 1 and "1 writing" or (payload.count .. " writings")
		body.Text = "Found on earlier climbs. The Codex has them."
	else
		kicker.Text = string.format("New wall writing   Journal %d/%d", payload.index, payload.total)
		day.Text = "Day " .. tostring(payload.day)
		body.Text = payload.text
	end

	chip.Visible = true
	chip.Position = UDim2.new(0, -WIDTH, Y, 0)
	UiTheme.tween(chip, 0.28, { Position = UDim2.new(0, EDGE, Y, 0) })
	UiTheme.playSound(Config.Sounds.JournalUnlock, 0.35, 0.45)
end

local function pump()
	if showing then
		return
	end
	local payload = table.remove(queue, 1)
	if not payload then
		return
	end
	showing = true
	present(payload)

	task.delay(Config.Lore.ToastSeconds, function()
		UiTheme.tween(chip, 0.35, { Position = UDim2.new(0, -WIDTH, Y, 0) })
		task.delay(0.35 + Config.Lore.ToastGapSeconds, function()
			chip.Visible = false
			showing = false
			pump()
		end)
	end)
end

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind ~= "unlocked" and payload.kind ~= "caughtUp" and payload.kind ~= "completed" then
		return
	end
	table.insert(queue, payload)
	pump()
end)

-- ============================================================
-- Wall writings
-- ============================================================
-- The other half of LORE.MD 9.2 and the substance of PETS_PLAN.md Clutch 7
-- unit 4: an unlocked fragment written on the maze itself, in the Cartographer's
-- own hand, for the player who earned it and for nobody standing next to them.
--
-- **It cannot be generation and that is the whole shape of this.** LORE.MD wrote
-- it as a spawn during generation, which two rules of this repo forbid at once:
-- MazeGenerator is deterministic and per section while an unlocked-only writing
-- is per player, so baking one in would break invariant 6 and the "two players
-- see different writings" property in the same stroke. So it is a client draw
-- over geometry the server already built, the way TimerGui draws its route
-- markers, in a model beside MazeCity and never inside it.
--
-- **A wall is chosen by hashing its own position, not by rolling.** Positions are
-- a pure function of the world seed, so the same wall carries a writing on every
-- machine and in every session: coming back down a corridor shows the same line,
-- and what differs between two players is which fragment it is, because the pool
-- is what they have unlocked. That is exactly the social property LORE.MD wanted
-- and it costs no randomness, no server state and nothing on the wire.
--
-- What crosses from the server is one number, the replicated `JournalUnlocked`
-- attribute. The seventeen lines are content in ReplicatedStorage.Journal, which
-- this client already has, so a rejoining player's maze is written on before
-- their first frame with nothing requested. The remote is still the toast's, a
-- moment being a different thing from a state.
--
-- The one host that is not a maze wall is the roost, for the one fragment marked
-- `nestOnly`: the story ends where every run of the player's own ends, which is
-- the only reason that flag is in the content at all.

local CollectionService = game:GetService("CollectionService")

local Journal = require(ReplicatedStorage:WaitForChild("Journal"))

-- MazeGenerator.WALL_GROUP, held as a literal here for the same reason the
-- generator holds copies of this theme's colours: the dependency runs one way,
-- and a client UI script must not require a server module to ask a question.
-- Invariant 7 is what makes the question askable at all: containment is a
-- property of which function built the part, so a part in this group is a maze
-- wall by construction and a facade, slab, stair or parapet never is.
local WALL_GROUP = "MazeWall"

local writings = nil
local drawn = {}
local pool = {}
local nestFragment = nil
local pooledFor = -1

local overlapParams = OverlapParams.new()
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function clearWritings()
	drawn = {}
	if writings then
		writings:Destroy()
		writings = nil
	end
end

-- Rebuilt only when the count moves, and clearing on that is not tidiness: a
-- wall's fragment is its hash taken against the pool, so a pool that grew is a
-- corridor whose writings all say something else now.
local function rebuildPool()
	local unlocked = math.floor(player:GetAttribute("JournalUnlocked") or 0)
	if unlocked == pooledFor then
		return
	end
	pooledFor = unlocked
	pool = {}
	nestFragment = nil
	for i = 1, math.min(unlocked, #Journal) do
		local fragment = Journal[i]
		if fragment.nestOnly then
			nestFragment = fragment
		else
			table.insert(pool, fragment)
		end
	end
	clearWritings()
end

-- Any three integers to one, mixed so that neighbouring walls land nowhere near
-- each other in the sequence: a hash that kept them adjacent would write on a
-- whole corridor at once or on none of it. bit32 rather than an operator, per
-- the repo's luac-parseable rule.
local function siteHash(position)
	local x = math.floor(position.X + 0.5) % 4096
	local y = math.floor(position.Y + 0.5) % 4096
	local z = math.floor(position.Z + 0.5) % 4096
	return bit32.bxor(x * 73856093, y * 19349663, z * 83492791)
end

-- The face a writing goes on, or nil for a wall that has none free. Two things
-- are decided here and both are geometry the client can read off the part alone.
--
-- The **normal** is the thin horizontal axis, because a maze wall is a panel and
-- a panel has one. Which of its two sides is the hash's, so a wall shows its
-- writing on the same side every visit rather than on whichever side it was
-- first walked past; the other side is the fallback, which is what keeps a
-- boundary wall's writing out of the apron.
--
-- The **height band** is the floor filter, and it is the reason this file names
-- no LEVEL_HEIGHT. A wall only carries a writing if its own vertical extent
-- contains the band the writing would occupy, so a wall a storey up or down is
-- rejected by the same test that stops a writing hanging off the top of one.
--
-- The same test sideways is not decoration either: a wall run is a cell and a
-- bit, but the two panels flanking a doorway are what is left of one after the
-- opening is taken out, and a writing wider than the panel it is on is a
-- sentence hanging in a doorway.
local function faceFor(part, hash, writeY)
	local size = part.Size
	local cf = part.CFrame
	local normal, half, run
	if size.X <= size.Z then
		normal, half, run = cf.RightVector, size.X / 2, size.Z
	else
		normal, half, run = cf.LookVector, size.Z / 2, size.X
	end

	local band = Config.Lore.WritingHeight / 2
	if math.abs(writeY - part.Position.Y) + band > size.Y / 2 or run < Config.Lore.WritingWidth then
		return nil
	end

	if bit32.band(hash, 1) == 1 then
		normal = -normal
	end

	local base = Vector3.new(part.Position.X, writeY, part.Position.Z)
	for _ = 1, 2 do
		local origin = base + normal * (half + 0.05)
		if not workspace:Raycast(origin, normal * Config.Lore.WritingClearance, rayParams) then
			local centre = base + normal * (half + Config.Lore.WritingLift)
			return CFrame.lookAt(centre, centre + normal)
		end
		normal = -normal
	end
	return nil
end

-- The fragment, drawn as the toast draws it minus the stone: the dateline in the
-- Display face under its rune rule, the sentence in Lantern, which is the colour
-- the toast already uses for somebody else's handwriting. No chip, no border and
-- no index, because a wall writing is a thing found in the world and a HUD
-- readout painted on a wall is a sign.
local function letter(surface, fragment)
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 24
	surface.LightInfluence = 0
	surface.MaxDistance = Config.Lore.WritingRange

	local dateline = UiTheme.label(surface, UDim2.new(1, -24, 0.26, 0), UDim2.new(0, 12, 0, 6), UiTheme.Display, 40)
	dateline.TextXAlignment = Enum.TextXAlignment.Left
	dateline.Text = "Day " .. tostring(fragment.day)
	dateline.TextTransparency = 0.05
	UiTheme.wordmark(dateline)

	local sentence =
		UiTheme.label(surface, UDim2.new(1, -24, 0.66, 0), UDim2.new(0, 12, 0.32, 0), UiTheme.Body, 24, UiTheme.Lantern)
	sentence.TextXAlignment = Enum.TextXAlignment.Left
	sentence.TextYAlignment = Enum.TextYAlignment.Top
	sentence.TextWrapped = true
	sentence.TextTransparency = 0.12
	sentence.Text = fragment.text
end

local function inscribe(fragment, cframe, twoSided)
	if not writings then
		writings = Instance.new("Model")
		writings.Name = "WallWritings"
		writings.Parent = workspace
	end

	local slab = Instance.new("Part")
	slab.Name = "WallWriting"
	slab.Anchored = true
	slab.CanCollide = false
	slab.CanTouch = false
	-- False, and load-bearing twice: the sweep below would otherwise find this
	-- client's own writings, and the clearance ray above would find the writing
	-- already standing where it is asking about.
	slab.CanQuery = false
	slab.CastShadow = false
	slab.Transparency = 1
	slab.Size = Vector3.new(Config.Lore.WritingWidth, Config.Lore.WritingHeight, 0.05)
	slab.CFrame = cframe
	slab.Parent = writings

	local faces = twoSided and { Enum.NormalId.Front, Enum.NormalId.Back } or { Enum.NormalId.Front }
	for _, face in ipairs(faces) do
		local surface = Instance.new("SurfaceGui")
		surface.Face = face
		surface.Parent = slab
		letter(surface, fragment)
	end
	return slab
end

-- The roost writing stands beside the pedestal rather than on it, a fragment on
-- a five stud plinth being a fragment nobody can read, and it is lettered on both
-- faces because the roof is walked round and a wall is not.
local function nestCFrame(pedestal)
	local deck = pedestal.Position.Y - pedestal.Size.Y / 2
	local centre = Vector3.new(
		pedestal.Position.X,
		deck + Config.Lore.WritingHeight / 2 + Config.Lore.WritingLift,
		pedestal.Position.Z - (pedestal.Size.Z / 2 + Config.Lore.NestWritingOffset)
	)
	return CFrame.lookAt(centre, centre + Vector3.new(0, 0, -1))
end

-- One broadphase query per tick, which is the bargain PickupService's magnet and
-- TimerGui's phantom sense already struck: a pregenerated city holds tens of
-- thousands of walls and at most a handful are ever near anybody. Writings are
-- diffed rather than rebuilt, so a player standing still is not respawning parts
-- three times a second.
local function updateWritings()
	rebuildPool()

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or (#pool == 0 and not nestFragment) then
		clearWritings()
		return
	end

	rayParams.FilterDescendantsInstances = { char }
	local writeY = root.Position.Y + Config.Lore.WritingRise
	local here = {}

	for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, Config.Lore.WritingRange, overlapParams)) do
		local fragment, cframe, twoSided
		if nestFragment and CollectionService:HasTag(part, "EggPedestal") then
			fragment, cframe, twoSided = nestFragment, nestCFrame(part), true
		elseif #pool > 0 and part.CollisionGroup == WALL_GROUP then
			-- A moving wall would leave its writing behind and a phantom is the one
			-- wall a player is meant to be reading for itself.
			if
				not CollectionService:HasTag(part, "MovingWall")
				and not CollectionService:HasTag(part, "PhantomWall")
			then
				local hash = siteHash(part.Position)
				if hash % Config.Lore.WritingSpacing == 0 then
					cframe = faceFor(part, hash, writeY)
					if cframe then
						fragment = pool[bit32.rshift(hash, 8) % #pool + 1]
					end
				end
			end
		end

		if fragment then
			here[part] = true
			if not drawn[part] then
				drawn[part] = inscribe(fragment, cframe, twoSided)
			end
		end
	end

	for part, slab in pairs(drawn) do
		if not here[part] then
			slab:Destroy()
			drawn[part] = nil
		end
	end

	if writings and next(drawn) == nil then
		clearWritings()
	end
end

-- The writing band is measured off the body, so a respawn is the one change the
-- diff above cannot see: the marks belong to where the old one was standing.
player.CharacterAdded:Connect(clearWritings)

if Config.Lore.Enabled and Config.Lore.WallWritings then
	task.spawn(function()
		while true do
			task.wait(Config.Lore.WritingTickSeconds)
			updateWritings()
		end
	end)
end
