-- PurchaseService -> ServerScriptService
-- The Robux side of the two-price shelves (docs/ROBUX_PLAN.md). This will be
-- the only owner of MarketplaceService.ProcessReceipt in the game and the only
-- thing that opens a purchase prompt; that receipt spine is Register R2 and is
-- not written yet, so today this file is R1's startup audit and nothing else.
--
-- The audit is the second half of the maintenance answer to one product per
-- sellable thing (tools/robux/products.sh is the first): every row's dashboard
-- price is compared against the rung the ladder computes, so drift between the
-- catalogue and the dashboard is loud rather than silent. It is one
-- GetProductInfo web call per product, so it ships off behind
-- Config.Robux.AuditOnStart and is flipped on in Studio after a repricing pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Config = require(ReplicatedStorage:WaitForChild("MazeConfig"))
local Storefront = require(ReplicatedStorage:WaitForChild("Storefront"))

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
