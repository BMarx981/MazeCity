# Robux Plan

Everything this game sells is sold for coins. This plan adds a second price to the same shelves: every item that can be bought can also be bought for Robux, and the Robux price is **derived from the coin price** rather than authored, so the one ladder the game already tuned against effectiveness is the one ladder both currencies read.

The word for a work unit here is a **Register**, R1 through R5, so it does not collide with Clutches (pets), Sets (gear) or the v1 milestone letters.

Only R4 touches `MazeGenerator`. Every other Register is services, config and UI, and can be reviewed without a double-build check.

## Goal

A player at the stall or at the roost sees two prices on the same thing and can pay either. Nothing is Robux-only that was not already Robux-only, nothing stops being earnable, and adding a catalogue entry later gets a Robux price for free because the price is a function of what the entry already carries.

## Non-goals

- **Coin packs.** Selling coins directly is the most standard Robux product there is, and it is deliberately out of scope. It creates a second path to every item at whatever rate the pack implies, and unless that rate is exactly the ladder's, one of the two paths is strictly better and the derived prices below become decoration. If coin packs ever ship they have to be priced off `Storefront.robuxFor` like everything else. See "Open decisions".
- **Gamepasses and subscriptions.** A gamepass cannot be bought twice, and every tiered thing in this game is bought three times. Uniform developer products, no exceptions.
- **Trading, gifting, limited-time sales, regional pricing.** Roblox owns the last one.
- **Anything Robux-only.** Every item stays earnable at its coin price. Robux buys the wait, not the item.

## The ladder

Two anchors and a rung list. Everything else falls out.

```lua
Config.Robux = {
	Enabled = true,
	-- Developer product price points. Every item is sold at one of these, so the
	-- dashboard holds eight distinct prices however many products exist.
	Rungs = { 25, 49, 99, 199, 299, 399, 599, 799 },
	-- The curve is whatever passes through these two points. Written as anchors
	-- rather than as an exponent because an exponent is a number nobody can sanity
	-- check: these say "the cheapest thing in the game is a bottom rung and the
	-- dearest is a top rung", which is a claim a playtest can disagree with.
	AnchorLowCoins = 25,
	AnchorLowRobux = 25,
	AnchorHighCoins = 3500,
	AnchorHighRobux = 799,
}
```

`src/shared/Storefront.lua` is the derivation, and it is pure so the client can draw a price without asking the server:

```
k     = ln(AnchorHighRobux / AnchorLowRobux) / ln(AnchorHighCoins / AnchorLowCoins)
raw   = AnchorLowRobux * (coins / AnchorLowCoins) ^ k
robux = the cheapest rung >= raw, clamped to the top rung
```

With the anchors above, `k` is 0.70. **The curve is deliberately sublinear.** Coin costs in this game span 25 to 3500, a 140x range; a Robux ladder spanning 140x is not a product ladder anyone would ship. At k = 0.70 the same range compresses to 32x, which is exactly the 25-to-799 span the rungs cover, and effectiveness still orders the list end to end: a Common cape is never dearer than an Epic one.

### What that prices things at

| Item | Coins | Raw | Rung |
|---|---|---|---|
| Fast Feet t1 | 25 | 25 | **25** |
| Wall Walker t1 | 30 | 28 | **49** |
| Fast Feet t2 | 60 | 46 | **49** |
| Coin Magnet t2 | 70 | 52 | **99** |
| Fast Feet t3 | 120 | 75 | **99** |
| Explorer's Cap (Common) | 150 | 88 | **99** |
| Cloak t3 | 175 | 98 | **99** |
| Summit Egg | 250 | 126 | **199** |
| Lantern Hat (Uncommon) | 350 | 159 | **199** |
| Tin Crown (Uncommon) | 400 | 175 | **199** |
| Guard Collar (Uncommon) | 500 | 204 | **299** |
| Runner's Cloak (Uncommon) | 600 | 232 | **299** |
| Coin Glimmer (Uncommon) | 700 | 259 | **299** |
| Compass Pendant (Rare) | 1000 | 332 | **399** |
| Cartographer's Circlet (Rare) | 1200 | 377 | **399** |
| Coin Satchel (Rare) | 1300 | 399 | **399** |
| Warm Amulet (Rare) | 1400 | 420 | **599** |
| Phase Pack (Rare) | 1500 | 441 | **599** |
| Royal Summit Egg | 2500 | 631 | **799** |
| Gilded Crown (Epic) | 3000 | 717 | **799** |
| Heartstone Locket (Epic) | 3200 | 750 | **799** |
| Wayfinder Halo (Epic) | 3400 | 782 | **799** |
| Moth Wings (Epic) | 3500 | 792 | **799** |

Every Epic lands on the top rung, which is correct and slightly flat. If that flatness matters after a playtest, the fix is rungs above 799 rather than a new curve.

### The three rows with no coin price

`streak_seven`, `beacon_crown` and `ember_trail` carry no `coinCost`, and that single absent field is the whole of what keeps them out of the roost's buy list and out of its sell path. They have no coin price to derive from, so under "everything is for sale" they carry an explicit `robuxCost = 799`.

The two fields are independent on purpose: **`coinCost` and `robuxProductId` are two one-field rules, not one rule with an exception.** An item can be for sale in one currency and not the other, and nothing downstream has to learn a second flag to express that.

Worth deciding before R3 ships, and flagged rather than assumed: selling `streak_seven` and `beacon_crown` for Robux removes the only reason to hold a seven day streak, which is the strongest retention mechanic the game has. This plan sells them because that is what was asked for, and the plan supports holding them back by deleting one field from each row. `ember_trail` is event gear with no such role and is an easy yes.

## Products

**One developer product per sellable thing.** 45 of them: 15 upgrade tiers, 3 eggs, 22 gear rows, 5 pets. The id lives on the row.

```lua
-- AccessoryCatalog / EggCatalog rows
robuxProductId = 1234567890,

-- Config.Shop.Upgrades rows, parallel to Costs
Costs = { 25, 60, 120 },
ProductIds = { 111, 222, 333 },
```

`ProcessReceipt` is then a pure lookup: a product id names exactly one item, so a receipt arriving on a server that never saw the prompt, or three days after the player left, still resolves.

**The rejected alternative was one product per rung**, eight products instead of forty five, with the item recorded as a pending intent when the prompt is fired. It is rejected because `ProcessReceipt` can arrive on another server or in another session, so the intent has to be durable, cross-server and unambiguous when two prompts at the same rung are open at once. The failure mode is a player charged for an item the server cannot name. Forty five dashboard rows created once is cheaper than that.

The maintenance cost of forty five is real and is handled two ways rather than absorbed:

- `tools/robux/products.lua` prints the full table (item, coin cost, raw price, rung) under the luau CLI, the way `tools/petlooks/check.sh` already runs outside Roblox. Creating or repricing products is reading one generated list.
- A startup audit in `PurchaseService` calls `MarketplaceService:GetProductInfo` once per row and warns where the dashboard price differs from the rung the ladder computed. Drift between the catalogue and the dashboard is loud, not silent. It runs behind `Config.Robux.AuditOnStart` and is off in production, being 45 web calls.

Because prices are rungs, a coin rebalance only needs a dashboard edit when it crosses a rung.

## Where it lives

| File | What |
|---|---|
| `src/shared/Storefront.lua` | New. The ladder, the rung search, `robuxFor(coins)`, and `offerFor(kind, id, tier)` returning `{ robux, productId }` or nil. Pure, no services, no yielding, so the client draws prices with it. |
| `src/shared/MazeConfig.lua` | New `Config.Robux` block. Sibling of `Config.Shop`, not inside it: the roost sells through it too. |
| `src/shared/Types.lua` | `robuxProductId` and `robuxCost` on `EggConfig` and `AccessoryConfig`; `PlayerData` gains `receipts`. |
| `src/shared/EggCatalog.lua`, `AccessoryCatalog.lua`, `PetCatalog.lua` | One field per row. |
| `src/server/PurchaseService.server.lua` | New. The only owner of `MarketplaceService.ProcessReceipt` in the game, and the only thing that opens a purchase prompt. |
| `src/server/PlayerProfiles.lua` | `receipts` in `defaults()` and in `adopt()`. Additive, so `KeyPrefix` does not move and there is no migration. |
| `src/server/SaveService.server.lua` | Listens on a new `UpgradesChanged` bindable and re-runs `applyStats`. Grants nothing itself. |
| `src/server/IncubatorService.server.lua` | Two new intents, `buyEggRobux` and `buyAccessoryRobux`, which validate and then ask PurchaseService to prompt. |
| `src/server/MazeGenerator.lua` | R4 only: a second ProximityPrompt on each `ShopItem` pedestal. |
| `src/client/PetGui.client.lua` | A Robux price beside the coin price on egg, gear and pet rows. |

`src/shared` and `src/server` are mapped wholesale by `default.project.json`, so both new files ship by existing.

## The receipt spine

This is the part where a bug costs somebody real money, so the rules are stated before the code.

1. **One `ProcessReceipt` in the whole game.** Roblox allows exactly one callback and a second assignment silently replaces the first. `PurchaseService` owns it and no other script assigns it. Same shape as `WalkSpeedResolver` being the only writer of `WalkSpeed`, and for the same reason.

2. **A profile that failed to load never takes a purchase.** `PlayerProfiles`' load-failure posture is that an unloaded profile is never saved over, so a purchase granted into one is a purchase the player paid for and loses at the next join. If `Profiles.isLoaded(player)` is false, or the player is not in this server, `ProcessReceipt` returns `NotProcessedYet` and Roblox retries. This is not a new rule, it is the existing one reaching a place where it now matters more.

3. **Granted means saved.** The order is grant, `Profiles.save(player)`, then return `PurchaseGranted`. A save that throws returns `NotProcessedYet`. Returning Granted before a successful save is the one way to take money and deliver nothing.

4. **Idempotent by `PurchaseId`.** `data.receipts[purchaseId] = os.time()` is written inside the same grant, before the save. A retry that finds the id already present returns `PurchaseGranted` immediately without granting again. Entries older than 30 days are pruned in `adopt`, so the table is bounded by how much anyone buys in a month.

5. **A receipt that cannot be spent as the item is spent as coins, never dropped.** Two cases and they resolve differently:
   - *Not yet grantable* (gear bag or egg shelf full): return `NotProcessedYet`. Roblox retries on the next join and the player gets it once they make room. The panel refuses to prompt when full, so this is the rare path.
   - *Never grantable* (an upgrade tier already owned): grant the row's `coinCost` in coins instead and tell the player what happened. Prompts are refused at max tier, so again this is the path that should not be reached, but a receipt is not allowed to evaporate.

6. **Only the server opens a prompt.** `MarketplaceService:PromptProductPurchase` is called from `PurchaseService` after the same checks the coin path already makes: proximity to a tagged pedestal for the roost, tier and ownership for the stall. The client asks over the existing `PetIntent` remote, which already carries `Config.Pets.IntentsPerSecond`. The prompt is a door into the purchase, never the authority, exactly as `atRoost` is re-checked on the mutation and not on the prompt today.

7. **Grants route through the existing rules and reimplement none of them.** Eggs and gear go through `PetInventory.grantEgg` / `grantAccessory` and get the same caps and the same `ok, reason` refusals; an upgrade tier is `data.upgrades[key] = owned + 1`. Nothing about a cap is written twice.

8. **Effects reach their services on the existing channels.** A pet, egg or gear grant fires `PetsChanged`, which PetService already listens to. An upgrade tier fires a new `UpgradesChanged` bindable that `SaveService` listens to and answers with `applyStats`, because a `.server.lua` cannot be required. Both are `FindFirstChild`-or-create on both ends, per the server-to-server convention.

### Testing it

Studio cannot complete a real purchase, so R2 ships its own way in, modelled on `EnemyDebug`: `PurchaseService` returns from its debug block immediately outside Studio, and inside it a `/buy <productId>` chat command synthesizes a receipt table and runs it through the same `ProcessReceipt` function the real one calls. Same code path, no second grant path to keep in sync. This is what makes R2 testable at all before any product exists on the dashboard.

## Registers

### R1: The ladder

`Config.Robux`, `src/shared/Storefront.lua`, the `robuxProductId` field on every row, `tools/robux/products.lua`, and the startup audit. No purchase happens.

**Exit:** `tools/robux/products.lua` prints all 45 rows with prices matching the table above. `selene src/` clean. Every existing coin path behaves identically.

**Done, with three things decided along the way.** The rung search runs on `raw` rounded to whole Robux, because a price is whole Robux and the fraction bit exactly once: Coin Satchel's 1300 coins computes 399.02, which unrounded lands on 599 where this table says 399; no other row is within half a Robux of a rung. `Storefront.rows()` is the one enumeration of what the game sells, shared by the tool and the audit so the two cannot cover different sets. And every `robuxProductId` is deliberately unset until the 45 dashboard products exist: absent means not for sale, so nothing is promptable before R2 lands, and the tool's id column is the paste-in worklist. The audit lives in `PurchaseService.server.lua`, which today is the audit and nothing else; R2 grows the receipt spine in the same file. The tool runs as `tools/robux/products.sh` (assembly, reusing petlooks' stubs) around `products.lua` (the driver), the same split petlooks uses.

### R2: The receipt spine

`PurchaseService`, the profile's `receipts` field, the `UpgradesChanged` bindable and `SaveService`'s listener, the Studio `/buy` command. Prompts are not yet reachable from any UI.

**Exit:** `/buy` on an egg product grants the egg and the shelf shows it. `/buy` twice with the same `PurchaseId` grants once. `/buy` with the profile forced unloaded grants nothing and returns `NotProcessedYet`. `/buy` on a maxed upgrade tier pays coins. Rejoin and confirm the grant came back, then confirm a session with no DataStore API access still plays, still saves nothing, and refuses every purchase.

**Done, pending the Studio play test above, with five things decided along the way.** The Studio debug block stamps synthetic product ids (9000001 up, by row index) onto every row that has none, into the server's copies of the catalogues only, which is what makes `/buy` runnable before a single dashboard product exists; `/buy repeat` re-runs the last receipt with its `PurchaseId` kept, which is the idempotency test, and forcing the profile unloaded is just running Studio without API access. `Profiles.save` now returns whether the payload reached the DataStore, because "granted means saved" needs the answer; every older caller ignores it. The prompt gate shipped here rather than waiting for R3, as the `PromptPurchase` BindableFunction: a caller validates its own context (the roost's proximity, the stall's pedestal) and this checks everything a receipt would, through `PetInventory.hasRoom`, the new single statement of the three storage caps that the grants now also refuse with. `PurchaseUpdate` is the remote the R3 panels will listen on; it carries only granted/coinsInstead. And an upgrade receipt whose tier is not exactly `owned + 1` pays coins, covering both the maxed case and a tier overtaken by a coin purchase while the receipt was in flight. `Config.Robux.Enabled` gates prompts and the audit, never receipt processing: a receipt is money already taken.

### R3: The roost

`buyEggRobux` and `buyAccessoryRobux` intents in `IncubatorService`, and a Robux price beside the coin price on every egg and gear row in `PetGui`. The panel reads `Storefront.offerFor` locally, so a row with no product id simply draws one price.

**Exit:** buy an egg and a piece of gear for Robux at a roost. Walk away from the pedestal mid-panel and confirm the purchase is refused. Confirm a full gear bag refuses the prompt rather than the receipt.

**Done, pending the Studio play test above, with four things decided along the way.** The synthetic id stamping moved from PurchaseService into `Storefront.stampSyntheticProductIds`, because module state does not replicate and the client has to stamp its own catalogue copies or the Robux buttons are undrawable exactly where `/buy` is testable; both sides walk the same `rows()` order so the ids agree, and the `IsStudio` guard stays with the callers so Storefront keeps requiring no services and the CLI tool keeps running. The two shop lists draw every row for sale in either currency, sorted by coin cost with Robux-only rows last, so the three `robuxCost` rows appear with a single button the day a product id joins them and the streak decision stays one field per row. The intents re-check `availableUntil` before prompting, because an expired receipt on a row with no coin price has no payout and must be stopped at the door; they deliberately do not check `coinCost`, the two fields being independent. And the Robux button keeps its price when the roost is out of reach rather than turning into a second AT A ROOST: the coin button beside it already says why nothing is pressable, and a press out of reach still gets the readable refusal. Prompt-gate refusals ride the existing denied channel and the gate's three new reasons got sentences in `REASONS`.

### R4: The stall

A second ProximityPrompt on each `ShopItem` pedestal, "Buy with Robux", bound by `SaveService` to the same `Upgrade` attribute the coin prompt reads.

This is the only generation change in the plan and it obeys invariant 6: the prompt is a pure function of the pedestal that already exists and draws no random numbers, so every pre-existing part stays where it was and the delta is countable. **One instance per pedestal, five pedestals per building, so +30 per section.** Run the double-build check and update the determinism baseline in memory with the new counts.

**Exit:** identical part counts across two builds at the same seed, differing from the recorded baseline by exactly +30 per section. Buy a tier for Robux, confirm `applyStats` ran (walk speed changed on the spot, no respawn needed), confirm the coin prompt still works and the tier is still capped at three.

**Done, pending the Studio play test above, with three things decided along the way.** The prompt carries its own keys, `R` on keyboard and `ButtonY` on gamepad with a `UIOffset` lifting it above the coin prompt, because the engine shows one prompt per key code at a time and two prompts on the default `E` would never both draw; it is named `RobuxPrompt` so SaveService can tell the pair apart, binding both off the same `Upgrade` attribute. Its `Enabled` is `Config.Robux.Enabled` read at generation time, so the whole surface switches off with the flag while the instance always exists and the part count never depends on it. SaveService answers maxed itself with the same message the coin path sends, since the gate would only call a tier past the ladder "unavailable"; every other refusal is the gate's, carried to TimerGui as a `robuxRefused` kind with the reason mapped to a sentence. The double-build check ran on a rebuilt harness (the old copy was cleaned out of its scratchpad): two runs byte-identical, and the before/after diff exactly the 90 added `RobuxPrompt` lines, +30 per section, with zero pre-existing lines changed.

### R5: Pets

The one Register that changes what the game is, so it is last and it has a principle rather than a price.

Pets carry no `coinCost`, because a pet is not bought, it is gambled for. So its implied coin value is **what rolling for it costs**: the cheapest egg that can produce it, divided by its probability from that egg, minimised across every egg. `Storefront.impliedCoinsForPet` is that function and it reads the same `hatchTable` weights the roll already reads.

| Pet | Rarity | Cheapest roll | Implied coins | Rung |
|---|---|---|---|---|
| Firefly | Common | Summit, 60/108 | 450 | **199** |
| Lumen Moth | Uncommon | Summit, 25/108 | 1,080 | **399** |
| Coin Bat | Rare | Summit, 10/108 | 2,700 | **799** |
| Ward Hound | Rare | Summit, 8/108 | 3,375 | **799** |
| Compass Crow | Rare | Summit, 5/108 | 5,400 | 1,084, clamped **799** |

**Buying the pet costs what rolling for it costs, so Robux buys certainty and not power.** That is the whole justification for direct pet sale existing beside the egg loop rather than replacing it, and it is why the price is derived from the gamble instead of from rarity: a pet nobody can roll cheaply is a pet nobody can buy cheaply, automatically, including pets added later.

The Compass Crow clamping is the ladder telling the truth about its top rung. If three pets at 799 reads flat, add rungs above 799 rather than bending the curve.

**Exit:** a Pets tab at the roost sells all five, each at the price above, each landing in the shelf through `PetInventory` with the storage cap enforced. The egg loop is untouched.

## Invariants this adds

1. **One ProcessReceipt, in `PurchaseService`, and nowhere else.**
2. **Granted is returned only after the grant succeeded and the profile saved.** An unloaded profile refuses every purchase.
3. **A Robux price is derived, never authored,** except for the three rows with no coin price. `Storefront.robuxFor` is the only place a price is computed and it is pure, so the server, the client and the dashboard tool cannot disagree.
4. **`coinCost` and `robuxProductId` are independent one-field rules.** Absent means not for sale in that currency, and neither field knows about the other.
5. **The purchase path reimplements no cap, no rule and no refusal.** It calls `PetInventory` and reads `Config.Shop.Upgrades` exactly as the coin path does.
6. **Only the server opens a prompt,** after the same checks the coin purchase makes.

## Open decisions

- **The streak items.** Sell `streak_seven` and `beacon_crown`, or hold them back as the one thing a seven day streak is for. Recommendation: hold them back, sell `ember_trail`. One field per row either way.
- **Coin packs.** If they ship, price them off `Storefront.robuxFor` on the coin amount so buying coins and buying the item cost the same. Any other rate makes one path strictly better and the derived ladder cosmetic.
- **The anchors.** `AnchorHighCoins = 3500` is the dearest catalogue row today. Adding something dearer moves the whole curve, which is correct behaviour and also a repricing of everything, so it wants noticing. Pinning the anchor to a constant rather than to `max(coinCost)` is what keeps that a decision instead of a side effect.
- **Rungs above 799.** Deferred until a playtest says the Epic and Rare shelf reads flat.

## What is not covered

Analytics on what sells, first-purchase incentives, sale pricing, bundles, and any UI beyond a second price on an existing row. The plan's claim is that the price of everything is one function of what the row already says; presenting that well is a separate pass.
