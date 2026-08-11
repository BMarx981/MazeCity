# Preview Plan

Follows the working agreement in PETS_PLAN.md: one set per branch, nothing invented outside a plan. This plan covers how generated content is looked at, not what any of it is. What pets look like is PET_LOOKS_PLAN.md, what they wear is PET_ACCESSORIES_PLAN.md, and the enemy silhouettes are the enemy brief.

## Goal

One Studio-only way to see every variant of a generated thing standing in a row, at true scale, labelled: pets, worn gear, enemy types, and building styles. Today there is one of these and it covers one kind. `PetLookPreview.server.lua` was written for Set 1 of the pet looks plan, marked temporary, and then outlived Set 1 because it turned out to be the only way to judge eleven silhouettes against each other rather than one at a time.

CLAUDE.md already records the gap this closes and its own suggested workaround: "Generated world is not inspectable in edit mode. Cost of dropping the plugin. If you need to eyeball geometry without playing, add a temporary `RunService:IsStudio()` branch in a throwaway script." The workaround is right and the throwaway part is what does not scale. Four look systems means four throwaway scripts, each written from nothing, each with its own row spacing and its own labels, and each one a file somebody has to remember to delete.

## Non-goals

- **A player-facing feature.** Every line of this is behind `RunService:IsStudio()` and returns before it requires anything, the way `EnemyDebug` does. A preview is a development tool and nothing in the shipped game may read it.
- **Replacing the bestiary or the pet portraits.** `PortraitGenerator` and `BestiaryGui` draw single rigs in ViewportFrames for players. This draws real parts in the real world at real scale, which is the thing a viewport cannot tell you: whether a Lumen Moth is wider than a corridor, whether a crown clears a Ward Hound's ears, whether the Ember facade reads next to the Bone one.
- **Changing any look.** This plan adds a way to see. Every recipe, style and silhouette is exactly as it was.
- **A test runner.** The offline harness in `tools/petlooks` asserts things about geometry and stays what it is. A preview is for the judgements a machine cannot make.
- **Animation.** Rigs turn on the spot because a still row hides half a silhouette. Nothing here drives a joint; that is PET_LOOKS_PLAN Set 4.

## Where it lives

| File | What |
|---|---|
| `src/server/PreviewService.server.lua` | New. Studio-gated. The registry, the row layout, the labels, the spin, and the command surface. One file, the way `EnemyDebug` is one file. |
| `src/server/PetLookPreview.server.lua` | Deleted by Set 1 of this plan, which is what it has been flagged for since it survived its own set. Already on `/petlook` rather than on first spawn, so the row it draws is opt-in until then. |
| `src/shared/GearModelGenerator.lua` | New in Set 2. `makeGearPlaceholder` and `gearOrientation` lifted out of `PetService.server.lua`, which is a Script and therefore cannot be required by anything. |
| `src/server/PetService.server.lua` | Set 2. Requires the module above instead of holding the two functions. |
| `src/server/MazeGenerator.lua` | Set 3. One exported entry point for a single building, and a `ctx.preview` branch in `tagWithContext`. |

No `Config` changes in any set. A preview has no tuning: its spacing and its spin rate are structural to the tool and belong beside it, and `Config.Pets.SpinDegreesPerSecond` is borrowed today only because a preview pet should turn at the rate a real follower turns.

## The contract

**A kind is a pure builder plus an enumeration of variants.** That pair is the whole registry entry, and it is the reason this is small: `PetLookPreview` is a hundred and twenty lines of row layout wrapped around eight lines that call `PetModelGenerator.build`. Everything else in it is generic and always was.

```
{
	name = "pets",
	variants = function() -> { { key, label } }
	build = function(key) -> Model
}
```

Three rules on a registry entry, and they are the same three that make `build` shareable in the first place:

1. **`build` is pure.** No yields, no ServerStorage, no randomness that is not derived from the key, no collision groups. A preview builds eleven models in one frame in front of a player, and a builder that yields turns that into a row that assembles itself while you watch.
2. **`build` returns a Model with a PrimaryPart**, because the row positions everything with `PivotTo` and nothing else.
3. **The output is inert.** The service sterilises everything it places, the same anchored, non-colliding, non-touch, non-query pass `PetService` runs over a follower, and it strips tags. A preview is scenery. Nothing that walks into the row may be affected by it, and nothing in the row may be discovered by a runtime service.

Rule 3 is doing more work than it looks and Set 3 is where it bites, below.

## Command surface

Same two doors as `EnemyDebug`, deliberately, because a second convention for the same job is a second thing to remember: chat `/preview <kind> [args]` as any player, or invoke the `PreviewCommand` BindableFunction from the command bar. Everything is drawn into `workspace.Preview`, never into `workspace.MazeCity`, and `/preview clear` destroys the folder.

Rows are built in front of the caller's character rather than at a fixed point, which is what `PetLookPreview` already does and is the whole ergonomics of it: you walk somewhere with room, you type, you look.

## The four kinds

**Pets** and **enemies** are ready today and need no other file touched.

`PetModelGenerator.build(petId, stage)` and `ModelGenerator.build(typeName)` are already pure, already shared, and already have their enumerations in `PetCatalog` and `EnemyDefinitions`. Enemies are the kind that most obviously wants this and has never had it: `BestiaryGui` gives you twenty portraits, one per card, and a portrait cannot tell you that two silhouettes are the same silhouette at corridor distance. Twenty rigs in a row at true scale can, and that is the exact judgement the enemy brief's "one rig in six colours is one rig" came from.

**Accessories** need one extraction first. `makeGearPlaceholder` and `gearOrientation` live inside `PetService.server.lua`, which is a Script, so nothing can require them and gear cannot be built anywhere else. Lifting them into `src/shared/GearModelGenerator.lua` is what PET_ACCESSORIES_PLAN's rendering section wants regardless, and it buys the thing gear actually needs, which is not a row of gear. A cape lying on the floor tells you nothing. **Gear previews worn**, one pet rig per accessory, which is why this kind takes a second argument: `/preview gear ward_hound` builds the Hound twenty-two times, each wearing one catalogue item, through the same `slotCFrame` path the real follower uses. That is also the cheapest possible test of the attachment work: if a crown sits inside a Bulwark's ears, you see it in one command instead of twenty-two equips.

**Buildings** are the kind this plan exists for and the only one that is not a registry entry alone.

## Buildings, and the tag problem

Two things stand between `/preview buildings` and a row of the six styles.

**Exposure.** `buildBuilding` is local to `MazeGenerator` and takes `(sectionFolder, origin, sectionIndex, buildingIndex, isExit, seed)`, picking its style with `STYLES[((sectionIndex + buildingIndex) % #STYLES) + 1]`. A preview wants to name a style, not solve a modulus for one, so the export takes a style index directly. That is an added parameter on a wrapper, not a change to how the city chooses styles, so every existing call site computes the same style it always did and the part counts per section are unchanged. Determinism is checked the way it always is: build twice with the same seed and compare `#folder:GetDescendants()` per section against the M0 baseline.

**Tags, which is the real one.** A building carries `LevelTrigger`, `RoofTrigger`, `TowerStart`, `EnemySpawn`, `Coin`, `Powerup`, `MovingWall`, `PhantomWall`, `SlideEntrance`, `ZipEntrance`, `EggPedestal` and `ShopItem`, and the entire runtime architecture is services discovering tagged instances through `CollectionService:GetTagged` plus `GetInstanceAddedSignal`. That is the thing that makes lazy generation work with no wiring, and it is exactly what makes a previewed building dangerous: six of them in a row would arm six floor timers, stand up a spawn director budget per floor, start sweeping moving walls, and offer the player a slide to a section that does not exist. Stripping the tags after the build does not help, because the added-signal has already fired.

So the tags must never go on. There is essentially one funnel, `tagWithContext` in `MazeGenerator.lua`, and the build functions already thread a `ctx` table through everything, so the guard is one branch inside that funnel keyed off `ctx.preview`. Two properties make this safe rather than clever:

- **It draws no random numbers.** Invariant 6 is that geometry added after a baseline draws nothing from the threaded `rng`, and a branch that skips an `AddTag` call draws less than nothing. The stream is untouched, so the city is identical part for part.
- **It is off by every path that is not the preview.** `ctx` is built by `buildSection`, which never sets the flag; only the new single-building export does.

The remaining question is cost and it is a judgement, not a blocker. A building is a ten-level tower and the whole point of a style is its skin, its windows and its crown, so the preview wants a shell: facade, windows, crown, roof, no mazes, no collectibles, no stairs. That is a second flag on the same `ctx` rather than a second code path, and the same rule applies, since skipping a `buildLevel` call skips its sub-stream entirely and disturbs nothing that runs without the flag.

## The offline half

`tools/petlooks/check.sh` runs `PetModelGenerator.build` outside Roblox under the `luau` CLI against a stub Color3/Vector3/CFrame/Instance, and reports every look's part count and bounding box while failing on an accent buried inside the body it was meant to hang off. It found three of those in Set 1, which is three Studio sessions it paid for.

It generalises to any shared generator by taking the module as an argument, so `tools/looks/check.sh PetModelGenerator` and `tools/looks/check.sh ModelGenerator` are the same script. That is worth doing in Set 1 and is cheap.

It does not generalise to `MazeGenerator`, and this plan deliberately does not try. The stub surface for the pet generator is four globals; for the city it is CollectionService, attributes, materials, surface types, mesh instances and a Random that has to reproduce Roblox's stream to be worth anything. Buildings stay eyeball-only, which is what the in-world row is for.

## Sets

### Set 1: The service, pets and enemies

`PreviewService.server.lua` with the registry, the row, the labels, the spin, `/preview <kind>`, `/preview clear`, and the `PreviewCommand` bindable. Two kinds registered, neither of which touches another file. `PetLookPreview.server.lua` deleted, and the paragraph flagging it deleted from PET_LOOKS_PLAN.md along with it. `tools/petlooks` becomes `tools/looks` and takes the generator as an argument.

Done looks like: `/preview pets` puts eleven labelled pets in a row and `/preview enemies` puts twenty labelled rigs in another, both turning, both inert to walk through, neither visible outside Studio, and `rojo build` of a fresh place has nothing in it that a player could reach.

### Set 2: Gear, worn

`GearModelGenerator.lua` extracted from PetService, PetService requiring it, and a `gear` kind that takes a pet id and builds one wearing rig per catalogue item.

Done looks like: `/preview gear ward_hound` shows twenty-two Hounds each wearing one thing, and every piece sits where the slot attachment says rather than somewhere inside the dog.

### Set 3: Building styles

The single-building export on `MazeGenerator`, `ctx.preview` in `tagWithContext`, the shell-only flag, and a `buildings` kind. This is the set that touches the generator, so it is the set that owes the determinism check: same seed twice, part counts per section identical to the M0 baseline, and a play test that a normal city still tags everything it always did.

Done looks like: `/preview buildings` stands the six styles side by side, no timer starts, no enemy spawns, no wall moves, and walking into one does nothing at all.

## Invariants this adds

1. **Nothing a preview builds is ever tagged.** Not stripped afterwards, not tagged and ignored: never tagged. The runtime services are tag consumers by design and a preview must be invisible to all of them.
2. **Nothing a preview builds is ever parented into `workspace.MazeCity`.** Same rule the route hints, coin flights, egg hints and enemy effects already follow. `workspace.Preview` and nowhere else.
3. **A registry entry's `build` is pure**: no yields, no ServerStorage, no collision groups, no randomness outside the key. A kind that cannot state that is a kind whose generator is not shareable yet, and the fix is the generator rather than the preview.
4. **The whole file is behind `RunService:IsStudio()` and returns before it requires anything**, exactly as `EnemyDebug` does.
5. **A preview reads what generation decided; it never decides anything.** No preview may change a look, a recipe, a style or a stream. If a row shows a problem, the fix goes in the generator and the row shows it again.

## Open decisions

- Whether the shell-only building flag is worth having at all, or whether six full towers is fine in a Studio session where nothing else is running. Decide by building six full ones once and looking at the frame time.
- Whether the row should label with a BillboardGui per model, which is what `PetLookPreview` does and what costs a GUI per variant, or one text object per row. Start with the per-model billboard, which is known to work.
- Whether `/preview gear` should default to a pet or require one. Requiring one is honest, defaulting to the Ward Hound is what anybody would type second.

## What is not covered

- Egg and `EggHint` looks, which PET_LOOKS_PLAN also leaves alone.
- Previewing an artist's model from `ServerStorage/Pets` or `ServerStorage/Enemies`. A preview builds from a recipe, and a rig that came from a folder is a rig you can already see by equipping it.
- Any offline check of `MazeGenerator`, for the stub-surface reason above.
- A preview of a whole section, which is what pressing Play already is.
