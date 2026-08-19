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

### Lore integration audit

The three items `docs/LORE.md` Section 10 adds to this checklist. Answered 2026-08-10 by reading the code; line numbers are against `main` at commit f51d592. LORE.md stays the source of truth for every line of player-facing text, and nothing below is a change to make now: it is where the game can be listened to as it stands.

- [x] **Where each Kept detection/alert event fires server-side.** Four of the seven are already discrete edge-triggered moments with the player in hand, one is discrete but anonymous, and two do not exist at all.

  The finding that covers all seven: **nothing an enemy notices leaves the enemy system today.** No module under `src/server/Enemy/` requires anything outside that folder and ReplicatedStorage, and `EnemyAlert.broadcast` returns a recipient count that nothing in the game reads (`EnemyAlert.lua:57`). So even the four clean moments need a channel before a journal can hear them: one BindableEvent in `ServerScriptService`, FindFirstChild-or-create on both ends, which is the convention `MazeProgress` and `PetsChanged` already follow (reconciliation point 5). Where a moment carries a player, the target is a HumanoidRootPart throughout and the character is `target.Parent`; the type is `controller.enemyType` (`EnemyController.lua:118`, set from `EnemyFactory.lua:113`).

  - **Watcher spot: detectable.** `Enemy/Behaviors/Guard.lua:66`, `onTargetAcquired`, broadcasting at line 71. The edge is the controller's, not the behavior's: `EnemyController:acquire` (`EnemyController.lua:347`) calls the hook at line 354 only under the `hadNone` guard at line 352, so it fires on the transition into having a target and not on every tick that holds one. Guard is shared by three types and the alert half is gated on `behaviorConfig.alertRadius` (`Guard.lua:69`), which only the Watcher row carries (`EnemyDefinitions.lua:491`); Sentry and Gatekeeper never reach line 71. A journal should still key on `enemyType` rather than on reaching that line, because the gate is a row field and a second row could grow one.
  - **Shrieker scream: detectable.** `Enemy/Behaviors/Shrieker.lua:32`, `shriek`, called from `update` at line 65 once `shriekWindup` has elapsed. The per-player line is 52, `EnemyStatusService.apply(character, "Revealed", seconds)`, with the character read at line 50. Note that `shriek` can also fire at `controller.lastSeen` with no live target (line 37), which is a scream with nobody in it; the character guard at line 50 is already where that distinction lives, so the journal listens there and not at the top of the function.
  - **Mimic reveal: detectable.** `Enemy/Behaviors/Mimic.lua:83`, `filterTarget`, at the transition on line 92 where `revealed` is set and the prop comes off. It is one-shot per rig by design, because a Mimic never re-hides (file header, lines 21 to 23), and the target that triggered it is the argument. One trap: `Mimic.lua:69` sets `revealed = true` at init for a rig with no allowed props, which is a Mimic that was never disguised, and that path must not be counted as a reveal.
  - **Shadow freeze: detectable, but anonymous.** `Enemy/Behaviors/Shadow.lua:87`, the branch that calls `setStatue(controller, true)` at line 89. It is a genuine edge and not a per-tick repeat, because `setStatue` (line 54) is cached against the flag and returns early at line 55. What is missing is who did it: `watchedBy` (line 37) finds the watching player and then discards it, returning `true` at line 46. **Smallest change that would make it listenable:** have `watchedBy` return the player it found instead of `true` (and `nil` instead of `false`), and bind it in the `update` branch at line 87. Two lines, no new module, no behavior change, and the loop already has the player in hand at line 39. Not made.
  - **Gatekeeper leash reset: not detectable as a discrete event.** There is no leash-reset moment anywhere in the system. What actually happens is that `EnemyTargeting.isEligible` fails its final range test against the marker (`EnemyTargeting.lua:137`), `pick` returns nil (line 158), the controller runs `loseTarget` (`EnemyController.lua:451`, then 358), and the Return branch transitions at line 496. Neither of those two points is specific to the leash. `loseTarget` is equally reached for lost line of sight, the floor band (`EnemyTargeting.lua:131`), a Ghost orb or a Cloak (`EnemyTargeting.lua:101` to 109), and a safe zone (line 134); `State.Return` is also entered from the ward and safe-zone branch at `EnemyController.lua:434` and from the drift test at line 496. Nothing anywhere distinguishes "you outran it" from "you cloaked" or "it lost sight of you", which is exactly the distinction fragment 14's text is teaching.

    **Smallest change that would make it listenable:** give `EnemyController:loseTarget` a reason argument and pass one from each of its two call sites in `tick`, the ward and safe-zone branch at line 430 and the targeting branch at line 451. The targeting one derives its reason by asking `EnemyTargeting.leashFor(self)` against the dropped target's distance from `self.home` before clearing it, which is one magnitude test on a tick that has already decided to lose the target, so it costs nothing per tick in the common case. `BaseBehavior.onTargetLost` (`BaseBehavior.lua:56`) then carries the reason to the behavior. Not made.
  - **Warden encounter: detectable.** `Enemy/Behaviors/Warden.lua:73`, `onTargetAcquired`, on the same `hadNone` edge as the Watcher and unconditional, because the Warden row always carries `alertRadius` (`EnemyDefinitions.lua:912`). This is "it saw you", which is the only sense of encounter the server currently holds an opinion about. If an encounter is meant to be "you saw it", nothing exists: there is no rig-proximity signal and no client visibility report anywhere in the enemy system.
  - **Warden survival: not detectable**, and the reason is structural rather than a missing hook. The enemy system has no notion of an encounter *ending*, well or badly. The three things that end a Warden's interest are the three that end anyone's and none of them is labelled: `loseTarget` (`EnemyController.lua:358`), the Return branch (line 496), and `EnemyController:stop` (line 243), which is the walk-away despawn `EnemyService` drives when the player gets far enough away. The player's own death is on the other side of the game entirely, in `TowerTimerService`.

    **Smallest change that would make it listenable:** the reason-carrying `loseTarget` above, plus a per-player "in an encounter with this rig" flag held by whichever service listens, so that an end can be paired with the start it belongs to. What the pairing has to satisfy is the open design decision immediately below, so the shape of the change is known and its condition is not. Not made.

- [x] **Login streak tracking.** It exists, and it is a **claim** streak rather than a login streak. The field is `data.daily = { lastClaimDayUtc, streak }`: defaulted at `PlayerProfiles.lua:76`, merged at line 174, written into the payload at line 244. Its only writer is `DailyRewardService.server.lua:78`, off `nextStreak` at line 46. Two properties bear directly on fragment 13:

  1. It counts claims, not sessions. A player who plays every day and never presses the claim button sits at `streak = 0` forever, so a fragment gated on "7-day login streak" is really gated on seven consecutive daily claims. There is no login timestamp, session counter or separate streak field anywhere in the profile.
  2. It wraps. `nextStreak` returns 1 as soon as the streak would exceed `Config.Pets.DailyStreakLength` (`DailyRewardService.server.lua:49`, seven at `MazeConfig.lua:609`), so `streak >= 7` is only true during the session in which the seventh claim is made. A `Stat`-style trigger evaluated on any later event would never see it. Fragment 13 therefore has to be caught or banked at the claim itself and cannot be a poll over the profile, which makes it the one trigger in the table that is genuinely event-shaped despite reading like a stat.

- [x] **What counts as "surviving" an encounter. Answered 2026-08-11: the enemy gives up while you are alive.** An encounter opens at a start moment the enemy system already holds (the scream, the acquisition) and closes when that same rig loses you or walks away and despawns, with a death between the two cancelling it rather than closing it. Not a timer and not a floor clear: both of those are true of a player who was never in danger, and fragment 14's own text ("they always go home") is a description of the enemy giving up rather than of the player outlasting anything. It is the gate on fragments 9, 14 and 17 and on the Codex's second-stage Kept unlock, and all four read it the same way.

  The consequence for unit 3 is that the pairing, not the reason, is what most of it needs. A start plus an end plus a death cancel is enough for fragment 9 and, on the same shape, for 17: `EnemyController:stop` and `onTargetLost` both already fire, and neither has to say why. **Fragment 14 is the one that still cannot be written**, because it is the only one that names *why* the enemy gave up, and outrunning a leash is exactly what the system does not distinguish from a lost line of sight or a Cloak. So the reason-carrying `loseTarget` above stays deferred and 14 stays unreachable, blocking 15 to 17 behind it until it is written.

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

## Clutch 7: Lore & Journal

**Done: all five units.** Defined by `docs/LORE.md` Section 10, which is the source of truth for every line of text this clutch ships; the audit above is where the game can be listened to. LORE.md's own exit criterion for the whole clutch is that a fresh save can unlock fragments 1 to 17 by playing, in order, with out-of-order accomplishments banked correctly.

The rule LORE.md asks CLAUDE.md to carry, and it belongs there rather than here: **all player-facing lore text lives in LORE.md first, then in the Lore and Journal configs.** No lore line is invented mid-task; new content means updating LORE.md in the same branch.

Five branch-sized units, in order.

**1. The configs. Done, 2026-08-11.** `src/shared/Lore.lua` and `src/shared/Journal.lua`, holding LORE.md sections 2, 3, 5 and 9.1 verbatim. `.lua` not `.luau` and directly under `src/shared`, not `src/shared/Config/`, per reconciliation point 1 and the shared-path convention: LORE.md's paths are the spec-generic shape, the same way the pet spec's were. `Journal.lua` is an array whose order is unlock order and whose triggers are the two-variant type in LORE.md 9.3. Content only, no runtime, the same bargain `PetCatalog` and `EnemyDefinitions` strike.

Four decisions settled it, taken 2026-08-10. Each one closed conflicts from the list below.

- **A lore key mirrors the case of the table it points at, rather than one blanket convention.** LORE.md's rule is that the keys match the source ids exactly, and the sources do not agree with each other: `EnemyDefinitions.types` is PascalCase (`Watcher`, `SplitterChild`) while the three catalogues key on a snake_case `id` field (`firefly`, `summit_common`, `lantern_hat`). So `kept` is PascalCase and the other three tables keep the case LORE.md already wrote. CLAUDE.md's PascalCase rule does not reach these: it governs attribute, tag and config keys, and a catalogue id is content.
- **`Lore.lua` validates its own keys at require time**, against the four source tables, all of which are already in ReplicatedStorage and requirable from it. The check runs one way only: every lore key must resolve to a real id, while an id with no lore is legal and simply means no flavour text. That is what makes the two conflicts below structurally unable to come back, and it turns a typo from a Codex row that silently never appears into a startup error.
- **The ten missing entries were drafted into LORE.md rather than invented here**, which is the rule LORE.md asks CLAUDE.md to carry. Six Kept (Drifter, Stalker, Sentry, Swarmer, Lurker, Charger), three pets (Lumen Moth, Ward Hound, Coin Bat) and the Streak Egg, each written against the shipped mechanic the way the existing thirteen are. They are a first draft standing in the doc for editing, and editing them is a doc change and not a code change.
- **`relics` ships empty and the Relics chapter is deferred.** No id in LORE.md Section 5 exists in `AccessoryCatalog`, there is no `set` field for the named sets, and nothing in the game drops anything, so the Hollow Set has no source. The chapter arrives with the gear economy, PET_ACCESSORIES_PLAN Set 5.

`Journal.lua` can be written complete today even though five of its triggers have no source yet: the array is content, and a fragment whose event never fires is unit 3's problem rather than this one's. Its stat triggers read `floorsCleared` and `summitsReached` and deliberately never `mazesCompleted`, for the reason recorded against conflict 11 below.

Four things landed that those decisions leave open, and they are what unit 3 and unit 5 inherit.

- **The one-way key check grew a second half, and it is the same rule applied to an array.** `evolutionLines` is positional against the catalogue's `evolutions`, so a line with no stage under it can never be shown, which is a lore key pointing at nothing spelled differently. More lines than stages is therefore an error too, and it catches something real today: LORE.md gives the Firefly a second evolution, "Solar", and `PetCatalog` ships one stage per pet. The line stays in the doc and is out of the config until the stage exists.
- **`Journal.lua` validates itself as well**, on the same reasoning and against a shorter list, since it has no catalogue to check against. Ids unique, trigger shapes well formed, and two rules that are content decisions made structural: a `Stat` trigger may only name `floorsCleared` or `summitsReached`, so conflict 11 cannot be reopened by a typo, and no two fragments may share an `Event`, because the second would unlock the moment the first banked without ever having been earned.
- **The module is the array**, per LORE.md 9.3, so `#Journal` is the chapter's size and there is no wrapper table to keep in step with it. The exported types went to `Types.lua` beside `JournalState` rather than into the config, which is where this repo documents shapes and where nothing requires a catalogue to read one.
- **A locked Codex row has no hint text yet.** LORE.md 9.2 wants `???` plus a subtle trigger hint and writes exactly one of them as an example ("Survive the bell"). There is no field for it and there are no lines, and inventing seventeen here would have broken the rule that text is written in the doc first. Unit 5 needs LORE.md to gain them, then a `hint` field beside `spawnHint`.

- Exit: met. `selene src/` clean, both modules in a cold `rojo build`, and the require-time validation run over the real catalogues outside Roblox under the luau CLI, the way `tools/petlooks/check.sh` runs the rig builder: 5 pets, 3 eggs and 20 Kept all resolving, 17 fragments across 5 stat and 12 event triggers, no catalogue entry left without lore. Both negative tests fail loudly as intended: a Kept key of `drifter` errors with "matches no EnemyDefinitions.types id", and a stat trigger moved to `mazesCompleted` errors with the stat it may not read.
- Depends on: nothing outstanding. Conflicts 1 to 6 and 9 to 11 are closed below; 7 and 8 are open but do not reach either file.

**2. The codex table in player data, with migration. Done, 2026-08-10.** `codex = { pets = {}, kept = {}, relics = {}, journal = { unlocked = 0, banked = {} } }` added to `defaults`, merged chapter by chapter in `adopt` so an absent chapter loads empty, and carried in the `save` payload. No `KeyPrefix` bump: it is additive and the loader already reads absent fields as defaults, which is reconciliation point 3 applied a second time.

Three things landed that LORE.md's `codex = { ... }` sketch leaves open, and unit 3 inherits them:

- **The journal chapter is a count, not a set.** Fragments unlock strictly in order, so "which are known" is how far `unlocked` has got, and a gap that cannot happen has no way to be written down. `banked` beside it is the Event triggers that fired before the fragment owing them came up; a Stat trigger banks nothing, `stats` being a running total that is still true whenever it is asked.
- **`kept` holds a stage rather than a flag**, because a Kept entry unlocks twice (LORE.md line 81: silhouette and name on first encounter, lore line on surviving one). What the stage numbers mean is unit 3's to name; unit 2 only left room for them. `pets` and `relics` are plain sets.
- **`adopt` type-checks `codex` and `codex.journal` before indexing them**, which nothing else in the file does. It is the first stored field read into rather than handed over whole, and `adopt` runs after `entry.loaded` is already true, so an error there would leave a profile that is allowed to save holding nothing but defaults. That is the wipe the failure posture exists to prevent, and the guard is two `type()` calls.

`Types.CodexState` and `Types.JournalState` are where the shape is documented, and `PlayerData` grew `codex`.

- Exit: met. Driven headlessly over the real module under stub services rather than in Studio, since both halves are load and save paths and neither needs a world: an old payload with no codex adopts four empty chapters, unlock state round-trips through save and rejoin, a scalar or half-written codex adopts as empty instead of erroring, and with the DataStore refused the profile plays on defaults and an existing record is left byte for byte alone. `selene src/` clean and both modules in a cold `rojo build`. Worth a Studio pass at the next real playtest anyway, since the stub store is not the real one.
- Depends on: no audit finding. This unit can land before any of the enemy questions are settled.

**3. Sequential unlock with banking. Done, 2026-08-19.** `src/server/LoreService.server.lua` owns the whole of LORE.md 9.1: on any trigger, satisfy only the next locked fragment; on any unlock, re-check, because an unlock can make a fragment's successor immediately satisfiable. That re-check is the unlock loop itself rather than a second pass, `satisfied` reading live state on every turn of it. `src/server/Enemy/EnemyLore.lua` is the channel out of the AI, `src/client/LoreGui.client.lua` is the toast, and `tools/lore/check.sh` drives the whole rule headlessly.

Five things landed that the sketch above left open, and units 4 and 5 inherit them.

- **A service fires facts, never fragment ids.** `EnemyLore` states that a Watcher opened an encounter or that one was survived; `LoreService`'s `ENCOUNTER` and `MOMENT` tables are the only place those facts and the journal's event strings meet. So reordering the array, renaming a fragment or writing one about the Trapper reaches no other file, and the AI never learns what a journal is. Same split as `EnemyWard` knowing one thing about pets.
- **An Event trigger has two detectors and one record.** A *fact* arrives on the channel. A *witness* is a predicate over the profile, and four of the five pet-side fragments are witnesses (`FirstEggAcquired`, `FirstEggPlaced`, `FirstHatch`, `FirstEvolution`), because the saved data already remembers them: an egg in the shelf, an incubator with something in it, `stats.eggsHatched`, a pet past stage 0. That removed the fire sites in `IncubatorService` and `PetService` the sketch assumed. Both kinds still bank, and that is the load-bearing half: the predicate is the detector, the bank is the record, so a witness that stops being monotonic later (pet release, an egg taken back out of a roost) cannot re-lock a fragment somebody has already read. `SevenDayStreak` is the one pet-side fragment that is a fact, and it has to be, for the login streak finding's reason.
- **The Gatekeeper finding is closed, and 14 has a source.** The audit read it as needing a new signal. It does not: `EnemyTargeting.pick` drops a held target for exactly two reasons, out of sight and out of leash, and which one it was is directly answerable at the instant of the close from the position the target was last at. So the encounter close carries a `reason` and the Gatekeeper's row requires `leash`. This is a deviation from the "must run correctly with 14 unreachable" line above and the service does still run correctly that way; what changed is that it no longer has to, and 15 to 17 are reachable rather than dark behind it. **Fragments 1 to 17 are all reachable by play.**
- **A qualifier is required, not decorative.** A Shrieker that chased somebody and gave up is not a scream survived, so the shriek marks the open encounter and the close carries the mark. `mark` and `reason` are the two qualifiers a row may state and both default to unstated.
- **A profile landing catches up quietly.** Every witness re-derives from saved data, so an existing save joining for the first time under this service clears its whole backlog in one pass. Toasting each is a minute and a half of chip for somebody who did nothing, so the join re-check is silent and sends one summary line instead. Live play is never quiet and cannot be: nothing is earned during a load. It also means the summary is the only payload that can be lost to a client whose GUI has not connected yet, and losing it costs nothing.

The toast half of unit 4 shipped with this, since a fragment that unlocks with no way of knowing is a fragment nobody finds. It is a chip on the free left edge and deliberately not `UiTheme.banner`: LORE.md 9.2 rules out a modal, and the game's banner lands in the middle of the screen, which is right for topping out a tower and wrong for a wall writing found halfway up one. `Config.Lore` is the two timings.

- Exit: met. LORE.md's clutch criterion driven headlessly over the real `LoreService` and the real `Journal` under stub channels rather than from a Studio command, since the rule is a function of the profile plus what arrived and needs no world: nine scenarios in `tools/lore/check.sh`, including a fresh save unlocking nothing, stat fragments landing in order, an out-of-order Warden banked and waiting, a missing source blocking its successors and nothing else, witnesses banking from saved data with nothing fired, both qualifiers refusing an unqualified encounter, all seventeen unlocking in array order from facts that arrived backwards, the join catch-up summarised into one line, and nothing unlocking twice under repeated re-checks. `selene src/` and `stylua --check src/` clean, all three new files in a cold `rojo build`. What the harness cannot cover is `EnemyLore`'s own half, the encounter pairing and the death cancel, which needs a live controller and a humanoid: that is the Studio pass.
- Depends on: nothing outstanding. The **login streak finding** is honoured (13 is caught at the claim in `DailyRewardService`, never polled). The **Gatekeeper finding** is closed above. The **surviving decision** is implemented as settled: an encounter opens where the controller acquires a target and closes where that same rig loses it, walks home or stops, cancelled by the player dying or respawning between the two, which the close checks by re-reading the humanoid rather than trusting the pair.

**4. The wall spawn hook and the unlock toast. Done, 2026-08-19.** The toast shipped with unit 3. The writings are the rest of `LoreGui`, and the thing settled before the branch opened held: this is not a generation change and could not be one, `MazeGenerator` being deterministic and per section while unlocked-only spawning is per player. It is a client draw over walls the server already built, in a `WallWritings` model beside `MazeCity` and never into it, cleared the way `RouteHint` is.

Four things landed that the sketch above left open, and unit 5 inherits the last of them.

- **A wall is chosen by hashing its own position, not by rolling and not by a tag.** The sketch said "an existing tagged wall", and there is no such thing: only `PhantomWall` and `MovingWall` carry one, and both are the wrong wall. What generation left behind that answers the question is invariant 7's collision group, so a maze wall is `part.CollisionGroup == "MazeWall"` and a facade, slab, stair or parapet is not, by construction. Position hashing then does the rest with no state on either side: positions are a pure function of the world seed, so a wall carries a writing on every machine and in every session and a corridor walked back down says what it said. What two players see differently is which fragment, their pools differing, which is exactly the property LORE.md wanted and it costs no randomness and nothing on the wire.
- **How far the trail has got is a replicated player attribute**, `JournalUnlocked`, and that is the whole of what crosses. Same rule as AbilityService's tiers and for a sharper version of the same reason: a rejoining player unlocks nothing on join, so a client waiting to be told would stand in an unwritten maze until it earned its next fragment. The seventeen lines are already on every client in `ReplicatedStorage.Journal`, so a count is enough and no line is sent twice. The remote stays the toast's: a toast is a moment, an attribute is a state.
- **The floor filter is the fit test.** A writing occupies a band at reading height and a wall carries one only if its own vertical extent contains that band, which rejects a wall a storey up or down by the same comparison that stops a writing hanging off the top of one. That is why this client names no `LEVEL_HEIGHT`, where TimerGui's phantom sense had to filter on the parts' own `Level` attribute; a maze wall has no attributes, and it turns out not to need any.
- **`nestOnly` became real and `spawnHint` did not.** Fragment 17 is out of the wall pool and stands beside the Egg Roost, lettered on both faces because a roof is walked around, which is the only reason that flag was ever in the content. `spawnHint` has no values written in LORE.md, so the "weighted toward thematically matching areas" half of 9.2 is a doc edit before it is a code one, and it is recorded there as unimplemented rather than left to be discovered as a field nothing reads.

- Exit: met. `tools/lore/check.sh` still passes over the nine unlock scenarios, now asserting the published attribute beside the profile's own count everywhere it moves, which needed the harness's players to become objects; the negative case was run and all three new assertions bite. `selene src/` and `stylua --check src/` clean, cold `rojo build` clean. What the harness cannot reach is the draw itself, which needs a world: the Studio pass is one climb with a few fragments unlocked, one moving wall watched for a writing that should not be on it, and one roof stood on with fragment 17 owned.
- Depends on: unit 3, and on no audit finding.

**5. The Codex UI. Done, 2026-08-19.** `src/client/CodexGui.client.lua` is the panel, and the two chapters that had no writer got one in `LoreService`: `codex.kept` off the encounter pair it was already listening to, `codex.pets` as a witness over the profile's own pet list. Locked entries are `???` plus the fragment's `hint`, which is a new required field on every `Journal` row and seventeen new lines in LORE.MD 9.1, written there first.

Five things landed that the sketch above left open.

- **It is a HUD panel and not the monument at the Nest LORE.md 6.2 asked for.** A monument is a part, a part is generation, and generation is deterministic and per section where a Codex is per player: the objection that stopped the wall writings being baked in, unchanged. It would also be a reading room at the top of a ten floor climb, so a fragment unlocked on floor three could not be read until the roof, and the Kept page could not be read at all by the player who most wants it. It opens from a chip directly above the pet panel's, which turns the left edge into the column of things that open; the two panels are centred and mutually exclusive over a `UiPanelOpened` BindableEvent in the PlayerGui, found-or-created on both ends for the same reason every server-side one is.
- **A chapter's size is what a player can actually reach.** The Kept counts the nineteen rows that are not `spawnable = false`, which is what closes the roster conflict this unit was said to depend on: the disagreement was never about the meter, it was about whether the Splitter Child is in it. It is not, because nothing in this game does damage and a Splitter therefore never breaks, and it draws as a row anyway for whoever meets one, so the denominator stays fillable without the lore line being deleted. Pets counts the catalogue.
- **There is no Relics chapter and that is the honest version.** `Lore.relics` is empty and nothing writes `codex.relics`, so a fourth tab today is a meter that reads 0 of 0 forever. Deferring it is the same call unit 1 made about the content, and undeferring it is one chapter in the client plus one writer beside the other two.
- **One reward is written and it is the one that shipped.** Journal 17/17 grants the Compass Crow through `PetInventory.grantPet`, which means a full shelf refuses it, which is why `codex.journal.rewarded` is set by the grant landing rather than by the trail finishing and an unpaid reward is retried on every later re-check. The title is a replicated `CodexTitle` attribute, not a chat tag, there being no chat surface to hang one on. Per-chapter rewards are named in LORE.md and nowhere else: no line says what finishing the Pets chapter gives, so they are unwritten content rather than missing code.
- **The projection is pushed on change and requested exactly once.** The plan's line was "never off a request", and the request that survives is the join: a remote fired at a player whose LocalScripts have not connected yet is a chapter that never arrives, and a player who opens the panel before their next floor would be told they have nothing. Everything after it is pushed, and only when something moved, because an encounter opens every time an enemy notices somebody.

- Exit: met. `tools/lore/check.sh` grew five scenarios over the same real `LoreService`: the Kept chapter recording every type and only ever upward (including the one the journal's qualifier refuses), the Pets chapter witnessed off the profile and surviving the pet being taken away again, the projection pushed on a join and on a change and not on a repeat or on a floor that unlocked nothing, the sync answered, and the completion paying once, refusing a full shelf, publishing the title anyway and paying on the retry. Every new assertion was run against a deliberately broken service and bites. `selene src/` and `stylua --check src/` clean, cold `rojo build` carries the new client file. What the harness cannot reach is the drawing: the Studio pass is one Codex opened with nothing in it, one enemy met and then escaped from with the row watched through both stages, and one hatch watched into the Pets chapter.
- Depends on: nothing outstanding. **The roster conflicts** are closed by the denominator rule above rather than by a count being agreed. **`codex.pets` and `codex.kept` had no writer** and now have one each, in the file that was already listening to both channels.

### Conflicts between LORE.md and the shipped configs

Found while auditing. Nine of the eleven are closed, each marked with how; conflicts 7 and 8 are open and reach neither config file.

1. **Roster size. Closed: LORE.md corrected.** Section 3's header and Section 4's opening both say fourteen enemies. There are nineteen names in `EnemyTypes.Name` (`EnemyTypes.lua:26`) and twenty rows in `EnemyDefinitions` (`types.Drifter` at line 125 through `types.Gatekeeper` at line 1180). Fourteen is the count of *behavior modules* (`EnemyTypes.Behavior`, `EnemyTypes.lua:52`), which is a different thing: Drifter, Stalker and Sprinter share Chaser, and Sentry, Watcher and Gatekeeper share Guard.

2. **Six enemies have no lore entry. Closed: drafted into LORE.md Section 3, awaiting your edit.** They are the six a player meets first: Drifter (`EnemyDefinitions.lua:125`), Stalker (155), Sentry (204), Swarmer (253), Lurker (308) and Charger (363). All six are spawnable and all six are in the director's roster from the lowest floors.

3. **The `kept` key case does not match the config ids. Closed: a lore key mirrors the case of the table it points at, so `kept` is PascalCase and the rest are unchanged.** LORE.md Section 7 keys them `watcher`, `shadow`, `warden` and states that they must match the enemy config ids exactly. The ids are `types.Watcher`, `types.Shadow` and `types.Warden`, PascalCase, which is also CLAUDE.md's convention for config keys. The `pets` and `eggs` keys in the same block are not affected: `firefly`, `compass_crow`, `summit_common` and `summit_royal` all match their catalogue ids exactly.

4. **Splitter Child. Closed: the lore key is `SplitterChild`, matching the definitions row, and its absence from `EnemyTypes.Name` is left alone as a separate repo inconsistency for a branch that is not this one.** LORE.md gives it a Kept entry. The row exists at `EnemyDefinitions.lua:973` with `name = "Splitter Child"`, but its key is `SplitterChild` and it is the one definitions row absent from `EnemyTypes.Name`, which enumerates nineteen. So it is simultaneously a real enemy, a lore entry, and not part of the type vocabulary the lore doc says the keys must match.

5. **The Sprinter's burst speed. Closed: LORE.md now says 15.** It said 14.6 studs/s. The row is `walkSpeed = 12` (`EnemyDefinitions.lua:503`) with `sprintSpeedMultiplier = 1.35` (line 549), a product of 16.2, and `EnemyController:chaseSpeed` (line 331) puts that through `EnemyFactory.clampSpeed` against `Config.Enemies.MaxChaseSpeed = 15` (`MazeConfig.lua:834`). The shipped burst is 15 and 14.6 matches neither number. The durations are right: `sprintDuration = 3` and `exhaustDuration = 2.5` (lines 550 and 551). "Half speed" is `exhaustedSpeedMultiplier = 0.55` (line 552), close enough to stand or not by choice.

6. **Three configured pets have no lore. Closed: drafted into LORE.md Section 2, awaiting your edit.** Section 2 listed Firefly and Compass Crow as the existing configured pets. `PetCatalog` also ships `lumen_moth` (Uncommon, Glow, line 92), `ward_hound` (Rare, Ward, line 164) and `coin_bat` (Rare, CoinMagnet, line 234).

7. **Ward has no counter family. Open, and recorded as an open decision in LORE.md Section 4 with two ways out: a seventh Repel family, or folding Ward into Escape.** Section 4 declares five families plus Wayfinding and rules that every future pet ability is assigned one at design time, with no orphan abilities. Ward shipped in Clutch 6 and is none of Alarm, Escape, Cleanse, Watch, Warning or Wayfinding: it is a repel, and repelling is not a category the table has. The one ability that already exists is the orphan the rule was written to prevent.

8. **CoinMagnet is assigned twice. Open, and recorded in LORE.md Section 4 alongside conflict 7.** Section 2 gives it to a planned pet, Gilded Mole (Rare, Wayfinding). `coin_bat` (Rare, `PetCatalog.lua:234`) already has it.

9. **The Streak Egg has no lore line. Closed: drafted into LORE.md Section 2, awaiting your edit.** Section 2 gave one line per egg for `summit_common` and `summit_royal`. `EggCatalog` has a third, `streak_seven` (line 52), which is the day-seven reward that fragment 13's own trigger pays out.

10. **No relic id in LORE.md exists in the game. Closed: `Lore.relics` ships empty and the Codex's Relics chapter is deferred to PET_ACCESSORIES_PLAN Set 5, recorded in LORE.md Section 5.** Sections 5 and 7 name `cracked_lantern`, the Cartographer's Satchel and the Hollow Mask, plus three named sets. `AccessoryCatalog` ships twenty-two items and none of those ids is among them; the near misses are `lantern_hat` (line 48), `cartographers_circlet` (73) and `coin_satchel` (217). There is also no `set` field on an accessory row, so the named sets have nowhere to live yet, and no accessory is a Warden drop because nothing in the game drops anything.

11. **`mazesCompleted` is towers, not mazes. Closed: the journal never reads `mazesCompleted`.** Fragment 1 becomes a first floor cleared, fragment 2 `floorsCleared >= 5` and fragment 12 `summitsReached >= 5`, all updated in LORE.md's fragment table; the journal's pacing is then immune to a `HatchUnit` flip meant for eggs. As found: fragments 2 and 12 were gated on `mazesCompleted >= 5` and `>= 25`, and fragment 1 on a first maze completed. The stat counts whatever `Config.Pets.HatchUnit` says a maze is (`PetService.server.lua:669`), which is `"tower"` today, so those thresholds are five and twenty-five *towers topped out*. `floorsCleared` is the per-floor counter (line 665) and is the one whose name matches the fragments' intent. Fragment 15's `summitsReached >= 10` is unaffected and reads exactly as written (line 667).

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
