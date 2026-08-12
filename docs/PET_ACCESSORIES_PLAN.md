# Pet Accessories Plan

Companion to `PETS_PLAN.md`, which lists "remaining abilities" and "premium products" as later clutches but has no unit of work for gear. This is that unit. The word for it here is a **Set** (a set of gear), so it does not collide with Clutches or with the v1 milestone letters.

Nothing in this plan touches `MazeGenerator`. No new tagged part, no new pedestal, no geometry: the determinism baseline in memory stays exactly where it is, and a Set can be reviewed without a double-build check.

## Goal

A pet can wear gear. Gear is bought at the roost with coins, worn into a slot on one pet, and does something the player can feel in a maze: moves faster, sees more of the route, keeps more of what it picks up. Cosmetic-only gear is a first-class case, not a degenerate one.

## Non-goals

- Trading or gifting gear
- Per-item upgrade levels, enchanting, rerolling stats
- Robux storefront (the catalogue carries `coinCost` only, same as eggs)
- Gear on the player character. This is pet gear. A hat on the player is a different system with a different art pipeline.

## Where it lives

Follows the split PETS_PLAN reconciliation point 4 settled: content grows by entries, tuning grows by edits.

| File | What |
|---|---|
| `src/shared/AccessoryCatalog.lua` | New. The items, next to `PetCatalog` and `EggCatalog`. |
| `src/shared/Types.lua` | Adds `AccessorySlot`, `AccessoryEffect`, `AccessoryConfig`, `AccessoryInstance`; `PetInstance` gains `worn`, `PlayerData` gains `accessories` and `accessoryStorageCap`. |
| `src/shared/MazeConfig.lua` | New `Config.Accessories` block, sibling to `Config.Pets`: slot list, storage cap, effect caps, sell-back fraction. Not inside `Config.Pets`, because the caps govern player stats the whole game is tuned against, not the pet system. |
| `src/server/PetInventory.lua` | The rules: wear, unwear, grant, sell, and the one effect resolver. |
| `src/server/PetService.server.lua` | Intents, rig attachment, publishing the effect totals. |
| `src/server/IncubatorService.server.lua` | The roost storefront gains a Gear tab's worth of buying, the same way it already sells eggs. |
| `src/client/PetGui.client.lua` | Gear tab, per-pet wear view, sell confirm. |
| `src/client/TimerGui.client.lua` | The two clarity effects, which are drawn where Reveal is already drawn. |

## Data model

```lua
export type AccessorySlot = "Head" | "Neck" | "Back" | "Aura"

export type AccessoryEffectType =
	"WalkSpeed" | "PickupRadius" | "CoinMultiplier" | "GlowRange"
	| "WallWalkSeconds" | "PetXp" | "HatchProgress"
	| "RouteVision" | "PhantomSense" | "ScoreBonus" | "Armor"

export type AccessoryEffect = { type: AccessoryEffectType, value: number }

export type AccessoryConfig = {
	id: string,
	name: string,
	slot: AccessorySlot,
	rarity: Rarity,
	model: string,
	placeholder: AccessoryPlaceholder,
	effects: { AccessoryEffect },
	coinCost: number?,
	availableUntil: number?,
}

export type AccessoryInstance = {
	uid: string,
	accessoryId: string,
	locked: boolean,
	acquiredAt: number,
}
```

`PlayerData.accessories: { [string]: AccessoryInstance }` and `PetInstance.worn: { [AccessorySlot]: string }`, a slot mapped to an accessory uid.

Three decisions worth writing down:

1. **Instances with uids, not a count map.** Two Coin Chains are two rows, the same shape pets and eggs already have, and `locked` has somewhere to live. A count map would make "which of my three chains is on the Firefly" unanswerable, and the wear map would have to hold counts instead of references.

2. **A worn accessory stays in the accessories map.** This is the opposite of the egg-into-the-incubator move, and for the opposite reason: an egg had to be in exactly one place so it could not be placed twice, whereas gear has to stay listed so the UI can show it as worn by a named pet. What replaces the structural guarantee is `Inventory.wearerOf(data, accessoryUid)`, one scan over pets, called by every mutation.

3. **Wearing an item that is already on another pet moves it.** Same reasoning as `maxEquipped == 1` making equip a swap: the player has one of the item and has said where they want it. The reply names the pet that lost it, so it is never silent.

## The resolver, and the one-writer rule

Everything an accessory does goes through one function:

```lua
Inventory.wornEffects(data) -> { [AccessoryEffectType]: number }
```

Summed over accessories worn by **equipped** pets only, then clamped per type against `Config.Accessories.Caps`. Two rules hold this together:

- **Gear is inert on a benched pet.** Otherwise a full 25-pet shelf in crowns is a permanent stat line, the pet slot stops being a choice, and the number moves when a pet is hatched rather than when anything is worn. It also bounds the arithmetic: at `MaxEquipped = 1` the totals are at most four items.
- **No consumer reads the catalogue.** Services read the totals table, or the attribute published from it. The day an effect is renamed or an item is rebalanced, exactly one file knows.

Additive effects sum. Multiplier effects sum their bonus fractions and are applied once as `1 + sum`, never chained: two 25% items are 50%, not 56.25%, which is the version a player can predict.

Then the integration problem PETS_PLAN already flagged, generalised. Today `MagnetRange` is written by SaveService from shop tiers; a second writer would clobber it. The rule for every effect that lands on an existing attribute:

> **One attribute, one writer. Readers add.**

So SaveService keeps writing `MagnetRange` and never learns that gear exists; PetService writes `PetMagnetBonus`; PickupService's magnet pass reaches `MagnetRange + PetMagnetBonus`. Every future source is one more attribute and one more addend at the reader, and no writer ever has to read another writer's value.

The attribute changed shape after this was written and the addend still works, but read it before using the number. `MagnetRange` is the pull in absolute studs rather than studs added to `PickupRadius`, and it drives a coins-only second query that tests no line of sight; an unbought magnet is a zero, so gear alone has to clear `PickupRadius` before it reaches anything, which is the honest answer for a +5 trinket and not a bug to route around.

Walk speed is the exception, and deliberately. `BaseWalkSpeed` is an absolute number that everything wanting the player faster multiplies, and that property is what keeps a Speed powerup and a phase from undoing each other. (When this was written they restored against it by hand, one at a time; `WalkSpeedResolver` has since made itself the only writer of `humanoid.WalkSpeed` and owns the product. That strengthens the rule below rather than replacing it: the resolver multiplies a baseline it never writes, and this is about who writes the baseline.) So:

> **`BaseWalkSpeed` has exactly one writer, SaveService.** Anything else that wants to move it publishes an addend and SaveService folds it in.

PetService writes `PetWalkSpeed` on the player; SaveService binds `player:GetAttributeChangedSignal("PetWalkSpeed")` to its existing `applyStats`. Nothing about the other sources changes.

That recompute was going to have a sharp edge, and by the time Set 3 was built it did not: `applyStats` no longer writes `humanoid.WalkSpeed` at all, it calls `WalkSpeedResolver.apply`, which re-multiplies every live factor over the new baseline. Buying Fast Feet mid-sprint was the bug that fix was written for and the resolver already fixed it.

## Effect vocabulary

Every effect names exactly one integration site. An effect with no site is not in the list.

| Effect | Unit | Lands at | Cap (all gear combined) |
|---|---|---|---|
| `WalkSpeed` | studs, additive | `PetWalkSpeed` attribute, folded into `BaseWalkSpeed` by SaveService | +2.0 |
| `PickupRadius` | studs, additive | `PetMagnetBonus`, added to `MagnetRange` in PickupService's magnet pass | +5.0 |
| `CoinMultiplier` | fraction | PickupService's `coinBonus` (`:247`), as a permanent addend beside the CoinBoost powerup | +0.5 |
| `GlowRange` | studs, additive | PetService `applyGlow` (`:147`). A glow item lights a pet that has no Glow ability, so this is not dead on a Coin Bat. | +25 |
| `WallWalkSeconds` | seconds, additive | `holdSeconds` in AbilityService, which becomes tier seconds plus bonus. Was `capacityFor` in WallWalkService, and the trailing claim that gear alone gives a meter to a player who never bought the upgrade died with that file; see Set 3. | +4.0 |
| `PetXp` | fraction | `awardXp` in PetService (`:298`) | +0.35 |
| `HatchProgress` | fraction | IncubatorService's boost resolve (`:182`), where `HatchBoost` already multiplies | +0.75 |
| `RouteVision` | hops | Client. TimerGui already decodes `LevelTrigger.Route` for Reveal (`:520`); this draws the first N hops permanently. | 14 hops |
| `PhantomSense` | studs | Client. TimerGui already binds the `PhantomWall` tag (`:666`); this marks phantoms within range before they are touched. | 30 |
| `ScoreBonus` | fraction | TowerTimerService's `award` (`:149`), which both payout sites already funnel through | +0.15 |
| `Armor` | fraction prevented | `EnemyCombat.applyDamage` (`:77`), the one place anything takes a player's health | 0.40 |

The two clarity effects are client draws with no server effect, which is the same shape Reveal already has and the reason they are cheap. They are hints, and a hint that is briefly wrong because a section has not replicated yet is the failure mode TimerGui is already written to tolerate.

Caps are not decoration. `Config.EnemyProfiles` is tuned on the stated rule that sustained enemy speed stays under the unupgraded player's 16 and that Fast Feet's 20.5 leaves everything behind. Gear at +2 puts the ceiling at 22.5 and moves nothing structural; gear uncapped eventually makes par times, which `Config.getParTime` shaves per floor, a formality. Whoever raises the `WalkSpeed` cap owes the enemy tuning comment a re-read.

## Slots

| Slot | Reads as | Attach point |
|---|---|---|
| `Head` | hats, crowns, circlets, halos worn low | top centre of the rig |
| `Neck` | necklaces, collars, pendants, bells | front, at 40% of rig height |
| `Back` | capes, wings, packs, satchels | rear centre |
| `Aura` | trails, motes, sparks; a particle rather than a solid | rig centre |

Four slots against one equipped pet is at most four items live, which is what makes the caps above reachable but not trivially so.

## The catalogue, first pass

Prices are read against the economy the shop is already tuned to: a floor fully explored pays about 13 coins, a tower about 130, the Summit Egg costs 250 and the Royal 2500. So a Common is most of one tower, an Epic is a campaign, and a Legendary is not for sale at all.

### Head

| Item | Rarity | Effects | Cost |
|---|---|---|---|
| Explorer's Cap | Common | RouteVision 3 | 150 |
| Lantern Hat | Uncommon | GlowRange +10 | 350 |
| Tin Crown | Uncommon | ScoreBonus +5%, RouteVision 2 | 400 |
| Cartographer's Circlet | Rare | RouteVision 8, PhantomSense 24 | 1200 |
| Gilded Crown | Epic | CoinMultiplier +25%, ScoreBonus +10% | 3000 |
| Beacon Crown | Legendary | RouteVision 14, GlowRange +20 | not for sale (streak day 7) |

### Neck

| Item | Rarity | Effects | Cost |
|---|---|---|---|
| Coin Chain | Common | PickupRadius +2 | 150 |
| Bell Collar | Common | PetXp +10% | 200 |
| Guard Collar | Uncommon | Armor 15% | 500 |
| Compass Pendant | Rare | PhantomSense 30, RouteVision 2 | 1000 |
| Warm Amulet | Rare | HatchProgress +50% | 1400 |
| Heartstone Locket | Epic | Armor 30%, WalkSpeed +0.5 | 3200 |

### Back

| Item | Rarity | Effects | Cost |
|---|---|---|---|
| Scrap Cape | Common | WalkSpeed +0.5 | 200 |
| Runner's Cloak | Uncommon | WalkSpeed +1.0 | 600 |
| Coin Satchel | Rare | CoinMultiplier +20% | 1300 |
| Phase Pack | Rare | WallWalkSeconds +2 | 1500 |
| Moth Wings | Epic | WalkSpeed +1.5, PetXp +15% | 3500 |

### Aura

| Item | Rarity | Effects | Cost |
|---|---|---|---|
| Dust Motes | Common | none, cosmetic | 250 |
| Coin Glimmer | Uncommon | PickupRadius +2.5 | 700 |
| Warding Sparks | Rare | Armor 20% | 1400 |
| Wayfinder Halo | Epic | RouteVision 10, ScoreBonus +8% | 3400 |
| Ember Trail | Legendary | GlowRange +14, WalkSpeed +1.0 | not for sale (event) |

Twenty two items, every effect type carried by something, and one item with no effects at all so the cosmetic case is exercised from the first day rather than being discovered to be broken later.

Two effects have exactly one source in this pass: `HatchProgress` (Warm Amulet) and `WallWalkSeconds` (Phase Pack). That is a content gap rather than a bug, and it is worth knowing before either is rebalanced, because retiring the one item that carries an effect retires the effect. The first draft of this table said every effect had two sources and counted twenty one items; both were miscounts against the table itself, corrected here after Set 1 counted them in code.

## Rendering

Rigs are anchored models moved by `PivotTo`, so an accessory is parented into the follower model at an offset and moves with it. No welds, no constraints, nothing for the physics solver to own.

- The model comes from `ServerStorage/Accessories/<model>`, with a coloured placeholder part when that name does not exist. Same bargain as `ServerStorage/Pets` and `ServerStorage/Enemies`: playable from a cold `rojo build`, real art drops in by name with no code change.
- Attach point is an `Attachment` named `HeadAttachment` / `NeckAttachment` / `BackAttachment` / `AuraAttachment` on the rig if the artist put one there; otherwise it is computed from the model's bounding box per the slot table. The computed path is what makes gear visible on the placeholder rigs that are all this game has today.
- Everything attached goes through `sterilise` (`PetService.server.lua:87`), so it is anchored, non-colliding, non-query and massless like the rest of the rig.
- `reconcileFollowers` currently rebuilds on a change of stage or petId. It gains a worn signature (slot and accessory id, concatenated) in the same comparison, so wearing a crown rebuilds one rig and changes nothing else.

## Sources

The lesson from PETS_PLAN reconciliation point 11 is that a system with one source and no repeat is a system whose loop dies after the first item. Three sources, none of which needs geometry:

1. **The roost storefront.** The `EggPedestal` prompt already opens a panel with an Eggs tab that sells anything carrying `coinCost` out of `leaderstats.Coins`. Gear is a second list through the same door, the same currency, the same proximity re-check on every mutation.
2. **Daily streak.** DailyRewardService already grants the streak egg on day seven. It gains a gear grant on a configured day, which is the only way to get a Legendary.
3. **Sell back.** Half the coin cost, rounded down, refused on a locked or worn item. This exists so the storage cap is a decision rather than the wall the pet cap currently is, which is the one gap PETS_PLAN records as uncovered.

## Sets

### Set 1: Data layer and resolver

**Done.**

- [x] Types, `AccessoryCatalog`, `Config.Accessories` (slots, `AccessoryStorageCap = 40`, `Caps`, `SellFraction = 0.5`)
- [x] Profile fields, added to `defaults` and to `adopt` field by field. `KeyPrefix` does not move; an old profile is a player with no gear.
- [x] `PetInventory`: `accessoryConfig`, `grantAccessory`, `wearerOf`, `wear`, `unwear`, `sellAccessory`, `setAccessoryLocked`, `wornEffects`, plus `pruneWorn`, called from PetService's existing `onReady` beside `pruneEquipped`
- [x] `Inventory.project` gains an `accessories` list and a `worn` map per pet

Exit: gear granted from the command bar survives a rejoin, a stale id warns and skips, and nothing is visible in game.

Four things the implementation settled, none of which the plan had an answer for:

- **An item with no `coinCost` cannot be sold either.** The field was specified as "cannot be bought", and half of nothing is nothing, so a Legendary would have sold for zero coins. `sellAccessory` refuses it with `notforsale`. The consequence is that the two unsellable items are also the two that cannot be cleared from a full bag, which `locked` was already the answer to for everything else.
- **Worn gear counts against the storage cap.** The alternative makes the cap mean a different number depending on how many pets a player owns, since gear only leaves the bag by being sold.
- **`pruneWorn` also drops an item filed under a slot it no longer belongs to.** A rebalance that moves an item from Neck to Head leaves a live uid under the old key, which would otherwise score twice: once from the stale key and once when it is worn again. Same posture as a vanished entry, and the instance is never deleted either way.
- **`wear` reads the wearer's slot from `wearerOf`, not from the catalogue.** Same reason: the item may be sitting under the slot key it had when it was last worn.

Exercised outside Studio with a stub prelude and the real modules concatenated into one Luau chunk: 50 checks over the catalogue shape, the cap clamp, the benched-pet rule, the move-between-pets reply, the refusals and the projection. That harness is a scratchpad artifact, not a repo file, because there is no test runner in this project to put it in.

### Set 2: Wearing and rendering

**Done.**

- [x] `wear` / `unwear` / `lockAccessory` intents in PetService, validated the way equip already is, refusals named
- [x] Attachment and placeholder fallback; worn signature in `reconcileFollowers`
- [x] PetGui: Gear tab listing owned items by slot, a wear target picker, worn chips on the pet rows

Exit: a crown appears on the follower, survives a death respawn, an evolution and a rejoin, and moving it to a second pet says which pet lost it.

Five things settled while building it:

- **`attachWorn` runs before `applyWard`, and that ordering is load-bearing.** The slot fallback measures the rig's bounding box, and the ward ring is a disc as wide as the ward, so a box measured after it exists puts a crown thirty studs over the pet's head. The comment says so at the call site.
- **The signature names the accessory id, not the uid**, as the plan said, and the consequence is worth stating: swapping one Coin Chain for a second identical one is not a rebuild, which is the point.
- **Two helpers rather than a catalogue require.** `Inventory.wornConfigs` and `Inventory.wornSignature` are what PetService reads, so invariant 3 holds for rendering the same way it holds for effects: PetService never requires `AccessoryCatalog`.
- **What a raw `0.25` means in words lives in `Config.Accessories`**, as `EffectLabels` and `EffectPercent`. The projection carries numbers and the catalogue is server-side, so without this the client would keep a second table of what every effect is, which is exactly the drift invariant 3 exists to stop.
- **`PetInstance.worn` is optional in the types.** A pet hatched before gear existed is a saved row with no such field, and `adopt` merges the pets map whole rather than per pet, so absent-means-empty is the honest contract and every reader keeps it.

The catalogue's placeholder needed one field the data model did not have: `AccessoryPlaceholder.size` is a `Vector3`, not the pet placeholder's scalar, because a cape is flat and wide and a scalar cannot say that. Aura items are particles rather than parts, so they carry `rate` and read `Config.Accessories.AuraLifetime`/`AuraSpeed`/`AuraDrag` for the drift every aura shares.

Harness now at 61 checks, covering the signature, slot ordering, the Aura-is-always-a-particle rule, and that every capped effect has a UI label. The rendering itself is not covered by it and is a Studio check: a `Model:GetBoundingBox` fallback and a `ParticleEmitter` are not things a stub prelude can honestly fake.

### Set 3: Effects that are one addend each

**Done.**

- [x] `PetWalkSpeed` and the `BaseWalkSpeed` single-writer rule
- [x] `PetMagnetBonus` in the sweep, `CoinMultiplier` in the coin award, `PetXp` in `awardXp`, `HatchProgress` in the incubator resolve, `WallWalkSeconds` in the Wall Walker's drain, `GlowRange` in `applyGlow`
- [x] Caps applied in the resolver, once, so no consumer clamps anything (Set 1 already did this; Set 3 confirmed no consumer added a second clamp)

Exit: each of the seven is measurable in a Studio session, and a benched pet's gear measurably does nothing.

**Four attributes, not seven.** `Config.Accessories.Attributes` names the ones that cross a service boundary, and PetService's `publishEffects` is the single writer of all four. The other three need none: `GlowRange` and `PetXp` are spent inside PetService, and `HatchProgress` inside IncubatorService, all three of which already require `PetInventory`. An attribute for a number with one reader in the script that computed it would be a second copy of it. Publishing happens in `reconcileFollowers`, which is what every mutation that can move a total already calls (equip, bench, wear, unwear, a `PetsChanged` from another service, a profile landing, a respawn) and what renaming a pet correctly does not.

Six things the implementation settled, and the first two are the plan being out of date rather than the plan being wrong:

- **The mid-powerup recompute fix this set was scoped to write no longer exists to write.** `WalkSpeedResolver` landed between this plan and this set and made itself the only writer of `humanoid.WalkSpeed`; `applyStats` already stamps `BaseWalkSpeed` and then calls `Resolver.apply`, so re-running it under a live Speed orb re-multiplies rather than cancels. The conditional write specified above ("write `humanoid.WalkSpeed` only when the humanoid is sitting at the old base") would now be a second writer racing the resolver, which is the exact bug the resolver exists to end. Folding one addend into `BaseWalkSpeed` was the whole edit.

- **`WallWalkSeconds` no longer gives a meter to a player who never bought the upgrade.** `WallWalkService` and its per-floor `capacityFor` were replaced by `AbilityService` and one charge shared by three abilities, so what a Phase Pack buys now is a slower drain on that charge: two more seconds of phase out of the same bar. Granting seconds at tier zero would be seconds on a key the HUD does not draw and the selection refuses to point at, because a tier of zero is what makes an ability selectable at all. The bonus is therefore added after the zero check, and `Config.Accessories.WallWalkAbility` names which of the three keys it lands on, since the effect names exactly one.

- **The client adds the same seconds off the same attribute.** `AbilityGui` computes the bar's fall between pushes from the tier rate rather than being sent it, so a server draining the geared rate while the client drew the tier rate would run the bar ahead and yank it back at `PushSeconds`. It reads `PetWallWalkSeconds` directly, which costs nothing: ownership already reaches that HUD as replicated attributes and this is one more.

- **Coin fractions are carried between pickups, not rounded at each one.** `CoinValue` is 1 and `leaderstats.Coins` is an IntValue, so a +20% chain rounded per coin pays either nothing or double. `PickupService` keeps the remainder per player and pays it out when it reaches a whole coin, so five coins pay six. Powerup multipliers are whole numbers and leave nothing behind, which is why this did not need to exist before gear did.

- **`GlowRange` is added to the ability's range rather than multiplied into it.** So a Lantern Hat is the same ten studs on a Solar Firefly as on a fresh one, and the evolution multiplier stays a property of the pet. `applyGlow` now runs for a pet with no Glow ability at all when the bonus is non-zero, which is the case the effect table already promised: a lantern hat on a Coin Bat is a lantern hat.

- **`PetXp` is floored and `HatchProgress` is not.** A level is drawn as a whole number of XP into a whole number needed, so 16.2 of 60 is a number nobody can act on; incubator progress was already fractional for `HatchBoost` and is already floored at the two places it is shown.

Checked with the same kind of stub-prelude harness Sets 1 and 2 used, at 70 checks: the caps, the benched-pet rule, fractions summing rather than chaining, every catalogue effect having both a cap and a label, an unknown id scoring nothing, and the coin carry paying five coins as six. It is a scratchpad artifact for the same reason theirs were, and it reaches only the resolver: the seven integration sites live in Scripts, and whether a crown actually makes a player faster is a Studio session.

### Set 5 ships before Set 4

The numbering stays as written, because CLAUDE.md and three sets of exit criteria refer to these by number, but the order of work inverts. `Inventory.grantAccessory` has no caller anywhere in the repo: the catalogue, the resolver, the rendering and seven of eleven effects are built and correct, and not one player can own a single item. Until Set 5's first unit lands, Set 4 is clarity nobody can buy and every earlier set is unreachable code. So Set 5 first, and inside it the source before the effects.

What both sets have in common is that the crossing is already built. `publishEffects` (`PetService.server.lua:99`) is a loop over `Config.Accessories.Attributes`, so an effect that needs to reach another script is one row in that table plus one reader that adds. The table goes from four rows to eight across the two sets and no new channel is invented for any of them.

### Set 5: Economy and the two award-site effects

**Done.**

**Unit 1: the source.** Buying and selling, at the roost, through the door that already exists.

- [x] `buyAccessory` and `sellAccessory` intents in IncubatorService, beside `buyEgg` and shaped like it: the proximity re-check on every mutation, the `leaderstats.Coins` deduction, the refund if the grant refuses, the `announce` on success. IncubatorService rather than PetService because it is already the service that spends coins at a pedestal, and because PetService is 930 lines and owns no purchase.
- [x] An item with no `coinCost` is refused on both paths, which Set 1 already settled for selling and which is what keeps the streak Legendary out of the shop.
- [x] PetGui's Gear tab gains a shop list beside the owned list and a sell action on owned rows. The tab, the slot grouping, the wear picker and the worn chips are all Set 2's and were not rebuilt.
- [x] `REASONS` covers every refusal the two intents can send: storage cap, cannot afford, not for sale, worn, locked, not at a roost, expired, unknown.

Exit: a player with no developer knowledge walks to a roost, buys a Coin Chain, wears it, feels the magnet reach further, and sells it back for 75.

**Unit 2: the streak grant.** The only way to get a Legendary, and the second source that keeps the loop from dying after the shop is cleared.

- [x] DailyRewardService grants `Config.Accessories.StreakGearId` on `StreakGearDay`, beside the day-seven streak egg. Same posture as that grant, including its decision to keep the day rather than roll the streak back when storage is full.
- [x] Rarity broadcast on a Legendary grant, reusing `Config.Pets.BroadcastFrom` and the announce path the hatch already uses.

**Unit 3: the two award-site effects.** Two rows and two readers.

- [x] `ScoreBonus` becomes `PetScoreBonus` in `Config.Accessories.Attributes`, read in TowerTimerService's `award`. The plan called this two award sites; it is one, because `enterFloor` and `completeTower` both funnel through that function, and applying it there rather than at each caller is what keeps a third payout from being written without it.
- [x] `Armor` becomes `PetArmor`, read in `EnemyCombat.applyDamage`. Also one site rather than the `EnemyService:235` this plan named before the enemy tree was split out: every hit on a player in the game goes through that function, and `EnemyController:takeDamage` is the enemy taking damage rather than dealing it.
- [x] Both are attributes rather than a `PetInventory` require, because neither script requires that module and neither should learn what gear is. This is the invariant, not a shortcut around it.

Exit: a tower topped out under a Tin Crown pays measurably more than one topped out without it, and a Guard Collar measurably survives one more hit.

Seven things the implementation settled:

- **PetGui requires `AccessoryCatalog`, and invariant 3 survives it.** The projection carries what a player owns, and a shop has to name what they do not, so the shop list is read off the catalogue exactly as the egg shelf beside it already reads `EggCatalog`. The invariant is about who resolves an *effect*: no total is computed here, the numbers on a row are the row's own `effects` list, and what a raw `0.25` means in words still comes from `Config.Accessories` rather than a second table on the client. A storefront naming a price is not a consumer.

- **Selling happens at the roost too.** The plan only said buying went through that door, but a sell path anywhere would have been the one mutation in the pet system with no proximity re-check behind it, and half the point of a bag cap is that clearing it is a decision made at the counter. The button says `ROOST` rather than going grey, which is the bargain the Place button already made.

- **`award` returns what it paid rather than what it was asked for.** Both call sites report `gained` to the client's celebration and, for a floor, to the `MazeProgress` bindable; a crown that pays 10% more while the banner says otherwise is worse than no crown. So the bonus is applied inside the function and the callers read its return, which is also what keeps the two sites from each remembering to multiply. Rounded once on the total, because a floor pays tens of points into an IntValue: this needs none of the carried remainder `CoinValue = 1` forced on PickupService.

- **The streak day is matched exactly where the egg's is `>=`.** The egg pays at the wrap, and `>=` is what keeps somebody who earned it from losing it if `DailyStreakLength` is lowered under a saved streak. Gear pays on one day of the week, and a day above the length is unreachable anyway: the streak resets to one the moment it would exceed it.

- **The server-wide broadcast grew a verb and a noun.** It said "%s hatched a %s", and a crown is not hatched. The payload now carries `verb` and `itemName`, both optional, so the hatch sends neither and reads exactly as it did.

- **A sell button is drawn only where selling is possible at all**, which is an unworn item that has a price; the lock button takes the full width otherwise. A *locked* item keeps its button, because there the refusal names a lock the player set themselves, which is worth reading.

- **`ember_trail` still has no source.** `beacon_crown` is the streak grant and the Legendary the plan promised, but the event trail is not for sale, not on the streak, and not in any hatch table, so it is currently unobtainable by design and by nothing else. A second `StreakGearId`-shaped knob is the cheap fix the day an event exists.

Checked with the same stub-prelude harness Sets 1 through 3 used, at 100 checks, and confirmed against a mutated config that the new ones bite: the streak item resolves and is unbuyable, its day is one the streak reaches, every for-sale item refunds between one coin and its price, a Coin Chain is 75, the bag cap refuses a purchase without charging, locked and worn refuse a sale, every refusal either intent can send has a sentence in `REASONS`, the six published attributes each have a cap and a label and no two share a name, and two armour pieces sum to 0.35 while three clamp at the cap. It is a scratchpad artifact for the reason the others were. What it cannot reach is both award sites and both intents, all four being in Scripts: whether a Tin Crown actually pays 42 for a 40 point floor is a Studio session.

### Set 4: Clarity

Two client draws, no server effect, which is the shape Reveal already has and the reason they are cheap.

- [ ] `RouteVision` and `PhantomSense` join `Config.Accessories.Attributes` as `PetRouteVision` and `PetPhantomSense`. This corrects that table's own comment, which says the two clarity effects come off the projection: the projection lands in PetGui and the trail is drawn by TimerGui, so coming off the projection means TimerGui subscribing to a second remote and parsing an inventory it has no other use for. Attributes are replicated, so the trail is correct on the first frame after a rejoin, which is the argument AbilityGui already made for ownership.
- [ ] `RouteVision`: the first N hops of the current floor's `Route`, drawn permanently in a distinct colour from Reveal's.
- [ ] The handback is the delicate part. `clearReveal` (`TimerGui.client.lua:533`) tears the whole `RouteHint` model down and zeroes the deadline, and two unrelated things already extend that deadline without owning it. So clearing means returning to the baseline the gear pays for rather than to nothing: `clearReveal` redraws the geared hops after it clears. The deadline stays the single owner of the temporary layer and neither the orb nor Trailblazer learns that gear exists.
- [ ] `PhantomSense`: phantoms within range marked before they are walked through, on the `PhantomWall` binding TimerGui already holds (`:794`).
- [ ] Both cleared on floor change, on respawn and on unwear, the way `clearReveal` already is. Unwear arrives as an attribute change, so it is a `GetAttributeChangedSignal` bind rather than anything new on the wire.

Exit: the trail is on at the item's hop count with no orb taken and no cast made, Reveal takes over and hands back to it rather than to nothing, and the markers still live in `RouteHint` outside `MazeCity`.

## Invariants this adds

1. **Gear on a benched pet does nothing.** Equipped pets only, resolved in one function.
2. **One attribute, one writer; readers add.** `BaseWalkSpeed` is the named exception and SaveService is its writer.
3. **No consumer reads `AccessoryCatalog`.** Services read `wornEffects` or the attribute published from it.
4. **Multipliers sum their fractions and apply once.** Never chained.
5. **An unknown accessory id is a warning and a skipped item.** The instance stays in the profile in case the entry comes back, which is what `resolvePet` already does for pets.
6. **Every effect names one integration site.** An effect with two sites is two effects.
7. **No geometry.** Nothing in this plan writes to `workspace.MazeCity` or adds a tag, so the determinism baseline is untouched and a generator double-build is not part of any Set's exit criteria.

## Open decisions

- **Whether `Armor` belongs at all.** It is the one effect that changes how dangerous the game is rather than how fast or how legible, and the enemy tuning comment argues that contact should be a mistake rather than a tax. 40% is chosen to keep a hit a mistake. Still open after Set 5, which shipped it wired rather than shipped it decided: it is one attribute read at one line in `EnemyCombat.applyDamage`, so lowering the cap is a `Config.Accessories` edit, and retiring the effect is deleting the three catalogue rows that carry it. The playtest this asked for is a Guard Collar worn against a Brute.
- **Whether gear should be droppable from eggs.** It would give hatching a second axis, and it would also make a full pet shelf stop being the only reason a hatch can refuse. Left out of v1 because an egg that pays either a pet or a hat needs its `hatchTable` to hold two kinds of thing, which is a wider change to the roll than it looks.
- **Where this sits against the ship plan.** Same question PETS_PLAN records and does not answer: this is additive to the save schema and to the client input surface, so it should not run beside the README/CI and ship milestones on the same save format.

## What is not covered

- Gear on the player character.
- Per-item progression. An item is the same item forever, which is why the profile row is four fields.
- Set bonuses (wearing three of a theme). The resolver would support it and the catalogue does not carry a set key, deliberately, until someone wants it.
