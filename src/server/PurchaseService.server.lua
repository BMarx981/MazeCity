-- PurchaseService -> ServerScriptService
-- The Robux side of the two-price shelves: the receipt spine of
-- docs/ROBUX_PLAN.md, where a bug costs somebody real money, so the rules come
-- before the code and are enforced here and nowhere else.
--
--  1. This is the only owner of MarketplaceService.ProcessReceipt in the game.
--     Roblox allows exactly one callback and a second assignment silently
--     replaces the first, so no other script assigns it, the same way
--     WalkSpeedResolver is the only writer of WalkSpeed.
--  2. A profile that failed to load never takes a purchase: not loaded, or not
--     in this server, is NotProcessedYet and Roblox retries. The existing
--     load-failure posture reaching the place where it matters more.
--  3. Granted means saved. Grant, record the PurchaseId, Profiles.save, and
--     only a save that reached the DataStore returns PurchaseGranted.
--  4. Idempotent by PurchaseId: recorded in the same profile the grant went
--     into, so the two persist or vanish together, and a retry that finds the
--     id present is answered Granted without granting again.
--  5. A receipt that cannot be spent as the item is spent as coins, never
--     dropped. A full shelf is NotProcessedYet (retried once there is room, and
--     the prompt gate refuses to open on full, so this is the rare path); an
--     upgrade tier already owned pays the row's coin price instead.
--  6. Only this script opens a purchase prompt, over the PromptPurchase
--     BindableFunction, after the same grantability checks the receipt makes.
--     Context checks (standing at a roost) stay with the calling service,
--     exactly as atRoost is re-checked on the coin mutation today.
--  7. Grants route through PetInventory and data.upgrades exactly as the coin
--     paths do. No cap, rule or refusal is written twice.
--  8. Effects reach their services on the existing channels: PetsChanged for
--     anything pet-shaped, and the UpgradesChanged bindable, which SaveService
--     answers with applyStats.
--
-- Config.Robux.Enabled gates the prompt gate and the audit, never the receipt
-- path: a receipt is money already taken, and it is processed whatever the
-- switch says today.
--
-- In Studio only, two debug affordances make the spine testable before any
-- dashboard product exists, modelled on EnemyDebug: synthetic product ids are
-- stamped onto rows that have none, and a /buy chat command synthesizes a
-- receipt table and runs it through the same processReceipt the real callback
-- calls. Same code path, no second grant path to keep in sync.

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local Storefront = require(ReplicatedStorage:WaitForChild("Storefront"))
local EggCatalog = require(ReplicatedStorage:WaitForChild("EggCatalog"))
local AccessoryCatalog = require(ReplicatedStorage:WaitForChild("AccessoryCatalog"))
local PetCatalog = require(ReplicatedStorage:WaitForChild("PetCatalog"))
local Profiles = require(ServerScriptService:WaitForChild("PlayerProfiles"))
local Inventory = require(ServerScriptService:WaitForChild("PetInventory"))

local function findOrCreate(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = parent
	return made
end

-- Owned here, listened to by the storefront panels from R3 on. Carries only
-- what happened (granted, or paid out as coins); the granted thing itself
-- reaches the client the way it always does, through the pet projection or the
-- replicated attributes.
local remote = findOrCreate(ReplicatedStorage, "RemoteEvent", "PurchaseUpdate")
-- FindFirstChild-or-create on both ends, per the server-to-server convention.
local petsChanged = findOrCreate(ServerScriptService, "BindableEvent", "PetsChanged")
local upgradesChanged = findOrCreate(ServerScriptService, "BindableEvent", "UpgradesChanged")

local RETRY = Enum.ProductPurchaseDecision.NotProcessedYet
local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted

-- ============================================================
-- Product resolution
-- ============================================================
-- One developer product per sellable thing, so a product id names exactly one
-- row and a receipt arriving on a server that never saw the prompt still
-- resolves. Built from Storefront.rows(), the same enumeration the dashboard
-- tool prints and the audit checks.

local byProduct = {}

local function rebuildIndex()
	table.clear(byProduct)
	for _, row in ipairs(Storefront.rows()) do
		if row.productId then
			byProduct[row.productId] = row
		end
	end
end

rebuildIndex()

-- ============================================================
-- Granting
-- ============================================================

-- What spending this receipt as its item comes to: "granted", "retry" for a
-- grant that will succeed once the player makes room, or "coins" for one that
-- can never be granted as bought and pays the row's coin price instead.
local function applyRow(player, data, row)
	if row.kind == "upgrade" then
		local owned = data.upgrades[row.id] or 0
		if row.tier == owned + 1 then
			data.upgrades[row.id] = row.tier
			upgradesChanged:Fire({ kind = "purchase", player = player, upgrade = row.id, tier = row.tier })
			return "granted"
		end
		-- Already owned, or above the next tier because the tier in between was
		-- bought with coins while this receipt was in flight. Either way the
		-- product paid for is not the grant the ladder allows, and rule 5 says a
		-- receipt never evaporates.
		return "coins"
	end

	local ok, result
	if row.kind == "egg" then
		ok, result = Inventory.grantEgg(data, row.id)
	elseif row.kind == "accessory" then
		ok, result = Inventory.grantAccessory(data, row.id)
	elseif row.kind == "pet" then
		ok, result = Inventory.grantPet(data, row.id, nil)
	else
		return "retry"
	end

	if ok then
		petsChanged:Fire({ player = player, event = "purchase" })
		return "granted"
	end
	if result == "eggsfull" or result == "gearfull" or result == "petsfull" then
		return "retry"
	end
	-- "expired" is the one refusal that never clears on its own; a row with no
	-- coin price to pay out (a catalogue entry gone missing entirely) stays a
	-- loud retry rather than money quietly dropped.
	if row.coins then
		return "coins"
	end
	warn(("PurchaseService: cannot grant or pay out %s (%s)"):format(row.label, tostring(result)))
	return "retry"
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return RETRY
	end
	if not Profiles.isLoaded(player) then
		return RETRY
	end
	local data = Profiles.data(player)
	if data.receipts[receipt.PurchaseId] then
		return GRANTED
	end

	local row = byProduct[receipt.ProductId]
	if not row then
		warn("PurchaseService: receipt for unknown product " .. tostring(receipt.ProductId))
		return RETRY
	end

	local outcome = applyRow(player, data, row)
	if outcome == "retry" then
		return RETRY
	end
	if outcome == "coins" then
		local coins = Profiles.coins(player)
		coins.Value = coins.Value + row.coins
		remote:FireClient(player, { kind = "coinsInstead", label = row.label, coins = row.coins })
	else
		remote:FireClient(
			player,
			{ kind = "granted", label = row.label, itemKind = row.kind, id = row.id, tier = row.tier }
		)
	end

	-- Inside the same grant, before the save, so the id and the grant persist
	-- or vanish together: a save that never lands loses both, and the retry
	-- that follows re-grants into a profile that shows neither.
	data.receipts[receipt.PurchaseId] = os.time()
	if not Profiles.save(player) then
		-- The grant stays in memory and the autosave will keep trying; the
		-- retry finds the PurchaseId above and answers Granted without granting
		-- twice.
		return RETRY
	end
	return GRANTED
end

MarketplaceService.ProcessReceipt = processReceipt

-- ============================================================
-- The prompt gate
-- ============================================================
-- The one door to PromptProductPurchase. A calling service validates its own
-- context (the roost checks proximity, the stall checks the pedestal) and asks
-- here; this checks what a receipt would check, so the refusal happens before
-- money moves and the receipt paths above stay the rare ones.

local promptGate = Instance.new("BindableFunction")
promptGate.Name = "PromptPurchase"
promptGate.OnInvoke = function(player, kind, id, tier)
	if not Config.Robux.Enabled then
		return false, "disabled"
	end
	local offer = Storefront.offerFor(kind, id, tier)
	if not offer then
		return false, "unavailable"
	end
	if not Profiles.isLoaded(player) then
		return false, "loading"
	end
	local data = Profiles.data(player)
	if kind == "upgrade" then
		local owned = data.upgrades[id] or 0
		if tier ~= owned + 1 then
			return false, tier <= owned and "maxed" or "locked"
		end
	else
		local room, reason = Inventory.hasRoom(data, kind)
		if not room then
			return false, reason
		end
	end
	MarketplaceService:PromptProductPurchase(player, offer.productId)
	return true
end
promptGate.Parent = ServerScriptService

-- ============================================================
-- The price audit
-- ============================================================
-- The second half of the answer to one product per sellable thing
-- (tools/robux/products.sh is the first): every row's dashboard price is
-- compared against the rung the ladder computes, so drift between the
-- catalogue and the dashboard is loud rather than silent. One GetProductInfo
-- web call per product, so it ships off behind Config.Robux.AuditOnStart.

local function auditProducts()
	local checked = 0
	local unset = 0
	for _, row in ipairs(Storefront.rows()) do
		if not row.productId then
			unset = unset + 1
		else
			checked = checked + 1
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(row.productId, Enum.InfoType.Product)
			end)
			if not ok then
				warn(
					("Robux audit: GetProductInfo failed for %s (%s): %s"):format(
						row.label,
						tostring(row.productId),
						tostring(info)
					)
				)
			elseif info.PriceInRobux ~= row.robux then
				warn(
					("Robux audit: %s is %s on the dashboard but the ladder computes %d"):format(
						row.label,
						tostring(info.PriceInRobux),
						row.robux
					)
				)
			end
		end
	end
	print(("Robux audit: %d products checked, %d rows with no product id"):format(checked, unset))
end

if Config.Robux.Enabled and Config.Robux.AuditOnStart then
	task.spawn(auditProducts)
end

-- ============================================================
-- Studio debug
-- ============================================================
-- Studio cannot complete a real purchase, so the way in is synthesized
-- receipts through the same processReceipt the callback runs. Rows with no
-- product id get a synthetic one first (the server's copies of the catalogues
-- only, and only where the dashboard id is absent), which is what makes the
-- whole spine exercisable before any product exists.
--
-- Chat "/buy <kind> <id> [tier]" (kind: upgrade, egg, gear, pet), or
-- "/buy <productId>", or "/buy repeat" to re-run the last receipt with the
-- same PurchaseId, which is the idempotency test. Same triple registration as
-- EnemyDebug, for the same ChatVersion reason; the command-bar door is
--
--   game:GetService("ServerScriptService").PurchaseDebugCommand:Invoke("egg", "summit_common")

if RunService:IsStudio() then
	local DEBUG_PRODUCT_BASE = 9000000
	local stamped = 0
	for index, row in ipairs(Storefront.rows()) do
		if not row.productId then
			local syntheticId = DEBUG_PRODUCT_BASE + index
			if row.kind == "upgrade" then
				local def = Config.Shop.Upgrades[row.id]
				def.ProductIds = def.ProductIds or {}
				def.ProductIds[row.tier] = syntheticId
			elseif row.kind == "egg" then
				EggCatalog[row.id].robuxProductId = syntheticId
			elseif row.kind == "accessory" then
				AccessoryCatalog[row.id].robuxProductId = syntheticId
			elseif row.kind == "pet" then
				PetCatalog[row.id].robuxProductId = syntheticId
			end
			stamped = stamped + 1
		end
	end
	if stamped > 0 then
		rebuildIndex()
		print(("[PurchaseService] stamped %d synthetic Studio product ids"):format(stamped))
	end

	local KINDS = { upgrade = "upgrade", egg = "egg", accessory = "accessory", gear = "accessory", pet = "pet" }
	local lastReceipt = nil

	local function runReceipt(receipt)
		lastReceipt = receipt
		local decision = processReceipt(receipt)
		local row = byProduct[receipt.ProductId]
		local result = ("%s -> %s"):format(row and row.label or tostring(receipt.ProductId), tostring(decision))
		print("[PurchaseService] " .. result)
		return result
	end

	local function dispatch(speaker, first, second, third)
		if not speaker then
			return "no player to buy as"
		end
		first = string.lower(tostring(first or ""))
		if first == "repeat" then
			if not lastReceipt then
				return "nothing to repeat"
			end
			return runReceipt(lastReceipt)
		end
		local productId = tonumber(first)
		if not productId then
			local kind = KINDS[first]
			if not kind then
				return "usage: /buy <upgrade|egg|gear|pet> <id> [tier], /buy <productId>, /buy repeat"
			end
			local offer = Storefront.offerFor(kind, second, tonumber(third))
			if not offer then
				return ("no offer for %s %s %s"):format(kind, tostring(second), tostring(third))
			end
			productId = offer.productId
		end
		if not byProduct[productId] then
			return "unknown product " .. tostring(productId)
		end
		return runReceipt({
			PlayerId = speaker.UserId,
			ProductId = productId,
			PurchaseId = HttpService:GenerateGUID(false),
			PlaceIdWherePurchased = game.PlaceId,
			CurrencySpent = byProduct[productId].robux,
			CurrencyType = Enum.CurrencyType.Robux,
		})
	end

	local CHAT_ECHO_GRACE = 0.5
	local lastChat, lastChatAt = nil, 0

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

	local function dispatchFromChat(speaker, message)
		local now = os.clock()
		if message == lastChat and now - lastChatAt < CHAT_ECHO_GRACE then
			return
		end
		lastChat, lastChatAt = message, now
		dispatch(speaker, table.unpack(argumentsIn(message)))
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "PurchaseDebugCommand"
	bindable.OnInvoke = function(...)
		return dispatch(Players:GetPlayers()[1], ...)
	end
	bindable.Parent = ServerScriptService

	local chatCommand = Instance.new("TextChatCommand")
	chatCommand.Name = "PurchaseDebugChatCommand"
	chatCommand.PrimaryAlias = "/buy"
	chatCommand.Triggered:Connect(function(source, message)
		dispatchFromChat(source and Players:GetPlayerByUserId(source.UserId) or nil, message)
	end)
	chatCommand.Parent = TextChatService

	local function hookChatted(player)
		player.Chatted:Connect(function(message)
			local words = string.split(message, " ")
			if string.lower(words[1]) == "/buy" then
				dispatchFromChat(player, message)
			end
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		hookChatted(player)
	end
	Players.PlayerAdded:Connect(hookChatted)
end
