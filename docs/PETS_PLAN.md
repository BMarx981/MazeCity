# Pet & Egg System Plan

Companion doc to `PET_EGG_DATA_SPEC.md`. This plan uses **Clutches** as its unit of work (a clutch is a group of eggs) to avoid colliding with the existing milestone plan. Clutches are sequential, each one independently testable in Studio, each one a candidate for its own branch.

## Goal

Players carry an egg to the summit, place it, and hatch it by completing mazes. Hatched pets follow the player and provide maze-relevant utility. Daily rewards feed pet progression.

## Non-goals (v1)

- Trading
- Pet food / consumable item inventory
- More than one incubator slot
- Premium/Robux egg products (data model supports them, no storefront yet)

## Prerequisites / integration audit

Answered 2026-08-06 by reading the code, not by guessing. Line numbers are against the `persistence` branch at commit 8825a93.

- [x] **Player data module / ProfileService wrapper**: there is none. `src/server/SaveService.server.lua` is a hand-rolled DataStore profile, about 290 lines, no ProfileService and no session locking. Live state is a `profiles` table keyed by Player holding `{ data = { upgrades, furthestSection }, loaded = bool }`. Its load posture is load-bearing: a profile that fails to load sets `loaded = false` and is then never saved over, which is what lets a Studio session without API access play identically and wipe nothing. Any pet field added has to keep that property.
- [x] **DefaultData location and current schema**: no DefaultData module exists. Defaults are an inline literal in `bindPlayer` (`SaveService.server.lua:250`). The saved payload is `{ coins, upgrades, furthestSection, savedAt }` (`SaveService.server.lua:141`). There is no `schemaVersion` field and no migration table: the schema is versioned through `Config.Persistence.KeyPrefix = "v1_p_"`, on the stated principle that a schema change starts clean rather than migrating. Bumping that prefix is a wipe, so it must not be bumped for an additive change.
- [x] **Maze completion, server side**: two candidate events, both in `src/server/TowerTimerService.server.lua`. `enterFloor` (line 134) fires when a floor is cleared, `completeTower` (line 212) when a tower is topped out. Neither is exposed to other server scripts: the file's only output is `push`, which fires the `TimerUpdate` RemoteEvent at the client. There is no server-to-server event channel anywhere in the project yet, so one has to be introduced. See the reconciliation section.
- [x] **Summit arrival**: already detected, no summit zone needs building. Every building has one `RoofTrigger`-tagged part carrying `Section`, `Building` and `ArrivalX/Y/Z`. `TowerTimerService.onRoof` (line 196) does an axis-aligned extent test inside the existing 4 Hz Heartbeat loop, with a `Touched` binding (line 328) as a backstop. Both paths call `completeTower`.
- [x] **Remotes convention**: RemoteEvents only. No RemoteFunctions, no BindableEvents, and today **zero client-to-server traffic of any kind**. The owning server service creates its remote at require time with a FindFirstChild-or-create in ReplicatedStorage; the client does `WaitForChild`. Three exist: `TimerUpdate` (TowerTimerService), `PickupUpdate` (PickupService), `ShopUpdate` (SaveService). Each carries a single table payload discriminated by a `kind` field, and carries events only, never numbers a late client could miss. Player interaction with world objects goes through ProximityPrompt or Touched, never a remote, so the pet system's intents are the first client-authored input the server will ever see.
- [x] **Currency**: `coins` already exists and is not new. It is `leaderstats.Coins`, an IntValue, awarded by PickupService, spent by SaveService's shop, and persisted by SaveService. It is deliberately stored in exactly one place: SaveService reads it back off leaderstats at save time rather than keeping a second copy. Egg `coinCost` reuses it directly.
- [x] **Shared module path convention**: `src/shared` maps **directly onto ReplicatedStorage**, not onto a `Shared` folder inside it, so the shared module require is `require(ReplicatedStorage:WaitForChild("MazeConfig"))`. Files are `.lua`, never `.luau`; Rojo infers class from the suffix (`.server.lua` Script, `.client.lua` LocalScript, plain `.lua` ModuleScript). `default.project.json` maps the three `src/` folders wholesale, so a new file or subfolder ships by existing in the right place with no project file edit.

## Repo reconciliation

Where the spec's generic shape meets this repo. The spec is written provider-neutral; these are the local answers and they win.

1. **File extension and require paths.** `.luau` becomes `.lua`. `require(game.ReplicatedStorage.Shared.Types)` in spec Section 3 is wrong here and becomes `require(ReplicatedStorage:WaitForChild("Types"))`. Verified: `selene` parses `export type` and type annotations inside a `.lua` file with zero errors, so the type layer costs nothing. The CLAUDE.md `luac -p` convention does not bite, because `luac` is not installed on this machine anyway; the real out-of-Studio syntax check is selene plus the luau binary under `~/.rokit/tool-storage`.

2. **`coins` comes out of `PlayerData`.** The spec's `PlayerData.coins` would create the second copy of the number that SaveService deliberately does not keep. Pet data stores no currency; egg purchases read and write `leaderstats.Coins`.

3. **`schemaVersion` without a migration, and without touching `KeyPrefix`.** Every pet field is additive, and the loader already reads absent fields as defaults (`result.upgrades or {}`), so old profiles need no migration to gain pet fields: they simply load with empty pets. Write `schemaVersion = 1` into the payload for later use, keep `KeyPrefix` at `v1_p_`. Bumping the prefix to get a "clean" pet schema would wipe every coin and upgrade tier already banked, for no gain.

4. **Config splits in two.** CLAUDE.md requires all gameplay tuning to live in MazeConfig and forbids magic numbers in services, but a pet and egg catalogue is content, not tuning, and MazeConfig is already 550 lines. So: tuning numbers (storage caps, `maxEquipped`, hatch boost rates, follow distance, prompt distance) go in a new `Config.Pets` block in `src/shared/MazeConfig.lua`; the catalogue goes in `src/shared/PetCatalog.lua` and `src/shared/EggCatalog.lua` next to it, with `src/shared/Types.lua` for the exported types.

5. **The maze completion hook needs a new convention.** TowerTimerService talks only to clients. Adding a `require` from a pet service into a `.server.lua` Script is not possible, and re-binding `RoofTrigger` in a second service would duplicate the poll that exists precisely because touch has a failure mode. The proposed channel is a single BindableEvent, created FindFirstChild-or-create in ServerScriptService by TowerTimerService and fired from `completeTower` and `enterFloor` with the same `kind`-discriminated payload shape the RemoteEvents use. That is a new project-wide convention and belongs in CLAUDE.md's conventions list once it exists.

6. **An incubator pedestal is a generator change, with all that implies.** Nothing is ever parented into `workspace.MazeCity` at runtime, so a roof prompt cannot simply be attached to the existing `RoofTrigger` part. The two honest options are: generation places an `EggPedestal`-tagged part on each roof exactly the way `buildShop` places `ShopItem` pedestals, which is subject to invariant 6 (it must draw no random numbers or the whole city reshuffles) and moves the part-count baseline by a countable per-building delta; or Clutch 2 places the egg from a HUD button gated on the server already knowing the player is on a roof, which adds no geometry at all. Recommend the HUD route for Clutch 2 to keep the loop testable, and defer the pedestal to Clutch 5 where the summit UI is being built anyway.

7. **Client-to-server intents are new ground.** PlaceEgg, EquipPet, UnequipPet, nickname and lock are the first messages this game will ever accept from a client. Every one of them validates ownership and state against the server profile, and nickname needs `TextService:FilterStringAsync`.

8. **A profile is a module, not a Script.** Implementing Clutch 1 turned up the thing the prerequisites audit recorded but did not follow through: `SaveService.server.lua` is a Script, and a Script cannot be required, so three new services could not reach the table they all mutate. The DataStore, the load posture, the autosave and the defaults moved into `src/server/PlayerProfiles.lua`, a ModuleScript alongside `MazeGenerator.lua`. SaveService kept the shop, the tier-to-attribute mapping and the furthest-section credit, and reads the profile through the module like everyone else. `Profiles.onReady(fn)` is how a service is told a profile is readable, and it replays for players already loaded, so registration order does not matter. The rules that operate on that table (caps, levels, the hatch roll, the client projection) went into `src/server/PetInventory.lua`, because three services enforcing the same cap check is three chances for them to disagree.

9. **Model references are ServerStorage names, not asset ids.** The spec's `baseModelId`/`modelId` would be a field nothing reads: this project loads rigs from `ServerStorage/<Kind>/<Name>` with a placeholder fallback, which is what lets the game be fully playable from a cold `rojo build`. Both became `model`, plus a fallback drawn until an artist puts a rig at that name: a `placeholder` table of colour, shape and size at first, and since PET_LOOKS_PLAN Set 2 a `look` recipe `PetModelGenerator` builds a whole rig from. `ServerStorage/Pets/<model>` is the pet equivalent of `ServerStorage/Enemies/<TypeName>`.

10. **`IncubatorState` carries `eggId`.** Placing an egg removes the `EggInstance` from the eggs map so it exists in exactly one place and cannot be placed twice or sold from under itself. The config key has to travel with it or the incubator references something that no longer exists.

11. **Eggs are sold at the roost.** The plan scheduled no way to get a second egg: the starter is granted once and the streak egg is a week away, so after the first hatch the loop was dead and Clutch 5's exit criterion could not be met. The pedestal prompt opens the panel, and the panel's Eggs tab sells any catalogue egg carrying a `coinCost` out of `leaderstats.Coins`, the same mechanism and the same currency as the upgrade shop. An egg with no `coinCost` is not for sale, which is what keeps the streak egg off the shelf without a second flag. Robux products remain a non-goal.

12. **Glow is a light on the rig, not a client draw.** Clutch 3 called it a pure client visual. A follower is a world object every player can see, so a `PointLight` on the rig replicates once instead of being drawn N times, and it is still driven entirely by server-validated equip state. The evolution multiplier scales range and deliberately not brightness, for the reason `Config.World.LampBrightness` documents at the other end of the city.

### Settled decisions

- **The climb that carries a player to the roost counts.** A roost is on a roof and the only way onto a roof is up through that tower's ten floors, so placing an egg always happens the instant a tower is finished. That completion used to be discarded, because the incubator was still empty when it fired, which made the Summit Egg's "2 towers" three climbs and the catalogue number a lie. `IncubatorService` now holds one summit as a credit and spends it on the next placement. Exactly one, never accumulated, and a summit that goes to an active incubator sets no credit, which is what stops a player hatching at a roost and then placing a second egg into the same climb.
- **What counts as a maze: towers topped out, at the spec's numbers.** `Config.Pets.HatchUnit = "tower"`, Summit Egg at 2 and Royal Summit Egg at 8. TowerTimerService fires both `floor` and `tower` on the bindable unconditionally, so this is a config read on the listening side and flipping it needs no service edit; what it does need is a pass over every `mazesRequired` in `EggCatalog`, because at `"floor"` the Royal Egg becomes most of one tower. XP is deliberately not governed by it: both kinds pay, so a player who only ever clears floors still levels a pet.
- **The summit prompt is generated geometry.** `buildEggRoost` puts an `EggPedestal`-tagged pedestal, egg, board and prompt on every roof deck, as a pure function of the footprint drawing no random numbers (invariant 6). Cost is +5 instances per building, +30 per section, which moves the determinism baseline once by a countable amount. It sits at `(FX / 2, FZ * CFG.ROOST_Z_FRAC)`, the one part of the deck nothing else uses.

- **A pet is a defence, and the shape of it is a ward rather than a fight.** Requested 2026-08-09, after the enemy roster was finished at Milestone E4. The design constraint is that combat is out of the game: enemies cannot be damaged, every one of them is outrunnable, and nothing a player does to an enemy exists. So the defensive pet does not fight, it makes enemies lose interest: an enemy inside an active ward drops its target, forgets where it saw anybody and walks back to its marker.

  The three things that keep it from swallowing the game:

  1. **It is a duty cycle, not a state.** The ward is idle until an enemy comes inside its radius, then it runs for `activeSeconds` and recharges for `rechargeSeconds`. A permanently-on aura would strictly dominate the Ghost powerup and the Cloak ability, which are the two things a player spends coins on for exactly this problem. Triggered rather than blindly cyclic because a ward that spends its uptime in an empty corridor is a ward a player cannot learn to rely on.
  2. **It costs the only equip slot.** `Config.Pets.MaxEquipped` is 1, so carrying the ward means not carrying Glow, and a dark maze is the price of a safe one. That is the trade the ability is for and it needs no extra mechanism.
  3. **It never damages, stuns, or moves an enemy.** A warded enemy walks home under its own power at its own speed, which means nothing about the enemy system's promises changes: it is the existing Return branch, reached from a new gate.

  The channel is the one Ghost and Cloak already use: **a flag on an instance, written by the owning service and read by the enemy side.** PetService writes `WardRadius` on the follower rig while the ward is running and clears it when it stops, so the attribute existing *is* the ward being up; `Enemy/EnemyWard` is the reader and the only thing on that side that knows pets exist.

### Open decisions

- **Where this sits against the ship plan.** The v1 plan is at P, then M5 (README/CI), then M6 (ship). Pets is a whole new system with a save-schema change and the project's first client input surface. Either it lands after M6 or it displaces M5 and M6; it should not run beside them on the same save format.

## Clutch 1: Data layer

Adapt spec Section 1-3 into the project's real paths. **Done.**

- [x] `src/shared/Types.lua`, exported Luau types, reconciled per points 2, 9 and 10 above
- [x] `src/shared/PetCatalog.lua` (4 pets) and `src/shared/EggCatalog.lua` (3 eggs), placeholder rigs
- [x] Pet fields in the profile defaults, in `src/server/PlayerProfiles.lua`
- [x] `schemaVersion = 1` written into the payload. No migration table: `adopt` merges field by field against defaults, so an absent field loads as its default and an old profile is simply a player with no pets. `KeyPrefix` stays at `v1_p_`.

Exit: new player joins, save contains pet fields, existing saves load with empty pets, no gameplay changes visible.

## Clutch 2: Incubator and hatching

Spec Section 4 transitions, minus equip. **Done.** `src/server/IncubatorService.server.lua`.

- [x] PlaceEgg validated on ownership, an empty slot, and proximity to a tagged `EggPedestal`
- [x] Maze completion hook: the `MazeProgress` BindableEvent, per reconciliation point 5
- [x] Weighted hatch roll server side, with the pet storage cap check refusing rather than dropping the pet
- [x] Rarity broadcast, Epic and above, `Config.Pets.BroadcastFrom`
- [x] Starter egg on first join, remembered by `starterGranted`

Exit: get egg, climb, place, top out twice, hatch, pet in the profile.

## Clutch 3: Pet presence and first ability

**Done.** `src/server/PetService.server.lua`.

- [x] Follower rig in `workspace.LivePets`: anchored, CFrame-eased, bobbing and spinning. Not pathfound and not physics, for the reasons in the file header.
- [x] Equip/unequip with `maxEquipped`. At one slot, equipping a second pet swaps rather than refusing.
- [x] Glow end to end, per reconciliation point 12
- [x] Evolution multiplier applied through `Inventory.abilityMultiplier`, reachable at Firefly level 10

Exit: equipped pet follows through a maze and lights it.

## Clutch 4: Progression and dailies

**Done.** XP and evolution in PetService, dailies in `src/server/DailyRewardService.server.lua`.

- [x] XP to equipped pets on both floor clears and tower completions
- [x] Levels from total XP against the curve, so a rebalance re-derives every existing pet rather than freezing it; stage swap rebuilds the rig and the light
- [x] Daily claim on the UTC day number, streak, day 7 streak egg

Exit: a pet levels and evolves; the claim refuses twice in one UTC day and grows the streak across a boundary.

## Clutch 5: Surfacing

**Done.** `src/client/PetGui.client.lua`.

- [x] `EggPedestal` prompt on every roof, opening the panel's Eggs tab; hatch progress bar; a client-drawn egg over the roost while one is incubating
- [x] Pet inventory: list, equip, lock, nickname, XP bars, caps
- [x] Hatch reveal: full-screen wash in the rarity colour, rays scaling with rarity
- [x] Rarity broadcast to every client

Exit: system is playable without developer knowledge.

## Clutch 6: Ward, the defensive ability

**Done, 2026-08-09.** The first pet ability that touches another system, and the first reason to equip a pet that is not convenience. Settled decision above is the design; this is what landed.

- [x] `Ward` ability type in `PetCatalog`, on one new pet (`ward_hound`, Rare), with `radius`, `activeSeconds` and `rechargeSeconds` params. The evolution multiplier scales radius and not uptime, on the same reasoning Glow scales range and not brightness: the stronger version covers more corridor rather than being on more of the time.
- [x] Added to all three egg hatch tables, because a pet no egg can roll is a pet nobody has.
- [x] PetService owns the cycle: it scans `workspace.LiveEnemies` at `Config.Pets.WardScanSeconds`, arms on the first enemy inside the radius, publishes `WardRadius` on the rig for `activeSeconds`, then clears it and recharges. The ring is a part on the rig, drawn on the floor rather than at pet height, and it is the whole of the feedback: ring up means safe.
- [x] `src/server/Enemy/EnemyWard.lua` is the enemy-side reader, list cached for one think interval, positions read live.
- [x] The gate in `EnemyController:tick`, placed after `behavior.update` rather than with freeze and stun, and the refusal in `EnemyCombat.canAttack`.

Exit: equip the ward pet, walk a floor with enemies on it, watch them turn around; unequip and watch them chase.

### What is not covered by any clutch

- Pet **release** does not exist, so a full pet shelf is unblocked only by raising the cap. `Inventory.setLocked` is in place for the day it does.
- Nicknames cannot be tested in a Studio session without text filtering: `TextService:FilterStringAsync` failing is treated as a refusal, which is the safe direction for a string other players read.
- `ServerStorage/Pets/<model>` is empty, so every pet is a rig `PetModelGenerator` builds from the `look` recipe on its catalogue entry. That is the same bargain enemies strike and needs no code change to undo: an artist's model at that name still wins. PET_LOOKS_PLAN.md Set 2 is what replaced the coloured placeholder with the generated rig, and the artist-model-wins-by-name half is unchanged.

## Later clutches (unscheduled)

- Remaining abilities: DeadEndPing, CoinMagnet, CheckpointSave, SpeedBoost, HatchBoost. Ward came out of this list ahead of all of them and is Clutch 6. `Inventory.equippedAbility(data, type)` is the resolver they all go through and is already wired for HatchBoost in `IncubatorService`, so the first of these should be a catalogue edit plus one applier. CoinMagnet is the one with an integration to think about first: `MagnetRange` on the player is written by SaveService from upgrade tiers, so a pet writing it too needs the two combined rather than one overwriting the other. It is the pull in absolute studs now, not a bonus on `PickupRadius`, so a pet adds to a reach rather than to a radius.
- Pet release, which is what makes the pet storage cap a decision rather than a wall
- Multi-equip gamepass, storage cap products, premium eggs
- Seasonal/event eggs via `availableUntil`
- Trading (separate spec required)

## Working agreement

- One clutch per branch, diff-reviewed against this plan
- Server authoritative for all mutations, client sends intents only
- No new systems invented outside this plan; if something's missing, update the plan first
