-- The driver products.sh appends after the stubs and the shared modules: prints
-- Storefront.rows() as the dashboard worklist and fails if the count ever
-- drifts from what the catalogues imply, which is what catches a row priced in
-- neither currency by accident.

local Storefront = MODULES.Storefront
local Config = MODULES.MazeConfig

local rows = Storefront.rows()

local function fmt(value, pattern)
	if value == nil then
		return "-"
	end
	return string.format(pattern, value)
end

print(string.format("%-4s %-10s %-26s %7s %7s %6s  %s", "#", "kind", "item", "coins", "raw", "robux", "productId"))
local kinds = {}
for index, row in ipairs(rows) do
	print(
		string.format(
			"%-4d %-10s %-26s %7s %7s %6d  %s",
			index,
			row.kind,
			row.label,
			fmt(row.coins, "%d"),
			fmt(row.raw, "%.0f"),
			row.robux,
			row.productId and tostring(row.productId) or "unset"
		)
	)
	kinds[row.kind] = (kinds[row.kind] or 0) + 1
end

print(
	string.format(
		"%d rows: %d upgrade tiers, %d eggs, %d gear, %d pets",
		#rows,
		kinds.upgrade or 0,
		kinds.egg or 0,
		kinds.accessory or 0,
		kinds.pet or 0
	)
)

-- The count the catalogues imply, recomputed here rather than pinned to 45, so
-- adding content moves both sides of the comparison and a genuine drop (a row
-- that lost its price) still fails.
local expected = 0
for _, key in ipairs(Config.shopOrder()) do
	expected = expected + #Config.Shop.Upgrades[key].Costs
end
for _, catalog in ipairs({ MODULES.EggCatalog, MODULES.AccessoryCatalog }) do
	for _, row in pairs(catalog) do
		if row.coinCost or row.robuxCost then
			expected = expected + 1
		end
	end
end
for id in pairs(MODULES.PetCatalog) do
	if Storefront.impliedCoinsForPet(id) then
		expected = expected + 1
	end
end

if #rows ~= expected then
	print(string.format("FAIL: %d rows printed, catalogues imply %d", #rows, expected))
	os.exit(1)
end
