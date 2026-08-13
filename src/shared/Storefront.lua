-- Storefront (ModuleScript) -> ReplicatedStorage.Storefront
-- The Robux price of everything, derived from the coin price of everything.
-- Pure: no services, no yielding, no state, so the server validates with the
-- same function the client draws prices with and tools/robux/products.lua runs
-- the same code under the luau CLI. See docs/ROBUX_PLAN.md.
--
-- Three rules, stated once here and leaned on everywhere:
--
--  1. A Robux price is derived from the coin price by robuxFor, never authored,
--     except for a row with no coin price at all, which may carry an explicit
--     robuxCost (the streak and event Legendaries).
--  2. coinCost and robuxProductId are two independent one-field rules. Absent
--     means not for sale in that currency, and neither field knows about the
--     other. offerFor returns nil unless the row has both a price and a product
--     id, so nothing is ever promptable that the dashboard cannot name.
--  3. A pet has no coin price because a pet is gambled for, so its implied coin
--     value is what rolling for it costs: the cheapest coin-priced egg that can
--     produce it, divided by its probability from that egg. Robux buys
--     certainty, not power, and a pet nobody can roll cheaply is a pet nobody
--     can buy cheaply, automatically, including pets added later.

local Storefront = {}

local Config = require(script.Parent:WaitForChild("MazeConfig"))
local EggCatalog = require(script.Parent:WaitForChild("EggCatalog"))
local AccessoryCatalog = require(script.Parent:WaitForChild("AccessoryCatalog"))
local PetCatalog = require(script.Parent:WaitForChild("PetCatalog"))

-- The rung a coin price lands on, and the raw curve value it landed there from.
-- The curve is the power law through the two anchors; the price is the cheapest
-- rung at or above it, clamped to the top rung. Rungs are ascending, so the
-- first match is the answer. The raw value is returned second for the tool and
-- the audit, which both print it; callers pricing things read only the rung.
function Storefront.robuxFor(coins)
	if type(coins) ~= "number" or coins <= 0 then
		return nil
	end
	local R = Config.Robux
	local k = math.log(R.AnchorHighRobux / R.AnchorLowRobux) / math.log(R.AnchorHighCoins / R.AnchorLowCoins)
	local raw = R.AnchorLowRobux * (coins / R.AnchorLowCoins) ^ k
	-- The search runs on whole Robux, a price being whole Robux. Not cosmetic: a
	-- 1300-coin row computes 399.02, and comparing the fraction would bump the
	-- one row that grazes a rung from 399 to 599.
	local rounded = math.floor(raw + 0.5)
	for _, rung in ipairs(R.Rungs) do
		if rung >= rounded then
			return rung, raw
		end
	end
	return R.Rungs[#R.Rungs], raw
end

-- What rolling for a pet costs, minimised across every egg that has a coin
-- price. Reads the same hatchTable weights the hatch roll reads, so a catalogue
-- rebalance reprices the pet with no edit here. nil for a pet no coin-priced
-- egg can produce, which under rule 2 simply means not for sale.
function Storefront.impliedCoinsForPet(petId)
	local best = nil
	for _, egg in pairs(EggCatalog) do
		if egg.coinCost then
			local total = 0
			local weight = 0
			for _, entry in ipairs(egg.hatchTable) do
				total = total + entry.weight
				if entry.petId == petId then
					weight = entry.weight
				end
			end
			if weight > 0 then
				local implied = egg.coinCost * total / weight
				if not best or implied < best then
					best = implied
				end
			end
		end
	end
	return best
end

-- One row's selling surface, whatever kind of row it is. Returns label, the
-- coin price (nil for a pet or an unbuyable row), the authored robuxCost if the
-- row carries one, and the product id if one has been pasted in from the
-- dashboard. nil for a kind/id/tier that names nothing.
local function lookup(kind, id, tier)
	if kind == "upgrade" then
		local def = Config.Shop.Upgrades[id]
		local coins = def and def.Costs and def.Costs[tier]
		if not coins then
			return nil
		end
		local productId = def.ProductIds and def.ProductIds[tier]
		return def.Label .. " t" .. tier, coins, nil, productId
	end
	local row
	if kind == "egg" then
		row = EggCatalog[id]
	elseif kind == "accessory" then
		row = AccessoryCatalog[id]
	elseif kind == "pet" then
		row = PetCatalog[id]
	end
	if not row then
		return nil
	end
	if kind == "pet" then
		return row.name, Storefront.impliedCoinsForPet(id), nil, row.robuxProductId
	end
	return row.name, row.coinCost, row.robuxCost, row.robuxProductId
end

-- What a Robux buy button needs, or nil if this row is not for sale in Robux:
-- no price to derive, no authored price, or no product on the dashboard yet.
-- tier is upgrades only. Pure, so the client draws the second price with this
-- and the server validates a prompt against the same numbers.
function Storefront.offerFor(kind, id, tier)
	if not Config.Robux.Enabled then
		return nil
	end
	local label, coins, robuxCost, productId = lookup(kind, id, tier)
	if not label or not productId then
		return nil
	end
	local robux = robuxCost or Storefront.robuxFor(coins)
	if not robux then
		return nil
	end
	return { robux = robux, productId = productId }
end

-- Every sellable row in one stable list: the stall's tiers in shop order, then
-- eggs, gear and pets, each catalogue in id order. This is the one enumeration
-- of "what the game sells", shared by tools/robux/products.lua (the dashboard
-- worklist) and PurchaseService's price audit, so the two cannot cover
-- different sets. Rows with no price in either currency are excluded the same
-- way offerFor would refuse them.
function Storefront.rows()
	local rows = {}
	local function add(kind, id, tier)
		local label, coins, robuxCost, productId = lookup(kind, id, tier)
		if not label then
			return
		end
		local robux, raw
		if robuxCost then
			robux = robuxCost
		else
			robux, raw = Storefront.robuxFor(coins)
		end
		if not robux then
			return
		end
		table.insert(rows, {
			kind = kind,
			id = id,
			tier = tier,
			label = label,
			coins = coins,
			raw = raw,
			robux = robux,
			productId = productId,
		})
	end
	for _, key in ipairs(Config.shopOrder()) do
		for tier = 1, #Config.Shop.Upgrades[key].Costs do
			add("upgrade", key, tier)
		end
	end
	local function addCatalog(kind, catalog)
		local ids = {}
		for id in pairs(catalog) do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ipairs(ids) do
			add(kind, id)
		end
	end
	addCatalog("egg", EggCatalog)
	addCatalog("accessory", AccessoryCatalog)
	addCatalog("pet", PetCatalog)
	return rows
end

-- Studio's stand-in for the dashboard: synthetic ids (9000001 up, by row
-- index) stamped onto every row that has none, which is what makes anything
-- promptable before a single real product exists. Mutates this environment's
-- copies of the catalogues only, and module state does not replicate, so the
-- server (PurchaseService) and the client (PetGui) each call it themselves;
-- both walking the same rows() order is what keeps their ids identical.
-- Callers guard with RunService:IsStudio(). The guard stays with them rather
-- than here so this module keeps requiring no services, which is what lets
-- tools/robux/products.lua run it under the luau CLI.
local SYNTHETIC_PRODUCT_BASE = 9000000

function Storefront.stampSyntheticProductIds()
	local stamped = 0
	for index, row in ipairs(Storefront.rows()) do
		if not row.productId then
			local syntheticId = SYNTHETIC_PRODUCT_BASE + index
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
	return stamped
end

return Storefront
