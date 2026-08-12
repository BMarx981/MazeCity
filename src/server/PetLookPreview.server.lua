-- PetLookPreview (Script) -> ServerScriptService
-- TEMPORARY. Delete this file before the pet looks branch merges.
--
-- Set 1 of docs/PET_LOOKS_PLAN.md has to be eyeballed and there is no way to
-- eyeball generated geometry in edit mode, which CLAUDE.md records as the cost
-- of dropping the Studio plugin. Its own suggested workaround is this: a
-- throwaway RunService:IsStudio() branch that builds the geometry where you can
-- see it, rather than owning eleven pets to look at eleven looks.
--
-- Builds every pet at every stage in one row in front of the caller, labelled,
-- turning at the same rate a real follower turns. Nothing else in the game reads
-- it and it writes nothing back.
--
-- **On demand, never on spawn.** It used to build itself the moment the first
-- character loaded, which put eleven AlwaysOnTop billboards in the view of
-- anyone who pressed Play for any other reason: the labels bunch into one stack
-- at the distance the row sits, and a debug surface that cannot be not-looked-at
-- is a debug surface that ruins every unrelated playtest. So it takes the same
-- two doors EnemyDebug takes, chat as any player or the command bar during Play:
--
--   /petlook          build the row, stand on its deck, replacing any row
--   /petlook clear    take it away
--
--   game:GetService("ServerScriptService").PetLookPreviewCommand:Invoke()
--   game:GetService("ServerScriptService").PetLookPreviewCommand:Invoke("clear")
--
-- **Chat needs both doors, and which one is live is now pinned rather than
-- inherited.** `default.project.json` sets `TextChatService.ChatVersion`,
-- because the project did not name it and a door that works depends entirely on
-- the answer: the modern service reads a leading `/` as a command and does not
-- hand the message to `Player.Chatted`, the legacy one does the reverse and
-- ignores a TextChatCommand. Unpinned, that was whatever the place happened to
-- carry, and a row nobody could summon looks exactly like a row that had been
-- deleted. So the alias is registered as a TextChatCommand, `Chatted` is kept
-- for the legacy setting, and `CHAT_ECHO_GRACE` stops a system that somehow
-- fires both from building the row twice, the second build placing it in front
-- of a player the first one had already teleported.
--
-- **You are put on the row rather than pointed at it.** Eleven looks at five
-- studs apart is fifty studs of row, which fits in one view from the deck but
-- was nowhere findable from wherever the caller happened to be standing. So the
-- row gets a floor and you are set down at its left end. LABEL_RANGE is not
-- about that distance, it is about the other one: the labels stack into an
-- unreadable smear when the row is seen from across the city, which is what
-- made the on-spawn build intolerable, and a MaxDistance means a row left
-- standing is invisible from anywhere you are not deliberately looking at it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

if not RunService:IsStudio() then
	return
end

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local PetCatalog = require(ReplicatedStorage:WaitForChild("PetCatalog"))
local PetModelGenerator = require(ReplicatedStorage:WaitForChild("PetModelGenerator"))

local SPACING = 5
local AHEAD = 16
local HEIGHT = 3

-- The deck, in the same root-local frame the row is laid out in: its top sits
-- DECK_DROP under the pets' pivots, it reaches DECK_MARGIN past both ends, and
-- you are set down VIEW_BACK behind the first pet.
local DECK_DROP = 1.5
local DECK_THICKNESS = 1
local DECK_MARGIN = 6
local VIEW_BACK = 7
local LABEL_RANGE = 60

-- Both chat doors can be live at once. Keyed on the text rather than on the
-- clock alone, because the double delivery is the same message twice and a
-- second command typed quickly is not. Same rule as EnemyDebug.
local CHAT_ECHO_GRACE = 0.5
local lastChat, lastChatAt = nil, 0

-- The spin loop, held so that clearing stops it. It was a bare Connect on a row
-- built exactly once, which was fine while the row was built exactly once;
-- rebuilding on a command leaves one connection per build turning models that
-- have been destroyed.
local spin = nil

-- Sorted, because pairs over the catalogue is not a stable order and a row that
-- reshuffles between runs is a row you cannot compare against the last one.
local function everyLook()
	local ids = {}
	for petId in pairs(PetCatalog) do
		table.insert(ids, petId)
	end
	table.sort(ids)

	local entries = {}
	for _, petId in ipairs(ids) do
		local petConfig = PetCatalog[petId]
		for stage = 0, #petConfig.evolutions do
			local evolution = stage > 0 and petConfig.evolutions[stage] or nil
			table.insert(entries, {
				petId = petId,
				stage = stage,
				label = petConfig.name .. (evolution and (" " .. (evolution.displaySuffix or stage)) or ""),
			})
		end
	end
	return entries
end

local function labelFor(model, text)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = LABEL_RANGE
	gui.Parent = model.PrimaryPart

	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(1, 1)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 16
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeTransparency = 0.4
	name.Text = text
	name.Parent = gui
end

local function clearRow()
	if spin then
		spin:Disconnect()
		spin = nil
	end
	local folder = workspace:FindFirstChild("PetLookPreview")
	if folder then
		folder:Destroy()
		return true
	end
	return false
end

local function buildRow(root)
	clearRow()

	local folder = Instance.new("Folder")
	folder.Name = "PetLookPreview"
	folder.Parent = workspace

	local entries = everyLook()
	local span = (#entries - 1) * SPACING
	local base = root.CFrame
	local origin = base * CFrame.new(-span / 2, HEIGHT, -AHEAD)

	-- Built before anyone is moved onto it. The deck is the only collidable
	-- thing this file makes, and clearing destroys it, so a caller who clears
	-- while standing on it drops the few studs back to whatever was underneath.
	local deck = Instance.new("Part")
	deck.Name = "Deck"
	deck.Anchored = true
	deck.CanQuery = false
	deck.Size = Vector3.new(span + DECK_MARGIN * 2, DECK_THICKNESS, VIEW_BACK + DECK_MARGIN)
	deck.CFrame = base * CFrame.new(0, HEIGHT - DECK_DROP - DECK_THICKNESS / 2, -AHEAD + VIEW_BACK / 2)
	deck.Material = Enum.Material.SmoothPlastic
	deck.Color = Color3.fromRGB(38, 40, 46)
	deck.TopSurface = Enum.SurfaceType.Smooth
	deck.Parent = folder

	local placed = {}
	local parts = 0
	for index, entry in ipairs(entries) do
		local model = PetModelGenerator.build(entry.petId, entry.stage)
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end
		local at = origin * CFrame.new((index - 1) * SPACING, 0, 0)
		model:PivotTo(at)
		labelFor(model, entry.label)
		model.Parent = folder
		parts = parts + #model:GetDescendants()
		table.insert(placed, { model = model, at = at })
	end

	-- Held in a list rather than read back off the folder, because GetChildren
	-- order is not build order and a row that pairs a model with someone else's
	-- slot spends every frame teleporting past itself.
	spin = RunService.Heartbeat:Connect(function()
		local turn = math.rad((os.clock() * Config.Pets.SpinDegreesPerSecond) % 360)
		for _, entry in ipairs(placed) do
			entry.model:PivotTo(CFrame.new(entry.at.Position) * CFrame.Angles(0, turn, 0))
		end
	end)

	-- The left end, facing the way the caller already was, which is the way the
	-- row faces: walking right reads it in catalogue order.
	local character = root.Parent
	if character then
		character:PivotTo(base * CFrame.new(-span / 2, HEIGHT - DECK_DROP + 3, -AHEAD + VIEW_BACK))
	end

	return string.format("%d looks, %d instances", #entries, parts)
end

-- The speaker's own character, falling back to the first player so the command
-- bar door works with no speaker to read a position off.
local function rootFor(speaker)
	local player = speaker or Players:GetPlayers()[1]
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function dispatch(speaker, command)
	if string.lower(tostring(command or "")) == "clear" then
		return clearRow() and "cleared" or "nothing to clear"
	end
	local root = rootFor(speaker)
	if not root then
		return "no character to build in front of"
	end
	return buildRow(root)
end

local function run(speaker, command)
	local result = dispatch(speaker, command)
	print("[PetLookPreview] " .. tostring(result))
	return result
end

-- The chat doors only. The command bar invokes `run` directly, because a script
-- driving this deliberately twice is asking for two builds.
-- The two doors do not agree on whether the text they hand back still has the
-- alias on the front of it. This file survived guessing wrong only because its
-- one argument is optional: "/petlook" parsed either way is a build. Same rule
-- as EnemyDebug, where the same guess ate the command word.
local function argumentsIn(message)
	local words = {}
	for _, word in ipairs(string.split(message, " ")) do
		if word ~= "" then
			table.insert(words, word)
		end
	end
	if words[1] and string.sub(words[1], 1, 1) == "/" then
		table.remove(words, 1)
	end
	return words
end

local function runFromChat(speaker, message)
	local now = os.clock()
	if message == lastChat and now - lastChatAt < CHAT_ECHO_GRACE then
		return
	end
	lastChat, lastChatAt = message, now

	run(speaker, argumentsIn(message)[1])
end

local bindable = Instance.new("BindableFunction")
bindable.Name = "PetLookPreviewCommand"
bindable.OnInvoke = function(command)
	return run(nil, command)
end
bindable.Parent = script.Parent

local chatCommand = Instance.new("TextChatCommand")
chatCommand.Name = "PetLookCommand"
chatCommand.PrimaryAlias = "/petlook"
chatCommand.SecondaryAlias = "/pets"
chatCommand.Triggered:Connect(function(source, message)
	runFromChat(source and Players:GetPlayerByUserId(source.UserId) or nil, message)
end)
chatCommand.Parent = TextChatService

-- Backfilled as well as connected. In Play Solo the local player can be added
-- before a ServerScriptService script gets to run, and a legacy door hooked
-- only on PlayerAdded then never hears from the one player in the session.
local function hookChatted(player)
	player.Chatted:Connect(function(message)
		local words = string.split(message, " ")
		if string.lower(words[1]) == "/petlook" or string.lower(words[1]) == "/pets" then
			runFromChat(player, message)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	hookChatted(player)
end
Players.PlayerAdded:Connect(hookChatted)

print(string.format("[PetLookPreview] ready on %s chat, say /petlook", TextChatService.ChatVersion.Name))
