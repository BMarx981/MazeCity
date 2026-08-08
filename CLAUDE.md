# CLAUDE.md - Maze City

A Roblox tower-climbing maze game, built entirely from this repo via Rojo. There is no Studio plugin and no hand-placed geometry. The world generates server-side at startup and extends itself lazily as players progress.

Players enter a building at street level, solve a maze on each of 10 floors against a per-floor timer, climb spiral stairwells to the roof, and ride a slide from designated exit buildings to the next section of the city. Every roof, exit building or not, also has a zipline down to the plaza outside its own door, so topping out is never a dead end. Higher floors have walls that slowly move. Enemy types vary by building style and can be overridden per section.

## Core architectural rules

**1. Generation produces geometry and tags. Runtime services read tags. Nothing else crosses that line.**

- `MazeGenerator` (ModuleScript) creates parts, sets attributes, applies CollectionService tags. Zero gameplay logic.
- `WorldBootstrap` is the only caller of `MazeGenerator`. It builds `Config.World.PregenerateSections` sections at startup, then lazily builds section N+1 when anyone touches a `SlideEntrance` targeting it.
- All gameplay (timers, moving walls, enemies, slides, bounce pads) lives in services that discover tagged instances via `CollectionService:GetTagged()` plus `GetInstanceAddedSignal`. This is why lazy generation works with no extra wiring: sections built mid-game are picked up by every service automatically.
- If a feature needs new data from generation, add an attribute to a tagged part. Never parent a script inside generated folders.

**2. Determinism is load-bearing.** All randomness flows from `Random.new(seed)` objects threaded through the generator. Never call `math.random` in `MazeGenerator`. Same `Config.World.Seed` produces an identical city across server restarts, and section N's slide targets section N+1's computed origin before that section exists.

## Repo layout

```
maze-city/
  default.project.json      Rojo tree (also sets Lighting defaults)
  aftman.toml               pinned toolchain (read by Rokit)
  selene.toml               lint config (roblox std)
  stylua.toml               formatter config
  src/
    shared/
      MazeConfig.lua        -> ReplicatedStorage.MazeConfig (ModuleScript)
      Types.lua               exported Luau types for the pet system, no runtime
      PetCatalog.lua          pet content
      EggCatalog.lua          egg content
      AccessoryCatalog.lua    gear content
      EnemyDefinitions.lua    enemy content, one row per type
      EnemyTypes.lua          the enemy vocabulary: type, behavior, state, role names
      StatusDefinitions.lua   timed statuses the enemy system can apply
      ModelGenerator.lua      procedural enemy rigs, shared so the client can draw portraits
    server/                 -> ServerScriptService
      MazeGenerator.lua       ModuleScript, all world generation
      PlayerProfiles.lua      ModuleScript, the saved profile and the only DataStore caller
      PetInventory.lua        ModuleScript, the pet rules as functions over a profile
      Enemy/                  ModuleScripts, the enemy AI (see the enemy section below)
        EnemyFactory.lua  EnemyController.lua  EnemyStateMachine.lua
        EnemyTargeting.lua  EnemyPathfinding.lua  EnemyCombat.lua
        EnemyStatusService.lua  EnemyRegistry.lua  EnemyRig.lua  SpawnDirector.lua
        Behaviors/            BaseBehavior.lua plus one module per behavior
      WorldBootstrap.server.lua
      TowerTimerService.server.lua
      MovingWallService.server.lua
      EnemyService.server.lua
      TraversalService.server.lua
      PickupService.server.lua
      SaveService.server.lua
      PetService.server.lua
      IncubatorService.server.lua
      DailyRewardService.server.lua
      WallWalkService.server.lua
    client/
      TimerGui.client.lua   -> StarterPlayer.StarterPlayerScripts (LocalScript)
      PetGui.client.lua
      WallWalkGui.client.lua
```

Rojo infers class from suffix: `.server.lua` is a Script, `.client.lua` is a LocalScript, plain `.lua` is a ModuleScript. Keep that convention for new files.

`default.project.json` maps the three `src/` folders wholesale rather than naming files one by one, so a new file ships by being in the right folder. It used to enumerate every script, and `PickupService` was written without being added: coins generated, nothing consumed the tag, and the symptom was a player running straight through them. A service that appears to do nothing is worth checking against the built place (`rojo build -o /tmp/check.rbxlx`) before it is debugged as a logic bug.

## Toolchain and workflow

Install tools once: `rokit install`. Rokit reads the existing `aftman.toml` manifest, so no migration is needed. Aftman itself is archived upstream and its Homebrew formula was disabled in July 2026; do not try to install it.

```
rojo serve                    # live sync; connect from the Rojo plugin in Studio, then hit Play
rojo build -o MazeCity.rbxlx  # or produce a place file cold and open it
selene src/                   # lint
stylua src/                   # format
```

The pinned rojo must match the Rojo Studio plugin's major line. Rojo changed its API encoding after 7.4, so a 7.7 plugin against a 7.4 server fails at connect with `attempt to index number with 'protocolVersion'`. If Studio shows that, bump the pin rather than downgrading the plugin. `rojo serve` also defaults to port 34872, so a server for another project on that port will quietly serve the wrong tree; `curl -s localhost:34872/api/rojo` names the project actually being served.

Studio's role is reduced to being the runner: press Play, the server builds the city, test, stop. In edit mode the workspace is empty except whatever Rojo syncs. Do not save generated geometry into the place file; it is a build artifact. If a play session leaves anything behind, delete `workspace.MazeCity`, `workspace.LiveEnemies`, `workspace.LivePets` and `ServerStorage.GeneratedEnemyModels`. The last of those is the one enemy rig template per type that `ModelGenerator` builds at startup; it rebuilds itself from scratch every run, so a stale copy is clutter rather than a bug.

The one thing Studio is still needed for is content that is genuinely art. Rigs go in `ServerStorage/<Kind>/<Name>`: enemies at `ServerStorage/Enemies/<TypeName>` matching keys in `Config.EnemyProfiles`, pets at `ServerStorage/Pets/<model>` matching the `model` field of a `PetCatalog` entry or one of its evolution stages. Until they exist both services substitute placeholder rigs, so the game is fully playable from a cold `rojo build` with zero Studio-side setup.

## Startup sequence

1. `WorldBootstrap` requires `MazeGenerator`, creates `workspace.MazeCity`, builds sections 1..PregenerateSections. The generator yields (`task.wait()`) between buildings so startup does not freeze the server.
2. `workspace:SetAttribute("MazeCityReady", true)` when pregeneration finishes.
3. If `Config.World.LazyGeneration`, bootstrap binds every `SlideEntrance` (current and future) and builds the target section on first touch. Ride time down the slide covers generation time; `ensureSection` also blocks duplicate concurrent builds.
4. Services bound tags at their own startup and via added-signals, in any order relative to generation. Order independence is a requirement, not an accident: never write a service that assumes geometry exists at require time.

## Generation invariants (do not break these)

These encode fixes for real bugs in an earlier version. Any change to `MazeGenerator` must preserve them.

1. **One slab per level boundary.** Level N's floor is the only horizontal slab at `Y = N * LEVEL_HEIGHT`. No separate ceiling for level N-1. The hole in level N's floor is positioned by level N-1's stair location, so the top step lands flush with the floor above. The old version had a ceiling and floor at the same Y with holes in different corners, making towers unclimbable.

2. **Stair cells are reserved before carving.** Each level picks an exit cell plus the cell inward of it, passes both as `reserved` to `newGrid`, carves around them, then seals both and cuts exactly two openings: bottom stair cell to the maze, bottom to top stair cell. Never open or close walls of an already-carved maze elsewhere; the maze is a spanning tree and post-hoc edits orphan regions.

3. **Perpendicular spiral, and the exit is half a floor from the entry.** `exitSide = rotateSide(entrySide, +/-1)`, never 0 or 2. The exit cell of level N is the entry cell of level N+1. This keeps stair holes and arrival triggers aligned across floors. Perpendicular alone still allowed the two to sit a cell or two apart near the corner the sides share, which is a floor climbed without entering its maze, so `pickExitIndex` draws only from the edge cells at least `STAIR_MIN_SEPARATION_FRAC` of the footprint from the arrival, in a straight line because nothing is carved yet. It is one draw either way, so the stream length per level is unchanged; the values are not, and changing the fraction reshuffles the city.

4. **Sections are self-contained except slide targets.** A section references section N+1 only through `MazeGenerator.sectionOrigin(N + 1)`, which is pure math. Changing plot layout constants changes every slide target, which is fine as long as it changes them consistently; never hardcode a world position.

5. **Tags carry Section, Building, Level attributes.** Runtime services key everything off these three. Any new tagged part type must set them. `SlideEntrance` additionally carries `FromSection`/`ToSection`, which lazy generation depends on, and `ShopItem` carries `Upgrade`, the key into `Config.Shop.Upgrades` that SaveService resolves a purchase against. `EggPedestal` carries nothing extra: every roost in the city is the same roost, and which one an egg was placed at is not a thing the incubator stores. `RoofTrigger` carries `ArrivalX/Y/Z` because its centre is not where the stairs come up, and `LevelTrigger` carries `Route`, the walk from that floor's arrival cell to its stairwell, as `;`-separated integer offsets from the trigger's own position. Offsets rather than world points so a client can rebuild them without knowing `CELL` or the plot origin; the longest across three sections is 79 hops and 624 characters.

6. **Geometry added after a baseline draws no random numbers.** `buildZipline` is a pure function of `entrySide`/`entryCell`, which the maze has already fixed, so adding it left every pre-existing part exactly where it was and the delta was countable: four instances per building. Drawing from the threaded `rng` instead would have shifted every subsequent draw and reshuffled the whole city for a feature that needs no randomness. Anything landing outside a deliberate world reshuffle has the same obligation: read what generation already decided, or draw from a derived sub-stream seeded off the per-building seed, but never from `rng` itself. `buildEggRoost` is the third of these and the cheapest to check: a pure function of the footprint, so the delta is five instances per building, thirty per section, and every pre-existing part is where it was.

   `markMovingWall` is the fourth and shows the shape of it under a function that *does* draw. `tagMovingWalls` rolls a mode and four timings per wall; the mark is created after all of them, from the wall's own size and position and the mode already chosen, so it adds no draw and the stream is the one it always was. It also reads the floor off the wall (`Position.Y - WALL_HEIGHT / 2`) rather than recomputing `baseY`, which is why it is right on level 0 where the slab is lifted.

7. **Containment is a property of which function built the part.** Two collision groups are assigned at generation time and each answers one question by construction, so there is no runtime check to forget.

   `MazeWall` is what the Wall Walker may phase through. `buildWalls` puts every wall it makes into it through the single `wallPart` funnel; `buildFacade`, `buildSlab`, `buildStairs` and `buildRoof` leave theirs at Default. That is the whole of what stops the upgrade stranding anyone: a phasing player crosses any wall on a floor, lands in the apron ring between the maze edge and the facade with slab under their feet, and stops there, because the facade is not in the group. Anything wall-like must go through `wallPart` or decide deliberately not to, and anything that is a new *boundary* must not go in the group.

   `EnemyBlock` is solid to enemies and absent to everyone else, and it exists because **collision groups do not reach the navmesh**: pathfinding reads `CanCollide` and nothing else, so the only way to stop a planner routing an enemy somewhere is to put a collidable obstacle there. Two things are in it. A phantom wall, which was `CanCollide = false` and therefore a doorway every enemy in the city had always been walking through, is collidable again and passable to a character by group. And `buildStairs` stands a `StairBlock` panel in the one opening cut between the maze and the stair cell, which is what keeps an enemy on its own floor: the floor band that notices afterwards and teleports it home is a backstop, not the mechanism. An enemy still sees into a stairwell and cannot follow.

   The rules are split the way the groups are owned. MazeGenerator registers both and sets what `EnemyBlock` *means* (nothing collides with it); WallWalkService excuses a phasing player from both; EnemyFactory states the single pair that does collide. A new group needs the same three-way split or it will be one default nobody wrote down.

8. **A collectible is placed by generation; what it is worth is not.** A powerup orb carries no `Kind`: PickupService rolls one from `Config.Collectibles.PowerupRoll` when the orb is touched, so the same orb is a different prize to the next player and after it respawns. Generation places it and stops. This is why the roll list can gain and lose entries freely, where the old generation-time draw made its length load-bearing; it is also why removing that draw shifted the orb cells once, on levels 2/5/8, and touched no coin, the coins being drawn earlier in the same sub-stream.

9. **A collectible count is a function of the settings, not of the seed.** `buildCollectibles` places dead-end coins first, then main-path coins, then tops up from anywhere still open, so every level places exactly `DeadEndCoinsPerLevel + PathCoinsPerLevel` however few leaves its spanning tree happened to grow. Powerup orbs run through the same two pools after the coins have taken theirs and top up the same way, so every level places exactly `PowerupsPerLevel` of them; it is a count, never a per-level roll. Without both of those the part count stops being checkable: a section could differ from its neighbour for no reason anyone could confirm was the intended one. The sub-stream is `Random.new(buildingSeed + level * 31)`, which cannot collide because building seeds are at least 7919 apart.

## Runtime services

| Service | Tags consumed | Notes |
|---|---|---|
| WorldBootstrap | `SlideEntrance` | Builds sections; the only writer of `workspace.MazeCity`. |
| TowerTimerService | `LevelTrigger`, `RoofTrigger`, `TowerStart` | Timer counts up from touching a floor's arrival trigger; `Config.getParTime` is a scoring target, not a deadline. Clearing a floor and topping out award `leaderstats.Score`. Death is the only failure: respawn configurable via `Config.DeathAction`, `restartLevel` (default) or `restartTower`. Pushes state, score, and celebration events to clients over the `TimerUpdate` RemoteEvent at 4 Hz. |
| MovingWallService | `MovingWall` | Reads Mode (slide/rotate), Travel, TweenTime, DwellOpen/Closed, Phase attributes; all are required, and a wall missing any of them warns and stays static rather than falling back to a default. Checks player occupancy before closing; postpones instead of shoving. |
| EnemyService | `EnemySpawn` | Bootstrap, registry and the spawn scan, and nothing an enemy does: that is the `Enemy/` module tree below. Type from marker attribute, overridable per section in MazeConfig. **A marker is permanent, its rig is not:** a rig is built when somebody comes within `Config.Enemies.SpawnRange` and destroyed past `DespawnRange`, measured from the rig so a chase is never deleted mid-stride. Gating only the pathfinding, as the old version did, left all 180 markers per section holding a live Humanoid, and a server spending its frame on hundreds of idle state machines is why the few that mattered moved like they were underwater. Candidates are sorted by distance before `GlobalCap`/`PerBuildingCap` is spent, because a cap over an unordered sweep of a hash table gives you forty arbitrary enemies out of the hundred in range rather than the forty nearest. |
| TraversalService | `SlideEntrance`, `SlideBooster`, `SlideExit`, `BouncePad`, `ZipEntrance`, `ZipExit` | PlatformStand during rides, velocity boosters, safety release after SlideMaxSeconds. The zipline is the exception to "rides are physics": it anchors the rider and tweens them down the cable, because the descent is 195 studs and a rider who clips off a physics line lands wherever the simulation drops them. Every exit path, including the failures, goes through `endRide`, which is the only thing that unanchors. The rider hangs `ZipHangOffset` under the cable and stays upright; putting the root part on the cable and aiming it down the slope ran the line through the character lengthwise. Bounce pads are the one thing here that is not a ride: the player keeps control throughout, so a pad cannot use PlatformStand and has to fight the humanoid state machine twice over, once for the ground controller and once for the jump impulse the Jumping state applies a step later. A pad returns `BouncePadMomentumGain` of the speed it was landed on with, capped at `BouncePadMaxPower`, so bouncing in place climbs by itself. |
| PickupService | `Coin`, `Powerup` | Server owns the count in `leaderstats.Coins`; a taken pickup is hidden with `Transparency`/`CanTouch` and comes back on a timer, never destroyed. Collected two ways: `Touched` for the zero-latency path, and a `PickupRadius` sweep per living player because a 3.4-stud disc reached by touch alone had to be walked into almost exactly. The sweep is one `GetPartBoundsInRadius` per player answered by the engine broadphase, not a distance test against the 1,068 collectibles per section; both paths funnel into the same handler and guard on the same taken table, neither yielding between reading that guard and setting it. The kind is rolled here, on touch, from `PowerupRoll`, not read off the orb; runtime randomness, deliberately not seeded off the world seed. Effects are restore closures, one active per player. Ghost sets `Unseen` on the character and Freeze sets `EnemyFreezeUntil` on `workspace`, both read by EnemyService; Reveal is drawn entirely by the client and has no server effect at all; CoinBoost pays a lump sum that is never taken back, so it is not in the undo list, plus a `coinBonus` multiplier that is. Fires the `PickupUpdate` RemoteEvent, which carries only events (the ding, which powerup started); the number itself rides replicated leaderstats, so a late client reads it correctly. |
| SaveService | `ShopItem`, `TowerStart` | The upgrade shop and the furthest-section credit; the profile it reads lives in `PlayerProfiles`. Purchases go through each pedestal's generated ProximityPrompt, deduct from `leaderstats.Coins`, and report bought/poor/maxed over the `ShopUpdate` RemoteEvent. Upgrades cross to other services as attributes, the same channel Ghost and Freeze use: `BaseWalkSpeed` on the character, which PickupService's Speed boost multiplies and restores against, and `MagnetBonus` on the player, which widens the pickup sweep. `TowerStart` touches are how furthest-section is credited. |
| PetService | (`EggPedestal`, to warn if none) | Owns the pet half of the profile: equip, XP, evolution, the follower rig, and the read-only projection every client draws from. Followers live in `workspace.LivePets`, anchored and eased by CFrame rather than pathfound: a pathfinding pet in a maze whose walls move is a pet stuck behind one. Glow is the one ability implemented, as a `PointLight` on the rig, with the evolution multiplier scaling range and deliberately not brightness. Owns the `PetUpdate` and `PetIntent` remotes and the rate limit on the latter. |
| IncubatorService | `EggPedestal` | Buying an egg, placing one, counting the climb, and rolling the hatch. Every mutation re-checks proximity to a tagged pedestal, so the prompt is a door into the UI and never the authority. A finished egg that cannot hatch into a full pet shelf stays in the slot and says so rather than dropping the pet. Broadcasts Epic and above to every client. |
| WallWalkService | `LevelTrigger` | The Wall Walker upgrade. Holding the key moves the character into a collision group that does not collide with `MazeWall`, and drains a per-floor meter sized by tier from `SecondsPerTier`. Containment is invariant 7 and not a check in this file. The one thing that is a check: a phase never ends while the player still overlaps a wall, because going solid inside geometry is how somebody gets stuck, capped by `GraceSeconds` so a player who never leaves a wall cannot ride the grace forever. Refills on `LevelTrigger` rather than on `MazeProgress`, because a tower's first floor is entered without one having been cleared. |
| DailyRewardService | none | One claim per UTC day off `math.floor(os.time() / 86400)`, a streak that grows while the days are consecutive, and the streak egg on day seven. No world object: a daily reward that needs a walk to a kiosk is a daily reward people miss. |
| PetGui (client) | `EggPedestal` | The whole surface of the pet system: inventory, egg shelf, daily claim, hatch reveal, rarity broadcast. Draws the projection and nothing else; every number arrives already resolved, so the client has no opinion to disagree with. Buttons fire intents and wait to be told what happened, including when the answer is no, which is what the `REASONS` table exists for. Reads the tag for two things only: whether the Place button is live, and where to draw the incubating egg, which goes in an `EggHint` model beside `MazeCity` and never inside it. |
| TimerGui (client) | `LevelTrigger`, `RoofTrigger`, `PhantomWall`, `Coin` | The tag consumer that predates the pet UI. HUD and celebrations come off the `TimerUpdate` payload; the tags are read for the compass arrow's target, the phantom pass-through sparkle, spinning the coins within `SpinRange`, and the Reveal powerup's trail, which decodes the current floor's `LevelTrigger.Route` into markers under one `Highlight` at `AlwaysOnTop`. Hints, never authority: a section that has not replicated yet just means no arrow for a moment. Markers go in a `RouteHint` model parented to `workspace`, never into `MazeCity`, and are cleared on the effect ending, on a floor change, and on respawn. The coin spin is a local CFrame on an anchored part the server never moves again, so it stays on the machine that drew it. |

Effects (sounds, particles, the compass billboard) attach at runtime to characters, enemy rigs in `workspace.LiveEnemies`, pet rigs in `workspace.LivePets`, or the PlayerGui. Nothing is ever parented into `workspace.MazeCity`, which stays exactly as the generator built it.

## Server modules

ModuleScripts in `src/server` hold state and rules that more than one Script needs. A `.server.lua` Script cannot be required, so anything shared has to be one of these. The enemy tree under `Enemy/` is the third of these and has its own section below.

- **`PlayerProfiles`** is the saved profile and the only caller of `DataStoreService`. Its failure posture is load-bearing and predates the pet system: a profile that fails to load sets `loaded = false` and is then never saved over, so a Studio session without API access plays identically and wipes nothing. Any field added has to keep that, which is why `adopt` merges field by field against defaults rather than replacing the table: an absent field loads as its default, and that is the whole migration story for an additive change. Coins are deliberately not in it, being `leaderstats.Coins`, read back off the IntValue at save time so the number the game already replicates is the only copy. The schema is versioned twice and they do different jobs: `Config.Persistence.KeyPrefix` is the wipe, `schemaVersion` in the payload is the record. `Profiles.onReady(fn)` is how a service is told a profile is readable, and it replays for players already loaded, so registration order does not matter.
- **`PetInventory`** is the pet rules as functions over that table: caps, levels, evolution stages, the hatch roll, the equip list, the client projection. No remotes, no instances, no yielding. It exists because three services mutate the same inventory and three copies of a cap check is three chances for them to disagree. Every mutating function returns `ok, reasonOrValue`; a refusal is an ordinary return, never an error and never a silent no-op, because the client is going to be told why.

## Enemy AI

`src/server/Enemy/` is the AI; `EnemyService` is only the loop that decides which markers hold a rig. Content is `ReplicatedStorage.EnemyDefinitions` (one row per type), the vocabulary is `EnemyTypes`, the rigs are `ModelGenerator`, and everything that governs the system as a whole is `Config.Enemies`.

**The controller knows how to move, look, attack and die; the behavior knows when.** `EnemyController` is one per rig and is the only thing that touches the Humanoid, so the freeze deadline, the stun, the floor band and the attack tell are written once and cannot be forgotten by a module that only meant to change how something walks. A behavior is a table of hooks over `BaseBehavior`, not a subclass of the controller.

The tick order is a contract: freeze, stun, off-floor, `update`, target selection wrapped in `filterTarget` and the two transition hooks, growl, then `onChase` or search or return or `onIdle`. Three hooks can claim a tick and end it there. `BaseBehavior.extend` errors at require time on a key that is not a hook, because `onStateEnter` for `onStateEntered` is otherwise invisible: the module looks written, the hook never fires, and the enemy just stands there.

Three things carried over from the old single-file service and must survive any change. Nothing blocks on `MoveToFinished`, whose eight second internal timeout turns a clipped corner into an enemy standing still; `EnemyPathfinding` decides arrival itself. A plan goes stale on both a timer and a drift, because the timer catches a moving wall closing across a clear path and the drift catches the player rounding a corner, and neither alone caught both. And leash is measured from the spawn marker, never from the enemy, so an enemy owns a patch of maze and can be left behind. Enemies also share a collision group that does not collide with itself, because three of them meeting in a corridor was most of "they just stand there".

`tick` never yields, which is load-bearing rather than incidental: the Charger's windup used to be a `task.wait` inside the loop, and a parked thread meant a Freeze powerup landing during a windup did not stop the charge until after it had already started.

**Adding an enemy is one definitions row, a behavior (pick an existing one or add a module under `Behaviors/`), and a `look` recipe.** No service is edited. A row naming a behavior with no module gets `BaseBehavior` and one warning, so it chases and hits like a baseline Drifter with that row's numbers rather than standing there. Six of the nineteen types are live; the rest have rows and no module yet.

Fields on a row that nothing reads yet are listed in `EnemyDefinitions`' own header, and that list is worth keeping honest, because a number nobody reads looks exactly like a number that is not working.

## Server-to-server events

Services talk to clients over RemoteEvents and, since the pet system, to each other over BindableEvents in `ServerScriptService`. Same shape either way: one table argument discriminated by a `kind` field.

The difference is who creates it. A RemoteEvent is created by its owning service and waited on by the client. A BindableEvent is created **FindFirstChild-or-create on both ends**, because scripts in `ServerScriptService` start in arbitrary order and a listener that happened to run first would wait forever on something it is allowed to make itself.

- **`MazeProgress`**, fired by TowerTimerService from `enterFloor` and `completeTower`. Both kinds fire unconditionally, so which of them counts as "a maze" is a config read on the listening side rather than a decision baked into the timer. Firing from `completeTower` after `state[player] = nil` is what stops a tower being handed to a listener twice, poll and touch both reaching the same place.
- **`PetsChanged`**, fired by any service that mutates a profile's pets or eggs. PetService listens and re-pushes the projection and re-rigs the followers, which is how IncubatorService and DailyRewardService reach the client without owning a remote.

All gameplay tuning lives in `MazeConfig`. World-shape knobs meant to change between playtests (seed, levels, pregenerate count, lamp brightness, moving wall start level, phantom count) live in `Config.World`; structural geometry constants (cell size, wall height, plot grid) live in `MazeGenerator.CFG` because changing them invalidates the whole city. Do not scatter magic numbers into services.

Content is the one thing that does not live in `MazeConfig`. A catalogue grows by entries where tuning grows by edits, so pets and eggs are `ReplicatedStorage.PetCatalog` and `ReplicatedStorage.EggCatalog` while the numbers governing the system as a whole (`HatchUnit`, storage caps, XP rates, follow distance, prompt distance) are `Config.Pets`. `Config.Pets.HatchUnit` is the one to be careful with: it silently rescales every `mazesRequired` in `EggCatalog`, so flipping it is a catalogue pass, not a knob turn.

## Conventions

- Tabs for indentation.
- No comments that restate the code. Comments explain why, or document a non-obvious invariant.
- Keep files compatible with `luac -p` where it costs nothing (avoid `+=`, `continue` unless there is a reason); it enables syntax checking outside Studio and in CI.
- Attribute names, tag names, and config keys are PascalCase.
- Direct file edits over generation scripts. When modifying these files, edit them in place rather than writing scripts that rewrite them.
- No em dashes in any file in this repo.

## Known gaps and deliberate deferrals

- **Slide physics.** SECTION_GAP of 620 makes the natural slope about 16 degrees, too shallow for gravity alone, hence the boosters. Shortening the gap below about 400 allows removing them.
- **Part count.** Roughly 8k parts per section, windows being the biggest single contributor. First optimization if needed: merge collinear maze wall runs, at the cost of complicating per-cell wall tagging. Also consider `workspace.StreamingEnabled` before any geometry surgery; with lazy generation plus streaming, section count is effectively unbounded. Do not optimize preemptively.
- **Enemy pathfinding scale.** Bounded by proximity rather than by section count: live rigs are only those near a player, so cost tracks players and not city size, and `Config.Enemies.GlobalCap` is the ceiling over that. The remaining flat cost is one sweep over every marker twice a second, about 1800 magnitude tests a second at five sections and four players, plus a sort of whatever is in range. If section count ever grows far enough for that to matter, bucket the markers spatially in the scan loop; do not put the cost back into keeping rigs alive.
- **Enemies cannot be damaged.** There is no combat, so a row's `health` and `Config.Enemies.HealthPerLevel` set a MaxHealth nothing reads and the `Died` path is reachable only in principle. It is wired correctly anyway (despawn, then respawn after `Config.Enemies.RespawnSeconds`), so adding a weapon is a weapon and not also a lifecycle. `EnemyController:takeDamage` is the entry point when one arrives.
- **Footprint variety.** All buildings share one footprint; styles vary skin, windows, crown. True silhouette variety requires per-building maze dimensions, which touches slab math, facade math, and slide targeting. Treat as a feature, not a tweak.
- **Progress within a run is not saved.** SaveService persists coins, upgrade tiers, and furthest section reached, but a rejoining player always spawns at section 1: `furthestSection` is stored without yet being spent. A checkpoint spawn reading it against existing `TowerStart` tags is the natural next feature, and needs no data migration.
- **Generated world is not inspectable in edit mode.** Cost of dropping the plugin. If you need to eyeball geometry without playing, add a temporary `RunService:IsStudio()` branch in a throwaway script, or run the game and use the server-side explorer during Play.

## Pet & Egg System

Active work on the pet/egg system follows [docs/PETS_PLAN.md](docs/PETS_PLAN.md) (clutch-based work units, prerequisites audit, exit criteria) and [docs/PET_EGG_DATA_SPEC.md](docs/PET_EGG_DATA_SPEC.md) (types, config shape, server-side state transitions). Read both before touching pet, egg, incubator, or daily reward code. If something needed isn't in the plan, update the plan first rather than inventing a parallel system.

The spec was written against a generic Roblox project, so its paths are not this repo's paths and some of its shape collides with decisions already made here: coins live in `leaderstats` and are stored exactly once, the wipe is `Config.Persistence.KeyPrefix` rather than the in-payload `schemaVersion`, and there is no ProfileService. The plan's "Repo reconciliation" section is the authority on every one of those; the spec is the authority on the data model itself. `docs/` is outside the three `src/` folders Rojo maps, so nothing here reaches the place file.

Clutches 1 through 5 are done: data layer, incubator and hatching, follower and Glow, XP and dailies, and the UI. The plan records what was decided along the way, including the three things it did not originally cover (a profile module, an egg storefront at the roost, and pet release still not existing).

## What "done" looks like for a change

1. `selene src/` clean.
2. Generator changes: run twice with the same seed and confirm identical output (part counts per section folder are a cheap proxy; `print(#folder:GetDescendants())`).
3. Runtime changes: Play test one full floor including a score award, one death and floor respawn, one moving wall cycle on level 5+, and one slide ride into a lazily generated section.
4. Profile changes: rejoin and confirm the field came back, then confirm a Studio session with no DataStore API access still plays and still saves nothing. The second half is the one that gets skipped and it is the one that protects everyone's coins.
5. No new magic numbers outside `MazeConfig`, `Config.Pets` or `MazeGenerator.CFG`.
