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

Then the integration problem PETS_PLAN already flagged, generalised. Today `MagnetBonus` is written by SaveService from shop tiers; a second writer would clobber it. The rule for every effect that lands on an existing attribute:

> **One attribute, one writer. Readers add.**

So SaveService keeps writing `MagnetBonus` and never learns that gear exists; PetService writes `PetMagnetBonus`; PickupService's sweep becomes `PickupRadius + MagnetBonus + PetMagnetBonus`. Every future source is one more attribute and one more addend at the reader, and no writer ever has to read another writer's value.

Walk speed is the exception, and deliberately. `BaseWalkSpeed` is an absolute number that two services restore against (`PickupService.server.lua:139`, `WallWalkService.server.lua:133`), and that property is what keeps a Speed powerup and a phase from undoing each other. So:

> **`BaseWalkSpeed` has exactly one writer, SaveService.** Anything else that wants to move it publishes an addend and SaveService folds it in.

PetService writes `PetWalkSpeed` on the player; SaveService binds `player:GetAttributeChangedSignal("PetWalkSpeed")` to its existing `applyStats`. Nothing about the two restore sites changes.

That recompute has one sharp edge to handle in Set 3: `applyStats` currently sets `humanoid.WalkSpeed` unconditionally (`SaveService.server.lua:50`), so re-running it mid Speed powerup cancels the boost the player is standing in. The fix is to always write the attribute and to write `humanoid.WalkSpeed` only when the humanoid is currently sitting at the old base, meaning nothing is modulating it; a running effect then restores to the new base when it ends, because it already restores against the attribute rather than against a remembered number.

## Effect vocabulary

Every effect names exactly one integration site. An effect with no site is not in the list.

| Effect | Unit | Lands at | Cap (all gear combined) |
|---|---|---|---|
| `WalkSpeed` | studs, additive | `PetWalkSpeed` attribute, folded into `BaseWalkSpeed` by SaveService | +2.0 |
| `PickupRadius` | studs, additive | `PetMagnetBonus`, added in PickupService's sweep (`:312`) | +5.0 |
| `CoinMultiplier` | fraction | PickupService's `coinBonus` (`:247`), as a permanent addend beside the CoinBoost powerup | +0.5 |
| `GlowRange` | studs, additive | PetService `applyGlow` (`:147`). A glow item lights a pet that has no Glow ability, so this is not dead on a Coin Bat. | +25 |
| `WallWalkSeconds` | seconds, additive | `capacityFor` in WallWalkService (`:62`), which becomes tier seconds plus bonus, so gear alone gives a meter to a player who never bought the upgrade | +4.0 |
| `PetXp` | fraction | `awardXp` in PetService (`:298`) | +0.35 |
| `HatchProgress` | fraction | IncubatorService's boost resolve (`:182`), where `HatchBoost` already multiplies | +0.75 |
| `RouteVision` | hops | Client. TimerGui already decodes `LevelTrigger.Route` for Reveal (`:520`); this draws the first N hops permanently. | 14 hops |
| `PhantomSense` | studs | Client. TimerGui already binds the `PhantomWall` tag (`:666`); this marks phantoms within range before they are touched. | 30 |
| `ScoreBonus` | fraction | TowerTimerService's two award sites (`:164`, `:245`) | +0.15 |
| `Armor` | fraction prevented | EnemyService's `TakeDamage` (`:235`) | 0.40 |

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

- [ ] `wear` / `unwear` / `lockAccessory` intents in PetService, validated the way equip already is, refusals named
- [ ] Attachment and placeholder fallback; worn signature in `reconcileFollowers`
- [ ] PetGui: Gear tab listing owned items by slot, a wear target picker, worn chips on the pet rows

Exit: a crown appears on the follower, survives a death respawn, an evolution and a rejoin, and moving it to a second pet says which pet lost it.

### Set 3: Effects that are one addend each

- [ ] `PetWalkSpeed` and the `BaseWalkSpeed` single-writer rule, including the mid-powerup recompute fix
- [ ] `PetMagnetBonus` in the sweep, `CoinMultiplier` in the coin award, `PetXp` in `awardXp`, `HatchProgress` in the incubator resolve, `WallWalkSeconds` in `capacityFor`, `GlowRange` in `applyGlow`
- [ ] Caps applied in the resolver, once, so no consumer clamps anything

Exit: each of the six is measurable in a Studio session, and a benched pet's gear measurably does nothing.

### Set 4: Clarity

- [ ] `RouteVision`: the first N hops of the current floor's `Route`, drawn permanently in a distinct colour, with the Reveal powerup still overriding it and restoring it on expiry
- [ ] `PhantomSense`: phantoms within range marked before they are walked through
- [ ] Both cleared on floor change, on respawn and on unwear, the way `clearReveal` already is

Exit: the trail is on at the item's hop count, Reveal takes over and hands back, and the markers still live in `RouteHint` outside `MazeCity`.

### Set 5: Economy and the two award-site effects

- [ ] Roost Gear tab: buy, sell back, storage cap refusal
- [ ] Daily streak grant
- [ ] `ScoreBonus` at both TowerTimerService award sites, `Armor` at the EnemyService damage site
- [ ] Rarity broadcast on a Legendary grant, reusing `Config.Pets.BroadcastFrom`

Exit: a player with no developer knowledge buys gear, wears it, feels it, and sells it back.

## Invariants this adds

1. **Gear on a benched pet does nothing.** Equipped pets only, resolved in one function.
2. **One attribute, one writer; readers add.** `BaseWalkSpeed` is the named exception and SaveService is its writer.
3. **No consumer reads `AccessoryCatalog`.** Services read `wornEffects` or the attribute published from it.
4. **Multipliers sum their fractions and apply once.** Never chained.
5. **An unknown accessory id is a warning and a skipped item.** The instance stays in the profile in case the entry comes back, which is what `resolvePet` already does for pets.
6. **Every effect names one integration site.** An effect with two sites is two effects.
7. **No geometry.** Nothing in this plan writes to `workspace.MazeCity` or adds a tag, so the determinism baseline is untouched and a generator double-build is not part of any Set's exit criteria.

## Open decisions

- **Whether `Armor` belongs at all.** It is the one effect that changes how dangerous the game is rather than how fast or how legible, and the enemy tuning comment argues that contact should be a mistake rather than a tax. 40% is chosen to keep a hit a mistake. Worth a playtest before Set 5 rather than after.
- **Whether gear should be droppable from eggs.** It would give hatching a second axis, and it would also make a full pet shelf stop being the only reason a hatch can refuse. Left out of v1 because an egg that pays either a pet or a hat needs its `hatchTable` to hold two kinds of thing, which is a wider change to the roll than it looks.
- **Where this sits against the ship plan.** Same question PETS_PLAN records and does not answer: this is additive to the save schema and to the client input surface, so it should not run beside the README/CI and ship milestones on the same save format.

## What is not covered

- Gear on the player character.
- Per-item progression. An item is the same item forever, which is why the profile row is four fields.
- Set bonuses (wearing three of a theme). The resolver would support it and the catalogue does not carry a set key, deliberately, until someone wants it.
