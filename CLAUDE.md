# CLAUDE.md - Maze City

A Roblox tower-climbing maze game, built entirely from this repo via Rojo. There is no Studio plugin and no hand-placed geometry. The world generates server-side at startup and extends itself lazily as players progress.

Players enter a building at street level, solve a maze on each of 10 floors against a per-floor timer, climb spiral stairwells to the roof, and ride a slide from designated exit buildings to the next section of the city. Higher floors have walls that slowly move. Enemy types vary by building style and can be overridden per section.

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
    server/                 -> ServerScriptService
      MazeGenerator.lua       ModuleScript, all world generation
      WorldBootstrap.server.lua
      TowerTimerService.server.lua
      MovingWallService.server.lua
      EnemyService.server.lua
      TraversalService.server.lua
    client/
      TimerGui.client.lua   -> StarterPlayer.StarterPlayerScripts (LocalScript)
```

Rojo infers class from suffix: `.server.lua` is a Script, `.client.lua` is a LocalScript, plain `.lua` is a ModuleScript. Keep that convention for new files.

## Toolchain and workflow

Install tools once: `rokit install`. Rokit reads the existing `aftman.toml` manifest, so no migration is needed. Aftman itself is archived upstream and its Homebrew formula was disabled in July 2026; do not try to install it.

```
rojo serve                    # live sync; connect from the Rojo plugin in Studio, then hit Play
rojo build -o MazeCity.rbxlx  # or produce a place file cold and open it
selene src/                   # lint
stylua src/                   # format
```

The pinned rojo must match the Rojo Studio plugin's major line. Rojo changed its API encoding after 7.4, so a 7.7 plugin against a 7.4 server fails at connect with `attempt to index number with 'protocolVersion'`. If Studio shows that, bump the pin rather than downgrading the plugin. `rojo serve` also defaults to port 34872, so a server for another project on that port will quietly serve the wrong tree; `curl -s localhost:34872/api/rojo` names the project actually being served.

Studio's role is reduced to being the runner: press Play, the server builds the city, test, stop. In edit mode the workspace is empty except whatever Rojo syncs. Do not save generated geometry into the place file; it is a build artifact. If a play session leaves anything behind, delete `workspace.MazeCity` and `workspace.LiveEnemies`.

The one thing Studio is still needed for is content that is genuinely art: enemy rigs go in `ServerStorage/Enemies/<TypeName>` matching keys in `Config.EnemyProfiles`. Until they exist, `EnemyService` substitutes placeholder rigs, so the game is fully playable from a cold `rojo build` with zero Studio-side setup.

## Startup sequence

1. `WorldBootstrap` requires `MazeGenerator`, creates `workspace.MazeCity`, builds sections 1..PregenerateSections. The generator yields (`task.wait()`) between buildings so startup does not freeze the server.
2. `workspace:SetAttribute("MazeCityReady", true)` when pregeneration finishes.
3. If `Config.World.LazyGeneration`, bootstrap binds every `SlideEntrance` (current and future) and builds the target section on first touch. Ride time down the slide covers generation time; `ensureSection` also blocks duplicate concurrent builds.
4. Services bound tags at their own startup and via added-signals, in any order relative to generation. Order independence is a requirement, not an accident: never write a service that assumes geometry exists at require time.

## Generation invariants (do not break these)

These encode fixes for real bugs in an earlier version. Any change to `MazeGenerator` must preserve them.

1. **One slab per level boundary.** Level N's floor is the only horizontal slab at `Y = N * LEVEL_HEIGHT`. No separate ceiling for level N-1. The hole in level N's floor is positioned by level N-1's stair location, so the top step lands flush with the floor above. The old version had a ceiling and floor at the same Y with holes in different corners, making towers unclimbable.

2. **Stair cells are reserved before carving.** Each level picks an exit cell plus the cell inward of it, passes both as `reserved` to `newGrid`, carves around them, then seals both and cuts exactly two openings: bottom stair cell to the maze, bottom to top stair cell. Never open or close walls of an already-carved maze elsewhere; the maze is a spanning tree and post-hoc edits orphan regions.

3. **Perpendicular spiral.** `exitSide = rotateSide(entrySide, +/-1)`, never 0 or 2. The exit cell of level N is the entry cell of level N+1. This keeps stair holes and arrival triggers aligned across floors.

4. **Sections are self-contained except slide targets.** A section references section N+1 only through `MazeGenerator.sectionOrigin(N + 1)`, which is pure math. Changing plot layout constants changes every slide target, which is fine as long as it changes them consistently; never hardcode a world position.

5. **Tags carry Section, Building, Level attributes.** Runtime services key everything off these three. Any new tagged part type must set them. `SlideEntrance` additionally carries `FromSection`/`ToSection`, which lazy generation depends on.

## Runtime services

| Service | Tags consumed | Notes |
|---|---|---|
| WorldBootstrap | `SlideEntrance` | Builds sections; the only writer of `workspace.MazeCity`. |
| TowerTimerService | `LevelTrigger`, `RoofTrigger`, `TowerStart` | Timer counts up from touching a floor's arrival trigger; `Config.getParTime` is a scoring target, not a deadline. Clearing a floor and topping out award `leaderstats.Score`. Death is the only failure: respawn configurable via `Config.DeathAction`, `restartLevel` (default) or `restartTower`. Pushes state, score, and celebration events to clients over the `TimerUpdate` RemoteEvent at 4 Hz. |
| MovingWallService | `MovingWall` | Reads Mode (slide/rotate), Travel, TweenTime, DwellOpen/Closed, Phase attributes; all are required, and a wall missing any of them warns and stays static rather than falling back to a default. Checks player occupancy before closing; postpones instead of shoving. |
| EnemyService | `EnemySpawn` | Type from marker attribute, overridable per section in MazeConfig. Rigs from `ServerStorage/Enemies/<TypeName>`, placeholder fallback. Enemies with no player inside `Config.EnemyActivationRange` stop pathfinding until one arrives. Respawn via `NeedsRespawn` attribute polling. |
| TraversalService | `SlideEntrance`, `SlideBooster`, `SlideExit`, `BouncePad` | PlatformStand during rides, velocity boosters, safety release after SlideMaxSeconds. |
| TimerGui (client) | `LevelTrigger`, `RoofTrigger`, `PhantomWall` | The one tag consumer that is not a server service. HUD and celebrations come off the `TimerUpdate` payload; the tags are read only for the compass arrow's target and the phantom pass-through sparkle. Hints, never authority: a section that has not replicated yet just means no arrow for a moment. |

Effects (sounds, particles, the compass billboard) attach at runtime to characters, enemy rigs in `workspace.LiveEnemies`, or the PlayerGui. Nothing is ever parented into `workspace.MazeCity`, which stays exactly as the generator built it.

All gameplay tuning lives in `MazeConfig`. World-shape knobs meant to change between playtests (seed, levels, pregenerate count, lamp brightness, moving wall start level, phantom count) live in `Config.World`; structural geometry constants (cell size, wall height, plot grid) live in `MazeGenerator.CFG` because changing them invalidates the whole city. Do not scatter magic numbers into services.

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
- **Enemy pathfinding scale.** Fine at 3 spawns per floor. Will not scale to dense hordes; if enemy count grows, move to zone-based activation.
- **Footprint variety.** All buildings share one footprint; styles vary skin, windows, crown. True silhouette variety requires per-building maze dimensions, which touches slab math, facade math, and slide targeting. Treat as a feature, not a tweak.
- **No persistence.** Progress is not saved. A checkpoint service reading existing `TowerStart` and roof tags is the natural next feature.
- **Generated world is not inspectable in edit mode.** Cost of dropping the plugin. If you need to eyeball geometry without playing, add a temporary `RunService:IsStudio()` branch in a throwaway script, or run the game and use the server-side explorer during Play.

## What "done" looks like for a change

1. `selene src/` clean.
2. Generator changes: run twice with the same seed and confirm identical output (part counts per section folder are a cheap proxy; `print(#folder:GetDescendants())`).
3. Runtime changes: Play test one full floor including a score award, one death and floor respawn, one moving wall cycle on level 5+, and one slide ride into a lazily generated section.
4. No new magic numbers outside `MazeConfig` or `MazeGenerator.CFG`.
