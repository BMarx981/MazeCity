# Pet Looks Plan

Follows the working agreement in PETS_PLAN.md: one set per branch, server authoritative, nothing invented outside a plan. This plan covers how pets look; what pets do is PETS_PLAN.md and what they wear is PET_ACCESSORIES_PLAN.md.

## Goal

Every pet and every evolution stage a distinct procedural silhouette, built the way enemy rigs already are: a `look` recipe on the catalogue entry, one shared generator, zero Studio art. The same generator drawn into ViewportFrames gives the UI portraits, so the inventory rows and the hatch reveal show the pet instead of a rarity-coloured square.

PETS_PLAN records the gap this closes: "`ServerStorage/Pets/<model>` is empty, so every pet is a coloured placeholder." The bargain it names stays intact. An artist model dropped into `ServerStorage/Pets/<model>` still wins by name with no code change; the generator replaces the neon cube as the fallback, not the artist.

## Non-goals

- **Motion.** Wing flap, tail sway, blink. The rig is built so motion later is a driver module beside it (the `ModelGenerator` / `EnemyRig` split), but no joint is animated in this plan. Set 4 sketches it and is explicitly unscheduled.
- **Accessory rendering.** PET_ACCESSORIES_PLAN Set 2 owns putting gear on rigs. This plan only guarantees the generated rigs carry the four slot attachments that plan's rendering section wants, so its computed-from-bounding-box fallback is never needed on a generated rig.
- **New pets, new abilities, balance changes.** The catalogue gains looks, not rows.
- **Egg looks.** The incubating egg in `EggHint` and the egg shelf keep their coloured shapes.
- **Replacing rarity colour in the UI.** Swatches, XP bars and reveal text stay `Config.rarityColor`. The portrait is the pet; the chrome around it is still the rarity.

## Where it lives

| File | What |
|---|---|
| `src/shared/PetModelGenerator.lua` | New. The generator: `DEFAULT_LOOK`, `lookFor`, `build`, `rigOf`. Shared for the same reason `ModelGenerator` is: portraits build on the client from the same recipes, costing the server nothing. |
| `src/shared/PetCatalog.lua` | Each entry and each evolution stage gains a `look`; `placeholder` is deleted once nothing reads it. |
| `src/server/PetInventory.lua` | `Inventory.look(petConfig, stage)` replaces `Inventory.placeholder`, same stage-override resolution. |
| `src/server/PetService.server.lua` | `buildRig` falls back to `PetModelGenerator.build` instead of `makePlaceholder`; the Glow light and the ward ring read `look.primary`. |
| `src/client/PetGui.client.lua` | Portraits: a viewport in each pet row, the model in the hatch reveal. |
| `src/server/IncubatorService.server.lua` | The `hatched` payload gains `petId` and `stage` so the reveal can build the model it is announcing. |

No `Config` changes. The recipe vocabulary and its defaults live in `PetModelGenerator` the way `DEFAULT_LOOK` lives in `ModelGenerator`: they are structural, and editing one is editing how a pet is built, not turning a knob between playtests.

## Art direction: deliberate contrast

The enemies are one silhouette family: dark translucent hoods, lit eyes, hands with no arms, segments trailing into smoke. Pets are the opposite of that on every axis that reads at corridor distance:

| | Enemy | Pet |
|---|---|---|
| Body | translucent, tapering | opaque, rounded |
| Material | Neon, glowing | SmoothPlastic, lit by the world |
| Eyes | lit points on a dark head | dark pupils on a bright body, large |
| Edges | smoke, tendrils, horns | ears, wings, tails, antennae |
| Palette | one dark colour per type | warm primary, lighter secondary, one small neon accent |

The rule behind the table: **a pet must never be mistakable for a threat**, and the Ward Hound is why the rule is load-bearing rather than taste. It is the one pet whose job is being near enemies, and a silhouette that reads as a seventh enemy type next to six real ones is a player sprinting away from their own defence.

Neon appears only as small accents that mean something: the Firefly's lantern is its Glow, the Ward Hound's collar is its ward, the Coin Bat's coin is its magnet. The accent is the ability made visible, which is also what makes an evolution legible (a stronger ability is a bigger or brighter accent).

No legs anywhere, for exactly the reason `ModelGenerator`'s header gives: a walk cycle needs art or a skeleton and foot-slides without both. Every pet hovers. The catalogue is already mostly fliers, and the follower rides at `FollowHeight` anyway; the Hound floats too, a stout balloon of a dog, and floats better than it would walk.

## The recipe

Same construction as the enemy recipes, restated because the details are the contract. `DEFAULT_LOOK` is the whole baseline; a pet's `look` merges over it shallowly; a stage's `look` merges over the pet's. Nested tables (wings, ears, tail, motes) replace whole rather than merging key by key, because a stage that overrides its wings means different wings, not the old wings with one field edited. A group absent or sized 0 is left off entirely.

Vocabulary, all optional except the first four:

- `scale`, `primary`, `secondary`, `accent`: the whole-rig multiplier and the three colours. `primary` is the body, `secondary` the soft parts (belly, wings, muzzle, beak), `accent` the one neon group. Every part takes its colour from exactly one of the three, so recolouring a pet is naming three colours.
- `body`: the torso ellipsoid (number for a sphere, Vector3 for an ellipsoid, same rule as enemy sizes).
- `belly`: a secondary-coloured ellipsoid sunk into the body, showing only underneath (the Hound).
- `head`, `headOffset`: a second ball, or 0 for the one-ball pets whose face sits on the body.
- `eyeCount`, `eyeSize`, `eyeSpread`, `eyeHeight`, `eyeDepth`, `pupilSize`: a dark ball proud of a light one, the inversion of the enemy eye. The two colours are fixed in the generator rather than per-pet, because a recipe that could opt out of them could build a pet that reads as a Kept.
- `ears`, `wings`, `antennae`: symmetric pairs, `{ size, spread, height, z, tilt, sweep, pitch, forward, color }`. Anchor, orient, then push out along the part's own axis, same order as the enemy pairs and for the same reason.
- `beak`, `muzzle`: a single part forward of the head (the Crow; the Hound).
- `tail`: one solid part with size and offset. Not the enemy's fading segment chain: a pet tail is a tail rather than a thing trailing into smoke.
- `crest`: a single upright accent on the head (the Crow's compass needle).
- `collar`, `halo`, `motes`: one ring builder, three uses, `{ count, radius, size, height, z, tilt, upright }`. Flat by default, which is a halo above the head or a dial at a needle's base; `upright` stands the ring in the XY plane, which is a collar around a neck. **The plane is the whole difference between an accent that reads and one that is buried**, and it cost a fix in Set 1: a flat ring wide enough to clear the Hound's chest at the sides puts its rear beads inside the ribs, where they read as parts coming loose. The same trap took the Wayfinder's compass ring back into the shoulders, which is why it ended up a dial above the skull instead.
- `charms`: a list of accent props the pet carries rather than wears, each `{ size, offset, color }`. The Firefly's lantern and the Coin Bat's coin. A list because a stage can add a second one, which is how Gilded reads: two coins is a thing you can count from across a room and 20% more coin is not.

`look.primary` is the stage's colour in the world, and the two runtime reads move to it: the Glow light colour ([PetService.server.lua:156](src/server/PetService.server.lua#L156)) and the ward ring colour ([PetService.server.lua:201](src/server/PetService.server.lua#L201)). One colour source per stage; `placeholder` is deleted, not left beside it to drift.

## The eleven looks

Five bases and six evolution stages. The standing rule: **an evolution adds or changes a group, never only scale and tint.** Enemies learned that lesson as "one rig in six colours is one rig"; here it is one pet in two sizes is one pet, and an evolution a player paid twenty-five levels for should read across a corridor.

- **Firefly**: small amber ball, stub wings, neon lantern at the tail. *Radiant* (10): brighter lantern, gains a halo. *Solar* (25): flame palette, halo plus orbiting spark motes.
- **Lumen Moth**: pale body, oversized flat wings, feathery antennae. *Pale* (12): wings grow past body length, secondary goes near-white.
- **Ward Hound**: stout ellipsoid body, muzzle, drooped ears, short tail, neon collar. *Bulwark* (15): broader body, upright ears, the collar widens into a shoulder ring (the ward, worn).
- **Coin Bat**: round body, big ears, membrane wings, a gold neon coin held under it. *Gilded* (15): gold secondary, second coin, wing edges go accent.
- **Compass Crow**: slate body, beak, fanned tail, needle crest. *Wayfinder* (15): crest becomes a spinning needle mote on a ring, lighter palette.

Exact numbers are Set 1's work, tuned by eye in a play test. The list above is the contract for what each stage must visibly add.

## Rig construction

Where the enemy rig is a Humanoid with unanchored skin, a pet follower is anchored and moved by `PivotTo`, and the rig has to be built for that:

- **No Humanoid, no HipHeight.** An invisible root Part is the PrimaryPart, sized to the body so `GetPivot` stays honest; skin parts hang off it on Motor6Ds. Everything passes through `sterilise` unchanged, so today every part is anchored and the motors are inert geometry: `PivotTo` carries the lot rigidly, exactly as it carries the placeholder cube now. Set 4 is what makes the motors real (see below), and building on them now is what makes Set 4 a driver module instead of a rebuild.
- **The four slot attachments** (`HeadAttachment`, `NeckAttachment`, `BackAttachment`, `AuraAttachment`) are created on the root at build time, placed per silhouette. PET_ACCESSORIES_PLAN's rendering section prefers an authored attachment over its bounding-box fallback; generated rigs author theirs.
- **`build(petId, stage)` is pure**: no randomness, no yielding, never touches ServerStorage, assigns no collision group. Client-callable is the point.
- **No `ensureTemplates`.** Enemies template because hundreds of rigs clone per session; a follower is one build per equip at `MaxEquipped = 1`, a dozen-odd instances, cheaper than the folder.
- **`rigOf`** reads the joints back by name, and it and `build` are the only functions that know the names, same two-function rule as `ModelGenerator`. Nothing animates yet; it exists so Set 4 starts from a readback, not a scan.

## Portraits

The generator being shared is the whole reason this set is small. The client requires `PetModelGenerator`, builds the same model the server built, and parents it to a ViewportFrame with its own camera.

- **Inventory rows**: a square viewport at the left edge of each pet row, the rarity swatch staying beside it. The projection already carries `petId` and `stage`, so there is nothing to add server-side.
- **Hatch reveal**: the model centred under the name, slowly turning (camera orbit on RenderStepped while the reveal is up, torn down with it). The rays and the arpeggio stay; the payload gains `petId` and `stage`, which is the one server edit in the set.
- **The caveat, recorded and accepted**: a portrait always draws the *generated* look. An artist model in `ServerStorage/Pets` is invisible to clients, so a pet whose follower is artist-made still shows its generated silhouette in the UI until a replicated template folder exists, which is a different bargain and out of scope. Same trade the bestiary portraits made.

## Sets

### Set 1: The generator and the recipes

**Done.** `PetModelGenerator.lua` with `DEFAULT_LOOK`, `lookFor`, `build`, `rigOf`; `look` on all five catalogue entries and six stages; `Inventory.look` beside the not-yet-deleted `Inventory.placeholder`; `PetLookPreview.server.lua`, which is the temporary `RunService:IsStudio()` branch CLAUDE.md already names as the way to eyeball generated geometry, and which is **deleted before this branch merges**.

Checked two ways, and the cheap one found the bug. `build` touches no service and yields nothing, so it runs outside Roblox: `tools/petlooks/check.sh` stubs Color3/Vector3/CFrame/Instance under the `luau` CLI already in the toolchain, builds all eleven looks, and reports each one's part count and bounding box. That caught three accents sitting inside the body they were meant to hang off, including the Ward Hound's collar, which is the accent that *is* its ability. The check is now in the harness (an accent's centre inside the body or head ellipsoid is a failure, and the run exits non-zero), so a future recipe cannot reintroduce it silently.

`tools/` sits outside the three `src/` folders Rojo maps, so like `docs/` it reaches nothing in the place file.

Worth keeping in mind for anything else in this repo that is pure geometry: `MazeGenerator` is the same shape of function and the same trick would run it.

### Set 2: The follower wears it

`buildRig` falls back to `PetModelGenerator.build`; `makePlaceholder` deleted; the Glow light and ward ring read `look.primary`; `Inventory.placeholder` deleted; `placeholder` fields deleted from the catalogue. Verify the artist-model path still wins by dropping any Model into `ServerStorage/Pets/Firefly` in a play session.

Done looks like: equip each pet, watch it follow, slide, zipline and respawn; a Glow pet lights the maze in its stage colour; a ward trigger draws the ring in the Hound's colour.

### Set 3: Portraits

The viewport in `petRow`, the model in `showReveal`, `petId` and `stage` on the `hatched` payload.

Done looks like: the shelf shows eleven distinguishable pets at a glance with no server round-trip beyond the projection it already had; a hatch shows the hatched pet turning.

### Set 4: Motion (unscheduled)

Wing flap, tail sway, ear twitch, blink, keyed off the joints `rigOf` returns. Two edits it needs and this plan deliberately leaves: `sterilise` anchors only the root while skin parts stay unanchored massless on their motors, and someone owns the C0 writes. Where they run is an open decision below. Ability tells belong here too: the lantern pulsing with Glow, the collar charging as the ward recharges.

## Invariants this adds

1. `PetModelGenerator.build` is a pure function of `(petId, stage)`: no randomness, no yields, no ServerStorage, no collision groups. Anything less and the client portrait stops matching the server follower.
2. `ServerStorage/Pets/<model>` wins by name over the generator, always. The generator replaced the placeholder, not the artist.
3. `look.primary` is the only world colour for a stage. `Config.rarityColor` is the only UI accent. Neither reads the other.
4. Only `build` and `rigOf` know part and joint names. Accessories land on attachments, effects land on the rig or its root, nothing hunts for `WingLeft` by name outside the module.
5. An evolution stage adds or changes a group, never only scale and tint.
6. Rigs stay `sterilise`-safe: anchored, non-colliding, non-touch, non-query, massless, and moved only by `PivotTo`.

## Open decisions

- Where Set 4's animation loop runs: the server beside the follow Heartbeat (replicated, costs the server per pet) or each client (free to the server, needs the recipes' motion params replicated, which they are, being shared). Leaning client, deciding when Set 4 is scheduled.
- Whether the portrait camera is one framing for all looks or a per-look override key. Start with one; add the key only when a wing clips.

## What is not covered

- Artist-model portraits (needs a replicated template folder; a different bargain than `ServerStorage/Pets`).
- Egg and `EggHint` looks.
- Enemy looks: `ModelGenerator` is untouched. The two generators share an approach, deliberately not code; a shared skinPart helper would couple the pet silhouettes to the enemy ones for thirty saved lines.
